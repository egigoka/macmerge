import Foundation

public enum WebPageComparisonSide: Equatable, Sendable {
    case left
    case right
}

public enum WebPageComparisonMode: String, Equatable, Sendable {
    /// Compares validated HTML source without rewriting it.
    case source
    /// Compares deterministic text extracted from the supplied HTML. No CSS or JavaScript runs.
    case renderedText
}

public struct WebPageComparisonLimits: Equatable, Sendable {
    public static let `default` = WebPageComparisonLimits()

    public let maximumInputBytes: Int
    public let maximumTokenCount: Int
    public let maximumAttributeCount: Int
    public let maximumAttributesPerTag: Int
    public let maximumElementDepth: Int
    public let maximumWorkUnits: Int
    public let maximumOutputBytes: Int

    public init(
        maximumInputBytes: Int = 64 * 1024 * 1024,
        maximumTokenCount: Int = 1_000_000,
        maximumAttributeCount: Int = 1_000_000,
        maximumAttributesPerTag: Int = 16_384,
        maximumElementDepth: Int = 16_384,
        maximumWorkUnits: Int = 256 * 1024 * 1024,
        maximumOutputBytes: Int = 64 * 1024 * 1024
    ) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumTokenCount = maximumTokenCount
        self.maximumAttributeCount = maximumAttributeCount
        self.maximumAttributesPerTag = maximumAttributesPerTag
        self.maximumElementDepth = maximumElementDepth
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumOutputBytes = maximumOutputBytes
    }
}

public struct WebPageComparisonOptions: Equatable, Sendable {
    public static let `default` = WebPageComparisonOptions()

    public let mode: WebPageComparisonMode
    public let lineDiffOptions: LineDiffOptions
    public let limits: WebPageComparisonLimits

    public init(
        mode: WebPageComparisonMode = .source,
        lineDiffOptions: LineDiffOptions = LineDiffOptions(),
        limits: WebPageComparisonLimits = .default
    ) {
        self.mode = mode
        self.lineDiffOptions = lineDiffOptions
        self.limits = limits
    }
}

public enum WebPageComparisonSegmentKind: Equatable, Sendable {
    case text
    case rawText
    case comment
    case startTag
    case endTag
    case declaration
    case renderedBoundary
}

/// Maps comparison output back to the supplied UTF-8 HTML where one contiguous mapping exists.
public struct WebPageComparisonSegment: Equatable, Sendable {
    public let kind: WebPageComparisonSegmentKind
    public let sourceUTF8Range: Range<Int>
    public let outputUTF8Range: Range<Int>

    public init(
        kind: WebPageComparisonSegmentKind,
        sourceUTF8Range: Range<Int>,
        outputUTF8Range: Range<Int>
    ) {
        self.kind = kind
        self.sourceUTF8Range = sourceUTF8Range
        self.outputUTF8Range = outputUTF8Range
    }
}

public struct WebPageComparisonDocument: Equatable, Sendable {
    public let mode: WebPageComparisonMode
    public let comparisonText: String
    public let segments: [WebPageComparisonSegment]
    public let sourceUTF8ByteCount: Int
    public let tokenCount: Int
    public let attributeCount: Int

    public init(
        mode: WebPageComparisonMode,
        comparisonText: String,
        segments: [WebPageComparisonSegment],
        sourceUTF8ByteCount: Int,
        tokenCount: Int,
        attributeCount: Int
    ) {
        self.mode = mode
        self.comparisonText = comparisonText
        self.segments = segments
        self.sourceUTF8ByteCount = sourceUTF8ByteCount
        self.tokenCount = tokenCount
        self.attributeCount = attributeCount
    }
}

public struct WebPageComparisonResult: Equatable, Sendable {
    public let mode: WebPageComparisonMode
    public let left: WebPageComparisonDocument
    public let right: WebPageComparisonDocument
    public let lineDiff: LineDiffResult
    public let summary: DiffSummary

    public var isEqual: Bool { summary.differences == 0 }

    public init(
        mode: WebPageComparisonMode,
        left: WebPageComparisonDocument,
        right: WebPageComparisonDocument,
        lineDiff: LineDiffResult
    ) {
        self.mode = mode
        self.left = left
        self.right = right
        self.lineDiff = lineDiff
        summary = DiffSummary(rows: lineDiff.rows)
    }
}

public enum WebPageHTMLMalformedReason: Equatable, Sendable {
    case unexpectedLessThan
    case invalidTagName
    case malformedClosingTag
    case invalidAttribute
    case missingAttributeValue
    case unterminatedAttributeValue
    case unterminatedTag
    case unterminatedComment
    case unsupportedDeclaration
    case invalidCharacterReference
    case unterminatedRawText(element: String)
}

public enum WebPageComparisonError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case invalidUTF8(side: WebPageComparisonSide)
    case inputTooLarge(side: WebPageComparisonSide, maximumBytes: Int)
    case nullByte(side: WebPageComparisonSide, utf8Offset: Int)
    case malformedHTML(
        side: WebPageComparisonSide,
        utf8Offset: Int,
        reason: WebPageHTMLMalformedReason
    )
    case tooManyTokens(side: WebPageComparisonSide, maximumTokens: Int)
    case tooManyAttributes(side: WebPageComparisonSide, maximumAttributes: Int)
    case tooManyAttributesInTag(
        side: WebPageComparisonSide,
        tagName: String,
        maximumAttributes: Int
    )
    case elementNestingTooDeep(side: WebPageComparisonSide, maximumDepth: Int)
    case workLimitExceeded(side: WebPageComparisonSide, maximumWorkUnits: Int)
    case outputTooLarge(side: WebPageComparisonSide, maximumBytes: Int)
    case cancelled
    case lineDiff(LineDiffError)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Webpage-comparison limits are invalid."
        case .invalidUTF8(let side):
            "The \(side.label) webpage is not valid UTF-8."
        case .inputTooLarge(let side, let maximumBytes):
            "The \(side.label) webpage exceeds the \(maximumBytes)-byte input limit."
        case .nullByte(let side, let utf8Offset):
            "The \(side.label) webpage contains a NUL byte at UTF-8 offset \(utf8Offset)."
        case .malformedHTML(let side, let utf8Offset, let reason):
            "The \(side.label) webpage contains \(reason.label) at UTF-8 offset \(utf8Offset)."
        case .tooManyTokens(let side, let maximumTokens):
            "The \(side.label) webpage exceeds the \(maximumTokens)-token limit."
        case .tooManyAttributes(let side, let maximumAttributes):
            "The \(side.label) webpage exceeds the \(maximumAttributes)-attribute limit."
        case .tooManyAttributesInTag(let side, let tagName, let maximumAttributes):
            "The \(side.label) <\(tagName)> tag exceeds the \(maximumAttributes)-attribute limit."
        case .elementNestingTooDeep(let side, let maximumDepth):
            "The \(side.label) webpage exceeds the \(maximumDepth)-element nesting limit."
        case .workLimitExceeded(let side, let maximumWorkUnits):
            "The \(side.label) webpage exceeds the \(maximumWorkUnits)-unit work limit."
        case .outputTooLarge(let side, let maximumBytes):
            "The \(side.label) webpage exceeds the \(maximumBytes)-byte output limit."
        case .cancelled:
            "Webpage comparison was cancelled."
        case .lineDiff(let error):
            error.errorDescription
        }
    }
}

public enum WebPageComparison: Sendable {
    public static func compare(
        left: String,
        right: String,
        options: WebPageComparisonOptions = .default
    ) throws -> WebPageComparisonResult {
        try validate(options.limits)
        try checkCancellation()
        var leftProcessor = HTMLProcessor(
            html: left,
            side: .left,
            mode: options.mode,
            limits: options.limits
        )
        let leftDocument = try leftProcessor.process()
        var rightProcessor = HTMLProcessor(
            html: right,
            side: .right,
            mode: options.mode,
            limits: options.limits
        )
        let rightDocument = try rightProcessor.process()
        try checkCancellation()

        let lineDiff: LineDiffResult
        do {
            lineDiff = try LineDiff.compareResult(
                left: leftDocument.comparisonText,
                right: rightDocument.comparisonText,
                options: options.lineDiffOptions
            )
        } catch let error as LineDiffError {
            throw WebPageComparisonError.lineDiff(error)
        }
        try checkCancellation()
        return WebPageComparisonResult(
            mode: options.mode,
            left: leftDocument,
            right: rightDocument,
            lineDiff: lineDiff
        )
    }

    public static func compare(
        left: Data,
        right: Data,
        options: WebPageComparisonOptions = .default
    ) throws -> WebPageComparisonResult {
        try validate(options.limits)
        let leftText = try decode(left, side: .left, limits: options.limits)
        let rightText = try decode(right, side: .right, limits: options.limits)
        return try compare(left: leftText, right: rightText, options: options)
    }

    private static func decode(
        _ data: Data,
        side: WebPageComparisonSide,
        limits: WebPageComparisonLimits
    ) throws -> String {
        try checkCancellation()
        guard data.count <= limits.maximumInputBytes else {
            throw WebPageComparisonError.inputTooLarge(
                side: side,
                maximumBytes: limits.maximumInputBytes
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw WebPageComparisonError.invalidUTF8(side: side)
        }
        try checkCancellation()
        return text
    }

    private static func validate(_ limits: WebPageComparisonLimits) throws {
        guard limits.maximumInputBytes >= 0,
              limits.maximumTokenCount >= 0,
              limits.maximumAttributeCount >= 0,
              limits.maximumAttributesPerTag >= 0,
              limits.maximumElementDepth >= 0,
              limits.maximumWorkUnits >= 0,
              limits.maximumOutputBytes >= 0 else {
            throw WebPageComparisonError.invalidLimits
        }
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw WebPageComparisonError.cancelled }
    }
}

private extension WebPageComparisonSide {
    var label: String {
        switch self {
        case .left: "left"
        case .right: "right"
        }
    }
}

private extension WebPageHTMLMalformedReason {
    var label: String {
        switch self {
        case .unexpectedLessThan:
            "an unescaped less-than sign"
        case .invalidTagName:
            "an invalid tag name"
        case .malformedClosingTag:
            "a malformed closing tag"
        case .invalidAttribute:
            "an invalid attribute"
        case .missingAttributeValue:
            "an attribute without a value"
        case .unterminatedAttributeValue:
            "an unterminated attribute value"
        case .unterminatedTag:
            "an unterminated tag"
        case .unterminatedComment:
            "an unterminated comment"
        case .unsupportedDeclaration:
            "an unsupported declaration"
        case .invalidCharacterReference:
            "an invalid numeric character reference"
        case .unterminatedRawText(let element):
            "an unterminated <\(element)> raw-text element"
        }
    }
}

private struct HTMLProcessor {
    private struct ElementContext {
        let name: String
        let suppressesText: Bool
        let preformatted: Bool
    }

    private struct StartTag {
        let name: String
        let sourceRange: Range<Int>
        let selfClosing: Bool
        let hidden: Bool
    }

    private let html: String
    private let bytes: [UInt8]
    private let side: WebPageComparisonSide
    private let mode: WebPageComparisonMode
    private let limits: WebPageComparisonLimits

    private var index = 0
    private var tokenCount = 0
    private var attributeCount = 0
    private var remainingWork: Int
    private var output: [UInt8] = []
    private var segments: [WebPageComparisonSegment] = []
    private var elements: [ElementContext] = []
    private var suppressionDepth = 0
    private var preformattedDepth = 0
    private var rawTextElement: String?
    private var pendingCollapsedSpace = false

    init(
        html: String,
        side: WebPageComparisonSide,
        mode: WebPageComparisonMode,
        limits: WebPageComparisonLimits
    ) {
        self.html = html
        bytes = Array(html.utf8)
        self.side = side
        self.mode = mode
        self.limits = limits
        remainingWork = limits.maximumWorkUnits
        output.reserveCapacity(min(html.utf8.count, limits.maximumOutputBytes))
        segments.reserveCapacity(min(limits.maximumTokenCount, 4_096))
        elements.reserveCapacity(min(limits.maximumElementDepth, 256))
    }

    mutating func process() throws -> WebPageComparisonDocument {
        guard bytes.count <= limits.maximumInputBytes else {
            throw WebPageComparisonError.inputTooLarge(
                side: side,
                maximumBytes: limits.maximumInputBytes
            )
        }
        if mode == .source, bytes.count > limits.maximumOutputBytes {
            throw WebPageComparisonError.outputTooLarge(
                side: side,
                maximumBytes: limits.maximumOutputBytes
            )
        }
        let (baseWork, baseWorkOverflow) = bytes.count.multipliedReportingOverflow(by: 2)
        guard !baseWorkOverflow else { throw workLimitError() }
        try consumeWork(baseWork)

        for offset in bytes.indices {
            try checkpoint(offset)
            if bytes[offset] == 0 {
                throw WebPageComparisonError.nullByte(side: side, utf8Offset: offset)
            }
        }

        while index < bytes.count {
            try checkpoint(index)
            if let rawTextElement {
                try parseRawText(for: rawTextElement)
            } else if bytes[index] == ASCII.lessThan {
                try parseMarkup()
            } else {
                try parseText()
            }
        }
        if let rawTextElement {
            throw malformed(
                at: bytes.count,
                .unterminatedRawText(element: rawTextElement)
            )
        }
        try checkCancellation()

        let comparisonText = mode == .source
            ? html
            : String(decoding: output, as: UTF8.self)
        return WebPageComparisonDocument(
            mode: mode,
            comparisonText: comparisonText,
            segments: segments,
            sourceUTF8ByteCount: bytes.count,
            tokenCount: tokenCount,
            attributeCount: attributeCount
        )
    }

    private mutating func parseText() throws {
        let start = index
        while index < bytes.count, bytes[index] != ASCII.lessThan {
            try checkpoint(index - start)
            index += 1
        }
        let range = start..<index
        try recordToken(kind: .text, sourceRange: range)
        if mode == .source || suppressionDepth > 0 {
            try validateCharacterReferences(in: range)
        } else {
            try appendRenderedText(from: range, preformatted: preformattedDepth > 0)
        }
    }

    private mutating func parseMarkup() throws {
        let start = index
        guard index + 1 < bytes.count else {
            throw malformed(at: start, .unexpectedLessThan)
        }
        if hasPrefix("<!--", at: start) {
            try parseComment()
        } else if bytes[index + 1] == ASCII.slash {
            try parseEndTag()
        } else if bytes[index + 1] == ASCII.exclamation {
            try parseDeclaration()
        } else if isTagNameStart(bytes[index + 1]) {
            let tag = try parseStartTag()
            try recordToken(kind: .startTag, sourceRange: tag.sourceRange)
            if mode == .renderedText {
                try processStartTag(tag)
            }
            if !tag.selfClosing, tag.name == "script" || tag.name == "style" {
                rawTextElement = tag.name
            }
        } else {
            throw malformed(at: start, .unexpectedLessThan)
        }
    }

    private mutating func parseComment() throws {
        let start = index
        var cursor = index + 4
        while cursor + 2 < bytes.count {
            try checkpoint(cursor - start)
            if bytes[cursor] == ASCII.hyphen,
               bytes[cursor + 1] == ASCII.hyphen,
               bytes[cursor + 2] == ASCII.greaterThan {
                index = cursor + 3
                try recordToken(kind: .comment, sourceRange: start..<index)
                return
            }
            cursor += 1
        }
        throw malformed(at: start, .unterminatedComment)
    }

    private mutating func parseDeclaration() throws {
        let start = index
        let prefix = "<!doctype"
        guard hasASCIICaseInsensitivePrefix(prefix, at: start) else {
            throw malformed(at: start, .unsupportedDeclaration)
        }
        var cursor = start + prefix.utf8.count
        guard cursor < bytes.count,
              isHTMLWhitespace(bytes[cursor]) || bytes[cursor] == ASCII.greaterThan else {
            throw malformed(at: start, .unsupportedDeclaration)
        }

        var quote: UInt8?
        while cursor < bytes.count {
            try checkpoint(cursor - start)
            let byte = bytes[cursor]
            if let activeQuote = quote {
                if byte == activeQuote { quote = nil }
            } else if byte == ASCII.doubleQuote || byte == ASCII.singleQuote {
                quote = byte
            } else if byte == ASCII.leftBracket {
                throw malformed(at: cursor, .unsupportedDeclaration)
            } else if byte == ASCII.greaterThan {
                index = cursor + 1
                try recordToken(kind: .declaration, sourceRange: start..<index)
                return
            }
            cursor += 1
        }
        throw malformed(at: start, .unterminatedTag)
    }

    private mutating func parseEndTag() throws {
        let start = index
        var cursor = index + 2
        guard cursor < bytes.count, isTagNameStart(bytes[cursor]) else {
            throw malformed(at: start, .invalidTagName)
        }
        let nameStart = cursor
        while cursor < bytes.count, isTagNameContinuation(bytes[cursor]) {
            cursor += 1
        }
        let name = lowercasedASCII(nameStart..<cursor)
        while cursor < bytes.count, isHTMLWhitespace(bytes[cursor]) {
            cursor += 1
        }
        guard cursor < bytes.count, bytes[cursor] == ASCII.greaterThan else {
            throw malformed(at: cursor, .malformedClosingTag)
        }
        index = cursor + 1
        let range = start..<index
        try recordToken(kind: .endTag, sourceRange: range)
        if mode == .renderedText {
            try processEndTag(name: name, sourceRange: range)
        }
        if rawTextElement == name { rawTextElement = nil }
    }

    private mutating func parseStartTag() throws -> StartTag {
        let start = index
        var cursor = index + 1
        guard cursor < bytes.count, isTagNameStart(bytes[cursor]) else {
            throw malformed(at: start, .invalidTagName)
        }
        let nameStart = cursor
        while cursor < bytes.count, isTagNameContinuation(bytes[cursor]) {
            cursor += 1
        }
        let name = lowercasedASCII(nameStart..<cursor)
        var attributesInTag = 0
        var hidden = false

        while cursor < bytes.count {
            try checkpoint(cursor - start)
            while cursor < bytes.count, isHTMLWhitespace(bytes[cursor]) {
                cursor += 1
            }
            guard cursor < bytes.count else {
                throw malformed(at: start, .unterminatedTag)
            }
            if bytes[cursor] == ASCII.greaterThan {
                index = cursor + 1
                return StartTag(
                    name: name,
                    sourceRange: start..<index,
                    selfClosing: false,
                    hidden: hidden
                )
            }
            if bytes[cursor] == ASCII.slash {
                guard cursor + 1 < bytes.count,
                      bytes[cursor + 1] == ASCII.greaterThan else {
                    throw malformed(at: cursor, .invalidAttribute)
                }
                index = cursor + 2
                return StartTag(
                    name: name,
                    sourceRange: start..<index,
                    selfClosing: true,
                    hidden: hidden
                )
            }

            let attributeStart = cursor
            while cursor < bytes.count, isAttributeNameByte(bytes[cursor]) {
                cursor += 1
            }
            guard cursor > attributeStart else {
                throw malformed(at: cursor, .invalidAttribute)
            }
            attributesInTag += 1
            guard attributesInTag <= limits.maximumAttributesPerTag else {
                throw WebPageComparisonError.tooManyAttributesInTag(
                    side: side,
                    tagName: name,
                    maximumAttributes: limits.maximumAttributesPerTag
                )
            }
            attributeCount += 1
            guard attributeCount <= limits.maximumAttributeCount else {
                throw WebPageComparisonError.tooManyAttributes(
                    side: side,
                    maximumAttributes: limits.maximumAttributeCount
                )
            }
            let isHiddenAttribute = asciiEquals(attributeStart..<cursor, "hidden")
            if isHiddenAttribute { hidden = true }

            while cursor < bytes.count, isHTMLWhitespace(bytes[cursor]) {
                cursor += 1
            }
            guard cursor < bytes.count else {
                throw malformed(at: start, .unterminatedTag)
            }
            guard bytes[cursor] == ASCII.equals else { continue }
            cursor += 1
            while cursor < bytes.count, isHTMLWhitespace(bytes[cursor]) {
                cursor += 1
            }
            guard cursor < bytes.count else {
                throw malformed(at: cursor, .missingAttributeValue)
            }

            let valueStart: Int
            let valueEnd: Int
            var hasCharacterReference = false
            if bytes[cursor] == ASCII.doubleQuote || bytes[cursor] == ASCII.singleQuote {
                let quote = bytes[cursor]
                cursor += 1
                valueStart = cursor
                while cursor < bytes.count, bytes[cursor] != quote {
                    try checkpoint(cursor - valueStart)
                    if bytes[cursor] == ASCII.ampersand { hasCharacterReference = true }
                    cursor += 1
                }
                guard cursor < bytes.count else {
                    throw malformed(at: valueStart, .unterminatedAttributeValue)
                }
                valueEnd = cursor
                cursor += 1
            } else {
                valueStart = cursor
                while cursor < bytes.count,
                      !isHTMLWhitespace(bytes[cursor]),
                      bytes[cursor] != ASCII.greaterThan {
                    let byte = bytes[cursor]
                    guard byte != ASCII.doubleQuote,
                          byte != ASCII.singleQuote,
                          byte != ASCII.lessThan,
                          byte != ASCII.equals,
                          byte != ASCII.backtick else {
                        throw malformed(at: cursor, .invalidAttribute)
                    }
                    if byte == ASCII.ampersand { hasCharacterReference = true }
                    cursor += 1
                }
                guard cursor > valueStart else {
                    throw malformed(at: cursor, .missingAttributeValue)
                }
                valueEnd = cursor
            }
            if hasCharacterReference {
                try validateCharacterReferences(in: valueStart..<valueEnd)
            }
        }
        throw malformed(at: start, .unterminatedTag)
    }

    private mutating func parseRawText(for element: String) throws {
        let contentStart = index
        let nameBytes = Array(element.utf8)
        var cursor = index
        while cursor < bytes.count {
            try checkpoint(cursor - contentStart)
            if bytes[cursor] == ASCII.lessThan,
               cursor + 2 + nameBytes.count <= bytes.count,
               bytes[cursor + 1] == ASCII.slash,
               asciiCaseInsensitiveMatch(nameBytes, at: cursor + 2) {
                let delimiterIndex = cursor + 2 + nameBytes.count
                if delimiterIndex < bytes.count,
                   isHTMLWhitespace(bytes[delimiterIndex]) ||
                    bytes[delimiterIndex] == ASCII.greaterThan {
                    if contentStart < cursor {
                        try recordToken(kind: .rawText, sourceRange: contentStart..<cursor)
                    }
                    index = cursor
                    rawTextElement = nil
                    return
                }
            }
            cursor += 1
        }
        throw malformed(
            at: contentStart,
            .unterminatedRawText(element: element)
        )
    }

    private mutating func recordToken(
        kind: WebPageComparisonSegmentKind,
        sourceRange: Range<Int>
    ) throws {
        tokenCount += 1
        guard tokenCount <= limits.maximumTokenCount else {
            throw WebPageComparisonError.tooManyTokens(
                side: side,
                maximumTokens: limits.maximumTokenCount
            )
        }
        if mode == .source {
            segments.append(
                WebPageComparisonSegment(
                    kind: kind,
                    sourceUTF8Range: sourceRange,
                    outputUTF8Range: sourceRange
                )
            )
        }
    }

    private mutating func processStartTag(_ tag: StartTag) throws {
        if tag.name == "body" {
            try implicitlyCloseHead()
        }
        let parentSuppressed = suppressionDepth > 0
        let suppresses = tag.hidden || Self.suppressedElementNames.contains(tag.name)
        if !parentSuppressed, !suppresses {
            try appendBoundary(for: tag.name, sourceRange: tag.sourceRange)
        }

        guard !tag.selfClosing, !Self.voidElementNames.contains(tag.name) else { return }
        guard elements.count < limits.maximumElementDepth else {
            throw WebPageComparisonError.elementNestingTooDeep(
                side: side,
                maximumDepth: limits.maximumElementDepth
            )
        }
        let preformatted = tag.name == "pre" || tag.name == "textarea"
        elements.append(
            ElementContext(
                name: tag.name,
                suppressesText: suppresses,
                preformatted: preformatted
            )
        )
        if suppresses { suppressionDepth += 1 }
        if preformatted { preformattedDepth += 1 }
    }

    private mutating func processEndTag(
        name: String,
        sourceRange: Range<Int>
    ) throws {
        var matchingIndex: Int?
        var cursor = elements.count
        while cursor > 0 {
            cursor -= 1
            try consumeWork(1)
            if elements[cursor].name == name {
                matchingIndex = cursor
                break
            }
        }

        let wasVisible = suppressionDepth == 0
        if let matchingIndex {
            for context in elements[matchingIndex...] {
                if context.suppressesText { suppressionDepth -= 1 }
                if context.preformatted { preformattedDepth -= 1 }
            }
            elements.removeSubrange(matchingIndex...)
        }
        if wasVisible {
            try appendBoundary(for: name, sourceRange: sourceRange)
        }
    }

    private mutating func implicitlyCloseHead() throws {
        guard suppressionDepth > 0 else { return }
        var headIndex: Int?
        var cursor = elements.count
        while cursor > 0 {
            cursor -= 1
            try consumeWork(1)
            if elements[cursor].name == "head" {
                headIndex = cursor
                break
            }
        }
        guard let headIndex else { return }
        for context in elements[headIndex...] {
            if context.suppressesText { suppressionDepth -= 1 }
            if context.preformatted { preformattedDepth -= 1 }
        }
        elements.removeSubrange(headIndex...)
    }

    private mutating func appendBoundary(
        for tagName: String,
        sourceRange: Range<Int>
    ) throws {
        guard Self.lineBoundaryElements.contains(tagName) else { return }
        pendingCollapsedSpace = false
        guard !output.isEmpty, output.last != ASCII.lineFeed else { return }
        let outputStart = output.count
        try appendOutput([ASCII.lineFeed])
        segments.append(
            WebPageComparisonSegment(
                kind: .renderedBoundary,
                sourceUTF8Range: sourceRange,
                outputUTF8Range: outputStart..<output.count
            )
        )
    }

    private mutating func appendRenderedText(
        from sourceRange: Range<Int>,
        preformatted: Bool
    ) throws {
        try consumeWork(sourceRange.count)
        let outputStart = output.count
        var cursor = sourceRange.lowerBound
        while cursor < sourceRange.upperBound {
            try checkpoint(cursor - sourceRange.lowerBound)
            if bytes[cursor] == ASCII.ampersand,
               let reference = try characterReference(at: cursor, end: sourceRange.upperBound) {
                if preformatted {
                    try appendPreformattedBytes(reference.bytes)
                } else {
                    try appendCollapsedBytes(reference.bytes)
                }
                cursor = reference.end
                continue
            }

            var runEnd = cursor + 1
            while runEnd < sourceRange.upperBound,
                  bytes[runEnd] != ASCII.ampersand {
                if preformatted {
                    if bytes[runEnd] == ASCII.carriageReturn { break }
                } else if isHTMLWhitespace(bytes[runEnd]) {
                    break
                }
                runEnd += 1
            }
            let run = Array(bytes[cursor..<runEnd])
            if preformatted {
                try appendPreformattedBytes(run)
            } else {
                try appendCollapsedBytes(run)
            }
            cursor = runEnd
        }
        if output.count > outputStart {
            segments.append(
                WebPageComparisonSegment(
                    kind: .text,
                    sourceUTF8Range: sourceRange,
                    outputUTF8Range: outputStart..<output.count
                )
            )
        }
    }

    private mutating func appendCollapsedBytes(_ value: [UInt8]) throws {
        var cursor = 0
        while cursor < value.count {
            if isHTMLWhitespace(value[cursor]) {
                pendingCollapsedSpace = !output.isEmpty && output.last != ASCII.lineFeed
                cursor += 1
                continue
            }
            var runEnd = cursor + 1
            while runEnd < value.count, !isHTMLWhitespace(value[runEnd]) {
                runEnd += 1
            }
            if pendingCollapsedSpace {
                try appendOutput([ASCII.space])
                pendingCollapsedSpace = false
            }
            try appendOutput(Array(value[cursor..<runEnd]))
            cursor = runEnd
        }
    }

    private mutating func appendPreformattedBytes(_ value: [UInt8]) throws {
        pendingCollapsedSpace = false
        var cursor = 0
        while cursor < value.count {
            if value[cursor] == ASCII.carriageReturn {
                try appendOutput([ASCII.lineFeed])
                cursor += 1
                if cursor < value.count, value[cursor] == ASCII.lineFeed {
                    cursor += 1
                }
            } else {
                var runEnd = cursor + 1
                while runEnd < value.count, value[runEnd] != ASCII.carriageReturn {
                    runEnd += 1
                }
                try appendOutput(Array(value[cursor..<runEnd]))
                cursor = runEnd
            }
        }
    }

    private mutating func validateCharacterReferences(in range: Range<Int>) throws {
        try consumeWork(range.count)
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            try checkpoint(cursor - range.lowerBound)
            if bytes[cursor] == ASCII.ampersand,
               let reference = try characterReference(at: cursor, end: range.upperBound) {
                cursor = reference.end
            } else {
                cursor += 1
            }
        }
    }

    private func characterReference(
        at start: Int,
        end: Int
    ) throws -> (bytes: [UInt8], end: Int)? {
        guard start + 1 < end else { return nil }
        if bytes[start + 1] == ASCII.numberSign {
            var cursor = start + 2
            var radix: UInt32 = 10
            if cursor < end, bytes[cursor] == ASCII.lowercaseX || bytes[cursor] == ASCII.uppercaseX {
                radix = 16
                cursor += 1
            }
            let digitStart = cursor
            var value: UInt32 = 0
            while cursor < end, let digit = digitValue(bytes[cursor], radix: radix) {
                let (multiplied, multiplyOverflow) = value.multipliedReportingOverflow(by: radix)
                let (added, addOverflow) = multiplied.addingReportingOverflow(digit)
                guard !multiplyOverflow, !addOverflow else {
                    throw malformed(at: start, .invalidCharacterReference)
                }
                value = added
                cursor += 1
            }
            guard cursor > digitStart,
                  cursor < end,
                  bytes[cursor] == ASCII.semicolon,
                  let scalar = Unicode.Scalar(value),
                  value != 0 else {
                throw malformed(at: start, .invalidCharacterReference)
            }
            return (Array(String(scalar).utf8), cursor + 1)
        }

        var cursor = start + 1
        while cursor < end, isASCIIAlphanumeric(bytes[cursor]) {
            cursor += 1
        }
        guard cursor > start + 1,
              cursor < end,
              bytes[cursor] == ASCII.semicolon else {
            return nil
        }
        let nameRange = (start + 1)..<cursor
        guard nameRange.count <= 16 else { return nil }
        let name = String(decoding: bytes[nameRange], as: UTF8.self)
        guard let decoded = Self.namedCharacterReferences[name] else { return nil }
        return (decoded, cursor + 1)
    }

    private mutating func appendOutput(_ value: [UInt8]) throws {
        guard value.count <= limits.maximumOutputBytes - output.count else {
            throw WebPageComparisonError.outputTooLarge(
                side: side,
                maximumBytes: limits.maximumOutputBytes
            )
        }
        try consumeWork(value.count)
        output.append(contentsOf: value)
    }

    private mutating func consumeWork(_ amount: Int) throws {
        guard amount >= 0, amount <= remainingWork else { throw workLimitError() }
        remainingWork -= amount
        try checkCancellation()
    }

    private func checkpoint(_ progress: Int) throws {
        if progress & 0xFFF == 0 { try checkCancellation() }
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw WebPageComparisonError.cancelled }
    }

    private func workLimitError() -> WebPageComparisonError {
        WebPageComparisonError.workLimitExceeded(
            side: side,
            maximumWorkUnits: limits.maximumWorkUnits
        )
    }

    private func malformed(
        at offset: Int,
        _ reason: WebPageHTMLMalformedReason
    ) -> WebPageComparisonError {
        WebPageComparisonError.malformedHTML(
            side: side,
            utf8Offset: min(max(0, offset), bytes.count),
            reason: reason
        )
    }

    private func hasPrefix(_ prefix: StaticString, at offset: Int) -> Bool {
        let prefixBytes = Array(String(describing: prefix).utf8)
        guard offset <= bytes.count - prefixBytes.count else { return false }
        return bytes[offset..<(offset + prefixBytes.count)].elementsEqual(prefixBytes)
    }

    private func hasASCIICaseInsensitivePrefix(_ prefix: String, at offset: Int) -> Bool {
        asciiCaseInsensitiveMatch(Array(prefix.utf8), at: offset)
    }

    private func asciiCaseInsensitiveMatch(_ value: [UInt8], at offset: Int) -> Bool {
        guard offset <= bytes.count - value.count else { return false }
        for valueIndex in value.indices {
            if asciiLower(bytes[offset + valueIndex]) != asciiLower(value[valueIndex]) {
                return false
            }
        }
        return true
    }

    private func lowercasedASCII(_ range: Range<Int>) -> String {
        String(decoding: bytes[range].map(asciiLower), as: UTF8.self)
    }

    private func asciiEquals(_ range: Range<Int>, _ value: String) -> Bool {
        asciiCaseInsensitiveMatch(Array(value.utf8), at: range.lowerBound) &&
            range.count == value.utf8.count
    }

    private static let suppressedElementNames: Set<String> = [
        "head", "script", "style", "template"
    ]

    private static let voidElementNames: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr"
    ]

    private static let lineBoundaryElements: Set<String> = [
        "address", "article", "aside", "blockquote", "br", "dd", "div", "dl", "dt",
        "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4",
        "h5", "h6", "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section",
        "table", "tr", "ul"
    ]

    private static let namedCharacterReferences: [String: [UInt8]] = [
        "amp": Array("&".utf8),
        "apos": Array("'".utf8),
        "bull": Array("•".utf8),
        "cent": Array("¢".utf8),
        "copy": Array("©".utf8),
        "emsp": Array(" ".utf8),
        "ensp": Array(" ".utf8),
        "euro": Array("€".utf8),
        "gt": Array(">".utf8),
        "hellip": Array("…".utf8),
        "laquo": Array("«".utf8),
        "ldquo": Array("“".utf8),
        "lsquo": Array("‘".utf8),
        "lt": Array("<".utf8),
        "mdash": Array("—".utf8),
        "middot": Array("·".utf8),
        "nbsp": Array(" ".utf8),
        "ndash": Array("–".utf8),
        "pound": Array("£".utf8),
        "quot": Array("\"".utf8),
        "raquo": Array("»".utf8),
        "rdquo": Array("”".utf8),
        "reg": Array("®".utf8),
        "rsquo": Array("’".utf8),
        "trade": Array("™".utf8),
        "yen": Array("¥".utf8)
    ]
}

private enum ASCII {
    static let space: UInt8 = 0x20
    static let exclamation: UInt8 = 0x21
    static let doubleQuote: UInt8 = 0x22
    static let numberSign: UInt8 = 0x23
    static let ampersand: UInt8 = 0x26
    static let singleQuote: UInt8 = 0x27
    static let hyphen: UInt8 = 0x2D
    static let slash: UInt8 = 0x2F
    static let semicolon: UInt8 = 0x3B
    static let lessThan: UInt8 = 0x3C
    static let equals: UInt8 = 0x3D
    static let greaterThan: UInt8 = 0x3E
    static let uppercaseX: UInt8 = 0x58
    static let leftBracket: UInt8 = 0x5B
    static let backtick: UInt8 = 0x60
    static let lowercaseX: UInt8 = 0x78
    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
}

private func isHTMLWhitespace(_ byte: UInt8) -> Bool {
    byte == ASCII.space || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
}

private func isTagNameStart(_ byte: UInt8) -> Bool {
    (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
}

private func isTagNameContinuation(_ byte: UInt8) -> Bool {
    isASCIIAlphanumeric(byte) || byte == 0x2D || byte == 0x3A || byte == 0x5F
}

private func isAttributeNameByte(_ byte: UInt8) -> Bool {
    !isHTMLWhitespace(byte) &&
        byte != ASCII.doubleQuote &&
        byte != ASCII.singleQuote &&
        byte != ASCII.slash &&
        byte != ASCII.lessThan &&
        byte != ASCII.equals &&
        byte != ASCII.greaterThan &&
        byte != ASCII.backtick
}

private func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte) ||
        (0x41...0x5A).contains(byte) ||
        (0x61...0x7A).contains(byte)
}

private func asciiLower(_ byte: UInt8) -> UInt8 {
    (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
}

private func digitValue(_ byte: UInt8, radix: UInt32) -> UInt32? {
    let value: UInt32
    switch byte {
    case 0x30...0x39:
        value = UInt32(byte - 0x30)
    case 0x41...0x46:
        value = UInt32(byte - 0x41 + 10)
    case 0x61...0x66:
        value = UInt32(byte - 0x61 + 10)
    default:
        return nil
    }
    return value < radix ? value : nil
}
