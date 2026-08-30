import Foundation

private let editorColorSchemeDiagnosticMaximumUTF8Bytes = 256

private func boundedEditorColorSchemeDiagnostic(
    _ value: String,
    maximumUTF8Bytes: Int = editorColorSchemeDiagnosticMaximumUTF8Bytes
) -> String {
    let bytes = value.utf8
    guard bytes.prefix(maximumUTF8Bytes + 1).count > maximumUTF8Bytes else { return value }
    return String(decoding: bytes.prefix(maximumUTF8Bytes - 5), as: UTF8.self) + "..."
}

private enum EditorColorSchemeCanonicalJSONValue {
    case array([Self])
    case number(String)
    case object([(String, Self)])
    case string(String)
}

private struct EditorColorSchemeCanonicalJSONParser {
    private let bytes: [UInt8]
    private let maximumDepth: Int
    private let maximumValues: Int
    private var index = 0
    private var valueCount = 0

    init(data: Data, maximumDepth: Int, maximumValues: Int) {
        bytes = Array(data)
        self.maximumDepth = maximumDepth
        self.maximumValues = maximumValues
    }

    mutating func parse() throws -> EditorColorSchemeCanonicalJSONValue {
        let value = try parseValue(depth: 0)
        guard index == bytes.count else { throw malformedJSON() }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> EditorColorSchemeCanonicalJSONValue {
        valueCount += 1
        guard valueCount <= maximumValues, let byte = currentByte else {
            throw malformedJSON()
        }
        switch byte {
        case 0x7B:
            return try parseObject(depth: depth + 1)
        case 0x5B:
            return try parseArray(depth: depth + 1)
        case 0x22:
            return .string(try parseString())
        case 0x2D, 0x30...0x39:
            return .number(try parseNumber())
        default:
            throw malformedJSON()
        }
    }

    private mutating func parseObject(
        depth: Int
    ) throws -> EditorColorSchemeCanonicalJSONValue {
        guard depth <= maximumDepth, consume(0x7B) else { throw malformedJSON() }
        if consume(0x7D) { return .object([]) }

        var entries: [(String, EditorColorSchemeCanonicalJSONValue)] = []
        var previousKeyBytes: [UInt8]?
        while true {
            let key = try parseString()
            let keyBytes = Array(key.utf8)
            if let previousKeyBytes {
                guard previousKeyBytes.lexicographicallyPrecedes(keyBytes) else {
                    throw malformedJSON()
                }
            }
            previousKeyBytes = keyBytes
            guard consume(0x3A) else { throw malformedJSON() }
            entries.append((key, try parseValue(depth: depth)))
            if consume(0x7D) { return .object(entries) }
            guard consume(0x2C) else { throw malformedJSON() }
        }
    }

    private mutating func parseArray(
        depth: Int
    ) throws -> EditorColorSchemeCanonicalJSONValue {
        guard depth <= maximumDepth, consume(0x5B) else { throw malformedJSON() }
        if consume(0x5D) { return .array([]) }

        var values: [EditorColorSchemeCanonicalJSONValue] = []
        while true {
            values.append(try parseValue(depth: depth))
            if consume(0x5D) { return .array(values) }
            guard consume(0x2C) else { throw malformedJSON() }
        }
    }

    private mutating func parseString() throws -> String {
        guard consume(0x22) else { throw malformedJSON() }
        var decoded: [UInt8] = []
        while let byte = currentByte {
            index += 1
            if byte == 0x22 {
                guard let value = String(bytes: decoded, encoding: .utf8) else {
                    throw malformedJSON()
                }
                return value
            }
            if byte == 0x5C {
                guard let escaped = currentByte, escaped == 0x22 || escaped == 0x5C else {
                    throw malformedJSON()
                }
                decoded.append(escaped)
                index += 1
            } else if byte < 0x20 {
                throw malformedJSON()
            } else {
                decoded.append(byte)
            }
        }
        throw malformedJSON()
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        _ = consume(0x2D)
        if consume(0x30) {
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw malformedJSON()
            }
        } else {
            guard consumeDigit(in: 0x31...0x39) else { throw malformedJSON() }
            while consumeDigit(in: 0x30...0x39) {}
        }
        if consume(0x2E) {
            guard consumeDigit(in: 0x30...0x39) else { throw malformedJSON() }
            while consumeDigit(in: 0x30...0x39) {}
        }
        if currentByte == 0x65 || currentByte == 0x45 {
            index += 1
            if currentByte == 0x2B || currentByte == 0x2D { index += 1 }
            guard consumeDigit(in: 0x30...0x39) else { throw malformedJSON() }
            while consumeDigit(in: 0x30...0x39) {}
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private mutating func consumeDigit(in range: ClosedRange<UInt8>) -> Bool {
        guard let currentByte, range.contains(currentByte) else { return false }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func malformedJSON() -> DecodingError {
        .dataCorrupted(
            .init(
                codingPath: [],
                debugDescription: "Editor color scheme data is not valid bounded strict JSON."
            )
        )
    }

}

private struct EditorColorSchemeCanonicalJSONWriter {
    private var bytes: [UInt8] = []

    var data: Data { Data(bytes) }

    mutating func append(_ value: StaticString) {
        value.withUTF8Buffer { bytes.append(contentsOf: $0) }
    }

    mutating func append(string value: String) {
        bytes.append(0x22)
        for byte in value.utf8 {
            if byte == 0x22 || byte == 0x5C { bytes.append(0x5C) }
            bytes.append(byte)
        }
        bytes.append(0x22)
    }

    mutating func append(integer value: UInt64) {
        bytes.append(contentsOf: String(value).utf8)
    }
}

extension EditorColorSchemeCanonicalJSONValue {
    fileprivate func array(maximumCount: Int) throws -> [Self] {
        guard case .array(let values) = self else {
            throw malformedEditorColorSchemeCanonicalJSON()
        }
        guard values.count <= maximumCount else {
            throw EditorColorSchemeError.paletteLimitExceeded
        }
        return values
    }

    fileprivate func object(keys expectedKeys: [String]) throws -> [Self] {
        guard case .object(let entries) = self, entries.map(\.0) == expectedKeys else {
            throw malformedEditorColorSchemeCanonicalJSON()
        }
        return entries.map(\.1)
    }

    fileprivate func string() throws -> String {
        guard case .string(let value) = self else {
            throw malformedEditorColorSchemeCanonicalJSON()
        }
        return value
    }

    fileprivate func uint64() throws -> UInt64 {
        guard case .number(let source) = self, let value = UInt64(source), String(value) == source
        else {
            throw malformedEditorColorSchemeCanonicalJSON()
        }
        return value
    }

    fileprivate func integer() throws -> Int {
        guard case .number(let source) = self, let value = Int(source), String(value) == source else {
            throw malformedEditorColorSchemeCanonicalJSON()
        }
        return value
    }
}

private func malformedEditorColorSchemeCanonicalJSON() -> DecodingError {
    .dataCorrupted(
        .init(
            codingPath: [],
            debugDescription: "Editor color scheme data is not canonical schema-v2 JSON."
        )
    )
}

/// Portable sRGB color components. Values are finite and normalized to `0...1`.
public struct EditorColorComponents: Encodable, Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) throws {
        try Self.validate(red, component: "red")
        try Self.validate(green, component: "green")
        try Self.validate(blue, component: "blue")
        try Self.validate(alpha, component: "alpha")
        self.red = Self.canonicalComponent(red)
        self.green = Self.canonicalComponent(green)
        self.blue = Self.canonicalComponent(blue)
        self.alpha = Self.canonicalComponent(alpha)
    }

    /// Accepts `RRGGBB`, `RRGGBBAA`, `#RRGGBB`, or `#RRGGBBAA`.
    public init(sRGBHex: String) throws {
        let sourceBytes = sRGBHex.utf8
        let hasHashPrefix = sourceBytes.first == 0x23
        let sourceCount = sourceBytes.prefix(10).count
        guard hasHashPrefix ? sourceCount == 7 || sourceCount == 9 : sourceCount == 6 || sourceCount == 8
        else {
            throw EditorColorSchemeError.invalidHexColor(
                boundedEditorColorSchemeDiagnostic(sRGBHex, maximumUTF8Bytes: 64)
            )
        }
        let valueBytes = hasHashPrefix ? sourceBytes.dropFirst() : sourceBytes[...]
        guard
            valueBytes.allSatisfy({
                (0x30...0x39).contains($0)
                    || (0x41...0x46).contains($0)
                    || (0x61...0x66).contains($0)
            }),
            let packed = UInt64(String(decoding: valueBytes, as: UTF8.self), radix: 16)
        else {
            throw EditorColorSchemeError.invalidHexColor(
                boundedEditorColorSchemeDiagnostic(sRGBHex, maximumUTF8Bytes: 64)
            )
        }

        let hasAlpha = valueBytes.count == 8
        let red = hasAlpha ? (packed >> 24) & 0xFF : (packed >> 16) & 0xFF
        let green = hasAlpha ? (packed >> 16) & 0xFF : (packed >> 8) & 0xFF
        let blue = hasAlpha ? (packed >> 8) & 0xFF : packed & 0xFF
        let alpha = hasAlpha ? packed & 0xFF : 0xFF
        try self.init(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            alpha: Double(alpha) / 255
        )
    }

    public var sRGBHex: String {
        let red = UInt8((self.red * 255).rounded())
        let green = UInt8((self.green * 255).rounded())
        let blue = UInt8((self.blue * 255).rounded())
        let alpha = UInt8((self.alpha * 255).rounded())
        if alpha == 255 {
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    /// WCAG-style relative luminance of the RGB channels. Alpha does not affect this value.
    public var relativeLuminance: Double {
        0.2126 * Self.linearized(red)
            + 0.7152 * Self.linearized(green)
            + 0.0722 * Self.linearized(blue)
    }

    /// WCAG-style contrast ratio of the RGB channels in `1...21`. Alpha is ignored.
    public func contrastRatio(with other: EditorColorComponents) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Composites this color over `background` using non-premultiplied source-over alpha.
    public func composited(over background: EditorColorComponents) -> EditorColorComponents {
        let outputAlpha = alpha + background.alpha * (1 - alpha)
        guard outputAlpha > 0 else {
            return EditorColorComponents(uncheckedRed: 0, green: 0, blue: 0, alpha: 0)
        }
        return EditorColorComponents(
            uncheckedRed: (red * alpha + background.red * background.alpha * (1 - alpha))
                / outputAlpha,
            green: (green * alpha + background.green * background.alpha * (1 - alpha))
                / outputAlpha,
            blue: (blue * alpha + background.blue * background.alpha * (1 - alpha))
                / outputAlpha,
            alpha: outputAlpha
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case red
        case green
        case blue
        case alpha
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validate(red, component: "red")
        try Self.validate(green, component: "green")
        try Self.validate(blue, component: "blue")
        try Self.validate(alpha, component: "alpha")
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(alpha, forKey: .alpha)
    }

    fileprivate init(uncheckedRed red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    fileprivate init(builtInHex value: String) {
        guard value.utf8.count == 6 || value.utf8.count == 8,
            value.utf8.allSatisfy({
                (0x30...0x39).contains($0) || (0x41...0x46).contains($0)
                    || (0x61...0x66).contains($0)
            }),
            let packed = UInt64(value, radix: 16)
        else {
            preconditionFailure("Invalid built-in editor color: \(value)")
        }
        let hasAlpha = value.utf8.count == 8
        red = Double(hasAlpha ? (packed >> 24) & 0xFF : (packed >> 16) & 0xFF) / 255
        green = Double(hasAlpha ? (packed >> 16) & 0xFF : (packed >> 8) & 0xFF) / 255
        blue = Double(hasAlpha ? (packed >> 8) & 0xFF : packed & 0xFF) / 255
        alpha = Double(hasAlpha ? packed & 0xFF : 0xFF) / 255
    }

    private static func validate(_ value: Double, component: String) throws {
        guard value.isFinite, (0...1).contains(value) else {
            throw EditorColorSchemeError.invalidColorComponent(component, value)
        }
    }

    private static func linearized(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func canonicalComponent(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }
}

/// Stable UI-independent name for a color supplied by an editor palette.
public struct EditorColorToken: Encodable, Comparable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 128

    public let rawValue: String

    public init(rawValue: String) throws {
        try Self.validate(rawValue, maximumUTF8Bytes: Self.maximumUTF8Bytes)
        self.rawValue = rawValue
    }

    fileprivate init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }

    public static func < (lhs: EditorColorToken, rhs: EditorColorToken) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validate(rawValue, maximumUTF8Bytes: Self.maximumUTF8Bytes)
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func validate(_ value: String, maximumUTF8Bytes: Int) throws {
        guard !value.isEmpty, value.utf8.count <= maximumUTF8Bytes,
            value.utf8.allSatisfy(Self.isPortableTokenByte),
            let first = value.utf8.first, Self.isASCIIAlphanumeric(first),
            let last = value.utf8.last, Self.isASCIIAlphanumeric(last)
        else {
            if value.utf8.count > maximumUTF8Bytes {
                throw EditorColorSchemeError.colorTokenTooLarge(
                    maximumUTF8Bytes: maximumUTF8Bytes
                )
            }
            throw EditorColorSchemeError.invalidColorToken(value)
        }
    }

    private static func isPortableTokenByte(_ byte: UInt8) -> Bool {
        isASCIIAlphanumeric(byte)
            || byte == 0x2D || byte == 0x2E || byte == 0x2F || byte == 0x3A
            || byte == 0x5F
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)
            || (0x61...0x7A).contains(byte)
    }
}

public enum EditorColorSchemeVariant: String, CaseIterable, Encodable, Equatable, Hashable, Sendable {
    case light
    case dark
    case highContrastLight
    case highContrastDark

    public var isDark: Bool {
        self == .dark || self == .highContrastDark
    }

    public var isHighContrast: Bool {
        self == .highContrastLight || self == .highContrastDark
    }
}

/// Semantic editor color slots. Renderers remain responsible for converting components to UI colors.
public enum EditorColorRole: String, CaseIterable, Encodable, Equatable, Hashable, Sendable {
    case textBackground = "text.background"
    case textForeground = "text.foreground"
    case textCaret = "text.caret"
    case textSecondary = "text.secondary"
    case textLineNumber = "text.line-number"
    case textCurrentLineBackground = "text.current-line-background"

    case selectionBackground = "selection.background"
    case selectionForeground = "selection.foreground"
    case selectionInactiveBackground = "selection.inactive-background"
    case selectionInactiveForeground = "selection.inactive-foreground"

    case differenceAddedBackground = "difference.added-background"
    case differenceAddedForeground = "difference.added-foreground"
    case differenceAddedCue = "difference.added-cue"
    case differenceAddedPattern = "difference.added-pattern"
    case differenceRemovedBackground = "difference.removed-background"
    case differenceRemovedForeground = "difference.removed-foreground"
    case differenceRemovedCue = "difference.removed-cue"
    case differenceRemovedPattern = "difference.removed-pattern"
    case differenceModifiedBackground = "difference.modified-background"
    case differenceModifiedForeground = "difference.modified-foreground"
    case differenceModifiedCue = "difference.modified-cue"
    case differenceModifiedPattern = "difference.modified-pattern"
    case differenceConflictBackground = "difference.conflict-background"
    case differenceConflictForeground = "difference.conflict-foreground"
    case differenceConflictCue = "difference.conflict-cue"
    case differenceConflictPattern = "difference.conflict-pattern"

    case movedLineBackground = "moved-line.background"
    case movedLineForeground = "moved-line.foreground"
    case movedLineCue = "moved-line.cue"
    case movedLinePattern = "moved-line.pattern"
    case movedLineConnector = "moved-line.connector"

    case syntaxKeyword = "syntax.keyword"
    case syntaxString = "syntax.string"
    case syntaxComment = "syntax.comment"
    case syntaxNumber = "syntax.number"
    case syntaxLiteral = "syntax.literal"
    case syntaxHeading = "syntax.heading"
    case syntaxEmphasis = "syntax.emphasis"
    case syntaxCode = "syntax.code"
    case syntaxLink = "syntax.link"

    case markerSearchBackground = "marker.search-background"
    case markerSearchForeground = "marker.search-foreground"
    case markerCurrentSearchBackground = "marker.current-search-background"
    case markerCurrentSearchForeground = "marker.current-search-foreground"
    case markerBookmark = "marker.bookmark"
    case markerWhitespace = "marker.whitespace"
    case markerEndOfLine = "marker.end-of-line"

    case systemGutterBackground = "system.gutter-background"
    case systemSeparator = "system.separator"
    case systemFocusRing = "system.focus-ring"
    case systemAccent = "system.accent"
    case systemWarning = "system.warning"
    case systemError = "system.error"

    /// Background layer for roles governed by editor overlay exclusivity, otherwise `nil`.
    public var backgroundLayer: EditorColorLayer? {
        switch self {
        case .differenceAddedBackground, .differenceRemovedBackground,
            .differenceModifiedBackground, .differenceConflictBackground,
            .movedLineBackground:
            .differenceOrMoved
        case .textCurrentLineBackground:
            .currentLine
        case .selectionBackground, .selectionInactiveBackground,
            .markerSearchBackground, .markerCurrentSearchBackground:
            .selectionOrSearch
        default:
            nil
        }
    }

    /// Geometry plane for roles rendered inside editor content. System roles used as colors by
    /// another plane return `nil`.
    public var renderPlane: EditorColorRenderPlane? {
        switch self {
        case .textBackground:
            .canvasBackground
        case .systemGutterBackground:
            .gutterBackground
        case .differenceAddedBackground, .differenceRemovedBackground,
            .differenceModifiedBackground, .differenceConflictBackground,
            .movedLineBackground:
            .differenceFill
        case .differenceAddedPattern, .differenceRemovedPattern,
            .differenceModifiedPattern, .differenceConflictPattern,
            .movedLinePattern:
            .differencePattern
        case .textCurrentLineBackground:
            .currentLineFill
        case .textForeground, .textSecondary, .textLineNumber,
            .differenceAddedForeground, .differenceRemovedForeground,
            .differenceModifiedForeground, .differenceConflictForeground,
            .movedLineForeground, .syntaxKeyword, .syntaxString, .syntaxComment,
            .syntaxNumber, .syntaxLiteral, .syntaxHeading, .syntaxEmphasis, .syntaxCode,
            .syntaxLink:
            .contentForeground
        case .differenceAddedCue, .differenceRemovedCue, .differenceModifiedCue,
            .differenceConflictCue, .movedLineCue:
            .differenceCue
        case .movedLineConnector:
            .movedLineConnector
        case .markerBookmark:
            .markerBookmark
        case .markerWhitespace:
            .markerWhitespace
        case .markerEndOfLine:
            .markerEndOfLine
        case .textCaret:
            .textCaret
        case .selectionBackground, .selectionInactiveBackground,
            .markerSearchBackground, .markerCurrentSearchBackground:
            .overlayFill
        case .selectionForeground, .selectionInactiveForeground,
            .markerSearchForeground, .markerCurrentSearchForeground:
            .overlayForeground
        case .systemSeparator, .systemFocusRing, .systemAccent, .systemWarning, .systemError:
            nil
        }
    }
}

public struct EditorColorDefinition: Encodable, Equatable, Hashable, Sendable {
    public let token: EditorColorToken
    public let components: EditorColorComponents

    public init(token: EditorColorToken, components: EditorColorComponents) {
        self.token = token
        self.components = components
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case token
        case components
    }

}

public struct EditorColorAssignment: Encodable, Equatable, Hashable, Sendable {
    public let role: EditorColorRole
    public let token: EditorColorToken

    public init(role: EditorColorRole, token: EditorColorToken) {
        self.role = role
        self.token = token
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case token
    }

}

public enum EditorDifferenceKind: String, CaseIterable, Encodable, Equatable, Hashable, Sendable {
    case added
    case removed
    case modified
    case conflict
    case moved
}

/// Geometry usable when color differentiation is disabled or unavailable.
public enum EditorDifferenceShape: String, CaseIterable, Encodable, Equatable, Hashable, Sendable {
    case leadingBar
    case trailingBar
    case underline
    case strikeThrough
    case outline
    case doubleOutline
}

/// Fill metadata usable by renderers that support patterned difference backgrounds.
public enum EditorDifferencePattern: String, CaseIterable, Encodable, Equatable, Hashable, Sendable {
    case solid
    case forwardDiagonal
    case backwardDiagonal
    case crosshatch
    case dots
}

/// Difference patterns share one canvas-anchored phase so adjacent lines cannot shift identity.
public enum EditorDifferencePatternPhase: String, Equatable, Hashable, Sendable {
    case editorCanvas
}

/// Difference foreground replaces ordinary text and syntax roles wherever its fill is present.
public enum EditorDifferenceForegroundBehavior: String, Equatable, Hashable, Sendable {
    case replacesTextAndSyntax
}

/// Required back-to-front rendering for a difference region.
public enum EditorDifferenceCompositingRule: String, Equatable, Hashable, Sendable {
    /// Source-over fill and canvas-phased pattern; higher backgrounds source-over that result. Pattern
    /// ink is clipped from foreground, cue, and selection/search geometry. Difference foreground
    /// replaces ordinary text and syntax over the resulting pattern gap. Difference cue is last
    /// within the decoration and precedes every higher render plane.
    case sourceOverFillClippedPatternForegroundCue
}

/// Total back-to-front order for every potentially overlapping editor-content plane.
///
/// Mutually exclusive states share a plane. At `contentForeground`, difference foreground replaces
/// ordinary text and syntax. Higher cue planes clip and replace lower cue pixels where they overlap.
public enum EditorColorRenderPlane: Int, CaseIterable, Comparable, Equatable, Hashable, Sendable {
    case canvasBackground
    /// Spatially limited to the gutter and composited source-over the canvas color.
    case gutterBackground
    case differenceFill
    case differencePattern
    case currentLineFill
    case contentForeground
    case differenceCue
    case currentLineCue
    case movedLineConnector
    case markerBookmark
    case markerWhitespace
    case markerEndOfLine
    case textCaret
    case overlayFill
    case overlayForeground
    case overlayCue

    public static func < (lhs: EditorColorRenderPlane, rhs: EditorColorRenderPlane) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Required source-over and clipping behavior for editor background planes.
public enum EditorBackgroundCompositingRule: String, Equatable, Hashable, Sendable {
    /// Draw backgrounds source-over in render order. Current-line fill preserves lower pattern ink.
    /// Selection/search fill clips lower pattern, foreground, and cue geometry and therefore
    /// composites over the lower pattern gap, not over pattern ink.
    case sourceOverInRenderOrderWithGapOnlyOverlayUnderlay
}

/// Required replacement and clipping behavior for editor foreground planes.
public enum EditorForegroundCompositingRule: String, Equatable, Hashable, Sendable {
    /// Difference foreground replaces ordinary text and syntax. All content and overlay foreground
    /// geometry clips lower difference-pattern ink before its color is composited.
    case differenceReplacesTextAndSyntaxOverPatternGap
}

/// Required source-over and overlap behavior for editor cue planes.
public enum EditorCueCompositingRule: String, Equatable, Hashable, Sendable {
    /// Clip difference-pattern ink from every cue. Boundary cues contrast on fill- and
    /// underlay-facing edges; single-plane cues contrast on every allowed background. Union
    /// same-plane geometry before compositing its color once. At cross-plane intersections, the
    /// higher render plane clips and replaces lower cues, so cue colors never composite together.
    case sourceOverClippedPatternWithHigherCueReplacement
}

/// Every background stack that a single-plane content cue may cover after pattern ink is clipped.
public enum EditorContentCueUnderlay: String, CaseIterable, Equatable, Hashable, Sendable {
    case canvas
    case differenceOrMovedPatternGap
    case currentLineOverCanvas
    case currentLineOverDifferenceOrMovedPatternGap
}

/// Public renderer contract mirrored by `EditorColorPalette` contrast validation.
public enum EditorColorRenderingContract {
    public static let backToFrontOrder: [EditorColorRenderPlane] = [
        .canvasBackground,
        .gutterBackground,
        .differenceFill,
        .differencePattern,
        .currentLineFill,
        .contentForeground,
        .differenceCue,
        .currentLineCue,
        .movedLineConnector,
        .markerBookmark,
        .markerWhitespace,
        .markerEndOfLine,
        .textCaret,
        .overlayFill,
        .overlayForeground,
        .overlayCue
    ]
    public static let backgroundCompositing: EditorBackgroundCompositingRule =
        .sourceOverInRenderOrderWithGapOnlyOverlayUnderlay
    public static let foregroundCompositing: EditorForegroundCompositingRule =
        .differenceReplacesTextAndSyntaxOverPatternGap
    public static let cueCompositing: EditorCueCompositingRule =
        .sourceOverClippedPatternWithHigherCueReplacement
    public static let contentCueUnderlays: [EditorContentCueUnderlay] = [
        .canvas,
        .differenceOrMovedPatternGap,
        .currentLineOverCanvas,
        .currentLineOverDifferenceOrMovedPatternGap
    ]
    /// Single-plane cues validated against every background they may cover, in render order.
    public static let contentCueRoles: [EditorColorRole] = [
        .movedLineConnector,
        .markerBookmark,
        .markerWhitespace,
        .markerEndOfLine,
        .textCaret
    ]
    /// Drawn after difference and current-line cues, and before bookmarks and all higher planes.
    public static let movedLineConnectorPlane: EditorColorRenderPlane = .movedLineConnector
    /// Drawn after moved-line connectors, and before whitespace markers and all higher planes.
    public static let markerBookmarkPlane: EditorColorRenderPlane = .markerBookmark
}

/// Back-to-front editor background layers and their exclusivity rules.
public enum EditorColorLayer: Int, CaseIterable, Comparable, Equatable, Hashable, Sendable {
    /// Zero or one added, removed, modified, conflict, or moved-line background.
    case differenceOrMoved
    /// Zero or one current-line background over the outer layer.
    case currentLine
    /// Zero or one active selection, inactive selection, ordinary search, or current search.
    case selectionOrSearch

    public static func < (lhs: EditorColorLayer, rhs: EditorColorLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Mutually exclusive states in the top selection/search layer.
///
/// Renderers draw at most one of these states over the optional current-line layer, which in
/// turn sits over exactly one difference/moved state or the editor canvas. The overlay clips lower
/// difference-pattern ink and replaces all lower foreground and cue geometry, including moved-line
/// connectors, bookmarks, whitespace, end-of-line markers, and the caret. Renderers must apply
/// `requiredNonColorCue` over the pattern-gap underlay.
public enum EditorOverlayState: String, CaseIterable, Equatable, Hashable, Sendable {
    case activeSelection
    case inactiveSelection
    case ordinarySearch
    case currentSearch

    /// Geometry that keeps paired states distinct without relying on color perception.
    public var requiredNonColorCue: EditorOverlayNonColorCue {
        switch self {
        case .activeSelection:
            .solidOutline
        case .inactiveSelection:
            .dashedOutline
        case .ordinarySearch:
            .underline
        case .currentSearch:
            .doubleUnderline
        }
    }

    /// Color used for the required geometry on its underlay-facing edge.
    public var requiredNonColorCueColorRole: EditorColorRole {
        .systemFocusRing
    }

    /// Color used for the required geometry on its overlay-fill-facing edge.
    public var requiredNonColorCueFillEdgeColorRole: EditorColorRole {
        switch self {
        case .activeSelection:
            .selectionForeground
        case .inactiveSelection:
            .selectionInactiveForeground
        case .ordinarySearch:
            .markerSearchForeground
        case .currentSearch:
            .markerCurrentSearchForeground
        }
    }
}

/// Renderer-required geometry for selection and search overlays.
public enum EditorOverlayNonColorCue: String, CaseIterable, Equatable, Hashable, Sendable {
    case solidOutline
    case dashedOutline
    case underline
    case doubleUnderline
}

/// Renderer-required geometry that identifies the current line without relying on its fill.
public enum EditorCurrentLineNonColorCue: String, CaseIterable, Equatable, Hashable, Sendable {
    case outline
}

public struct EditorDifferenceDecoration: Encodable, Equatable, Hashable, Sendable {
    public let kind: EditorDifferenceKind
    public let shape: EditorDifferenceShape
    public let pattern: EditorDifferencePattern

    public var cueColorRole: EditorColorRole { Self.roles(for: kind).cue }
    public var patternColorRole: EditorColorRole { Self.roles(for: kind).pattern }
    public var patternPhase: EditorDifferencePatternPhase { .editorCanvas }
    public var foregroundBehavior: EditorDifferenceForegroundBehavior { .replacesTextAndSyntax }
    public var compositingRule: EditorDifferenceCompositingRule {
        .sourceOverFillClippedPatternForegroundCue
    }

    public init(
        kind: EditorDifferenceKind,
        shape: EditorDifferenceShape,
        pattern: EditorDifferencePattern
    ) {
        self.kind = kind
        self.shape = shape
        self.pattern = pattern
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case shape
        case pattern
    }

    fileprivate static func roles(
        for kind: EditorDifferenceKind
    ) -> (background: EditorColorRole, foreground: EditorColorRole, cue: EditorColorRole, pattern: EditorColorRole) {
        switch kind {
        case .added:
            (.differenceAddedBackground, .differenceAddedForeground, .differenceAddedCue, .differenceAddedPattern)
        case .removed:
            (.differenceRemovedBackground, .differenceRemovedForeground, .differenceRemovedCue, .differenceRemovedPattern)
        case .modified:
            (.differenceModifiedBackground, .differenceModifiedForeground, .differenceModifiedCue, .differenceModifiedPattern)
        case .conflict:
            (.differenceConflictBackground, .differenceConflictForeground, .differenceConflictCue, .differenceConflictPattern)
        case .moved:
            (.movedLineBackground, .movedLineForeground, .movedLineCue, .movedLinePattern)
        }
    }

}

public struct EditorContrastStandards: Equatable, Hashable, Sendable {
    public static let `default` = EditorContrastStandards(
        uncheckedNormalText: 4.5,
        enhancedText: 7,
        nonText: 3,
        enhancedNonText: 4.5
    )

    public let normalText: Double
    public let enhancedText: Double
    public let nonText: Double
    public let enhancedNonText: Double

    public init(
        normalText: Double = 4.5,
        enhancedText: Double = 7,
        nonText: Double = 3,
        enhancedNonText: Double = 4.5
    ) throws {
        for value in [normalText, enhancedText, nonText, enhancedNonText] {
            guard value.isFinite, (1...21).contains(value) else {
                throw EditorColorSchemeError.invalidContrastRatio(value)
            }
        }
        guard enhancedText >= normalText, enhancedNonText >= nonText else {
            throw EditorColorSchemeError.invalidContrastStandards
        }
        self.normalText = normalText
        self.enhancedText = enhancedText
        self.nonText = nonText
        self.enhancedNonText = enhancedNonText
    }

    private init(
        uncheckedNormalText normalText: Double,
        enhancedText: Double,
        nonText: Double,
        enhancedNonText: Double
    ) {
        self.normalText = normalText
        self.enhancedText = enhancedText
        self.nonText = nonText
        self.enhancedNonText = enhancedNonText
    }
}

public struct EditorContrastIssue: Equatable, Hashable, Sendable {
    public let variant: EditorColorSchemeVariant
    public let foregroundRole: EditorColorRole
    public let backgroundRole: EditorColorRole
    public let actualRatio: Double
    public let minimumRatio: Double

    public init(
        variant: EditorColorSchemeVariant,
        foregroundRole: EditorColorRole,
        backgroundRole: EditorColorRole,
        actualRatio: Double,
        minimumRatio: Double
    ) {
        self.variant = variant
        self.foregroundRole = foregroundRole
        self.backgroundRole = backgroundRole
        self.actualRatio = actualRatio
        self.minimumRatio = minimumRatio
    }

    public static func == (lhs: EditorContrastIssue, rhs: EditorContrastIssue) -> Bool {
        lhs.variant == rhs.variant
            && lhs.foregroundRole == rhs.foregroundRole
            && lhs.backgroundRole == rhs.backgroundRole
            && lhs.actualRatio.bitPattern == rhs.actualRatio.bitPattern
            && lhs.minimumRatio.bitPattern == rhs.minimumRatio.bitPattern
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(variant)
        hasher.combine(foregroundRole)
        hasher.combine(backgroundRole)
        hasher.combine(actualRatio.bitPattern)
        hasher.combine(minimumRatio.bitPattern)
    }
}

public struct EditorColorPalette: Encodable, Equatable, Sendable {
    public static let maximumDefinitions = 128
    public static let maximumAssignments = 64
    /// Renderers must draw this cue even when the current-line fill differs from the canvas.
    public static let requiredCurrentLineNonColorCue: EditorCurrentLineNonColorCue = .outline
    /// Color used for the required current-line geometry on its underlay-facing edge.
    public static let requiredCurrentLineNonColorCueColorRole: EditorColorRole = .systemSeparator

    public let variant: EditorColorSchemeVariant
    /// Sorted by token so encoding and equality do not depend on caller insertion order.
    public let definitions: [EditorColorDefinition]
    /// Sorted by semantic role so encoding and equality do not depend on caller insertion order.
    public let assignments: [EditorColorAssignment]

    public init(
        variant: EditorColorSchemeVariant,
        definitions: [EditorColorDefinition],
        assignments: [EditorColorAssignment]
    ) throws {
        guard definitions.count <= Self.maximumDefinitions,
            assignments.count <= Self.maximumAssignments
        else {
            throw EditorColorSchemeError.paletteLimitExceeded
        }
        self.variant = variant
        self.definitions = definitions.sorted { $0.token < $1.token }
        self.assignments = assignments.sorted { $0.role.rawValue < $1.role.rawValue }
        try validate(limits: .default)
    }

    fileprivate init(
        uncheckedVariant variant: EditorColorSchemeVariant,
        definitions: [EditorColorDefinition],
        assignments: [EditorColorAssignment]
    ) {
        self.variant = variant
        self.definitions = definitions.sorted { $0.token < $1.token }
        self.assignments = assignments.sorted { $0.role.rawValue < $1.role.rawValue }
    }

    public func token(for role: EditorColorRole) -> EditorColorToken? {
        assignments.first(where: { $0.role == role })?.token
    }

    public func components(for token: EditorColorToken) -> EditorColorComponents? {
        definitions.first(where: { $0.token == token })?.components
    }

    public func color(for role: EditorColorRole) -> EditorColorComponents? {
        guard let token = token(for: role) else { return nil }
        return components(for: token)
    }

    /// Returns every WCAG-like text or non-text contrast failure in stable layer order.
    public func contrastIssues(
        standards: EditorContrastStandards = .default
    ) -> [EditorContrastIssue] {
        guard let canvas = color(for: .textBackground), canvas.alpha == 1 else { return [] }
        let textMinimum = variant.isHighContrast ? standards.enhancedText : standards.normalText
        let nonTextMinimum =
            variant.isHighContrast
            ? standards.enhancedNonText : standards.nonText

        var issues: [EditorContrastIssue] = Self.baseContrastRequirements.compactMap {
            requirement -> EditorContrastIssue? in
            guard let background = renderedColor(for: requirement.background, over: canvas) else {
                return nil
            }
            return contrastIssue(
                foregroundRole: requirement.foreground,
                backgroundRole: requirement.background,
                background: background,
                minimum: requirement.isText ? textMinimum : nonTextMinimum
            )
        }

        let outerBackgrounds = reachableOuterBackgrounds(canvas: canvas)
        for difference in reachableDifferenceBackgrounds(canvas: canvas) {
            if let issue = contrastIssue(
                foregroundRole: difference.roles.pattern,
                backgroundRole: difference.gap.role,
                foreground: difference.pattern.components,
                background: difference.gap.components,
                minimum: nonTextMinimum
            ) {
                issues.append(issue)
            }
            if let issue = contrastIssue(
                foregroundRole: difference.roles.foreground,
                backgroundRole: difference.gap.role,
                background: difference.gap.components,
                minimum: textMinimum
            ) {
                issues.append(issue)
            }
            for background in [difference.underlay, difference.gap] {
                if let issue = contrastIssue(
                    foregroundRole: difference.roles.cue,
                    backgroundRole: background.role,
                    background: background.components,
                    minimum: nonTextMinimum
                ) {
                    issues.append(issue)
                }
            }
        }

        let contentBackgrounds = reachableContentBackgrounds(outerBackgrounds: outerBackgrounds)
        for background in contentBackgrounds where background.role == .textCurrentLineBackground {
            let outerRole = background.predecessorRole ?? .textBackground
            guard Self.foregroundRole(forLayerBackground: outerRole) == nil else { continue }
            for foregroundRole in Self.currentLineTextRoles {
                if let issue = contrastIssue(
                    foregroundRole: foregroundRole,
                    backgroundRole: background.role,
                    background: background.components,
                    minimum: textMinimum
                ) {
                    issues.append(issue)
                }
            }
        }

        for background in contentBackgrounds where background.role == .textCurrentLineBackground {
            if let issue = contrastIssue(
                foregroundRole: Self.requiredCurrentLineNonColorCueColorRole,
                backgroundRole: background.role,
                background: background.components,
                minimum: nonTextMinimum
            ) {
                issues.append(issue)
            }
            if let predecessor = outerBackgrounds.first(where: {
                $0.role == background.predecessorRole
            }),
                let issue = contrastIssue(
                    foregroundRole: Self.requiredCurrentLineNonColorCueColorRole,
                    backgroundRole: predecessor.role,
                    background: predecessor.components,
                    minimum: nonTextMinimum
                )
            {
                issues.append(issue)
            }
        }

        for underlay in EditorColorRenderingContract.contentCueUnderlays {
            for background in contentBackgrounds where background.contentCueUnderlay == underlay {
                for foregroundRole in EditorColorRenderingContract.contentCueRoles {
                    if let issue = contrastIssue(
                        foregroundRole: foregroundRole,
                        backgroundRole: background.role,
                        background: background.components,
                        minimum: nonTextMinimum
                    ) {
                        issues.append(issue)
                    }
                }
            }
        }

        let overlayUnderlays = reachableOverlayUnderlays(canvas: canvas)
        for (state, overlayRole) in Self.overlayLayers {
            guard let overlay = color(for: overlayRole) else { continue }
            let foregroundRole = Self.foregroundRole(for: state)
            for predecessor in overlayUnderlays {
                let background = overlay.composited(over: predecessor.components)
                if let issue = contrastIssue(
                    foregroundRole: foregroundRole,
                    backgroundRole: overlayRole,
                    background: background,
                    minimum: textMinimum
                ) {
                    issues.append(issue)
                }
                if let issue = contrastIssue(
                    foregroundRole: state.requiredNonColorCueFillEdgeColorRole,
                    backgroundRole: overlayRole,
                    background: background,
                    minimum: nonTextMinimum
                ) {
                    issues.append(issue)
                }
            }
            for predecessor in overlayUnderlays {
                if let issue = contrastIssue(
                    foregroundRole: state.requiredNonColorCueColorRole,
                    backgroundRole: predecessor.role,
                    background: predecessor.components,
                    minimum: nonTextMinimum
                ) {
                    issues.append(issue)
                }
            }
        }
        return issues
    }

    public func validateContrast(
        standards: EditorContrastStandards = .default
    ) throws {
        if let issue = contrastIssues(standards: standards).first {
            throw EditorColorSchemeError.insufficientContrast(issue)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case variant
        case definitions
        case assignments
    }

    public func encode(to encoder: Encoder) throws {
        try validate(limits: .default)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(variant, forKey: .variant)
        try container.encode(definitions, forKey: .definitions)
        try container.encode(assignments, forKey: .assignments)
    }

    fileprivate func validate(limits: EditorColorSchemeLimits) throws {
        guard definitions.count <= limits.maximumDefinitionsPerPalette,
            definitions.count <= Self.maximumDefinitions,
            assignments.count <= limits.maximumAssignmentsPerPalette,
            assignments.count <= Self.maximumAssignments
        else {
            throw EditorColorSchemeError.paletteLimitExceeded
        }

        var tokens: Set<EditorColorToken> = []
        for definition in definitions {
            guard tokens.insert(definition.token).inserted else {
                throw EditorColorSchemeError.duplicateColorToken(definition.token.rawValue)
            }
            try EditorColorToken.validate(
                definition.token.rawValue,
                maximumUTF8Bytes: limits.maximumColorTokenUTF8Bytes
            )
        }

        var roles: Set<EditorColorRole> = []
        var usedTokens: Set<EditorColorToken> = []
        for assignment in assignments {
            guard roles.insert(assignment.role).inserted else {
                throw EditorColorSchemeError.duplicateColorRole(assignment.role)
            }
            guard tokens.contains(assignment.token) else {
                throw EditorColorSchemeError.undefinedColorToken(assignment.token.rawValue)
            }
            usedTokens.insert(assignment.token)
        }

        for role in EditorColorRole.allCases where !roles.contains(role) {
            throw EditorColorSchemeError.missingColorRole(role)
        }
        if let unused = tokens.subtracting(usedTokens).sorted().first {
            throw EditorColorSchemeError.unusedColorToken(unused.rawValue)
        }
        guard let canvas = color(for: .textBackground), canvas.alpha == 1 else {
            throw EditorColorSchemeError.editorBackgroundMustBeOpaque(variant)
        }
        try validateContrast()
    }

    private struct ReachableBackground {
        let role: EditorColorRole
        let predecessorRole: EditorColorRole?
        let components: EditorColorComponents
        let contentCueUnderlay: EditorContentCueUnderlay?

        init(
            role: EditorColorRole,
            predecessorRole: EditorColorRole?,
            components: EditorColorComponents,
            contentCueUnderlay: EditorContentCueUnderlay? = nil
        ) {
            self.role = role
            self.predecessorRole = predecessorRole
            self.components = components
            self.contentCueUnderlay = contentCueUnderlay
        }
    }

    private struct DifferenceBackgrounds {
        let roles: (background: EditorColorRole, foreground: EditorColorRole, cue: EditorColorRole, pattern: EditorColorRole)
        let underlay: ReachableBackground
        let fill: ReachableBackground
        let gap: ReachableBackground
        let pattern: ReachableBackground
    }

    private func reachableOuterBackgrounds(
        canvas: EditorColorComponents
    ) -> [ReachableBackground] {
        [
            ReachableBackground(
                role: .textBackground,
                predecessorRole: nil,
                components: canvas,
                contentCueUnderlay: .canvas
            )
        ]
            + differenceBackgrounds(canvas: canvas).map {
                ReachableBackground(
                    role: $0.fill.role,
                    predecessorRole: $0.fill.predecessorRole,
                    components: $0.fill.components,
                    contentCueUnderlay: .differenceOrMovedPatternGap
                )
            }
    }

    private func differenceBackgrounds(
        canvas: EditorColorComponents
    ) -> [DifferenceBackgrounds] {
        var backgrounds: [DifferenceBackgrounds] = []
        for roles in Self.differenceRoles {
            if let fill = renderedColor(for: roles.background, over: canvas),
                let pattern = renderedColor(for: roles.pattern, over: fill)
            {
                backgrounds.append(
                    DifferenceBackgrounds(
                        roles: roles,
                        underlay: ReachableBackground(
                            role: .textBackground,
                            predecessorRole: nil,
                            components: canvas
                        ),
                        fill: ReachableBackground(
                            role: roles.background,
                            predecessorRole: .textBackground,
                            components: fill
                        ),
                        gap: ReachableBackground(
                            role: roles.background,
                            predecessorRole: .textBackground,
                            components: fill
                        ),
                        pattern: ReachableBackground(
                            role: roles.pattern,
                            predecessorRole: roles.background,
                            components: pattern
                        )
                    )
                )
            }
        }
        return backgrounds
    }

    private func reachableDifferenceBackgrounds(
        canvas: EditorColorComponents
    ) -> [DifferenceBackgrounds] {
        let backgrounds = differenceBackgrounds(canvas: canvas)
        guard let currentLine = color(for: .textCurrentLineBackground) else {
            return backgrounds
        }
        return backgrounds
            + backgrounds.map { background in
                DifferenceBackgrounds(
                    roles: background.roles,
                    underlay: ReachableBackground(
                        role: .textCurrentLineBackground,
                        predecessorRole: .textBackground,
                        components: currentLine.composited(over: background.underlay.components)
                    ),
                    fill: ReachableBackground(
                        role: .textCurrentLineBackground,
                        predecessorRole: background.roles.background,
                        components: currentLine.composited(over: background.fill.components)
                    ),
                    gap: ReachableBackground(
                        role: .textCurrentLineBackground,
                        predecessorRole: background.roles.background,
                        components: currentLine.composited(over: background.gap.components)
                    ),
                    pattern: ReachableBackground(
                        role: .textCurrentLineBackground,
                        predecessorRole: background.roles.pattern,
                        components: currentLine.composited(over: background.pattern.components)
                    )
                )
            }
    }

    private func reachableContentBackgrounds(
        outerBackgrounds: [ReachableBackground]
    ) -> [ReachableBackground] {
        guard let currentLine = color(for: .textCurrentLineBackground) else {
            return outerBackgrounds
        }
        return outerBackgrounds
            + outerBackgrounds.map {
                let contentCueUnderlay: EditorContentCueUnderlay?
                switch $0.contentCueUnderlay {
                case .canvas:
                    contentCueUnderlay = .currentLineOverCanvas
                case .differenceOrMovedPatternGap:
                    contentCueUnderlay = .currentLineOverDifferenceOrMovedPatternGap
                default:
                    contentCueUnderlay = nil
                }
                return ReachableBackground(
                    role: .textCurrentLineBackground,
                    predecessorRole: $0.role,
                    components: currentLine.composited(over: $0.components),
                    contentCueUnderlay: contentCueUnderlay
                )
            }
    }

    private func reachableOverlayUnderlays(
        canvas: EditorColorComponents
    ) -> [ReachableBackground] {
        let differenceBackgrounds = differenceBackgrounds(canvas: canvas)
        let outer =
            [
                ReachableBackground(
                    role: .textBackground,
                    predecessorRole: nil,
                    components: canvas
                )
            ]
            + differenceBackgrounds.map(\.gap)
        guard let currentLine = color(for: .textCurrentLineBackground) else { return outer }
        return outer
            + outer.map {
                ReachableBackground(
                    role: .textCurrentLineBackground,
                    predecessorRole: $0.role,
                    components: currentLine.composited(over: $0.components)
                )
            }
    }

    private func renderedColor(
        for role: EditorColorRole,
        over underlay: EditorColorComponents
    ) -> EditorColorComponents? {
        color(for: role)?.composited(over: underlay)
    }

    private func contrastIssue(
        foregroundRole: EditorColorRole,
        backgroundRole: EditorColorRole,
        background: EditorColorComponents,
        minimum: Double
    ) -> EditorContrastIssue? {
        guard let foreground = color(for: foregroundRole) else { return nil }
        let effectiveForeground = foreground.composited(over: background)
        let actual = effectiveForeground.contrastRatio(with: background)
        guard actual < minimum else { return nil }
        return EditorContrastIssue(
            variant: variant,
            foregroundRole: foregroundRole,
            backgroundRole: backgroundRole,
            actualRatio: actual,
            minimumRatio: minimum
        )
    }

    private func contrastIssue(
        foregroundRole: EditorColorRole,
        backgroundRole: EditorColorRole,
        foreground: EditorColorComponents,
        background: EditorColorComponents,
        minimum: Double
    ) -> EditorContrastIssue? {
        let actual = foreground.contrastRatio(with: background)
        guard actual < minimum else { return nil }
        return EditorContrastIssue(
            variant: variant,
            foregroundRole: foregroundRole,
            backgroundRole: backgroundRole,
            actualRatio: actual,
            minimumRatio: minimum
        )
    }

    private struct ContrastRequirement: Sendable {
        let foreground: EditorColorRole
        let background: EditorColorRole
        let isText: Bool
    }

    private static let baseContrastRequirements: [ContrastRequirement] = [
        .init(foreground: .textForeground, background: .textBackground, isText: true),
        .init(foreground: .textSecondary, background: .textBackground, isText: true),
        .init(foreground: .textLineNumber, background: .systemGutterBackground, isText: true),
        .init(foreground: .syntaxKeyword, background: .textBackground, isText: true),
        .init(foreground: .syntaxString, background: .textBackground, isText: true),
        .init(foreground: .syntaxComment, background: .textBackground, isText: true),
        .init(foreground: .syntaxNumber, background: .textBackground, isText: true),
        .init(foreground: .syntaxLiteral, background: .textBackground, isText: true),
        .init(foreground: .syntaxHeading, background: .textBackground, isText: true),
        .init(foreground: .syntaxEmphasis, background: .textBackground, isText: true),
        .init(foreground: .syntaxCode, background: .textBackground, isText: true),
        .init(foreground: .syntaxLink, background: .textBackground, isText: true),
        .init(foreground: .systemSeparator, background: .textBackground, isText: false),
        .init(foreground: .systemFocusRing, background: .textBackground, isText: false),
        .init(foreground: .systemAccent, background: .textBackground, isText: false),
        .init(foreground: .systemWarning, background: .textBackground, isText: false),
        .init(foreground: .systemError, background: .textBackground, isText: false)
    ]

    private static let differenceRoles = EditorDifferenceKind.allCases.map {
        EditorDifferenceDecoration.roles(for: $0)
    }

    private static let overlayLayers: [(EditorOverlayState, EditorColorRole)] = [
        (.activeSelection, .selectionBackground),
        (.inactiveSelection, .selectionInactiveBackground),
        (.ordinarySearch, .markerSearchBackground),
        (.currentSearch, .markerCurrentSearchBackground)
    ]

    private static let currentLineTextRoles: [EditorColorRole] = [
        .textForeground,
        .textSecondary,
        .syntaxKeyword,
        .syntaxString,
        .syntaxComment,
        .syntaxNumber,
        .syntaxLiteral,
        .syntaxHeading,
        .syntaxEmphasis,
        .syntaxCode,
        .syntaxLink
    ]

    private static func foregroundRole(
        for state: EditorOverlayState
    ) -> EditorColorRole {
        switch state {
        case .activeSelection:
            .selectionForeground
        case .inactiveSelection:
            .selectionInactiveForeground
        case .ordinarySearch:
            .markerSearchForeground
        case .currentSearch:
            .markerCurrentSearchForeground
        }
    }

    private static func foregroundRole(
        forLayerBackground role: EditorColorRole
    ) -> EditorColorRole? {
        switch role {
        case .differenceAddedBackground:
            .differenceAddedForeground
        case .differenceRemovedBackground:
            .differenceRemovedForeground
        case .differenceModifiedBackground:
            .differenceModifiedForeground
        case .differenceConflictBackground:
            .differenceConflictForeground
        case .movedLineBackground:
            .movedLineForeground
        case .differenceAddedPattern:
            .differenceAddedForeground
        case .differenceRemovedPattern:
            .differenceRemovedForeground
        case .differenceModifiedPattern:
            .differenceModifiedForeground
        case .differenceConflictPattern:
            .differenceConflictForeground
        case .movedLinePattern:
            .movedLineForeground
        default:
            nil
        }
    }
}

private struct EditorColorSchemeLimits: Equatable, Sendable {
    static let hardMaximumEncodedBytes = 256 * 1024
    static let hardMaximumJSONValues = 4_096
    static let `default` = EditorColorSchemeLimits()

    let maximumEncodedBytes: Int
    let maximumJSONDepth: Int
    let maximumJSONValues: Int
    let maximumIdentifierUTF8Bytes: Int
    let maximumDisplayNameUTF8Bytes: Int
    let maximumColorTokenUTF8Bytes: Int
    let maximumDefinitionsPerPalette: Int
    let maximumAssignmentsPerPalette: Int

    init(
        maximumEncodedBytes: Int = 128 * 1024,
        maximumJSONDepth: Int = 16,
        maximumJSONValues: Int = 3_072,
        maximumIdentifierUTF8Bytes: Int = 128,
        maximumDisplayNameUTF8Bytes: Int = 256,
        maximumColorTokenUTF8Bytes: Int = EditorColorToken.maximumUTF8Bytes,
        maximumDefinitionsPerPalette: Int = EditorColorPalette.maximumDefinitions,
        maximumAssignmentsPerPalette: Int = EditorColorPalette.maximumAssignments
    ) {
        self.maximumEncodedBytes = maximumEncodedBytes
        self.maximumJSONDepth = maximumJSONDepth
        self.maximumJSONValues = maximumJSONValues
        self.maximumIdentifierUTF8Bytes = maximumIdentifierUTF8Bytes
        self.maximumDisplayNameUTF8Bytes = maximumDisplayNameUTF8Bytes
        self.maximumColorTokenUTF8Bytes = maximumColorTokenUTF8Bytes
        self.maximumDefinitionsPerPalette = maximumDefinitionsPerPalette
        self.maximumAssignmentsPerPalette = maximumAssignmentsPerPalette
    }

    fileprivate func validate() throws {
        guard maximumEncodedBytes > 0,
            maximumEncodedBytes <= Self.hardMaximumEncodedBytes,
            maximumJSONDepth > 0,
            maximumJSONDepth <= 32,
            maximumJSONValues > 0,
            maximumJSONValues <= Self.hardMaximumJSONValues,
            maximumIdentifierUTF8Bytes > 0,
            maximumIdentifierUTF8Bytes <= 128,
            maximumDisplayNameUTF8Bytes > 0,
            maximumDisplayNameUTF8Bytes <= 256,
            maximumColorTokenUTF8Bytes > 0,
            maximumColorTokenUTF8Bytes <= EditorColorToken.maximumUTF8Bytes,
            maximumDefinitionsPerPalette > 0,
            maximumDefinitionsPerPalette <= EditorColorPalette.maximumDefinitions,
            maximumAssignmentsPerPalette >= EditorColorRole.allCases.count,
            maximumAssignmentsPerPalette <= EditorColorPalette.maximumAssignments
        else {
            throw EditorColorSchemeError.invalidLimits
        }
    }
}

public enum EditorBuiltInColorScheme: String, CaseIterable, Equatable, Hashable, Sendable {
    case standard
    case monochrome
}

/// Complete, versioned editor palette set with deterministic persistence.
public struct EditorColorScheme: Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public static let standard = makeBuiltIn(.standard)
    public static let monochrome = makeBuiltIn(.monochrome)
    public static let `default` = standard
    public static let builtIns = [standard, monochrome]

    public let schemaVersion: Int
    public let identifier: String
    public let displayName: String
    /// Stored in `EditorColorSchemeVariant.allCases` order.
    public let palettes: [EditorColorPalette]
    /// Stored in `EditorDifferenceKind.allCases` order.
    public let differenceDecorations: [EditorDifferenceDecoration]

    public init(
        identifier: String,
        displayName: String,
        palettes: [EditorColorPalette],
        differenceDecorations: [EditorDifferenceDecoration]
    ) throws {
        guard palettes.count <= EditorColorSchemeVariant.allCases.count,
            differenceDecorations.count <= EditorDifferenceKind.allCases.count
        else {
            throw EditorColorSchemeError.paletteLimitExceeded
        }
        let normalizedDisplayName = Self.normalizedDisplayName(displayName)
        guard
            normalizedDisplayName.utf8.count
                <= EditorColorSchemeLimits.default.maximumDisplayNameUTF8Bytes
        else {
            throw EditorColorSchemeError.displayNameTooLarge(
                maximumUTF8Bytes: EditorColorSchemeLimits.default.maximumDisplayNameUTF8Bytes
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.identifier = identifier
        self.displayName = normalizedDisplayName
        self.palettes = Self.sortedPalettes(palettes)
        self.differenceDecorations = Self.sortedDecorations(differenceDecorations)
        try validate(limits: .default)
    }

    fileprivate init(
        uncheckedIdentifier identifier: String,
        displayName: String,
        palettes: [EditorColorPalette],
        differenceDecorations: [EditorDifferenceDecoration]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.identifier = identifier
        self.displayName = displayName
        self.palettes = Self.sortedPalettes(palettes)
        self.differenceDecorations = Self.sortedDecorations(differenceDecorations)
    }

    public static func builtIn(_ scheme: EditorBuiltInColorScheme) -> EditorColorScheme {
        switch scheme {
        case .standard:
            standard
        case .monochrome:
            monochrome
        }
    }

    public func palette(for variant: EditorColorSchemeVariant) -> EditorColorPalette? {
        palettes.first(where: { $0.variant == variant })
    }

    public func decoration(for kind: EditorDifferenceKind) -> EditorDifferenceDecoration? {
        differenceDecorations.first(where: { $0.kind == kind })
    }

    public func validate() throws {
        try validate(limits: .default)
    }

    fileprivate func validate(limits: EditorColorSchemeLimits) throws {
        try limits.validate()
        guard schemaVersion == Self.currentSchemaVersion else {
            throw EditorColorSchemeError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.validateIdentifier(identifier, maximumUTF8Bytes: limits.maximumIdentifierUTF8Bytes)
        try Self.validateDisplayName(
            displayName,
            maximumUTF8Bytes: limits.maximumDisplayNameUTF8Bytes
        )

        var variants: Set<EditorColorSchemeVariant> = []
        for palette in palettes {
            guard variants.insert(palette.variant).inserted else {
                throw EditorColorSchemeError.duplicateVariant(palette.variant)
            }
            try palette.validate(limits: limits)
        }
        for variant in EditorColorSchemeVariant.allCases where !variants.contains(variant) {
            throw EditorColorSchemeError.missingVariant(variant)
        }
        guard palettes.count == EditorColorSchemeVariant.allCases.count else {
            throw EditorColorSchemeError.paletteLimitExceeded
        }

        var kinds: Set<EditorDifferenceKind> = []
        var shapes: Set<EditorDifferenceShape> = []
        for decoration in differenceDecorations {
            guard kinds.insert(decoration.kind).inserted else {
                throw EditorColorSchemeError.duplicateDifferenceDecoration(decoration.kind)
            }
            guard shapes.insert(decoration.shape).inserted else {
                throw EditorColorSchemeError.ambiguousDifferenceShape(decoration.shape)
            }
        }
        for kind in EditorDifferenceKind.allCases where !kinds.contains(kind) {
            throw EditorColorSchemeError.missingDifferenceDecoration(kind)
        }
        guard differenceDecorations.count == EditorDifferenceKind.allCases.count else {
            throw EditorColorSchemeError.paletteLimitExceeded
        }
    }

    /// Returns schema-v2 canonical JSON. Key order, escaping, number spelling, and collection order
    /// are owned by this type and do not depend on `JSONEncoder` or Foundation JSON behavior.
    public func encodedData() throws -> Data {
        try encodedData(limits: .default)
    }

    fileprivate func encodedData(limits: EditorColorSchemeLimits) throws -> Data {
        try validate(limits: limits)
        var writer = EditorColorSchemeCanonicalJSONWriter()
        writer.append("{\"differenceDecorations\":[")
        for (index, decoration) in differenceDecorations.enumerated() {
            if index > 0 { writer.append(",") }
            writer.append("{\"kind\":")
            writer.append(string: decoration.kind.rawValue)
            writer.append(",\"pattern\":")
            writer.append(string: decoration.pattern.rawValue)
            writer.append(",\"shape\":")
            writer.append(string: decoration.shape.rawValue)
            writer.append("}")
        }
        writer.append("],\"displayName\":")
        writer.append(string: displayName)
        writer.append(",\"identifier\":")
        writer.append(string: identifier)
        writer.append(",\"palettes\":[")
        for (paletteIndex, palette) in palettes.enumerated() {
            if paletteIndex > 0 { writer.append(",") }
            writer.append("{\"assignments\":[")
            for (assignmentIndex, assignment) in palette.assignments.enumerated() {
                if assignmentIndex > 0 { writer.append(",") }
                writer.append("{\"role\":")
                writer.append(string: assignment.role.rawValue)
                writer.append(",\"token\":")
                writer.append(string: assignment.token.rawValue)
                writer.append("}")
            }
            writer.append("],\"definitions\":[")
            for (definitionIndex, definition) in palette.definitions.enumerated() {
                if definitionIndex > 0 { writer.append(",") }
                let components = definition.components
                writer.append("{\"components\":{\"alpha\":")
                writer.append(integer: components.alpha.bitPattern)
                writer.append(",\"blue\":")
                writer.append(integer: components.blue.bitPattern)
                writer.append(",\"green\":")
                writer.append(integer: components.green.bitPattern)
                writer.append(",\"red\":")
                writer.append(integer: components.red.bitPattern)
                writer.append("},\"token\":")
                writer.append(string: definition.token.rawValue)
                writer.append("}")
            }
            writer.append("],\"variant\":")
            writer.append(string: palette.variant.rawValue)
            writer.append("}")
        }
        writer.append("],\"schemaVersion\":2}")
        let data = writer.data
        guard data.count <= limits.maximumEncodedBytes else {
            throw EditorColorSchemeError.encodedDataTooLarge(
                maximumBytes: limits.maximumEncodedBytes
            )
        }
        var parser = EditorColorSchemeCanonicalJSONParser(
            data: data,
            maximumDepth: limits.maximumJSONDepth,
            maximumValues: limits.maximumJSONValues
        )
        _ = try parser.parse()
        return data
    }

    /// Parses canonical schema-v2 JSON only. Whitespace, alternate escaping or numbers, duplicate or
    /// unknown keys, and alternate key or collection order are rejected by the schema parser.
    public static func decode(
        from data: Data
    ) throws -> EditorColorScheme {
        try decode(from: data, limits: .default)
    }

    fileprivate static func decode(
        from data: Data,
        limits: EditorColorSchemeLimits
    ) throws -> EditorColorScheme {
        try limits.validate()
        guard data.count <= limits.maximumEncodedBytes else {
            throw EditorColorSchemeError.encodedDataTooLarge(
                maximumBytes: limits.maximumEncodedBytes
            )
        }
        var parser = EditorColorSchemeCanonicalJSONParser(
            data: data,
            maximumDepth: limits.maximumJSONDepth,
            maximumValues: limits.maximumJSONValues
        )
        let values = try parser.parse().object(
            keys: ["differenceDecorations", "displayName", "identifier", "palettes", "schemaVersion"]
        )
        let schemaVersion = try values[4].integer()
        guard schemaVersion == Self.currentSchemaVersion else {
            throw EditorColorSchemeError.unsupportedSchemaVersion(schemaVersion)
        }
        let decorations = try values[0].array(
            maximumCount: EditorDifferenceKind.allCases.count
        ).map { value -> EditorDifferenceDecoration in
            let fields = try value.object(keys: ["kind", "pattern", "shape"])
            guard let kind = EditorDifferenceKind(rawValue: try fields[0].string()),
                let pattern = EditorDifferencePattern(rawValue: try fields[1].string()),
                let shape = EditorDifferenceShape(rawValue: try fields[2].string())
            else {
                throw malformedEditorColorSchemeCanonicalJSON()
            }
            return EditorDifferenceDecoration(kind: kind, shape: shape, pattern: pattern)
        }
        guard decorations.map(\.kind) == EditorDifferenceKind.allCases else {
            throw malformedEditorColorSchemeCanonicalJSON()
        }
        let palettes = try values[3].array(
            maximumCount: EditorColorSchemeVariant.allCases.count
        ).map { value -> EditorColorPalette in
            let fields = try value.object(keys: ["assignments", "definitions", "variant"])
            let assignments = try fields[0].array(
                maximumCount: limits.maximumAssignmentsPerPalette
            ).map { value -> EditorColorAssignment in
                let fields = try value.object(keys: ["role", "token"])
                guard let role = EditorColorRole(rawValue: try fields[0].string()) else {
                    throw malformedEditorColorSchemeCanonicalJSON()
                }
                return try EditorColorAssignment(
                    role: role,
                    token: EditorColorToken(rawValue: fields[1].string())
                )
            }
            guard
                zip(assignments, assignments.dropFirst()).allSatisfy({
                    $0.role.rawValue < $1.role.rawValue
                })
            else {
                throw malformedEditorColorSchemeCanonicalJSON()
            }
            let definitions = try fields[1].array(
                maximumCount: limits.maximumDefinitionsPerPalette
            ).map { value -> EditorColorDefinition in
                let fields = try value.object(keys: ["components", "token"])
                let componentFields = try fields[0].object(
                    keys: ["alpha", "blue", "green", "red"]
                )
                let alphaBits = try componentFields[0].uint64()
                let blueBits = try componentFields[1].uint64()
                let greenBits = try componentFields[2].uint64()
                let redBits = try componentFields[3].uint64()
                let components = try EditorColorComponents(
                    red: Double(bitPattern: redBits),
                    green: Double(bitPattern: greenBits),
                    blue: Double(bitPattern: blueBits),
                    alpha: Double(bitPattern: alphaBits)
                )
                guard components.red.bitPattern == redBits,
                    components.green.bitPattern == greenBits,
                    components.blue.bitPattern == blueBits,
                    components.alpha.bitPattern == alphaBits
                else {
                    throw malformedEditorColorSchemeCanonicalJSON()
                }
                return try EditorColorDefinition(
                    token: EditorColorToken(rawValue: fields[1].string()),
                    components: components
                )
            }
            guard
                zip(definitions, definitions.dropFirst()).allSatisfy({
                    $0.token < $1.token
                })
            else {
                throw malformedEditorColorSchemeCanonicalJSON()
            }
            guard let variant = EditorColorSchemeVariant(rawValue: try fields[2].string()) else {
                throw malformedEditorColorSchemeCanonicalJSON()
            }
            return try EditorColorPalette(
                variant: variant,
                definitions: definitions,
                assignments: assignments
            )
        }
        guard palettes.map(\.variant) == EditorColorSchemeVariant.allCases else {
            throw malformedEditorColorSchemeCanonicalJSON()
        }
        let displayName = try values[1].string()
        let identifier = try values[2].string()
        try validateIdentifier(identifier, maximumUTF8Bytes: limits.maximumIdentifierUTF8Bytes)
        try validateDisplayName(displayName, maximumUTF8Bytes: limits.maximumDisplayNameUTF8Bytes)
        let scheme = try EditorColorScheme(
            identifier: identifier,
            displayName: displayName,
            palettes: palettes,
            differenceDecorations: decorations
        )
        try scheme.validate(limits: limits)
        return scheme
    }

    /// Returns a validated fallback for missing, malformed, unsupported, or unsafe data.
    public static func restored(
        from data: Data?,
        fallback: EditorColorScheme = .default
    ) throws -> EditorColorScheme {
        let limits = EditorColorSchemeLimits.default
        try limits.validate()
        if let data, let restored = try? decode(from: data, limits: limits) {
            return restored
        }
        _ = try fallback.encodedData(limits: limits)
        return fallback
    }

    private static func sortedPalettes(_ palettes: [EditorColorPalette]) -> [EditorColorPalette] {
        let order = Dictionary(
            uniqueKeysWithValues: EditorColorSchemeVariant.allCases.enumerated().map {
                ($1, $0)
            }
        )
        return palettes.sorted { order[$0.variant, default: 0] < order[$1.variant, default: 0] }
    }

    private static func sortedDecorations(
        _ decorations: [EditorDifferenceDecoration]
    ) -> [EditorDifferenceDecoration] {
        let order = Dictionary(
            uniqueKeysWithValues: EditorDifferenceKind.allCases.enumerated().map { ($1, $0) }
        )
        return decorations.sorted { order[$0.kind, default: 0] < order[$1.kind, default: 0] }
    }

    private static func validateIdentifier(_ value: String, maximumUTF8Bytes: Int) throws {
        do {
            try EditorColorToken.validate(value, maximumUTF8Bytes: maximumUTF8Bytes)
        } catch EditorColorSchemeError.colorTokenTooLarge {
            throw EditorColorSchemeError.identifierTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
        } catch {
            throw EditorColorSchemeError.invalidIdentifier(value)
        }
    }

    private static func validateDisplayName(_ value: String, maximumUTF8Bytes: Int) throws {
        let normalizedValue = normalizedDisplayName(value)
        guard value.utf8.elementsEqual(normalizedValue.utf8) else {
            throw EditorColorSchemeError.invalidDisplayName
        }
        guard normalizedValue.utf8.count <= maximumUTF8Bytes else {
            throw EditorColorSchemeError.displayNameTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
        }
        guard !value.isEmpty,
            value == value.trimmingCharacters(in: .whitespacesAndNewlines),
            value.unicodeScalars.contains(where: isVisibleDisplayNameScalar),
            !value.unicodeScalars.contains(where: {
                CharacterSet.newlines.contains($0)
                    || (CharacterSet.controlCharacters.contains($0)
                        && $0.value != 0x200D && !isEmojiTagScalar($0))
            }),
            value.allSatisfy(isValidDisplayNameGrapheme)
        else {
            throw EditorColorSchemeError.invalidDisplayName
        }
    }

    private static func isVisibleDisplayNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        !scalar.properties.isWhitespace
            && !CharacterSet.controlCharacters.contains(scalar)
            && !scalar.properties.isDefaultIgnorableCodePoint
            && !isZeroInkBlankScalar(scalar)
    }

    private static func isZeroInkBlankScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x115F, 0x1160, 0x2800, 0x3164, 0xFFA0:
            true
        default:
            false
        }
    }

    private static func isValidDisplayNameGrapheme(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        let requiresEmojiGrammar = scalars.contains(where: isEmojiGrammarScalar)
        guard requiresEmojiGrammar else {
            return !scalars.contains(where: { $0.properties.isDefaultIgnorableCodePoint })
        }
        if let last = scalars.last, isEmojiModifier(last),
            scalars.dropLast().allSatisfy({ $0.properties.isWhitespace })
        {
            return true
        }
        return isEmojiFlagSequence(scalars)
            || isEmojiKeycapSequence(scalars)
            || isEmojiTagSequence(scalars)
            || isEmojiCoreSequence(scalars)
            || isEmojiZWJSequence(scalars)
    }

    private static func isEmojiVariationSelector(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0xFE0E || scalar.value == 0xFE0F
    }

    private static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F1E6...0x1F1FF).contains(scalar.value)
    }

    private static func isEmojiModifier(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F3FB...0x1F3FF).contains(scalar.value)
    }

    private static func isEmojiGrammarScalar(_ scalar: Unicode.Scalar) -> Bool {
        isRegionalIndicator(scalar)
            || isEmojiModifier(scalar)
            || isEmojiVariationSelector(scalar)
            || scalar.value == 0x200D
            || scalar.value == 0x20E3
            || isEmojiTagScalar(scalar)
    }

    private static func isEmojiFlagSequence(_ scalars: [Unicode.Scalar]) -> Bool {
        guard scalars.count == 2, scalars.allSatisfy(isRegionalIndicator) else { return false }
        let first = Int(scalars[0].value - 0x1F1E6)
        let second = scalars[1].value - 0x1F1E6
        return emojiFlagSecondLetterMasks[first] & (1 << second) != 0
    }

    private static func isEmojiKeycapSequence(_ scalars: [Unicode.Scalar]) -> Bool {
        guard scalars.count == 3,
            let first = scalars.first,
            first.value == 0x23 || first.value == 0x2A || (0x30...0x39).contains(first.value),
            scalars[1].value == 0xFE0F,
            scalars.last?.value == 0x20E3
        else {
            return false
        }
        return true
    }

    private static func isEmojiTagSequence(_ scalars: [Unicode.Scalar]) -> Bool {
        var index = 0
        return parseEmojiTagSequence(scalars, index: &index) && index == scalars.count
    }

    private static func isEmojiCoreSequence(_ scalars: [Unicode.Scalar]) -> Bool {
        var index = 0
        return parseEmojiCoreSequence(scalars, index: &index) && index == scalars.count
    }

    private static func isEmojiZWJSequence(_ scalars: [Unicode.Scalar]) -> Bool {
        guard !scalars.contains(where: { $0.value == 0xFE0E }) else { return false }
        var index = 0
        var componentCount = 0
        while index < scalars.count {
            guard parseEmojiZWJElement(scalars, index: &index) else { return false }
            componentCount += 1
            if index == scalars.count { break }
            guard scalars[index].value == 0x200D else { return false }
            index += 1
        }
        return componentCount >= 2
    }

    private static func parseEmojiZWJElement(
        _ scalars: [Unicode.Scalar],
        index: inout Int
    ) -> Bool {
        guard index < scalars.count, !isEmojiModifier(scalars[index]) else { return false }
        let start = index
        if parseEmojiTagSequence(scalars, index: &index) { return true }
        index = start
        return parseEmojiCoreSequence(scalars, index: &index)
    }

    private static func parseEmojiTagSequence(
        _ scalars: [Unicode.Scalar],
        index: inout Int
    ) -> Bool {
        let start = index
        guard index < scalars.count, scalars[index].value == 0x1F3F4 else { return false }
        index += 1
        var identifier = ""
        while index < scalars.count, isEmojiTagIdentifierScalar(scalars[index]),
            index - start < 31
        {
            identifier.unicodeScalars.append(Unicode.Scalar(scalars[index].value - 0xE0000)!)
            index += 1
        }
        guard isPinnedEmojiTagIdentifier(identifier), index < scalars.count,
            scalars[index].value == 0xE007F, index - start < 32
        else {
            index = start
            return false
        }
        index += 1
        return true
    }

    private static func parseEmojiCoreSequence(
        _ scalars: [Unicode.Scalar],
        index: inout Int
    ) -> Bool {
        guard index < scalars.count else { return false }
        if index + 1 < scalars.count,
            isEmojiFlagSequence(Array(scalars[index...(index + 1)]))
        {
            index += 2
            return true
        }
        if index + 2 < scalars.count {
            let base = scalars[index]
            if base.value == 0x23 || base.value == 0x2A || (0x30...0x39).contains(base.value),
                scalars[index + 1].value == 0xFE0F,
                scalars[index + 2].value == 0x20E3
            {
                index += 3
                return true
            }
        }

        let base = scalars[index]
        if isEmojiModifier(base) {
            index += 1
            return true
        }
        guard isPinnedEmoji(base), !isRegionalIndicator(base) else {
            return false
        }
        if isKeycapBase(base) {
            guard index + 1 < scalars.count, isEmojiVariationSelector(scalars[index + 1])
            else { return false }
            index += 2
            return true
        }
        index += 1
        if index < scalars.count, isEmojiModifier(scalars[index]) {
            guard isPinnedEmojiModifierBase(base) else { return false }
            index += 1
        } else if index < scalars.count, isEmojiVariationSelector(scalars[index]) {
            guard isPinnedEmojiVariationBase(base) else { return false }
            index += 1
        }
        return true
    }

    private static func isKeycapBase(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x23 || scalar.value == 0x2A || (0x30...0x39).contains(scalar.value)
    }

    private static func isEmojiTagScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0xE0020...0xE007F).contains(scalar.value)
    }

    private static func isEmojiTagIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0xE0030...0xE0039).contains(scalar.value)
            || (0xE0061...0xE007A).contains(scalar.value)
    }

    private static func isPinnedEmojiTagIdentifier(_ identifier: String) -> Bool {
        let bytes = Array(identifier.utf8)
        if bytes.count == 3, bytes.allSatisfy({ (0x30...0x39).contains($0) }) {
            let value =
                UInt16(bytes[0] - 0x30) * 100
                + UInt16(bytes[1] - 0x30) * 10
                + UInt16(bytes[2] - 0x30)
            return pinnedEmojiNumericRegionIdentifiers.contains(value)
        }
        guard let value = packedEmojiSubdivisionIdentifier(bytes) else { return false }
        var lowerBound = 0
        var upperBound = pinnedEmojiSubdivisionIdentifiers.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if pinnedEmojiSubdivisionIdentifiers[middle] < value {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound < pinnedEmojiSubdivisionIdentifiers.count
            && pinnedEmojiSubdivisionIdentifiers[lowerBound] == value
    }

    private static func packedEmojiSubdivisionIdentifier(_ bytes: [UInt8]) -> UInt32? {
        guard (3...5).contains(bytes.count) else { return nil }
        var value: UInt32 = 1
        for byte in bytes {
            let digit: UInt32
            switch byte {
            case 0x30...0x39:
                digit = UInt32(byte - 0x30)
            case 0x61...0x7A:
                digit = UInt32(byte - 0x61 + 10)
            default:
                return nil
            }
            value = value * 36 + digit
        }
        return value
    }

    // Unicode Emoji 16.0 and CLDR 46, pinned for schema-v2 display-name stability.
    private static let emojiFlagSecondLetterMasks: [UInt32] = [
        0x02DF_797C, 0x037F_7BFB, 0x03F7_FDED, 0x0200_5658, 0x001E_00D5, 0x0082_5700,
        0x015F_B9FB, 0x001A_3400, 0x000F_781C, 0x0000_D010, 0x0342_B1D0, 0x013E_0507,
        0x03FF_FCFD, 0x021A_C975, 0x0000_1000, 0x014E_3CF1, 0x0010_0001, 0x0054_4010,
        0x03BE_7FDF, 0x026A_FEED, 0x0304_3041, 0x0010_2155, 0x0004_0020, 0x0000_0400,
        0x0018_0018, 0x0042_1001
    ]

    private static let pinnedEmojiNumericRegionIdentifiers: Set<UInt16> = [
        1, 2, 3, 5, 9, 11, 13, 14, 15, 17, 18, 19, 21, 29, 30, 34, 35, 39, 53, 54,
        57, 61, 142, 143, 145, 150, 151, 154, 155, 202, 419
    ]

    private static let pinnedEmojiSubdivisionIdentifiers: [UInt32] = {
        guard
            let data = Data(
                base64Encoded: pinnedEmojiSubdivisionIdentifierDeltasBase64,
                options: .ignoreUnknownCharacters
            )
        else {
            preconditionFailure("Invalid pinned CLDR subdivision data")
        }
        var identifiers: [UInt32] = []
        identifiers.reserveCapacity(5_653)
        var previous: UInt32 = 0
        var delta: UInt32 = 0
        var shift: UInt32 = 0
        for byte in data {
            delta |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                previous += delta
                identifiers.append(previous)
                delta = 0
                shift = 0
            } else {
                shift += 7
            }
        }
        precondition(identifiers.count == 5_653 && delta == 0 && shift == 0)
        return identifiers
    }()

    private static let pinnedEmojiSubdivisionIdentifierDeltasBase64 = """
        ttkDAQEBAQEBAQIBAQEBAgEBAQEBAQEBAQEmAQEBAQEBAQHRBQEBAQEBAQGGAwEFBAIBAQMB1QcDAgEBjQMCBAEEBIIBEeIOAQEBAQEBAQEDAQEBAQIBAQEC
        AQEBea4DAQEFAgIBAgEDAQIEtQcCCQQFigIBAQEBAQEBAQEBAQEBAQEBAQEBAQGOBQEBAQEBAQEBsgMKAQEHAg8BAQIFAQEBYQYcAQEBAQEBAQEBAQEBswEC
        BYgPAQMFAQjrAQkN2QEBAQEBAQEBAfMQAQcEAQUFAwEBAQEBAQEBKwUEgQEGBiIDjgkBAQEBAQEBAaECAQEBAQEBAQIBQQMFjQYDAgcHARsIdAEBAQEBAQEB
        QM8CCwVaAQUCAwICAQIBgAQBAQEBAQEBhQMBAQEB+gIFgQ0BAQEBAQEBAdgGAQEBAQEBAQG6EakHAQEBAQEBAgIBAQQBAQIBAQHnAQkFBJkCA6wGCAIDAySi
        AQECCAEGqAgCCQmyCQEBAQEBAQEBAQEBAQEBAQIBAQEBAQEBAYfYfgEBAQEBAYMNEGdIpgMhUdELAQEBAQEcAawyAQEBAQEBAQEbAQGBAwM8AwYEGgYkHAgT
        bAEBDAMDEQMQGgIFAl8KAQNfAwcXCwJClwQLBIwBSJIBH/UBDSU28E6hAZAB3Cy0AbQBLBwVAp0BDAWjASjbZQEBAQEBAQEBG+0JAQEBAQEBAQEbAfwTAQEB
        AQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBxRIBAQEBAQEBARsBAQHqCQEBAQEBAQEBGwEBAQEB
        AQEBARsBAQEBAQEBAecJAQEBAfwMCgEFEwiQAZABCQcwFAICEpYBBwWeBQEFIiQk/AEeKk4b6wLWIQiABRCiGdYEBIYFCQEDFSglMUTKAQYMAVkBAwQJQAQB
        AwEUAgsj4AQiBwkQBAIEBDwRHBcqCx5nHgQCIAoBA4ABBhwECgQEgAGlAQEBAQEgAQEBIQEBASEBAQEBtQPsA7gZA3YTB3sUBQscPhKiAQoBBLoP0wECA6MB
        CMQC0QQjrgN8p2oliwMkCgcBAR0bIlDhAeMXCwdoZgEJIzUCAgIFAgUEHAYQDQEgCiF/CgoQDgbiDiMJ2AECBlsFHyQOISeFAU4kxQEBAQEBAd4MAgkXBweP
        ARcHBm9IOBIkgAEBBwsRAi0WD4QBARQBAQEBAQEBARsBAQEBAQEBAQHGAjUeJWKzAQQk3gEJWDRDMZsXBQICAhkqvgIDBhMLGpsBPFqNBElRBf0BQwgikAEC
        pQIBAQEBIAEBIgEBAQEBAR4BAQEBAR4BAQEBIQEBAQEgSAEzJitlHg8FAgsBAwQCAQJGBwU+JSILXEMBBAYKFg2DARAYIPED0yKuFgIBAQEBAQEbAQEBAQEB
        owLqCgQPBQzXAg5eDQQ4BQwVAgYBAgQDDxKBFgEBAQEBrgokJQEjASMBASQBIQEimAMKGBEbKkUZCwZuRyqDAYaRAQMSAsEBAwPCARcOiQEcBAIGGK4tAWIB
        hAOzAZMEAQEBAf0RAQEBAQEBARsB/BMBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAZ9uAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEB
        AQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBkYoBAZUNAh8BBBsBAQQBAhsEAQIBHAEDBAEcAQICAY8VB0sJYBJBJBMMLhoG+mtpClnXAeIB/wQK
        AgQBAw8IDBABAQIHAQEBAwEBAUsxAgYJAyQRbwoGEAIBCAkQAjMfAgc7HAQCCAQWAQk6AgaIAYwDBQccR2kkjQKHAQUBCBbr9AEBAQEBAQEBARsBAQEBAQEB
        AQHkCQEBAQEBAQEBGwEBAQHZUAEBAQEBAQEBGwEBAQEBAQEBARwBAQEBAQEBAQEBGQEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsB
        AQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBWCiGAQrOAQsWSwdASWxW/NQBAQEBAQEe3wwI4wFAPApKswEiAQ8MgxkFAh0ECiVIuQILKJIBJBMSPwKuIucCxAEE
        D0G0DwEFKBcHAwk0DgMTFHwBAgEJAQQSBAoYAQgBMTdsIAq0Ac8XJAUkG4ACH5EDegIBAQEBHgEBAQEBAR4BAQEhAQEBIQEBASEBAQEBAQEBARwBAQEFHAEB
        IgEBAQEgAQEBIbgRAQEBAQEBAQEbAQEBAQEBAQEBGwEBvQIkGwRKSiQpCxTIAQ0VFw8gDAIDAx7KAdAXCwEGEpABqAJUZooPOBQhEY4CeAekARDA9wE8BAED
        AkYhG0YMYwtfCYYBa3rhHgEBAQEBAQEBGwEBAQEBAQEBARsB2hY7jAH/AQEEBip/AagFAgIGCgUdFhAWCxcyBg0DEUAbCAk7JgQKNA5dAgIDAwEEAQYMDToE
        CIQBBKq5ASIBAw+vAV4BBwIJAw4BBwkBAQEQJAsJERIBNAECAQsDAT0cAQUFAQEEAQEB0gHuAwkBCBn1AQYODwQDAgYZBgFSYSUWbwQPAb1CVNwCgQ8CAgEj
        GQEMFAQEAl8JKgI+AxoLGQMoBAICChYcDhQXOSUgBwQBHAUENqQYBBMBBUIICOwBCAk3FBAIZEsRfIYBAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEb
        AQH7EwICIQICIAMhAwIfAwIfAwIBHgZQBQIBAQEBAgIPBgIDAgEDAQEGCwEDAwEDAgEDAQEGPBkCAgIEBRcKA0MGRxUCBAYFAREBAgQFAQQBEQ4GFgsCEQIB
        AQICBQEDAgEBBC8CAgICBAEBFgMFBgECAQIBDwQJAQECAQMSIQEBAgQJAQEC1pwCAQEBAQEBAQEbAQEBAfMWAwQDBguNAhMkSAMK4gMBAQEBAQEBARsBAQEB
        AQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEB+vsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAdQXDdwFAQEB
        AQEBAQEBGwEBAQEBlDwBAQEBAQEBARsBAQEC+BMBAQEBAQEBARsDAQGcFCkBAQEbASQBAQEBAQEBARuVNK0BSEg4SJ4YAQQEHgQeAgIEHgQiBBwBASIEBLBw
        GwEguwFlKQNxF3AKXws1BAQFBcwDCBIHAZgCC4UBywMBAQIBAQEcAQG7PAEBAQEBAQEBGwGgFAEBIgEBIgEBIgEBAQEgAQEiASMBIwEjAcZHBiSFAQUEBbMB
        HAgKFI4BAiSfDAEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbpQHoAglFaF8kBDMc2QQLIR4QR7cB
        FLMBCYcBKcQiFEVuWQYCDBVEBwEHHwWlARAUawMPWstvAQEBAQEBAQEbAQEBAQEBuxcDbBZwRCQCBAgGX2gLAQJsmAQXAw4BEgsBBQEBAR4DAxMhCxkLIRxw
        TB4PXwQfBQUBBQIPBC3CAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAZQ8AQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEB
        GwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBjwjtCQEBAQEBAR4BAQEBAQEBpTIBAQEBAQEBARsBAQEBAfgTAQEBAQEBAQEbAQEBAQEBAQEB
        GwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAagLKQYVEmMo1wFeCwkCDzEDE3ubAQEBAQEBAgEeAQEDHQMBAQEBAQHt
        AooDDKgBEkEF0gQLIwcCFQr/AQEaAhwEAQ0CAwwDBAIIAjtVECvfAZ0KAQEBAQEBAQEbAQEBAQEB0HxZW2wEAw0CfQQGBQED0zgCBwMXBAoKHRchAgcDGTBG
        IB8BCQEFAw5ICCIHBQYXRSoWwgEWqQ0FIBYIBkxHY0QjCgUBI4YBJbUZSB9CBhcNqwFBBjKSAUSlAQO0FAEBAQEBAQEBGwEBAgEBAQEBGwEBASEEBB4EHgTu
        CwdIZWwkDioQBCA/AQEBAQEBSyQEowwBAQEBAQEBARsBAQEB3rwCCQkCNMQCFMsBAgmSAVgUmukB6gPkAVUSl0ABAQECAQEBARsBAQEBAWcBtSC1AVkcKaYB
        biH0AQICAhwCAgICHAICAgIcAoID+QEWAhEQGT4YBwJqAZIBAmz8RgEBAQEBAQEBGwEBAQEBAQEBHCSIMgEBAQEBAQPxfIMCU6IBK1M2bJ3zAwULFQUGBAIC
        BBQCBwECEAhsAgYWDhgGB4UBBQYlJBhmCAMJGgEFQgIFyB8BAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBAZUFjgOhDggZFBQQEMEBPAEIAQMDOwrKAQQg
        GA/cCwEBAQHcjQEBAQEBAQEBARsBAQKmDQMMkQFGiAEBqgFLbIMBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQGhDQIJBQRZBw93BwYFWw0DBYwBGoEFASWI
        EQEBAQH/DIUCpQOqGQnBAmxVewLeAe4GtQMBAQEBAQEBAeYNCUiqAQMBBx8xyQEHGwXXAZwDGAMEB5wBBChDBHkkoAEDBAckbL8YHwXXAixMBVsIiAGpBAlY
        AhKkAUxSgAJBdgEBAQEBkxdBBw24AipebAwCBANABcIZCQd4CAMBG2nIARADNRDnBp0BEN8B9YgBBggXSwpLHmEmDAMTAgIKGSSNAQgcCGnVHwEBAQEBAQEB
        ARsBAQEBAQEBHQEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEcAQEBAQEBAR0BAQEBAQEBHQEBAQEBAR4BAQEBAQHIFVmiAekBOI8PAhcOJB4t6wEIIQ45
        gALXCwEBASEBASIBAQEhAQEiAQEiJAEBIgEB7gcBAQEBrB4BAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEB
        AQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAeBOAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsByG4CAh0CBB0CAx4CAx8DAwIdAgMDHAICAx0DA5x5HgUD
        HAMCAyCTPQEGAQcvDgUTAk8ZFBgcAwgCTQYMJAMBBAUBAQMBEwEBAwIDCQMTAwcTET8eAS4KGQcRCAsRCA0DwTY3CwMqNw/GASQOXlUBBw8JBRYT3gQrfJgB
        jgEQVhE3CAwaBJABlXoBAQEBAatvAQEBAQEBAh4BBBwBAQEBAQEBAQEbAQEBAQEBAQIbAQIBAQEBAhsBAQEBAQEBAQEcAgMBAQEbAQEBzgEekAECgwO9lgKD
        BVfrfQsIoQEoBLwCbDg5DZvFBAIJGEgHjAEGCxEjSCQRBZ4BJAMEBgcQ5r8CNCEEsAEkFwkLsAK1cAEBAQEBAQEBG6ZoxAG0AQICBAUFAwH1x8ojAWYMZdUS
        7Bj9AasFDqEJBo0XgwYMAnaFAdsBsQb4A68QnwK1A8wOBI8CSNQbBYkK/g65D6Aepd8XBjjtB1uFAwGAAr4yCMomugE0ywSEBI0GikmyMMOOD5OIAaEcsxuw
        FoTIDKIBAgoGAq8D9gQKBpcBgwHmBwrQBccE9xmqBIYEB9YCrAPGDdwBlw8C1AWxBAuUAYEJkwvnCvsCug8WAgsIzQPpAb8OAgQDAQYCHocCQT8PmwK/BPwD
        ywbqHU7pAb4DqgSUAfgIAwHWuB2/Ap2sAfWFCtXFASjdAgJ5oALuAyraAYMBETGnlAEBAQzQAakBBP4KySTHAziQCv0JqhCaAZYCDEgDAQOjB+gCkwqQBgIK
        9APVCwLPBPMDyBuVAZEBFyoFlgbJBf4sDa4M1AEHk5Q3hKkBuo8s/PECh9YWN31T3AgNiwYFAgKOAWj/AdQBsygVgwruIpAKnQH+CPcE+xSFCuoG6wcCwwXB
        CJ8QEo8CzPQcAQEBAQEBAQEBAQEBAQEVAQEBAQEBAQEBGwEBxwkBAQEBAQEBAQEBAakKAQEBAQEBHgEBAQEBAeYJAQEiAQEBAQEB5gkBAQEhAQEBASABAQHF
        CQEBAQEgAQEBAQEBHgEBAQEgAQEBAQEBngkBAQEBIAEBAcUJAQEBAQG215ABJQFrJyEHyQcjbQIeBEUlASECA8kHAiYeK0OlCSABASMBBG4cBu0HIgMoayRH
        kwgDHgIoQQIiAgVJI8wHHgIFISADswEiAQPJBwZDJEmLAQcCxAcCBCQCI9XoBfIBBtsIxiuqLbMWlSD0GgsgvAPaIsXYdqQx0inxLdrXC/8qHNoI3RQBAQEC
        5A/iBrIDsQn2AeMjrgSxBZAKpyLABYgK+QPRBsgJdb/hNwEBsQEX5wEKBQGAAQmyBRUwGgErCh8WEkNDGBgTHgMDCx0kPwEVH0a7BAwRJZcBCBMSWw4UBwcT
        AwpICFwTHZcB6wMxYQQEQAvmAQEyBWgGVw66BAsCWw2ZAgU7AaABAh4F/ASWAYQBdCXlBh7hAgzKAb0B9gMBCT1DlgFkJjFBUAMCngkEhQFjvA8LaiqOA2T6
        AxkFITIUFIcBCJABEpoBGFq6BGAVDjdjb2xyBUgXkAG9AxdKIggbJk1lAxoouQEYBwQIBWADQwKzBii3AdMB6wTZAS9fBgWiAboPBQwSBVhY6QHYAcMEAjES
        YwkTJwgEahoBBEEsAQZyMQMCAQYFAQVUAwf6A74BQ+wBBGy2AeUG/wi+CB1SRx5GQioCBQM2BAUiB2YIBBkLihOqB/y8+wEGB/UBF8UGzwEOZAWeEBTDArwL
        4QLyBQg9Aw6EB+0DcwcEmQWWAc8DDl4NAg8EoAmjD8cCtQGWBo0O0QGWAagHkyYUE3IIvgcMQggaDQxNbAEIAwNdJQWKAQ0jBzahBPcBUOoSBeYC3aXfAQcR
        DIMCKeQEiVvRBboBkQ24HsAfb6YgjyC2BO0B46hYAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsB
        AQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQHDBwEBAQEBAQEBARsBAQH4fY48zgH4AvIS1jmOAaYnpAKKhSmxApUB6wGgBAUB2QIJca0F
        7gEEC+0MmQobBIMFmwGEAaECnQsBxAQF7APbB5MCrAfwA8kGBV4JAYYIEZAKYCIHiQGQAQpCDYcGiQTUCwMGEMgYlgH+CAaKAQ5+BAUBRPIDtAMDBgMCBooB
        igEMoQENyzS0BMD9EQHaAXCRI6oD9S4KsAztA/wDnQIJ7wcCjgGSAZ8LCoEp7xzwAp8UAqqDBgEBAQEBAQEBiAoBAQEBAQEBARsB7AkCAQMBHAEBAeoJAQEB
        AQEBAQEb7QkBAQEBAQEBAYgKAQEBAQEBAQGICgEBAQEBiwoBAQEBAQEBARsBAQEBAQEBrZAD2eQEAgIcAgMBAhwCAgICHAIBAQICHALNng2WqAuc3gT5CAXC
        CfcBCLwBMQuyCLwDwR1e4waIEswfe+cBnwb4ApcHzQ+QCsIItwhuaowGC4ADtRLhIsAE1tkE3+M9AQGR5ie9CJYGpgK/KMcKkjCABvoIIoUKyyjrBN4CpR2R
        AbgC4ryPASZaOPgByQ0C1wXAMhPzBKUPzg4BoAKEAVn2BpkDuhqiAqkD3xiGCtoF/AS+pgQCrRDNAbACbKgT9gi2F7IYgwQBR+wF3wGBAl7ULfsB5ibaAZcC
        9okBsAEFiQEaWjXFAbwEBYsBjgHUAbMBByEBuwQGAQIDAQJ88wKaBgQDmALVA6AE5hmQEMwBBQXqAaMPiwoHBZYBtQS2BAMMXA9oBaICfg/NBTwP5wNMEccO
        AZUDwgwE8QbLAZ0GRdABahBp0QEDBMAEBaIjtRkFnwPfAeO2Hf4PoyS9A4sVAc4Dlwz0F7sB/yD7BZAB9AunB74CzIYJAiCQAdwItAGCCQIEHgICAQH0CkiC
        pgaD0MEBJaoBLZAG4QOUBxC+P4YBuA5gMD8KFwwpb2ps6gHNBJIB5weEBATTAcwFTFDNA8wHpgEHwgbMAn8mmBPWAroDAgWtA2KMAUykBPgD1wEdfMAGygiu
        AQZ3tBoElAHsCN7GQQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEB
        ARsBAQEBAQEBAQEbAQEBAQEBAQEBwwcBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQIBAQEbAQEBAQEBAQEBGwEBAQEBAQEB
        ARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQEBAcMHAQEBAQEBAQEBGwEBAffDhgGwEcMDjgiNDKxQ3Rr3Am06ww/+ChpTILoL5gGLHpOtBNZNOgY9BqIC
        sEuErgHsBAj4MAkvzAeoEm8JIYcKjAr9B54Gkg+IAakm0wMDPAyTAYMBCuExoqM2AQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAcMJAQEBAQEBAQEbAQEBAQEB
        AQEBGwEBAQEBAQEBARsBAQEBAQEBngkBAQEBAQEBARsBAQEBAQEBAQEbAQEBAQEBAQEBGwEBAQEBAQGeCQEBAQEBAQEBGwEBAQEBAQEBARsBAQEBAQEBAQEb
        AQEBAQGw6Y8BrR6wHogBgAn1A4i24AI=
        """

    private static func isPinnedEmoji(_ scalar: Unicode.Scalar) -> Bool {
        pinnedEmojiRanges.contains(where: { $0.contains(scalar.value) })
    }

    private static func isPinnedEmojiModifierBase(_ scalar: Unicode.Scalar) -> Bool {
        pinnedEmojiModifierBaseRanges.contains(where: { $0.contains(scalar.value) })
    }

    private static func isPinnedEmojiVariationBase(_ scalar: Unicode.Scalar) -> Bool {
        pinnedEmojiVariationBaseRanges.contains(where: { $0.contains(scalar.value) })
    }

    private static let pinnedEmojiRanges: [ClosedRange<UInt32>] = [
        0x23...0x23, 0x2A...0x2A, 0x30...0x39, 0xA9...0xA9,
        0xAE...0xAE, 0x203C...0x203C, 0x2049...0x2049, 0x2122...0x2122,
        0x2139...0x2139, 0x2194...0x2199, 0x21A9...0x21AA, 0x231A...0x231B,
        0x2328...0x2328, 0x23CF...0x23CF, 0x23E9...0x23F3, 0x23F8...0x23FA,
        0x24C2...0x24C2, 0x25AA...0x25AB, 0x25B6...0x25B6, 0x25C0...0x25C0,
        0x25FB...0x25FE, 0x2600...0x2604, 0x260E...0x260E, 0x2611...0x2611,
        0x2614...0x2615, 0x2618...0x2618, 0x261D...0x261D, 0x2620...0x2620,
        0x2622...0x2623, 0x2626...0x2626, 0x262A...0x262A, 0x262E...0x262F,
        0x2638...0x263A, 0x2640...0x2640, 0x2642...0x2642, 0x2648...0x2653,
        0x265F...0x2660, 0x2663...0x2663, 0x2665...0x2666, 0x2668...0x2668,
        0x267B...0x267B, 0x267E...0x267F, 0x2692...0x2697, 0x2699...0x2699,
        0x269B...0x269C, 0x26A0...0x26A1, 0x26A7...0x26A7, 0x26AA...0x26AB,
        0x26B0...0x26B1, 0x26BD...0x26BE, 0x26C4...0x26C5, 0x26C8...0x26C8,
        0x26CE...0x26CF, 0x26D1...0x26D1, 0x26D3...0x26D4, 0x26E9...0x26EA,
        0x26F0...0x26F5, 0x26F7...0x26FA, 0x26FD...0x26FD, 0x2702...0x2702,
        0x2705...0x2705, 0x2708...0x270D, 0x270F...0x270F, 0x2712...0x2712,
        0x2714...0x2714, 0x2716...0x2716, 0x271D...0x271D, 0x2721...0x2721,
        0x2728...0x2728, 0x2733...0x2734, 0x2744...0x2744, 0x2747...0x2747,
        0x274C...0x274C, 0x274E...0x274E, 0x2753...0x2755, 0x2757...0x2757,
        0x2763...0x2764, 0x2795...0x2797, 0x27A1...0x27A1, 0x27B0...0x27B0,
        0x27BF...0x27BF, 0x2934...0x2935, 0x2B05...0x2B07, 0x2B1B...0x2B1C,
        0x2B50...0x2B50, 0x2B55...0x2B55, 0x3030...0x3030, 0x303D...0x303D,
        0x3297...0x3297, 0x3299...0x3299, 0x1F004...0x1F004, 0x1F0CF...0x1F0CF,
        0x1F170...0x1F171, 0x1F17E...0x1F17F, 0x1F18E...0x1F18E, 0x1F191...0x1F19A,
        0x1F1E6...0x1F1FF, 0x1F201...0x1F202, 0x1F21A...0x1F21A, 0x1F22F...0x1F22F,
        0x1F232...0x1F23A, 0x1F250...0x1F251, 0x1F300...0x1F321, 0x1F324...0x1F393,
        0x1F396...0x1F397, 0x1F399...0x1F39B, 0x1F39E...0x1F3F0, 0x1F3F3...0x1F3F5,
        0x1F3F7...0x1F4FD, 0x1F4FF...0x1F53D, 0x1F549...0x1F54E, 0x1F550...0x1F567,
        0x1F56F...0x1F570, 0x1F573...0x1F57A, 0x1F587...0x1F587, 0x1F58A...0x1F58D,
        0x1F590...0x1F590, 0x1F595...0x1F596, 0x1F5A4...0x1F5A5, 0x1F5A8...0x1F5A8,
        0x1F5B1...0x1F5B2, 0x1F5BC...0x1F5BC, 0x1F5C2...0x1F5C4, 0x1F5D1...0x1F5D3,
        0x1F5DC...0x1F5DE, 0x1F5E1...0x1F5E1, 0x1F5E3...0x1F5E3, 0x1F5E8...0x1F5E8,
        0x1F5EF...0x1F5EF, 0x1F5F3...0x1F5F3, 0x1F5FA...0x1F64F, 0x1F680...0x1F6C5,
        0x1F6CB...0x1F6D2, 0x1F6D5...0x1F6D7, 0x1F6DC...0x1F6E5, 0x1F6E9...0x1F6E9,
        0x1F6EB...0x1F6EC, 0x1F6F0...0x1F6F0, 0x1F6F3...0x1F6FC, 0x1F7E0...0x1F7EB,
        0x1F7F0...0x1F7F0, 0x1F90C...0x1F93A, 0x1F93C...0x1F945, 0x1F947...0x1F9FF,
        0x1FA70...0x1FA7C, 0x1FA80...0x1FA89, 0x1FA8F...0x1FAC6, 0x1FACE...0x1FADC,
        0x1FADF...0x1FAE9, 0x1FAF0...0x1FAF8
    ]

    private static let pinnedEmojiModifierBaseRanges: [ClosedRange<UInt32>] = [
        0x261D...0x261D, 0x26F9...0x26F9, 0x270A...0x270D, 0x1F385...0x1F385,
        0x1F3C2...0x1F3C4, 0x1F3C7...0x1F3C7, 0x1F3CA...0x1F3CC, 0x1F442...0x1F443,
        0x1F446...0x1F450, 0x1F466...0x1F478, 0x1F47C...0x1F47C, 0x1F481...0x1F483,
        0x1F485...0x1F487, 0x1F48F...0x1F48F, 0x1F491...0x1F491, 0x1F4AA...0x1F4AA,
        0x1F574...0x1F575, 0x1F57A...0x1F57A, 0x1F590...0x1F590, 0x1F595...0x1F596,
        0x1F645...0x1F647, 0x1F64B...0x1F64F, 0x1F6A3...0x1F6A3, 0x1F6B4...0x1F6B6,
        0x1F6C0...0x1F6C0, 0x1F6CC...0x1F6CC, 0x1F90C...0x1F90C, 0x1F90F...0x1F90F,
        0x1F918...0x1F91F, 0x1F926...0x1F926, 0x1F930...0x1F939, 0x1F93C...0x1F93E,
        0x1F977...0x1F977, 0x1F9B5...0x1F9B6, 0x1F9B8...0x1F9B9, 0x1F9BB...0x1F9BB,
        0x1F9CD...0x1F9CF, 0x1F9D1...0x1F9DD, 0x1FAC3...0x1FAC5, 0x1FAF0...0x1FAF8
    ]

    private static let pinnedEmojiVariationBaseRanges: [ClosedRange<UInt32>] = [
        0x23...0x23, 0x2A...0x2A, 0x30...0x39, 0xA9...0xA9,
        0xAE...0xAE, 0x203C...0x203C, 0x2049...0x2049, 0x2122...0x2122,
        0x2139...0x2139, 0x2194...0x2199, 0x21A9...0x21AA, 0x231A...0x231B,
        0x2328...0x2328, 0x23CF...0x23CF, 0x23E9...0x23F3, 0x23F8...0x23FA,
        0x24C2...0x24C2, 0x25AA...0x25AB, 0x25B6...0x25B6, 0x25C0...0x25C0,
        0x25FB...0x25FE, 0x2600...0x2604, 0x260E...0x260E, 0x2611...0x2611,
        0x2614...0x2615, 0x2618...0x2618, 0x261D...0x261D, 0x2620...0x2620,
        0x2622...0x2623, 0x2626...0x2626, 0x262A...0x262A, 0x262E...0x262F,
        0x2638...0x263A, 0x2640...0x2640, 0x2642...0x2642, 0x2648...0x2653,
        0x265F...0x2660, 0x2663...0x2663, 0x2665...0x2666, 0x2668...0x2668,
        0x267B...0x267B, 0x267E...0x267F, 0x2692...0x2697, 0x2699...0x2699,
        0x269B...0x269C, 0x26A0...0x26A1, 0x26A7...0x26A7, 0x26AA...0x26AB,
        0x26B0...0x26B1, 0x26BD...0x26BE, 0x26C4...0x26C5, 0x26C8...0x26C8,
        0x26CE...0x26CF, 0x26D1...0x26D1, 0x26D3...0x26D4, 0x26E9...0x26EA,
        0x26F0...0x26F5, 0x26F7...0x26FA, 0x26FD...0x26FD, 0x2702...0x2702,
        0x2705...0x2705, 0x2708...0x270D, 0x270F...0x270F, 0x2712...0x2712,
        0x2714...0x2714, 0x2716...0x2716, 0x271D...0x271D, 0x2721...0x2721,
        0x2728...0x2728, 0x2733...0x2734, 0x2744...0x2744, 0x2747...0x2747,
        0x274C...0x274C, 0x274E...0x274E, 0x2753...0x2755, 0x2757...0x2757,
        0x2763...0x2764, 0x2795...0x2797, 0x27A1...0x27A1, 0x27B0...0x27B0,
        0x27BF...0x27BF, 0x2934...0x2935, 0x2B05...0x2B07, 0x2B1B...0x2B1C,
        0x2B50...0x2B50, 0x2B55...0x2B55, 0x3030...0x3030, 0x303D...0x303D,
        0x3297...0x3297, 0x3299...0x3299, 0x1F004...0x1F004, 0x1F170...0x1F171,
        0x1F17E...0x1F17F, 0x1F202...0x1F202, 0x1F21A...0x1F21A, 0x1F22F...0x1F22F,
        0x1F237...0x1F237, 0x1F30D...0x1F30F, 0x1F315...0x1F315, 0x1F31C...0x1F31C,
        0x1F321...0x1F321, 0x1F324...0x1F32C, 0x1F336...0x1F336, 0x1F378...0x1F378,
        0x1F37D...0x1F37D, 0x1F393...0x1F393, 0x1F396...0x1F397, 0x1F399...0x1F39B,
        0x1F39E...0x1F39F, 0x1F3A7...0x1F3A7, 0x1F3AC...0x1F3AE, 0x1F3C2...0x1F3C2,
        0x1F3C4...0x1F3C4, 0x1F3C6...0x1F3C6, 0x1F3CA...0x1F3CE, 0x1F3D4...0x1F3E0,
        0x1F3ED...0x1F3ED, 0x1F3F3...0x1F3F3, 0x1F3F5...0x1F3F5, 0x1F3F7...0x1F3F7,
        0x1F408...0x1F408, 0x1F415...0x1F415, 0x1F41F...0x1F41F, 0x1F426...0x1F426,
        0x1F43F...0x1F43F, 0x1F441...0x1F442, 0x1F446...0x1F449, 0x1F44D...0x1F44E,
        0x1F453...0x1F453, 0x1F46A...0x1F46A, 0x1F47D...0x1F47D, 0x1F4A3...0x1F4A3,
        0x1F4B0...0x1F4B0, 0x1F4B3...0x1F4B3, 0x1F4BB...0x1F4BB, 0x1F4BF...0x1F4BF,
        0x1F4CB...0x1F4CB, 0x1F4DA...0x1F4DA, 0x1F4DF...0x1F4DF, 0x1F4E4...0x1F4E6,
        0x1F4EA...0x1F4ED, 0x1F4F7...0x1F4F7, 0x1F4F9...0x1F4FB, 0x1F4FD...0x1F4FD,
        0x1F508...0x1F508, 0x1F50D...0x1F50D, 0x1F512...0x1F513, 0x1F549...0x1F54A,
        0x1F550...0x1F567, 0x1F56F...0x1F570, 0x1F573...0x1F579, 0x1F587...0x1F587,
        0x1F58A...0x1F58D, 0x1F590...0x1F590, 0x1F5A5...0x1F5A5, 0x1F5A8...0x1F5A8,
        0x1F5B1...0x1F5B2, 0x1F5BC...0x1F5BC, 0x1F5C2...0x1F5C4, 0x1F5D1...0x1F5D3,
        0x1F5DC...0x1F5DE, 0x1F5E1...0x1F5E1, 0x1F5E3...0x1F5E3, 0x1F5E8...0x1F5E8,
        0x1F5EF...0x1F5EF, 0x1F5F3...0x1F5F3, 0x1F5FA...0x1F5FA, 0x1F610...0x1F610,
        0x1F687...0x1F687, 0x1F68D...0x1F68D, 0x1F691...0x1F691, 0x1F694...0x1F694,
        0x1F698...0x1F698, 0x1F6AD...0x1F6AD, 0x1F6B2...0x1F6B2, 0x1F6B9...0x1F6BA,
        0x1F6BC...0x1F6BC, 0x1F6CB...0x1F6CB, 0x1F6CD...0x1F6CF, 0x1F6E0...0x1F6E5,
        0x1F6E9...0x1F6E9, 0x1F6F0...0x1F6F0, 0x1F6F3...0x1F6F3
    ]

    private static func normalizedDisplayName(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
    }
}

public enum EditorColorSchemeError: Error, Equatable, LocalizedError, Sendable {
    case invalidColorComponent(String, Double)
    case invalidHexColor(String)
    case invalidColorToken(String)
    case colorTokenTooLarge(maximumUTF8Bytes: Int)
    case invalidIdentifier(String)
    case identifierTooLarge(maximumUTF8Bytes: Int)
    case invalidDisplayName
    case displayNameTooLarge(maximumUTF8Bytes: Int)
    case duplicateColorToken(String)
    case undefinedColorToken(String)
    case unusedColorToken(String)
    case duplicateColorRole(EditorColorRole)
    case missingColorRole(EditorColorRole)
    case duplicateVariant(EditorColorSchemeVariant)
    case missingVariant(EditorColorSchemeVariant)
    case editorBackgroundMustBeOpaque(EditorColorSchemeVariant)
    case layerBackgroundMustBeOpaque(EditorColorSchemeVariant, EditorColorRole)
    case invalidContrastRatio(Double)
    case invalidContrastStandards
    case insufficientContrast(EditorContrastIssue)
    case indistinguishableColorState(
        EditorColorSchemeVariant,
        EditorColorRole,
        EditorColorRole
    )
    case duplicateDifferenceDecoration(EditorDifferenceKind)
    case missingDifferenceDecoration(EditorDifferenceKind)
    case ambiguousDifferenceShape(EditorDifferenceShape)
    case paletteLimitExceeded
    case invalidLimits
    case encodedDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)

    public static func == (lhs: EditorColorSchemeError, rhs: EditorColorSchemeError) -> Bool {
        switch (lhs, rhs) {
        case (
            .invalidColorComponent(let lhsName, let lhsValue),
            .invalidColorComponent(let rhsName, let rhsValue)
        ):
            lhsName == rhsName && lhsValue.bitPattern == rhsValue.bitPattern
        case (.invalidHexColor(let lhsValue), .invalidHexColor(let rhsValue)),
            (.invalidColorToken(let lhsValue), .invalidColorToken(let rhsValue)),
            (.invalidIdentifier(let lhsValue), .invalidIdentifier(let rhsValue)),
            (.duplicateColorToken(let lhsValue), .duplicateColorToken(let rhsValue)),
            (.undefinedColorToken(let lhsValue), .undefinedColorToken(let rhsValue)),
            (.unusedColorToken(let lhsValue), .unusedColorToken(let rhsValue)):
            lhsValue == rhsValue
        case (
            .colorTokenTooLarge(let lhsMaximum),
            .colorTokenTooLarge(let rhsMaximum)
        ),
            (
                .identifierTooLarge(let lhsMaximum),
                .identifierTooLarge(let rhsMaximum)
            ),
            (
                .displayNameTooLarge(let lhsMaximum),
                .displayNameTooLarge(let rhsMaximum)
            ),
            (
                .encodedDataTooLarge(let lhsMaximum),
                .encodedDataTooLarge(let rhsMaximum)
            ):
            lhsMaximum == rhsMaximum
        case (.duplicateColorRole(let lhsRole), .duplicateColorRole(let rhsRole)),
            (.missingColorRole(let lhsRole), .missingColorRole(let rhsRole)):
            lhsRole == rhsRole
        case (.duplicateVariant(let lhsVariant), .duplicateVariant(let rhsVariant)),
            (.missingVariant(let lhsVariant), .missingVariant(let rhsVariant)),
            (
                .editorBackgroundMustBeOpaque(let lhsVariant),
                .editorBackgroundMustBeOpaque(let rhsVariant)
            ):
            lhsVariant == rhsVariant
        case (
            .layerBackgroundMustBeOpaque(let lhsVariant, let lhsRole),
            .layerBackgroundMustBeOpaque(let rhsVariant, let rhsRole)
        ):
            lhsVariant == rhsVariant && lhsRole == rhsRole
        case (.invalidContrastRatio(let lhsRatio), .invalidContrastRatio(let rhsRatio)):
            lhsRatio.bitPattern == rhsRatio.bitPattern
        case (.insufficientContrast(let lhsIssue), .insufficientContrast(let rhsIssue)):
            lhsIssue == rhsIssue
        case (
            .indistinguishableColorState(let lhsVariant, let lhsFirst, let lhsSecond),
            .indistinguishableColorState(let rhsVariant, let rhsFirst, let rhsSecond)
        ):
            lhsVariant == rhsVariant && lhsFirst == rhsFirst && lhsSecond == rhsSecond
        case (
            .duplicateDifferenceDecoration(let lhsKind),
            .duplicateDifferenceDecoration(let rhsKind)
        ),
            (
                .missingDifferenceDecoration(let lhsKind),
                .missingDifferenceDecoration(let rhsKind)
            ):
            lhsKind == rhsKind
        case (.ambiguousDifferenceShape(let lhsShape), .ambiguousDifferenceShape(let rhsShape)):
            lhsShape == rhsShape
        case (
            .unsupportedSchemaVersion(let lhsVersion),
            .unsupportedSchemaVersion(let rhsVersion)
        ):
            lhsVersion == rhsVersion
        case (.invalidDisplayName, .invalidDisplayName),
            (.invalidContrastStandards, .invalidContrastStandards),
            (.paletteLimitExceeded, .paletteLimitExceeded),
            (.invalidLimits, .invalidLimits):
            true
        default:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidColorComponent(let component, let value):
            "Editor color \(component) must be finite and between 0 and 1: \(value)."
        case .invalidHexColor(let value):
            "Editor color is not six- or eight-digit hexadecimal sRGB: \(value)."
        case .invalidColorToken(let token):
            "Editor color token is not portable: \(token)."
        case .colorTokenTooLarge(let maximumUTF8Bytes):
            "Editor color token exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .invalidIdentifier(let identifier):
            "Editor color scheme identifier is invalid: \(identifier)."
        case .identifierTooLarge(let maximumUTF8Bytes):
            "Editor color scheme identifier exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .invalidDisplayName:
            "Editor color scheme display name must contain visible text and no control characters."
        case .displayNameTooLarge(let maximumUTF8Bytes):
            "Editor color scheme display name exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .duplicateColorToken(let token):
            "Editor color palette contains duplicate token: \(token)."
        case .undefinedColorToken(let token):
            "Editor color assignment references undefined token: \(token)."
        case .unusedColorToken(let token):
            "Editor color palette contains unused token: \(token)."
        case .duplicateColorRole(let role):
            "Editor color palette contains duplicate role: \(role.rawValue)."
        case .missingColorRole(let role):
            "Editor color palette is missing role: \(role.rawValue)."
        case .duplicateVariant(let variant):
            "Editor color scheme contains duplicate variant: \(variant.rawValue)."
        case .missingVariant(let variant):
            "Editor color scheme is missing variant: \(variant.rawValue)."
        case .editorBackgroundMustBeOpaque(let variant):
            "Editor background must be opaque for variant: \(variant.rawValue)."
        case .layerBackgroundMustBeOpaque(let variant, let role):
            "Editor layer background \(role.rawValue) must be opaque for variant: \(variant.rawValue)."
        case .invalidContrastRatio(let ratio):
            "Editor contrast ratio must be finite and between 1 and 21: \(ratio)."
        case .invalidContrastStandards:
            "Enhanced editor contrast minima must not be lower than standard minima."
        case .insufficientContrast(let issue):
            "Editor colors \(issue.foregroundRole.rawValue) and \(issue.backgroundRole.rawValue) have contrast \(issue.actualRatio), below \(issue.minimumRatio)."
        case .indistinguishableColorState(let variant, let first, let second):
            "Editor states \(first.rawValue) and \(second.rawValue) are not visibly distinct for variant: \(variant.rawValue)."
        case .duplicateDifferenceDecoration(let kind):
            "Editor color scheme contains duplicate decoration: \(kind.rawValue)."
        case .missingDifferenceDecoration(let kind):
            "Editor color scheme is missing decoration: \(kind.rawValue)."
        case .ambiguousDifferenceShape(let shape):
            "Difference decoration fallback shape is not unique: \(shape.rawValue)."
        case .paletteLimitExceeded:
            "Editor color palette exceeds structural limits."
        case .invalidLimits:
            "Editor color scheme limits are invalid."
        case .encodedDataTooLarge(let maximumBytes):
            "Editor color scheme exceeds the \(maximumBytes)-byte persistence limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported editor color scheme schema version: \(version)."
        }
    }
}

extension EditorColorScheme {
    fileprivate static func makeBuiltIn(_ builtIn: EditorBuiltInColorScheme) -> EditorColorScheme {
        let palettes = EditorColorSchemeVariant.allCases.map { variant in
            switch builtIn {
            case .standard:
                makeStandardPalette(variant)
            case .monochrome:
                makeMonochromePalette(variant)
            }
        }
        let scheme = EditorColorScheme(
            uncheckedIdentifier: "macmerge.\(builtIn.rawValue)",
            displayName: builtIn == .standard ? "MacMerge Standard" : "MacMerge Monochrome",
            palettes: palettes,
            differenceDecorations: builtInDecorations
        )
        do {
            try scheme.validate()
        } catch {
            preconditionFailure("Invalid built-in editor color scheme \(builtIn.rawValue): \(error)")
        }
        return scheme
    }

    fileprivate static var builtInDecorations: [EditorDifferenceDecoration] {
        [
            .init(kind: .added, shape: .leadingBar, pattern: .solid),
            .init(kind: .removed, shape: .strikeThrough, pattern: .backwardDiagonal),
            .init(kind: .modified, shape: .underline, pattern: .forwardDiagonal),
            .init(kind: .conflict, shape: .outline, pattern: .crosshatch),
            .init(kind: .moved, shape: .doubleOutline, pattern: .dots)
        ]
    }

    fileprivate static func makeStandardPalette(
        _ variant: EditorColorSchemeVariant
    ) -> EditorColorPalette {
        if variant.isHighContrast { return makeMonochromePalette(variant) }
        let values = variant.isDark ? standardDarkValues : standardLightValues
        return makePalette(variant: variant, values: values)
    }

    fileprivate static func makeMonochromePalette(
        _ variant: EditorColorSchemeVariant
    ) -> EditorColorPalette {
        let background = variant.isDark ? "000000" : "FFFFFF"
        let foreground = variant.isDark ? "FFFFFF" : "000000"
        let inverseBackground = foreground
        let inverseForeground = background
        let currentLineBackground = variant.isDark ? "30303020" : "D0D0D020"
        let inactiveSelectionBackground = variant.isDark ? "A0A0A0" : "555555"
        let inactiveSelectionForeground = variant.isDark ? "000000" : "FFFFFF"
        let searchBackground = inactiveSelectionBackground
        let searchForeground = inactiveSelectionForeground
        let backgroundRoles: Set<EditorColorRole> = [
            .textBackground,
            .differenceAddedBackground, .differenceRemovedBackground,
            .differenceModifiedBackground, .differenceConflictBackground,
            .movedLineBackground, .systemGutterBackground
        ]
        let patternRoles: Set<EditorColorRole> = [
            .differenceAddedPattern, .differenceRemovedPattern,
            .differenceModifiedPattern, .differenceConflictPattern,
            .movedLinePattern
        ]
        let inverseBackgroundRoles: Set<EditorColorRole> = [
            .selectionBackground, .markerCurrentSearchBackground
        ]
        let inverseForegroundRoles: Set<EditorColorRole> = [
            .selectionForeground, .markerCurrentSearchForeground
        ]
        let values = EditorColorRole.allCases.map { role -> (EditorColorRole, String) in
            switch role {
            case .textCurrentLineBackground:
                return (role, currentLineBackground)
            case .selectionInactiveBackground:
                return (role, inactiveSelectionBackground)
            case .selectionInactiveForeground:
                return (role, inactiveSelectionForeground)
            case .markerSearchBackground:
                return (role, searchBackground)
            case .markerSearchForeground:
                return (role, searchForeground)
            default:
                break
            }
            if backgroundRoles.contains(role) { return (role, background) }
            if patternRoles.contains(role) {
                return (role, foreground)
            }
            if inverseBackgroundRoles.contains(role) { return (role, inverseBackground) }
            if inverseForegroundRoles.contains(role) { return (role, inverseForeground) }
            return (role, foreground)
        }
        return makePalette(variant: variant, values: values)
    }

    fileprivate static func makePalette(
        variant: EditorColorSchemeVariant,
        values: [(EditorColorRole, String)]
    ) -> EditorColorPalette {
        let definitions = values.map { role, hex in
            EditorColorDefinition(
                token: EditorColorToken(uncheckedRawValue: role.rawValue),
                components: EditorColorComponents(builtInHex: hex)
            )
        }
        let assignments = values.map { role, _ in
            EditorColorAssignment(
                role: role,
                token: EditorColorToken(uncheckedRawValue: role.rawValue)
            )
        }
        return EditorColorPalette(
            uncheckedVariant: variant,
            definitions: definitions,
            assignments: assignments
        )
    }

    fileprivate static var standardLightValues: [(EditorColorRole, String)] {
        [
            (.textBackground, "FFFFFF"),
            (.textForeground, "1C1C1E"),
            (.textCaret, "1C1C1E"),
            (.textSecondary, "494D52"),
            (.textLineNumber, "555B63"),
            (.textCurrentLineBackground, "F4F6F820"),
            (.selectionBackground, "005AC8"),
            (.selectionForeground, "FFFFFF"),
            (.selectionInactiveBackground, "6B6B6B"),
            (.selectionInactiveForeground, "FFFFFF"),
            (.differenceAddedBackground, "E5F5E9"),
            (.differenceAddedForeground, "17451F"),
            (.differenceAddedCue, "17451F"),
            (.differenceAddedPattern, "17451F"),
            (.differenceRemovedBackground, "FDE8E7"),
            (.differenceRemovedForeground, "681C17"),
            (.differenceRemovedCue, "681C17"),
            (.differenceRemovedPattern, "681C17"),
            (.differenceModifiedBackground, "FFF3C4"),
            (.differenceModifiedForeground, "574000"),
            (.differenceModifiedCue, "574000"),
            (.differenceModifiedPattern, "574000"),
            (.differenceConflictBackground, "F6E7FF"),
            (.differenceConflictForeground, "52206D"),
            (.differenceConflictCue, "52206D"),
            (.differenceConflictPattern, "52206D"),
            (.movedLineBackground, "E7F0FF"),
            (.movedLineForeground, "163A69"),
            (.movedLineCue, "163A69"),
            (.movedLinePattern, "163A69"),
            (.movedLineConnector, "315F9A"),
            (.syntaxKeyword, "6F1D9B"),
            (.syntaxString, "006B3C"),
            (.syntaxComment, "545B63"),
            (.syntaxNumber, "8A3412"),
            (.syntaxLiteral, "8A1C4A"),
            (.syntaxHeading, "273A8A"),
            (.syntaxEmphasis, "5B3AB5"),
            (.syntaxCode, "8A3500"),
            (.syntaxLink, "0057B8"),
            (.markerSearchBackground, "795000"),
            (.markerSearchForeground, "FFFFFF"),
            (.markerCurrentSearchBackground, "6B4300"),
            (.markerCurrentSearchForeground, "FFFFFF"),
            (.markerBookmark, "6F1D9B"),
            (.markerWhitespace, "66707A"),
            (.markerEndOfLine, "66707A"),
            (.systemGutterBackground, "F4F5F7"),
            (.systemSeparator, "666D75"),
            (.systemFocusRing, "005AC8"),
            (.systemAccent, "005AC8"),
            (.systemWarning, "795000"),
            (.systemError, "A61B1B")
        ]
    }

    fileprivate static var standardDarkValues: [(EditorColorRole, String)] {
        [
            (.textBackground, "111318"),
            (.textForeground, "F2F3F5"),
            (.textCaret, "F2F3F5"),
            (.textSecondary, "C1C6CE"),
            (.textLineNumber, "AAB1BC"),
            (.textCurrentLineBackground, "191C2320"),
            (.selectionBackground, "2869C7"),
            (.selectionForeground, "FFFFFF"),
            (.selectionInactiveBackground, "D0D0D0"),
            (.selectionInactiveForeground, "111318"),
            (.differenceAddedBackground, "173824"),
            (.differenceAddedForeground, "B9F6CA"),
            (.differenceAddedCue, "B9F6CA"),
            (.differenceAddedPattern, "B9F6CA"),
            (.differenceRemovedBackground, "4A2024"),
            (.differenceRemovedForeground, "FFDAD6"),
            (.differenceRemovedCue, "FFDAD6"),
            (.differenceRemovedPattern, "FFDAD6"),
            (.differenceModifiedBackground, "453600"),
            (.differenceModifiedForeground, "FFEDA6"),
            (.differenceModifiedCue, "FFEDA6"),
            (.differenceModifiedPattern, "FFEDA6"),
            (.differenceConflictBackground, "3D2451"),
            (.differenceConflictForeground, "F1D1FF"),
            (.differenceConflictCue, "F1D1FF"),
            (.differenceConflictPattern, "F1D1FF"),
            (.movedLineBackground, "1E344E"),
            (.movedLineForeground, "C7E0FF"),
            (.movedLineCue, "C7E0FF"),
            (.movedLinePattern, "C7E0FF"),
            (.movedLineConnector, "8CC8FF"),
            (.syntaxKeyword, "D8B4FE"),
            (.syntaxString, "75E0A7"),
            (.syntaxComment, "AFB6C0"),
            (.syntaxNumber, "FFBA8A"),
            (.syntaxLiteral, "F9A8D4"),
            (.syntaxHeading, "AEC6FF"),
            (.syntaxEmphasis, "C4B5FD"),
            (.syntaxCode, "FDBA74"),
            (.syntaxLink, "8CC8FF"),
            (.markerSearchBackground, "B08000"),
            (.markerSearchForeground, "111318"),
            (.markerCurrentSearchBackground, "FFC857"),
            (.markerCurrentSearchForeground, "111318"),
            (.markerBookmark, "D8B4FE"),
            (.markerWhitespace, "AAB1BC"),
            (.markerEndOfLine, "AAB1BC"),
            (.systemGutterBackground, "191C23"),
            (.systemSeparator, "9CA3AF"),
            (.systemFocusRing, "8CC8FF"),
            (.systemAccent, "8CC8FF"),
            (.systemWarning, "FFD166"),
            (.systemError, "FFAAA2")
        ]
    }
}
