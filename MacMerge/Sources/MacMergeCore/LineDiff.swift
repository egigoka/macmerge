import CXDiff
import Foundation

public enum DiffKind: Equatable, Sendable {
    case unchanged
    case modified
    case removed
    case added
}

public enum DiffAlgorithm: String, Codable, Equatable, Sendable {
    case `default`
    case minimal
    case patience
    case histogram
    case none
}

public enum WhitespaceComparison: String, Codable, Equatable, Sendable {
    case compareAll
    case ignoreChanges
    case ignoreAll
}

public enum CommentSyntax: Equatable, Sendable {
    case cFamily
    case hashLine
    case python
    case sql
    case markup
    case matlab
    case properties
    case toml
    case yaml
    case basic
    case css
    case ini
    case tex
    case adaVhdl
    case dcl
    case rexx
    case lispSiod
    case fortran
    case nsis
    case resources
    case verilog
    case batch
    case pascal
    case lua
    case innoSetup

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "c", "cc", "cpp", "cppm", "ixx", "cxx", "h", "hm", "hpp", "hxx", "inl", "rh", "tlh",
             "tli", "xs", "cs", "java", "jav", "js", "json", "rul":
            self = .cFamily
        case "pl", "pm", "plx", "po", "pot", "ps1", "psm1", "psd1", "rb", "rbw", "rake", "gemspec",
             "sh", "conf", "tcl":
            self = .hashLine
        case "py":
            self = .python
        case "sql":
            self = .sql
        case "m":
            self = .matlab
        case "properties":
            self = .properties
        case "toml":
            self = .toml
        case "yaml", "yml":
            self = .yaml
        case "bas", "vb", "vbs", "frm", "dsm", "cls", "ctl", "pag", "dsr":
            self = .basic
        case "css":
            self = .css
        case "ini", "reg", "vbp", "isl":
            self = .ini
        case "tex", "sty", "clo", "ltx", "fd", "dtx":
            self = .tex
        case "ads", "adb", "vhd", "vhdl", "vho":
            self = .adaVhdl
        case "dcl", "dcc":
            self = .dcl
        case "rex", "rexx":
            self = .rexx
        case "lsp", "dsl", "scm":
            self = .lispSiod
        case "f", "f90", "f9p", "fpp", "for", "f77":
            self = .fortran
        case "nsi", "nsh":
            self = .nsis
        case "rc", "dlg", "r16", "r32", "rc2":
            self = .resources
        case "v", "vh":
            self = .verilog
        case "bat", "btm", "cmd":
            self = .batch
        case "pas":
            self = .pascal
        case "lua":
            self = .lua
        case "iss":
            self = .innoSetup
        case "html", "htm", "shtml", "ihtml", "ssi", "stm", "stml", "jsp", "md", "markdown", "mdown",
             "mkd", "mkdn", "sgml", "xml":
            self = .markup
        default:
            return nil
        }
    }
}

public struct LineFilterRule: Codable, Equatable, Sendable {
    public var pattern: String
    public var caseSensitive: Bool

    public init(pattern: String, caseSensitive: Bool = true) {
        self.pattern = pattern
        self.caseSensitive = caseSensitive
    }
}

public struct SubstitutionRule: Codable, Equatable, Sendable {
    public var pattern: String
    public var replacement: String
    public var caseSensitive: Bool

    public init(pattern: String, replacement: String, caseSensitive: Bool = true) {
        self.pattern = pattern
        self.replacement = replacement
        self.caseSensitive = caseSensitive
    }
}

public struct LineDiffOptions: Codable, Equatable, Sendable {
    public var algorithm: DiffAlgorithm
    public var whitespace: WhitespaceComparison
    public var ignoreCase: Bool
    public var ignoreNumbers: Bool
    public var ignoreBlankLines: Bool
    public var ignoreComments: Bool
    public var ignoreLineEndings: Bool
    public var indentHeuristic: Bool
    public var lineFiltersEnabled: Bool
    public var lineFilters: [LineFilterRule]
    public var substitutionsEnabled: Bool
    public var substitutions: [SubstitutionRule]
    public var commentSyntax: CommentSyntax?

    public init(
        algorithm: DiffAlgorithm = .default,
        whitespace: WhitespaceComparison = .compareAll,
        ignoreCase: Bool = false,
        ignoreNumbers: Bool = false,
        ignoreBlankLines: Bool = false,
        ignoreComments: Bool = false,
        ignoreLineEndings: Bool = true,
        indentHeuristic: Bool = false,
        lineFiltersEnabled: Bool = true,
        lineFilters: [LineFilterRule] = [],
        substitutionsEnabled: Bool = true,
        substitutions: [SubstitutionRule] = [],
        commentSyntax: CommentSyntax? = nil
    ) {
        self.algorithm = algorithm
        self.whitespace = whitespace
        self.ignoreCase = ignoreCase
        self.ignoreNumbers = ignoreNumbers
        self.ignoreBlankLines = ignoreBlankLines
        self.ignoreComments = ignoreComments
        self.ignoreLineEndings = ignoreLineEndings
        self.indentHeuristic = indentHeuristic
        self.lineFiltersEnabled = lineFiltersEnabled
        self.lineFilters = lineFilters
        self.substitutionsEnabled = substitutionsEnabled
        self.substitutions = substitutions
        self.commentSyntax = commentSyntax
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case whitespace
        case ignoreCase
        case ignoreNumbers
        case ignoreBlankLines
        case ignoreComments
        case ignoreLineEndings
        case indentHeuristic
        case lineFiltersEnabled
        case lineFilters
        case substitutionsEnabled
        case substitutions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        algorithm = try container.decodeIfPresent(DiffAlgorithm.self, forKey: .algorithm) ?? .default
        whitespace = try container.decodeIfPresent(WhitespaceComparison.self, forKey: .whitespace) ?? .compareAll
        ignoreCase = try container.decodeIfPresent(Bool.self, forKey: .ignoreCase) ?? false
        ignoreNumbers = try container.decodeIfPresent(Bool.self, forKey: .ignoreNumbers) ?? false
        ignoreBlankLines = try container.decodeIfPresent(Bool.self, forKey: .ignoreBlankLines) ?? false
        ignoreComments = try container.decodeIfPresent(Bool.self, forKey: .ignoreComments) ?? false
        ignoreLineEndings = try container.decodeIfPresent(Bool.self, forKey: .ignoreLineEndings) ?? true
        indentHeuristic = try container.decodeIfPresent(Bool.self, forKey: .indentHeuristic) ?? false
        lineFiltersEnabled = try container.decodeIfPresent(Bool.self, forKey: .lineFiltersEnabled) ?? true
        lineFilters = try container.decodeIfPresent([LineFilterRule].self, forKey: .lineFilters) ?? []
        substitutionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .substitutionsEnabled) ?? true
        substitutions = try container.decodeIfPresent([SubstitutionRule].self, forKey: .substitutions) ?? []
        commentSyntax = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(algorithm, forKey: .algorithm)
        try container.encode(whitespace, forKey: .whitespace)
        try container.encode(ignoreCase, forKey: .ignoreCase)
        try container.encode(ignoreNumbers, forKey: .ignoreNumbers)
        try container.encode(ignoreBlankLines, forKey: .ignoreBlankLines)
        try container.encode(ignoreComments, forKey: .ignoreComments)
        try container.encode(ignoreLineEndings, forKey: .ignoreLineEndings)
        try container.encode(indentHeuristic, forKey: .indentHeuristic)
        try container.encode(lineFiltersEnabled, forKey: .lineFiltersEnabled)
        try container.encode(lineFilters, forKey: .lineFilters)
        try container.encode(substitutionsEnabled, forKey: .substitutionsEnabled)
        try container.encode(substitutions, forKey: .substitutions)
    }
}

public enum LineDiffError: Error, LocalizedError, Equatable, Sendable {
    case nativeEngineFailure(Int32)
    case inputTooLarge(maximumBytes: Int)
    case tooManyLines(maximumLines: Int)
    case invalidRegularExpression(String)
    case filterChangedLineStructure
    case rawBytePlaceholderUnavailable
    case substitutionEngineFailure(Int32)
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
        case .rawBytePlaceholderUnavailable:
            "Raw-byte substitutions could not reserve a collision-free placeholder range."
        case let .substitutionEngineFailure(code):
            "WinMerge substitution engine failed with code \(code)."
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

    public let left: DiffLine?
    public let right: DiffLine?
    public let kind: DiffKind

    public var id: ID {
        ID(leftNumber: left?.number, rightNumber: right?.number)
    }

    public init(left: DiffLine?, right: DiffLine?, kind: DiffKind) {
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
        let commentFiltered = transform.commentFilteredPair(left: leftDocument, right: rightDocument)
        let hunks = try nativeHunks(
            left: leftDocument.comparisonText(options: options),
            right: rightDocument.comparisonText(options: options),
            options: options
        )
        var rows: [DiffRow] = []
        var leftIndex = 0
        var rightIndex = 0

        for hunk in hunks {
            guard hunk.leftStart >= leftIndex,
                  hunk.rightStart >= rightIndex,
                  hunk.leftStart <= leftDocument.records.count,
                  hunk.rightStart <= rightDocument.records.count,
                  hunk.leftCount <= leftDocument.records.count - hunk.leftStart,
                  hunk.rightCount <= rightDocument.records.count - hunk.rightStart,
                  hunk.leftStart - leftIndex == hunk.rightStart - rightIndex else {
                throw LineDiffError.invalidNativeResult
            }

            while leftIndex < hunk.leftStart {
                rows.append(row(
                    left: line(at: leftIndex, in: leftDocument),
                    right: line(at: rightIndex, in: rightDocument),
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
                    commentFiltered: commentFiltered,
                    options: options,
                    leftIndex: &leftIndex,
                    rightIndex: &rightIndex
                )
            } else {
                appendChangedRows(
                    to: &rows,
                    hunk: hunk,
                    left: leftDocument,
                    right: rightDocument,
                    leftFiltered: nil,
                    rightFiltered: nil,
                    leftIndex: &leftIndex,
                    rightIndex: &rightIndex
                )
            }
        }

        guard leftDocument.records.count - leftIndex == rightDocument.records.count - rightIndex else {
            throw LineDiffError.invalidNativeResult
        }
        while leftIndex < leftDocument.records.count {
            rows.append(row(
                left: line(at: leftIndex, in: leftDocument),
                right: line(at: rightIndex, in: rightDocument),
                kind: .unchanged
            ))
            leftIndex += 1
            rightIndex += 1
        }

        return rows
    }

    private static func line(
        at index: Int,
        in document: TextDocument,
        numberOffset: Int = 0
    ) -> DiffLine {
        DiffLine(number: numberOffset + index + 1, text: document.records[index].content)
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
            left: left,
            right: right,
            kind: kind
        )
    }

    private static func appendChangedRows(
        to rows: inout [DiffRow],
        hunk: NativeHunk,
        left: TextDocument,
        right: TextDocument,
        leftFiltered: [Bool]?,
        rightFiltered: [Bool]?,
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
            let leftIsFiltered = hasLeft && leftFiltered?[leftIndex] == true
            let rightIsFiltered = hasRight && rightFiltered?[rightIndex] == true

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
        commentFiltered: ComparisonTransform.CommentFilteredPair?,
        options: LineDiffOptions,
        leftIndex: inout Int,
        rightIndex: inout Int
    ) throws {
        let leftSlice = leftDocument.slice(start: hunk.leftStart, count: hunk.leftCount)
        let rightSlice = rightDocument.slice(start: hunk.rightStart, count: hunk.rightCount)
        let prepared = try transform.prepare(
            left: leftSlice,
            right: rightSlice,
            options: options,
            leftComments: commentFiltered?.left.slice(start: hunk.leftStart, count: hunk.leftCount),
            rightComments: commentFiltered?.right.slice(start: hunk.rightStart, count: hunk.rightCount)
        )
        let secondaryHunks = try nativeHunks(
            left: prepared.left.bytes,
            right: prepared.right.bytes,
            options: options
        )
        var localLeftIndex = 0
        var localRightIndex = 0

        for secondary in secondaryHunks {
            guard secondary.leftStart >= localLeftIndex,
                  secondary.rightStart >= localRightIndex,
                  secondary.leftStart <= leftSlice.records.count,
                  secondary.rightStart <= rightSlice.records.count,
                  secondary.leftCount <= leftSlice.records.count - secondary.leftStart,
                  secondary.rightCount <= rightSlice.records.count - secondary.rightStart,
                  secondary.leftStart - localLeftIndex == secondary.rightStart - localRightIndex else {
                throw LineDiffError.invalidNativeResult
            }
            while localLeftIndex < secondary.leftStart {
                rows.append(row(
                    left: line(at: localLeftIndex, in: leftSlice, numberOffset: hunk.leftStart),
                    right: line(at: localRightIndex, in: rightSlice, numberOffset: hunk.rightStart),
                    kind: .unchanged
                ))
                localLeftIndex += 1
                localRightIndex += 1
            }
            appendChangedRows(
                to: &rows,
                hunk: secondary,
                left: leftSlice,
                right: rightSlice,
                leftFiltered: prepared.left.filteredLines,
                rightFiltered: prepared.right.filteredLines,
                leftIndex: &localLeftIndex,
                rightIndex: &localRightIndex,
                leftNumberOffset: hunk.leftStart,
                rightNumberOffset: hunk.rightStart
            )
        }

        guard leftSlice.records.count - localLeftIndex == rightSlice.records.count - localRightIndex else {
            throw LineDiffError.invalidNativeResult
        }
        while localLeftIndex < leftSlice.records.count {
            rows.append(row(
                left: line(at: localLeftIndex, in: leftSlice, numberOffset: hunk.leftStart),
                right: line(at: localRightIndex, in: rightSlice, numberOffset: hunk.rightStart),
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
        try nativeHunks(left: Array(left.utf8), right: Array(right.utf8), options: options)
    }

    private static func nativeHunks(
        left leftBytes: [UInt8],
        right rightBytes: [UInt8],
        options: LineDiffOptions
    ) throws -> [NativeHunk] {
        let maximumBytes = Int(MMX_MAX_INPUT_SIZE)
        guard leftBytes.count <= maximumBytes, rightBytes.count <= maximumBytes else {
            throw LineDiffError.inputTooLarge(maximumBytes: maximumBytes)
        }
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
    let bytes: [UInt8]
    let filteredLines: [Bool]
}

private struct PreparedComparisonPair {
    let left: PreparedComparison
    let right: PreparedComparison
}

private struct PascalCommentState {
    var lineComment = false
    var parenComment = false
    var braceComment = false
    var directive = false
    var rawString = false
    var quote: UInt16?
}

private struct ComparisonTransform {
    struct CommentFilteredContents {
        let contents: [String]
        let commentOnly: [Bool]

        func slice(start: Int, count: Int) -> CommentFilteredContents {
            let range = start..<(start + count)
            return CommentFilteredContents(
                contents: Array(contents[range]),
                commentOnly: Array(commentOnly[range])
            )
        }
    }

    struct CommentFilteredPair {
        let left: CommentFilteredContents
        let right: CommentFilteredContents
    }

    private enum ReplacementPart {
        case literal(String)
        case capture(Int)
        case rawByte(UInt8)

        var bytes: [UInt8] {
            switch self {
            case let .literal(value):
                Array(value.utf8)
            case let .capture(group):
                Array("$\(group)".utf8)
            case let .rawByte(byte):
                [byte]
            }
        }
    }

    private struct CompiledRule {
        let pattern: String
        let caseSensitive: Bool
        let expression: NSRegularExpression
        let replacement: [ReplacementPart]?

        var replacementBytes: [UInt8] { replacement?.flatMap(\.bytes) ?? [] }
    }

    private let lineFilters: [CompiledRule]
    private let substitutions: [CompiledRule]
    private let commentSyntax: CommentSyntax?

    var isActive: Bool { commentSyntax != nil || !lineFilters.isEmpty || !substitutions.isEmpty }

    init(options: LineDiffOptions) throws {
        lineFilters = try (options.lineFiltersEnabled ? options.lineFilters : []).map {
            return CompiledRule(
                pattern: $0.pattern,
                caseSensitive: $0.caseSensitive,
                expression: try Self.compile(pattern: $0.pattern, caseSensitive: $0.caseSensitive),
                replacement: nil
            )
        }
        substitutions = try (options.substitutionsEnabled ? options.substitutions : [])
            .filter { !$0.pattern.isEmpty }
            .map {
            _ = try Self.replaceBytes(
                in: [],
                pattern: Array($0.pattern.utf8),
                replacement: [],
                caseSensitive: $0.caseSensitive,
                maximumBytes: Int(MMX_MAX_INPUT_SIZE)
            )
            return CompiledRule(
                pattern: $0.pattern,
                caseSensitive: $0.caseSensitive,
                expression: try Self.compile(pattern: "(?:)", caseSensitive: true),
                replacement: try Self.parseReplacement($0.replacement)
            )
        }
        commentSyntax = options.ignoreComments ? options.commentSyntax : nil
    }

    func prepare(
        left: TextDocument,
        right: TextDocument,
        options: LineDiffOptions,
        leftComments: CommentFilteredContents? = nil,
        rightComments: CommentFilteredContents? = nil
    ) throws -> PreparedComparisonPair {
        let marker = collisionFreeMarker(left: left.text, right: right.text)
        return try PreparedComparisonPair(
            left: prepare(
                document: left,
                marker: marker,
                options: options,
                commentFiltered: leftComments
            ),
            right: prepare(
                document: right,
                marker: marker,
                options: options,
                commentFiltered: rightComments
            )
        )
    }

    private func prepare(
        document: TextDocument,
        marker: String,
        options: LineDiffOptions,
        commentFiltered: CommentFilteredContents?
    ) throws -> PreparedComparison {
        var contents: [String] = []
        var filteredLines: [Bool] = []
        let maximumBytes = Int(MMX_MAX_INPUT_SIZE)
        let commentFiltered = commentFiltered ?? commentFilteredContents(in: document)
        contents.reserveCapacity(document.records.count)
        filteredLines.reserveCapacity(document.records.count)

        for (index, record) in document.records.enumerated() {
            let content = commentFiltered?.contents[index] ?? record.content
            let fullRange = NSRange(content.startIndex..<content.endIndex, in: content)
            let isFiltered = commentFiltered?.commentOnly[index] == true || lineFilters.contains {
                $0.expression.firstMatch(in: content, range: fullRange) != nil
            }
            contents.append(isFiltered ? marker : content)
            filteredLines.append(isFiltered)
        }

        let transformedText = zip(contents, document.records)
            .map { $0 + $1.terminator }
            .joined()
        var transformedBytes = Array(transformedText.utf8)
        for substitution in substitutions {
            transformedBytes = try Self.replaceBytes(
                in: transformedBytes,
                pattern: Array(substitution.pattern.utf8),
                replacement: substitution.replacementBytes,
                caseSensitive: substitution.caseSensitive,
                maximumBytes: maximumBytes
            )
        }
        var transformedRecords = Self.byteRecords(transformedBytes)
        if transformedRecords.count + 1 == document.records.count,
           document.records.last?.terminator.isEmpty == true,
           transformedBytes.isEmpty || transformedBytes.last == 10 || transformedBytes.last == 13 {
            transformedRecords.append(([], []))
        }
        guard transformedRecords.count == document.records.count else {
            throw LineDiffError.filterChangedLineStructure
        }
        var comparisonBytes: [UInt8] = []
        comparisonBytes.reserveCapacity(transformedBytes.count + transformedRecords.count * 2)
        for ((content, terminator), isFiltered) in zip(transformedRecords, filteredLines) {
            if isFiltered {
                comparisonBytes.append(contentsOf: marker.utf8)
                comparisonBytes.append(contentsOf: options.ignoreLineEndings ? [10] : terminator)
                continue
            }
            let preservesBlankLine = options.ignoreBlankLines &&
                content.allSatisfy { $0 == 32 || $0 == 9 }
            if !preservesBlankLine { comparisonBytes.append(contentsOf: [85, 58]) }
            comparisonBytes.append(contentsOf: content)
            comparisonBytes.append(contentsOf: options.ignoreLineEndings ? [10] : terminator)
        }

        return PreparedComparison(
            bytes: comparisonBytes,
            filteredLines: filteredLines
        )
    }

    func commentFilteredPair(left: TextDocument, right: TextDocument) -> CommentFilteredPair? {
        guard let left = commentFilteredContents(in: left),
              let right = commentFilteredContents(in: right) else { return nil }
        return CommentFilteredPair(left: left, right: right)
    }

    private func commentFilteredContents(
        in document: TextDocument
    ) -> CommentFilteredContents? {
        guard let commentSyntax else { return nil }
        switch commentSyntax {
        case .cFamily:
            return legacyCLikeCommentFilteredContents(
                in: document,
                carriesEscapedState: true,
                preprocessorMarker: "#"
            )
        case .dcl:
            return legacyCLikeCommentFilteredContents(in: document, carriesEscapedState: false)
        case .rexx:
            return legacyCLikeCommentFilteredContents(in: document, carriesEscapedState: true)
        case .lispSiod:
            return lispCommentFilteredContents(in: document)
        case .fortran:
            return fortranCommentFilteredContents(in: document)
        case .nsis:
            return legacyCLikeCommentFilteredContents(
                in: document,
                carriesEscapedState: true,
                preprocessorMarker: "!"
            )
        case .resources:
            return legacyCLikeCommentFilteredContents(
                in: document,
                carriesEscapedState: true,
                preprocessorMarker: "#",
                singleQuoteUsesTwoLookback: false
            )
        case .verilog:
            return legacyCLikeCommentFilteredContents(
                in: document,
                carriesEscapedState: false,
                preprocessorMarker: "`",
                supportsSingleQuote: false
            )
        case .batch:
            return batchCommentFilteredContents(in: document)
        case .pascal:
            return pascalCommentFilteredContents(in: document)
        case .lua:
            return luaCommentFilteredContents(in: document)
        case .innoSetup:
            return innoSetupCommentFilteredContents(in: document)
        case .matlab:
            return matlabCommentFilteredContents(in: document)
        case .properties:
            return propertiesCommentFilteredContents(in: document)
        case .toml:
            return tomlCommentFilteredContents(in: document)
        case .yaml:
            return yamlCommentFilteredContents(in: document)
        case .basic:
            return quotedLineCommentFilteredContents(in: document, delimiter: "'", quote: "\"")
        case .css:
            return blockCommentFilteredContents(in: document, opener: "/*", closer: "*/")
        case .ini:
            return firstNonspaceCommentFilteredContents(in: document, delimiters: [";"])
        case .tex:
            return texCommentFilteredContents(in: document)
        case .adaVhdl:
            return unquotedLineCommentFilteredContents(in: document, delimiter: "--")
        default:
            break
        }
        let lineDelimiters: [String]
        let blockDelimiter: (start: String, end: String)?
        let supportsTripleQuotedStrings: Bool
        switch commentSyntax {
        case .hashLine:
            lineDelimiters = ["#"]
            blockDelimiter = nil
            supportsTripleQuotedStrings = false
        case .python:
            lineDelimiters = ["#"]
            blockDelimiter = nil
            supportsTripleQuotedStrings = true
        case .sql:
            lineDelimiters = ["//", "--"]
            blockDelimiter = ("/*", "*/")
            supportsTripleQuotedStrings = false
        case .markup:
            lineDelimiters = []
            blockDelimiter = ("<!--", "-->")
            supportsTripleQuotedStrings = false
        case .cFamily, .matlab, .properties, .toml, .yaml, .basic, .css, .ini, .tex, .adaVhdl,
             .dcl, .rexx, .lispSiod, .fortran, .nsis, .resources, .verilog, .batch, .pascal,
             .lua, .innoSetup:
            preconditionFailure("Dedicated comment scanner was not selected")
        }
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inBlockComment = false
        var inMarkupElement = false
        var quote: Character?
        var tripleQuote: String?
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var index = record.content.startIndex
            var containedComment = inBlockComment

            while index < record.content.endIndex {
                let character = record.content[index]
                let nextIndex = record.content.index(after: index)
                let remainder = record.content[index...]

                if inBlockComment {
                    containedComment = true
                    if let blockDelimiter, remainder.hasPrefix(blockDelimiter.end) {
                        inBlockComment = false
                        index = record.content.index(index, offsetBy: blockDelimiter.end.count)
                    } else {
                        index = nextIndex
                    }
                    continue
                }

                if let activeTripleQuote = tripleQuote {
                    if remainder.hasPrefix(activeTripleQuote) {
                        output.append(contentsOf: activeTripleQuote)
                        index = record.content.index(index, offsetBy: activeTripleQuote.count)
                        tripleQuote = nil
                    } else {
                        output.append(character)
                        index = nextIndex
                    }
                    continue
                }

                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: record.content, at: index) {
                        quote = nil
                    }
                    index = nextIndex
                    continue
                }

                if supportsTripleQuotedStrings,
                   let delimiter = ["\"\"\"", "'''"].first(where: remainder.hasPrefix) {
                    tripleQuote = delimiter
                    output.append(contentsOf: delimiter)
                    index = record.content.index(index, offsetBy: delimiter.count)
                    continue
                }
                if let blockDelimiter, remainder.hasPrefix(blockDelimiter.start) {
                    containedComment = true
                    inBlockComment = true
                    if commentSyntax == .markup { inMarkupElement = false }
                    index = record.content.index(index, offsetBy: blockDelimiter.start.count)
                    continue
                }
                if lineDelimiters.contains(where: remainder.hasPrefix) {
                    containedComment = true
                    break
                }
                if commentSyntax == .markup, character == "<" {
                    inMarkupElement = true
                } else if commentSyntax == .markup, character == ">" {
                    inMarkupElement = false
                }
                if (commentSyntax != .markup || inMarkupElement), character == "\"" || character == "'" {
                    quote = character
                }
                output.append(character)
                index = nextIndex
            }

            if tripleQuote == nil {
                if commentSyntax == .markup {
                    if quote != "\"" { quote = nil }
                } else if record.content.last != "\\" {
                    quote = nil
                }
            }

            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func legacyCLikeCommentFilteredContents(
        in document: TextDocument,
        carriesEscapedState: Bool,
        preprocessorMarker: Character? = nil,
        supportsSingleQuote: Bool = true,
        singleQuoteUsesTwoLookback: Bool = true
    ) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inBlockComment = false
        var inLineComment = false
        var inPreprocessor = false
        var quote: Character?
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            if record.content.isEmpty {
                let containedComment = inBlockComment
                contents.append("")
                commentOnly.append(Self.isWholeCommentLine(containedComment, output: "", record: record))
                inLineComment = false
                inPreprocessor = false
                quote = nil
                continue
            }

            var output = ""
            var index = record.content.startIndex
            var containedComment = inBlockComment || inLineComment
            var firstToken = !inLineComment && !inPreprocessor && quote == nil

            if inLineComment {
                index = record.content.endIndex
            }

            while index < record.content.endIndex {
                let character = record.content[index]
                let nextIndex = record.content.index(after: index)
                let remainder = record.content[index...]

                if inBlockComment {
                    containedComment = true
                    if remainder.hasPrefix("*/") {
                        inBlockComment = false
                        index = record.content.index(index, offsetBy: 2)
                    } else {
                        index = nextIndex
                    }
                    continue
                }

                if let activeQuote = quote {
                    output.append(character)
                    let closes = activeQuote == "'" && !singleQuoteUsesTwoLookback
                        ? Self.oneLookbackQuoteCloses(in: record.content, at: index)
                        : Self.twoLookbackQuoteCloses(in: record.content, at: index)
                    if character == activeQuote, closes { quote = nil }
                    index = nextIndex
                    continue
                }

                if remainder.hasPrefix("//") {
                    containedComment = true
                    inLineComment = true
                    break
                }
                if remainder.hasPrefix("/*") {
                    containedComment = true
                    if inPreprocessor, remainder.hasPrefix("/*/") {
                        index = record.content.index(index, offsetBy: 3)
                        continue
                    }
                    inBlockComment = true
                    firstToken = false
                    index = record.content.index(index, offsetBy: 2)
                    continue
                }
                if !inPreprocessor, character == "\"" {
                    quote = character
                    output.append(character)
                    index = nextIndex
                    continue
                }
                if !inPreprocessor, supportsSingleQuote, character == "'",
                   index == record.content.startIndex ||
                   !Self.legacyIsAlphanumeric(record.content[record.content.index(before: index)]) {
                    quote = character
                    output.append(character)
                    index = nextIndex
                    continue
                }
                if !inPreprocessor, firstToken, character == preprocessorMarker {
                    inPreprocessor = true
                }
                output.append(character)
                if !character.isWhitespace { firstToken = false }
                index = nextIndex
            }

            if !carriesEscapedState || record.content.last != "\\" {
                inLineComment = false
                inPreprocessor = false
                quote = nil
            }
            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func lispCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inBlockComment = false
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var index = record.content.startIndex
            var quote: Character?
            var containedComment = inBlockComment

            while index < record.content.endIndex {
                let character = record.content[index]
                let nextIndex = record.content.index(after: index)
                let remainder = record.content[index...]

                if inBlockComment {
                    containedComment = true
                    if remainder.hasPrefix("|;") {
                        inBlockComment = false
                        index = record.content.index(index, offsetBy: 2)
                    } else {
                        index = nextIndex
                    }
                    continue
                }
                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: record.content, at: index) {
                        quote = nil
                    }
                    index = nextIndex
                    continue
                }
                if remainder.hasPrefix(";|") {
                    containedComment = true
                    inBlockComment = true
                    index = record.content.index(index, offsetBy: 2)
                    continue
                }
                if character == ";", nextIndex < record.content.endIndex {
                    containedComment = true
                    break
                }
                if character == "\"" || character == "'" && (
                    index == record.content.startIndex ||
                    !Self.legacyIsAlphanumeric(record.content[record.content.index(before: index)])
                ) {
                    quote = character
                }
                output.append(character)
                index = nextIndex
            }

            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func fortranCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inLineComment = false
        var quote: Character?
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            if record.content.isEmpty {
                contents.append("")
                commentOnly.append(false)
                inLineComment = false
                quote = nil
                continue
            }

            var output = ""
            var index = record.content.startIndex
            var containedComment = inLineComment
            if inLineComment { index = record.content.endIndex }

            while index < record.content.endIndex {
                let character = record.content[index]
                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: record.content, at: index) {
                        quote = nil
                    }
                } else if character == "!" ||
                          index == record.content.startIndex && (character == "C" || character == "c") {
                    containedComment = true
                    inLineComment = true
                    break
                } else {
                    if character == "\"" || character == "'" && (
                        index == record.content.startIndex ||
                        !Self.legacyIsAlphanumeric(record.content[record.content.index(before: index)])
                    ) {
                        quote = character
                    }
                    output.append(character)
                }
                index = record.content.index(after: index)
            }

            if record.content.last != "\\" {
                inLineComment = false
                quote = nil
            }
            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func batchCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var index = record.content.startIndex
            var quote: Character?
            var firstToken = true
            var containedComment = false

            while index < record.content.endIndex {
                let character = record.content[index]
                let nextIndex = record.content.index(after: index)

                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: record.content, at: index) {
                        quote = nil
                    }
                    index = nextIndex
                    continue
                }
                if character == "\"" || character == "'" && (
                    index == record.content.startIndex ||
                    !Self.legacyIsAlphanumeric(record.content[record.content.index(before: index)])
                ) {
                    quote = character
                    output.append(character)
                    index = nextIndex
                    continue
                }
                if firstToken {
                    let remainder = record.content[index...]
                    if remainder.count >= 3,
                       remainder.prefix(3).lowercased() == "rem" {
                        let boundary = record.content.index(index, offsetBy: 3)
                        if boundary == record.content.endIndex || record.content[boundary].isWhitespace {
                            containedComment = true
                            break
                        }
                    }
                    let afterColon = record.content[nextIndex...].utf16
                    if character == ":", afterColon.count > 1, let next = afterColon.first {
                        if !Self.legacyIsAlphanumeric(next), !Self.legacyIsWhitespace(next) {
                            containedComment = true
                            break
                        }
                    }
                }
                output.append(character)
                if !character.isWhitespace { firstToken = false }
                index = nextIndex
            }

            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func pascalCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var state = PascalCommentState()
        var contents: [String] = []
        var commentOnly: [Bool] = []
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let result = Self.filterPascalCommentLine(record.content, state: &state)
            if record.content.isEmpty {
                state.lineComment = false
                state.directive = false
                state.quote = nil
            } else if record.content.last != "\\" {
                state.lineComment = false
                state.directive = false
                state.quote = nil
            }
            contents.append(result.output)
            commentOnly.append(Self.isWholeCommentLine(
                result.containedComment,
                output: result.output,
                record: record
            ))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func luaCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var longCommentEquals: Int?
        var longStringEquals: Int?
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var quote: UInt16?
            var containedComment = longCommentEquals != nil

            while index < units.count {
                let character = units[index]
                if character == 0 {
                    if longCommentEquals == nil { output.append(contentsOf: units[index...]) }
                    break
                }

                if let equalsCount = longCommentEquals {
                    containedComment = true
                    if let end = Self.luaLongDelimiterEnd(
                        in: units,
                        at: index,
                        bracket: 93,
                        equalsCount: equalsCount
                    ) {
                        longCommentEquals = nil
                        index = end
                    } else {
                        index += 1
                    }
                    continue
                }
                if let equalsCount = longStringEquals {
                    if let end = Self.luaLongDelimiterEnd(
                        in: units,
                        at: index,
                        bracket: 93,
                        equalsCount: equalsCount
                    ) {
                        output.append(contentsOf: units[index..<end])
                        longStringEquals = nil
                        index = end
                    } else {
                        output.append(character)
                        index += 1
                    }
                    continue
                }
                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: units, at: index) {
                        quote = nil
                    }
                    index += 1
                    continue
                }
                if index + 1 < units.count, character == 45, units[index + 1] == 45 {
                    if let delimiter = Self.luaLongDelimiter(in: units, at: index + 2, bracket: 91) {
                        containedComment = true
                        longCommentEquals = delimiter.equalsCount & 0xF
                        index = delimiter.end
                    } else {
                        containedComment = true
                        break
                    }
                    continue
                }
                if character == 34 || character == 39 && (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                    quote = character
                    output.append(character)
                    index += 1
                    continue
                }
                if let delimiter = Self.luaLongDelimiter(in: units, at: index, bracket: 91) {
                    longStringEquals = delimiter.equalsCount & 0xF
                    output.append(contentsOf: units[index..<delimiter.end])
                    index = delimiter.end
                    continue
                }
                output.append(character)
                index += 1
            }

            let outputText = String(decoding: output, as: UTF16.self)
            contents.append(outputText)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: outputText, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func innoSetupCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inCodeSection = false
        var pascalState = PascalCommentState()
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            if record.content.isEmpty {
                pascalState.lineComment = false
                pascalState.directive = false
                pascalState.rawString = false
                pascalState.quote = nil
                contents.append("")
                commentOnly.append(false)
                continue
            }

            if let section = Self.innoSetupSection(in: record.content) {
                inCodeSection = section.caseInsensitiveCompare("Code") == .orderedSame
                pascalState = PascalCommentState()
            } else if inCodeSection {
                let result = Self.filterPascalCommentLine(record.content, state: &pascalState)
                if record.content.last != "\\" {
                    pascalState.lineComment = false
                    pascalState.directive = false
                    pascalState.quote = nil
                }
                contents.append(result.output)
                commentOnly.append(Self.isWholeCommentLine(
                    result.containedComment,
                    output: result.output,
                    record: record
                ))
                continue
            }

            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var quote: UInt16?
            var inConstant = false
            var inSection = false
            var firstToken = true
            var containedComment = false

            while index < units.count {
                let character = units[index]
                if character == 0 {
                    output.append(contentsOf: units[index...])
                    break
                }
                if inConstant {
                    output.append(character)
                    if character == 125 { inConstant = false }
                    index += 1
                    continue
                }
                if inSection {
                    output.append(character)
                    if character == 93 { inSection = false }
                    index += 1
                    continue
                }
                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: units, at: index) {
                        quote = nil
                    }
                    index += 1
                    continue
                }
                if character == 34 || character == 39 && (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                    quote = character
                    output.append(character)
                    index += 1
                    continue
                }
                if character == 123 {
                    inConstant = true
                    output.append(character)
                    index += 1
                    continue
                }
                if firstToken, character == 91 {
                    inSection = true
                    output.append(character)
                    index += 1
                    continue
                }
                if firstToken, character == 35 {
                    output.append(character)
                    index += 1
                    continue
                }
                if firstToken, character == 59 {
                    containedComment = true
                    break
                }
                output.append(character)
                if !Self.legacyIsWhitespace(character) { firstToken = false }
                index += 1
            }

            let outputText = String(decoding: output, as: UTF16.self)
            contents.append(outputText)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: outputText, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private static func filterPascalCommentLine(
        _ text: String,
        state: inout PascalCommentState
    ) -> (output: String, containedComment: Bool) {
        let units = Array(text.utf16)
        var output: [UInt16] = []
        var index = 0
        var containedComment = state.lineComment || state.parenComment || state.braceComment

        if state.lineComment { return ("", true) }
        while index < units.count {
            let character = units[index]
            if character == 0 {
                if !state.parenComment, !state.braceComment { output.append(contentsOf: units[index...]) }
                break
            }

            if state.parenComment {
                containedComment = true
                if index + 1 < units.count, character == 42, units[index + 1] == 41,
                   index == 0 || units[index - 1] != 40 {
                    state.parenComment = false
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if state.braceComment {
                containedComment = true
                if character == 125 { state.braceComment = false }
                index += 1
                continue
            }
            if state.directive {
                output.append(character)
                if character == 125 {
                    state.directive = false
                } else if index + 1 < units.count, character == 42, units[index + 1] == 41,
                          index == 0 || units[index - 1] != 40 {
                    output.append(41)
                    state.directive = false
                    index += 2
                    continue
                }
                index += 1
                continue
            }
            if state.rawString {
                output.append(character)
                if index + 2 < units.count, character == 39, units[index + 1] == 39, units[index + 2] == 39,
                   Self.pascalRawStringCanClose(in: units, at: index) {
                    output.append(contentsOf: [39, 39])
                    state.rawString = false
                    index += 3
                } else {
                    index += 1
                }
                continue
            }
            if let activeQuote = state.quote {
                output.append(character)
                if character == activeQuote, Self.twoLookbackQuoteCloses(in: units, at: index) {
                    if activeQuote == 39, index > 0, index + 1 < units.count,
                       units[index - 1] == 39, units[index + 1] == 39,
                       (index + 2 == units.count || units[index + 2] != 39),
                       Self.pascalRawStringCanOpen(in: units, after: index + 2) {
                        output.append(39)
                        state.quote = nil
                        state.rawString = true
                        index += 2
                        continue
                    }
                    state.quote = nil
                }
                index += 1
                continue
            }
            if index + 1 < units.count, character == 47, units[index + 1] == 47 {
                containedComment = true
                state.lineComment = true
                break
            }
            if index + 1 < units.count, character == 40, units[index + 1] == 42 {
                if index + 2 < units.count, units[index + 2] == 36 {
                    state.directive = true
                    output.append(contentsOf: [40, 42])
                } else {
                    state.parenComment = true
                    containedComment = true
                }
                index += 2
                continue
            }
            if character == 123 {
                if index + 1 < units.count, units[index + 1] == 36 {
                    state.directive = true
                    output.append(character)
                } else {
                    state.braceComment = true
                    containedComment = true
                }
                index += 1
                continue
            }
            if index + 2 < units.count, character == 39, units[index + 1] == 39, units[index + 2] == 39,
               (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])),
               Self.pascalRawStringCanOpen(in: units, after: index + 3) {
                state.rawString = true
                output.append(contentsOf: [39, 39, 39])
                index += 3
                continue
            }
            if character == 34 || character == 39 && (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                state.quote = character
            }
            output.append(character)
            index += 1
        }
        return (String(decoding: output, as: UTF16.self), containedComment)
    }

    private static func pascalRawStringCanOpen(in units: [UInt16], after index: Int) -> Bool {
        units[index...].allSatisfy { $0 == 32 || $0 == 9 }
    }

    private static func pascalRawStringCanClose(in units: [UInt16], at index: Int) -> Bool {
        guard index > 0 else { return true }
        return units[1..<index].allSatisfy { $0 == 32 || $0 == 9 }
    }

    private static func luaLongDelimiter(
        in units: [UInt16],
        at index: Int,
        bracket: UInt16
    ) -> (equalsCount: Int, end: Int)? {
        guard index < units.count, units[index] == bracket else { return nil }
        var cursor = index + 1
        var equalsCount = 0
        while cursor < units.count, units[cursor] == 61 {
            equalsCount += 1
            cursor += 1
        }
        guard cursor < units.count, units[cursor] == bracket else { return nil }
        return (equalsCount, cursor + 1)
    }

    private static func luaLongDelimiterEnd(
        in units: [UInt16],
        at index: Int,
        bracket: UInt16,
        equalsCount: Int
    ) -> Int? {
        guard let delimiter = luaLongDelimiter(in: units, at: index, bracket: bracket),
              delimiter.equalsCount == equalsCount else { return nil }
        return delimiter.end
    }

    private static func innoSetupSection(in text: String) -> String? {
        let units = Array(text.utf16)
        var start = 0
        while start < units.count, legacyIsWhitespace(units[start]) { start += 1 }
        guard start < units.count, units[start] == 91,
              let end = units[(start + 1)...].firstIndex(of: 93) else { return nil }
        return String(decoding: units[(start + 1)..<end], as: UTF16.self)
    }

    private func matlabCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var blockDepth = 0
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var index = record.content.startIndex
            var quote: Character?
            var containedComment = blockDepth > 0

            while index < record.content.endIndex {
                let character = record.content[index]
                let nextIndex = record.content.index(after: index)
                let remainder = record.content[index...]

                if blockDepth > 0 {
                    containedComment = true
                    if remainder.hasPrefix("%{") {
                        blockDepth += 1
                        index = record.content.index(index, offsetBy: 2)
                    } else if remainder.hasPrefix("%}") {
                        blockDepth -= 1
                        index = record.content.index(index, offsetBy: 2)
                    } else {
                        index = nextIndex
                    }
                    continue
                }

                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: record.content, at: index) {
                        quote = nil
                    }
                    index = nextIndex
                    continue
                }

                if remainder.hasPrefix("%{") {
                    let afterOpener = record.content.index(index, offsetBy: 2)
                    if afterOpener == record.content.endIndex || record.content[afterOpener].isWhitespace {
                        containedComment = true
                        blockDepth = 1
                        index = afterOpener
                        continue
                    }
                }
                if character == "%" {
                    containedComment = true
                    break
                }
                if remainder.hasPrefix("...") {
                    output.append(contentsOf: "...")
                    index = record.content.index(index, offsetBy: 3)
                    if index < record.content.endIndex { containedComment = true }
                    break
                }
                if character == "\"" {
                    quote = character
                } else if character == "'" {
                    let opensString = index == record.content.startIndex ||
                        !record.content[record.content.index(before: index)].isLetter &&
                        !record.content[record.content.index(before: index)].isNumber
                    if opensString { quote = character }
                }
                output.append(character)
                index = nextIndex
            }

            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func propertiesCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var continuesValue = false
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let firstContent = record.content.firstIndex { $0 != " " && $0 != "\t" && $0 != "\u{000C}" }
            let isComment = !continuesValue && firstContent.map {
                record.content[$0] == "#" || record.content[$0] == "!"
            } == true
            if isComment {
                let leading = firstContent.map { String(record.content[..<$0]) } ?? ""
                contents.append(leading)
                commentOnly.append(Self.isWholeCommentLine(true, output: leading, record: record))
                continuesValue = false
            } else {
                contents.append(record.content)
                commentOnly.append(false)
                continuesValue = record.content.reversed().prefix(while: { $0 == "\\" }).count.isMultiple(of: 2) == false
            }
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func tomlCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var multilineDelimiter: String?
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var index = record.content.startIndex
            var quote: Character?
            var escaped = false
            var containedComment = false

            while index < record.content.endIndex {
                let character = record.content[index]
                let nextIndex = record.content.index(after: index)
                let remainder = record.content[index...]

                if let delimiter = multilineDelimiter {
                    if delimiter == "\"\"\"", escaped {
                        output.append(character)
                        escaped = false
                        index = nextIndex
                    } else if delimiter == "\"\"\"", character == "\\" {
                        output.append(character)
                        escaped = true
                        index = nextIndex
                    } else if remainder.hasPrefix(delimiter) {
                        let runLength = remainder.prefix(while: { $0 == character }).count
                        if runLength > 5 {
                            output.append(character)
                            index = nextIndex
                            continue
                        }
                        if runLength > delimiter.count {
                            output.append(contentsOf: String(repeating: character, count: runLength - delimiter.count))
                        }
                        output.append(contentsOf: delimiter)
                        index = record.content.index(index, offsetBy: runLength)
                        multilineDelimiter = nil
                    } else {
                        output.append(character)
                        index = nextIndex
                    }
                    continue
                }

                if let activeQuote = quote {
                    output.append(character)
                    if activeQuote == "\"" {
                        if escaped {
                            escaped = false
                        } else if character == "\\" {
                            escaped = true
                        } else if character == activeQuote {
                            quote = nil
                        }
                    } else if character == activeQuote {
                        quote = nil
                    }
                    index = nextIndex
                    continue
                }

                if let delimiter = ["\"\"\"", "'''"].first(where: remainder.hasPrefix) {
                    multilineDelimiter = delimiter
                    output.append(contentsOf: delimiter)
                    index = record.content.index(index, offsetBy: delimiter.count)
                    continue
                }
                if character == "#" {
                    containedComment = true
                    break
                }
                if character == "\"" || character == "'" { quote = character }
                output.append(character)
                index = nextIndex
            }

            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func yamlCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var quote: Character?
        var blockScalarIndent: Int?
        var pendingBlockScalar: (parentIndent: Int, explicitIndent: Int?)?
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let leadingSpaces = record.content.prefix(while: { $0 == " " }).count
            let isBlank = record.content.allSatisfy(\.isWhitespace)

            if let pending = pendingBlockScalar, !isBlank {
                let requiredIndent = pending.explicitIndent.map { pending.parentIndent + $0 } ?? leadingSpaces
                if leadingSpaces > pending.parentIndent, leadingSpaces >= requiredIndent {
                    blockScalarIndent = requiredIndent
                }
                pendingBlockScalar = nil
            }
            if let requiredIndent = blockScalarIndent {
                if isBlank || leadingSpaces >= requiredIndent {
                    contents.append(record.content)
                    commentOnly.append(false)
                    continue
                }
                blockScalarIndent = nil
            }
            if pendingBlockScalar != nil, isBlank {
                contents.append(record.content)
                commentOnly.append(false)
                continue
            }

            var output = ""
            var index = record.content.startIndex
            var escaped = false
            var containedComment = false

            while index < record.content.endIndex {
                let character = record.content[index]
                let nextIndex = record.content.index(after: index)

                if let activeQuote = quote {
                    output.append(character)
                    if activeQuote == "\"" {
                        if escaped {
                            escaped = false
                        } else if character == "\\" {
                            escaped = true
                        } else if character == activeQuote {
                            quote = nil
                        }
                    } else if character == "'" {
                        if nextIndex < record.content.endIndex, record.content[nextIndex] == "'" {
                            output.append("'")
                            index = record.content.index(after: nextIndex)
                            continue
                        }
                        quote = nil
                    }
                    index = nextIndex
                    continue
                }

                if character == "#" {
                    let isSeparated = index == record.content.startIndex ||
                        [" ", "\t"].contains(record.content[record.content.index(before: index)])
                    if isSeparated {
                        containedComment = true
                        break
                    }
                }
                if character == "\"" || character == "'" {
                    let startsScalar = index == record.content.startIndex || {
                        let previous = record.content[record.content.index(before: index)]
                        return previous == " " || previous == "\t" || "-?:,[]{}".contains(previous)
                    }()
                    if startsScalar { quote = character }
                }
                output.append(character)
                index = nextIndex
            }

            let trimmedOutput = output.drop(while: { $0 == " " || $0 == "\t" })
            let indicator = trimmedOutput.split(whereSeparator: { $0 == " " || $0 == "\t" }).last
            let indicatorPrefix = indicator.flatMap { indicator -> Substring? in
                guard let lastContent = output.lastIndex(where: { $0 != " " && $0 != "\t" }) else { return nil }
                let indicatorEnd = output.index(after: lastContent)
                guard let indicatorStart = output.index(
                    indicatorEnd,
                    offsetBy: -indicator.count,
                    limitedBy: output.startIndex
                ) else { return nil }
                return output[..<indicatorStart]
            }
            let validIndicatorPosition = indicatorPrefix.map(Self.yamlPrefixAllowsBlockScalar) == true
            if quote == nil, validIndicatorPosition, let indicator,
               let parsed = Self.yamlBlockScalarIndicator(String(indicator)) {
                pendingBlockScalar = (leadingSpaces, parsed)
            }
            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private static func yamlBlockScalarIndicator(_ token: String) -> Int?? {
        guard let first = token.first, first == "|" || first == ">" else { return nil }
        var explicitIndent: Int?
        for character in token.dropFirst() {
            if character == "+" || character == "-" { continue }
            guard let value = character.wholeNumberValue, (1...9).contains(value), explicitIndent == nil else {
                return nil
            }
            explicitIndent = value
        }
        return .some(explicitIndent)
    }

    private static func yamlPrefixAllowsBlockScalar(_ prefix: Substring) -> Bool {
        var tokens = prefix.split(whereSeparator: { $0 == " " || $0 == "\t" })
        while let token = tokens.last, token.first == "!" || token.first == "&" {
            tokens.removeLast()
        }
        guard let token = tokens.last else { return true }
        return token == "-" || token == "?" || token.last == ":"
    }

    private static func twoLookbackQuoteCloses(in text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text.index(before: index)
        guard text[previous] == "\\" else { return true }
        guard previous > text.startIndex else { return false }
        return text[text.index(before: previous)] == "\\"
    }

    private static func twoLookbackQuoteCloses(in units: [UInt16], at index: Int) -> Bool {
        index == 0 || units[index - 1] != 92 || index >= 2 && units[index - 2] == 92
    }

    private static func oneLookbackQuoteCloses(in text: String, at index: String.Index) -> Bool {
        index == text.startIndex || text[text.index(before: index)] != "\\"
    }

    private static func legacyIsAlphanumeric(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.contains { $0.value > 0x7F } ||
            character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func legacyIsAlphanumeric(_ codeUnit: UInt16) -> Bool {
        codeUnit > 0x7F || codeUnit == 0x5F ||
            UnicodeScalar(codeUnit).map(CharacterSet.alphanumerics.contains) == true
    }

    private static func legacyIsWhitespace(_ codeUnit: UInt16) -> Bool {
        codeUnit == 32 || (9...13).contains(codeUnit)
    }

    private func quotedLineCommentFilteredContents(
        in document: TextDocument,
        delimiter: Character,
        quote: Character?
    ) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var inQuote = false
            var containedComment = false
            for character in record.content {
                if let quote, character == quote {
                    inQuote.toggle()
                    output.append(character)
                } else if !inQuote, character == delimiter {
                    containedComment = true
                    break
                } else {
                    output.append(character)
                }
            }
            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func unquotedLineCommentFilteredContents(
        in document: TextDocument,
        delimiter: String
    ) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            if let range = record.content.range(of: delimiter) {
                let output = String(record.content[..<range.lowerBound])
                contents.append(output)
                commentOnly.append(Self.isWholeCommentLine(true, output: output, record: record))
            } else {
                contents.append(record.content)
                commentOnly.append(false)
            }
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func texCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var index = record.content.startIndex
            var quote: Character?
            var containedComment = false
            while index < record.content.endIndex {
                let character = record.content[index]
                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: record.content, at: index) {
                        quote = nil
                    }
                } else if character == "%" {
                    containedComment = true
                    break
                } else {
                    if character == "\"" {
                        quote = character
                    } else if character == "'" {
                        let previousIsAlphanumeric = index > record.content.startIndex &&
                            record.content[record.content.index(before: index)].isLetter ||
                            index > record.content.startIndex && record.content[record.content.index(before: index)].isNumber
                        if !previousIsAlphanumeric { quote = character }
                    }
                    output.append(character)
                }
                index = record.content.index(after: index)
            }
            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func firstNonspaceCommentFilteredContents(
        in document: TextDocument,
        delimiters: Set<Character>
    ) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let firstContent = record.content.firstIndex { $0 != " " && $0 != "\t" }
            if let firstContent, delimiters.contains(record.content[firstContent]) {
                let output = String(record.content[..<firstContent])
                contents.append(output)
                commentOnly.append(Self.isWholeCommentLine(true, output: output, record: record))
            } else {
                contents.append(record.content)
                commentOnly.append(false)
            }
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func blockCommentFilteredContents(
        in document: TextDocument,
        opener: String,
        closer: String
    ) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inComment = false
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var index = record.content.startIndex
            var containedComment = inComment
            while index < record.content.endIndex {
                let remainder = record.content[index...]
                if inComment {
                    containedComment = true
                    if remainder.hasPrefix(closer) {
                        inComment = false
                        index = record.content.index(index, offsetBy: closer.count)
                    } else {
                        index = record.content.index(after: index)
                    }
                } else if remainder.hasPrefix(opener) {
                    containedComment = true
                    inComment = true
                    index = record.content.index(index, offsetBy: opener.count)
                } else {
                    output.append(record.content[index])
                    index = record.content.index(after: index)
                }
            }
            contents.append(output)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: output, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private static func isWholeCommentLine(
        _ containedComment: Bool,
        output: String,
        record: TextDocument.Record
    ) -> Bool {
        containedComment && !record.content.isEmpty && output.isEmpty && !record.terminator.isEmpty
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
                            if let value = Self.winMergeHexByte(hex), value > 0x7F {
                                flushLiteral()
                                parts.append(.rawByte(value))
                                index = secondHexIndex
                            } else if let value = Self.winMergeHexByte(hex),
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

    private static func winMergeHexByte(_ text: String) -> UInt8? {
        let prefix = text.prefix { $0.isHexDigit }
        guard !prefix.isEmpty else { return nil }
        return UInt8(prefix, radix: 16)
    }

    private static func replaceBytes(
        in source: [UInt8],
        pattern: [UInt8],
        replacement: [UInt8],
        caseSensitive: Bool,
        maximumBytes: Int
    ) throws -> [UInt8] {
        var result = mmx_bytes_result(bytes: nil, size: 0)
        let status = source.withUnsafeBytes { sourceBuffer in
            pattern.withUnsafeBytes { patternBuffer in
                replacement.withUnsafeBytes { replacementBuffer in
                    mmx_regex_substitute(
                        sourceBuffer.baseAddress,
                        sourceBuffer.count,
                        patternBuffer.baseAddress,
                        patternBuffer.count,
                        replacementBuffer.baseAddress,
                        replacementBuffer.count,
                        caseSensitive ? 1 : 0,
                        maximumBytes,
                        &result
                    )
                }
            }
        }
        defer { mmx_bytes_result_free(&result) }
        guard status == 0 else {
            if status == 1 { throw LineDiffError.invalidRegularExpression(String(decoding: pattern, as: UTF8.self)) }
            if status == 4 { throw LineDiffError.inputTooLarge(maximumBytes: maximumBytes) }
            throw LineDiffError.substitutionEngineFailure(status)
        }
        guard result.size == 0 || result.bytes != nil else {
            throw LineDiffError.substitutionEngineFailure(3)
        }
        return Array(UnsafeBufferPointer(start: result.bytes, count: result.size))
    }

    private static func byteRecords(_ bytes: [UInt8]) -> [(content: [UInt8], terminator: [UInt8])] {
        var records: [(content: [UInt8], terminator: [UInt8])] = []
        var start = 0
        var index = 0
        while index < bytes.count {
            if bytes[index] == 13 {
                let terminatorEnd = index + 1 < bytes.count && bytes[index + 1] == 10 ? index + 2 : index + 1
                records.append((Array(bytes[start..<index]), Array(bytes[index..<terminatorEnd])))
                index = terminatorEnd
                start = index
            } else if bytes[index] == 10 {
                records.append((Array(bytes[start..<index]), [10]))
                index += 1
                start = index
            } else {
                index += 1
            }
        }
        if start < bytes.count {
            records.append((Array(bytes[start...] as ArraySlice<UInt8>), []))
        }
        return records
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
        guard let rowIndex = rows.firstIndex(where: {
            $0.left?.number == rowID.leftNumber && $0.right?.number == rowID.rightNumber
        }),
              rows[rowIndex].kind != .unchanged else {
            return nil
        }

        var left = TextDocument(text: leftText)
        var right = TextDocument(text: rightText)
        let leftEnding = left.lineEnding ?? right.lineEnding ?? "\n"
        let rightEnding = right.lineEnding ?? left.lineEnding ?? "\n"
        let sourceLine: DiffLine?
        let targetLine: DiffLine?
        let insertionIndex: Int

        switch direction {
        case .leftToRight:
            sourceLine = rows[rowIndex].left
            targetLine = rows[rowIndex].right
            insertionIndex = rows[..<rowIndex].lazy.compactMap(\.right).count
        case .rightToLeft:
            sourceLine = rows[rowIndex].right
            targetLine = rows[rowIndex].left
            insertionIndex = rows[..<rowIndex].lazy.compactMap(\.left).count
        }

        switch direction {
        case .leftToRight:
            apply(
                source: sourceLine,
                sourceDocument: left,
                target: targetLine,
                insertionIndex: insertionIndex,
                lineEnding: rightEnding,
                options: options,
                to: &right
            )
        case .rightToLeft:
            apply(
                source: sourceLine,
                sourceDocument: right,
                target: targetLine,
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

    func comparisonText(options: LineDiffOptions) -> String {
        guard options.ignoreLineEndings else { return text }
        guard !records.isEmpty else { return "" }
        var result = ""
        result.reserveCapacity(records.reduce(into: records.count) { $0 += $1.content.utf8.count })
        for record in records {
            result += record.content
            result += "\n"
        }
        return result
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
