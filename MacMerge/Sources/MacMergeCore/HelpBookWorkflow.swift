import Foundation

/// UI-independent Help Book expansion planner over `HelpCatalog`.
///
/// Plan-only: no Help Book UI, no app wiring, no writes, no process launch.
/// Trusted bundled-resource links are revalidated read-only through
/// `HelpCatalogLink` construction; executors must open resources via
/// `HelpCatalogLink.openBundledResource()` at execution time.
public struct HelpBookWorkflowReleaseVersion: Codable, Comparable, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let original: String

    public init(major: Int, minor: Int, patch: Int, original: String) throws {
        guard major >= 0, minor >= 0, patch >= 0 else {
            throw HelpBookWorkflowError.invalidReleaseVersion(original)
        }
        guard major <= 999_999, minor <= 999_999, patch <= 999_999 else {
            throw HelpBookWorkflowError.invalidReleaseVersion(original)
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.original = original
    }

    public init(parsing value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 64 else {
            throw HelpBookWorkflowError.invalidReleaseVersion(value)
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else {
            throw HelpBookWorkflowError.invalidReleaseVersion(value)
        }
        var numbers: [Int] = []
        numbers.reserveCapacity(3)
        for part in parts {
            guard part.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else {
                throw HelpBookWorkflowError.invalidReleaseVersion(value)
            }
            let dropped = part.drop(while: { $0 == "0" })
            let normalized = dropped.isEmpty ? "0" : String(dropped)
            guard normalized.utf8.count <= 6, let number = Int(normalized) else {
                throw HelpBookWorkflowError.invalidReleaseVersion(value)
            }
            numbers.append(number)
        }
        try self.init(major: numbers[0], minor: numbers[1], patch: numbers[2], original: trimmed)
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.major != right.major { return left.major < right.major }
        if left.minor != right.minor { return left.minor < right.minor }
        return left.patch < right.patch
    }
}

/// Caller-declared release-notes binding. Version orders presentation; topic holds content.
public struct HelpBookWorkflowReleaseInput: Codable, Hashable, Sendable {
    public let version: String
    public let topicID: String

    public init(version: String, topicID: String) {
        self.version = version
        self.topicID = topicID
    }
}

public struct HelpBookWorkflowProvenance: Codable, Equatable, Hashable, Sendable {
    public let versionSource: HelpCatalog.VersionSource?
    public let buildSource: HelpCatalog.VersionSource?
    public let catalogManifestVersion: Int

    public init(
        versionSource: HelpCatalog.VersionSource? = nil,
        buildSource: HelpCatalog.VersionSource? = nil,
        catalogManifestVersion: Int = HelpCatalog.currentManifestVersion
    ) {
        self.versionSource = versionSource
        self.buildSource = buildSource
        self.catalogManifestVersion = catalogManifestVersion
    }
}

public struct HelpBookWorkflowLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumAnchors = 8_192
    public static let hardMaximumReleaseNotes = 1_024
    public static let hardMaximumLocales = 64
    public static let hardMaximumLicenseTopics = 64
    public static let hardMaximumContributorRefs = 16_384
    public static let hardMaximumValidatedLinks = 32_768
    public static let hardMaximumMetadataUTF8Bytes = 8 * 1_024 * 1_024
    public static let hardMaximumPersistedBytes = 1 * 1_024 * 1_024
    public static let hardMaximumWorkUnits = 16 * 1_024 * 1_024
    public static let `default` = HelpBookWorkflowLimits()

    public let maximumAnchors: Int
    public let maximumReleaseNotes: Int
    public let maximumLocales: Int
    public let maximumLicenseTopics: Int
    public let maximumContributorRefs: Int
    public let maximumValidatedLinks: Int
    public let maximumMetadataUTF8Bytes: Int
    public let maximumPersistedBytes: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumAnchors: Int = 1_024,
        maximumReleaseNotes: Int = 256,
        maximumLocales: Int = 16,
        maximumLicenseTopics: Int = 16,
        maximumContributorRefs: Int = 4_096,
        maximumValidatedLinks: Int = 8_192,
        maximumMetadataUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumPersistedBytes: Int = 256 * 1_024,
        maximumWorkUnits: Int = 4 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 128
    ) {
        self.maximumAnchors = maximumAnchors
        self.maximumReleaseNotes = maximumReleaseNotes
        self.maximumLocales = maximumLocales
        self.maximumLicenseTopics = maximumLicenseTopics
        self.maximumContributorRefs = maximumContributorRefs
        self.maximumValidatedLinks = maximumValidatedLinks
        self.maximumMetadataUTF8Bytes = maximumMetadataUTF8Bytes
        self.maximumPersistedBytes = maximumPersistedBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct HelpBookWorkflowRequest: Sendable {
    public let catalog: HelpCatalog
    public let preferredLocaleIdentifiers: [String]
    public let releaseInputs: [HelpBookWorkflowReleaseInput]
    public let trustPolicy: HelpCatalog.TrustPolicy
    public let provenance: HelpBookWorkflowProvenance
    public let limits: HelpBookWorkflowLimits
    public let searchLimits: HelpCatalog.SearchLimits

    public init(
        catalog: HelpCatalog,
        preferredLocaleIdentifiers: [String] = [],
        releaseInputs: [HelpBookWorkflowReleaseInput] = [],
        trustPolicy: HelpCatalog.TrustPolicy = .denyAll,
        provenance: HelpBookWorkflowProvenance = HelpBookWorkflowProvenance(),
        limits: HelpBookWorkflowLimits = .default,
        searchLimits: HelpCatalog.SearchLimits = .default
    ) {
        self.catalog = catalog
        self.preferredLocaleIdentifiers = preferredLocaleIdentifiers
        self.releaseInputs = releaseInputs
        self.trustPolicy = trustPolicy
        self.provenance = provenance
        self.limits = limits
        self.searchLimits = searchLimits
    }
}

public struct HelpBookWorkflowAnchorResolution: Codable, Equatable, Hashable, Sendable {
    public let anchor: String
    public let topicID: String

    public init(anchor: String, topicID: String) {
        self.anchor = anchor
        self.topicID = topicID
    }
}

public struct HelpBookWorkflowReleaseResolution: Codable, Equatable, Hashable, Sendable {
    public let version: HelpBookWorkflowReleaseVersion
    public let topicID: String

    public init(version: HelpBookWorkflowReleaseVersion, topicID: String) {
        self.version = version
        self.topicID = topicID
    }
}

public struct HelpBookWorkflowEstimate: Codable, Equatable, Hashable, Sendable {
    public let anchorCount: Int
    public let releaseNoteCount: Int
    public let licenseTopicCount: Int
    public let contributorCount: Int
    public let validatedLinkCount: Int
    public let metadataUTF8ByteCount: Int
    public let workUnits: Int

    fileprivate init(
        anchorCount: Int,
        releaseNoteCount: Int,
        licenseTopicCount: Int,
        contributorCount: Int,
        validatedLinkCount: Int,
        metadataUTF8ByteCount: Int,
        workUnits: Int
    ) {
        self.anchorCount = anchorCount
        self.releaseNoteCount = releaseNoteCount
        self.licenseTopicCount = licenseTopicCount
        self.contributorCount = contributorCount
        self.validatedLinkCount = validatedLinkCount
        self.metadataUTF8ByteCount = metadataUTF8ByteCount
        self.workUnits = workUnits
    }
}

public struct HelpBookWorkflowSnapshotReference: Codable, Equatable, Hashable, Sendable {
    public let planID: UUID
    public let catalogDigest: UInt64
    public let inputDigest: UInt64

    public init(planID: UUID, catalogDigest: UInt64, inputDigest: UInt64) {
        self.planID = planID
        self.catalogDigest = catalogDigest
        self.inputDigest = inputDigest
    }
}

public enum HelpBookWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(name: String, value: Int)
    case tooManyAnchors(maximum: Int)
    case tooManyReleaseNotes(maximum: Int)
    case tooManyLocales(maximum: Int)
    case tooManyLicenseTopics(maximum: Int)
    case tooManyContributorRefs(maximum: Int)
    case tooManyValidatedLinks(maximum: Int)
    case metadataTooLarge(maximumUTF8Bytes: Int)
    case persistedDataTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case invalidLocale(String)
    case invalidReleaseVersion(String)
    case duplicateReleaseVersion(String)
    case unknownReleaseTopic(String)
    case releaseTopicKindMismatch(String)
    case invalidAnchor(String)
    case duplicateAnchor(String)
    case unknownTopic(String)
    case untrustedLink(topicID: String, target: String)
    case searchFailed(String)
    case invalidReceipt(String)
    case unsupportedReceiptVersion(Int)
    case unknownReceiptKey(path: String, key: String)
    case snapshotContentsChanged
    case arithmeticOverflow

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Help Book planning was cancelled."
        case .invalidLimit(let name, let value):
            "Invalid Help Book workflow limit \(name): \(value)."
        case .tooManyAnchors(let maximum):
            "Help Book exceeds the \(maximum)-anchor limit."
        case .tooManyReleaseNotes(let maximum):
            "Help Book exceeds the \(maximum)-release-note limit."
        case .tooManyLocales(let maximum):
            "Help Book exceeds the \(maximum)-locale limit."
        case .tooManyLicenseTopics(let maximum):
            "Help Book exceeds the \(maximum)-license-topic limit."
        case .tooManyContributorRefs(let maximum):
            "Help Book exceeds the \(maximum)-contributor limit."
        case .tooManyValidatedLinks(let maximum):
            "Help Book exceeds the \(maximum)-validated-link limit."
        case .metadataTooLarge(let maximum):
            "Help Book metadata exceeds the \(maximum)-byte UTF-8 limit."
        case .persistedDataTooLarge(let maximum):
            "Help Book receipt exceeds the \(maximum)-byte limit."
        case .workLimitExceeded(let maximum):
            "Help Book planning exceeds the \(maximum)-unit work limit."
        case .invalidLocale(let value):
            "Help Book locale identifier is invalid: \(value)."
        case .invalidReleaseVersion(let value):
            "Help Book release version is invalid: \(value)."
        case .duplicateReleaseVersion(let value):
            "Help Book release version appears more than once: \(value)."
        case .unknownReleaseTopic(let value):
            "Help Book release topic is unknown: \(value)."
        case .releaseTopicKindMismatch(let value):
            "Help Book release topic has wrong kind: \(value)."
        case .invalidAnchor(let value):
            "Help Book anchor is invalid: \(value)."
        case .duplicateAnchor(let value):
            "Help Book anchor appears more than once: \(value)."
        case .unknownTopic(let value):
            "Help Book topic is unknown: \(value)."
        case .untrustedLink(let topicID, let target):
            "Help Book link in \(topicID) is not trusted: \(target)."
        case .searchFailed(let value):
            "Help Book search failed: \(value)."
        case .invalidReceipt(let value):
            "Help Book receipt is invalid: \(value)."
        case .unsupportedReceiptVersion(let value):
            "Unsupported Help Book receipt version: \(value)."
        case .unknownReceiptKey(let path, let key):
            "Help Book receipt contains unknown key \(key) at \(path)."
        case .snapshotContentsChanged:
            "Help Book snapshot changed without a plan refresh."
        case .arithmeticOverflow:
            "Help Book size calculation overflowed."
        }
    }
}

/// Plan-only workflow output. No filesystem writes, no pasteboard, no Help viewer calls.
public struct HelpBookWorkflowPlan: Equatable, Sendable {
    public static let currentReceiptVersion = 1

    public let reference: HelpBookWorkflowSnapshotReference
    public let catalog: HelpCatalog
    public let fallbackLocales: [String]
    public let anchors: [HelpBookWorkflowAnchorResolution]
    public let releases: [HelpBookWorkflowReleaseResolution]
    public let licenseTopicIDs: [String]
    public let contributorCreditIDs: [String]
    public let provenance: HelpBookWorkflowProvenance
    public let estimate: HelpBookWorkflowEstimate
    public let limits: HelpBookWorkflowLimits
    public let searchLimits: HelpCatalog.SearchLimits

    fileprivate init(
        reference: HelpBookWorkflowSnapshotReference,
        catalog: HelpCatalog,
        fallbackLocales: [String],
        anchors: [HelpBookWorkflowAnchorResolution],
        releases: [HelpBookWorkflowReleaseResolution],
        licenseTopicIDs: [String],
        contributorCreditIDs: [String],
        provenance: HelpBookWorkflowProvenance,
        estimate: HelpBookWorkflowEstimate,
        limits: HelpBookWorkflowLimits,
        searchLimits: HelpCatalog.SearchLimits
    ) {
        self.reference = reference
        self.catalog = catalog
        self.fallbackLocales = fallbackLocales
        self.anchors = anchors
        self.releases = releases
        self.licenseTopicIDs = licenseTopicIDs
        self.contributorCreditIDs = contributorCreditIDs
        self.provenance = provenance
        self.estimate = estimate
        self.limits = limits
        self.searchLimits = searchLimits
    }

    public var primaryLocale: Locale {
        Locale(identifier: fallbackLocales.first ?? "en")
    }

    public var orderedReleaseTopicIDs: [String] {
        releases.map(\.topicID)
    }

    public func topic(forAnchor anchor: String) throws -> HelpCatalog.Topic {
        do {
            try Task.checkCancellation()
            guard anchors.contains(where: { $0.anchor == anchor }) else {
                throw HelpBookWorkflowError.invalidAnchor(anchor)
            }
            guard let topic = try catalog.topic(forHelpBookAnchor: anchor) else {
                throw HelpBookWorkflowError.unknownTopic(anchor)
            }
            return topic
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        } catch let error as HelpBookWorkflowError {
            throw error
        } catch {
            throw HelpBookWorkflowError.searchFailed(anchor)
        }
    }

    public func licenseTopics() throws -> [HelpCatalog.Topic] {
        do {
            try Task.checkCancellation()
            var result: [HelpCatalog.Topic] = []
            result.reserveCapacity(licenseTopicIDs.count)
            for id in licenseTopicIDs {
                try Task.checkCancellation()
                guard let topic = catalog.topic(withID: id) else {
                    throw HelpBookWorkflowError.unknownTopic(id)
                }
                result.append(topic)
            }
            return result
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        }
    }

    public func contributorCredits() throws -> [HelpCatalog.Credit] {
        do {
            try Task.checkCancellation()
            var result: [HelpCatalog.Credit] = []
            result.reserveCapacity(contributorCreditIDs.count)
            for id in contributorCreditIDs {
                try Task.checkCancellation()
                guard let credit = catalog.credit(withID: id) else {
                    throw HelpBookWorkflowError.unknownTopic(id)
                }
                result.append(credit)
            }
            return result
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        }
    }

    /// Locale-aware search using primary fallback locale. Localized values fall back
    /// through `fallbackLocales` keys when caller supplies per-locale dictionaries.
    public func search(
        _ query: String,
        localizedValues: [String: String] = [:]
    ) throws -> [HelpCatalog.SearchResult] {
        do {
            try Task.checkCancellation()
            do {
                return try catalog.search(
                    query,
                    locale: primaryLocale,
                    localizedValues: localizedValues,
                    limits: searchLimits
                )
            } catch let error as HelpCatalogError {
                throw HelpBookWorkflowError.searchFailed(error.localizedDescription)
            }
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        }
    }

    /// Fallback search: tries each fallback locale in order, returns first non-empty hit.
    public func searchWithFallback(
        _ query: String,
        localizedValuesByLocale: [String: [String: String]] = [:]
    ) throws -> [HelpCatalog.SearchResult] {
        do {
            try Task.checkCancellation()
            var lastEmpty: [HelpCatalog.SearchResult] = []
            for (index, identifier) in fallbackLocales.enumerated() {
                if index % 8 == 0 { try Task.checkCancellation() }
                let values = localizedValuesByLocale[identifier] ?? [:]
                let locale = Locale(identifier: identifier)
                let hits: [HelpCatalog.SearchResult]
                do {
                    hits = try catalog.search(
                        query,
                        locale: locale,
                        localizedValues: values,
                        limits: searchLimits
                    )
                } catch let error as HelpCatalogError {
                    throw HelpBookWorkflowError.searchFailed(error.localizedDescription)
                }
                if !hits.isEmpty { return hits }
                lastEmpty = hits
            }
            return lastEmpty
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        }
    }

    public func receipt() -> HelpBookWorkflowReceipt {
        HelpBookWorkflowReceipt(
            receiptVersion: Self.currentReceiptVersion,
            reference: reference,
            fallbackLocales: fallbackLocales,
            releaseTopicIDs: orderedReleaseTopicIDs,
            anchorCount: estimate.anchorCount,
            licenseTopicCount: estimate.licenseTopicCount,
            contributorCount: estimate.contributorCount,
            validatedLinkCount: estimate.validatedLinkCount,
            provenance: provenance
        )
    }

    public func encodeReceipt() throws -> Data {
        do {
            try Task.checkCancellation()
            let receipt = self.receipt()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(receipt)
            guard data.count <= limits.maximumPersistedBytes else {
                throw HelpBookWorkflowError.persistedDataTooLarge(
                    maximumBytes: limits.maximumPersistedBytes
                )
            }
            return data
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        }
    }

    public func validateCurrent(
        _ snapshot: HelpCatalog,
        preferredLocaleIdentifiers: [String],
        releaseInputs: [HelpBookWorkflowReleaseInput]
    ) throws {
        do {
            try Task.checkCancellation()
            try HelpBookWorkflowPlanner.validate(
                snapshot,
                preferredLocaleIdentifiers: preferredLocaleIdentifiers,
                releaseInputs: releaseInputs,
                against: self
            )
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        }
    }

    public func isCurrent(
        _ snapshot: HelpCatalog,
        preferredLocaleIdentifiers: [String],
        releaseInputs: [HelpBookWorkflowReleaseInput]
    ) throws -> Bool {
        do {
            try validateCurrent(
                snapshot,
                preferredLocaleIdentifiers: preferredLocaleIdentifiers,
                releaseInputs: releaseInputs
            )
            return true
        } catch HelpBookWorkflowError.snapshotContentsChanged {
            return false
        }
    }
}

public struct HelpBookWorkflowReceipt: Codable, Equatable, Hashable, Sendable {
    public let receiptVersion: Int
    public let reference: HelpBookWorkflowSnapshotReference
    public let fallbackLocales: [String]
    public let releaseTopicIDs: [String]
    public let anchorCount: Int
    public let licenseTopicCount: Int
    public let contributorCount: Int
    public let validatedLinkCount: Int
    public let provenance: HelpBookWorkflowProvenance

    public init(
        receiptVersion: Int,
        reference: HelpBookWorkflowSnapshotReference,
        fallbackLocales: [String],
        releaseTopicIDs: [String],
        anchorCount: Int,
        licenseTopicCount: Int,
        contributorCount: Int,
        validatedLinkCount: Int,
        provenance: HelpBookWorkflowProvenance
    ) {
        self.receiptVersion = receiptVersion
        self.reference = reference
        self.fallbackLocales = fallbackLocales
        self.releaseTopicIDs = releaseTopicIDs
        self.anchorCount = anchorCount
        self.licenseTopicCount = licenseTopicCount
        self.contributorCount = contributorCount
        self.validatedLinkCount = validatedLinkCount
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case receiptVersion
        case reference
        case fallbackLocales
        case releaseTopicIDs
        case anchorCount
        case licenseTopicCount
        case contributorCount
        case validatedLinkCount
        case provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: HelpBookWorkflowAnyKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
        if let key = unknown.first {
            let path = decoder.codingPath.isEmpty ? "$" : "$." + decoder.codingPath.map(\.stringValue).joined(separator: ".")
            throw HelpBookWorkflowError.unknownReceiptKey(path: path, key: key)
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let version = try keyed.decode(Int.self, forKey: .receiptVersion)
        guard version == HelpBookWorkflowPlan.currentReceiptVersion else {
            throw HelpBookWorkflowError.unsupportedReceiptVersion(version)
        }
        self.init(
            receiptVersion: version,
            reference: try keyed.decode(HelpBookWorkflowSnapshotReference.self, forKey: .reference),
            fallbackLocales: try keyed.decode([String].self, forKey: .fallbackLocales),
            releaseTopicIDs: try keyed.decode([String].self, forKey: .releaseTopicIDs),
            anchorCount: try keyed.decode(Int.self, forKey: .anchorCount),
            licenseTopicCount: try keyed.decode(Int.self, forKey: .licenseTopicCount),
            contributorCount: try keyed.decode(Int.self, forKey: .contributorCount),
            validatedLinkCount: try keyed.decode(Int.self, forKey: .validatedLinkCount),
            provenance: try keyed.decode(HelpBookWorkflowProvenance.self, forKey: .provenance)
        )
    }
}

private struct HelpBookWorkflowAnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

public enum HelpBookWorkflowPlanner: Sendable {
    public static func plan(_ request: HelpBookWorkflowRequest) throws -> HelpBookWorkflowPlan {
        do {
            return try makePlan(request)
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        } catch let error as HelpBookWorkflowError {
            throw error
        } catch {
            throw HelpBookWorkflowError.searchFailed("planning failed")
        }
    }

    public static func decodeReceipt(
        from data: Data,
        limits: HelpBookWorkflowLimits = .default
    ) throws -> HelpBookWorkflowReceipt {
        do {
            try Task.checkCancellation()
            try validateLimits(limits)
            guard data.count <= limits.maximumPersistedBytes else {
                throw HelpBookWorkflowError.persistedDataTooLarge(
                    maximumBytes: limits.maximumPersistedBytes
                )
            }
            do {
                let decoder = JSONDecoder()
                let receipt = try decoder.decode(HelpBookWorkflowReceipt.self, from: data)
                try validateReceipt(receipt, limits: limits)
                return receipt
            } catch let error as HelpBookWorkflowError {
                throw error
            } catch {
                throw HelpBookWorkflowError.invalidReceipt("decode failed")
            }
        } catch is CancellationError {
            throw HelpBookWorkflowError.cancelled
        }
    }

    fileprivate static func validate(
        _ snapshot: HelpCatalog,
        preferredLocaleIdentifiers: [String],
        releaseInputs: [HelpBookWorkflowReleaseInput],
        against plan: HelpBookWorkflowPlan
    ) throws {
        try Task.checkCancellation()
        try validateLimits(plan.limits)
        let catalogDigest = try digest(catalog: snapshot, limits: plan.limits)
        let expectedCatalogDigest = plan.reference.catalogDigest
        guard catalogDigest == expectedCatalogDigest else {
            throw HelpBookWorkflowError.snapshotContentsChanged
        }
        let fallback = try fallbackChain(
            preferredLocaleIdentifiers,
            limits: plan.limits
        )
        guard fallback == plan.fallbackLocales else {
            throw HelpBookWorkflowError.snapshotContentsChanged
        }
        let releases = try orderedReleases(
            releaseInputs,
            catalog: snapshot,
            limits: plan.limits
        )
        guard releases.map(\.topicID) == plan.releases.map(\.topicID) else {
            throw HelpBookWorkflowError.snapshotContentsChanged
        }
    }

    private static func makePlan(_ request: HelpBookWorkflowRequest) throws -> HelpBookWorkflowPlan {
        try Task.checkCancellation()
        try validateLimits(request.limits)
        try validateSearchLimits(request.searchLimits)
        guard request.provenance.catalogManifestVersion == HelpCatalog.currentManifestVersion else {
            throw HelpBookWorkflowError.invalidReceipt("catalogManifestVersion")
        }

        var work = HelpBookWorkflowBudget(maximum: request.limits.maximumWorkUnits)
        var metadataBytes = 0

        let fallback = try fallbackChain(
            request.preferredLocaleIdentifiers,
            limits: request.limits
        )
        for identifier in fallback {
            try consumeUTF8(
                identifier,
                total: &metadataBytes,
                maximum: request.limits.maximumMetadataUTF8Bytes
            )
            try work.consume(identifier.utf8.count)
        }

        let releases = try orderedReleases(
            request.releaseInputs,
            catalog: request.catalog,
            limits: request.limits
        )
        for release in releases {
            try consumeUTF8(
                release.topicID,
                total: &metadataBytes,
                maximum: request.limits.maximumMetadataUTF8Bytes
            )
            try consumeUTF8(
                release.version.original,
                total: &metadataBytes,
                maximum: request.limits.maximumMetadataUTF8Bytes
            )
            try work.consume(64)
        }

        let anchors = try anchorResolutions(
            catalog: request.catalog,
            limits: request.limits,
            work: &work,
            metadata: &metadataBytes
        )
        let licenseIDs = try licenseTopicIDs(
            catalog: request.catalog,
            limits: request.limits,
            work: &work,
            metadata: &metadataBytes
        )
        let contributorIDs = try contributorCreditIDs(
            catalog: request.catalog,
            limits: request.limits,
            work: &work,
            metadata: &metadataBytes
        )
        let validatedLinks = try validateTrustedLinks(
            catalog: request.catalog,
            trustPolicy: request.trustPolicy,
            limits: request.limits,
            work: &work,
            metadata: &metadataBytes
        )

        let catalogDigest = try digest(catalog: request.catalog, limits: request.limits)
        let inputDigest = try inputDigest(
            fallback: fallback,
            releases: releases,
            limits: request.limits
        )
        let estimate = HelpBookWorkflowEstimate(
            anchorCount: anchors.count,
            releaseNoteCount: releases.count,
            licenseTopicCount: licenseIDs.count,
            contributorCount: contributorIDs.count,
            validatedLinkCount: validatedLinks,
            metadataUTF8ByteCount: metadataBytes,
            workUnits: work.consumed
        )
        return HelpBookWorkflowPlan(
            reference: HelpBookWorkflowSnapshotReference(
                planID: UUID(),
                catalogDigest: catalogDigest,
                inputDigest: inputDigest
            ),
            catalog: request.catalog,
            fallbackLocales: fallback,
            anchors: anchors,
            releases: releases,
            licenseTopicIDs: licenseIDs,
            contributorCreditIDs: contributorIDs,
            provenance: request.provenance,
            estimate: estimate,
            limits: request.limits,
            searchLimits: request.searchLimits
        )
    }

    private static func fallbackChain(
        _ identifiers: [String],
        limits: HelpBookWorkflowLimits
    ) throws -> [String] {
        try Task.checkCancellation()
        guard identifiers.count <= limits.maximumLocales else {
            throw HelpBookWorkflowError.tooManyLocales(maximum: limits.maximumLocales)
        }
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(min(identifiers.count + 1, limits.maximumLocales))
        for (index, raw) in identifiers.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            let canonical = try canonicalLocale(raw)
            if seen.insert(canonical).inserted {
                result.append(canonical)
            }
        }
        if seen.insert("en").inserted {
            guard result.count < limits.maximumLocales else {
                throw HelpBookWorkflowError.tooManyLocales(maximum: limits.maximumLocales)
            }
            result.append("en")
        }
        return result
    }

    private static func canonicalLocale(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 35 else {
            throw HelpBookWorkflowError.invalidLocale(value)
        }
        let lowered = trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard !lowered.hasPrefix("-"), !lowered.hasSuffix("-"), !lowered.contains("--") else {
            throw HelpBookWorkflowError.invalidLocale(value)
        }
        let isLocaleByte: (UInt8) -> Bool = {
            ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D
        }
        guard lowered.utf8.allSatisfy(isLocaleByte) else {
            throw HelpBookWorkflowError.invalidLocale(value)
        }
        return lowered
    }

    private static func orderedReleases(
        _ inputs: [HelpBookWorkflowReleaseInput],
        catalog: HelpCatalog,
        limits: HelpBookWorkflowLimits
    ) throws -> [HelpBookWorkflowReleaseResolution] {
        try Task.checkCancellation()
        guard inputs.count <= limits.maximumReleaseNotes else {
            throw HelpBookWorkflowError.tooManyReleaseNotes(maximum: limits.maximumReleaseNotes)
        }
        var seenVersions: Set<String> = []
        var seenTopicIDs: Set<String> = []
        var parsed: [HelpBookWorkflowReleaseResolution] = []
        parsed.reserveCapacity(inputs.count)
        for (index, input) in inputs.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            let version = try HelpBookWorkflowReleaseVersion(parsing: input.version)
            guard seenVersions.insert(version.original).inserted else {
                throw HelpBookWorkflowError.duplicateReleaseVersion(version.original)
            }
            guard seenTopicIDs.insert(input.topicID).inserted else {
                throw HelpBookWorkflowError.duplicateReleaseVersion(input.topicID)
            }
            guard let topic = catalog.topic(withID: input.topicID) else {
                throw HelpBookWorkflowError.unknownReleaseTopic(input.topicID)
            }
            guard topic.kind == .releaseNotes else {
                throw HelpBookWorkflowError.releaseTopicKindMismatch(input.topicID)
            }
            parsed.append(HelpBookWorkflowReleaseResolution(version: version, topicID: input.topicID))
        }
        parsed.sort { left, right in
            if left.version != right.version { return left.version > right.version }
            return left.topicID < right.topicID
        }
        return parsed
    }

    private static func anchorResolutions(
        catalog: HelpCatalog,
        limits: HelpBookWorkflowLimits,
        work: inout HelpBookWorkflowBudget,
        metadata: inout Int
    ) throws -> [HelpBookWorkflowAnchorResolution] {
        try Task.checkCancellation()
        var seen: Set<String> = []
        var result: [HelpBookWorkflowAnchorResolution] = []
        for (index, topic) in catalog.topics.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            for link in topic.links where link.scheme == .helpBook {
                try work.consume(link.target.utf8.count + 8)
                guard let anchor = link.helpBookAnchor else { continue }
                try consumeUTF8(anchor, total: &metadata, maximum: limits.maximumMetadataUTF8Bytes)
                guard !anchor.isEmpty else {
                    throw HelpBookWorkflowError.invalidAnchor(topic.id)
                }
                guard seen.insert(anchor).inserted else {
                    throw HelpBookWorkflowError.duplicateAnchor(anchor)
                }
                guard result.count < limits.maximumAnchors else {
                    throw HelpBookWorkflowError.tooManyAnchors(maximum: limits.maximumAnchors)
                }
                _ = try catalog.topic(forHelpBookAnchor: anchor)
                result.append(HelpBookWorkflowAnchorResolution(anchor: anchor, topicID: topic.id))
            }
        }
        result.sort { $0.anchor < $1.anchor }
        return result
    }

    private static func licenseTopicIDs(
        catalog: HelpCatalog,
        limits: HelpBookWorkflowLimits,
        work: inout HelpBookWorkflowBudget,
        metadata: inout Int
    ) throws -> [String] {
        try Task.checkCancellation()
        let topics = try catalog.topics(ofKind: .license)
        guard topics.count <= limits.maximumLicenseTopics else {
            throw HelpBookWorkflowError.tooManyLicenseTopics(maximum: limits.maximumLicenseTopics)
        }
        var result: [String] = []
        result.reserveCapacity(topics.count)
        for (index, topic) in topics.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            try work.consume(topic.id.utf8.count + 16)
            try consumeUTF8(topic.id, total: &metadata, maximum: limits.maximumMetadataUTF8Bytes)
            result.append(topic.id)
        }
        return result.sorted()
    }

    private static func contributorCreditIDs(
        catalog: HelpCatalog,
        limits: HelpBookWorkflowLimits,
        work: inout HelpBookWorkflowBudget,
        metadata: inout Int
    ) throws -> [String] {
        try Task.checkCancellation()
        guard catalog.creditIDs.count <= limits.maximumContributorRefs else {
            throw HelpBookWorkflowError.tooManyContributorRefs(maximum: limits.maximumContributorRefs)
        }
        var result: [String] = []
        result.reserveCapacity(catalog.creditIDs.count)
        for (index, id) in catalog.creditIDs.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            try work.consume(id.utf8.count + 8)
            try consumeUTF8(id, total: &metadata, maximum: limits.maximumMetadataUTF8Bytes)
            result.append(id)
        }
        for topic in catalog.topics {
            for creditID in topic.creditIDs where !result.contains(creditID) {
                result.append(creditID)
            }
        }
        for creditID in catalog.about.creditIDs where !result.contains(creditID) {
            result.append(creditID)
        }
        guard result.count <= limits.maximumContributorRefs else {
            throw HelpBookWorkflowError.tooManyContributorRefs(maximum: limits.maximumContributorRefs)
        }
        return result.sorted()
    }

    private static func validateTrustedLinks(
        catalog: HelpCatalog,
        trustPolicy: HelpCatalog.TrustPolicy,
        limits: HelpBookWorkflowLimits,
        work: inout HelpBookWorkflowBudget,
        metadata: inout Int
    ) throws -> Int {
        try Task.checkCancellation()
        var count = 0
        var allLinks: [(owner: String, link: HelpCatalog.Link)] = []
        allLinks.reserveCapacity(min(catalog.topics.count * 2, limits.maximumValidatedLinks))
        for topic in catalog.topics {
            for link in topic.links {
                allLinks.append((owner: topic.id, link: link))
            }
        }
        for credit in catalog.credits {
            for link in credit.links {
                allLinks.append((owner: credit.id, link: link))
            }
        }
        for link in catalog.about.links {
            allLinks.append((owner: "about", link: link))
        }
        guard allLinks.count <= limits.maximumValidatedLinks else {
            throw HelpBookWorkflowError.tooManyValidatedLinks(maximum: limits.maximumValidatedLinks)
        }
        for (index, entry) in allLinks.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            try work.consume(entry.link.target.utf8.count + 32)
            try consumeUTF8(entry.link.target, total: &metadata, maximum: limits.maximumMetadataUTF8Bytes)
            do {
                _ = try HelpCatalog.Link(
                    scheme: entry.link.scheme,
                    target: entry.link.target,
                    fragment: entry.link.fragment,
                    labelLocalizationKey: entry.link.labelLocalizationKey,
                    trustPolicy: trustPolicy
                )
            } catch {
                throw HelpBookWorkflowError.untrustedLink(topicID: entry.owner, target: entry.link.target)
            }
            count += 1
        }
        return count
    }

    private static func digest(
        catalog: HelpCatalog,
        limits: HelpBookWorkflowLimits
    ) throws -> UInt64 {
        try Task.checkCancellation()
        var hash: UInt64 = 14_695_981_039_346_656_037
        func mix(_ value: UInt64) {
            hash ^= value &+ 0x9E37_79B9_7F4A_7C15
            hash = hash &* 1_099_511_628_211
        }
        mix(UInt64(catalog.manifestVersion))
        for (index, id) in catalog.topicIDs.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            for byte in id.utf8 { mix(UInt64(byte)) }
            mix(0xFF)
        }
        for (index, id) in catalog.creditIDs.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            for byte in id.utf8 { mix(UInt64(byte)) }
            mix(0xFE)
        }
        if let version = catalog.about.version {
            for byte in version.value.utf8 { mix(UInt64(byte)) }
        }
        if let build = catalog.about.build {
            for byte in build.value.utf8 { mix(UInt64(byte)) }
        }
        return hash
    }

    private static func inputDigest(
        fallback: [String],
        releases: [HelpBookWorkflowReleaseResolution],
        limits: HelpBookWorkflowLimits
    ) throws -> UInt64 {
        try Task.checkCancellation()
        var hash: UInt64 = 14_695_981_039_346_656_037
        func mix(_ value: UInt64) {
            hash ^= value &+ 0x9E37_79B9_7F4A_7C15
            hash = hash &* 1_099_511_628_211
        }
        for (index, identifier) in fallback.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            for byte in identifier.utf8 { mix(UInt64(byte)) }
            mix(0xFD)
        }
        for (index, release) in releases.enumerated() {
            if index % limits.cancellationCheckInterval == 0 { try Task.checkCancellation() }
            for byte in release.version.original.utf8 { mix(UInt64(byte)) }
            mix(0xFC)
            for byte in release.topicID.utf8 { mix(UInt64(byte)) }
            mix(0xFB)
        }
        return hash
    }

    private static func validateReceipt(
        _ receipt: HelpBookWorkflowReceipt,
        limits: HelpBookWorkflowLimits
    ) throws {
        try Task.checkCancellation()
        guard receipt.fallbackLocales.count <= limits.maximumLocales else {
            throw HelpBookWorkflowError.tooManyLocales(maximum: limits.maximumLocales)
        }
        guard receipt.releaseTopicIDs.count <= limits.maximumReleaseNotes else {
            throw HelpBookWorkflowError.tooManyReleaseNotes(maximum: limits.maximumReleaseNotes)
        }
        guard receipt.anchorCount <= limits.maximumAnchors else {
            throw HelpBookWorkflowError.tooManyAnchors(maximum: limits.maximumAnchors)
        }
        guard receipt.licenseTopicCount <= limits.maximumLicenseTopics else {
            throw HelpBookWorkflowError.tooManyLicenseTopics(maximum: limits.maximumLicenseTopics)
        }
        guard receipt.contributorCount <= limits.maximumContributorRefs else {
            throw HelpBookWorkflowError.tooManyContributorRefs(maximum: limits.maximumContributorRefs)
        }
        guard receipt.validatedLinkCount <= limits.maximumValidatedLinks else {
            throw HelpBookWorkflowError.tooManyValidatedLinks(maximum: limits.maximumValidatedLinks)
        }
        for identifier in receipt.fallbackLocales {
            _ = try canonicalLocale(identifier)
        }
    }

    private static func validateLimits(_ limits: HelpBookWorkflowLimits) throws {
        let values: [(String, Int, Int)] = [
            ("maximumAnchors", limits.maximumAnchors, HelpBookWorkflowLimits.hardMaximumAnchors),
            ("maximumReleaseNotes", limits.maximumReleaseNotes, HelpBookWorkflowLimits.hardMaximumReleaseNotes),
            ("maximumLocales", limits.maximumLocales, HelpBookWorkflowLimits.hardMaximumLocales),
            ("maximumLicenseTopics", limits.maximumLicenseTopics, HelpBookWorkflowLimits.hardMaximumLicenseTopics),
            ("maximumContributorRefs", limits.maximumContributorRefs, HelpBookWorkflowLimits.hardMaximumContributorRefs),
            ("maximumValidatedLinks", limits.maximumValidatedLinks, HelpBookWorkflowLimits.hardMaximumValidatedLinks),
            ("maximumMetadataUTF8Bytes", limits.maximumMetadataUTF8Bytes, HelpBookWorkflowLimits.hardMaximumMetadataUTF8Bytes),
            ("maximumPersistedBytes", limits.maximumPersistedBytes, HelpBookWorkflowLimits.hardMaximumPersistedBytes),
            ("maximumWorkUnits", limits.maximumWorkUnits, HelpBookWorkflowLimits.hardMaximumWorkUnits)
        ]
        for (name, value, hardMaximum) in values {
            guard value >= 0, value <= hardMaximum else {
                throw HelpBookWorkflowError.invalidLimit(name: name, value: value)
            }
        }
        guard limits.maximumMetadataUTF8Bytes > 0 else {
            throw HelpBookWorkflowError.invalidLimit(
                name: "maximumMetadataUTF8Bytes",
                value: limits.maximumMetadataUTF8Bytes
            )
        }
        guard limits.maximumPersistedBytes > 0 else {
            throw HelpBookWorkflowError.invalidLimit(
                name: "maximumPersistedBytes",
                value: limits.maximumPersistedBytes
            )
        }
        guard limits.maximumWorkUnits > 0 else {
            throw HelpBookWorkflowError.invalidLimit(
                name: "maximumWorkUnits",
                value: limits.maximumWorkUnits
            )
        }
        guard limits.cancellationCheckInterval > 0, limits.cancellationCheckInterval <= 4_096 else {
            throw HelpBookWorkflowError.invalidLimit(
                name: "cancellationCheckInterval",
                value: limits.cancellationCheckInterval
            )
        }
    }

    private static func validateSearchLimits(_ limits: HelpCatalog.SearchLimits) throws {
        guard limits.maximumResults >= 0, limits.maximumWorkUnits > 0 else {
            throw HelpBookWorkflowError.invalidLimit(
                name: "searchLimits",
                value: limits.maximumResults
            )
        }
    }

    private static func consumeUTF8(_ value: String, total: inout Int, maximum: Int) throws {
        var count = 0
        for (index, _) in value.utf8.enumerated() {
            if index % 4_096 == 0 { try Task.checkCancellation() }
            guard count < maximum, total < maximum - count else {
                throw HelpBookWorkflowError.metadataTooLarge(maximumUTF8Bytes: maximum)
            }
            count += 1
        }
        let (next, overflow) = total.addingReportingOverflow(count)
        guard !overflow, next <= maximum else {
            throw HelpBookWorkflowError.metadataTooLarge(maximumUTF8Bytes: maximum)
        }
        total = next
    }
}

private struct HelpBookWorkflowBudget: Sendable {
    let maximum: Int
    private(set) var consumed: Int = 0

    mutating func consume(_ units: Int = 1) throws {
        guard units >= 0 else { throw HelpBookWorkflowError.arithmeticOverflow }
        let (next, overflow) = consumed.addingReportingOverflow(units)
        guard !overflow, next <= maximum else {
            throw HelpBookWorkflowError.workLimitExceeded(maximumWorkUnits: maximum)
        }
        consumed = next
    }
}
