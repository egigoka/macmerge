import Foundation

public enum BackupTrigger: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case beforeSave
    case beforeFileOperation
}

public enum BackupDestinationStrategy: Equatable, Hashable, Sendable {
    /// Every strategy resolves an existing authorized directory. Directory creation is executor
    /// setup outside a backup plan; planners never create it implicitly.
    case alongsideSource
    case sourceParentSubdirectory(String)
    case customDirectory(URL)
}

public enum BackupNameStyle: String, Codable, Equatable, Hashable, Sendable {
    case suffixOnly
    case suffixAndTimestamp
}

public struct BackupNamingPolicy: Equatable, Hashable, Sendable {
    public let style: BackupNameStyle
    public let suffix: String

    public init(style: BackupNameStyle = .suffixAndTimestamp, suffix: String = ".macmerge-backup") {
        self.style = style
        self.suffix = suffix
    }
}

public enum BackupCollisionBehavior: String, Codable, Equatable, Hashable, Sendable {
    case fail
    case useNumberedCandidates
}

public struct BackupRetentionPolicy: Equatable, Hashable, Sendable {
    public let maximumCount: Int?
    public let maximumAgeSeconds: UInt64?

    public init(maximumCount: Int? = 20, maximumAgeSeconds: UInt64? = nil) {
        self.maximumCount = maximumCount
        self.maximumAgeSeconds = maximumAgeSeconds
    }

    public static let keepAll = BackupRetentionPolicy(maximumCount: nil, maximumAgeSeconds: nil)
}

public struct BackupMetadataRequirements: OptionSet, Codable, Equatable, Hashable, Sendable {
    public static let permissions = BackupMetadataRequirements(rawValue: 1 << 0)
    public static let ownership = BackupMetadataRequirements(rawValue: 1 << 1)
    /// Access, modification, and creation/birth timestamps. Status-change time is kernel-owned and
    /// excluded. An executor must fail when a required timestamp cannot be preserved and verified.
    public static let timestamps = BackupMetadataRequirements(rawValue: 1 << 2)
    public static let extendedAttributes = BackupMetadataRequirements(rawValue: 1 << 3)
    public static let accessControlLists = BackupMetadataRequirements(rawValue: 1 << 4)
    public static let fileFlags = BackupMetadataRequirements(rawValue: 1 << 5)
    public static let resourceForks = BackupMetadataRequirements(rawValue: 1 << 6)
    public static let all: BackupMetadataRequirements = [
        .permissions,
        .ownership,
        .timestamps,
        .extendedAttributes,
        .accessControlLists,
        .fileFlags,
        .resourceForks
    ]

    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
}

/// Determines whether observations may rely on access already granted to the process.
/// Security-scoped bookmarks and their data are deliberately outside this policy model.
public enum BackupSandboxAccessPolicy: String, Codable, Equatable, Hashable, Sendable {
    case allowDeclaredAmbientAccess
    case requireSecurityScopedAccess
}

public struct BackupPlanningLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumNameCandidates = 4_096
    public static let hardMaximumSourceItemCount = 1_000_000
    public static let hardMaximumExistingBackupCount = 100_000
    public static let hardMaximumRetentionItemCount = 1_000_000
    public static let hardMaximumPathUTF8Bytes = 16 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumEstimatedWorkUnits: UInt64 = 10_000_000
    public static let hardMaximumOutputBytes: UInt64 = 1 * 1_024 * 1_024 * 1_024 * 1_024
    public static let hardMaximumPlanStepCount = 100_000

    public static let `default`: BackupPlanningLimits = {
        try! BackupPlanningLimits()
    }()

    public let maximumNameCandidates: Int
    public let maximumSourceItemCount: Int
    public let maximumExistingBackupCount: Int
    public let maximumRetentionItemCount: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumEstimatedWorkUnits: UInt64
    public let maximumOutputBytes: UInt64
    public let maximumPlanStepCount: Int

    public init(
        maximumNameCandidates: Int = 128,
        maximumSourceItemCount: Int = 100_000,
        maximumExistingBackupCount: Int = 4_096,
        maximumRetentionItemCount: Int = 100_000,
        maximumPathUTF8Bytes: Int = 4_096,
        maximumTotalPathUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumEstimatedWorkUnits: UInt64 = 1_000_000,
        maximumOutputBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024,
        maximumPlanStepCount: Int = 4_096
    ) throws {
        try Self.require(
            maximumNameCandidates,
            name: "maximumNameCandidates",
            range: 1...Self.hardMaximumNameCandidates
        )
        try Self.require(
            maximumSourceItemCount,
            name: "maximumSourceItemCount",
            range: 1...Self.hardMaximumSourceItemCount
        )
        try Self.require(
            maximumExistingBackupCount,
            name: "maximumExistingBackupCount",
            range: 0...Self.hardMaximumExistingBackupCount
        )
        try Self.require(
            maximumRetentionItemCount,
            name: "maximumRetentionItemCount",
            range: 0...Self.hardMaximumRetentionItemCount
        )
        try Self.require(
            maximumPathUTF8Bytes,
            name: "maximumPathUTF8Bytes",
            range: 1...Self.hardMaximumPathUTF8Bytes
        )
        try Self.require(
            maximumTotalPathUTF8Bytes,
            name: "maximumTotalPathUTF8Bytes",
            range: maximumPathUTF8Bytes...Self.hardMaximumTotalPathUTF8Bytes
        )
        guard maximumEstimatedWorkUnits > 0,
            maximumEstimatedWorkUnits <= Self.hardMaximumEstimatedWorkUnits
        else {
            throw BackupPolicyError.invalidLimit(
                name: "maximumEstimatedWorkUnits",
                value: String(maximumEstimatedWorkUnits)
            )
        }
        guard maximumOutputBytes > 0, maximumOutputBytes <= Self.hardMaximumOutputBytes else {
            throw BackupPolicyError.invalidLimit(
                name: "maximumOutputBytes",
                value: String(maximumOutputBytes)
            )
        }
        try Self.require(
            maximumPlanStepCount,
            name: "maximumPlanStepCount",
            range: 1...Self.hardMaximumPlanStepCount
        )

        self.maximumNameCandidates = maximumNameCandidates
        self.maximumSourceItemCount = maximumSourceItemCount
        self.maximumExistingBackupCount = maximumExistingBackupCount
        self.maximumRetentionItemCount = maximumRetentionItemCount
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumEstimatedWorkUnits = maximumEstimatedWorkUnits
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumPlanStepCount = maximumPlanStepCount
    }

    private static func require(_ value: Int, name: String, range: ClosedRange<Int>) throws {
        guard range.contains(value) else {
            throw BackupPolicyError.invalidLimit(name: name, value: String(value))
        }
    }
}

/// Exact policy persistence format. Canonical JSON is UTF-8 without a BOM, whitespace, or trailing
/// bytes. Object keys are lexicographically ordered; integers use minimal base-10 notation; `/` and
/// non-control Unicode scalars are unescaped; JSON-required escapes and lowercase `\u00xx` escapes
/// are used for control scalars. Decoding accepts only bytes reproduced by `encodedData()`.
public enum BackupPolicyPersistenceFormat: Sendable {
    public static let mediaType = "application/vnd.macmerge.backup-policy+json"
    public static let canonicalEncodingIdentifier = "com.macmerge.backup-policy.canonical-json.v1"
}

/// UI-independent settings. Custom-directory URLs carry no access grant. Persist security-scoped
/// bookmarks separately; policy bytes are configuration, never authorization.
public struct BackupPolicy: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEncodedBytes = 64 * 1_024

    public static let `default`: BackupPolicy = {
        try! BackupPolicy()
    }()

    public let enabledTriggers: [BackupTrigger]
    public let destination: BackupDestinationStrategy
    public let naming: BackupNamingPolicy
    public let collisionBehavior: BackupCollisionBehavior
    public let retention: BackupRetentionPolicy
    public let metadataRequirements: BackupMetadataRequirements
    public let sandboxAccessPolicy: BackupSandboxAccessPolicy
    public let limits: BackupPlanningLimits

    public init(
        enabledTriggers: [BackupTrigger] = BackupTrigger.allCases,
        destination: BackupDestinationStrategy = .alongsideSource,
        naming: BackupNamingPolicy = BackupNamingPolicy(),
        collisionBehavior: BackupCollisionBehavior = .useNumberedCandidates,
        retention: BackupRetentionPolicy = BackupRetentionPolicy(),
        metadataRequirements: BackupMetadataRequirements = .all,
        sandboxAccessPolicy: BackupSandboxAccessPolicy = .allowDeclaredAmbientAccess,
        limits: BackupPlanningLimits = .default
    ) throws {
        let triggers = enabledTriggers.sorted { $0.sortOrder < $1.sortOrder }
        guard Set(triggers).count == triggers.count else {
            throw BackupPolicyError.duplicateTrigger
        }
        try Self.validateDestination(destination, limits: limits)
        try Self.validateNaming(naming)
        try Self.validateRetention(retention, limits: limits)
        guard !metadataRequirements.isEmpty,
            metadataRequirements.subtracting(.all).isEmpty
        else {
            throw BackupPolicyError.invalidMetadataRequirements(metadataRequirements.rawValue)
        }

        self.enabledTriggers = triggers
        switch destination {
        case .alongsideSource, .sourceParentSubdirectory:
            self.destination = destination
        case .customDirectory(let url):
            self.destination = .customDirectory(url.standardizedFileURL)
        }
        self.naming = naming
        self.collisionBehavior = collisionBehavior
        self.retention = retention
        self.metadataRequirements = metadataRequirements
        self.sandboxAccessPolicy = sandboxAccessPolicy
        self.limits = limits
    }

    public func encodedData() throws -> Data {
        let data = BackupCanonicalPolicyEncoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw BackupPolicyError.persistenceDataTooLarge(maximumBytes: Self.maximumEncodedBytes)
        }
        return data
    }

    public static func decode(from data: Data) throws -> BackupPolicy {
        guard data.count <= maximumEncodedBytes else {
            throw BackupPolicyError.persistenceDataTooLarge(maximumBytes: maximumEncodedBytes)
        }
        try BackupPersistencePreflight.validate(data)
        let decoder = JSONDecoder()
        let schemaVersion: Int
        do {
            schemaVersion = try decoder.decode(BackupWireVersionProbe.self, from: data).schemaVersion
        } catch {
            throw BackupPolicyError.malformedPersistence
        }
        guard schemaVersion == currentSchemaVersion else {
            throw BackupPolicyError.unsupportedSchemaVersion(schemaVersion)
        }
        let policy: BackupPolicy
        do {
            policy = try decoder.decode(BackupWirePolicy.self, from: data).policy()
        } catch let error as CancellationError {
            throw error
        } catch let error as BackupPolicyError {
            throw error
        } catch {
            throw BackupPolicyError.malformedPersistence
        }
        guard try policy.encodedData() == data else {
            throw BackupPolicyError.nonCanonicalPersistence
        }
        return policy
    }

    private static func validateDestination(
        _ destination: BackupDestinationStrategy,
        limits: BackupPlanningLimits
    ) throws {
        switch destination {
        case .alongsideSource:
            break
        case .sourceParentSubdirectory(let name):
            guard BackupPlanner.isValidLeafName(name), name.utf8.count <= 255 else {
                throw BackupPolicyError.invalidDestinationComponent(name)
            }
        case .customDirectory(let url):
            guard try BackupPlanner.isValidAbsoluteFileURL(url),
                url.path.utf8.count <= limits.maximumPathUTF8Bytes
            else {
                throw BackupPolicyError.invalidFileURL(url.absoluteString)
            }
        }
    }

    private static func validateNaming(_ naming: BackupNamingPolicy) throws {
        guard !naming.suffix.isEmpty,
            naming.suffix.utf8.count <= 128,
            !naming.suffix.utf8.contains(0),
            !naming.suffix.contains("/")
        else {
            throw BackupPolicyError.invalidNamingSuffix(naming.suffix)
        }
    }

    private static func validateRetention(
        _ retention: BackupRetentionPolicy,
        limits: BackupPlanningLimits
    ) throws {
        if let maximumCount = retention.maximumCount {
            guard maximumCount > 0,
                maximumCount <= limits.maximumExistingBackupCount + 1
            else {
                throw BackupPolicyError.invalidRetentionCount(maximumCount)
            }
        }
        if let maximumAgeSeconds = retention.maximumAgeSeconds {
            guard maximumAgeSeconds > 0 else {
                throw BackupPolicyError.invalidRetentionAge(maximumAgeSeconds)
            }
        }
    }
}

public struct BackupTimestamp: Codable, Equatable, Hashable, Comparable, Sendable {
    public let secondsSince1970: Int64
    public let nanoseconds: UInt32

    public init(secondsSince1970: Int64, nanoseconds: UInt32 = 0) throws {
        guard nanoseconds < 1_000_000_000 else {
            throw BackupPolicyError.invalidTimestampNanoseconds(nanoseconds)
        }
        self.secondsSince1970 = secondsSince1970
        self.nanoseconds = nanoseconds
    }

    private enum CodingKeys: String, CodingKey, CaseIterable, Hashable {
        case secondsSince1970
        case nanoseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid backup timestamp keys.")
            )
        }
        try self.init(
            secondsSince1970: container.decode(Int64.self, forKey: .secondsSince1970),
            nanoseconds: container.decode(UInt32.self, forKey: .nanoseconds)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(secondsSince1970, forKey: .secondsSince1970)
        try container.encode(nanoseconds, forKey: .nanoseconds)
    }

    public static func < (lhs: BackupTimestamp, rhs: BackupTimestamp) -> Bool {
        if lhs.secondsSince1970 != rhs.secondsSince1970 {
            return lhs.secondsSince1970 < rhs.secondsSince1970
        }
        return lhs.nanoseconds < rhs.nanoseconds
    }
}

/// Executor monotonic-clock sample bound to one unpredictable boot/session identifier and journaled
/// to detect wall-clock rollback between publication and retention authorization.
public struct BackupMonotonicInstant: Equatable, Hashable, Sendable {
    public let clockSessionIdentifier: [UInt8]
    public let nanoseconds: UInt64

    public init(clockSessionIdentifier: [UInt8], nanoseconds: UInt64) throws {
        guard clockSessionIdentifier.count == BackupAuthenticationFormat.identifierByteCount else {
            throw BackupPolicyError.invalidObservation("Monotonic clock session identifier has an invalid size.")
        }
        self.clockSessionIdentifier = clockSessionIdentifier
        self.nanoseconds = nanoseconds
    }
}

public enum BackupItemKind: String, Codable, Equatable, Hashable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case finderAlias
    case socket
    case fifo
    case blockDevice
    case characterDevice
    case unknown

    fileprivate var isSupported: Bool {
        self == .regularFile || self == .directory
    }
}

/// Persistent filesystem volume identity. `bytes` are the filesystem's stable volume identifier
/// (for example, canonical UUID bytes), not a mount path, device number, or user-provided label.
public struct BackupPersistentVolumeIdentity: Equatable, Hashable, Sendable {
    public static let maximumByteCount = 128

    public let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard !bytes.isEmpty, bytes.count <= Self.maximumByteCount else {
            throw BackupPolicyError.invalidObservation("Persistent backup volume identity has an invalid size.")
        }
        self.bytes = bytes
    }
}

/// Filesystem-provided node generation whose non-reuse semantics are reliable on its persistent
/// volume. Executors must not construct this value from zero-filled, synthesized, truncated, or
/// otherwise unavailable generation data. A volume without reliable generations cannot issue or
/// satisfy backup capabilities.
public struct BackupReliableFileGeneration: Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(reliablyReportedValue: UInt64) {
        rawValue = reliablyReportedValue
    }
}

/// Identity captured by a read-only observer. Executors must compare every field before use.
public struct BackupItemIdentity: Equatable, Hashable, Sendable {
    public let persistentVolumeIdentity: BackupPersistentVolumeIdentity
    /// Mount-local value used to reject mount crossings during one descriptor-bound operation.
    public let device: UInt64
    public let inode: UInt64
    public let generation: BackupReliableFileGeneration
    public let kind: BackupItemKind
    public let linkCount: UInt64
    public let size: UInt64
    /// Conservative copy charge including data, resource forks, extended attributes, ACLs, and
    /// metadata representation. Observers must fail instead of supplying an incomplete charge.
    public let outputByteCharge: UInt64
    public let modificationTime: BackupTimestamp
    public let changeTime: BackupTimestamp
    /// SHA-256 over rename-invariant content. For regular files this includes every copied data
    /// stream; for directories it covers the canonical raw-UTF8 child inventory.
    public let contentDigest: BackupIntegrityDigest
    /// SHA-256 over every metadata value named by the enclosing tree's requirements. Observers must
    /// sample change time before and after hashing and reject a changed sample. Change time itself is
    /// retained above and authenticated, but excluded from this digest because rename mutates it.
    public let requiredMetadataDigest: BackupIntegrityDigest
    /// SHA-256 over required permissions, ownership, xattrs, ACLs, flags, and resource forks, but
    /// not timestamps, link count, size, or directory child state. During manifest deletion this
    /// remains exact while authenticated child removal may mutate directory timestamps/link count.
    public let deletionInvariantMetadataDigest: BackupIntegrityDigest

    public init(
        persistentVolumeIdentity: BackupPersistentVolumeIdentity,
        device: UInt64,
        inode: UInt64,
        generation: BackupReliableFileGeneration,
        kind: BackupItemKind,
        linkCount: UInt64,
        size: UInt64,
        outputByteCharge: UInt64,
        modificationTime: BackupTimestamp,
        changeTime: BackupTimestamp,
        contentDigest: BackupIntegrityDigest,
        requiredMetadataDigest: BackupIntegrityDigest,
        deletionInvariantMetadataDigest: BackupIntegrityDigest
    ) {
        self.persistentVolumeIdentity = persistentVolumeIdentity
        self.device = device
        self.inode = inode
        self.generation = generation
        self.kind = kind
        self.linkCount = linkCount
        self.size = size
        self.outputByteCharge = outputByteCharge
        self.modificationTime = modificationTime
        self.changeTime = changeTime
        self.contentDigest = contentDigest
        self.requiredMetadataDigest = requiredMetadataDigest
        self.deletionInvariantMetadataDigest = deletionInvariantMetadataDigest
    }

    public var stableNodeIdentity: BackupStableNodeIdentity {
        BackupStableNodeIdentity(
            persistentVolumeIdentity: persistentVolumeIdentity,
            inode: inode,
            generation: generation
        )
    }
}

/// Exact SHA-256 value supplied by a descriptor-bound observer. A digest is evidence only after it
/// is covered by an authenticated capability, provenance record, or transaction journal.
public struct BackupIntegrityDigest: Equatable, Hashable, Sendable {
    public static let algorithmIdentifier = "SHA-256"
    public static let byteCount = 32

    public let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw BackupPolicyError.invalidObservation("Backup integrity digest has an invalid size.")
        }
        self.bytes = bytes
    }
}

/// Capability-safe identity fields expected to remain stable across remounts and metadata changes.
public struct BackupStableNodeIdentity: Equatable, Hashable, Sendable {
    public let persistentVolumeIdentity: BackupPersistentVolumeIdentity
    public let inode: UInt64
    public let generation: BackupReliableFileGeneration

    public init(
        persistentVolumeIdentity: BackupPersistentVolumeIdentity,
        inode: UInt64,
        generation: BackupReliableFileGeneration
    ) {
        self.persistentVolumeIdentity = persistentVolumeIdentity
        self.inode = inode
        self.generation = generation
    }
}

public struct BackupRelativePath: Equatable, Hashable, Sendable {
    public static let maximumRawUTF8ByteCount = BackupPlanningLimits.hardMaximumPathUTF8Bytes
    public static let maximumComponentCount = (maximumRawUTF8ByteCount + 1) / 2

    public let rawValue: String
    public let components: [String]
    /// Prebounded canonical comparison/encoding forms. Consumers never need to re-encode untrusted
    /// path strings before applying limits.
    public let rawUTF8Bytes: [UInt8]
    public let componentUTF8Bytes: [[UInt8]]

    public init(_ rawValue: String) throws {
        let utf8 = rawValue.utf8
        guard !utf8.isEmpty, utf8.count <= Self.maximumRawUTF8ByteCount else {
            throw BackupPolicyError.invalidRelativePath(rawValue)
        }
        var componentCount = 1
        var componentByteCount = 0
        for (index, byte) in utf8.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard byte != 0 else { throw BackupPolicyError.invalidRelativePath(rawValue) }
            if byte == 0x2F {
                guard componentByteCount > 0 else {
                    throw BackupPolicyError.invalidRelativePath(rawValue)
                }
                componentCount += 1
                componentByteCount = 0
                guard componentCount <= Self.maximumComponentCount else {
                    throw BackupPolicyError.invalidRelativePath(rawValue)
                }
            } else {
                componentByteCount += 1
                guard componentByteCount <= 255 else {
                    throw BackupPolicyError.invalidRelativePath(rawValue)
                }
            }
        }
        guard componentByteCount > 0 else { throw BackupPolicyError.invalidRelativePath(rawValue) }
        try Task.checkCancellation()

        let rawUTF8Bytes = Array(utf8)
        let componentSlices = rawUTF8Bytes.split(separator: 0x2F, omittingEmptySubsequences: false)
        guard componentSlices.count == componentCount else {
            throw BackupPolicyError.invalidRelativePath(rawValue)
        }
        let componentUTF8Bytes = componentSlices.map(Array.init)
        let components = componentUTF8Bytes.compactMap { String(bytes: $0, encoding: .utf8) }
        guard components.count == componentCount,
            components.allSatisfy({ BackupPlanner.isValidLeafName($0) })
        else {
            throw BackupPolicyError.invalidRelativePath(rawValue)
        }
        self.rawValue = rawValue
        self.components = components
        self.rawUTF8Bytes = rawUTF8Bytes
        self.componentUTF8Bytes = componentUTF8Bytes
    }
}

/// One already-existing path component pinned to the identity observed without following links.
public struct BackupBoundPathComponent: Equatable, Hashable, Sendable {
    public let name: String
    public let nameUTF8Bytes: [UInt8]
    public let expectedIdentity: BackupItemIdentity

    public init(name: String, expectedIdentity: BackupItemIdentity) throws {
        let nameUTF8Bytes = Array(name.utf8)
        guard BackupPlanner.isValidLeafName(name), nameUTF8Bytes.count <= 255 else {
            throw BackupPolicyError.invalidRelativePath(name)
        }
        self.name = name
        self.nameUTF8Bytes = nameUTF8Bytes
        self.expectedIdentity = expectedIdentity
    }
}

/// Descriptor-relative path whose complete component chain was identity-bound before planning.
/// Executors open each component from its pinned parent with no-follow semantics and compare the
/// complete identity before using the resulting descriptor.
public struct BackupBoundRelativePath: Equatable, Hashable, Sendable {
    public let relativePath: BackupRelativePath
    public let components: [BackupBoundPathComponent]

    public init(
        relativePath: BackupRelativePath,
        components: [BackupBoundPathComponent]
    ) throws {
        guard !components.isEmpty,
            components.map(\.nameUTF8Bytes) == relativePath.componentUTF8Bytes
        else {
            throw BackupPolicyError.invalidRelativePath(relativePath.rawValue)
        }
        self.relativePath = relativePath
        self.components = components
    }
}

public struct BackupObservedTreeEntry: Equatable, Hashable, Sendable {
    public let relativePath: BackupRelativePath
    public let identity: BackupItemIdentity

    public init(relativePath: BackupRelativePath, identity: BackupItemIdentity) {
        self.relativePath = relativePath
        self.identity = identity
    }
}

/// Complete, descriptor-derived tree inventory. Descendants exclude the root, may contain only
/// regular files and directories, and must be strictly sorted by `relativePath.rawValue`.
/// Incomplete inventories must never be passed to the planner.
public struct BackupTreeSnapshot: Equatable, Hashable, Sendable {
    public let rootIdentity: BackupItemIdentity
    public let metadataRequirements: BackupMetadataRequirements
    public let descendants: [BackupObservedTreeEntry]

    public init(
        rootIdentity: BackupItemIdentity,
        metadataRequirements: BackupMetadataRequirements,
        descendants: [BackupObservedTreeEntry] = []
    ) {
        self.rootIdentity = rootIdentity
        self.metadataRequirements = metadataRequirements
        self.descendants = descendants
    }

    fileprivate func validateCanonicalCompleteInventory() throws {
        guard rootIdentity.kind.isSupported,
            !metadataRequirements.isEmpty,
            metadataRequirements.subtracting(.all).isEmpty,
            rootIdentity.kind != .regularFile || rootIdentity.linkCount > 0,
            rootIdentity.kind == .directory || descendants.isEmpty
        else {
            throw BackupPolicyError.invalidObservation("Backup tree inventory is incomplete or noncanonical.")
        }
        var priorPathBytes: [UInt8]?
        var kindsByComponents: [[[UInt8]]: BackupItemKind] = [:]
        var identities: [BackupStableNodeIdentity: (identity: BackupItemIdentity, count: UInt64)] = [
            rootIdentity.stableNodeIdentity: (rootIdentity, 1)
        ]
        for (index, entry) in descendants.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard entry.identity.kind.isSupported,
                entry.identity.kind != .regularFile || entry.identity.linkCount > 0,
                entry.identity.device == rootIdentity.device,
                entry.identity.persistentVolumeIdentity == rootIdentity.persistentVolumeIdentity,
                priorPathBytes.map({ $0.lexicographicallyPrecedes(entry.relativePath.rawUTF8Bytes) }) ?? true
            else {
                throw BackupPolicyError.invalidObservation("Backup tree inventory is incomplete or noncanonical.")
            }
            let stableIdentity = entry.identity.stableNodeIdentity
            if let prior = identities[stableIdentity] {
                guard entry.identity.kind == .regularFile,
                    prior.identity.kind == .regularFile,
                    prior.identity == entry.identity,
                    entry.identity.linkCount > 1,
                    prior.count < entry.identity.linkCount
                else {
                    throw BackupPolicyError.invalidObservation("Backup tree has an invalid hardlink identity.")
                }
                identities[stableIdentity] = (entry.identity, prior.count + 1)
            } else {
                identities[stableIdentity] = (entry.identity, 1)
            }
            let components = entry.relativePath.componentUTF8Bytes
            if components.count > 1,
                kindsByComponents[Array(components.dropLast())] != .directory
            {
                throw BackupPolicyError.invalidObservation("Backup tree parent is missing or not a directory.")
            }
            guard kindsByComponents.updateValue(entry.identity.kind, forKey: components) == nil else {
                throw BackupPolicyError.invalidObservation("Backup tree paths are duplicated.")
            }
            priorPathBytes = entry.relativePath.rawUTF8Bytes
        }
        for (index, alias) in identities.values.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard alias.identity.kind != .regularFile || alias.count == alias.identity.linkCount else {
                throw BackupPolicyError.invalidObservation(
                    "Backup tree regular-file link count does not match its authenticated in-tree aliases."
                )
            }
        }
        try Task.checkCancellation()
    }

    /// Provenance persists across remounts, so its authenticated tree uses stable node identity.
    /// Callers separately validate the fresh observation's mount-local device against pinned roots.
    fileprivate func matchesAuthenticatedProvenanceTree(_ authenticated: BackupTreeSnapshot) throws -> Bool {
        try validateCanonicalCompleteInventory()
        try authenticated.validateCanonicalCompleteInventory()
        guard metadataRequirements == authenticated.metadataRequirements,
            Self.matchesAuthenticatedIdentity(rootIdentity, authenticated.rootIdentity),
            descendants.count == authenticated.descendants.count
        else {
            return false
        }
        for index in descendants.indices {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let freshEntry = descendants[index]
            let authenticatedEntry = authenticated.descendants[index]
            guard freshEntry.relativePath == authenticatedEntry.relativePath,
                Self.matchesAuthenticatedIdentity(freshEntry.identity, authenticatedEntry.identity)
            else {
                return false
            }
        }
        try Task.checkCancellation()
        return true
    }

    /// Compares copied bytes, required metadata, paths, kinds, and hardlink equivalence classes while
    /// intentionally ignoring destination-specific inode identity and kernel-owned change time.
    fileprivate func hasEquivalentCopiedContent(to copy: BackupTreeSnapshot) throws -> Bool {
        guard metadataRequirements == copy.metadataRequirements,
            Self.hasEquivalentCopiedItem(rootIdentity, copy.rootIdentity),
            descendants.count == copy.descendants.count
        else {
            return false
        }
        var sourceNodes: Set<BackupStableNodeIdentity> = [rootIdentity.stableNodeIdentity]
        sourceNodes.reserveCapacity(descendants.count + 1)
        for (index, entry) in descendants.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            sourceNodes.insert(entry.identity.stableNodeIdentity)
        }
        let copyRootIdentity = copy.rootIdentity.stableNodeIdentity
        guard !sourceNodes.contains(copyRootIdentity) else { return false }
        var sourceToCopy: [BackupStableNodeIdentity: BackupStableNodeIdentity] = [
            rootIdentity.stableNodeIdentity: copyRootIdentity
        ]
        var copyToSource: [BackupStableNodeIdentity: BackupStableNodeIdentity] = [
            copyRootIdentity: rootIdentity.stableNodeIdentity
        ]
        for (index, pair) in zip(descendants, copy.descendants).enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let (sourceEntry, copyEntry) = pair
            guard sourceEntry.relativePath == copyEntry.relativePath,
                Self.hasEquivalentCopiedItem(sourceEntry.identity, copyEntry.identity)
            else {
                return false
            }
            let sourceIdentity = sourceEntry.identity.stableNodeIdentity
            let copyIdentity = copyEntry.identity.stableNodeIdentity
            guard !sourceNodes.contains(copyIdentity) else { return false }
            if let expectedCopy = sourceToCopy[sourceIdentity] {
                guard expectedCopy == copyIdentity else { return false }
            } else {
                sourceToCopy[sourceIdentity] = copyIdentity
            }
            if let expectedSource = copyToSource[copyIdentity] {
                guard expectedSource == sourceIdentity else { return false }
            } else {
                copyToSource[copyIdentity] = sourceIdentity
            }
        }
        try Task.checkCancellation()
        return true
    }

    private static func hasEquivalentCopiedItem(
        _ source: BackupItemIdentity,
        _ copy: BackupItemIdentity
    ) -> Bool {
        source.kind == copy.kind
            && source.size == copy.size
            && source.outputByteCharge == copy.outputByteCharge
            && source.modificationTime == copy.modificationTime
            && source.contentDigest == copy.contentDigest
            && source.requiredMetadataDigest == copy.requiredMetadataDigest
            && source.deletionInvariantMetadataDigest == copy.deletionInvariantMetadataDigest
    }

    private static func matchesAuthenticatedIdentity(
        _ fresh: BackupItemIdentity,
        _ authenticated: BackupItemIdentity
    ) -> Bool {
        fresh.persistentVolumeIdentity == authenticated.persistentVolumeIdentity
            && fresh.inode == authenticated.inode
            && fresh.generation == authenticated.generation
            && fresh.kind == authenticated.kind
            && fresh.linkCount == authenticated.linkCount
            && fresh.size == authenticated.size
            && fresh.outputByteCharge == authenticated.outputByteCharge
            && fresh.modificationTime == authenticated.modificationTime
            && fresh.changeTime == authenticated.changeTime
            && fresh.contentDigest == authenticated.contentDigest
            && fresh.requiredMetadataDigest == authenticated.requiredMetadataDigest
            && fresh.deletionInvariantMetadataDigest == authenticated.deletionInvariantMetadataDigest
    }

    /// Rename may change only kernel-owned root change time. Descendants and every other observed
    /// root field remain exact; added or changed descendants therefore cannot enter provenance or a
    /// deletion manifest during the rename window.
    fileprivate func matchesAfterRename(from stagedTree: BackupTreeSnapshot) throws -> Bool {
        try validateCanonicalCompleteInventory()
        try stagedTree.validateCanonicalCompleteInventory()
        let root = rootIdentity
        let stagedRoot = stagedTree.rootIdentity
        guard metadataRequirements == stagedTree.metadataRequirements,
            descendants.count == stagedTree.descendants.count
        else {
            return false
        }
        for index in descendants.indices {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard descendants[index].relativePath == stagedTree.descendants[index].relativePath,
                Self.matchesAuthenticatedIdentity(
                    descendants[index].identity,
                    stagedTree.descendants[index].identity
                )
            else {
                return false
            }
        }
        try Task.checkCancellation()
        return root.persistentVolumeIdentity == stagedRoot.persistentVolumeIdentity
            && root.inode == stagedRoot.inode
            && root.generation == stagedRoot.generation
            && root.kind == stagedRoot.kind
            && root.linkCount == stagedRoot.linkCount
            && root.size == stagedRoot.size
            && root.outputByteCharge == stagedRoot.outputByteCharge
            && root.modificationTime == stagedRoot.modificationTime
            && root.contentDigest == stagedRoot.contentDigest
            && root.requiredMetadataDigest == stagedRoot.requiredMetadataDigest
            && root.deletionInvariantMetadataDigest == stagedRoot.deletionInvariantMetadataDigest
    }
}

/// Stable cryptographic wire contract shared by source capabilities and provenance records.
public enum BackupAuthenticationFormat: Sendable {
    public static let algorithmIdentifier = "HMAC-SHA256"
    public static let keyIdentifierMaximumUTF8Bytes = 128
    public static let sourceBindingDomain = "com.macmerge.backup-source-binding.hmac-sha256.v3"
    public static let provenanceDomain = "com.macmerge.backup-provenance.hmac-sha256.v4"
    public static let transactionJournalDomain = "com.macmerge.backup-transaction-journal.hmac-sha256.v3"
    public static let identifierByteCount = 32
    public static let authenticationTagByteCount = 32
}

/// Executor-issued deletion authority bound to one source node and one destination directory.
/// `sourceBindingIdentifier` is an executor-owned, unpredictable stable identifier, not a secret.
/// Executor reuses it when renewing authority for the same source/destination binding. Authority
/// comes from the HMAC and executor key custody. Executors reject expired capabilities and those
/// whose source or destination identity no longer matches pinned descriptors.
public struct BackupSourceBinding: Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let sourceBindingIdentifier: [UInt8]
    public let seriesIdentifier: String
    public let sourceRootIdentity: BackupStableNodeIdentity
    public let destinationDirectoryIdentity: BackupStableNodeIdentity
    /// Earliest authenticated time accepted for provenance in this binding. Renewal for an existing
    /// identifier must carry forward the original value, preventing capability renewal from
    /// invalidating legitimate older backups or admitting records older than binding history.
    public let provenanceNotBefore: BackupTimestamp
    public let issuedAt: BackupTimestamp
    public let expiresAt: BackupTimestamp

    public init(
        sourceBindingIdentifier: [UInt8],
        seriesIdentifier: String,
        sourceRootIdentity: BackupStableNodeIdentity,
        destinationDirectoryIdentity: BackupStableNodeIdentity,
        provenanceNotBefore: BackupTimestamp,
        issuedAt: BackupTimestamp,
        expiresAt: BackupTimestamp
    ) throws {
        guard sourceBindingIdentifier.count == BackupAuthenticationFormat.identifierByteCount else {
            throw BackupPolicyError.invalidObservation("Backup source binding identifier has an invalid size.")
        }
        try BackupPlanner.validateSeriesIdentifier(seriesIdentifier)
        guard provenanceNotBefore <= issuedAt, issuedAt < expiresAt else {
            throw BackupPolicyError.invalidObservation("Backup source capability has an invalid validity interval.")
        }
        schemaVersion = Self.currentSchemaVersion
        self.sourceBindingIdentifier = sourceBindingIdentifier
        self.seriesIdentifier = seriesIdentifier
        self.sourceRootIdentity = sourceRootIdentity
        self.destinationDirectoryIdentity = destinationDirectoryIdentity
        self.provenanceNotBefore = provenanceNotBefore
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    /// Exact MAC input: UTF-8 domain, zero byte, then every field in declaration order as a
    /// UInt64 big-endian byte length followed by bytes. Integers are fixed-width big-endian;
    /// timestamps are Int64 bit pattern then UInt32. Stable identities are persistent-volume bytes,
    /// inode, and reliable generation. Item identities add mount-local device, kind raw-value UTF-8,
    /// link count, size, output byte charge, modification time, and change time. `keyIdentifier` is
    /// included first, preventing key-label substitution. Every nested scalar remains its own
    /// length-framed field.
    public func authenticationBytes(keyIdentifier: String) throws -> Data {
        try BackupCanonicalAuthenticationEncoder.sourceBinding(self, keyIdentifier: keyIdentifier)
    }
}

public struct BackupAuthenticatedSourceBinding: Equatable, Hashable, Sendable {
    public let binding: BackupSourceBinding
    public let keyIdentifier: String
    public let authenticationTag: [UInt8]

    public init(
        binding: BackupSourceBinding,
        keyIdentifier: String,
        authenticationTag: [UInt8]
    ) throws {
        try BackupCanonicalAuthenticationEncoder.validateKeyIdentifier(keyIdentifier)
        guard authenticationTag.count == BackupAuthenticationFormat.authenticationTagByteCount else {
            throw BackupPolicyError.invalidObservation("Backup source capability authentication tag has an invalid size.")
        }
        self.binding = binding
        self.keyIdentifier = keyIdentifier
        self.authenticationTag = authenticationTag
    }

    public func authenticationBytes() throws -> Data {
        try binding.authenticationBytes(keyIdentifier: keyIdentifier)
    }
}

public enum BackupAccessRequirement: Equatable, Hashable, Sendable {
    /// Caller has explicitly established that App Sandbox permits this access without a scope.
    case declaredAmbientAccess
    /// Executor must start and stop access on this URL for the complete operation.
    case securityScoped(resourceURL: URL)
}

public struct BackupSourceObservation: Equatable, Sendable {
    public let sourceURL: URL
    /// Required only when execution opens the source relative to its parent. Exact source scopes
    /// use the source tree root directly and need no parent-directory authority.
    public let parentDirectoryIdentity: BackupItemIdentity?
    public let tree: BackupTreeSnapshot
    public let accessRequirement: BackupAccessRequirement

    public init(
        sourceURL: URL,
        parentDirectoryIdentity: BackupItemIdentity? = nil,
        tree: BackupTreeSnapshot,
        accessRequirement: BackupAccessRequirement
    ) {
        self.sourceURL = sourceURL
        self.parentDirectoryIdentity = parentDirectoryIdentity
        self.tree = tree
        self.accessRequirement = accessRequirement
    }
}

/// One candidate probed without following links. `isOccupied` must reflect filesystem collision
/// semantics for the destination volume, not a case-sensitive string comparison.
public struct BackupNameCandidateObservation: Equatable, Hashable, Sendable {
    public let name: String
    public let isOccupied: Bool

    public init(name: String, isOccupied: Bool) {
        self.name = name
        self.isOccupied = isOccupied
    }
}

/// Complete identity inventory for a backup previously created and tracked by MacMerge.
public struct BackupExistingBackup: Equatable, Sendable {
    /// Existing target path with every component bound to an observed inode identity.
    public let boundPath: BackupBoundRelativePath
    public let provenanceRecord: BackupAuthenticatedProvenance
    public let tree: BackupTreeSnapshot

    public var seriesIdentifier: String { provenanceRecord.provenance.seriesIdentifier }
    public var name: String { provenanceRecord.provenance.name }
    public var createdAt: BackupTimestamp { provenanceRecord.provenance.createdAt }

    public init(
        boundPath: BackupBoundRelativePath,
        provenanceRecord: BackupAuthenticatedProvenance,
        tree: BackupTreeSnapshot
    ) throws {
        let provenanceTreeMatches = try tree.matchesAuthenticatedProvenanceTree(
            provenanceRecord.provenance.backupTree
        )
        guard boundPath.relativePath.components.count == 1,
            boundPath.relativePath.rawUTF8Bytes == Array(provenanceRecord.provenance.name.utf8),
            boundPath.components.last?.expectedIdentity == tree.rootIdentity,
            provenanceTreeMatches
        else {
            throw BackupPolicyError.invalidObservation("Managed backup path is not bound to its provenance and tree.")
        }
        self.boundPath = boundPath
        self.provenanceRecord = provenanceRecord
        self.tree = tree
    }
}

/// Deterministic payload requested when a backup is created. Executor adds final target identity,
/// authenticates complete provenance, and stores it durably outside copied source metadata.
public struct BackupProvenanceRequest: Equatable, Hashable, Sendable {
    public let sourceBinding: BackupAuthenticatedSourceBinding
    public let name: String
    public let sourceRootIdentity: BackupItemIdentity
    public let destinationDirectoryIdentity: BackupStableNodeIdentity

    public init(
        sourceBinding: BackupAuthenticatedSourceBinding,
        name: String,
        sourceRootIdentity: BackupItemIdentity,
        destinationDirectoryIdentity: BackupStableNodeIdentity
    ) {
        self.sourceBinding = sourceBinding
        self.name = name
        self.sourceRootIdentity = sourceRootIdentity
        self.destinationDirectoryIdentity = destinationDirectoryIdentity
    }
}

/// Durable executor-issued provenance. Authentication binds every field and the exact, complete
/// final no-follow tree inventory. An added, removed, renamed, or changed descendant therefore
/// invalidates retention authority even if the root identity remains stable. Executor issues this
/// provenance from a fresh inventory after publication rename, so expected rename-induced root
/// change-time mutation is captured rather than compared with the staged root's stale metadata.
public struct BackupProvenance: Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let transactionIdentifier: [UInt8]
    public let sourceBindingIdentifier: [UInt8]
    public let seriesIdentifier: String
    public let name: String
    public let createdAt: BackupTimestamp
    public let sourceRootIdentity: BackupItemIdentity
    public let destinationDirectoryIdentity: BackupStableNodeIdentity
    public let backupTree: BackupTreeSnapshot

    public init(
        transactionIdentifier: [UInt8],
        sourceBindingIdentifier: [UInt8],
        seriesIdentifier: String,
        name: String,
        createdAt: BackupTimestamp,
        sourceRootIdentity: BackupItemIdentity,
        destinationDirectoryIdentity: BackupStableNodeIdentity,
        backupTree: BackupTreeSnapshot
    ) throws {
        guard transactionIdentifier.count == BackupAuthenticationFormat.identifierByteCount else {
            throw BackupPolicyError.invalidObservation("Backup provenance transaction identifier has an invalid size.")
        }
        guard sourceBindingIdentifier.count == BackupAuthenticationFormat.identifierByteCount else {
            throw BackupPolicyError.invalidObservation("Backup provenance source binding identifier has an invalid size.")
        }
        try BackupPlanner.validateSeriesIdentifier(seriesIdentifier)
        guard BackupPlanner.isValidLeafName(name), name.utf8.count <= 255 else {
            throw BackupPolicyError.invalidObservation("Backup provenance has an invalid name.")
        }
        try backupTree.validateCanonicalCompleteInventory()
        schemaVersion = Self.currentSchemaVersion
        self.transactionIdentifier = transactionIdentifier
        self.sourceBindingIdentifier = sourceBindingIdentifier
        self.seriesIdentifier = seriesIdentifier
        self.name = name
        self.createdAt = createdAt
        self.sourceRootIdentity = sourceRootIdentity
        self.destinationDirectoryIdentity = destinationDirectoryIdentity
        self.backupTree = backupTree
    }

    /// Exact MAC input uses the same length-framed binary rules as `BackupSourceBinding`, with
    /// `BackupAuthenticationFormat.provenanceDomain` and every field in declaration order.
    public func authenticationBytes(keyIdentifier: String) throws -> Data {
        try BackupCanonicalAuthenticationEncoder.provenance(self, keyIdentifier: keyIdentifier)
    }
}

public struct BackupAuthenticatedProvenance: Equatable, Hashable, Sendable {
    public let provenance: BackupProvenance
    /// Identifier for executor-owned HMAC key. Key material is never stored in policy, plans,
    /// provenance, or quarantine journals.
    public let keyIdentifier: String
    /// HMAC-SHA256 over `provenance.authenticationBytes(keyIdentifier:)`.
    public let authenticationTag: [UInt8]

    public init(
        provenance: BackupProvenance,
        keyIdentifier: String,
        authenticationTag: [UInt8]
    ) throws {
        try BackupCanonicalAuthenticationEncoder.validateKeyIdentifier(keyIdentifier)
        guard authenticationTag.count == BackupAuthenticationFormat.authenticationTagByteCount else {
            throw BackupPolicyError.invalidObservation("Backup provenance authentication tag has an invalid size.")
        }
        self.provenance = provenance
        self.keyIdentifier = keyIdentifier
        self.authenticationTag = authenticationTag
    }

    public func authenticationBytes() throws -> Data {
        try provenance.authenticationBytes(keyIdentifier: keyIdentifier)
    }

    /// Streams canonical provenance MAC input for incremental authentication.
    public func writeAuthenticationBytes(_ write: @escaping (Data) throws -> Void) throws {
        try BackupCanonicalAuthenticationEncoder.writeProvenanceAuthentication(
            provenance,
            keyIdentifier: keyIdentifier,
            to: write
        )
    }
}

public struct BackupDestinationObservation: Equatable, Sendable {
    public let directoryURL: URL
    public let directoryIdentity: BackupItemIdentity
    public let accessRequirement: BackupAccessRequirement
    public let nameCandidates: [BackupNameCandidateObservation]
    /// Complete bounded inventory of every managed backup visible in this directory, strictly
    /// sorted oldest first with names as the timestamp tie-breaker.
    public let managedBackups: [BackupExistingBackup]

    public init(
        directoryURL: URL,
        directoryIdentity: BackupItemIdentity,
        accessRequirement: BackupAccessRequirement,
        nameCandidates: [BackupNameCandidateObservation],
        managedBackups: [BackupExistingBackup] = []
    ) {
        self.directoryURL = directoryURL
        self.directoryIdentity = directoryIdentity
        self.accessRequirement = accessRequirement
        self.nameCandidates = nameCandidates
        self.managedBackups = managedBackups
    }
}

public enum BackupParentMutationSemantics: String, Equatable, Hashable, Sendable {
    /// Executor continuously holds non-bypassable exclusive mutation authority for every parent
    /// directory from final validation through rename/unlink and during authenticated recovery.
    case executorHeldExclusiveAuthority
    /// Filesystem primitive atomically compares parent descriptor, leaf name, and expected node
    /// identity while renaming or unlinking. Separate validate-then-mutate calls do not conform.
    case descriptorRelativeIdentityConditional
}

/// Executor-issued handle for live parent-mutation authority. Identifier is an unpredictable handle,
/// not authority by itself; executor must reject a plan unless same live capability remains held.
/// Capability is rooted at destination identity but covers every executor-created descendant parent
/// only while executor retains its exclusive descriptors/leases. Plans and journals never make this
/// handle transferable or persistent authorization.
public struct BackupParentMutationCapability: Equatable, Hashable, Sendable {
    public let capabilityIdentifier: [UInt8]
    public let destinationDirectoryIdentity: BackupStableNodeIdentity
    public let semantics: BackupParentMutationSemantics

    public init(
        capabilityIdentifier: [UInt8],
        destinationDirectoryIdentity: BackupStableNodeIdentity,
        semantics: BackupParentMutationSemantics
    ) throws {
        guard capabilityIdentifier.count == BackupAuthenticationFormat.identifierByteCount else {
            throw BackupPolicyError.invalidObservation("Backup parent-mutation capability identifier has an invalid size.")
        }
        self.capabilityIdentifier = capabilityIdentifier
        self.destinationDirectoryIdentity = destinationDirectoryIdentity
        self.semantics = semantics
    }
}

public struct BackupPlanningRequest: Equatable, Sendable {
    public let trigger: BackupTrigger
    public let sourceBinding: BackupAuthenticatedSourceBinding
    public let timestamp: BackupTimestamp
    public let source: BackupSourceObservation
    public let destination: BackupDestinationObservation
    /// Required executor observation. Planner rejects absent or destination-mismatched capability;
    /// executor still must prove handle liveness before each parent mutation.
    public let parentMutationCapability: BackupParentMutationCapability?

    public init(
        trigger: BackupTrigger,
        sourceBinding: BackupAuthenticatedSourceBinding,
        timestamp: BackupTimestamp,
        source: BackupSourceObservation,
        destination: BackupDestinationObservation,
        parentMutationCapability: BackupParentMutationCapability? = nil
    ) {
        self.trigger = trigger
        self.sourceBinding = sourceBinding
        self.timestamp = timestamp
        self.source = source
        self.destination = destination
        self.parentMutationCapability = parentMutationCapability
    }
}

public struct BackupDescriptorRoot: Equatable, Sendable {
    public let url: URL
    public let expectedIdentity: BackupItemIdentity
    public let accessRequirement: BackupAccessRequirement

    public init(
        url: URL,
        expectedIdentity: BackupItemIdentity,
        accessRequirement: BackupAccessRequirement
    ) {
        self.url = url
        self.expectedIdentity = expectedIdentity
        self.accessRequirement = accessRequirement
    }
}

public enum BackupDescriptorPath: Equatable, Hashable, Sendable {
    case root
    /// A destination leaf proven absent immediately before exclusive creation.
    case newLeaf(BackupRelativePath)
    /// An existing path whose complete descriptor walk is pre-bound to observed identities.
    case boundExisting(BackupBoundRelativePath)
}

public struct BackupDescriptorLocation: Equatable, Sendable {
    public let root: BackupDescriptorRoot
    public let path: BackupDescriptorPath

    public init(root: BackupDescriptorRoot, path: BackupDescriptorPath) {
        self.root = root
        self.path = path
    }
}

public struct BackupCopyInstruction: Equatable, Sendable {
    public let source: BackupDescriptorLocation
    public let destination: BackupDescriptorLocation
    public let expectedSourceTree: BackupTreeSnapshot
    public let metadataRequirements: BackupMetadataRequirements
    public let expectedOutputBytes: UInt64
    public let provenanceRequest: BackupProvenanceRequest

    public init(
        source: BackupDescriptorLocation,
        destination: BackupDescriptorLocation,
        expectedSourceTree: BackupTreeSnapshot,
        metadataRequirements: BackupMetadataRequirements,
        expectedOutputBytes: UInt64,
        provenanceRequest: BackupProvenanceRequest
    ) {
        self.source = source
        self.destination = destination
        self.expectedSourceTree = expectedSourceTree
        self.metadataRequirements = metadataRequirements
        self.expectedOutputBytes = expectedOutputBytes
        self.provenanceRequest = provenanceRequest
    }
}

public struct BackupRemovalInstruction: Equatable, Sendable {
    public let target: BackupDescriptorLocation
    public let expectedTree: BackupTreeSnapshot
    public let expectedProvenance: BackupAuthenticatedProvenance
    public let sourceBinding: BackupAuthenticatedSourceBinding

    public init(
        target: BackupDescriptorLocation,
        expectedTree: BackupTreeSnapshot,
        expectedProvenance: BackupAuthenticatedProvenance,
        sourceBinding: BackupAuthenticatedSourceBinding
    ) throws {
        let binding = sourceBinding.binding
        let provenance = expectedProvenance.provenance
        let provenanceTreeMatches = try expectedTree.matchesAuthenticatedProvenanceTree(
            provenance.backupTree
        )
        guard target.root.expectedIdentity.stableNodeIdentity == binding.destinationDirectoryIdentity,
            provenance.sourceBindingIdentifier == binding.sourceBindingIdentifier,
            provenance.seriesIdentifier == binding.seriesIdentifier,
            provenance.sourceRootIdentity.stableNodeIdentity == binding.sourceRootIdentity,
            provenance.destinationDirectoryIdentity == binding.destinationDirectoryIdentity,
            binding.provenanceNotBefore <= provenance.createdAt,
            provenance.createdAt < binding.expiresAt,
            provenanceTreeMatches
        else {
            throw BackupPolicyError.invalidObservation(
                "Removal target provenance does not match its capability, series, identities, tree, or time."
            )
        }
        self.target = target
        self.expectedTree = expectedTree
        self.expectedProvenance = expectedProvenance
        self.sourceBinding = sourceBinding
    }
}

public enum BackupExecutionStep: Equatable, Sendable {
    case createBackup(BackupCopyInstruction)
    case removeRetainedBackup(BackupRemovalInstruction)
}

/// Complete planner input for retention. Executor authenticates `sourceBinding` before treating its
/// series as deletion authority, authenticates every provenance record, obtains its own wall-clock
/// sample, and recomputes removals. `plannedRemovalNames` is an untrusted consistency preview: exact
/// equality with executor recomputation is required, but the preview never authorizes deletion.
/// Caller-provided series text or time therefore cannot independently authorize cleanup.
public struct BackupRetentionValidation: Equatable, Sendable {
    public let sourceBinding: BackupAuthenticatedSourceBinding
    public let existingBackups: [BackupExistingBackup]
    public let retentionPolicy: BackupRetentionPolicy
    public let plannedRemovalNames: [String]

    public init(
        sourceBinding: BackupAuthenticatedSourceBinding,
        existingBackups: [BackupExistingBackup],
        retentionPolicy: BackupRetentionPolicy,
        plannedRemovalNames: [String]
    ) {
        self.sourceBinding = sourceBinding
        self.existingBackups = existingBackups
        self.retentionPolicy = retentionPolicy
        self.plannedRemovalNames = plannedRemovalNames
    }
}

public enum BackupPathResolutionContract: String, Equatable, Hashable, Sendable {
    case descriptorRelativeNoFollow
}

public enum BackupParentMutationContract: String, Equatable, Hashable, Sendable {
    case liveExclusiveCapabilityOrDescriptorRelativeIdentityConditionalMutation
}

public enum BackupPublicationContract: String, Equatable, Hashable, Sendable {
    case stagedAndSyncedThenExclusiveDurablePublish
}

public enum BackupSourceValidationContract: String, Equatable, Hashable, Sendable {
    case completeTreeIdentityBeforeAndAfterCopy
}

public enum BackupMetadataContract: String, Equatable, Hashable, Sendable {
    case preserveAndVerifyEveryRequirement
}

public enum BackupRetentionContract: String, Equatable, Hashable, Sendable {
    case authenticatedCapabilityQuarantineAndRevalidate
}

public enum BackupCancellationContract: String, Equatable, Hashable, Sendable {
    case reportDurableOrUncertainOutcomeAfterRename
}

public struct BackupTrustedTimeContract: Equatable, Hashable, Sendable {
    /// Limits caller timestamp influence on naming and planner previews. Executor samples its own
    /// wall and monotonic clocks before publication and retention authorization. Monotonic samples must
    /// advance; wall time must not move backward and must remain within bounded request skew. This does
    /// not claim resistance to a compromised host clock.
    public static let maximumRequestSkewSeconds: UInt64 = 300

    public let maximumRequestSkewSeconds = Self.maximumRequestSkewSeconds

    /// After durable publication intent, executor samples wall and monotonic time, validates skew,
    /// and durably replaces the journal with `publicationAuthorized` before rename. It then
    /// reauthenticates source capability, persistent-volume identities, reliable generations,
    /// destination descriptor, selected-name absence, and complete source tree. No filesystem
    /// observation or mutation may intervene before exclusive rename. Provenance `createdAt` uses
    /// persisted authorization time. Executor samples again
    /// immediately before retention authorization. Retention age and capability validity use the
    /// second sample; backward movement or excessive request skew aborts cleanup without undoing an
    /// already-published backup. Authenticated provenance later than the retention sample plus this
    /// skew also aborts cleanup.
    public let provenanceTimeSource = "executor-wall-clock-at-publication"
    public let retentionTimeSource = "executor-wall-clock-before-retention"
    public let monotonicRequirement = "strictly-nondecreasing-same-session-monotonic-clock"

    public init() {}
}

public enum BackupTransactionPhase: String, CaseIterable, Equatable, Hashable, Sendable {
    case acquireDestinationLock
    case compareRollbackResistantSequenceAnchor
    case authenticateJournalAndPlanRecovery
    case reserveTwoJournalRecords
    case recoverAuthenticatedJournal
    case recordStagedDeletionManifest
    case recordStagedDeletionEntryIntent
    case deleteStagedManifestEntry
    case recordStagedDeletionProgress
    case writePreparedJournal
    case createStagingRootExclusively
    case recordStagingIdentity
    case recordStagedConstructionEntryIntent
    case constructStagedEntry
    case recordStagedConstructionProgress
    /// Repeats after every durable authorizing journal replacement and before its filesystem mutation.
    case bindLatestJournalSequenceAndTagBeforeAuthorizedMutation
    case stageBackup
    case syncStagedBackup
    case revalidateSourceTree
    case recordPublicationIntent
    case persistPublicationAuthorization
    case reauthorizeImmediatelyBeforePublication
    case publishBackupExclusively
    case inventoryPublishedTreeAndIssueProvenance
    case recordPublishedJournal
    case syncPublishedBackup
    case syncDestinationDirectory
    case confirmDurablePublication
    case authenticateAndRecomputeRetention
    case revalidateOriginalRetentionTargets
    case recordQuarantineIntent
    case quarantineRetentionTargets
    case syncQuarantineAndParent
    case recordQuarantinedJournal
    case revalidateQuarantinedTargets
    case recordDeletionIntent
    case deleteQuarantinedTargets
    case syncQuarantineDeletion
    case recordCleanupComplete
    case recordCommittedJournal
    case advanceRollbackResistantSequenceAnchor
    case retainCommittedJournalAsRolloverPredecessor
    case replaceCommittedWithNextPreparedTransaction
    case releaseDestinationLock
}

public enum BackupTransactionJournalRecordKind: String, Equatable, Hashable, Sendable {
    case prepared
    case stageIdentityBound
    case stageConstructionIntent
    case stageConstructionProgress
    case stageDeletionIntent
    case stageDeletionProgress
    case stageCleanupComplete
    case publicationIntent
    case publicationAuthorized
    case published
    case quarantineIntent
    case quarantined
    case deletionIntent
    case deletionProgress
    case cleanupComplete
    case committed
}

/// Canonical source-derived ownership intent for one staging descendant. Entries are ordered exactly
/// like `sourceTree.descendants`; durable prefix identities bind created destination nodes to these
/// parent/name slots before another descendant may be created.
public struct BackupStagedConstructionManifestEntry: Equatable, Hashable, Sendable {
    public let relativePath: BackupRelativePath
    public let parentRelativePath: BackupRelativePath?
    public let name: String
    public let nameUTF8Bytes: [UInt8]
    public let expectedKind: BackupItemKind
    public let sourceNodeIdentity: BackupStableNodeIdentity

    public init(
        relativePath: BackupRelativePath,
        parentRelativePath: BackupRelativePath?,
        name: String,
        expectedKind: BackupItemKind,
        sourceNodeIdentity: BackupStableNodeIdentity
    ) throws {
        let nameUTF8Bytes = Array(name.utf8)
        let expectedParentComponents = Array(relativePath.componentUTF8Bytes.dropLast())
        guard BackupPlanner.isValidLeafName(name),
            nameUTF8Bytes.count <= 255,
            relativePath.componentUTF8Bytes.last == nameUTF8Bytes,
            (parentRelativePath?.componentUTF8Bytes ?? []) == expectedParentComponents,
            expectedKind.isSupported
        else {
            throw BackupPolicyError.invalidObservation("Backup staged-construction manifest entry is invalid.")
        }
        self.relativePath = relativePath
        self.parentRelativePath = parentRelativePath
        self.name = name
        self.nameUTF8Bytes = nameUTF8Bytes
        self.expectedKind = expectedKind
        self.sourceNodeIdentity = sourceNodeIdentity
    }
}

public enum BackupStagedConstructionManifest: Sendable {
    public static func entries(
        for sourceTree: BackupTreeSnapshot
    ) throws -> [BackupStagedConstructionManifestEntry] {
        try sourceTree.validateCanonicalCompleteInventory()
        var result: [BackupStagedConstructionManifestEntry] = []
        result.reserveCapacity(sourceTree.descendants.count)
        for (index, entry) in sourceTree.descendants.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            result.append(
                try BackupStagedConstructionManifestEntry(
                    relativePath: entry.relativePath,
                    parentRelativePath: entry.relativePath.components.count > 1
                        ? BackupRelativePath(entry.relativePath.components.dropLast().joined(separator: "/"))
                        : nil,
                    name: entry.relativePath.components.last!,
                    expectedKind: entry.identity.kind,
                    sourceNodeIdentity: entry.identity.stableNodeIdentity
                )
            )
        }
        try Task.checkCancellation()
        return result
    }
}

public enum BackupStagingRootIntentRecoveryDisposition: Equatable, Hashable, Sendable {
    case createMissingRoot
    case bindObservedRootIdentity(BackupStableNodeIdentity)
    case reject
}

public enum BackupStagedConstructionEntryReplayDisposition: Equatable, Hashable, Sendable {
    case createMissingInFlightEntry
    case createMissingInFlightHardlink(BackupStableNodeIdentity)
    case bindObservedInFlightEntryIdentity(BackupStableNodeIdentity)
    case reject
}

public enum BackupStagingRecoveryRemovalScope: Equatable, Hashable, Sendable {
    case reject
    /// Root-only state permits an identity-matched root unlink only after descriptor enumeration
    /// proves it empty. It never authorizes traversal or descendant removal.
    case emptyRootOnlyRequiresWriteAheadManifest
    /// Authenticated construction slots and exact durable stable identities cover the complete
    /// observed partial tree. Executor must first journal a fresh full deletion manifest.
    case constructionProgressRequiresWriteAheadManifest
    /// Complete staged-tree identities are authenticated. Executor must durably replace state with
    /// exact `.stageDeletionIntent` manifest before first postorder unlink.
    case completeTreeRequiresWriteAheadManifest
    /// Some authenticated entries are already gone. Only exact in-flight entry replay and monotonic
    /// durable progress may continue; complete-tree comparison is no longer possible.
    case authenticatedManifestProgress
}

public enum BackupStagingRecoveryAuthorization: Sendable {
    public static func removalScope(
        recordKind: BackupTransactionJournalRecordKind,
        durableStagingRootIdentity: BackupStableNodeIdentity?,
        durableStagedTree: BackupTreeSnapshot?,
        durableDeletionManifest: [BackupJournalDeletionManifestEntry] = [],
        durableDeletedManifestEntryCount: UInt64 = 0,
        durableDeletionInFlightManifestEntryIndex: UInt64? = nil,
        observedStagingTree: BackupTreeSnapshot
    ) throws -> BackupStagingRecoveryRemovalScope {
        try observedStagingTree.validateCanonicalCompleteInventory()
        guard durableStagingRootIdentity == observedStagingTree.rootIdentity.stableNodeIdentity else {
            return .reject
        }
        switch recordKind {
        case .stageIdentityBound:
            guard durableStagedTree == nil,
                observedStagingTree.rootIdentity.kind.isSupported,
                observedStagingTree.descendants.isEmpty
            else {
                return .reject
            }
            return .emptyRootOnlyRequiresWriteAheadManifest
        case .stageConstructionIntent, .stageConstructionProgress:
            // Construction records need manifest-specific recovery validation on full record.
            return .reject
        case .publicationIntent, .publicationAuthorized:
            guard let durableStagedTree,
                try observedStagingTree.matchesAuthenticatedProvenanceTree(durableStagedTree)
            else {
                return .reject
            }
            return .completeTreeRequiresWriteAheadManifest
        case .stageDeletionIntent, .stageDeletionProgress:
            guard let durableStagedTree,
                try BackupDeletionManifestRecovery.matchesAuthenticatedRemainingTree(
                    originalTree: durableStagedTree,
                    manifest: durableDeletionManifest,
                    deletedManifestEntryCount: durableDeletedManifestEntryCount,
                    inFlightManifestEntryIndex: durableDeletionInFlightManifestEntryIndex,
                    observedRemainingTree: observedStagingTree
                )
            else {
                return .reject
            }
            return .authenticatedManifestProgress
        case .prepared, .stageCleanupComplete, .published, .quarantineIntent, .quarantined,
            .deletionIntent, .deletionProgress, .cleanupComplete, .committed:
            return .reject
        }
    }
}

/// One exact postorder deletion entry. `relativePath == nil` denotes the backup root and must be
/// last. Children are recursively ordered by UTF-8 relative path before their parent. Journal
/// progress is the count of this immutable manifest's deleted prefix; no path may be skipped. For a
/// hardlink alias after its first unlink, executor accepts only authenticated link-count decrement
/// and resulting kernel-owned change-time mutation; stable identity, content digest, required
/// metadata digest, and every other identity field remain bound.
public struct BackupJournalDeletionManifestEntry: Equatable, Hashable, Sendable {
    public let relativePath: BackupRelativePath?
    /// `nil` names the authenticated staging/quarantine container. Otherwise this is target-relative
    /// path of direct parent. `name` is exact raw-UTF8 leaf passed to descriptor-relative mutation.
    public let parentRelativePath: BackupRelativePath?
    public let name: String
    public let nameUTF8Bytes: [UInt8]
    public let expectedParentIdentity: BackupStableNodeIdentity
    public let expectedIdentity: BackupItemIdentity
    /// Link count expected immediately before unlinking this path. Earlier manifest entries sharing
    /// stable identity account for each authenticated decrement; other fields remain provenance-bound.
    public let expectedLinkCountBeforeDeletion: UInt64
    /// Direct child count required immediately before deleting a directory. Postorder manifests
    /// require zero; executor enumerates the descriptor and rejects any remaining/unmanifested node.
    public let expectedDirectChildCountBeforeDeletion: UInt64?

    public init(
        relativePath: BackupRelativePath?,
        parentRelativePath: BackupRelativePath?,
        name: String,
        expectedParentIdentity: BackupStableNodeIdentity,
        expectedIdentity: BackupItemIdentity,
        expectedLinkCountBeforeDeletion: UInt64,
        expectedDirectChildCountBeforeDeletion: UInt64?
    ) throws {
        let nameUTF8Bytes = Array(name.utf8)
        guard BackupPlanner.isValidLeafName(name), nameUTF8Bytes.count <= 255,
            relativePath?.componentUTF8Bytes.last == nameUTF8Bytes || relativePath == nil,
            relativePath.map({ path in
                let expectedParentComponents = Array(path.componentUTF8Bytes.dropLast())
                return (parentRelativePath?.componentUTF8Bytes ?? []) == expectedParentComponents
            }) ?? (parentRelativePath == nil)
        else {
            throw BackupPolicyError.invalidObservation("Backup deletion manifest has an invalid parent/name binding.")
        }
        self.relativePath = relativePath
        self.parentRelativePath = parentRelativePath
        self.name = name
        self.nameUTF8Bytes = nameUTF8Bytes
        self.expectedParentIdentity = expectedParentIdentity
        self.expectedIdentity = expectedIdentity
        self.expectedLinkCountBeforeDeletion = expectedLinkCountBeforeDeletion
        self.expectedDirectChildCountBeforeDeletion = expectedDirectChildCountBeforeDeletion
    }

    /// Caller supplies observations obtained from exact authenticated parent descriptor and leaf name
    /// without following links. Only durable write-ahead state for this exact manifest index makes
    /// either an unlink or absent-entry replay acceptable.
    public func replayDisposition(
        manifestEntryIndex: UInt64,
        authenticatedState: BackupDeletionManifestReplayState,
        observedFreshRootDevice: UInt64,
        observedParentIdentity: BackupItemIdentity,
        observedNameUTF8Bytes: [UInt8],
        observedIdentity: BackupItemIdentity?,
        observedDirectChildCount: UInt64?
    ) -> BackupDeletionEntryReplayDisposition {
        let manifestCount = UInt64(authenticatedState.manifest.count)
        guard manifestEntryIndex == authenticatedState.deletedManifestEntryCount,
            authenticatedState.inFlightManifestEntryIndex == manifestEntryIndex,
            manifestEntryIndex < manifestCount,
            let manifestIndex = Int(exactly: manifestEntryIndex),
            authenticatedState.manifest[manifestIndex] == self,
            observedParentIdentity.stableNodeIdentity == expectedParentIdentity,
            observedParentIdentity.kind == .directory,
            observedParentIdentity.device == observedFreshRootDevice,
            observedNameUTF8Bytes == nameUTF8Bytes
        else {
            return .reject
        }
        guard let observedIdentity else {
            return observedDirectChildCount == nil ? .advanceDurableProgressForProvenAbsentInFlightEntry : .reject
        }
        guard observedIdentity.device == observedFreshRootDevice,
            matchesIdentityImmediatelyBeforeDeletion(
                observedIdentity,
                changeTimeChangedByPriorAuthenticatedHardlinkDeletion: authenticatedState
                    .changeTimeChangedRegularFileIdentities.contains(expectedIdentity.stableNodeIdentity)
            ),
            observedDirectChildCount == expectedDirectChildCountBeforeDeletion
        else {
            return .reject
        }
        return .unlinkIdentityMatchedEntry
    }

    private func matchesIdentityImmediatelyBeforeDeletion(
        _ observed: BackupItemIdentity,
        changeTimeChangedByPriorAuthenticatedHardlinkDeletion: Bool
    ) -> Bool {
        let expected = expectedIdentity
        let commonMatch =
            observed.persistentVolumeIdentity == expected.persistentVolumeIdentity
            && observed.inode == expected.inode
            && observed.generation == expected.generation
            && observed.kind == expected.kind
            && observed.linkCount == expectedLinkCountBeforeDeletion
            && observed.deletionInvariantMetadataDigest == expected.deletionInvariantMetadataDigest
        guard commonMatch else { return false }
        if observed.kind == .directory {
            return true
        }
        return observed.size == expected.size
            && observed.outputByteCharge == expected.outputByteCharge
            && observed.modificationTime == expected.modificationTime
            && (changeTimeChangedByPriorAuthenticatedHardlinkDeletion
                || observed.changeTime == expected.changeTime)
            && observed.contentDigest == expected.contentDigest
            && observed.requiredMetadataDigest == expected.requiredMetadataDigest
    }
}

/// Derived from one authenticated deletion manifest and its durable cursor. Building this state once
/// binds replay to the exact indexed entry and explicitly tracks only regular-file nodes whose change
/// time was necessarily mutated by an earlier authenticated hardlink unlink.
public struct BackupDeletionManifestReplayState: Sendable {
    public let deletedManifestEntryCount: UInt64
    public let inFlightManifestEntryIndex: UInt64?
    fileprivate let manifest: [BackupJournalDeletionManifestEntry]
    fileprivate let changeTimeChangedRegularFileIdentities: Set<BackupStableNodeIdentity>

    public init(
        authenticatedManifest: [BackupJournalDeletionManifestEntry],
        authenticatedDeletedManifestEntryCount: UInt64,
        authenticatedInFlightManifestEntryIndex: UInt64?
    ) throws {
        let manifestCount = UInt64(authenticatedManifest.count)
        guard authenticatedManifest.count <= BackupPlanningLimits.hardMaximumRetentionItemCount,
            authenticatedDeletedManifestEntryCount <= manifestCount,
            authenticatedInFlightManifestEntryIndex == nil
                || authenticatedInFlightManifestEntryIndex == authenticatedDeletedManifestEntryCount,
            authenticatedInFlightManifestEntryIndex.map({ $0 < manifestCount }) ?? true,
            let deletedCount = Int(exactly: authenticatedDeletedManifestEntryCount)
        else {
            throw BackupPolicyError.invalidObservation("Backup deletion replay state is malformed.")
        }
        var changedRegularFileIdentities: Set<BackupStableNodeIdentity> = []
        changedRegularFileIdentities.reserveCapacity(deletedCount)
        for (index, entry) in authenticatedManifest.prefix(deletedCount).enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            if entry.expectedIdentity.kind == .regularFile {
                changedRegularFileIdentities.insert(entry.expectedIdentity.stableNodeIdentity)
            }
        }
        try Task.checkCancellation()
        manifest = authenticatedManifest
        deletedManifestEntryCount = authenticatedDeletedManifestEntryCount
        inFlightManifestEntryIndex = authenticatedInFlightManifestEntryIndex
        changeTimeChangedRegularFileIdentities = changedRegularFileIdentities
    }
}

/// Stable root-only recovery state becomes deletion authority only after executor freshly proves root
/// empty and authenticates this one-entry manifest in `.stageDeletionIntent`. Name stays journaled
/// staging leaf; root stable identity alone never reaches unlink.
public enum BackupStagingDeletionManifest: Sendable {
    public static func emptyRootManifest(
        stagingName: String,
        destinationDirectoryIdentity: BackupItemIdentity,
        observedEmptyStagingRootIdentity: BackupItemIdentity
    ) throws -> [BackupJournalDeletionManifestEntry] {
        guard observedEmptyStagingRootIdentity.kind.isSupported else {
            throw BackupPolicyError.invalidObservation("Backup staging root has an unsupported kind.")
        }
        return [
            try BackupJournalDeletionManifestEntry(
                relativePath: nil,
                parentRelativePath: nil,
                name: stagingName,
                expectedParentIdentity: destinationDirectoryIdentity.stableNodeIdentity,
                expectedIdentity: observedEmptyStagingRootIdentity,
                expectedLinkCountBeforeDeletion: observedEmptyStagingRootIdentity.linkCount,
                expectedDirectChildCountBeforeDeletion: observedEmptyStagingRootIdentity.kind == .directory ? 0 : nil
            )
        ]
    }
}

public enum BackupDeletionEntryReplayDisposition: Equatable, Hashable, Sendable {
    case unlinkIdentityMatchedEntry
    /// Entry was present when exact write-ahead state became durable and may have been unlinked before
    /// crash. Executor must durably replace and anchor journal with monotonic progress before any next
    /// filesystem mutation. This result never authorizes a second unlink.
    case advanceDurableProgressForProvenAbsentInFlightEntry
    case reject
}

public enum BackupDeletionProgressAuthorization: Sendable {
    /// Exact immutable manifests plus write-ahead cursor prove one monotonic deletion step. Successor
    /// advances deleted prefix and clears in-flight state. Separate durable successor authorizes next
    /// entry, preventing one record from claiming prior completion and preauthorizing new unlink.
    public static func authorizesDurableSuccessor(
        priorManifest: [BackupJournalDeletionManifestEntry],
        priorDeletedManifestEntryCount: UInt64,
        priorInFlightManifestEntryIndex: UInt64?,
        successorManifest: [BackupJournalDeletionManifestEntry],
        successorDeletedManifestEntryCount: UInt64,
        successorInFlightManifestEntryIndex: UInt64?
    ) throws -> Bool {
        guard try BackupTransactionJournalTarget.manifestsAreExactlyEqual(priorManifest, successorManifest),
            priorDeletedManifestEntryCount < UInt64(priorManifest.count),
            priorInFlightManifestEntryIndex == priorDeletedManifestEntryCount
        else {
            return false
        }
        let successorCount = priorDeletedManifestEntryCount.addingReportingOverflow(1)
        guard !successorCount.overflow,
            successorDeletedManifestEntryCount == successorCount.partialValue
        else {
            return false
        }
        return successorInFlightManifestEntryIndex == nil
    }

    public static func authorizesNextWriteAheadEntry(
        priorManifest: [BackupJournalDeletionManifestEntry],
        priorDeletedManifestEntryCount: UInt64,
        priorInFlightManifestEntryIndex: UInt64?,
        successorManifest: [BackupJournalDeletionManifestEntry],
        successorDeletedManifestEntryCount: UInt64,
        successorInFlightManifestEntryIndex: UInt64?
    ) throws -> Bool {
        try BackupTransactionJournalTarget.manifestsAreExactlyEqual(priorManifest, successorManifest)
            && priorDeletedManifestEntryCount < UInt64(priorManifest.count)
            && priorInFlightManifestEntryIndex == nil
            && successorDeletedManifestEntryCount == priorDeletedManifestEntryCount
            && successorInFlightManifestEntryIndex == successorDeletedManifestEntryCount
    }
}

public enum BackupDeletionManifestRecovery: Sendable {
    /// Rejects any injected or changed remaining node. Exactly one absent in-flight entry may be
    /// tolerated here only so caller can prove its authenticated parent/name with `replayDisposition`;
    /// this inventory check alone never advances progress or authorizes another unlink.
    public static func matchesAuthenticatedRemainingTree(
        originalTree: BackupTreeSnapshot,
        manifest: [BackupJournalDeletionManifestEntry],
        deletedManifestEntryCount: UInt64,
        inFlightManifestEntryIndex: UInt64?,
        observedRemainingTree: BackupTreeSnapshot
    ) throws -> Bool {
        try originalTree.validateCanonicalCompleteInventory()
        try observedRemainingTree.validateCanonicalCompleteInventory()
        guard deletedManifestEntryCount <= UInt64(manifest.count),
            inFlightManifestEntryIndex == nil || inFlightManifestEntryIndex == deletedManifestEntryCount,
            inFlightManifestEntryIndex.map({ $0 < UInt64(manifest.count) }) ?? true,
            originalTree.metadataRequirements == observedRemainingTree.metadataRequirements
        else {
            return false
        }
        let deletedCount = Int(deletedManifestEntryCount)
        if try matchesAuthenticatedRemainingTree(
            originalTree: originalTree,
            manifest: manifest,
            assumedDeletedPrefixCount: deletedCount,
            observedRemainingTree: observedRemainingTree
        ) {
            return true
        }
        guard inFlightManifestEntryIndex != nil, deletedCount < manifest.count else { return false }
        return try matchesAuthenticatedRemainingTree(
            originalTree: originalTree,
            manifest: manifest,
            assumedDeletedPrefixCount: deletedCount + 1,
            observedRemainingTree: observedRemainingTree
        )
    }

    private static func matchesAuthenticatedRemainingTree(
        originalTree: BackupTreeSnapshot,
        manifest: [BackupJournalDeletionManifestEntry],
        assumedDeletedPrefixCount: Int,
        observedRemainingTree: BackupTreeSnapshot
    ) throws -> Bool {
        guard assumedDeletedPrefixCount <= manifest.count else { return false }
        var removedRegularLinks: [BackupStableNodeIdentity: UInt64] = [:]
        var removedChildDirectories: [BackupRelativePath?: UInt64] = [:]
        var changedDirectories: Set<BackupRelativePath?> = []
        for (index, entry) in manifest.prefix(assumedDeletedPrefixCount).enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            changedDirectories.insert(entry.parentRelativePath)
            if entry.expectedIdentity.kind == .regularFile {
                removedRegularLinks[entry.expectedIdentity.stableNodeIdentity, default: 0] += 1
            } else if entry.expectedIdentity.kind == .directory {
                removedChildDirectories[entry.parentRelativePath, default: 0] += 1
            }
        }
        var expectedByPath: [BackupRelativePath: BackupJournalDeletionManifestEntry] = [:]
        var expectedRoot: BackupJournalDeletionManifestEntry?
        for (index, entry) in manifest.dropFirst(assumedDeletedPrefixCount).enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            if let path = entry.relativePath {
                guard expectedByPath.updateValue(entry, forKey: path) == nil else { return false }
            } else {
                guard expectedRoot == nil else { return false }
                expectedRoot = entry
            }
        }
        guard let expectedRoot,
            expectedByPath.count == observedRemainingTree.descendants.count,
            matchesRemainingIdentity(
                observedRemainingTree.rootIdentity,
                expected: expectedRoot.expectedIdentity,
                observedFreshRootDevice: observedRemainingTree.rootIdentity.device,
                removedRegularLinks: removedRegularLinks,
                removedChildDirectoryCount: removedChildDirectories[nil, default: 0],
                changedByAuthenticatedDeletion: changedDirectories.contains(nil)
            )
        else {
            return false
        }
        for (index, observed) in observedRemainingTree.descendants.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard let expected = expectedByPath.removeValue(forKey: observed.relativePath),
                matchesRemainingIdentity(
                    observed.identity,
                    expected: expected.expectedIdentity,
                    observedFreshRootDevice: observedRemainingTree.rootIdentity.device,
                    removedRegularLinks: removedRegularLinks,
                    removedChildDirectoryCount: removedChildDirectories[observed.relativePath, default: 0],
                    changedByAuthenticatedDeletion: changedDirectories.contains(observed.relativePath)
                )
            else {
                return false
            }
        }
        try Task.checkCancellation()
        return expectedByPath.isEmpty
    }

    private static func matchesRemainingIdentity(
        _ observed: BackupItemIdentity,
        expected: BackupItemIdentity,
        observedFreshRootDevice: UInt64,
        removedRegularLinks: [BackupStableNodeIdentity: UInt64],
        removedChildDirectoryCount: UInt64,
        changedByAuthenticatedDeletion: Bool
    ) -> Bool {
        let common =
            observed.persistentVolumeIdentity == expected.persistentVolumeIdentity
            && observed.device == observedFreshRootDevice
            && observed.inode == expected.inode
            && observed.generation == expected.generation
            && observed.kind == expected.kind
            && observed.deletionInvariantMetadataDigest == expected.deletionInvariantMetadataDigest
        guard common else { return false }
        if expected.kind == .directory {
            guard removedChildDirectoryCount <= expected.linkCount else { return false }
            let expectedLinkCount = expected.linkCount - removedChildDirectoryCount
            guard observed.linkCount == expectedLinkCount else { return false }
            if changedByAuthenticatedDeletion { return true }
            return observed.size == expected.size
                && observed.outputByteCharge == expected.outputByteCharge
                && observed.modificationTime == expected.modificationTime
                && observed.changeTime == expected.changeTime
                && observed.contentDigest == expected.contentDigest
                && observed.requiredMetadataDigest == expected.requiredMetadataDigest
        }
        let removedLinks = removedRegularLinks[expected.stableNodeIdentity, default: 0]
        guard removedLinks <= expected.linkCount else { return false }
        return observed.linkCount == expected.linkCount - removedLinks
            && observed.size == expected.size
            && observed.outputByteCharge == expected.outputByteCharge
            && observed.modificationTime == expected.modificationTime
            && (removedLinks > 0 || observed.changeTime == expected.changeTime)
            && observed.contentDigest == expected.contentDigest
            && observed.requiredMetadataDigest == expected.requiredMetadataDigest
    }
}

/// Retention target state carried in every journal replacement. Pre-rename inventory is the exact
/// authenticated provenance inventory. Once quarantined, `postRenameTree` is a complete fresh
/// no-follow inventory accounting for expected rename-induced root metadata changes.
public struct BackupTransactionJournalTarget: Equatable, Hashable, Sendable {
    public let originalPath: BackupBoundRelativePath
    public let quarantineName: String?
    /// Stable identity of executor-private quarantine container that directly owns `quarantineName`.
    /// Fresh replay separately requires every opened parent/node device to equal fresh container root.
    public let quarantineContainerIdentity: BackupStableNodeIdentity?
    public let provenance: BackupAuthenticatedProvenance
    public let preRenameTree: BackupTreeSnapshot
    public let postRenameTree: BackupTreeSnapshot?
    public let deletionManifest: [BackupJournalDeletionManifestEntry]
    public let deletedManifestEntryCount: UInt64
    /// Write-ahead index for one unlink. When present it equals `deletedManifestEntryCount`; absence
    /// after crash is accepted only under authenticated parent/name and held parent mutation authority.
    public let deletionInFlightManifestEntryIndex: UInt64?

    public init(
        originalPath: BackupBoundRelativePath,
        quarantineName: String?,
        quarantineContainerIdentity: BackupStableNodeIdentity? = nil,
        provenance: BackupAuthenticatedProvenance,
        preRenameTree: BackupTreeSnapshot,
        postRenameTree: BackupTreeSnapshot?,
        deletionManifest: [BackupJournalDeletionManifestEntry],
        deletedManifestEntryCount: UInt64,
        deletionInFlightManifestEntryIndex: UInt64? = nil
    ) throws {
        guard preRenameTree.descendants.count <= BackupPlanningLimits.hardMaximumRetentionItemCount - 1,
            postRenameTree?.descendants.count ?? 0 <= BackupPlanningLimits.hardMaximumRetentionItemCount - 1,
            deletionManifest.count <= BackupPlanningLimits.hardMaximumRetentionItemCount
        else {
            throw BackupPolicyError.invalidObservation("Backup journal target exceeds hard item limits.")
        }
        if let quarantineName {
            guard BackupPlanner.isValidLeafName(quarantineName), quarantineName.utf8.count <= 255 else {
                throw BackupPolicyError.invalidObservation("Backup journal has an invalid quarantine name.")
            }
        }
        guard (quarantineName == nil) == (quarantineContainerIdentity == nil),
            quarantineContainerIdentity?.persistentVolumeIdentity
                == provenance.provenance.destinationDirectoryIdentity.persistentVolumeIdentity
                || quarantineContainerIdentity == nil
        else {
            throw BackupPolicyError.invalidObservation("Backup journal has an invalid quarantine-container binding.")
        }
        try preRenameTree.validateCanonicalCompleteInventory()
        try postRenameTree?.validateCanonicalCompleteInventory()
        let postRenameMatches = try postRenameTree.map { try $0.matchesAfterRename(from: preRenameTree) } ?? true
        let expectedManifest: [BackupJournalDeletionManifestEntry]
        if let postRenameTree {
            guard let quarantineName else {
                throw BackupPolicyError.invalidObservation("Backup journal deletion manifest lacks quarantine name.")
            }
            expectedManifest = try Self.deletionManifest(
                for: postRenameTree,
                rootName: quarantineName,
                rootParentIdentity: quarantineContainerIdentity!
            )
        } else {
            expectedManifest = []
        }
        let provenanceTreeMatches = try preRenameTree.matchesAuthenticatedProvenanceTree(
            provenance.provenance.backupTree
        )
        let manifestMatches = try Self.manifestsAreExactlyEqual(deletionManifest, expectedManifest)
        guard originalPath.relativePath.components.count == 1,
            originalPath.relativePath.rawUTF8Bytes == Array(provenance.provenance.name.utf8),
            originalPath.components.last?.expectedIdentity == preRenameTree.rootIdentity,
            provenanceTreeMatches,
            deletedManifestEntryCount <= UInt64(deletionManifest.count),
            deletionInFlightManifestEntryIndex == nil
                || deletionInFlightManifestEntryIndex == deletedManifestEntryCount,
            deletionInFlightManifestEntryIndex.map({ $0 < UInt64(deletionManifest.count) }) ?? true,
            manifestMatches,
            postRenameTree == nil || quarantineName != nil,
            postRenameMatches
        else {
            throw BackupPolicyError.invalidObservation("Backup journal has an invalid deletion manifest or progress.")
        }
        self.originalPath = originalPath
        self.quarantineName = quarantineName
        self.quarantineContainerIdentity = quarantineContainerIdentity
        self.provenance = provenance
        self.preRenameTree = preRenameTree
        self.postRenameTree = postRenameTree
        self.deletionManifest = deletionManifest
        self.deletedManifestEntryCount = deletedManifestEntryCount
        self.deletionInFlightManifestEntryIndex = deletionInFlightManifestEntryIndex
    }

    public func matchesAuthenticatedRemainingQuarantineTree(
        _ observedRemainingTree: BackupTreeSnapshot,
        observedFreshQuarantineContainerIdentity: BackupItemIdentity
    ) throws -> Bool {
        guard let postRenameTree,
            observedFreshQuarantineContainerIdentity.kind == .directory,
            observedFreshQuarantineContainerIdentity.stableNodeIdentity == quarantineContainerIdentity,
            observedRemainingTree.rootIdentity.device == observedFreshQuarantineContainerIdentity.device,
            observedRemainingTree.rootIdentity.persistentVolumeIdentity
                == observedFreshQuarantineContainerIdentity.persistentVolumeIdentity
        else {
            return false
        }
        return try BackupDeletionManifestRecovery.matchesAuthenticatedRemainingTree(
            originalTree: postRenameTree,
            manifest: deletionManifest,
            deletedManifestEntryCount: deletedManifestEntryCount,
            inFlightManifestEntryIndex: deletionInFlightManifestEntryIndex,
            observedRemainingTree: observedRemainingTree
        )
    }

    fileprivate static func deletionManifest(
        for tree: BackupTreeSnapshot,
        rootName: String,
        rootParentIdentity: BackupStableNodeIdentity
    ) throws -> [BackupJournalDeletionManifestEntry] {
        let root = BackupDeletionManifestNode()
        root.identity = tree.rootIdentity
        for (index, entry) in tree.descendants.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            var node = root
            var parent = root
            for component in entry.relativePath.componentUTF8Bytes {
                parent = node
                if let child = node.children[component] {
                    node = child
                } else {
                    let child = BackupDeletionManifestNode()
                    child.parent = node
                    node.children[component] = child
                    node.childrenInCanonicalOrder.append(child)
                    node = child
                }
            }
            guard node.entry == nil else {
                throw BackupPolicyError.invalidObservation("Backup deletion manifest path is duplicated.")
            }
            node.entry = entry
            if entry.identity.kind == .directory { parent.directDirectoryChildCount += 1 }
        }

        var manifest: [BackupJournalDeletionManifestEntry] = []
        manifest.reserveCapacity(tree.descendants.count + 1)
        var priorHardlinkDeletions: [BackupStableNodeIdentity: UInt64] = [:]
        // Canonically sorted tree input first encounters each sibling in canonical order.
        var stack: [(BackupDeletionManifestNode, Bool)] = []
        stack.reserveCapacity(tree.descendants.count)
        for (index, child) in root.childrenInCanonicalOrder.reversed().enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            stack.append((child, false))
        }
        var visitedCount = 0
        while let (node, visited) = stack.popLast() {
            if visited {
                guard let entry = node.entry else {
                    throw BackupPolicyError.invalidObservation("Backup deletion manifest parent is missing.")
                }
                let stableIdentity = entry.identity.stableNodeIdentity
                let priorCount = priorHardlinkDeletions[stableIdentity, default: 0]
                let removedChildDirectoryCount =
                    entry.identity.kind == .directory
                    ? node.directDirectoryChildCount
                    : 0
                guard priorCount + removedChildDirectoryCount <= entry.identity.linkCount else {
                    throw BackupPolicyError.invalidObservation("Backup deletion manifest has invalid link counts.")
                }
                manifest.append(
                    try BackupJournalDeletionManifestEntry(
                        relativePath: entry.relativePath,
                        parentRelativePath: try entry.relativePath.components.count > 1
                            ? BackupRelativePath(entry.relativePath.components.dropLast().joined(separator: "/"))
                            : nil,
                        name: entry.relativePath.components.last!,
                        expectedParentIdentity: node.parent?.identity?.stableNodeIdentity
                            ?? tree.rootIdentity.stableNodeIdentity,
                        expectedIdentity: entry.identity,
                        expectedLinkCountBeforeDeletion: entry.identity.linkCount - priorCount
                            - removedChildDirectoryCount,
                        expectedDirectChildCountBeforeDeletion: entry.identity.kind == .directory ? 0 : nil
                    )
                )
                if entry.identity.kind == .regularFile {
                    priorHardlinkDeletions[stableIdentity] = priorCount + 1
                }
                continue
            }
            visitedCount += 1
            if visitedCount.isMultiple(of: 1_024) { try Task.checkCancellation() }
            stack.append((node, true))
            for (index, child) in node.childrenInCanonicalOrder.reversed().enumerated() {
                if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                stack.append((child, false))
            }
        }
        let removedRootChildDirectoryCount = root.directDirectoryChildCount
        guard removedRootChildDirectoryCount <= tree.rootIdentity.linkCount else {
            throw BackupPolicyError.invalidObservation("Backup deletion manifest root has invalid link count.")
        }
        manifest.append(
            try BackupJournalDeletionManifestEntry(
                relativePath: nil,
                parentRelativePath: nil,
                name: rootName,
                expectedParentIdentity: rootParentIdentity,
                expectedIdentity: tree.rootIdentity,
                expectedLinkCountBeforeDeletion: tree.rootIdentity.linkCount
                    - removedRootChildDirectoryCount,
                expectedDirectChildCountBeforeDeletion: tree.rootIdentity.kind == .directory ? 0 : nil
            )
        )
        return manifest
    }

    fileprivate static func manifestsAreExactlyEqual(
        _ lhs: [BackupJournalDeletionManifestEntry],
        _ rhs: [BackupJournalDeletionManifestEntry]
    ) throws -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in lhs.indices {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard lhs[index] == rhs[index] else { return false }
        }
        try Task.checkCancellation()
        return true
    }

}

private final class BackupDeletionManifestNode {
    weak var parent: BackupDeletionManifestNode?
    var entry: BackupObservedTreeEntry?
    var identity: BackupItemIdentity? {
        get { entry?.identity ?? storedIdentity }
        set { storedIdentity = newValue }
    }
    private var storedIdentity: BackupItemIdentity?
    var children: [[UInt8]: BackupDeletionManifestNode] = [:]
    var childrenInCanonicalOrder: [BackupDeletionManifestNode] = []
    var directDirectoryChildCount: UInt64 = 0
}

/// Versioned, canonical transaction state. Arrays encode an explicit UInt64 count and preserve the
/// declared order. Optional fields encode one byte (`0` absent, `1` present) before any value.
/// `plannedRemovalNames` and `retentionTargets` use executor recomputation order; each target's
/// deletion manifest uses the exact postorder defined above. Every field that authorizes publish or
/// retention is present: authenticated source capability, complete source inventory, persistent
/// destination identity, selected/staging names, metadata/output/plan constraints, request and
/// trusted times, exact two-record reservation size, final complete-tree provenance, retention
/// policy, recomputed removals, and exact progress.
public struct BackupTransactionJournalRecord: Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let recordKind: BackupTransactionJournalRecordKind
    public let transactionSequenceNumber: UInt64
    public let sequenceNumber: UInt64
    public let sequenceAnchorIdentifier: [UInt8]
    public let transactionIdentifier: [UInt8]
    public let previousRecordAuthenticationTag: [UInt8]?
    public let sourceBinding: BackupAuthenticatedSourceBinding
    public let sourceTree: BackupTreeSnapshot
    public let stagedConstructionManifest: [BackupStagedConstructionManifestEntry]
    public let stagedConstructedNodeIdentities: [BackupStableNodeIdentity]
    public let stagedConstructionInFlightManifestEntryIndex: UInt64?
    public let stagedTree: BackupTreeSnapshot?
    public let stagedDeletionManifest: [BackupJournalDeletionManifestEntry]
    public let stagedDeletedManifestEntryCount: UInt64
    public let stagedDeletionInFlightManifestEntryIndex: UInt64?
    public let destinationDirectoryIdentity: BackupItemIdentity
    public let stagingName: String
    /// Non-reusable identity of the exclusively created staging root. Mutable inode metadata is
    /// deliberately excluded so this binding survives copy progress and metadata restoration.
    public let stagingRootIdentity: BackupStableNodeIdentity?
    public let publicationName: String
    public let metadataRequirements: BackupMetadataRequirements
    public let expectedOutputBytes: UInt64
    public let planningLimits: BackupPlanningLimits
    public let journalReservationBytes: Int
    public let requestTimestamp: BackupTimestamp
    public let publicationAuthorizationTime: BackupTimestamp?
    public let publicationMonotonicTime: BackupMonotonicInstant?
    public let publishedProvenance: BackupAuthenticatedProvenance?
    public let retentionAuthorizationTime: BackupTimestamp?
    public let retentionMonotonicTime: BackupMonotonicInstant?
    public let retentionPolicy: BackupRetentionPolicy
    public let plannedRemovalNames: [String]
    public let retentionTargets: [BackupTransactionJournalTarget]
    private let sourceNodeIdentities: Set<BackupStableNodeIdentity>

    public init(
        recordKind: BackupTransactionJournalRecordKind,
        transactionSequenceNumber: UInt64,
        sequenceNumber: UInt64,
        sequenceAnchorIdentifier: [UInt8],
        transactionIdentifier: [UInt8],
        previousRecordAuthenticationTag: [UInt8]?,
        sourceBinding: BackupAuthenticatedSourceBinding,
        sourceTree: BackupTreeSnapshot,
        stagedConstructionManifest: [BackupStagedConstructionManifestEntry] = [],
        stagedConstructedNodeIdentities: [BackupStableNodeIdentity] = [],
        stagedConstructionInFlightManifestEntryIndex: UInt64? = nil,
        stagedTree: BackupTreeSnapshot?,
        stagedDeletionManifest: [BackupJournalDeletionManifestEntry] = [],
        stagedDeletedManifestEntryCount: UInt64 = 0,
        stagedDeletionInFlightManifestEntryIndex: UInt64? = nil,
        destinationDirectoryIdentity: BackupItemIdentity,
        stagingName: String,
        stagingRootIdentity: BackupStableNodeIdentity?,
        publicationName: String,
        metadataRequirements: BackupMetadataRequirements,
        expectedOutputBytes: UInt64,
        planningLimits: BackupPlanningLimits,
        journalReservationBytes: Int,
        requestTimestamp: BackupTimestamp,
        publicationAuthorizationTime: BackupTimestamp?,
        publicationMonotonicTime: BackupMonotonicInstant?,
        publishedProvenance: BackupAuthenticatedProvenance?,
        retentionAuthorizationTime: BackupTimestamp?,
        retentionMonotonicTime: BackupMonotonicInstant?,
        retentionPolicy: BackupRetentionPolicy,
        plannedRemovalNames: [String],
        retentionTargets: [BackupTransactionJournalTarget]
    ) throws {
        try Self.validateAgainstSignedLimits(
            sourceTree: sourceTree,
            stagedConstructionManifest: stagedConstructionManifest,
            stagedConstructedNodeIdentities: stagedConstructedNodeIdentities,
            stagedTree: stagedTree,
            stagedDeletionManifest: stagedDeletionManifest,
            expectedOutputBytes: expectedOutputBytes,
            retentionPolicy: retentionPolicy,
            stagingName: stagingName,
            publicationName: publicationName,
            plannedRemovalNames: plannedRemovalNames,
            retentionTargets: retentionTargets,
            limits: planningLimits
        )
        let canonicalJournalReservationBytes = try BackupJournalSizePreflight.requiredReservationBytes(
            sourceTree: sourceTree,
            publicationName: publicationName,
            sourceBinding: sourceBinding,
            destinationDirectoryIdentity: destinationDirectoryIdentity,
            retentionPolicy: retentionPolicy,
            retentionTargets: retentionTargets
        )
        try sourceTree.validateCanonicalCompleteInventory()
        try stagedTree?.validateCanonicalCompleteInventory()
        let expectedStagedConstructionManifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
        let stagedConstructionManifestMatches =
            stagedConstructionManifest == expectedStagedConstructionManifest
        let stagedConstructionCount = stagedConstructedNodeIdentities.count
        let constructionRecord =
            recordKind == .stageConstructionIntent || recordKind == .stageConstructionProgress
        var sourceNodeIdentities: Set<BackupStableNodeIdentity> = [sourceTree.rootIdentity.stableNodeIdentity]
        sourceNodeIdentities.reserveCapacity(sourceTree.descendants.count + 1)
        for (index, entry) in sourceTree.descendants.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            sourceNodeIdentities.insert(entry.identity.stableNodeIdentity)
        }
        try Task.checkCancellation()
        var stagedConstructionIdentitiesAreValid = true
        var sourceToStagedIdentity: [BackupStableNodeIdentity: BackupStableNodeIdentity] = [:]
        var stagedToSourceIdentity: [BackupStableNodeIdentity: BackupStableNodeIdentity] = [:]
        sourceToStagedIdentity.reserveCapacity(stagedConstructedNodeIdentities.count)
        stagedToSourceIdentity.reserveCapacity(stagedConstructedNodeIdentities.count)
        for (index, identity) in stagedConstructedNodeIdentities.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard index < stagedConstructionManifest.count else {
                stagedConstructionIdentitiesAreValid = false
                break
            }
            let sourceIdentity = stagedConstructionManifest[index].sourceNodeIdentity
            let priorStagedIdentity = sourceToStagedIdentity[sourceIdentity]
            let priorSourceIdentity = stagedToSourceIdentity[identity]
            stagedConstructionIdentitiesAreValid =
                stagedConstructionIdentitiesAreValid
                && identity.persistentVolumeIdentity == destinationDirectoryIdentity.persistentVolumeIdentity
                && identity != destinationDirectoryIdentity.stableNodeIdentity
                && identity != stagingRootIdentity
                && !sourceNodeIdentities.contains(identity)
                && (priorStagedIdentity == nil || priorStagedIdentity == identity)
                && (priorSourceIdentity == nil || priorSourceIdentity == sourceIdentity)
            if !stagedConstructionIdentitiesAreValid { break }
            sourceToStagedIdentity[sourceIdentity] = identity
            stagedToSourceIdentity[identity] = sourceIdentity
        }
        let expectedStagedDeletionManifest: [BackupJournalDeletionManifestEntry]
        if let stagedTree {
            expectedStagedDeletionManifest = try BackupTransactionJournalTarget.deletionManifest(
                for: stagedTree,
                rootName: stagingName,
                rootParentIdentity: destinationDirectoryIdentity.stableNodeIdentity
            )
        } else {
            expectedStagedDeletionManifest = []
        }
        let stagedDeletionManifestMatches = try BackupTransactionJournalTarget.manifestsAreExactlyEqual(
            stagedDeletionManifest,
            recordKind == .stageDeletionIntent || recordKind == .stageDeletionProgress
                || recordKind == .stageCleanupComplete
                || (recordKind == .committed && publishedProvenance == nil)
                ? expectedStagedDeletionManifest
                : []
        )
        let stagedContentMatches =
            stagedDeletionManifest.isEmpty
            ? try stagedTree.map { try sourceTree.hasEquivalentCopiedContent(to: $0) } ?? true
            : true
        let stageDeletionRecord = !stagedDeletionManifest.isEmpty
        let stagedIdentityMatches =
            stagedTree.map { $0.rootIdentity.stableNodeIdentity == stagingRootIdentity } ?? true
        let stagingIdentityAliasesSource = stagingRootIdentity.map(sourceNodeIdentities.contains) ?? false
        let publishedTreeMatches =
            try publishedProvenance.map { provenance in
                try stagedTree.map { try provenance.provenance.backupTree.matchesAfterRename(from: $0) } ?? false
            } ?? true
        var plannedRemovalNameBytes: Set<[UInt8]> = []
        plannedRemovalNameBytes.reserveCapacity(plannedRemovalNames.count)
        var quarantineNameBytes: Set<[UInt8]> = []
        quarantineNameBytes.reserveCapacity(retentionTargets.count)
        var quarantineContainerIdentity: BackupStableNodeIdentity?
        var retentionTargetsAreValid = plannedRemovalNames.count == retentionTargets.count
        if retentionTargetsAreValid {
            for index in retentionTargets.indices {
                if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                let target = retentionTargets[index]
                let provenance = target.provenance.provenance
                let nameBytes = Array(plannedRemovalNames[index].utf8)
                retentionTargetsAreValid =
                    plannedRemovalNameBytes.insert(nameBytes).inserted
                    && nameBytes == Array(provenance.name.utf8)
                    && provenance.sourceBindingIdentifier == sourceBinding.binding.sourceBindingIdentifier
                    && provenance.seriesIdentifier == sourceBinding.binding.seriesIdentifier
                    && provenance.sourceRootIdentity.stableNodeIdentity == sourceBinding.binding.sourceRootIdentity
                    && provenance.destinationDirectoryIdentity
                        == sourceBinding.binding.destinationDirectoryIdentity
                    && sourceBinding.binding.provenanceNotBefore <= provenance.createdAt
                    && provenance.createdAt < sourceBinding.binding.expiresAt
                    && provenance.createdAt <= (retentionAuthorizationTime ?? provenance.createdAt)
                if let quarantineName = target.quarantineName {
                    retentionTargetsAreValid =
                        retentionTargetsAreValid
                        && quarantineNameBytes.insert(Array(quarantineName.utf8)).inserted
                    if let targetContainerIdentity = target.quarantineContainerIdentity {
                        if let quarantineContainerIdentity {
                            retentionTargetsAreValid =
                                retentionTargetsAreValid
                                && quarantineContainerIdentity == targetContainerIdentity
                        } else {
                            quarantineContainerIdentity = targetContainerIdentity
                        }
                        retentionTargetsAreValid =
                            retentionTargetsAreValid
                            && targetContainerIdentity != destinationDirectoryIdentity.stableNodeIdentity
                            && targetContainerIdentity != stagingRootIdentity
                            && !sourceNodeIdentities.contains(targetContainerIdentity)
                    } else {
                        retentionTargetsAreValid = false
                    }
                }
                if !retentionTargetsAreValid { break }
            }
        }
        try Task.checkCancellation()
        guard journalReservationBytes == canonicalJournalReservationBytes else {
            throw BackupPolicyError.invalidObservation(
                "Backup journal reservation \(journalReservationBytes) does not match canonical two-record size \(canonicalJournalReservationBytes)."
            )
        }
        let canonicalState = try Self.hasCanonicalState(
            recordKind,
            transactionSequenceNumber: transactionSequenceNumber,
            sequenceNumber: sequenceNumber,
            previousRecordAuthenticationTag: previousRecordAuthenticationTag,
            stagingRootIdentity: stagingRootIdentity,
            stagedConstructionManifest: stagedConstructionManifest,
            stagedConstructedNodeIdentities: stagedConstructedNodeIdentities,
            stagedConstructionInFlightManifestEntryIndex: stagedConstructionInFlightManifestEntryIndex,
            stagedTree: stagedTree,
            stagedDeletionManifest: stagedDeletionManifest,
            stagedDeletedManifestEntryCount: stagedDeletedManifestEntryCount,
            stagedDeletionInFlightManifestEntryIndex: stagedDeletionInFlightManifestEntryIndex,
            publicationAuthorizationTime: publicationAuthorizationTime,
            publishedProvenance: publishedProvenance,
            retentionAuthorizationTime: retentionAuthorizationTime,
            retentionTargets: retentionTargets
        )
        guard canonicalState else {
            throw BackupPolicyError.invalidObservation(
                "Backup journal record kind has noncanonical state."
            )
        }
        guard retentionTargetsAreValid else {
            throw BackupPolicyError.invalidObservation("Backup journal retention targets are invalid.")
        }
        guard stagedDeletionManifestMatches, stagedConstructionIdentitiesAreValid else {
            throw BackupPolicyError.invalidObservation("Backup journal staged state is invalid.")
        }
        guard publishedTreeMatches, stagedContentMatches, stagedIdentityMatches else {
            throw BackupPolicyError.invalidObservation("Backup journal staged/published tree state is invalid.")
        }
        guard transactionSequenceNumber > 0,
            sequenceAnchorIdentifier.count == BackupAuthenticationFormat.identifierByteCount,
            transactionIdentifier.count == BackupAuthenticationFormat.identifierByteCount,
            previousRecordAuthenticationTag?.count == nil
                || previousRecordAuthenticationTag?.count == BackupAuthenticationFormat.authenticationTagByteCount,
            BackupPlanner.isValidLeafName(stagingName),
            BackupPlanner.isValidLeafName(publicationName),
            stagingName.utf8.count <= 255,
            publicationName.utf8.count <= 255,
            !metadataRequirements.isEmpty,
            metadataRequirements.subtracting(.all).isEmpty,
            expectedOutputBytes <= planningLimits.maximumOutputBytes
        else {
            throw BackupPolicyError.invalidObservation("Backup journal scalar fields are malformed.")
        }
        guard sourceBinding.binding.sourceRootIdentity == sourceTree.rootIdentity.stableNodeIdentity,
            sourceBinding.binding.destinationDirectoryIdentity
                == destinationDirectoryIdentity.stableNodeIdentity,
            sourceTree.metadataRequirements == metadataRequirements,
            stagedTree == nil || stagedTree?.metadataRequirements == metadataRequirements
        else {
            throw BackupPolicyError.invalidObservation("Backup journal source binding is malformed.")
        }
        guard
            constructionRecord || stagedConstructionManifest.isEmpty,
            constructionRecord || stagedConstructedNodeIdentities.isEmpty,
            constructionRecord || stagedConstructionInFlightManifestEntryIndex == nil,
            !constructionRecord || stagedConstructionManifestMatches,
            stagedConstructionCount <= stagedConstructionManifest.count,
            stagedConstructionInFlightManifestEntryIndex == nil
                || stagedConstructionInFlightManifestEntryIndex == UInt64(stagedConstructionCount),
            stagedConstructionInFlightManifestEntryIndex.map({
                $0 < UInt64(stagedConstructionManifest.count)
            }) ?? true,
            stagedTree == nil || stagingRootIdentity != nil,
            stagedDeletedManifestEntryCount <= UInt64(stagedDeletionManifest.count),
            stagedDeletionInFlightManifestEntryIndex == nil
                || stagedDeletionInFlightManifestEntryIndex == stagedDeletedManifestEntryCount,
            stagedDeletionInFlightManifestEntryIndex.map({ $0 < UInt64(stagedDeletionManifest.count) }) ?? true,
            stagingRootIdentity?.persistentVolumeIdentity
                == destinationDirectoryIdentity.persistentVolumeIdentity
                || stagingRootIdentity == nil,
            stagingRootIdentity != destinationDirectoryIdentity.stableNodeIdentity,
            !stagingIdentityAliasesSource
        else {
            throw BackupPolicyError.invalidObservation("Backup journal source or staging binding is malformed.")
        }
        guard
            publishedProvenance == nil
                || publishedProvenance?.provenance.transactionIdentifier == transactionIdentifier,
            publishedProvenance == nil
                || publishedProvenance?.provenance.sourceBindingIdentifier
                    == sourceBinding.binding.sourceBindingIdentifier,
            publishedProvenance == nil
                || publishedProvenance?.provenance.sourceRootIdentity == sourceTree.rootIdentity,
            publishedProvenance == nil
                || publishedProvenance?.provenance.destinationDirectoryIdentity
                    == destinationDirectoryIdentity.stableNodeIdentity,
            publishedProvenance == nil
                || publishedProvenance?.provenance.name.utf8.elementsEqual(publicationName.utf8) == true,
            publishedProvenance == nil
                || publishedProvenance?.provenance.seriesIdentifier
                    == sourceBinding.binding.seriesIdentifier,
            publishedProvenance == nil
                || publishedProvenance?.provenance.createdAt == publicationAuthorizationTime,
            stageDeletionRecord || stagedContentMatches
        else {
            throw BackupPolicyError.invalidObservation("Backup journal provenance binding is malformed.")
        }
        guard
            publicationAuthorizationTime.map({ time in
                sourceBinding.binding.issuedAt <= time && time < sourceBinding.binding.expiresAt
                    && Self.isWithinMaximumSkew(requestTimestamp, time)
            }) ?? true,
            (publicationAuthorizationTime == nil) == (publicationMonotonicTime == nil),
            retentionAuthorizationTime.map({ time in
                sourceBinding.binding.issuedAt <= time && time < sourceBinding.binding.expiresAt
                    && publicationAuthorizationTime.map({ $0 <= time }) ?? false
                    && Self.isWithinMaximumSkew(requestTimestamp, time)
            }) ?? true,
            (retentionAuthorizationTime == nil) == (retentionMonotonicTime == nil),
            retentionMonotonicTime.map({ time in
                publicationMonotonicTime.map({ publication in
                    publication.clockSessionIdentifier == time.clockSessionIdentifier
                        && publication.nanoseconds < time.nanoseconds
                }) ?? false
            }) ?? true,
            retentionAuthorizationTime == nil
                || Self.hasConsistentClockProgress(
                    publicationWallTime: publicationAuthorizationTime,
                    publicationMonotonicTime: publicationMonotonicTime,
                    retentionWallTime: retentionAuthorizationTime,
                    retentionMonotonicTime: retentionMonotonicTime
                )
        else {
            throw BackupPolicyError.invalidObservation("Backup journal trusted-time state is malformed.")
        }
        schemaVersion = Self.currentSchemaVersion
        self.recordKind = recordKind
        self.transactionSequenceNumber = transactionSequenceNumber
        self.sequenceNumber = sequenceNumber
        self.sequenceAnchorIdentifier = sequenceAnchorIdentifier
        self.transactionIdentifier = transactionIdentifier
        self.previousRecordAuthenticationTag = previousRecordAuthenticationTag
        self.sourceBinding = sourceBinding
        self.sourceTree = sourceTree
        self.stagedConstructionManifest = stagedConstructionManifest
        self.stagedConstructedNodeIdentities = stagedConstructedNodeIdentities
        self.stagedConstructionInFlightManifestEntryIndex = stagedConstructionInFlightManifestEntryIndex
        self.stagedTree = stagedTree
        self.stagedDeletionManifest = stagedDeletionManifest
        self.stagedDeletedManifestEntryCount = stagedDeletedManifestEntryCount
        self.stagedDeletionInFlightManifestEntryIndex = stagedDeletionInFlightManifestEntryIndex
        self.destinationDirectoryIdentity = destinationDirectoryIdentity
        self.stagingName = stagingName
        self.stagingRootIdentity = stagingRootIdentity
        self.publicationName = publicationName
        self.metadataRequirements = metadataRequirements
        self.expectedOutputBytes = expectedOutputBytes
        self.planningLimits = planningLimits
        self.journalReservationBytes = journalReservationBytes
        self.requestTimestamp = requestTimestamp
        self.publicationAuthorizationTime = publicationAuthorizationTime
        self.publicationMonotonicTime = publicationMonotonicTime
        self.publishedProvenance = publishedProvenance
        self.retentionAuthorizationTime = retentionAuthorizationTime
        self.retentionMonotonicTime = retentionMonotonicTime
        self.retentionPolicy = retentionPolicy
        self.plannedRemovalNames = plannedRemovalNames
        self.retentionTargets = retentionTargets
        self.sourceNodeIdentities = sourceNodeIdentities
    }

    public func authenticationBytes(keyIdentifier: String) throws -> Data {
        try BackupCanonicalAuthenticationEncoder.transactionJournal(self, keyIdentifier: keyIdentifier)
    }

    /// `.prepared` authenticates exclusive-name intent. Under live non-bypassable parent authority,
    /// recovery may either create an absent root or bind an observed fresh empty root before any
    /// descendant survives. Binding must become durable `.stageIdentityBound` before construction.
    public func stagingRootIntentRecoveryDisposition(
        parentMutationCapability: BackupParentMutationCapability,
        observedFreshDestinationDirectoryIdentity: BackupItemIdentity,
        observedStagingNameUTF8Bytes: [UInt8],
        observedStagingRootIdentity: BackupItemIdentity?,
        observedStagingRootDirectChildCount: UInt64?
    ) -> BackupStagingRootIntentRecoveryDisposition {
        guard recordKind == .prepared,
            parentMutationCapability.semantics == .executorHeldExclusiveAuthority,
            parentMutationCapability.destinationDirectoryIdentity == destinationDirectoryIdentity.stableNodeIdentity,
            observedFreshDestinationDirectoryIdentity.stableNodeIdentity
                == destinationDirectoryIdentity.stableNodeIdentity,
            observedFreshDestinationDirectoryIdentity.kind == .directory,
            observedStagingNameUTF8Bytes == stagingNameUTF8Bytes
        else {
            return .reject
        }
        guard let observedStagingRootIdentity else {
            return observedStagingRootDirectChildCount == nil ? .createMissingRoot : .reject
        }
        guard observedStagingRootIdentity.kind == sourceTree.rootIdentity.kind,
            observedStagingRootIdentity.persistentVolumeIdentity
                == observedFreshDestinationDirectoryIdentity.persistentVolumeIdentity,
            observedStagingRootIdentity.device == observedFreshDestinationDirectoryIdentity.device,
            observedStagingRootIdentity.stableNodeIdentity
                != observedFreshDestinationDirectoryIdentity.stableNodeIdentity,
            !sourceNodeIdentities.contains(observedStagingRootIdentity.stableNodeIdentity),
            observedStagingRootIdentity.kind != .regularFile || observedStagingRootIdentity.linkCount == 1,
            observedStagingRootIdentity.kind == .directory
                ? observedStagingRootDirectChildCount == 0
                : observedStagingRootDirectChildCount == nil && observedStagingRootIdentity.size == 0
        else {
            return .reject
        }
        return .bindObservedRootIdentity(observedStagingRootIdentity.stableNodeIdentity)
    }

    /// Replays only one authenticated in-flight construction slot. Present node is adopted under
    /// held exclusive parent authority, then exact stable identity must be durably journaled before
    /// any later slot is created. Missing slot may be created once; neither result authorizes deletion.
    public func stagedConstructionEntryReplayDisposition(
        manifestEntryIndex: UInt64,
        parentMutationCapability: BackupParentMutationCapability,
        observedFreshStagingRootIdentity: BackupItemIdentity,
        observedFreshParentIdentity: BackupItemIdentity,
        observedNameUTF8Bytes: [UInt8],
        observedIdentity: BackupItemIdentity?,
        observedDirectChildCount: UInt64? = nil
    ) -> BackupStagedConstructionEntryReplayDisposition {
        let manifestCount = UInt64(stagedConstructionManifest.count)
        guard recordKind == .stageConstructionIntent,
            parentMutationCapability.semantics == .executorHeldExclusiveAuthority,
            parentMutationCapability.destinationDirectoryIdentity == destinationDirectoryIdentity.stableNodeIdentity,
            observedFreshStagingRootIdentity.stableNodeIdentity == stagingRootIdentity,
            observedFreshStagingRootIdentity.device == observedFreshParentIdentity.device,
            stagedConstructionInFlightManifestEntryIndex == manifestEntryIndex,
            manifestEntryIndex < manifestCount,
            let manifestIndex = Int(exactly: manifestEntryIndex),
            manifestIndex == stagedConstructedNodeIdentities.count
        else {
            return .reject
        }
        let entry = stagedConstructionManifest[manifestIndex]
        let expectedParentIdentity: BackupStableNodeIdentity
        if let parentPath = entry.parentRelativePath,
            let parentIndex = stagedConstructionManifest.firstIndex(where: { $0.relativePath == parentPath }),
            parentIndex < stagedConstructedNodeIdentities.count
        {
            expectedParentIdentity = stagedConstructedNodeIdentities[parentIndex]
        } else if entry.parentRelativePath == nil, let stagingRootIdentity {
            expectedParentIdentity = stagingRootIdentity
        } else {
            return .reject
        }
        guard observedFreshParentIdentity.kind == .directory,
            observedFreshParentIdentity.stableNodeIdentity == expectedParentIdentity,
            observedNameUTF8Bytes == entry.nameUTF8Bytes
        else {
            return .reject
        }
        var priorHardlinkIdentity: BackupStableNodeIdentity?
        var priorHardlinkAliasCount: UInt64 = 0
        for index in 0..<stagedConstructedNodeIdentities.count
        where stagedConstructionManifest[index].sourceNodeIdentity == entry.sourceNodeIdentity {
            let constructedIdentity = stagedConstructedNodeIdentities[index]
            if let priorHardlinkIdentity {
                guard priorHardlinkIdentity == constructedIdentity else { return .reject }
            } else {
                priorHardlinkIdentity = constructedIdentity
            }
            let (nextAliasCount, overflow) = priorHardlinkAliasCount.addingReportingOverflow(1)
            guard !overflow else { return .reject }
            priorHardlinkAliasCount = nextAliasCount
        }
        guard let observedIdentity else {
            guard observedDirectChildCount == nil else { return .reject }
            return priorHardlinkIdentity.map(BackupStagedConstructionEntryReplayDisposition.createMissingInFlightHardlink)
                ?? .createMissingInFlightEntry
        }
        let (expectedRegularFileLinkCount, linkCountOverflow) = priorHardlinkAliasCount.addingReportingOverflow(1)
        guard observedIdentity.kind == entry.expectedKind,
            observedIdentity.device == observedFreshStagingRootIdentity.device,
            observedIdentity.persistentVolumeIdentity
                == observedFreshStagingRootIdentity.persistentVolumeIdentity,
            !linkCountOverflow,
            observedIdentity.kind != .regularFile
                || observedIdentity.linkCount == expectedRegularFileLinkCount,
            observedIdentity.kind == .directory
                ? observedDirectChildCount == 0
                : observedDirectChildCount == nil,
            !sourceNodeIdentities.contains(observedIdentity.stableNodeIdentity),
            observedIdentity.stableNodeIdentity != destinationDirectoryIdentity.stableNodeIdentity,
            observedIdentity.stableNodeIdentity != stagingRootIdentity,
            priorHardlinkIdentity == nil
                ? !stagedConstructedNodeIdentities.contains(observedIdentity.stableNodeIdentity)
                : entry.expectedKind == .regularFile
                    && observedIdentity.stableNodeIdentity == priorHardlinkIdentity
        else {
            return .reject
        }
        return .bindObservedInFlightEntryIdentity(observedIdentity.stableNodeIdentity)
    }

    /// Complete durable construction prefix owns exactly the observed partial tree. No in-flight
    /// slot may remain: recovery must bind it durably first. Fresh device equality rejects remount
    /// crossings while all journal comparisons use persistent volume/inode/generation identity.
    public func constructionRecoveryRemovalScope(
        forObservedStagingTree observedTree: BackupTreeSnapshot
    ) throws -> BackupStagingRecoveryRemovalScope {
        guard recordKind == .stageConstructionProgress,
            stagedConstructionInFlightManifestEntryIndex == nil,
            observedTree.rootIdentity.stableNodeIdentity == stagingRootIdentity,
            observedTree.descendants.count == stagedConstructedNodeIdentities.count,
            observedTree.metadataRequirements == metadataRequirements
        else {
            return .reject
        }
        try observedTree.validateCanonicalCompleteInventory()
        for index in observedTree.descendants.indices {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let observed = observedTree.descendants[index]
            let intent = stagedConstructionManifest[index]
            guard observed.relativePath == intent.relativePath,
                observed.identity.kind == intent.expectedKind,
                observed.identity.stableNodeIdentity == stagedConstructedNodeIdentities[index],
                observed.identity.device == observedTree.rootIdentity.device
            else {
                return .reject
            }
        }
        try Task.checkCancellation()
        return .constructionProgressRequiresWriteAheadManifest
    }

    /// Root-only `.stageIdentityBound` permits only empty-root removal. Recursive removal requires a
    /// complete authenticated staged tree and exact manifest; no root identity authorizes descendants.
    public func recoveryRemovalScope(
        forObservedStagingTree observedTree: BackupTreeSnapshot
    ) throws -> BackupStagingRecoveryRemovalScope {
        try BackupStagingRecoveryAuthorization.removalScope(
            recordKind: recordKind,
            durableStagingRootIdentity: stagingRootIdentity,
            durableStagedTree: stagedTree,
            durableDeletionManifest: stagedDeletionManifest,
            durableDeletedManifestEntryCount: stagedDeletedManifestEntryCount,
            durableDeletionInFlightManifestEntryIndex: stagedDeletionInFlightManifestEntryIndex,
            observedStagingTree: observedTree
        )
    }

    public func matchesAuthenticatedRemainingStagedTree(
        _ observedRemainingTree: BackupTreeSnapshot
    ) throws -> Bool {
        guard let stagedTree, !stagedDeletionManifest.isEmpty else { return false }
        return try BackupDeletionManifestRecovery.matchesAuthenticatedRemainingTree(
            originalTree: stagedTree,
            manifest: stagedDeletionManifest,
            deletedManifestEntryCount: stagedDeletedManifestEntryCount,
            inFlightManifestEntryIndex: stagedDeletionInFlightManifestEntryIndex,
            observedRemainingTree: observedRemainingTree
        )
    }

    /// Executor invokes this only after authenticating exact journal records and verifying direct
    /// sequence/tag successor relation. It enforces monotonic staged/retention deletion state across
    /// replacements; canonical shape of either record alone cannot skip, rewind, or clear progress.
    public func authorizesDeletionStateSuccessor(_ successor: BackupTransactionJournalRecord) throws -> Bool {
        let nextSequence = sequenceNumber.addingReportingOverflow(1)
        guard !nextSequence.overflow,
            sequenceAnchorIdentifier == successor.sequenceAnchorIdentifier,
            transactionSequenceNumber == successor.transactionSequenceNumber,
            successor.sequenceNumber == nextSequence.partialValue,
            transactionIdentifier == successor.transactionIdentifier,
            successor.previousRecordAuthenticationTag != nil,
            sourceBinding == successor.sourceBinding,
            sourceTree == successor.sourceTree,
            destinationDirectoryIdentity == successor.destinationDirectoryIdentity,
            stagingName.utf8.elementsEqual(successor.stagingName.utf8),
            publicationName.utf8.elementsEqual(successor.publicationName.utf8),
            previousFieldsOutsideDeletionEqual(successor)
        else {
            return false
        }
        if recordKind == .stageIdentityBound {
            guard stagedTree == nil && stagedDeletionManifest.isEmpty,
                retentionTargets == successor.retentionTargets,
                successor.recordKind == .stageDeletionIntent,
                successor.stagedDeletedManifestEntryCount == 0,
                successor.stagedDeletionInFlightManifestEntryIndex == 0,
                let successorTree = successor.stagedTree,
                successorTree.rootIdentity.kind.isSupported,
                successorTree.rootIdentity.stableNodeIdentity == stagingRootIdentity,
                successorTree.descendants.isEmpty,
                successor.stagedDeletionManifest.count == 1,
                let rootEntry = successor.stagedDeletionManifest.first,
                rootEntry.relativePath == nil,
                rootEntry.parentRelativePath == nil,
                rootEntry.nameUTF8Bytes == Array(stagingName.utf8),
                rootEntry.expectedParentIdentity == destinationDirectoryIdentity.stableNodeIdentity,
                rootEntry.expectedIdentity == successorTree.rootIdentity,
                rootEntry.expectedDirectChildCountBeforeDeletion
                    == (successorTree.rootIdentity.kind == .directory ? 0 : nil)
            else {
                return false
            }
            return true
        }
        guard stagedTree == successor.stagedTree else { return false }
        if recordKind == .publicationIntent || recordKind == .publicationAuthorized {
            guard successor.recordKind == .stageDeletionIntent,
                retentionTargets == successor.retentionTargets,
                successor.stagedDeletedManifestEntryCount == 0,
                successor.stagedDeletionInFlightManifestEntryIndex == 0,
                let stagedTree
            else {
                return false
            }
            return try BackupTransactionJournalTarget.manifestsAreExactlyEqual(
                successor.stagedDeletionManifest,
                BackupTransactionJournalTarget.deletionManifest(
                    for: stagedTree,
                    rootName: stagingName,
                    rootParentIdentity: destinationDirectoryIdentity.stableNodeIdentity
                )
            )
        }
        if recordKind == .stageDeletionIntent || recordKind == .stageDeletionProgress {
            guard retentionTargets == successor.retentionTargets else { return false }
            let advances = try BackupDeletionProgressAuthorization.authorizesDurableSuccessor(
                priorManifest: stagedDeletionManifest,
                priorDeletedManifestEntryCount: stagedDeletedManifestEntryCount,
                priorInFlightManifestEntryIndex: stagedDeletionInFlightManifestEntryIndex,
                successorManifest: successor.stagedDeletionManifest,
                successorDeletedManifestEntryCount: successor.stagedDeletedManifestEntryCount,
                successorInFlightManifestEntryIndex: successor.stagedDeletionInFlightManifestEntryIndex
            )
            let authorizesNext = try BackupDeletionProgressAuthorization.authorizesNextWriteAheadEntry(
                priorManifest: stagedDeletionManifest,
                priorDeletedManifestEntryCount: stagedDeletedManifestEntryCount,
                priorInFlightManifestEntryIndex: stagedDeletionInFlightManifestEntryIndex,
                successorManifest: successor.stagedDeletionManifest,
                successorDeletedManifestEntryCount: successor.stagedDeletedManifestEntryCount,
                successorInFlightManifestEntryIndex: successor.stagedDeletionInFlightManifestEntryIndex
            )
            if advances {
                let completed =
                    successor.stagedDeletedManifestEntryCount
                    == UInt64(successor.stagedDeletionManifest.count)
                return successor.recordKind == (completed ? .stageCleanupComplete : .stageDeletionProgress)
            }
            return authorizesNext
                && successor.recordKind
                    == (stagedDeletedManifestEntryCount == 0 ? .stageDeletionIntent : .stageDeletionProgress)
        }
        if recordKind == .stageCleanupComplete, successor.recordKind == .committed {
            return stagedDeletionManifest == successor.stagedDeletionManifest
                && stagedDeletedManifestEntryCount == successor.stagedDeletedManifestEntryCount
                && stagedDeletionInFlightManifestEntryIndex == nil
                && retentionTargets == successor.retentionTargets
        }
        guard stagedDeletionManifest == successor.stagedDeletionManifest,
            stagedDeletedManifestEntryCount == successor.stagedDeletedManifestEntryCount,
            stagedDeletionInFlightManifestEntryIndex == successor.stagedDeletionInFlightManifestEntryIndex,
            retentionTargets.count == successor.retentionTargets.count
        else {
            return false
        }
        var changedTargetIndex: Int?
        for index in retentionTargets.indices {
            let prior = retentionTargets[index]
            let next = successor.retentionTargets[index]
            if prior == next { continue }
            guard changedTargetIndex == nil,
                prior.originalPath == next.originalPath,
                prior.quarantineName == next.quarantineName,
                prior.quarantineContainerIdentity == next.quarantineContainerIdentity,
                prior.provenance == next.provenance,
                prior.preRenameTree == next.preRenameTree,
                prior.postRenameTree == next.postRenameTree
            else {
                return false
            }
            let advances = try BackupDeletionProgressAuthorization.authorizesDurableSuccessor(
                priorManifest: prior.deletionManifest,
                priorDeletedManifestEntryCount: prior.deletedManifestEntryCount,
                priorInFlightManifestEntryIndex: prior.deletionInFlightManifestEntryIndex,
                successorManifest: next.deletionManifest,
                successorDeletedManifestEntryCount: next.deletedManifestEntryCount,
                successorInFlightManifestEntryIndex: next.deletionInFlightManifestEntryIndex
            )
            let authorizesNext = try BackupDeletionProgressAuthorization.authorizesNextWriteAheadEntry(
                priorManifest: prior.deletionManifest,
                priorDeletedManifestEntryCount: prior.deletedManifestEntryCount,
                priorInFlightManifestEntryIndex: prior.deletionInFlightManifestEntryIndex,
                successorManifest: next.deletionManifest,
                successorDeletedManifestEntryCount: next.deletedManifestEntryCount,
                successorInFlightManifestEntryIndex: next.deletionInFlightManifestEntryIndex
            )
            guard advances || authorizesNext else { return false }
            if advances {
                let allComplete = successor.retentionTargets.allSatisfy {
                    $0.deletedManifestEntryCount == UInt64($0.deletionManifest.count)
                        && $0.deletionInFlightManifestEntryIndex == nil
                }
                guard successor.recordKind == (allComplete ? .cleanupComplete : .deletionProgress) else {
                    return false
                }
            } else {
                let hasProgress = successor.retentionTargets.contains { $0.deletedManifestEntryCount > 0 }
                guard successor.recordKind == (hasProgress ? .deletionProgress : .deletionIntent) else {
                    return false
                }
            }
            changedTargetIndex = index
        }
        return changedTargetIndex != nil
    }

    /// Exhaustive transaction-state edge validation. Authentication wrapper separately binds exact
    /// predecessor tag; this function validates semantic payload delta for one sequence increment.
    public func authorizesSemanticDirectSuccessor(
        _ successor: BackupTransactionJournalRecord
    ) throws -> Bool {
        let nextSequence = sequenceNumber.addingReportingOverflow(1)
        guard !nextSequence.overflow,
            successor.sequenceNumber == nextSequence.partialValue,
            successor.transactionSequenceNumber == transactionSequenceNumber,
            successor.sequenceAnchorIdentifier == sequenceAnchorIdentifier,
            successor.transactionIdentifier == transactionIdentifier,
            successor.previousRecordAuthenticationTag != nil,
            successor.sourceBinding == sourceBinding,
            successor.sourceTree == sourceTree,
            successor.destinationDirectoryIdentity == destinationDirectoryIdentity,
            successor.stagingNameUTF8Bytes == stagingNameUTF8Bytes,
            successor.publicationNameUTF8Bytes == publicationNameUTF8Bytes,
            recordKind == .prepared || successor.stagingRootIdentity == stagingRootIdentity,
            immutableTransactionFieldsEqual(successor)
        else {
            return false
        }
        switch (recordKind, successor.recordKind) {
        case (.prepared, .stageIdentityBound):
            return stagingRootIdentity == nil
                && successor.stagingRootIdentity != nil
                && successor.stagedTree == nil
                && successor.retentionTargets == retentionTargets
        case (.stageIdentityBound, .stageConstructionIntent):
            let expectedManifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
            return stagedTree == nil
                && stagedConstructionManifest.isEmpty
                && successor.stagedConstructionManifest == expectedManifest
                && successor.stagedConstructedNodeIdentities.isEmpty
                && successor.stagedConstructionInFlightManifestEntryIndex == 0
                && successor.retentionTargets == retentionTargets
        case (.stageIdentityBound, .publicationIntent):
            let completedTreeMatches = try successor.matchesCompletedStagedTree()
            return sourceTree.descendants.isEmpty
                && successor.stagedConstructionManifest.isEmpty
                && completedTreeMatches
                && successor.retentionTargets == retentionTargets
        case (.stageConstructionIntent, .stageConstructionProgress):
            guard stagedConstructionManifest == successor.stagedConstructionManifest,
                stagedConstructionInFlightManifestEntryIndex
                    == UInt64(stagedConstructedNodeIdentities.count),
                successor.stagedConstructionInFlightManifestEntryIndex == nil,
                successor.stagedConstructedNodeIdentities.count
                    == stagedConstructedNodeIdentities.count + 1,
                Array(successor.stagedConstructedNodeIdentities.dropLast())
                    == stagedConstructedNodeIdentities,
                successor.stagedTree == nil,
                successor.retentionTargets == retentionTargets
            else {
                return false
            }
            return true
        case (.stageConstructionProgress, .stageConstructionIntent):
            return stagedConstructedNodeIdentities.count < stagedConstructionManifest.count
                && successor.stagedConstructionManifest == stagedConstructionManifest
                && successor.stagedConstructedNodeIdentities == stagedConstructedNodeIdentities
                && successor.stagedConstructionInFlightManifestEntryIndex
                    == UInt64(stagedConstructedNodeIdentities.count)
                && successor.stagedTree == nil
                && successor.retentionTargets == retentionTargets
        case (.stageConstructionProgress, .publicationIntent):
            let completedTreeMatches = try successor.matchesCompletedStagedTree(
                expectedDescendantIdentities: stagedConstructedNodeIdentities
            )
            return stagedConstructionInFlightManifestEntryIndex == nil
                && stagedConstructedNodeIdentities.count == stagedConstructionManifest.count
                && successor.stagedConstructionManifest.isEmpty
                && successor.stagedConstructedNodeIdentities.isEmpty
                && successor.stagedConstructionInFlightManifestEntryIndex == nil
                && completedTreeMatches
                && successor.retentionTargets == retentionTargets
        case (.stageConstructionProgress, .stageDeletionIntent):
            let prefixTreeMatches = try successor.matchesConstructionPrefixTree(
                manifest: stagedConstructionManifest,
                constructedIdentities: stagedConstructedNodeIdentities
            )
            return stagedConstructionInFlightManifestEntryIndex == nil
                && successor.stagedConstructionManifest.isEmpty
                && successor.stagedConstructedNodeIdentities.isEmpty
                && successor.stagedConstructionInFlightManifestEntryIndex == nil
                && prefixTreeMatches
                && successor.retentionTargets == retentionTargets
        case (.stageConstructionIntent, .stageDeletionIntent):
            let prefixTreeMatches = try successor.matchesConstructionPrefixTree(
                manifest: stagedConstructionManifest,
                constructedIdentities: stagedConstructedNodeIdentities
            )
            return stagedConstructionInFlightManifestEntryIndex
                == UInt64(stagedConstructedNodeIdentities.count)
                && successor.stagedConstructionManifest.isEmpty
                && successor.stagedConstructedNodeIdentities.isEmpty
                && successor.stagedConstructionInFlightManifestEntryIndex == nil
                && prefixTreeMatches
                && successor.retentionTargets == retentionTargets
        case (.publicationIntent, .publicationAuthorized):
            return successor.stagedTree == stagedTree
                && successor.publicationAuthorizationTime != nil
                && successor.publicationMonotonicTime != nil
                && successor.publishedProvenance == nil
                && successor.retentionTargets == retentionTargets
        case (.publicationAuthorized, .published):
            return successor.stagedTree == stagedTree
                && successor.publicationAuthorizationTime == publicationAuthorizationTime
                && successor.publicationMonotonicTime == publicationMonotonicTime
                && successor.publishedProvenance != nil
                && successor.retentionTargets == retentionTargets
        case (.published, .quarantineIntent):
            return successor.stagedTree == stagedTree
                && successor.publicationAuthorizationTime == publicationAuthorizationTime
                && successor.publicationMonotonicTime == publicationMonotonicTime
                && successor.publishedProvenance == publishedProvenance
                && successor.retentionAuthorizationTime != nil
                && successor.retentionMonotonicTime != nil
                && retentionTargetsAuthorizeQuarantineIntent(successor.retentionTargets)
        case (.published, .committed):
            return successor.stagedTree == stagedTree
                && retentionAuthorizationTime == nil
                && successor.publicationAuthorizationTime == publicationAuthorizationTime
                && successor.publicationMonotonicTime == publicationMonotonicTime
                && successor.publishedProvenance == publishedProvenance
                && (successor.retentionAuthorizationTime == nil
                    || retentionTargets.isEmpty && successor.retentionTargets.isEmpty)
                && successor.retentionTargets == retentionTargets
        case (.quarantineIntent, .quarantined):
            return successor.stagedTree == stagedTree
                && previousFieldsOutsideDeletionEqual(successor)
                && quarantineIntentAuthorizesInventories(successor.retentionTargets)
        case (.quarantineIntent, .committed), (.quarantined, .committed):
            return try successor.stagedTree == stagedTree
                && successor.publicationAuthorizationTime == publicationAuthorizationTime
                && successor.publicationMonotonicTime == publicationMonotonicTime
                && successor.publishedProvenance == publishedProvenance
                && successor.retentionAuthorizationTime == nil
                && successor.retentionMonotonicTime == nil
                && retentionTargetsAuthorizeRestoredCommit(successor.retentionTargets)
        case (.quarantined, .deletionIntent),
            (.deletionIntent, .deletionIntent),
            (.deletionIntent, .deletionProgress),
            (.deletionIntent, .cleanupComplete),
            (.deletionProgress, .deletionProgress),
            (.deletionProgress, .cleanupComplete),
            (.stageIdentityBound, .stageDeletionIntent),
            (.publicationIntent, .stageDeletionIntent),
            (.publicationAuthorized, .stageDeletionIntent),
            (.stageDeletionIntent, .stageDeletionIntent),
            (.stageDeletionIntent, .stageDeletionProgress),
            (.stageDeletionIntent, .stageCleanupComplete),
            (.stageDeletionProgress, .stageDeletionProgress),
            (.stageDeletionProgress, .stageCleanupComplete),
            (.stageCleanupComplete, .committed):
            return try authorizesDeletionStateSuccessor(successor)
        case (.cleanupComplete, .committed):
            return stagedTree == successor.stagedTree
                && stagedDeletionManifest == successor.stagedDeletionManifest
                && previousFieldsOutsideDeletionEqual(successor)
                && retentionTargets == successor.retentionTargets
        default:
            return false
        }
    }

    private var stagingNameUTF8Bytes: [UInt8] { Array(stagingName.utf8) }
    private var publicationNameUTF8Bytes: [UInt8] { Array(publicationName.utf8) }

    private func immutableTransactionFieldsEqual(_ other: BackupTransactionJournalRecord) -> Bool {
        metadataRequirements == other.metadataRequirements
            && expectedOutputBytes == other.expectedOutputBytes
            && planningLimits == other.planningLimits
            && journalReservationBytes == other.journalReservationBytes
            && requestTimestamp == other.requestTimestamp
            && retentionPolicy == other.retentionPolicy
            && plannedRemovalNames == other.plannedRemovalNames
    }

    private func matchesCompletedStagedTree(
        expectedDescendantIdentities: [BackupStableNodeIdentity]? = nil
    ) throws -> Bool {
        guard let stagedTree,
            stagedTree.rootIdentity.stableNodeIdentity == stagingRootIdentity,
            try sourceTree.hasEquivalentCopiedContent(to: stagedTree)
        else {
            return false
        }
        if let expectedDescendantIdentities {
            return stagedTree.descendants.map({ $0.identity.stableNodeIdentity })
                == expectedDescendantIdentities
        }
        return true
    }

    private func matchesConstructionPrefixTree(
        manifest: [BackupStagedConstructionManifestEntry],
        constructedIdentities: [BackupStableNodeIdentity]
    ) throws -> Bool {
        guard let stagedTree,
            stagedTree.rootIdentity.stableNodeIdentity == stagingRootIdentity,
            stagedTree.descendants.count == constructedIdentities.count,
            constructedIdentities.count <= manifest.count
        else {
            return false
        }
        try stagedTree.validateCanonicalCompleteInventory()
        for index in stagedTree.descendants.indices {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard stagedTree.descendants[index].relativePath == manifest[index].relativePath,
                stagedTree.descendants[index].identity.kind == manifest[index].expectedKind,
                stagedTree.descendants[index].identity.stableNodeIdentity == constructedIdentities[index]
            else {
                return false
            }
        }
        try Task.checkCancellation()
        return true
    }

    private func retentionTargetsAuthorizeQuarantineIntent(
        _ successors: [BackupTransactionJournalTarget]
    ) -> Bool {
        guard retentionTargets.count == successors.count, !successors.isEmpty else { return false }
        var container: BackupStableNodeIdentity?
        for index in retentionTargets.indices {
            let prior = retentionTargets[index]
            let next = successors[index]
            guard prior.quarantineName == nil,
                prior.quarantineContainerIdentity == nil,
                prior.postRenameTree == nil,
                next.quarantineName != nil,
                let nextContainer = next.quarantineContainerIdentity,
                next.originalPath == prior.originalPath,
                next.provenance == prior.provenance,
                next.preRenameTree == prior.preRenameTree,
                next.postRenameTree == nil,
                next.deletionManifest.isEmpty,
                next.deletedManifestEntryCount == 0,
                next.deletionInFlightManifestEntryIndex == nil,
                container == nil || container == nextContainer
            else {
                return false
            }
            container = nextContainer
        }
        return true
    }

    private func quarantineIntentAuthorizesInventories(
        _ successors: [BackupTransactionJournalTarget]
    ) -> Bool {
        guard retentionTargets.count == successors.count else { return false }
        for index in retentionTargets.indices {
            let prior = retentionTargets[index]
            let next = successors[index]
            guard prior.quarantineName == next.quarantineName,
                prior.quarantineContainerIdentity == next.quarantineContainerIdentity,
                prior.originalPath == next.originalPath,
                prior.provenance == next.provenance,
                prior.preRenameTree == next.preRenameTree,
                prior.postRenameTree == nil,
                next.postRenameTree != nil,
                !next.deletionManifest.isEmpty,
                next.deletedManifestEntryCount == 0,
                next.deletionInFlightManifestEntryIndex == nil
            else {
                return false
            }
        }
        return true
    }

    private func retentionTargetsAuthorizeRestoredCommit(
        _ successors: [BackupTransactionJournalTarget]
    ) throws -> Bool {
        guard retentionTargets.count == successors.count else { return false }
        for index in retentionTargets.indices {
            let prior = retentionTargets[index]
            let next = successors[index]
            let priorProvenance = prior.provenance.provenance
            let nextProvenance = next.provenance.provenance
            let restorationSourceTree = prior.postRenameTree ?? prior.preRenameTree
            guard prior.quarantineName != nil,
                prior.quarantineContainerIdentity != nil,
                prior.deletedManifestEntryCount == 0,
                prior.deletionInFlightManifestEntryIndex == nil,
                next.quarantineName == nil,
                next.quarantineContainerIdentity == nil,
                next.originalPath.relativePath == prior.originalPath.relativePath,
                next.originalPath.components.last?.expectedIdentity == next.preRenameTree.rootIdentity,
                try next.preRenameTree.matchesAfterRename(from: restorationSourceTree),
                nextProvenance.transactionIdentifier == priorProvenance.transactionIdentifier,
                nextProvenance.sourceBindingIdentifier == priorProvenance.sourceBindingIdentifier,
                nextProvenance.seriesIdentifier == priorProvenance.seriesIdentifier,
                nextProvenance.name == priorProvenance.name,
                nextProvenance.createdAt == priorProvenance.createdAt,
                nextProvenance.sourceRootIdentity == priorProvenance.sourceRootIdentity,
                nextProvenance.destinationDirectoryIdentity == priorProvenance.destinationDirectoryIdentity,
                nextProvenance.backupTree == next.preRenameTree,
                next.provenance.keyIdentifier == prior.provenance.keyIdentifier,
                next.postRenameTree == nil,
                next.deletionManifest.isEmpty,
                next.deletedManifestEntryCount == 0,
                next.deletionInFlightManifestEntryIndex == nil
            else {
                return false
            }
        }
        return true
    }

    private func previousFieldsOutsideDeletionEqual(_ other: BackupTransactionJournalRecord) -> Bool {
        metadataRequirements == other.metadataRequirements
            && expectedOutputBytes == other.expectedOutputBytes
            && planningLimits == other.planningLimits
            && journalReservationBytes == other.journalReservationBytes
            && requestTimestamp == other.requestTimestamp
            && publicationAuthorizationTime == other.publicationAuthorizationTime
            && publicationMonotonicTime == other.publicationMonotonicTime
            && publishedProvenance == other.publishedProvenance
            && retentionAuthorizationTime == other.retentionAuthorizationTime
            && retentionMonotonicTime == other.retentionMonotonicTime
            && retentionPolicy == other.retentionPolicy
            && plannedRemovalNames == other.plannedRemovalNames
    }

    private static func hasCanonicalState(
        _ kind: BackupTransactionJournalRecordKind,
        transactionSequenceNumber: UInt64,
        sequenceNumber: UInt64,
        previousRecordAuthenticationTag: [UInt8]?,
        stagingRootIdentity: BackupStableNodeIdentity?,
        stagedConstructionManifest: [BackupStagedConstructionManifestEntry],
        stagedConstructedNodeIdentities: [BackupStableNodeIdentity],
        stagedConstructionInFlightManifestEntryIndex: UInt64?,
        stagedTree: BackupTreeSnapshot?,
        stagedDeletionManifest: [BackupJournalDeletionManifestEntry],
        stagedDeletedManifestEntryCount: UInt64,
        stagedDeletionInFlightManifestEntryIndex: UInt64?,
        publicationAuthorizationTime: BackupTimestamp?,
        publishedProvenance: BackupAuthenticatedProvenance?,
        retentionAuthorizationTime: BackupTimestamp?,
        retentionTargets: [BackupTransactionJournalTarget]
    ) throws -> Bool {
        let initialRecord = sequenceNumber == 0 && previousRecordAuthenticationTag == nil
        let rolloverPreparedRecord =
            transactionSequenceNumber > 1 && sequenceNumber == 0
            && previousRecordAuthenticationTag != nil
        let chainedRecord = sequenceNumber > 0 && previousRecordAuthenticationTag != nil
        let noStagedDeletion =
            stagedDeletionManifest.isEmpty
            && stagedDeletedManifestEntryCount == 0 && stagedDeletionInFlightManifestEntryIndex == nil
        let noStagedConstruction =
            stagedConstructionManifest.isEmpty
            && stagedConstructedNodeIdentities.isEmpty
            && stagedConstructionInFlightManifestEntryIndex == nil
        let stagedConstructionIntent =
            !stagedConstructionManifest.isEmpty
            && stagedConstructedNodeIdentities.count < stagedConstructionManifest.count
            && stagedConstructionInFlightManifestEntryIndex
                == UInt64(stagedConstructedNodeIdentities.count)
        let stagedConstructionProgress =
            !stagedConstructionManifest.isEmpty
            && stagedConstructedNodeIdentities.count <= stagedConstructionManifest.count
            && stagedConstructionInFlightManifestEntryIndex == nil
        let stagedDeletionIntent =
            !stagedDeletionManifest.isEmpty
            && stagedDeletedManifestEntryCount == 0
            && stagedDeletionInFlightManifestEntryIndex == 0
        let stagedDeletionProgress =
            !stagedDeletionManifest.isEmpty
            && stagedDeletedManifestEntryCount > 0
            && stagedDeletedManifestEntryCount < UInt64(stagedDeletionManifest.count)
        let stagedDeletionComplete =
            !stagedDeletionManifest.isEmpty
            && stagedDeletedManifestEntryCount == UInt64(stagedDeletionManifest.count)
            && stagedDeletionInFlightManifestEntryIndex == nil
        var beforeQuarantine = true
        var quarantinePlanned = true
        var fullyQuarantined = true
        var hasDeletedEntry = false
        var hasRemainingEntry = false
        var cleanupComplete = true
        var retentionDeletionCursorIsCanonical = true
        var foundIncompleteTarget = false
        for (index, target) in retentionTargets.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            beforeQuarantine =
                beforeQuarantine
                && target.quarantineName == nil && target.postRenameTree == nil
                && target.deletionManifest.isEmpty && target.deletedManifestEntryCount == 0
                && target.deletionInFlightManifestEntryIndex == nil
            quarantinePlanned =
                quarantinePlanned
                && target.quarantineName != nil && target.postRenameTree == nil
                && target.deletionManifest.isEmpty && target.deletedManifestEntryCount == 0
                && target.deletionInFlightManifestEntryIndex == nil
            let targetFullyQuarantined =
                target.quarantineName != nil && target.postRenameTree != nil
                && !target.deletionManifest.isEmpty
            let targetDeletionComplete =
                targetFullyQuarantined
                && target.deletedManifestEntryCount == UInt64(target.deletionManifest.count)
                && target.deletionInFlightManifestEntryIndex == nil
            fullyQuarantined =
                fullyQuarantined
                && targetFullyQuarantined
            hasDeletedEntry = hasDeletedEntry || target.deletedManifestEntryCount > 0
            hasRemainingEntry =
                hasRemainingEntry
                || target.deletedManifestEntryCount < UInt64(target.deletionManifest.count)
            cleanupComplete = cleanupComplete && targetDeletionComplete
            let targetIsComplete = target.deletedManifestEntryCount == UInt64(target.deletionManifest.count)
            if !foundIncompleteTarget, !targetIsComplete {
                foundIncompleteTarget = true
                retentionDeletionCursorIsCanonical =
                    retentionDeletionCursorIsCanonical
                    && (target.deletionInFlightManifestEntryIndex == nil
                        || target.deletionInFlightManifestEntryIndex == target.deletedManifestEntryCount)
            } else if foundIncompleteTarget {
                retentionDeletionCursorIsCanonical =
                    retentionDeletionCursorIsCanonical
                    && target.deletedManifestEntryCount == 0
                    && target.deletionInFlightManifestEntryIndex == nil
            } else {
                retentionDeletionCursorIsCanonical =
                    retentionDeletionCursorIsCanonical
                    && target.deletionInFlightManifestEntryIndex == nil
            }
        }
        try Task.checkCancellation()
        switch kind {
        case .prepared:
            return (initialRecord || rolloverPreparedRecord) && stagingRootIdentity == nil && stagedTree == nil
                && publicationAuthorizationTime == nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && noStagedDeletion && noStagedConstruction
        case .stageIdentityBound:
            return chainedRecord && stagingRootIdentity != nil && stagedTree == nil
                && publicationAuthorizationTime == nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && noStagedDeletion && noStagedConstruction
        case .stageConstructionIntent:
            return chainedRecord && stagingRootIdentity != nil && stagedTree == nil
                && publicationAuthorizationTime == nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && noStagedDeletion && stagedConstructionIntent
        case .stageConstructionProgress:
            return chainedRecord && stagingRootIdentity != nil && stagedTree == nil
                && publicationAuthorizationTime == nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && noStagedDeletion && stagedConstructionProgress
        case .stageDeletionIntent:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && stagedDeletionIntent && noStagedConstruction
        case .stageDeletionProgress:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && stagedDeletionProgress
                && noStagedConstruction
                && (stagedDeletionInFlightManifestEntryIndex == nil
                    || stagedDeletionInFlightManifestEntryIndex == stagedDeletedManifestEntryCount)
        case .stageCleanupComplete:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && stagedDeletionComplete && noStagedConstruction
        case .publicationIntent:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publicationAuthorizationTime == nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && noStagedDeletion && noStagedConstruction
        case .publicationAuthorized:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publicationAuthorizationTime != nil
                && publishedProvenance == nil && retentionAuthorizationTime == nil && beforeQuarantine
                && noStagedDeletion && noStagedConstruction
        case .published:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publicationAuthorizationTime != nil
                && publishedProvenance != nil && retentionAuthorizationTime == nil && beforeQuarantine
                && noStagedDeletion && noStagedConstruction
        case .quarantineIntent:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publicationAuthorizationTime != nil
                && publishedProvenance != nil && retentionAuthorizationTime != nil && quarantinePlanned
                && noStagedDeletion && noStagedConstruction
        case .quarantined, .deletionIntent:
            let deletionCursorIsValid =
                kind == .quarantined
                ? !hasDeletedEntry && hasRemainingEntry
                    && retentionTargets.allSatisfy({ $0.deletionInFlightManifestEntryIndex == nil })
                : !hasDeletedEntry && hasRemainingEntry && retentionDeletionCursorIsCanonical
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publicationAuthorizationTime != nil
                && publishedProvenance != nil && retentionAuthorizationTime != nil && fullyQuarantined
                && deletionCursorIsValid && noStagedDeletion && noStagedConstruction
        case .deletionProgress:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publicationAuthorizationTime != nil
                && publishedProvenance != nil && retentionAuthorizationTime != nil && fullyQuarantined
                && hasDeletedEntry && hasRemainingEntry && retentionDeletionCursorIsCanonical
                && noStagedDeletion && noStagedConstruction
        case .cleanupComplete:
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && publicationAuthorizationTime != nil
                && publishedProvenance != nil && retentionAuthorizationTime != nil && fullyQuarantined
                && cleanupComplete && noStagedDeletion && noStagedConstruction
        case .committed:
            let completedCleanup =
                retentionAuthorizationTime != nil && fullyQuarantined && cleanupComplete
            let recoveredWithoutRetention = retentionAuthorizationTime == nil && beforeQuarantine
            let committedPublication =
                publicationAuthorizationTime != nil && publishedProvenance != nil
                && (completedCleanup || recoveredWithoutRetention) && noStagedDeletion
                && noStagedConstruction
            let committedPrepublicationCleanup =
                publishedProvenance == nil
                && retentionAuthorizationTime == nil && beforeQuarantine
                && stagedDeletionComplete && noStagedConstruction
            return chainedRecord && stagingRootIdentity != nil && stagedTree != nil
                && (committedPublication || committedPrepublicationCleanup)
        }
    }

    private static func validateAgainstSignedLimits(
        sourceTree: BackupTreeSnapshot,
        stagedConstructionManifest: [BackupStagedConstructionManifestEntry],
        stagedConstructedNodeIdentities: [BackupStableNodeIdentity],
        stagedTree: BackupTreeSnapshot?,
        stagedDeletionManifest: [BackupJournalDeletionManifestEntry],
        expectedOutputBytes: UInt64,
        retentionPolicy: BackupRetentionPolicy,
        stagingName: String,
        publicationName: String,
        plannedRemovalNames: [String],
        retentionTargets: [BackupTransactionJournalTarget],
        limits: BackupPlanningLimits
    ) throws {
        try sourceTree.validateCanonicalCompleteInventory()
        try stagedTree?.validateCanonicalCompleteInventory()
        guard sourceTree.descendants.count < limits.maximumSourceItemCount,
            stagedConstructionManifest.count <= limits.maximumSourceItemCount,
            stagedConstructedNodeIdentities.count <= stagedConstructionManifest.count,
            stagedTree.map({ $0.descendants.count < limits.maximumSourceItemCount }) ?? true,
            stagedDeletionManifest.count <= limits.maximumSourceItemCount,
            retentionTargets.count <= limits.maximumExistingBackupCount,
            retentionTargets.count <= limits.maximumPlanStepCount - 1,
            plannedRemovalNames.count == retentionTargets.count,
            retentionPolicy.maximumCount.map({ $0 > 0 && $0 <= limits.maximumExistingBackupCount + 1 }) ?? true,
            retentionPolicy.maximumAgeSeconds.map({ $0 > 0 }) ?? true
        else {
            throw BackupPolicyError.invalidObservation("Authenticated journal exceeds its signed item limits.")
        }
        var totalPathBytes = 0
        var retentionItems = 0
        var workUnits: UInt64 = 0
        func addPathBytes(_ bytes: [UInt8]) throws {
            let count = bytes.count
            guard count <= limits.maximumPathUTF8Bytes,
                count <= limits.maximumTotalPathUTF8Bytes - totalPathBytes
            else {
                throw BackupPolicyError.invalidObservation("Authenticated journal exceeds its signed path limits.")
            }
            totalPathBytes += count
        }
        func addPath(_ path: BackupRelativePath) throws {
            try addPathBytes(path.rawUTF8Bytes)
        }
        func addWork(_ count: Int) throws {
            let (next, overflow) = workUnits.addingReportingOverflow(UInt64(count))
            guard !overflow, next <= limits.maximumEstimatedWorkUnits else {
                throw BackupPolicyError.invalidObservation("Authenticated journal exceeds its signed work limit.")
            }
            workUnits = next
        }
        var chargedSourceNodes: Set<BackupStableNodeIdentity> = []
        var recomputedOutputBytes: UInt64 = 0
        func addOutputCharge(_ identity: BackupItemIdentity) throws {
            try addWork(1)
            guard
                identity.kind != .regularFile
                    || chargedSourceNodes.insert(identity.stableNodeIdentity).inserted
            else {
                return
            }
            let (next, overflow) = recomputedOutputBytes.addingReportingOverflow(identity.outputByteCharge)
            guard !overflow, next <= limits.maximumOutputBytes else {
                throw BackupPolicyError.invalidObservation("Authenticated journal exceeds its signed output limit.")
            }
            recomputedOutputBytes = next
        }
        try addOutputCharge(sourceTree.rootIdentity)
        for (index, entry) in sourceTree.descendants.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            try addOutputCharge(entry.identity)
        }
        guard recomputedOutputBytes == expectedOutputBytes else {
            throw BackupPolicyError.invalidObservation("Authenticated journal output charge is inconsistent.")
        }
        try addPathBytes(Array(stagingName.utf8))
        try addPathBytes(Array(publicationName.utf8))
        for name in plannedRemovalNames {
            try addPathBytes(Array(name.utf8))
            try addWork(1)
        }
        for tree in [sourceTree, stagedTree].compactMap({ $0 }) {
            for (index, entry) in tree.descendants.enumerated() {
                if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                try addPath(entry.relativePath)
                try addWork(entry.relativePath.componentUTF8Bytes.count)
            }
        }
        for (index, entry) in stagedConstructionManifest.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            try addPath(entry.relativePath)
            if let parentPath = entry.parentRelativePath { try addPath(parentPath) }
            try addPathBytes(entry.nameUTF8Bytes)
            try addWork(1)
        }
        for (index, entry) in stagedDeletionManifest.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            if let path = entry.relativePath { try addPath(path) }
            if let parentPath = entry.parentRelativePath { try addPath(parentPath) }
            try addPathBytes(entry.nameUTF8Bytes)
            try addWork(1)
        }
        for (targetIndex, target) in retentionTargets.enumerated() {
            if targetIndex.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let targetItems = 1 + target.preRenameTree.descendants.count
            guard targetItems <= limits.maximumRetentionItemCount - retentionItems else {
                throw BackupPolicyError.invalidObservation("Authenticated journal exceeds its signed retention limit.")
            }
            retentionItems += targetItems
            try addWork(targetItems)
            try addPath(target.originalPath.relativePath)
            if let quarantineName = target.quarantineName {
                try addPathBytes(Array(quarantineName.utf8))
            }
            for (index, entry) in target.preRenameTree.descendants.enumerated() {
                if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                try addPath(entry.relativePath)
                try addWork(entry.relativePath.componentUTF8Bytes.count)
            }
            if let postRenameTree = target.postRenameTree {
                for (index, entry) in postRenameTree.descendants.enumerated() {
                    if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                    try addPath(entry.relativePath)
                    try addWork(entry.relativePath.componentUTF8Bytes.count)
                }
            }
            for (index, entry) in target.deletionManifest.enumerated() {
                if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                if let path = entry.relativePath { try addPath(path) }
                if let parentPath = entry.parentRelativePath { try addPath(parentPath) }
                try addPathBytes(entry.nameUTF8Bytes)
                try addWork(1)
            }
        }
    }

    private static func isWithinMaximumSkew(_ lhs: BackupTimestamp, _ rhs: BackupTimestamp) -> Bool {
        let earlier = min(lhs, rhs)
        let later = max(lhs, rhs)
        let biasedEarlier = UInt64(bitPattern: earlier.secondsSince1970) ^ (1 << 63)
        let biasedLater = UInt64(bitPattern: later.secondsSince1970) ^ (1 << 63)
        let seconds = biasedLater - biasedEarlier
        let maximum = BackupTrustedTimeContract.maximumRequestSkewSeconds
        if seconds != maximum { return seconds < maximum }
        return later.nanoseconds <= earlier.nanoseconds
    }

    private static func elapsedNanoseconds(
        from earlier: BackupTimestamp,
        to later: BackupTimestamp
    ) -> UInt64? {
        guard earlier <= later else { return nil }
        let biasedEarlier = UInt64(bitPattern: earlier.secondsSince1970) ^ (1 << 63)
        let biasedLater = UInt64(bitPattern: later.secondsSince1970) ^ (1 << 63)
        let seconds = biasedLater - biasedEarlier
        let multiplied = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !multiplied.overflow else { return nil }
        if later.nanoseconds >= earlier.nanoseconds {
            let added = multiplied.partialValue.addingReportingOverflow(
                UInt64(later.nanoseconds - earlier.nanoseconds)
            )
            return added.overflow ? nil : added.partialValue
        }
        guard seconds > 0 else { return nil }
        return multiplied.partialValue - UInt64(earlier.nanoseconds - later.nanoseconds)
    }

    private static func hasConsistentClockProgress(
        publicationWallTime: BackupTimestamp?,
        publicationMonotonicTime: BackupMonotonicInstant?,
        retentionWallTime: BackupTimestamp?,
        retentionMonotonicTime: BackupMonotonicInstant?
    ) -> Bool {
        guard let publicationWallTime,
            let publicationMonotonicTime,
            let retentionWallTime,
            let retentionMonotonicTime
        else {
            return retentionWallTime == nil && retentionMonotonicTime == nil
        }
        guard
            publicationMonotonicTime.clockSessionIdentifier
                == retentionMonotonicTime.clockSessionIdentifier,
            publicationMonotonicTime.nanoseconds < retentionMonotonicTime.nanoseconds,
            publicationWallTime <= retentionWallTime
        else {
            return false
        }
        let monotonicDeltaNanoseconds =
            retentionMonotonicTime.nanoseconds
            - publicationMonotonicTime.nanoseconds
        guard
            let wallDeltaNanoseconds = elapsedNanoseconds(
                from: publicationWallTime,
                to: retentionWallTime
            )
        else { return false }
        let toleranceNanoseconds = BackupTrustedTimeContract.maximumRequestSkewSeconds * 1_000_000_000
        let difference =
            monotonicDeltaNanoseconds > wallDeltaNanoseconds
            ? monotonicDeltaNanoseconds - wallDeltaNanoseconds
            : wallDeltaNanoseconds - monotonicDeltaNanoseconds
        return difference <= toleranceNanoseconds
    }
}

public struct BackupAuthenticatedTransactionJournalRecord: Equatable, Hashable, Sendable {
    public let record: BackupTransactionJournalRecord
    public let keyIdentifier: String
    public let authenticationTag: [UInt8]

    public init(
        record: BackupTransactionJournalRecord,
        keyIdentifier: String,
        authenticationTag: [UInt8]
    ) throws {
        try BackupCanonicalAuthenticationEncoder.validateKeyIdentifier(keyIdentifier)
        guard authenticationTag.count == BackupAuthenticationFormat.authenticationTagByteCount else {
            throw BackupPolicyError.invalidObservation("Backup journal authentication tag has an invalid size.")
        }
        self.record = record
        self.keyIdentifier = keyIdentifier
        self.authenticationTag = authenticationTag
    }

    public func authenticationBytes() throws -> Data {
        try record.authenticationBytes(keyIdentifier: keyIdentifier)
    }

    /// Streams canonical MAC input without materializing complete authenticated inventory.
    public func writeAuthenticationBytes(_ write: @escaping (Data) throws -> Void) throws {
        try BackupCanonicalAuthenticationEncoder.writeTransactionJournalAuthentication(
            record,
            keyIdentifier: keyIdentifier,
            to: write
        )
    }

    /// Exact journal file bytes: `authenticationBytes()`, followed by the authentication tag as one
    /// UInt64 big-endian length-framed field. Decoder must reject trailing bytes, unsupported schema
    /// versions, invalid HMACs, and any input not reproduced byte-for-byte by this method.
    public func encodedData() throws -> Data {
        var data = Data()
        try writeEncodedData { data.append($0) }
        return data
    }

    /// Streams canonical file bytes in bounded field-sized chunks. Executors should use this API for
    /// journal files rather than materializing attacker-sized authenticated inventories in memory.
    public func writeEncodedData(_ write: @escaping (Data) throws -> Void) throws {
        try BackupCanonicalAuthenticationEncoder.writeAuthenticatedTransactionJournal(self, to: write)
    }
}

public enum BackupJournalAnchorRecoveryDisposition: Equatable, Hashable, Sendable {
    case exactMatch
    case advanceAtomicallyToSemanticDirectSuccessor
    case advanceAtomicallyToPreparedRollover
    case reject
}

/// Rollback-resistant cursor for one exact durable journal record. Executor stores this outside the
/// destination volume and compares all fields before any journal-authorized filesystem mutation.
public struct BackupJournalSequenceAnchor: Equatable, Hashable, Sendable {
    public let sequenceAnchorIdentifier: [UInt8]
    public let transactionSequenceNumber: UInt64
    public let journalSequenceNumber: UInt64
    public let journalRecordKind: BackupTransactionJournalRecordKind
    public let journalAuthenticationTag: [UInt8]

    public init(
        sequenceAnchorIdentifier: [UInt8],
        transactionSequenceNumber: UInt64,
        journalSequenceNumber: UInt64,
        journalRecordKind: BackupTransactionJournalRecordKind,
        journalAuthenticationTag: [UInt8]
    ) throws {
        guard sequenceAnchorIdentifier.count == BackupAuthenticationFormat.identifierByteCount,
            transactionSequenceNumber > 0,
            journalAuthenticationTag.count == BackupAuthenticationFormat.authenticationTagByteCount
        else {
            throw BackupPolicyError.invalidObservation("Backup journal sequence anchor is malformed.")
        }
        self.sequenceAnchorIdentifier = sequenceAnchorIdentifier
        self.transactionSequenceNumber = transactionSequenceNumber
        self.journalSequenceNumber = journalSequenceNumber
        self.journalRecordKind = journalRecordKind
        self.journalAuthenticationTag = journalAuthenticationTag
    }

    /// Caller first verifies journal HMAC, canonical bytes, durability, and destination binding.
    /// Exact equality authorizes normal recovery. Any authenticated semantic direct successor and
    /// next-transaction `.prepared` rollover may repair journal/anchor crash gap. Same-transaction
    /// recovery requires retained authenticated predecessor because anchor tag alone cannot validate
    /// payload semantics.
    public func recoveryDisposition(
        forAuthenticatedDurableJournal journal: BackupAuthenticatedTransactionJournalRecord,
        retainedAuthenticatedPredecessor: BackupAuthenticatedTransactionJournalRecord? = nil
    ) -> BackupJournalAnchorRecoveryDisposition {
        let record = journal.record
        if record.sequenceAnchorIdentifier == sequenceAnchorIdentifier,
            record.transactionSequenceNumber == transactionSequenceNumber,
            record.sequenceNumber == journalSequenceNumber,
            record.recordKind == journalRecordKind,
            journal.authenticationTag == journalAuthenticationTag
        {
            return .exactMatch
        }
        if let predecessor = retainedAuthenticatedPredecessor,
            predecessor.record.sequenceAnchorIdentifier == sequenceAnchorIdentifier,
            predecessor.record.transactionSequenceNumber == transactionSequenceNumber,
            predecessor.record.sequenceNumber == journalSequenceNumber,
            predecessor.record.recordKind == journalRecordKind,
            predecessor.authenticationTag == journalAuthenticationTag,
            record.previousRecordAuthenticationTag == predecessor.authenticationTag,
            (try? predecessor.record.authorizesSemanticDirectSuccessor(record)) == true
        {
            return .advanceAtomicallyToSemanticDirectSuccessor
        }
        return recoveryDisposition(
            recordKind: record.recordKind,
            sequenceAnchorIdentifier: record.sequenceAnchorIdentifier,
            transactionSequenceNumber: record.transactionSequenceNumber,
            journalSequenceNumber: record.sequenceNumber,
            previousJournalAuthenticationTag: record.previousRecordAuthenticationTag,
            journalAuthenticationTag: journal.authenticationTag
        )
    }

    public func recoveryDisposition(
        recordKind: BackupTransactionJournalRecordKind,
        sequenceAnchorIdentifier: [UInt8],
        transactionSequenceNumber: UInt64,
        journalSequenceNumber: UInt64,
        previousJournalAuthenticationTag: [UInt8]?,
        journalAuthenticationTag: [UInt8]
    ) -> BackupJournalAnchorRecoveryDisposition {
        guard sequenceAnchorIdentifier == self.sequenceAnchorIdentifier,
            journalAuthenticationTag.count == BackupAuthenticationFormat.authenticationTagByteCount,
            previousJournalAuthenticationTag?.count == nil
                || previousJournalAuthenticationTag?.count
                    == BackupAuthenticationFormat.authenticationTagByteCount
        else {
            return .reject
        }
        if transactionSequenceNumber == self.transactionSequenceNumber,
            journalSequenceNumber == self.journalSequenceNumber,
            recordKind == journalRecordKind,
            journalAuthenticationTag == self.journalAuthenticationTag
        {
            return .exactMatch
        }
        let nextTransaction = self.transactionSequenceNumber.addingReportingOverflow(1)
        guard !nextTransaction.overflow,
            journalRecordKind == .committed,
            recordKind == .prepared,
            transactionSequenceNumber == nextTransaction.partialValue,
            journalSequenceNumber == 0,
            previousJournalAuthenticationTag == self.journalAuthenticationTag
        else {
            return .reject
        }
        return .advanceAtomicallyToPreparedRollover
    }

    /// Validates record-chain continuity before durable replacement. This does not authorize a
    /// filesystem mutation; executor must first durably write successor and atomically anchor its tag.
    public func isDirectSuccessor(
        sequenceAnchorIdentifier: [UInt8],
        transactionSequenceNumber: UInt64,
        journalSequenceNumber: UInt64,
        previousJournalAuthenticationTag: [UInt8]?
    ) -> Bool {
        let successor = self.journalSequenceNumber.addingReportingOverflow(1)
        return !successor.overflow
            && sequenceAnchorIdentifier == self.sequenceAnchorIdentifier
            && transactionSequenceNumber == self.transactionSequenceNumber
            && journalSequenceNumber == successor.partialValue
            && previousJournalAuthenticationTag == journalAuthenticationTag
    }

    /// Returns exact successor state after retained authenticated predecessor proves one legal
    /// same-transaction transition and exact tag chain.
    public func advancingToAuthenticatedDurableSemanticDirectSuccessor(
        _ journal: BackupAuthenticatedTransactionJournalRecord,
        retainedAuthenticatedPredecessor: BackupAuthenticatedTransactionJournalRecord
    ) throws -> BackupJournalSequenceAnchor {
        guard
            recoveryDisposition(
                forAuthenticatedDurableJournal: journal,
                retainedAuthenticatedPredecessor: retainedAuthenticatedPredecessor
            ) == .advanceAtomicallyToSemanticDirectSuccessor
        else {
            throw BackupPolicyError.invalidObservation(
                "Backup journal is not an authenticated semantic direct successor."
            )
        }
        return try BackupJournalSequenceAnchor(
            sequenceAnchorIdentifier: sequenceAnchorIdentifier,
            transactionSequenceNumber: transactionSequenceNumber,
            journalSequenceNumber: journal.record.sequenceNumber,
            journalRecordKind: journal.record.recordKind,
            journalAuthenticationTag: journal.authenticationTag
        )
    }

    /// Returns next transaction cursor only after authenticated prepared record directly chains from
    /// anchored committed tag with exact transaction + 1 and reset journal sequence zero.
    public func advancingToAuthenticatedDurablePreparedRollover(
        _ journal: BackupAuthenticatedTransactionJournalRecord
    ) throws -> BackupJournalSequenceAnchor {
        guard
            recoveryDisposition(forAuthenticatedDurableJournal: journal)
                == .advanceAtomicallyToPreparedRollover
        else {
            throw BackupPolicyError.invalidObservation(
                "Backup journal is not the authenticated next prepared transaction."
            )
        }
        return try BackupJournalSequenceAnchor(
            sequenceAnchorIdentifier: sequenceAnchorIdentifier,
            transactionSequenceNumber: journal.record.transactionSequenceNumber,
            journalSequenceNumber: journal.record.sequenceNumber,
            journalRecordKind: journal.record.recordKind,
            journalAuthenticationTag: journal.authenticationTag
        )
    }
}

/// Exact rollback-resistant cursor stored outside the destination volume (for example Keychain
/// secure storage). Cursor binds anchor identifier, transaction sequence, latest durable journal
/// sequence, and latest authentication tag. Before every journal-authorized filesystem mutation,
/// executor atomically advances cursor to exact durable record that authorizes it. Recovery accepts
/// exact cursor equality or one authenticated semantic direct successor proven against retained
/// authenticated predecessor from second reserved slot; recovery advances cursor before applying
/// successor semantics. Rollover retains anchored committed journal until next `.prepared` record is
/// durably replaced with transaction sequence + 1, journal sequence zero, same anchor identifier, and
/// previous tag equal committed tag; anchor then advances atomically. Recovery may perform same exact
/// advance. Old journal removal or an unchained prepared record is forbidden. Missing, rolled-back,
/// skipped, duplicated, or unavailable cursor state fails
/// closed; HMAC chaining alone is not rollback resistance.
public struct BackupJournalSequenceAnchorContract: Equatable, Hashable, Sendable {
    public let storageRequirement = "rollback-resistant-storage-outside-destination-volume"
    public let boundState =
        "anchor-id + transaction-sequence + journal-sequence + journal-record-kind + journal-authentication-tag"
    public let mutationRequirement = "anchor exactly equals latest durable authorizing record before each mutation"
    public let committedRecoveryRelation =
        "authenticated successor == anchored journal semantic direct successor with retained predecessor and exact tag chain"
    public let committedRecoveryAction = "atomically advance anchor to authenticated successor before its recovery action"
    public let preparedRolloverRelation =
        "authenticated prepared transaction == anchored committed transaction + 1, journal sequence 0, previous tag == committed tag"
    public let preparedRolloverAction = "atomically advance anchor to prepared rollover before staging mutation"
    public let recoveryOrderingRequirement =
        "authenticate journal and exactly compare sequence-and-tag anchor before any recovery mutation or deletion"

    public init() {}
}

public enum BackupJournalReplacementPhase: String, CaseIterable, Equatable, Hashable, Sendable {
    case writeExclusiveTemporaryRecord
    case syncTemporaryRecord
    case atomicallyReplaceJournal
    case syncReplacementRecord
    case syncJournalDirectory
    case atomicallyBindRollbackAnchorSequenceAndTag
}

/// Exact canonical journal MAC input is UTF-8 transaction-journal domain plus zero, then key
/// identifier and every `BackupTransactionJournalRecord` field in declaration order using the
/// source-binding length framing. Integers are fixed-width big-endian.
/// Optionals and arrays use the presence/count rules above. Nested identities, trees, capabilities,
/// provenance, bound paths, manifests, and progress recursively encode every declaration-order
/// field. Authenticated file bytes append the length-framed HMAC tag to that MAC input. Replacement
/// completes only after rollback anchor atomically binds exact durable sequence and tag. Prior
/// authenticated record remains in second reserved slot until binding, enabling semantic gap recovery. No padding,
/// native-layout bytes, omitted defaults, trailing data, or alternate encoding is accepted.
public struct BackupTransactionJournalFormat: Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = BackupTransactionJournalRecord.currentSchemaVersion
    public static let canonicalEncodingIdentifier = "com.macmerge.backup-transaction-journal.canonical-binary.v3"
    public static let requiredReplacementOrder = BackupJournalReplacementPhase.allCases
    public static let maximumEncodedBytes = 16 * 1_024 * 1_024
    public static let requiredReservedRecordCount = 2
    public static let maximumReservedBytes = maximumEncodedBytes * requiredReservedRecordCount
    public static let maximumAuthenticationFieldBytes = 64 * 1_024

    public let canonicalEncodingIdentifier = Self.canonicalEncodingIdentifier
    public let replacementOrder = Self.requiredReplacementOrder
    public let reservedRecordCount = Self.requiredReservedRecordCount
    public let maximumReservedBytes = Self.maximumReservedBytes
    public let sequenceAnchor = BackupJournalSequenceAnchorContract()

    /// `durablyReservedBytes` means allocation and quota are already guaranteed on journal volume;
    /// free-space observation alone is not a reservation and must not be passed here.
    public static func hasRequiredDurableReservation(
        requiredBytes: Int,
        durablyReservedBytes: Int
    ) -> Bool {
        isValidReservationPlan(requiredBytes: requiredBytes)
            && durablyReservedBytes >= requiredBytes
    }

    public static func isValidReservationPlan(requiredBytes: Int) -> Bool {
        requiredBytes > 0
            && requiredBytes.isMultiple(of: requiredReservedRecordCount)
            && requiredBytes / requiredReservedRecordCount <= maximumEncodedBytes
            && requiredBytes <= maximumReservedBytes
    }

    public init() {}
}

private enum BackupJournalSizePreflight {
    static func validate(
        sourceTree: BackupTreeSnapshot,
        publicationName: String,
        sourceBinding: BackupAuthenticatedSourceBinding,
        destinationDirectoryIdentity: BackupItemIdentity,
        retentionPolicy: BackupRetentionPolicy,
        retentionTargets: [BackupExistingBackup]
    ) throws -> Int {
        return try requiredReservationBytes(
            sourceTree: sourceTree,
            publicationName: publicationName,
            sourceBinding: sourceBinding,
            destinationDirectoryIdentity: destinationDirectoryIdentity,
            retentionPolicy: retentionPolicy,
            retentionTargets: retentionTargets.map {
                Target(
                    boundPath: $0.boundPath,
                    provenanceRecord: $0.provenanceRecord,
                    tree: $0.tree
                )
            }
        )
    }

    static func requiredReservationBytes(
        sourceTree: BackupTreeSnapshot,
        publicationName: String,
        sourceBinding: BackupAuthenticatedSourceBinding,
        destinationDirectoryIdentity: BackupItemIdentity,
        retentionPolicy: BackupRetentionPolicy,
        retentionTargets: [BackupTransactionJournalTarget]
    ) throws -> Int {
        let conservativeTargets = retentionTargets.map { target in
            let tree = target.postRenameTree ?? target.preRenameTree
            return Target(
                boundPath: target.originalPath,
                provenanceRecord: target.provenance,
                tree: tree
            )
        }
        return try requiredReservationBytes(
            sourceTree: sourceTree,
            publicationName: publicationName,
            sourceBinding: sourceBinding,
            destinationDirectoryIdentity: destinationDirectoryIdentity,
            retentionPolicy: retentionPolicy,
            retentionTargets: conservativeTargets
        )
    }

    private static func requiredReservationBytes(
        sourceTree: BackupTreeSnapshot,
        publicationName: String,
        sourceBinding: BackupAuthenticatedSourceBinding,
        destinationDirectoryIdentity: BackupItemIdentity,
        retentionPolicy: BackupRetentionPolicy,
        retentionTargets: [Target]
    ) throws -> Int {
        var budget = Budget()
        try budget.addRaw(BackupAuthenticationFormat.transactionJournalDomain.utf8.count + 1)
        try budget.addField(BackupAuthenticationFormat.keyIdentifierMaximumUTF8Bytes)
        try budget.addField(8)
        try budget.addField("publicationAuthorized".utf8.count)
        try budget.addField(8)
        try budget.addField(8)
        try budget.addField(BackupAuthenticationFormat.identifierByteCount)
        try budget.addField(BackupAuthenticationFormat.identifierByteCount)
        try budget.addPresence()
        try budget.addField(BackupAuthenticationFormat.authenticationTagByteCount)
        try budget.add(sourceBinding)
        try budget.add(tree: sourceTree)
        try budget.addStagedConstructionManifest(sourceTree)
        try budget.addField(8)
        for (index, _) in sourceTree.descendants.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            try budget.add(
                destinationDirectoryIdentity.stableNodeIdentity,
                persistentVolumeIdentityByteCount: destinationDirectoryIdentity.persistentVolumeIdentity.bytes.count
            )
        }
        try budget.addPresence()
        try budget.addField(8)
        try budget.addPresence()
        try budget.add(
            tree: sourceTree,
            persistentVolumeIdentityByteCount: destinationDirectoryIdentity.persistentVolumeIdentity.bytes.count
        )
        try budget.addDeletionManifest(
            tree: sourceTree,
            rootNameByteCount: 255,
            rootParentIdentity: destinationDirectoryIdentity.stableNodeIdentity,
            persistentVolumeIdentityByteCount: destinationDirectoryIdentity.persistentVolumeIdentity.bytes.count
        )
        try budget.addField(8)
        try budget.addPresence()
        try budget.addField(8)
        try budget.add(destinationDirectoryIdentity)
        try budget.addField(255)
        try budget.addPresence()
        try budget.add(destinationDirectoryIdentity.stableNodeIdentity)
        try budget.addField(publicationName.utf8.count)
        try budget.addField(2)
        try budget.addField(8)
        for _ in 0..<9 { try budget.addField(8) }
        try budget.addField(8)
        try budget.addTimestamp()
        try budget.addPresence()
        try budget.addTimestamp()
        try budget.addPresence()
        try budget.addField(BackupAuthenticationFormat.identifierByteCount)
        try budget.addField(8)
        try budget.addPresence()
        try budget.addPublishedProvenance(
            sourceBinding: sourceBinding,
            publicationName: publicationName,
            sourceRootIdentity: sourceTree.rootIdentity,
            destinationDirectoryIdentity: destinationDirectoryIdentity,
            copiedTree: sourceTree
        )
        try budget.addPresence()
        try budget.addTimestamp()
        try budget.addPresence()
        try budget.addField(BackupAuthenticationFormat.identifierByteCount)
        try budget.addField(8)
        try budget.addPresence()
        if retentionPolicy.maximumCount != nil { try budget.addField(8) }
        try budget.addPresence()
        if retentionPolicy.maximumAgeSeconds != nil { try budget.addField(8) }
        try budget.addField(8)
        for (index, target) in retentionTargets.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            try budget.addField(target.name.utf8.count)
        }
        try budget.addField(8)
        for (index, target) in retentionTargets.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            try budget.add(target: target)
        }
        try budget.addField(BackupAuthenticationFormat.authenticationTagByteCount)
        let requiredReservationBytes = try budget.requiredReservationBytes()
        try Task.checkCancellation()
        return requiredReservationBytes
    }

    private struct Target {
        let boundPath: BackupBoundRelativePath
        let provenanceRecord: BackupAuthenticatedProvenance
        let tree: BackupTreeSnapshot

        var name: String { provenanceRecord.provenance.name }
    }

    private struct Budget {
        var count = 0

        mutating func addRaw(_ byteCount: Int) throws {
            guard byteCount >= 0,
                count <= BackupTransactionJournalFormat.maximumEncodedBytes - byteCount
            else {
                throw BackupPolicyError.invalidObservation(
                    "Backup plan could create a transaction journal larger than the 16 MiB operational limit."
                )
            }
            count += byteCount
        }

        mutating func addField(_ byteCount: Int) throws {
            guard byteCount <= BackupTransactionJournalFormat.maximumAuthenticationFieldBytes else {
                throw BackupPolicyError.invalidObservation(
                    "Backup plan could create an oversized transaction-journal field."
                )
            }
            try addRaw(8)
            try addRaw(byteCount)
        }

        mutating func addPresence() throws {
            try addField(1)
        }

        func requiredReservationBytes() throws -> Int {
            let (requiredBytes, overflow) = count.multipliedReportingOverflow(
                by: BackupTransactionJournalFormat.requiredReservedRecordCount
            )
            guard !overflow,
                requiredBytes <= BackupTransactionJournalFormat.maximumReservedBytes
            else {
                throw BackupPolicyError.invalidObservation(
                    "Backup plan cannot reserve capacity for two maximum-size transaction journal records."
                )
            }
            return requiredBytes
        }

        mutating func addTimestamp() throws {
            try addField(8)
            try addField(4)
        }

        mutating func add(
            _ identity: BackupStableNodeIdentity,
            persistentVolumeIdentityByteCount: Int? = nil
        ) throws {
            try addField(persistentVolumeIdentityByteCount ?? identity.persistentVolumeIdentity.bytes.count)
            try addField(8)
            try addField(8)
        }

        mutating func add(
            _ identity: BackupItemIdentity,
            persistentVolumeIdentityByteCount: Int? = nil
        ) throws {
            try addField(persistentVolumeIdentityByteCount ?? identity.persistentVolumeIdentity.bytes.count)
            try addField(8)
            try addField(8)
            try addField(8)
            try addField(identity.kind.rawValue.utf8.count)
            try addField(8)
            try addField(8)
            try addField(8)
            try addTimestamp()
            try addTimestamp()
            try addField(BackupIntegrityDigest.byteCount)
            try addField(BackupIntegrityDigest.byteCount)
            try addField(BackupIntegrityDigest.byteCount)
        }

        mutating func add(
            tree: BackupTreeSnapshot,
            persistentVolumeIdentityByteCount: Int? = nil
        ) throws {
            try add(
                tree.rootIdentity,
                persistentVolumeIdentityByteCount: persistentVolumeIdentityByteCount
            )
            try addField(2)
            try addField(8)
            for (index, entry) in tree.descendants.enumerated() {
                if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                try addField(entry.relativePath.rawUTF8Bytes.count)
                try add(
                    entry.identity,
                    persistentVolumeIdentityByteCount: persistentVolumeIdentityByteCount
                )
            }
        }

        mutating func add(_ sourceBinding: BackupAuthenticatedSourceBinding) throws {
            let binding = sourceBinding.binding
            try addField(8)
            try addField(binding.sourceBindingIdentifier.count)
            try addField(binding.seriesIdentifier.utf8.count)
            try add(binding.sourceRootIdentity)
            try add(binding.destinationDirectoryIdentity)
            try addTimestamp()
            try addTimestamp()
            try addTimestamp()
            try addField(sourceBinding.keyIdentifier.utf8.count)
            try addField(sourceBinding.authenticationTag.count)
        }

        mutating func add(_ provenance: BackupAuthenticatedProvenance) throws {
            let record = provenance.provenance
            try addField(8)
            try addField(record.transactionIdentifier.count)
            try addField(record.sourceBindingIdentifier.count)
            try addField(record.seriesIdentifier.utf8.count)
            try addField(record.name.utf8.count)
            try addTimestamp()
            try add(record.sourceRootIdentity)
            try add(record.destinationDirectoryIdentity)
            try add(tree: record.backupTree)
            try addField(provenance.keyIdentifier.utf8.count)
            try addField(provenance.authenticationTag.count)
        }

        mutating func addPublishedProvenance(
            sourceBinding: BackupAuthenticatedSourceBinding,
            publicationName: String,
            sourceRootIdentity: BackupItemIdentity,
            destinationDirectoryIdentity: BackupItemIdentity,
            copiedTree: BackupTreeSnapshot
        ) throws {
            try addField(8)
            try addField(BackupAuthenticationFormat.identifierByteCount)
            try addField(sourceBinding.binding.sourceBindingIdentifier.count)
            try addField(sourceBinding.binding.seriesIdentifier.utf8.count)
            try addField(publicationName.utf8.count)
            try addTimestamp()
            try add(sourceRootIdentity)
            try add(destinationDirectoryIdentity.stableNodeIdentity)
            try add(
                tree: copiedTree,
                persistentVolumeIdentityByteCount: destinationDirectoryIdentity.persistentVolumeIdentity.bytes.count
            )
            try addField(BackupAuthenticationFormat.keyIdentifierMaximumUTF8Bytes)
            try addField(BackupAuthenticationFormat.authenticationTagByteCount)
        }

        mutating func addDeletionManifest(
            tree: BackupTreeSnapshot,
            rootNameByteCount: Int,
            rootParentIdentity: BackupStableNodeIdentity,
            persistentVolumeIdentityByteCount: Int? = nil
        ) throws {
            try addField(8)
            for (index, entry) in tree.descendants.enumerated() {
                if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                try addPresence()
                try addField(entry.relativePath.rawUTF8Bytes.count)
                try addPresence()
                if entry.relativePath.components.count > 1 {
                    try addField(
                        entry.relativePath.rawUTF8Bytes.count
                            - entry.relativePath.componentUTF8Bytes.last!.count - 1
                    )
                }
                try addField(entry.relativePath.componentUTF8Bytes.last!.count)
                try add(
                    entry.identity.stableNodeIdentity,
                    persistentVolumeIdentityByteCount: persistentVolumeIdentityByteCount
                )
                try add(
                    entry.identity,
                    persistentVolumeIdentityByteCount: persistentVolumeIdentityByteCount
                )
                try addField(8)
                try addPresence()
                if entry.identity.kind == .directory { try addField(8) }
            }
            try addPresence()
            try addPresence()
            try addField(rootNameByteCount)
            try add(
                rootParentIdentity,
                persistentVolumeIdentityByteCount: persistentVolumeIdentityByteCount
            )
            try add(
                tree.rootIdentity,
                persistentVolumeIdentityByteCount: persistentVolumeIdentityByteCount
            )
            try addField(8)
            try addPresence()
            if tree.rootIdentity.kind == .directory { try addField(8) }
        }

        mutating func addStagedConstructionManifest(_ tree: BackupTreeSnapshot) throws {
            try addField(8)
            for (index, entry) in tree.descendants.enumerated() {
                if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
                try addField(entry.relativePath.rawUTF8Bytes.count)
                try addPresence()
                if entry.relativePath.components.count > 1 {
                    try addField(
                        entry.relativePath.rawUTF8Bytes.count
                            - entry.relativePath.componentUTF8Bytes.last!.count - 1
                    )
                }
                try addField(entry.relativePath.componentUTF8Bytes.last!.count)
                try addField(entry.identity.kind.rawValue.utf8.count)
                try add(entry.identity.stableNodeIdentity)
            }
        }

        mutating func add(target: Target) throws {
            try addField(target.boundPath.relativePath.rawUTF8Bytes.count)
            try addField(8)
            for component in target.boundPath.components {
                try addField(component.nameUTF8Bytes.count)
                try add(component.expectedIdentity)
            }
            try addPresence()
            try addField(255)
            try addPresence()
            try add(target.provenanceRecord.provenance.destinationDirectoryIdentity)
            try add(target.provenanceRecord)
            try add(tree: target.tree)
            try addPresence()
            try add(tree: target.tree)
            try addDeletionManifest(
                tree: target.tree,
                rootNameByteCount: 255,
                rootParentIdentity: target.provenanceRecord.provenance.destinationDirectoryIdentity,
                persistentVolumeIdentityByteCount: target.tree.rootIdentity.persistentVolumeIdentity.bytes.count
            )
            try addField(8)
            try addPresence()
            try addField(8)
        }
    }
}

/// Decoder contract for untrusted journal files. Executor reads at most `maximumEncodedBytes` from a
/// descriptor in fixed-size chunks, incrementally authenticates bytes before constructing records,
/// rejects any field over `maximumAuthenticationFieldBytes`, validates array counts before
/// allocation, applies signed path/item/work/output limits while parsing, checks cancellation per
/// chunk, and accepts only bytes reproduced exactly by streaming canonical encoding.
public struct BackupTransactionJournalDecodingContract: Equatable, Hashable, Sendable {
    public let maximumEncodedBytes = BackupTransactionJournalFormat.maximumEncodedBytes
    public let maximumFieldBytes = BackupTransactionJournalFormat.maximumAuthenticationFieldBytes
    public let requiredReadChunkBytes = 64 * 1_024
    public let authenticationRequirement = "incremental-hmac-before-record-construction"
    public let canonicalityRequirement = "streaming-byte-for-byte-reencoding"

    public init() {}
}

/// Required transaction and recovery protocol. Journal and quarantine live on the destination
/// persistent volume in an executor-private directory opened from the pinned destination
/// descriptor. Journal authenticates that private container's stable identity and binds every
/// quarantine-root deletion manifest to it, never directly to destination parent. Before first mutation or publication, executor must prove available allocated
/// space and quota for plan `requiredJournalReservationBytes`, reserve it for two complete planned
/// records, and retain that reservation until committed anchor advancement and authenticated rollover. Every journal
/// replacement consumes one reserved slot while the prior durable record occupies the other; ENOSPC,
/// quota failure, unsupported reservation, or lost reservation fails before mutation/publication.
/// Authenticated journal carries same reservation size, so recovery re-establishes it before recovery
/// mutation. Every replacement uses `BackupTransactionJournalFormat`: exclusively write temporary record,
/// stream at most `maximumEncodedBytes`, sync temporary record, atomically replace journal, sync the
/// replacement record, then sync journal directory, atomically bind rollback anchor to replacement's
/// exact sequence and authentication tag, and only then perform its authorized mutation. Prior record
/// remains durable in second slot until anchor binds, so any semantic direct-successor gap recovers by
/// authenticating both records, validating exact transition, and advancing anchor first. Staging uses
/// unpredictable exclusive leaf. `.prepared` authenticates absent-name creation intent; recovery may
/// bind an observed empty root only under continuously held non-bypassable parent authority. Executor
/// immediately records durable `.stageIdentityBound` with exact stable root identity. Before each
/// descendant creation, it durably authenticates canonical source-derived parent/name/kind slot and
/// in-flight index; after creation it durably records exact destination stable identity before next
/// slot. Thus no descendant survives without authenticated ownership intent and progress. Root-only
/// state authorizes at most descriptor-enumerated empty-root removal. Before recursive stage deletion,
/// executor authenticates complete observed staged-tree identities
/// and exact parent/name bindings in postorder. It durably records one in-flight entry before unlink,
/// then durably advances monotonic prefix progress. Crash replay accepts absence only for that exact
/// authenticated parent/name and in-flight cursor, then anchors advanced progress before another
/// mutation. Injected descendants, missing non-in-flight entries, or identity drift fail closed. All
/// copied file data, metadata, provenance placeholders, and directories are synced bottom-up before
/// publication intent is journaled. Executor then samples monotonic and wall time, rejects backward
/// movement or excessive skew, and durably journals publication authorization time before rename.
/// It reauthorizes every publication condition immediately before same-volume no-replace rename,
/// with no intervening filesystem observation or mutation.
/// After rename it inventories the final tree, issues complete-tree provenance, syncs provenance and
/// published tree bottom-up, then syncs destination directory. Only then may publication be reported
/// durable. Unsupported primitives fail closed. Rename success followed by any uncertain sync or
/// journal result reports publication uncertainty, never pre-publication failure or durable success.
///
/// Retention runs under the same destination lock. Before quarantine, executor authenticates the
/// source capability and exact provenance-bound complete inventory, checks provenance
/// source/destination binding, requires exact equality with recomputed removal names, and
/// descriptor-walks every original tree. It then uses same-volume no-replace renames into unique
/// quarantine leaves while retaining root descriptors, records complete post-rename inventories,
/// and syncs both directories. Because rename can change root metadata, the journal authenticates
/// both fully validated pre-rename and complete post-rename trees. Before deletion executor again
/// pins each quarantine root, authenticates provenance, and compares the complete post-rename
/// no-follow tree. Recursive deletion is postorder with authenticated, durably recorded progress.
/// Recovery compares persistent volume/inode/generation identities across remount, while requiring
/// every fresh parent/node mount-local device to equal fresh opened root. It permits only directory metadata
/// changes caused by recorded child deletion and regular-file change-time mutation caused by a prior
/// authenticated hardlink unlink, and stops on any unmanifested node or other drift.
/// Recovery authenticates and exactly compares rollback anchor sequence and tag before removing a
/// stage, finishing deletion, restoring quarantine, or mutating any other filesystem state. Any durable
/// authenticated semantic direct successor may first atomically advance anchor after retained
/// predecessor proves exact payload transition and tag chain. Committed journal remains durable rollover predecessor until next
/// `.prepared` transaction (transaction sequence + 1, journal sequence zero, previous committed tag)
/// is durably replaced and atomically anchored; recovery accepts only same authenticated edge.
/// Quarantine restore runs under the anchored pre-commit record. After no-replace rename, executor
/// inventories the fresh restored tree, reissues and authenticates provenance over that exact tree,
/// then durably writes and anchors `.committed` before reporting recovery complete.
public struct BackupTransactionContract: Equatable, Hashable, Sendable {
    public static let requiredOrder = BackupTransactionPhase.allCases

    public let orderedPhases = Self.requiredOrder
    public let journalFormat = BackupTransactionJournalFormat()
    public let journalDecoding = BackupTransactionJournalDecodingContract()

    public init() {}
}

public enum BackupRecoveryContract: String, Equatable, Hashable, Sendable {
    /// Under destination lock, authenticate journal-owned records, pin recorded identities, remove
    /// an unpublished stage, preserve a durably published backup, finish quarantined deletion only
    /// under the authenticated deletion manifest, and otherwise restore intact quarantine by
    /// no-replace rename. Before any such mutation or deletion, authenticate the journal and compare
    /// its exact rollback-resistant journal sequence-and-tag anchor. `.prepared` has no bound stage
    /// identity and never authorizes deletion. `.stageIdentityBound` authorizes only empty-root
    /// removal. Recursive stage deletion requires complete authenticated per-entry identities,
    /// parent/name bindings, write-ahead in-flight cursor, and monotonic durable progress;
    /// postpublication records never authorize stage deletion. Partly
    /// deleted trees are never restored. Ambiguity,
    /// collision, authentication failure, or identity drift fails closed for operator recovery.
    /// Restore rename runs under the anchored quarantine record. Recovery journals the fresh restored
    /// tree and freshly authenticated provenance in a durable anchored `.committed` successor before
    /// discarding quarantine state or reporting completion.
    /// A publication-uncertain transaction must be recovered before another transaction: verify the
    /// authenticated journal and both stage/publication names under the lock. If rename is proven,
    /// preserve the published tree, issue/verify final complete-tree provenance as needed, finish
    /// required syncs, and report durable publication. If rename is proven not to have occurred,
    /// remove the stage and report no publication. Never repeat the rename or copy. Any inability to
    /// prove exactly one state remains publication-uncertain and requires operator recovery. Recovery
    /// may atomically advance any authenticated durable semantic direct successor over its exact
    /// retained predecessor before successor recovery; replay, skipped sequence, wrong tag, and any
    /// illegal state edge fail closed. Next prepared transaction may replace committed journal only through
    /// authenticated transaction-sequence + 1 rollover chained to committed tag and atomically anchored.
    case resumeAuthenticatedJournalBeforeNewTransaction
}

/// Non-negotiable executor behavior. Paths are display/audit data until their root is pinned and
/// every component is opened relative to descriptors with no-follow semantics. An executor must
/// fail closed for links, aliases, mount crossings, unsupported item kinds, identity changes,
/// metadata loss, destination collisions, incomplete synchronization, and uncertain outcomes.
/// It must also enforce the plan limits while traversing and count file data, resource forks,
/// extended attributes, and other copied metadata against `maximumOutputBytes`.
/// Root full identities are checked when descriptors are first pinned. Descriptors remain open for
/// the transaction; after executor mutations, persistent volume/inode/reliable-generation identity
/// and authenticated expected-mutation records replace impossible equality against pre-mutation
/// directory timestamps and sizes.
/// Destination lock coordinates conforming executors but cannot exclude hostile or unrelated writers.
/// Every rename/unlink therefore requires either continuously held, non-bypassable exclusive mutation
/// authority for exact parent or one atomic descriptor-relative identity-conditional primitive.
/// `renameat`/`unlinkat` after separate identity validation is insufficient and must fail planning or
/// execution. Same rule applies to staging descendants, quarantine descendants, and crash recovery.
public struct BackupExecutorContract: Equatable, Hashable, Sendable {
    public static let required = BackupExecutorContract()

    public let pathResolution = BackupPathResolutionContract.descriptorRelativeNoFollow
    public let parentMutation =
        BackupParentMutationContract.liveExclusiveCapabilityOrDescriptorRelativeIdentityConditionalMutation
    public let publication = BackupPublicationContract.stagedAndSyncedThenExclusiveDurablePublish
    public let sourceValidation = BackupSourceValidationContract.completeTreeIdentityBeforeAndAfterCopy
    public let metadata = BackupMetadataContract.preserveAndVerifyEveryRequirement
    public let retention = BackupRetentionContract.authenticatedCapabilityQuarantineAndRevalidate
    public let cancellation = BackupCancellationContract.reportDurableOrUncertainOutcomeAfterRename
    public let trustedTime = BackupTrustedTimeContract()
    public let transaction = BackupTransactionContract()
    public let recovery = BackupRecoveryContract.resumeAuthenticatedJournalBeforeNewTransaction

    public init() {}
}

/// Deterministic instructions only. Constructing a plan performs no filesystem mutation and starts
/// no security-scoped access. Plans are intentionally not persistent authorization artifacts.
public struct BackupExecutionPlan: Equatable, Sendable {
    public let trigger: BackupTrigger
    public let sourceBinding: BackupAuthenticatedSourceBinding
    public let timestamp: BackupTimestamp
    public let contract: BackupExecutorContract
    public let parentMutationCapability: BackupParentMutationCapability
    public let steps: [BackupExecutionStep]
    public let retentionValidation: BackupRetentionValidation
    public let estimatedWorkUnits: UInt64
    public let expectedOutputBytes: UInt64
    /// Executor must make this journal capacity durable and exclusively reserved before mutation.
    public let requiredJournalReservationBytes: Int
    public let limits: BackupPlanningLimits

    fileprivate init(
        trigger: BackupTrigger,
        sourceBinding: BackupAuthenticatedSourceBinding,
        timestamp: BackupTimestamp,
        parentMutationCapability: BackupParentMutationCapability,
        steps: [BackupExecutionStep],
        retentionValidation: BackupRetentionValidation,
        estimatedWorkUnits: UInt64,
        expectedOutputBytes: UInt64,
        requiredJournalReservationBytes: Int,
        limits: BackupPlanningLimits
    ) {
        precondition(
            BackupTransactionJournalFormat.isValidReservationPlan(
                requiredBytes: requiredJournalReservationBytes
            )
        )
        self.trigger = trigger
        self.sourceBinding = sourceBinding
        self.timestamp = timestamp
        contract = .required
        self.parentMutationCapability = parentMutationCapability
        self.steps = steps
        self.retentionValidation = retentionValidation
        self.estimatedWorkUnits = estimatedWorkUnits
        self.expectedOutputBytes = expectedOutputBytes
        self.requiredJournalReservationBytes = requiredJournalReservationBytes
        self.limits = limits
    }
}

public struct BackupExecutionResult: Equatable, Sendable {
    public let backupURL: URL
    /// Targets whose quarantine trees were fully deleted and durably synced.
    public let removedBackupURLs: [URL]
    /// Targets moved to transaction quarantine but not yet durably deleted. Recovery owns them.
    public let pendingCleanupURLs: [URL]
    public let outputBytes: UInt64

    public init(
        backupURL: URL,
        removedBackupURLs: [URL],
        pendingCleanupURLs: [URL],
        outputBytes: UInt64
    ) {
        self.backupURL = backupURL
        self.removedBackupURLs = removedBackupURLs
        self.pendingCleanupURLs = pendingCleanupURLs
        self.outputBytes = outputBytes
    }
}

public enum BackupExecutionFailure: Equatable, Sendable {
    case beforePublication(reason: String)
    case afterPublication(
        backupURL: URL,
        removedBackupURLs: [URL],
        quarantinedBackupURLs: [URL],
        reason: String
    )
}

/// Rename may have succeeded, but durable publication could not be proven after a synchronization
/// or journal result became uncertain. `backupURL` is an audit location, not proof that an entry is
/// present or durable. Caller must report indeterminate status and run authenticated recovery under
/// the destination lock before retrying or starting another transaction.
public struct BackupPublicationUncertainty: Equatable, Sendable {
    public let backupURL: URL
    public let transactionIdentifier: [UInt8]
    public let reason: String

    public init(backupURL: URL, transactionIdentifier: [UInt8], reason: String) throws {
        guard transactionIdentifier.count == BackupAuthenticationFormat.identifierByteCount else {
            throw BackupPolicyError.invalidObservation("Uncertain publication transaction identifier has an invalid size.")
        }
        self.backupURL = backupURL
        self.transactionIdentifier = transactionIdentifier
        self.reason = reason
    }
}

public enum BackupExecutionOutcome: Equatable, Sendable {
    case completed(BackupExecutionResult)
    case failed(BackupExecutionFailure)
    case cancelled(BackupExecutionFailure)
    case publicationUncertain(BackupPublicationUncertainty)
}

/// Mutation boundary kept separate from `BackupPlanner`. Implementations must enforce
/// `BackupExecutorContract.required`; executing URL paths directly is nonconforming. Cancellation
/// before publication reports no `backupURL`. Cancellation or failure after durable publication
/// reports `.afterPublication`, physically deleted targets, and recoverable quarantined targets.
/// Rename success without proven tree and parent-directory durability reports
/// `.publicationUncertain`; cancellation cannot relabel this state. Recovery owns final resolution.
public protocol BackupPlanExecutor: Sendable {
    /// Executor rejects plan unless capability remains live and continuously held, or its semantics
    /// provide atomic descriptor-relative identity-conditional rename/unlink. Validate-then-name-swap
    /// mutation is nonconforming even while destination lock is held.
    func execute(_ plan: BackupExecutionPlan) async -> BackupExecutionOutcome
}

public enum BackupPolicyError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimit(name: String, value: String)
    case duplicateTrigger
    case invalidDestinationComponent(String)
    case invalidNamingSuffix(String)
    case invalidRetentionCount(Int)
    case invalidRetentionAge(UInt64)
    case invalidMetadataRequirements(UInt16)
    case persistenceDataTooLarge(maximumBytes: Int)
    case malformedPersistence
    case nonCanonicalPersistence
    case unsupportedSchemaVersion(Int)
    case invalidTimestampNanoseconds(UInt32)
    case invalidFileURL(String)
    case invalidRelativePath(String)
    case invalidSeriesIdentifier(String)
    case triggerDisabled(BackupTrigger)
    case invalidObservation(String)
    case unsupportedItem(path: String, kind: BackupItemKind)
    case volumeBoundaryNotAllowed(String)
    case securityScopedAccessRequired(String)
    case invalidSecurityScope(resource: String, target: String)
    case sourceDestinationOverlap(source: String, destination: String)
    case nameCandidatesIncomplete(expected: Int, actual: Int)
    case nameCandidateMismatch(expected: String, actual: String)
    case noAvailableName(maximumCandidates: Int)
    case pathTooLarge(path: String, maximumUTF8Bytes: Int)
    case totalPathsTooLarge(maximumUTF8Bytes: Int)
    case tooManySourceItems(maximum: Int)
    case tooManyExistingBackups(maximum: Int)
    case tooManyRetentionItems(maximum: Int)
    case outputTooLarge(maximumBytes: UInt64)
    case workLimitExceeded(maximumUnits: UInt64)
    case tooManyPlanSteps(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value):
            "Invalid backup limit \(name): \(value)."
        case .duplicateTrigger:
            "Backup policy contains a duplicate trigger."
        case .invalidDestinationComponent(let value):
            "Invalid backup destination directory name: \(value)."
        case .invalidNamingSuffix(let value):
            "Invalid backup naming suffix: \(value)."
        case .invalidRetentionCount(let value):
            "Invalid backup retention count: \(value)."
        case .invalidRetentionAge(let value):
            "Invalid backup retention age: \(value)."
        case .invalidMetadataRequirements(let value):
            "Invalid backup metadata requirement bits: \(value)."
        case .persistenceDataTooLarge(let maximumBytes):
            "Backup policy data exceeds the \(maximumBytes)-byte limit."
        case .malformedPersistence:
            "Backup policy data is malformed."
        case .nonCanonicalPersistence:
            "Backup policy data is not canonical."
        case .unsupportedSchemaVersion(let version):
            "Unsupported backup policy schema version: \(version)."
        case .invalidTimestampNanoseconds(let value):
            "Invalid backup timestamp nanoseconds: \(value)."
        case .invalidFileURL(let value):
            "Backup planning requires an absolute canonical local file URL: \(value)."
        case .invalidRelativePath(let value):
            "Invalid descriptor-relative backup path: \(value)."
        case .invalidSeriesIdentifier(let value):
            "Invalid backup series identifier: \(value)."
        case .triggerDisabled(let trigger):
            "Backup trigger is disabled: \(trigger.rawValue)."
        case .invalidObservation(let reason):
            "Invalid backup observation: \(reason)."
        case .unsupportedItem(let path, let kind):
            "Backup planning rejects \(kind.rawValue) items: \(path)."
        case .volumeBoundaryNotAllowed(let path):
            "Backup planning rejects a mounted-volume boundary: \(path)."
        case .securityScopedAccessRequired(let path):
            "Backup policy requires security-scoped access: \(path)."
        case .invalidSecurityScope(let resource, let target):
            "Security-scoped resource \(resource) does not cover backup target \(target)."
        case .sourceDestinationOverlap(let source, let destination):
            "Backup destination overlaps source. Source: \(source), destination: \(destination)."
        case .nameCandidatesIncomplete(let expected, let actual):
            "Backup candidate observation has \(actual) entries; \(expected) are required."
        case .nameCandidateMismatch(let expected, let actual):
            "Backup candidate mismatch. Expected \(expected), observed \(actual)."
        case .noAvailableName(let maximumCandidates):
            "No backup name is available within \(maximumCandidates) candidates."
        case .pathTooLarge(let path, let maximumUTF8Bytes):
            "Backup path exceeds the \(maximumUTF8Bytes)-byte limit: \(path)."
        case .totalPathsTooLarge(let maximumUTF8Bytes):
            "Backup paths exceed the \(maximumUTF8Bytes)-byte aggregate limit."
        case .tooManySourceItems(let maximum):
            "Backup source exceeds the \(maximum)-item limit."
        case .tooManyExistingBackups(let maximum):
            "Backup observation exceeds the \(maximum)-backup limit."
        case .tooManyRetentionItems(let maximum):
            "Backup retention observation exceeds the \(maximum)-item limit."
        case .outputTooLarge(let maximumBytes):
            "Backup output exceeds the \(maximumBytes)-byte limit."
        case .workLimitExceeded(let maximumUnits):
            "Backup plan exceeds the \(maximumUnits)-unit work limit."
        case .tooManyPlanSteps(let maximum):
            "Backup plan exceeds the \(maximum)-step limit."
        }
    }
}

/// Pure planner over caller-supplied, read-only observations.
public struct BackupPlanner: Sendable {
    public let policy: BackupPolicy

    public init(policy: BackupPolicy = .default) {
        self.policy = policy
    }

    public func candidateNames(for sourceURL: URL, at timestamp: BackupTimestamp) throws -> [String] {
        try Task.checkCancellation()
        guard try Self.isValidAbsoluteFileURL(sourceURL),
            sourceURL.path.utf8.count <= policy.limits.maximumPathUTF8Bytes
        else {
            throw BackupPolicyError.invalidFileURL(sourceURL.absoluteString)
        }
        let sourceName = Self.sourceLeafName(sourceURL)
        guard let sourceName else {
            throw BackupPolicyError.invalidFileURL(sourceURL.absoluteString)
        }
        let count = policy.collisionBehavior == .fail ? 1 : policy.limits.maximumNameCandidates
        guard UInt64(count) <= policy.limits.maximumEstimatedWorkUnits else {
            throw BackupPolicyError.workLimitExceeded(
                maximumUnits: policy.limits.maximumEstimatedWorkUnits
            )
        }
        var names: [String] = []
        names.reserveCapacity(count)
        var pathBudget = PathBudget(limits: policy.limits)
        try pathBudget.add(sourceURL.path)
        for index in 0..<count {
            try Task.checkCancellation()
            let name = try candidateName(sourceName: sourceName, timestamp: timestamp, index: index)
            try pathBudget.add(name)
            names.append(name)
        }
        return names
    }

    public func plan(_ request: BackupPlanningRequest) throws -> BackupExecutionPlan {
        try Task.checkCancellation()
        guard policy.enabledTriggers.contains(request.trigger) else {
            throw BackupPolicyError.triggerDisabled(request.trigger)
        }
        let sourceBinding = request.sourceBinding.binding
        try Self.validateSeriesIdentifier(sourceBinding.seriesIdentifier)
        let sourceURL = request.source.sourceURL.standardizedFileURL
        let sourceLeafName = Self.sourceLeafName(sourceURL)
        guard try Self.isValidAbsoluteFileURL(request.source.sourceURL),
            sourceLeafName != nil
        else {
            throw BackupPolicyError.invalidFileURL(request.source.sourceURL.absoluteString)
        }
        let expectedDestinationURL = try destinationDirectory(for: sourceURL)
        let destinationURL = request.destination.directoryURL.standardizedFileURL
        guard try Self.isValidAbsoluteFileURL(request.destination.directoryURL),
            destinationURL == expectedDestinationURL
        else {
            throw BackupPolicyError.invalidObservation("Destination directory does not match policy.")
        }
        if sourceURL.path != "/",
            request.source.tree.rootIdentity.kind == .directory,
            try Self.contains(destinationURL, within: sourceURL)
        {
            throw BackupPolicyError.sourceDestinationOverlap(
                source: sourceURL.path,
                destination: destinationURL.path
            )
        }

        if let parentIdentity = request.source.parentDirectoryIdentity,
            parentIdentity.kind != .directory
        {
            throw BackupPolicyError.invalidObservation("Source parent is not a directory.")
        }
        guard request.destination.directoryIdentity.kind == .directory else {
            throw BackupPolicyError.invalidObservation("Backup destination is not a directory.")
        }
        guard let parentMutationCapability = request.parentMutationCapability,
            parentMutationCapability.destinationDirectoryIdentity
                == request.destination.directoryIdentity.stableNodeIdentity
        else {
            throw BackupPolicyError.invalidObservation(
                "Backup planning requires live destination parent-mutation authority or identity-conditional semantics."
            )
        }
        if let parentIdentity = request.source.parentDirectoryIdentity,
            parentIdentity.device != request.source.tree.rootIdentity.device
                || parentIdentity.persistentVolumeIdentity
                    != request.source.tree.rootIdentity.persistentVolumeIdentity
        {
            throw BackupPolicyError.volumeBoundaryNotAllowed(sourceURL.path)
        }
        guard request.source.tree.metadataRequirements == policy.metadataRequirements else {
            throw BackupPolicyError.invalidObservation("Source tree does not cover required backup metadata.")
        }
        guard sourceBinding.schemaVersion == BackupSourceBinding.currentSchemaVersion,
            sourceBinding.sourceRootIdentity == request.source.tree.rootIdentity.stableNodeIdentity,
            sourceBinding.destinationDirectoryIdentity
                == request.destination.directoryIdentity.stableNodeIdentity
        else {
            throw BackupPolicyError.invalidObservation(
                "Authenticated source binding does not match source and destination identities."
            )
        }
        if sourceURL.deletingLastPathComponent() == destinationURL,
            let parentIdentity = request.source.parentDirectoryIdentity,
            parentIdentity != request.destination.directoryIdentity
        {
            throw BackupPolicyError.invalidObservation("Shared source and destination directory identities differ.")
        }
        if let parentIdentity = request.source.parentDirectoryIdentity,
            Self.sameNode(parentIdentity, request.destination.directoryIdentity),
            parentIdentity != request.destination.directoryIdentity
        {
            throw BackupPolicyError.invalidObservation("Aliased source and destination directory identities differ.")
        }
        try validateAccess(
            request.source.accessRequirement,
            target: sourceURL
        )
        try validateAccess(
            request.destination.accessRequirement,
            target: destinationURL
        )

        var pathBudget = PathBudget(limits: policy.limits)
        var workBudget = WorkBudget(limits: policy.limits)
        try pathBudget.add(sourceURL.path)
        try pathBudget.add(destinationURL.path)
        try addAccessPath(request.source.accessRequirement, to: &pathBudget)
        try addAccessPath(request.destination.accessRequirement, to: &pathBudget)

        try workBudget.add(1 + request.source.tree.descendants.count, passes: 4)
        let sourceTree = try validateTree(
            request.source.tree,
            rootDisplayPath: sourceURL.path,
            requiredDevice: request.source.tree.rootIdentity.device,
            requiredPersistentVolumeIdentity: request.source.tree.rootIdentity.persistentVolumeIdentity,
            maximumItems: policy.limits.maximumSourceItemCount,
            tooMany: BackupPolicyError.tooManySourceItems(maximum: policy.limits.maximumSourceItemCount),
            pathBudget: &pathBudget,
            workBudget: &workBudget
        )
        var destinationOverlapsSource = Self.sameNode(
            sourceTree.rootIdentity,
            request.destination.directoryIdentity
        )
        for entry in sourceTree.descendants where !destinationOverlapsSource {
            try Task.checkCancellation()
            destinationOverlapsSource = Self.sameNode(
                entry.identity,
                request.destination.directoryIdentity
            )
        }
        if destinationOverlapsSource {
            throw BackupPolicyError.sourceDestinationOverlap(
                source: sourceURL.path,
                destination: destinationURL.path
            )
        }
        let expectedNames = try candidateNames(for: sourceURL, at: request.timestamp)
        try workBudget.add(expectedNames.count, passes: 3)
        guard request.destination.nameCandidates.count == expectedNames.count else {
            throw BackupPolicyError.nameCandidatesIncomplete(
                expected: expectedNames.count,
                actual: request.destination.nameCandidates.count
            )
        }
        var selectedName: String?
        var candidateOccupancy: [[UInt8]: Bool] = [:]
        candidateOccupancy.reserveCapacity(expectedNames.count)
        for pair in zip(expectedNames, request.destination.nameCandidates) {
            try Task.checkCancellation()
            let (expected, observed) = pair
            guard expected.utf8.elementsEqual(observed.name.utf8) else {
                throw BackupPolicyError.nameCandidateMismatch(expected: expected, actual: observed.name)
            }
            try pathBudget.add(Self.destinationPath(directory: destinationURL, name: observed.name))
            candidateOccupancy[Array(observed.name.utf8)] = observed.isOccupied
            if selectedName == nil, !observed.isOccupied {
                selectedName = observed.name
            }
        }
        guard let selectedName else {
            throw BackupPolicyError.noAvailableName(maximumCandidates: expectedNames.count)
        }

        guard request.destination.managedBackups.count <= policy.limits.maximumExistingBackupCount else {
            throw BackupPolicyError.tooManyExistingBackups(
                maximum: policy.limits.maximumExistingBackupCount
            )
        }
        var existingNames: Set<[UInt8]> = []
        var canonicalBackups: [BackupExistingBackup] = []
        canonicalBackups.reserveCapacity(request.destination.managedBackups.count)
        var retentionItemCount = 0
        var previousBackup: BackupExistingBackup?
        for backup in request.destination.managedBackups {
            try Task.checkCancellation()
            try workBudget.add(1 + backup.tree.descendants.count, passes: 5)
            try Self.validateSeriesIdentifier(backup.seriesIdentifier)
            guard Self.isValidLeafName(backup.name), backup.name.utf8.count <= 255 else {
                throw BackupPolicyError.invalidObservation("Managed backup has an invalid name.")
            }
            if let previousBackup, !Self.oldestFirst(previousBackup, backup) {
                throw BackupPolicyError.invalidObservation("Managed backups are not in canonical order.")
            }
            previousBackup = backup
            guard backup.provenanceRecord.provenance.schemaVersion == BackupProvenance.currentSchemaVersion,
                backup.provenanceRecord.provenance.destinationDirectoryIdentity
                    == request.destination.directoryIdentity.stableNodeIdentity,
                backup.tree.metadataRequirements == policy.metadataRequirements,
                try backup.tree.matchesAuthenticatedProvenanceTree(
                    backup.provenanceRecord.provenance.backupTree
                )
            else {
                throw BackupPolicyError.invalidObservation("Managed backup provenance does not match its tree.")
            }
            guard existingNames.insert(Array(backup.name.utf8)).inserted else {
                throw BackupPolicyError.invalidObservation("Managed backup names are duplicated.")
            }
            try pathBudget.add(Self.destinationPath(directory: destinationURL, name: backup.name))
            let remainingItems = policy.limits.maximumRetentionItemCount - retentionItemCount
            guard remainingItems > 0 else {
                throw BackupPolicyError.tooManyRetentionItems(
                    maximum: policy.limits.maximumRetentionItemCount
                )
            }
            let tree = try validateTree(
                backup.tree,
                rootDisplayPath: Self.destinationPath(directory: destinationURL, name: backup.name),
                requiredDevice: request.destination.directoryIdentity.device,
                requiredPersistentVolumeIdentity: request.destination.directoryIdentity.persistentVolumeIdentity,
                enforceOutputLimit: false,
                maximumItems: remainingItems,
                tooMany: BackupPolicyError.tooManyRetentionItems(
                    maximum: policy.limits.maximumRetentionItemCount
                ),
                pathBudget: &pathBudget,
                workBudget: &workBudget
            )
            retentionItemCount += 1 + tree.descendants.count
            canonicalBackups.append(
                try BackupExistingBackup(
                    boundPath: backup.boundPath,
                    provenanceRecord: backup.provenanceRecord,
                    tree: tree
                )
            )
        }
        guard !existingNames.contains(Array(selectedName.utf8)),
            request.destination.managedBackups.allSatisfy({
                candidateOccupancy[Array($0.name.utf8)] != false
            })
        else {
            throw BackupPolicyError.invalidObservation("A managed backup was observed as an available name.")
        }

        let outputBytes = try contentBytes(in: sourceTree)
        guard outputBytes <= policy.limits.maximumOutputBytes else {
            throw BackupPolicyError.outputTooLarge(maximumBytes: policy.limits.maximumOutputBytes)
        }
        try validateDestinationExpandedPaths(
            tree: sourceTree,
            destinationDirectory: destinationURL,
            destinationName: selectedName,
            pathBudget: &pathBudget,
            workBudget: &workBudget
        )
        let removals = try retentionRemovals(
            from: canonicalBackups,
            sourceBindingIdentifier: sourceBinding.sourceBindingIdentifier,
            seriesIdentifier: sourceBinding.seriesIdentifier,
            now: request.timestamp
        )
        for removal in removals {
            try Task.checkCancellation()
            let provenance = removal.provenanceRecord.provenance
            guard provenance.sourceBindingIdentifier == sourceBinding.sourceBindingIdentifier,
                provenance.seriesIdentifier == sourceBinding.seriesIdentifier,
                provenance.sourceRootIdentity.stableNodeIdentity == sourceBinding.sourceRootIdentity,
                provenance.destinationDirectoryIdentity
                    == request.destination.directoryIdentity.stableNodeIdentity,
                sourceBinding.provenanceNotBefore <= provenance.createdAt,
                provenance.createdAt < sourceBinding.expiresAt,
                provenance.createdAt <= request.timestamp
            else {
                throw BackupPolicyError.invalidObservation(
                    "Removal target provenance does not match its capability, series, identities, or time."
                )
            }
            var removalContainsSource = Self.sameNode(
                removal.tree.rootIdentity,
                sourceTree.rootIdentity
            )
            for entry in removal.tree.descendants where !removalContainsSource {
                try Task.checkCancellation()
                removalContainsSource = Self.sameNode(entry.identity, sourceTree.rootIdentity)
            }
            if removalContainsSource {
                throw BackupPolicyError.sourceDestinationOverlap(
                    source: sourceURL.path,
                    destination: Self.destinationPath(directory: destinationURL, name: removal.name)
                )
            }
        }
        guard removals.count <= policy.limits.maximumPlanStepCount - 1 else {
            throw BackupPolicyError.tooManyPlanSteps(maximum: policy.limits.maximumPlanStepCount)
        }
        let requiredJournalReservationBytes = try validateMaximumJournalSize(
            sourceTree: sourceTree,
            selectedName: selectedName,
            sourceBinding: request.sourceBinding,
            destinationDirectoryIdentity: request.destination.directoryIdentity,
            retentionTargets: removals
        )
        try workBudget.add(1 + removals.count, passes: 1)

        let sourceLocation: BackupDescriptorLocation
        switch request.source.accessRequirement {
        case .declaredAmbientAccess:
            if sourceURL.path == "/" {
                sourceLocation = BackupDescriptorLocation(
                    root: BackupDescriptorRoot(
                        url: sourceURL,
                        expectedIdentity: sourceTree.rootIdentity,
                        accessRequirement: request.source.accessRequirement
                    ),
                    path: .root
                )
            } else {
                guard let sourceLeafName else {
                    throw BackupPolicyError.invalidFileURL(sourceURL.absoluteString)
                }
                guard let parentIdentity = request.source.parentDirectoryIdentity else {
                    throw BackupPolicyError.invalidObservation("Ambient source access requires parent identity.")
                }
                let sourceRoot = BackupDescriptorRoot(
                    url: sourceURL.deletingLastPathComponent(),
                    expectedIdentity: parentIdentity,
                    accessRequirement: request.source.accessRequirement
                )
                sourceLocation = BackupDescriptorLocation(
                    root: sourceRoot,
                    path: .boundExisting(
                        try BackupBoundRelativePath(
                            relativePath: BackupRelativePath(sourceLeafName),
                            components: [
                                BackupBoundPathComponent(
                                    name: sourceLeafName,
                                    expectedIdentity: sourceTree.rootIdentity
                                )
                            ]
                        )
                    )
                )
            }
        case .securityScoped(let resourceURL):
            let resource = resourceURL.standardizedFileURL
            if resource == sourceURL {
                let sourceRoot = BackupDescriptorRoot(
                    url: sourceURL,
                    expectedIdentity: sourceTree.rootIdentity,
                    accessRequirement: request.source.accessRequirement
                )
                sourceLocation = BackupDescriptorLocation(root: sourceRoot, path: .root)
            } else {
                guard sourceURL.path != "/", let sourceLeafName else {
                    throw BackupPolicyError.invalidSecurityScope(
                        resource: resource.path,
                        target: sourceURL.path
                    )
                }
                let sourceParent = sourceURL.deletingLastPathComponent()
                guard try Self.contains(sourceParent, within: resource) else {
                    throw BackupPolicyError.invalidSecurityScope(
                        resource: resource.path,
                        target: sourceParent.path
                    )
                }
                guard let parentIdentity = request.source.parentDirectoryIdentity else {
                    throw BackupPolicyError.invalidObservation("Ancestor source scope requires parent identity.")
                }
                let sourceRoot = BackupDescriptorRoot(
                    url: sourceParent,
                    expectedIdentity: parentIdentity,
                    accessRequirement: request.source.accessRequirement
                )
                sourceLocation = BackupDescriptorLocation(
                    root: sourceRoot,
                    path: .boundExisting(
                        try BackupBoundRelativePath(
                            relativePath: BackupRelativePath(sourceLeafName),
                            components: [
                                BackupBoundPathComponent(
                                    name: sourceLeafName,
                                    expectedIdentity: sourceTree.rootIdentity
                                )
                            ]
                        )
                    )
                )
            }
        }
        let destinationRoot = BackupDescriptorRoot(
            url: destinationURL,
            expectedIdentity: request.destination.directoryIdentity,
            accessRequirement: request.destination.accessRequirement
        )
        let destinationPath = try BackupRelativePath(selectedName)
        var steps: [BackupExecutionStep] = [
            .createBackup(
                BackupCopyInstruction(
                    source: sourceLocation,
                    destination: BackupDescriptorLocation(root: destinationRoot, path: .newLeaf(destinationPath)),
                    expectedSourceTree: sourceTree,
                    metadataRequirements: policy.metadataRequirements,
                    expectedOutputBytes: outputBytes,
                    provenanceRequest: BackupProvenanceRequest(
                        sourceBinding: request.sourceBinding,
                        name: selectedName,
                        sourceRootIdentity: sourceTree.rootIdentity,
                        destinationDirectoryIdentity: request.destination.directoryIdentity.stableNodeIdentity
                    )
                )
            )
        ]
        steps.reserveCapacity(1 + removals.count)
        for removal in removals {
            try Task.checkCancellation()
            steps.append(
                .removeRetainedBackup(
                    try BackupRemovalInstruction(
                        target: BackupDescriptorLocation(
                            root: destinationRoot,
                            path: .boundExisting(removal.boundPath)
                        ),
                        expectedTree: removal.tree,
                        expectedProvenance: removal.provenanceRecord,
                        sourceBinding: request.sourceBinding
                    )
                )
            )
        }

        return BackupExecutionPlan(
            trigger: request.trigger,
            sourceBinding: request.sourceBinding,
            timestamp: request.timestamp,
            parentMutationCapability: parentMutationCapability,
            steps: steps,
            retentionValidation: BackupRetentionValidation(
                sourceBinding: request.sourceBinding,
                existingBackups: canonicalBackups,
                retentionPolicy: policy.retention,
                plannedRemovalNames: removals.map(\.name)
            ),
            estimatedWorkUnits: workBudget.total,
            expectedOutputBytes: outputBytes,
            requiredJournalReservationBytes: requiredJournalReservationBytes,
            limits: policy.limits
        )
    }
}

extension BackupPlanner {
    fileprivate static func isValidLeafName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.utf8.contains(0)
    }

    fileprivate static func isValidAbsoluteFileURL(_ url: URL) throws -> Bool {
        let pathUTF8 = url.path.utf8
        guard !pathUTF8.isEmpty,
            pathUTF8.count <= BackupPlanningLimits.hardMaximumPathUTF8Bytes,
            pathUTF8.first == 0x2F
        else {
            return false
        }
        var componentByteCount = 0
        var componentCount = 0
        for (index, byte) in pathUTF8.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard byte != 0 else { return false }
            if byte == 0x2F {
                if componentByteCount > 0 {
                    componentCount += 1
                    componentByteCount = 0
                } else if index != 0 {
                    return false
                }
            } else {
                componentByteCount += 1
                guard componentByteCount <= 255 else { return false }
            }
        }
        if componentByteCount > 0 { componentCount += 1 }
        try Task.checkCancellation()
        let pathBytes = Array(pathUTF8)
        let fileSystemBytes = url.withUnsafeFileSystemRepresentation { pointer -> [UInt8]? in
            guard let pointer else { return nil }
            var bytes: [UInt8] = []
            bytes.reserveCapacity(pathBytes.count)
            for index in 0...BackupPlanningLimits.hardMaximumPathUTF8Bytes {
                let byte = UInt8(bitPattern: pointer[index])
                if byte == 0 { return bytes }
                bytes.append(byte)
            }
            return nil
        }
        guard url.isFileURL,
            url.baseURL == nil,
            url.query == nil,
            url.fragment == nil,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "file",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.host?.isEmpty != false
                || components.host?.caseInsensitiveCompare("localhost") == .orderedSame,
            fileSystemBytes == pathBytes,
            url.path == url.standardizedFileURL.path,
            pathBytes == [0x2F] || componentCount > 0
        else {
            return false
        }
        return true
    }

    private func destinationDirectory(for sourceURL: URL) throws -> URL {
        let destination: URL
        switch policy.destination {
        case .alongsideSource:
            destination = sourceURL.deletingLastPathComponent()
        case .sourceParentSubdirectory(let name):
            destination = sourceURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        case .customDirectory(let url):
            destination = url
        }
        let standardized = destination.standardizedFileURL
        guard try Self.isValidAbsoluteFileURL(standardized),
            standardized.path.utf8.count <= policy.limits.maximumPathUTF8Bytes
        else {
            throw BackupPolicyError.invalidFileURL(destination.absoluteString)
        }
        return standardized
    }

    private func candidateName(
        sourceName: String,
        timestamp: BackupTimestamp,
        index: Int
    ) throws -> String {
        let base: String
        switch policy.naming.style {
        case .suffixOnly:
            base = sourceName + policy.naming.suffix
        case .suffixAndTimestamp:
            let nanoseconds = String(timestamp.nanoseconds)
            let padding = String(repeating: "0", count: 9 - nanoseconds.count)
            base =
                sourceName + policy.naming.suffix + "."
                + String(timestamp.secondsSince1970) + "." + padding + nanoseconds
        }
        let name = index == 0 ? base : base + "." + String(index)
        guard Self.isValidLeafName(name), name.utf8.count <= 255 else {
            throw BackupPolicyError.pathTooLarge(
                path: name,
                maximumUTF8Bytes: min(255, policy.limits.maximumPathUTF8Bytes)
            )
        }
        return name
    }

    private func validateAccess(_ access: BackupAccessRequirement, target: URL) throws {
        switch access {
        case .declaredAmbientAccess:
            guard policy.sandboxAccessPolicy == .allowDeclaredAmbientAccess else {
                throw BackupPolicyError.securityScopedAccessRequired(target.path)
            }
        case .securityScoped(let resourceURL):
            let resource = resourceURL.standardizedFileURL
            guard try Self.isValidAbsoluteFileURL(resourceURL),
                try Self.contains(target, within: resource)
            else {
                throw BackupPolicyError.invalidSecurityScope(
                    resource: resourceURL.path,
                    target: target.path
                )
            }
        }
    }

    private func addAccessPath(
        _ access: BackupAccessRequirement,
        to budget: inout PathBudget
    ) throws {
        if case .securityScoped(let resourceURL) = access {
            try budget.add(resourceURL.path)
        }
    }

    private func validateTree(
        _ tree: BackupTreeSnapshot,
        rootDisplayPath: String,
        requiredDevice: UInt64,
        requiredPersistentVolumeIdentity: BackupPersistentVolumeIdentity,
        enforceOutputLimit: Bool = true,
        maximumItems: Int,
        tooMany: BackupPolicyError,
        pathBudget: inout PathBudget,
        workBudget: inout WorkBudget
    ) throws -> BackupTreeSnapshot {
        guard maximumItems > 0, tree.descendants.count <= maximumItems - 1 else {
            throw tooMany
        }
        try tree.validateCanonicalCompleteInventory()
        guard tree.rootIdentity.kind.isSupported else {
            throw BackupPolicyError.unsupportedItem(
                path: rootDisplayPath,
                kind: tree.rootIdentity.kind
            )
        }
        try validateByteCharge(
            tree.rootIdentity,
            path: rootDisplayPath,
            enforceOutputLimit: enforceOutputLimit
        )
        guard tree.rootIdentity.device == requiredDevice,
            tree.rootIdentity.persistentVolumeIdentity == requiredPersistentVolumeIdentity
        else {
            throw BackupPolicyError.volumeBoundaryNotAllowed(rootDisplayPath)
        }
        if tree.rootIdentity.kind == .regularFile, !tree.descendants.isEmpty {
            throw BackupPolicyError.invalidObservation("Regular-file tree has descendants.")
        }

        let entries = tree.descendants
        var byComponents: [[[UInt8]]: BackupItemKind] = [:]
        byComponents.reserveCapacity(entries.count)
        var previousPathBytes: [UInt8]?
        for entry in entries {
            try Task.checkCancellation()
            let path = entry.relativePath.rawValue
            try pathBudget.add(path)
            if let previousPathBytes,
                !previousPathBytes.lexicographicallyPrecedes(entry.relativePath.rawUTF8Bytes)
            {
                throw BackupPolicyError.invalidObservation("Tree paths are not in canonical order.")
            }
            previousPathBytes = entry.relativePath.rawUTF8Bytes
            try workBudget.add(entry.relativePath.components.count, passes: 1)
            guard entry.identity.kind.isSupported else {
                throw BackupPolicyError.unsupportedItem(
                    path: rootDisplayPath + "/" + path,
                    kind: entry.identity.kind
                )
            }
            try validateByteCharge(
                entry.identity,
                path: rootDisplayPath + "/" + path,
                enforceOutputLimit: enforceOutputLimit
            )
            guard entry.identity.device == requiredDevice,
                entry.identity.persistentVolumeIdentity == requiredPersistentVolumeIdentity
            else {
                throw BackupPolicyError.volumeBoundaryNotAllowed(rootDisplayPath + "/" + path)
            }
            let components = entry.relativePath.componentUTF8Bytes
            if components.count > 1 {
                try Task.checkCancellation()
                let parent = Array(components.dropLast())
                guard byComponents[parent] == .directory else {
                    throw BackupPolicyError.invalidObservation(
                        "Tree entry parent is missing or not a directory: \(path)."
                    )
                }
            }
            guard byComponents.updateValue(entry.identity.kind, forKey: components) == nil else {
                throw BackupPolicyError.invalidObservation("Tree paths are duplicated.")
            }
            let fullPathByteCount = rootDisplayPath.utf8.count + 1 + path.utf8.count
            guard fullPathByteCount <= policy.limits.maximumPathUTF8Bytes else {
                throw BackupPolicyError.pathTooLarge(
                    path: rootDisplayPath + "/" + path,
                    maximumUTF8Bytes: policy.limits.maximumPathUTF8Bytes
                )
            }
        }
        return BackupTreeSnapshot(
            rootIdentity: tree.rootIdentity,
            metadataRequirements: tree.metadataRequirements,
            descendants: entries
        )
    }

    private func contentBytes(in tree: BackupTreeSnapshot) throws -> UInt64 {
        var chargedRegularFiles: Set<BackupStableNodeIdentity> = []
        var total: UInt64 = 0
        func shouldCharge(_ identity: BackupItemIdentity) -> Bool {
            identity.kind != .regularFile
                || chargedRegularFiles.insert(identity.stableNodeIdentity).inserted
        }
        if shouldCharge(tree.rootIdentity) { total = tree.rootIdentity.outputByteCharge }
        for entry in tree.descendants {
            try Task.checkCancellation()
            guard shouldCharge(entry.identity) else { continue }
            let (next, overflow) = total.addingReportingOverflow(entry.identity.outputByteCharge)
            guard !overflow, next <= policy.limits.maximumOutputBytes else {
                throw BackupPolicyError.outputTooLarge(maximumBytes: policy.limits.maximumOutputBytes)
            }
            total = next
        }
        return total
    }

    private func validateMaximumJournalSize(
        sourceTree: BackupTreeSnapshot,
        selectedName: String,
        sourceBinding: BackupAuthenticatedSourceBinding,
        destinationDirectoryIdentity: BackupItemIdentity,
        retentionTargets: [BackupExistingBackup]
    ) throws -> Int {
        try BackupJournalSizePreflight.validate(
            sourceTree: sourceTree,
            publicationName: selectedName,
            sourceBinding: sourceBinding,
            destinationDirectoryIdentity: destinationDirectoryIdentity,
            retentionPolicy: policy.retention,
            retentionTargets: retentionTargets
        )
    }

    private func validateDestinationExpandedPaths(
        tree: BackupTreeSnapshot,
        destinationDirectory: URL,
        destinationName: String,
        pathBudget: inout PathBudget,
        workBudget: inout WorkBudget
    ) throws {
        let rootPath = Self.destinationPath(directory: destinationDirectory, name: destinationName)
        try pathBudget.add(rootPath)
        for entry in tree.descendants {
            try Task.checkCancellation()
            try workBudget.add(1, passes: 1)
            let count = rootPath.utf8.count + 1 + entry.relativePath.rawValue.utf8.count
            guard count <= policy.limits.maximumPathUTF8Bytes else {
                throw BackupPolicyError.pathTooLarge(
                    path: rootPath + "/" + entry.relativePath.rawValue,
                    maximumUTF8Bytes: policy.limits.maximumPathUTF8Bytes
                )
            }
            try pathBudget.add(entry.relativePath.rawValue)
        }
    }

    private func validateByteCharge(
        _ identity: BackupItemIdentity,
        path: String,
        enforceOutputLimit: Bool
    ) throws {
        guard identity.kind != .regularFile || identity.outputByteCharge >= identity.size else {
            throw BackupPolicyError.invalidObservation("Output byte charge is smaller than file data: \(path).")
        }
        guard !enforceOutputLimit || identity.outputByteCharge <= policy.limits.maximumOutputBytes else {
            throw BackupPolicyError.outputTooLarge(maximumBytes: policy.limits.maximumOutputBytes)
        }
    }

    private func retentionRemovals(
        from backups: [BackupExistingBackup],
        sourceBindingIdentifier: [UInt8],
        seriesIdentifier: String,
        now: BackupTimestamp
    ) throws -> [BackupExistingBackup] {
        var series: [BackupExistingBackup] = []
        series.reserveCapacity(backups.count)
        for backup in backups {
            try Task.checkCancellation()
            if backup.seriesIdentifier == seriesIdentifier,
                backup.provenanceRecord.provenance.sourceBindingIdentifier == sourceBindingIdentifier
            {
                series.append(backup)
            }
        }
        var removedNames: Set<[UInt8]> = []
        if let maximumAgeSeconds = policy.retention.maximumAgeSeconds {
            for backup in series {
                try Task.checkCancellation()
                if Self.age(of: backup.createdAt, at: now, exceeds: maximumAgeSeconds) {
                    removedNames.insert(Array(backup.name.utf8))
                }
            }
        }
        if let maximumCount = policy.retention.maximumCount {
            let keepExistingCount = maximumCount - 1
            var ageSurvivors: [BackupExistingBackup] = []
            ageSurvivors.reserveCapacity(series.count)
            for backup in series {
                try Task.checkCancellation()
                if !removedNames.contains(Array(backup.name.utf8)) { ageSurvivors.append(backup) }
            }
            if ageSurvivors.count > keepExistingCount {
                for backup in ageSurvivors.prefix(ageSurvivors.count - keepExistingCount) {
                    try Task.checkCancellation()
                    removedNames.insert(Array(backup.name.utf8))
                }
            }
        }
        var removals: [BackupExistingBackup] = []
        removals.reserveCapacity(removedNames.count)
        for backup in series {
            try Task.checkCancellation()
            if removedNames.contains(Array(backup.name.utf8)) { removals.append(backup) }
        }
        return removals
    }

    fileprivate static func validateSeriesIdentifier(_ identifier: String) throws {
        guard !identifier.isEmpty, identifier.utf8.count <= 128 else {
            throw BackupPolicyError.invalidSeriesIdentifier(identifier)
        }
        let bytes = Array(identifier.utf8)
        guard
            bytes.allSatisfy({ byte in
                (0x30...0x39).contains(byte)
                    || (0x41...0x5A).contains(byte)
                    || (0x61...0x7A).contains(byte)
                    || byte == 0x2D
                    || byte == 0x2E
                    || byte == 0x5F
            })
        else {
            throw BackupPolicyError.invalidSeriesIdentifier(identifier)
        }
    }

    private static func contains(_ target: URL, within root: URL) throws -> Bool {
        try Task.checkCancellation()
        let targetComponents = target.standardizedFileURL.path.utf8.split(
            separator: 0x2F,
            omittingEmptySubsequences: true
        )
        let rootComponents = root.standardizedFileURL.path.utf8.split(
            separator: 0x2F,
            omittingEmptySubsequences: true
        )
        guard rootComponents.count <= targetComponents.count else { return false }
        return zip(rootComponents, targetComponents).allSatisfy { root, target in
            root.elementsEqual(target)
        }
    }

    private static func sourceLeafName(_ sourceURL: URL) -> String? {
        if sourceURL.path == "/" { return "root" }
        let name = sourceURL.lastPathComponent
        return isValidLeafName(name) ? name : nil
    }

    private static func sameNode(_ lhs: BackupItemIdentity, _ rhs: BackupItemIdentity) -> Bool {
        lhs.persistentVolumeIdentity == rhs.persistentVolumeIdentity
            && lhs.inode == rhs.inode
            && lhs.generation == rhs.generation
    }

    private static func destinationPath(directory: URL, name: String) -> String {
        directory.path == "/" ? "/" + name : directory.path + "/" + name
    }

    private static func age(
        of timestamp: BackupTimestamp,
        at now: BackupTimestamp,
        exceeds maximumSeconds: UInt64
    ) -> Bool {
        guard timestamp < now else { return false }
        let biasedTimestamp = UInt64(bitPattern: timestamp.secondsSince1970) ^ (1 << 63)
        let biasedNow = UInt64(bitPattern: now.secondsSince1970) ^ (1 << 63)
        let seconds = biasedNow - biasedTimestamp
        if seconds != maximumSeconds { return seconds > maximumSeconds }
        return now.nanoseconds > timestamp.nanoseconds
    }

    private static func oldestFirst(_ lhs: BackupExistingBackup, _ rhs: BackupExistingBackup) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.name.utf8.lexicographicallyPrecedes(rhs.name.utf8)
    }

    private struct PathBudget {
        let limits: BackupPlanningLimits
        var total = 0

        mutating func add(_ path: String) throws {
            let count = path.utf8.count
            guard count <= limits.maximumPathUTF8Bytes else {
                throw BackupPolicyError.pathTooLarge(
                    path: path,
                    maximumUTF8Bytes: limits.maximumPathUTF8Bytes
                )
            }
            guard count <= limits.maximumTotalPathUTF8Bytes - total else {
                throw BackupPolicyError.totalPathsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalPathUTF8Bytes
                )
            }
            total += count
        }
    }

    private struct WorkBudget {
        let limits: BackupPlanningLimits
        var total: UInt64 = 0

        mutating func add(_ count: Int, passes: UInt64) throws {
            let (value, multiplicationOverflow) = UInt64(count).multipliedReportingOverflow(by: passes)
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !multiplicationOverflow,
                !overflow,
                next <= limits.maximumEstimatedWorkUnits
            else {
                throw BackupPolicyError.workLimitExceeded(
                    maximumUnits: limits.maximumEstimatedWorkUnits
                )
            }
            total = next
        }
    }
}

extension BackupTrigger {
    fileprivate var sortOrder: Int {
        switch self {
        case .beforeSave: 0
        case .beforeFileOperation: 1
        }
    }
}

private enum BackupCanonicalAuthenticationEncoder {
    static func validateKeyIdentifier(_ keyIdentifier: String) throws {
        let bytes = Array(keyIdentifier.utf8)
        guard !bytes.isEmpty,
            bytes.count <= BackupAuthenticationFormat.keyIdentifierMaximumUTF8Bytes,
            bytes.allSatisfy({ byte in
                (0x30...0x39).contains(byte)
                    || (0x41...0x5A).contains(byte)
                    || (0x61...0x7A).contains(byte)
                    || byte == 0x2D
                    || byte == 0x2E
                    || byte == 0x5F
            })
        else {
            throw BackupPolicyError.invalidObservation("Backup authentication key identifier is invalid.")
        }
    }

    static func sourceBinding(
        _ binding: BackupSourceBinding,
        keyIdentifier: String
    ) throws -> Data {
        try validateKeyIdentifier(keyIdentifier)
        var writer = Writer(domain: BackupAuthenticationFormat.sourceBindingDomain)
        writer.field(keyIdentifier)
        writer.field(binding.schemaVersion)
        writer.field(binding.sourceBindingIdentifier)
        writer.field(binding.seriesIdentifier)
        writer.field(binding.sourceRootIdentity)
        writer.field(binding.destinationDirectoryIdentity)
        writer.field(binding.provenanceNotBefore)
        writer.field(binding.issuedAt)
        writer.field(binding.expiresAt)
        return try writer.finishedData()
    }

    static func provenance(
        _ provenance: BackupProvenance,
        keyIdentifier: String
    ) throws -> Data {
        try validateKeyIdentifier(keyIdentifier)
        var writer = Writer(domain: BackupAuthenticationFormat.provenanceDomain)
        encodeProvenance(provenance, keyIdentifier: keyIdentifier, to: &writer)
        return try writer.finishedData()
    }

    static func writeProvenanceAuthentication(
        _ provenance: BackupProvenance,
        keyIdentifier: String,
        to write: @escaping (Data) throws -> Void
    ) throws {
        try validateKeyIdentifier(keyIdentifier)
        var outputFailure: Error?
        var writer = Writer(
            domain: BackupAuthenticationFormat.provenanceDomain,
            emit: { bytes in
                guard outputFailure == nil else { return }
                do {
                    try write(bytes)
                } catch {
                    outputFailure = error
                }
            },
            shouldStop: { outputFailure != nil }
        )
        encodeProvenance(provenance, keyIdentifier: keyIdentifier, to: &writer)
        if let outputFailure { throw outputFailure }
        try writer.finishStreaming()
    }

    private static func encodeProvenance(
        _ provenance: BackupProvenance,
        keyIdentifier: String,
        to writer: inout Writer
    ) {
        writer.field(keyIdentifier)
        writer.field(provenance.schemaVersion)
        writer.field(provenance.transactionIdentifier)
        writer.field(provenance.sourceBindingIdentifier)
        writer.field(provenance.seriesIdentifier)
        writer.field(provenance.name)
        writer.field(provenance.createdAt)
        writer.field(provenance.sourceRootIdentity)
        writer.field(provenance.destinationDirectoryIdentity)
        writer.field(provenance.backupTree)
    }

    static func transactionJournal(
        _ record: BackupTransactionJournalRecord,
        keyIdentifier: String
    ) throws -> Data {
        try validateKeyIdentifier(keyIdentifier)
        var writer = Writer(domain: BackupAuthenticationFormat.transactionJournalDomain)
        encodeTransactionJournal(record, keyIdentifier: keyIdentifier, to: &writer)
        return try writer.finishedData()
    }

    static func writeTransactionJournalAuthentication(
        _ record: BackupTransactionJournalRecord,
        keyIdentifier: String,
        to write: @escaping (Data) throws -> Void
    ) throws {
        try validateKeyIdentifier(keyIdentifier)
        var outputFailure: Error?
        var writer = Writer(
            domain: BackupAuthenticationFormat.transactionJournalDomain,
            emit: { bytes in
                guard outputFailure == nil else { return }
                do {
                    try write(bytes)
                } catch {
                    outputFailure = error
                }
            },
            shouldStop: { outputFailure != nil }
        )
        encodeTransactionJournal(record, keyIdentifier: keyIdentifier, to: &writer)
        if let outputFailure { throw outputFailure }
        try writer.finishStreaming()
    }

    private static func encodeTransactionJournal(
        _ record: BackupTransactionJournalRecord,
        keyIdentifier: String,
        to writer: inout Writer
    ) {
        writer.field(keyIdentifier)
        writer.field(record.schemaVersion)
        writer.field(record.recordKind.rawValue)
        writer.field(record.transactionSequenceNumber)
        writer.field(record.sequenceNumber)
        writer.field(record.sequenceAnchorIdentifier)
        writer.field(record.transactionIdentifier)
        writer.optional(record.previousRecordAuthenticationTag) { $0.field($1) }
        writer.field(record.sourceBinding)
        writer.field(record.sourceTree)
        writer.array(record.stagedConstructionManifest) { $0.field($1) }
        writer.array(record.stagedConstructedNodeIdentities) { $0.field($1) }
        writer.optional(record.stagedConstructionInFlightManifestEntryIndex) { $0.field($1) }
        writer.optional(record.stagedTree) { $0.field($1) }
        writer.array(record.stagedDeletionManifest) { $0.field($1) }
        writer.field(record.stagedDeletedManifestEntryCount)
        writer.optional(record.stagedDeletionInFlightManifestEntryIndex) { $0.field($1) }
        writer.field(record.destinationDirectoryIdentity)
        writer.field(record.stagingName)
        writer.optional(record.stagingRootIdentity) { $0.field($1) }
        writer.field(record.publicationName)
        writer.field(record.metadataRequirements.rawValue)
        writer.field(record.expectedOutputBytes)
        writer.field(record.planningLimits)
        writer.field(record.journalReservationBytes)
        writer.field(record.requestTimestamp)
        writer.optional(record.publicationAuthorizationTime) { $0.field($1) }
        writer.optional(record.publicationMonotonicTime) {
            $0.field($1.clockSessionIdentifier)
            $0.field($1.nanoseconds)
        }
        writer.optional(record.publishedProvenance) { $0.field($1) }
        writer.optional(record.retentionAuthorizationTime) { $0.field($1) }
        writer.optional(record.retentionMonotonicTime) {
            $0.field($1.clockSessionIdentifier)
            $0.field($1.nanoseconds)
        }
        writer.optional(record.retentionPolicy.maximumCount) { $0.field($1) }
        writer.optional(record.retentionPolicy.maximumAgeSeconds) { $0.field($1) }
        writer.array(record.plannedRemovalNames) { $0.field($1) }
        writer.array(record.retentionTargets) { $0.field($1) }
    }

    static func authenticatedTransactionJournal(
        _ authenticatedRecord: BackupAuthenticatedTransactionJournalRecord
    ) throws -> Data {
        var data = Data()
        try writeAuthenticatedTransactionJournal(authenticatedRecord) { data.append($0) }
        return data
    }

    static func writeAuthenticatedTransactionJournal(
        _ authenticatedRecord: BackupAuthenticatedTransactionJournalRecord,
        to write: @escaping (Data) throws -> Void
    ) throws {
        var total = 0
        func writeBounded(_ bytes: Data) throws {
            guard bytes.count <= BackupTransactionJournalFormat.maximumEncodedBytes - total else {
                throw BackupPolicyError.invalidObservation("Authenticated journal exceeds its encoded-byte limit.")
            }
            try Task.checkCancellation()
            try write(bytes)
            total += bytes.count
        }
        try writeTransactionJournalAuthentication(
            authenticatedRecord.record,
            keyIdentifier: authenticatedRecord.keyIdentifier,
            to: writeBounded
        )
        var length = UInt64(authenticatedRecord.authenticationTag.count).bigEndian
        try withUnsafeBytes(of: &length) { try writeBounded(Data($0)) }
        try writeBounded(Data(authenticatedRecord.authenticationTag))
    }

    private struct Writer {
        var data: Data?
        var failure: Error?
        var operationCount = 0
        var byteCount = 0
        let maximumBytes: Int
        let emit: ((Data) -> Void)?
        let shouldStop: () -> Bool

        init(
            domain: String,
            maximumBytes: Int = BackupTransactionJournalFormat.maximumEncodedBytes,
            emit: ((Data) -> Void)? = nil,
            shouldStop: @escaping () -> Bool = { false }
        ) {
            data = emit == nil ? Data() : nil
            self.maximumBytes = maximumBytes
            self.emit = emit
            self.shouldStop = shouldStop
            appendRaw(Data(domain.utf8))
            appendRaw(Data([0]))
        }

        mutating func finishedData() throws -> Data {
            try recordCancellation()
            if let failure { throw failure }
            guard let data else {
                throw BackupPolicyError.invalidObservation("Streaming authentication writer has no buffered data.")
            }
            return data
        }

        mutating func finishStreaming() throws {
            try recordCancellation()
            if let failure { throw failure }
        }

        mutating func field(_ value: String) {
            field(Array(value.utf8))
        }

        mutating func field(_ value: [UInt8]) {
            guard failure == nil, !shouldStop() else { return }
            operationCount += 1
            if operationCount.isMultiple(of: 1_024) { try? recordCancellation() }
            guard value.count <= BackupTransactionJournalFormat.maximumAuthenticationFieldBytes,
                byteCount <= maximumBytes - 8,
                value.count <= maximumBytes - byteCount - 8
            else {
                failure = BackupPolicyError.invalidObservation("Authenticated record exceeds its encoded-byte limit.")
                return
            }
            appendLength(value.count)
            appendRaw(Data(value))
        }

        mutating func field(_ value: Int) {
            field(UInt64(bitPattern: Int64(value)))
        }

        mutating func field(_ value: UInt16) {
            var value = value.bigEndian
            withUnsafeBytes(of: &value) { field(Array($0)) }
        }

        mutating func field(_ value: UInt32) {
            var value = value.bigEndian
            withUnsafeBytes(of: &value) { field(Array($0)) }
        }

        mutating func field(_ value: UInt64) {
            var value = value.bigEndian
            withUnsafeBytes(of: &value) { field(Array($0)) }
        }

        mutating func field(_ value: BackupTimestamp) {
            field(UInt64(bitPattern: value.secondsSince1970))
            field(value.nanoseconds)
        }

        mutating func field(_ value: BackupStableNodeIdentity) {
            field(value.persistentVolumeIdentity.bytes)
            field(value.inode)
            field(value.generation.rawValue)
        }

        mutating func field(_ value: BackupItemIdentity) {
            field(value.persistentVolumeIdentity.bytes)
            field(value.device)
            field(value.inode)
            field(value.generation.rawValue)
            field(value.kind.rawValue)
            field(value.linkCount)
            field(value.size)
            field(value.outputByteCharge)
            field(value.modificationTime)
            field(value.changeTime)
            field(value.contentDigest.bytes)
            field(value.requiredMetadataDigest.bytes)
            field(value.deletionInvariantMetadataDigest.bytes)
        }

        mutating func field(_ value: BackupPlanningLimits) {
            field(value.maximumNameCandidates)
            field(value.maximumSourceItemCount)
            field(value.maximumExistingBackupCount)
            field(value.maximumRetentionItemCount)
            field(value.maximumPathUTF8Bytes)
            field(value.maximumTotalPathUTF8Bytes)
            field(value.maximumEstimatedWorkUnits)
            field(value.maximumOutputBytes)
            field(value.maximumPlanStepCount)
        }

        mutating func field(_ value: BackupRelativePath) {
            field(value.rawUTF8Bytes)
        }

        mutating func field(_ value: BackupBoundPathComponent) {
            field(value.nameUTF8Bytes)
            field(value.expectedIdentity)
        }

        mutating func field(_ value: BackupBoundRelativePath) {
            field(value.relativePath)
            array(value.components) { $0.field($1) }
        }

        mutating func field(_ value: BackupTreeSnapshot) {
            field(value.rootIdentity)
            field(value.metadataRequirements.rawValue)
            array(value.descendants) { writer, entry in
                writer.field(entry.relativePath)
                writer.field(entry.identity)
            }
        }

        mutating func field(_ value: BackupSourceBinding) {
            field(value.schemaVersion)
            field(value.sourceBindingIdentifier)
            field(value.seriesIdentifier)
            field(value.sourceRootIdentity)
            field(value.destinationDirectoryIdentity)
            field(value.provenanceNotBefore)
            field(value.issuedAt)
            field(value.expiresAt)
        }

        mutating func field(_ value: BackupAuthenticatedSourceBinding) {
            field(value.binding)
            field(value.keyIdentifier)
            field(value.authenticationTag)
        }

        mutating func field(_ value: BackupProvenance) {
            field(value.schemaVersion)
            field(value.transactionIdentifier)
            field(value.sourceBindingIdentifier)
            field(value.seriesIdentifier)
            field(value.name)
            field(value.createdAt)
            field(value.sourceRootIdentity)
            field(value.destinationDirectoryIdentity)
            field(value.backupTree)
        }

        mutating func field(_ value: BackupAuthenticatedProvenance) {
            field(value.provenance)
            field(value.keyIdentifier)
            field(value.authenticationTag)
        }

        mutating func field(_ value: BackupJournalDeletionManifestEntry) {
            optional(value.relativePath) { $0.field($1) }
            optional(value.parentRelativePath) { $0.field($1) }
            field(value.nameUTF8Bytes)
            field(value.expectedParentIdentity)
            field(value.expectedIdentity)
            field(value.expectedLinkCountBeforeDeletion)
            optional(value.expectedDirectChildCountBeforeDeletion) { $0.field($1) }
        }

        mutating func field(_ value: BackupStagedConstructionManifestEntry) {
            field(value.relativePath)
            optional(value.parentRelativePath) { $0.field($1) }
            field(value.nameUTF8Bytes)
            field(value.expectedKind.rawValue)
            field(value.sourceNodeIdentity)
        }

        mutating func field(_ value: BackupTransactionJournalTarget) {
            field(value.originalPath)
            optional(value.quarantineName) { $0.field($1) }
            optional(value.quarantineContainerIdentity) { $0.field($1) }
            field(value.provenance)
            field(value.preRenameTree)
            optional(value.postRenameTree) { $0.field($1) }
            array(value.deletionManifest) { $0.field($1) }
            field(value.deletedManifestEntryCount)
            optional(value.deletionInFlightManifestEntryIndex) { $0.field($1) }
        }

        mutating func array<Element>(
            _ values: [Element],
            encode: (inout Writer, Element) -> Void
        ) {
            field(UInt64(values.count))
            for value in values {
                guard failure == nil, !shouldStop() else { return }
                encode(&self, value)
            }
        }

        mutating func optional<Value>(
            _ value: Value?,
            encode: (inout Writer, Value) -> Void
        ) {
            guard let value else {
                field([0])
                return
            }
            field([1])
            encode(&self, value)
        }

        private mutating func appendLength(_ count: Int) {
            var length = UInt64(count).bigEndian
            withUnsafeBytes(of: &length) { appendRaw(Data($0)) }
        }

        private mutating func appendRaw(_ bytes: Data) {
            guard failure == nil, !shouldStop() else { return }
            guard byteCount <= maximumBytes, bytes.count <= maximumBytes - byteCount else {
                failure = BackupPolicyError.invalidObservation("Authenticated record exceeds its encoded-byte limit.")
                return
            }
            if emit != nil {
                emit?(bytes)
            } else {
                data?.append(bytes)
            }
            byteCount += bytes.count
        }

        private mutating func recordCancellation() throws {
            guard failure == nil else { return }
            do {
                try Task.checkCancellation()
            } catch {
                failure = error
                throw error
            }
        }
    }
}

private enum BackupCanonicalPolicyEncoder {
    static func encode(_ policy: BackupPolicy) -> Data {
        var writer = Writer()
        writer.object([
            ("collisionBehavior", { $0.string(policy.collisionBehavior.rawValue) }),
            ("destination", { destination(policy.destination, to: &$0) }),
            (
                "enabledTriggers",
                {
                    $0.array(policy.enabledTriggers) { writer, trigger in
                        writer.string(trigger.rawValue)
                    }
                }
            ),
            ("limits", { limits(policy.limits, to: &$0) }),
            ("metadataRequirements", { $0.integer(policy.metadataRequirements.rawValue) }),
            ("naming", { naming(policy.naming, to: &$0) }),
            ("retention", { retention(policy.retention, to: &$0) }),
            ("sandboxAccessPolicy", { $0.string(policy.sandboxAccessPolicy.rawValue) }),
            ("schemaVersion", { $0.integer(BackupPolicy.currentSchemaVersion) })
        ])
        return writer.data
    }

    private static func destination(_ destination: BackupDestinationStrategy, to writer: inout Writer) {
        let kind: String
        let value: String?
        switch destination {
        case .alongsideSource:
            kind = "alongsideSource"
            value = nil
        case .sourceParentSubdirectory(let name):
            kind = "sourceParentSubdirectory"
            value = name
        case .customDirectory(let url):
            kind = "customDirectory"
            value = url.absoluteString
        }
        writer.object([
            ("kind", { $0.string(kind) }),
            (
                "value",
                {
                    if let value { $0.string(value) } else { $0.null() }
                }
            )
        ])
    }

    private static func naming(_ naming: BackupNamingPolicy, to writer: inout Writer) {
        writer.object([
            ("style", { $0.string(naming.style.rawValue) }),
            ("suffix", { $0.string(naming.suffix) })
        ])
    }

    private static func retention(_ retention: BackupRetentionPolicy, to writer: inout Writer) {
        writer.object([
            (
                "maximumAgeSeconds",
                {
                    if let value = retention.maximumAgeSeconds { $0.integer(value) } else { $0.null() }
                }
            ),
            (
                "maximumCount",
                {
                    if let value = retention.maximumCount { $0.integer(value) } else { $0.null() }
                }
            )
        ])
    }

    private static func limits(_ limits: BackupPlanningLimits, to writer: inout Writer) {
        writer.object([
            ("maximumEstimatedWorkUnits", { $0.integer(limits.maximumEstimatedWorkUnits) }),
            ("maximumExistingBackupCount", { $0.integer(limits.maximumExistingBackupCount) }),
            ("maximumNameCandidates", { $0.integer(limits.maximumNameCandidates) }),
            ("maximumOutputBytes", { $0.integer(limits.maximumOutputBytes) }),
            ("maximumPathUTF8Bytes", { $0.integer(limits.maximumPathUTF8Bytes) }),
            ("maximumPlanStepCount", { $0.integer(limits.maximumPlanStepCount) }),
            ("maximumRetentionItemCount", { $0.integer(limits.maximumRetentionItemCount) }),
            ("maximumSourceItemCount", { $0.integer(limits.maximumSourceItemCount) }),
            ("maximumTotalPathUTF8Bytes", { $0.integer(limits.maximumTotalPathUTF8Bytes) })
        ])
    }

    private struct Writer {
        var data = Data()

        mutating func object(_ members: [(String, (inout Writer) -> Void)]) {
            data.append(0x7B)
            for (index, member) in members.enumerated() {
                if index > 0 { data.append(0x2C) }
                string(member.0)
                data.append(0x3A)
                member.1(&self)
            }
            data.append(0x7D)
        }

        mutating func array<Element>(
            _ values: [Element],
            write: (inout Writer, Element) -> Void
        ) {
            data.append(0x5B)
            for (index, value) in values.enumerated() {
                if index > 0 { data.append(0x2C) }
                write(&self, value)
            }
            data.append(0x5D)
        }

        mutating func string(_ value: String) {
            data.append(0x22)
            for byte in value.utf8 {
                switch byte {
                case 0x22: data.append(contentsOf: [0x5C, 0x22])
                case 0x5C: data.append(contentsOf: [0x5C, 0x5C])
                case 0x08: data.append(contentsOf: [0x5C, 0x62])
                case 0x09: data.append(contentsOf: [0x5C, 0x74])
                case 0x0A: data.append(contentsOf: [0x5C, 0x6E])
                case 0x0C: data.append(contentsOf: [0x5C, 0x66])
                case 0x0D: data.append(contentsOf: [0x5C, 0x72])
                case 0x00...0x1F:
                    let hexadecimal = Array("0123456789abcdef".utf8)
                    data.append(contentsOf: [0x5C, 0x75, 0x30, 0x30, hexadecimal[Int(byte >> 4)], hexadecimal[Int(byte & 0x0F)]])
                default: data.append(byte)
                }
            }
            data.append(0x22)
        }

        mutating func integer<T: FixedWidthInteger>(_ value: T) {
            data.append(contentsOf: String(value).utf8)
        }

        mutating func null() {
            data.append(contentsOf: [0x6E, 0x75, 0x6C, 0x6C])
        }
    }
}

private struct BackupWireVersionProbe: Decodable {
    let schemaVersion: Int
}

private enum BackupPersistencePreflight {
    static let maximumDepth = 16

    static func validate(_ data: Data) throws {
        guard
            let object = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        else {
            throw BackupPolicyError.malformedPersistence
        }
        try validate(object, depth: 0)
    }

    private static func validate(_ value: Any, depth: Int) throws {
        guard depth <= maximumDepth else {
            throw BackupPolicyError.malformedPersistence
        }
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                try validate(dictionary[key] as Any, depth: depth + 1)
            }
            return
        }
        if let array = value as? [Any] {
            for element in array {
                try validate(element, depth: depth + 1)
            }
        }
    }
}

private struct BackupWirePolicy: Codable {
    private static let keys: Set<String> = [
        "schemaVersion",
        "enabledTriggers",
        "destination",
        "naming",
        "collisionBehavior",
        "retention",
        "metadataRequirements",
        "sandboxAccessPolicy",
        "limits"
    ]

    let schemaVersion: Int
    let enabledTriggers: [BackupTrigger]
    let destination: BackupWireDestination
    let naming: BackupWireNaming
    let collisionBehavior: BackupCollisionBehavior
    let retention: BackupWireRetention
    let metadataRequirements: UInt16
    let sandboxAccessPolicy: BackupSandboxAccessPolicy
    let limits: BackupWireLimits

    init(_ policy: BackupPolicy) {
        schemaVersion = BackupPolicy.currentSchemaVersion
        enabledTriggers = policy.enabledTriggers
        destination = BackupWireDestination(policy.destination)
        naming = BackupWireNaming(policy.naming)
        collisionBehavior = policy.collisionBehavior
        retention = BackupWireRetention(policy.retention)
        metadataRequirements = policy.metadataRequirements.rawValue
        sandboxAccessPolicy = policy.sandboxAccessPolicy
        limits = BackupWireLimits(policy.limits)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BackupWireKey.self)
        try BackupWireKey.requireExactKeys(container, expected: Self.keys)
        schemaVersion = try container.decode(Int.self, forKey: BackupWireKey("schemaVersion"))
        guard schemaVersion == BackupPolicy.currentSchemaVersion else {
            throw BackupPolicyError.unsupportedSchemaVersion(schemaVersion)
        }
        enabledTriggers = try container.decode([BackupTrigger].self, forKey: BackupWireKey("enabledTriggers"))
        destination = try container.decode(BackupWireDestination.self, forKey: BackupWireKey("destination"))
        naming = try container.decode(BackupWireNaming.self, forKey: BackupWireKey("naming"))
        collisionBehavior = try container.decode(
            BackupCollisionBehavior.self,
            forKey: BackupWireKey("collisionBehavior")
        )
        retention = try container.decode(BackupWireRetention.self, forKey: BackupWireKey("retention"))
        metadataRequirements = try container.decode(UInt16.self, forKey: BackupWireKey("metadataRequirements"))
        sandboxAccessPolicy = try container.decode(
            BackupSandboxAccessPolicy.self,
            forKey: BackupWireKey("sandboxAccessPolicy")
        )
        limits = try container.decode(BackupWireLimits.self, forKey: BackupWireKey("limits"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BackupWireKey.self)
        try container.encode(schemaVersion, forKey: BackupWireKey("schemaVersion"))
        try container.encode(enabledTriggers, forKey: BackupWireKey("enabledTriggers"))
        try container.encode(destination, forKey: BackupWireKey("destination"))
        try container.encode(naming, forKey: BackupWireKey("naming"))
        try container.encode(collisionBehavior, forKey: BackupWireKey("collisionBehavior"))
        try container.encode(retention, forKey: BackupWireKey("retention"))
        try container.encode(metadataRequirements, forKey: BackupWireKey("metadataRequirements"))
        try container.encode(sandboxAccessPolicy, forKey: BackupWireKey("sandboxAccessPolicy"))
        try container.encode(limits, forKey: BackupWireKey("limits"))
    }

    func policy() throws -> BackupPolicy {
        try BackupPolicy(
            enabledTriggers: enabledTriggers,
            destination: try destination.destination(),
            naming: naming.naming,
            collisionBehavior: collisionBehavior,
            retention: retention.retention,
            metadataRequirements: BackupMetadataRequirements(rawValue: metadataRequirements),
            sandboxAccessPolicy: sandboxAccessPolicy,
            limits: try limits.limits()
        )
    }
}

private struct BackupWireDestination: Codable {
    private enum Kind: String, Codable {
        case alongsideSource
        case sourceParentSubdirectory
        case customDirectory
    }

    private let kind: Kind
    let value: String?

    init(_ destination: BackupDestinationStrategy) {
        switch destination {
        case .alongsideSource:
            kind = .alongsideSource
            value = nil
        case .sourceParentSubdirectory(let name):
            kind = .sourceParentSubdirectory
            value = name
        case .customDirectory(let url):
            kind = .customDirectory
            value = url.absoluteString
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BackupWireKey.self)
        try BackupWireKey.requireExactKeys(container, expected: ["kind", "value"])
        kind = try container.decode(Kind.self, forKey: BackupWireKey("kind"))
        value = try container.decodeIfPresent(String.self, forKey: BackupWireKey("value"))
        switch kind {
        case .alongsideSource:
            guard value == nil else { throw BackupPolicyError.malformedPersistence }
        case .sourceParentSubdirectory, .customDirectory:
            guard value != nil else { throw BackupPolicyError.malformedPersistence }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BackupWireKey.self)
        try container.encode(kind, forKey: BackupWireKey("kind"))
        try container.encode(value, forKey: BackupWireKey("value"))
    }

    func destination() throws -> BackupDestinationStrategy {
        switch kind {
        case .alongsideSource:
            return .alongsideSource
        case .sourceParentSubdirectory:
            guard let value else { throw BackupPolicyError.malformedPersistence }
            return .sourceParentSubdirectory(value)
        case .customDirectory:
            guard let value, let url = URL(string: value), url.absoluteString == value else {
                throw BackupPolicyError.malformedPersistence
            }
            return .customDirectory(url)
        }
    }
}

private struct BackupWireNaming: Codable {
    private static let keys: Set<String> = ["style", "suffix"]

    let style: BackupNameStyle
    let suffix: String

    init(_ naming: BackupNamingPolicy) {
        style = naming.style
        suffix = naming.suffix
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BackupWireKey.self)
        try BackupWireKey.requireExactKeys(container, expected: Self.keys)
        style = try container.decode(BackupNameStyle.self, forKey: BackupWireKey("style"))
        suffix = try container.decode(String.self, forKey: BackupWireKey("suffix"))
    }

    var naming: BackupNamingPolicy {
        BackupNamingPolicy(style: style, suffix: suffix)
    }
}

private struct BackupWireRetention: Codable {
    private static let keys: Set<String> = ["maximumCount", "maximumAgeSeconds"]

    let maximumCount: Int?
    let maximumAgeSeconds: UInt64?

    init(_ retention: BackupRetentionPolicy) {
        maximumCount = retention.maximumCount
        maximumAgeSeconds = retention.maximumAgeSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BackupWireKey.self)
        try BackupWireKey.requireExactKeys(container, expected: Self.keys)
        maximumCount = try container.decodeIfPresent(Int.self, forKey: BackupWireKey("maximumCount"))
        maximumAgeSeconds = try container.decodeIfPresent(
            UInt64.self,
            forKey: BackupWireKey("maximumAgeSeconds")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BackupWireKey.self)
        try container.encode(maximumCount, forKey: BackupWireKey("maximumCount"))
        try container.encode(maximumAgeSeconds, forKey: BackupWireKey("maximumAgeSeconds"))
    }

    var retention: BackupRetentionPolicy {
        BackupRetentionPolicy(
            maximumCount: maximumCount,
            maximumAgeSeconds: maximumAgeSeconds
        )
    }
}

private struct BackupWireLimits: Codable {
    private static let keys: Set<String> = [
        "maximumNameCandidates",
        "maximumSourceItemCount",
        "maximumExistingBackupCount",
        "maximumRetentionItemCount",
        "maximumPathUTF8Bytes",
        "maximumTotalPathUTF8Bytes",
        "maximumEstimatedWorkUnits",
        "maximumOutputBytes",
        "maximumPlanStepCount"
    ]

    let maximumNameCandidates: Int
    let maximumSourceItemCount: Int
    let maximumExistingBackupCount: Int
    let maximumRetentionItemCount: Int
    let maximumPathUTF8Bytes: Int
    let maximumTotalPathUTF8Bytes: Int
    let maximumEstimatedWorkUnits: UInt64
    let maximumOutputBytes: UInt64
    let maximumPlanStepCount: Int

    init(_ limits: BackupPlanningLimits) {
        maximumNameCandidates = limits.maximumNameCandidates
        maximumSourceItemCount = limits.maximumSourceItemCount
        maximumExistingBackupCount = limits.maximumExistingBackupCount
        maximumRetentionItemCount = limits.maximumRetentionItemCount
        maximumPathUTF8Bytes = limits.maximumPathUTF8Bytes
        maximumTotalPathUTF8Bytes = limits.maximumTotalPathUTF8Bytes
        maximumEstimatedWorkUnits = limits.maximumEstimatedWorkUnits
        maximumOutputBytes = limits.maximumOutputBytes
        maximumPlanStepCount = limits.maximumPlanStepCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BackupWireKey.self)
        try BackupWireKey.requireExactKeys(container, expected: Self.keys)
        maximumNameCandidates = try container.decode(Int.self, forKey: BackupWireKey("maximumNameCandidates"))
        maximumSourceItemCount = try container.decode(Int.self, forKey: BackupWireKey("maximumSourceItemCount"))
        maximumExistingBackupCount = try container.decode(
            Int.self,
            forKey: BackupWireKey("maximumExistingBackupCount")
        )
        maximumRetentionItemCount = try container.decode(
            Int.self,
            forKey: BackupWireKey("maximumRetentionItemCount")
        )
        maximumPathUTF8Bytes = try container.decode(Int.self, forKey: BackupWireKey("maximumPathUTF8Bytes"))
        maximumTotalPathUTF8Bytes = try container.decode(
            Int.self,
            forKey: BackupWireKey("maximumTotalPathUTF8Bytes")
        )
        maximumEstimatedWorkUnits = try container.decode(
            UInt64.self,
            forKey: BackupWireKey("maximumEstimatedWorkUnits")
        )
        maximumOutputBytes = try container.decode(UInt64.self, forKey: BackupWireKey("maximumOutputBytes"))
        maximumPlanStepCount = try container.decode(Int.self, forKey: BackupWireKey("maximumPlanStepCount"))
    }

    func limits() throws -> BackupPlanningLimits {
        try BackupPlanningLimits(
            maximumNameCandidates: maximumNameCandidates,
            maximumSourceItemCount: maximumSourceItemCount,
            maximumExistingBackupCount: maximumExistingBackupCount,
            maximumRetentionItemCount: maximumRetentionItemCount,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes,
            maximumEstimatedWorkUnits: maximumEstimatedWorkUnits,
            maximumOutputBytes: maximumOutputBytes,
            maximumPlanStepCount: maximumPlanStepCount
        )
    }
}

private struct BackupWireKey: CodingKey, Hashable {
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

    static func requireExactKeys<Value>(
        _ container: KeyedDecodingContainer<Value>,
        expected: Set<String>
    ) throws where Value: CodingKey {
        guard Set(container.allKeys.map(\.stringValue)) == expected else {
            throw BackupPolicyError.malformedPersistence
        }
    }
}
