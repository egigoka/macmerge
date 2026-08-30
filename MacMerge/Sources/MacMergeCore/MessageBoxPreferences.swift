import Foundation

/// Stable persistence identity for one message. Values use an ASCII token grammar so they remain
/// independent of localized copy and UI implementation details.
public struct MessageBoxIdentifier: Codable, Equatable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 128

    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateMessageBoxToken(rawValue, maximumUTF8Bytes: Self.maximumUTF8Bytes)
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Stable identity for one result produced by a message-box button.
public struct MessageBoxOutcomeIdentifier: Codable, Equatable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 64

    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateMessageBoxToken(rawValue, maximumUTF8Bytes: Self.maximumUTF8Bytes)
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Lookup token interpreted by the localization layer. It is not user-visible copy.
public struct MessageBoxLocalizationToken: Codable, Equatable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 256

    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateMessageBoxToken(rawValue, maximumUTF8Bytes: Self.maximumUTF8Bytes)
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Stable accessibility identity interpreted by the UI layer.
public struct MessageBoxAccessibilityToken: Codable, Equatable, Hashable, Sendable {
    public static let maximumUTF8Bytes = 256

    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateMessageBoxToken(rawValue, maximumUTF8Bytes: Self.maximumUTF8Bytes)
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Safety classification is authoritative. UI wording never makes an unsafe prompt suppressible.
public enum MessageBoxCategory: String, CaseIterable, Equatable, Hashable, Sendable {
    case informational
    case nonDestructive
    case destructive
    case security
    case dataLoss
    case error

    public var permanentlyForbidsSuppression: Bool {
        switch self {
        case .informational, .nonDestructive:
            false
        case .destructive, .security, .dataLoss, .error:
            true
        }
    }
}

public enum MessageBoxButtonRole: String, CaseIterable, Equatable, Hashable, Sendable {
    case normal
    case cancel
    case destructive
}

/// Localization and accessibility metadata needed to render one button.
public struct MessageBoxButton: Equatable, Hashable, Sendable {
    public let outcome: MessageBoxOutcomeIdentifier
    public let role: MessageBoxButtonRole
    public let titleLocalizationToken: MessageBoxLocalizationToken
    public let accessibilityToken: MessageBoxAccessibilityToken

    public init(
        outcome: MessageBoxOutcomeIdentifier,
        role: MessageBoxButtonRole = .normal,
        titleLocalizationToken: MessageBoxLocalizationToken,
        accessibilityToken: MessageBoxAccessibilityToken
    ) {
        self.outcome = outcome
        self.role = role
        self.titleLocalizationToken = titleLocalizationToken
        self.accessibilityToken = accessibilityToken
    }
}

/// UI-independent metadata for message copy, accessibility, and an optional suppression control.
public struct MessageBoxMetadata: Equatable, Hashable, Sendable {
    public let titleLocalizationToken: MessageBoxLocalizationToken
    public let messageLocalizationToken: MessageBoxLocalizationToken
    public let accessibilityToken: MessageBoxAccessibilityToken
    public let suppressionLocalizationToken: MessageBoxLocalizationToken?
    public let suppressionAccessibilityToken: MessageBoxAccessibilityToken?

    public init(
        titleLocalizationToken: MessageBoxLocalizationToken,
        messageLocalizationToken: MessageBoxLocalizationToken,
        accessibilityToken: MessageBoxAccessibilityToken,
        suppressionLocalizationToken: MessageBoxLocalizationToken? = nil,
        suppressionAccessibilityToken: MessageBoxAccessibilityToken? = nil
    ) {
        self.titleLocalizationToken = titleLocalizationToken
        self.messageLocalizationToken = messageLocalizationToken
        self.accessibilityToken = accessibilityToken
        self.suppressionLocalizationToken = suppressionLocalizationToken
        self.suppressionAccessibilityToken = suppressionAccessibilityToken
    }
}

/// Complete contract for one message box. Button order remains presentation order.
public struct MessageBoxDefinition: Equatable, Hashable, Sendable {
    public static let hardMaximumOutcomeCount = 16

    public let identifier: MessageBoxIdentifier
    public let category: MessageBoxCategory
    public let metadata: MessageBoxMetadata
    public let buttons: [MessageBoxButton]
    public let defaultOutcome: MessageBoxOutcomeIdentifier
    public let cancellationOutcome: MessageBoxOutcomeIdentifier?
    public let allowsSuppression: Bool

    public var availableOutcomes: [MessageBoxOutcomeIdentifier] {
        buttons.map(\.outcome)
    }

    public var defaultButton: MessageBoxButton {
        buttons.first { $0.outcome == defaultOutcome }!
    }

    public var cancellationButton: MessageBoxButton? {
        guard let cancellationOutcome else { return nil }
        return buttons.first { $0.outcome == cancellationOutcome }
    }

    public var canBeSuppressed: Bool {
        allowsSuppression
            && !category.permanentlyForbidsSuppression
            && !buttons.contains(where: { $0.role == .destructive })
    }

    public init(
        identifier: MessageBoxIdentifier,
        category: MessageBoxCategory,
        metadata: MessageBoxMetadata,
        buttons: [MessageBoxButton],
        defaultOutcome: MessageBoxOutcomeIdentifier,
        cancellationOutcome: MessageBoxOutcomeIdentifier? = nil,
        allowsSuppression: Bool = false
    ) throws {
        self.identifier = identifier
        self.category = category
        self.metadata = metadata
        self.buttons = buttons
        self.defaultOutcome = defaultOutcome
        self.cancellationOutcome = cancellationOutcome
        self.allowsSuppression = allowsSuppression
        try validate()
    }

    public func button(for outcome: MessageBoxOutcomeIdentifier) -> MessageBoxButton? {
        buttons.first { $0.outcome == outcome }
    }

    public func validate() throws {
        guard !buttons.isEmpty else {
            throw MessageBoxPreferencesError.messageHasNoOutcomes(identifier)
        }
        guard buttons.count <= Self.hardMaximumOutcomeCount else {
            throw MessageBoxPreferencesError.tooManyOutcomes(
                message: identifier,
                maximumCount: Self.hardMaximumOutcomeCount
            )
        }

        var outcomes: Set<MessageBoxOutcomeIdentifier> = []
        var accessibilityTokens: Set<MessageBoxAccessibilityToken> = []
        for button in buttons {
            guard outcomes.insert(button.outcome).inserted else {
                throw MessageBoxPreferencesError.duplicateOutcome(
                    message: identifier,
                    outcome: button.outcome
                )
            }
            guard accessibilityTokens.insert(button.accessibilityToken).inserted else {
                throw MessageBoxPreferencesError.duplicateButtonAccessibilityToken(
                    message: identifier,
                    token: button.accessibilityToken
                )
            }
        }
        guard outcomes.contains(defaultOutcome) else {
            throw MessageBoxPreferencesError.defaultOutcomeUnavailable(
                message: identifier,
                outcome: defaultOutcome
            )
        }
        guard defaultButton.role != .destructive else {
            throw MessageBoxPreferencesError.destructiveDefaultOutcome(
                message: identifier,
                outcome: defaultOutcome
            )
        }
        if let cancellationOutcome {
            guard let button = button(for: cancellationOutcome) else {
                throw MessageBoxPreferencesError.cancellationOutcomeUnavailable(
                    message: identifier,
                    outcome: cancellationOutcome
                )
            }
            guard button.role == .cancel else {
                throw MessageBoxPreferencesError.cancellationOutcomeIsNotCancel(
                    message: identifier,
                    outcome: cancellationOutcome
                )
            }
        }
        if let unmatchedCancelButton = buttons.first(where: {
            $0.role == .cancel && $0.outcome != cancellationOutcome
        }) {
            throw MessageBoxPreferencesError.unexpectedCancelButton(
                message: identifier,
                outcome: unmatchedCancelButton.outcome
            )
        }

        let hasSuppressionLocalization = metadata.suppressionLocalizationToken != nil
        let hasSuppressionAccessibility = metadata.suppressionAccessibilityToken != nil
        guard hasSuppressionLocalization == hasSuppressionAccessibility else {
            throw MessageBoxPreferencesError.incompleteSuppressionMetadata(identifier)
        }
        if allowsSuppression {
            guard hasSuppressionLocalization else {
                throw MessageBoxPreferencesError.missingSuppressionMetadata(identifier)
            }
            guard !category.permanentlyForbidsSuppression,
                !buttons.contains(where: { $0.role == .destructive })
            else {
                throw MessageBoxPreferencesError.suppressionForbidden(
                    message: identifier,
                    category: category
                )
            }
        } else if hasSuppressionLocalization {
            throw MessageBoxPreferencesError.unexpectedSuppressionMetadata(identifier)
        }
    }
}

/// Runtime and persistence bounds. Callers may tighten, but cannot exceed, hard limits.
public struct MessageBoxPreferencesLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumDefinitionCount = 256
    public static let hardMaximumOutcomeCountPerMessage = MessageBoxDefinition.hardMaximumOutcomeCount
    public static let hardMaximumRememberedOutcomeCount = 256
    public static let hardMaximumEncodedBytes = 64 * 1024

    public static let `default` = MessageBoxPreferencesLimits(
        validatedMaximumDefinitionCount: 128,
        maximumOutcomeCountPerMessage: 8,
        maximumRememberedOutcomeCount: 128,
        maximumEncodedBytes: 32 * 1024
    )

    public let maximumDefinitionCount: Int
    public let maximumOutcomeCountPerMessage: Int
    public let maximumRememberedOutcomeCount: Int
    public let maximumEncodedBytes: Int

    public init(
        maximumDefinitionCount: Int = 128,
        maximumOutcomeCountPerMessage: Int = 8,
        maximumRememberedOutcomeCount: Int = 128,
        maximumEncodedBytes: Int = 32 * 1024
    ) throws {
        guard (1...Self.hardMaximumDefinitionCount).contains(maximumDefinitionCount) else {
            throw MessageBoxPreferencesError.invalidLimit(
                name: "maximumDefinitionCount",
                value: maximumDefinitionCount
            )
        }
        guard
            (1...Self.hardMaximumOutcomeCountPerMessage).contains(
                maximumOutcomeCountPerMessage
            )
        else {
            throw MessageBoxPreferencesError.invalidLimit(
                name: "maximumOutcomeCountPerMessage",
                value: maximumOutcomeCountPerMessage
            )
        }
        guard
            (1...Self.hardMaximumRememberedOutcomeCount).contains(
                maximumRememberedOutcomeCount
            ),
            maximumRememberedOutcomeCount <= maximumDefinitionCount
        else {
            throw MessageBoxPreferencesError.invalidLimit(
                name: "maximumRememberedOutcomeCount",
                value: maximumRememberedOutcomeCount
            )
        }
        guard (256...Self.hardMaximumEncodedBytes).contains(maximumEncodedBytes) else {
            throw MessageBoxPreferencesError.invalidLimit(
                name: "maximumEncodedBytes",
                value: maximumEncodedBytes
            )
        }

        self.maximumDefinitionCount = maximumDefinitionCount
        self.maximumOutcomeCountPerMessage = maximumOutcomeCountPerMessage
        self.maximumRememberedOutcomeCount = maximumRememberedOutcomeCount
        self.maximumEncodedBytes = maximumEncodedBytes
    }

    private init(
        validatedMaximumDefinitionCount: Int,
        maximumOutcomeCountPerMessage: Int,
        maximumRememberedOutcomeCount: Int,
        maximumEncodedBytes: Int
    ) {
        maximumDefinitionCount = validatedMaximumDefinitionCount
        self.maximumOutcomeCountPerMessage = maximumOutcomeCountPerMessage
        self.maximumRememberedOutcomeCount = maximumRememberedOutcomeCount
        self.maximumEncodedBytes = maximumEncodedBytes
    }
}

/// Validated definitions known by one application version.
public struct MessageBoxCatalog: Equatable, Sendable {
    public let definitions: [MessageBoxDefinition]
    public let limits: MessageBoxPreferencesLimits

    public init(
        definitions: [MessageBoxDefinition],
        limits: MessageBoxPreferencesLimits = .default,
        cancellationCheck: @Sendable () throws -> Void = MessageBoxPreferences.checkCancellation
    ) throws {
        try cancellationCheck()
        guard definitions.count <= limits.maximumDefinitionCount else {
            throw MessageBoxPreferencesError.tooManyDefinitions(
                maximumCount: limits.maximumDefinitionCount
            )
        }

        let sortedDefinitions = definitions.sorted {
            $0.identifier.rawValue < $1.identifier.rawValue
        }
        for (index, definition) in sortedDefinitions.enumerated() {
            try cancellationCheck()
            try definition.validate()
            guard definition.buttons.count <= limits.maximumOutcomeCountPerMessage else {
                throw MessageBoxPreferencesError.tooManyOutcomes(
                    message: definition.identifier,
                    maximumCount: limits.maximumOutcomeCountPerMessage
                )
            }
            if index > sortedDefinitions.startIndex,
                sortedDefinitions[index - 1].identifier == definition.identifier
            {
                throw MessageBoxPreferencesError.duplicateMessageIdentifier(
                    definition.identifier
                )
            }
        }
        try cancellationCheck()

        self.definitions = sortedDefinitions
        self.limits = limits
    }

    public func definition(for identifier: MessageBoxIdentifier) -> MessageBoxDefinition? {
        definitions.first { $0.identifier == identifier }
    }
}

public enum MessageBoxPresentationDecision: Equatable, Sendable {
    case present
    case useRememberedOutcome(MessageBoxOutcomeIdentifier)

    public var requiresPresentation: Bool {
        if case .present = self { return true }
        return false
    }
}

/// Unsupported schemas are never guessed. No historic schema exists yet, so the only explicit
/// migration choice is rejecting the data or resetting this preference domain.
public enum MessageBoxPreferencesMigrationPolicy: Equatable, Sendable {
    case rejectUnsupportedSchema
    case resetToDefaults
}

/// Remembered non-destructive message outcomes. This type contains no AppKit or SwiftUI state.
public struct MessageBoxPreferences: Equatable, Sendable {
    public typealias Identifier = MessageBoxIdentifier
    public typealias Outcome = MessageBoxOutcomeIdentifier
    public typealias Definition = MessageBoxDefinition

    public static let currentSchemaVersion = 1

    public let limits: MessageBoxPreferencesLimits
    private var rememberedOutcomes: [MessageBoxIdentifier: MessageBoxOutcomeIdentifier]

    public init(limits: MessageBoxPreferencesLimits = .default) {
        self.limits = limits
        rememberedOutcomes = [:]
    }

    public var count: Int { rememberedOutcomes.count }
    public var isEmpty: Bool { rememberedOutcomes.isEmpty }

    public var rememberedMessageIdentifiers: [MessageBoxIdentifier] {
        rememberedOutcomes.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Returns a remembered result only if the current definition still permits suppression and
    /// still offers that exact non-destructive result.
    public func rememberedOutcome(
        for identifier: MessageBoxIdentifier,
        in catalog: MessageBoxCatalog
    ) -> MessageBoxOutcomeIdentifier? {
        guard let definition = catalog.definition(for: identifier) else { return nil }
        return rememberedOutcome(forTrustedDefinition: definition)
    }

    private func rememberedOutcome(
        forTrustedDefinition definition: MessageBoxDefinition
    ) -> MessageBoxOutcomeIdentifier? {
        guard definition.canBeSuppressed,
            let outcome = rememberedOutcomes[definition.identifier],
            let button = definition.button(for: outcome),
            button.role != .destructive
        else {
            return nil
        }
        return outcome
    }

    public func decision(
        for identifier: MessageBoxIdentifier,
        in catalog: MessageBoxCatalog
    ) -> MessageBoxPresentationDecision {
        guard let outcome = rememberedOutcome(for: identifier, in: catalog) else {
            return .present
        }
        return .useRememberedOutcome(outcome)
    }

    public func isSuppressed(
        _ identifier: MessageBoxIdentifier,
        in catalog: MessageBoxCatalog
    ) -> Bool {
        rememberedOutcome(for: identifier, in: catalog) != nil
    }

    /// Records one result only for a definition that explicitly opts into safe suppression.
    public mutating func remember(
        _ outcome: MessageBoxOutcomeIdentifier,
        for identifier: MessageBoxIdentifier,
        in catalog: MessageBoxCatalog
    ) throws {
        guard let definition = catalog.definition(for: identifier) else {
            throw MessageBoxPreferencesError.unknownMessageIdentifier(identifier)
        }
        try remember(
            outcome,
            forTrustedDefinition: definition,
            maximumRememberedOutcomeCount: min(
                limits.maximumRememberedOutcomeCount,
                catalog.limits.maximumRememberedOutcomeCount
            )
        )
    }

    private mutating func remember(
        _ outcome: MessageBoxOutcomeIdentifier,
        forTrustedDefinition definition: MessageBoxDefinition,
        maximumRememberedOutcomeCount: Int
    ) throws {
        try Self.validateRememberedOutcome(outcome, for: definition)
        if rememberedOutcomes[definition.identifier] == nil {
            guard rememberedOutcomes.count < maximumRememberedOutcomeCount else {
                throw MessageBoxPreferencesError.tooManyRememberedOutcomes(
                    maximumCount: maximumRememberedOutcomeCount
                )
            }
        }
        rememberedOutcomes[definition.identifier] = outcome
    }

    /// Validates every response. `suppressFutureMessages == false` leaves preferences unchanged.
    public mutating func record(
        _ outcome: MessageBoxOutcomeIdentifier,
        suppressFutureMessages: Bool,
        for identifier: MessageBoxIdentifier,
        in catalog: MessageBoxCatalog
    ) throws {
        guard let definition = catalog.definition(for: identifier) else {
            throw MessageBoxPreferencesError.unknownMessageIdentifier(identifier)
        }
        guard let button = definition.button(for: outcome) else {
            throw MessageBoxPreferencesError.outcomeUnavailable(
                message: definition.identifier,
                outcome: outcome
            )
        }
        guard suppressFutureMessages else { return }
        guard button.role != .destructive else {
            throw MessageBoxPreferencesError.destructiveOutcomeCannotBeRemembered(
                message: definition.identifier,
                outcome: outcome
            )
        }
        try remember(
            outcome,
            forTrustedDefinition: definition,
            maximumRememberedOutcomeCount: min(
                limits.maximumRememberedOutcomeCount,
                catalog.limits.maximumRememberedOutcomeCount
            )
        )
    }

    @discardableResult
    public mutating func reset(_ identifier: MessageBoxIdentifier) -> Bool {
        rememberedOutcomes.removeValue(forKey: identifier) != nil
    }

    @discardableResult
    public mutating func resetAll() -> Int {
        let removedCount = rememberedOutcomes.count
        rememberedOutcomes.removeAll(keepingCapacity: false)
        return removedCount
    }

    /// Verifies all remembered values against the complete catalog used by the current build.
    public func validate(
        against catalog: MessageBoxCatalog,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws {
        try cancellationCheck()
        guard rememberedOutcomes.count <= limits.maximumRememberedOutcomeCount,
            rememberedOutcomes.count <= catalog.limits.maximumRememberedOutcomeCount
        else {
            throw MessageBoxPreferencesError.tooManyRememberedOutcomes(
                maximumCount: min(
                    limits.maximumRememberedOutcomeCount,
                    catalog.limits.maximumRememberedOutcomeCount
                )
            )
        }
        for identifier in rememberedMessageIdentifiers {
            try cancellationCheck()
            guard let definition = catalog.definition(for: identifier) else {
                throw MessageBoxPreferencesError.unknownMessageIdentifier(identifier)
            }
            guard let outcome = rememberedOutcomes[identifier] else { continue }
            try Self.validateRememberedOutcome(outcome, for: definition)
        }
        try cancellationCheck()
    }

    /// Compact deterministic JSON. Entries and object keys always use stable lexical ordering.
    public func encodedData(
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> Data {
        try encodedData(
            maximumEncodedBytes: limits.maximumEncodedBytes,
            cancellationCheck: cancellationCheck
        )
    }

    /// Encodes only values accepted by `catalog`, bounded by both persistence byte limits.
    public func encodedData(
        against catalog: MessageBoxCatalog,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> Data {
        try validate(against: catalog, cancellationCheck: cancellationCheck)
        return try encodedData(
            maximumEncodedBytes: min(
                limits.maximumEncodedBytes,
                catalog.limits.maximumEncodedBytes
            ),
            cancellationCheck: cancellationCheck
        )
    }

    private func encodedData(
        maximumEncodedBytes: Int,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> Data {
        try cancellationCheck()
        let entries = rememberedMessageIdentifiers.compactMap { identifier -> WireEntry? in
            guard let outcome = rememberedOutcomes[identifier] else { return nil }
            return WireEntry(messageIdentifier: identifier, outcome: outcome)
        }
        let document = WireDocument(
            schemaVersion: Self.currentSchemaVersion,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try cancellationCheck()
        guard data.count <= maximumEncodedBytes else {
            throw MessageBoxPreferencesError.encodedDataTooLarge(
                maximumBytes: maximumEncodedBytes
            )
        }
        return data
    }

    /// Strict bounded decoding. Current-schema unknown fields and duplicate JSON keys are rejected.
    public static func decode(
        from data: Data,
        catalog: MessageBoxCatalog,
        migrationPolicy: MessageBoxPreferencesMigrationPolicy = .rejectUnsupportedSchema,
        cancellationCheck: @escaping @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> MessageBoxPreferences {
        try cancellationCheck()
        guard data.count <= catalog.limits.maximumEncodedBytes else {
            throw MessageBoxPreferencesError.encodedDataTooLarge(
                maximumBytes: catalog.limits.maximumEncodedBytes
            )
        }
        let snapshot = immutableSnapshot(of: data)
        guard snapshot.count <= catalog.limits.maximumEncodedBytes else {
            throw MessageBoxPreferencesError.encodedDataTooLarge(
                maximumBytes: catalog.limits.maximumEncodedBytes
            )
        }
        var scanner = MessageBoxJSONScanner(
            data: snapshot,
            cancellationCheck: cancellationCheck
        )
        try scanner.validate()
        let schemaVersion = try JSONDecoder().decode(
            SchemaProbe.self,
            from: snapshot
        ).schemaVersion
        guard schemaVersion == Self.currentSchemaVersion else {
            switch migrationPolicy {
            case .rejectUnsupportedSchema:
                throw MessageBoxPreferencesError.unsupportedSchemaVersion(schemaVersion)
            case .resetToDefaults:
                try cancellationCheck()
                return MessageBoxPreferences(limits: catalog.limits)
            }
        }

        let document = try JSONDecoder().decode(WireDocument.self, from: snapshot)
        guard document.entries.count <= catalog.limits.maximumRememberedOutcomeCount else {
            throw MessageBoxPreferencesError.tooManyRememberedOutcomes(
                maximumCount: catalog.limits.maximumRememberedOutcomeCount
            )
        }
        var outcomes: [MessageBoxIdentifier: MessageBoxOutcomeIdentifier] = [:]
        outcomes.reserveCapacity(document.entries.count)
        for entry in document.entries {
            try cancellationCheck()
            guard outcomes.updateValue(entry.outcome, forKey: entry.messageIdentifier) == nil else {
                throw MessageBoxPreferencesError.duplicateRememberedMessage(
                    entry.messageIdentifier
                )
            }
            guard let definition = catalog.definition(for: entry.messageIdentifier) else {
                throw MessageBoxPreferencesError.unknownMessageIdentifier(
                    entry.messageIdentifier
                )
            }
            try validateRememberedOutcome(entry.outcome, for: definition)
        }
        try cancellationCheck()

        var preferences = MessageBoxPreferences(limits: catalog.limits)
        preferences.rememberedOutcomes = outcomes
        return preferences
    }

    public static func restored(
        from data: Data?,
        catalog: MessageBoxCatalog,
        migrationPolicy: MessageBoxPreferencesMigrationPolicy = .rejectUnsupportedSchema,
        cancellationCheck: @escaping @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> MessageBoxPreferences {
        try cancellationCheck()
        guard let data else { return MessageBoxPreferences(limits: catalog.limits) }
        return try decode(
            from: data,
            catalog: catalog,
            migrationPolicy: migrationPolicy,
            cancellationCheck: cancellationCheck
        )
    }

    public static func checkCancellation() throws {
        try Task<Never, Never>.checkCancellation()
    }

    private static func validateRememberedOutcome(
        _ outcome: MessageBoxOutcomeIdentifier,
        for definition: MessageBoxDefinition
    ) throws {
        guard definition.canBeSuppressed else {
            throw MessageBoxPreferencesError.messageDoesNotAllowSuppression(
                definition.identifier
            )
        }
        guard let button = definition.button(for: outcome) else {
            throw MessageBoxPreferencesError.outcomeUnavailable(
                message: definition.identifier,
                outcome: outcome
            )
        }
        guard button.role != .destructive else {
            throw MessageBoxPreferencesError.destructiveOutcomeCannotBeRemembered(
                message: definition.identifier,
                outcome: outcome
            )
        }
    }

    private static func immutableSnapshot(of data: Data) -> Data {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return Data() }
            return Data(bytes: baseAddress, count: bytes.count)
        }
    }
}

public enum MessageBoxPreferencesError: Error, Equatable, LocalizedError, Sendable {
    case invalidToken(String)
    case invalidLimit(name: String, value: Int)
    case tooManyDefinitions(maximumCount: Int)
    case duplicateMessageIdentifier(MessageBoxIdentifier)
    case messageHasNoOutcomes(MessageBoxIdentifier)
    case tooManyOutcomes(message: MessageBoxIdentifier, maximumCount: Int)
    case duplicateOutcome(message: MessageBoxIdentifier, outcome: MessageBoxOutcomeIdentifier)
    case duplicateButtonAccessibilityToken(
        message: MessageBoxIdentifier,
        token: MessageBoxAccessibilityToken
    )
    case defaultOutcomeUnavailable(
        message: MessageBoxIdentifier,
        outcome: MessageBoxOutcomeIdentifier
    )
    case destructiveDefaultOutcome(
        message: MessageBoxIdentifier,
        outcome: MessageBoxOutcomeIdentifier
    )
    case cancellationOutcomeUnavailable(
        message: MessageBoxIdentifier,
        outcome: MessageBoxOutcomeIdentifier
    )
    case cancellationOutcomeIsNotCancel(
        message: MessageBoxIdentifier,
        outcome: MessageBoxOutcomeIdentifier
    )
    case unexpectedCancelButton(
        message: MessageBoxIdentifier,
        outcome: MessageBoxOutcomeIdentifier
    )
    case incompleteSuppressionMetadata(MessageBoxIdentifier)
    case missingSuppressionMetadata(MessageBoxIdentifier)
    case unexpectedSuppressionMetadata(MessageBoxIdentifier)
    case suppressionForbidden(message: MessageBoxIdentifier, category: MessageBoxCategory)
    case messageDoesNotAllowSuppression(MessageBoxIdentifier)
    case outcomeUnavailable(
        message: MessageBoxIdentifier,
        outcome: MessageBoxOutcomeIdentifier
    )
    case destructiveOutcomeCannotBeRemembered(
        message: MessageBoxIdentifier,
        outcome: MessageBoxOutcomeIdentifier
    )
    case tooManyRememberedOutcomes(maximumCount: Int)
    case duplicateRememberedMessage(MessageBoxIdentifier)
    case unknownMessageIdentifier(MessageBoxIdentifier)
    case encodedDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case invalidJSON
    case jsonNestingTooDeep(maximumDepth: Int)
    case jsonContainerTooLarge(maximumElements: Int)
    case tooManyJSONValues(maximumValues: Int)
    case jsonStringTooLarge(maximumBytes: Int)
    case jsonNumberTooLarge(maximumBytes: Int)
    case duplicateJSONKey(String)
    case unknownField(String)

    public var errorDescription: String? {
        switch self {
        case .invalidToken(let value):
            "Message-box identifiers and metadata must be bounded ASCII tokens: \(value)."
        case .invalidLimit(let name, let value):
            "Invalid message-box limit \(name): \(value)."
        case .tooManyDefinitions(let maximumCount):
            "Message-box catalog cannot exceed \(maximumCount) definitions."
        case .duplicateMessageIdentifier(let identifier):
            "Message-box identifier appears more than once: \(identifier.rawValue)."
        case .messageHasNoOutcomes(let identifier):
            "Message box has no available outcome: \(identifier.rawValue)."
        case .tooManyOutcomes(let message, let maximumCount):
            "Message box \(message.rawValue) cannot exceed \(maximumCount) outcomes."
        case .duplicateOutcome(let message, let outcome):
            "Message box \(message.rawValue) repeats outcome \(outcome.rawValue)."
        case .duplicateButtonAccessibilityToken(let message, let token):
            "Message box \(message.rawValue) repeats button accessibility token \(token.rawValue)."
        case .defaultOutcomeUnavailable(let message, let outcome):
            "Default outcome \(outcome.rawValue) is unavailable for \(message.rawValue)."
        case .destructiveDefaultOutcome(let message, let outcome):
            "Destructive outcome \(outcome.rawValue) cannot be the default for \(message.rawValue)."
        case .cancellationOutcomeUnavailable(let message, let outcome):
            "Cancellation outcome \(outcome.rawValue) is unavailable for \(message.rawValue)."
        case .cancellationOutcomeIsNotCancel(let message, let outcome):
            "Cancellation outcome \(outcome.rawValue) is not a cancel button for \(message.rawValue)."
        case .unexpectedCancelButton(let message, let outcome):
            "Cancel button \(outcome.rawValue) is not the cancellation outcome for \(message.rawValue)."
        case .incompleteSuppressionMetadata(let identifier):
            "Message box \(identifier.rawValue) has incomplete suppression metadata."
        case .missingSuppressionMetadata(let identifier):
            "Suppressible message box \(identifier.rawValue) requires suppression metadata."
        case .unexpectedSuppressionMetadata(let identifier):
            "Non-suppressible message box \(identifier.rawValue) cannot expose suppression metadata."
        case .suppressionForbidden(let message, let category):
            "Message box \(message.rawValue) cannot suppress \(category.rawValue) prompts."
        case .messageDoesNotAllowSuppression(let identifier):
            "Message box does not explicitly allow suppression: \(identifier.rawValue)."
        case .outcomeUnavailable(let message, let outcome):
            "Outcome \(outcome.rawValue) is unavailable for \(message.rawValue)."
        case .destructiveOutcomeCannotBeRemembered(let message, let outcome):
            "Destructive outcome \(outcome.rawValue) cannot be remembered for \(message.rawValue)."
        case .tooManyRememberedOutcomes(let maximumCount):
            "Message-box preferences cannot exceed \(maximumCount) remembered outcomes."
        case .duplicateRememberedMessage(let identifier):
            "Message-box preferences repeat \(identifier.rawValue)."
        case .unknownMessageIdentifier(let identifier):
            "Unknown message-box identifier: \(identifier.rawValue)."
        case .encodedDataTooLarge(let maximumBytes):
            "Message-box preferences exceed the \(maximumBytes)-byte persistence limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported message-box preferences schema version: \(version)."
        case .invalidJSON:
            "Message-box preferences are not valid strict JSON."
        case .jsonNestingTooDeep(let maximumDepth):
            "Message-box preferences exceed the \(maximumDepth)-level JSON nesting limit."
        case .jsonContainerTooLarge(let maximumElements):
            "A message-box JSON container exceeds \(maximumElements) elements."
        case .tooManyJSONValues(let maximumValues):
            "Message-box preferences exceed \(maximumValues) JSON values."
        case .jsonStringTooLarge(let maximumBytes):
            "A message-box JSON string exceeds \(maximumBytes) UTF-8 bytes."
        case .jsonNumberTooLarge(let maximumBytes):
            "A message-box JSON number exceeds \(maximumBytes) bytes."
        case .duplicateJSONKey(let key):
            "Message-box preferences repeat JSON key \(key)."
        case .unknownField(let field):
            "Unknown message-box preferences field: \(field)."
        }
    }
}

private struct MessageBoxCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

private struct SchemaProbe: Decodable {
    let schemaVersion: Int
}

private struct WireDocument: Codable {
    static let fields: Set<String> = ["schemaVersion", "rememberedOutcomes"]

    let schemaVersion: Int
    let entries: [WireEntry]

    init(schemaVersion: Int, entries: [WireEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MessageBoxCodingKey.self)
        try rejectUnknownMessageBoxFields(container, allowed: Self.fields)
        schemaVersion = try container.decode(
            Int.self,
            forKey: MessageBoxCodingKey("schemaVersion")
        )
        var entriesContainer = try container.nestedUnkeyedContainer(
            forKey: MessageBoxCodingKey("rememberedOutcomes")
        )
        if let count = entriesContainer.count,
            count > MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount
        {
            throw MessageBoxPreferencesError.tooManyRememberedOutcomes(
                maximumCount: MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount
            )
        }
        var entries: [WireEntry] = []
        entries.reserveCapacity(
            min(
                entriesContainer.count ?? 0,
                MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount
            )
        )
        while !entriesContainer.isAtEnd {
            guard
                entries.count
                    < MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount
            else {
                throw MessageBoxPreferencesError.tooManyRememberedOutcomes(
                    maximumCount: MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount
                )
            }
            entries.append(try entriesContainer.decode(WireEntry.self))
        }
        self.entries = entries
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: MessageBoxCodingKey.self)
        try container.encode(
            schemaVersion,
            forKey: MessageBoxCodingKey("schemaVersion")
        )
        try container.encode(
            entries,
            forKey: MessageBoxCodingKey("rememberedOutcomes")
        )
    }
}

private struct WireEntry: Codable {
    static let fields: Set<String> = ["messageIdentifier", "outcome"]

    let messageIdentifier: MessageBoxIdentifier
    let outcome: MessageBoxOutcomeIdentifier

    init(
        messageIdentifier: MessageBoxIdentifier,
        outcome: MessageBoxOutcomeIdentifier
    ) {
        self.messageIdentifier = messageIdentifier
        self.outcome = outcome
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MessageBoxCodingKey.self)
        try rejectUnknownMessageBoxFields(container, allowed: Self.fields)
        messageIdentifier = try container.decode(
            MessageBoxIdentifier.self,
            forKey: MessageBoxCodingKey("messageIdentifier")
        )
        outcome = try container.decode(
            MessageBoxOutcomeIdentifier.self,
            forKey: MessageBoxCodingKey("outcome")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: MessageBoxCodingKey.self)
        try container.encode(
            messageIdentifier,
            forKey: MessageBoxCodingKey("messageIdentifier")
        )
        try container.encode(outcome, forKey: MessageBoxCodingKey("outcome"))
    }
}

private func rejectUnknownMessageBoxFields<Value>(
    _ container: KeyedDecodingContainer<Value>,
    allowed: Set<String>
) throws where Value: CodingKey {
    if let field = container.allKeys.map(\.stringValue)
        .filter({ !allowed.contains($0) })
        .sorted()
        .first
    {
        throw MessageBoxPreferencesError.unknownField(field)
    }
}

private func validateMessageBoxToken(
    _ value: String,
    maximumUTF8Bytes: Int
) throws {
    let bytes = value.utf8.prefix(maximumUTF8Bytes + 1)
    guard let firstByte = bytes.first,
        bytes.count <= maximumUTF8Bytes,
        isMessageBoxASCIIAlphaNumeric(firstByte),
        bytes.allSatisfy({
            isMessageBoxASCIIAlphaNumeric($0)
                || $0 == 0x2D
                || $0 == 0x2E
                || $0 == 0x5F
        })
    else {
        throw MessageBoxPreferencesError.invalidToken(boundedMessageBoxErrorPayload(value))
    }
}

private func boundedMessageBoxErrorPayload(_ value: String) -> String {
    let maximumUTF8Bytes = 128
    let suffix = "..."
    let inspectedBytes = value.utf8.prefix(maximumUTF8Bytes + 1)
    guard inspectedBytes.count > maximumUTF8Bytes else { return value }

    let maximumContentBytes = maximumUTF8Bytes - suffix.utf8.count
    var content = String()
    content.reserveCapacity(maximumContentBytes)
    var contentBytes = 0
    for scalar in value.unicodeScalars {
        let scalarBytes = scalar.utf8.count
        guard scalarBytes <= maximumContentBytes - contentBytes else { break }
        content.unicodeScalars.append(scalar)
        contentBytes += scalarBytes
    }
    return content + suffix
}

private func isMessageBoxASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
        || (0x41...0x5A).contains(byte)
        || (0x61...0x7A).contains(byte)
}

private struct MessageBoxJSONScanner {
    private static let maximumNestingDepth = 8
    private static let maximumContainerElements =
        MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount + 8
    private static let maximumValueCount = 1_024
    private static let maximumStringUTF8Bytes = 256
    private static let maximumTotalStringUTF8Bytes =
        MessageBoxPreferencesLimits.hardMaximumEncodedBytes
    private static let maximumNumberBytes = 32
    private static let cancellationInterval = 1_024

    private let bytes: Data
    private let cancellationCheck: @Sendable () throws -> Void
    private var index = 0
    private var valueCount = 0
    private var totalStringUTF8Bytes = 0
    private var nextCancellationIndex = 0

    init(data: Data, cancellationCheck: @escaping @Sendable () throws -> Void) {
        bytes = data
        self.cancellationCheck = cancellationCheck
    }

    mutating func validate() throws {
        try checkpoint(force: true)
        try skipWhitespace()
        try parseValue(depth: 0)
        try skipWhitespace()
        guard index == bytes.count else { throw MessageBoxPreferencesError.invalidJSON }
        try checkpoint(force: true)
    }

    private mutating func parseValue(depth: Int) throws {
        try checkpoint()
        guard valueCount < Self.maximumValueCount else {
            throw MessageBoxPreferencesError.tooManyJSONValues(
                maximumValues: Self.maximumValueCount
            )
        }
        valueCount += 1
        guard let byte = currentByte else { throw MessageBoxPreferencesError.invalidJSON }
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
            throw MessageBoxPreferencesError.invalidJSON
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        try skipWhitespace()
        if consume(0x7D) { return }

        var elementCount = 0
        var keys: Set<String> = []
        while true {
            try checkpoint()
            try incrementContainerCount(&elementCount)
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw MessageBoxPreferencesError.duplicateJSONKey(key)
            }
            try skipWhitespace()
            guard consume(0x3A) else { throw MessageBoxPreferencesError.invalidJSON }
            try skipWhitespace()
            try parseValue(depth: depth)
            try skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw MessageBoxPreferencesError.invalidJSON }
            try skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        try skipWhitespace()
        if consume(0x5D) { return }

        var elementCount = 0
        while true {
            try checkpoint()
            try incrementContainerCount(&elementCount)
            try parseValue(depth: depth)
            try skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw MessageBoxPreferencesError.invalidJSON }
            try skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        guard consume(0x22) else { throw MessageBoxPreferencesError.invalidJSON }
        while let byte = currentByte {
            try checkpoint()
            switch byte {
            case 0x22:
                index += 1
                let encodedString = Data(bytes[start..<index])
                let decoded: String
                do {
                    decoded = try JSONDecoder().decode(String.self, from: encodedString)
                } catch {
                    throw MessageBoxPreferencesError.invalidJSON
                }
                let count = decoded.utf8.count
                guard count <= Self.maximumStringUTF8Bytes,
                    count <= Self.maximumTotalStringUTF8Bytes - totalStringUTF8Bytes
                else {
                    throw MessageBoxPreferencesError.jsonStringTooLarge(
                        maximumBytes: Self.maximumStringUTF8Bytes
                    )
                }
                totalStringUTF8Bytes += count
                return decoded
            case 0x00...0x1F:
                throw MessageBoxPreferencesError.invalidJSON
            case 0x5C:
                index += 1
                try parseEscape()
            default:
                index += 1
            }
        }
        throw MessageBoxPreferencesError.invalidJSON
    }

    private mutating func parseEscape() throws {
        guard let byte = currentByte else { throw MessageBoxPreferencesError.invalidJSON }
        index += 1
        switch byte {
        case 0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74:
            return
        case 0x75:
            for _ in 0..<4 {
                guard let digit = currentByte, Self.isHexDigit(digit) else {
                    throw MessageBoxPreferencesError.invalidJSON
                }
                index += 1
            }
        default:
            throw MessageBoxPreferencesError.invalidJSON
        }
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = consume(0x2D)
        guard let first = currentByte else { throw MessageBoxPreferencesError.invalidJSON }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw MessageBoxPreferencesError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw MessageBoxPreferencesError.invalidJSON
            }
            repeat {
                try checkpoint()
                index += 1
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw MessageBoxPreferencesError.invalidJSON
            }
            repeat {
                try checkpoint()
                index += 1
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x65) || consume(0x45) {
            _ = consume(0x2B) || consume(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw MessageBoxPreferencesError.invalidJSON
            }
            repeat {
                try checkpoint()
                index += 1
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        guard index - start <= Self.maximumNumberBytes else {
            throw MessageBoxPreferencesError.jsonNumberTooLarge(
                maximumBytes: Self.maximumNumberBytes
            )
        }
    }

    private mutating func validateDepth(_ depth: Int) throws {
        guard depth <= Self.maximumNestingDepth else {
            throw MessageBoxPreferencesError.jsonNestingTooDeep(
                maximumDepth: Self.maximumNestingDepth
            )
        }
    }

    private mutating func incrementContainerCount(_ count: inout Int) throws {
        guard count < Self.maximumContainerElements else {
            throw MessageBoxPreferencesError.jsonContainerTooLarge(
                maximumElements: Self.maximumContainerElements
            )
        }
        count += 1
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else {
            throw MessageBoxPreferencesError.invalidJSON
        }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw MessageBoxPreferencesError.invalidJSON }
            index += 1
        }
    }

    private mutating func checkpoint(force: Bool = false) throws {
        guard force || index >= nextCancellationIndex else { return }
        try cancellationCheck()
        nextCancellationIndex = index + Self.cancellationInterval
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            try checkpoint()
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

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x46).contains(byte)
            || (0x61...0x66).contains(byte)
    }
}
