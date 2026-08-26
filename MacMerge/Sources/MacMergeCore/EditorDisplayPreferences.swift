import Foundation

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct EditorDisplayPreferencesJSONPreflight {
    private static let maximumDepth = 16

    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw malformedJSON() }
    }

    private mutating func parseValue(depth: Int) throws {
        guard let byte = currentByte else { throw malformedJSON() }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString()
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw malformedJSON()
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validate(depth: depth)
        guard consume(0x7B) else { throw malformedJSON() }
        skipWhitespace()
        if consume(0x7D) { return }

        var keys: Set<String> = []
        while true {
            let key = try parseString()
            guard keys.insert(key).inserted else { throw malformedJSON() }
            skipWhitespace()
            guard consume(0x3A) else { throw malformedJSON() }
            skipWhitespace()
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw malformedJSON() }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validate(depth: depth)
        guard consume(0x5B) else { throw malformedJSON() }
        skipWhitespace()
        if consume(0x5D) { return }

        while true {
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw malformedJSON() }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        guard consume(0x22) else { throw malformedJSON() }
        var escaped = false
        while let byte = currentByte {
            index += 1
            if escaped {
                escaped = false
                continue
            }
            if byte == 0x5C {
                escaped = true
            } else if byte == 0x22 {
                return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
            } else if byte < 0x20 {
                throw malformedJSON()
            }
        }
        throw malformedJSON()
    }

    private mutating func parseNumber() throws {
        let start = index
        while let byte = currentByte,
            byte == 0x2B || byte == 0x2D || byte == 0x2E || (0x30...0x39).contains(byte)
                || byte == 0x45 || byte == 0x65
        {
            index += 1
        }
        guard index > start else { throw malformedJSON() }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard literalBytes.count <= bytes.count - index else { throw malformedJSON() }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw malformedJSON() }
            index += 1
        }
    }

    private func validate(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw malformedJSON() }
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
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
                debugDescription: "Editor display preferences data is not valid strict JSON."
            )
        )
    }
}

private func rejectUnknownKeys<Key>(
    from decoder: Decoder,
    allowedBy _: Key.Type
) throws where Key: CodingKey & CaseIterable {
    let allowedKeys = Set(Key.allCases.map(\.stringValue))
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    let unknownKeys = container.allKeys.map(\.stringValue).filter {
        !allowedKeys.contains($0)
    }.sorted()

    guard unknownKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown keys: \(unknownKeys.joined(separator: ", "))."
            )
        )
    }
}

/// UI-independent font selection for comparison editors.
public struct EditorFontDescriptor: Codable, Equatable, Hashable, Sendable {
    public static let minimumPointSize = 1.0
    public static let maximumPointSize = 72.0
    public static let maximumFamilyNameUTF8Bytes = 256

    /// Leaves concrete platform-font resolution to the UI layer.
    public enum Family: Equatable, Hashable, Sendable {
        case systemMonospaced
        case named(String)
    }

    public static let `default` = EditorFontDescriptor(
        validatedFamily: .systemMonospaced,
        pointSize: 12
    )

    public let family: Family
    public let pointSize: Double

    public var familyName: String? {
        guard case .named(let name) = family else { return nil }
        return name
    }

    public var usesSystemMonospacedFont: Bool {
        family == .systemMonospaced
    }

    public init(family: Family, pointSize: Double) throws {
        try Self.validate(family: family, pointSize: pointSize)
        self.family = family
        self.pointSize = pointSize
    }

    public init(familyName: String, pointSize: Double) throws {
        try self.init(family: .named(familyName), pointSize: pointSize)
    }

    public init(systemMonospacedPointSize pointSize: Double = 12) throws {
        try self.init(family: .systemMonospaced, pointSize: pointSize)
    }

    public func validate() throws {
        try Self.validate(family: family, pointSize: pointSize)
    }

    private init(validatedFamily family: Family, pointSize: Double) {
        self.family = family
        self.pointSize = pointSize
    }

    private static func validate(family: Family, pointSize: Double) throws {
        guard pointSize.isFinite,
            pointSize >= minimumPointSize,
            pointSize <= maximumPointSize
        else {
            throw EditorFontDescriptorError.invalidPointSize(pointSize)
        }

        guard case .named(let name) = family else { return }
        guard !name.isEmpty,
            name.unicodeScalars.contains(where: { !$0.properties.isWhitespace })
        else {
            throw EditorFontDescriptorError.invalidFamilyName
        }
        guard name.utf8.count <= maximumFamilyNameUTF8Bytes else {
            throw EditorFontDescriptorError.familyNameTooLarge(
                maximumUTF8Bytes: maximumFamilyNameUTF8Bytes
            )
        }
        guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            name.unicodeScalars.contains(where: {
                !$0.properties.isWhitespace
                    && !CharacterSet.controlCharacters.contains($0)
                    && !$0.properties.isDefaultIgnorableCodePoint
            })
        else {
            throw EditorFontDescriptorError.invalidFamilyName
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case family
        case familyName
        case pointSize
    }

    private enum FamilyWireValue: String, Codable {
        case systemMonospaced
        case named
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowedBy: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wireFamily = try container.decode(FamilyWireValue.self, forKey: .family)
        let family: Family
        switch wireFamily {
        case .systemMonospaced:
            guard !container.contains(.familyName) else {
                throw EditorFontDescriptorError.invalidFamilyName
            }
            family = .systemMonospaced
        case .named:
            family = .named(try container.decode(String.self, forKey: .familyName))
        }
        try self.init(
            family: family,
            pointSize: container.decode(Double.self, forKey: .pointSize)
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pointSize, forKey: .pointSize)
        switch family {
        case .systemMonospaced:
            try container.encode(FamilyWireValue.systemMonospaced, forKey: .family)
        case .named(let name):
            try container.encode(FamilyWireValue.named, forKey: .family)
            try container.encode(name, forKey: .familyName)
        }
    }
}

public enum EditorFontDescriptorError: Error, Equatable, LocalizedError, Sendable {
    case invalidFamilyName
    case familyNameTooLarge(maximumUTF8Bytes: Int)
    case invalidPointSize(Double)

    public static func == (
        lhs: EditorFontDescriptorError,
        rhs: EditorFontDescriptorError
    ) -> Bool {
        switch (lhs, rhs) {
        case (.invalidFamilyName, .invalidFamilyName):
            true
        case (
            .familyNameTooLarge(let lhsMaximum),
            .familyNameTooLarge(let rhsMaximum)
        ):
            lhsMaximum == rhsMaximum
        case (.invalidPointSize(let lhsSize), .invalidPointSize(let rhsSize)):
            lhsSize == rhsSize || (lhsSize.isNaN && rhsSize.isNaN)
        default:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidFamilyName:
            "Editor font family name must contain visible text and no control characters."
        case .familyNameTooLarge(let maximumUTF8Bytes):
            "Editor font family name exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .invalidPointSize(let pointSize):
            "Editor font point size must be finite and between \(EditorFontDescriptor.minimumPointSize) and \(EditorFontDescriptor.maximumPointSize): \(pointSize)."
        }
    }
}

/// Persistable, UI-independent display state shared by comparison editor panes.
public struct EditorDisplayPreferences: Encodable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEncodedBytes = 4 * 1024

    /// Zoom is stored as exact ten-per-normal ticks to avoid floating-point persistence drift.
    public static let minimumZoomStep = 1
    public static let normalZoomStep = 10
    public static let maximumZoomStep = 80

    public static let `default` = EditorDisplayPreferences()

    public let schemaVersion: Int
    public var font: EditorFontDescriptor
    public private(set) var zoomStep: Int
    public var syntaxHighlightingLanguage: SyntaxHighlightingLanguage
    public var showsWhitespace: Bool
    public var showsEndOfLineMarkers: Bool
    public var showsLineDifferences: Bool
    public var showsLineNumbers: Bool
    public var showsMargins: Bool
    public var showsTopMargin: Bool
    public var wrapsLines: Bool

    public var isUsingDefaultFont: Bool { font == Self.default.font }
    public var canZoomIn: Bool { zoomStep < Self.maximumZoomStep }
    public var canZoomOut: Bool { zoomStep > Self.minimumZoomStep }
    public var zoomPercentage: Int { zoomStep * 10 }
    public var zoomScale: Double { Double(zoomStep) / Double(Self.normalZoomStep) }
    public var effectiveFontPointSize: Double { font.pointSize * zoomScale }

    /// Defaults mirror WinMerge display behavior while retaining MacMerge's current editor font.
    public init() {
        schemaVersion = Self.currentSchemaVersion
        font = .default
        zoomStep = Self.normalZoomStep
        syntaxHighlightingLanguage = .plainText
        showsWhitespace = false
        showsEndOfLineMarkers = false
        showsLineDifferences = true
        showsLineNumbers = false
        showsMargins = false
        showsTopMargin = false
        wrapsLines = false
    }

    public init(
        font: EditorFontDescriptor,
        zoomStep: Int = normalZoomStep,
        syntaxHighlightingLanguage: SyntaxHighlightingLanguage = .plainText,
        showsWhitespace: Bool = false,
        showsEndOfLineMarkers: Bool = false,
        showsLineDifferences: Bool = true,
        showsLineNumbers: Bool = false,
        showsMargins: Bool = false,
        showsTopMargin: Bool = false,
        wrapsLines: Bool = false
    ) throws {
        try font.validate()
        try Self.validate(zoomStep: zoomStep)
        schemaVersion = Self.currentSchemaVersion
        self.font = font
        self.zoomStep = zoomStep
        self.syntaxHighlightingLanguage = syntaxHighlightingLanguage
        self.showsWhitespace = showsWhitespace
        self.showsEndOfLineMarkers = showsEndOfLineMarkers
        self.showsLineDifferences = showsLineDifferences
        self.showsLineNumbers = showsLineNumbers
        self.showsMargins = showsMargins
        self.showsTopMargin = showsTopMargin
        self.wrapsLines = wrapsLines
    }

    public mutating func setFont(_ font: EditorFontDescriptor) {
        self.font = font
    }

    public mutating func useDefaultFont() {
        font = Self.default.font
    }

    public mutating func setZoomStep(_ zoomStep: Int) throws {
        try Self.validate(zoomStep: zoomStep)
        self.zoomStep = zoomStep
    }

    @discardableResult
    public mutating func zoomIn() -> Bool {
        guard canZoomIn else { return false }
        zoomStep += 1
        return true
    }

    @discardableResult
    public mutating func zoomOut() -> Bool {
        guard canZoomOut else { return false }
        zoomStep -= 1
        return true
    }

    @discardableResult
    public mutating func zoomToNormal() -> Bool {
        guard zoomStep != Self.normalZoomStep else { return false }
        zoomStep = Self.normalZoomStep
        return true
    }

    @discardableResult
    public mutating func toggleWhitespace() -> Bool {
        showsWhitespace.toggle()
        return showsWhitespace
    }

    @discardableResult
    public mutating func toggleEndOfLineMarkers() -> Bool {
        showsEndOfLineMarkers.toggle()
        return showsEndOfLineMarkers
    }

    @discardableResult
    public mutating func toggleLineDifferences() -> Bool {
        showsLineDifferences.toggle()
        return showsLineDifferences
    }

    @discardableResult
    public mutating func toggleLineNumbers() -> Bool {
        showsLineNumbers.toggle()
        return showsLineNumbers
    }

    @discardableResult
    public mutating func toggleMargins() -> Bool {
        showsMargins.toggle()
        return showsMargins
    }

    @discardableResult
    public mutating func toggleTopMargin() -> Bool {
        showsTopMargin.toggle()
        return showsTopMargin
    }

    @discardableResult
    public mutating func toggleWrapLines() -> Bool {
        wrapsLines.toggle()
        return wrapsLines
    }

    public mutating func reset() {
        self = Self.default
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw EditorDisplayPreferencesError.unsupportedSchemaVersion(schemaVersion)
        }
        try font.validate()
        try Self.validate(zoomStep: zoomStep)
    }

    /// Returns compact JSON with stable object-key ordering.
    public func encodedData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw EditorDisplayPreferencesError.encodedDataTooLarge(
                maximumBytes: Self.maximumEncodedBytes
            )
        }
        return data
    }

    /// Strict schema-1 decoding. Schema 1 is the first persisted representation.
    public static func decode(from data: Data) throws -> EditorDisplayPreferences {
        guard data.count <= maximumEncodedBytes else {
            throw EditorDisplayPreferencesError.encodedDataTooLarge(
                maximumBytes: maximumEncodedBytes
            )
        }
        var preflight = EditorDisplayPreferencesJSONPreflight(data: data)
        try preflight.validate()
        let preferences = try JSONDecoder().decode(Wire.self, from: data).preferences()
        try preferences.validate()
        return preferences
    }

    /// Restores one complete snapshot or returns deterministic defaults on any persistence error.
    public static func restored(from data: Data?) -> EditorDisplayPreferences {
        guard let data else { return .default }
        return (try? decode(from: data)) ?? .default
    }

    private static func validate(zoomStep: Int) throws {
        guard (minimumZoomStep...maximumZoomStep).contains(zoomStep) else {
            throw EditorDisplayPreferencesError.invalidZoomStep(zoomStep)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case font
        case zoomStep
        case syntaxHighlightingLanguage
        case showsWhitespace
        case showsEndOfLineMarkers
        case showsLineDifferences
        case showsLineNumbers
        case showsMargins
        case showsTopMargin
        case wrapsLines
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(font, forKey: .font)
        try container.encode(zoomStep, forKey: .zoomStep)
        try container.encode(
            syntaxHighlightingLanguage.rawValue,
            forKey: .syntaxHighlightingLanguage
        )
        try container.encode(showsWhitespace, forKey: .showsWhitespace)
        try container.encode(showsEndOfLineMarkers, forKey: .showsEndOfLineMarkers)
        try container.encode(showsLineDifferences, forKey: .showsLineDifferences)
        try container.encode(showsLineNumbers, forKey: .showsLineNumbers)
        try container.encode(showsMargins, forKey: .showsMargins)
        try container.encode(showsTopMargin, forKey: .showsTopMargin)
        try container.encode(wrapsLines, forKey: .wrapsLines)
    }

    private struct Wire: Decodable {
        let schemaVersion: Int
        let font: EditorFontDescriptor
        let zoomStep: Int
        let syntaxHighlightingLanguage: String
        let showsWhitespace: Bool
        let showsEndOfLineMarkers: Bool
        let showsLineDifferences: Bool
        let showsLineNumbers: Bool
        let showsMargins: Bool
        let showsTopMargin: Bool
        let wrapsLines: Bool

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion
            case font
            case zoomStep
            case syntaxHighlightingLanguage
            case showsWhitespace
            case showsEndOfLineMarkers
            case showsLineDifferences
            case showsLineNumbers
            case showsMargins
            case showsTopMargin
            case wrapsLines
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownKeys(from: decoder, allowedBy: CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            font = try container.decode(EditorFontDescriptor.self, forKey: .font)
            zoomStep = try container.decode(Int.self, forKey: .zoomStep)
            syntaxHighlightingLanguage = try container.decode(
                String.self,
                forKey: .syntaxHighlightingLanguage
            )
            showsWhitespace = try container.decode(Bool.self, forKey: .showsWhitespace)
            showsEndOfLineMarkers = try container.decode(
                Bool.self,
                forKey: .showsEndOfLineMarkers
            )
            showsLineDifferences = try container.decode(
                Bool.self,
                forKey: .showsLineDifferences
            )
            showsLineNumbers = try container.decode(Bool.self, forKey: .showsLineNumbers)
            showsMargins = try container.decode(Bool.self, forKey: .showsMargins)
            showsTopMargin = try container.decode(Bool.self, forKey: .showsTopMargin)
            wrapsLines = try container.decode(Bool.self, forKey: .wrapsLines)
        }

        func preferences() throws -> EditorDisplayPreferences {
            guard schemaVersion == EditorDisplayPreferences.currentSchemaVersion else {
                throw EditorDisplayPreferencesError.unsupportedSchemaVersion(schemaVersion)
            }
            guard
                let language = SyntaxHighlightingLanguage(
                    rawValue: syntaxHighlightingLanguage
                )
            else {
                throw EditorDisplayPreferencesError.invalidSyntaxHighlightingLanguage(
                    syntaxHighlightingLanguage
                )
            }
            return try EditorDisplayPreferences(
                font: font,
                zoomStep: zoomStep,
                syntaxHighlightingLanguage: language,
                showsWhitespace: showsWhitespace,
                showsEndOfLineMarkers: showsEndOfLineMarkers,
                showsLineDifferences: showsLineDifferences,
                showsLineNumbers: showsLineNumbers,
                showsMargins: showsMargins,
                showsTopMargin: showsTopMargin,
                wrapsLines: wrapsLines
            )
        }
    }
}

public enum EditorDisplayPreferencesError: Error, Equatable, LocalizedError, Sendable {
    case encodedDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case invalidZoomStep(Int)
    case invalidSyntaxHighlightingLanguage(String)

    public var errorDescription: String? {
        switch self {
        case .encodedDataTooLarge(let maximumBytes):
            "Editor display preferences exceed the \(maximumBytes)-byte persistence limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported editor display preferences schema version: \(version)."
        case .invalidZoomStep(let zoomStep):
            "Editor zoom step must be between \(EditorDisplayPreferences.minimumZoomStep) and \(EditorDisplayPreferences.maximumZoomStep): \(zoomStep)."
        case .invalidSyntaxHighlightingLanguage(let language):
            "Unknown syntax highlighting language: \(language)."
        }
    }
}
