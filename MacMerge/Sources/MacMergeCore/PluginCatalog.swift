import CryptoKit
import Foundation

/// Metadata capabilities represented by the catalog. This type does not imply an execution backend.
public enum PluginCapability: String, CaseIterable, Equatable, Hashable, Sendable {
    case unpacker
    case prediffer
    case editor
    case copy
    case transform

    /// External-tool capability used when this metadata item names an approved executable rule.
    public var externalToolCapability: ExternalToolCapability? {
        switch self {
        case .unpacker: .unpacker
        case .prediffer: .prediffer
        case .editor: .editorScript
        case .copy: .copyingScript
        case .transform: nil
        }
    }
}

public enum PluginInvocationMode: String, CaseIterable, Equatable, Hashable, Sendable {
    case manual
    case automatic
}

/// Trust is an observation supplied by trusted application code, never catalog metadata or preferences.
public enum PluginTrustState: String, CaseIterable, Equatable, Hashable, Sendable {
    case bundled
    case trustedPublisher
    case localDevelopment
    case untrusted
    case revoked
    case invalid

    fileprivate var permitsManualUse: Bool {
        switch self {
        case .bundled, .trustedPublisher, .localDevelopment: true
        case .untrusted, .revoked, .invalid: false
        }
    }

    fileprivate var permitsAutomaticUse: Bool {
        switch self {
        case .bundled, .trustedPublisher: true
        case .localDevelopment, .untrusted, .revoked, .invalid: false
        }
    }
}

/// Approval is action-specific state supplied alongside trust. Automatic approval includes manual use.
public enum PluginApprovalState: String, CaseIterable, Equatable, Hashable, Sendable {
    case notApproved
    case manual
    case automatic

    fileprivate func permits(_ mode: PluginInvocationMode) -> Bool {
        switch (self, mode) {
        case (.manual, .manual), (.automatic, .manual), (.automatic, .automatic): true
        default: false
        }
    }
}

/// One atomically sampled trusted authority state. The authority owns both values and must prevent
/// clock rollback if wall-clock rollback is relevant to its threat model.
package struct PluginAuthorizationAuthorityState: Equatable, Hashable, Sendable {
    package let revocationGeneration: UInt64
    package let currentTime: Date

    package init(revocationGeneration: UInt64, currentTime: Date) {
        self.revocationGeneration = revocationGeneration
        self.currentTime = currentTime
    }
}

/// Application-owned source of current revocation and clock state.
package protocol PluginAuthorizationAuthorityStateProviding: AnyObject, Sendable {
    func currentPluginAuthorizationAuthorityState() -> PluginAuthorizationAuthorityState
}

/// Opaque capability minted by `PluginAuthorizationVerifier`. It is not catalog metadata or
/// persisted preference state.
public struct PluginAuthorization:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    let authorityDomainIdentifier: Data
    let trust: PluginTrustState
    let approval: PluginApprovalState
    let revocationGeneration: UInt64
    let expiresAt: Date
    let authenticationCode: Data

    init(
        authorityDomainIdentifier: Data,
        trust: PluginTrustState,
        approval: PluginApprovalState,
        revocationGeneration: UInt64,
        expiresAt: Date,
        authenticationCode: Data
    ) {
        self.authorityDomainIdentifier = authorityDomainIdentifier
        self.trust = trust
        self.approval = approval
        self.revocationGeneration = revocationGeneration
        self.expiresAt = expiresAt
        self.authenticationCode = authenticationCode
    }

    public var description: String { "PluginAuthorization(<opaque>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "capability": "<opaque>"
            ],
            displayStyle: .struct
        )
    }

}

/// Trusted application authority for plugin authorization capabilities.
///
/// Key bytes and the state provider must come from application-owned trusted infrastructure, never
/// plugin metadata or preferences. The capability MAC covers plugin identity, every external-rule
/// field, trust, approval, current revocation generation, and expiry.
public struct PluginAuthorizationVerifier:
    Equatable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let authenticationKeyByteCount = 32
    package static let authorityDomainIdentifierByteCount = 32

    private let authenticationKey: Data
    private let authorityDomainIdentifier: Data
    private let authorityStateProvider: any PluginAuthorizationAuthorityStateProviding

    package init(
        authenticationKey: Data,
        authorityDomainIdentifier: Data,
        authorityStateProvider: any PluginAuthorizationAuthorityStateProviding
    ) throws {
        guard authenticationKey.count == Self.authenticationKeyByteCount else {
            throw PluginCatalogError.invalidAuthorizationVerifierKey
        }
        guard authorityDomainIdentifier.count == Self.authorityDomainIdentifierByteCount else {
            throw PluginCatalogError.invalidAuthorizationAuthorityDomainIdentifier
        }
        self.authenticationKey = authenticationKey
        self.authorityDomainIdentifier = authorityDomainIdentifier
        self.authorityStateProvider = authorityStateProvider
    }

    package func issue(
        for item: PluginCatalogItem,
        trust: PluginTrustState,
        approval: PluginApprovalState,
        externalToolPolicy: ExternalToolPolicy,
        expiresAt: Date
    ) throws -> PluginAuthorization {
        guard let rule = PluginAuthorizationBinding.rule(for: item, in: externalToolPolicy) else {
            throw PluginCatalogError.authorizationSubjectUnavailable
        }
        let authorityState = authorityStateProvider.currentPluginAuthorizationAuthorityState()
        try Task.checkCancellation()
        try Self.validate(authorityState: authorityState)
        guard
            expiresAt.timeIntervalSinceReferenceDate.isFinite,
            expiresAt > authorityState.currentTime
        else {
            throw PluginCatalogError.invalidAuthorizationExpiry
        }
        let input = try PluginAuthorizationBinding.authenticationInput(
            item: item,
            rule: rule,
            authorityDomainIdentifier: authorityDomainIdentifier,
            trust: trust,
            approval: approval,
            revocationGeneration: authorityState.revocationGeneration,
            expiresAt: expiresAt
        )
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: input,
            using: SymmetricKey(data: authenticationKey)
        )
        return PluginAuthorization(
            authorityDomainIdentifier: authorityDomainIdentifier,
            trust: trust,
            approval: approval,
            revocationGeneration: authorityState.revocationGeneration,
            expiresAt: expiresAt,
            authenticationCode: Data(authenticationCode)
        )
    }

    fileprivate func verifies(
        _ authorization: PluginAuthorization,
        for item: PluginCatalogItem,
        rule: ExternalToolExecutableRule
    ) throws -> Bool {
        guard authorization.authorityDomainIdentifier == authorityDomainIdentifier else {
            return false
        }
        guard authorization.expiresAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        let input = try PluginAuthorizationBinding.authenticationInput(
            item: item,
            rule: rule,
            authorityDomainIdentifier: authorization.authorityDomainIdentifier,
            trust: authorization.trust,
            approval: authorization.approval,
            revocationGeneration: authorization.revocationGeneration,
            expiresAt: authorization.expiresAt
        )
        guard
            HMAC<SHA256>.isValidAuthenticationCode(
                authorization.authenticationCode,
                authenticating: input,
                using: SymmetricKey(data: authenticationKey)
            )
        else {
            return false
        }
        let authorityState = authorityStateProvider.currentPluginAuthorizationAuthorityState()
        try Task.checkCancellation()
        try Self.validate(authorityState: authorityState)
        return authorization.revocationGeneration == authorityState.revocationGeneration
            && authorityState.currentTime < authorization.expiresAt
    }

    private static func validate(authorityState: PluginAuthorizationAuthorityState) throws {
        guard
            authorityState.currentTime.timeIntervalSinceReferenceDate.isFinite
        else {
            throw PluginCatalogError.invalidAuthorizationAuthorityState
        }
    }

    public var description: String { "PluginAuthorizationVerifier(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "authenticationKey": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public static func == (
        left: PluginAuthorizationVerifier,
        right: PluginAuthorizationVerifier
    ) -> Bool {
        let probe = Data("MacMerge.PluginAuthorizationVerifier.Equality.v1".utf8)
        let leftCode = HMAC<SHA256>.authenticationCode(
            for: probe,
            using: SymmetricKey(data: left.authenticationKey)
        )
        return HMAC<SHA256>.isValidAuthenticationCode(
            leftCode,
            authenticating: probe,
            using: SymmetricKey(data: right.authenticationKey)
        ) && left.authorityDomainIdentifier == right.authorityDomainIdentifier
            && left.authorityStateProvider === right.authorityStateProvider
    }

}

/// Stable, non-localized ASCII identity. Equality and ordering never depend on display metadata.
public struct PluginIdentifier:
    Equatable, Hashable, Sendable, Comparable, CustomStringConvertible
{
    public static let maximumUTF8Bytes = 256

    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard PluginCatalogValidation.isIdentifier(rawValue, maximumUTF8Bytes: Self.maximumUTF8Bytes) else {
            throw PluginCatalogError.invalidIdentifier
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (left: PluginIdentifier, right: PluginIdentifier) -> Bool {
        PluginCatalogValidation.compareUTF8(left.rawValue, right.rawValue) < 0
    }
}

public enum PluginSettingValueKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case boolean
    case integer
    case string
    case choice
}

/// A typed preference value. Reflection deliberately omits its payload.
public enum PluginSettingValue:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case boolean(Bool)
    case integer(Int64)
    case string(String)
    case choice(String)

    public var kind: PluginSettingValueKind {
        switch self {
        case .boolean: .boolean
        case .integer: .integer
        case .string: .string
        case .choice: .choice
        }
    }

    public var description: String { "\(kind.rawValue):<redacted>" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": kind.rawValue,
                "value": "<redacted>"
            ],
            displayStyle: .enum
        )
    }
}

/// Closed, host-rendered setting constraints. Privacy is deliberately absent from public metadata.
public enum PluginSettingConstraint: Equatable, Hashable, Sendable {
    case boolean
    case integer(minimum: Int64, maximum: Int64)
    case string(maximumUTF8Bytes: Int)
    case choice([String])

    public var kind: PluginSettingValueKind {
        switch self {
        case .boolean: .boolean
        case .integer: .integer
        case .string: .string
        case .choice: .choice
        }
    }
}

public enum PluginSettingPrivacy: String, CaseIterable, Equatable, Hashable, Sendable {
    case nonSecret
    case secret
}

/// Opaque trusted-policy key for one setting. Raw plugin-authored strings cannot classify settings.
public struct PluginSettingIdentity:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    fileprivate let pluginIdentifier: PluginIdentifier
    fileprivate let settingKey: String
    fileprivate let catalogMetadataDigest: Data

    public var description: String { "PluginSettingIdentity(<opaque>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["identity": "<opaque>"], displayStyle: .struct)
    }
}

/// Application-owned classification supplied separately from plugin metadata.
public struct PluginSettingPrivacyPolicy:
    Equatable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let denyAll = try! PluginSettingPrivacyPolicy()

    private let classifications: [PluginSettingIdentity: PluginSettingPrivacy]

    public init(
        classifications: [PluginSettingIdentity: PluginSettingPrivacy] = [:],
        limits: PluginCatalogLimits = .default
    ) throws {
        guard classifications.count <= limits.maximumPreferenceValueCount else {
            throw PluginCatalogError.tooManyPreferenceValues(
                maximum: limits.maximumPreferenceValueCount
            )
        }
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        for identity in classifications.keys {
            try budget.consume(
                identity.pluginIdentifier.rawValue.utf8.count + identity.settingKey.utf8.count + 1
            )
            guard PluginCatalogValidation.isSettingKey(identity.settingKey) else {
                throw PluginCatalogError.invalidSettingSchema
            }
        }
        self.classifications = classifications
    }

    fileprivate func classification(for identity: PluginSettingIdentity) throws
        -> PluginSettingPrivacy?
    {
        try Task.checkCancellation()
        return classifications[identity]
    }

    fileprivate var settingIdentities: Dictionary<PluginSettingIdentity, PluginSettingPrivacy>.Keys {
        classifications.keys
    }

    public var description: String {
        "PluginSettingPrivacyPolicy(classifications: \(classifications.count), values: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "namespaceCount": classifications.count,
                "classifications": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Trusted Keychain integration consumes this operation identifier.
package struct PluginSettingKeychainOperation: Equatable, Hashable, Sendable {
    package static let maximumIdentifierUTF8Bytes = 256

    package let identifier: String

    package init(identifier: String) throws {
        guard
            !identifier.isEmpty,
            identifier.utf8.count <= Self.maximumIdentifierUTF8Bytes,
            identifier.utf8.allSatisfy({
                (0x30...0x39).contains($0) || (0x41...0x5A).contains($0)
                    || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
            })
        else {
            throw PluginCatalogError.invalidKeychainOperation
        }
        self.identifier = identifier
    }
}

/// Package-trusted adapter that performs a fixed operation against the referenced Keychain item.
/// It must not return the persistent reference or secret material to its caller.
package protocol PluginSettingKeychainResolving: AnyObject, Sendable {
    func perform(
        operation: PluginSettingKeychainOperation,
        keychainPersistentReference: Data
    ) throws
}

/// Opaque Keychain persistent-reference capability. Only `PluginSettingKeychainAuthority` can mint
/// one, and its MAC authenticates the setting identity, operation, persistent reference, authority
/// generation, and finite expiry.
public struct PluginSettingKeychainCapability:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let maximumPersistentReferenceBytes = 4 * 1_024

    let authorityDomainIdentifier: Data
    let settingIdentity: PluginSettingIdentity
    let operation: PluginSettingKeychainOperation
    let persistentReference: Data
    let revocationGeneration: UInt64
    let expiresAt: Date
    let authenticationCode: Data

    init(
        authorityDomainIdentifier: Data,
        settingIdentity: PluginSettingIdentity,
        operation: PluginSettingKeychainOperation,
        persistentReference: Data,
        revocationGeneration: UInt64,
        expiresAt: Date,
        authenticationCode: Data
    ) {
        self.authorityDomainIdentifier = authorityDomainIdentifier
        self.settingIdentity = settingIdentity
        self.operation = operation
        self.persistentReference = persistentReference
        self.revocationGeneration = revocationGeneration
        self.expiresAt = expiresAt
        self.authenticationCode = authenticationCode
    }

    fileprivate func matches(settingIdentity: PluginSettingIdentity) -> Bool {
        self.settingIdentity == settingIdentity
    }

    public var description: String { "PluginSettingKeychainCapability(<opaque>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "persistentReference": "<opaque>"
            ],
            displayStyle: .struct
        )
    }
}

/// Package-trusted authority for minting and using authenticated Keychain capabilities. Public
/// clients can carry capabilities but cannot construct an authority or extract references.
public struct PluginSettingKeychainAuthority:
    Equatable, Sendable, CustomReflectable, CustomStringConvertible, CustomDebugStringConvertible
{
    public static let authenticationKeyByteCount = 32
    package static let authorityDomainIdentifierByteCount = 32

    private let authenticationKey: Data
    private let authorityDomainIdentifier: Data
    private let resolver: any PluginSettingKeychainResolving
    private let authorityStateProvider: any PluginAuthorizationAuthorityStateProviding

    package init(
        authenticationKey: Data,
        authorityDomainIdentifier: Data,
        resolver: any PluginSettingKeychainResolving,
        authorityStateProvider: any PluginAuthorizationAuthorityStateProviding
    ) throws {
        guard authenticationKey.count == Self.authenticationKeyByteCount else {
            throw PluginCatalogError.invalidKeychainAuthorityKey
        }
        guard authorityDomainIdentifier.count == Self.authorityDomainIdentifierByteCount else {
            throw PluginCatalogError.invalidKeychainAuthorityDomainIdentifier
        }
        self.authenticationKey = authenticationKey
        self.authorityDomainIdentifier = authorityDomainIdentifier
        self.resolver = resolver
        self.authorityStateProvider = authorityStateProvider
    }

    package func issue(
        for settingIdentity: PluginSettingIdentity,
        operation: PluginSettingKeychainOperation,
        keychainPersistentReference: Data,
        expiresAt: Date
    ) throws -> PluginSettingKeychainCapability {
        guard
            !keychainPersistentReference.isEmpty,
            keychainPersistentReference.count
                <= PluginSettingKeychainCapability.maximumPersistentReferenceBytes
        else {
            throw PluginCatalogError.invalidKeychainPersistentReference
        }
        let authorityState = authorityStateProvider.currentPluginAuthorizationAuthorityState()
        try Task.checkCancellation()
        try Self.validate(authorityState: authorityState)
        guard
            expiresAt.timeIntervalSinceReferenceDate.isFinite,
            expiresAt > authorityState.currentTime
        else {
            throw PluginCatalogError.invalidKeychainCapabilityExpiry
        }
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: try PluginSettingKeychainBinding.authenticationInput(
                authorityDomainIdentifier: authorityDomainIdentifier,
                settingIdentity: settingIdentity,
                operation: operation,
                persistentReference: keychainPersistentReference,
                revocationGeneration: authorityState.revocationGeneration,
                expiresAt: expiresAt
            ),
            using: SymmetricKey(data: authenticationKey)
        )
        return PluginSettingKeychainCapability(
            authorityDomainIdentifier: authorityDomainIdentifier,
            settingIdentity: settingIdentity,
            operation: operation,
            persistentReference: keychainPersistentReference,
            revocationGeneration: authorityState.revocationGeneration,
            expiresAt: expiresAt,
            authenticationCode: Data(authenticationCode)
        )
    }

    fileprivate func verifies(
        _ capability: PluginSettingKeychainCapability,
        for settingIdentity: PluginSettingIdentity
    ) throws -> Bool {
        guard try authenticates(capability, for: settingIdentity) else { return false }
        let authorityState = try currentAuthorityState()
        return isCurrent(capability, in: authorityState)
    }

    private func authenticates(
        _ capability: PluginSettingKeychainCapability,
        for settingIdentity: PluginSettingIdentity
    ) throws -> Bool {
        guard capability.matches(settingIdentity: settingIdentity) else { return false }
        guard capability.authorityDomainIdentifier == authorityDomainIdentifier else { return false }
        guard capability.expiresAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            capability.authenticationCode,
            authenticating: try PluginSettingKeychainBinding.authenticationInput(
                authorityDomainIdentifier: capability.authorityDomainIdentifier,
                settingIdentity: settingIdentity,
                operation: capability.operation,
                persistentReference: capability.persistentReference,
                revocationGeneration: capability.revocationGeneration,
                expiresAt: capability.expiresAt
            ),
            using: SymmetricKey(data: authenticationKey)
        )
    }

    private func currentAuthorityState() throws -> PluginAuthorizationAuthorityState {
        let authorityState = authorityStateProvider.currentPluginAuthorizationAuthorityState()
        try Task.checkCancellation()
        try Self.validate(authorityState: authorityState)
        return authorityState
    }

    private static func validate(authorityState: PluginAuthorizationAuthorityState) throws {
        guard
            authorityState.currentTime.timeIntervalSinceReferenceDate.isFinite
        else {
            throw PluginCatalogError.invalidKeychainAuthorityState
        }
    }

    private func isCurrent(
        _ capability: PluginSettingKeychainCapability,
        in authorityState: PluginAuthorizationAuthorityState
    ) -> Bool {
        capability.revocationGeneration == authorityState.revocationGeneration
            && authorityState.currentTime < capability.expiresAt
    }

    fileprivate func perform(
        using capability: PluginSettingKeychainCapability,
        for settingIdentity: PluginSettingIdentity
    ) throws {
        guard try authenticates(capability, for: settingIdentity) else {
            throw PluginCatalogError.invalidKeychainCapability
        }
        let authorityState = try currentAuthorityState()
        guard isCurrent(capability, in: authorityState) else {
            throw PluginCatalogError.invalidKeychainCapability
        }
        do {
            try resolver.perform(
                operation: capability.operation,
                keychainPersistentReference: capability.persistentReference
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw PluginCatalogError.keychainOperationFailed
        }
    }

    public var description: String { "PluginSettingKeychainAuthority(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "authenticationKey": "<redacted>",
                "resolver": "<redacted>",
                "authorityStateProvider": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public static func == (
        left: PluginSettingKeychainAuthority,
        right: PluginSettingKeychainAuthority
    ) -> Bool {
        let probe = Data("MacMerge.PluginSettingKeychainAuthority.Equality.v1".utf8)
        let leftCode = HMAC<SHA256>.authenticationCode(
            for: probe,
            using: SymmetricKey(data: left.authenticationKey)
        )
        return HMAC<SHA256>.isValidAuthenticationCode(
            leftCode,
            authenticating: probe,
            using: SymmetricKey(data: right.authenticationKey)
        ) && left.authorityDomainIdentifier == right.authorityDomainIdentifier
            && left.resolver === right.resolver
            && left.authorityStateProvider === right.authorityStateProvider
    }
}

public enum PluginResolvedSettingValue:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case nonSecret(PluginSettingValue)
    case secret(PluginSettingKeychainCapability)

    public var description: String {
        switch self {
        case .nonSecret(let value): "nonSecret:\(value.kind.rawValue):<redacted>"
        case .secret: "secret:<keychain-capability>"
        }
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "value": "<redacted>"
            ],
            displayStyle: .enum
        )
    }
}

public struct PluginSettingSchema:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let key: String
    public let title: String
    public let summary: String?
    public let constraint: PluginSettingConstraint
    public let defaultValue: PluginSettingValue?

    public init(
        key: String,
        title: String,
        summary: String? = nil,
        constraint: PluginSettingConstraint,
        defaultValue: PluginSettingValue? = nil,
        limits: PluginCatalogLimits = .default
    ) throws {
        self.key = key
        self.title = title
        self.summary = summary
        self.constraint = constraint
        self.defaultValue = defaultValue
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        try PluginCatalogValidation.validate(
            settingSchema: self,
            limits: limits,
            budget: &budget
        )
    }

    public var description: String {
        "PluginSettingSchema(key: <redacted>, kind: \(constraint.kind.rawValue), value: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "key": "<redacted>",
                "kind": constraint.kind.rawValue,
                "defaultValue": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Declarative filename/UTI matching. Empty declarations match any supplied content metadata.
public struct PluginMatchMetadata: Equatable, Hashable, Sendable {
    public let fileExtensions: [String]
    public let contentTypeIdentifiers: [String]

    public init(
        fileExtensions: [String] = [],
        contentTypeIdentifiers: [String] = [],
        limits: PluginCatalogLimits = .default
    ) throws {
        guard
            fileExtensions.count <= limits.maximumMatchValuesPerItem,
            contentTypeIdentifiers.count
                <= limits.maximumMatchValuesPerItem - fileExtensions.count
        else {
            throw PluginCatalogError.tooManyMatchValues(
                maximum: limits.maximumMatchValuesPerItem
            )
        }
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        self.fileExtensions = try PluginCatalogValidation.canonicalFileExtensions(
            fileExtensions,
            limits: limits,
            budget: &budget
        )
        self.contentTypeIdentifiers = try PluginCatalogValidation.canonicalContentTypes(
            contentTypeIdentifiers,
            limits: limits,
            budget: &budget
        )
    }

    fileprivate func matches(fileExtension: String?, contentTypeIdentifier: String?) -> Bool {
        guard !fileExtensions.isEmpty || !contentTypeIdentifiers.isEmpty else { return true }
        if let fileExtension, fileExtensions.contains(fileExtension) { return true }
        if let contentTypeIdentifier, contentTypeIdentifiers.contains(contentTypeIdentifier) {
            return true
        }
        return false
    }
}

/// One metadata-only catalog action. It contains no code, path, command, closure, or loader hook.
public struct PluginCatalogItem:
    Identifiable, Equatable, Hashable, Sendable, CustomReflectable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public let id: PluginIdentifier
    public let displayName: String
    public let summary: String?
    public let version: String
    public let capability: PluginCapability
    public let manualEligible: Bool
    public let automaticEligible: Bool
    public let matchMetadata: PluginMatchMetadata
    public let settings: [PluginSettingSchema]
    /// Stable rule reference only. Executable identity and approval remain owned by `ExternalToolPolicy`.
    public let externalToolRuleIdentifier: String?

    public init(
        id: PluginIdentifier,
        displayName: String,
        summary: String? = nil,
        version: String,
        capability: PluginCapability,
        manualEligible: Bool = true,
        automaticEligible: Bool = false,
        matchMetadata: PluginMatchMetadata = try! PluginMatchMetadata(),
        settings: [PluginSettingSchema] = [],
        externalToolRuleIdentifier: String? = nil,
        limits: PluginCatalogLimits = .default
    ) throws {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.version = version
        self.capability = capability
        self.manualEligible = manualEligible
        self.automaticEligible = automaticEligible
        self.matchMetadata = matchMetadata
        guard settings.count <= limits.maximumSettingsPerItem else {
            throw PluginCatalogError.tooManySettings(maximum: limits.maximumSettingsPerItem)
        }
        self.settings = try pluginCatalogCancellableSorted(settings) {
            PluginCatalogValidation.utf8Precedes($0.key, $1.key)
        }
        self.externalToolRuleIdentifier = externalToolRuleIdentifier
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        try PluginCatalogValidation.validate(item: self, limits: limits, budget: &budget)
    }

    public var description: String {
        "PluginCatalogItem(id: \(id), capability: \(capability.rawValue), settings: \(settings.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "id": id.rawValue,
                "capability": capability.rawValue,
                "manualEligible": manualEligible,
                "automaticEligible": automaticEligible,
                "settingCount": settings.count,
                "metadata": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    /// Produces opaque identity consumed by trusted privacy policy configuration.
    public func settingIdentity(forKey key: String) throws -> PluginSettingIdentity {
        var lower = settings.startIndex
        var upper = settings.endIndex
        while lower < upper {
            try Task.checkCancellation()
            let middle = lower + (upper - lower) / 2
            if PluginCatalogValidation.utf8Precedes(settings[middle].key, key) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < settings.endIndex, settings[lower].key == key else {
            throw PluginCatalogError.preferenceReferencesUnknownSetting
        }
        let setting = settings[lower]
        return PluginSettingIdentity(
            pluginIdentifier: id,
            settingKey: key,
            catalogMetadataDigest: try PluginCatalogMetadataBinding.digest(
                item: self,
                setting: setting
            )
        )
    }
}

public struct PluginCatalogFilter: Equatable, Hashable, Sendable {
    public static let all = try! PluginCatalogFilter()

    public let identifier: PluginIdentifier?
    public let capability: PluginCapability?
    public let mode: PluginInvocationMode?
    public let fileExtension: String?
    public let contentTypeIdentifier: String?

    public init(
        identifier: PluginIdentifier? = nil,
        capability: PluginCapability? = nil,
        mode: PluginInvocationMode? = nil,
        fileExtension: String? = nil,
        contentTypeIdentifier: String? = nil
    ) throws {
        self.identifier = identifier
        self.capability = capability
        self.mode = mode
        self.fileExtension = try fileExtension.map {
            try PluginCatalogValidation.canonicalFileExtension($0)
        }
        self.contentTypeIdentifier = try contentTypeIdentifier.map {
            try PluginCatalogValidation.canonicalContentType($0)
        }
    }

}

public enum PluginCatalogAvailabilityStatus: String, CaseIterable, Equatable, Hashable, Sendable {
    case eligible
    case disabled
    case unsupported
}

public enum PluginCatalogEligibilityReason: Equatable, Hashable, Sendable {
    case eligible
    case manualUseNotDeclared
    case automaticUseNotDeclared
    case pluginNotEnabled
    case automaticUseNotEnabled
    case authorizationMissing
    case authorizationInvalid
    case trustDoesNotPermitManualUse
    case trustDoesNotPermitAutomaticUse
    case manualApprovalRequired
    case automaticApprovalRequired
    case externalToolRuleRequired
    case externalToolRuleNotConfigured
    case externalToolRuleCapabilityMismatch
    case externalToolPolicy(ExternalToolCapabilityReason)
    case executionBackendUnavailable
}

public struct PluginCatalogEligibilityDecision: Equatable, Hashable, Sendable {
    public let identifier: PluginIdentifier
    public let capability: PluginCapability
    public let mode: PluginInvocationMode
    public let status: PluginCatalogAvailabilityStatus
    public let reason: PluginCatalogEligibilityReason

    public var isEligible: Bool { status == .eligible }
}

public enum PluginCatalogOperation: String, CaseIterable, Equatable, Hashable, Sendable {
    case reload
    case inProcessLoading
}

public struct PluginCatalogOperationOutcome: Equatable, Hashable, Sendable {
    public let operation: PluginCatalogOperation
    public let status: ExternalToolCapabilityStatus
    public let reason: ExternalToolCapabilityReason

    public var isSupported: Bool { status == .supported }
}

public enum PluginCatalogSelectionOutcome: Equatable, Sendable {
    case noMatch
    case selected(PluginCatalogItem)
    case ambiguous([PluginIdentifier])
}

public struct PluginCatalogLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumItemCount = 4_096
    public static let hardMaximumSettingsPerItem = 1_024
    public static let hardMaximumMatchValuesPerItem = 4_096
    public static let hardMaximumChoiceCount = 1_024
    public static let hardMaximumMetadataStringUTF8Bytes = 16 * 1_024
    public static let hardMaximumPreferencePluginCount = 8_192
    public static let hardMaximumPreferenceValueCount = 65_536
    public static let hardMaximumPreferenceStringUTF8Bytes = 64 * 1_024
    /// `JSONDecoder` remains one bounded atomic decode after incremental validation.
    public static let hardMaximumPersistenceBytes = 1 * 1_024 * 1_024
    public static let hardMaximumJSONDepth = 32
    public static let hardMaximumJSONValueCount = 262_144
    public static let hardMaximumWork = 64 * 1_024 * 1_024

    public static let `default` = PluginCatalogLimits(
        maximumItemCount: 1_024,
        maximumSettingsPerItem: 128,
        maximumMatchValuesPerItem: 256,
        maximumChoiceCount: 128,
        maximumMetadataStringUTF8Bytes: 4 * 1_024,
        maximumPreferencePluginCount: 4_096,
        maximumPreferenceValueCount: 16_384,
        maximumPreferenceStringUTF8Bytes: 4 * 1_024,
        maximumPersistenceBytes: 1 * 1_024 * 1_024,
        maximumJSONDepth: 16,
        maximumJSONValueCount: 65_536,
        maximumWork: 8 * 1_024 * 1_024,
        validated: ()
    )

    public let maximumItemCount: Int
    public let maximumSettingsPerItem: Int
    public let maximumMatchValuesPerItem: Int
    public let maximumChoiceCount: Int
    public let maximumMetadataStringUTF8Bytes: Int
    public let maximumPreferencePluginCount: Int
    public let maximumPreferenceValueCount: Int
    public let maximumPreferenceStringUTF8Bytes: Int
    public let maximumPersistenceBytes: Int
    public let maximumJSONDepth: Int
    public let maximumJSONValueCount: Int
    public let maximumWork: Int

    public init(
        maximumItemCount: Int = 1_024,
        maximumSettingsPerItem: Int = 128,
        maximumMatchValuesPerItem: Int = 256,
        maximumChoiceCount: Int = 128,
        maximumMetadataStringUTF8Bytes: Int = 4 * 1_024,
        maximumPreferencePluginCount: Int = 4_096,
        maximumPreferenceValueCount: Int = 16_384,
        maximumPreferenceStringUTF8Bytes: Int = 4 * 1_024,
        maximumPersistenceBytes: Int = 1 * 1_024 * 1_024,
        maximumJSONDepth: Int = 16,
        maximumJSONValueCount: Int = 65_536,
        maximumWork: Int = 8 * 1_024 * 1_024
    ) throws {
        guard
            (1...Self.hardMaximumItemCount).contains(maximumItemCount),
            (1...Self.hardMaximumSettingsPerItem).contains(maximumSettingsPerItem),
            (1...Self.hardMaximumMatchValuesPerItem).contains(maximumMatchValuesPerItem),
            (1...Self.hardMaximumChoiceCount).contains(maximumChoiceCount),
            (256...Self.hardMaximumMetadataStringUTF8Bytes).contains(
                maximumMetadataStringUTF8Bytes
            ),
            (1...Self.hardMaximumPreferencePluginCount).contains(maximumPreferencePluginCount),
            (1...Self.hardMaximumPreferenceValueCount).contains(maximumPreferenceValueCount),
            (256...Self.hardMaximumPreferenceStringUTF8Bytes).contains(
                maximumPreferenceStringUTF8Bytes
            ),
            (1_024...Self.hardMaximumPersistenceBytes).contains(maximumPersistenceBytes),
            (4...Self.hardMaximumJSONDepth).contains(maximumJSONDepth),
            (32...Self.hardMaximumJSONValueCount).contains(maximumJSONValueCount),
            (maximumPersistenceBytes...Self.hardMaximumWork).contains(maximumWork)
        else {
            throw PluginCatalogError.invalidLimits
        }
        self.init(
            maximumItemCount: maximumItemCount,
            maximumSettingsPerItem: maximumSettingsPerItem,
            maximumMatchValuesPerItem: maximumMatchValuesPerItem,
            maximumChoiceCount: maximumChoiceCount,
            maximumMetadataStringUTF8Bytes: maximumMetadataStringUTF8Bytes,
            maximumPreferencePluginCount: maximumPreferencePluginCount,
            maximumPreferenceValueCount: maximumPreferenceValueCount,
            maximumPreferenceStringUTF8Bytes: maximumPreferenceStringUTF8Bytes,
            maximumPersistenceBytes: maximumPersistenceBytes,
            maximumJSONDepth: maximumJSONDepth,
            maximumJSONValueCount: maximumJSONValueCount,
            maximumWork: maximumWork,
            validated: ()
        )
    }

    private init(
        maximumItemCount: Int,
        maximumSettingsPerItem: Int,
        maximumMatchValuesPerItem: Int,
        maximumChoiceCount: Int,
        maximumMetadataStringUTF8Bytes: Int,
        maximumPreferencePluginCount: Int,
        maximumPreferenceValueCount: Int,
        maximumPreferenceStringUTF8Bytes: Int,
        maximumPersistenceBytes: Int,
        maximumJSONDepth: Int,
        maximumJSONValueCount: Int,
        maximumWork: Int,
        validated: Void
    ) {
        self.maximumItemCount = maximumItemCount
        self.maximumSettingsPerItem = maximumSettingsPerItem
        self.maximumMatchValuesPerItem = maximumMatchValuesPerItem
        self.maximumChoiceCount = maximumChoiceCount
        self.maximumMetadataStringUTF8Bytes = maximumMetadataStringUTF8Bytes
        self.maximumPreferencePluginCount = maximumPreferencePluginCount
        self.maximumPreferenceValueCount = maximumPreferenceValueCount
        self.maximumPreferenceStringUTF8Bytes = maximumPreferenceStringUTF8Bytes
        self.maximumPersistenceBytes = maximumPersistenceBytes
        self.maximumJSONDepth = maximumJSONDepth
        self.maximumJSONValueCount = maximumJSONValueCount
        self.maximumWork = maximumWork
    }
}

public enum PluginCatalogError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case invalidAuthorizationVerifierKey
    case invalidAuthorizationAuthorityDomainIdentifier
    case invalidAuthorizationAuthorityState
    case invalidAuthorizationExpiry
    case authorizationSubjectUnavailable
    case invalidIdentifier
    case invalidExternalToolRuleIdentifier
    case missingTrustedSettingClassification
    case unexpectedTrustedSettingClassification
    case secretSettingCannotHaveDefaultValue
    case nonSecretSettingRequiresDefaultValue
    case secretSettingCannotBePersisted
    case secretSettingRequiresKeychainCapability
    case nonSecretSettingCannotUseKeychainCapability
    case invalidKeychainAuthorityKey
    case invalidKeychainAuthorityDomainIdentifier
    case invalidKeychainAuthorityState
    case invalidKeychainCapabilityExpiry
    case invalidKeychainCapability
    case invalidKeychainOperation
    case invalidKeychainPersistentReference
    case keychainOperationFailed
    case invalidMetadata(field: String)
    case invalidSettingSchema
    case invalidSettingValue
    case duplicateItemIdentifier
    case duplicateSettingKey
    case duplicateMatchValue
    case tooManyItems(maximum: Int)
    case tooManySettings(maximum: Int)
    case tooManyMatchValues(maximum: Int)
    case tooManyChoices(maximum: Int)
    case tooManyPreferencePlugins(maximum: Int)
    case tooManyPreferenceValues(maximum: Int)
    case automaticPreferenceRequiresEnabledPlugin
    case preferredPluginMustBeAutomatic
    case duplicatePreferredPlugin
    case preferenceReferencesUnknownPlugin
    case preferenceReferencesUnknownSetting
    case persistenceDataTooLarge(maximumBytes: Int)
    case persistenceOutputTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case malformedPersistence
    case unknownPersistenceKey
    case duplicatePersistenceKey
    case nonCanonicalPersistence
    case jsonTooDeep(maximumDepth: Int)
    case jsonValueLimitExceeded(maximumValues: Int)
    case workLimitExceeded(maximumWork: Int)
    case boundedDecodingRequired

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Plugin catalog limits are invalid."
        case .invalidAuthorizationVerifierKey:
            "Plugin authorization verifier requires a 256-bit authentication key."
        case .invalidAuthorizationAuthorityDomainIdentifier:
            "Plugin authorization verifier requires a 256-bit authority-domain identifier."
        case .invalidAuthorizationAuthorityState:
            "Plugin authorization authority supplied invalid trusted clock state."
        case .invalidAuthorizationExpiry:
            "Plugin authorization expiry must be finite and later than trusted authority time."
        case .authorizationSubjectUnavailable:
            "Plugin authorization requires a matching configured external-tool rule."
        case .invalidIdentifier:
            "Plugin identifier must be bounded ASCII letters, digits, dots, hyphens, or underscores."
        case .invalidExternalToolRuleIdentifier:
            "External-tool rule identifier is invalid."
        case .missingTrustedSettingClassification:
            "Plugin setting lacks an externally trusted privacy classification."
        case .unexpectedTrustedSettingClassification:
            "Trusted setting privacy policy references undeclared plugin metadata."
        case .secretSettingCannotHaveDefaultValue:
            "Secret plugin settings cannot contain default values."
        case .nonSecretSettingRequiresDefaultValue:
            "Nonsecret plugin settings require a validated default value."
        case .secretSettingCannotBePersisted:
            "Secret plugin settings cannot be stored in plugin preferences."
        case .secretSettingRequiresKeychainCapability:
            "Secret plugin settings require an opaque Keychain capability."
        case .nonSecretSettingCannotUseKeychainCapability:
            "Nonsecret plugin settings cannot use a Keychain capability."
        case .invalidKeychainAuthorityKey:
            "Plugin Keychain authority requires a 256-bit authentication key."
        case .invalidKeychainAuthorityDomainIdentifier:
            "Plugin Keychain authority requires a 256-bit authority-domain identifier."
        case .invalidKeychainAuthorityState:
            "Plugin Keychain authority supplied invalid trusted clock state."
        case .invalidKeychainCapabilityExpiry:
            "Plugin Keychain capability expiry must be finite and later than trusted authority time."
        case .invalidKeychainCapability:
            "Plugin Keychain capability authentication or setting binding is invalid."
        case .invalidKeychainOperation:
            "Plugin Keychain operation identifier is invalid."
        case .invalidKeychainPersistentReference:
            "Keychain capability requires a bounded opaque persistent reference."
        case .keychainOperationFailed:
            "Trusted Keychain operation failed."
        case .invalidMetadata(let field):
            "Plugin metadata field is invalid: \(field)."
        case .invalidSettingSchema:
            "Plugin setting schema is invalid."
        case .invalidSettingValue:
            "Plugin setting value does not satisfy its schema."
        case .duplicateItemIdentifier:
            "Plugin catalog contains a duplicate stable identifier."
        case .duplicateSettingKey:
            "Plugin metadata contains a duplicate setting key."
        case .duplicateMatchValue:
            "Plugin metadata contains a duplicate match value."
        case .tooManyItems(let maximum):
            "Plugin catalog exceeds the \(maximum)-item limit."
        case .tooManySettings(let maximum):
            "Plugin metadata exceeds the \(maximum)-setting limit."
        case .tooManyMatchValues(let maximum):
            "Plugin metadata exceeds the \(maximum)-match-value limit."
        case .tooManyChoices(let maximum):
            "Plugin setting exceeds the \(maximum)-choice limit."
        case .tooManyPreferencePlugins(let maximum):
            "Plugin preferences exceed the \(maximum)-plugin limit."
        case .tooManyPreferenceValues(let maximum):
            "Plugin preferences exceed the \(maximum)-value limit."
        case .automaticPreferenceRequiresEnabledPlugin:
            "An automatic plugin preference must also enable the plugin."
        case .preferredPluginMustBeAutomatic:
            "A preferred automatic plugin must be enabled for automatic use."
        case .duplicatePreferredPlugin:
            "Preferred automatic plugin order contains a duplicate identifier."
        case .preferenceReferencesUnknownPlugin:
            "Plugin preferences reference an unknown plugin."
        case .preferenceReferencesUnknownSetting:
            "Plugin preferences reference an undeclared setting."
        case .persistenceDataTooLarge(let maximumBytes):
            "Plugin preference data exceeds the \(maximumBytes)-byte input limit."
        case .persistenceOutputTooLarge(let maximumBytes):
            "Plugin preference data exceeds the \(maximumBytes)-byte output limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported plugin preference schema version: \(version)."
        case .malformedPersistence:
            "Plugin preference data is malformed."
        case .unknownPersistenceKey:
            "Plugin preference data contains an unknown key."
        case .duplicatePersistenceKey:
            "Plugin preference data contains a duplicate key."
        case .nonCanonicalPersistence:
            "Plugin preference data is not in canonical form."
        case .jsonTooDeep(let maximumDepth):
            "Plugin preference JSON exceeds the \(maximumDepth)-level depth limit."
        case .jsonValueLimitExceeded(let maximumValues):
            "Plugin preference JSON exceeds the \(maximumValues)-value limit."
        case .workLimitExceeded(let maximumWork):
            "Plugin catalog work exceeds the \(maximumWork)-unit limit."
        case .boundedDecodingRequired:
            "Plugin preferences require bounded decoding."
        }
    }
}

/// Persisted user choices only. Trust, approval, catalog metadata, and executable data are excluded.
public struct PluginCatalogPreferences:
    Equatable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let currentSchemaVersion = 1

    public let enabledPluginIdentifiers: Set<PluginIdentifier>
    public let automaticPluginIdentifiers: Set<PluginIdentifier>
    public let preferredAutomaticPluginIdentifiers: [PluginIdentifier]
    /// Nonsecret values only. Secret settings live behind separately supplied Keychain capabilities.
    public let settingValues: [PluginIdentifier: [String: PluginSettingValue]]

    public init(
        catalog: PluginCatalog,
        enabledPluginIdentifiers: Set<PluginIdentifier> = [],
        automaticPluginIdentifiers: Set<PluginIdentifier> = [],
        preferredAutomaticPluginIdentifiers: [PluginIdentifier] = [],
        settingValues: [PluginIdentifier: [String: PluginSettingValue]] = [:]
    ) throws {
        self.enabledPluginIdentifiers = enabledPluginIdentifiers
        self.automaticPluginIdentifiers = automaticPluginIdentifiers
        self.preferredAutomaticPluginIdentifiers = preferredAutomaticPluginIdentifiers
        self.settingValues = settingValues
        try catalog.validate(preferences: self)
    }

    fileprivate init(
        enabledPluginIdentifiers: Set<PluginIdentifier>,
        automaticPluginIdentifiers: Set<PluginIdentifier>,
        preferredAutomaticPluginIdentifiers: [PluginIdentifier],
        settingValues: [PluginIdentifier: [String: PluginSettingValue]],
        limits: PluginCatalogLimits
    ) throws {
        self.enabledPluginIdentifiers = enabledPluginIdentifiers
        self.automaticPluginIdentifiers = automaticPluginIdentifiers
        self.preferredAutomaticPluginIdentifiers = preferredAutomaticPluginIdentifiers
        self.settingValues = settingValues
        try validate(limits: limits)
    }

    public var description: String {
        "PluginCatalogPreferences(enabled: \(enabledPluginIdentifiers.count), automatic: \(automaticPluginIdentifiers.count), settings: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "enabledCount": enabledPluginIdentifiers.count,
                "automaticCount": automaticPluginIdentifiers.count,
                "preferredCount": preferredAutomaticPluginIdentifiers.count,
                "settingNamespaces": settingValues.count,
                "identifiers": "<redacted>",
                "settingValues": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    /// Compact canonical JSON. Secret settings, capabilities, trust, approvals, and metadata are
    /// never encoded. Catalog validation supplies externally trusted privacy classifications.
    public func encodedData(for catalog: PluginCatalog) throws -> Data {
        try catalog.validate(preferences: self)
        let wire = try PluginPreferencesWire(self)
        return try wire.canonicalEncodedData(limits: catalog.limits)
    }

    /// Strictly decodes canonical schema-versioned preference JSON after bounded token validation.
    public static func decode(
        from data: Data,
        for catalog: PluginCatalog
    ) throws -> PluginCatalogPreferences {
        try Task.checkCancellation()
        let limits = catalog.limits
        guard data.count <= limits.maximumPersistenceBytes else {
            throw PluginCatalogError.persistenceDataTooLarge(
                maximumBytes: limits.maximumPersistenceBytes
            )
        }
        do {
            try data.withUnsafeBytes { rawBuffer in
                var scanner = PluginCatalogJSONScanner(
                    bytes: rawBuffer.bindMemory(to: UInt8.self),
                    limits: limits
                )
                try scanner.validate()
            }
            let decoder = JSONDecoder()
            decoder.userInfo[PluginCatalogCoding.limitsKey] = limits
            decoder.userInfo[PluginCatalogCoding.decodeStateKey] = PluginCatalogDecodeState(
                limits: limits
            )
            let wire = try decoder.decode(PluginPreferencesWire.self, from: data)
            let preferences = try wire.preferences(limits: limits)
            try catalog.validate(preferences: preferences)
            let canonicalWire = try PluginPreferencesWire(preferences)
            let canonicalData = try canonicalWire.canonicalEncodedData(limits: limits)
            guard canonicalData == data else { throw PluginCatalogError.nonCanonicalPersistence }
            return preferences
        } catch let error as PluginCatalogError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PluginCatalogError.malformedPersistence
        }
    }

    fileprivate func validate(limits: PluginCatalogLimits) throws {
        try Task.checkCancellation()
        guard
            enabledPluginIdentifiers.count <= limits.maximumPreferencePluginCount,
            automaticPluginIdentifiers.count <= limits.maximumPreferencePluginCount,
            preferredAutomaticPluginIdentifiers.count <= limits.maximumPreferencePluginCount,
            settingValues.count <= limits.maximumPreferencePluginCount
        else {
            throw PluginCatalogError.tooManyPreferencePlugins(
                maximum: limits.maximumPreferencePluginCount
            )
        }
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        var allIdentifiers: Set<PluginIdentifier> = []
        func record<S: Sequence>(_ identifiers: S) throws where S.Element == PluginIdentifier {
            for identifier in identifiers {
                try budget.consume(identifier.rawValue.utf8.count + 1)
                guard
                    allIdentifiers.contains(identifier)
                        || allIdentifiers.count < limits.maximumPreferencePluginCount
                else {
                    throw PluginCatalogError.tooManyPreferencePlugins(
                        maximum: limits.maximumPreferencePluginCount
                    )
                }
                allIdentifiers.insert(identifier)
            }
        }
        try record(enabledPluginIdentifiers)
        try record(automaticPluginIdentifiers)
        try record(preferredAutomaticPluginIdentifiers)
        try record(settingValues.keys)
        guard automaticPluginIdentifiers.isSubset(of: enabledPluginIdentifiers) else {
            throw PluginCatalogError.automaticPreferenceRequiresEnabledPlugin
        }
        var preferredSeen: Set<PluginIdentifier> = []
        for identifier in preferredAutomaticPluginIdentifiers {
            try budget.consume(identifier.rawValue.utf8.count + 1)
            guard automaticPluginIdentifiers.contains(identifier) else {
                throw PluginCatalogError.preferredPluginMustBeAutomatic
            }
            guard preferredSeen.insert(identifier).inserted else {
                throw PluginCatalogError.duplicatePreferredPlugin
            }
        }

        var valueCount = 0
        for identifier in try pluginCatalogCancellableSorted(settingValues.keys, by: <) {
            try budget.consume(identifier.rawValue.utf8.count + 1)
            guard let values = settingValues[identifier] else { continue }
            guard valueCount <= limits.maximumPreferenceValueCount - values.count else {
                throw PluginCatalogError.tooManyPreferenceValues(
                    maximum: limits.maximumPreferenceValueCount
                )
            }
            valueCount += values.count
            for key in values.keys {
                try budget.consume(key.utf8.count + 1)
                guard PluginCatalogValidation.isSettingKey(key) else {
                    throw PluginCatalogError.invalidSettingSchema
                }
            }
            for key in try pluginCatalogCancellableSorted(
                values.keys,
                by: PluginCatalogValidation.utf8Precedes
            ) {
                if let value = values[key] {
                    try PluginCatalogValidation.validate(
                        preferenceValue: value,
                        key: key,
                        limits: limits,
                        budget: &budget
                    )
                }
            }
        }
    }
}

/// Deterministic metadata registry. Construction performs no discovery and opens no resources.
public struct PluginCatalog:
    Equatable, Sendable, RandomAccessCollection, CustomReflectable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public typealias Index = Int

    public let limits: PluginCatalogLimits
    public let items: [PluginCatalogItem]
    private let settingPrivacyPolicy: PluginSettingPrivacyPolicy
    private let authorizationVerifier: PluginAuthorizationVerifier?
    private let keychainAuthority: PluginSettingKeychainAuthority?

    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    public subscript(position: Int) -> PluginCatalogItem { items[position] }

    public var description: String { "PluginCatalog(itemCount: \(items.count))" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "limits": limits,
                "itemCount": items.count,
                "items": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public init(
        items: [PluginCatalogItem] = [],
        settingPrivacyPolicy: PluginSettingPrivacyPolicy = .denyAll,
        authorizationVerifier: PluginAuthorizationVerifier? = nil,
        keychainAuthority: PluginSettingKeychainAuthority? = nil,
        limits: PluginCatalogLimits = .default
    ) throws {
        try Task.checkCancellation()
        guard items.count <= limits.maximumItemCount else {
            throw PluginCatalogError.tooManyItems(maximum: limits.maximumItemCount)
        }
        var validated = items
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        for (index, item) in validated.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            try PluginCatalogValidation.validate(item: item, limits: limits, budget: &budget)
        }
        validated = try pluginCatalogCancellableSorted(validated) { $0.id < $1.id }
        for index in validated.indices.dropFirst() where validated[index - 1].id == validated[index].id {
            throw PluginCatalogError.duplicateItemIdentifier
        }
        try Self.validate(
            settingPrivacyPolicy: settingPrivacyPolicy,
            items: validated,
            limits: limits
        )
        self.limits = limits
        self.items = validated
        self.settingPrivacyPolicy = settingPrivacyPolicy
        self.authorizationVerifier = authorizationVerifier
        self.keychainAuthority = keychainAuthority
    }

    /// Returns only application-owned classification, never a metadata-authored assertion.
    public func settingPrivacy(
        for identifier: PluginIdentifier,
        key: String
    ) throws -> PluginSettingPrivacy? {
        try Task.checkCancellation()
        guard let item = item(withIdentifier: identifier) else { return nil }
        let identity: PluginSettingIdentity
        do {
            identity = try item.settingIdentity(forKey: key)
        } catch is CancellationError {
            throw CancellationError()
        } catch PluginCatalogError.preferenceReferencesUnknownSetting {
            return nil
        }
        return try settingPrivacyPolicy.classification(for: identity)
    }

    public func item(withIdentifier identifier: PluginIdentifier) -> PluginCatalogItem? {
        var lower = items.startIndex
        var upper = items.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if items[middle].id < identifier {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < items.endIndex, items[lower].id == identifier else { return nil }
        return items[lower]
    }

    /// Returns metadata in stable identifier order, independent of registration order.
    public func items(matching filter: PluginCatalogFilter = .all) throws -> [PluginCatalogItem] {
        try Task.checkCancellation()
        var result: [PluginCatalogItem] = []
        result.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            if let identifier = filter.identifier, item.id != identifier { continue }
            if let capability = filter.capability, item.capability != capability { continue }
            if let mode = filter.mode {
                if mode == .manual, !item.manualEligible { continue }
                if mode == .automatic, !item.automaticEligible { continue }
            }
            if filter.fileExtension != nil || filter.contentTypeIdentifier != nil {
                guard
                    item.matchMetadata.matches(
                        fileExtension: filter.fileExtension,
                        contentTypeIdentifier: filter.contentTypeIdentifier
                    )
                else { continue }
            }
            result.append(item)
        }
        return result
    }

    public func decision(
        for identifier: PluginIdentifier,
        mode: PluginInvocationMode,
        authorization: PluginAuthorization?,
        preferences: PluginCatalogPreferences,
        externalToolPolicy: ExternalToolPolicy = .default
    ) throws -> PluginCatalogEligibilityDecision? {
        try Task.checkCancellation()
        guard let item = item(withIdentifier: identifier) else { return nil }
        return try decision(
            for: item,
            mode: mode,
            authorization: authorization,
            preferences: preferences,
            externalToolPolicy: externalToolPolicy
        )
    }

    /// Returns eligible items with explicit automatic preference order, then stable ID order.
    public func eligibleItems(
        matching filter: PluginCatalogFilter = .all,
        mode: PluginInvocationMode,
        authorizations: [PluginIdentifier: PluginAuthorization],
        preferences: PluginCatalogPreferences,
        externalToolPolicy: ExternalToolPolicy = .default
    ) throws -> [PluginCatalogItem] {
        let candidates = try items(matching: filter)
        var result: [PluginCatalogItem] = []
        result.reserveCapacity(candidates.count)
        for (index, item) in candidates.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let outcome = try decision(
                for: item,
                mode: mode,
                authorization: authorizations[item.id],
                preferences: preferences,
                externalToolPolicy: externalToolPolicy
            )
            if outcome.isEligible { result.append(item) }
        }
        guard mode == .automatic else { return result }
        let ranks = Dictionary(
            uniqueKeysWithValues: preferences.preferredAutomaticPluginIdentifiers.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        result = try pluginCatalogCancellableSorted(result) {
            let leftRank = ranks[$0.id] ?? Int.max
            let rightRank = ranks[$1.id] ?? Int.max
            return leftRank == rightRank ? $0.id < $1.id : leftRank < rightRank
        }
        return result
    }

    /// Selects only a unique match or an explicitly first automatic preference; scan order never wins.
    public func select(
        matching filter: PluginCatalogFilter = .all,
        mode: PluginInvocationMode,
        authorizations: [PluginIdentifier: PluginAuthorization],
        preferences: PluginCatalogPreferences,
        externalToolPolicy: ExternalToolPolicy = .default
    ) throws -> PluginCatalogSelectionOutcome {
        let eligible = try eligibleItems(
            matching: filter,
            mode: mode,
            authorizations: authorizations,
            preferences: preferences,
            externalToolPolicy: externalToolPolicy
        )
        guard let first = eligible.first else { return .noMatch }
        if eligible.count == 1 || filter.identifier != nil { return .selected(first) }
        if mode == .automatic,
            preferences.preferredAutomaticPluginIdentifiers.contains(first.id)
        {
            return .selected(first)
        }
        return .ambiguous(try pluginCatalogCancellableSorted(eligible.map(\.id), by: <))
    }

    /// Resolves nonsecret values and authenticated Keychain capabilities. Secret values are never
    /// accepted, and persistent references are never exported.
    public func resolvedSettings(
        for identifier: PluginIdentifier,
        preferences: PluginCatalogPreferences,
        keychainCapabilities: [String: PluginSettingKeychainCapability] = [:]
    ) throws -> [String: PluginResolvedSettingValue] {
        guard let item = item(withIdentifier: identifier) else {
            throw PluginCatalogError.preferenceReferencesUnknownPlugin
        }
        let persisted = preferences.settingValues[identifier] ?? [:]
        let schemas = Dictionary(uniqueKeysWithValues: item.settings.map { ($0.key, $0) })
        for key in persisted.keys where schemas[key] == nil {
            throw PluginCatalogError.preferenceReferencesUnknownSetting
        }
        guard keychainCapabilities.count <= limits.maximumSettingsPerItem else {
            throw PluginCatalogError.tooManySettings(maximum: limits.maximumSettingsPerItem)
        }
        var result: [String: PluginResolvedSettingValue] = [:]
        result.reserveCapacity(item.settings.count)
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        for key in keychainCapabilities.keys {
            try budget.consume(key.utf8.count + 1)
            guard PluginCatalogValidation.isSettingKey(key), schemas[key] != nil else {
                throw PluginCatalogError.preferenceReferencesUnknownSetting
            }
        }
        for schema in item.settings {
            try Task.checkCancellation()
            let settingIdentity = try item.settingIdentity(forKey: schema.key)
            switch try settingPrivacyPolicy.classification(for: settingIdentity) {
            case .nonSecret:
                guard keychainCapabilities[schema.key] == nil else {
                    throw PluginCatalogError.nonSecretSettingCannotUseKeychainCapability
                }
                guard let value = persisted[schema.key] ?? schema.defaultValue else {
                    throw PluginCatalogError.nonSecretSettingRequiresDefaultValue
                }
                try PluginCatalogValidation.validate(
                    value: value,
                    against: schema,
                    limits: limits,
                    budget: &budget
                )
                result[schema.key] = .nonSecret(value)
            case .secret:
                guard persisted[schema.key] == nil else {
                    throw PluginCatalogError.secretSettingCannotBePersisted
                }
                guard
                    let capability = keychainCapabilities[schema.key],
                    let keychainAuthority,
                    try keychainAuthority.verifies(capability, for: settingIdentity)
                else {
                    throw PluginCatalogError.secretSettingRequiresKeychainCapability
                }
                result[schema.key] = .secret(capability)
            case nil:
                throw PluginCatalogError.missingTrustedSettingClassification
            }
        }
        return result
    }

    /// Asks trusted Keychain integration to perform one fixed operation. Neither persistent
    /// references nor secret bytes cross this API boundary.
    public func performSecretSettingOperation(
        for identifier: PluginIdentifier,
        key: String,
        capability: PluginSettingKeychainCapability
    ) throws {
        guard let item = item(withIdentifier: identifier) else {
            throw PluginCatalogError.preferenceReferencesUnknownPlugin
        }
        let settingIdentity = try item.settingIdentity(forKey: key)
        guard try settingPrivacyPolicy.classification(for: settingIdentity) == .secret else {
            throw PluginCatalogError.nonSecretSettingCannotUseKeychainCapability
        }
        guard let keychainAuthority else {
            throw PluginCatalogError.invalidKeychainCapability
        }
        try keychainAuthority.perform(
            using: capability,
            for: settingIdentity
        )
    }

    /// Validates preference references without retaining trust or approval state.
    public func validate(preferences: PluginCatalogPreferences) throws {
        try preferences.validate(limits: limits)
        let referenced = preferences.enabledPluginIdentifiers
            .union(preferences.automaticPluginIdentifiers)
            .union(preferences.preferredAutomaticPluginIdentifiers)
            .union(preferences.settingValues.keys)
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        for identifier in try pluginCatalogCancellableSorted(referenced, by: <) {
            try Task.checkCancellation()
            guard let item = item(withIdentifier: identifier) else {
                throw PluginCatalogError.preferenceReferencesUnknownPlugin
            }
            let persisted = preferences.settingValues[identifier] ?? [:]
            let schemas = Dictionary(uniqueKeysWithValues: item.settings.map { ($0.key, $0) })
            for key in try pluginCatalogCancellableSorted(
                persisted.keys,
                by: PluginCatalogValidation.utf8Precedes
            ) {
                guard let schema = schemas[key] else {
                    throw PluginCatalogError.preferenceReferencesUnknownSetting
                }
                let settingIdentity = try item.settingIdentity(forKey: key)
                guard try settingPrivacyPolicy.classification(for: settingIdentity) == .nonSecret
                else {
                    throw PluginCatalogError.secretSettingCannotBePersisted
                }
                guard let value = persisted[key] else { continue }
                try PluginCatalogValidation.validate(
                    value: value,
                    against: schema,
                    limits: limits,
                    budget: &budget
                )
            }
        }
    }

    public func operationOutcome(
        for operation: PluginCatalogOperation,
        externalToolPolicy: ExternalToolPolicy = .default
    ) -> PluginCatalogOperationOutcome {
        let capability: ExternalToolCapability
        switch operation {
        case .reload: capability = .pluginReload
        case .inProcessLoading: capability = .inProcessExtensions
        }
        let decision = externalToolPolicy.decision(for: capability)
        return PluginCatalogOperationOutcome(
            operation: operation,
            status: decision.status,
            reason: decision.reason
        )
    }

    public func reloadOutcome(
        externalToolPolicy: ExternalToolPolicy = .default
    ) -> PluginCatalogOperationOutcome {
        operationOutcome(for: .reload, externalToolPolicy: externalToolPolicy)
    }

    public func inProcessLoadingOutcome(
        externalToolPolicy: ExternalToolPolicy = .default
    ) -> PluginCatalogOperationOutcome {
        operationOutcome(for: .inProcessLoading, externalToolPolicy: externalToolPolicy)
    }

    private func decision(
        for item: PluginCatalogItem,
        mode: PluginInvocationMode,
        authorization: PluginAuthorization?,
        preferences: PluginCatalogPreferences,
        externalToolPolicy: ExternalToolPolicy
    ) throws -> PluginCatalogEligibilityDecision {
        func outcome(
            _ status: PluginCatalogAvailabilityStatus,
            _ reason: PluginCatalogEligibilityReason
        ) -> PluginCatalogEligibilityDecision {
            PluginCatalogEligibilityDecision(
                identifier: item.id,
                capability: item.capability,
                mode: mode,
                status: status,
                reason: reason
            )
        }

        if mode == .manual, !item.manualEligible {
            return outcome(.disabled, .manualUseNotDeclared)
        }
        if mode == .automatic, !item.automaticEligible {
            return outcome(.disabled, .automaticUseNotDeclared)
        }
        guard let externalCapability = item.capability.externalToolCapability else {
            return outcome(.unsupported, .executionBackendUnavailable)
        }
        let policyDecision = externalToolPolicy.decision(for: externalCapability)
        guard policyDecision.status == .supported else {
            return outcome(policyDecision.status == .unsupported ? .unsupported : .disabled, .externalToolPolicy(policyDecision.reason))
        }
        guard preferences.enabledPluginIdentifiers.contains(item.id) else {
            return outcome(.disabled, .pluginNotEnabled)
        }
        if mode == .automatic,
            !preferences.automaticPluginIdentifiers.contains(item.id)
        {
            return outcome(.disabled, .automaticUseNotEnabled)
        }
        guard let authorization else {
            return outcome(.disabled, .authorizationMissing)
        }
        guard let ruleIdentifier = item.externalToolRuleIdentifier else {
            return outcome(.disabled, .externalToolRuleRequired)
        }
        guard
            let rule = externalToolPolicy.externalExecutableRules.first(where: {
                $0.identifier == ruleIdentifier
            })
        else {
            return outcome(.disabled, .externalToolRuleNotConfigured)
        }
        guard rule.capability == externalCapability else {
            return outcome(.disabled, .externalToolRuleCapabilityMismatch)
        }
        guard
            let authorizationVerifier,
            try authorizationVerifier.verifies(authorization, for: item, rule: rule)
        else {
            return outcome(.disabled, .authorizationInvalid)
        }
        if mode == .manual, !authorization.trust.permitsManualUse {
            return outcome(.disabled, .trustDoesNotPermitManualUse)
        }
        if mode == .automatic, !authorization.trust.permitsAutomaticUse {
            return outcome(.disabled, .trustDoesNotPermitAutomaticUse)
        }
        guard authorization.approval.permits(mode) else {
            return outcome(
                .disabled,
                mode == .manual ? .manualApprovalRequired : .automaticApprovalRequired
            )
        }
        return outcome(.eligible, .eligible)
    }

    private static func validate(
        settingPrivacyPolicy: PluginSettingPrivacyPolicy,
        items: [PluginCatalogItem],
        limits: PluginCatalogLimits
    ) throws {
        let declaredItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var budget = PluginCatalogWorkBudget(maximum: limits.maximumWork)
        guard settingPrivacyPolicy.settingIdentities.count <= limits.maximumPreferenceValueCount else {
            throw PluginCatalogError.tooManyPreferenceValues(
                maximum: limits.maximumPreferenceValueCount
            )
        }
        for item in items {
            for setting in item.settings {
                try budget.consume(setting.key.utf8.count + 1)
                guard
                    let privacy = try settingPrivacyPolicy.classification(
                        for: try item.settingIdentity(forKey: setting.key)
                    )
                else {
                    throw PluginCatalogError.missingTrustedSettingClassification
                }
                switch privacy {
                case .nonSecret:
                    guard setting.defaultValue != nil else {
                        throw PluginCatalogError.nonSecretSettingRequiresDefaultValue
                    }
                case .secret:
                    guard setting.defaultValue == nil else {
                        throw PluginCatalogError.secretSettingCannotHaveDefaultValue
                    }
                }
            }
        }
        for identity in settingPrivacyPolicy.settingIdentities {
            try budget.consume(
                identity.pluginIdentifier.rawValue.utf8.count
                    + identity.settingKey.utf8.count + 1
            )
            guard let item = declaredItems[identity.pluginIdentifier] else {
                throw PluginCatalogError.unexpectedTrustedSettingClassification
            }
            let expectedIdentity: PluginSettingIdentity
            do {
                expectedIdentity = try item.settingIdentity(forKey: identity.settingKey)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw PluginCatalogError.unexpectedTrustedSettingClassification
            }
            guard expectedIdentity == identity else {
                throw PluginCatalogError.unexpectedTrustedSettingClassification
            }
        }
    }
}

private enum PluginCatalogMetadataBinding {
    static func digest(
        item: PluginCatalogItem,
        setting: PluginSettingSchema? = nil
    ) throws -> Data {
        var writer = PluginCatalogDigestWriter()
        try writer.add("MacMerge.PluginCatalogMetadata.v1")
        try writer.add(item.id.rawValue)
        try writer.add(item.version)
        try writer.add(item.capability.rawValue)
        if let setting {
            try writer.add(setting)
        } else {
            try writer.add(item.displayName)
            try writer.add(item.summary)
            try writer.add(item.manualEligible)
            try writer.add(item.automaticEligible)
            try writer.add(item.matchMetadata.fileExtensions)
            try writer.add(item.matchMetadata.contentTypeIdentifiers)
            try writer.add(item.externalToolRuleIdentifier)
            try writer.add(item.settings.count)
            for setting in item.settings {
                try writer.add(setting)
            }
        }
        return writer.finalize()
    }
}

private enum PluginSettingKeychainBinding {
    private static let domain = Data("MacMerge.PluginSettingKeychainCapability.v3".utf8)
    private static let maximumBindingBytes =
        PluginSettingKeychainCapability.maximumPersistentReferenceBytes + 1_024

    static func authenticationInput(
        authorityDomainIdentifier: Data,
        settingIdentity: PluginSettingIdentity,
        operation: PluginSettingKeychainOperation,
        persistentReference: Data,
        revocationGeneration: UInt64,
        expiresAt: Date
    ) throws -> Data {
        var writer = PluginAuthorizationBindingWriter(maximumBytes: maximumBindingBytes)
        try writer.add(domain)
        try writer.add(authorityDomainIdentifier)
        try writer.add(settingIdentity.pluginIdentifier.rawValue)
        try writer.add(settingIdentity.settingKey)
        try writer.add(settingIdentity.catalogMetadataDigest)
        try writer.add(operation.identifier)
        try writer.add(persistentReference)
        try writer.add(revocationGeneration)
        try writer.add(expiresAt.timeIntervalSinceReferenceDate.bitPattern)
        return writer.data
    }
}

private struct PluginCatalogDigestWriter {
    private var hasher = SHA256()

    mutating func add(_ value: String) throws {
        try add(Data(value.utf8))
    }

    mutating func add(_ value: String?) throws {
        try add(value != nil)
        if let value { try add(value) }
    }

    mutating func add(_ value: Bool) throws {
        try add(Data([value ? 1 : 0]))
    }

    mutating func add(_ value: Int) throws {
        try add(Data(UInt64(value).bigEndianBytes))
    }

    mutating func add(_ values: [String]) throws {
        try add(values.count)
        for value in values { try add(value) }
    }

    mutating func add(_ setting: PluginSettingSchema) throws {
        try add(setting.key)
        try add(setting.title)
        try add(setting.summary)
        switch setting.constraint {
        case .boolean:
            try add("boolean")
        case .integer(let minimum, let maximum):
            try add("integer")
            try add(Data(UInt64(bitPattern: minimum).bigEndianBytes))
            try add(Data(UInt64(bitPattern: maximum).bigEndianBytes))
        case .string(let maximumUTF8Bytes):
            try add("string")
            try add(maximumUTF8Bytes)
        case .choice(let choices):
            try add("choice")
            try add(choices)
        }
        try add(setting.defaultValue != nil)
        if let defaultValue = setting.defaultValue {
            switch defaultValue {
            case .boolean(let value):
                try add("boolean")
                try add(value)
            case .integer(let value):
                try add("integer")
                try add(Data(UInt64(bitPattern: value).bigEndianBytes))
            case .string(let value):
                try add("string")
                try add(value)
            case .choice(let value):
                try add("choice")
                try add(value)
            }
        }
    }

    mutating func add(_ field: Data) throws {
        try Task.checkCancellation()
        hasher.update(data: Data(UInt64(field.count).bigEndianBytes))
        hasher.update(data: field)
    }

    mutating func finalize() -> Data {
        Data(hasher.finalize())
    }
}

private enum PluginAuthorizationBinding {
    private static let domain = Data("MacMerge.PluginAuthorization.v3".utf8)
    private static let maximumBindingBytes = 32 * 1_024 * 1_024

    static func rule(
        for item: PluginCatalogItem,
        in policy: ExternalToolPolicy
    ) -> ExternalToolExecutableRule? {
        guard
            let ruleIdentifier = item.externalToolRuleIdentifier,
            let capability = item.capability.externalToolCapability
        else {
            return nil
        }
        return policy.externalExecutableRules.first {
            $0.identifier == ruleIdentifier && $0.capability == capability
        }
    }

    static func authenticationInput(
        item: PluginCatalogItem,
        rule: ExternalToolExecutableRule,
        authorityDomainIdentifier: Data,
        trust: PluginTrustState,
        approval: PluginApprovalState,
        revocationGeneration: UInt64,
        expiresAt: Date
    ) throws -> Data {
        var writer = PluginAuthorizationBindingWriter(maximumBytes: maximumBindingBytes)
        try writer.add(domain)
        try writer.add(authorityDomainIdentifier)
        try writer.add(PluginCatalogMetadataBinding.digest(item: item))
        try writer.add(rule.identifier)
        try writer.add(rule.capability.rawValue)
        try writer.add(rule.executableURL.absoluteString)
        try writer.add(Data(rule.approvedExecutableSHA256))
        try writer.add(rule.permittedWorkingDirectories)
        try writer.add(rule.permittedReadScopes)
        try writer.add(rule.permittedWriteScopes)
        try writer.add(rule.allowedEnvironmentKeys)
        try writer.add(rule.argumentConstraints)
        try writer.add(rule.isolationPolicy.network.rawValue)
        try writer.add(rule.isolationPolicy.childProcesses.rawValue)
        try writer.add(rule.isolationPolicy.interprocessCommunication.rawValue)
        try writer.add(rule.limits.maximumArgumentCount)
        try writer.add(rule.limits.maximumArgumentUTF8Bytes)
        try writer.add(rule.limits.maximumTotalArgumentUTF8Bytes)
        try writer.add(rule.limits.maximumEnvironmentEntryCount)
        try writer.add(rule.limits.maximumEnvironmentKeyUTF8Bytes)
        try writer.add(rule.limits.maximumEnvironmentValueUTF8Bytes)
        try writer.add(rule.limits.maximumTotalEnvironmentUTF8Bytes)
        try writer.add(rule.limits.maximumScopeCount)
        try writer.add(rule.limits.maximumPathUTF8Bytes)
        try writer.add(rule.limits.maximumTotalPathUTF8Bytes)
        try writer.add(Data(rule.limits.timeoutSeconds.bitPattern.bigEndianBytes))
        try writer.add(rule.limits.standardOutputLimitBytes)
        try writer.add(rule.limits.standardErrorLimitBytes)
        try writer.add(rule.limits.combinedOutputLimitBytes)
        try writer.add(trust.rawValue)
        try writer.add(approval.rawValue)
        try writer.add(revocationGeneration)
        try writer.add(expiresAt.timeIntervalSinceReferenceDate.bitPattern)
        return writer.data
    }
}

private struct PluginAuthorizationBindingWriter {
    let maximumBytes: Int
    private(set) var data = Data()

    mutating func add(_ scopes: [ExternalToolPathScope]) throws {
        try add(scopes.count)
        for scope in scopes {
            try add(scope.kind.rawValue)
            try add(scope.url.absoluteString)
        }
    }

    mutating func add(_ values: [String]) throws {
        try add(values.count)
        for value in values {
            try add(value)
        }
    }

    mutating func add(_ constraints: [ExternalToolArgumentConstraint]) throws {
        try add(constraints.count)
        for constraint in constraints {
            try Task.checkCancellation()
            switch constraint {
            case .exact(let value):
                try add("exact")
                try add(value)
            case .oneOf(let values):
                try add("oneOf")
                try add(values)
            case .value:
                try add("value")
            case .readPath:
                try add("readPath")
            case .writePath:
                try add("writePath")
            }
        }
    }

    mutating func add(_ value: Int) throws {
        try add(Data(UInt64(value).bigEndianBytes))
    }

    mutating func add(_ value: UInt64) throws {
        try add(Data(value.bigEndianBytes))
    }

    mutating func add(_ value: String) throws {
        try add(Data(value.utf8))
    }

    mutating func add(_ field: Data) throws {
        try Task.checkCancellation()
        let prefixSize = MemoryLayout<UInt64>.size
        guard
            data.count <= maximumBytes - prefixSize,
            field.count <= maximumBytes - data.count - prefixSize
        else {
            throw PluginCatalogError.workLimitExceeded(maximumWork: maximumBytes)
        }
        var count = UInt64(field.count).bigEndian
        Swift.withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(field)
    }
}

extension FixedWidthInteger {
    fileprivate var bigEndianBytes: [UInt8] {
        Swift.withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}

private enum PluginCatalogCoding {
    static let limitsKey = CodingUserInfoKey(
        rawValue: "com.macmerge.plugin-catalog.decode-limits"
    )!
    static let decodeStateKey = CodingUserInfoKey(
        rawValue: "com.macmerge.plugin-catalog.decode-state"
    )!

}

private final class PluginCatalogDecodeState: @unchecked Sendable {
    let limits: PluginCatalogLimits
    private var settingValueCount = 0

    init(limits: PluginCatalogLimits) {
        self.limits = limits
    }

    func consumeSettingValue() throws {
        guard settingValueCount < limits.maximumPreferenceValueCount else {
            throw PluginCatalogError.tooManyPreferenceValues(
                maximum: limits.maximumPreferenceValueCount
            )
        }
        settingValueCount += 1
    }
}

private struct PluginPreferencesWire: Codable {
    let schemaVersion: Int
    let enabledPluginIdentifiers: [String]
    let automaticPluginIdentifiers: [String]
    let preferredAutomaticPluginIdentifiers: [String]
    let settings: [PluginSettingsWire]

    private static let keys: Set<String> = [
        "schemaVersion",
        "enabledPluginIdentifiers",
        "automaticPluginIdentifiers",
        "preferredAutomaticPluginIdentifiers",
        "settings"
    ]

    init(_ preferences: PluginCatalogPreferences) throws {
        schemaVersion = PluginCatalogPreferences.currentSchemaVersion
        enabledPluginIdentifiers = try pluginCatalogCancellableSorted(
            preferences.enabledPluginIdentifiers,
            by: <
        ).map(\.rawValue)
        automaticPluginIdentifiers = try pluginCatalogCancellableSorted(
            preferences.automaticPluginIdentifiers,
            by: <
        ).map(\.rawValue)
        preferredAutomaticPluginIdentifiers = preferences.preferredAutomaticPluginIdentifiers.map(
            \.rawValue
        )
        settings = try pluginCatalogCancellableSorted(
            preferences.settingValues.keys,
            by: <
        ).map { identifier in
            try PluginSettingsWire(
                pluginIdentifier: identifier.rawValue,
                values: pluginCatalogCancellableSorted(
                    (preferences.settingValues[identifier] ?? [:]).keys,
                    by: PluginCatalogValidation.utf8Precedes
                ).map { key in
                    PluginSettingValueWire(
                        key: key,
                        value: preferences.settingValues[identifier]![key]!
                    )
                }
            )
        }
    }

    init(from decoder: Decoder) throws {
        guard
            let limits = decoder.userInfo[PluginCatalogCoding.limitsKey]
                as? PluginCatalogLimits,
            decoder.userInfo[PluginCatalogCoding.decodeStateKey]
                as? PluginCatalogDecodeState != nil
        else {
            throw PluginCatalogError.boundedDecodingRequired
        }
        let container = try decoder.container(keyedBy: PluginWireKey.self)
        try PluginWireKey.requireExactKeys(container, expected: Self.keys)
        schemaVersion = try container.decode(Int.self, forKey: PluginWireKey("schemaVersion"))
        guard schemaVersion == PluginCatalogPreferences.currentSchemaVersion else {
            throw PluginCatalogError.unsupportedSchemaVersion(schemaVersion)
        }
        enabledPluginIdentifiers = try Self.decodeArray(
            from: container,
            forKey: "enabledPluginIdentifiers",
            maximum: limits.maximumPreferencePluginCount
        )
        automaticPluginIdentifiers = try Self.decodeArray(
            from: container,
            forKey: "automaticPluginIdentifiers",
            maximum: limits.maximumPreferencePluginCount
        )
        preferredAutomaticPluginIdentifiers = try Self.decodeArray(
            from: container,
            forKey: "preferredAutomaticPluginIdentifiers",
            maximum: limits.maximumPreferencePluginCount
        )
        settings = try Self.decodeArray(
            from: container,
            forKey: "settings",
            maximum: limits.maximumPreferencePluginCount
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PluginWireKey.self)
        try container.encode(schemaVersion, forKey: PluginWireKey("schemaVersion"))
        try container.encode(
            enabledPluginIdentifiers,
            forKey: PluginWireKey("enabledPluginIdentifiers")
        )
        try container.encode(
            automaticPluginIdentifiers,
            forKey: PluginWireKey("automaticPluginIdentifiers")
        )
        try container.encode(
            preferredAutomaticPluginIdentifiers,
            forKey: PluginWireKey("preferredAutomaticPluginIdentifiers")
        )
        try container.encode(settings, forKey: PluginWireKey("settings"))
    }

    func preferences(limits: PluginCatalogLimits) throws -> PluginCatalogPreferences {
        let enabled = try identifiers(enabledPluginIdentifiers)
        let automatic = try identifiers(automaticPluginIdentifiers)
        let preferred = try preferredAutomaticPluginIdentifiers.map(PluginIdentifier.init)
        guard Set(enabled).count == enabled.count, Set(automatic).count == automatic.count else {
            throw PluginCatalogError.duplicatePersistenceKey
        }
        var values: [PluginIdentifier: [String: PluginSettingValue]] = [:]
        for namespace in settings {
            try Task.checkCancellation()
            let identifier = try PluginIdentifier(namespace.pluginIdentifier)
            guard values[identifier] == nil else {
                throw PluginCatalogError.duplicatePersistenceKey
            }
            var namespaceValues: [String: PluginSettingValue] = [:]
            for value in namespace.values {
                let decodedValue = try value.value
                guard namespaceValues.updateValue(decodedValue, forKey: value.key) == nil else {
                    throw PluginCatalogError.duplicatePersistenceKey
                }
            }
            values[identifier] = namespaceValues
        }
        return try PluginCatalogPreferences(
            enabledPluginIdentifiers: Set(enabled),
            automaticPluginIdentifiers: Set(automatic),
            preferredAutomaticPluginIdentifiers: preferred,
            settingValues: values,
            limits: limits
        )
    }

    func canonicalEncodedData(limits: PluginCatalogLimits) throws -> Data {
        var valueCount = 6
        valueCount += enabledPluginIdentifiers.count
        valueCount += automaticPluginIdentifiers.count
        valueCount += preferredAutomaticPluginIdentifiers.count
        valueCount += settings.count * 3
        for namespace in settings {
            valueCount += namespace.values.count * 4
        }
        let requiredDepth: Int
        if settings.contains(where: { !$0.values.isEmpty }) {
            requiredDepth = 6
        } else if settings.isEmpty {
            requiredDepth =
                enabledPluginIdentifiers.isEmpty
                    && automaticPluginIdentifiers.isEmpty
                    && preferredAutomaticPluginIdentifiers.isEmpty ? 2 : 3
        } else {
            requiredDepth = 4
        }
        guard limits.maximumJSONDepth >= requiredDepth else {
            throw PluginCatalogError.jsonTooDeep(maximumDepth: limits.maximumJSONDepth)
        }
        guard valueCount <= limits.maximumJSONValueCount else {
            throw PluginCatalogError.jsonValueLimitExceeded(
                maximumValues: limits.maximumJSONValueCount
            )
        }
        var output = PluginCatalogOutputBudget(maximum: limits.maximumPersistenceBytes)
        try output.addASCII("{\"automaticPluginIdentifiers\":[")
        for (index, identifier) in automaticPluginIdentifiers.enumerated() {
            if index > 0 { try output.addASCII(",") }
            try output.addJSONString(identifier)
        }
        try output.addASCII("],\"enabledPluginIdentifiers\":[")
        for (index, identifier) in enabledPluginIdentifiers.enumerated() {
            if index > 0 { try output.addASCII(",") }
            try output.addJSONString(identifier)
        }
        try output.addASCII("],\"preferredAutomaticPluginIdentifiers\":[")
        for (index, identifier) in preferredAutomaticPluginIdentifiers.enumerated() {
            if index > 0 { try output.addASCII(",") }
            try output.addJSONString(identifier)
        }
        try output.addASCII("],\"schemaVersion\":")
        try output.addASCII(String(schemaVersion))
        try output.addASCII(",\"settings\":[")
        for (namespaceIndex, namespace) in settings.enumerated() {
            if namespaceIndex > 0 { try output.addASCII(",") }
            try output.addASCII("{\"pluginIdentifier\":")
            try output.addJSONString(namespace.pluginIdentifier)
            try output.addASCII(",\"values\":[")
            for (valueIndex, value) in namespace.values.enumerated() {
                if valueIndex > 0 { try output.addASCII(",") }
                try value.encodeCanonicalJSON(to: &output)
            }
            try output.addASCII("]}")
        }
        try output.addASCII("]}")
        return output.data
    }

    private func identifiers(_ values: [String]) throws -> [PluginIdentifier] {
        try values.map(PluginIdentifier.init)
    }

    private static func decodeArray<Value: Decodable>(
        from container: KeyedDecodingContainer<PluginWireKey>,
        forKey key: String,
        maximum: Int
    ) throws -> [Value] {
        var nested = try container.nestedUnkeyedContainer(forKey: PluginWireKey(key))
        var result: [Value] = []
        result.reserveCapacity(min(nested.count ?? 0, maximum))
        while !nested.isAtEnd {
            try Task.checkCancellation()
            guard result.count < maximum else {
                throw PluginCatalogError.tooManyPreferencePlugins(maximum: maximum)
            }
            result.append(try nested.decode(Value.self))
        }
        return result
    }
}

private struct PluginSettingsWire: Codable {
    let pluginIdentifier: String
    let values: [PluginSettingValueWire]

    private static let keys: Set<String> = ["pluginIdentifier", "values"]

    init(pluginIdentifier: String, values: [PluginSettingValueWire]) {
        self.pluginIdentifier = pluginIdentifier
        self.values = values
    }

    init(from decoder: Decoder) throws {
        guard
            let state = decoder.userInfo[PluginCatalogCoding.decodeStateKey]
                as? PluginCatalogDecodeState
        else {
            throw PluginCatalogError.boundedDecodingRequired
        }
        let container = try decoder.container(keyedBy: PluginWireKey.self)
        try PluginWireKey.requireExactKeys(container, expected: Self.keys)
        pluginIdentifier = try container.decode(String.self, forKey: PluginWireKey("pluginIdentifier"))
        var nested = try container.nestedUnkeyedContainer(forKey: PluginWireKey("values"))
        var decodedValues: [PluginSettingValueWire] = []
        decodedValues.reserveCapacity(
            min(nested.count ?? 0, state.limits.maximumPreferenceValueCount)
        )
        while !nested.isAtEnd {
            try Task.checkCancellation()
            try state.consumeSettingValue()
            decodedValues.append(try nested.decode(PluginSettingValueWire.self))
        }
        values = decodedValues
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PluginWireKey.self)
        try container.encode(pluginIdentifier, forKey: PluginWireKey("pluginIdentifier"))
        try container.encode(values, forKey: PluginWireKey("values"))
    }
}

private struct PluginSettingValueWire: Codable {
    let key: String
    let kind: PluginSettingValueKind
    let booleanValue: Bool?
    let integerValue: Int64?
    let stringValue: String?

    init(key: String, value: PluginSettingValue) {
        self.key = key
        kind = value.kind
        switch value {
        case .boolean(let value):
            booleanValue = value
            integerValue = nil
            stringValue = nil
        case .integer(let value):
            booleanValue = nil
            integerValue = value
            stringValue = nil
        case .string(let value), .choice(let value):
            booleanValue = nil
            integerValue = nil
            stringValue = value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PluginWireKey.self)
        let decodedKind = try container.decode(
            PluginSettingValueKind.self,
            forKey: PluginWireKey("kind")
        )
        let expected: Set<String>
        switch decodedKind {
        case .boolean: expected = ["key", "kind", "booleanValue"]
        case .integer: expected = ["key", "kind", "integerValue"]
        case .string, .choice: expected = ["key", "kind", "stringValue"]
        }
        try PluginWireKey.requireExactKeys(container, expected: expected)
        key = try container.decode(String.self, forKey: PluginWireKey("key"))
        kind = decodedKind
        booleanValue = try container.decodeIfPresent(
            Bool.self,
            forKey: PluginWireKey("booleanValue")
        )
        integerValue = try container.decodeIfPresent(
            Int64.self,
            forKey: PluginWireKey("integerValue")
        )
        stringValue = try container.decodeIfPresent(
            String.self,
            forKey: PluginWireKey("stringValue")
        )
        _ = try value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PluginWireKey.self)
        try container.encode(key, forKey: PluginWireKey("key"))
        try container.encode(kind, forKey: PluginWireKey("kind"))
        switch kind {
        case .boolean:
            try container.encode(booleanValue, forKey: PluginWireKey("booleanValue"))
        case .integer:
            try container.encode(integerValue, forKey: PluginWireKey("integerValue"))
        case .string, .choice:
            try container.encode(stringValue, forKey: PluginWireKey("stringValue"))
        }
    }

    var value: PluginSettingValue {
        get throws {
            switch kind {
            case .boolean:
                guard let booleanValue, integerValue == nil, stringValue == nil else {
                    throw PluginCatalogError.malformedPersistence
                }
                return .boolean(booleanValue)
            case .integer:
                guard let integerValue, booleanValue == nil, stringValue == nil else {
                    throw PluginCatalogError.malformedPersistence
                }
                return .integer(integerValue)
            case .string:
                guard let stringValue, booleanValue == nil, integerValue == nil else {
                    throw PluginCatalogError.malformedPersistence
                }
                return .string(stringValue)
            case .choice:
                guard let stringValue, booleanValue == nil, integerValue == nil else {
                    throw PluginCatalogError.malformedPersistence
                }
                return .choice(stringValue)
            }
        }
    }

    func encodeCanonicalJSON(to output: inout PluginCatalogOutputBudget) throws {
        switch kind {
        case .boolean:
            guard let booleanValue else { throw PluginCatalogError.malformedPersistence }
            try output.addASCII("{\"booleanValue\":")
            try output.addASCII(booleanValue ? "true" : "false")
            try output.addASCII(",\"key\":")
            try output.addJSONString(key)
            try output.addASCII(",\"kind\":\"boolean\"}")
        case .integer:
            guard let integerValue else { throw PluginCatalogError.malformedPersistence }
            try output.addASCII("{\"integerValue\":")
            try output.addASCII(String(integerValue))
            try output.addASCII(",\"key\":")
            try output.addJSONString(key)
            try output.addASCII(",\"kind\":\"integer\"}")
        case .string, .choice:
            guard let stringValue else { throw PluginCatalogError.malformedPersistence }
            try output.addASCII("{\"key\":")
            try output.addJSONString(key)
            try output.addASCII(",\"kind\":")
            try output.addJSONString(kind.rawValue)
            try output.addASCII(",\"stringValue\":")
            try output.addJSONString(stringValue)
            try output.addASCII("}")
        }
    }
}

private struct PluginWireKey: CodingKey, Hashable {
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

    static func requireExactKeys(
        _ container: KeyedDecodingContainer<PluginWireKey>,
        expected: Set<String>
    ) throws {
        let actual = Set(container.allKeys.map(\.stringValue))
        guard actual == expected else { throw PluginCatalogError.unknownPersistenceKey }
    }
}

private struct PluginCatalogWorkBudget {
    let maximum: Int
    private(set) var consumed = 0

    mutating func consume(_ amount: Int) throws {
        try Task.checkCancellation()
        guard amount >= 0, amount <= maximum - consumed else {
            throw PluginCatalogError.workLimitExceeded(maximumWork: maximum)
        }
        consumed += amount
    }
}

private func pluginCatalogCancellableSorted<Values: Sequence>(
    _ values: Values,
    by areInIncreasingOrder: (Values.Element, Values.Element) -> Bool
) throws -> [Values.Element] {
    var source: [Values.Element] = []
    source.reserveCapacity(values.underestimatedCount)
    for value in values {
        if source.count.isMultiple(of: 256) { try Task.checkCancellation() }
        source.append(value)
    }
    guard source.count > 1 else {
        try Task.checkCancellation()
        return source
    }
    var destination = source
    var width = 1
    while width < source.count {
        var lowerBound = 0
        while lowerBound < source.count {
            try Task.checkCancellation()
            let middle = min(lowerBound + width, source.count)
            let upperBound = min(lowerBound + width + width, source.count)
            var left = lowerBound
            var right = middle
            var output = lowerBound
            while output < upperBound {
                if output.isMultiple(of: 256) { try Task.checkCancellation() }
                if right == upperBound
                    || (left < middle && !areInIncreasingOrder(source[right], source[left]))
                {
                    destination[output] = source[left]
                    left += 1
                } else {
                    destination[output] = source[right]
                    right += 1
                }
                output += 1
            }
            lowerBound = upperBound
        }
        swap(&source, &destination)
        guard width <= source.count / 2 else { break }
        width *= 2
    }
    try Task.checkCancellation()
    return source
}

private struct PluginCatalogOutputBudget {
    let maximum: Int
    private(set) var count = 0
    private(set) var data = Data()

    mutating func add(_ amount: Int) throws {
        try Task.checkCancellation()
        guard amount >= 0, amount <= maximum - count else {
            throw PluginCatalogError.persistenceOutputTooLarge(maximumBytes: maximum)
        }
        count += amount
    }

    mutating func addJSONString(_ value: String) throws {
        try addASCII("\"")
        for scalar in value.unicodeScalars {
            try Task.checkCancellation()
            switch scalar.value {
            case 0x08: try addASCII("\\b")
            case 0x09: try addASCII("\\t")
            case 0x0A: try addASCII("\\n")
            case 0x0C: try addASCII("\\f")
            case 0x0D: try addASCII("\\r")
            case 0x22: try addASCII("\\\"")
            case 0x5C: try addASCII("\\\\")
            case 0x00...0x1F:
                let hex = String(scalar.value, radix: 16, uppercase: false)
                try addASCII("\\u" + String(repeating: "0", count: 4 - hex.count) + hex)
            default:
                try addUTF8(String(scalar))
            }
        }
        try addASCII("\"")
    }

    mutating func addASCII(_ value: String) throws {
        precondition(value.unicodeScalars.allSatisfy(\.isASCII))
        try append(value.utf8)
    }

    private mutating func addUTF8(_ value: String) throws {
        try append(value.utf8)
    }

    private mutating func append<Bytes: Collection>(_ bytes: Bytes) throws
    where Bytes.Element == UInt8 {
        try add(bytes.count)
        data.append(contentsOf: bytes)
    }
}

private enum PluginCatalogValidation {
    static func compareUTF8(_ left: String, _ right: String) -> Int {
        let leftBytes = left.utf8
        let rightBytes = right.utf8
        var leftIndex = leftBytes.startIndex
        var rightIndex = rightBytes.startIndex
        while leftIndex != leftBytes.endIndex, rightIndex != rightBytes.endIndex {
            let leftByte = leftBytes[leftIndex]
            let rightByte = rightBytes[rightIndex]
            if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
            leftBytes.formIndex(after: &leftIndex)
            rightBytes.formIndex(after: &rightIndex)
        }
        if leftIndex == leftBytes.endIndex, rightIndex == rightBytes.endIndex { return 0 }
        return leftIndex == leftBytes.endIndex ? -1 : 1
    }

    static func utf8Precedes(_ left: String, _ right: String) -> Bool {
        compareUTF8(left, right) < 0
    }

    static func isIdentifier(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        let bytes = value.utf8
        guard
            !bytes.isEmpty,
            bytes.count <= maximumUTF8Bytes,
            let first = bytes.first,
            isASCIIAlphaNumeric(first)
        else {
            return false
        }
        return bytes.allSatisfy {
            isASCIIAlphaNumeric($0) || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }

    static func isSettingKey(_ value: String) -> Bool {
        isIdentifier(value, maximumUTF8Bytes: 128)
    }

    static func validate(
        item: PluginCatalogItem,
        limits: PluginCatalogLimits,
        budget: inout PluginCatalogWorkBudget
    ) throws {
        try budget.consume(item.id.rawValue.utf8.count + item.version.utf8.count + 1)
        guard isIdentifier(item.id.rawValue, maximumUTF8Bytes: PluginIdentifier.maximumUTF8Bytes) else {
            throw PluginCatalogError.invalidIdentifier
        }
        try validateDisplayText(
            item.displayName,
            field: "displayName",
            limits: limits,
            budget: &budget
        )
        if let summary = item.summary {
            try validateDisplayText(
                summary,
                field: "summary",
                limits: limits,
                budget: &budget
            )
        }
        guard isVersion(item.version, maximumUTF8Bytes: limits.maximumMetadataStringUTF8Bytes) else {
            throw PluginCatalogError.invalidMetadata(field: "version")
        }
        guard item.settings.count <= limits.maximumSettingsPerItem else {
            throw PluginCatalogError.tooManySettings(maximum: limits.maximumSettingsPerItem)
        }
        var seen: Set<String> = []
        for setting in item.settings {
            try budget.consume(setting.key.utf8.count + 1)
            guard seen.insert(setting.key).inserted else {
                throw PluginCatalogError.duplicateSettingKey
            }
            try validate(settingSchema: setting, limits: limits, budget: &budget)
        }
        guard
            item.matchMetadata.fileExtensions.count <= limits.maximumMatchValuesPerItem,
            item.matchMetadata.contentTypeIdentifiers.count
                <= limits.maximumMatchValuesPerItem
                - item.matchMetadata.fileExtensions.count
        else {
            throw PluginCatalogError.tooManyMatchValues(
                maximum: limits.maximumMatchValuesPerItem
            )
        }
        _ = try canonicalFileExtensions(
            item.matchMetadata.fileExtensions,
            limits: limits,
            budget: &budget
        )
        _ = try canonicalContentTypes(
            item.matchMetadata.contentTypeIdentifiers,
            limits: limits,
            budget: &budget
        )
        if let ruleIdentifier = item.externalToolRuleIdentifier {
            try budget.consume(ruleIdentifier.utf8.count + 1)
            guard isIdentifier(ruleIdentifier, maximumUTF8Bytes: 128) else {
                throw PluginCatalogError.invalidExternalToolRuleIdentifier
            }
        }
        if item.capability == .transform, item.externalToolRuleIdentifier != nil {
            throw PluginCatalogError.invalidExternalToolRuleIdentifier
        }
    }

    static func validate(
        settingSchema: PluginSettingSchema,
        limits: PluginCatalogLimits,
        budget: inout PluginCatalogWorkBudget
    ) throws {
        try budget.consume(settingSchema.key.utf8.count + 1)
        guard isSettingKey(settingSchema.key) else {
            throw PluginCatalogError.invalidSettingSchema
        }
        try validateDisplayText(
            settingSchema.title,
            field: "setting.title",
            limits: limits,
            budget: &budget
        )
        if let summary = settingSchema.summary {
            try validateDisplayText(
                summary,
                field: "setting.summary",
                limits: limits,
                budget: &budget
            )
        }
        switch settingSchema.constraint {
        case .boolean:
            break
        case .integer(let minimum, let maximum):
            guard minimum <= maximum else {
                throw PluginCatalogError.invalidSettingSchema
            }
        case .string(let maximumUTF8Bytes):
            guard
                maximumUTF8Bytes >= 0,
                maximumUTF8Bytes <= limits.maximumPreferenceStringUTF8Bytes
            else {
                throw PluginCatalogError.invalidSettingSchema
            }
        case .choice(let choices):
            guard !choices.isEmpty, choices.count <= limits.maximumChoiceCount else {
                if choices.count > limits.maximumChoiceCount {
                    throw PluginCatalogError.tooManyChoices(maximum: limits.maximumChoiceCount)
                }
                throw PluginCatalogError.invalidSettingSchema
            }
            var seen: Set<String> = []
            for choice in choices {
                guard choice.utf8.count <= limits.maximumPreferenceStringUTF8Bytes else {
                    throw PluginCatalogError.invalidSettingSchema
                }
                try validateDisplayText(
                    choice,
                    field: "setting.choice",
                    limits: limits,
                    budget: &budget
                )
                guard seen.insert(choice).inserted else {
                    throw PluginCatalogError.invalidSettingSchema
                }
            }
        }
        if let defaultValue = settingSchema.defaultValue {
            try validate(
                value: defaultValue,
                against: settingSchema,
                limits: limits,
                budget: &budget
            )
        }
    }

    static func validate(
        value: PluginSettingValue,
        against schema: PluginSettingSchema,
        limits: PluginCatalogLimits,
        budget: inout PluginCatalogWorkBudget
    ) throws {
        guard value.kind == schema.constraint.kind else {
            throw PluginCatalogError.invalidSettingValue
        }
        switch (value, schema.constraint) {
        case (.boolean, .boolean):
            try budget.consume(1)
        case (.integer(let value), .integer(let minimum, let maximum)):
            try budget.consume(1)
            guard (minimum...maximum).contains(value) else {
                throw PluginCatalogError.invalidSettingValue
            }
        case (.string(let value), .string(let maximumUTF8Bytes)):
            try budget.consume(value.utf8.count + 1)
            guard value.utf8.count <= maximumUTF8Bytes, isSafePreferenceString(value) else {
                throw PluginCatalogError.invalidSettingValue
            }
        case (.choice(let value), .choice(let choices)):
            var matches = false
            for choice in choices {
                try budget.consume(value.utf8.count + choice.utf8.count + 1)
                if choice == value {
                    matches = true
                    break
                }
            }
            guard matches else {
                throw PluginCatalogError.invalidSettingValue
            }
        default:
            throw PluginCatalogError.invalidSettingValue
        }
    }

    static func validate(
        preferenceValue: PluginSettingValue,
        key: String,
        limits: PluginCatalogLimits,
        budget: inout PluginCatalogWorkBudget
    ) throws {
        switch preferenceValue {
        case .boolean, .integer:
            try budget.consume(1)
        case .string(let value), .choice(let value):
            try budget.consume(value.utf8.count + 1)
            guard
                value.utf8.count <= limits.maximumPreferenceStringUTF8Bytes,
                isSafePreferenceString(value)
            else {
                throw PluginCatalogError.invalidSettingValue
            }
        }
    }

    static func canonicalFileExtensions(
        _ values: [String],
        limits: PluginCatalogLimits,
        budget: inout PluginCatalogWorkBudget
    ) throws -> [String] {
        guard values.count <= limits.maximumMatchValuesPerItem else {
            throw PluginCatalogError.tooManyMatchValues(maximum: limits.maximumMatchValuesPerItem)
        }
        var result: [String] = []
        result.reserveCapacity(values.count)
        var seen: Set<String> = []
        for value in values {
            try budget.consume(value.utf8.count + 1)
            let canonical = try canonicalFileExtension(value)
            guard canonical.utf8.count <= limits.maximumMetadataStringUTF8Bytes else {
                throw PluginCatalogError.invalidMetadata(field: "fileExtension")
            }
            guard seen.insert(canonical).inserted else {
                throw PluginCatalogError.duplicateMatchValue
            }
            result.append(canonical)
        }
        return try pluginCatalogCancellableSorted(result, by: utf8Precedes)
    }

    static func canonicalContentTypes(
        _ values: [String],
        limits: PluginCatalogLimits,
        budget: inout PluginCatalogWorkBudget
    ) throws -> [String] {
        guard values.count <= limits.maximumMatchValuesPerItem else {
            throw PluginCatalogError.tooManyMatchValues(maximum: limits.maximumMatchValuesPerItem)
        }
        var result: [String] = []
        result.reserveCapacity(values.count)
        var seen: Set<String> = []
        for value in values {
            try budget.consume(value.utf8.count + 1)
            let canonical = try canonicalContentType(value)
            guard canonical.utf8.count <= limits.maximumMetadataStringUTF8Bytes else {
                throw PluginCatalogError.invalidMetadata(field: "contentTypeIdentifier")
            }
            guard seen.insert(canonical).inserted else {
                throw PluginCatalogError.duplicateMatchValue
            }
            result.append(canonical)
        }
        return try pluginCatalogCancellableSorted(result, by: utf8Precedes)
    }

    static func canonicalFileExtension(_ value: String) throws -> String {
        guard value.utf8.count <= 257 else {
            throw PluginCatalogError.invalidMetadata(field: "fileExtension")
        }
        var bytes = Array(value.utf8)
        if bytes.first == 0x2E { bytes.removeFirst() }
        guard
            !bytes.isEmpty,
            bytes.count <= 256,
            bytes.first != 0x2E,
            bytes.allSatisfy({
                isASCIIAlphaNumeric($0)
                    || $0 == 0x2B || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
            })
        else {
            throw PluginCatalogError.invalidMetadata(field: "fileExtension")
        }
        return String(decoding: bytes.map(asciiLowercased), as: UTF8.self)
    }

    static func canonicalContentType(_ value: String) throws -> String {
        guard value.utf8.count <= 256 else {
            throw PluginCatalogError.invalidMetadata(field: "contentTypeIdentifier")
        }
        let bytes = Array(value.utf8)
        guard
            !bytes.isEmpty,
            bytes.count <= 256,
            bytes.allSatisfy({ isASCIIAlphaNumeric($0) || $0 == 0x2D || $0 == 0x2E })
        else {
            throw PluginCatalogError.invalidMetadata(field: "contentTypeIdentifier")
        }
        return String(decoding: bytes.map(asciiLowercased), as: UTF8.self)
    }

    private static func validateDisplayText(
        _ value: String,
        field: String,
        limits: PluginCatalogLimits,
        budget: inout PluginCatalogWorkBudget
    ) throws {
        try budget.consume(value.utf8.count + 1)
        guard
            !value.isEmpty,
            value.utf8.count <= limits.maximumMetadataStringUTF8Bytes,
            isSafeDisplayText(value)
        else {
            throw PluginCatalogError.invalidMetadata(field: field)
        }
    }

    private static func isVersion(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        let bytes = value.utf8
        return !bytes.isEmpty
            && bytes.count <= min(maximumUTF8Bytes, 256)
            && bytes.allSatisfy {
                isASCIIAlphaNumeric($0) || $0 == 0x2B || $0 == 0x2D || $0 == 0x2E
            }
    }

    private static func isSafeDisplayText(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate:
                false
            default:
                !scalar.properties.isDefaultIgnorableCodePoint
            }
        }
    }

    private static func isSafePreferenceString(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate:
                false
            default:
                true
            }
        }
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x5A).contains(byte)
            || (0x61...0x7A).contains(byte)
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
    }
}

enum PluginCatalogTestHooks {
    @TaskLocal static var persistenceScanCheckpoint: (@Sendable (Int) -> Void)?
}

private struct PluginCatalogJSONScanner {
    let bytes: UnsafeBufferPointer<UInt8>
    let limits: PluginCatalogLimits
    var index = 0
    var valueCount = 0
    var work: PluginCatalogWorkBudget

    init(bytes: UnsafeBufferPointer<UInt8>, limits: PluginCatalogLimits) {
        self.bytes = bytes
        self.limits = limits
        work = PluginCatalogWorkBudget(maximum: limits.maximumWork)
    }

    mutating func validate() throws {
        try work.consume(bytes.count)
        try parseValue(depth: 1)
        try skipWhitespace()
        guard index == bytes.count else { throw PluginCatalogError.malformedPersistence }
    }

    private mutating func parseValue(depth: Int) throws {
        try countValue(depth: depth)
        try skipWhitespace()
        guard let byte = current else { throw PluginCatalogError.malformedPersistence }
        switch byte {
        case 0x7B: try parseObject(depth: depth)
        case 0x5B: try parseArray(depth: depth)
        case 0x22: _ = try parseString()
        case 0x74: try consumeLiteral([0x74, 0x72, 0x75, 0x65])
        case 0x66: try consumeLiteral([0x66, 0x61, 0x6C, 0x73, 0x65])
        case 0x6E: try consumeLiteral([0x6E, 0x75, 0x6C, 0x6C])
        case 0x2D, 0x30...0x39: try parseNumber()
        default: throw PluginCatalogError.malformedPersistence
        }
    }

    private mutating func parseObject(depth: Int) throws {
        index += 1
        try skipWhitespace()
        if consumeIfPresent(0x7D) { return }
        var keys: Set<String> = []
        while true {
            guard current == 0x22 else { throw PluginCatalogError.malformedPersistence }
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw PluginCatalogError.duplicatePersistenceKey
            }
            try skipWhitespace()
            guard consumeIfPresent(0x3A) else { throw PluginCatalogError.malformedPersistence }
            try parseValue(depth: depth + 1)
            try skipWhitespace()
            if consumeIfPresent(0x7D) { return }
            guard consumeIfPresent(0x2C) else { throw PluginCatalogError.malformedPersistence }
            try skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        index += 1
        try skipWhitespace()
        if consumeIfPresent(0x5D) { return }
        while true {
            try parseValue(depth: depth + 1)
            try skipWhitespace()
            if consumeIfPresent(0x5D) { return }
            guard consumeIfPresent(0x2C) else { throw PluginCatalogError.malformedPersistence }
            try skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        guard consumeIfPresent(0x22) else { throw PluginCatalogError.malformedPersistence }
        var decoded: [UInt8] = []
        decoded.reserveCapacity(32)
        while let byte = current {
            if index.isMultiple(of: 4_096) { try checkCancellation() }
            index += 1
            switch byte {
            case 0x22:
                guard let value = String(bytes: decoded, encoding: .utf8) else {
                    throw PluginCatalogError.malformedPersistence
                }
                return value
            case 0x00...0x1F:
                throw PluginCatalogError.malformedPersistence
            case 0x5C:
                try parseEscape(into: &decoded)
            default:
                decoded.append(byte)
            }
            guard decoded.count <= limits.maximumPreferenceStringUTF8Bytes else {
                throw PluginCatalogError.persistenceDataTooLarge(
                    maximumBytes: limits.maximumPersistenceBytes
                )
            }
        }
        throw PluginCatalogError.malformedPersistence
    }

    private mutating func parseEscape(into decoded: inout [UInt8]) throws {
        guard let escaped = current else { throw PluginCatalogError.malformedPersistence }
        index += 1
        switch escaped {
        case 0x22, 0x5C, 0x2F: decoded.append(escaped)
        case 0x62: decoded.append(0x08)
        case 0x66: decoded.append(0x0C)
        case 0x6E: decoded.append(0x0A)
        case 0x72: decoded.append(0x0D)
        case 0x74: decoded.append(0x09)
        case 0x75:
            let first = try parseHexQuad()
            let scalarValue: UInt32
            if (0xD800...0xDBFF).contains(first) {
                guard consumeIfPresent(0x5C), consumeIfPresent(0x75) else {
                    throw PluginCatalogError.malformedPersistence
                }
                let second = try parseHexQuad()
                guard (0xDC00...0xDFFF).contains(second) else {
                    throw PluginCatalogError.malformedPersistence
                }
                scalarValue = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
            } else {
                guard !(0xDC00...0xDFFF).contains(first) else {
                    throw PluginCatalogError.malformedPersistence
                }
                scalarValue = first
            }
            guard let scalar = Unicode.Scalar(scalarValue) else {
                throw PluginCatalogError.malformedPersistence
            }
            decoded.append(contentsOf: String(scalar).utf8)
        default:
            throw PluginCatalogError.malformedPersistence
        }
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current, let digit = hexValue(byte) else {
                throw PluginCatalogError.malformedPersistence
            }
            index += 1
            value = value * 16 + digit
        }
        return value
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = consumeIfPresent(0x2D)
        try requireNumberLimit(from: start)
        guard let first = current else { throw PluginCatalogError.malformedPersistence }
        if first == 0x30 {
            index += 1
            try requireNumberLimit(from: start)
            if let next = current, (0x30...0x39).contains(next) {
                throw PluginCatalogError.malformedPersistence
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw PluginCatalogError.malformedPersistence
            }
            while current.map({ (0x30...0x39).contains($0) }) == true {
                index += 1
                try requireNumberLimit(from: start)
            }
        }
        if consumeIfPresent(0x2E) {
            try requireNumberLimit(from: start)
            guard current.map({ (0x30...0x39).contains($0) }) == true else {
                throw PluginCatalogError.malformedPersistence
            }
            while current.map({ (0x30...0x39).contains($0) }) == true {
                index += 1
                try requireNumberLimit(from: start)
            }
        }
        if current == 0x65 || current == 0x45 {
            index += 1
            try requireNumberLimit(from: start)
            if current == 0x2B || current == 0x2D {
                index += 1
                try requireNumberLimit(from: start)
            }
            guard current.map({ (0x30...0x39).contains($0) }) == true else {
                throw PluginCatalogError.malformedPersistence
            }
            while current.map({ (0x30...0x39).contains($0) }) == true {
                index += 1
                try requireNumberLimit(from: start)
            }
        }
    }

    private func requireNumberLimit(from start: Int) throws {
        try Task.checkCancellation()
        guard index - start <= 64 else { throw PluginCatalogError.malformedPersistence }
    }

    private mutating func countValue(depth: Int) throws {
        guard depth <= limits.maximumJSONDepth else {
            throw PluginCatalogError.jsonTooDeep(maximumDepth: limits.maximumJSONDepth)
        }
        guard valueCount < limits.maximumJSONValueCount else {
            throw PluginCatalogError.jsonValueLimitExceeded(
                maximumValues: limits.maximumJSONValueCount
            )
        }
        valueCount += 1
        try work.consume(1)
    }

    private mutating func consumeLiteral(_ literal: [UInt8]) throws {
        guard literal.count <= bytes.count - index else {
            throw PluginCatalogError.malformedPersistence
        }
        for byte in literal {
            guard current == byte else { throw PluginCatalogError.malformedPersistence }
            index += 1
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            if index.isMultiple(of: 4_096) { try checkCancellation() }
            index += 1
        }
    }

    private func checkCancellation() throws {
        PluginCatalogTestHooks.persistenceScanCheckpoint?(index)
        try Task.checkCancellation()
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        index += 1
        return true
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func hexValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case 0x30...0x39: UInt32(byte - 0x30)
        case 0x41...0x46: UInt32(byte - 0x41 + 10)
        case 0x61...0x66: UInt32(byte - 0x61 + 10)
        default: nil
        }
    }
}
