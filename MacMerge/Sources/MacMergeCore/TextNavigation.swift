import Foundation

public struct TextNavigationLimits: Equatable, Sendable {
    public static let `default` = TextNavigationLimits()

    public let maximumInputUTF16Length: Int
    public let maximumLineCount: Int
    public let maximumLineUTF16Length: Int
    public let maximumTokenCount: Int
    public let maximumSymbolCount: Int
    public let maximumSymbolNameUTF16Length: Int
    public let maximumLookupResults: Int

    public init(
        maximumInputUTF16Length: Int = 64 * 1024 * 1024,
        maximumLineCount: Int = 1_000_000,
        maximumLineUTF16Length: Int = 1024 * 1024,
        maximumTokenCount: Int = 4_000_000,
        maximumSymbolCount: Int = 100_000,
        maximumSymbolNameUTF16Length: Int = 256,
        maximumLookupResults: Int = 256
    ) {
        self.maximumInputUTF16Length = maximumInputUTF16Length
        self.maximumLineCount = maximumLineCount
        self.maximumLineUTF16Length = maximumLineUTF16Length
        self.maximumTokenCount = maximumTokenCount
        self.maximumSymbolCount = maximumSymbolCount
        self.maximumSymbolNameUTF16Length = maximumSymbolNameUTF16Length
        self.maximumLookupResults = maximumLookupResults
    }
}

public enum TextNavigationClamping: Equatable, Sendable {
    case reject
    case clamp
}

public struct TextPosition: Equatable, Hashable, Sendable {
    /// One-based line number.
    public let line: Int
    /// One-based extended-grapheme-cluster column.
    public let column: Int

    public init(line: Int, column: Int = 1) {
        self.line = line
        self.column = column
    }
}

public struct TextLocation: Equatable, Hashable, Sendable {
    public let position: TextPosition
    /// One-based UTF-16 column, suitable for Cocoa text storage.
    public let utf16Column: Int
    /// Zero-based UTF-16 offset in the complete text.
    public let utf16Offset: Int

    public var line: Int { position.line }
    public var column: Int { position.column }

    public init(position: TextPosition, utf16Column: Int, utf16Offset: Int) {
        self.position = position
        self.utf16Column = utf16Column
        self.utf16Offset = utf16Offset
    }
}

public struct TextLine: Equatable, Sendable {
    public let number: Int
    /// Content only; excludes CR, LF, or CRLF terminator.
    public let range: NSRange
    public let terminatorRange: NSRange

    /// Content and terminator, or `nil` when their combined length is not representable.
    public var completeRange: NSRange? {
        guard range.location >= 0, range.length >= 0,
            terminatorRange.location >= 0, terminatorRange.length >= 0
        else {
            return nil
        }
        let (contentEnd, locationOverflow) = range.location.addingReportingOverflow(range.length)
        let (length, overflow) = range.length.addingReportingOverflow(terminatorRange.length)
        let (_, endOverflow) = range.location.addingReportingOverflow(length)
        guard !locationOverflow, !overflow, !endOverflow,
            contentEnd == terminatorRange.location
        else { return nil }
        return NSRange(location: range.location, length: length)
    }

    public init(number: Int, range: NSRange, terminatorRange: NSRange) {
        self.number = number
        self.range = range
        self.terminatorRange = terminatorRange
    }
}

public enum TextNavigationError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case inputTooLarge(maximumUTF16Length: Int)
    case tooManyLines(maximumLines: Int)
    case lineTooLong(line: Int, maximumUTF16Length: Int)
    case invalidLine(Int)
    case invalidColumn(line: Int, column: Int)
    case invalidUTF16Column(line: Int, column: Int)
    case invalidUTF16Offset(Int)
    case offsetSplitsCharacter(Int)
    case tooManyTokens(maximumTokens: Int)
    case tooManySymbols(maximumSymbols: Int)
    case symbolNameTooLong(maximumUTF16Length: Int)
    case invalidLookupLimit(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Text navigation limits are invalid."
        case .inputTooLarge(let maximumUTF16Length):
            "Text exceeds the \(maximumUTF16Length)-UTF-16-unit navigation limit."
        case .tooManyLines(let maximumLines):
            "Text exceeds the \(maximumLines)-line navigation limit."
        case .lineTooLong(let line, let maximumUTF16Length):
            "Line \(line) exceeds the \(maximumUTF16Length)-UTF-16-unit navigation limit."
        case .invalidLine(let line):
            "Line \(line) is outside the document."
        case .invalidColumn(let line, let column):
            "Column \(column) is outside line \(line)."
        case .invalidUTF16Column(let line, let column):
            "UTF-16 column \(column) is outside line \(line)."
        case .invalidUTF16Offset(let offset):
            "UTF-16 offset \(offset) is outside the document."
        case .offsetSplitsCharacter(let offset):
            "UTF-16 offset \(offset) splits an extended grapheme cluster."
        case .tooManyTokens(let maximumTokens):
            "Definition indexing exceeds the \(maximumTokens)-token limit."
        case .tooManySymbols(let maximumSymbols):
            "Definition indexing exceeds the \(maximumSymbols)-symbol limit."
        case .symbolNameTooLong(let maximumUTF16Length):
            "Symbol name exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .invalidLookupLimit(let limit):
            "Definition lookup result limit \(limit) is invalid."
        }
    }
}

public struct TextLineIndex: Equatable, Sendable {
    private struct Record: Equatable, Sendable {
        let start: Int
        let contentEnd: Int
        let end: Int
    }

    public let text: String
    private let records: [Record]

    public var lineCount: Int { records.count }
    public var utf16Length: Int { records.last?.end ?? 0 }

    public init(text: String, limits: TextNavigationLimits = .default) throws {
        try Self.validate(limits)
        let utf16Length = text.utf16.count
        guard utf16Length <= limits.maximumInputUTF16Length else {
            throw TextNavigationError.inputTooLarge(
                maximumUTF16Length: limits.maximumInputUTF16Length
            )
        }

        var records: [Record] = []
        records.reserveCapacity(min(limits.maximumLineCount, 4096))
        var lineStart = 0
        var offset = 0
        var iterator = text.utf16.makeIterator()
        var pending = iterator.next()

        while let unit = pending {
            pending = iterator.next()
            guard unit == 0x0A || unit == 0x0D else {
                offset += 1
                continue
            }

            let terminatorLength: Int
            if unit == 0x0D, pending == 0x0A {
                terminatorLength = 2
                pending = iterator.next()
            } else {
                terminatorLength = 1
            }
            try Self.appendRecord(
                to: &records,
                start: lineStart,
                contentEnd: offset,
                end: offset + terminatorLength,
                limits: limits
            )
            offset += terminatorLength
            lineStart = offset
        }

        try Self.appendRecord(
            to: &records,
            start: lineStart,
            contentEnd: utf16Length,
            end: utf16Length,
            limits: limits
        )
        self.text = text
        self.records = records
    }

    public func line(at number: Int) -> TextLine? {
        guard number > 0, number <= records.count else { return nil }
        let record = records[number - 1]
        return TextLine(
            number: number,
            range: NSRange(location: record.start, length: record.contentEnd - record.start),
            terminatorRange: NSRange(
                location: record.contentEnd,
                length: record.end - record.contentEnd
            )
        )
    }

    public func stringIndex(atUTF16Offset offset: Int) throws -> String.Index {
        guard offset >= 0, offset <= utf16Length else {
            throw TextNavigationError.invalidUTF16Offset(offset)
        }
        let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: offset)
        guard let index = String.Index(utf16Index, within: text) else {
            throw TextNavigationError.offsetSplitsCharacter(offset)
        }
        return index
    }

    public func utf16Offset(of index: String.Index) -> Int? {
        guard let utf16Index = index.samePosition(in: text.utf16) else { return nil }
        let offset = text.utf16.distance(from: text.utf16.startIndex, to: utf16Index)
        guard offset >= 0, offset <= utf16Length,
            let roundTrip = try? stringIndex(atUTF16Offset: offset), roundTrip == index
        else {
            return nil
        }
        return offset
    }

    public func stringRange(ofLine number: Int, includingTerminator: Bool = false) throws
        -> Range<String.Index>
    {
        guard let line = line(at: number) else { throw TextNavigationError.invalidLine(number) }
        let range: NSRange
        if includingTerminator {
            guard let completeRange = line.completeRange else {
                throw TextNavigationError.invalidUTF16Offset(line.range.location)
            }
            range = completeRange
        } else {
            range = line.range
        }
        let lower = try stringIndex(atUTF16Offset: range.location)
        let (upperOffset, overflow) = range.location.addingReportingOverflow(range.length)
        guard !overflow else { throw TextNavigationError.invalidUTF16Offset(range.location) }
        let upper = try stringIndex(atUTF16Offset: upperOffset)
        return lower..<upper
    }

    public func location(
        at position: TextPosition,
        clamping: TextNavigationClamping = .reject
    ) throws -> TextLocation {
        let lineNumber = try resolvedLine(position.line, clamping: clamping)
        let record = records[lineNumber - 1]
        let start = try stringIndex(atUTF16Offset: record.start)
        let end = try stringIndex(atUTF16Offset: record.contentEnd)
        let maximumColumn = text.distance(from: start, to: end) + 1
        let column = try Self.resolved(
            position.column,
            in: 1...maximumColumn,
            clamping: clamping,
            error: .invalidColumn(line: lineNumber, column: position.column)
        )
        let index = text.index(start, offsetBy: column - 1)
        guard let offset = utf16Offset(of: index) else {
            throw TextNavigationError.offsetSplitsCharacter(record.start)
        }
        return TextLocation(
            position: TextPosition(line: lineNumber, column: column),
            utf16Column: offset - record.start + 1,
            utf16Offset: offset
        )
    }

    public func location(
        line requestedLine: Int,
        utf16Column requestedColumn: Int,
        clamping: TextNavigationClamping = .reject
    ) throws -> TextLocation {
        let lineNumber = try resolvedLine(requestedLine, clamping: clamping)
        let record = records[lineNumber - 1]
        let maximumColumn = record.contentEnd - record.start + 1
        let column = try Self.resolved(
            requestedColumn,
            in: 1...maximumColumn,
            clamping: clamping,
            error: .invalidUTF16Column(line: lineNumber, column: requestedColumn)
        )
        let offset = record.start + column - 1
        do {
            return try location(atUTF16Offset: offset)
        } catch TextNavigationError.offsetSplitsCharacter {
            throw TextNavigationError.offsetSplitsCharacter(offset)
        }
    }

    public func location(atUTF16Offset offset: Int) throws -> TextLocation {
        let index = try stringIndex(atUTF16Offset: offset)
        let recordIndex = recordIndex(containing: offset)
        let record = records[recordIndex]
        let lineStart = try stringIndex(atUTF16Offset: record.start)
        return TextLocation(
            position: TextPosition(
                line: recordIndex + 1,
                column: text.distance(from: lineStart, to: index) + 1
            ),
            utf16Column: offset - record.start + 1,
            utf16Offset: offset
        )
    }

    /// Resolves user-entered line and column. Go-to-line defaults to safe document clamping.
    public func goToLine(
        _ line: Int,
        column: Int = 1,
        clamping: TextNavigationClamping = .clamp
    ) throws -> TextLocation {
        try location(at: TextPosition(line: line, column: column), clamping: clamping)
    }

    private func resolvedLine(
        _ line: Int,
        clamping: TextNavigationClamping
    ) throws -> Int {
        try Self.resolved(
            line,
            in: 1...lineCount,
            clamping: clamping,
            error: .invalidLine(line)
        )
    }

    private func recordIndex(containing offset: Int) -> Int {
        var lower = 0
        var upper = records.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if records[middle].start <= offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(0, lower - 1)
    }

    private static func resolved(
        _ value: Int,
        in range: ClosedRange<Int>,
        clamping: TextNavigationClamping,
        error: TextNavigationError
    ) throws -> Int {
        if range.contains(value) { return value }
        guard clamping == .clamp else { throw error }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private static func appendRecord(
        to records: inout [Record],
        start: Int,
        contentEnd: Int,
        end: Int,
        limits: TextNavigationLimits
    ) throws {
        guard records.count < limits.maximumLineCount else {
            throw TextNavigationError.tooManyLines(maximumLines: limits.maximumLineCount)
        }
        guard contentEnd - start <= limits.maximumLineUTF16Length else {
            throw TextNavigationError.lineTooLong(
                line: records.count + 1,
                maximumUTF16Length: limits.maximumLineUTF16Length
            )
        }
        records.append(Record(start: start, contentEnd: contentEnd, end: end))
    }

    fileprivate static func validate(_ limits: TextNavigationLimits) throws {
        guard limits.maximumInputUTF16Length >= 0,
            limits.maximumLineCount > 0,
            limits.maximumLineUTF16Length >= 0,
            limits.maximumTokenCount > 0,
            limits.maximumSymbolCount >= 0,
            limits.maximumSymbolNameUTF16Length > 0,
            limits.maximumLookupResults > 0
        else {
            throw TextNavigationError.invalidLimits
        }
    }
}

public enum DefinitionSymbolKind: String, Equatable, Hashable, Sendable {
    case type
    case extensionDeclaration
    case function
    case initializer
    case variable
    case constant
    case enumerationCase
    case macro
}

public struct DefinitionSymbol: Equatable, Hashable, Sendable {
    public let name: String
    public let kind: DefinitionSymbolKind
    public let location: TextLocation
    public let nameRange: NSRange
    public let declarationRange: NSRange

    public init(
        name: String,
        kind: DefinitionSymbolKind,
        location: TextLocation,
        nameRange: NSRange,
        declarationRange: NSRange
    ) {
        self.name = name
        self.kind = kind
        self.location = location
        self.nameRange = nameRange
        self.declarationRange = declarationRange
    }
}

public struct DefinitionLookupResult: Equatable, Sendable {
    public let symbolName: String
    public let definitions: [DefinitionSymbol]
    public let isTruncated: Bool

    public init(symbolName: String, definitions: [DefinitionSymbol], isTruncated: Bool) {
        self.symbolName = symbolName
        self.definitions = definitions
        self.isTruncated = isTruncated
    }
}

/// Deterministic lexical index for common C-like and Swift declarations.
/// It intentionally does not perform type resolution, overload ranking, or language-server semantics.
public struct DefinitionSymbolIndex: Equatable, Sendable {
    private enum LexicalLanguage {
        case swift
        case cLike
        case mixed

        var supportsSwiftDeclarations: Bool { self != .cLike }
        var supportsCLikeDeclarations: Bool { self != .swift }
        var usesSwiftCommentRules: Bool { self == .swift }
    }

    private struct Token: Equatable, Sendable {
        let text: String
        let localRange: NSRange
        let isIdentifier: Bool
        let isEscapedIdentifier: Bool
    }

    private struct DeclarationState {
        var braceDepth = 0
        var enumDepths: [Int] = []
        var pendingEnum = false

        mutating func consume(_ tokens: [Token]) {
            for token in tokens {
                if token.text == "enum" {
                    pendingEnum = true
                } else if token.text == "{" {
                    braceDepth += 1
                    if pendingEnum {
                        enumDepths.append(braceDepth)
                        pendingEnum = false
                    }
                } else if token.text == "}" {
                    if enumDepths.last == braceDepth {
                        enumDepths.removeLast()
                    }
                    braceDepth = max(0, braceDepth - 1)
                } else if token.text == ";" {
                    pendingEnum = false
                }
            }
        }

        func isInsideEnum(before index: Int, in tokens: [Token]) -> Bool {
            var copy = self
            copy.consume(Array(tokens[..<index]))
            return copy.enumDepths.last == copy.braceDepth
        }
    }

    private struct Lexer {
        private enum MultilineLiteral {
            case string(hashCount: Int)
            case regex(hashCount: Int, inCharacterClass: Bool)
            case backtick
            case cPlusPlusRaw(delimiter: [UInt16])
        }

        private struct ContinuedQuote {
            let quote: UInt16
            let escapeNext: Bool
        }

        let language: LexicalLanguage
        var blockCommentDepth = 0
        private var multilineLiteral: MultilineLiteral?
        private var continuedQuote: ContinuedQuote?
        private var lineCommentContinued = false
        private var preprocessorContinued = false

        init(language: LexicalLanguage) {
            self.language = language
        }

        mutating func tokens(in line: String, maximumCount: Int) throws -> [Token] {
            let units = Array(line.utf16)
            var tokens: [Token] = []
            var index = 0

            if preprocessorContinued {
                preprocessorContinued = units.last == 0x5C
                return []
            }
            if units.first(where: { !isHorizontalWhitespace($0) }) == 0x23 {
                preprocessorContinued = units.last == 0x5C
            }

            if lineCommentContinued {
                lineCommentContinued = units.last == 0x5C
                return []
            }

            while index < units.count {
                if blockCommentDepth > 0 {
                    if language.usesSwiftCommentRules, has(units, at: index, 0x2F, 0x2A) {
                        blockCommentDepth += 1
                        index += 2
                    } else if has(units, at: index, 0x2A, 0x2F) {
                        blockCommentDepth -= 1
                        index += 2
                    } else {
                        index += scalarLength(in: units, at: index)
                    }
                    continue
                }

                if let literal = multilineLiteral {
                    let result: (end: Int, closed: Bool)
                    var carriedLiteral = literal
                    switch literal {
                    case .string(let hashCount):
                        result = endOfString(
                            in: units,
                            after: index,
                            quoteCount: 3,
                            hashCount: hashCount
                        )
                    case .regex(let hashCount, var inCharacterClass):
                        result = endOfRegex(
                            in: units,
                            after: index,
                            hashCount: hashCount,
                            inCharacterClass: &inCharacterClass
                        )
                        if !result.closed {
                            carriedLiteral = .regex(
                                hashCount: hashCount,
                                inCharacterClass: inCharacterClass
                            )
                        }
                    case .backtick:
                        result = endOfBacktick(in: units, after: index)
                    case .cPlusPlusRaw(let delimiter):
                        result = endOfCPlusPlusRawString(
                            in: units,
                            after: index,
                            delimiter: delimiter
                        )
                    }
                    multilineLiteral = result.closed ? nil : carriedLiteral
                    index = result.end
                    continue
                }

                if let continuation = continuedQuote {
                    if continuation.escapeNext, index < units.count {
                        index += scalarLength(in: units, at: index)
                    }
                    let result = endOfString(
                        in: units,
                        after: index,
                        quoteCount: 1,
                        hashCount: 0,
                        quote: continuation.quote
                    )
                    continuedQuote = continuedQuoteState(
                        after: result,
                        quote: continuation.quote,
                        in: units
                    )
                    index = result.end
                    continue
                }

                if has(units, at: index, 0x2F, 0x2F) {
                    lineCommentContinued = !language.usesSwiftCommentRules && units.last == 0x5C
                    break
                }
                if has(units, at: index, 0x2F, 0x2A) {
                    blockCommentDepth = 1
                    index += 2
                    continue
                }

                if let opening = cPlusPlusRawStringOpening(in: units, at: index) {
                    let result = endOfCPlusPlusRawString(
                        in: units,
                        after: opening.contentStart,
                        delimiter: opening.delimiter
                    )
                    if !result.closed {
                        multilineLiteral = .cPlusPlusRaw(delimiter: opening.delimiter)
                    }
                    index = result.end
                    continue
                }

                if units[index] == 0x23 {
                    let hashCount = repeatedCount(of: 0x23, in: units, at: index)
                    let delimiter = index + hashCount
                    if delimiter < units.count, units[delimiter] == 0x22 {
                        let quoteCount = has(units, at: delimiter, 0x22, 0x22, 0x22) ? 3 : 1
                        let result = endOfString(
                            in: units,
                            after: delimiter + quoteCount,
                            quoteCount: quoteCount,
                            hashCount: hashCount
                        )
                        if quoteCount == 3, !result.closed {
                            multilineLiteral = .string(hashCount: hashCount)
                        }
                        index = result.end
                        continue
                    }
                    if delimiter < units.count, units[delimiter] == 0x2F {
                        var inCharacterClass = false
                        let result = endOfRegex(
                            in: units,
                            after: delimiter + 1,
                            hashCount: hashCount,
                            inCharacterClass: &inCharacterClass
                        )
                        if !result.closed {
                            multilineLiteral = .regex(
                                hashCount: hashCount,
                                inCharacterClass: inCharacterClass
                            )
                        }
                        index = result.end
                        continue
                    }
                }

                if has(units, at: index, 0x22, 0x22, 0x22) {
                    let result = endOfString(
                        in: units,
                        after: index + 3,
                        quoteCount: 3,
                        hashCount: 0
                    )
                    if !result.closed {
                        multilineLiteral = .string(hashCount: 0)
                    }
                    index = result.end
                    continue
                }
                if units[index] == 0x60 {
                    let start = index + 1
                    var end = start
                    while end < units.count, units[end] != 0x60 {
                        end += scalarLength(in: units, at: end)
                    }
                    if end < units.count, isIdentifier(in: units[start..<end]) {
                        guard tokens.count < maximumCount else {
                            throw TextNavigationError.tooManyTokens(maximumTokens: maximumCount)
                        }
                        tokens.append(
                            Token(
                                text: String(decoding: units[start..<end], as: UTF16.self),
                                localRange: NSRange(location: start, length: end - start),
                                isIdentifier: true,
                                isEscapedIdentifier: true
                            ))
                        index = end + 1
                    } else {
                        if end == units.count {
                            multilineLiteral = .backtick
                        }
                        index = end == units.count ? end : end + 1
                    }
                    continue
                }
                if units[index] == 0x22 || units[index] == 0x27 {
                    let quote = units[index]
                    let result = endOfString(
                        in: units,
                        after: index + 1,
                        quoteCount: 1,
                        hashCount: 0,
                        quote: quote
                    )
                    continuedQuote = continuedQuoteState(
                        after: result,
                        quote: quote,
                        in: units
                    )
                    index = result.end
                    continue
                }
                if units[index] == 0x2F, canStartBareRegex(after: tokens.last) {
                    var inCharacterClass = false
                    let result = endOfRegex(
                        in: units,
                        after: index + 1,
                        hashCount: 0,
                        inCharacterClass: &inCharacterClass
                    )
                    if result.closed {
                        index = result.end
                        continue
                    }
                }

                let length = scalarLength(in: units, at: index)
                guard let currentScalar = scalar(in: units, at: index) else {
                    index += length
                    continue
                }
                if isIdentifierStart(currentScalar) {
                    let start = index
                    index += length
                    while index < units.count, let next = scalar(in: units, at: index),
                        isIdentifierContinuation(next)
                    {
                        index += scalarLength(in: units, at: index)
                    }
                    guard tokens.count < maximumCount else {
                        throw TextNavigationError.tooManyTokens(maximumTokens: maximumCount)
                    }
                    tokens.append(
                        Token(
                            text: String(decoding: units[start..<index], as: UTF16.self),
                            localRange: NSRange(location: start, length: index - start),
                            isIdentifier: true,
                            isEscapedIdentifier: false
                        ))
                    continue
                }
                if isPunctuation(units[index]) {
                    guard tokens.count < maximumCount else {
                        throw TextNavigationError.tooManyTokens(maximumTokens: maximumCount)
                    }
                    tokens.append(
                        Token(
                            text: String(UnicodeScalar(units[index])!),
                            localRange: NSRange(location: index, length: 1),
                            isIdentifier: false,
                            isEscapedIdentifier: false
                        ))
                }
                index += length
            }
            return tokens
        }

        private func endOfString(
            in units: [UInt16],
            after start: Int,
            quoteCount: Int,
            hashCount: Int,
            quote: UInt16 = 0x22
        ) -> (end: Int, closed: Bool) {
            var index = start
            while index < units.count {
                if units[index] == 0x5C,
                    hasRepeated(0x23, count: hashCount, in: units, at: index + 1)
                {
                    let escaped = index + 1 + hashCount
                    guard escaped < units.count else { return (units.count, false) }
                    index = escaped + scalarLength(in: units, at: escaped)
                    continue
                }
                if hasRepeated(quote, count: quoteCount, in: units, at: index),
                    hasExactHashes(
                        0x23,
                        count: hashCount,
                        in: units,
                        at: index + quoteCount
                    )
                {
                    return (index + quoteCount + hashCount, true)
                }
                index += scalarLength(in: units, at: index)
            }
            return (index, false)
        }

        private func endOfRegex(
            in units: [UInt16],
            after start: Int,
            hashCount: Int,
            inCharacterClass: inout Bool
        ) -> (end: Int, closed: Bool) {
            var index = start
            while index < units.count {
                if units[index] == 0x5C, index + 1 < units.count {
                    index += 1 + scalarLength(in: units, at: index + 1)
                    continue
                }
                if units[index] == 0x5B {
                    inCharacterClass = true
                } else if units[index] == 0x5D {
                    inCharacterClass = false
                } else if !inCharacterClass, units[index] == 0x2F,
                    hasExactHashes(
                        0x23,
                        count: hashCount,
                        in: units,
                        at: index + 1
                    )
                {
                    return (index + 1 + hashCount, true)
                }
                index += scalarLength(in: units, at: index)
            }
            return (index, false)
        }

        private func endOfBacktick(
            in units: [UInt16],
            after start: Int
        ) -> (end: Int, closed: Bool) {
            var index = start
            while index < units.count {
                if units[index] == 0x5C, index + 1 < units.count {
                    index += 1 + scalarLength(in: units, at: index + 1)
                } else if units[index] == 0x60 {
                    return (index + 1, true)
                } else {
                    index += scalarLength(in: units, at: index)
                }
            }
            return (index, false)
        }

        private func cPlusPlusRawStringOpening(
            in units: [UInt16],
            at start: Int
        ) -> (contentStart: Int, delimiter: [UInt16])? {
            let prefixes: [[UInt16]] = [
                [0x75, 0x38, 0x52, 0x22],
                [0x75, 0x52, 0x22],
                [0x55, 0x52, 0x22],
                [0x4C, 0x52, 0x22],
                [0x52, 0x22]
            ]
            guard
                start == 0
                    || scalar(in: units, at: start - 1).map({
                        !isIdentifierContinuation($0)
                    }) == true
            else {
                return nil
            }
            guard
                let prefix = prefixes.first(where: { prefix in
                    prefix.count <= units.count - start
                        && prefix.indices.allSatisfy { units[start + $0] == prefix[$0] }
                })
            else {
                return nil
            }

            let delimiterStart = start + prefix.count
            var index = delimiterStart
            while index < units.count, units[index] != 0x28 {
                guard index - delimiterStart < 16,
                    !isHorizontalWhitespace(units[index]),
                    units[index] != 0x29,
                    units[index] != 0x5C
                else {
                    return nil
                }
                index += 1
            }
            guard index < units.count else { return nil }
            return (index + 1, Array(units[delimiterStart..<index]))
        }

        private func endOfCPlusPlusRawString(
            in units: [UInt16],
            after start: Int,
            delimiter: [UInt16]
        ) -> (end: Int, closed: Bool) {
            var index = start
            while index < units.count {
                if units[index] == 0x29 {
                    let delimiterStart = index + 1
                    let quote = delimiterStart + delimiter.count
                    let delimiterMatches =
                        quote < units.count
                        && delimiter.indices.allSatisfy {
                            units[delimiterStart + $0] == delimiter[$0]
                        }
                    if quote < units.count,
                        delimiterMatches,
                        units[quote] == 0x22
                    {
                        return (quote + 1, true)
                    }
                }
                index += scalarLength(in: units, at: index)
            }
            return (index, false)
        }

        private func repeatedCount(
            of value: UInt16,
            in units: [UInt16],
            at start: Int
        ) -> Int {
            var index = start
            while index < units.count, units[index] == value { index += 1 }
            return index - start
        }

        private func hasRepeated(
            _ value: UInt16,
            count: Int,
            in units: [UInt16],
            at index: Int
        ) -> Bool {
            guard index >= 0, count <= units.count - index else { return false }
            return (0..<count).allSatisfy { units[index + $0] == value }
        }

        private func hasExactHashes(
            _ value: UInt16,
            count: Int,
            in units: [UInt16],
            at index: Int
        ) -> Bool {
            guard hasRepeated(value, count: count, in: units, at: index) else {
                return false
            }
            return count == 0 || index + count == units.count || units[index + count] != value
        }

        private func continuedQuoteState(
            after result: (end: Int, closed: Bool),
            quote: UInt16,
            in units: [UInt16]
        ) -> ContinuedQuote? {
            guard !result.closed, units.last == 0x5C else { return nil }
            var trailingBackslashes = 0
            var index = units.count
            while index > 0, units[index - 1] == 0x5C {
                trailingBackslashes += 1
                index -= 1
            }
            return ContinuedQuote(
                quote: quote,
                escapeNext: trailingBackslashes.isMultiple(of: 2)
            )
        }

        private func canStartBareRegex(after token: Token?) -> Bool {
            guard let token else { return true }
            if token.isIdentifier {
                return [
                    "await", "case", "else", "guard", "if", "in", "return", "throw",
                    "try", "where", "while"
                ].contains(token.text)
            }
            return [
                "=", "(", "[", "{", ",", ":", ";", "!", "?", "+", "-", "*",
                "%", "&", "|", "^", "~", "<", ">"
            ].contains(token.text)
        }

        private func has(_ units: [UInt16], at index: Int, _ values: UInt16...) -> Bool {
            guard values.count <= units.count - index else { return false }
            return values.indices.allSatisfy { units[index + $0] == values[$0] }
        }

        private func isIdentifier(in units: ArraySlice<UInt16>) -> Bool {
            guard !units.isEmpty else { return false }
            let values = Array(units)
            var index = 0
            guard let first = scalar(in: values, at: index), isIdentifierStart(first) else {
                return false
            }
            index += scalarLength(in: values, at: index)
            while index < values.count {
                guard let next = scalar(in: values, at: index),
                    isIdentifierContinuation(next)
                else {
                    return false
                }
                index += scalarLength(in: values, at: index)
            }
            return true
        }
    }

    public let lineIndex: TextLineIndex
    private let symbolsByName: [String: [DefinitionSymbol]]
    private let limits: TextNavigationLimits

    public var symbolCount: Int {
        symbolsByName.values.reduce(into: 0) { $0 += $1.count }
    }

    public init(text: String, limits: TextNavigationLimits = .default) throws {
        let lineIndex = try TextLineIndex(text: text, limits: limits)
        let language = Self.lexicalLanguage(in: text)
        var lexer = Lexer(language: language)
        var declarationState = DeclarationState()
        var symbolsByName: [String: [DefinitionSymbol]] = [:]
        var symbolCount = 0
        var tokenCount = 0
        var seenOffsets: Set<Int> = []

        for lineNumber in 1...lineIndex.lineCount {
            guard let line = lineIndex.line(at: lineNumber),
                let stringRange = Range(line.range, in: text)
            else {
                continue
            }
            let lineText = String(text[stringRange])
            let tokens: [Token]
            do {
                tokens = try lexer.tokens(
                    in: lineText,
                    maximumCount: limits.maximumTokenCount - tokenCount
                )
            } catch TextNavigationError.tooManyTokens {
                throw TextNavigationError.tooManyTokens(
                    maximumTokens: limits.maximumTokenCount
                )
            }
            tokenCount += tokens.count

            let declarations = Self.declarations(
                in: tokens,
                language: language,
                state: declarationState
            )
            declarationState.consume(tokens)
            var pending: [(token: Token, kind: DefinitionSymbolKind, offset: Int)] = []
            for declaration in declarations {
                let token = declaration.token
                let offset = line.range.location + token.localRange.location
                guard seenOffsets.insert(offset).inserted else { continue }
                guard token.localRange.length <= limits.maximumSymbolNameUTF16Length else {
                    throw TextNavigationError.symbolNameTooLong(
                        maximumUTF16Length: limits.maximumSymbolNameUTF16Length
                    )
                }
                guard symbolCount < limits.maximumSymbolCount else {
                    throw TextNavigationError.tooManySymbols(
                        maximumSymbols: limits.maximumSymbolCount
                    )
                }
                pending.append((token, declaration.kind, offset))
                symbolCount += 1
            }

            let columns = try Self.graphemeColumns(
                atUTF16Offsets: pending.map { $0.token.localRange.location },
                in: lineText,
                absoluteLineOffset: line.range.location
            )
            for (pendingDeclaration, column) in zip(pending, columns) {
                let token = pendingDeclaration.token
                let offset = pendingDeclaration.offset
                let location = TextLocation(
                    position: TextPosition(line: lineNumber, column: column),
                    utf16Column: token.localRange.location + 1,
                    utf16Offset: offset
                )
                let symbol = DefinitionSymbol(
                    name: token.text,
                    kind: pendingDeclaration.kind,
                    location: location,
                    nameRange: NSRange(location: offset, length: token.localRange.length),
                    declarationRange: line.range
                )
                symbolsByName[token.text, default: []].append(symbol)
            }
        }

        self.lineIndex = lineIndex
        self.symbolsByName = symbolsByName
        self.limits = limits
    }

    public func lookup(
        _ symbolName: String,
        maximumResults: Int? = nil
    ) throws -> DefinitionLookupResult {
        guard symbolName.utf16.count <= limits.maximumSymbolNameUTF16Length else {
            throw TextNavigationError.symbolNameTooLong(
                maximumUTF16Length: limits.maximumSymbolNameUTF16Length
            )
        }
        let maximumResults = maximumResults ?? limits.maximumLookupResults
        guard maximumResults > 0, maximumResults <= limits.maximumLookupResults else {
            throw TextNavigationError.invalidLookupLimit(maximumResults)
        }
        let matches = symbolsByName[symbolName] ?? []
        return DefinitionLookupResult(
            symbolName: symbolName,
            definitions: Array(matches.prefix(maximumResults)),
            isTruncated: matches.count > maximumResults
        )
    }

    public func definitions(
        named symbolName: String,
        maximumResults: Int? = nil
    ) throws -> [DefinitionSymbol] {
        try lookup(symbolName, maximumResults: maximumResults).definitions
    }

    public func symbolName(atUTF16Offset offset: Int) throws -> String? {
        let text = lineIndex.text
        var index = try lineIndex.stringIndex(atUTF16Offset: offset)
        if index == text.endIndex || !Self.isIdentifierCharacter(text[index]) {
            guard index > text.startIndex else { return nil }
            let previous = text.index(before: index)
            guard Self.isIdentifierCharacter(text[previous]) else { return nil }
            index = previous
        }

        var lower = index
        while lower > text.startIndex {
            let previous = text.index(before: lower)
            guard Self.isIdentifierCharacter(text[previous]) else { break }
            lower = previous
        }
        var upper = text.index(after: index)
        while upper < text.endIndex, Self.isIdentifierCharacter(text[upper]) {
            upper = text.index(after: upper)
        }
        let nameSlice = text[lower..<upper]
        guard let first = nameSlice.unicodeScalars.first, isIdentifierStart(first) else {
            return nil
        }
        guard nameSlice.utf16.count <= limits.maximumSymbolNameUTF16Length else {
            throw TextNavigationError.symbolNameTooLong(
                maximumUTF16Length: limits.maximumSymbolNameUTF16Length
            )
        }
        return String(nameSlice)
    }

    public func definition(
        forSymbolAtUTF16Offset offset: Int,
        maximumResults: Int? = nil
    ) throws -> DefinitionLookupResult? {
        guard let name = try symbolName(atUTF16Offset: offset) else { return nil }
        return try lookup(name, maximumResults: maximumResults)
    }

    private static func declarations(
        in tokens: [Token],
        language: LexicalLanguage,
        state: DeclarationState
    ) -> [(token: Token, kind: DefinitionSymbolKind)] {
        guard !tokens.isEmpty else { return [] }
        var declarations: [(Token, DefinitionSymbolKind)] = []

        func append(_ token: Token?, _ kind: DefinitionSymbolKind) {
            guard let token, token.isIdentifier else { return }
            declarations.append((token, kind))
        }

        if tokens.count >= 3, tokens[0].text == "#", tokens[1].text == "define" {
            append(tokens[2], .macro)
            return declarations
        }
        if tokens.first?.text == "#" {
            return []
        }

        for (index, token) in tokens.enumerated() where token.isIdentifier {
            guard !token.isEscapedIdentifier else { continue }
            switch token.text {
            case "class", "struct", "enum", "protocol", "actor", "union", "interface",
                "namespace", "trait", "record", "module":
                if token.text == "namespace", index > 0, tokens[index - 1].text == "using" {
                    break
                }
                if token.text == "class", index + 1 < tokens.count,
                    ["func", "let", "subscript", "var"].contains(tokens[index + 1].text)
                {
                    break
                }
                let name = nextIdentifier(
                    after: index,
                    in: tokens,
                    skipping: ["class", "struct"]
                )
                append(name?.token, .type)
            case "extension":
                append(nextIdentifier(after: index, in: tokens)?.token, .extensionDeclaration)
            case "typealias", "associatedtype":
                append(nextIdentifier(after: index, in: tokens)?.token, .type)
            case "type", "using":
                if token.text == "using", tokens.dropFirst(index + 1).first?.text == "namespace" {
                    break
                }
                if let name = nextIdentifier(after: index, in: tokens),
                    tokens.dropFirst(name.index + 1).contains(where: { $0.text == "=" })
                {
                    append(name.token, .type)
                }
            case "typedef":
                append(typedefName(after: index, in: tokens), .type)
            case "func", "function", "fn", "fun":
                append(nextIdentifier(after: index, in: tokens)?.token, .function)
            case "init":
                let previousIsMemberAccess = index > 0 && tokens[index - 1].text == "."
                if language.supportsSwiftDeclarations, index == 0, !previousIsMemberAccess,
                    tokens.dropFirst(index + 1).first(where: { $0.text != "?" && $0.text != "!" })?.text == "("
                {
                    append(token, .initializer)
                }
            case "let", "var":
                guard index == 0 || tokens[index - 1].text != "case" else { break }
                appendSwiftBindings(
                    after: index,
                    in: tokens,
                    kind: token.text == "let" ? .constant : .variable,
                    to: &declarations
                )
            case "const":
                append(
                    lastIdentifier(after: index, beforeAnyOf: ["=", ";", ","], in: tokens),
                    .constant)
            case "case":
                if language.supportsSwiftDeclarations,
                    state.isInsideEnum(before: index, in: tokens)
                {
                    appendCaseNames(after: index, in: tokens, to: &declarations)
                }
            default:
                break
            }
        }

        if language.supportsCLikeDeclarations {
            appendCEnumNames(in: tokens, state: state, to: &declarations)
            if let function = cLikeFunction(in: tokens) {
                append(function, .function)
            } else {
                let kind: DefinitionSymbolKind =
                    tokens.contains(where: { $0.text == "const" })
                    ? .constant : .variable
                for variable in cLikeVariables(in: tokens) {
                    append(variable, kind)
                }
            }
        }
        return declarations
    }

    private static func typedefName(after index: Int, in tokens: [Token]) -> Token? {
        guard index + 1 < tokens.count else { return nil }
        if let star = tokens[(index + 1)...].firstIndex(where: { $0.text == "*" }),
            star + 1 < tokens.count,
            tokens[star + 1].isIdentifier,
            tokens[(star + 1)...].contains(where: { $0.text == ")" })
        {
            return tokens[star + 1]
        }
        return lastIdentifier(after: index, beforeAnyOf: [";"], in: tokens)
    }

    private static func appendSwiftBindings(
        after index: Int,
        in tokens: [Token],
        kind: DefinitionSymbolKind,
        to declarations: inout [(Token, DefinitionSymbolKind)]
    ) {
        guard index + 1 < tokens.count else { return }
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var inInitializer = false
        var wantsName = true

        for token in tokens.dropFirst(index + 1) {
            if token.text == ";", parenthesisDepth == 0, bracketDepth == 0, braceDepth == 0 {
                break
            }
            if token.text == ",", parenthesisDepth == 0, bracketDepth == 0, braceDepth == 0 {
                inInitializer = false
                wantsName = true
                continue
            }
            if token.text == ",", !inInitializer {
                wantsName = true
                continue
            }
            if token.text == "=", parenthesisDepth == 0, bracketDepth == 0, braceDepth == 0 {
                inInitializer = true
                continue
            }
            if token.text == "(" { parenthesisDepth += 1 }
            if token.text == ")" { parenthesisDepth = max(0, parenthesisDepth - 1) }
            if token.text == "[" { bracketDepth += 1 }
            if token.text == "]" { bracketDepth = max(0, bracketDepth - 1) }
            if token.text == "{" { braceDepth += 1 }
            if token.text == "}" { braceDepth = max(0, braceDepth - 1) }

            guard !inInitializer, wantsName, token.isIdentifier,
                token.isEscapedIdentifier || !declarationKeywords.contains(token.text)
            else {
                continue
            }
            declarations.append((token, kind))
            wantsName = false
        }
    }

    private static func nextIdentifier(
        after index: Int,
        in tokens: [Token],
        skipping skipped: Set<String> = []
    ) -> (index: Int, token: Token)? {
        guard index + 1 < tokens.count else { return nil }
        for next in (index + 1)..<tokens.count {
            let token = tokens[next]
            if ["(", ")", "{", "=", ";"].contains(token.text) { return nil }
            if token.isIdentifier,
                token.isEscapedIdentifier
                    || (!skipped.contains(token.text)
                        && !declarationKeywords.contains(token.text))
            {
                return (next, token)
            }
        }
        return nil
    }

    private static func lastIdentifier(
        after index: Int,
        beforeAnyOf delimiters: Set<String>,
        in tokens: [Token]
    ) -> Token? {
        guard index + 1 < tokens.count else { return nil }
        var result: Token?
        for token in tokens[(index + 1)...] {
            if delimiters.contains(token.text) { break }
            if token.isIdentifier { result = token }
        }
        return result
    }

    private static func appendCaseNames(
        after index: Int,
        in tokens: [Token],
        to declarations: inout [(Token, DefinitionSymbolKind)]
    ) {
        var depth = 0
        for token in tokens.dropFirst(index + 1) {
            if token.text == "(" || token.text == "[" || token.text == "{" { depth += 1 }
            if token.text == ")" || token.text == "]" || token.text == "}" {
                depth = max(0, depth - 1)
            }
            if depth == 0, token.text == ":" { return }
        }

        depth = 0
        var wantsName = true
        for token in tokens.dropFirst(index + 1) {
            if depth == 0, token.text == "," {
                wantsName = true
                continue
            }
            if depth == 0, token.text == ";" { break }
            if depth == 0, wantsName, token.isIdentifier,
                token.isEscapedIdentifier || !declarationKeywords.contains(token.text)
            {
                declarations.append((token, .enumerationCase))
                wantsName = false
            }
            if token.text == "(" || token.text == "[" || token.text == "{" { depth += 1 }
            if token.text == ")" || token.text == "]" || token.text == "}" {
                depth = max(0, depth - 1)
            }
        }
    }

    private static func appendCEnumNames(
        in tokens: [Token],
        state: DeclarationState,
        to declarations: inout [(Token, DefinitionSymbolKind)]
    ) {
        var inEnum = state.isInsideEnum(before: 0, in: tokens)
        var pendingEnum = false
        var nestedDepth = 0
        var wantsName = inEnum

        for token in tokens {
            if token.text == "enum", !inEnum {
                pendingEnum = true
                continue
            }
            if pendingEnum, token.text == "{" {
                inEnum = true
                pendingEnum = false
                wantsName = true
                continue
            }
            guard inEnum else { continue }
            if token.text == "}" && nestedDepth == 0 { break }
            if token.text == "(" || token.text == "[" || token.text == "{" {
                nestedDepth += 1
                continue
            }
            if token.text == ")" || token.text == "]" || token.text == "}" {
                nestedDepth = max(0, nestedDepth - 1)
                continue
            }
            if token.text == ",", nestedDepth == 0 {
                wantsName = true
                continue
            }
            if wantsName, nestedDepth == 0, token.isIdentifier,
                token.isEscapedIdentifier || !declarationKeywords.contains(token.text)
            {
                declarations.append((token, .enumerationCase))
                wantsName = false
            }
        }
    }

    private static func cLikeFunction(in tokens: [Token]) -> Token? {
        let excluded = Set([
            "if", "for", "while", "switch", "catch", "return", "throw", "sizeof", "new",
            "delete", "case", "else", "do", "await", "try", "guard", "typedef"
        ])
        guard let parenthesis = tokens.firstIndex(where: { $0.text == "(" }),
            parenthesis > 0
        else { return nil }
        let candidateIndex = parenthesis - 1
        guard candidateIndex > 0, tokens[candidateIndex].isIdentifier else { return nil }
        let candidate = tokens[candidateIndex]
        guard !excluded.contains(candidate.text),
            candidate.isEscapedIdentifier || !declarationKeywords.contains(candidate.text),
            !tokens[..<candidateIndex].contains(where: { $0.text == "=" }),
            tokens[candidateIndex - 1].text != ".",
            let firstIdentifier = tokens[..<candidateIndex].first(where: \.isIdentifier),
            !excluded.contains(firstIdentifier.text),
            hasCDeclaratorPrefix(before: candidateIndex, in: tokens)
        else {
            return nil
        }
        return candidate
    }

    private static func hasCDeclaratorPrefix(before candidateIndex: Int, in tokens: [Token]) -> Bool {
        var prefixEnd = candidateIndex
        if candidateIndex >= 2,
            tokens[candidateIndex - 1].text == ":",
            tokens[candidateIndex - 2].text == ":"
        {
            guard let qualifier = cQualifiedName(before: candidateIndex, in: tokens) else {
                return false
            }
            prefixEnd = qualifier.start
            if prefixEnd == 0 {
                return qualifier.terminalName == tokens[candidateIndex].text
            }
        }

        let allowedPunctuation: Set<String> = [
            "<", ">", ",", "*", "&", "[", "]", "?"
        ]
        let prefix = tokens[..<prefixEnd]
        guard prefix.contains(where: \.isIdentifier) else { return false }

        var angleDepth = 0
        var bracketDepth = 0
        var index = prefix.startIndex
        while index < prefix.endIndex {
            let token = prefix[index]
            if token.text == ":" {
                let next = prefix.index(after: index)
                guard next < prefix.endIndex, prefix[next].text == ":" else { return false }
                index = prefix.index(after: next)
                continue
            }
            guard token.isIdentifier || allowedPunctuation.contains(token.text) else {
                return false
            }
            switch token.text {
            case "<":
                angleDepth += 1
            case ">":
                guard angleDepth > 0 else { return false }
                angleDepth -= 1
            case "[":
                bracketDepth += 1
            case "]":
                guard bracketDepth > 0 else { return false }
                bracketDepth -= 1
            case ",":
                guard angleDepth > 0 else { return false }
            default:
                break
            }
            index = prefix.index(after: index)
        }
        return angleDepth == 0 && bracketDepth == 0
    }

    private static func cQualifiedName(
        before candidateIndex: Int,
        in tokens: [Token]
    ) -> (start: Int, terminalName: String)? {
        var separator = candidateIndex - 2
        var start = separator
        var terminalName: String?

        while true {
            var componentEnd = separator
            if componentEnd > 0, tokens[componentEnd - 1].text == ">" {
                var depth = 1
                componentEnd -= 1
                while componentEnd > 0, depth > 0 {
                    componentEnd -= 1
                    if tokens[componentEnd].text == ">" { depth += 1 }
                    if tokens[componentEnd].text == "<" { depth -= 1 }
                }
                guard depth == 0 else { return nil }
            }
            guard componentEnd > 0, tokens[componentEnd - 1].isIdentifier else { return nil }
            let componentStart = componentEnd - 1
            if terminalName == nil {
                terminalName = tokens[componentStart].text
            }
            start = componentStart

            guard componentStart >= 2,
                tokens[componentStart - 1].text == ":",
                tokens[componentStart - 2].text == ":"
            else {
                break
            }
            separator = componentStart - 2
        }
        guard let terminalName else { return nil }
        return (start, terminalName)
    }

    private static func graphemeColumns(
        atUTF16Offsets offsets: [Int],
        in line: String,
        absoluteLineOffset: Int
    ) throws -> [Int] {
        let ordered = offsets.enumerated().sorted { $0.element < $1.element }
        var columns = Array(repeating: 0, count: offsets.count)
        var index = line.startIndex
        var utf16Offset = 0
        var column = 1

        for target in ordered {
            while utf16Offset < target.element, index < line.endIndex {
                let next = line.index(after: index)
                utf16Offset += line[index..<next].utf16.count
                index = next
                column += 1
            }
            guard utf16Offset == target.element else {
                throw TextNavigationError.offsetSplitsCharacter(
                    absoluteLineOffset + target.element
                )
            }
            columns[target.offset] = column
        }
        return columns
    }

    private static func cLikeVariables(in tokens: [Token]) -> [Token] {
        let excluded = Set([
            "return", "throw", "if", "for", "while", "switch", "case", "break", "continue",
            "goto", "import", "include", "package", "namespace", "typedef", "using"
        ])
        guard let first = tokens.first(where: \.isIdentifier),
            !excluded.contains(first.text),
            !tokens.contains(where: { $0.text == "(" || $0.text == ")" || $0.text == "." })
        else {
            return []
        }

        var segments: [Range<Int>] = []
        var start = 0
        var bracketDepth = 0
        var braceDepth = 0
        for index in tokens.indices {
            switch tokens[index].text {
            case "[": bracketDepth += 1
            case "]": bracketDepth = max(0, bracketDepth - 1)
            case "{": braceDepth += 1
            case "}": braceDepth = max(0, braceDepth - 1)
            case "," where bracketDepth == 0 && braceDepth == 0,
                ";" where bracketDepth == 0 && braceDepth == 0:
                if start < index { segments.append(start..<index) }
                start = index + 1
            default: break
            }
        }
        if start < tokens.count { segments.append(start..<tokens.count) }

        var variables: [Token] = []
        for (segmentNumber, segment) in segments.enumerated() {
            let boundary = segment.first(where: { tokens[$0].text == "=" }) ?? segment.upperBound
            guard let candidateIndex = tokens[segment.lowerBound..<boundary].lastIndex(where: \.isIdentifier),
                candidateIndex > 0,
                tokens[candidateIndex].isEscapedIdentifier
                    || !declarationKeywords.contains(tokens[candidateIndex].text)
            else {
                continue
            }
            if segmentNumber == 0 {
                guard hasCDeclaratorPrefix(before: candidateIndex, in: tokens) else { return [] }
            }
            variables.append(tokens[candidateIndex])
        }
        return variables
    }

    private static func lexicalLanguage(in text: String) -> LexicalLanguage {
        let swiftMarkers = [
            "func", "init", "let", "var", "protocol", "extension", "actor", "associatedtype",
            "typealias"
        ]
        let cMarkers = [
            "typedef", "union", "void", "char", "short", "int", "long", "float", "double",
            "signed", "unsigned"
        ]
        let swiftScore = swiftMarkers.reduce(into: 0) { score, marker in
            if text.range(of: "\\b\(marker)\\b", options: .regularExpression) != nil { score += 1 }
        }
        let cScore = cMarkers.reduce(into: 0) { score, marker in
            if text.range(of: "\\b\(marker)\\b", options: .regularExpression) != nil { score += 1 }
        }
        let hasPreprocessorDirective =
            text.range(
                of: #"(?m)^\s*#\s*(?:define|include)\b"#,
                options: .regularExpression
            ) != nil
        if swiftScore > cScore {
            return hasPreprocessorDirective || cScore > 0 ? .mixed : .swift
        }
        return .cLike
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(isIdentifierContinuation)
    }

    private static let declarationKeywords: Set<String> = [
        "actor", "associatedtype", "case", "class", "const", "enum", "extension", "fn",
        "func", "fun", "function", "interface", "let", "module", "namespace", "protocol",
        "record", "struct", "trait", "type", "typealias", "typedef", "union", "using", "var"
    ]
}

public typealias TextDefinitionIndex = DefinitionSymbolIndex
public typealias TextDefinitionSymbol = DefinitionSymbol

public enum TextNavigation {
    public static func lineIndex(
        for text: String,
        limits: TextNavigationLimits = .default
    ) throws -> TextLineIndex {
        try TextLineIndex(text: text, limits: limits)
    }

    public static func goToLine(
        _ line: Int,
        column: Int = 1,
        in text: String,
        clamping: TextNavigationClamping = .clamp,
        limits: TextNavigationLimits = .default
    ) throws -> TextLocation {
        try TextLineIndex(text: text, limits: limits).goToLine(
            line,
            column: column,
            clamping: clamping
        )
    }

    public static func definitionIndex(
        for text: String,
        limits: TextNavigationLimits = .default
    ) throws -> DefinitionSymbolIndex {
        try DefinitionSymbolIndex(text: text, limits: limits)
    }
}

private func scalarLength(in units: [UInt16], at index: Int) -> Int {
    guard (0xD800...0xDBFF).contains(units[index]), index + 1 < units.count,
        (0xDC00...0xDFFF).contains(units[index + 1])
    else {
        return 1
    }
    return 2
}

private func scalar(in units: [UInt16], at index: Int) -> UnicodeScalar? {
    let first = units[index]
    guard (0xD800...0xDBFF).contains(first) else { return UnicodeScalar(first) }
    guard index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) else {
        return nil
    }
    let high = UInt32(first - 0xD800)
    let low = UInt32(units[index + 1] - 0xDC00)
    return UnicodeScalar(0x10000 + (high << 10) + low)
}

private func isIdentifierStart(_ scalar: UnicodeScalar) -> Bool {
    if scalar == "_" || scalar == "$" { return true }
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
        .letterNumber, .modifierSymbol, .otherSymbol:
        return true
    default:
        return false
    }
}

private func isIdentifierContinuation(_ scalar: UnicodeScalar) -> Bool {
    if isIdentifierStart(scalar) { return true }
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .connectorPunctuation,
        .format:
        return true
    default:
        return false
    }
}

private func isHorizontalWhitespace(_ unit: UInt16) -> Bool {
    unit == 0x09 || unit == 0x0B || unit == 0x0C || unit == 0x20
}

private func isPunctuation(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E:
        return true
    default:
        return false
    }
}
