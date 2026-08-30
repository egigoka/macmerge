import Darwin
import Foundation

private struct HelpCatalogFileIdentity: Equatable, Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let generation: UInt64
}

private struct HelpCatalogBundledResourceIdentity: Equatable, Hashable, Sendable {
    let resolvedURL: URL
    let relativePath: String
    let resolverProvenance: UUID
    let trustRootURL: URL
    let trustRootFileIdentity: HelpCatalogFileIdentity
    let resourceFileIdentity: HelpCatalogFileIdentity
}

private struct HelpCatalogLinkWireIdentity: Hashable, Sendable {
    let scheme: HelpCatalogLinkScheme
    let target: String
    let fragment: String?
    let labelLocalizationKey: String?
}

/// Stable content roles understood by Help and About presentation code.
public enum HelpCatalogTopicKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case helpBook
    case command
    case dialog
    case releaseNotes
    case translations
    case license
    case contributors
    case about
}

/// A command or dialog identity that can request contextual help.
public struct HelpCatalogContext: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case command
        case dialog
    }

    public let kind: Kind
    public let identifier: String

    public init(kind: Kind, identifier: String) throws {
        guard HelpCatalogValidation.isIdentifier(identifier) else {
            throw HelpCatalogError.invalidIdentifier(field: "context.identifier")
        }
        self.kind = kind
        self.identifier = identifier
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case identifier
    }

    public init(from decoder: Decoder) throws {
        try HelpCatalogValidation.requireBoundedDecoding(decoder)
        try HelpCatalogValidation.rejectUnknownKeys(
            from: decoder,
            allowed: CodingKeys.allNames
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(Kind.self, forKey: .kind),
            identifier: container.decode(String.self, forKey: .identifier)
        )
    }
}

/// Schemes are deliberately closed. The catalog cannot represent executable, file, or data URLs.
public enum HelpCatalogLinkScheme: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case helpBook
    case bundledResource
    case https
    case mailto
}

/// Trust supplied by the application, never by catalog data.
public struct HelpCatalogTrustPolicy: Sendable {
    public typealias BundledResourceResolver = @Sendable (String) -> URL?

    public static let denyAll = HelpCatalogTrustPolicy(
        trustedExternalHosts: [],
        resolvedBundleRoot: nil,
        bundledResourceResolver: nil,
        bundledResourceRootHandle: nil,
        bundledResourceRootIdentity: nil,
        bundledResourceResolverProvenance: nil,
        validated: ()
    )

    fileprivate let trustedExternalHosts: Set<String>
    fileprivate let resolvedBundleRoot: URL?
    fileprivate let bundledResourceResolver: BundledResourceResolver?
    fileprivate let bundledResourceRootHandle: FileHandle?
    fileprivate let bundledResourceRootIdentity: HelpCatalogFileIdentity?
    fileprivate let bundledResourceResolverProvenance: UUID?

    public init(
        trustedExternalHosts: Set<String> = [],
        resolvedBundleRoot: URL? = nil,
        bundledResourceResolver: BundledResourceResolver? = nil
    ) throws {
        var canonicalHosts: Set<String> = []
        canonicalHosts.reserveCapacity(trustedExternalHosts.count)
        for host in trustedExternalHosts {
            guard let canonicalHost = HelpCatalogValidation.canonicalExternalHost(host) else {
                throw HelpCatalogError.invalidTrustedExternalHost(host)
            }
            canonicalHosts.insert(canonicalHost)
        }
        guard (resolvedBundleRoot == nil) == (bundledResourceResolver == nil) else {
            throw HelpCatalogError.invalidResolvedBundleRoot
        }
        let canonicalRoot: URL?
        let rootHandle: FileHandle?
        let rootIdentity: HelpCatalogFileIdentity?
        let resolverProvenance: UUID?
        if let resolvedBundleRoot {
            guard let root = HelpCatalogValidation.canonicalResolvedFileURL(resolvedBundleRoot),
                root == root.resolvingSymlinksInPath().standardizedFileURL,
                let openedRoot = HelpCatalogValidation.openBundleRoot(root)
            else {
                throw HelpCatalogError.invalidResolvedBundleRoot
            }
            canonicalRoot = root
            rootHandle = openedRoot.handle
            rootIdentity = openedRoot.identity
            resolverProvenance = UUID()
        } else {
            canonicalRoot = nil
            rootHandle = nil
            rootIdentity = nil
            resolverProvenance = nil
        }
        self.init(
            trustedExternalHosts: canonicalHosts,
            resolvedBundleRoot: canonicalRoot,
            bundledResourceResolver: bundledResourceResolver,
            bundledResourceRootHandle: rootHandle,
            bundledResourceRootIdentity: rootIdentity,
            bundledResourceResolverProvenance: resolverProvenance,
            validated: ()
        )
    }

    private init(
        trustedExternalHosts: Set<String>,
        resolvedBundleRoot: URL?,
        bundledResourceResolver: BundledResourceResolver?,
        bundledResourceRootHandle: FileHandle?,
        bundledResourceRootIdentity: HelpCatalogFileIdentity?,
        bundledResourceResolverProvenance: UUID?,
        validated: Void
    ) {
        self.trustedExternalHosts = trustedExternalHosts
        self.resolvedBundleRoot = resolvedBundleRoot
        self.bundledResourceResolver = bundledResourceResolver
        self.bundledResourceRootHandle = bundledResourceRootHandle
        self.bundledResourceRootIdentity = bundledResourceRootIdentity
        self.bundledResourceResolverProvenance = bundledResourceResolverProvenance
    }
}

/// Validated link metadata with descriptor-safe opening for bundled resources.
public struct HelpCatalogLink: Codable, Equatable, Hashable, Sendable {
    public let scheme: HelpCatalogLinkScheme
    public let target: String
    public let fragment: String?
    public let labelLocalizationKey: String?
    /// Resolution provenance only. Use `openBundledResource()` when opening the resource.
    public let resolvedBundledResourceURL: URL?
    private let bundledResourceTrustPolicy: HelpCatalogTrustPolicy?
    private let bundledResourceIdentity: HelpCatalogBundledResourceIdentity?

    public init(
        scheme: HelpCatalogLinkScheme,
        target: String,
        fragment: String? = nil,
        labelLocalizationKey: String? = nil,
        trustPolicy: HelpCatalogTrustPolicy = .denyAll
    ) throws {
        let bundledResourceIdentity = try HelpCatalogValidation.validateLink(
            scheme: scheme,
            target: target,
            fragment: fragment,
            trustPolicy: trustPolicy
        )
        if let labelLocalizationKey {
            try HelpCatalogValidation.validateLocalizationKey(
                labelLocalizationKey,
                field: "link.labelLocalizationKey"
            )
        }
        self.scheme = scheme
        self.target = target
        self.fragment = fragment
        self.labelLocalizationKey = labelLocalizationKey
        resolvedBundledResourceURL = bundledResourceIdentity?.resolvedURL
        bundledResourceTrustPolicy = scheme == .bundledResource ? trustPolicy : nil
        self.bundledResourceIdentity = bundledResourceIdentity
    }

    public static func helpBook(
        anchor: String,
        labelLocalizationKey: String? = nil
    ) throws -> HelpCatalogLink {
        try HelpCatalogLink(
            scheme: .helpBook,
            target: anchor,
            labelLocalizationKey: labelLocalizationKey
        )
    }

    public static func bundledResource(
        path: String,
        fragment: String? = nil,
        labelLocalizationKey: String? = nil,
        trustPolicy: HelpCatalogTrustPolicy
    ) throws -> HelpCatalogLink {
        try HelpCatalogLink(
            scheme: .bundledResource,
            target: path,
            fragment: fragment,
            labelLocalizationKey: labelLocalizationKey,
            trustPolicy: trustPolicy
        )
    }

    public static func secureWeb(
        _ url: String,
        labelLocalizationKey: String? = nil,
        trustPolicy: HelpCatalogTrustPolicy
    ) throws -> HelpCatalogLink {
        try HelpCatalogLink(
            scheme: .https,
            target: url,
            labelLocalizationKey: labelLocalizationKey,
            trustPolicy: trustPolicy
        )
    }

    public static func email(
        _ address: String,
        labelLocalizationKey: String? = nil,
        trustPolicy: HelpCatalogTrustPolicy
    ) throws -> HelpCatalogLink {
        try HelpCatalogLink(
            scheme: .mailto,
            target: address,
            labelLocalizationKey: labelLocalizationKey,
            trustPolicy: trustPolicy
        )
    }

    public var helpBookAnchor: String? {
        scheme == .helpBook ? target : nil
    }

    /// Opens the validated bundled resource without following replaceable symlinks.
    public func openBundledResource() throws -> FileHandle {
        guard scheme == .bundledResource,
            let bundledResourceTrustPolicy,
            let bundledResourceIdentity
        else {
            throw HelpCatalogError.invalidLinkTarget(scheme: scheme)
        }
        return try HelpCatalogValidation.openBundledResource(
            path: target,
            trustPolicy: bundledResourceTrustPolicy,
            identity: bundledResourceIdentity
        )
    }

    public static func == (left: HelpCatalogLink, right: HelpCatalogLink) -> Bool {
        left.scheme == right.scheme
            && left.target == right.target
            && left.fragment == right.fragment
            && left.labelLocalizationKey == right.labelLocalizationKey
            && left.bundledResourceIdentity == right.bundledResourceIdentity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(scheme)
        hasher.combine(target)
        hasher.combine(fragment)
        hasher.combine(labelLocalizationKey)
        hasher.combine(bundledResourceIdentity)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case scheme
        case target
        case fragment
        case labelLocalizationKey
    }

    public init(from decoder: Decoder) throws {
        try HelpCatalogValidation.requireBoundedDecoding(decoder)
        try HelpCatalogValidation.rejectUnknownKeys(
            from: decoder,
            allowed: CodingKeys.allNames
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let trustPolicy = try HelpCatalogValidation.requireTrustPolicy(decoder)
        try self.init(
            scheme: container.decode(HelpCatalogLinkScheme.self, forKey: .scheme),
            target: container.decode(String.self, forKey: .target),
            fragment: container.decodeIfPresent(String.self, forKey: .fragment),
            labelLocalizationKey: container.decodeIfPresent(
                String.self,
                forKey: .labelLocalizationKey
            ),
            trustPolicy: trustPolicy
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scheme, forKey: .scheme)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(fragment, forKey: .fragment)
        try container.encodeIfPresent(labelLocalizationKey, forKey: .labelLocalizationKey)
    }
}

/// Catalog entry. Text fields are localization keys, never UI strings.
public struct HelpCatalogTopic: Codable, Equatable, Sendable {
    private static let maximumKeywords = 4_096
    private static let maximumContexts = 4_096
    private static let maximumLinks = 8_192
    private static let maximumRelationships = 16_384

    public let id: String
    public let kind: HelpCatalogTopicKind
    public let titleLocalizationKey: String
    public let summaryLocalizationKey: String?
    public let keywordLocalizationKeys: [String]
    public let contexts: [HelpCatalogContext]
    public let links: [HelpCatalogLink]
    public let relatedTopicIDs: [String]
    public let creditIDs: [String]

    public init(
        id: String,
        kind: HelpCatalogTopicKind,
        titleLocalizationKey: String,
        summaryLocalizationKey: String? = nil,
        keywordLocalizationKeys: [String] = [],
        contexts: [HelpCatalogContext] = [],
        links: [HelpCatalogLink] = [],
        relatedTopicIDs: [String] = [],
        creditIDs: [String] = []
    ) throws {
        try Task.checkCancellation()
        guard keywordLocalizationKeys.count <= Self.maximumKeywords else {
            throw HelpCatalogError.tooManyLocalizationKeys(maximum: Self.maximumKeywords)
        }
        guard contexts.count <= Self.maximumContexts else {
            throw HelpCatalogError.tooManyContexts(maximum: Self.maximumContexts)
        }
        guard links.count <= Self.maximumLinks else {
            throw HelpCatalogError.tooManyLinks(maximum: Self.maximumLinks)
        }
        guard relatedTopicIDs.count <= Self.maximumRelationships,
            creditIDs.count <= Self.maximumRelationships - relatedTopicIDs.count
        else {
            throw HelpCatalogError.tooManyRelationships(maximum: Self.maximumRelationships)
        }
        guard HelpCatalogValidation.isIdentifier(id) else {
            throw HelpCatalogError.invalidIdentifier(field: "topic.id")
        }
        try HelpCatalogValidation.validateLocalizationKey(
            titleLocalizationKey,
            field: "topic.titleLocalizationKey"
        )
        if let summaryLocalizationKey {
            try HelpCatalogValidation.validateLocalizationKey(
                summaryLocalizationKey,
                field: "topic.summaryLocalizationKey"
            )
        }
        for (index, key) in keywordLocalizationKeys.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            try HelpCatalogValidation.validateLocalizationKey(
                key,
                field: "topic.keywordLocalizationKeys"
            )
        }
        for (index, relatedTopicID) in relatedTopicIDs.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard HelpCatalogValidation.isIdentifier(relatedTopicID) else {
                throw HelpCatalogError.invalidIdentifier(field: "topic.relatedTopicIDs")
            }
        }
        for (index, creditID) in creditIDs.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard HelpCatalogValidation.isIdentifier(creditID) else {
                throw HelpCatalogError.invalidIdentifier(field: "topic.creditIDs")
            }
        }
        try HelpCatalogValidation.requireUnique(
            keywordLocalizationKeys,
            field: "topic.keywordLocalizationKeys"
        )
        try HelpCatalogValidation.requireUnique(contexts, field: "topic.contexts")
        try HelpCatalogValidation.requireUniqueLinks(links, field: "topic.links")
        try HelpCatalogValidation.requireUnique(
            relatedTopicIDs,
            field: "topic.relatedTopicIDs"
        )
        try HelpCatalogValidation.requireUnique(creditIDs, field: "topic.creditIDs")
        if !contexts.isEmpty {
            let expectedKind: HelpCatalogContext.Kind
            switch kind {
            case .command:
                expectedKind = .command
            case .dialog:
                expectedKind = .dialog
            default:
                throw HelpCatalogError.contextKindMismatch(topicID: id)
            }
            guard contexts.allSatisfy({ $0.kind == expectedKind }) else {
                throw HelpCatalogError.contextKindMismatch(topicID: id)
            }
        }
        guard !relatedTopicIDs.contains(id) else {
            throw HelpCatalogError.selfRelatedTopic(id)
        }

        self.id = id
        self.kind = kind
        self.titleLocalizationKey = titleLocalizationKey
        self.summaryLocalizationKey = summaryLocalizationKey
        self.keywordLocalizationKeys = keywordLocalizationKeys
        self.contexts = contexts
        self.links = links
        self.relatedTopicIDs = relatedTopicIDs
        self.creditIDs = creditIDs
    }

    public var localizationKeys: [String] {
        [titleLocalizationKey]
            + (summaryLocalizationKey.map { [$0] } ?? [])
            + keywordLocalizationKeys
            + links.compactMap(\.labelLocalizationKey)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case titleLocalizationKey
        case summaryLocalizationKey
        case keywordLocalizationKeys
        case contexts
        case links
        case relatedTopicIDs
        case creditIDs
    }

    public init(from decoder: Decoder) throws {
        try HelpCatalogValidation.requireBoundedDecoding(decoder)
        try HelpCatalogValidation.rejectUnknownKeys(
            from: decoder,
            allowed: CodingKeys.allNames
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = try HelpCatalogValidation.requireLimits(decoder)
        let keywordLocalizationKeys = try HelpCatalogValidation.decodeBoundedArray(
            String.self,
            from: container,
            forKey: .keywordLocalizationKeys,
            maximum: Swift.min(Self.maximumKeywords, limits.maximumLocalizationKeys),
            error: .tooManyLocalizationKeys(
                maximum: Swift.min(Self.maximumKeywords, limits.maximumLocalizationKeys)
            )
        )
        let contexts = try HelpCatalogValidation.decodeBoundedArray(
            HelpCatalogContext.self,
            from: container,
            forKey: .contexts,
            maximum: Swift.min(Self.maximumContexts, limits.maximumContexts),
            error: .tooManyContexts(
                maximum: Swift.min(Self.maximumContexts, limits.maximumContexts)
            )
        )
        let links = try HelpCatalogValidation.decodeBoundedArray(
            HelpCatalogLink.self,
            from: container,
            forKey: .links,
            maximum: Swift.min(Self.maximumLinks, limits.maximumLinks),
            error: .tooManyLinks(maximum: Swift.min(Self.maximumLinks, limits.maximumLinks))
        )
        let relatedTopicIDs = try HelpCatalogValidation.decodeBoundedArray(
            String.self,
            from: container,
            forKey: .relatedTopicIDs,
            maximum: Self.maximumRelationships,
            error: .tooManyRelationships(maximum: Self.maximumRelationships)
        )
        let creditIDs = try HelpCatalogValidation.decodeBoundedArray(
            String.self,
            from: container,
            forKey: .creditIDs,
            maximum: Self.maximumRelationships - relatedTopicIDs.count,
            error: .tooManyRelationships(maximum: Self.maximumRelationships)
        )
        try self.init(
            id: container.decode(String.self, forKey: .id),
            kind: container.decode(HelpCatalogTopicKind.self, forKey: .kind),
            titleLocalizationKey: container.decode(String.self, forKey: .titleLocalizationKey),
            summaryLocalizationKey: container.decodeIfPresent(
                String.self,
                forKey: .summaryLocalizationKey
            ),
            keywordLocalizationKeys: keywordLocalizationKeys,
            contexts: contexts,
            links: links,
            relatedTopicIDs: relatedTopicIDs,
            creditIDs: creditIDs
        )
    }
}

public enum HelpCatalogCreditKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case contributor
    case translator
    case acknowledgement
    case thirdParty
}

/// Localizable credit metadata. Names remain caller-provided localization keys.
public struct HelpCatalogCredit: Codable, Equatable, Sendable {
    private static let maximumLinks = 8_192

    public let id: String
    public let kind: HelpCatalogCreditKind
    public let nameLocalizationKey: String
    public let roleLocalizationKey: String?
    public let detailLocalizationKey: String?
    public let links: [HelpCatalogLink]

    public init(
        id: String,
        kind: HelpCatalogCreditKind,
        nameLocalizationKey: String,
        roleLocalizationKey: String? = nil,
        detailLocalizationKey: String? = nil,
        links: [HelpCatalogLink] = []
    ) throws {
        try Task.checkCancellation()
        guard links.count <= Self.maximumLinks else {
            throw HelpCatalogError.tooManyLinks(maximum: Self.maximumLinks)
        }
        guard HelpCatalogValidation.isIdentifier(id) else {
            throw HelpCatalogError.invalidIdentifier(field: "credit.id")
        }
        try HelpCatalogValidation.validateLocalizationKey(
            nameLocalizationKey,
            field: "credit.nameLocalizationKey"
        )
        if let roleLocalizationKey {
            try HelpCatalogValidation.validateLocalizationKey(
                roleLocalizationKey,
                field: "credit.roleLocalizationKey"
            )
        }
        if let detailLocalizationKey {
            try HelpCatalogValidation.validateLocalizationKey(
                detailLocalizationKey,
                field: "credit.detailLocalizationKey"
            )
        }
        try HelpCatalogValidation.requireUniqueLinks(links, field: "credit.links")
        self.id = id
        self.kind = kind
        self.nameLocalizationKey = nameLocalizationKey
        self.roleLocalizationKey = roleLocalizationKey
        self.detailLocalizationKey = detailLocalizationKey
        self.links = links
    }

    public var localizationKeys: [String] {
        [nameLocalizationKey]
            + (roleLocalizationKey.map { [$0] } ?? [])
            + (detailLocalizationKey.map { [$0] } ?? [])
            + links.compactMap(\.labelLocalizationKey)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case nameLocalizationKey
        case roleLocalizationKey
        case detailLocalizationKey
        case links
    }

    public init(from decoder: Decoder) throws {
        try HelpCatalogValidation.requireBoundedDecoding(decoder)
        try HelpCatalogValidation.rejectUnknownKeys(
            from: decoder,
            allowed: CodingKeys.allNames
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = try HelpCatalogValidation.requireLimits(decoder)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            kind: container.decode(HelpCatalogCreditKind.self, forKey: .kind),
            nameLocalizationKey: container.decode(String.self, forKey: .nameLocalizationKey),
            roleLocalizationKey: container.decodeIfPresent(
                String.self,
                forKey: .roleLocalizationKey
            ),
            detailLocalizationKey: container.decodeIfPresent(
                String.self,
                forKey: .detailLocalizationKey
            ),
            links: HelpCatalogValidation.decodeBoundedArray(
                HelpCatalogLink.self,
                from: container,
                forKey: .links,
                maximum: Swift.min(Self.maximumLinks, limits.maximumLinks),
                error: .tooManyLinks(maximum: Swift.min(Self.maximumLinks, limits.maximumLinks))
            )
        )
    }
}

/// Declares where a displayed version or build value came from without claiming its correctness.
public enum HelpCatalogVersionSource: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case applicationBundleMetadata
    case buildConfiguration
    case releaseManifest
    case callerProvided
}

/// Provenance assigned by the trusted caller while decoding manifest values.
public struct HelpCatalogManifestProvenance: Equatable, Sendable {
    public static let none = HelpCatalogManifestProvenance()

    public let versionSource: HelpCatalogVersionSource?
    public let buildSource: HelpCatalogVersionSource?

    public init(
        versionSource: HelpCatalogVersionSource? = nil,
        buildSource: HelpCatalogVersionSource? = nil
    ) {
        self.versionSource = versionSource
        self.buildSource = buildSource
    }
}

public struct HelpCatalogProvenancedValue: Codable, Equatable, Hashable, Sendable {
    public let value: String
    public let source: HelpCatalogVersionSource

    public init(value: String, source: HelpCatalogVersionSource) throws {
        guard HelpCatalogValidation.isSafeVersionValue(value) else {
            throw HelpCatalogError.invalidVersionOrBuildValue
        }
        self.value = value
        self.source = source
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case value
    }

    public init(from decoder: Decoder) throws {
        try HelpCatalogValidation.requireBoundedDecoding(decoder)
        try HelpCatalogValidation.rejectUnknownKeys(
            from: decoder,
            allowed: CodingKeys.allNames
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: container.decode(String.self, forKey: .value),
            source: HelpCatalogValidation.requireVersionSource(decoder)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }
}

/// About-window metadata. Missing values stay absent rather than being inferred or fabricated.
public struct HelpCatalogAboutMetadata: Codable, Equatable, Sendable {
    private static let maximumLinks = 8_192
    private static let maximumCredits = 16_384

    public let version: HelpCatalogProvenancedValue?
    public let build: HelpCatalogProvenancedValue?
    public let copyrightLocalizationKey: String?
    public let links: [HelpCatalogLink]
    public let creditIDs: [String]

    public init(
        version: HelpCatalogProvenancedValue? = nil,
        build: HelpCatalogProvenancedValue? = nil,
        copyrightLocalizationKey: String? = nil,
        links: [HelpCatalogLink] = [],
        creditIDs: [String] = []
    ) throws {
        try Task.checkCancellation()
        guard links.count <= Self.maximumLinks else {
            throw HelpCatalogError.tooManyLinks(maximum: Self.maximumLinks)
        }
        guard creditIDs.count <= Self.maximumCredits else {
            throw HelpCatalogError.tooManyRelationships(maximum: Self.maximumCredits)
        }
        if let copyrightLocalizationKey {
            try HelpCatalogValidation.validateLocalizationKey(
                copyrightLocalizationKey,
                field: "about.copyrightLocalizationKey"
            )
        }
        for (index, creditID) in creditIDs.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard HelpCatalogValidation.isIdentifier(creditID) else {
                throw HelpCatalogError.invalidIdentifier(field: "about.creditIDs")
            }
        }
        try HelpCatalogValidation.requireUniqueLinks(links, field: "about.links")
        try HelpCatalogValidation.requireUnique(creditIDs, field: "about.creditIDs")
        self.version = version
        self.build = build
        self.copyrightLocalizationKey = copyrightLocalizationKey
        self.links = links
        self.creditIDs = creditIDs
    }

    public static let empty = HelpCatalogAboutMetadata(
        version: nil,
        build: nil,
        copyrightLocalizationKey: nil,
        links: [],
        creditIDs: [],
        validated: ()
    )

    private init(
        version: HelpCatalogProvenancedValue?,
        build: HelpCatalogProvenancedValue?,
        copyrightLocalizationKey: String?,
        links: [HelpCatalogLink],
        creditIDs: [String],
        validated: Void
    ) {
        self.version = version
        self.build = build
        self.copyrightLocalizationKey = copyrightLocalizationKey
        self.links = links
        self.creditIDs = creditIDs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case build
        case copyrightLocalizationKey
        case links
        case creditIDs
    }

    public init(from decoder: Decoder) throws {
        try HelpCatalogValidation.requireBoundedDecoding(decoder)
        try HelpCatalogValidation.rejectUnknownKeys(
            from: decoder,
            allowed: CodingKeys.allNames
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = try HelpCatalogValidation.requireLimits(decoder)
        try self.init(
            version: container.decodeIfPresent(
                HelpCatalogProvenancedValue.self,
                forKey: .version
            ),
            build: container.decodeIfPresent(
                HelpCatalogProvenancedValue.self,
                forKey: .build
            ),
            copyrightLocalizationKey: container.decodeIfPresent(
                String.self,
                forKey: .copyrightLocalizationKey
            ),
            links: HelpCatalogValidation.decodeBoundedArray(
                HelpCatalogLink.self,
                from: container,
                forKey: .links,
                maximum: Swift.min(Self.maximumLinks, limits.maximumLinks),
                error: .tooManyLinks(maximum: Swift.min(Self.maximumLinks, limits.maximumLinks))
            ),
            creditIDs: HelpCatalogValidation.decodeBoundedArray(
                String.self,
                from: container,
                forKey: .creditIDs,
                maximum: Swift.min(Self.maximumCredits, limits.maximumRelationships),
                error: .tooManyRelationships(
                    maximum: Swift.min(Self.maximumCredits, limits.maximumRelationships)
                )
            )
        )
    }
}

/// Construction and untrusted-manifest bounds. Values above hard ceilings are rejected.
public struct HelpCatalogLimits: Equatable, Sendable {
    public static let `default` = HelpCatalogLimits()

    public let maximumTopics: Int
    public let maximumCredits: Int
    public let maximumContexts: Int
    public let maximumLinks: Int
    public let maximumRelationships: Int
    public let maximumLocalizationKeys: Int
    public let maximumMetadataUTF8Bytes: Int
    public let maximumManifestBytes: Int
    public let maximumJSONValues: Int

    public init(
        maximumTopics: Int = 1_024,
        maximumCredits: Int = 4_096,
        maximumContexts: Int = 4_096,
        maximumLinks: Int = 8_192,
        maximumRelationships: Int = 16_384,
        maximumLocalizationKeys: Int = 16_384,
        maximumMetadataUTF8Bytes: Int = 8 * 1_024 * 1_024,
        maximumManifestBytes: Int = 1 * 1_024 * 1_024,
        maximumJSONValues: Int = 131_072
    ) {
        self.maximumTopics = maximumTopics
        self.maximumCredits = maximumCredits
        self.maximumContexts = maximumContexts
        self.maximumLinks = maximumLinks
        self.maximumRelationships = maximumRelationships
        self.maximumLocalizationKeys = maximumLocalizationKeys
        self.maximumMetadataUTF8Bytes = maximumMetadataUTF8Bytes
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumJSONValues = maximumJSONValues
    }
}

public struct HelpCatalogSearchLimits: Equatable, Sendable {
    public static let `default` = HelpCatalogSearchLimits()

    public let maximumResults: Int
    public let maximumQueryUTF8Bytes: Int
    public let maximumQueryTokens: Int
    public let maximumDocumentTokens: Int
    public let maximumTokenUTF8Bytes: Int
    public let maximumLocalizedValues: Int
    public let maximumLocalizedValueUTF8Bytes: Int
    public let maximumLocalizedUTF8Bytes: Int
    public let maximumWorkUnits: Int

    public init(
        maximumResults: Int = 100,
        maximumQueryUTF8Bytes: Int = 4_096,
        maximumQueryTokens: Int = 64,
        maximumDocumentTokens: Int = 16_384,
        maximumTokenUTF8Bytes: Int = 16 * 1_024,
        maximumLocalizedValues: Int = 16_384,
        maximumLocalizedValueUTF8Bytes: Int = 256 * 1_024,
        maximumLocalizedUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumWorkUnits: Int = 2_000_000
    ) {
        self.maximumResults = maximumResults
        self.maximumQueryUTF8Bytes = maximumQueryUTF8Bytes
        self.maximumQueryTokens = maximumQueryTokens
        self.maximumDocumentTokens = maximumDocumentTokens
        self.maximumTokenUTF8Bytes = maximumTokenUTF8Bytes
        self.maximumLocalizedValues = maximumLocalizedValues
        self.maximumLocalizedValueUTF8Bytes = maximumLocalizedValueUTF8Bytes
        self.maximumLocalizedUTF8Bytes = maximumLocalizedUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
    }
}

public struct HelpCatalogSearchResult: Equatable, Sendable {
    public let topic: HelpCatalogTopic
    public let score: Int
    public let matchedTokens: [String]

    public init(topic: HelpCatalogTopic, score: Int, matchedTokens: [String]) {
        self.topic = topic
        self.score = score
        self.matchedTokens = matchedTokens
    }
}

public enum HelpCatalogNavigationDirection: Equatable, Sendable {
    case next
    case previous
}

public enum HelpCatalogError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimit(name: String, value: Int)
    case tooManyTopics(maximum: Int)
    case tooManyCredits(maximum: Int)
    case tooManyContexts(maximum: Int)
    case tooManyLinks(maximum: Int)
    case tooManyRelationships(maximum: Int)
    case tooManyLocalizationKeys(maximum: Int)
    case metadataTooLarge(maximumUTF8Bytes: Int)
    case invalidIdentifier(field: String)
    case invalidLocalizationKey(field: String)
    case invalidLinkTarget(scheme: HelpCatalogLinkScheme)
    case invalidLinkFragment
    case invalidTrustedExternalHost(String)
    case invalidResolvedBundleRoot
    case bundledResourceResolutionFailed(String)
    case invalidVersionOrBuildValue
    case missingManifestProvenance(field: String)
    case duplicateValue(field: String)
    case duplicateTopicID(String)
    case duplicateCreditID(String)
    case duplicateContext(HelpCatalogContext)
    case duplicateHelpBookAnchor(String)
    case contextKindMismatch(topicID: String)
    case selfRelatedTopic(String)
    case missingRelatedTopic(String)
    case missingCredit(String)
    case unknownTopicID(String)
    case queryTooLarge(maximumUTF8Bytes: Int)
    case tooManyQueryTokens(maximum: Int)
    case tooManyDocumentTokens(maximum: Int)
    case searchTokenTooLarge(maximumUTF8Bytes: Int)
    case tooManyLocalizedValues(maximum: Int)
    case localizedValuesTooLarge(maximumUTF8Bytes: Int)
    case searchWorkLimitExceeded(maximum: Int)
    case manifestDataTooLarge(maximumBytes: Int)
    case boundedManifestDecodingRequired
    case unsupportedManifestVersion(Int)
    case invalidJSON
    case duplicateJSONKey(String)
    case unknownManifestKey(path: String, key: String)
    case jsonNestingTooDeep(maximum: Int)
    case jsonContainerTooLarge(maximumElements: Int)
    case jsonValueLimitExceeded(maximum: Int)
    case jsonStringTooLarge(maximumUTF8Bytes: Int)
    case jsonStringsTooLarge(maximumUTF8Bytes: Int)
    case jsonKeyTooLarge(maximumUTF8Bytes: Int)
    case jsonNumberTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value):
            "Help catalog limit \(name) is invalid: \(value)."
        case .tooManyTopics(let maximum):
            "Help catalog exceeds the \(maximum)-topic limit."
        case .tooManyCredits(let maximum):
            "Help catalog exceeds the \(maximum)-credit limit."
        case .tooManyContexts(let maximum):
            "Help catalog exceeds the \(maximum)-context limit."
        case .tooManyLinks(let maximum):
            "Help catalog exceeds the \(maximum)-link limit."
        case .tooManyRelationships(let maximum):
            "Help catalog exceeds the \(maximum)-relationship limit."
        case .tooManyLocalizationKeys(let maximum):
            "Help catalog exceeds the \(maximum)-localization-key limit."
        case .metadataTooLarge(let maximumUTF8Bytes):
            "Help catalog metadata exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .invalidIdentifier(let field):
            "Help catalog field \(field) contains an invalid identifier."
        case .invalidLocalizationKey(let field):
            "Help catalog field \(field) contains an invalid localization key."
        case .invalidLinkTarget(let scheme):
            "Help catalog contains an invalid or unsafe \(scheme.rawValue) link target."
        case .invalidLinkFragment:
            "Help catalog link fragment is invalid."
        case .invalidTrustedExternalHost(let host):
            "Help catalog trust policy contains an invalid host: \(HelpCatalogValidation.safeDiagnostic(host))."
        case .invalidResolvedBundleRoot:
            "Help catalog trust policy requires a canonical, symlink-resolved bundle root and resolver."
        case .bundledResourceResolutionFailed(let path):
            "Help catalog bundled resource does not resolve inside the trusted bundle root: \(HelpCatalogValidation.safeDiagnostic(path))."
        case .invalidVersionOrBuildValue:
            "Help catalog version or build metadata is empty, unsafe, or too large."
        case .missingManifestProvenance(let field):
            "Help catalog manifest requires caller-supplied provenance for \(field)."
        case .duplicateValue(let field):
            "Help catalog field \(field) contains a duplicate value."
        case .duplicateTopicID(let id):
            "Help catalog topic identifier appears more than once: \(HelpCatalogValidation.safeDiagnostic(id))."
        case .duplicateCreditID(let id):
            "Help catalog credit identifier appears more than once: \(HelpCatalogValidation.safeDiagnostic(id))."
        case .duplicateContext(let context):
            "Help catalog context appears more than once: \(context.kind.rawValue).\(context.identifier)."
        case .duplicateHelpBookAnchor(let anchor):
            "Help Book anchor appears more than once: \(HelpCatalogValidation.safeDiagnostic(anchor))."
        case .contextKindMismatch(let topicID):
            "Help catalog contexts do not match topic kind: \(HelpCatalogValidation.safeDiagnostic(topicID))."
        case .selfRelatedTopic(let id):
            "Help catalog topic cannot relate to itself: \(HelpCatalogValidation.safeDiagnostic(id))."
        case .missingRelatedTopic(let id):
            "Help catalog references a missing related topic: \(HelpCatalogValidation.safeDiagnostic(id))."
        case .missingCredit(let id):
            "Help catalog references a missing credit: \(HelpCatalogValidation.safeDiagnostic(id))."
        case .unknownTopicID(let id):
            "Help catalog has no topic with identifier: \(HelpCatalogValidation.safeDiagnostic(id))."
        case .queryTooLarge(let maximumUTF8Bytes):
            "Help search query exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .tooManyQueryTokens(let maximum):
            "Help search query exceeds the \(maximum)-token limit."
        case .tooManyDocumentTokens(let maximum):
            "Help search document exceeds the \(maximum)-token limit."
        case .searchTokenTooLarge(let maximumUTF8Bytes):
            "Help search token exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .tooManyLocalizedValues(let maximum):
            "Help search exceeds the \(maximum)-localized-value limit."
        case .localizedValuesTooLarge(let maximumUTF8Bytes):
            "Help search localized values exceed the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .searchWorkLimitExceeded(let maximum):
            "Help search exceeds the \(maximum)-unit work limit."
        case .manifestDataTooLarge(let maximumBytes):
            "Help catalog manifest exceeds the \(maximumBytes)-byte limit."
        case .boundedManifestDecodingRequired:
            "Help catalog values must be decoded with HelpCatalog.decodeManifest(from:limits:)."
        case .unsupportedManifestVersion(let version):
            "Unsupported Help catalog manifest version: \(version)."
        case .invalidJSON:
            "Help catalog manifest is not valid JSON."
        case .duplicateJSONKey(let key):
            "Help catalog manifest key appears more than once in one object: \(HelpCatalogValidation.safeDiagnostic(key))."
        case .unknownManifestKey(let path, let key):
            "Help catalog manifest contains unknown key \(HelpCatalogValidation.safeDiagnostic(key)) at \(HelpCatalogValidation.safeDiagnostic(path))."
        case .jsonNestingTooDeep(let maximum):
            "Help catalog manifest exceeds the \(maximum)-level JSON nesting limit."
        case .jsonContainerTooLarge(let maximumElements):
            "Help catalog manifest contains a JSON container with more than \(maximumElements) elements."
        case .jsonValueLimitExceeded(let maximum):
            "Help catalog manifest exceeds the \(maximum)-value JSON limit."
        case .jsonStringTooLarge(let maximumUTF8Bytes):
            "A Help catalog JSON string exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .jsonStringsTooLarge(let maximumUTF8Bytes):
            "Help catalog JSON strings exceed the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .jsonKeyTooLarge(let maximumUTF8Bytes):
            "A Help catalog JSON key exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .jsonNumberTooLarge(let maximumBytes):
            "A Help catalog JSON number exceeds the \(maximumBytes)-byte limit."
        }
    }
}

/// Immutable, UI-independent Help and About content catalog.
public struct HelpCatalog: Equatable, Sendable {
    public static let currentManifestVersion = 1
    private static let maximumAtomicDecodeBytes = 1 * 1_024 * 1_024

    /// Intentionally contains no project names, resources, people, versions, or URLs.
    public static let structuralDefault = HelpCatalog()
    public static let empty = structuralDefault

    public typealias Topic = HelpCatalogTopic
    public typealias TopicKind = HelpCatalogTopicKind
    public typealias Context = HelpCatalogContext
    public typealias Link = HelpCatalogLink
    public typealias Credit = HelpCatalogCredit
    public typealias AboutMetadata = HelpCatalogAboutMetadata
    public typealias ProvenancedValue = HelpCatalogProvenancedValue
    public typealias VersionSource = HelpCatalogVersionSource
    public typealias Limits = HelpCatalogLimits
    public typealias SearchLimits = HelpCatalogSearchLimits
    public typealias SearchResult = HelpCatalogSearchResult
    public typealias NavigationDirection = HelpCatalogNavigationDirection
    public typealias TrustPolicy = HelpCatalogTrustPolicy
    public typealias ManifestProvenance = HelpCatalogManifestProvenance

    public let topics: [HelpCatalogTopic]
    public let credits: [HelpCatalogCredit]
    public let about: HelpCatalogAboutMetadata
    private let indexes: Indexes

    private struct Indexes: Equatable, Sendable {
        let topicByID: [String: Int]
        let creditByID: [String: Int]
        let topicByContext: [HelpCatalogContext: Int]
        let topicByHelpBookAnchor: [String: Int]
        let topicsByKind: [HelpCatalogTopicKind: [Int]]

        static let empty = Indexes(
            topicByID: [:],
            creditByID: [:],
            topicByContext: [:],
            topicByHelpBookAnchor: [:],
            topicsByKind: [:]
        )
    }

    public var manifestVersion: Int { Self.currentManifestVersion }
    public var topicIDs: [String] { topics.map(\.id) }
    public var creditIDs: [String] { credits.map(\.id) }

    public init() {
        topics = []
        credits = []
        about = .empty
        indexes = .empty
    }

    public init(
        topics: [HelpCatalogTopic],
        credits: [HelpCatalogCredit] = [],
        about: HelpCatalogAboutMetadata = .empty,
        limits: HelpCatalogLimits = .default
    ) throws {
        try Task.checkCancellation()
        try Self.validateLimits(limits)
        try Self.validate(topics: topics, credits: credits, about: about, limits: limits)
        let indexes = try Self.makeIndexes(topics: topics, credits: credits)
        self.topics = topics
        self.credits = credits
        self.about = about
        self.indexes = indexes
    }

    public func topic(withID id: String) -> HelpCatalogTopic? {
        indexes.topicByID[id].map { topics[$0] }
    }

    public func credit(withID id: String) -> HelpCatalogCredit? {
        indexes.creditByID[id].map { credits[$0] }
    }

    public func lookupTopic(_ id: String) throws -> HelpCatalogTopic? {
        try Task.checkCancellation()
        return topic(withID: id)
    }

    public func lookupCredit(_ id: String) throws -> HelpCatalogCredit? {
        try Task.checkCancellation()
        return credit(withID: id)
    }

    /// Contexts are globally unique, so contextual lookup returns at most one topic.
    public func topic(for context: HelpCatalogContext) throws -> HelpCatalogTopic? {
        try Task.checkCancellation()
        return indexes.topicByContext[context].map { topics[$0] }
    }

    public func topic(forHelpBookAnchor anchor: String) throws -> HelpCatalogTopic? {
        guard HelpCatalogValidation.isValidAnchor(anchor) else {
            throw HelpCatalogError.invalidLinkTarget(scheme: .helpBook)
        }
        try Task.checkCancellation()
        return indexes.topicByHelpBookAnchor[anchor].map { topics[$0] }
    }

    public func topics(ofKind kind: HelpCatalogTopicKind) throws -> [HelpCatalogTopic] {
        try Task.checkCancellation()
        return indexes.topicsByKind[kind, default: []].map { topics[$0] }
    }

    public func relatedTopics(to topicID: String) throws -> [HelpCatalogTopic] {
        guard let source = try lookupTopic(topicID) else {
            throw HelpCatalogError.unknownTopicID(topicID)
        }
        var result: [HelpCatalogTopic] = []
        result.reserveCapacity(source.relatedTopicIDs.count)
        for relatedID in source.relatedTopicIDs {
            try Task.checkCancellation()
            if let topic = topic(withID: relatedID) { result.append(topic) }
        }
        return result
    }

    /// Navigates source order. Source order is the catalog's deterministic presentation order.
    public func topic(
        adjacentTo topicID: String,
        direction: HelpCatalogNavigationDirection,
        wrapping: Bool = true,
        kinds: Set<HelpCatalogTopicKind>? = nil
    ) throws -> HelpCatalogTopic? {
        try Task.checkCancellation()
        guard let sourceIndex = indexes.topicByID[topicID] else {
            throw HelpCatalogError.unknownTopicID(topicID)
        }
        guard !topics.isEmpty else { return nil }

        var index = sourceIndex
        var visited = 0
        while visited < topics.count {
            try Task.checkCancellation()
            switch direction {
            case .next:
                if index == topics.index(before: topics.endIndex) {
                    guard wrapping else { return nil }
                    index = topics.startIndex
                } else {
                    topics.formIndex(after: &index)
                }
            case .previous:
                if index == topics.startIndex {
                    guard wrapping else { return nil }
                    index = topics.index(before: topics.endIndex)
                } else {
                    topics.formIndex(before: &index)
                }
            }
            visited += 1
            if kinds?.contains(topics[index].kind) ?? true { return topics[index] }
        }
        return nil
    }

    /// Deterministic metadata search. Caller-supplied localized values are optional and bounded.
    public func search(
        _ query: String,
        locale: Locale,
        localizedValues: [String: String] = [:],
        limits: HelpCatalogSearchLimits = .default
    ) throws -> [HelpCatalogSearchResult] {
        try Task.checkCancellation()
        try Self.validateSearchLimits(limits)
        let queryByteCount = query.utf8.count
        guard queryByteCount <= limits.maximumQueryUTF8Bytes else {
            throw HelpCatalogError.queryTooLarge(
                maximumUTF8Bytes: limits.maximumQueryUTF8Bytes
            )
        }
        guard localizedValues.count <= limits.maximumLocalizedValues else {
            throw HelpCatalogError.tooManyLocalizedValues(
                maximum: limits.maximumLocalizedValues
            )
        }

        let localizedKeys = Array(localizedValues.keys)
        for (index, key) in localizedKeys.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            try HelpCatalogValidation.validateLocalizationKey(
                key,
                field: "search.localizedValues"
            )
            guard let value = localizedValues[key],
                value.utf8.count <= limits.maximumLocalizedValueUTF8Bytes
            else {
                throw HelpCatalogError.localizedValuesTooLarge(
                    maximumUTF8Bytes: limits.maximumLocalizedValueUTF8Bytes
                )
            }
        }
        var localizedByteCount = 0
        for (index, key) in localizedKeys.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard let value = localizedValues[key] else { continue }
            try Self.consumeUTF8(
                key,
                total: &localizedByteCount,
                maximum: limits.maximumLocalizedUTF8Bytes,
                error: .localizedValuesTooLarge(
                    maximumUTF8Bytes: limits.maximumLocalizedUTF8Bytes
                )
            )
            try Self.consumeUTF8(
                value,
                total: &localizedByteCount,
                maximum: limits.maximumLocalizedUTF8Bytes,
                error: .localizedValuesTooLarge(
                    maximumUTF8Bytes: limits.maximumLocalizedUTF8Bytes
                )
            )
        }

        guard queryByteCount <= limits.maximumWorkUnits else {
            throw HelpCatalogError.searchWorkLimitExceeded(maximum: limits.maximumWorkUnits)
        }
        var budget = HelpCatalogSearchBudget(maximum: limits.maximumWorkUnits)
        let localizedQueryTokens = try HelpCatalogTokenizer.tokens(
            in: query,
            maximumTokens: limits.maximumQueryTokens,
            maximumTokenUTF8Bytes: limits.maximumTokenUTF8Bytes,
            limitError: .tooManyQueryTokens(maximum: limits.maximumQueryTokens),
            locale: locale,
            budget: &budget
        )
        let structuralQueryTokens = try HelpCatalogTokenizer.tokens(
            in: query,
            maximumTokens: limits.maximumQueryTokens,
            maximumTokenUTF8Bytes: limits.maximumTokenUTF8Bytes,
            limitError: .tooManyQueryTokens(maximum: limits.maximumQueryTokens),
            locale: HelpCatalogTokenizer.posixLocale,
            budget: &budget
        )
        guard localizedQueryTokens.count <= limits.maximumQueryTokens,
            structuralQueryTokens.count == localizedQueryTokens.count
        else {
            throw HelpCatalogError.tooManyQueryTokens(maximum: limits.maximumQueryTokens)
        }
        guard !localizedQueryTokens.isEmpty, limits.maximumResults > 0 else { return [] }

        var candidates: [(sourceIndex: Int, result: HelpCatalogSearchResult)] = []
        candidates.reserveCapacity(Swift.min(topics.count, limits.maximumResults))
        for (sourceIndex, topic) in topics.enumerated() {
            try Task.checkCancellation()
            var structuralDocumentTokens: [String] = []
            for field in structuralSearchFields(for: topic) {
                let tokens = try HelpCatalogTokenizer.tokens(
                    in: field,
                    maximumTokens: limits.maximumDocumentTokens,
                    maximumTokenUTF8Bytes: limits.maximumTokenUTF8Bytes,
                    limitError: .tooManyDocumentTokens(
                        maximum: limits.maximumDocumentTokens
                    ),
                    locale: HelpCatalogTokenizer.posixLocale,
                    budget: &budget
                )
                guard
                    tokens.count
                        <= limits.maximumDocumentTokens - structuralDocumentTokens.count
                else {
                    throw HelpCatalogError.tooManyDocumentTokens(
                        maximum: limits.maximumDocumentTokens
                    )
                }
                structuralDocumentTokens.append(contentsOf: tokens)
            }
            var localizedDocumentTokens: [String] = []
            for field in localizedSearchFields(for: topic, localizedValues: localizedValues) {
                let tokens = try HelpCatalogTokenizer.tokens(
                    in: field,
                    maximumTokens: limits.maximumDocumentTokens,
                    maximumTokenUTF8Bytes: limits.maximumTokenUTF8Bytes,
                    limitError: .tooManyDocumentTokens(
                        maximum: limits.maximumDocumentTokens
                    ),
                    locale: locale,
                    budget: &budget
                )
                guard
                    tokens.count
                        <= limits.maximumDocumentTokens - structuralDocumentTokens.count
                        - localizedDocumentTokens.count
                else {
                    throw HelpCatalogError.tooManyDocumentTokens(
                        maximum: limits.maximumDocumentTokens
                    )
                }
                localizedDocumentTokens.append(contentsOf: tokens)
            }

            if let score = try Self.searchScore(
                structuralQueryTokens: structuralQueryTokens,
                localizedQueryTokens: localizedQueryTokens,
                structuralDocumentTokens: structuralDocumentTokens,
                localizedDocumentTokens: localizedDocumentTokens,
                limits: limits,
                budget: &budget
            ) {
                candidates.append(
                    (
                        sourceIndex,
                        HelpCatalogSearchResult(
                            topic: topic,
                            score: score,
                            matchedTokens: localizedQueryTokens
                        )
                    )
                )
            }
        }

        candidates.sort { left, right in
            if left.result.score != right.result.score {
                return left.result.score > right.result.score
            }
            return left.sourceIndex < right.sourceIndex
        }
        try Task.checkCancellation()
        return candidates.prefix(limits.maximumResults).map(\.result)
    }

    /// Compact, recursively key-sorted, versioned JSON suitable for persistence or packaging.
    public func manifestData(limits: HelpCatalogLimits = .default) throws -> Data {
        try Task.checkCancellation()
        try Self.validateLimits(limits)
        try Self.validate(topics: topics, credits: credits, about: about, limits: limits)
        let maximumBytes = Swift.min(limits.maximumManifestBytes, Self.maximumAtomicDecodeBytes)
        var writer = HelpCatalogManifestWriter(
            maximumBytes: maximumBytes
        )
        try writer.write(catalog: self)
        let data = writer.data
        try data.withUnsafeBytes { rawBuffer in
            var scanner = HelpCatalogJSONScanner(
                bytes: rawBuffer.bindMemory(to: UInt8.self),
                limits: limits
            )
            try scanner.validate()
        }
        return data
    }

    public func encodedData(limits: HelpCatalogLimits = .default) throws -> Data {
        try manifestData(limits: limits)
    }

    /// Decodes only after structural JSON bounds and duplicate-key checks have passed.
    public static func decodeManifest(
        from data: Data,
        limits: HelpCatalogLimits = .default,
        provenance: HelpCatalogManifestProvenance = .none,
        trustPolicy: HelpCatalogTrustPolicy = .denyAll
    ) throws -> HelpCatalog {
        try Task.checkCancellation()
        try validateLimits(limits)
        let maximumBytes = Swift.min(limits.maximumManifestBytes, maximumAtomicDecodeBytes)
        guard data.count <= maximumBytes else {
            throw HelpCatalogError.manifestDataTooLarge(maximumBytes: maximumBytes)
        }
        let manifestVersion = try data.withUnsafeBytes { rawBuffer in
            var scanner = HelpCatalogJSONScanner(
                bytes: rawBuffer.bindMemory(to: UInt8.self),
                limits: limits
            )
            try scanner.validate()
            guard let manifestVersion = scanner.manifestVersion else {
                throw HelpCatalogError.invalidJSON
            }
            return manifestVersion
        }
        guard manifestVersion == currentManifestVersion else {
            throw HelpCatalogError.unsupportedManifestVersion(manifestVersion)
        }
        try Task.checkCancellation()
        do {
            let decoder = JSONDecoder()
            decoder.userInfo[HelpCatalogValidation.boundedDecodeKey] = HelpCatalogValidation.boundedDecodeToken
            decoder.userInfo[HelpCatalogValidation.provenanceKey] = provenance
            decoder.userInfo[HelpCatalogValidation.trustPolicyKey] = trustPolicy
            decoder.userInfo[HelpCatalogValidation.limitsKey] = limits
            let manifest = try decoder.decode(Manifest.self, from: data)
            try Task.checkCancellation()
            return try HelpCatalog(
                topics: manifest.topics,
                credits: manifest.credits,
                about: manifest.about,
                limits: limits
            )
        } catch let error as HelpCatalogError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HelpCatalogError.invalidJSON
        }
    }

    public static func decode(
        from data: Data,
        limits: HelpCatalogLimits = .default,
        provenance: HelpCatalogManifestProvenance = .none,
        trustPolicy: HelpCatalogTrustPolicy = .denyAll
    ) throws -> HelpCatalog {
        try decodeManifest(
            from: data,
            limits: limits,
            provenance: provenance,
            trustPolicy: trustPolicy
        )
    }

    private struct Manifest: Codable {
        let manifestVersion: Int
        let topics: [HelpCatalogTopic]
        let credits: [HelpCatalogCredit]
        let about: HelpCatalogAboutMetadata

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case manifestVersion
            case topics
            case credits
            case about
        }

        init(from decoder: Decoder) throws {
            try HelpCatalogValidation.requireBoundedDecoding(decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
            guard manifestVersion == HelpCatalog.currentManifestVersion else {
                throw HelpCatalogError.unsupportedManifestVersion(manifestVersion)
            }
            try HelpCatalogValidation.rejectUnknownKeys(
                from: decoder,
                allowed: CodingKeys.allNames
            )
            let limits = try HelpCatalogValidation.requireLimits(decoder)
            topics = try HelpCatalogValidation.decodeBoundedArray(
                HelpCatalogTopic.self,
                from: container,
                forKey: .topics,
                maximum: limits.maximumTopics,
                error: .tooManyTopics(maximum: limits.maximumTopics)
            )
            credits = try HelpCatalogValidation.decodeBoundedArray(
                HelpCatalogCredit.self,
                from: container,
                forKey: .credits,
                maximum: limits.maximumCredits,
                error: .tooManyCredits(maximum: limits.maximumCredits)
            )
            about = try container.decode(HelpCatalogAboutMetadata.self, forKey: .about)
        }
    }

    private func structuralSearchFields(for topic: HelpCatalogTopic) -> [String] {
        var fields = [topic.id, topic.kind.rawValue]
        for key in topic.localizationKeys {
            fields.append(key)
        }
        for context in topic.contexts {
            fields.append(context.kind.rawValue)
            fields.append(context.identifier)
        }
        for link in topic.links where link.scheme == .helpBook || link.scheme == .bundledResource {
            fields.append(link.target)
            if let fragment = link.fragment { fields.append(fragment) }
        }
        return fields
    }

    private func localizedSearchFields(
        for topic: HelpCatalogTopic,
        localizedValues: [String: String]
    ) -> [String] {
        topic.localizationKeys.compactMap { localizedValues[$0] }
    }

    private static func searchScore(
        structuralQueryTokens: [String],
        localizedQueryTokens: [String],
        structuralDocumentTokens: [String],
        localizedDocumentTokens: [String],
        limits: HelpCatalogSearchLimits,
        budget: inout HelpCatalogSearchBudget
    ) throws -> Int? {
        if localizedQueryTokens.count == 1 {
            var bestScore = 0
            let variants = [
                (structuralQueryTokens[0], structuralDocumentTokens),
                (localizedQueryTokens[0], localizedDocumentTokens)
            ]
            variantLoop: for (queryToken, documentTokens) in variants {
                for documentToken in documentTokens {
                    let score = try tokenScore(
                        queryToken: queryToken,
                        documentToken: documentToken,
                        limits: limits,
                        budget: &budget
                    )
                    if score == 8 {
                        bestScore = score
                        break variantLoop
                    }
                    bestScore = Swift.max(bestScore, score)
                }
            }
            return bestScore > 0 ? bestScore : nil
        }

        let documentCount = structuralDocumentTokens.count + localizedDocumentTokens.count
        guard documentCount >= localizedQueryTokens.count else { return nil }
        let (matrixCount, overflow) = localizedQueryTokens.count.multipliedReportingOverflow(
            by: documentCount
        )
        guard !overflow else {
            throw HelpCatalogError.searchWorkLimitExceeded(maximum: limits.maximumWorkUnits)
        }
        try budget.consume(matrixCount)
        var scores = [UInt8](repeating: 0, count: matrixCount)
        for queryIndex in localizedQueryTokens.indices {
            let rowStart = queryIndex * documentCount
            for documentIndex in structuralDocumentTokens.indices {
                scores[rowStart + documentIndex] = UInt8(
                    try tokenScore(
                        queryToken: structuralQueryTokens[queryIndex],
                        documentToken: structuralDocumentTokens[documentIndex],
                        limits: limits,
                        budget: &budget
                    )
                )
            }
            for documentIndex in localizedDocumentTokens.indices {
                scores[rowStart + structuralDocumentTokens.count + documentIndex] = UInt8(
                    try tokenScore(
                        queryToken: localizedQueryTokens[queryIndex],
                        documentToken: localizedDocumentTokens[documentIndex],
                        limits: limits,
                        budget: &budget
                    )
                )
            }
        }
        return try maximumAssignmentScore(
            scores: scores,
            queryCount: localizedQueryTokens.count,
            documentCount: documentCount,
            budget: &budget
        )
    }

    private static func tokenScore(
        queryToken: String,
        documentToken: String,
        limits: HelpCatalogSearchLimits,
        budget: inout HelpCatalogSearchBudget
    ) throws -> Int {
        try budget.consume(queryToken.utf8.count)
        try budget.consume(documentToken.utf8.count)
        if documentToken == queryToken { return 8 }
        if documentToken.hasPrefix(queryToken) { return 4 }
        let (containmentWork, overflow) = queryToken.utf8.count.multipliedReportingOverflow(
            by: documentToken.utf8.count
        )
        guard !overflow else {
            throw HelpCatalogError.searchWorkLimitExceeded(maximum: limits.maximumWorkUnits)
        }
        try budget.consume(containmentWork)
        return documentToken.contains(queryToken) ? 2 : 0
    }

    private static func maximumAssignmentScore(
        scores: [UInt8],
        queryCount: Int,
        documentCount: Int,
        budget: inout HelpCatalogSearchBudget
    ) throws -> Int? {
        let infinity = Int.max / 4
        var queryPotential = [Int](repeating: 0, count: queryCount + 1)
        var documentPotential = [Int](repeating: 0, count: documentCount + 1)
        var matchedQuery = [Int](repeating: 0, count: documentCount + 1)
        var path = [Int](repeating: 0, count: documentCount + 1)

        for query in 1...queryCount {
            matchedQuery[0] = query
            var currentDocument = 0
            var minimumCost = [Int](repeating: infinity, count: documentCount + 1)
            var visited = [Bool](repeating: false, count: documentCount + 1)
            repeat {
                visited[currentDocument] = true
                let currentQuery = matchedQuery[currentDocument]
                let rowStart = (currentQuery - 1) * documentCount
                var nextDocument = 0
                var delta = infinity
                for document in 1...documentCount where !visited[document] {
                    try budget.consume()
                    let score = Int(scores[rowStart + document - 1])
                    guard score > 0 else { continue }
                    let reducedCost =
                        8 - score - queryPotential[currentQuery] - documentPotential[document]
                    if reducedCost < minimumCost[document] {
                        minimumCost[document] = reducedCost
                        path[document] = currentDocument
                    }
                    if minimumCost[document] < delta {
                        delta = minimumCost[document]
                        nextDocument = document
                    }
                }
                guard delta < infinity else { return nil }
                for document in 0...documentCount {
                    try budget.consume()
                    if visited[document] {
                        queryPotential[matchedQuery[document]] += delta
                        documentPotential[document] -= delta
                    } else {
                        minimumCost[document] -= delta
                    }
                }
                currentDocument = nextDocument
            } while matchedQuery[currentDocument] != 0

            repeat {
                try budget.consume()
                let previousDocument = path[currentDocument]
                matchedQuery[currentDocument] = matchedQuery[previousDocument]
                currentDocument = previousDocument
            } while currentDocument != 0
        }

        var total = 0
        for document in 1...documentCount where matchedQuery[document] != 0 {
            try budget.consume()
            let query = matchedQuery[document]
            total += Int(scores[(query - 1) * documentCount + document - 1])
        }
        return total
    }

    private static func validateLimits(_ limits: HelpCatalogLimits) throws {
        let values: [(String, Int, Int)] = [
            ("maximumTopics", limits.maximumTopics, 4_096),
            ("maximumCredits", limits.maximumCredits, 16_384),
            ("maximumContexts", limits.maximumContexts, 16_384),
            ("maximumLinks", limits.maximumLinks, 32_768),
            ("maximumRelationships", limits.maximumRelationships, 65_536),
            ("maximumLocalizationKeys", limits.maximumLocalizationKeys, 65_536),
            ("maximumMetadataUTF8Bytes", limits.maximumMetadataUTF8Bytes, 32 * 1_024 * 1_024),
            ("maximumManifestBytes", limits.maximumManifestBytes, maximumAtomicDecodeBytes),
            ("maximumJSONValues", limits.maximumJSONValues, 524_288)
        ]
        for (name, value, hardMaximum) in values {
            guard value >= 0, value <= hardMaximum else {
                throw HelpCatalogError.invalidLimit(name: name, value: value)
            }
        }
        guard limits.maximumMetadataUTF8Bytes > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumMetadataUTF8Bytes",
                value: limits.maximumMetadataUTF8Bytes
            )
        }
        guard limits.maximumManifestBytes > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumManifestBytes",
                value: limits.maximumManifestBytes
            )
        }
        guard limits.maximumJSONValues > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumJSONValues",
                value: limits.maximumJSONValues
            )
        }
    }

    private static func validateSearchLimits(_ limits: HelpCatalogSearchLimits) throws {
        let values: [(String, Int, Int)] = [
            ("maximumResults", limits.maximumResults, 4_096),
            ("maximumQueryUTF8Bytes", limits.maximumQueryUTF8Bytes, 64 * 1_024),
            ("maximumQueryTokens", limits.maximumQueryTokens, 1_024),
            ("maximumDocumentTokens", limits.maximumDocumentTokens, 65_536),
            ("maximumTokenUTF8Bytes", limits.maximumTokenUTF8Bytes, 64 * 1_024),
            ("maximumLocalizedValues", limits.maximumLocalizedValues, 65_536),
            ("maximumLocalizedValueUTF8Bytes", limits.maximumLocalizedValueUTF8Bytes, 1_024 * 1_024),
            ("maximumLocalizedUTF8Bytes", limits.maximumLocalizedUTF8Bytes, 32 * 1_024 * 1_024),
            ("maximumWorkUnits", limits.maximumWorkUnits, 100_000_000)
        ]
        for (name, value, hardMaximum) in values {
            guard value >= 0, value <= hardMaximum else {
                throw HelpCatalogError.invalidLimit(name: name, value: value)
            }
        }
        guard limits.maximumQueryUTF8Bytes > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumQueryUTF8Bytes",
                value: limits.maximumQueryUTF8Bytes
            )
        }
        guard limits.maximumLocalizedUTF8Bytes > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumLocalizedUTF8Bytes",
                value: limits.maximumLocalizedUTF8Bytes
            )
        }
        guard limits.maximumDocumentTokens > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumDocumentTokens",
                value: limits.maximumDocumentTokens
            )
        }
        guard limits.maximumTokenUTF8Bytes > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumTokenUTF8Bytes",
                value: limits.maximumTokenUTF8Bytes
            )
        }
        guard limits.maximumLocalizedValueUTF8Bytes > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumLocalizedValueUTF8Bytes",
                value: limits.maximumLocalizedValueUTF8Bytes
            )
        }
        guard limits.maximumWorkUnits > 0 else {
            throw HelpCatalogError.invalidLimit(
                name: "maximumWorkUnits",
                value: limits.maximumWorkUnits
            )
        }
    }

    private static func validate(
        topics: [HelpCatalogTopic],
        credits: [HelpCatalogCredit],
        about: HelpCatalogAboutMetadata,
        limits: HelpCatalogLimits
    ) throws {
        guard topics.count <= limits.maximumTopics else {
            throw HelpCatalogError.tooManyTopics(maximum: limits.maximumTopics)
        }
        guard credits.count <= limits.maximumCredits else {
            throw HelpCatalogError.tooManyCredits(maximum: limits.maximumCredits)
        }

        var topicIDs: Set<String> = []
        var creditIDs: Set<String> = []
        var contexts: Set<HelpCatalogContext> = []
        var anchors: Set<String> = []
        var contextCount = 0
        var linkCount = about.links.count
        var relationshipCount = about.creditIDs.count
        var localizationKeyCount =
            about.links.compactMap(\.labelLocalizationKey).count
            + (about.copyrightLocalizationKey == nil ? 0 : 1)
        var metadataByteCount = 0

        try HelpCatalogValidation.requireUniqueLinks(about.links, field: "about.links")
        if let version = about.version {
            try consumeMetadata(version.value, total: &metadataByteCount, limits: limits)
        }
        if let build = about.build {
            try consumeMetadata(build.value, total: &metadataByteCount, limits: limits)
        }
        if let key = about.copyrightLocalizationKey {
            try consumeMetadata(key, total: &metadataByteCount, limits: limits)
        }
        for link in about.links {
            try consume(link: link, total: &metadataByteCount, limits: limits)
            if let key = link.labelLocalizationKey {
                try consumeMetadata(key, total: &metadataByteCount, limits: limits)
            }
        }
        for creditID in about.creditIDs {
            try consumeMetadata(creditID, total: &metadataByteCount, limits: limits)
        }

        for (index, topic) in topics.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            guard topicIDs.insert(topic.id).inserted else {
                throw HelpCatalogError.duplicateTopicID(topic.id)
            }
            try HelpCatalogValidation.requireUniqueLinks(topic.links, field: "topic.links")
            contextCount = try checkedAdd(
                contextCount,
                topic.contexts.count,
                maximum: limits.maximumContexts,
                error: .tooManyContexts(maximum: limits.maximumContexts)
            )
            linkCount = try checkedAdd(
                linkCount,
                topic.links.count,
                maximum: limits.maximumLinks,
                error: .tooManyLinks(maximum: limits.maximumLinks)
            )
            relationshipCount = try checkedAdd(
                relationshipCount,
                topic.relatedTopicIDs.count,
                maximum: limits.maximumRelationships,
                error: .tooManyRelationships(maximum: limits.maximumRelationships)
            )
            relationshipCount = try checkedAdd(
                relationshipCount,
                topic.creditIDs.count,
                maximum: limits.maximumRelationships,
                error: .tooManyRelationships(maximum: limits.maximumRelationships)
            )
            localizationKeyCount = try checkedAdd(
                localizationKeyCount,
                topic.localizationKeys.count,
                maximum: limits.maximumLocalizationKeys,
                error: .tooManyLocalizationKeys(maximum: limits.maximumLocalizationKeys)
            )
            try consumeMetadata(topic.id, total: &metadataByteCount, limits: limits)
            for key in topic.localizationKeys {
                try consumeMetadata(key, total: &metadataByteCount, limits: limits)
            }
            for context in topic.contexts {
                guard contexts.insert(context).inserted else {
                    throw HelpCatalogError.duplicateContext(context)
                }
                try consumeMetadata(
                    context.identifier,
                    total: &metadataByteCount,
                    limits: limits
                )
            }
            for link in topic.links {
                if let anchor = link.helpBookAnchor, !anchors.insert(anchor).inserted {
                    throw HelpCatalogError.duplicateHelpBookAnchor(anchor)
                }
                try consume(link: link, total: &metadataByteCount, limits: limits)
            }
            for id in topic.relatedTopicIDs + topic.creditIDs {
                try consumeMetadata(id, total: &metadataByteCount, limits: limits)
            }
        }

        for (index, credit) in credits.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            guard creditIDs.insert(credit.id).inserted else {
                throw HelpCatalogError.duplicateCreditID(credit.id)
            }
            try HelpCatalogValidation.requireUniqueLinks(credit.links, field: "credit.links")
            linkCount = try checkedAdd(
                linkCount,
                credit.links.count,
                maximum: limits.maximumLinks,
                error: .tooManyLinks(maximum: limits.maximumLinks)
            )
            localizationKeyCount = try checkedAdd(
                localizationKeyCount,
                credit.localizationKeys.count,
                maximum: limits.maximumLocalizationKeys,
                error: .tooManyLocalizationKeys(maximum: limits.maximumLocalizationKeys)
            )
            try consumeMetadata(credit.id, total: &metadataByteCount, limits: limits)
            for key in credit.localizationKeys {
                try consumeMetadata(key, total: &metadataByteCount, limits: limits)
            }
            for link in credit.links {
                try consume(link: link, total: &metadataByteCount, limits: limits)
            }
        }

        guard contextCount <= limits.maximumContexts else {
            throw HelpCatalogError.tooManyContexts(maximum: limits.maximumContexts)
        }
        guard linkCount <= limits.maximumLinks else {
            throw HelpCatalogError.tooManyLinks(maximum: limits.maximumLinks)
        }
        guard relationshipCount <= limits.maximumRelationships else {
            throw HelpCatalogError.tooManyRelationships(
                maximum: limits.maximumRelationships
            )
        }
        guard localizationKeyCount <= limits.maximumLocalizationKeys else {
            throw HelpCatalogError.tooManyLocalizationKeys(
                maximum: limits.maximumLocalizationKeys
            )
        }

        for topic in topics {
            try Task.checkCancellation()
            for id in topic.relatedTopicIDs where !topicIDs.contains(id) {
                throw HelpCatalogError.missingRelatedTopic(id)
            }
            for id in topic.creditIDs where !creditIDs.contains(id) {
                throw HelpCatalogError.missingCredit(id)
            }
        }
        for id in about.creditIDs where !creditIDs.contains(id) {
            throw HelpCatalogError.missingCredit(id)
        }
        try Task.checkCancellation()
    }

    private static func makeIndexes(
        topics: [HelpCatalogTopic],
        credits: [HelpCatalogCredit]
    ) throws -> Indexes {
        var topicByID: [String: Int] = [:]
        var creditByID: [String: Int] = [:]
        var topicByContext: [HelpCatalogContext: Int] = [:]
        var topicByHelpBookAnchor: [String: Int] = [:]
        var topicsByKind: [HelpCatalogTopicKind: [Int]] = [:]
        topicByID.reserveCapacity(topics.count)
        creditByID.reserveCapacity(credits.count)
        topicByContext.reserveCapacity(topics.reduce(into: 0) { $0 += $1.contexts.count })

        for (index, topic) in topics.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            topicByID[topic.id] = index
            topicsByKind[topic.kind, default: []].append(index)
            for context in topic.contexts { topicByContext[context] = index }
            for anchor in topic.links.compactMap(\.helpBookAnchor) {
                topicByHelpBookAnchor[anchor] = index
            }
        }
        for (index, credit) in credits.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            creditByID[credit.id] = index
        }
        try Task.checkCancellation()
        return Indexes(
            topicByID: topicByID,
            creditByID: creditByID,
            topicByContext: topicByContext,
            topicByHelpBookAnchor: topicByHelpBookAnchor,
            topicsByKind: topicsByKind
        )
    }

    private static func checkedAdd(
        _ value: Int,
        _ addition: Int,
        maximum: Int,
        error: HelpCatalogError
    ) throws -> Int {
        guard addition <= maximum, value <= maximum - addition else { throw error }
        return value + addition
    }

    private static func consume(
        link: HelpCatalogLink,
        total: inout Int,
        limits: HelpCatalogLimits
    ) throws {
        try consumeMetadata(link.target, total: &total, limits: limits)
        if let fragment = link.fragment {
            try consumeMetadata(fragment, total: &total, limits: limits)
        }
    }

    private static func consumeMetadata(
        _ value: String,
        total: inout Int,
        limits: HelpCatalogLimits
    ) throws {
        try consumeUTF8(
            value,
            total: &total,
            maximum: limits.maximumMetadataUTF8Bytes,
            error: .metadataTooLarge(maximumUTF8Bytes: limits.maximumMetadataUTF8Bytes)
        )
    }

    private static func consumeUTF8(
        _ value: String,
        total: inout Int,
        maximum: Int,
        error: HelpCatalogError
    ) throws {
        var count = 0
        for (index, _) in value.utf8.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            guard count < maximum, total < maximum - count else { throw error }
            count += 1
        }
        total += count
    }
}

private enum HelpCatalogValidation {
    static let maximumIdentifierUTF8Bytes = 256
    static let maximumLocalizationKeyUTF8Bytes = 512
    static let maximumLinkTargetUTF8Bytes = 8 * 1_024
    static let maximumFragmentUTF8Bytes = 512
    static let maximumVersionValueUTF8Bytes = 512
    static let boundedDecodeKey = CodingUserInfoKey(
        rawValue: "org.macmerge.HelpCatalog.boundedDecode"
    )!
    static let boundedDecodeToken = UUID()
    static let provenanceKey = CodingUserInfoKey(
        rawValue: "org.macmerge.HelpCatalog.provenance"
    )!
    static let trustPolicyKey = CodingUserInfoKey(
        rawValue: "org.macmerge.HelpCatalog.trustPolicy"
    )!
    static let limitsKey = CodingUserInfoKey(
        rawValue: "org.macmerge.HelpCatalog.limits"
    )!

    static func isIdentifier(_ value: String) -> Bool {
        isASCIIName(
            value,
            maximumUTF8Bytes: maximumIdentifierUTF8Bytes,
            allowsColon: false,
            allowsSlash: false
        )
    }

    static func validateLocalizationKey(_ value: String, field: String) throws {
        guard isLocalizationKey(value) else {
            throw HelpCatalogError.invalidLocalizationKey(field: field)
        }
    }

    static func isValidAnchor(_ value: String) -> Bool {
        isAnchor(value)
    }

    static func requireBoundedDecoding(_ decoder: Decoder) throws {
        guard decoder.userInfo[boundedDecodeKey] as? UUID == boundedDecodeToken else {
            throw HelpCatalogError.boundedManifestDecodingRequired
        }
    }

    static func requireTrustPolicy(_ decoder: Decoder) throws -> HelpCatalogTrustPolicy {
        guard let policy = decoder.userInfo[trustPolicyKey] as? HelpCatalogTrustPolicy else {
            throw HelpCatalogError.boundedManifestDecodingRequired
        }
        return policy
    }

    static func requireLimits(_ decoder: Decoder) throws -> HelpCatalogLimits {
        guard let limits = decoder.userInfo[limitsKey] as? HelpCatalogLimits else {
            throw HelpCatalogError.boundedManifestDecodingRequired
        }
        return limits
    }

    static func requireVersionSource(_ decoder: Decoder) throws -> HelpCatalogVersionSource {
        guard
            let provenance = decoder.userInfo[provenanceKey]
                as? HelpCatalogManifestProvenance
        else {
            throw HelpCatalogError.boundedManifestDecodingRequired
        }
        let field = decoder.codingPath.last?.stringValue ?? "value"
        let source = field == "version" ? provenance.versionSource : provenance.buildSource
        guard let source else {
            throw HelpCatalogError.missingManifestProvenance(field: field)
        }
        return source
    }

    static func decodeBoundedArray<Element: Decodable, Key: CodingKey>(
        _ type: Element.Type,
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key,
        maximum: Int,
        error: HelpCatalogError
    ) throws -> [Element] {
        var values = try container.nestedUnkeyedContainer(forKey: key)
        if let count = values.count, count > maximum { throw error }
        var result: [Element] = []
        result.reserveCapacity(Swift.min(values.count ?? 0, maximum))
        while !values.isAtEnd {
            guard result.count < maximum else { throw error }
            if result.count.isMultiple(of: 128) { try Task.checkCancellation() }
            result.append(try values.decode(type))
        }
        try Task.checkCancellation()
        return result
    }

    static func requireUnique<Value: Hashable>(
        _ values: [Value],
        field: String
    ) throws {
        var seen: Set<Value> = []
        seen.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard seen.insert(value).inserted else {
                throw HelpCatalogError.duplicateValue(field: field)
            }
        }
        try Task.checkCancellation()
    }

    static func requireUniqueLinks(_ links: [HelpCatalogLink], field: String) throws {
        var seen: Set<HelpCatalogLinkWireIdentity> = []
        seen.reserveCapacity(links.count)
        for (index, link) in links.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let identity = HelpCatalogLinkWireIdentity(
                scheme: link.scheme,
                target: link.target,
                fragment: link.fragment,
                labelLocalizationKey: link.labelLocalizationKey
            )
            guard seen.insert(identity).inserted else {
                throw HelpCatalogError.duplicateValue(field: field)
            }
        }
        try Task.checkCancellation()
    }

    static func isLocalizationKey(_ value: String) -> Bool {
        guard value.utf8.count <= maximumLocalizationKeyUTF8Bytes,
            let first = value.utf8.first,
            isASCIIAlphanumeric(first)
        else {
            return false
        }
        var previousWasDot = false
        for byte in value.utf8 {
            if byte == 0x2E {
                if previousWasDot { return false }
                previousWasDot = true
            } else {
                guard
                    isASCIIAlphanumeric(byte)
                        || byte == 0x2D
                        || byte == 0x5F
                else {
                    return false
                }
                previousWasDot = false
            }
        }
        return !previousWasDot
    }

    static func validateLink(
        scheme: HelpCatalogLinkScheme,
        target: String,
        fragment: String?,
        trustPolicy: HelpCatalogTrustPolicy
    ) throws -> HelpCatalogBundledResourceIdentity? {
        guard target.utf8.count <= maximumLinkTargetUTF8Bytes else {
            throw HelpCatalogError.invalidLinkTarget(scheme: scheme)
        }
        if let fragment {
            guard scheme == .bundledResource,
                isAnchor(fragment),
                fragment.utf8.count <= maximumFragmentUTF8Bytes
            else {
                throw HelpCatalogError.invalidLinkFragment
            }
        }
        switch scheme {
        case .helpBook:
            guard fragment == nil, isAnchor(target) else {
                throw HelpCatalogError.invalidLinkTarget(scheme: scheme)
            }
            return nil
        case .bundledResource:
            guard isSafeResourcePath(target) else {
                throw HelpCatalogError.invalidLinkTarget(scheme: scheme)
            }
            guard let root = trustPolicy.resolvedBundleRoot,
                let resolver = trustPolicy.bundledResourceResolver,
                let rootHandle = trustPolicy.bundledResourceRootHandle,
                let rootIdentity = trustPolicy.bundledResourceRootIdentity,
                let resolverProvenance = trustPolicy.bundledResourceResolverProvenance,
                let resolvedURL = resolver(target),
                let canonicalURL = canonicalResolvedFileURL(resolvedURL),
                canonicalURL == canonicalURL.resolvingSymlinksInPath().standardizedFileURL,
                contains(canonicalURL, within: root),
                let relativePath = relativePath(of: canonicalURL, within: root)
            else {
                throw HelpCatalogError.bundledResourceResolutionFailed(target)
            }
            let openedResource = try openBundledResourceDescriptor(
                relativePath: relativePath,
                rootHandle: rootHandle,
                diagnosticPath: target
            )
            Darwin.close(openedResource.descriptor)
            return HelpCatalogBundledResourceIdentity(
                resolvedURL: canonicalURL,
                relativePath: relativePath,
                resolverProvenance: resolverProvenance,
                trustRootURL: root,
                trustRootFileIdentity: rootIdentity,
                resourceFileIdentity: openedResource.identity
            )
        case .https:
            guard fragment == nil,
                isSafeHTTPSURL(target, trustedHosts: trustPolicy.trustedExternalHosts)
            else {
                throw HelpCatalogError.invalidLinkTarget(scheme: scheme)
            }
            return nil
        case .mailto:
            guard fragment == nil,
                isSafeEmailAddress(target, trustedHosts: trustPolicy.trustedExternalHosts)
            else {
                throw HelpCatalogError.invalidLinkTarget(scheme: scheme)
            }
            return nil
        }
    }

    static func openBundleRoot(
        _ root: URL
    ) -> (handle: FileHandle, identity: HelpCatalogFileIdentity)? {
        let components = root.path.split(separator: "/", omittingEmptySubsequences: true)
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer {
            if descriptor >= 0 { Darwin.close(descriptor) }
        }
        for component in components {
            guard !component.utf8.contains(0) else { return nil }
            let nextDescriptor = component.withCString {
                Darwin.openat(
                    descriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard nextDescriptor >= 0 else { return nil }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
        }
        guard let identity = fileIdentity(of: descriptor) else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        descriptor = -1
        return (handle, identity)
    }

    static func openBundledResource(
        path: String,
        trustPolicy: HelpCatalogTrustPolicy,
        identity: HelpCatalogBundledResourceIdentity
    ) throws -> FileHandle {
        guard isSafeResourcePath(path),
            let root = trustPolicy.resolvedBundleRoot,
            let rootHandle = trustPolicy.bundledResourceRootHandle,
            identity.trustRootURL == root,
            identity.trustRootFileIdentity == trustPolicy.bundledResourceRootIdentity,
            identity.resolverProvenance == trustPolicy.bundledResourceResolverProvenance
        else {
            throw HelpCatalogError.bundledResourceResolutionFailed(path)
        }
        let openedResource = try openBundledResourceDescriptor(
            relativePath: identity.relativePath,
            rootHandle: rootHandle,
            diagnosticPath: path
        )
        var descriptor = openedResource.descriptor
        defer {
            if descriptor >= 0 { Darwin.close(descriptor) }
        }
        guard openedResource.identity == identity.resourceFileIdentity else {
            throw HelpCatalogError.bundledResourceResolutionFailed(path)
        }
        try Task.checkCancellation()
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        descriptor = -1
        return handle
    }

    private static func openBundledResourceDescriptor(
        relativePath: String,
        rootHandle: FileHandle,
        diagnosticPath: String
    ) throws -> (descriptor: Int32, identity: HelpCatalogFileIdentity) {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else {
            throw HelpCatalogError.bundledResourceResolutionFailed(diagnosticPath)
        }
        var descriptor = Darwin.fcntl(rootHandle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else {
            throw HelpCatalogError.bundledResourceResolutionFailed(diagnosticPath)
        }
        defer {
            if descriptor >= 0 { Darwin.close(descriptor) }
        }
        for (index, component) in components.enumerated() {
            if index.isMultiple(of: 32) { try Task.checkCancellation() }
            let isLeaf = index == components.count - 1
            let flags =
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
                | (isLeaf ? O_NONBLOCK : O_DIRECTORY)
            guard !component.utf8.contains(0) else {
                throw HelpCatalogError.bundledResourceResolutionFailed(diagnosticPath)
            }
            let nextDescriptor = component.withCString {
                Darwin.openat(descriptor, $0, flags)
            }
            guard nextDescriptor >= 0 else {
                throw HelpCatalogError.bundledResourceResolutionFailed(diagnosticPath)
            }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
        }

        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
            status.st_mode & S_IFMT == S_IFREG
        else {
            throw HelpCatalogError.bundledResourceResolutionFailed(diagnosticPath)
        }
        let descriptorFlags = Darwin.fcntl(descriptor, F_GETFL)
        guard descriptorFlags >= 0 else {
            throw HelpCatalogError.bundledResourceResolutionFailed(diagnosticPath)
        }
        if descriptorFlags & O_NONBLOCK != 0 {
            guard Darwin.fcntl(descriptor, F_SETFL, descriptorFlags & ~O_NONBLOCK) == 0 else {
                throw HelpCatalogError.bundledResourceResolutionFailed(diagnosticPath)
            }
        }
        let identity = fileIdentity(from: status)
        let openedDescriptor = descriptor
        descriptor = -1
        return (descriptor: openedDescriptor, identity: identity)
    }

    private static func fileIdentity(of descriptor: Int32) -> HelpCatalogFileIdentity? {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { return nil }
        return fileIdentity(from: status)
    }

    private static func fileIdentity(from status: stat) -> HelpCatalogFileIdentity {
        HelpCatalogFileIdentity(
            device: UInt64(bitPattern: Int64(status.st_dev)),
            inode: UInt64(status.st_ino),
            generation: UInt64(status.st_gen)
        )
    }

    static func isSafeVersionValue(_ value: String) -> Bool {
        guard !value.isEmpty,
            value.utf8.count <= maximumVersionValueUTF8Bytes,
            value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return false
        }
        return value.unicodeScalars.allSatisfy(isPermittedMetadataScalar)
            && value.unicodeScalars.contains(where: isVisibleMetadataScalar)
    }

    static func rejectUnknownKeys(from decoder: Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: HelpCatalogAnyCodingKey.self)
        let unknownKeys = container.allKeys
            .map(\.stringValue)
            .filter { !allowed.contains($0) }
            .sorted(by: utf8Precedes)
        guard let key = unknownKeys.first else { return }
        let path =
            decoder.codingPath.isEmpty
            ? "$"
            : "$"
                + decoder.codingPath.map { component in
                    if let index = component.intValue { return "[\(index)]" }
                    return ".\(component.stringValue)"
                }.joined()
        throw HelpCatalogError.unknownManifestKey(path: path, key: key)
    }

    static func safeDiagnostic(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars.prefix(256) {
            if !isPermittedMetadataScalar(scalar) {
                result.append("\\u{")
                result.append(String(scalar.value, radix: 16, uppercase: true))
                result.append("}")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func isAnchor(_ value: String) -> Bool {
        isASCIIName(
            value,
            maximumUTF8Bytes: maximumFragmentUTF8Bytes,
            allowsColon: true,
            allowsSlash: false
        )
    }

    private static func isASCIIName(
        _ value: String,
        maximumUTF8Bytes: Int,
        allowsColon: Bool,
        allowsSlash: Bool
    ) -> Bool {
        guard !value.isEmpty,
            value.utf8.count <= maximumUTF8Bytes,
            let first = value.utf8.first,
            isASCIIAlphanumeric(first)
        else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            isASCIIAlphanumeric(byte)
                || byte == 0x2D
                || byte == 0x2E
                || byte == 0x5F
                || (allowsColon && byte == 0x3A)
                || (allowsSlash && byte == 0x2F)
        }
    }

    private static func isSafeResourcePath(_ value: String) -> Bool {
        guard !value.isEmpty,
            !value.hasPrefix("/"),
            !value.hasPrefix("~"),
            !value.contains("\\"),
            !value.contains("%"),
            !value.contains(":"),
            !value.contains("?"),
            !value.contains("#"),
            value.unicodeScalars.allSatisfy(isPermittedMetadataScalar)
        else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty
            && components.allSatisfy { component in
                !component.isEmpty && component != "." && component != ".."
            }
    }

    static func canonicalExternalHost(_ value: String) -> String? {
        let host = value.lowercased()
        guard !host.isEmpty,
            host == value.lowercased(with: Locale(identifier: "en_US_POSIX")),
            host.utf8.count <= 253,
            host.unicodeScalars.allSatisfy({ $0.isASCII })
        else {
            return nil
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return nil }
        for label in labels {
            guard !label.isEmpty,
                label.utf8.count <= 63,
                label.first != "-",
                label.last != "-",
                label.utf8.allSatisfy({ isASCIIAlphanumeric($0) || $0 == 0x2D })
            else {
                return nil
            }
        }
        return host
    }

    static func canonicalResolvedFileURL(_ value: URL) -> URL? {
        guard value.isFileURL,
            value.baseURL == nil,
            value.host == nil || value.host?.isEmpty == true,
            value.user == nil,
            value.password == nil,
            value.port == nil,
            value.query == nil,
            value.fragment == nil,
            value.path.hasPrefix("/")
        else {
            return nil
        }
        return value.standardizedFileURL
    }

    private static func contains(_ child: URL, within root: URL) -> Bool {
        let rootPath = root.path
        let childPath = child.path
        return childPath != rootPath
            && childPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    private static func relativePath(of child: URL, within root: URL) -> String? {
        guard contains(child, within: root) else { return nil }
        let rootPath = root.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return String(child.path.dropFirst(prefix.count))
    }

    private static func isSafeHTTPSURL(_ value: String, trustedHosts: Set<String>) -> Bool {
        guard value.hasPrefix("https://"),
            !value.contains("\\"),
            value.unicodeScalars.allSatisfy(isPermittedMetadataScalar),
            let components = URLComponents(string: value),
            components.scheme == "https",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            let host = components.host?.lowercased(),
            canonicalExternalHost(host) == host,
            trustedHosts.contains(host)
        else {
            return false
        }
        guard let decoded = value.removingPercentEncoding,
            decoded.unicodeScalars.allSatisfy(isPermittedMetadataScalar)
        else {
            return false
        }
        return true
    }

    private static func isSafeEmailAddress(
        _ value: String,
        trustedHosts: Set<String>
    ) -> Bool {
        guard value.unicodeScalars.allSatisfy({ $0.isASCII }),
            value.unicodeScalars.allSatisfy(isPermittedMetadataScalar),
            !value.contains("?"),
            !value.contains("#"),
            !value.contains("%")
        else {
            return false
        }
        let pieces = value.split(separator: "@", omittingEmptySubsequences: false)
        let localPart = pieces.first ?? ""
        guard pieces.count == 2,
            !localPart.isEmpty,
            localPart.first != ".",
            localPart.last != ".",
            !localPart.contains(".."),
            localPart.utf8.count <= 64,
            localPart.utf8.allSatisfy({ byte in
                isASCIIAlphanumeric(byte)
                    || byte == 0x21
                    || byte == 0x23
                    || byte == 0x24
                    || byte == 0x25
                    || byte == 0x26
                    || byte == 0x27
                    || byte == 0x2A
                    || byte == 0x2B
                    || byte == 0x2D
                    || byte == 0x2E
                    || byte == 0x2F
                    || byte == 0x3D
                    || byte == 0x3F
                    || byte == 0x5E
                    || byte == 0x5F
                    || byte == 0x60
                    || byte == 0x7B
                    || byte == 0x7C
                    || byte == 0x7D
                    || byte == 0x7E
            })
        else {
            return false
        }
        let host = String(pieces[1]).lowercased()
        return canonicalExternalHost(host) == host && trustedHosts.contains(host)
    }

    private static func isUnsafeScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.controlCharacters.contains(scalar)
            || CharacterSet.whitespacesAndNewlines.contains(scalar)
            || scalar.value == 0x061C
            || (0x200B...0x200F).contains(scalar.value)
            || (0x202A...0x202E).contains(scalar.value)
            || (0x2060...0x206F).contains(scalar.value)
            || scalar.value == 0xFEFF
    }

    static func isDefaultIgnorableScalar(_ scalar: UnicodeScalar) -> Bool {
        scalar.properties.isDefaultIgnorableCodePoint
    }

    private static func isPermittedMetadataScalar(_ scalar: UnicodeScalar) -> Bool {
        guard !isUnsafeScalar(scalar),
            !isDefaultIgnorableScalar(scalar),
            !isBlankRenderingScalar(scalar),
            !scalar.properties.isNoncharacterCodePoint,
            scalar.properties.generalCategory != .unassigned
        else {
            return false
        }
        return isVisibleMetadataScalar(scalar) || isCombiningMetadataScalar(scalar)
    }

    private static func isVisibleMetadataScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
            || CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar)
    }

    private static func isBlankRenderingScalar(_ scalar: UnicodeScalar) -> Bool {
        scalar.value == 0x115F
            || scalar.value == 0x1160
            || scalar.value == 0x2800
            || scalar.value == 0x3164
            || scalar.value == 0xFFA0
            || (0x13441...0x13442).contains(scalar.value)
            || scalar.value == 0x16FE4
    }

    private static func isCombiningMetadataScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            true
        default:
            false
        }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x5A).contains(byte)
            || (0x61...0x7A).contains(byte)
    }

    private static func utf8Precedes(_ left: String, _ right: String) -> Bool {
        left.utf8.lexicographicallyPrecedes(right.utf8)
    }
}

private struct HelpCatalogAnyCodingKey: CodingKey {
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

extension CodingKey where Self: CaseIterable, Self: RawRepresentable, RawValue == String {
    fileprivate static var allNames: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}

private struct HelpCatalogSearchBudget {
    let maximum: Int
    private(set) var used = 0

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0, amount <= maximum, used <= maximum - amount else {
            throw HelpCatalogError.searchWorkLimitExceeded(maximum: maximum)
        }
        try Task.checkCancellation()
        used += amount
    }
}

private enum HelpCatalogTokenizer {
    static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func tokens(
        in value: String,
        maximumTokens: Int,
        maximumTokenUTF8Bytes: Int,
        limitError: HelpCatalogError,
        locale: Locale,
        budget: inout HelpCatalogSearchBudget
    ) throws -> [String] {
        try Task.checkCancellation()
        try budget.consume(value.utf8.count)
        let normalized = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: locale
        ).precomposedStringWithCanonicalMapping
        var tokens: [String] = []
        var current = ""
        for scalar in normalized.unicodeScalars {
            try budget.consume()
            if HelpCatalogValidation.isDefaultIgnorableScalar(scalar) {
                continue
            } else if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty, CharacterSet.nonBaseCharacters.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                try append(current, to: &tokens, maximumTokens: maximumTokens, error: limitError)
                current.removeAll(keepingCapacity: true)
            }
            guard current.utf8.count <= maximumTokenUTF8Bytes else {
                throw HelpCatalogError.searchTokenTooLarge(
                    maximumUTF8Bytes: maximumTokenUTF8Bytes
                )
            }
        }
        if !current.isEmpty {
            try append(current, to: &tokens, maximumTokens: maximumTokens, error: limitError)
        }
        return tokens
    }

    private static func append(
        _ token: String,
        to tokens: inout [String],
        maximumTokens: Int,
        error: HelpCatalogError
    ) throws {
        guard tokens.count < maximumTokens else { throw error }
        tokens.append(token)
    }
}

private struct HelpCatalogManifestWriter {
    private(set) var data = Data()
    private let maximumBytes: Int
    private var nextCancellationCheck = 4_096

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        data.reserveCapacity(Swift.min(maximumBytes, 64 * 1_024))
    }

    mutating func write(catalog: HelpCatalog) throws {
        try append("{\"about\":")
        try write(about: catalog.about)
        try append(",\"credits\":[")
        for (index, credit) in catalog.credits.enumerated() {
            if index > 0 { try append(",") }
            try write(credit: credit)
        }
        try append("],\"manifestVersion\":")
        try append(String(HelpCatalog.currentManifestVersion))
        try append(",\"topics\":[")
        for (index, topic) in catalog.topics.enumerated() {
            if index > 0 { try append(",") }
            try write(topic: topic)
        }
        try append("]}")
        try Task.checkCancellation()
    }

    private mutating func write(topic: HelpCatalogTopic) throws {
        try append("{\"contexts\":[")
        for (index, context) in topic.contexts.enumerated() {
            if index > 0 { try append(",") }
            try write(context: context)
        }
        try append("],\"creditIDs\":")
        try write(strings: topic.creditIDs)
        try append(",\"id\":")
        try write(string: topic.id)
        try append(",\"keywordLocalizationKeys\":")
        try write(strings: topic.keywordLocalizationKeys)
        try append(",\"kind\":")
        try write(string: topic.kind.rawValue)
        try append(",\"links\":[")
        for (index, link) in topic.links.enumerated() {
            if index > 0 { try append(",") }
            try write(link: link)
        }
        try append("],\"relatedTopicIDs\":")
        try write(strings: topic.relatedTopicIDs)
        if let key = topic.summaryLocalizationKey {
            try append(",\"summaryLocalizationKey\":")
            try write(string: key)
        }
        try append(",\"titleLocalizationKey\":")
        try write(string: topic.titleLocalizationKey)
        try append("}")
    }

    private mutating func write(context: HelpCatalogContext) throws {
        try append("{\"identifier\":")
        try write(string: context.identifier)
        try append(",\"kind\":")
        try write(string: context.kind.rawValue)
        try append("}")
    }

    private mutating func write(credit: HelpCatalogCredit) throws {
        try append("{")
        var hasField = false
        if let key = credit.detailLocalizationKey {
            try append("\"detailLocalizationKey\":")
            try write(string: key)
            hasField = true
        }
        if hasField { try append(",") }
        try append("\"id\":")
        try write(string: credit.id)
        try append(",\"kind\":")
        try write(string: credit.kind.rawValue)
        try append(",\"links\":[")
        for (index, link) in credit.links.enumerated() {
            if index > 0 { try append(",") }
            try write(link: link)
        }
        try append("],\"nameLocalizationKey\":")
        try write(string: credit.nameLocalizationKey)
        if let key = credit.roleLocalizationKey {
            try append(",\"roleLocalizationKey\":")
            try write(string: key)
        }
        try append("}")
    }

    private mutating func write(about: HelpCatalogAboutMetadata) throws {
        try append("{")
        var hasField = false
        if let build = about.build {
            try append("\"build\":")
            try write(provenancedValue: build)
            hasField = true
        }
        if let key = about.copyrightLocalizationKey {
            if hasField { try append(",") }
            try append("\"copyrightLocalizationKey\":")
            try write(string: key)
            hasField = true
        }
        if hasField { try append(",") }
        try append("\"creditIDs\":")
        try write(strings: about.creditIDs)
        try append(",\"links\":[")
        for (index, link) in about.links.enumerated() {
            if index > 0 { try append(",") }
            try write(link: link)
        }
        if let version = about.version {
            try append("],\"version\":")
            try write(provenancedValue: version)
        } else {
            try append("]")
        }
        try append("}")
    }

    private mutating func write(provenancedValue: HelpCatalogProvenancedValue) throws {
        try append("{\"value\":")
        try write(string: provenancedValue.value)
        try append("}")
    }

    private mutating func write(link: HelpCatalogLink) throws {
        try append("{")
        var hasField = false
        if let fragment = link.fragment {
            try append("\"fragment\":")
            try write(string: fragment)
            hasField = true
        }
        if let key = link.labelLocalizationKey {
            if hasField { try append(",") }
            try append("\"labelLocalizationKey\":")
            try write(string: key)
            hasField = true
        }
        if hasField { try append(",") }
        try append("\"scheme\":")
        try write(string: link.scheme.rawValue)
        try append(",\"target\":")
        try write(string: link.target)
        try append("}")
    }

    private mutating func write(strings: [String]) throws {
        try append("[")
        for (index, string) in strings.enumerated() {
            if index > 0 { try append(",") }
            try write(string: string)
        }
        try append("]")
    }

    private mutating func write(string: String) throws {
        try append("\"")
        for (index, scalar) in string.unicodeScalars.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            switch scalar.value {
            case 0x22:
                try append("\\\"")
            case 0x5C:
                try append("\\\\")
            case 0x08:
                try append("\\b")
            case 0x0C:
                try append("\\f")
            case 0x0A:
                try append("\\n")
            case 0x0D:
                try append("\\r")
            case 0x09:
                try append("\\t")
            case 0x00...0x1F:
                try append("\\u")
                try append(String(scalar.value, radix: 16, uppercase: true).leftPadded(to: 4))
            default:
                try append(String(scalar))
            }
        }
        try append("\"")
    }

    private mutating func append(_ string: String) throws {
        let bytes = string.utf8
        guard bytes.count <= maximumBytes, data.count <= maximumBytes - bytes.count else {
            throw HelpCatalogError.manifestDataTooLarge(maximumBytes: maximumBytes)
        }
        data.append(contentsOf: bytes)
        if data.count >= nextCancellationCheck {
            try Task.checkCancellation()
            nextCancellationCheck = data.count + 4_096
        }
    }
}

extension String {
    fileprivate func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: Swift.max(0, length - count)) + self
    }
}

private struct HelpCatalogJSONScanner {
    private enum SchemaPath: Equatable {
        case root
        case topics
        case topic
        case topicContexts
        case topicContext
        case topicLinks
        case topicLink
        case topicRelatedTopicIDs
        case topicCreditIDs
        case topicKeywordLocalizationKeys
        case credits
        case credit
        case creditLinks
        case creditLink
        case about
        case aboutLinks
        case aboutLink
        case aboutCreditIDs
        case unknown
    }

    private enum Aggregate {
        case topics
        case credits
        case contexts
        case links
        case relationships
        case localizationKeys
    }

    private static let maximumNestingDepth = 16
    private static let maximumJSONKeyUTF8Bytes = 128
    private static let maximumJSONStringUTF8Bytes = 64 * 1_024
    private static let maximumJSONNumberBytes = 64

    private let bytes: UnsafeBufferPointer<UInt8>
    private let limits: HelpCatalogLimits
    private let maximumContainerElements: Int
    private var index = 0
    private var valueCount = 0
    private var totalStringUTF8Bytes = 0
    private var nextCancellationCheck = 4_096
    private(set) var manifestVersion: Int?
    private var remainingTopics: Int
    private var remainingCredits: Int
    private var remainingContexts: Int
    private var remainingLinks: Int
    private var remainingRelationships: Int
    private var remainingLocalizationKeys: Int

    init(bytes: UnsafeBufferPointer<UInt8>, limits: HelpCatalogLimits) {
        self.bytes = bytes
        self.limits = limits
        remainingTopics = limits.maximumTopics
        remainingCredits = limits.maximumCredits
        remainingContexts = limits.maximumContexts
        remainingLinks = limits.maximumLinks
        remainingRelationships = limits.maximumRelationships
        remainingLocalizationKeys = limits.maximumLocalizationKeys
        maximumContainerElements =
            [
                16,
                limits.maximumTopics,
                limits.maximumCredits,
                limits.maximumContexts,
                limits.maximumLinks,
                limits.maximumRelationships,
                limits.maximumLocalizationKeys
            ].max() ?? 16
    }

    mutating func validate() throws {
        try Task.checkCancellation()
        try skipWhitespace()
        try parseValue(depth: 0, schemaPath: .root, arrayLimit: nil, aggregate: nil)
        try skipWhitespace()
        guard index == bytes.count else { throw HelpCatalogError.invalidJSON }
        try Task.checkCancellation()
    }

    private mutating func parseValue(
        depth: Int,
        schemaPath: SchemaPath,
        arrayLimit: Int?,
        aggregate: Aggregate?
    ) throws {
        valueCount += 1
        guard valueCount <= limits.maximumJSONValues else {
            throw HelpCatalogError.jsonValueLimitExceeded(maximum: limits.maximumJSONValues)
        }
        if valueCount.isMultiple(of: 256) { try Task.checkCancellation() }
        guard let byte = currentByte else { throw HelpCatalogError.invalidJSON }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1, schemaPath: schemaPath)
        case 0x5B:
            try parseArray(
                depth: depth + 1,
                schemaPath: schemaPath,
                maximumElements: arrayLimit ?? maximumContainerElements,
                aggregate: aggregate
            )
        case 0x22:
            _ = try parseString(capturing: false, isKey: false)
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw HelpCatalogError.invalidJSON
        }
    }

    private mutating func parseObject(depth: Int, schemaPath: SchemaPath) throws {
        try validateDepth(depth)
        index += 1
        try skipWhitespace()
        if consume(0x7D) { return }

        var keys: Set<String> = []
        var count = 0
        while true {
            count += 1
            guard count <= maximumContainerElements else {
                throw HelpCatalogError.jsonContainerTooLarge(
                    maximumElements: maximumContainerElements
                )
            }
            guard let key = try parseString(capturing: true, isKey: true) else {
                throw HelpCatalogError.invalidJSON
            }
            guard keys.insert(key).inserted else {
                throw HelpCatalogError.duplicateJSONKey(key)
            }
            try skipWhitespace()
            guard consume(0x3A) else { throw HelpCatalogError.invalidJSON }
            try skipWhitespace()
            if schemaPath == .root, key == "manifestVersion" {
                valueCount += 1
                guard valueCount <= limits.maximumJSONValues else {
                    throw HelpCatalogError.jsonValueLimitExceeded(
                        maximum: limits.maximumJSONValues
                    )
                }
                manifestVersion = try parseInteger()
            } else {
                let childPath = objectChildPath(for: key, at: schemaPath)
                try parseValue(
                    depth: depth,
                    schemaPath: childPath,
                    arrayLimit: arrayLimit(at: childPath),
                    aggregate: aggregate(at: childPath)
                )
            }
            try skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw HelpCatalogError.invalidJSON }
            try skipWhitespace()
        }
    }

    private mutating func parseArray(
        depth: Int,
        schemaPath: SchemaPath,
        maximumElements: Int,
        aggregate: Aggregate?
    ) throws {
        try validateDepth(depth)
        index += 1
        try skipWhitespace()
        if consume(0x5D) { return }

        var count = 0
        while true {
            count += 1
            guard count <= maximumElements else {
                throw HelpCatalogError.jsonContainerTooLarge(
                    maximumElements: maximumElements
                )
            }
            try consumeAggregateElement(aggregate)
            try parseValue(
                depth: depth,
                schemaPath: arrayElementPath(for: schemaPath),
                arrayLimit: nil,
                aggregate: nil
            )
            try skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw HelpCatalogError.invalidJSON }
            try skipWhitespace()
        }
    }

    private mutating func parseString(capturing: Bool, isKey: Bool) throws -> String? {
        let start = index
        guard consume(0x22) else { throw HelpCatalogError.invalidJSON }
        var decodedCount = 0
        var captured = capturing ? "" : nil
        while let byte = currentByte {
            if byte == 0x22 {
                index += 1
                if isKey, decodedCount > Self.maximumJSONKeyUTF8Bytes {
                    throw HelpCatalogError.jsonKeyTooLarge(
                        maximumUTF8Bytes: Self.maximumJSONKeyUTF8Bytes
                    )
                }
                guard decodedCount <= limits.maximumManifestBytes,
                    totalStringUTF8Bytes <= limits.maximumManifestBytes - decodedCount
                else {
                    throw HelpCatalogError.jsonStringsTooLarge(
                        maximumUTF8Bytes: limits.maximumManifestBytes
                    )
                }
                totalStringUTF8Bytes += decodedCount
                return captured
            }
            let scalar: UnicodeScalar
            if byte == 0x5C {
                index += 1
                scalar = try parseEscapedScalar()
            } else {
                scalar = try parseUTF8Scalar()
                guard scalar.value >= 0x20 else { throw HelpCatalogError.invalidJSON }
            }
            decodedCount += scalar.utf8.count
            guard decodedCount <= Self.maximumJSONStringUTF8Bytes else {
                throw HelpCatalogError.jsonStringTooLarge(
                    maximumUTF8Bytes: Self.maximumJSONStringUTF8Bytes
                )
            }
            captured?.unicodeScalars.append(scalar)
            guard index - start <= Self.maximumJSONStringUTF8Bytes * 6 + 2 else {
                throw HelpCatalogError.jsonStringTooLarge(
                    maximumUTF8Bytes: Self.maximumJSONStringUTF8Bytes
                )
            }
            try checkCancellationAfterAdvance()
        }
        throw HelpCatalogError.invalidJSON
    }

    private mutating func parseEscapedScalar() throws -> UnicodeScalar {
        guard let escaped = currentByte else { throw HelpCatalogError.invalidJSON }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            return UnicodeScalar(escaped)
        case 0x62:
            return UnicodeScalar(0x08)
        case 0x66:
            return UnicodeScalar(0x0C)
        case 0x6E:
            return UnicodeScalar(0x0A)
        case 0x72:
            return UnicodeScalar(0x0D)
        case 0x74:
            return UnicodeScalar(0x09)
        case 0x75:
            let first = try parseHexQuad()
            let scalarValue: UInt32
            if (0xD800...0xDBFF).contains(first) {
                guard consume(0x5C), consume(0x75) else {
                    throw HelpCatalogError.invalidJSON
                }
                let second = try parseHexQuad()
                guard (0xDC00...0xDFFF).contains(second) else {
                    throw HelpCatalogError.invalidJSON
                }
                scalarValue = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00
            } else {
                guard !(0xDC00...0xDFFF).contains(first) else {
                    throw HelpCatalogError.invalidJSON
                }
                scalarValue = first
            }
            guard let scalar = UnicodeScalar(scalarValue) else {
                throw HelpCatalogError.invalidJSON
            }
            return scalar
        default:
            throw HelpCatalogError.invalidJSON
        }
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw HelpCatalogError.invalidJSON
            }
            value = (value << 4) | UInt32(digit)
            index += 1
        }
        return value
    }

    private mutating func parseUTF8Scalar() throws -> UnicodeScalar {
        guard let first = currentByte else { throw HelpCatalogError.invalidJSON }
        let length: Int
        let minimum: UInt32
        var value: UInt32
        switch first {
        case 0x00...0x7F:
            length = 1
            minimum = 0
            value = UInt32(first)
        case 0xC2...0xDF:
            length = 2
            minimum = 0x80
            value = UInt32(first & 0x1F)
        case 0xE0...0xEF:
            length = 3
            minimum = 0x800
            value = UInt32(first & 0x0F)
        case 0xF0...0xF4:
            length = 4
            minimum = 0x10000
            value = UInt32(first & 0x07)
        default:
            throw HelpCatalogError.invalidJSON
        }
        guard length <= bytes.count, index <= bytes.count - length else {
            throw HelpCatalogError.invalidJSON
        }
        for offset in 1..<length {
            let continuation = bytes[index + offset]
            guard (0x80...0xBF).contains(continuation) else {
                throw HelpCatalogError.invalidJSON
            }
            value = (value << 6) | UInt32(continuation & 0x3F)
        }
        guard value >= minimum,
            !(0xD800...0xDFFF).contains(value),
            value <= 0x10FFFF,
            let scalar = UnicodeScalar(value)
        else {
            throw HelpCatalogError.invalidJSON
        }
        index += length
        return scalar
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = consume(0x2D)
        guard let first = currentByte else { throw HelpCatalogError.invalidJSON }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw HelpCatalogError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw HelpCatalogError.invalidJSON
            }
            while currentByte.map({ (0x30...0x39).contains($0) }) == true {
                try advanceNumber(from: start)
            }
        }
        if consume(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw HelpCatalogError.invalidJSON
            }
            while currentByte.map({ (0x30...0x39).contains($0) }) == true {
                try advanceNumber(from: start)
            }
        }
        if consume(0x65) || consume(0x45) {
            _ = consume(0x2B) || consume(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw HelpCatalogError.invalidJSON
            }
            while currentByte.map({ (0x30...0x39).contains($0) }) == true {
                try advanceNumber(from: start)
            }
        }
        guard index - start <= Self.maximumJSONNumberBytes else {
            throw HelpCatalogError.jsonNumberTooLarge(
                maximumBytes: Self.maximumJSONNumberBytes
            )
        }
    }

    private mutating func parseInteger() throws -> Int {
        let start = index
        _ = consume(0x2D)
        guard let first = currentByte else { throw HelpCatalogError.invalidJSON }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw HelpCatalogError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw HelpCatalogError.invalidJSON
            }
            while currentByte.map({ (0x30...0x39).contains($0) }) == true {
                try advanceNumber(from: start)
            }
        }
        guard index - start <= Self.maximumJSONNumberBytes,
            let value = Int(String(decoding: bytes[start..<index], as: UTF8.self))
        else {
            throw HelpCatalogError.jsonNumberTooLarge(
                maximumBytes: Self.maximumJSONNumberBytes
            )
        }
        return value
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard literalBytes.count <= bytes.count,
            index <= bytes.count - literalBytes.count
        else {
            throw HelpCatalogError.invalidJSON
        }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw HelpCatalogError.invalidJSON }
            index += 1
        }
    }

    private mutating func advanceNumber(from start: Int) throws {
        index += 1
        guard index - start <= Self.maximumJSONNumberBytes else {
            throw HelpCatalogError.jsonNumberTooLarge(
                maximumBytes: Self.maximumJSONNumberBytes
            )
        }
        if index.isMultiple(of: 32) { try Task.checkCancellation() }
    }

    private mutating func consumeAggregateElement(_ aggregate: Aggregate?) throws {
        switch aggregate {
        case .topics:
            guard remainingTopics > 0 else {
                throw HelpCatalogError.tooManyTopics(maximum: limits.maximumTopics)
            }
            remainingTopics -= 1
        case .credits:
            guard remainingCredits > 0 else {
                throw HelpCatalogError.tooManyCredits(maximum: limits.maximumCredits)
            }
            remainingCredits -= 1
        case .contexts:
            guard remainingContexts > 0 else {
                throw HelpCatalogError.tooManyContexts(maximum: limits.maximumContexts)
            }
            remainingContexts -= 1
        case .links:
            guard remainingLinks > 0 else {
                throw HelpCatalogError.tooManyLinks(maximum: limits.maximumLinks)
            }
            remainingLinks -= 1
        case .relationships:
            guard remainingRelationships > 0 else {
                throw HelpCatalogError.tooManyRelationships(
                    maximum: limits.maximumRelationships
                )
            }
            remainingRelationships -= 1
        case .localizationKeys:
            guard remainingLocalizationKeys > 0 else {
                throw HelpCatalogError.tooManyLocalizationKeys(
                    maximum: limits.maximumLocalizationKeys
                )
            }
            remainingLocalizationKeys -= 1
        case nil:
            break
        }
    }

    private func arrayLimit(at path: SchemaPath) -> Int? {
        switch path {
        case .topics:
            limits.maximumTopics
        case .credits:
            limits.maximumCredits
        case .topicContexts:
            limits.maximumContexts
        case .topicLinks, .creditLinks, .aboutLinks:
            limits.maximumLinks
        case .topicRelatedTopicIDs, .topicCreditIDs, .aboutCreditIDs:
            limits.maximumRelationships
        case .topicKeywordLocalizationKeys:
            limits.maximumLocalizationKeys
        default: nil
        }
    }

    private func aggregate(at path: SchemaPath) -> Aggregate? {
        switch path {
        case .topics:
            .topics
        case .credits:
            .credits
        case .topicContexts:
            .contexts
        case .topicLinks, .creditLinks, .aboutLinks:
            .links
        case .topicRelatedTopicIDs, .topicCreditIDs, .aboutCreditIDs:
            .relationships
        case .topicKeywordLocalizationKeys:
            .localizationKeys
        default: nil
        }
    }

    private func objectChildPath(for key: String, at path: SchemaPath) -> SchemaPath {
        switch (path, key) {
        case (.root, "topics"):
            .topics
        case (.root, "credits"):
            .credits
        case (.root, "about"):
            .about
        case (.topic, "contexts"):
            .topicContexts
        case (.topic, "links"):
            .topicLinks
        case (.topic, "relatedTopicIDs"):
            .topicRelatedTopicIDs
        case (.topic, "creditIDs"):
            .topicCreditIDs
        case (.topic, "keywordLocalizationKeys"):
            .topicKeywordLocalizationKeys
        case (.credit, "links"):
            .creditLinks
        case (.about, "links"):
            .aboutLinks
        case (.about, "creditIDs"):
            .aboutCreditIDs
        default:
            .unknown
        }
    }

    private func arrayElementPath(for path: SchemaPath) -> SchemaPath {
        switch path {
        case .topics:
            .topic
        case .topicContexts:
            .topicContext
        case .topicLinks:
            .topicLink
        case .credits:
            .credit
        case .creditLinks:
            .creditLink
        case .aboutLinks:
            .aboutLink
        default:
            .unknown
        }
    }

    private func validateDepth(_ depth: Int) throws {
        guard depth <= Self.maximumNestingDepth else {
            throw HelpCatalogError.jsonNestingTooDeep(maximum: Self.maximumNestingDepth)
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
            try checkCancellationAfterAdvance()
        }
    }

    private mutating func checkCancellationAfterAdvance() throws {
        guard index >= nextCancellationCheck else { return }
        try Task.checkCancellation()
        nextCancellationCheck = index + 4_096
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }
}
