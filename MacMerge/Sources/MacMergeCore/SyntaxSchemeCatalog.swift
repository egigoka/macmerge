import Foundation

extension SyntaxTokenKind {
    /// Exact semantic color role consumed by editor palettes for this token kind.
    public var editorColorRole: EditorColorRole {
        switch self {
        case .keyword: .syntaxKeyword
        case .string: .syntaxString
        case .comment: .syntaxComment
        case .number: .syntaxNumber
        case .literal: .syntaxLiteral
        case .heading: .syntaxHeading
        case .emphasis: .syntaxEmphasis
        case .code: .syntaxCode
        case .link: .syntaxLink
        }
    }
}

extension EditorColorRole {
    /// Token kind represented by this role, or `nil` for non-syntax editor roles.
    public var syntaxTokenKind: SyntaxTokenKind? {
        switch self {
        case .syntaxKeyword: .keyword
        case .syntaxString: .string
        case .syntaxComment: .comment
        case .syntaxNumber: .number
        case .syntaxLiteral: .literal
        case .syntaxHeading: .heading
        case .syntaxEmphasis: .emphasis
        case .syntaxCode: .code
        case .syntaxLink: .link
        default: nil
        }
    }
}

/// Stable, nonlocalized ASCII identity. Display names never participate in identity or ordering.
public struct SyntaxSchemeIdentifier:
    Codable, Comparable, CustomStringConvertible, Hashable, Sendable
{
    public static let maximumUTF8Bytes = 128

    public static let builtInPlainText = Self(uncheckedRawValue: "macmerge.syntax.plain-text")
    public static let builtInSwift = Self(uncheckedRawValue: "macmerge.syntax.swift")
    public static let builtInCLike = Self(uncheckedRawValue: "macmerge.syntax.c-like")
    public static let builtInJSON = Self(uncheckedRawValue: "macmerge.syntax.json")
    public static let builtInMarkdown = Self(uncheckedRawValue: "macmerge.syntax.markdown")

    public let rawValue: String

    public init(_ rawValue: String) throws {
        try self.init(rawValue: rawValue)
    }

    public init(rawValue: String) throws {
        guard rawValue.utf8.prefix(Self.maximumUTF8Bytes + 1).count <= Self.maximumUTF8Bytes
        else {
            throw SyntaxSchemeCatalogError.identifierTooLarge(
                maximumUTF8Bytes: Self.maximumUTF8Bytes
            )
        }
        guard Self.isValid(rawValue) else {
            throw SyntaxSchemeCatalogError.invalidIdentifier
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        guard Self.isValid(rawValue), rawValue.utf8.count <= Self.maximumUTF8Bytes else {
            throw SyntaxSchemeCatalogError.invalidIdentifier
        }
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue.utf8.lexicographicallyPrecedes(right.rawValue.utf8)
    }

    public static func builtIn(for language: SyntaxHighlightingLanguage) -> Self {
        switch language {
        case .plainText: .builtInPlainText
        case .swift: .builtInSwift
        case .cLike: .builtInCLike
        case .json: .builtInJSON
        case .markdown: .builtInMarkdown
        }
    }

    fileprivate static let builtInNamespace = "macmerge.syntax."

    fileprivate init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }

    fileprivate static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty,
            let first = value.utf8.first,
            let last = value.utf8.last,
            isASCIIAlphanumeric(first),
            isASCIIAlphanumeric(last)
        else {
            return false
        }
        return value.utf8.allSatisfy {
            isASCIIAlphanumeric($0) || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)
            || (0x61...0x7A).contains(byte)
    }
}

public enum SyntaxSchemeOrigin: String, CaseIterable, Codable, Hashable, Sendable {
    case builtIn
    case custom
}

/// Textual workspace shape in which a syntax scheme may be selected.
public enum SyntaxSchemeApplicationMode: String, CaseIterable, Codable, Hashable, Sendable {
    case textComparison
    case threeWayTextComparison
    case conflictComparison
    case textEditor
}

public typealias SyntaxSchemeMode = SyntaxSchemeApplicationMode

/// Strict bridge between lexical token kinds and semantic editor color roles.
public struct SyntaxSchemeColorRoleReference: Hashable, Sendable {
    public let tokenKind: SyntaxTokenKind
    public let colorRole: EditorColorRole

    public init(tokenKind: SyntaxTokenKind, colorRole: EditorColorRole) throws {
        guard colorRole == tokenKind.editorColorRole else {
            throw SyntaxSchemeCatalogError.incompatibleColorRole(
                tokenKind: tokenKind,
                colorRole: colorRole
            )
        }
        self.tokenKind = tokenKind
        self.colorRole = colorRole
    }

    /// Resolves through an existing UI-independent editor palette.
    public func color(in palette: EditorColorPalette) -> EditorColorComponents? {
        palette.color(for: colorRole)
    }

    fileprivate init(uncheckedTokenKind tokenKind: SyntaxTokenKind) {
        self.tokenKind = tokenKind
        colorRole = tokenKind.editorColorRole
    }
}

public struct SyntaxSchemeCatalogLimits: Hashable, Sendable {
    public static let hardMaximumCustomSchemeCount = 4_096
    public static let hardMaximumDisplayNameUTF8Bytes = 4 * 1_024
    public static let hardMaximumPersistenceBytes = 64 * 1_024
    public static let hardMaximumJSONDepth = 16
    public static let hardMaximumWorkUnits = 16 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 4_096

    public static let `default` = Self(
        maximumCustomSchemeCount: 512,
        maximumDisplayNameUTF8Bytes: 256,
        maximumPersistenceBytes: 4 * 1_024,
        maximumJSONDepth: 4,
        maximumWorkUnits: 1 * 1_024 * 1_024,
        cancellationCheckInterval: 64,
        validated: ()
    )

    public let maximumCustomSchemeCount: Int
    public let maximumDisplayNameUTF8Bytes: Int
    public let maximumPersistenceBytes: Int
    public let maximumJSONDepth: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumCustomSchemeCount: Int = 512,
        maximumDisplayNameUTF8Bytes: Int = 256,
        maximumPersistenceBytes: Int = 4 * 1_024,
        maximumJSONDepth: Int = 4,
        maximumWorkUnits: Int = 1 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) throws {
        self.init(
            maximumCustomSchemeCount: maximumCustomSchemeCount,
            maximumDisplayNameUTF8Bytes: maximumDisplayNameUTF8Bytes,
            maximumPersistenceBytes: maximumPersistenceBytes,
            maximumJSONDepth: maximumJSONDepth,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval,
            validated: ()
        )
        try validate()
    }

    fileprivate func validate() throws {
        guard (0...Self.hardMaximumCustomSchemeCount).contains(maximumCustomSchemeCount),
            (1...Self.hardMaximumDisplayNameUTF8Bytes).contains(
                maximumDisplayNameUTF8Bytes
            ),
            (1...Self.hardMaximumPersistenceBytes).contains(maximumPersistenceBytes),
            (1...Self.hardMaximumJSONDepth).contains(maximumJSONDepth),
            (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits),
            (1...Self.hardMaximumCancellationCheckInterval).contains(
                cancellationCheckInterval
            )
        else {
            throw SyntaxSchemeCatalogError.invalidLimits
        }
    }

    private init(
        maximumCustomSchemeCount: Int,
        maximumDisplayNameUTF8Bytes: Int,
        maximumPersistenceBytes: Int,
        maximumJSONDepth: Int,
        maximumWorkUnits: Int,
        cancellationCheckInterval: Int,
        validated: Void
    ) {
        self.maximumCustomSchemeCount = maximumCustomSchemeCount
        self.maximumDisplayNameUTF8Bytes = maximumDisplayNameUTF8Bytes
        self.maximumPersistenceBytes = maximumPersistenceBytes
        self.maximumJSONDepth = maximumJSONDepth
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum SyntaxSchemeCatalogError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case invalidIdentifier
    case identifierTooLarge(maximumUTF8Bytes: Int)
    case reservedCustomIdentifier
    case invalidDisplayName
    case displayNameTooLarge(maximumUTF8Bytes: Int)
    case emptySupportedLanguages
    case tooManySupportedLanguages(maximum: Int)
    case duplicateSupportedLanguage(SyntaxHighlightingLanguage)
    case emptyApplicationModes
    case tooManyApplicationModes(maximum: Int)
    case duplicateApplicationMode(SyntaxSchemeApplicationMode)
    case tooManyColorRoleReferences(maximum: Int)
    case duplicateColorRoleReference(SyntaxTokenKind)
    case missingColorRoleReference(SyntaxTokenKind)
    case incompatibleColorRole(tokenKind: SyntaxTokenKind, colorRole: EditorColorRole)
    case customCatalogContainsBuiltInScheme
    case duplicateSchemeIdentifier(SyntaxSchemeIdentifier)
    case tooManyCustomSchemes(maximum: Int)
    case noApplicableScheme(
        language: SyntaxHighlightingLanguage,
        mode: SyntaxSchemeApplicationMode
    )
    case persistenceInputTooLarge(maximumBytes: Int)
    case persistenceOutputTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case malformedPersistence
    case nonCanonicalPersistence
    case jsonTooDeep(maximumDepth: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case cancelled
    case staleCatalog(expected: SyntaxSchemeCatalogRevision, actual: SyntaxSchemeCatalogRevision)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Syntax scheme catalog limits are invalid."
        case .invalidIdentifier:
            "Syntax scheme identifier is invalid."
        case .identifierTooLarge(let maximumUTF8Bytes):
            "Syntax scheme identifier exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .reservedCustomIdentifier:
            "Custom syntax scheme identifier uses a reserved built-in namespace."
        case .invalidDisplayName:
            "Syntax scheme display name is invalid."
        case .displayNameTooLarge(let maximumUTF8Bytes):
            "Syntax scheme display name exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .emptySupportedLanguages:
            "Syntax scheme must support at least one highlighting language."
        case .tooManySupportedLanguages(let maximum):
            "Syntax scheme exceeds the \(maximum)-language limit."
        case .duplicateSupportedLanguage(let language):
            "Syntax scheme repeats language \(language.rawValue)."
        case .emptyApplicationModes:
            "Syntax scheme must apply to at least one textual mode."
        case .tooManyApplicationModes(let maximum):
            "Syntax scheme exceeds the \(maximum)-mode limit."
        case .duplicateApplicationMode(let mode):
            "Syntax scheme repeats mode \(mode.rawValue)."
        case .tooManyColorRoleReferences(let maximum):
            "Syntax scheme exceeds the \(maximum)-color-role-reference limit."
        case .duplicateColorRoleReference(let tokenKind):
            "Syntax scheme repeats color role for token kind \(tokenKind.rawValue)."
        case .missingColorRoleReference(let tokenKind):
            "Syntax scheme is missing color role for token kind \(tokenKind.rawValue)."
        case .incompatibleColorRole(let tokenKind, let colorRole):
            "Color role \(colorRole.rawValue) is incompatible with token kind \(tokenKind.rawValue)."
        case .customCatalogContainsBuiltInScheme:
            "Custom syntax scheme input contains a built-in scheme."
        case .duplicateSchemeIdentifier:
            "Syntax scheme catalog contains a duplicate stable identifier."
        case .tooManyCustomSchemes(let maximum):
            "Syntax scheme catalog exceeds the \(maximum)-custom-scheme limit."
        case .noApplicableScheme(let language, let mode):
            "No syntax scheme supports \(language.rawValue) in \(mode.rawValue)."
        case .persistenceInputTooLarge(let maximumBytes):
            "Syntax scheme selection data exceeds the \(maximumBytes)-byte input limit."
        case .persistenceOutputTooLarge(let maximumBytes):
            "Syntax scheme selection data exceeds the \(maximumBytes)-byte output limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported syntax scheme selection schema version: \(version)."
        case .malformedPersistence:
            "Syntax scheme selection data is malformed."
        case .nonCanonicalPersistence:
            "Syntax scheme selection data is not canonical."
        case .jsonTooDeep(let maximumDepth):
            "Syntax scheme selection JSON exceeds the \(maximumDepth)-level depth limit."
        case .workLimitExceeded(let maximumWorkUnits):
            "Syntax scheme catalog work exceeds the \(maximumWorkUnits)-unit limit."
        case .cancelled:
            "Syntax scheme catalog operation was cancelled."
        case .staleCatalog:
            "Syntax scheme resolution belongs to a stale catalog snapshot."
        }
    }
}

/// Metadata-only highlighting scheme. It contains no renderer, parser, path, or executable hook.
public struct SyntaxScheme:
    Identifiable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let id: SyntaxSchemeIdentifier
    public let displayName: String
    public let origin: SyntaxSchemeOrigin
    /// Stored in `SyntaxHighlightingLanguage.allCases` order.
    public let supportedLanguages: [SyntaxHighlightingLanguage]
    /// Stored in `SyntaxSchemeApplicationMode.allCases` order.
    public let applicationModes: [SyntaxSchemeApplicationMode]
    /// Complete and stored in `SyntaxTokenKind.allCases` order.
    public let colorRoleReferences: [SyntaxSchemeColorRoleReference]

    public init(
        id: SyntaxSchemeIdentifier,
        displayName: String,
        supportedLanguages: [SyntaxHighlightingLanguage],
        applicationModes: [SyntaxSchemeApplicationMode] = SyntaxSchemeApplicationMode.allCases,
        colorRoleReferences: [SyntaxSchemeColorRoleReference] = Self.canonicalColorRoleReferences,
        limits: SyntaxSchemeCatalogLimits = .default
    ) throws {
        try limits.validate()
        try SyntaxSchemeCatalogValidation.checkCancellation()
        guard supportedLanguages.count <= SyntaxHighlightingLanguage.allCases.count else {
            throw SyntaxSchemeCatalogError.tooManySupportedLanguages(
                maximum: SyntaxHighlightingLanguage.allCases.count
            )
        }
        guard applicationModes.count <= SyntaxSchemeApplicationMode.allCases.count else {
            throw SyntaxSchemeCatalogError.tooManyApplicationModes(
                maximum: SyntaxSchemeApplicationMode.allCases.count
            )
        }
        guard colorRoleReferences.count <= SyntaxTokenKind.allCases.count else {
            throw SyntaxSchemeCatalogError.tooManyColorRoleReferences(
                maximum: SyntaxTokenKind.allCases.count
            )
        }
        guard
            displayName.utf8.prefix(limits.maximumDisplayNameUTF8Bytes + 1).count
                <= limits.maximumDisplayNameUTF8Bytes
        else {
            throw SyntaxSchemeCatalogError.displayNameTooLarge(
                maximumUTF8Bytes: limits.maximumDisplayNameUTF8Bytes
            )
        }
        self.id = id
        self.displayName = displayName.precomposedStringWithCanonicalMapping
        origin = .custom
        self.supportedLanguages = Self.sortedLanguages(supportedLanguages)
        self.applicationModes = Self.sortedModes(applicationModes)
        self.colorRoleReferences = Self.sortedReferences(colorRoleReferences)
        var budget = SyntaxSchemeCatalogWorkBudget(limits: limits)
        try validate(limits: limits, budget: &budget)
    }

    public static let canonicalColorRoleReferences = SyntaxTokenKind.allCases.map {
        SyntaxSchemeColorRoleReference(uncheckedTokenKind: $0)
    }

    public static let builtIns: [SyntaxScheme] = [
        makeBuiltIn(
            id: .builtInPlainText,
            displayName: "Plain Text",
            language: .plainText
        ),
        makeBuiltIn(id: .builtInSwift, displayName: "Swift", language: .swift),
        makeBuiltIn(id: .builtInCLike, displayName: "C and C++", language: .cLike),
        makeBuiltIn(id: .builtInJSON, displayName: "JSON", language: .json),
        makeBuiltIn(id: .builtInMarkdown, displayName: "Markdown", language: .markdown)
    ].sorted { $0.id < $1.id }

    public var description: String {
        "SyntaxScheme(origin: \(origin.rawValue), languages: \(supportedLanguages.count), metadata: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "origin": origin.rawValue,
                "languageCount": supportedLanguages.count,
                "applicationModeCount": applicationModes.count,
                "metadata": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public func supports(
        language: SyntaxHighlightingLanguage,
        mode: SyntaxSchemeApplicationMode
    ) -> Bool {
        supportedLanguages.contains(language) && applicationModes.contains(mode)
    }

    public func colorRole(for tokenKind: SyntaxTokenKind) -> EditorColorRole {
        tokenKind.editorColorRole
    }

    fileprivate func validate(
        limits: SyntaxSchemeCatalogLimits,
        budget: inout SyntaxSchemeCatalogWorkBudget
    ) throws {
        try budget.consume(id.rawValue.utf8.count + displayName.utf8.count + 1)
        guard displayName.utf8.count <= limits.maximumDisplayNameUTF8Bytes else {
            throw SyntaxSchemeCatalogError.displayNameTooLarge(
                maximumUTF8Bytes: limits.maximumDisplayNameUTF8Bytes
            )
        }
        guard SyntaxSchemeCatalogValidation.isValidDisplayName(displayName) else {
            throw SyntaxSchemeCatalogError.invalidDisplayName
        }
        if origin == .custom,
            id.rawValue.hasPrefix(SyntaxSchemeIdentifier.builtInNamespace)
        {
            throw SyntaxSchemeCatalogError.reservedCustomIdentifier
        }

        guard !supportedLanguages.isEmpty else {
            throw SyntaxSchemeCatalogError.emptySupportedLanguages
        }
        guard supportedLanguages.count <= SyntaxHighlightingLanguage.allCases.count else {
            throw SyntaxSchemeCatalogError.tooManySupportedLanguages(
                maximum: SyntaxHighlightingLanguage.allCases.count
            )
        }
        var languages: Set<SyntaxHighlightingLanguage> = []
        for language in supportedLanguages {
            try budget.consume()
            guard languages.insert(language).inserted else {
                throw SyntaxSchemeCatalogError.duplicateSupportedLanguage(language)
            }
        }
        guard supportedLanguages == Self.sortedLanguages(supportedLanguages) else {
            throw SyntaxSchemeCatalogError.duplicateSupportedLanguage(supportedLanguages[0])
        }

        guard !applicationModes.isEmpty else {
            throw SyntaxSchemeCatalogError.emptyApplicationModes
        }
        guard applicationModes.count <= SyntaxSchemeApplicationMode.allCases.count else {
            throw SyntaxSchemeCatalogError.tooManyApplicationModes(
                maximum: SyntaxSchemeApplicationMode.allCases.count
            )
        }
        var modes: Set<SyntaxSchemeApplicationMode> = []
        for mode in applicationModes {
            try budget.consume()
            guard modes.insert(mode).inserted else {
                throw SyntaxSchemeCatalogError.duplicateApplicationMode(mode)
            }
        }
        guard applicationModes == Self.sortedModes(applicationModes) else {
            throw SyntaxSchemeCatalogError.duplicateApplicationMode(applicationModes[0])
        }

        guard colorRoleReferences.count <= SyntaxTokenKind.allCases.count else {
            throw SyntaxSchemeCatalogError.tooManyColorRoleReferences(
                maximum: SyntaxTokenKind.allCases.count
            )
        }
        var kinds: Set<SyntaxTokenKind> = []
        for reference in colorRoleReferences {
            try budget.consume()
            guard kinds.insert(reference.tokenKind).inserted else {
                throw SyntaxSchemeCatalogError.duplicateColorRoleReference(reference.tokenKind)
            }
            guard reference.colorRole == reference.tokenKind.editorColorRole else {
                throw SyntaxSchemeCatalogError.incompatibleColorRole(
                    tokenKind: reference.tokenKind,
                    colorRole: reference.colorRole
                )
            }
        }
        for tokenKind in SyntaxTokenKind.allCases where !kinds.contains(tokenKind) {
            throw SyntaxSchemeCatalogError.missingColorRoleReference(tokenKind)
        }
    }

    private static func makeBuiltIn(
        id: SyntaxSchemeIdentifier,
        displayName: String,
        language: SyntaxHighlightingLanguage
    ) -> SyntaxScheme {
        SyntaxScheme(
            uncheckedID: id,
            displayName: displayName,
            language: language
        )
    }

    private init(
        uncheckedID id: SyntaxSchemeIdentifier,
        displayName: String,
        language: SyntaxHighlightingLanguage
    ) {
        self.id = id
        self.displayName = displayName
        origin = .builtIn
        supportedLanguages = [language]
        applicationModes = SyntaxSchemeApplicationMode.allCases
        colorRoleReferences = Self.canonicalColorRoleReferences
    }

    private static func sortedLanguages(
        _ values: [SyntaxHighlightingLanguage]
    ) -> [SyntaxHighlightingLanguage] {
        values.sorted {
            Self.languageRank($0) < Self.languageRank($1)
        }
    }

    private static func languageRank(_ value: SyntaxHighlightingLanguage) -> Int {
        SyntaxHighlightingLanguage.allCases.firstIndex(of: value) ?? Int.max
    }

    private static func sortedModes(
        _ values: [SyntaxSchemeApplicationMode]
    ) -> [SyntaxSchemeApplicationMode] {
        values.sorted {
            Self.modeRank($0) < Self.modeRank($1)
        }
    }

    private static func modeRank(_ value: SyntaxSchemeApplicationMode) -> Int {
        SyntaxSchemeApplicationMode.allCases.firstIndex(of: value) ?? Int.max
    }

    private static func sortedReferences(
        _ values: [SyntaxSchemeColorRoleReference]
    ) -> [SyntaxSchemeColorRoleReference] {
        values.sorted {
            Self.tokenKindRank($0.tokenKind) < Self.tokenKindRank($1.tokenKind)
        }
    }

    private static func tokenKindRank(_ value: SyntaxTokenKind) -> Int {
        SyntaxTokenKind.allCases.firstIndex(of: value) ?? Int.max
    }
}

/// Persisted choice only. Scheme metadata, display names, colors, and catalog contents are excluded.
public struct SyntaxSchemeSelection:
    Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let currentSchemaVersion = 1
    public static let none = SyntaxSchemeSelection()

    public let schemaVersion: Int
    public let selectedIdentifier: SyntaxSchemeIdentifier?
    public let fallbackIdentifier: SyntaxSchemeIdentifier?

    public init(
        selectedIdentifier: SyntaxSchemeIdentifier? = nil,
        fallbackIdentifier: SyntaxSchemeIdentifier? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.selectedIdentifier = selectedIdentifier
        self.fallbackIdentifier = fallbackIdentifier
    }

    public var description: String {
        "SyntaxSchemeSelection(schemaVersion: \(schemaVersion), identifiers: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "schemaVersion": schemaVersion,
                "selectedIdentifier": "<redacted>",
                "fallbackIdentifier": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    /// Canonical schema-versioned JSON containing stable identifiers only.
    public func encodedData(
        limits: SyntaxSchemeCatalogLimits = .default
    ) throws -> Data {
        try limits.validate()
        try SyntaxSchemeCatalogValidation.checkCancellation()
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SyntaxSchemeCatalogError.unsupportedSchemaVersion(schemaVersion)
        }
        let wire = SyntaxSchemeSelectionWire(selection: self)
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            data = try encoder.encode(wire)
        } catch let error as SyntaxSchemeCatalogError {
            throw error
        } catch {
            throw SyntaxSchemeCatalogError.malformedPersistence
        }
        guard data.count <= limits.maximumPersistenceBytes else {
            throw SyntaxSchemeCatalogError.persistenceOutputTooLarge(
                maximumBytes: limits.maximumPersistenceBytes
            )
        }
        var budget = SyntaxSchemeCatalogWorkBudget(limits: limits)
        try budget.consume(data.count)
        return data
    }

    public func redactedEncodedData(
        limits: SyntaxSchemeCatalogLimits = .default
    ) throws -> Data {
        try encodedData(limits: limits)
    }

    /// Strictly accepts the canonical representation produced by `encodedData(limits:)`.
    public static func decode(
        from data: Data,
        limits: SyntaxSchemeCatalogLimits = .default
    ) throws -> SyntaxSchemeSelection {
        try limits.validate()
        try SyntaxSchemeCatalogValidation.checkCancellation()
        guard data.count <= limits.maximumPersistenceBytes else {
            throw SyntaxSchemeCatalogError.persistenceInputTooLarge(
                maximumBytes: limits.maximumPersistenceBytes
            )
        }
        try SyntaxSchemeCatalogValidation.preflightJSON(data, limits: limits)
        do {
            let version = try JSONDecoder().decode(
                SyntaxSchemeSelectionVersionWire.self,
                from: data
            )
            guard version.schemaVersion == currentSchemaVersion else {
                throw SyntaxSchemeCatalogError.unsupportedSchemaVersion(version.schemaVersion)
            }
            let wire = try JSONDecoder().decode(SyntaxSchemeSelectionWire.self, from: data)
            let selection = try wire.selection()
            let canonical = try selection.encodedData(limits: limits)
            guard canonical == data else {
                throw SyntaxSchemeCatalogError.nonCanonicalPersistence
            }
            return selection
        } catch let error as SyntaxSchemeCatalogError {
            throw error
        } catch {
            throw SyntaxSchemeCatalogError.malformedPersistence
        }
    }

    public static func decodeRedacted(
        from data: Data,
        limits: SyntaxSchemeCatalogLimits = .default
    ) throws -> SyntaxSchemeSelection {
        try decode(from: data, limits: limits)
    }

    /// Returns `fallback` for absent or invalid persistence while preserving typed cancellation.
    public static func restored(
        from data: Data?,
        fallback: SyntaxSchemeSelection = .none,
        limits: SyntaxSchemeCatalogLimits = .default
    ) throws -> SyntaxSchemeSelection {
        try limits.validate()
        try SyntaxSchemeCatalogValidation.checkCancellation()
        guard let data else { return fallback }
        do {
            return try decode(from: data, limits: limits)
        } catch SyntaxSchemeCatalogError.cancelled {
            throw SyntaxSchemeCatalogError.cancelled
        } catch {
            return fallback
        }
    }
}

/// Caller-owned lineage and monotonic generation used to diagnose stale resolutions.
public struct SyntaxSchemeCatalogRevision:
    Codable, Comparable, Hashable, Sendable
{
    public let lineage: UInt64
    public let generation: UInt64

    public init(lineage: UInt64, generation: UInt64) {
        self.lineage = lineage
        self.generation = generation
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.lineage == right.lineage
            ? left.generation < right.generation
            : left.lineage < right.lineage
    }
}

/// Exact immutable catalog identity. Reflection deliberately omits scheme metadata.
public struct SyntaxSchemeCatalogFingerprint:
    Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let revision: SyntaxSchemeCatalogRevision
    private let schemes: [SyntaxScheme]
    private let limits: SyntaxSchemeCatalogLimits

    fileprivate init(
        revision: SyntaxSchemeCatalogRevision,
        schemes: [SyntaxScheme],
        limits: SyntaxSchemeCatalogLimits
    ) {
        self.revision = revision
        self.schemes = schemes
        self.limits = limits
    }

    public var description: String {
        "SyntaxSchemeCatalogFingerprint(revision: \(revision), schemes: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "revision": revision,
                "schemeCount": schemes.count,
                "schemes": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    fileprivate func matches(_ catalog: SyntaxSchemeCatalog) throws -> Bool {
        guard revision == catalog.revision,
            limits == catalog.limits,
            schemes.count == catalog.schemes.count
        else {
            return false
        }
        var budget = SyntaxSchemeCatalogWorkBudget(limits: catalog.limits)
        for (expected, actual) in zip(schemes, catalog.schemes) {
            try budget.consume(
                expected.id.rawValue.utf8.count + expected.displayName.utf8.count + 1
            )
            guard expected == actual else { return false }
        }
        return true
    }
}

public enum SyntaxSchemeSelectionRejection: String, CaseIterable, Hashable, Sendable {
    case unavailable
    case unsupportedLanguage
    case unsupportedMode
}

public enum SyntaxSchemeResolutionSource: String, CaseIterable, Hashable, Sendable {
    case selected
    case explicitFallback
    case languageDefault
}

/// Applicable scheme plus exact catalog snapshot contract for later execution or rendering.
public struct SyntaxSchemeResolution: Hashable, Sendable {
    public let scheme: SyntaxScheme
    public let requestedLanguage: SyntaxHighlightingLanguage
    public let applicationMode: SyntaxSchemeApplicationMode
    public let source: SyntaxSchemeResolutionSource
    public let selectedRejection: SyntaxSchemeSelectionRejection?
    public let fallbackRejection: SyntaxSchemeSelectionRejection?
    public let catalogFingerprint: SyntaxSchemeCatalogFingerprint

    public var expectedCatalogRevision: SyntaxSchemeCatalogRevision {
        catalogFingerprint.revision
    }

    public func isCurrent(in catalog: SyntaxSchemeCatalog) throws -> Bool {
        try SyntaxSchemeCatalogValidation.checkCancellation()
        return try catalogFingerprint.matches(catalog)
    }

    public func validate(against catalog: SyntaxSchemeCatalog) throws {
        guard try isCurrent(in: catalog) else {
            throw SyntaxSchemeCatalogError.staleCatalog(
                expected: catalogFingerprint.revision,
                actual: catalog.revision
            )
        }
    }
}

/// Deterministic metadata registry. Construction performs no discovery and opens no resources.
public struct SyntaxSchemeCatalog:
    Hashable, RandomAccessCollection, Sendable, CustomReflectable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public typealias Index = Int

    public static let builtInSchemes = SyntaxScheme.builtIns

    public let revision: SyntaxSchemeCatalogRevision
    public let limits: SyntaxSchemeCatalogLimits
    /// Built-in and custom schemes in stable identifier order.
    public let schemes: [SyntaxScheme]

    public var startIndex: Int { schemes.startIndex }
    public var endIndex: Int { schemes.endIndex }
    public subscript(position: Int) -> SyntaxScheme { schemes[position] }

    public var fingerprint: SyntaxSchemeCatalogFingerprint {
        SyntaxSchemeCatalogFingerprint(
            revision: revision,
            schemes: schemes,
            limits: limits
        )
    }

    public init(
        customSchemes: [SyntaxScheme] = [],
        revision: SyntaxSchemeCatalogRevision = .init(lineage: 0, generation: 0),
        limits: SyntaxSchemeCatalogLimits = .default
    ) throws {
        try limits.validate()
        try SyntaxSchemeCatalogValidation.checkCancellation()
        guard customSchemes.count <= limits.maximumCustomSchemeCount else {
            throw SyntaxSchemeCatalogError.tooManyCustomSchemes(
                maximum: limits.maximumCustomSchemeCount
            )
        }

        var budget = SyntaxSchemeCatalogWorkBudget(limits: limits)
        var validated = Self.builtInSchemes
        validated.reserveCapacity(Self.builtInSchemes.count + customSchemes.count)
        for scheme in Self.builtInSchemes {
            try scheme.validate(limits: limits, budget: &budget)
        }
        for scheme in customSchemes {
            try budget.consume()
            guard scheme.origin == .custom else {
                throw SyntaxSchemeCatalogError.customCatalogContainsBuiltInScheme
            }
            try scheme.validate(limits: limits, budget: &budget)
            validated.append(scheme)
        }
        validated = try syntaxSchemeCatalogSorted(validated, budget: &budget)
        try SyntaxSchemeCatalogValidation.checkCancellation()
        for index in validated.indices.dropFirst() {
            try budget.consume()
            guard validated[index - 1].id != validated[index].id else {
                throw SyntaxSchemeCatalogError.duplicateSchemeIdentifier(validated[index].id)
            }
        }

        self.revision = revision
        self.limits = limits
        schemes = validated
    }

    public var description: String {
        "SyntaxSchemeCatalog(revision: \(revision), schemeCount: \(schemes.count), schemes: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "revision": revision,
                "schemeCount": schemes.count,
                "schemes": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public static func defaultIdentifier(
        for language: SyntaxHighlightingLanguage
    ) -> SyntaxSchemeIdentifier {
        .builtIn(for: language)
    }

    public func scheme(withIdentifier identifier: SyntaxSchemeIdentifier) -> SyntaxScheme? {
        var lower = schemes.startIndex
        var upper = schemes.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if schemes[middle].id < identifier {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < schemes.endIndex, schemes[lower].id == identifier else { return nil }
        return schemes[lower]
    }

    /// Returns matches in stable identifier order, independent of registration order.
    public func schemes(
        supporting language: SyntaxHighlightingLanguage,
        in mode: SyntaxSchemeApplicationMode
    ) throws -> [SyntaxScheme] {
        try SyntaxSchemeCatalogValidation.checkCancellation()
        var result: [SyntaxScheme] = []
        result.reserveCapacity(schemes.count)
        var budget = SyntaxSchemeCatalogWorkBudget(limits: limits)
        for scheme in schemes {
            try budget.consume()
            if scheme.supports(language: language, mode: mode) {
                result.append(scheme)
            }
        }
        return result
    }

    /// Selected ID wins only when applicable, then explicit fallback, then fixed language built-in.
    public func resolve(
        _ selection: SyntaxSchemeSelection,
        language: SyntaxHighlightingLanguage,
        mode: SyntaxSchemeApplicationMode
    ) throws -> SyntaxSchemeResolution {
        try SyntaxSchemeCatalogValidation.checkCancellation()
        guard selection.schemaVersion == SyntaxSchemeSelection.currentSchemaVersion else {
            throw SyntaxSchemeCatalogError.unsupportedSchemaVersion(selection.schemaVersion)
        }

        let selected = evaluation(
            of: selection.selectedIdentifier,
            language: language,
            mode: mode
        )
        if let scheme = selected.scheme {
            return resolution(
                scheme: scheme,
                language: language,
                mode: mode,
                source: .selected,
                selectedRejection: nil,
                fallbackRejection: nil
            )
        }

        let fallback = evaluation(
            of: selection.fallbackIdentifier,
            language: language,
            mode: mode
        )
        if let scheme = fallback.scheme {
            return resolution(
                scheme: scheme,
                language: language,
                mode: mode,
                source: .explicitFallback,
                selectedRejection: selected.rejection,
                fallbackRejection: nil
            )
        }

        let defaultIdentifier = Self.defaultIdentifier(for: language)
        guard let scheme = scheme(withIdentifier: defaultIdentifier),
            scheme.supports(language: language, mode: mode)
        else {
            throw SyntaxSchemeCatalogError.noApplicableScheme(language: language, mode: mode)
        }
        return resolution(
            scheme: scheme,
            language: language,
            mode: mode,
            source: .languageDefault,
            selectedRejection: selected.rejection,
            fallbackRejection: fallback.rejection
        )
    }

    private func evaluation(
        of identifier: SyntaxSchemeIdentifier?,
        language: SyntaxHighlightingLanguage,
        mode: SyntaxSchemeApplicationMode
    ) -> (scheme: SyntaxScheme?, rejection: SyntaxSchemeSelectionRejection?) {
        guard let identifier else { return (nil, nil) }
        guard let scheme = scheme(withIdentifier: identifier) else {
            return (nil, .unavailable)
        }
        guard scheme.supportedLanguages.contains(language) else {
            return (nil, .unsupportedLanguage)
        }
        guard scheme.applicationModes.contains(mode) else {
            return (nil, .unsupportedMode)
        }
        return (scheme, nil)
    }

    private func resolution(
        scheme: SyntaxScheme,
        language: SyntaxHighlightingLanguage,
        mode: SyntaxSchemeApplicationMode,
        source: SyntaxSchemeResolutionSource,
        selectedRejection: SyntaxSchemeSelectionRejection?,
        fallbackRejection: SyntaxSchemeSelectionRejection?
    ) -> SyntaxSchemeResolution {
        SyntaxSchemeResolution(
            scheme: scheme,
            requestedLanguage: language,
            applicationMode: mode,
            source: source,
            selectedRejection: selectedRejection,
            fallbackRejection: fallbackRejection,
            catalogFingerprint: fingerprint
        )
    }
}

private struct SyntaxSchemeSelectionWire: Codable {
    let fallbackIdentifier: String?
    let schemaVersion: Int
    let selectedIdentifier: String?

    init(selection: SyntaxSchemeSelection) {
        fallbackIdentifier = selection.fallbackIdentifier?.rawValue
        schemaVersion = selection.schemaVersion
        selectedIdentifier = selection.selectedIdentifier?.rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.fallbackIdentifier),
            container.contains(.schemaVersion),
            container.contains(.selectedIdentifier)
        else {
            throw SyntaxSchemeCatalogError.malformedPersistence
        }
        fallbackIdentifier = try Self.decodeOptionalString(
            from: container,
            forKey: .fallbackIdentifier
        )
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        selectedIdentifier = try Self.decodeOptionalString(
            from: container,
            forKey: .selectedIdentifier
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let fallbackIdentifier {
            try container.encode(fallbackIdentifier, forKey: .fallbackIdentifier)
        } else {
            try container.encodeNil(forKey: .fallbackIdentifier)
        }
        try container.encode(schemaVersion, forKey: .schemaVersion)
        if let selectedIdentifier {
            try container.encode(selectedIdentifier, forKey: .selectedIdentifier)
        } else {
            try container.encodeNil(forKey: .selectedIdentifier)
        }
    }

    func selection() throws -> SyntaxSchemeSelection {
        SyntaxSchemeSelection(
            selectedIdentifier: try selectedIdentifier.map {
                try SyntaxSchemeIdentifier(rawValue: $0)
            },
            fallbackIdentifier: try fallbackIdentifier.map {
                try SyntaxSchemeIdentifier(rawValue: $0)
            }
        )
    }

    private static func decodeOptionalString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        if try container.decodeNil(forKey: key) { return nil }
        return try container.decode(String.self, forKey: key)
    }

    private enum CodingKeys: String, CodingKey {
        case fallbackIdentifier
        case schemaVersion
        case selectedIdentifier
    }
}

private struct SyntaxSchemeSelectionVersionWire: Decodable {
    let schemaVersion: Int
}

private enum SyntaxSchemeCatalogValidation {
    static func checkCancellation() throws {
        if Task.isCancelled { throw SyntaxSchemeCatalogError.cancelled }
    }

    static func isValidDisplayName(_ value: String) -> Bool {
        guard !value.isEmpty,
            value == value.precomposedStringWithCanonicalMapping,
            value == value.trimmingCharacters(in: .whitespacesAndNewlines),
            value.contains(where: isVisibleDisplayNameCharacter)
        else {
            return false
        }
        return !value.unicodeScalars.contains {
            CharacterSet.newlines.contains($0)
                || CharacterSet.controlCharacters.contains($0)
                || (0x202A...0x202E).contains($0.value)
                || (0x2066...0x2069).contains($0.value)
                || ($0.properties.isDefaultIgnorableCodePoint
                    && $0.value != 0x200D
                    && $0.value != 0xFE0E
                    && $0.value != 0xFE0F
                    && !(0xE0020...0xE007F).contains($0.value))
        }
    }

    private static func isVisibleDisplayNameCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            !$0.properties.isWhitespace
                && !CharacterSet.controlCharacters.contains($0)
                && !$0.properties.isDefaultIgnorableCodePoint
        }
    }

    static func preflightJSON(
        _ data: Data,
        limits: SyntaxSchemeCatalogLimits
    ) throws {
        var budget = SyntaxSchemeCatalogWorkBudget(limits: limits)
        var expectedClosings: [UInt8] = []
        expectedClosings.reserveCapacity(limits.maximumJSONDepth)
        var inString = false
        var escaped = false

        for byte in data {
            try budget.consume()
            guard byte <= 0x7F else {
                throw SyntaxSchemeCatalogError.malformedPersistence
            }
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }
            switch byte {
            case 0x22:
                inString = true
            case 0x7B:
                expectedClosings.append(0x7D)
            case 0x5B:
                expectedClosings.append(0x5D)
            case 0x7D, 0x5D:
                guard expectedClosings.popLast() == byte else {
                    throw SyntaxSchemeCatalogError.malformedPersistence
                }
            default:
                break
            }
            guard expectedClosings.count <= limits.maximumJSONDepth else {
                throw SyntaxSchemeCatalogError.jsonTooDeep(
                    maximumDepth: limits.maximumJSONDepth
                )
            }
        }
        guard !inString, !escaped, expectedClosings.isEmpty else {
            throw SyntaxSchemeCatalogError.malformedPersistence
        }
    }
}

private struct SyntaxSchemeCatalogWorkBudget {
    let limits: SyntaxSchemeCatalogLimits
    private(set) var consumed = 0

    init(limits: SyntaxSchemeCatalogLimits) {
        self.limits = limits
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            throw SyntaxSchemeCatalogError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let addition = consumed.addingReportingOverflow(amount)
        guard !addition.overflow, addition.partialValue <= limits.maximumWorkUnits else {
            throw SyntaxSchemeCatalogError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let previous = consumed
        consumed = addition.partialValue
        if previous / limits.cancellationCheckInterval
            != consumed / limits.cancellationCheckInterval
        {
            try SyntaxSchemeCatalogValidation.checkCancellation()
        }
    }
}

private func syntaxSchemeCatalogSorted(
    _ values: [SyntaxScheme],
    budget: inout SyntaxSchemeCatalogWorkBudget
) throws -> [SyntaxScheme] {
    guard values.count > 1 else {
        try SyntaxSchemeCatalogValidation.checkCancellation()
        return values
    }

    var source = values
    var destination = values
    var width = 1
    while width < source.count {
        var lower = 0
        while lower < source.count {
            let middle = min(lower + width, source.count)
            let upper = min(middle + width, source.count)
            var left = lower
            var right = middle
            var output = lower
            while left < middle || right < upper {
                try budget.consume()
                if right == upper || (left < middle && source[left].id < source[right].id) {
                    destination[output] = source[left]
                    left += 1
                } else {
                    destination[output] = source[right]
                    right += 1
                }
                output += 1
            }
            lower = upper
        }
        swap(&source, &destination)
        width = width > source.count / 2 ? source.count : width * 2
    }
    try SyntaxSchemeCatalogValidation.checkCancellation()
    return source
}
