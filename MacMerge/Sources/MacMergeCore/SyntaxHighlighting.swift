import Foundation

public enum SyntaxHighlightingLanguage: String, CaseIterable, Equatable, Hashable, Sendable {
    case plainText
    case swift
    case cLike
    case json
    case markdown
}

public enum SyntaxTokenKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case keyword
    case string
    case comment
    case number
    case literal
    case heading
    case emphasis
    case code
    case link
}

public struct SyntaxToken: Equatable, Hashable, Sendable {
    public let kind: SyntaxTokenKind
    /// Zero-based UTF-16 range suitable for Cocoa text APIs.
    public let range: NSRange

    public init(kind: SyntaxTokenKind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

public struct SyntaxHighlightingLimits: Equatable, Sendable {
    public static let `default` = SyntaxHighlightingLimits()

    public let maximumInputUTF8Bytes: Int
    public let maximumTokenCount: Int
    public let maximumWorkUnits: Int
    public let maximumMetadataEntries: Int

    public init(
        maximumInputUTF8Bytes: Int = 16 * 1024 * 1024,
        maximumTokenCount: Int = 1_000_000,
        maximumWorkUnits: Int = 64 * 1024 * 1024,
        maximumMetadataEntries: Int = 1_000_000
    ) {
        self.maximumInputUTF8Bytes = maximumInputUTF8Bytes
        self.maximumTokenCount = maximumTokenCount
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumMetadataEntries = maximumMetadataEntries
    }
}

public enum SyntaxHighlightingError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case inputTooLarge(maximumUTF8Bytes: Int)
    case tooManyTokens(maximumTokens: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case metadataLimitExceeded(maximumEntries: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Syntax highlighting limits are invalid."
        case .inputTooLarge(let maximumUTF8Bytes):
            "Text exceeds the \(maximumUTF8Bytes)-byte UTF-8 syntax highlighting limit."
        case .tooManyTokens(let maximumTokens):
            "Syntax highlighting exceeds the \(maximumTokens)-token limit."
        case .workLimitExceeded(let maximumWorkUnits):
            "Syntax highlighting exceeds the \(maximumWorkUnits)-unit work limit."
        case .metadataLimitExceeded(let maximumEntries):
            "Syntax highlighting exceeds the \(maximumEntries)-entry metadata limit."
        }
    }
}

public enum SyntaxHighlighter: Sendable {
    enum Checkpoint: Equatable, Sendable {
        case scanner
        case markdownCodeSpanMetadata
        case markdownInlineMetadata
        case markdownEmission
    }

    @TaskLocal
    static var checkpointObserver: (@Sendable (Checkpoint) -> Void)?

    /// Returns ordered, non-overlapping token ranges. Unstyled text is omitted.
    ///
    /// This is bounded, best-effort lexical highlighting for Swift 6 source forms, selected
    /// C23/C++23 forms, RFC 8259 JSON tokens, and selected CommonMark 0.31.2 constructs. The
    /// combined C/C++ mode accepts C++23 whitespace-bearing line splices as an extension when
    /// highlighting C; C23 itself requires an immediate backslash-newline pair. It is not a
    /// compiler lexer, validator, complete parser, or complete CommonMark implementation.
    public static func highlight(
        _ text: String,
        language: SyntaxHighlightingLanguage,
        limits: SyntaxHighlightingLimits = .default
    ) throws -> [SyntaxToken] {
        try highlight(text, language: language, limits: limits, workObserver: nil)
    }

    static func highlight(
        _ text: String,
        language: SyntaxHighlightingLanguage,
        limits: SyntaxHighlightingLimits = .default,
        workObserver: (@Sendable (Int) -> Void)?
    ) throws -> [SyntaxToken] {
        guard limits.maximumInputUTF8Bytes >= 0,
            limits.maximumTokenCount >= 0,
            limits.maximumWorkUnits >= 0,
            limits.maximumMetadataEntries >= 0
        else {
            throw SyntaxHighlightingError.invalidLimits
        }
        try Task.checkCancellation()
        try validateInputSize(text, maximumUTF8Bytes: limits.maximumInputUTF8Bytes)
        try Task.checkCancellation()
        guard language != .plainText, !text.isEmpty else { return [] }

        var scanner = try SyntaxScanner(
            text: text,
            language: language,
            maximumTokenCount: limits.maximumTokenCount,
            maximumWorkUnits: limits.maximumWorkUnits,
            maximumMetadataEntries: limits.maximumMetadataEntries,
            workObserver: workObserver
        )
        let tokens = try scanner.scan()
        try Task.checkCancellation()
        return tokens
    }

    private static func validateInputSize(_ text: String, maximumUTF8Bytes: Int) throws {
        var byteCount = 0
        for _ in text.utf8 {
            guard byteCount < maximumUTF8Bytes else {
                throw SyntaxHighlightingError.inputTooLarge(
                    maximumUTF8Bytes: maximumUTF8Bytes
                )
            }
            byteCount += 1
            if byteCount.isMultiple(of: 4_096) { try Task.checkCancellation() }
        }
    }

    static func checkpoint(_ checkpoint: Checkpoint) throws {
        checkpointObserver?(checkpoint)
        try Task.checkCancellation()
    }
}

private struct SyntaxScanner {
    private static let swiftKeywords: Set<String> = [
        "Any", "Protocol", "Self", "Type", "actor", "any", "as", "associativity",
        "associatedtype", "async", "await", "borrowing", "break", "case", "catch", "class",
        "consume", "consuming", "continue", "convenience", "copy", "default", "defer", "deinit",
        "didSet", "discard", "distributed", "do", "dynamic", "each", "else", "enum", "extension",
        "fallthrough", "fileprivate", "final", "for", "func", "get", "guard", "higherThan", "if",
        "import", "in", "indirect", "infix", "init", "inout", "internal", "is", "isolated", "lazy", "left",
        "let", "lowerThan", "macro", "mutating", "none", "nonisolated", "nonmutating", "open",
        "operator", "optional", "override", "package", "postfix", "precedencegroup", "prefix", "private",
        "protocol", "public", "repeat", "required", "rethrows", "return", "right", "safe", "self",
        "sending", "set", "some", "static", "struct", "subscript", "super", "switch", "throw", "throwing",
        "throws", "try", "typealias", "unowned", "unsafe", "var", "weak", "where", "while",
        "willSet", "yield", "assignment", "attached", "freestanding"
    ]

    private static let cLikeKeywords: Set<String> = [
        "_Alignas", "_Alignof", "_Atomic", "_BitInt", "_Bool", "_Complex", "_Generic", "_Imaginary",
        "_Noreturn", "_Static_assert", "_Thread_local", "alignas", "alignof", "and", "and_eq", "asm",
        "atomic_cancel", "atomic_commit", "atomic_noexcept", "auto", "bitand", "bitor", "bool", "break",
        "case", "catch", "char", "char8_t", "char16_t", "char32_t", "class", "co_await", "co_return",
        "co_yield", "compl", "concept", "const", "const_cast", "consteval", "constexpr", "constinit",
        "continue", "decltype", "default", "delete", "do", "double", "dynamic_cast",
        "else", "enum", "explicit", "export", "extern", "float", "for", "friend", "goto", "if",
        "final", "import", "inline", "int", "long", "module", "mutable", "namespace", "new", "noexcept",
        "not", "not_eq", "operator", "or", "or_eq", "override", "private", "protected", "public", "reflexpr",
        "register", "reinterpret_cast", "requires", "restrict", "return", "short", "signed", "sizeof",
        "static", "static_assert", "static_cast",
        "struct", "switch", "synchronized", "template", "this", "thread_local", "throw", "try", "typedef",
        "typeid", "typename", "typeof", "typeof_unqual", "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t",
        "while", "xor", "xor_eq"
    ]

    private static let swiftLiterals: Set<String> = ["false", "nil", "true"]
    private static let cLikeLiterals: Set<String> = ["false", "NULL", "nullptr", "true"]
    private static let swiftKeywordUnits = Set(swiftKeywords.map { Array($0.utf16) })
    private static let cLikeKeywordUnits = Set(cLikeKeywords.map { Array($0.utf16) })
    private static let swiftLiteralUnits = Set(swiftLiterals.map { Array($0.utf16) })
    private static let cLikeLiteralUnits = Set(cLikeLiterals.map { Array($0.utf16) })
    private static let cxxRawStringPrefixes: [[UInt16]] = [
        Array("u8R\"".utf16), Array("uR\"".utf16), Array("UR\"".utf16),
        Array("LR\"".utf16), Array("R\"".utf16)
    ]
    private static let cLikeStringPrefixes: [[UInt16]] = [
        Array("u8".utf16), Array("u".utf16), Array("U".utf16), Array("L".utf16)
    ]
    private static let cxxFloatingNumberSuffixes: [[UInt16]] = [
        "bf16", "BF16", "f128", "F128", "f16", "F16", "f32", "F32", "f64", "F64", "f", "F", "l", "L"
    ].map { Array($0.utf16) }
    private static let cxxIntegerNumberSuffixes: [[UInt16]] = [
        "uwb", "uWB", "Uwb", "UWB", "wbu", "wbU", "WBu", "WBU",
        "ull", "uLL", "Ull", "ULL", "llu", "llU", "LLu", "LLU",
        "uz", "uZ", "Uz", "UZ", "zu", "zU", "Zu", "ZU",
        "ul", "uL", "Ul", "UL", "lu", "lU", "Lu", "LU",
        "wb", "WB", "ll", "LL", "u", "U", "l", "L", "z", "Z"
    ].map { Array($0.utf16) }
    private static let cxxNumberSuffixUnits = Set(
        (cxxFloatingNumberSuffixes + cxxIntegerNumberSuffixes).flatMap { $0 }
    )
    private static let maximumCxxNumberSuffixLength = 4
    private static let asciiDigits = Array(0x30...0x39).map(UInt16.init)
    private static let asciiIdentifierContinuationUnits = (Array(0x30...0x39) + Array(0x41...0x5A) + [0x5F] + Array(0x61...0x7A)).map(UInt16.init)
    private static let hexadecimalPrefixUnits: [UInt16] = [0x78, 0x58]
    private static let binaryPrefixUnits: [UInt16] = [0x62, 0x42]
    private static let octalPrefixUnits: [UInt16] = [0x6F, 0x4F]
    private static let hexadecimalExponentUnits: [UInt16] = [0x50, 0x70]
    private static let decimalExponentUnits: [UInt16] = [0x45, 0x65]
    private static let exponentSignUnits: [UInt16] = [0x2B, 0x2D]
    private static let swiftIdentifierHeadRanges: [ClosedRange<UInt32>] = [
        0x00A8...0x00A8, 0x00AA...0x00AA, 0x00AD...0x00AD, 0x00AF...0x00AF,
        0x00B2...0x00B5, 0x00B7...0x00BA, 0x00BC...0x00BE, 0x00C0...0x00D6,
        0x00D8...0x00F6, 0x00F8...0x00FF, 0x0100...0x02FF, 0x0370...0x167F,
        0x1681...0x180D, 0x180F...0x1DBF, 0x1E00...0x1FFF, 0x200B...0x200D,
        0x202A...0x202E, 0x203F...0x2040, 0x2054...0x2054, 0x2060...0x206F,
        0x2070...0x20CF, 0x2100...0x218F, 0x2460...0x24FF, 0x2776...0x2793,
        0x2C00...0x2DFF, 0x2E80...0x2FFF, 0x3004...0x3007, 0x3021...0x302F,
        0x3031...0x303F, 0x3040...0xD7FF, 0xF900...0xFD3D, 0xFD40...0xFDCF,
        0xFDF0...0xFE1F, 0xFE30...0xFE44, 0xFE47...0xFFFD
    ]
    private static let jsonLiteralUnits: [[UInt16]] = [
        Array("false".utf16), Array("null".utf16), Array("true".utf16)
    ]

    private struct MarkdownDelimiterRun {
        let start: Int
        let length: Int
        let canClose: Bool
    }

    private struct MarkdownBracket {
        let start: Int
        let isImage: Bool
        let completedLinkCount: Int
        let asteriskDelimiterFloor: Int
        let underscoreDelimiterFloor: Int
        var deferredEmphasis: [MarkdownDeferredEmphasis] = []
    }

    private struct MarkdownDeferredEmphasis {
        let marker: UInt16
        let closingStart: Int
        let closingLength: Int
        let closingCanOpen: Bool
    }

    private enum MarkdownDestinationPhase {
        case leading
        case angle
        case afterAngle
        case bare
        case afterDestination
        case doubleQuotedTitle
        case singleQuotedTitle
        case parenthesizedTitle
        case afterTitle
    }

    private struct MarkdownDestination {
        let tokenStart: Int
        let isImage: Bool
        let openingParenthesis: Int
        let openingLineStart: Bool
        let openingLineHasContent: Bool
        let asteriskDelimiterFloor: Int
        let underscoreDelimiterFloor: Int
        var phase: MarkdownDestinationPhase = .leading
        var parenthesisDepth = 0
        var escaped = false
        var sawLeadingWhitespace = false
        var crossedSoftBreak = false
        var deferredEmphasis: [MarkdownDeferredEmphasis] = []
    }

    private struct SwiftLexicalContext {
        var failedBareRegexUntil = 0
        var bareRegexRecoveryStart: Int?
        var failedRawRegexUntilByHashCount: [Int: Int] = [:]
        var failedRawRegexUntilForHashCountsAtLeast = 0
        var failedRawRegexMinimumHashCount = Int.max
        var commentTriviaEnd = -1
        var regexContextBeforeComment = false
    }

    private enum MarkdownDestinationStep {
        case advance
        case complete
        case invalid
    }

    private let units: [UInt16]
    private let language: SyntaxHighlightingLanguage
    private let maximumTokenCount: Int
    private let maximumWorkUnits: Int
    private let maximumMetadataEntries: Int
    private let workObserver: (@Sendable (Int) -> Void)?
    private var tokens: [SyntaxToken]
    private var workUnits = 0
    private var metadataEntries = 0
    private var cursor = 0
    private var swiftContext = SwiftLexicalContext()
    private var markdownLinkEnds: [Int: Int] = [:]
    private var markdownCodeSpanEnds: [Int: Int] = [:]
    private var markdownEmphasisEnds: [Int: Int] = [:]
    private var markdownLinkStartOrder: [Int] = []
    private var markdownCodeSpanStarts: [Int] = []
    private var markdownEmphasisStartOrder: [Int] = []
    private var cxxSuffixLogicalUnits: [UInt16] = []
    private var cxxSuffixPhysicalEnds: [Int] = []
    private var cxxSuffixLogicalStarts: [Int] = []
    private var identifierUnits: [UInt16] = []

    init(
        text: String,
        language: SyntaxHighlightingLanguage,
        maximumTokenCount: Int,
        maximumWorkUnits: Int,
        maximumMetadataEntries: Int,
        workObserver: (@Sendable (Int) -> Void)?
    ) throws {
        var units: [UInt16] = []
        for unit in text.utf16 {
            units.append(unit)
            if units.count.isMultiple(of: 4_096) { try Task.checkCancellation() }
        }
        self.units = units
        self.language = language
        self.maximumTokenCount = maximumTokenCount
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumMetadataEntries = maximumMetadataEntries
        self.workObserver = workObserver
        tokens = []
        tokens.reserveCapacity(min(maximumTokenCount, 4_096))
    }

    mutating func scan() throws -> [SyntaxToken] {
        try SyntaxHighlighter.checkpoint(.scanner)
        switch language {
        case .plainText:
            break
        case .swift, .cLike:
            try scanCode()
        case .json:
            try scanJSON()
        case .markdown:
            try scanMarkdown()
        }
        workObserver?(workUnits)
        try Task.checkCancellation()
        return tokens
    }

    private mutating func append(_ kind: SyntaxTokenKind, from start: Int, to end: Int) throws {
        guard end > start else { return }
        guard tokens.count < maximumTokenCount else {
            throw SyntaxHighlightingError.tooManyTokens(maximumTokens: maximumTokenCount)
        }
        tokens.append(
            SyntaxToken(kind: kind, range: NSRange(location: start, length: end - start))
        )
    }

    private mutating func consumeWork(_ amount: Int = 1) throws {
        let previousWorkUnits = workUnits
        let addition = workUnits.addingReportingOverflow(amount)
        guard !addition.overflow, addition.partialValue <= maximumWorkUnits else {
            throw SyntaxHighlightingError.workLimitExceeded(
                maximumWorkUnits: maximumWorkUnits
            )
        }
        workUnits = addition.partialValue
        if previousWorkUnits / 4_096 != workUnits / 4_096 {
            workObserver?(workUnits)
            try Task.checkCancellation()
        }
    }

    private mutating func retainMetadataEntry() throws {
        guard metadataEntries < maximumMetadataEntries else {
            throw SyntaxHighlightingError.metadataLimitExceeded(
                maximumEntries: maximumMetadataEntries
            )
        }
        metadataEntries += 1
    }

    private mutating func scanCode() throws {
        while cursor < units.count {
            try consumeWork()
            if language == .swift {
                if units[cursor] == 0x2F {
                    if swiftContext.bareRegexRecoveryStart.map({ cursor >= $0 }) ?? true {
                        swiftContext.bareRegexRecoveryStart = nil
                        if let end = try swiftRegexEnd(startingAt: cursor, nesting: 0) {
                            try append(.string, from: cursor, to: end)
                            cursor = end
                            continue
                        }
                    }
                }
                if has(0x2F, 0x2F, at: cursor) {
                    let commentStart = cursor
                    let end = try codeLineCommentEnd(startingAt: cursor + 2)
                    try rememberSwiftCommentContext(start: commentStart, end: end)
                    try append(.comment, from: cursor, to: end)
                    cursor = end
                    continue
                }
                if has(0x2F, 0x2A, at: cursor) {
                    let commentStart = cursor
                    let end = try blockCommentEnd(contentStartingAt: cursor + 2)
                    try rememberSwiftCommentContext(start: commentStart, end: end)
                    try append(.comment, from: cursor, to: end)
                    cursor = end
                    continue
                }
                invalidateSwiftCommentContextIfNeeded(at: cursor)
            } else if let opening = try cLikeCommentOpening(startingAt: cursor) {
                let end =
                    opening.isBlock
                    ? try blockCommentEnd(contentStartingAt: opening.contentStart)
                    : try codeLineCommentEnd(startingAt: opening.contentStart)
                try append(.comment, from: cursor, to: end)
                cursor = end
                continue
            }
            if language == .swift {
                if units[cursor] == 0x60 {
                    if let end = try swiftEscapedIdentifierEnd(startingAt: cursor) {
                        cursor = end
                    } else {
                        cursor += 1
                    }
                    continue
                }
                if units[cursor] == 0x23 {
                    let hashCount = try repeatedUnitCount(0x23, startingAt: cursor)
                    let quoteStart = cursor + hashCount
                    if quoteStart < units.count,
                        units[quoteStart] == 0x2F,
                        let end = try swiftRegexEnd(
                            openingSlash: quoteStart,
                            hashCount: hashCount,
                            nesting: 0
                        )
                    {
                        try append(.string, from: cursor, to: end)
                        cursor = end
                        continue
                    }
                    guard quoteStart < units.count, units[quoteStart] == 0x22 else {
                        cursor = quoteStart
                        continue
                    }
                    let end = try swiftStringEnd(
                        quoteStart: quoteStart,
                        hashCount: hashCount,
                        nesting: 0
                    )
                    try append(.string, from: cursor, to: end)
                    cursor = end
                    continue
                }
                if units[cursor] == 0x22 {
                    let end = try swiftStringEnd(
                        quoteStart: cursor,
                        hashCount: 0,
                        nesting: 0
                    )
                    try append(.string, from: cursor, to: end)
                    cursor = end
                    continue
                }
            } else {
                if let end = try cxxRawStringEnd(startingAt: cursor) {
                    try append(.string, from: cursor, to: end)
                    cursor = end
                    continue
                }
                if let quoteStart = try cLikeQuotedStringStart(startingAt: cursor) {
                    let end = try quotedStringEnd(
                        startingAt: quoteStart,
                        quote: units[quoteStart],
                        delimiterLength: 1,
                        allowsEscapedNewlines: true,
                        terminatesAtRawC0: false
                    )
                    try append(.string, from: cursor, to: end)
                    cursor = end
                    continue
                }
            }
            var startsCDecimalFraction = false
            if language == .cLike, units[cursor] == 0x2E {
                let digit = try cLikeSplicedIndex(
                    startingAt: cursor + 1,
                    followedBy: Self.asciiDigits
                )
                startsCDecimalFraction = digit < units.count && isASCIIDigit(units[digit])
            }
            if isASCIIDigit(units[cursor]) || startsCDecimalFraction {
                let number = try codeNumberEnd(startingAt: cursor)
                if language == .cLike,
                    let malformedEnd = try cLikeMalformedPreprocessingNumberEnd(
                        startingAt: number.end
                    )
                {
                    cursor = malformedEnd
                    continue
                }
                if number.isValid {
                    try append(.number, from: cursor, to: number.end)
                }
                cursor =
                    language == .swift && !number.isValid
                    ? try malformedSwiftNumberEnd(startingAt: number.end)
                    : number.end
                continue
            }
            if isCodeIdentifierStart(at: cursor) {
                let start = cursor
                identifierUnits.removeAll(keepingCapacity: true)
                let firstLength = scalarLength(at: cursor)
                identifierUnits.append(contentsOf: units[cursor..<(cursor + firstLength)])
                cursor += firstLength
                while cursor < units.count {
                    if isCodeIdentifierContinuation(at: cursor) {
                        try consumeWork()
                        let length = scalarLength(at: cursor)
                        if identifierUnits.count <= 32 {
                            identifierUnits.append(contentsOf: units[cursor..<(cursor + length)])
                        }
                        cursor += length
                    } else if language == .cLike,
                        let spliceEnd = try cLineSplicesEnd(startingAt: cursor),
                        spliceEnd < units.count,
                        isCodeIdentifierContinuation(at: spliceEnd)
                    {
                        try consumeWork(spliceEnd - cursor)
                        cursor = spliceEnd
                    } else {
                        break
                    }
                }
                try Task.checkCancellation()
                guard identifierUnits.count <= 32 else { continue }
                let literals = language == .swift ? Self.swiftLiteralUnits : Self.cLikeLiteralUnits
                let keywords = language == .swift ? Self.swiftKeywordUnits : Self.cLikeKeywordUnits
                if literals.contains(identifierUnits) {
                    try append(.literal, from: start, to: cursor)
                } else if keywords.contains(identifierUnits) {
                    try append(.keyword, from: start, to: cursor)
                }
                continue
            }
            cursor += 1
        }
    }

    private mutating func scanJSON() throws {
        var recoveringMalformedString = false
        var recoveryEscape = false
        while cursor < units.count {
            try consumeWork()
            if recoveringMalformedString {
                if isLineBreak(units[cursor]) {
                    recoveringMalformedString = false
                    recoveryEscape = false
                } else if units[cursor] == 0x5C {
                    recoveryEscape.toggle()
                    cursor += 1
                    continue
                } else {
                    if units[cursor] == 0x22, !recoveryEscape {
                        recoveringMalformedString = false
                    }
                    recoveryEscape = false
                    cursor += 1
                    continue
                }
            }
            if units[cursor] == 0x22 {
                let result = try jsonStringEnd(startingAt: cursor)
                if result.isValid { try append(.string, from: cursor, to: result.end) }
                recoveringMalformedString = result.needsRecovery
                recoveryEscape = false
                cursor = result.end
                continue
            }
            if isASCIIDigit(units[cursor])
                || (units[cursor] == 0x2D
                    && cursor + 1 < units.count
                    && isASCIIDigit(units[cursor + 1]))
            {
                let result = try jsonNumberEnd(startingAt: cursor)
                guard jsonNumberCanStart(at: cursor) else {
                    cursor = result.end
                    continue
                }
                if result.isValid { try append(.number, from: cursor, to: result.end) }
                cursor = result.end
                continue
            }
            if let end = jsonLiteralEnd(startingAt: cursor) {
                try append(.literal, from: cursor, to: end)
                cursor = end
                continue
            }
            cursor += 1
        }
    }

    private mutating func scanMarkdown() throws {
        try prepareMarkdownMetadata()
        try SyntaxHighlighter.checkpoint(.markdownEmission)
        while cursor < units.count {
            try consumeWork()
            if isLineStart(cursor) {
                let markerStart = markdownMarkerStart(forLineAt: cursor)
                if let end = try markdownFenceEnd(startingAt: markerStart) {
                    try append(.code, from: markerStart, to: end)
                    cursor = end
                    continue
                }
                if let end = try markdownHeadingEnd(startingAt: markerStart) {
                    try append(.heading, from: markerStart, to: end)
                    cursor = end
                    continue
                }
            }

            if units[cursor] == 0x5C,
                cursor + 1 < units.count
            {
                cursor += 2
                continue
            }
            if units[cursor] == 0x60 {
                let delimiterLength = try repeatedUnitCount(0x60, startingAt: cursor)
                if let end = markdownCodeSpanEnd(startingAt: cursor) {
                    try append(.code, from: cursor, to: end)
                    cursor = end
                } else {
                    cursor += delimiterLength
                }
                continue
            }
            if units[cursor] == 0x5B
                || (units[cursor] == 0x21
                    && cursor + 1 < units.count
                    && units[cursor + 1] == 0x5B)
            {
                let result = markdownLinkEnd(startingAt: cursor)
                if let end = result {
                    try append(.link, from: cursor, to: end)
                    cursor = end
                } else {
                    cursor += 1
                }
                continue
            }
            if units[cursor] == 0x2A || units[cursor] == 0x5F {
                let delimiterLength = try repeatedUnitCount(units[cursor], startingAt: cursor)
                let delimiterEnd = cursor + delimiterLength
                var tokenStart: Int?
                var candidate = cursor
                while candidate < delimiterEnd {
                    try consumeWork()
                    if markdownEmphasisEnd(startingAt: candidate) != nil {
                        tokenStart = candidate
                        break
                    }
                    candidate += 1
                }
                if let tokenStart, let end = markdownEmphasisEnd(startingAt: tokenStart) {
                    try append(.emphasis, from: tokenStart, to: end)
                    cursor = end
                } else {
                    cursor = delimiterEnd
                }
                continue
            }
            cursor += 1
        }
    }

    private mutating func codeLineCommentEnd(startingAt start: Int) throws -> Int {
        var index = start
        while index < units.count {
            try consumeWork()
            guard isLineBreak(units[index]) else {
                index += 1
                continue
            }
            guard language == .cLike else {
                return index
            }
            var spliceStart = index
            while spliceStart > start, isCLineSpliceWhitespace(units[spliceStart - 1]) {
                try consumeWork()
                spliceStart -= 1
            }
            guard spliceStart > start, units[spliceStart - 1] == 0x5C else { return index }
            index = try nextLineStart(afterLineContaining: index)
        }
        return units.count
    }

    private mutating func cLikeCommentOpening(
        startingAt start: Int
    ) throws -> (contentStart: Int, isBlock: Bool)? {
        guard units[start] == 0x2F else { return nil }
        var second = start + 1
        while let spliceEnd = try cLineSpliceEnd(startingAt: second) {
            while second < spliceEnd {
                try consumeWork()
                second += 1
            }
        }
        guard second < units.count else { return nil }
        if units[second] == 0x2F { return (second + 1, false) }
        if units[second] == 0x2A { return (second + 1, true) }
        return nil
    }

    private mutating func cLineSpliceEnd(startingAt start: Int) throws -> Int? {
        guard start + 1 < units.count, units[start] == 0x5C else { return nil }
        try consumeWork()
        var lineBreak = start + 1
        while lineBreak < units.count, isCLineSpliceWhitespace(units[lineBreak]) {
            try consumeWork()
            lineBreak += 1
        }
        guard lineBreak < units.count else { return nil }
        if units[lineBreak] == 0x0A { return lineBreak + 1 }
        if units[lineBreak] == 0x0D {
            return lineBreak + 1 < units.count && units[lineBreak + 1] == 0x0A
                ? lineBreak + 2
                : lineBreak + 1
        }
        return nil
    }

    private mutating func cLineSplicesEnd(startingAt start: Int) throws -> Int? {
        guard var end = try cLineSpliceEnd(startingAt: start) else { return nil }
        while let next = try cLineSpliceEnd(startingAt: end) { end = next }
        return end
    }

    private func isCLineSpliceWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x09 || unit == 0x0B || unit == 0x0C || unit == 0x20
    }

    private mutating func blockCommentEnd(contentStartingAt start: Int) throws -> Int {
        var index = start
        var depth = 1
        while index < units.count {
            try consumeWork()
            if language == .swift, has(0x2F, 0x2A, at: index) {
                depth += 1
                index += 2
            } else if has(0x2A, 0x2F, at: index) {
                depth -= 1
                index += 2
                if depth == 0 { return index }
            } else if language == .cLike,
                units[index] == 0x2A
            {
                var slash = index + 1
                while let spliceEnd = try cLineSpliceEnd(startingAt: slash) {
                    try consumeWork(spliceEnd - slash)
                    slash = spliceEnd
                }
                if slash < units.count, units[slash] == 0x2F { return slash + 1 }
                index += 1
            } else {
                index += 1
            }
        }
        return units.count
    }

    private mutating func swiftStringEnd(
        quoteStart: Int,
        hashCount: Int,
        nesting: Int
    ) throws -> Int {
        guard nesting <= 128 else {
            throw SyntaxHighlightingError.workLimitExceeded(
                maximumWorkUnits: maximumWorkUnits
            )
        }
        let delimiterLength = swiftStringDelimiterLength(quoteStart: quoteStart)
        var index = quoteStart + delimiterLength
        while index < units.count {
            try consumeWork()
            if try hasRepeatedUnit(0x22, count: delimiterLength, at: index) {
                let hashStart = index + delimiterLength
                var hashEnd = hashStart
                while hashEnd < units.count,
                    hashEnd - hashStart < hashCount,
                    units[hashEnd] == 0x23
                {
                    try consumeWork()
                    hashEnd += 1
                }
                if hashEnd - hashStart == hashCount { return hashEnd }
                index = hashEnd
                continue
            }
            if delimiterLength == 1, isLineBreak(units[index]) { return index }
            if units[index] == 0x5C {
                let hashStart = index + 1
                var hashEnd = hashStart
                while hashEnd < units.count,
                    hashEnd - hashStart < hashCount,
                    units[hashEnd] == 0x23
                {
                    try consumeWork()
                    hashEnd += 1
                }
                guard hashEnd - hashStart == hashCount else {
                    index = hashEnd
                    continue
                }
                let escapedStart = hashEnd
                if escapedStart < units.count, units[escapedStart] == 0x28 {
                    index = try swiftInterpolationEnd(
                        startingAt: escapedStart + 1,
                        nesting: nesting + 1,
                        allowsLineBreaks: delimiterLength == 3
                    )
                } else if escapedStart < units.count {
                    if delimiterLength == 1, isLineBreak(units[escapedStart]) { return escapedStart }
                    index = escapedStart + scalarLength(at: escapedStart)
                } else {
                    index = escapedStart
                }
                continue
            }
            index += scalarLength(at: index)
        }
        return units.count
    }

    private func swiftStringDelimiterLength(quoteStart: Int) -> Int {
        guard hasSequence([0x22, 0x22, 0x22], at: quoteStart) else { return 1 }
        let contentStart = quoteStart + 3
        guard contentStart < units.count, isLineBreak(units[contentStart]) else { return 1 }
        return 3
    }

    private mutating func swiftInterpolationEnd(
        startingAt start: Int,
        nesting: Int,
        allowsLineBreaks: Bool
    ) throws -> Int {
        var outerContext = swiftContext
        swiftContext = SwiftLexicalContext()
        defer {
            metadataEntries -= swiftContext.failedRawRegexUntilByHashCount.count
            swiftContext = outerContext
        }

        var index = start
        var depth = 1
        while index < units.count {
            try consumeWork()
            if !allowsLineBreaks, isLineBreak(units[index]) {
                outerContext.commentTriviaEnd = index
                outerContext.regexContextBeforeComment = true
                return index
            }
            if units[index] == 0x2F,
                let end = try swiftRegexEnd(startingAt: index, nesting: nesting)
            {
                index = end
                continue
            }
            if has(0x2F, 0x2F, at: index) {
                let commentStart = index
                index = try codeLineCommentEnd(startingAt: index + 2)
                try rememberSwiftCommentContext(start: commentStart, end: index)
                continue
            }
            if has(0x2F, 0x2A, at: index) {
                let commentStart = index
                index = try blockCommentEnd(contentStartingAt: index + 2)
                try rememberSwiftCommentContext(start: commentStart, end: index)
                continue
            }
            invalidateSwiftCommentContextIfNeeded(at: index)
            if units[index] == 0x23 {
                let hashCount = try repeatedUnitCount(0x23, startingAt: index)
                let quoteStart = index + hashCount
                if quoteStart < units.count,
                    units[quoteStart] == 0x2F,
                    let end = try swiftRegexEnd(
                        openingSlash: quoteStart,
                        hashCount: hashCount,
                        nesting: nesting
                    )
                {
                    index = end
                } else if quoteStart < units.count, units[quoteStart] == 0x22 {
                    index = try swiftStringEnd(
                        quoteStart: quoteStart,
                        hashCount: hashCount,
                        nesting: nesting
                    )
                } else {
                    index = quoteStart
                }
                continue
            }
            if units[index] == 0x22 {
                index = try swiftStringEnd(
                    quoteStart: index,
                    hashCount: 0,
                    nesting: nesting
                )
                continue
            }
            if units[index] == 0x28 {
                depth += 1
            } else if units[index] == 0x29 {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
            index += scalarLength(at: index)
        }
        return units.count
    }

    private mutating func swiftRegexEnd(startingAt start: Int, nesting: Int) throws -> Int? {
        if let recoveryStart = swiftContext.bareRegexRecoveryStart {
            guard start >= recoveryStart else { return nil }
            swiftContext.bareRegexRecoveryStart = nil
        }
        guard units[start] == 0x2F,
            try swiftRegexCanStart(at: start),
            start + 1 < units.count,
            units[start + 1] != 0x20,
            units[start + 1] != 0x09,
            units[start + 1] != 0x2F,
            units[start + 1] != 0x2A
        else { return nil }
        return try swiftRegexEnd(openingSlash: start, hashCount: 0, nesting: nesting)
    }

    private mutating func swiftRegexEnd(
        openingSlash: Int,
        hashCount: Int,
        nesting: Int
    ) throws -> Int? {
        guard
            hashCount == 0
                ? openingSlash >= swiftContext.failedBareRegexUntil
                : openingSlash >= swiftContext.failedRawRegexUntilByHashCount[hashCount, default: 0]
        else { return nil }
        if hashCount > 0,
            openingSlash < swiftContext.failedRawRegexUntilForHashCountsAtLeast,
            hashCount >= swiftContext.failedRawRegexMinimumHashCount
        {
            return nil
        }
        guard nesting <= 128 else {
            throw SyntaxHighlightingError.workLimitExceeded(
                maximumWorkUnits: maximumWorkUnits
            )
        }
        var index = openingSlash + 1
        var characterClassDepth = 0
        var maximumClosingHashRun = 0
        var traversedInterpolation = false
        var sawIgnoredClosingDelimiter = false
        var bareRecoverySlash: Int?
        var bareRecoveryClassDepth = 0
        var earliestBareRecoverySlash: Int?
        var lastIgnoredBareSlash: Int?
        while index < units.count {
            try consumeWork()
            if units[index] == 0x5C {
                let hashStart = index + 1
                var hashEnd = hashStart
                while hashEnd < units.count,
                    hashEnd - hashStart < hashCount,
                    units[hashEnd] == 0x23
                {
                    try consumeWork()
                    hashEnd += 1
                }
                if hashEnd - hashStart == hashCount,
                    hashEnd < units.count,
                    units[hashEnd] == 0x28
                {
                    traversedInterpolation = true
                    index = try swiftInterpolationEnd(
                        startingAt: hashEnd + 1,
                        nesting: nesting + 1,
                        allowsLineBreaks: hashCount > 0
                    )
                } else {
                    let escapedIndex = index + 1
                    if hashCount == 0,
                        escapedIndex < units.count,
                        isLineBreak(units[escapedIndex])
                    {
                        rememberSwiftBareRegexFailure(
                            endingAt: escapedIndex,
                            characterClassDepth: characterClassDepth,
                            recovery: earliestBareRecoverySlash ?? lastIgnoredBareSlash,
                            nesting: nesting
                        )
                        return nil
                    }
                    index += 1
                    if index < units.count {
                        index += scalarLength(at: index)
                    }
                }
                continue
            }
            if units[index] == 0x5B {
                characterClassDepth += 1
                if bareRecoverySlash != nil { bareRecoveryClassDepth += 1 }
                index += 1
                continue
            }
            if units[index] == 0x5D, characterClassDepth > 0 {
                characterClassDepth -= 1
                if bareRecoveryClassDepth > 0 { bareRecoveryClassDepth -= 1 }
                index += 1
                continue
            }
            if units[index] == 0x2F {
                let hashStart = index + 1
                if hashCount == 0, characterClassDepth == 0 {
                    guard try swiftBareRegexCanClose(at: index) else {
                        rememberSwiftBareRegexFailure(
                            endingAt: hashStart,
                            characterClassDepth: characterClassDepth,
                            recovery: earliestBareRecoverySlash ?? lastIgnoredBareSlash,
                            nesting: nesting
                        )
                        return nil
                    }
                    return hashStart
                }
                if hashCount == 0, characterClassDepth > 0 {
                    lastIgnoredBareSlash = index
                    if bareRecoverySlash == nil {
                        bareRecoverySlash = index
                    } else if bareRecoveryClassDepth == 0, earliestBareRecoverySlash == nil {
                        earliestBareRecoverySlash = bareRecoverySlash
                    }
                }
                let closingHashRun = try repeatedUnitPrefixLength(
                    0x23,
                    maximum: hashCount,
                    startingAt: hashStart
                )
                maximumClosingHashRun = max(maximumClosingHashRun, closingHashRun)
                if characterClassDepth == 0, closingHashRun == hashCount {
                    return hashStart + hashCount
                }
                if characterClassDepth > 0, closingHashRun == hashCount {
                    sawIgnoredClosingDelimiter = true
                }
            }
            if hashCount == 0, isLineBreak(units[index]) {
                rememberSwiftBareRegexFailure(
                    endingAt: index,
                    characterClassDepth: characterClassDepth,
                    recovery: earliestBareRecoverySlash ?? lastIgnoredBareSlash,
                    nesting: nesting
                )
                return nil
            }
            index += scalarLength(at: index)
        }
        if hashCount == 0 {
            rememberSwiftBareRegexFailure(
                endingAt: index,
                characterClassDepth: characterClassDepth,
                recovery: earliestBareRecoverySlash ?? lastIgnoredBareSlash,
                nesting: nesting
            )
        } else {
            if !traversedInterpolation, maximumClosingHashRun < hashCount {
                swiftContext.failedRawRegexMinimumHashCount = min(
                    swiftContext.failedRawRegexMinimumHashCount,
                    maximumClosingHashRun + 1
                )
                swiftContext.failedRawRegexUntilForHashCountsAtLeast = max(
                    swiftContext.failedRawRegexUntilForHashCountsAtLeast,
                    index
                )
            }
            if characterClassDepth == 0,
                !traversedInterpolation,
                !sawIgnoredClosingDelimiter
            {
                if swiftContext.failedRawRegexUntilByHashCount[hashCount] == nil {
                    try retainMetadataEntry()
                }
                swiftContext.failedRawRegexUntilByHashCount[hashCount] = max(
                    swiftContext.failedRawRegexUntilByHashCount[hashCount, default: 0],
                    index
                )
            }
        }
        return nil
    }

    private mutating func rememberSwiftBareRegexFailure(
        endingAt end: Int,
        characterClassDepth: Int,
        recovery: Int?,
        nesting _: Int
    ) {
        if characterClassDepth == 0 {
            swiftContext.failedBareRegexUntil = max(swiftContext.failedBareRegexUntil, end)
        } else {
            swiftContext.bareRegexRecoveryStart = recovery
        }
    }

    private mutating func swiftRegexCanStart(at start: Int) throws -> Bool {
        try swiftRegexCanStart(at: start, requiresSeparatingWhitespace: true)
    }

    private mutating func swiftRegexCanStart(
        at start: Int,
        requiresSeparatingWhitespace: Bool
    ) throws -> Bool {
        if swiftContext.commentTriviaEnd >= 0, swiftContext.commentTriviaEnd <= start {
            var trivia = swiftContext.commentTriviaEnd
            while trivia < start,
                units[trivia] == 0x20 || units[trivia] == 0x09 || isLineBreak(units[trivia])
            {
                try consumeWork()
                trivia += 1
            }
            if trivia == start { return swiftContext.regexContextBeforeComment }
            swiftContext.commentTriviaEnd = -1
        }
        var index = start
        var sawWhitespace = false
        while index > 0 {
            index -= 1
            let unit = units[index]
            if unit == 0x20 || unit == 0x09 || isLineBreak(unit) {
                try consumeWork()
                sawWhitespace = true
                continue
            }
            if [
                0x21, 0x25, 0x26, 0x28, 0x2A, 0x2B, 0x2C, 0x2D, 0x3A,
                0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x5B, 0x5E, 0x7B, 0x7C, 0x7E
            ].contains(unit) {
                return true
            }
            guard !requiresSeparatingWhitespace || sawWhitespace,
                isCodeIdentifierContinuation(at: index)
            else {
                return false
            }
            var wordStart = index
            while wordStart > 0,
                isCodeIdentifierContinuation(before: wordStart)
            {
                try consumeWork()
                wordStart -= 1
            }
            guard index - wordStart < 8 else { return false }
            let word = String(decoding: units[wordStart...index], as: UTF16.self)
            return [
                "await", "case", "else", "guard", "if", "in", "return", "switch",
                "throw", "try", "where", "while", "yield"
            ].contains(word)
        }
        return true
    }

    private mutating func swiftBareRegexCanClose(at slash: Int) throws -> Bool {
        guard slash > 0, units[slash - 1] == 0x20 || units[slash - 1] == 0x09 else {
            return true
        }
        var backslash = slash - 1
        var count = 0
        while backslash > 0, units[backslash - 1] == 0x5C {
            try consumeWork()
            count += 1
            backslash -= 1
        }
        return !count.isMultiple(of: 2)
    }

    private mutating func rememberSwiftCommentContext(start: Int, end: Int) throws {
        swiftContext.regexContextBeforeComment = try swiftRegexCanStart(
            at: start,
            requiresSeparatingWhitespace: false
        )
        swiftContext.commentTriviaEnd = end
    }

    private mutating func invalidateSwiftCommentContextIfNeeded(at index: Int) {
        guard swiftContext.commentTriviaEnd >= 0,
            index >= swiftContext.commentTriviaEnd,
            units[index] != 0x20,
            units[index] != 0x09,
            !isLineBreak(units[index])
        else { return }
        swiftContext.commentTriviaEnd = -1
    }

    private mutating func swiftEscapedIdentifierEnd(startingAt start: Int) throws -> Int? {
        var index = start + 1
        while index < units.count, !isLineBreak(units[index]) {
            try consumeWork()
            if units[index] == 0x60 { return index + 1 }
            index += scalarLength(at: index)
        }
        return nil
    }

    private mutating func cLikeQuotedStringStart(startingAt start: Int) throws -> Int? {
        if units[start] == 0x22 || units[start] == 0x27 { return start }
        guard start == 0 || !isCodeIdentifierContinuation(at: start - 1) else { return nil }
        for prefix in Self.cLikeStringPrefixes {
            if let prefixEnd = try cLikeSequenceEnd(prefix, startingAt: start) {
                let quoteStart = try cLineSplicesEnd(startingAt: prefixEnd) ?? prefixEnd
                if quoteStart > prefixEnd { try consumeWork(quoteStart - prefixEnd) }
                if quoteStart < units.count,
                    units[quoteStart] == 0x22 || units[quoteStart] == 0x27
                {
                    return quoteStart
                }
            }
        }
        return nil
    }

    private mutating func cxxRawStringEnd(startingAt start: Int) throws -> Int? {
        guard start == 0 || !isCodeIdentifierContinuation(at: start - 1) else { return nil }
        var delimiterStart: Int?
        for prefix in Self.cxxRawStringPrefixes {
            if let end = try cLikeSequenceEnd(prefix, startingAt: start) {
                delimiterStart = end
                break
            }
        }
        guard let delimiterStart else { return nil }
        var openParenthesis = delimiterStart
        while openParenthesis < units.count,
            openParenthesis - delimiterStart <= 16,
            units[openParenthesis] != 0x28
        {
            try consumeWork()
            let unit = units[openParenthesis]
            guard (0x21...0x7E).contains(unit),
                unit != 0x28,
                unit != 0x29,
                unit != 0x5C
            else { return nil }
            openParenthesis += 1
        }
        guard openParenthesis < units.count,
            units[openParenthesis] == 0x28,
            openParenthesis - delimiterStart <= 16
        else { return nil }

        var index = openParenthesis + 1
        while index < units.count {
            try consumeWork()
            if units[index] == 0x29,
                hasSequence(from: delimiterStart..<openParenthesis, at: index + 1),
                index + (openParenthesis - delimiterStart) + 1 < units.count,
                units[index + (openParenthesis - delimiterStart) + 1] == 0x22
            {
                return index + (openParenthesis - delimiterStart) + 2
            }
            index += scalarLength(at: index)
        }
        return units.count
    }

    private mutating func quotedStringEnd(
        startingAt start: Int,
        quote: UInt16,
        delimiterLength: Int,
        allowsEscapedNewlines: Bool,
        terminatesAtRawC0: Bool
    ) throws -> Int {
        var index = start + delimiterLength
        var escaped = false
        var previousWasBackslash = false
        while index < units.count {
            try consumeWork()
            if language == .cLike,
                let spliceEnd = try cLineSpliceEnd(startingAt: index)
            {
                try consumeWork(spliceEnd - index - 1)
                index = spliceEnd
                continue
            }
            if units[index] == 0x5C {
                escaped.toggle()
                previousWasBackslash = true
                index += 1
                continue
            }
            if isLineBreak(units[index]) {
                guard allowsEscapedNewlines, previousWasBackslash else { return index }
                escaped.toggle()
                previousWasBackslash = false
                index = try nextLineStart(afterLineContaining: index)
                continue
            }
            if terminatesAtRawC0, units[index] <= 0x1F { return index }
            if !escaped, try hasRepeatedUnit(quote, count: delimiterLength, at: index) {
                return index + delimiterLength
            }
            escaped = false
            previousWasBackslash = false
            index += scalarLength(at: index)
        }
        return units.count
    }

    private mutating func jsonStringEnd(startingAt start: Int) throws -> (
        end: Int,
        isValid: Bool,
        needsRecovery: Bool
    ) {
        var index = start + 1
        var isValid = true
        while index < units.count {
            try consumeWork()
            let unit = units[index]
            if unit == 0x22 { return (index + 1, isValid, false) }
            if unit <= 0x1F {
                return (index, false, !isLineBreak(unit))
            }
            guard unit == 0x5C else {
                index += scalarLength(at: index)
                continue
            }

            guard index + 1 < units.count else { return (units.count, false, false) }
            let escape = units[index + 1]
            if isLineBreak(escape) { return (index, false, false) }
            if [0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(escape) {
                try consumeWork()
                index += 2
                continue
            }
            if escape == 0x75 {
                var hexEnd = index + 2
                while hexEnd < units.count,
                    hexEnd < index + 6,
                    isASCIIHexDigit(units[hexEnd])
                {
                    try consumeWork()
                    hexEnd += 1
                }
                if hexEnd != index + 6 { isValid = false }
                index = hexEnd
                continue
            }
            isValid = false
            try consumeWork()
            index += 2
        }
        return (units.count, false, false)
    }

    private mutating func codeNumberEnd(startingAt start: Int) throws -> (
        end: Int,
        isValid: Bool
    ) {
        var index = start
        var isFloating = units[start] == 0x2E
        var isValid = true
        if let prefixEnd = try cLikeRadixPrefixEnd(
            startingAt: index,
            secondUnits: Self.hexadecimalPrefixUnits
        ) {
            index = prefixEnd
            let integerDigitsStart = index
            index = try codeDigitsEnd(startingAt: index, radix: 16)
            let hasIntegerDigit = index > integerDigitsStart
            var hasSignificandDigit = hasIntegerDigit
            index = try cLikeSplicedIndex(startingAt: index, followedBy: [0x2E])
            var hasFraction = false
            if index < units.count,
                units[index] == 0x2E,
                language == .cLike
                    || (index + 1 < units.count && isASCIIHexDigit(units[index + 1]))
            {
                hasFraction = true
                isFloating = true
                index += 1
                let fractionDigitsStart = index
                index = try codeDigitsEnd(startingAt: index, radix: 16)
                hasSignificandDigit = hasSignificandDigit || index > fractionDigitsStart
            }
            let exponentMarker = try cLikeSplicedIndex(
                startingAt: index,
                followedBy: Self.hexadecimalExponentUnits
            )
            let hasExponentMarker =
                exponentMarker < units.count
                && Self.hexadecimalExponentUnits.contains(units[exponentMarker])
            let exponent = try exponentEnd(
                startingAt: index,
                markers: Self.hexadecimalExponentUnits
            )
            let hasExponent = exponent != index
            isFloating = isFloating || hasExponent
            index = exponent
            isValid =
                hasSignificandDigit
                && (language != .swift || hasIntegerDigit)
                && (!hasExponentMarker || hasExponent)
                && (!hasFraction || hasExponent)
                && (language != .swift
                    || index >= units.count
                    || !isCodeIdentifierContinuation(at: index))
        } else if let prefixEnd = try cLikeRadixPrefixEnd(
            startingAt: index,
            secondUnits: Self.binaryPrefixUnits
        ) {
            index = prefixEnd
            let digitsStart = index
            index = try codeDigitsEnd(startingAt: index, radix: 2)
            isValid =
                index > digitsStart
                && (language != .swift
                    || index >= units.count
                    || !isCodeIdentifierContinuation(at: index))
        } else if language == .swift,
            let prefixEnd = try cLikeRadixPrefixEnd(
                startingAt: index,
                secondUnits: Self.octalPrefixUnits
            )
        {
            index = prefixEnd
            let digitsStart = index
            index = try codeDigitsEnd(startingAt: index, radix: 8)
            isValid =
                index > digitsStart
                && (index >= units.count || !isCodeIdentifierContinuation(at: index))
        } else {
            index = try codeDigitsEnd(startingAt: index, radix: 10)
            index = try cLikeSplicedIndex(startingAt: index, followedBy: [0x2E])
            if index < units.count,
                units[index] == 0x2E,
                language == .cLike || (index + 1 < units.count && isASCIIDigit(units[index + 1]))
            {
                isFloating = true
                index += 1
                index = try codeDigitsEnd(startingAt: index, radix: 10)
            }
            let exponentStart = index
            let hasExponentMarker =
                exponentStart < units.count
                && Self.decimalExponentUnits.contains(units[exponentStart])
            let exponent = try exponentEnd(
                startingAt: index,
                markers: Self.decimalExponentUnits
            )
            let hasExponent = exponent != exponentStart
            isFloating = isFloating || hasExponent
            if language == .swift, hasExponentMarker, !hasExponent {
                isValid = false
                index = try malformedSwiftNumberEnd(startingAt: exponentStart)
            } else {
                index = exponent
            }
            if language == .cLike,
                units[start] == 0x30,
                !isFloating,
                try containsCInvalidOctalDigit(from: start, to: index)
            {
                isValid = false
            }
            if language == .swift,
                index < units.count,
                isCodeIdentifierContinuation(at: index)
            {
                isValid = false
            }
        }

        if language == .cLike {
            let suffix = try cxxNumberSuffixEnd(startingAt: index, isFloating: isFloating)
            index = suffix.end
            if isUnicodeIdentifierContinuation(at: suffix.boundary) {
                index = suffix.boundary
            }
            let dot = index == suffix.end ? suffix.boundary : index
            if dot < units.count, units[dot] == 0x2E {
                let member = try cLikeSplicedIndex(
                    startingAt: dot + 1,
                    followedBy: Self.asciiIdentifierContinuationUnits
                )
                if isUnicodeIdentifierContinuation(at: member) { index = member }
            }
        }
        return (index, isValid)
    }

    private mutating func cLikeMalformedPreprocessingNumberEnd(
        startingAt start: Int
    ) throws -> Int? {
        var index = start
        var previousUnit: UInt16? = start > 0 ? units[start - 1] : nil
        var consumedTail = false

        while index < units.count {
            let logicalIndex = try cLineSplicesEnd(startingAt: index) ?? index
            guard logicalIndex < units.count else { break }
            let unit = units[logicalIndex]

            if isUnicodeIdentifierContinuation(at: logicalIndex) {
                if logicalIndex > index { try consumeWork(logicalIndex - index) }
                try consumeWork()
                index = logicalIndex + scalarLength(at: logicalIndex)
                previousUnit = unit
                consumedTail = true
                continue
            }
            if unit == 0x27 {
                let next = logicalIndex + 1
                let following = try cLineSplicesEnd(startingAt: next) ?? next
                guard following < units.count,
                    isUnicodeIdentifierContinuation(at: following)
                else { break }
                if logicalIndex > index { try consumeWork(logicalIndex - index) }
                try consumeWork()
                index = next
                previousUnit = unit
                consumedTail = true
                continue
            }
            if unit == 0x2E {
                if logicalIndex > index { try consumeWork(logicalIndex - index) }
                try consumeWork()
                index = logicalIndex + 1
                previousUnit = unit
                consumedTail = true
                continue
            }
            if unit == 0x2B || unit == 0x2D,
                let priorUnit = previousUnit,
                [0x45, 0x50, 0x65, 0x70].contains(priorUnit)
            {
                if logicalIndex > index { try consumeWork(logicalIndex - index) }
                try consumeWork()
                index = logicalIndex + 1
                previousUnit = unit
                consumedTail = true
                continue
            }
            break
        }
        return consumedTail ? index : nil
    }

    private mutating func malformedSwiftNumberEnd(startingAt start: Int) throws -> Int {
        var index = start
        var previousUnit: UInt16?
        while index < units.count {
            let unit = units[index]
            guard
                isCodeIdentifierContinuation(at: index)
                    || unit == 0x2E
                    || ((unit == 0x2B || unit == 0x2D)
                        && previousUnit.map { [0x45, 0x50, 0x65, 0x70].contains($0) } == true)
            else { break }
            try consumeWork()
            index += scalarLength(at: index)
            previousUnit = unit
        }
        return index
    }

    private mutating func containsCInvalidOctalDigit(from start: Int, to end: Int) throws -> Bool {
        var index = start
        while index < end {
            if let spliceEnd = try cLineSplicesEnd(startingAt: index) {
                try consumeWork(spliceEnd - index)
                index = spliceEnd
                continue
            }
            try consumeWork()
            if units[index] == 0x38 || units[index] == 0x39 { return true }
            index += scalarLength(at: index)
        }
        return false
    }

    private mutating func cLikeRadixPrefixEnd(
        startingAt start: Int,
        secondUnits: [UInt16]
    ) throws -> Int? {
        guard start < units.count, units[start] == 0x30 else { return nil }
        let second =
            language == .cLike
            ? try cLikeSplicedIndex(startingAt: start + 1, followedBy: secondUnits)
            : start + 1
        guard second < units.count,
            secondUnits.contains(units[second]),
            language != .swift || (0x61...0x7A).contains(units[second])
        else { return nil }
        return second + 1
    }

    private mutating func cLikeSplicedIndex(
        startingAt start: Int,
        followedBy acceptedUnits: [UInt16]
    ) throws -> Int {
        guard language == .cLike,
            let end = try cLineSplicesEnd(startingAt: start),
            end < units.count,
            acceptedUnits.contains(units[end])
        else { return start }
        try consumeWork(end - start)
        return end
    }

    private mutating func cxxNumberSuffixEnd(
        startingAt start: Int,
        isFloating: Bool
    ) throws -> (end: Int, boundary: Int) {
        let suffixes =
            isFloating
            ? Self.cxxFloatingNumberSuffixes
            : Self.cxxIntegerNumberSuffixes
        cxxSuffixLogicalUnits.removeAll(keepingCapacity: true)
        cxxSuffixPhysicalEnds.removeAll(keepingCapacity: true)
        cxxSuffixLogicalStarts.removeAll(keepingCapacity: true)
        var index = start
        while cxxSuffixLogicalUnits.count < Self.maximumCxxNumberSuffixLength {
            let logicalStart = try cLineSplicesEnd(startingAt: index) ?? index
            if logicalStart > index { try consumeWork(logicalStart - index) }
            cxxSuffixLogicalStarts.append(logicalStart)
            guard logicalStart < units.count,
                Self.cxxNumberSuffixUnits.contains(units[logicalStart])
            else {
                break
            }
            try consumeWork()
            cxxSuffixLogicalUnits.append(units[logicalStart])
            cxxSuffixPhysicalEnds.append(logicalStart + 1)
            index = logicalStart + 1
        }
        if cxxSuffixLogicalStarts.count == cxxSuffixLogicalUnits.count {
            let logicalStart = try cLineSplicesEnd(startingAt: index) ?? index
            if logicalStart > index { try consumeWork(logicalStart - index) }
            cxxSuffixLogicalStarts.append(logicalStart)
        }
        for suffix in suffixes {
            guard suffix.count <= cxxSuffixLogicalUnits.count,
                cxxSuffixLogicalUnits.starts(with: suffix),
                !isUnicodeIdentifierContinuation(
                    at: cxxSuffixLogicalStarts[suffix.count]
                )
            else { continue }
            return (
                cxxSuffixPhysicalEnds[suffix.count - 1],
                cxxSuffixLogicalStarts[suffix.count]
            )
        }
        return (start, cxxSuffixLogicalStarts[0])
    }

    private mutating func cLikeSequenceEnd(
        _ sequence: String,
        startingAt start: Int
    ) throws -> Int? {
        try cLikeSequenceEnd(Array(sequence.utf16), startingAt: start)
    }

    private mutating func cLikeSequenceEnd(
        _ sequence: [UInt16],
        startingAt start: Int
    ) throws -> Int? {
        var index = start
        for (offset, expected) in sequence.enumerated() {
            if offset > 0, let spliceEnd = try cLineSplicesEnd(startingAt: index) {
                try consumeWork(spliceEnd - index)
                index = spliceEnd
            }
            guard index < units.count, units[index] == expected else { return nil }
            try consumeWork()
            index += 1
        }
        return index
    }

    private mutating func codeDigitsEnd(startingAt start: Int, radix: Int) throws -> Int {
        var index = start
        var sawDigit = false
        while index < units.count {
            if isCodeDigit(units[index], radix: radix) {
                sawDigit = true
            } else if language == .cLike,
                sawDigit,
                let digitIndex = try cLikeDigitAfterSeparator(startingAt: index, radix: radix)
            {
                try consumeWork(digitIndex - index)
                index = digitIndex
                continue
            } else if !isValidDigitSeparator(at: index, radix: radix, afterDigit: sawDigit) {
                guard language == .cLike,
                    let spliceEnd = try cLineSplicesEnd(startingAt: index),
                    spliceEnd < units.count,
                    try isCodeDigit(units[spliceEnd], radix: radix)
                        || cLikeDigitAfterSeparator(
                            startingAt: spliceEnd,
                            radix: radix
                        ) != nil
                else { break }
                try consumeWork(spliceEnd - index)
                index = spliceEnd
                continue
            }
            try consumeWork()
            index += 1
        }
        return index
    }

    private mutating func cLikeDigitAfterSeparator(startingAt start: Int, radix: Int) throws -> Int? {
        guard start < units.count, units[start] == 0x27 else { return nil }
        let next = start + 1
        let digit = try cLineSplicesEnd(startingAt: next) ?? next
        guard digit < units.count, isCodeDigit(units[digit], radix: radix) else { return nil }
        return digit
    }

    private mutating func exponentEnd(startingAt start: Int, markers: [UInt16]) throws -> Int {
        let marker = try cLikeSplicedIndex(startingAt: start, followedBy: markers)
        guard marker < units.count, markers.contains(units[marker]) else { return start }
        var index = marker + 1
        index = try cLikeSplicedIndex(startingAt: index, followedBy: Self.exponentSignUnits)
        if index < units.count, units[index] == 0x2B || units[index] == 0x2D {
            index += 1
        }
        index = try cLikeSplicedIndex(
            startingAt: index,
            followedBy: Self.asciiDigits
        )
        let digitsStart = index
        index = try codeDigitsEnd(startingAt: index, radix: 10)
        return index > digitsStart ? index : start
    }

    private mutating func jsonNumberEnd(startingAt start: Int) throws -> (
        end: Int,
        isValid: Bool
    ) {
        var index = start
        if units[index] == 0x2D { index += 1 }
        let integerStart = index
        guard index < units.count, isASCIIDigit(units[index]) else { return (index, false) }
        index += 1
        if units[integerStart] == 0x30, index < units.count, isASCIIDigit(units[index]) {
            return (try malformedJSONNumberEnd(startingAt: index), false)
        }
        while index < units.count, isASCIIDigit(units[index]) {
            try consumeWork()
            index += 1
        }
        if index < units.count, units[index] == 0x2E {
            guard index + 1 < units.count, isASCIIDigit(units[index + 1]) else {
                return (try malformedJSONNumberEnd(startingAt: index), false)
            }
            index += 1
            while index < units.count, isASCIIDigit(units[index]) {
                try consumeWork()
                index += 1
            }
        }
        let exponentMarker = index
        index = try exponentEnd(startingAt: index, markers: Self.decimalExponentUnits)
        if exponentMarker < units.count,
            Self.decimalExponentUnits.contains(units[exponentMarker]),
            index == exponentMarker
        {
            return (try malformedJSONNumberEnd(startingAt: exponentMarker), false)
        }
        if index < units.count, units[index] == 0x2E {
            return (try malformedJSONNumberEnd(startingAt: index), false)
        }
        guard !isUnicodeIdentifierContinuation(at: index) else {
            while index < units.count, isUnicodeIdentifierContinuation(at: index) {
                try consumeWork()
                index += scalarLength(at: index)
            }
            return (index, false)
        }
        return (index, true)
    }

    private func jsonNumberCanStart(at start: Int) -> Bool {
        guard !isUnicodeIdentifierContinuation(before: start) else { return false }
        guard start > 0 else { return true }
        let previous = units[start - 1]
        return previous == 0x20
            || previous == 0x09
            || isLineBreak(previous)
            || previous == 0x5B
            || previous == 0x7B
            || previous == 0x2C
            || previous == 0x3A
    }

    private mutating func malformedJSONNumberEnd(startingAt start: Int) throws -> Int {
        var index = start
        while index < units.count {
            let unit = units[index]
            guard
                isASCIIDigit(unit)
                    || [0x2B, 0x2D, 0x2E, 0x45, 0x65].contains(unit)
                    || isUnicodeIdentifierContinuation(at: index)
            else { break }
            try consumeWork()
            index += scalarLength(at: index)
        }
        return index
    }

    private func jsonLiteralEnd(startingAt start: Int) -> Int? {
        for literalUnits in Self.jsonLiteralUnits {
            let end = start + literalUnits.count
            guard hasSequence(literalUnits, at: start),
                !isUnicodeIdentifierContinuation(before: start),
                !isUnicodeIdentifierContinuation(at: end)
            else { continue }
            return end
        }
        return nil
    }

    private func markdownMarkerStart(forLineAt start: Int) -> Int {
        var index = start
        var spaces = 0
        while index < units.count, units[index] == 0x20, spaces < 3 {
            index += 1
            spaces += 1
        }
        return index
    }

    private mutating func markdownFenceEnd(startingAt start: Int) throws -> Int? {
        guard start < units.count, units[start] == 0x60 || units[start] == 0x7E else {
            return nil
        }
        let marker = units[start]
        let delimiterLength = try repeatedUnitCount(marker, startingAt: start)
        guard delimiterLength >= 3 else { return nil }
        let openingLineEnd = try lineEnd(startingAt: start + delimiterLength)
        if marker == 0x60 {
            var infoIndex = start + delimiterLength
            while infoIndex < openingLineEnd {
                try consumeWork()
                if units[infoIndex] == 0x60 { return nil }
                infoIndex += 1
            }
        }

        var lineStart = try nextLineStart(afterLineContaining: start)
        while lineStart < units.count {
            try consumeWork()
            let candidate = markdownMarkerStart(forLineAt: lineStart)
            if candidate < units.count,
                units[candidate] == marker,
                try repeatedUnitCount(marker, startingAt: candidate) >= delimiterLength
            {
                var trailing = candidate + (try repeatedUnitCount(marker, startingAt: candidate))
                let end = try lineEnd(startingAt: trailing)
                while trailing < end, units[trailing] == 0x20 || units[trailing] == 0x09 {
                    try consumeWork()
                    trailing += 1
                }
                if trailing == end { return end }
            }
            lineStart = try nextLineStart(afterLineContaining: lineStart)
        }
        return units.count
    }

    private mutating func prepareMarkdownMetadata() throws {
        try prepareMarkdownCodeSpans()
        try SyntaxHighlighter.checkpoint(.markdownInlineMetadata)
        var bracketStack: [MarkdownBracket] = []
        var destination: MarkdownDestination?
        var delimiterStacks: [UInt16: [MarkdownDelimiterRun]] = [:]
        var completedLinkCount = 0
        var failedDestinationStarts: Set<Int> = []
        var failedDestinationOrder: [Int] = []
        var failedDestinationHead = 0
        var unmatchedDestinationParentheses: [Int] = []
        var index = 0
        var lineStart = true
        var lineHasContent = false
        while index < units.count || destination != nil {
            if index == units.count, let failedDestination = destination {
                metadataEntries -= 1
                try restoreMarkdownDeferredEmphasis(
                    failedDestination.deferredEmphasis,
                    bracketStack: &bracketStack,
                    delimiterStacks: &delimiterStacks
                )
                try transferUnmatchedDestinationParentheses(
                    &unmatchedDestinationParentheses,
                    to: &failedDestinationStarts,
                    order: &failedDestinationOrder
                )
                destination = nil
                index = failedDestination.openingParenthesis + 1
                lineStart = failedDestination.openingLineStart
                lineHasContent = failedDestination.openingLineHasContent
                continue
            }
            try consumeWork()
            try reclaimFailedDestinationStarts(
                through: index,
                starts: &failedDestinationStarts,
                order: &failedDestinationOrder,
                head: &failedDestinationHead
            )
            if var currentDestination = destination {
                if currentDestination.crossedSoftBreak,
                    isLineStart(index),
                    try markdownInterruptingBlockStarts(at: index)
                {
                    metadataEntries -= 1
                    try restoreMarkdownDeferredEmphasis(
                        currentDestination.deferredEmphasis,
                        bracketStack: &bracketStack,
                        delimiterStacks: &delimiterStacks
                    )
                    try transferUnmatchedDestinationParentheses(
                        &unmatchedDestinationParentheses,
                        to: &failedDestinationStarts,
                        order: &failedDestinationOrder
                    )
                    destination = nil
                    index = currentDestination.openingParenthesis + 1
                    lineStart = currentDestination.openingLineStart
                    lineHasContent = currentDestination.openingLineHasContent
                    continue
                }
                let previousParenthesisDepth = currentDestination.parenthesisDepth
                switch markdownDestinationStep(&currentDestination, at: index) {
                case .advance:
                    if currentDestination.parenthesisDepth > previousParenthesisDepth {
                        try retainMetadataEntry()
                        unmatchedDestinationParentheses.append(index)
                    } else if currentDestination.parenthesisDepth < previousParenthesisDepth {
                        unmatchedDestinationParentheses.removeLast()
                        metadataEntries -= 1
                    }
                    destination = currentDestination
                    if isLineBreak(units[index]) {
                        if !lineHasContent {
                            try restoreMarkdownBrackets(
                                &bracketStack,
                                delimiterStacks: &delimiterStacks
                            )
                            metadataEntries -= delimiterStacks.values.reduce(0) { $0 + $1.count }
                            delimiterStacks.removeAll(keepingCapacity: true)
                        }
                        index = try nextLineStart(afterLineContaining: index)
                        lineStart = true
                        lineHasContent = false
                    } else {
                        lineStart = false
                        if !isMarkdownWhitespace(units[index]) { lineHasContent = true }
                        index += scalarLength(at: index)
                    }
                    continue
                case .complete:
                    metadataEntries -= unmatchedDestinationParentheses.count
                    unmatchedDestinationParentheses.removeAll(keepingCapacity: true)
                    metadataEntries -= 1
                    metadataEntries -= currentDestination.deferredEmphasis.count
                    try discardCompletedMarkdownMetadata(
                        after: currentDestination.tokenStart,
                        through: index + 1
                    )
                    discardMarkdownDelimiters(
                        in: &delimiterStacks,
                        marker: 0x2A,
                        keeping: currentDestination.asteriskDelimiterFloor
                    )
                    discardMarkdownDelimiters(
                        in: &delimiterStacks,
                        marker: 0x5F,
                        keeping: currentDestination.underscoreDelimiterFloor
                    )
                    try retainMetadataEntry()
                    markdownLinkEnds[currentDestination.tokenStart] = index + 1
                    markdownLinkStartOrder.append(currentDestination.tokenStart)
                    if !currentDestination.isImage { completedLinkCount += 1 }
                    destination = nil
                    lineStart = false
                    lineHasContent = true
                    index += 1
                    continue
                case .invalid:
                    metadataEntries -= 1
                    try restoreMarkdownDeferredEmphasis(
                        currentDestination.deferredEmphasis,
                        bracketStack: &bracketStack,
                        delimiterStacks: &delimiterStacks
                    )
                    try transferUnmatchedDestinationParentheses(
                        &unmatchedDestinationParentheses,
                        to: &failedDestinationStarts,
                        order: &failedDestinationOrder
                    )
                    destination = nil
                    index = currentDestination.openingParenthesis + 1
                    lineStart = currentDestination.openingLineStart
                    lineHasContent = currentDestination.openingLineHasContent
                    continue
                }
            }
            if isLineBreak(units[index]) {
                if !lineHasContent {
                    try restoreMarkdownBrackets(
                        &bracketStack,
                        delimiterStacks: &delimiterStacks
                    )
                    metadataEntries -= delimiterStacks.values.reduce(0) { $0 + $1.count }
                    delimiterStacks.removeAll(keepingCapacity: true)
                }
                index = try nextLineStart(afterLineContaining: index)
                lineStart = true
                lineHasContent = false
                continue
            }
            if lineStart {
                let markerStart = markdownMarkerStart(forLineAt: index)
                if markerStart < units.count,
                    units[markerStart] == 0x60 || units[markerStart] == 0x7E
                {
                    let marker = units[markerStart]
                    let delimiterLength = try repeatedUnitCount(marker, startingAt: markerStart)
                    if delimiterLength >= 3 {
                        if let fenceEnd = try markdownFenceEnd(startingAt: markerStart) {
                            try restoreMarkdownBrackets(
                                &bracketStack,
                                delimiterStacks: &delimiterStacks
                            )
                            metadataEntries -= delimiterStacks.values.reduce(0) { $0 + $1.count }
                            delimiterStacks.removeAll(keepingCapacity: true)
                            index = fenceEnd
                            lineStart = true
                            lineHasContent = false
                            continue
                        }
                    }
                }
                if let headingEnd = try markdownHeadingEnd(startingAt: markerStart) {
                    try restoreMarkdownBrackets(
                        &bracketStack,
                        delimiterStacks: &delimiterStacks
                    )
                    metadataEntries -= delimiterStacks.values.reduce(0) { $0 + $1.count }
                    delimiterStacks.removeAll(keepingCapacity: true)
                    index = headingEnd
                    lineStart = false
                    continue
                }
                lineStart = false
            }
            if units[index] == 0x5C,
                index + 1 < units.count,
                units[index + 1] != 0x60
            {
                if isLineBreak(units[index + 1]) {
                    index = try nextLineStart(afterLineContaining: index + 1)
                    lineStart = true
                    lineHasContent = false
                } else {
                    lineHasContent = true
                    index += 2
                }
                continue
            }
            if units[index] == 0x60 {
                lineHasContent = true
                let delimiterLength = try repeatedUnitCount(0x60, startingAt: index)
                if let end = markdownCodeSpanEnds[index] {
                    index = end
                } else {
                    index += delimiterLength
                }
                continue
            }
            if units[index] == 0x5B {
                let isImage =
                    try index > 0
                    && units[index - 1] == 0x21
                    && !isMarkdownEscaped(at: index - 1)
                try retainMetadataEntry()
                bracketStack.append(
                    MarkdownBracket(
                        start: index,
                        isImage: isImage,
                        completedLinkCount: completedLinkCount,
                        asteriskDelimiterFloor: delimiterStacks[0x2A]?.count ?? 0,
                        underscoreDelimiterFloor: delimiterStacks[0x5F]?.count ?? 0
                    )
                )
                lineHasContent = true
                index += 1
                continue
            }
            if units[index] == 0x5D, let opening = bracketStack.popLast() {
                metadataEntries -= 1
                lineHasContent = true
                let destinationStart = index + 1
                if destinationStart < units.count,
                    units[destinationStart] == 0x28,
                    !failedDestinationStarts.contains(destinationStart),
                    opening.isImage || opening.completedLinkCount == completedLinkCount
                {
                    try retainMetadataEntry()
                    destination = MarkdownDestination(
                        tokenStart: opening.isImage ? opening.start - 1 : opening.start,
                        isImage: opening.isImage,
                        openingParenthesis: destinationStart,
                        openingLineStart: false,
                        openingLineHasContent: true,
                        asteriskDelimiterFloor: opening.asteriskDelimiterFloor,
                        underscoreDelimiterFloor: opening.underscoreDelimiterFloor,
                        deferredEmphasis: opening.deferredEmphasis
                    )
                    unmatchedDestinationParentheses.removeAll(keepingCapacity: true)
                    index = destinationStart + 1
                } else {
                    try restoreMarkdownDeferredEmphasis(
                        opening.deferredEmphasis,
                        bracketStack: &bracketStack,
                        delimiterStacks: &delimiterStacks
                    )
                    index += 1
                }
                continue
            }
            if units[index] == 0x5D {
                lineHasContent = true
                index += 1
                continue
            }
            if units[index] == 0x2A || units[index] == 0x5F {
                let marker = units[index]
                let delimiterLength = try repeatedUnitCount(marker, startingAt: index)
                let contentStart = index + delimiterLength
                let flanking = markdownDelimiterFlanking(from: index, to: contentStart)
                let canOpen =
                    flanking.left
                    && (marker != 0x5F || !flanking.right || flanking.previousIsPunctuation)
                let canClose =
                    flanking.right
                    && (marker != 0x5F || !flanking.left || flanking.nextIsPunctuation)
                let delimiterFloor = markdownDelimiterFloor(
                    for: marker,
                    inside: bracketStack.last
                )
                if canClose,
                    let openings = delimiterStacks[marker],
                    let openingIndex = try markdownOpeningDelimiterIndex(
                        in: openings,
                        floor: delimiterFloor,
                        before: index,
                        closingLength: delimiterLength,
                        closingCanOpen: canOpen
                    ),
                    let opening = delimiterStacks[marker]?[openingIndex]
                {
                    let matchedLength = min(2, opening.length, delimiterLength)
                    let removedCount = delimiterStacks[marker]!.count - openingIndex
                    delimiterStacks[marker]?.removeSubrange(openingIndex...)
                    metadataEntries -= removedCount
                    try retainMetadataEntry()
                    let tokenStart = opening.start + opening.length - matchedLength
                    try discardCompletedMarkdownMetadata(
                        after: tokenStart,
                        through: index + matchedLength
                    )
                    markdownEmphasisEnds[tokenStart] = index + matchedLength
                    markdownEmphasisStartOrder.append(tokenStart)
                    if canOpen, delimiterLength > matchedLength {
                        try retainMetadataEntry()
                        delimiterStacks[marker, default: []].append(
                            MarkdownDelimiterRun(
                                start: index + matchedLength,
                                length: delimiterLength - matchedLength,
                                canClose: canClose
                            )
                        )
                    }
                } else if canClose, delimiterFloor > 0, !bracketStack.isEmpty {
                    try retainMetadataEntry()
                    bracketStack[bracketStack.count - 1].deferredEmphasis.append(
                        MarkdownDeferredEmphasis(
                            marker: marker,
                            closingStart: index,
                            closingLength: delimiterLength,
                            closingCanOpen: canOpen
                        )
                    )
                } else if canOpen {
                    try retainMetadataEntry()
                    delimiterStacks[marker, default: []].append(
                        MarkdownDelimiterRun(
                            start: index,
                            length: delimiterLength,
                            canClose: canClose
                        )
                    )
                }
                lineHasContent = true
                index += delimiterLength
                continue
            }
            if !isMarkdownWhitespace(units[index]) { lineHasContent = true }
            index += scalarLength(at: index)
        }
        try restoreMarkdownBrackets(&bracketStack, delimiterStacks: &delimiterStacks)
        try Task.checkCancellation()
    }

    private mutating func markdownInterruptingBlockStarts(at lineStart: Int) throws -> Bool {
        let markerStart = markdownMarkerStart(forLineAt: lineStart)
        if try markdownHeadingEnd(startingAt: markerStart) != nil { return true }
        return try markdownFenceEnd(startingAt: markerStart) != nil
    }

    private func markdownDelimiterRunsMayMatch(
        opening: MarkdownDelimiterRun,
        closingLength: Int,
        closingCanOpen: Bool
    ) -> Bool {
        guard opening.canClose || closingCanOpen else { return true }
        return (opening.length + closingLength) % 3 != 0
            || (opening.length.isMultiple(of: 3) && closingLength.isMultiple(of: 3))
    }

    private mutating func markdownOpeningDelimiterIndex(
        in openings: [MarkdownDelimiterRun],
        floor: Int,
        before closingStart: Int,
        closingLength: Int,
        closingCanOpen: Bool
    ) throws -> Int? {
        var index = openings.count
        while index > floor {
            try consumeWork()
            index -= 1
            let opening = openings[index]
            if closingStart > opening.start + opening.length,
                markdownDelimiterRunsMayMatch(
                    opening: opening,
                    closingLength: closingLength,
                    closingCanOpen: closingCanOpen
                )
            {
                return index
            }
        }
        return nil
    }

    private func markdownDelimiterFloor(
        for marker: UInt16,
        inside bracket: MarkdownBracket?
    ) -> Int {
        guard let bracket else { return 0 }
        return marker == 0x2A
            ? bracket.asteriskDelimiterFloor
            : bracket.underscoreDelimiterFloor
    }

    private mutating func restoreMarkdownDeferredEmphasis(
        _ deferred: [MarkdownDeferredEmphasis],
        bracketStack: inout [MarkdownBracket],
        delimiterStacks: inout [UInt16: [MarkdownDelimiterRun]]
    ) throws {
        for candidate in deferred {
            try consumeWork()
            let floor = markdownDelimiterFloor(
                for: candidate.marker,
                inside: bracketStack.last
            )
            if let openings = delimiterStacks[candidate.marker],
                let openingIndex = try markdownOpeningDelimiterIndex(
                    in: openings,
                    floor: floor,
                    before: candidate.closingStart,
                    closingLength: candidate.closingLength,
                    closingCanOpen: candidate.closingCanOpen
                ),
                let opening = delimiterStacks[candidate.marker]?[openingIndex]
            {
                metadataEntries -= 1
                let matchedLength = min(2, opening.length, candidate.closingLength)
                let removedCount = delimiterStacks[candidate.marker]!.count - openingIndex
                delimiterStacks[candidate.marker]?.removeSubrange(openingIndex...)
                metadataEntries -= removedCount
                try retainMetadataEntry()
                let tokenStart = opening.start + opening.length - matchedLength
                try discardCompletedMarkdownMetadata(
                    after: tokenStart,
                    through: candidate.closingStart + matchedLength
                )
                markdownEmphasisEnds[tokenStart] = candidate.closingStart + matchedLength
                markdownEmphasisStartOrder.append(tokenStart)
                if candidate.closingCanOpen, candidate.closingLength > matchedLength {
                    try retainMetadataEntry()
                    delimiterStacks[candidate.marker, default: []].append(
                        MarkdownDelimiterRun(
                            start: candidate.closingStart + matchedLength,
                            length: candidate.closingLength - matchedLength,
                            canClose: true
                        )
                    )
                }
            } else if floor > 0, !bracketStack.isEmpty {
                bracketStack[bracketStack.count - 1].deferredEmphasis.append(candidate)
            } else if candidate.closingCanOpen {
                delimiterStacks[candidate.marker, default: []].append(
                    MarkdownDelimiterRun(
                        start: candidate.closingStart,
                        length: candidate.closingLength,
                        canClose: true
                    )
                )
            } else {
                metadataEntries -= 1
            }
        }
    }

    private mutating func discardMarkdownDelimiters(
        in stacks: inout [UInt16: [MarkdownDelimiterRun]],
        marker: UInt16,
        keeping count: Int
    ) {
        guard let currentCount = stacks[marker]?.count, currentCount > count else { return }
        metadataEntries -= currentCount - count
        stacks[marker]?.removeSubrange(count...)
    }

    private mutating func discardCompletedMarkdownMetadata(
        after start: Int,
        through end: Int
    ) throws {
        while let candidate = markdownLinkStartOrder.last, candidate > start {
            try consumeWork()
            guard candidate < end else { break }
            markdownLinkStartOrder.removeLast()
            if markdownLinkEnds.removeValue(forKey: candidate) != nil { metadataEntries -= 1 }
        }
        try discardMarkdownCodeSpanMetadata(after: start, through: end)
        while let candidate = markdownEmphasisStartOrder.last, candidate > start {
            try consumeWork()
            guard candidate < end else { break }
            markdownEmphasisStartOrder.removeLast()
            if markdownEmphasisEnds.removeValue(forKey: candidate) != nil { metadataEntries -= 1 }
        }
    }

    private mutating func discardMarkdownCodeSpanMetadata(
        after start: Int,
        through end: Int
    ) throws {
        let lower = firstMarkdownStart(after: start)
        let upper = firstMarkdownStart(atOrAfter: end)
        guard lower < upper else { return }
        for index in lower..<upper {
            try consumeWork()
            if markdownCodeSpanEnds.removeValue(forKey: markdownCodeSpanStarts[index]) != nil {
                metadataEntries -= 1
            }
        }
    }

    private func firstMarkdownStart(after value: Int) -> Int {
        var lower = markdownCodeSpanStarts.startIndex
        var upper = markdownCodeSpanStarts.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if markdownCodeSpanStarts[middle] <= value {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func firstMarkdownStart(atOrAfter value: Int) -> Int {
        var lower = markdownCodeSpanStarts.startIndex
        var upper = markdownCodeSpanStarts.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if markdownCodeSpanStarts[middle] < value {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private mutating func restoreMarkdownBrackets(
        _ bracketStack: inout [MarkdownBracket],
        delimiterStacks: inout [UInt16: [MarkdownDelimiterRun]]
    ) throws {
        while let opening = bracketStack.popLast() {
            try consumeWork()
            metadataEntries -= 1
            try restoreMarkdownDeferredEmphasis(
                opening.deferredEmphasis,
                bracketStack: &bracketStack,
                delimiterStacks: &delimiterStacks
            )
        }
    }

    private mutating func transferUnmatchedDestinationParentheses(
        _ unmatched: inout [Int],
        to failed: inout Set<Int>,
        order: inout [Int]
    ) throws {
        metadataEntries -= unmatched.count
        for opening in unmatched {
            try consumeWork()
            if failed.insert(opening).inserted {
                metadataEntries += 1
                order.append(opening)
            }
        }
        unmatched.removeAll(keepingCapacity: true)
    }

    private mutating func reclaimFailedDestinationStarts(
        through index: Int,
        starts: inout Set<Int>,
        order: inout [Int],
        head: inout Int
    ) throws {
        while head < order.count, order[head] <= index {
            try consumeWork()
            if starts.remove(order[head]) != nil { metadataEntries -= 1 }
            head += 1
        }
        if head == order.count {
            order.removeAll(keepingCapacity: true)
            head = 0
        } else if head >= 1_024, head >= order.count / 2 {
            try consumeWork(order.count - head)
            order.removeFirst(head)
            head = 0
        }
    }

    private func markdownDestinationStep(
        _ destination: inout MarkdownDestination,
        at index: Int
    ) -> MarkdownDestinationStep {
        let unit = units[index]
        if destination.escaped {
            destination.escaped = false
            if !isMarkdownWhitespace(unit) { destination.crossedSoftBreak = false }
            return .advance
        }
        if unit == 0x5C,
            index + 1 < units.count,
            isASCIIEscapablePunctuation(units[index + 1])
        {
            switch destination.phase {
            case .afterAngle, .afterDestination, .afterTitle:
                return .invalid
            case .leading:
                destination.phase = .bare
            case .angle, .bare, .doubleQuotedTitle, .singleQuotedTitle,
                .parenthesizedTitle:
                break
            }
            destination.escaped = true
            return .advance
        }
        if isLineBreak(unit) {
            switch destination.phase {
            case .leading, .afterDestination, .doubleQuotedTitle, .singleQuotedTitle,
                .parenthesizedTitle, .afterTitle:
                guard !destination.crossedSoftBreak else { return .invalid }
                destination.crossedSoftBreak = true
                destination.sawLeadingWhitespace = true
                return .advance
            case .afterAngle:
                destination.phase = .afterDestination
                destination.crossedSoftBreak = true
                return .advance
            case .bare where destination.parenthesisDepth == 0:
                destination.phase = .afterDestination
                destination.crossedSoftBreak = true
                return .advance
            case .angle, .bare:
                return .invalid
            }
        }
        if unit != 0x20, unit != 0x09 { destination.crossedSoftBreak = false }

        switch destination.phase {
        case .leading:
            if unit == 0x20 || unit == 0x09 {
                destination.sawLeadingWhitespace = true
            } else if unit == 0x29 {
                return .complete
            } else if isASCIIControl(unit) {
                return .invalid
            } else if unit == 0x3C {
                destination.phase = .angle
            } else if destination.sawLeadingWhitespace, unit == 0x22 {
                destination.phase = .doubleQuotedTitle
            } else if destination.sawLeadingWhitespace, unit == 0x27 {
                destination.phase = .singleQuotedTitle
            } else {
                destination.phase = .bare
                if unit == 0x28 { destination.parenthesisDepth = 1 }
            }
        case .angle:
            if unit == 0x3E {
                destination.phase = .afterAngle
            } else if isASCIIControl(unit) || unit == 0x3C {
                return .invalid
            }
        case .afterAngle:
            if unit == 0x29 {
                return .complete
            }
            guard unit == 0x20 || unit == 0x09 else { return .invalid }
            destination.phase = .afterDestination
        case .bare:
            if unit == 0x20 || unit == 0x09 {
                guard destination.parenthesisDepth == 0 else { return .invalid }
                destination.phase = .afterDestination
            } else if isASCIIControl(unit) {
                return .invalid
            } else if unit == 0x28 {
                destination.parenthesisDepth += 1
            } else if unit == 0x29 {
                if destination.parenthesisDepth == 0 { return .complete }
                destination.parenthesisDepth -= 1
            }
        case .afterDestination:
            if unit == 0x20 || unit == 0x09 {
                break
            }
            if unit == 0x29 { return .complete }
            if unit == 0x22 {
                destination.phase = .doubleQuotedTitle
            } else if unit == 0x27 {
                destination.phase = .singleQuotedTitle
            } else if unit == 0x28 {
                destination.phase = .parenthesizedTitle
            } else {
                return .invalid
            }
        case .doubleQuotedTitle:
            if unit == 0x22 { destination.phase = .afterTitle }
        case .singleQuotedTitle:
            if unit == 0x27 { destination.phase = .afterTitle }
        case .parenthesizedTitle:
            if unit == 0x28 { return .invalid }
            if unit == 0x29 { destination.phase = .afterTitle }
        case .afterTitle:
            if unit == 0x29 { return .complete }
            if unit != 0x20, unit != 0x09 { return .invalid }
        }
        return .advance
    }

    private mutating func prepareMarkdownCodeSpans() throws {
        try SyntaxHighlighter.checkpoint(.markdownCodeSpanMetadata)
        var pending: [Int: Int] = [:]
        var index = 0
        while index < units.count {
            try consumeWork()
            if isLineStart(index) {
                let markerStart = markdownMarkerStart(forLineAt: index)
                if try markdownLineIsBlank(startingAt: index) {
                    metadataEntries -= pending.count
                    pending.removeAll(keepingCapacity: true)
                }
                if let fenceEnd = try markdownFenceEnd(startingAt: markerStart) {
                    metadataEntries -= pending.count
                    pending.removeAll(keepingCapacity: true)
                    index = fenceEnd
                    continue
                }
                if let headingEnd = try markdownHeadingEnd(startingAt: markerStart) {
                    metadataEntries -= pending.count
                    pending.removeAll(keepingCapacity: true)
                    index = headingEnd
                    continue
                }
            }
            if units[index] == 0x60 {
                let delimiterLength = try repeatedUnitCount(0x60, startingAt: index)
                if let opening = pending.removeValue(forKey: delimiterLength) {
                    metadataEntries -= 1
                    for (length, coveredOpening) in pending {
                        try consumeWork()
                        if coveredOpening > opening {
                            pending.removeValue(forKey: length)
                            metadataEntries -= 1
                        }
                    }
                    try discardCompletedMarkdownMetadata(
                        after: opening,
                        through: index + delimiterLength
                    )
                    try retainMetadataEntry()
                    markdownCodeSpanEnds[opening] = index + delimiterLength
                    markdownCodeSpanStarts.append(opening)
                } else if !(try isMarkdownEscaped(at: index)) {
                    try retainMetadataEntry()
                    pending[delimiterLength] = index
                }
                index += delimiterLength
                continue
            }
            index += scalarLength(at: index)
        }
        metadataEntries -= pending.count
    }

    private mutating func markdownHeadingEnd(startingAt start: Int) throws -> Int? {
        guard start < units.count, units[start] == 0x23 else { return nil }
        let markerCount = try repeatedUnitCount(0x23, startingAt: start)
        guard markerCount <= 6 else { return nil }
        let contentStart = start + markerCount
        guard
            contentStart == units.count
                || isLineBreak(units[contentStart])
                || units[contentStart] == 0x20
                || units[contentStart] == 0x09
        else { return nil }
        return try lineEnd(startingAt: contentStart)
    }

    private mutating func markdownLineIsBlank(startingAt start: Int) throws -> Bool {
        var index = start
        while index < units.count, units[index] == 0x20 || units[index] == 0x09 {
            try consumeWork()
            index += 1
        }
        return index == units.count || isLineBreak(units[index])
    }

    private func markdownCodeSpanEnd(startingAt start: Int) -> Int? {
        return markdownCodeSpanEnds[start]
    }

    private func markdownLinkEnd(startingAt start: Int) -> Int? {
        return markdownLinkEnds[start]
    }

    private func markdownEmphasisEnd(startingAt start: Int) -> Int? {
        return markdownEmphasisEnds[start]
    }

    private mutating func lineEnd(startingAt start: Int) throws -> Int {
        var index = min(start, units.count)
        while index < units.count, !isLineBreak(units[index]) {
            try consumeWork()
            index += 1
        }
        return index
    }

    private mutating func nextLineStart(afterLineContaining index: Int) throws -> Int {
        let end = try lineEnd(startingAt: index)
        guard end < units.count else { return units.count }
        if units[end] == 0x0D, end + 1 < units.count, units[end + 1] == 0x0A {
            return end + 2
        }
        return end + 1
    }

    private func isLineStart(_ index: Int) -> Bool {
        if index == 0 { return true }
        if units[index - 1] == 0x0A { return true }
        return units[index - 1] == 0x0D && (index >= units.count || units[index] != 0x0A)
    }

    private mutating func repeatedUnitCount(_ unit: UInt16, startingAt start: Int) throws -> Int {
        var index = start
        while index < units.count, units[index] == unit {
            try consumeWork()
            index += 1
        }
        return index - start
    }

    private func has(_ first: UInt16, _ second: UInt16, at index: Int) -> Bool {
        index + 1 < units.count && units[index] == first && units[index + 1] == second
    }

    private func hasSequence(_ sequence: [UInt16], at index: Int) -> Bool {
        guard index >= 0, sequence.count <= units.count - min(index, units.count) else {
            return false
        }
        for offset in sequence.indices where units[index + offset] != sequence[offset] {
            return false
        }
        return true
    }

    private func hasSequence(from source: Range<Int>, at index: Int) -> Bool {
        guard source.lowerBound >= 0,
            source.upperBound <= units.count,
            index >= 0,
            source.count <= units.count - min(index, units.count)
        else { return false }
        for offset in 0..<source.count
        where units[source.lowerBound + offset] != units[index + offset] {
            return false
        }
        return true
    }

    private mutating func repeatedUnitPrefixLength(
        _ unit: UInt16,
        maximum: Int,
        startingAt start: Int
    ) throws -> Int {
        var index = start
        while index < units.count, index - start < maximum, units[index] == unit {
            try consumeWork()
            index += 1
        }
        return index - start
    }

    private mutating func hasRepeatedUnit(_ unit: UInt16, count: Int, at index: Int) throws -> Bool {
        guard count >= 0, index >= 0, index <= units.count, count <= units.count - index else {
            return false
        }
        for offset in 0..<count {
            try consumeWork()
            if units[index + offset] != unit { return false }
        }
        return true
    }

    private func isASCIIDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    private func isASCIIHexDigit(_ unit: UInt16) -> Bool {
        isASCIIDigit(unit)
            || (unit >= 0x41 && unit <= 0x46)
            || (unit >= 0x61 && unit <= 0x66)
    }

    private func isCodeDigit(_ unit: UInt16, radix: Int) -> Bool {
        switch radix {
        case 2:
            return unit == 0x30 || unit == 0x31
        case 8:
            return unit >= 0x30 && unit <= 0x37
        case 10:
            return isASCIIDigit(unit)
        case 16:
            return isASCIIHexDigit(unit)
        default:
            return false
        }
    }

    private func isValidDigitSeparator(at index: Int, radix: Int, afterDigit: Bool) -> Bool {
        guard afterDigit, index < units.count else { return false }
        if language == .swift {
            return units[index] == 0x5F
                && index + 1 < units.count
                && isCodeDigit(units[index + 1], radix: radix)
        }
        return language == .cLike
            && units[index] == 0x27
            && index + 1 < units.count
            && isCodeDigit(units[index + 1], radix: radix)
    }

    private func scalarLength(at index: Int) -> Int {
        guard index < units.count, (0xD800...0xDBFF).contains(units[index]),
            index + 1 < units.count,
            (0xDC00...0xDFFF).contains(units[index + 1])
        else { return 1 }
        return 2
    }

    private func unicodeScalar(at index: Int) -> UnicodeScalar? {
        let first = units[index]
        guard (0xD800...0xDBFF).contains(first) else { return UnicodeScalar(first) }
        guard index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) else {
            return nil
        }
        let high = UInt32(first - 0xD800)
        let low = UInt32(units[index + 1] - 0xDC00)
        return UnicodeScalar(0x10000 + (high << 10) + low)
    }

    private func unicodeScalar(before index: Int) -> UnicodeScalar? {
        guard index > 0 else { return nil }
        let previous = index - 1
        guard (0xDC00...0xDFFF).contains(units[previous]), previous > 0 else {
            return UnicodeScalar(units[previous])
        }
        return unicodeScalar(at: previous - 1)
    }

    private func isUnicodeIdentifierContinuation(at index: Int) -> Bool {
        guard index < units.count, let scalar = unicodeScalar(at: index) else { return false }
        return scalar == "_" || scalar.properties.isXIDContinue
    }

    private func isUnicodeIdentifierContinuation(before index: Int) -> Bool {
        guard let scalar = unicodeScalar(before: index) else { return false }
        return scalar == "_" || scalar.properties.isXIDContinue
    }

    private func isCodeIdentifierContinuation(before index: Int) -> Bool {
        guard index > 0 else { return false }
        let previous = index - 1
        let scalarStart =
            (0xDC00...0xDFFF).contains(units[previous]) && previous > 0
            ? previous - 1
            : previous
        return isCodeIdentifierContinuation(at: scalarStart)
    }

    private func markdownDelimiterFlanking(
        from start: Int,
        to end: Int
    ) -> (
        left: Bool,
        right: Bool,
        previousIsPunctuation: Bool,
        nextIsPunctuation: Bool
    ) {
        let previous = unicodeScalar(before: start)
        let next = end < units.count ? unicodeScalar(at: end) : nil
        let previousIsWhitespace = previous.map(isUnicodeWhitespace) ?? true
        let nextIsWhitespace = next.map(isUnicodeWhitespace) ?? true
        let previousIsPunctuation = previous.map(isUnicodePunctuation) ?? false
        let nextIsPunctuation = next.map(isUnicodePunctuation) ?? false
        return (
            left: !nextIsWhitespace
                && (!nextIsPunctuation || previousIsWhitespace || previousIsPunctuation),
            right: !previousIsWhitespace
                && (!previousIsPunctuation || nextIsWhitespace || nextIsPunctuation),
            previousIsPunctuation: previousIsPunctuation,
            nextIsPunctuation: nextIsPunctuation
        )
    }

    private func isUnicodeWhitespace(_ scalar: UnicodeScalar) -> Bool {
        scalar.properties.isWhitespace
    }

    private func isUnicodePunctuation(_ scalar: UnicodeScalar) -> Bool {
        if scalar.isASCII, isASCIIEscapablePunctuation(UInt16(scalar.value)) {
            return true
        }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation,
            .closePunctuation, .initialPunctuation, .finalPunctuation,
            .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol,
            .otherSymbol:
            return true
        default:
            return false
        }
    }

    private func isASCIIControl(_ unit: UInt16) -> Bool {
        unit < 0x20 || unit == 0x7F
    }

    private mutating func isMarkdownEscaped(at index: Int) throws -> Bool {
        var backslashCount = 0
        var cursor = index
        while cursor > 0, units[cursor - 1] == 0x5C {
            try consumeWork()
            backslashCount += 1
            cursor -= 1
        }
        return !backslashCount.isMultiple(of: 2)
    }

    private func isASCIIEscapablePunctuation(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B,
            0x2C, 0x2D, 0x2E, 0x2F, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40,
            0x5B, 0x5C, 0x5D, 0x5E, 0x5F, 0x60, 0x7B, 0x7C, 0x7D, 0x7E:
            return true
        default:
            return false
        }
    }

    private func isCodeIdentifierStart(at index: Int) -> Bool {
        guard let scalar = unicodeScalar(at: index) else { return false }
        if language == .swift {
            if scalar == "$" {
                return index + 1 < units.count && isASCIIDigit(units[index + 1])
            }
            return isSwiftIdentifierHead(scalar.value)
        }
        return scalar == "_" || scalar.properties.isXIDStart
    }

    private func isCodeIdentifierContinuation(at index: Int) -> Bool {
        guard let scalar = unicodeScalar(at: index) else { return false }
        if language == .swift {
            return isSwiftIdentifierHead(scalar.value)
                || (0x30...0x39).contains(scalar.value)
                || (0x0300...0x036F).contains(scalar.value)
                || (0x1DC0...0x1DFF).contains(scalar.value)
                || (0x20D0...0x20FF).contains(scalar.value)
                || (0xFE20...0xFE2F).contains(scalar.value)
        }
        if scalar == "_" || scalar.properties.isXIDStart { return true }
        return scalar.properties.isXIDContinue
    }

    private func isSwiftIdentifierHead(_ value: UInt32) -> Bool {
        if value == 0x5F
            || (0x41...0x5A).contains(value)
            || (0x61...0x7A).contains(value)
        {
            return true
        }
        if Self.swiftIdentifierHeadRanges.contains(where: { $0.contains(value) }) { return true }
        guard value >= 0x10000, value <= 0xEFFFD else { return false }
        return value & 0xFFFF <= 0xFFFD
    }

    private func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D
    }

    private func isMarkdownWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || isLineBreak(unit)
    }
}
