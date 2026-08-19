import CXDiff
import Foundation

public enum DiffKind: Hashable, Sendable {
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
    case powerShell
    case python
    case sql
    case html
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
    case dlang
    case go
    case rust
    case abap
    case autoIt
    case fsharp
    case asp
    case php
    case smarty

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "c", "cc", "cpp", "cppm", "ixx", "cxx", "h", "hm", "hpp", "hxx", "inl", "rh", "tlh",
             "tli", "xs", "cs", "java", "jav", "js", "json", "rul":
            self = .cFamily
        case "pl", "pm", "plx", "po", "pot", "rb", "rbw", "rake", "gemspec", "sh", "conf", "tcl":
            self = .hashLine
        case "ps1", "psm1", "psd1":
            self = .powerShell
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
        case "d", "di":
            self = .dlang
        case "go":
            self = .go
        case "rs":
            self = .rust
        case "abap":
            self = .abap
        case "au3":
            self = .autoIt
        case "fs", "fsx":
            self = .fsharp
        case "asp", "ascx":
            self = .asp
        case "php", "php3", "php4", "php5", "phtml":
            self = .php
        case "tpl":
            self = .smarty
        case "html", "htm", "shtml", "ihtml", "ssi", "stm", "stml", "jsp":
            self = .html
        case "md", "markdown", "mdown", "mkd", "mkdn", "sgml", "xml":
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
    public var detectMovedBlocks: Bool
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
        detectMovedBlocks: Bool = false,
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
        self.detectMovedBlocks = detectMovedBlocks
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
        case detectMovedBlocks
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
        detectMovedBlocks = try container.decodeIfPresent(Bool.self, forKey: .detectMovedBlocks) ?? false
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
        try container.encode(detectMovedBlocks, forKey: .detectMovedBlocks)
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
    case lineFilterEngineFailure(Int32)
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
        case let .lineFilterEngineFailure(code):
            "WinMerge line filter engine failed with code \(code)."
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

public struct DiffLine: Hashable, Sendable {
    public let number: Int
    public let text: String

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
}

fileprivate final class DiffRowTextSource: @unchecked Sendable {
    private let bytes: [UInt8]
    private let ranges: [UInt64]

    init(text: String) {
        bytes = Array(text.utf8)
        var ranges: [UInt64] = []
        var start = 0
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == 0x0A || byte == 0x0D else {
                index += 1
                continue
            }
            ranges.append(Self.pack(start: start, end: index))
            if byte == 0x0D, index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                index += 2
            } else {
                index += 1
            }
            start = index
        }
        if start < bytes.count {
            ranges.append(Self.pack(start: start, end: bytes.count))
        }
        self.ranges = ranges
    }

    var count: Int { ranges.count }

    func content(at index: Int) -> String {
        let range = unpackedRange(at: index)
        return String(decoding: bytes[range], as: UTF8.self)
    }

    func contentUTF8Count(at index: Int) -> Int {
        unpackedRange(at: index).count
    }

    func contentUTF8(at index: Int) -> ArraySlice<UInt8> {
        bytes[unpackedRange(at: index)]
    }

    func record(at index: Int, equals other: DiffRowTextSource, at otherIndex: Int) -> Bool {
        guard ranges.indices.contains(index), other.ranges.indices.contains(otherIndex) else {
            return false
        }
        return bytes[recordRange(at: index)].elementsEqual(other.bytes[other.recordRange(at: otherIndex)])
    }

    private func recordRange(at index: Int) -> Range<Int> {
        let contentRange = unpackedRange(at: index)
        let end = index + 1 < ranges.count ? unpackedRange(at: index + 1).lowerBound : bytes.count
        return contentRange.lowerBound..<end
    }

    private func unpackedRange(at index: Int) -> Range<Int> {
        let packed = ranges[index]
        return Int(UInt32(truncatingIfNeeded: packed)) ..< Int(UInt32(truncatingIfNeeded: packed >> 32))
    }

    private static func pack(start: Int, end: Int) -> UInt64 {
        guard let start = UInt32(exactly: start), let end = UInt32(exactly: end) else {
            preconditionFailure("Diff row source exceeds comparison limits")
        }
        return UInt64(start) | (UInt64(end) << 32)
    }
}

fileprivate enum DiffRowText: Sendable {
    case missing
    case owned(String)
    case source(DiffRowTextSource)
}

fileprivate final class DiffRowTextStorage: @unchecked Sendable {
    let left: DiffRowText
    let right: DiffRowText

    init(left: DiffRowText, right: DiffRowText) {
        self.left = left
        self.right = right
    }

    var isSourceBacked: Bool {
        if case .source = left { return true }
        if case .source = right { return true }
        return false
    }

    func text(from source: DiffRowText, lineNumber: Int) -> String? {
        guard lineNumber != 0 else { return nil }
        return switch source {
        case .missing:
            nil
        case let .owned(text):
            text
        case let .source(source):
            source.content(at: lineNumber - 1)
        }
    }

    func sourceTextUTF8Count(from source: DiffRowText, lineNumber: Int) -> Int? {
        guard lineNumber != 0, case let .source(source) = source else { return nil }
        return source.contentUTF8Count(at: lineNumber - 1)
    }

    func sourceTextUTF8(from source: DiffRowText, lineNumber: Int) -> ArraySlice<UInt8>? {
        guard lineNumber != 0, case let .source(source) = source else { return nil }
        return source.contentUTF8(at: lineNumber - 1)
    }

    func sourceRecordsEqual(leftNumber: Int?, rightNumber: Int?) -> Bool {
        guard let leftNumber, let rightNumber, leftNumber > 0, rightNumber > 0,
              case .source(let leftSource) = left,
              case .source(let rightSource) = right else {
            return false
        }
        return leftSource.record(at: leftNumber - 1, equals: rightSource, at: rightNumber - 1)
    }
}

public struct DiffRow: Identifiable, Hashable, Sendable {
    private static let lineNumberBits = 30
    private static let lineNumberMask = (UInt64(1) << lineNumberBits) - 1
    private static let encodedLineNumber = Int(lineNumberMask)
    private static let sharesTextBit = UInt64(1) << 62
    private static let equalSourceRecordsBit = UInt64(1) << 63

    public struct ID: Hashable, Sendable {
        public let leftNumber: Int?
        public let rightNumber: Int?

        public init(leftNumber: Int?, rightNumber: Int?) {
            self.leftNumber = leftNumber
            self.rightNumber = rightNumber
        }
    }

    private let storage: DiffRowTextStorage
    private let metadata: UInt64

    private var storedLeftNumber: Int { Int(metadata & Self.lineNumberMask) }
    private var storedRightNumber: Int {
        Int((metadata >> Self.lineNumberBits) & Self.lineNumberMask)
    }

    public var kind: DiffKind {
        switch (metadata >> (Self.lineNumberBits * 2)) & 0b11 {
        case 0: .unchanged
        case 1: .modified
        case 2: .removed
        default: .added
        }
    }

    var sharesTextStorage: Bool { metadata & Self.sharesTextBit != 0 }
    var usesSourceTextStorage: Bool { storage.isSourceBacked }
    func sourceTextUTF8Count(onLeft: Bool) -> Int? {
        if onLeft {
            return storage.sourceTextUTF8Count(
                from: storage.left,
                lineNumber: storedLeftNumber
            )
        }
        if metadata & Self.sharesTextBit != 0 {
            return storage.sourceTextUTF8Count(
                from: storage.left,
                lineNumber: storedLeftNumber
            )
        }
        return storage.sourceTextUTF8Count(
            from: storage.right,
            lineNumber: storedRightNumber
        )
    }

    func sourceTextUTF8(onLeft: Bool) -> ArraySlice<UInt8>? {
        if onLeft {
            return storage.sourceTextUTF8(
                from: storage.left,
                lineNumber: storedLeftNumber
            )
        }
        if metadata & Self.sharesTextBit != 0 {
            return storage.sourceTextUTF8(
                from: storage.left,
                lineNumber: storedLeftNumber
            )
        }
        return storage.sourceTextUTF8(
            from: storage.right,
            lineNumber: storedRightNumber
        )
    }
    /// Whether both original line records, including their terminators, are byte-identical.
    public var hasEqualSourceRecords: Bool { metadata & Self.equalSourceRecordsBit != 0 }

    public var left: DiffLine? {
        Self.line(
            text: storage.text(from: storage.left, lineNumber: storedLeftNumber),
            storedNumber: storedLeftNumber
        )
    }

    public var right: DiffLine? {
        Self.line(
            text: metadata & Self.sharesTextBit == 0
                ? storage.text(from: storage.right, lineNumber: storedRightNumber)
                : storage.text(from: storage.left, lineNumber: storedLeftNumber),
            storedNumber: storedRightNumber
        )
    }

    public var id: ID {
        ID(
            leftNumber: Self.lineNumber(
                text: storedLeftNumber == Self.encodedLineNumber
                    ? storage.text(from: storage.left, lineNumber: storedLeftNumber)
                    : nil,
                storedNumber: storedLeftNumber
            ),
            rightNumber: Self.lineNumber(
                text: storedRightNumber == Self.encodedLineNumber
                    ? storage.text(from: storage.right, lineNumber: storedRightNumber)
                    : nil,
                storedNumber: storedRightNumber
            )
        )
    }

    public static func == (lhs: DiffRow, rhs: DiffRow) -> Bool {
        lhs.left == rhs.left &&
            lhs.right == rhs.right &&
            lhs.kind == rhs.kind &&
            lhs.hasEqualSourceRecords == rhs.hasEqualSourceRecords
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(left)
        hasher.combine(right)
        hasher.combine(kind)
        hasher.combine(hasEqualSourceRecords)
    }

    public init(left: DiffLine?, right: DiffLine?, kind: DiffKind) {
        let storedLeft = Self.store(left)
        let storedRight = Self.store(right)
        let hasEqualSourceRecords = if let left, let right {
            left.text.utf8.elementsEqual(right.text.utf8)
        } else {
            false
        }
        let sharesText = if case let .owned(leftText) = storedLeft.text,
                            case let .owned(rightText) = storedRight.text {
            storedLeft.number != Self.encodedLineNumber &&
                storedRight.number != Self.encodedLineNumber &&
                leftText.utf8.elementsEqual(rightText.utf8)
        } else {
            false
        }
        storage = DiffRowTextStorage(
            left: storedLeft.text,
            right: sharesText ? .missing : storedRight.text
        )
        metadata = Self.metadata(
            leftNumber: storedLeft.number,
            rightNumber: storedRight.number,
            kind: kind,
            sharesText: sharesText,
            hasEqualSourceRecords: hasEqualSourceRecords
        )
    }

    fileprivate init(
        leftNumber: Int?,
        rightNumber: Int?,
        storage: DiffRowTextStorage,
        kind: DiffKind,
        sharesText: Bool,
        hasEqualSourceRecords: Bool
    ) {
        self.storage = storage
        metadata = Self.metadata(
            leftNumber: leftNumber ?? 0,
            rightNumber: rightNumber ?? 0,
            kind: kind,
            sharesText: sharesText,
            hasEqualSourceRecords: hasEqualSourceRecords
        )
    }

    fileprivate static func sourceBacked(
        leftNumber: Int?,
        rightNumber: Int?,
        storage: DiffRowTextStorage,
        kind: DiffKind
    ) -> DiffRow {
        DiffRow(
            leftNumber: leftNumber,
            rightNumber: rightNumber,
            storage: storage,
            kind: kind,
            sharesText: false,
            hasEqualSourceRecords: storage.sourceRecordsEqual(
                leftNumber: leftNumber,
                rightNumber: rightNumber
            )
        )
    }

    private static func metadata(
        leftNumber: Int,
        rightNumber: Int,
        kind: DiffKind,
        sharesText: Bool,
        hasEqualSourceRecords: Bool
    ) -> UInt64 {
        let kindValue: UInt64 = switch kind {
        case .unchanged: 0
        case .modified: 1
        case .removed: 2
        case .added: 3
        }
        return UInt64(leftNumber) |
            (UInt64(rightNumber) << Self.lineNumberBits) |
            (kindValue << (Self.lineNumberBits * 2)) |
            (sharesText ? Self.sharesTextBit : 0) |
            (hasEqualSourceRecords ? Self.equalSourceRecordsBit : 0)
    }

    private static func store(_ line: DiffLine?) -> (text: DiffRowText, number: Int) {
        guard let line else { return (.missing, 0) }
        if (1..<encodedLineNumber).contains(line.number) {
            return (.owned(line.text), line.number)
        }
        return (.owned("\(line.number)\0\(line.text)"), encodedLineNumber)
    }

    private static func line(text: String?, storedNumber: Int) -> DiffLine? {
        guard storedNumber != 0, let text else { return nil }
        guard storedNumber == encodedLineNumber else {
            return DiffLine(number: storedNumber, text: text)
        }
        guard let separator = text.firstIndex(of: "\0"),
              let number = Int(text[..<separator]) else {
            preconditionFailure("Invalid encoded line number")
        }
        return DiffLine(number: number, text: String(text[text.index(after: separator)...]))
    }

    private static func lineNumber(text: String?, storedNumber: Int) -> Int? {
        guard storedNumber != 0 else { return nil }
        guard storedNumber == encodedLineNumber else { return storedNumber }
        guard let text,
              let separator = text.firstIndex(of: "\0"),
              let number = Int(text[..<separator]) else {
            preconditionFailure("Invalid encoded line number")
        }
        return number
    }
}

public struct MovedLinePair: Equatable, Sendable {
    public let leftLine: Int
    public let rightLine: Int
}

public struct MovedLines: Equatable, Sendable {
    private let leftToRight: [UInt64]
    private let rightToLeft: [UInt64]

    public init() {
        leftToRight = []
        rightToLeft = []
    }

    fileprivate init(leftToRight: [UInt64], rightToLeft: [UInt64]) {
        self.leftToRight = leftToRight
        self.rightToLeft = rightToLeft
    }

    public var isEmpty: Bool { leftToRight.isEmpty && rightToLeft.isEmpty }
    public var leftToRightCount: Int { leftToRight.count }
    public var rightToLeftCount: Int { rightToLeft.count }
    public var shallowStorageBytes: Int {
        (leftToRight.count + rightToLeft.count) * MemoryLayout<UInt64>.stride
    }

    public func rightLine(forLeftLine line: Int) -> Int? {
        partner(for: line, in: leftToRight)
    }

    public func leftLine(forRightLine line: Int) -> Int? {
        partner(for: line, in: rightToLeft)
    }

    public func leftToRightPair(at index: Int) -> MovedLinePair {
        pair(leftToRight[index], sourceIsLeft: true)
    }

    public func rightToLeftPair(at index: Int) -> MovedLinePair {
        pair(rightToLeft[index], sourceIsLeft: false)
    }

    private func partner(for line: Int, in entries: [UInt64]) -> Int? {
        guard let source = UInt32(exactly: line), source != 0 else { return nil }
        var lower = entries.startIndex
        var upper = entries.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let storedSource = UInt32(entries[middle] >> 32)
            if storedSource < source {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < entries.endIndex, UInt32(entries[lower] >> 32) == source else {
            return nil
        }
        return Int(UInt32(truncatingIfNeeded: entries[lower]))
    }

    private func pair(_ entry: UInt64, sourceIsLeft: Bool) -> MovedLinePair {
        let source = Int(UInt32(entry >> 32))
        let target = Int(UInt32(truncatingIfNeeded: entry))
        return sourceIsLeft
            ? MovedLinePair(leftLine: source, rightLine: target)
            : MovedLinePair(leftLine: target, rightLine: source)
    }
}

public struct LineDiffResult: Equatable, Sendable {
    public let rows: [DiffRow]
    public let movedLines: MovedLines
    public let movedLineAnalysisStatus: MovedLineAnalysisStatus
}

public enum MovedLineAnalysisStatus: Equatable, Sendable {
    case notRequested
    case available
    case unavailableWithinResourceLimits
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
    static let transformedMoveAnalysisMaximumBytesPerFile = 8 * 1024 * 1024
    static let transformedMoveAnalysisMaximumLinesPerFile = 64 * 1024

    public static func compare(
        left leftText: String,
        right rightText: String,
        options: LineDiffOptions = LineDiffOptions()
    ) throws -> [DiffRow] {
        var rowOptions = options
        rowOptions.detectMovedBlocks = false
        return try compareResult(left: leftText, right: rightText, options: rowOptions).rows
    }

    public static func compareResult(
        left leftText: String,
        right rightText: String,
        options: LineDiffOptions = LineDiffOptions()
    ) throws -> LineDiffResult {
        try validateInput(leftText)
        try validateInput(rightText)
        let leftDocument = TextDocument(text: leftText)
        let rightDocument = TextDocument(text: rightText)
        let rowStorage = DiffRowTextStorage(
            left: .source(DiffRowTextSource(text: leftText)),
            right: .source(DiffRowTextSource(text: rightText))
        )
        let transform = try ComparisonTransform(options: options)
        let commentFiltered = transform.commentFilteredPair(left: leftDocument, right: rightDocument)
        let native = try nativeComparison(
            left: leftDocument.comparisonText(options: options),
            right: rightDocument.comparisonText(options: options),
            options: options,
            detectMoves: options.detectMovedBlocks && !transform.isActive
        )
        let movedLines: MovedLines
        let movedLineAnalysisStatus: MovedLineAnalysisStatus
        if options.detectMovedBlocks && transform.isActive {
            if transformedMoveAnalysisIsWithinBudget(
                leftByteCount: leftText.utf8.count,
                rightByteCount: rightText.utf8.count,
                leftLineCount: leftDocument.records.count,
                rightLineCount: rightDocument.records.count
            ) {
                do {
                    let prepared = try transform.prepare(
                        left: leftDocument,
                        right: rightDocument,
                        options: options,
                        leftComments: commentFiltered?.left,
                        rightComments: commentFiltered?.right,
                        maximumBytes: transformedMoveAnalysisMaximumBytesPerFile
                    )
                    movedLines = try nativeComparison(
                        left: prepared.left.bytes,
                        right: prepared.right.bytes,
                        options: options,
                        detectMoves: true
                    ).movedLines
                    movedLineAnalysisStatus = .available
                } catch LineDiffError.inputTooLarge(maximumBytes: _) {
                    movedLines = MovedLines()
                    movedLineAnalysisStatus = .unavailableWithinResourceLimits
                }
            } else {
                movedLines = MovedLines()
                movedLineAnalysisStatus = .unavailableWithinResourceLimits
            }
        } else {
            movedLines = native.movedLines
            movedLineAnalysisStatus = options.detectMovedBlocks ? .available : .notRequested
        }
        var rows: [DiffRow] = []
        var leftIndex = 0
        var rightIndex = 0

        for hunk in native.hunks {
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
                    leftIndex: leftIndex,
                    rightIndex: rightIndex,
                    storage: rowStorage,
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
                    rowStorage: rowStorage,
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
                    rowStorage: rowStorage,
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
                leftIndex: leftIndex,
                rightIndex: rightIndex,
                storage: rowStorage,
                kind: .unchanged
            ))
            leftIndex += 1
            rightIndex += 1
        }

        return LineDiffResult(
            rows: rows,
            movedLines: movedLines,
            movedLineAnalysisStatus: movedLineAnalysisStatus
        )
    }

    static func transformedMoveAnalysisIsWithinBudget(
        leftByteCount: Int,
        rightByteCount: Int,
        leftLineCount: Int,
        rightLineCount: Int
    ) -> Bool {
        leftByteCount <= transformedMoveAnalysisMaximumBytesPerFile &&
            rightByteCount <= transformedMoveAnalysisMaximumBytesPerFile &&
            leftLineCount <= transformedMoveAnalysisMaximumLinesPerFile &&
            rightLineCount <= transformedMoveAnalysisMaximumLinesPerFile
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

    private static func row(
        leftIndex: Int?,
        rightIndex: Int?,
        storage: DiffRowTextStorage,
        kind: DiffKind,
        leftNumberOffset: Int = 0,
        rightNumberOffset: Int = 0
    ) -> DiffRow {
        DiffRow.sourceBacked(
            leftNumber: leftIndex.map { leftNumberOffset + $0 + 1 },
            rightNumber: rightIndex.map { rightNumberOffset + $0 + 1 },
            storage: storage,
            kind: kind
        )
    }

    private static func appendChangedRows(
        to rows: inout [DiffRow],
        hunk: NativeHunk,
        left: TextDocument,
        right: TextDocument,
        rowStorage: DiffRowTextStorage,
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
                rows.append(row(
                    leftIndex: hasLeft ? leftIndex : nil,
                    rightIndex: hasRight ? rightIndex : nil,
                    storage: rowStorage,
                    kind: .unchanged,
                    leftNumberOffset: leftNumberOffset,
                    rightNumberOffset: rightNumberOffset
                ))
                if hasLeft { leftIndex += 1 }
                if hasRight { rightIndex += 1 }
            } else if leftIsFiltered && leftEnd - leftIndex > rightEnd - rightIndex {
                rows.append(row(
                    leftIndex: leftIndex,
                    rightIndex: nil,
                    storage: rowStorage,
                    kind: .unchanged,
                    leftNumberOffset: leftNumberOffset
                ))
                leftIndex += 1
            } else if rightIsFiltered && rightEnd - rightIndex > leftEnd - leftIndex {
                rows.append(row(
                    leftIndex: nil,
                    rightIndex: rightIndex,
                    storage: rowStorage,
                    kind: .unchanged,
                    rightNumberOffset: rightNumberOffset
                ))
                rightIndex += 1
            } else if hasLeft && hasRight {
                rows.append(row(
                    leftIndex: leftIndex,
                    rightIndex: rightIndex,
                    storage: rowStorage,
                    kind: .modified,
                    leftNumberOffset: leftNumberOffset,
                    rightNumberOffset: rightNumberOffset
                ))
                leftIndex += 1
                rightIndex += 1
            } else if hasLeft {
                rows.append(row(
                    leftIndex: leftIndex,
                    rightIndex: nil,
                    storage: rowStorage,
                    kind: .removed,
                    leftNumberOffset: leftNumberOffset
                ))
                leftIndex += 1
            } else {
                rows.append(row(
                    leftIndex: nil,
                    rightIndex: rightIndex,
                    storage: rowStorage,
                    kind: .added,
                    rightNumberOffset: rightNumberOffset
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
        rowStorage: DiffRowTextStorage,
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
                    leftIndex: localLeftIndex,
                    rightIndex: localRightIndex,
                    storage: rowStorage,
                    kind: .unchanged,
                    leftNumberOffset: hunk.leftStart,
                    rightNumberOffset: hunk.rightStart
                ))
                localLeftIndex += 1
                localRightIndex += 1
            }
            appendChangedRows(
                to: &rows,
                hunk: secondary,
                left: leftSlice,
                right: rightSlice,
                rowStorage: rowStorage,
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
                leftIndex: localLeftIndex,
                rightIndex: localRightIndex,
                storage: rowStorage,
                kind: .unchanged,
                leftNumberOffset: hunk.leftStart,
                rightNumberOffset: hunk.rightStart
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
        try nativeComparison(
            left: Array(left.utf8),
            right: Array(right.utf8),
            options: options,
            detectMoves: false
        ).hunks
    }

    private static func nativeHunks(
        left leftBytes: [UInt8],
        right rightBytes: [UInt8],
        options: LineDiffOptions
    ) throws -> [NativeHunk] {
        try nativeComparison(
            left: leftBytes,
            right: rightBytes,
            options: options,
            detectMoves: false
        ).hunks
    }

    private static func nativeComparison(
        left: String,
        right: String,
        options: LineDiffOptions,
        detectMoves: Bool
    ) throws -> NativeComparison {
        try nativeComparison(
            left: Array(left.utf8),
            right: Array(right.utf8),
            options: options,
            detectMoves: detectMoves
        )
    }

    private static func nativeComparison(
        left leftBytes: [UInt8],
        right rightBytes: [UInt8],
        options: LineDiffOptions,
        detectMoves: Bool
    ) throws -> NativeComparison {
        let maximumBytes = Int(MMX_MAX_INPUT_SIZE)
        guard leftBytes.count <= maximumBytes, rightBytes.count <= maximumBytes else {
            throw LineDiffError.inputTooLarge(maximumBytes: maximumBytes)
        }
        var result = mmx_diff_result(hunks: nil, count: 0)
        var moved = mmx_moved_result(
            left_to_right: nil,
            left_to_right_count: 0,
            right_to_left: nil,
            right_to_left_count: 0
        )
        let status = leftBytes.withUnsafeBytes { leftBuffer in
            rightBytes.withUnsafeBytes { rightBuffer in
                if detectMoves {
                    mmx_diff_with_moves(
                        leftBuffer.baseAddress,
                        leftBuffer.count,
                        rightBuffer.baseAddress,
                        rightBuffer.count,
                        options.nativeFlags,
                        &result,
                        &moved
                    )
                } else {
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
        }
        defer { mmx_diff_result_free(&result) }
        defer { mmx_moved_result_free(&moved) }

        guard status == 0 else {
            throw LineDiffError.nativeEngineFailure(status)
        }
        guard (result.count == 0 || result.hunks != nil),
              (moved.left_to_right_count == 0 || moved.left_to_right != nil),
              (moved.right_to_left_count == 0 || moved.right_to_left != nil) else {
            throw LineDiffError.invalidNativeResult
        }

        let native = UnsafeBufferPointer(start: result.hunks, count: result.count)
        let hunks = try native.map { hunk in
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
        return NativeComparison(
            hunks: hunks,
            movedLines: try movedLines(from: moved)
        )
    }

    private static func movedLines(from result: mmx_moved_result) throws -> MovedLines {
        func entries(
            _ pointer: UnsafeMutablePointer<mmx_moved_line>?,
            count: Int,
            sourceIsLeft: Bool
        ) throws -> [UInt64] {
            let native = UnsafeBufferPointer(start: pointer, count: count)
            return try native.map { pair in
                guard pair.left_line >= 0, pair.right_line >= 0 else {
                    throw LineDiffError.invalidNativeResult
                }
                let left = UInt32(pair.left_line) + 1
                let right = UInt32(pair.right_line) + 1
                let source = sourceIsLeft ? left : right
                let target = sourceIsLeft ? right : left
                return UInt64(source) << 32 | UInt64(target)
            }
        }
        return try MovedLines(
            leftToRight: entries(
                result.left_to_right,
                count: result.left_to_right_count,
                sourceIsLeft: true
            ),
            rightToLeft: entries(
                result.right_to_left,
                count: result.right_to_left_count,
                sourceIsLeft: false
            )
        )
    }
}

private struct NativeComparison {
    let hunks: [NativeHunk]
    let movedLines: MovedLines
}

private struct NativeHunk {
    let leftStart: Int
    let leftCount: Int
    let rightStart: Int
    let rightCount: Int
    let isTrivial: Bool
}

private final class CompiledLineFilter {
    private let handle: UnsafeMutableRawPointer

    init(pattern: String, caseSensitive: Bool) throws {
        let patternBytes = Array(pattern.utf8)
        var nativeFilter: UnsafeMutableRawPointer?
        let status = patternBytes.withUnsafeBytes { patternBuffer in
            mmx_line_filter_create(
                patternBuffer.baseAddress,
                patternBuffer.count,
                caseSensitive ? 1 : 0,
                &nativeFilter
            )
        }
        guard status == 0, let nativeFilter else {
            if status == 1 {
                throw LineDiffError.invalidRegularExpression(pattern)
            }
            throw LineDiffError.lineFilterEngineFailure(status)
        }
        handle = nativeFilter
    }

    deinit {
        mmx_line_filter_free(handle)
    }

    func matches(_ subject: String) throws -> Bool {
        var matched: Int32 = 0
        let status = withUTF8Bytes(of: subject) { subjectBuffer in
            mmx_line_filter_matches(
                handle,
                subjectBuffer.baseAddress,
                subjectBuffer.count,
                &matched
            )
        }
        guard status == 0 else {
            throw LineDiffError.lineFilterEngineFailure(status)
        }
        return matched != 0
    }
}

private func withUTF8Bytes<Result>(
    of string: String,
    _ body: (UnsafeRawBufferPointer) -> Result
) -> Result {
    if let result = string.utf8.withContiguousStorageIfAvailable({ buffer in
        body(UnsafeRawBufferPointer(buffer))
    }) {
        return result
    }
    return Array(string.utf8).withUnsafeBytes(body)
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

private enum DBlockCommentMode {
    case slashStar
    case slashPlus
}

private enum DStringMode {
    case escaped
    case rawQuote(delimiter: UInt16)
    case backtick
    case braceToken
}

private enum EmbeddedHTMLLanguage {
    case javascript
    case asp
    case php
    case smarty
}

private enum EmbeddedHTMLMode {
    case html
    case embedded
    case script
    case style
}

private enum EmbeddedCommentKind {
    case html
    case cBlock
    case smarty
}

private enum EmbeddedQuoteContext {
    case html
    case script
    case style
    case php
    case smarty
    case asp
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
        let lineFilter: CompiledLineFilter?
        let replacement: [ReplacementPart]?

        var replacementBytes: [UInt8] { replacement?.flatMap(\.bytes) ?? [] }
    }

    private let lineFilters: [CompiledRule]
    private let substitutions: [CompiledRule]
    private let commentSyntax: CommentSyntax?
    private let ignoresBlankLines: Bool
    private var prefixesContent: Bool {
        commentSyntax != nil || !lineFilters.isEmpty || !substitutions.isEmpty
    }

    var isActive: Bool {
        ignoresBlankLines || commentSyntax != nil || !lineFilters.isEmpty || !substitutions.isEmpty
    }

    init(options: LineDiffOptions) throws {
        lineFilters = try (options.lineFiltersEnabled ? options.lineFilters : []).map {
            return CompiledRule(
                pattern: $0.pattern,
                caseSensitive: $0.caseSensitive,
                lineFilter: try CompiledLineFilter(
                    pattern: $0.pattern,
                    caseSensitive: $0.caseSensitive
                ),
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
                lineFilter: nil,
                replacement: try Self.parseReplacement($0.replacement)
            )
        }
        commentSyntax = options.ignoreComments ? options.commentSyntax : nil
        ignoresBlankLines = options.ignoreBlankLines
    }

    func prepare(
        left: TextDocument,
        right: TextDocument,
        options: LineDiffOptions,
        leftComments: CommentFilteredContents? = nil,
        rightComments: CommentFilteredContents? = nil,
        maximumBytes: Int? = nil
    ) throws -> PreparedComparisonPair {
        let marker = collisionFreeMarker(left: left.text, right: right.text)
        return try PreparedComparisonPair(
            left: prepare(
                document: left,
                marker: marker,
                options: options,
                commentFiltered: leftComments,
                maximumBytes: maximumBytes
            ),
            right: prepare(
                document: right,
                marker: marker,
                options: options,
                commentFiltered: rightComments,
                maximumBytes: maximumBytes
            )
        )
    }

    private func prepare(
        document: TextDocument,
        marker: String,
        options: LineDiffOptions,
        commentFiltered: CommentFilteredContents?,
        maximumBytes: Int?
    ) throws -> PreparedComparison {
        var contents: [String] = []
        var filteredLines: [Bool] = []
        let replacementMaximumBytes = maximumBytes ?? Int(MMX_MAX_INPUT_SIZE)
        let commentFiltered = commentFiltered ?? commentFilteredContents(in: document)
        contents.reserveCapacity(document.records.count)
        filteredLines.reserveCapacity(document.records.count)

        for (index, record) in document.records.enumerated() {
            let content = commentFiltered?.contents[index] ?? record.content
            var isFiltered = commentFiltered?.commentOnly[index] == true
            if !isFiltered {
                for rule in lineFilters {
                    try Task.checkCancellation()
                    if try rule.lineFilter?.matches(content) == true {
                        isFiltered = true
                        break
                    }
                }
            }
            contents.append(isFiltered ? marker : content)
            filteredLines.append(isFiltered)
        }

        var transformedBytes: [UInt8]
        if let maximumBytes {
            transformedBytes = []
            transformedBytes.reserveCapacity(min(maximumBytes, document.text.utf8.count))
            for (content, record) in zip(contents, document.records) {
                let addedByteCount = content.utf8.count + record.terminator.utf8.count
                guard addedByteCount <= maximumBytes - transformedBytes.count else {
                    throw LineDiffError.inputTooLarge(maximumBytes: maximumBytes)
                }
                transformedBytes.append(contentsOf: content.utf8)
                transformedBytes.append(contentsOf: record.terminator.utf8)
            }
        } else {
            let transformedText = zip(contents, document.records)
                .map { $0 + $1.terminator }
                .joined()
            transformedBytes = Array(transformedText.utf8)
        }
        for substitution in substitutions {
            transformedBytes = try Self.replaceBytes(
                in: transformedBytes,
                pattern: Array(substitution.pattern.utf8),
                replacement: substitution.replacementBytes,
                caseSensitive: substitution.caseSensitive,
                maximumBytes: replacementMaximumBytes
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
        let comparisonCapacity = transformedBytes.count + transformedRecords.count * 2
        comparisonBytes.reserveCapacity(maximumBytes.map { min($0, comparisonCapacity) } ?? comparisonCapacity)
        let markerBytes = Array(marker.utf8)
        for (index, record) in transformedRecords.enumerated() {
            let (content, terminator) = record
            let isFiltered = filteredLines[index]
            let comparisonTerminator = options.ignoreLineEndings ? [10] : terminator
            if isFiltered {
                let addedByteCount = markerBytes.count + comparisonTerminator.count
                if let maximumBytes,
                   addedByteCount > maximumBytes - comparisonBytes.count {
                    throw LineDiffError.inputTooLarge(maximumBytes: maximumBytes)
                }
                comparisonBytes.append(contentsOf: markerBytes)
                comparisonBytes.append(contentsOf: comparisonTerminator)
                continue
            }
            let preservesBlankLine = options.ignoreBlankLines &&
                content.allSatisfy { $0 == 32 || (9...13).contains($0) }
            if preservesBlankLine { filteredLines[index] = true }
            let prefixByteCount = !preservesBlankLine && prefixesContent ? 2 : 0
            let addedByteCount = prefixByteCount + content.count + comparisonTerminator.count
            if let maximumBytes,
               addedByteCount > maximumBytes - comparisonBytes.count {
                throw LineDiffError.inputTooLarge(maximumBytes: maximumBytes)
            }
            if prefixByteCount != 0 { comparisonBytes.append(contentsOf: [85, 58]) }
            comparisonBytes.append(contentsOf: content)
            comparisonBytes.append(contentsOf: comparisonTerminator)
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
        case .dlang:
            return dCommentFilteredContents(in: document)
        case .go:
            return goCommentFilteredContents(in: document)
        case .rust:
            return rustCommentFilteredContents(in: document)
        case .abap:
            return abapCommentFilteredContents(in: document)
        case .autoIt:
            return autoItCommentFilteredContents(in: document)
        case .fsharp:
            return fsharpCommentFilteredContents(in: document)
        case .html:
            return embeddedHTMLCommentFilteredContents(in: document, language: .javascript)
        case .asp:
            return embeddedHTMLCommentFilteredContents(in: document, language: .asp)
        case .php:
            return embeddedHTMLCommentFilteredContents(in: document, language: .php)
        case .smarty:
            return embeddedHTMLCommentFilteredContents(in: document, language: .smarty)
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
        let carriesEscapedState: Bool
        switch commentSyntax {
        case .hashLine:
            lineDelimiters = ["#"]
            blockDelimiter = nil
            supportsTripleQuotedStrings = false
            carriesEscapedState = true
        case .powerShell:
            lineDelimiters = ["#"]
            blockDelimiter = nil
            supportsTripleQuotedStrings = false
            carriesEscapedState = false
        case .python:
            lineDelimiters = ["#"]
            blockDelimiter = nil
            supportsTripleQuotedStrings = true
            carriesEscapedState = true
        case .sql:
            lineDelimiters = ["//", "--"]
            blockDelimiter = ("/*", "*/")
            supportsTripleQuotedStrings = false
            carriesEscapedState = true
        case .markup:
            lineDelimiters = []
            blockDelimiter = ("<!--", "-->")
            supportsTripleQuotedStrings = false
            carriesEscapedState = false
        case .cFamily, .matlab, .properties, .toml, .yaml, .basic, .css, .ini, .tex, .adaVhdl,
             .dcl, .rexx, .lispSiod, .fortran, .nsis, .resources, .verilog, .batch, .pascal,
             .lua, .innoSetup, .dlang, .go, .rust, .abap, .autoIt, .fsharp, .html, .asp, .php,
             .smarty:
            preconditionFailure("Dedicated comment scanner was not selected")
        }
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inBlockComment = false
        var inLineComment = false
        var inMarkupElement = false
        var inPowerShellVariable = false
        var quote: Character?
        var tripleQuote: String?
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            var output = ""
            var index = record.content.startIndex
            var containedComment = inBlockComment || inLineComment

            if inLineComment {
                index = record.content.endIndex
            }

            while index < record.content.endIndex {
                let character = record.content[index]
                let nextIndex = record.content.index(after: index)
                let remainder = record.content[index...]

                if character == "\0" {
                    if !inBlockComment { output.append(contentsOf: remainder) }
                    break
                }

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

                if inPowerShellVariable {
                    output.append(character)
                    if !Self.legacyIsAlphanumeric(character) { inPowerShellVariable = false }
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
                    inLineComment = true
                    break
                }
                if commentSyntax == .powerShell, character == "$" {
                    inPowerShellVariable = true
                    output.append(character)
                    index = nextIndex
                    continue
                }
                if commentSyntax == .markup, character == "<" {
                    inMarkupElement = true
                } else if commentSyntax == .markup, character == ">" {
                    inMarkupElement = false
                }
                if (commentSyntax != .markup || inMarkupElement),
                   character == "\"" || character == "'" && (
                    index == record.content.startIndex ||
                    !Self.legacyIsAlphanumeric(record.content[record.content.index(before: index)])
                   ) {
                    quote = character
                }
                output.append(character)
                index = nextIndex
            }

            if tripleQuote == nil {
                if commentSyntax == .markup {
                    if quote != "\"" { quote = nil }
                } else if !carriesEscapedState || record.content.last != "\\" {
                    quote = nil
                }
            }
            if !carriesEscapedState || record.content.last != "\\" {
                inLineComment = false
            }
            inPowerShellVariable = false

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

    private func goCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inBlockComment = false
        var inRawString = false
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var quote: UInt16?
            var containedComment = inBlockComment

            while index < units.count {
                let character = units[index]
                if character == 0 {
                    if !inBlockComment { output.append(contentsOf: units[index...]) }
                    break
                }
                if inBlockComment {
                    containedComment = true
                    if index + 1 < units.count, character == 42, units[index + 1] == 47 {
                        inBlockComment = false
                        index += 2
                    } else {
                        index += 1
                    }
                    continue
                }
                if inRawString {
                    output.append(character)
                    if character == 96 { inRawString = false }
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
                if index + 1 < units.count, character == 47, units[index + 1] == 47 {
                    containedComment = true
                    break
                }
                if index + 1 < units.count, character == 47, units[index + 1] == 42 {
                    containedComment = true
                    inBlockComment = true
                    index += 2
                    continue
                }
                if character == 96 {
                    inRawString = true
                } else if character == 34 || character == 39 &&
                          (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                    quote = character
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

    private func rustCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var blockDepth: Int?
        var inString = false
        var rawHashCount: Int?
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var rawPayloadStart: Int? = rawHashCount == nil ? nil : -1
            var containedComment = blockDepth != nil

            while index < units.count {
                let character = units[index]
                if character == 0 {
                    if blockDepth == nil { output.append(contentsOf: units[index...]) }
                    break
                }
                if let depth = blockDepth {
                    containedComment = true
                    if index + 1 < units.count, character == 47, units[index + 1] == 42 {
                        blockDepth = (depth + 1) & 0xF
                        index += 2
                    } else if index + 1 < units.count, character == 42, units[index + 1] == 47 {
                        blockDepth = depth == 0 ? nil : depth - 1
                        index += 2
                    } else {
                        index += 1
                    }
                    continue
                }
                if inString {
                    output.append(character)
                    if character == 34, Self.twoLookbackQuoteCloses(in: units, at: index) { inString = false }
                    index += 1
                    continue
                }
                if let hashCount = rawHashCount {
                    output.append(character)
                    if character == 34, index > (rawPayloadStart ?? index),
                       index + hashCount < units.count,
                       units[index..<(index + hashCount + 1)].dropFirst().allSatisfy({ $0 == 35 }) {
                        if hashCount > 0 { output.append(contentsOf: units[(index + 1)...(index + hashCount)]) }
                        rawHashCount = nil
                        rawPayloadStart = nil
                        index += hashCount + 1
                    } else {
                        index += 1
                    }
                    continue
                }
                if index + 1 < units.count, character == 47, units[index + 1] == 47 {
                    containedComment = true
                    break
                }
                if index + 1 < units.count, character == 47, units[index + 1] == 42 {
                    containedComment = true
                    blockDepth = 0
                    index += 2
                    continue
                }
                if let raw = Self.rustRawStringOpener(in: units, at: index) {
                    rawHashCount = raw.hashCount & 0xF
                    rawPayloadStart = raw.end
                    output.append(contentsOf: units[index..<raw.end])
                    index = raw.end
                    continue
                }
                if character == 34 { inString = true }
                output.append(character)
                index += 1
            }

            let outputText = String(decoding: output, as: UTF16.self)
            contents.append(outputText)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: outputText, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func dCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var blockMode: DBlockCommentMode?
        var stringMode: DStringMode?
        var sharedCookieByte = 0
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var characterQuote = false
            var containedComment = blockMode != nil

            while index < units.count {
                let character = units[index]
                if character == 0 {
                    if blockMode == nil { output.append(contentsOf: units[index...]) }
                    break
                }
                if let mode = blockMode {
                    containedComment = true
                    let depth = sharedCookieByte & 0xF
                    switch mode {
                    case .slashStar:
                        if depth == 0 {
                            if index + 1 < units.count, character == 42, units[index + 1] == 47 {
                                blockMode = nil
                                index += 2
                            } else {
                                index += 1
                            }
                        } else if index + 1 < units.count, character == 47, units[index + 1] == 43 {
                            sharedCookieByte = (sharedCookieByte & 0xF0) | ((depth + 1) & 0xF)
                            index += 2
                        } else if index + 1 < units.count, character == 43, units[index + 1] == 47 {
                            if depth <= 1 { blockMode = nil }
                            sharedCookieByte = (sharedCookieByte & 0xF0) | ((depth - 1) & 0xF)
                            index += 2
                        } else {
                            index += 1
                        }
                    case .slashPlus:
                        if depth == 0 {
                            if index + 1 < units.count, character == 42, units[index + 1] == 47 {
                                blockMode = nil
                                index += 2
                            } else {
                                index += 1
                            }
                        } else if index + 1 < units.count, character == 47, units[index + 1] == 43 {
                            sharedCookieByte = (sharedCookieByte & 0xF0) | ((depth + 1) & 0xF)
                            index += 2
                        } else if index + 1 < units.count, character == 43, units[index + 1] == 47 {
                            if depth <= 1 { blockMode = nil }
                            sharedCookieByte = (sharedCookieByte & 0xF0) | ((depth - 1) & 0xF)
                            index += 2
                        } else {
                            index += 1
                        }
                    }
                    continue
                }
                if let mode = stringMode {
                    output.append(character)
                    switch mode {
                    case .escaped:
                        if character == 34, Self.fullBackslashParityQuoteCloses(in: units, at: index) {
                            stringMode = nil
                        }
                        index += 1
                    case .rawQuote(let delimiter):
                        if character == 34, delimiter == 0 || index > 0 && units[index - 1] == delimiter {
                            stringMode = nil
                        }
                        index += 1
                    case .backtick:
                        if sharedCookieByte >> 4 == 0, character == 96 { stringMode = nil }
                        index += 1
                    case .braceToken:
                        let depth = sharedCookieByte >> 4
                        if character == 123 {
                            sharedCookieByte = (sharedCookieByte & 0x0F) | (((depth + 1) & 0xF) << 4)
                        } else if character == 125 {
                            if depth <= 1 { stringMode = nil }
                            sharedCookieByte = (sharedCookieByte & 0x0F) | (((depth - 1) & 0xF) << 4)
                        }
                        index += 1
                    }
                    continue
                }
                if characterQuote {
                    output.append(character)
                    if character == 39, Self.twoLookbackQuoteCloses(in: units, at: index) { characterQuote = false }
                    index += 1
                    continue
                }
                if index + 1 < units.count, character == 47, units[index + 1] == 47 {
                    containedComment = true
                    break
                }
                if index + 1 < units.count, character == 47, units[index + 1] == 42 {
                    containedComment = true
                    blockMode = .slashStar
                    index += 2
                    continue
                }
                if index + 1 < units.count, character == 47, units[index + 1] == 43 {
                    containedComment = true
                    blockMode = .slashPlus
                    sharedCookieByte = (sharedCookieByte & 0xF0) | 1
                    index += 2
                    continue
                }
                if index + 1 < units.count, character == 113, units[index + 1] == 123 {
                    stringMode = .braceToken
                    sharedCookieByte = (sharedCookieByte & 0x0F) | 0x10
                    output.append(contentsOf: units[index...index + 1])
                    index += 2
                    continue
                }
                if character == 96 {
                    stringMode = sharedCookieByte >> 4 == 0 ? .backtick : .braceToken
                } else if character == 34 {
                    if index > 0, units[index - 1] == 114 {
                        stringMode = .rawQuote(delimiter: 0)
                    } else if index > 0, units[index - 1] == 113 {
                        let delimiter = index + 1 < units.count ? Self.dClosingDelimiter(units[index + 1]) : 0
                        sharedCookieByte = Int(delimiter & 0xFF)
                        stringMode = .rawQuote(delimiter: delimiter)
                    } else {
                        stringMode = .escaped
                    }
                } else if character == 39, index == 0 || !Self.legacyIsAlphanumeric(units[index - 1]) {
                    characterQuote = true
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

    private static func rustRawStringOpener(
        in units: [UInt16],
        at index: Int
    ) -> (hashCount: Int, end: Int)? {
        let prefix: Int
        if units[index] == 114 {
            prefix = 1
        } else if units[index] == 98, index + 1 < units.count, units[index + 1] == 114 {
            prefix = 2
        } else {
            return nil
        }
        var cursor = index + prefix
        var hashCount = 0
        while cursor < units.count, units[cursor] == 35 {
            hashCount += 1
            cursor += 1
        }
        guard cursor < units.count, units[cursor] == 34 else { return nil }
        return (hashCount, cursor + 1)
    }

    private static func fullBackslashParityQuoteCloses(in units: [UInt16], at index: Int) -> Bool {
        var cursor = index
        var count = 0
        while cursor > 0, units[cursor - 1] == 92 {
            count += 1
            cursor -= 1
        }
        return count.isMultiple(of: 2)
    }

    private static func dClosingDelimiter(_ delimiter: UInt16) -> UInt16 {
        switch delimiter {
        case 40: 41
        case 91: 93
        case 123: 125
        case 60: 62
        default: delimiter
        }
    }

    private func abapCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var lineComment = false
        var inString = false
        var inSection = false
        var inVariable = false
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var containedComment = lineComment

            if units.isEmpty {
                lineComment = false
                inString = false
                inSection = false
                inVariable = false
            } else if lineComment { index = units.count }
            while index < units.count {
                let character = units[index]
                if character == 0 {
                    output.append(contentsOf: units[index...])
                    break
                }
                if inString {
                    output.append(character)
                    if character == 39, !inSection { inString = false }
                    if character == 123 {
                        inString = false
                        inVariable = true
                    }
                    index += 1
                    continue
                }
                if index == 0, character == 42 {
                    containedComment = true
                    lineComment = true
                    break
                }
                if index > 0, units[index - 1] == 34 || character == 35 && units[index - 1] == 35 {
                    containedComment = true
                    lineComment = true
                    if !output.isEmpty { output.removeLast() }
                    break
                }
                if character == 39 || character == 124 {
                    inString = true
                    if character == 124 { inSection.toggle() }
                    output.append(character)
                    index += 1
                    continue
                }
                if inVariable, index > 0, units[index - 1] == 125 {
                    inString = true
                    inVariable = false
                    output.append(character)
                    index += 1
                    continue
                }
                output.append(character)
                index += 1
            }

            if units.last != 92 {
                lineComment = false
                inString = false
                inSection = false
                inVariable = false
            }
            let outputText = String(decoding: output, as: UTF16.self)
            contents.append(outputText)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: outputText, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private func autoItCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inBlockComment = false
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var quote: UInt16?
            var atVariable = false
            var dollarVariable = false
            var preprocessor = false
            var firstToken = true
            var containedComment = inBlockComment

            while index < units.count {
                let character = units[index]
                if character == 0 {
                    if !inBlockComment { output.append(contentsOf: units[index...]) }
                    break
                }
                if inBlockComment {
                    containedComment = true
                    if firstToken, let endLength = Self.autoItBlockEndLength(in: units, at: index) {
                        inBlockComment = false
                        index += endLength
                        firstToken = false
                    } else {
                        if !Self.legacyIsWhitespace(character) { firstToken = false }
                        index += 1
                    }
                    continue
                }
                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote { quote = nil }
                    index += 1
                    continue
                }
                if character == 59 {
                    containedComment = true
                    break
                }
                if preprocessor {
                    output.append(character)
                    index += 1
                    continue
                }
                if character == 64 {
                    atVariable = true
                    output.append(character)
                    index += 1
                    continue
                }
                if atVariable {
                    output.append(character)
                    if !Self.legacyIsAlphanumeric(character) { atVariable = false }
                    index += 1
                    continue
                }
                if character == 36 {
                    dollarVariable = true
                    output.append(character)
                    index += 1
                    continue
                }
                if dollarVariable {
                    output.append(character)
                    if !Self.legacyIsAlphanumeric(character) { dollarVariable = false }
                    index += 1
                    continue
                }
                if character == 34 || character == 39 {
                    quote = character
                    output.append(character)
                    index += 1
                    continue
                }
                if firstToken, let startLength = Self.autoItBlockStartLength(in: units, at: index) {
                    containedComment = true
                    inBlockComment = true
                    index += startLength
                    firstToken = false
                    continue
                }
                if firstToken, character == 35 {
                    preprocessor = true
                    output.append(character)
                    index += 1
                    continue
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

    private func fsharpCommentFilteredContents(in document: TextDocument) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var inBlockComment = false
        var inRawString = false
        var carriedLineComment = false
        var carriedQuote: UInt16?
        var carriedPreprocessor = false
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var quote = carriedQuote
            var lineComment = carriedLineComment
            var preprocessor = carriedPreprocessor
            var rawTextEnd = -1
            var commentEnd = -1
            var firstToken = !lineComment && quote == nil && !preprocessor
            var containedComment = inBlockComment || lineComment

            if lineComment { index = units.count }
            while index < units.count {
                let character = units[index]
                if character == 0 {
                    if !inBlockComment { output.append(contentsOf: units[index...]) }
                    break
                }
                if inBlockComment {
                    containedComment = true
                    if index + 1 < units.count, character == 42, units[index + 1] == 41 {
                        inBlockComment = false
                        commentEnd = index + 2
                        index += 2
                    } else {
                        index += 1
                    }
                    continue
                }
                if let activeQuote = quote {
                    output.append(character)
                    if character == activeQuote, Self.twoLookbackQuoteCloses(in: units, at: index) { quote = nil }
                    index += 1
                    continue
                }
                if index + 1 < units.count, character == 47, units[index + 1] == 47 {
                    containedComment = true
                    lineComment = true
                    break
                }
                if inRawString {
                    output.append(character)
                    if index >= 2, character == 34, units[index - 1] == 34, units[index - 2] == 34 {
                        inRawString = false
                        rawTextEnd = index + 2
                    }
                    index += 1
                    continue
                }
                if index > rawTextEnd, index >= 2, character == 34,
                   units[index - 1] == 34, units[index - 2] == 34 {
                    inRawString = true
                    output.append(character)
                    index += 1
                    continue
                }
                if preprocessor {
                    if index > commentEnd, index > 0, character == 42, units[index - 1] == 41 {
                        if !output.isEmpty { output.removeLast() }
                        containedComment = true
                        inBlockComment = true
                    } else {
                        output.append(character)
                    }
                    index += 1
                    continue
                }
                if !preprocessor, character == 34,
                   (index < 2 || units[index - 1] != 34 || units[index - 2] != 34) ||
                   !preprocessor && character == 39 &&
                   (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                    quote = character
                    output.append(character)
                    index += 1
                    continue
                }
                if index + 1 > commentEnd, index + 1 < units.count,
                   character == 40, units[index + 1] == 42 {
                    containedComment = true
                    inBlockComment = true
                    index += 2
                    continue
                }
                if firstToken, character == 35 { preprocessor = true }
                output.append(character)
                if !Self.legacyIsWhitespace(character) { firstToken = false }
                index += 1
            }

            if units.last == 92 {
                carriedLineComment = lineComment
                carriedQuote = quote
                carriedPreprocessor = preprocessor
            } else {
                carriedLineComment = false
                carriedQuote = nil
                carriedPreprocessor = false
            }
            let outputText = String(decoding: output, as: UTF16.self)
            contents.append(outputText)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: outputText, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private static func autoItBlockStartLength(in units: [UInt16], at index: Int) -> Int? {
        for token in ["#cs", "#CS", "#comments-start"] {
            let tokenUnits = Array(token.utf16)
            if index + tokenUnits.count <= units.count,
               units[index..<(index + tokenUnits.count)].elementsEqual(tokenUnits) {
                return tokenUnits.count
            }
        }
        return nil
    }

    private static func autoItBlockEndLength(in units: [UInt16], at index: Int) -> Int? {
        for token in ["#ce", "#CE", "#comments-end"] {
            let tokenUnits = Array(token.utf16)
            if index + tokenUnits.count <= units.count,
               units[index..<(index + tokenUnits.count)].elementsEqual(tokenUnits) {
                return tokenUnits.count
            }
        }
        return nil
    }

    private func embeddedHTMLCommentFilteredContents(
        in document: TextDocument,
        language: EmbeddedHTMLLanguage
    ) -> CommentFilteredContents {
        var contents: [String] = []
        var commentOnly: [Bool] = []
        var mode = EmbeddedHTMLMode.html
        var commentKind: EmbeddedCommentKind?
        var quote: UInt16?
        var quoteContext = EmbeddedQuoteContext.html
        var scriptLineComment = false
        var scriptPreprocessor = false
        var scriptCookieNoise = false
        var smartyHash = false
        var inElement = false
        var pendingScript = false
        var pendingStyle = false
        var pendingEmbedded = false
        var aspAliasComment = false
        contents.reserveCapacity(document.records.count)
        commentOnly.reserveCapacity(document.records.count)

        for record in document.records {
            let units = Array(record.content.utf16)
            var output: [UInt16] = []
            var index = 0
            var containedComment = commentKind != nil || scriptLineComment
            var modeBoundary: Range<Int>?
            var searchedModeBoundary = false
            var scriptFirstToken = (mode == .script || mode == .embedded && language == .javascript) &&
                quote == nil && !scriptPreprocessor && !scriptCookieNoise
            var embeddedLineComment = false
            var modeStartIndex = 0
            var scriptParserRan = false
            let nulIndex = units.firstIndex(of: 0) ?? units.count
            var scriptBoundaryCursor = 0
            var styleBoundaryCursor = 0
            var questionBoundaryCursor = 0
            var percentBoundaryCursor = 0
            var smartyBoundaryCursor = 0
            smartyHash = false

            if (mode == .script || mode == .embedded && language == .javascript), scriptPreprocessor {
                let preprocessorMode = mode
                mode = .html
                pendingScript = preprocessorMode == .script
                pendingEmbedded = preprocessorMode == .embedded
                inElement = true
                if commentKind == .cBlock { commentKind = .html }
            }

            while index < units.count {
                if !searchedModeBoundary {
                    modeBoundary = switch mode {
                    case .script:
                        scriptPreprocessor
                            ? nil
                            : Self.nextUTF16Range(
                                in: units,
                                token: Array("</script>".utf16),
                                cursor: &scriptBoundaryCursor,
                                from: index,
                                before: nulIndex
                            )
                    case .style:
                        Self.nextUTF16Range(
                            in: units,
                            token: Array("</style>".utf16),
                            cursor: &styleBoundaryCursor,
                            from: index,
                            before: nulIndex
                        )
                    case .embedded:
                        language == .smarty
                            ? Self.nextUTF16Range(
                                in: units,
                                token: [125],
                                cursor: &smartyBoundaryCursor,
                                from: index,
                                before: nulIndex
                            )
                            : Self.nextEmbeddedCloser(
                                in: units,
                                questionCursor: &questionBoundaryCursor,
                                percentCursor: &percentBoundaryCursor,
                                from: index,
                                before: nulIndex
                            )
                    case .html:
                        nil
                    }
                    searchedModeBoundary = true
                }
                if let boundary = modeBoundary, index == boundary.lowerBound {
                    let closingMode = mode
                    if language == .smarty, closingMode == .embedded,
                       commentKind == .smarty, index > 0, units[index - 1] == 42 {
                        mode = .html
                        commentKind = nil
                        quote = nil
                        pendingEmbedded = false
                        index = boundary.upperBound
                        searchedModeBoundary = false
                        continue
                    }
                    let protected = switch language {
                    case .javascript:
                        false
                    case .asp:
                        false
                    case .php:
                        mode == .embedded && (commentKind == .cBlock || quote != nil)
                    case .smarty:
                        mode == .embedded && (commentKind == .smarty || quote == 34)
                    }
                    if protected {
                        if commentKind == nil { output.append(contentsOf: units[boundary]) }
                        index = boundary.upperBound
                        modeStartIndex = index
                        searchedModeBoundary = false
                        continue
                    }
                    mode = .html
                    commentKind = nil
                    quote = nil
                    scriptPreprocessor = false
                    scriptCookieNoise = false
                    smartyHash = false
                    scriptLineComment = false
                    pendingScript = false
                    pendingStyle = false
                    pendingEmbedded = false
                    if closingMode == .embedded, (embeddedLineComment || aspAliasComment), modeStartIndex > 0 {
                        output.append(contentsOf: units[(boundary.lowerBound + 1)..<boundary.upperBound])
                    } else {
                        output.append(contentsOf: units[boundary])
                    }
                    embeddedLineComment = false
                    aspAliasComment = false
                    index = boundary.upperBound
                    searchedModeBoundary = false
                    continue
                }

                let character = units[index]
                if character == 0 {
                    if commentKind == nil && !scriptLineComment && !aspAliasComment {
                        output.append(contentsOf: units[index...])
                    }
                    break
                }
                if scriptLineComment {
                    containedComment = true
                    index = modeBoundary?.lowerBound ?? units.count
                    continue
                }
                if let activeComment = commentKind {
                    containedComment = true
                    let closer: [UInt16] = switch activeComment {
                    case .html: Array("-->".utf16)
                    case .cBlock: [42, 47]
                    case .smarty: [42, 125]
                    }
                    if Self.utf16HasPrefix(units, closer, at: index) {
                        commentKind = nil
                        index += closer.count
                        if activeComment == .html, !inElement {
                            if pendingScript {
                                mode = .script
                            } else if pendingStyle {
                                mode = .style
                            } else if pendingEmbedded {
                                mode = .embedded
                            }
                            if mode != .html {
                                let cookieNoise = mode == .script && (pendingStyle || pendingEmbedded)
                                if mode == .embedded, language == .asp { aspAliasComment = true }
                                pendingScript = false
                                pendingStyle = false
                                pendingEmbedded = false
                                scriptCookieNoise = cookieNoise
                                scriptFirstToken = !cookieNoise
                                searchedModeBoundary = false
                                modeStartIndex = index
                            }
                        } else if activeComment == .smarty {
                            mode = .html
                        }
                    } else {
                        index += 1
                    }
                    continue
                }
                if let activeQuote = quote {
                    output.append(character)
                    let closes = quoteContext == .asp
                        ? character == activeQuote
                        : character == activeQuote && Self.twoLookbackQuoteCloses(in: units, at: index)
                    if closes {
                        quote = nil
                    }
                    index += 1
                    continue
                }

                switch mode {
                case .html:
                    if Self.utf16HasPrefix(units, Array("<!--".utf16), at: index) {
                        containedComment = true
                        commentKind = .html
                        inElement = false
                        scriptPreprocessor = false
                        index += 4
                        if pendingScript {
                            mode = .script
                            commentKind = .cBlock
                        } else if pendingStyle {
                            mode = .style
                            commentKind = .cBlock
                        } else if pendingEmbedded {
                            mode = .embedded
                            if language == .php { commentKind = .cBlock }
                            if language == .javascript { commentKind = .cBlock }
                            if language == .smarty { commentKind = .smarty }
                            if language == .asp {
                                commentKind = nil
                                aspAliasComment = true
                            }
                        }
                        if mode != .html {
                            let cookieNoise = mode == .script && (pendingStyle || pendingEmbedded)
                            pendingScript = false
                            pendingStyle = false
                            pendingEmbedded = false
                            scriptCookieNoise = cookieNoise
                            scriptFirstToken = !cookieNoise
                            searchedModeBoundary = false
                            modeStartIndex = index
                        }
                        continue
                    }
                    if character == 60, index + 1 < units.count,
                        units[index + 1] == 63 || units[index + 1] == 37 {
                        if inElement {
                            pendingEmbedded = true
                        } else {
                            mode = .embedded
                            searchedModeBoundary = false
                            modeStartIndex = index + 1
                        }
                        output.append(character)
                        index += 1
                        continue
                    }
                    if language == .smarty, index + 1 < units.count,
                        character == 123, units[index + 1] == 42 {
                        if inElement {
                            pendingEmbedded = true
                            output.append(character)
                            index += 1
                        } else {
                            containedComment = true
                            commentKind = .smarty
                            mode = .embedded
                            index += 2
                            searchedModeBoundary = false
                            modeStartIndex = index
                        }
                        continue
                    }
                    if language == .smarty, character == 123,
                       (index > 0 && !Self.legacyIsWhitespace(units[index - 1]) ||
                        index + 1 < units.count && !Self.legacyIsWhitespace(units[index + 1])) {
                        if inElement {
                            pendingEmbedded = true
                        } else {
                            mode = .embedded
                            searchedModeBoundary = false
                            modeStartIndex = index + 1
                        }
                        output.append(character)
                        index += 1
                        continue
                    }
                    if language != .smarty, character == 60,
                       let blockMode = Self.embeddedBlockMode(in: units, at: index) {
                        if blockMode == .script { pendingScript = true }
                        if blockMode == .style { pendingStyle = true }
                    }
                    if inElement {
                        if character == 34 || character == 39 &&
                           (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                            quote = character
                            quoteContext = .html
                        }
                        output.append(character)
                        index += 1
                        if character == 62 {
                            inElement = false
                            if pendingScript {
                                mode = .script
                            } else if pendingStyle {
                                mode = .style
                            } else if pendingEmbedded {
                                mode = .embedded
                                if quote != nil {
                                    quoteContext = switch language {
                                    case .javascript: .script
                                    case .asp: .asp
                                    case .php: .php
                                    case .smarty: .smarty
                                    }
                                }
                            }
                            if mode != .html {
                                let cookieNoise = mode == .script && (pendingStyle || pendingEmbedded)
                                pendingScript = false
                                pendingStyle = false
                                pendingEmbedded = false
                                scriptCookieNoise = cookieNoise
                                scriptFirstToken = (mode == .script || mode == .embedded && language == .javascript) &&
                                    quote == nil && !cookieNoise
                                scriptPreprocessor = false
                                searchedModeBoundary = false
                                modeStartIndex = index
                            }
                        }
                        continue
                    }
                    if character == 60 { inElement = true }
                    output.append(character)
                    index += 1

                case .script:
                    scriptParserRan = true
                    if index + 1 < units.count, character == 47, units[index + 1] == 47 {
                        containedComment = true
                        scriptLineComment = true
                        index = modeBoundary?.lowerBound ?? units.count
                        continue
                    }
                    if index + 1 < units.count, character == 47, units[index + 1] == 42 {
                        containedComment = true
                        commentKind = .cBlock
                        index += 2
                        continue
                    }
                    if scriptPreprocessor {
                        output.append(character)
                        index += 1
                        continue
                    }
                    if scriptFirstToken, character == 35 {
                        scriptPreprocessor = true
                        output.append(character)
                        index += 1
                        continue
                    }
                    if character == 34 || character == 39 &&
                       (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                        quote = character
                        quoteContext = .script
                        output.append(character)
                        index += 1
                        continue
                    }
                    output.append(character)
                    if !Self.legacyIsWhitespace(character) { scriptFirstToken = false }
                    index += 1

                case .style:
                    if index + 1 < units.count, character == 47, units[index + 1] == 42 {
                        containedComment = true
                        commentKind = .cBlock
                        index += 2
                        continue
                    }
                    output.append(character)
                    index += 1

                case .embedded:
                    switch language {
                    case .javascript:
                        scriptParserRan = true
                        if index + 1 < units.count, character == 47, units[index + 1] == 47 {
                            containedComment = true
                            embeddedLineComment = true
                            index = modeBoundary?.lowerBound ?? units.count
                            continue
                        }
                        if index + 1 < units.count, character == 47, units[index + 1] == 42 {
                            containedComment = true
                            commentKind = .cBlock
                            index += 2
                            continue
                        }
                        if scriptPreprocessor {
                            output.append(character)
                            index += 1
                            continue
                        }
                        if scriptFirstToken, character == 35 {
                            scriptPreprocessor = true
                        }
                        if character == 34 || character == 39 &&
                           (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                            quote = character
                            quoteContext = .script
                        } else if !Self.legacyIsWhitespace(character) {
                            scriptFirstToken = false
                        }
                    case .asp:
                        if character == 39 {
                            containedComment = true
                            embeddedLineComment = true
                            index = modeBoundary?.lowerBound ?? units.count
                            continue
                        }
                        if character == 34 {
                            quote = character
                            quoteContext = .asp
                        }
                        if aspAliasComment, quote == nil {
                            index += 1
                            continue
                        }
                    case .php:
                        if character == 35 || index + 1 < units.count && character == 47 && units[index + 1] == 47 {
                            containedComment = true
                            embeddedLineComment = true
                            index = modeBoundary?.lowerBound ?? units.count
                            continue
                        }
                        if index + 1 < units.count, character == 47, units[index + 1] == 42 {
                            containedComment = true
                            commentKind = .cBlock
                            index += 2
                            continue
                        }
                        if character == 34 || character == 39 &&
                           (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                            quote = character
                            quoteContext = .php
                        }
                    case .smarty:
                        if smartyHash {
                            output.append(character)
                            if character == 35, Self.twoLookbackQuoteCloses(in: units, at: index) {
                                smartyHash = false
                            }
                            index += 1
                            continue
                        }
                        if index + 1 < units.count, character == 123, units[index + 1] == 42 {
                            containedComment = true
                            commentKind = .smarty
                            index += 2
                            continue
                        }
                        if character == 35 {
                            smartyHash = true
                            output.append(character)
                            index += 1
                            continue
                        }
                        if character == 34 || character == 39 &&
                           (index == 0 || !Self.legacyIsAlphanumeric(units[index - 1])) {
                            quote = character
                            quoteContext = .smarty
                        }
                    }
                    output.append(character)
                    index += 1
                }
            }

            smartyHash = false
            scriptLineComment = false
            if mode == .script || mode == .embedded && language == .javascript {
                if scriptParserRan, units.last != 92 {
                    scriptPreprocessor = false
                    scriptCookieNoise = false
                    if quoteContext == .script { quote = nil }
                }
            } else if !(mode == .html && pendingScript && inElement) {
                scriptPreprocessor = false
                scriptCookieNoise = false
            }
            if let activeQuote = quote {
                switch quoteContext {
                case .html:
                    let preservesPendingEmbeddedQuote = pendingEmbedded && language != .asp
                    if !preservesPendingEmbeddedQuote && (activeQuote != 34 || units.isEmpty) { quote = nil }
                case .script:
                    if activeQuote != 34 || units.last != 92 { quote = nil }
                case .php, .smarty:
                    if mode != .embedded { quote = nil }
                case .asp, .style:
                    quote = nil
                }
            }
            let outputText = String(decoding: output, as: UTF16.self)
            contents.append(outputText)
            commentOnly.append(Self.isWholeCommentLine(containedComment, output: outputText, record: record))
        }
        return CommentFilteredContents(contents: contents, commentOnly: commentOnly)
    }

    private static func utf16HasPrefix(_ units: [UInt16], _ prefix: [UInt16], at index: Int) -> Bool {
        index + prefix.count <= units.count && units[index..<(index + prefix.count)].elementsEqual(prefix)
    }

    private static func embeddedBlockMode(in units: [UInt16], at index: Int) -> EmbeddedHTMLMode? {
        guard units[index] == 60 else { return nil }
        var end = index + 1
        while end < units.count, legacyIsAlphanumeric(units[end]) || units[end] == 46 { end += 1 }
        if utf16HasPrefix(units, Array("<!--".utf16), at: end) ||
            utf16HasPrefix(units, [60, 63], at: end) ||
            utf16HasPrefix(units, [60, 37], at: end) {
            return nil
        }
        let identifier = String(decoding: units[(index + 1)..<end], as: UTF16.self).lowercased()
        if identifier == "script" { return .script }
        if identifier == "style" { return .style }
        return nil
    }

    private static func nextUTF16Range(
        in units: [UInt16],
        token: [UInt16],
        cursor: inout Int,
        from start: Int,
        before end: Int
    ) -> Range<Int>? {
        cursor = max(cursor, start)
        guard !token.isEmpty, cursor + token.count <= end else { return nil }
        while cursor + token.count <= end {
            if utf16HasPrefix(units, token, at: cursor) {
                let range = cursor..<(cursor + token.count)
                cursor = range.upperBound
                return range
            }
            cursor += 1
        }
        return nil
    }

    private static func nextEmbeddedCloser(
        in units: [UInt16],
        questionCursor: inout Int,
        percentCursor: inout Int,
        from start: Int,
        before end: Int
    ) -> Range<Int>? {
        nextUTF16Range(in: units, token: [63, 62], cursor: &questionCursor, from: start, before: end) ??
            nextUTF16Range(in: units, token: [37, 62], cursor: &percentCursor, from: start, before: end)
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

    private static func twoLookbackQuoteCloses(
        in units: [UInt16],
        at index: Int,
        escape: UInt16
    ) -> Bool {
        index == 0 || units[index - 1] != escape || index >= 2 && units[index - 2] == escape
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
