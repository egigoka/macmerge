import Foundation

extension CodingUserInfoKey {
    fileprivate static let textMarkersLimits = CodingUserInfoKey(rawValue: "MacMerge.TextMarkersLimits")!
}

enum TextMarkersCancellationPhase: Equatable, Sendable {
    case evaluatingMarker(String)
    case literalSearchChunk
    case regularExpressionProgress
    case encoded
    case decodePreflightComplete
}

enum TextMarkersTestHooks {
    @TaskLocal static var cancellationPhaseHandler: (@Sendable (TextMarkersCancellationPhase) -> Void)?
}

private struct TextMarkersWireJSONPreflight {
    private static let maximumNestingDepth = 16

    private let bytes: [UInt8]
    private let maximumMarkers: Int
    private let cancellationCheckInterval: Int
    private var index = 0
    private var lastCancellationCheckIndex = 0

    init(data: Data, maximumMarkers: Int, cancellationCheckInterval: Int) {
        bytes = Array(data)
        self.maximumMarkers = maximumMarkers
        self.cancellationCheckInterval = cancellationCheckInterval
    }

    mutating func validate() throws {
        try skipWhitespace()
        try parseRootObject()
        try skipWhitespace()
        guard index == bytes.count else { throw failure("Unexpected data after root object.") }
    }

    private mutating func parseRootObject() throws {
        try consume(0x7B, description: "Expected root object.")
        var keys: Set<String> = []
        try skipWhitespace()
        if consumeIfPresent(0x7D) { return }

        while true {
            let key = try parseKey()
            guard keys.insert(key).inserted else {
                throw failure("Duplicate root key: \(key).")
            }
            try skipWhitespace()
            try consume(0x3A, description: "Expected ':' after root key.")
            try skipWhitespace()
            switch key {
            case "schemaVersion", "activeMarkerID", "repeatDirection":
                try skipValue(depth: 1)
            case "markers":
                try parseMarkersArray()
            default:
                throw failure("Unknown root key: \(key).")
            }
            try skipWhitespace()
            if consumeIfPresent(0x7D) { return }
            try consume(0x2C, description: "Expected ',' between root members.")
            try skipWhitespace()
        }
    }

    private mutating func parseMarkersArray() throws {
        try consume(0x5B, description: "Expected markers array.")
        try skipWhitespace()
        if consumeIfPresent(0x5D) { return }

        var markerCount = 0
        while true {
            guard markerCount < maximumMarkers else {
                throw TextMarkersError.tooManyMarkers(maximumMarkers: maximumMarkers)
            }
            try parseMarkerObject(at: markerCount)
            markerCount += 1
            try skipWhitespace()
            if consumeIfPresent(0x5D) { return }
            try consume(0x2C, description: "Expected ',' between markers.")
            try skipWhitespace()
        }
    }

    private mutating func parseMarkerObject(at markerIndex: Int) throws {
        try consume(0x7B, description: "Expected marker object at index \(markerIndex).")
        var keys: Set<String> = []
        try skipWhitespace()
        if consumeIfPresent(0x7D) { return }

        while true {
            let key = try parseKey()
            guard keys.insert(key).inserted else {
                throw failure("Duplicate marker key at index \(markerIndex): \(key).")
            }
            try skipWhitespace()
            try consume(0x3A, description: "Expected ':' after marker key.")
            try skipWhitespace()
            switch key {
            case "id", "name", "pattern", "patternKind", "caseSensitive", "wholeWord",
                "colorToken":
                try skipValue(depth: 2)
            case "scope":
                try parseScopeObject(markerIndex: markerIndex)
            default:
                throw failure("Unknown marker key at index \(markerIndex): \(key).")
            }
            try skipWhitespace()
            if consumeIfPresent(0x7D) { return }
            try consume(0x2C, description: "Expected ',' between marker members.")
            try skipWhitespace()
        }
    }

    private mutating func parseScopeObject(markerIndex: Int) throws {
        try consume(0x7B, description: "Expected scope object at marker index \(markerIndex).")
        var keys: Set<String> = []
        var kind: String?
        try skipWhitespace()
        if consumeIfPresent(0x7D) { return }

        while true {
            let key = try parseKey()
            guard keys.insert(key).inserted else {
                throw failure("Duplicate scope key at marker index \(markerIndex): \(key).")
            }
            try skipWhitespace()
            try consume(0x3A, description: "Expected ':' after scope key.")
            try skipWhitespace()
            switch key {
            case "kind":
                if let decodedKind = try parseStringIfPresent() {
                    kind = decodedKind
                } else {
                    try skipValue(depth: 3)
                }
            case "location", "length", "firstLine", "lastLine":
                try skipValue(depth: 3)
            default:
                throw failure("Unknown scope key at marker index \(markerIndex): \(key).")
            }
            try skipWhitespace()
            if consumeIfPresent(0x7D) { break }
            try consume(0x2C, description: "Expected ',' between scope members.")
            try skipWhitespace()
        }

        let expectedKeys: Set<String>?
        switch kind {
        case "entireDocument":
            expectedKeys = ["kind"]
        case "utf16Range":
            expectedKeys = ["kind", "location", "length"]
        case "lineRange":
            expectedKeys = ["kind", "firstLine", "lastLine"]
        default:
            expectedKeys = nil
        }
        if let expectedKeys, keys != expectedKeys {
            throw failure("Illegal key combination for \(kind ?? "unknown") scope at marker index \(markerIndex).")
        }
    }

    private mutating func parseKey() throws -> String {
        guard let key = try parseStringIfPresent() else {
            throw failure("Expected JSON object key.")
        }
        return key
    }

    private mutating func parseStringIfPresent() throws -> String? {
        guard currentByte == 0x22 else { return nil }
        index += 1
        var decoded = String.UnicodeScalarView()
        while index < bytes.count {
            try checkCancellationIfNeeded()
            let byte = bytes[index]
            if byte == 0x22 {
                index += 1
                return String(decoded)
            }
            if byte == 0x5C {
                index += 1
                guard index < bytes.count else { throw failure("Unterminated JSON escape.") }
                let escaped = bytes[index]
                if escaped == 0x75 {
                    let first = try parseUnicodeEscape()
                    if (0xD800...0xDBFF).contains(first) {
                        guard index + 1 < bytes.count,
                            bytes[index] == 0x5C,
                            bytes[index + 1] == 0x75
                        else {
                            throw failure("Invalid JSON Unicode surrogate pair.")
                        }
                        index += 2
                        let second = try parseUnicodeEscapeDigits()
                        guard (0xDC00...0xDFFF).contains(second) else {
                            throw failure("Invalid JSON Unicode surrogate pair.")
                        }
                        let scalarValue =
                            0x10000 + ((UInt32(first) - 0xD800) << 10)
                            + (UInt32(second) - 0xDC00)
                        guard let scalar = Unicode.Scalar(scalarValue) else {
                            throw failure("Invalid JSON Unicode scalar.")
                        }
                        decoded.append(scalar)
                    } else {
                        guard !(0xDC00...0xDFFF).contains(first),
                            let scalar = Unicode.Scalar(first)
                        else {
                            throw failure("Invalid JSON Unicode scalar.")
                        }
                        decoded.append(scalar)
                    }
                    continue
                }
                guard let scalar = Self.escapedScalar(escaped) else {
                    throw failure("Invalid JSON escape.")
                }
                decoded.append(scalar)
                index += 1
                continue
            }
            guard byte >= 0x20 else { throw failure("Unescaped control byte in JSON string.") }
            let sequenceLength = Self.utf8SequenceLength(startingWith: byte)
            guard sequenceLength > 0, index + sequenceLength <= bytes.count,
                let text = String(bytes: bytes[index..<(index + sequenceLength)], encoding: .utf8)
            else {
                throw failure("Invalid UTF-8 in JSON string.")
            }
            decoded.append(contentsOf: text.unicodeScalars)
            index += sequenceLength
        }
        throw failure("Unterminated JSON string.")
    }

    private mutating func parseUnicodeEscape() throws -> UInt16 {
        index += 1
        return try parseUnicodeEscapeDigits()
    }

    private mutating func parseUnicodeEscapeDigits() throws -> UInt16 {
        guard index + 4 <= bytes.count else { throw failure("Invalid JSON Unicode escape.") }
        var value: UInt16 = 0
        for byte in bytes[index..<(index + 4)] {
            guard let digit = Self.hexDigitValue(byte) else {
                throw failure("Invalid JSON Unicode escape.")
            }
            value = value * 16 + UInt16(digit)
        }
        index += 4
        return value
    }

    private mutating func skipValue(depth: Int) throws {
        guard depth <= Self.maximumNestingDepth else {
            throw failure("JSON nesting exceeds strict decoder limit.")
        }
        try checkCancellationIfNeeded()
        guard let byte = currentByte else { throw failure("Expected JSON value.") }
        switch byte {
        case 0x22:
            _ = try parseStringIfPresent()
        case 0x7B:
            try skipObject(depth: depth)
        case 0x5B:
            try skipArray(depth: depth)
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try skipNumber()
        default:
            throw failure("Expected JSON value.")
        }
    }

    private mutating func skipObject(depth: Int) throws {
        try consume(0x7B, description: "Expected JSON object.")
        try skipWhitespace()
        if consumeIfPresent(0x7D) { return }
        while true {
            _ = try parseKey()
            try skipWhitespace()
            try consume(0x3A, description: "Expected ':' after object key.")
            try skipWhitespace()
            try skipValue(depth: depth + 1)
            try skipWhitespace()
            if consumeIfPresent(0x7D) { return }
            try consume(0x2C, description: "Expected ',' between object members.")
            try skipWhitespace()
        }
    }

    private mutating func skipArray(depth: Int) throws {
        try consume(0x5B, description: "Expected JSON array.")
        try skipWhitespace()
        if consumeIfPresent(0x5D) { return }
        while true {
            try skipValue(depth: depth + 1)
            try skipWhitespace()
            if consumeIfPresent(0x5D) { return }
            try consume(0x2C, description: "Expected ',' between array values.")
            try skipWhitespace()
        }
    }

    private mutating func skipNumber() throws {
        _ = consumeIfPresent(0x2D)
        if consumeIfPresent(0x30) {
            guard currentByte.map({ $0 < 0x30 || $0 > 0x39 }) ?? true else {
                throw failure("Leading zero in JSON number.")
            }
        } else {
            guard consumeDigit(in: 0x31...0x39) else { throw failure("Invalid JSON number.") }
            try consumeDigits(in: 0x30...0x39)
        }
        if consumeIfPresent(0x2E) {
            guard consumeDigit(in: 0x30...0x39) else {
                throw failure("Missing JSON fractional digits.")
            }
            try consumeDigits(in: 0x30...0x39)
        }
        if currentByte == 0x65 || currentByte == 0x45 {
            index += 1
            if currentByte == 0x2B || currentByte == 0x2D { index += 1 }
            guard consumeDigit(in: 0x30...0x39) else {
                throw failure("Missing JSON exponent digits.")
            }
            try consumeDigits(in: 0x30...0x39)
        }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = Array(String(describing: literal).utf8)
        guard index + literalBytes.count <= bytes.count,
            bytes[index..<(index + literalBytes.count)].elementsEqual(literalBytes)
        else {
            throw failure("Invalid JSON literal.")
        }
        index += literalBytes.count
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
            try checkCancellationIfNeeded()
        }
    }

    private mutating func consume(_ byte: UInt8, description: String) throws {
        guard consumeIfPresent(byte) else { throw failure(description) }
    }

    private mutating func consumeDigit(in range: ClosedRange<UInt8>) -> Bool {
        guard let byte = currentByte, range.contains(byte) else { return false }
        index += 1
        return true
    }

    private mutating func consumeDigits(in range: ClosedRange<UInt8>) throws {
        while consumeDigit(in: range) {
            try checkCancellationIfNeeded()
        }
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private mutating func checkCancellationIfNeeded() throws {
        if index - lastCancellationCheckIndex >= cancellationCheckInterval {
            try Task.checkCancellation()
            lastCancellationCheckIndex = index
        }
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func escapedScalar(_ byte: UInt8) -> Unicode.Scalar? {
        switch byte {
        case 0x22, 0x2F, 0x5C: Unicode.Scalar(byte)
        case 0x62: "\u{08}"
        case 0x66: "\u{0C}"
        case 0x6E: "\n"
        case 0x72: "\r"
        case 0x74: "\t"
        default: nil
        }
    }

    private static func hexDigitValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    private static func utf8SequenceLength(startingWith byte: UInt8) -> Int {
        switch byte {
        case 0x00...0x7F: 1
        case 0xC2...0xDF: 2
        case 0xE0...0xEF: 3
        case 0xF0...0xF4: 4
        default: 0
        }
    }

    private func failure(_ description: String) -> DecodingError {
        DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: description)
        )
    }
}

public struct TextMarkerDocumentRevision: RawRepresentable, Codable, Comparable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TextMarkerDocumentRevision, rhs: TextMarkerDocumentRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TextMarkerDocument: Equatable, Sendable {
    public let text: String
    public let revision: TextMarkerDocumentRevision

    public init(text: String, revision: TextMarkerDocumentRevision) {
        self.text = text
        self.revision = revision
    }
}

/// UI-independent semantic color name, such as `search.primary` or `warning`.
public struct TextMarkerColorToken: Codable, Equatable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 128
    public static let `default` = TextMarkerColorToken(uncheckedRawValue: "search-marker")

    public let rawValue: String

    public init(rawValue: String) throws {
        try Self.validate(rawValue)
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        do {
            try self.init(rawValue: rawValue)
        } catch let error as TextMarkersError {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }

    fileprivate static func validate(_ value: String, maximumUTF8Bytes: Int = maximumUTF8Bytes) throws {
        guard !value.isEmpty else { throw TextMarkersError.invalidColorToken(value) }
        guard value.utf8.count <= maximumUTF8Bytes else {
            throw TextMarkersError.colorTokenTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
        }
        guard value.unicodeScalars.allSatisfy(Self.isSemanticTokenScalar) else {
            throw TextMarkersError.invalidColorToken(value)
        }
    }

    private static func isSemanticTokenScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
            || scalar == "-" || scalar == "_" || scalar == "." || scalar == ":" || scalar == "/"
    }
}

public enum TextMarkerScope: Codable, Equatable, Sendable {
    /// Scope is an eligibility filter over full-document search results. Regex anchors,
    /// lookarounds, and overlap selection therefore keep `TextSearch` document semantics.
    case entireDocument
    /// Zero-based UTF-16 range. Both endpoints must be extended-grapheme boundaries.
    case utf16Range(NSRange)
    /// Inclusive one-based logical line range.
    case lineRange(ClosedRange<Int>)

    private enum Kind: String, Codable {
        case entireDocument
        case utf16Range
        case lineRange
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case location
        case length
        case firstLine
        case lastLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .entireDocument:
            self = .entireDocument
        case .utf16Range:
            let range = NSRange(
                location: try container.decode(Int.self, forKey: .location),
                length: try container.decode(Int.self, forKey: .length)
            )
            do {
                try Self.validate(range)
            } catch let error as TextMarkersError {
                throw DecodingError.dataCorruptedError(
                    forKey: .location,
                    in: container,
                    debugDescription: error.localizedDescription
                )
            }
            self = .utf16Range(range)
        case .lineRange:
            let firstLine = try container.decode(Int.self, forKey: .firstLine)
            let lastLine = try container.decode(Int.self, forKey: .lastLine)
            guard firstLine > 0, lastLine >= firstLine else {
                throw DecodingError.dataCorruptedError(
                    forKey: .firstLine,
                    in: container,
                    debugDescription: TextMarkersError.invalidLineRange(
                        lowerBound: firstLine,
                        upperBound: lastLine
                    ).localizedDescription
                )
            }
            self = .lineRange(firstLine...lastLine)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .entireDocument:
            try container.encode(Kind.entireDocument, forKey: .kind)
        case .utf16Range(let range):
            try Self.validate(range)
            try container.encode(Kind.utf16Range, forKey: .kind)
            try container.encode(range.location, forKey: .location)
            try container.encode(range.length, forKey: .length)
        case .lineRange(let range):
            guard range.lowerBound > 0 else {
                throw TextMarkersError.invalidLineRange(
                    lowerBound: range.lowerBound,
                    upperBound: range.upperBound
                )
            }
            try container.encode(Kind.lineRange, forKey: .kind)
            try container.encode(range.lowerBound, forKey: .firstLine)
            try container.encode(range.upperBound, forKey: .lastLine)
        }
    }

    fileprivate func validate() throws {
        switch self {
        case .entireDocument:
            break
        case .utf16Range(let range):
            try Self.validate(range)
        case .lineRange(let range):
            guard range.lowerBound > 0 else {
                throw TextMarkersError.invalidLineRange(
                    lowerBound: range.lowerBound,
                    upperBound: range.upperBound
                )
            }
        }
    }

    private static func validate(_ range: NSRange) throws {
        let (_, overflow) = range.location.addingReportingOverflow(range.length)
        guard range.location >= 0, range.length >= 0, !overflow else {
            throw TextMarkersError.invalidUTF16Range(range)
        }
    }
}

public struct NamedTextMarker: Codable, Equatable, Sendable {
    public static let maximumIdentifierUTF8Bytes = 128
    public static let maximumNameUTF8Bytes = 256
    public static let maximumPatternUTF16Length = 64 * 1024

    public let id: String
    public let name: String
    public let query: TextSearchQuery
    public let colorToken: TextMarkerColorToken
    public let scope: TextMarkerScope

    public init(
        id: String,
        name: String,
        query: TextSearchQuery,
        colorToken: TextMarkerColorToken = .default,
        scope: TextMarkerScope = .entireDocument
    ) throws {
        self.id = id
        self.name = name
        self.query = query
        self.colorToken = colorToken
        self.scope = scope
        try validate()
    }

    public init(
        id: String,
        name: String,
        literal: String,
        caseSensitive: Bool = true,
        wholeWord: Bool = false,
        colorToken: TextMarkerColorToken = .default,
        scope: TextMarkerScope = .entireDocument
    ) throws {
        try self.init(
            id: id,
            name: name,
            query: TextSearchQuery(
                literal: literal,
                caseSensitive: caseSensitive,
                wholeWord: wholeWord
            ),
            colorToken: colorToken,
            scope: scope
        )
    }

    public init(
        id: String,
        name: String,
        regularExpression: String,
        caseSensitive: Bool = true,
        wholeWord: Bool = false,
        colorToken: TextMarkerColorToken = .default,
        scope: TextMarkerScope = .entireDocument
    ) throws {
        try self.init(
            id: id,
            name: name,
            query: TextSearchQuery(
                regularExpression: regularExpression,
                caseSensitive: caseSensitive,
                wholeWord: wholeWord
            ),
            colorToken: colorToken,
            scope: scope
        )
    }

    private enum PatternKind: String, Codable {
        case literal
        case regularExpression
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case pattern
        case patternKind
        case caseSensitive
        case wholeWord
        case colorToken
        case scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = decoder.userInfo[.textMarkersLimits] as? TextMarkersLimits
        let pattern = try container.decode(String.self, forKey: .pattern)
        let query: TextSearchQuery
        switch try container.decode(PatternKind.self, forKey: .patternKind) {
        case .literal:
            query = TextSearchQuery(
                literal: pattern,
                caseSensitive: try container.decode(Bool.self, forKey: .caseSensitive),
                wholeWord: try container.decode(Bool.self, forKey: .wholeWord)
            )
        case .regularExpression:
            query = TextSearchQuery(
                regularExpression: pattern,
                caseSensitive: try container.decode(Bool.self, forKey: .caseSensitive),
                wholeWord: try container.decode(Bool.self, forKey: .wholeWord)
            )
        }
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        self.query = query
        colorToken = try container.decode(TextMarkerColorToken.self, forKey: .colorToken)
        scope = try container.decode(TextMarkerScope.self, forKey: .scope)
        do {
            _ = try validateStructure(limits: limits)
            if limits == nil {
                try Task.checkCancellation()
                try validatePattern(searchLimits: .default)
            }
        } catch let error as TextMarkersError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.localizedDescription)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        let limits = encoder.userInfo[.textMarkersLimits] as? TextMarkersLimits
        _ = try validateStructure(limits: limits)
        if limits == nil {
            try Task.checkCancellation()
            try validatePattern(searchLimits: .default)
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(query.pattern.text, forKey: .pattern)
        switch query.pattern {
        case .literal:
            try container.encode(PatternKind.literal, forKey: .patternKind)
        case .regularExpression:
            try container.encode(PatternKind.regularExpression, forKey: .patternKind)
        }
        try container.encode(query.caseSensitive, forKey: .caseSensitive)
        try container.encode(query.wholeWord, forKey: .wholeWord)
        try container.encode(colorToken, forKey: .colorToken)
        try container.encode(scope, forKey: .scope)
    }

    fileprivate func validate() throws {
        _ = try validateStructure(limits: nil)
        try Task.checkCancellation()
        try validatePattern(searchLimits: .default)
    }

    fileprivate func validateStructure(limits: TextMarkersLimits?) throws -> Int {
        let maximumIdentifierBytes =
            limits?.maximumIdentifierUTF8Bytes
            ?? Self.maximumIdentifierUTF8Bytes
        let maximumNameBytes = limits?.maximumNameUTF8Bytes ?? Self.maximumNameUTF8Bytes
        let maximumColorBytes =
            limits?.maximumColorTokenUTF8Bytes
            ?? TextMarkerColorToken.maximumUTF8Bytes
        let maximumPatternLength = Swift.min(
            limits?.searchLimits.maximumPatternUTF16Length ?? Self.maximumPatternUTF16Length,
            Self.maximumPatternUTF16Length
        )

        try Self.validateIdentifier(id, maximumUTF8Bytes: maximumIdentifierBytes)
        try Self.validateName(name, maximumUTF8Bytes: maximumNameBytes)
        try TextMarkerColorToken.validate(
            colorToken.rawValue,
            maximumUTF8Bytes: maximumColorBytes
        )
        try scope.validate()
        if let limits {
            switch scope {
            case .entireDocument:
                break
            case .utf16Range(let range):
                guard range.length <= limits.maximumScopeUTF16Length else {
                    throw TextMarkersError.scopeTooLarge(
                        markerID: id,
                        maximumUTF16Length: limits.maximumScopeUTF16Length
                    )
                }
            case .lineRange(let range):
                guard range.upperBound <= limits.maximumLineCount else {
                    throw TextMarkersError.lineRangeExceedsLimit(
                        maximumLine: limits.maximumLineCount
                    )
                }
            }
        }
        guard query.pattern.text.utf16.count <= maximumPatternLength else {
            throw TextMarkersError.patternTooLarge(maximumUTF16Length: maximumPatternLength)
        }
        if case .literal(let pattern) = query.pattern, pattern.isEmpty {
            throw TextMarkersError.emptyLiteralPattern
        }
        return query.pattern.text.utf16.count
    }

    fileprivate func validatePattern(searchLimits: TextSearchLimits) throws {
        guard case .regularExpression = query.pattern else { return }
        do {
            _ = try TextMarkers.regularExpressionMarkerRanges(
                in: "",
                matching: query,
                scopeRange: NSRange(location: 0, length: 0),
                includesUpperBoundZeroLengthMatch: true,
                limits: searchLimits,
                maximumMatches: searchLimits.maximumMatches,
                maximumTotalMatches: searchLimits.maximumMatches,
                maximumCaptureRanges: searchLimits.maximumStoredCaptureRanges,
                maximumTotalCaptureRanges: searchLimits.maximumStoredCaptureRanges,
                maximumResultRanges: searchLimits.maximumMatches,
                maximumTotalResultRanges: searchLimits.maximumMatches,
                maximumWorkUnits: Int.max,
                maximumTotalWorkUnits: Int.max
            )
        } catch TextSearchError.invalidPattern {
            throw TextMarkersError.invalidRegularExpression(query.pattern.text)
        }
    }

    private static func validateIdentifier(_ id: String, maximumUTF8Bytes: Int) throws {
        guard !id.isEmpty, id == id.trimmingCharacters(in: .whitespacesAndNewlines),
            id.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
                    && !CharacterSet.whitespacesAndNewlines.contains($0)
            })
        else {
            throw TextMarkersError.invalidIdentifier(id)
        }
        guard id.utf8.count <= maximumUTF8Bytes else {
            throw TextMarkersError.identifierTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
        }
    }

    private static func validateName(_ name: String, maximumUTF8Bytes: Int) throws {
        guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
            name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            throw TextMarkersError.invalidName(name)
        }
        guard name.utf8.count <= maximumUTF8Bytes else {
            throw TextMarkersError.nameTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
        }
    }

}

public struct TextMarkersLimits: Equatable, Sendable {
    public static let `default` = TextMarkersLimits()

    public let maximumMarkers: Int
    public let maximumIdentifierUTF8Bytes: Int
    public let maximumNameUTF8Bytes: Int
    public let maximumColorTokenUTF8Bytes: Int
    public let maximumLineCount: Int
    public let maximumLineUTF16Length: Int
    public let maximumScopeUTF16Length: Int
    public let maximumResultRanges: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int
    public let maximumEncodedBytes: Int
    public let searchLimits: TextSearchLimits

    public init(
        maximumMarkers: Int = TextMarkers.maximumMarkerCount,
        maximumIdentifierUTF8Bytes: Int = NamedTextMarker.maximumIdentifierUTF8Bytes,
        maximumNameUTF8Bytes: Int = NamedTextMarker.maximumNameUTF8Bytes,
        maximumColorTokenUTF8Bytes: Int = TextMarkerColorToken.maximumUTF8Bytes,
        maximumLineCount: Int = 1_000_000,
        maximumLineUTF16Length: Int = 1024 * 1024,
        maximumScopeUTF16Length: Int = 64 * 1024 * 1024,
        maximumResultRanges: Int = 100_000,
        maximumWorkUnits: Int = 256 * 1024 * 1024,
        cancellationCheckInterval: Int = 4_096,
        maximumEncodedBytes: Int = TextMarkers.maximumEncodedBytes,
        searchLimits: TextSearchLimits = .default
    ) {
        self.maximumMarkers = maximumMarkers
        self.maximumIdentifierUTF8Bytes = maximumIdentifierUTF8Bytes
        self.maximumNameUTF8Bytes = maximumNameUTF8Bytes
        self.maximumColorTokenUTF8Bytes = maximumColorTokenUTF8Bytes
        self.maximumLineCount = maximumLineCount
        self.maximumLineUTF16Length = maximumLineUTF16Length
        self.maximumScopeUTF16Length = maximumScopeUTF16Length
        self.maximumResultRanges = maximumResultRanges
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
        self.maximumEncodedBytes = maximumEncodedBytes
        self.searchLimits = searchLimits
    }
}

public enum TextMarkersError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case invalidIdentifier(String)
    case identifierTooLarge(maximumUTF8Bytes: Int)
    case invalidName(String)
    case nameTooLarge(maximumUTF8Bytes: Int)
    case invalidColorToken(String)
    case colorTokenTooLarge(maximumUTF8Bytes: Int)
    case emptyLiteralPattern
    case patternTooLarge(maximumUTF16Length: Int)
    case invalidRegularExpression(String)
    case invalidUTF16Range(NSRange)
    case utf16RangeOutOfBounds(range: NSRange, documentUTF16Length: Int)
    case utf16RangeSplitsCharacter(NSRange)
    case invalidLineRange(lowerBound: Int, upperBound: Int)
    case lineRangeExceedsLimit(maximumLine: Int)
    case lineRangeOutOfBounds(range: ClosedRange<Int>, lineCount: Int)
    case scopeTooLarge(markerID: String, maximumUTF16Length: Int)
    case tooManyMarkers(maximumMarkers: Int)
    case combinedPatternsTooLarge(maximumUTF16Length: Int)
    case duplicateIdentifier(String)
    case duplicateName(String)
    case unknownMarker(String)
    case noActiveMarker
    case tooManyResultRanges(maximumRanges: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case invalidNavigationOffset(Int)
    case navigationOffsetSplitsCharacter(Int)
    case invalidCurrentMatch(TextMarkerRange)
    case staleMatchSet
    case staleDocument
    case staleDocumentRevision(
        expected: TextMarkerDocumentRevision,
        actual: TextMarkerDocumentRevision
    )
    case encodedDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Text marker limits are invalid."
        case .invalidIdentifier(let id):
            "Text marker identifier is invalid: \(id)."
        case .identifierTooLarge(let maximumUTF8Bytes):
            "Text marker identifier exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .invalidName(let name):
            "Text marker name is invalid: \(name)."
        case .nameTooLarge(let maximumUTF8Bytes):
            "Text marker name exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .invalidColorToken(let token):
            "Text marker color token is invalid: \(token)."
        case .colorTokenTooLarge(let maximumUTF8Bytes):
            "Text marker color token exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .emptyLiteralPattern:
            "A literal text marker pattern must not be empty."
        case .patternTooLarge(let maximumUTF16Length):
            "Text marker pattern exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .invalidRegularExpression(let pattern):
            "Text marker regular expression is invalid: \(pattern)."
        case .invalidUTF16Range(let range):
            "Text marker UTF-16 range is invalid: \(NSStringFromRange(range))."
        case .utf16RangeOutOfBounds(let range, let documentUTF16Length):
            "Text marker UTF-16 range \(NSStringFromRange(range)) is outside a \(documentUTF16Length)-unit document."
        case .utf16RangeSplitsCharacter(let range):
            "Text marker UTF-16 range splits an extended grapheme cluster: \(NSStringFromRange(range))."
        case .invalidLineRange(let lowerBound, let upperBound):
            "Text marker line range \(lowerBound)...\(upperBound) is invalid."
        case .lineRangeExceedsLimit(let maximumLine):
            "Text marker line range exceeds the \(maximumLine)-line limit."
        case .lineRangeOutOfBounds(let range, let lineCount):
            "Text marker line range \(range.lowerBound)...\(range.upperBound) is outside a \(lineCount)-line document."
        case .scopeTooLarge(let markerID, let maximumUTF16Length):
            "Text marker \(markerID) scope exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .tooManyMarkers(let maximumMarkers):
            "Text markers exceed the \(maximumMarkers)-marker limit."
        case .combinedPatternsTooLarge(let maximumUTF16Length):
            "Text marker patterns exceed the combined \(maximumUTF16Length)-UTF-16-unit limit."
        case .duplicateIdentifier(let id):
            "Text marker identifier is duplicated: \(id)."
        case .duplicateName(let name):
            "Text marker name is duplicated: \(name)."
        case .unknownMarker(let id):
            "Text marker does not exist: \(id)."
        case .noActiveMarker:
            "No text marker is active."
        case .tooManyResultRanges(let maximumRanges):
            "Text marker search exceeds the \(maximumRanges)-range limit."
        case .workLimitExceeded(let maximumWorkUnits):
            "Text marker search exceeds the \(maximumWorkUnits)-unit work limit."
        case .invalidNavigationOffset(let offset):
            "Text marker navigation offset is outside the document: \(offset)."
        case .navigationOffsetSplitsCharacter(let offset):
            "Text marker navigation offset splits an extended grapheme cluster: \(offset)."
        case .invalidCurrentMatch(let match):
            "Text marker repeat match is not in the computed result: \(match.markerID) at \(NSStringFromRange(match.range))."
        case .staleMatchSet:
            "Text marker navigation result belongs to a different match set."
        case .staleDocument:
            "Text marker results belong to different document content."
        case .staleDocumentRevision(let expected, let actual):
            "Text marker results are stale (computed for revision \(expected.rawValue), current revision \(actual.rawValue))."
        case .encodedDataTooLarge(let maximumBytes):
            "Text marker persistence data exceeds the \(maximumBytes)-byte limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported text marker schema version: \(version)."
        }
    }
}

public struct TextMarkerNavigationResult: Equatable, Sendable {
    public let match: TextMarkerRange?
    public let didWrap: Bool
    public let direction: TextSearchDirection
    fileprivate let matchSetID: UUID

    public static func == (lhs: TextMarkerNavigationResult, rhs: TextMarkerNavigationResult) -> Bool {
        lhs.matchSetID == rhs.matchSetID
            && lhs.match == rhs.match
            && lhs.didWrap == rhs.didWrap
            && lhs.direction == rhs.direction
    }
}

private struct TextMarkerDocumentFingerprint: Equatable, Sendable {
    private let text: String

    init(text: String) {
        self.text = text
    }

    func matches(_ candidate: String, cancellationCheckInterval: Int) throws -> Bool {
        try Task.checkCancellation()
        var candidateIterator = candidate.utf8.makeIterator()
        var expectedIterator = text.utf8.makeIterator()
        var bytesSinceCancellationCheck = 0
        while true {
            let candidateByte = candidateIterator.next()
            let expectedByte = expectedIterator.next()
            if candidateByte == nil || expectedByte == nil {
                try Task.checkCancellation()
                return candidateByte == nil && expectedByte == nil
            }
            guard candidateByte == expectedByte else { return false }
            bytesSinceCancellationCheck += 1
            if bytesSinceCancellationCheck == cancellationCheckInterval {
                try Task.checkCancellation()
                bytesSinceCancellationCheck = 0
            }
        }
    }
}

private struct TextMarkerLineIndex {
    private struct Record {
        let start: Int
        let contentEnd: Int
        let end: Int
    }

    private let records: [Record]

    var lineCount: Int { records.count }

    init(
        text: String,
        limits: TextMarkersLimits,
        work: inout TextMarkerWorkBudget
    ) throws {
        var records: [Record] = []
        records.reserveCapacity(Swift.min(limits.maximumLineCount, 4_096))
        var lineStart = 0
        var offset = 0
        var pendingWork = 0
        var iterator = text.utf16.makeIterator()
        var pending = iterator.next()

        try Task.checkCancellation()
        while let unit = pending {
            pending = iterator.next()
            guard unit == 0x0A || unit == 0x0D else {
                offset += 1
                pendingWork += 1
                guard offset - lineStart <= limits.maximumLineUTF16Length else {
                    throw TextNavigationError.lineTooLong(
                        line: records.count + 1,
                        maximumUTF16Length: limits.maximumLineUTF16Length
                    )
                }
                let workThreshold = Swift.min(
                    limits.cancellationCheckInterval,
                    Swift.max(1, work.remainingWorkUnits)
                )
                if pendingWork >= workThreshold {
                    try work.consume(pendingWork)
                    pendingWork = 0
                }
                continue
            }

            let terminatorLength: Int
            if unit == 0x0D, pending == 0x0A {
                terminatorLength = 2
                pending = iterator.next()
            } else {
                terminatorLength = 1
            }
            guard records.count < limits.maximumLineCount else {
                throw TextNavigationError.tooManyLines(maximumLines: limits.maximumLineCount)
            }
            records.append(
                Record(
                    start: lineStart,
                    contentEnd: offset,
                    end: offset + terminatorLength
                )
            )
            offset += terminatorLength
            lineStart = offset
            pendingWork += terminatorLength
            let workThreshold = Swift.min(
                limits.cancellationCheckInterval,
                Swift.max(1, work.remainingWorkUnits)
            )
            if pendingWork >= workThreshold {
                try work.consume(pendingWork)
                pendingWork = 0
            }
        }
        if pendingWork > 0 {
            try work.consume(pendingWork)
        }
        guard records.count < limits.maximumLineCount else {
            throw TextNavigationError.tooManyLines(maximumLines: limits.maximumLineCount)
        }
        records.append(Record(start: lineStart, contentEnd: offset, end: offset))
        try Task.checkCancellation()
        self.records = records
    }

    func line(at number: Int) -> TextLine? {
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
}

/// Immutable, revision-tagged ranges produced by one marker configuration and document snapshot.
public struct TextMarkerMatchSet: Equatable, Sendable {
    public let documentRevision: TextMarkerDocumentRevision
    public let documentUTF16Length: Int
    public let markers: [NamedTextMarker]
    public let activeMarkerID: String?
    public let repeatDirection: TextSearchDirection
    private let id: UUID
    private let documentFingerprint: TextMarkerDocumentFingerprint
    private let storedRanges: [TextMarkerRange]
    private let cancellationCheckInterval: Int

    fileprivate init(
        documentRevision: TextMarkerDocumentRevision,
        documentUTF16Length: Int,
        documentFingerprint: TextMarkerDocumentFingerprint,
        markers: [NamedTextMarker],
        activeMarkerID: String?,
        repeatDirection: TextSearchDirection,
        ranges: [TextMarkerRange],
        cancellationCheckInterval: Int,
        id: UUID = UUID()
    ) {
        self.documentRevision = documentRevision
        self.documentUTF16Length = documentUTF16Length
        self.markers = markers
        self.activeMarkerID = activeMarkerID
        self.repeatDirection = repeatDirection
        self.id = id
        self.documentFingerprint = documentFingerprint
        storedRanges = ranges
        self.cancellationCheckInterval = cancellationCheckInterval
    }

    public static func == (lhs: TextMarkerMatchSet, rhs: TextMarkerMatchSet) -> Bool {
        lhs.id == rhs.id
            && lhs.documentRevision == rhs.documentRevision
            && lhs.documentUTF16Length == rhs.documentUTF16Length
            && lhs.documentFingerprint == rhs.documentFingerprint
            && lhs.markers == rhs.markers
            && lhs.activeMarkerID == rhs.activeMarkerID
            && lhs.repeatDirection == rhs.repeatDirection
            && lhs.storedRanges == rhs.storedRanges
            && lhs.cancellationCheckInterval == rhs.cancellationCheckInterval
    }

    private func validateRevision(_ currentRevision: TextMarkerDocumentRevision) throws {
        guard currentRevision == documentRevision else {
            throw TextMarkersError.staleDocumentRevision(
                expected: documentRevision,
                actual: currentRevision
            )
        }
    }

    public func validate(in document: TextMarkerDocument) throws {
        try validateRevision(document.revision)
        guard
            try documentFingerprint.matches(
                document.text,
                cancellationCheckInterval: cancellationCheckInterval
            )
        else {
            throw TextMarkersError.staleDocument
        }
    }

    public func marker(id: String) -> NamedTextMarker? {
        markers.first { $0.id == id }
    }

    public func ranges(
        forMarker id: String,
        in document: TextMarkerDocument
    ) throws -> [TextMarkerRange] {
        try validate(in: document)
        guard marker(id: id) != nil else { throw TextMarkersError.unknownMarker(id) }
        return storedRanges.filter { $0.markerID == id }
    }

    public func allRanges(in document: TextMarkerDocument) throws -> [TextMarkerRange] {
        try validate(in: document)
        return storedRanges
    }

    public func navigate(
        fromUTF16Offset offset: Int,
        markerID requestedMarkerID: String? = nil,
        direction: TextSearchDirection? = nil,
        wrap: Bool = true,
        in document: TextMarkerDocument
    ) throws -> TextMarkerNavigationResult {
        try validate(in: document)
        guard offset >= 0, offset <= documentUTF16Length else {
            throw TextMarkersError.invalidNavigationOffset(offset)
        }
        guard isExtendedGraphemeClusterBoundary(offset, in: document.text as NSString) else {
            throw TextMarkersError.navigationOffsetSplitsCharacter(offset)
        }
        let markerID = try resolvedMarkerID(requestedMarkerID)
        let direction = direction ?? repeatDirection
        return navigationResult(
            in: storedRanges.filter { $0.markerID == markerID },
            direction: direction,
            offset: offset,
            wrap: wrap,
            excluding: nil
        )
    }

    /// Repeats using the prior navigation direction unless an explicit direction is supplied.
    public func repeatSearch(
        after previous: TextMarkerNavigationResult,
        direction requestedDirection: TextSearchDirection? = nil,
        wrap: Bool = true,
        in document: TextMarkerDocument
    ) throws -> TextMarkerNavigationResult {
        try validate(in: document)
        guard previous.matchSetID == id else { throw TextMarkersError.staleMatchSet }
        let direction = requestedDirection ?? previous.direction
        guard let current = previous.match else {
            return TextMarkerNavigationResult(
                match: nil,
                didWrap: false,
                direction: direction,
                matchSetID: id
            )
        }
        let candidates = storedRanges.filter { $0.markerID == current.markerID }
        guard candidates.contains(current) else {
            throw TextMarkersError.invalidCurrentMatch(current)
        }
        let offset = direction == .forward ? Self.upperBound(of: current.range) : current.range.location
        return navigationResult(
            in: candidates,
            direction: direction,
            offset: offset,
            wrap: wrap,
            excluding: current.range.length == 0 ? current.range : nil
        )
    }

    private func resolvedMarkerID(_ requestedMarkerID: String?) throws -> String {
        guard let markerID = requestedMarkerID ?? activeMarkerID else {
            throw TextMarkersError.noActiveMarker
        }
        guard marker(id: markerID) != nil else { throw TextMarkersError.unknownMarker(markerID) }
        return markerID
    }

    private func navigationResult(
        in candidates: [TextMarkerRange],
        direction: TextSearchDirection,
        offset: Int,
        wrap: Bool,
        excluding excludedRange: NSRange?
    ) -> TextMarkerNavigationResult {
        let candidates = candidates.filter { excludedRange == nil || $0.range != excludedRange }
        let primary: TextMarkerRange?
        switch direction {
        case .forward:
            primary = candidates.first { $0.range.location >= offset }
        case .backward:
            primary = candidates.last { Self.upperBound(of: $0.range) <= offset }
        }
        if let primary {
            return TextMarkerNavigationResult(
                match: primary,
                didWrap: false,
                direction: direction,
                matchSetID: id
            )
        }
        guard wrap else {
            return TextMarkerNavigationResult(
                match: nil,
                didWrap: false,
                direction: direction,
                matchSetID: id
            )
        }
        let wrapped = direction == .forward ? candidates.first : candidates.last
        return TextMarkerNavigationResult(
            match: wrapped,
            didWrap: wrapped != nil,
            direction: direction,
            matchSetID: id
        )
    }

    private static func upperBound(of range: NSRange) -> Int {
        range.location + range.length
    }
}

/// Ordered named search markers. Marker order is the deterministic tie-breaker for equal ranges.
public struct TextMarkers: Equatable, Sendable, RandomAccessCollection {
    public static let currentSchemaVersion = 1
    public static let maximumMarkerCount = 256
    public static let maximumEncodedBytes = 8 * 1024 * 1024

    public typealias Index = Int

    public private(set) var markers: [NamedTextMarker]
    public private(set) var activeMarkerID: String?
    public private(set) var repeatDirection: TextSearchDirection

    public var startIndex: Int { markers.startIndex }
    public var endIndex: Int { markers.endIndex }
    public var activeMarker: NamedTextMarker? {
        guard let activeMarkerID else { return nil }
        return markers.first { $0.id == activeMarkerID }
    }

    public subscript(position: Int) -> NamedTextMarker {
        markers[position]
    }

    public init(
        markers: [NamedTextMarker] = [],
        activeMarkerID: String? = nil,
        repeatDirection: TextSearchDirection = .forward
    ) throws {
        self.markers = markers
        self.activeMarkerID = activeMarkerID
        self.repeatDirection = repeatDirection
        try validate()
    }

    public func marker(id: String) -> NamedTextMarker? {
        markers.first { $0.id == id }
    }

    @discardableResult
    public mutating func add(_ marker: NamedTextMarker) throws -> Bool {
        try marker.validate()
        guard self.marker(id: marker.id) == nil else {
            throw TextMarkersError.duplicateIdentifier(marker.id)
        }
        guard !markers.contains(where: { Self.namesAreEquivalent($0.name, marker.name) }) else {
            throw TextMarkersError.duplicateName(marker.name)
        }
        guard markers.count < Self.maximumMarkerCount else {
            throw TextMarkersError.tooManyMarkers(maximumMarkers: Self.maximumMarkerCount)
        }
        markers.append(marker)
        if activeMarkerID == nil { activeMarkerID = marker.id }
        return true
    }

    public mutating func update(_ marker: NamedTextMarker) throws {
        try marker.validate()
        guard let index = markers.firstIndex(where: { $0.id == marker.id }) else {
            throw TextMarkersError.unknownMarker(marker.id)
        }
        guard
            !markers.enumerated().contains(where: {
                $0.offset != index && Self.namesAreEquivalent($0.element.name, marker.name)
            })
        else {
            throw TextMarkersError.duplicateName(marker.name)
        }
        markers[index] = marker
    }

    @discardableResult
    public mutating func remove(id: String) -> Bool {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return false }
        markers.remove(at: index)
        if activeMarkerID == id {
            activeMarkerID = markers.indices.contains(index) ? markers[index].id : markers.last?.id
        }
        return true
    }

    public mutating func activate(id: String) throws {
        guard marker(id: id) != nil else { throw TextMarkersError.unknownMarker(id) }
        activeMarkerID = id
    }

    public mutating func deactivate() {
        activeMarkerID = nil
    }

    public mutating func setRepeatDirection(_ direction: TextSearchDirection) {
        repeatDirection = direction
    }

    public func validate(limits: TextMarkersLimits = .default) throws {
        try Self.validate(limits)
        var work = TextMarkerWorkBudget(limits: limits)
        try validate(limits: limits, work: &work)
    }

    private func validate(
        limits: TextMarkersLimits,
        work: inout TextMarkerWorkBudget,
        validatePatterns: Bool = true
    ) throws {
        try Task.checkCancellation()
        guard markers.count <= limits.maximumMarkers,
            markers.count <= limits.searchLimits.maximumMarkers,
            markers.count <= Self.maximumMarkerCount
        else {
            throw TextMarkersError.tooManyMarkers(
                maximumMarkers: Swift.min(
                    limits.maximumMarkers,
                    limits.searchLimits.maximumMarkers,
                    Self.maximumMarkerCount
                )
            )
        }

        var identifiers: Set<String> = []
        var names: Set<String> = []
        var combinedPatternLength = 0
        for marker in markers {
            let patternLength = try marker.validateStructure(limits: limits)
            try work.consume(Swift.max(1, patternLength))
            guard identifiers.insert(marker.id).inserted else {
                throw TextMarkersError.duplicateIdentifier(marker.id)
            }
            let canonicalName = Self.canonicalName(marker.name)
            guard names.insert(canonicalName).inserted else {
                throw TextMarkersError.duplicateName(marker.name)
            }
            let (nextPatternLength, overflow) = combinedPatternLength.addingReportingOverflow(
                patternLength
            )
            guard !overflow,
                nextPatternLength <= limits.searchLimits.maximumCombinedPatternUTF16Length
            else {
                throw TextMarkersError.combinedPatternsTooLarge(
                    maximumUTF16Length: limits.searchLimits.maximumCombinedPatternUTF16Length
                )
            }
            combinedPatternLength = nextPatternLength
        }
        if let activeMarkerID, !identifiers.contains(activeMarkerID) {
            throw TextMarkersError.unknownMarker(activeMarkerID)
        }
        if validatePatterns {
            for marker in markers {
                try Task.checkCancellation()
                try marker.validatePattern(searchLimits: limits.searchLimits)
            }
        }
    }

    /// Computes all ranges with cancellation-aware literal matching and shared regular-expression semantics.
    /// Task cancellation is checked before and after every marker search and while collecting ranges.
    public func matches(
        in document: TextMarkerDocument,
        limits: TextMarkersLimits = .default
    ) throws -> TextMarkerMatchSet {
        try Self.validate(limits)
        var work = TextMarkerWorkBudget(limits: limits)
        try validate(limits: limits, work: &work, validatePatterns: false)
        try Task.checkCancellation()

        let documentLength = document.text.utf16.count
        guard documentLength <= limits.searchLimits.maximumInputUTF16Length else {
            throw TextSearchError.inputTooLarge(
                maximumUTF16Length: limits.searchLimits.maximumInputUTF16Length
            )
        }
        let documentFingerprint = TextMarkerDocumentFingerprint(text: document.text)
        let source = document.text as NSString
        let needsLineIndex = markers.contains {
            if case .lineRange = $0.scope { return true }
            return false
        }
        let lineIndex: TextMarkerLineIndex?
        if needsLineIndex {
            lineIndex = try TextMarkerLineIndex(
                text: document.text,
                limits: limits,
                work: &work
            )
        } else {
            lineIndex = nil
        }

        var collected: [(markerIndex: Int, value: TextMarkerRange)] = []
        collected.reserveCapacity(Swift.min(limits.maximumResultRanges, 4_096))
        var remainingMatches = limits.searchLimits.maximumMatches
        var remainingCaptureRanges = limits.searchLimits.maximumStoredCaptureRanges

        for (markerIndex, marker) in markers.enumerated() {
            try Task.checkCancellation()
            TextMarkersTestHooks.cancellationPhaseHandler?(.evaluatingMarker(marker.id))
            try Task.checkCancellation()
            let scopeRange = try Self.resolvedScopeRange(
                marker.scope,
                text: document.text,
                documentLength: documentLength,
                lineIndex: lineIndex
            )
            try Self.validateRangeEndpoints(
                scopeRange,
                in: source,
                documentLength: documentLength
            )
            guard scopeRange.length <= limits.maximumScopeUTF16Length else {
                throw TextMarkersError.scopeTooLarge(
                    markerID: marker.id,
                    maximumUTF16Length: limits.maximumScopeUTF16Length
                )
            }
            try work.consume(documentLength)

            let includesUpperBoundZeroLengthMatch: Bool
            switch marker.scope {
            case .entireDocument:
                includesUpperBoundZeroLengthMatch = true
            case .utf16Range:
                includesUpperBoundZeroLengthMatch = scopeRange.length == 0
            case .lineRange(let range):
                guard let finalSelectedLine = lineIndex?.line(at: range.upperBound) else {
                    preconditionFailure("Line index was not created")
                }
                includesUpperBoundZeroLengthMatch =
                    finalSelectedLine.terminatorRange.length == 0
                    && Self.upperBound(of: finalSelectedLine.range) == documentLength
            }

            let searchResult: TextMarkerRangeSearchResult
            do {
                switch marker.query.pattern {
                case .literal:
                    searchResult = try Self.literalMarkerRanges(
                        in: document.text,
                        matching: marker.query,
                        scopeRange: scopeRange,
                        includesUpperBoundZeroLengthMatch: includesUpperBoundZeroLengthMatch,
                        limits: limits.searchLimits,
                        cancellationCheckInterval: limits.cancellationCheckInterval,
                        maximumMatches: remainingMatches,
                        maximumTotalMatches: limits.searchLimits.maximumMatches,
                        maximumCaptureRanges: remainingCaptureRanges,
                        maximumTotalCaptureRanges: limits.searchLimits.maximumStoredCaptureRanges,
                        maximumResultRanges: limits.maximumResultRanges - collected.count,
                        maximumTotalResultRanges: limits.maximumResultRanges,
                        maximumWorkUnits: work.remainingWorkUnits,
                        maximumTotalWorkUnits: limits.maximumWorkUnits
                    )
                case .regularExpression:
                    searchResult = try Self.regularExpressionMarkerRanges(
                        in: document.text,
                        matching: marker.query,
                        scopeRange: scopeRange,
                        includesUpperBoundZeroLengthMatch: includesUpperBoundZeroLengthMatch,
                        limits: limits.searchLimits,
                        maximumMatches: remainingMatches,
                        maximumTotalMatches: limits.searchLimits.maximumMatches,
                        maximumCaptureRanges: remainingCaptureRanges,
                        maximumTotalCaptureRanges: limits.searchLimits.maximumStoredCaptureRanges,
                        maximumResultRanges: limits.maximumResultRanges - collected.count,
                        maximumTotalResultRanges: limits.maximumResultRanges,
                        maximumWorkUnits: work.remainingWorkUnits,
                        maximumTotalWorkUnits: limits.maximumWorkUnits
                    )
                }
            } catch TextSearchError.tooManyMatches(let maximumMatches) {
                throw TextMarkersError.tooManyResultRanges(
                    maximumRanges: maximumMatches
                )
            }
            try Task.checkCancellation()
            remainingMatches -= searchResult.matchCount
            remainingCaptureRanges -= searchResult.captureRangeCount
            try work.consume(searchResult.workUnits)
            for range in searchResult.ranges {
                try Self.validateRangeEndpoints(
                    range,
                    in: source,
                    documentLength: documentLength
                )
                collected.append(
                    (
                        markerIndex,
                        TextMarkerRange(
                            markerID: marker.id,
                            range: range
                        )
                    )
                )
            }
        }

        collected.sort {
            if $0.value.range.location != $1.value.range.location {
                return $0.value.range.location < $1.value.range.location
            }
            if $0.markerIndex != $1.markerIndex {
                return $0.markerIndex < $1.markerIndex
            }
            return $0.value.range.length < $1.value.range.length
        }
        try Task.checkCancellation()
        return TextMarkerMatchSet(
            documentRevision: document.revision,
            documentUTF16Length: documentLength,
            documentFingerprint: documentFingerprint,
            markers: markers,
            activeMarkerID: activeMarkerID,
            repeatDirection: repeatDirection,
            ranges: collected.map(\.value),
            cancellationCheckInterval: limits.cancellationCheckInterval
        )
    }

    /// Compact JSON with stable object-key ordering for user or project persistence.
    public func encodedData(limits: TextMarkersLimits = .default) throws -> Data {
        try validate(limits: limits)
        let encoder = JSONEncoder()
        encoder.userInfo[.textMarkersLimits] = limits
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(WireTextMarkers(self))
        TextMarkersTestHooks.cancellationPhaseHandler?(.encoded)
        try Task.checkCancellation()
        guard data.count <= limits.maximumEncodedBytes,
            data.count <= Self.maximumEncodedBytes
        else {
            throw TextMarkersError.encodedDataTooLarge(
                maximumBytes: Swift.min(limits.maximumEncodedBytes, Self.maximumEncodedBytes)
            )
        }
        return data
    }

    public static func decode(
        from data: Data,
        limits: TextMarkersLimits = .default
    ) throws -> TextMarkers {
        try validate(limits)
        let maximumBytes = Swift.min(limits.maximumEncodedBytes, maximumEncodedBytes)
        guard data.count <= maximumBytes else {
            throw TextMarkersError.encodedDataTooLarge(maximumBytes: maximumBytes)
        }
        try Task.checkCancellation()
        let maximumMarkers = Swift.min(
            limits.maximumMarkers,
            limits.searchLimits.maximumMarkers,
            Self.maximumMarkerCount
        )
        var preflight = TextMarkersWireJSONPreflight(
            data: data,
            maximumMarkers: maximumMarkers,
            cancellationCheckInterval: limits.cancellationCheckInterval
        )
        try preflight.validate()
        TextMarkersTestHooks.cancellationPhaseHandler?(.decodePreflightComplete)
        try Task.checkCancellation()
        let decoder = JSONDecoder()
        decoder.userInfo[.textMarkersLimits] = limits
        let markers = try decoder.decode(WireTextMarkers.self, from: data).decodedMarkers(limits: limits)
        return markers
    }

    private enum Direction: String, Codable {
        case forward
        case backward

        init(_ direction: TextSearchDirection) {
            switch direction {
            case .forward: self = .forward
            case .backward: self = .backward
            }
        }

        var value: TextSearchDirection {
            switch self {
            case .forward: .forward
            case .backward: .backward
            }
        }
    }

    private struct WireTextMarkers: Codable {
        let schemaVersion: Int
        let markers: [NamedTextMarker]
        let activeMarkerID: String?
        let repeatDirection: Direction

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case markers
            case activeMarkerID
            case repeatDirection
        }

        init(_ markers: TextMarkers) {
            schemaVersion = TextMarkers.currentSchemaVersion
            self.markers = markers.markers
            activeMarkerID = markers.activeMarkerID
            repeatDirection = Direction(markers.repeatDirection)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let limits = decoder.userInfo[.textMarkersLimits] as? TextMarkersLimits ?? .default
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == TextMarkers.currentSchemaVersion else {
                throw TextMarkersError.unsupportedSchemaVersion(schemaVersion)
            }

            var decodedMarkers = try container.nestedUnkeyedContainer(forKey: .markers)
            let maximumMarkers = Swift.min(
                limits.maximumMarkers,
                limits.searchLimits.maximumMarkers,
                TextMarkers.maximumMarkerCount
            )
            if let count = decodedMarkers.count, count > maximumMarkers {
                throw TextMarkersError.tooManyMarkers(
                    maximumMarkers: maximumMarkers
                )
            }
            var markers: [NamedTextMarker] = []
            markers.reserveCapacity(
                Swift.min(decodedMarkers.count ?? 0, maximumMarkers)
            )
            while !decodedMarkers.isAtEnd {
                try Task.checkCancellation()
                guard markers.count < maximumMarkers else {
                    throw TextMarkersError.tooManyMarkers(
                        maximumMarkers: maximumMarkers
                    )
                }
                markers.append(try decodedMarkers.decode(NamedTextMarker.self))
            }
            self.markers = markers
            activeMarkerID = try container.decodeIfPresent(String.self, forKey: .activeMarkerID)
            repeatDirection = try container.decode(Direction.self, forKey: .repeatDirection)
        }

        func decodedMarkers(limits: TextMarkersLimits) throws -> TextMarkers {
            let decoded = TextMarkers(
                uncheckedMarkers: markers,
                activeMarkerID: activeMarkerID,
                repeatDirection: repeatDirection.value
            )
            try decoded.validate(limits: limits)
            return decoded
        }
    }

    private init(
        uncheckedMarkers markers: [NamedTextMarker],
        activeMarkerID: String?,
        repeatDirection: TextSearchDirection
    ) {
        self.markers = markers
        self.activeMarkerID = activeMarkerID
        self.repeatDirection = repeatDirection
    }

    private static func validate(_ limits: TextMarkersLimits) throws {
        guard limits.maximumMarkers >= 0,
            limits.maximumMarkers <= Self.maximumMarkerCount,
            limits.maximumIdentifierUTF8Bytes > 0,
            limits.maximumIdentifierUTF8Bytes <= NamedTextMarker.maximumIdentifierUTF8Bytes,
            limits.maximumNameUTF8Bytes > 0,
            limits.maximumNameUTF8Bytes <= NamedTextMarker.maximumNameUTF8Bytes,
            limits.maximumColorTokenUTF8Bytes > 0,
            limits.maximumColorTokenUTF8Bytes <= TextMarkerColorToken.maximumUTF8Bytes,
            limits.maximumLineCount > 0,
            limits.maximumLineUTF16Length >= 0,
            limits.maximumScopeUTF16Length >= 0,
            limits.maximumResultRanges > 0,
            limits.maximumWorkUnits >= 0,
            limits.cancellationCheckInterval > 0,
            limits.maximumEncodedBytes > 0,
            limits.maximumEncodedBytes <= Self.maximumEncodedBytes
        else {
            throw TextMarkersError.invalidLimits
        }
    }

    private static func canonicalName(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
    }

    private static func namesAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        canonicalName(lhs) == canonicalName(rhs)
    }

    private static func resolvedScopeRange(
        _ scope: TextMarkerScope,
        text: String,
        documentLength: Int,
        lineIndex: TextMarkerLineIndex?
    ) throws -> NSRange {
        switch scope {
        case .entireDocument:
            return NSRange(location: 0, length: documentLength)
        case .utf16Range(let range):
            let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
            guard range.location >= 0, range.length >= 0, !overflow,
                upperBound <= documentLength
            else {
                throw TextMarkersError.utf16RangeOutOfBounds(
                    range: range,
                    documentUTF16Length: documentLength
                )
            }
            guard
                Self.hasExtendedGraphemeClusterBoundaryEndpoints(
                    range,
                    in: text as NSString
                )
            else {
                throw TextMarkersError.utf16RangeSplitsCharacter(range)
            }
            return range
        case .lineRange(let range):
            guard let lineIndex else { preconditionFailure("Line index was not created") }
            guard range.lowerBound > 0, range.upperBound <= lineIndex.lineCount else {
                throw TextMarkersError.lineRangeOutOfBounds(
                    range: range,
                    lineCount: lineIndex.lineCount
                )
            }
            guard let first = lineIndex.line(at: range.lowerBound),
                let last = lineIndex.line(at: range.upperBound),
                let lastRange = last.completeRange
            else {
                throw TextMarkersError.lineRangeOutOfBounds(
                    range: range,
                    lineCount: lineIndex.lineCount
                )
            }
            return NSRange(
                location: first.range.location,
                length: lastRange.location + lastRange.length - first.range.location
            )
        }
    }

    private static func contains(
        _ outer: NSRange,
        _ inner: NSRange,
        includesUpperBoundZeroLengthMatch: Bool
    ) -> Bool {
        let outerEnd = upperBound(of: outer)
        let innerEnd = upperBound(of: inner)
        guard inner.location >= outer.location, innerEnd <= outerEnd else { return false }
        return inner.length > 0
            || inner.location < outerEnd
            || includesUpperBoundZeroLengthMatch
    }

    private static func upperBound(of range: NSRange) -> Int {
        range.location + range.length
    }

    fileprivate struct TextMarkerRangeSearchResult {
        let ranges: [NSRange]
        let workUnits: Int
        let matchCount: Int
        let captureRangeCount: Int
    }

    private static func literalMarkerRanges(
        in text: String,
        matching query: TextSearchQuery,
        scopeRange: NSRange,
        includesUpperBoundZeroLengthMatch: Bool,
        limits: TextSearchLimits,
        cancellationCheckInterval: Int,
        maximumMatches: Int,
        maximumTotalMatches: Int,
        maximumCaptureRanges: Int,
        maximumTotalCaptureRanges: Int,
        maximumResultRanges: Int,
        maximumTotalResultRanges: Int,
        maximumWorkUnits: Int,
        maximumTotalWorkUnits: Int
    ) throws -> TextMarkerRangeSearchResult {
        guard case .literal(let pattern) = query.pattern, !pattern.isEmpty else {
            return TextMarkerRangeSearchResult(
                ranges: [],
                workUnits: 0,
                matchCount: 0,
                captureRangeCount: 0
            )
        }
        let source = text as NSString
        let textLength = source.length
        let patternLength = (pattern as NSString).length
        let maximumMatchLength = maximumLiteralMatchUTF16Length(
            pattern,
            patternLength: patternLength,
            caseSensitive: query.caseSensitive
        )
        let options: NSString.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive]
        var ranges: [NSRange] = []
        ranges.reserveCapacity(Swift.min(maximumResultRanges, 1_024))
        var cursor = 0
        var matchCount = 0
        var workUnits = 0

        while cursor < textLength {
            guard
                let range = try nextLiteralRange(
                    in: source,
                    pattern: pattern,
                    maximumMatchLength: maximumMatchLength,
                    options: options,
                    from: cursor,
                    cancellationCheckInterval: cancellationCheckInterval
                )
            else {
                break
            }
            let end = Self.upperBound(of: range)
            guard end > cursor else { break }
            guard Self.hasExtendedGraphemeClusterBoundaryEndpoints(range, in: source),
                !query.wholeWord || Self.hasWholeWordBoundaries(range, in: source)
            else {
                guard
                    let next = Self.nextExtendedGraphemeClusterBoundary(
                        after: range.location,
                        in: source
                    )
                else {
                    break
                }
                cursor = next
                continue
            }
            cursor = end
            guard matchCount < maximumMatches else {
                throw TextSearchError.tooManyMatches(maximumMatches: maximumTotalMatches)
            }
            matchCount += 1
            guard matchCount <= maximumCaptureRanges else {
                throw TextSearchError.tooManyCaptureRanges(
                    maximumRanges: maximumTotalCaptureRanges
                )
            }
            guard workUnits < maximumWorkUnits else {
                throw TextMarkersError.workLimitExceeded(
                    maximumWorkUnits: maximumTotalWorkUnits
                )
            }
            workUnits += 1
            guard
                Self.contains(
                    scopeRange,
                    range,
                    includesUpperBoundZeroLengthMatch: includesUpperBoundZeroLengthMatch
                )
            else {
                continue
            }
            guard ranges.count < maximumResultRanges else {
                throw TextMarkersError.tooManyResultRanges(
                    maximumRanges: maximumTotalResultRanges
                )
            }
            ranges.append(range)
        }
        try Task.checkCancellation()
        return TextMarkerRangeSearchResult(
            ranges: ranges,
            workUnits: workUnits,
            matchCount: matchCount,
            captureRangeCount: matchCount
        )
    }

    private static func nextLiteralRange(
        in source: NSString,
        pattern: String,
        maximumMatchLength: Int,
        options: NSString.CompareOptions,
        from start: Int,
        cancellationCheckInterval: Int
    ) throws -> NSRange? {
        var chunkStart = start
        let overlap = Swift.max(0, maximumMatchLength - 1)
        while chunkStart < source.length {
            try Task.checkCancellation()
            TextMarkersTestHooks.cancellationPhaseHandler?(.literalSearchChunk)
            try Task.checkCancellation()
            let coreLength = Swift.min(cancellationCheckInterval, source.length - chunkStart)
            let maximumWindowLength = source.length - chunkStart
            let (requestedWindowLength, overflow) = coreLength.addingReportingOverflow(
                overlap
            )
            let windowLength =
                overflow
                ? maximumWindowLength
                : Swift.min(maximumWindowLength, requestedWindowLength)
            let range = source.range(
                of: pattern,
                options: options,
                range: NSRange(location: chunkStart, length: windowLength)
            )
            try Task.checkCancellation()
            if range.location != NSNotFound { return range }
            chunkStart += coreLength
        }
        return nil
    }

    private static func maximumLiteralMatchUTF16Length(
        _ pattern: String,
        patternLength: Int,
        caseSensitive: Bool
    ) -> Int {
        var comparablePattern = pattern.decomposedStringWithCanonicalMapping
        if !caseSensitive {
            comparablePattern =
                comparablePattern
                .folding(
                    options: [.caseInsensitive],
                    locale: nil
                )
                .decomposedStringWithCanonicalMapping
        }
        let maximumSourceLength = comparablePattern.unicodeScalars.count * 2
        return Swift.max(patternLength, maximumSourceLength)
    }

    fileprivate static func regularExpressionMarkerRanges(
        in text: String,
        matching query: TextSearchQuery,
        scopeRange: NSRange,
        includesUpperBoundZeroLengthMatch: Bool,
        limits: TextSearchLimits,
        maximumMatches: Int,
        maximumTotalMatches: Int,
        maximumCaptureRanges: Int,
        maximumTotalCaptureRanges: Int,
        maximumResultRanges: Int,
        maximumTotalResultRanges: Int,
        maximumWorkUnits: Int,
        maximumTotalWorkUnits: Int
    ) throws -> TextMarkerRangeSearchResult {
        guard case .regularExpression(let pattern) = query.pattern else {
            return TextMarkerRangeSearchResult(
                ranges: [],
                workUnits: 0,
                matchCount: 0,
                captureRangeCount: 0
            )
        }
        try Task.checkCancellation()
        let expression: NSRegularExpression
        do {
            expression = try regularExpression(matching: query)
        } catch {
            throw TextSearchError.invalidPattern(pattern)
        }
        try Task.checkCancellation()

        let source = text as NSString
        let matchingOptions: NSRegularExpression.MatchingOptions = [
            .reportProgress,
            .reportCompletion,
            .withTransparentBounds,
            .withoutAnchoringBounds
        ]
        var ranges: [NSRange] = []
        ranges.reserveCapacity(Swift.min(maximumResultRanges, 1_024))
        var matchCount = 0
        var captureRangeCount = 0
        var workUnits = 0
        var progressSteps = 0
        var wasCancelled = false
        var evaluationFailed = false
        var exceededProgressLimit = false
        var exceededMatchLimit = false
        var exceededCaptureLimit = false
        var exceededWorkLimit = false
        var exceededResultLimit = false
        var cursorFloor = 0

        func chargeProgress(
            by amount: Int = 1,
            _ stop: UnsafeMutablePointer<ObjCBool>? = nil
        ) -> Bool {
            let (nextProgressSteps, overflow) = progressSteps.addingReportingOverflow(amount)
            guard !overflow,
                nextProgressSteps <= limits.maximumRegularExpressionProgressSteps
            else {
                exceededProgressLimit = true
                stop?.pointee = true
                return false
            }
            progressSteps = nextProgressSteps
            return true
        }

        func firstResult(
            using candidateExpression: NSRegularExpression,
            range: NSRange
        ) -> NSTextCheckingResult? {
            var found: NSTextCheckingResult?
            candidateExpression.enumerateMatches(
                in: text,
                options: matchingOptions.union(.anchored),
                range: range
            ) { result, flags, stop in
                if Task.isCancelled {
                    wasCancelled = true
                    stop.pointee = true
                    return
                }
                if flags.contains(.internalError) {
                    evaluationFailed = true
                    stop.pointee = true
                    return
                }
                if flags.contains(.progress), !chargeProgress(stop) { return }
                guard let result, chargeProgress(stop) else { return }
                found = result
                stop.pointee = true
            }
            return found
        }

        func boundaryAdjusted(_ initial: NSTextCheckingResult) -> NSTextCheckingResult? {
            guard isExtendedGraphemeClusterBoundary(initial.range.location, in: source),
                !query.wholeWord || pattern.isEmpty
                    || Self.hasLeftWholeWordBoundary(initial.range, in: source)
            else {
                return nil
            }
            var candidate = initial
            var excludedSuffixScalarCounts: [Int] = []
            while !isExtendedGraphemeClusterBoundary(
                Self.upperBound(of: candidate.range), in: source
            )
                || query.wholeWord && !pattern.isEmpty
                    && !Self.hasRightWholeWordBoundary(candidate.range, in: source)
            {
                if Task.isCancelled {
                    wasCancelled = true
                    return nil
                }
                let suffixStart = Self.upperBound(of: candidate.range)
                guard chargeProgress(by: source.length - suffixStart) else { return nil }
                let suffix = source.substring(from: suffixStart)
                excludedSuffixScalarCounts.append(suffix.unicodeScalars.count)
                let excludedEnds =
                    excludedSuffixScalarCounts
                    .map { "[\\s\\S]{\($0)}" }
                    .joined(separator: "|")
                let boundarySuffix = "(?!(?:\(excludedEnds))\\z)"
                let retryPattern =
                    "(?:\(Self.closingOpenQuote(in: expression.pattern)))\(boundarySuffix)"
                guard chargeProgress(by: retryPattern.utf16.count) else { return nil }
                let retry: NSRegularExpression
                do {
                    retry = try NSRegularExpression(pattern: retryPattern, options: expression.options)
                } catch {
                    do {
                        let fallbackPattern =
                            "(?:\(Self.closingOpenQuote(in: expression.pattern + "\n")))\(boundarySuffix)"
                        guard chargeProgress(by: fallbackPattern.utf16.count) else { return nil }
                        retry = try NSRegularExpression(
                            pattern: fallbackPattern,
                            options: expression.options
                        )
                    } catch {
                        evaluationFailed = true
                        return nil
                    }
                }
                guard
                    let next = firstResult(
                        using: retry,
                        range: NSRange(
                            location: initial.range.location,
                            length: source.length - initial.range.location
                        )
                    ),
                    next.range.location == initial.range.location
                else {
                    return nil
                }
                candidate = next
            }
            return candidate
        }

        expression.enumerateMatches(
            in: text,
            options: matchingOptions,
            range: NSRange(location: 0, length: source.length)
        ) { result, flags, stop in
            TextMarkersTestHooks.cancellationPhaseHandler?(.regularExpressionProgress)
            if Task.isCancelled {
                wasCancelled = true
                stop.pointee = true
                return
            }
            if flags.contains(.internalError) {
                evaluationFailed = true
                stop.pointee = true
                return
            }
            if flags.contains(.progress) || result != nil {
                guard chargeProgress(stop) else { return }
            }
            guard let result else { return }
            guard result.range.location >= cursorFloor else { return }
            guard let adjustedResult = boundaryAdjusted(result) else {
                if wasCancelled || evaluationFailed || exceededProgressLimit {
                    stop.pointee = true
                }
                return
            }
            let range = adjustedResult.range
            if range.length > 0 {
                cursorFloor = Self.upperBound(of: range)
            } else if let next = Self.nextExtendedGraphemeClusterBoundary(
                after: range.location,
                in: source
            ) {
                cursorFloor = next
            } else {
                cursorFloor = source.length + 1
            }
            guard matchCount < maximumMatches else {
                exceededMatchLimit = true
                stop.pointee = true
                return
            }
            matchCount += 1
            var resultCaptureRangeCount = 0
            for index in 0..<adjustedResult.numberOfRanges
            where adjustedResult.range(at: index).location != NSNotFound {
                resultCaptureRangeCount += 1
            }
            let (nextCaptureRangeCount, captureOverflow) =
                captureRangeCount.addingReportingOverflow(resultCaptureRangeCount)
            guard !captureOverflow,
                nextCaptureRangeCount <= maximumCaptureRanges
            else {
                exceededCaptureLimit = true
                stop.pointee = true
                return
            }
            captureRangeCount = nextCaptureRangeCount
            guard workUnits < maximumWorkUnits else {
                exceededWorkLimit = true
                stop.pointee = true
                return
            }
            workUnits += 1
            guard
                Self.contains(
                    scopeRange,
                    range,
                    includesUpperBoundZeroLengthMatch: includesUpperBoundZeroLengthMatch
                )
            else {
                return
            }
            guard ranges.count < maximumResultRanges else {
                exceededResultLimit = true
                stop.pointee = true
                return
            }
            ranges.append(range)
        }

        if wasCancelled || Task.isCancelled {
            try Task.checkCancellation()
        }
        guard !evaluationFailed else { throw TextSearchError.evaluationFailed }
        guard !exceededProgressLimit else {
            throw TextSearchError.evaluationLimitExceeded(
                maximumProgressSteps: limits.maximumRegularExpressionProgressSteps
            )
        }
        guard !exceededMatchLimit else {
            throw TextSearchError.tooManyMatches(maximumMatches: maximumTotalMatches)
        }
        guard !exceededCaptureLimit else {
            throw TextSearchError.tooManyCaptureRanges(
                maximumRanges: maximumTotalCaptureRanges
            )
        }
        guard !exceededWorkLimit else {
            throw TextMarkersError.workLimitExceeded(
                maximumWorkUnits: maximumTotalWorkUnits
            )
        }
        guard !exceededResultLimit else {
            throw TextMarkersError.tooManyResultRanges(
                maximumRanges: maximumTotalResultRanges
            )
        }
        return TextMarkerRangeSearchResult(
            ranges: ranges,
            workUnits: workUnits,
            matchCount: matchCount,
            captureRangeCount: captureRangeCount
        )
    }

    private static func regularExpression(
        matching query: TextSearchQuery
    ) throws -> NSRegularExpression {
        guard case .regularExpression(let value) = query.pattern else {
            preconditionFailure("A regular-expression query is required")
        }
        let pattern = value.isEmpty ? "(?:)" : value
        let options: NSRegularExpression.Options = query.caseSensitive ? [] : [.caseInsensitive]
        return try NSRegularExpression(pattern: pattern, options: options)
    }

    private static func closingOpenQuote(in pattern: String) -> String {
        let units = Array(pattern.utf16)
        var quoted = false
        var index = 0
        while index + 1 < units.count {
            guard units[index] == 0x5C else {
                index += 1
                continue
            }
            let escaped = units[index + 1]
            if quoted {
                if escaped == 0x45 { quoted = false }
            } else if escaped == 0x51 {
                quoted = true
            }
            index += 2
        }
        return quoted ? pattern + "\\E" : pattern
    }

    private static func validateRangeEndpoints(
        _ range: NSRange,
        in text: NSString,
        documentLength: Int
    ) throws {
        let (end, overflow) = range.location.addingReportingOverflow(range.length)
        guard range.location >= 0, range.length >= 0, !overflow, end <= documentLength else {
            throw TextMarkersError.utf16RangeOutOfBounds(
                range: range,
                documentUTF16Length: documentLength
            )
        }
        guard hasExtendedGraphemeClusterBoundaryEndpoints(range, in: text) else {
            throw TextMarkersError.utf16RangeSplitsCharacter(range)
        }
    }

    private static func hasExtendedGraphemeClusterBoundaryEndpoints(
        _ range: NSRange,
        in text: NSString
    ) -> Bool {
        isExtendedGraphemeClusterBoundary(range.location, in: text)
            && isExtendedGraphemeClusterBoundary(upperBound(of: range), in: text)
    }

    private static func hasWholeWordBoundaries(_ range: NSRange, in text: NSString) -> Bool {
        hasLeftWholeWordBoundary(range, in: text)
            && hasRightWholeWordBoundary(range, in: text)
    }

    private static func hasLeftWholeWordBoundary(_ range: NSRange, in text: NSString) -> Bool {
        guard range.location > 0 else { return true }
        let previous = text.substring(
            with: text.rangeOfComposedCharacterSequence(at: range.location - 1)
        )
        return !isWordCharacter(previous)
    }

    private static func hasRightWholeWordBoundary(_ range: NSRange, in text: NSString) -> Bool {
        let end = upperBound(of: range)
        guard end < text.length else { return true }
        let next = text.substring(with: text.rangeOfComposedCharacterSequence(at: end))
        return !isWordCharacter(next)
    }

    private static func isWordCharacter(_ character: String) -> Bool {
        var hasMark = false
        for scalar in character.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                .otherLetter, .decimalNumber, .letterNumber, .otherNumber,
                .connectorPunctuation:
                return true
            case .nonspacingMark, .spacingMark, .enclosingMark:
                if !scalar.properties.isVariationSelector {
                    hasMark = true
                }
            default:
                break
            }
        }
        return hasMark
    }

    private static func nextExtendedGraphemeClusterBoundary(
        after offset: Int,
        in text: NSString
    ) -> Int? {
        guard offset >= 0, offset < text.length else { return nil }
        let boundary = upperBound(of: text.rangeOfComposedCharacterSequence(at: offset))
        return boundary > offset ? boundary : nil
    }
}

private func isExtendedGraphemeClusterBoundary(_ offset: Int, in text: NSString) -> Bool {
    guard offset >= 0, offset <= text.length else { return false }
    guard offset < text.length else { return true }
    return text.rangeOfComposedCharacterSequence(at: offset).location == offset
}

private struct TextMarkerWorkBudget {
    let maximumWorkUnits: Int
    let cancellationCheckInterval: Int
    private var completedWork = 0
    private var workAtLastCancellationCheck = 0

    var remainingWorkUnits: Int { maximumWorkUnits - completedWork }

    init(limits: TextMarkersLimits) {
        maximumWorkUnits = limits.maximumWorkUnits
        cancellationCheckInterval = limits.cancellationCheckInterval
    }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximumWorkUnits - completedWork else {
            throw TextMarkersError.workLimitExceeded(maximumWorkUnits: maximumWorkUnits)
        }
        completedWork += amount
        if completedWork - workAtLastCancellationCheck >= cancellationCheckInterval {
            try Task.checkCancellation()
            workAtLastCancellationCheck = completedWork
        }
    }
}
