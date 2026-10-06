import CryptoKit
import Foundation

public struct ArchiveGenerationEntryID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ArchiveGenerationComparisonKind: String, CaseIterable, Hashable, Sendable {
    case file
    case folder
}

public enum ArchiveGenerationSide: String, CaseIterable, Hashable, Sendable {
    case left
    case right
}

public enum ArchiveGenerationComparisonStatus: String, CaseIterable, Hashable, Sendable {
    case identical
    case leftOnly
    case rightOnly
    case different
    case typeMismatch
    case skipped
    case error
}

public enum ArchiveGenerationItemKind: String, CaseIterable, Hashable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case specialFile
}

/// Exact directory `contentSHA256` serialization. Every field is framed by an unsigned UInt64
/// big-endian payload length. Hash UTF-8 domain `ArchiveGenerationDirectoryChildren/v1`, UInt64
/// big-endian child count, then each direct child sorted by raw UTF-8 name: UTF-8 name followed by
/// one byte (regular file 0, directory 1, symbolic link 2, special file 3).
public enum ArchiveGenerationDirectoryRevisionPolicy: String, CaseIterable, Hashable, Sendable {
    case sortedLengthPrefixedUTF8NameAndFixedKindV1

    public static let required = ArchiveGenerationDirectoryRevisionPolicy
        .sortedLengthPrefixedUTF8NameAndFixedKindV1
}

public struct ArchiveGenerationNodeIdentity: Hashable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    public init(deviceID: UInt64, fileID: UInt64, generation: UInt32) {
        self.deviceID = deviceID
        self.fileID = fileID
        self.generation = generation
    }
}

/// Caller-captured canonical directory identity. Planning performs no path resolution.
public struct ArchiveGenerationCanonicalDirectoryIdentity: Hashable, Sendable {
    public let canonicalURL: URL
    public let node: ArchiveGenerationNodeIdentity

    public init(canonicalURL: URL, node: ArchiveGenerationNodeIdentity) {
        self.canonicalURL = canonicalURL
        self.node = node
    }
}

/// Exact canonical source identity. `canonicalURL` must equal `root/relativePath` lexically.
/// Executors still resolve from a pinned root descriptor and compare `node`; URLs are not capabilities.
public struct ArchiveGenerationCanonicalItemIdentity: Hashable, Sendable {
    public let canonicalURL: URL
    public let root: ArchiveGenerationCanonicalDirectoryIdentity
    public let relativePath: String
    public let kind: ArchiveGenerationItemKind
    public let node: ArchiveGenerationNodeIdentity

    public init(
        canonicalURL: URL,
        root: ArchiveGenerationCanonicalDirectoryIdentity,
        relativePath: String,
        kind: ArchiveGenerationItemKind,
        node: ArchiveGenerationNodeIdentity
    ) {
        self.canonicalURL = canonicalURL
        self.root = root
        self.relativePath = relativePath
        self.kind = kind
        self.node = node
    }
}

/// Complete caller-captured revision. For directories, `contentSHA256` identifies the sorted,
/// raw-UTF-8 child-name/type snapshot whose exact enumeration bounds are recorded below. Executors
/// must stop and reject before exceeding either bound, then require both exact totals. For links,
/// `contentSHA256` identifies link text.
public struct ArchiveGenerationSourceRevision: Hashable, Sendable {
    public let identity: ArchiveGenerationCanonicalItemIdentity
    public let byteCount: UInt64
    public let directoryChildCount: UInt64
    public let directoryChildNameUTF8ByteCount: UInt64
    public let linkCount: UInt64
    public let permissions: UInt16
    public let ownerID: UInt32
    public let groupID: UInt32
    public let flags: UInt32
    public let metadataByteCount: UInt64
    public let modificationTimeSeconds: Int64
    public let modificationTimeNanoseconds: Int32
    public let statusChangeTimeSeconds: Int64
    public let statusChangeTimeNanoseconds: Int32
    public let contentSHA256: [UInt8]
    /// Digest of executor-defined complete metadata, including ACLs and extended attributes.
    public let metadataSHA256: [UInt8]

    public init(
        identity: ArchiveGenerationCanonicalItemIdentity,
        byteCount: UInt64,
        directoryChildCount: UInt64,
        directoryChildNameUTF8ByteCount: UInt64,
        linkCount: UInt64,
        permissions: UInt16,
        ownerID: UInt32,
        groupID: UInt32,
        flags: UInt32,
        metadataByteCount: UInt64,
        modificationTimeSeconds: Int64,
        modificationTimeNanoseconds: Int32,
        statusChangeTimeSeconds: Int64,
        statusChangeTimeNanoseconds: Int32,
        contentSHA256: [UInt8],
        metadataSHA256: [UInt8]
    ) {
        self.identity = identity
        self.byteCount = byteCount
        self.directoryChildCount = directoryChildCount
        self.directoryChildNameUTF8ByteCount = directoryChildNameUTF8ByteCount
        self.linkCount = linkCount
        self.permissions = permissions
        self.ownerID = ownerID
        self.groupID = groupID
        self.flags = flags
        self.metadataByteCount = metadataByteCount
        self.modificationTimeSeconds = modificationTimeSeconds
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.statusChangeTimeSeconds = statusChangeTimeSeconds
        self.statusChangeTimeNanoseconds = statusChangeTimeNanoseconds
        self.contentSHA256 = contentSHA256
        self.metadataSHA256 = metadataSHA256
    }
}

public enum ArchiveGenerationAuthorityCoverage: String, CaseIterable, Hashable, Sendable {
    case exactItem
    case directoryTree
}

/// Declared authority acquisition intent. Construction is not proof that sandbox access is valid.
public enum ArchiveGenerationAccessAuthority: Hashable, Sendable {
    case ambient
    case callerManagedWhenRequired
    case securityScoped(resourceURL: URL, coverage: ArchiveGenerationAuthorityCoverage)
}

/// `requestedURL` is retained because it may carry sandbox authorization. Its binding to the
/// canonical identity is a caller attestation that every executor must independently verify.
public struct ArchiveGenerationSourceItem: Hashable, Sendable {
    public let requestedURL: URL
    public let revision: ArchiveGenerationSourceRevision
    public let accessAuthority: ArchiveGenerationAccessAuthority

    public init(
        requestedURL: URL,
        revision: ArchiveGenerationSourceRevision,
        accessAuthority: ArchiveGenerationAccessAuthority = .callerManagedWhenRequired
    ) {
        self.requestedURL = requestedURL
        self.revision = revision
        self.accessAuthority = accessAuthority
    }
}

/// Immutable file/folder comparison row. Folder snapshots must supply every descendant that may be
/// selected; this workflow never enumerates a directory.
public struct ArchiveGenerationComparisonEntry: Hashable, Sendable {
    public let id: ArchiveGenerationEntryID
    public let relativePath: String
    public let status: ArchiveGenerationComparisonStatus
    public let isHidden: Bool
    public let left: ArchiveGenerationSourceItem?
    public let right: ArchiveGenerationSourceItem?

    public init(
        id: ArchiveGenerationEntryID,
        relativePath: String,
        status: ArchiveGenerationComparisonStatus,
        isHidden: Bool = false,
        left: ArchiveGenerationSourceItem?,
        right: ArchiveGenerationSourceItem?
    ) {
        self.id = id
        self.relativePath = relativePath
        self.status = status
        self.isHidden = isHidden
        self.left = left
        self.right = right
    }

    public func item(on side: ArchiveGenerationSide) -> ArchiveGenerationSourceItem? {
        switch side {
        case .left: left
        case .right: right
        }
    }
}

public struct ArchiveGenerationSnapshotIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Owners must advance `generation` whenever comparison entries, filtering inputs, or source
/// revisions change. State digesting detects a violated generation contract.
public struct ArchiveGenerationComparisonSnapshot: Hashable, Sendable {
    public let identity: ArchiveGenerationSnapshotIdentity
    public let generation: UInt64
    public let comparisonKind: ArchiveGenerationComparisonKind
    public let entries: [ArchiveGenerationComparisonEntry]

    public init(
        identity: ArchiveGenerationSnapshotIdentity,
        generation: UInt64,
        comparisonKind: ArchiveGenerationComparisonKind,
        entries: [ArchiveGenerationComparisonEntry]
    ) {
        self.identity = identity
        self.generation = generation
        self.comparisonKind = comparisonKind
        self.entries = entries
    }
}

public struct ArchiveGenerationSnapshotReference: Hashable, Sendable {
    public let identity: ArchiveGenerationSnapshotIdentity
    public let generation: UInt64

    public init(identity: ArchiveGenerationSnapshotIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }

    public init(_ snapshot: ArchiveGenerationComparisonSnapshot) {
        identity = snapshot.identity
        generation = snapshot.generation
    }
}

/// Exact owner-state compare-and-swap token for stale-plan rejection.
public struct ArchiveGenerationSnapshotCAS: Hashable, Sendable {
    public let reference: ArchiveGenerationSnapshotReference
    public let stateSHA256: [UInt8]

    fileprivate init(reference: ArchiveGenerationSnapshotReference, stateSHA256: [UInt8]) {
        self.reference = reference
        self.stateSHA256 = stateSHA256
    }
}

public struct ArchiveGenerationSelectedEntry: Hashable, Sendable {
    public let id: ArchiveGenerationEntryID
    public let side: ArchiveGenerationSide
    /// Optional archive path before the request-wide prefix is applied.
    public let archiveRelativePath: String?

    public init(
        id: ArchiveGenerationEntryID,
        side: ArchiveGenerationSide,
        archiveRelativePath: String? = nil
    ) {
        self.id = id
        self.side = side
        self.archiveRelativePath = archiveRelativePath
    }
}

public enum ArchiveGenerationSelection: Hashable, Sendable {
    case all(side: ArchiveGenerationSide)
    /// Set-like explicit selection. Output order is always canonical, not caller order.
    case only([ArchiveGenerationSelectedEntry])
}

public enum ArchiveGenerationDirectorySelectionPolicy: String, CaseIterable, Hashable, Sendable {
    /// A selected directory contributes one directory manifest entry.
    case selectedEntriesOnly
    /// A selected directory also contributes descendants already present in the immutable snapshot.
    case includeSnapshotDescendants
}

public enum ArchiveGenerationUnsupportedItemDisposition: String, CaseIterable, Hashable, Sendable {
    case reject
    case omit
}

public enum ArchiveGenerationMissingSideDisposition: String, CaseIterable, Hashable, Sendable {
    case reject
    case omit
}

public enum ArchiveGenerationHiddenFilter: String, CaseIterable, Hashable, Sendable {
    case include
    case exclude
    case only
}

public enum ArchiveGenerationPathRuleAction: String, CaseIterable, Hashable, Sendable {
    case include
    case exclude
}

public enum ArchiveGenerationPathRuleMatch: Hashable, Sendable {
    case exact(String)
    case subtree(String)
    /// Extension without a leading dot.
    case pathExtension(String)
}

/// Rules are applied in order; the last matching rule wins.
public struct ArchiveGenerationPathRule: Hashable, Sendable {
    public let action: ArchiveGenerationPathRuleAction
    public let match: ArchiveGenerationPathRuleMatch

    public init(action: ArchiveGenerationPathRuleAction, match: ArchiveGenerationPathRuleMatch) {
        self.action = action
        self.match = match
    }
}

public enum ArchiveGenerationPathComparison: String, CaseIterable, Hashable, Sendable {
    case caseSensitive
    case portableCaseInsensitive
}

/// Pinned path semantics used by planning and required of executors. Paths preserve their UTF-8
/// bytes. Portable names and case-insensitive matching accept ASCII only and fold A-Z explicitly.
public enum ArchiveGenerationPathPolicy: String, CaseIterable, Hashable, Sendable {
    case bytePreservingASCIIPortableV1

    public static let required = ArchiveGenerationPathPolicy.bytePreservingASCIIPortableV1
}

public struct ArchiveGenerationFilterPolicy: Hashable, Sendable {
    public static let includeAll = ArchiveGenerationFilterPolicy()

    public let statuses: Set<ArchiveGenerationComparisonStatus>
    public let kinds: Set<ArchiveGenerationItemKind>
    public let hidden: ArchiveGenerationHiddenFilter
    public let defaultPathAction: ArchiveGenerationPathRuleAction
    public let pathRules: [ArchiveGenerationPathRule]
    public let pathComparison: ArchiveGenerationPathComparison

    public init(
        statuses: Set<ArchiveGenerationComparisonStatus> = [],
        kinds: Set<ArchiveGenerationItemKind> = [],
        hidden: ArchiveGenerationHiddenFilter = .include,
        defaultPathAction: ArchiveGenerationPathRuleAction = .include,
        pathRules: [ArchiveGenerationPathRule] = [],
        pathComparison: ArchiveGenerationPathComparison = .portableCaseInsensitive
    ) {
        self.statuses = statuses
        self.kinds = kinds
        self.hidden = hidden
        self.defaultPathAction = defaultPathAction
        self.pathRules = pathRules
        self.pathComparison = pathComparison
    }
}

public struct ArchiveGenerationInclusionPolicy: Hashable, Sendable {
    public static let secureDefault = ArchiveGenerationInclusionPolicy()

    public let filter: ArchiveGenerationFilterPolicy
    public let directorySelection: ArchiveGenerationDirectorySelectionPolicy
    public let missingSide: ArchiveGenerationMissingSideDisposition
    public let symbolicLinks: ArchiveGenerationUnsupportedItemDisposition
    public let specialFiles: ArchiveGenerationUnsupportedItemDisposition

    public init(
        filter: ArchiveGenerationFilterPolicy = .includeAll,
        directorySelection: ArchiveGenerationDirectorySelectionPolicy = .selectedEntriesOnly,
        missingSide: ArchiveGenerationMissingSideDisposition = .reject,
        symbolicLinks: ArchiveGenerationUnsupportedItemDisposition = .reject,
        specialFiles: ArchiveGenerationUnsupportedItemDisposition = .reject
    ) {
        self.filter = filter
        self.directorySelection = directorySelection
        self.missingSide = missingSide
        self.symbolicLinks = symbolicLinks
        self.specialFiles = specialFiles
    }
}

public enum ArchiveGenerationContainerFormat: String, CaseIterable, Hashable, Sendable {
    case zip
    case tar
    case sevenZip
}

public enum ArchiveGenerationCompressionMethod: String, CaseIterable, Hashable, Sendable {
    case store
    case deflate
    case bzip2
    case lzma
    case zstandard
}

public struct ArchiveGenerationCodec: Hashable, Sendable {
    public let format: ArchiveGenerationContainerFormat
    public let compression: ArchiveGenerationCompressionMethod

    public init(
        format: ArchiveGenerationContainerFormat,
        compression: ArchiveGenerationCompressionMethod
    ) {
        self.format = format
        self.compression = compression
    }
}

/// Exact codec implementation family an executor promises to use. Revision changes whenever encoded
/// bytes, supported options, or deterministic behavior changes.
public struct ArchiveGenerationExecutorCapabilities: Hashable, Sendable {
    public static let portableBaseline = ArchiveGenerationExecutorCapabilities(
        identifier: "macmerge.portable-archive",
        revision: 1,
        codecs: [
            ArchiveGenerationCodec(format: .zip, compression: .store),
            ArchiveGenerationCodec(format: .zip, compression: .deflate),
            ArchiveGenerationCodec(format: .tar, compression: .store)
        ]
    )

    public let identifier: String
    public let revision: UInt64
    public let codecs: Set<ArchiveGenerationCodec>

    public init(identifier: String, revision: UInt64, codecs: Set<ArchiveGenerationCodec>) {
        self.identifier = identifier
        self.revision = revision
        self.codecs = codecs
    }
}

public enum ArchiveGenerationMetadataPolicy: String, CaseIterable, Hashable, Sendable {
    /// Fixed 0600/0700 modes and 1980-01-01 00:00:00 UTC timestamps.
    case reproducible
    /// Exact mode and modification time from each source revision.
    case preserveSource
}

public struct ArchiveGenerationOutputOptions: Hashable, Sendable {
    public let format: ArchiveGenerationContainerFormat
    public let compression: ArchiveGenerationCompressionMethod
    /// Required for compressed output and absent for `.store`.
    public let compressionLevel: Int?
    public let metadataPolicy: ArchiveGenerationMetadataPolicy
    /// Normalized prefix applied to every output entry.
    public let pathPrefix: String?
    public let archiveComment: String?
    public let destinationPermissions: UInt16

    public init(
        format: ArchiveGenerationContainerFormat = .zip,
        compression: ArchiveGenerationCompressionMethod = .store,
        compressionLevel: Int? = nil,
        metadataPolicy: ArchiveGenerationMetadataPolicy = .reproducible,
        pathPrefix: String? = nil,
        archiveComment: String? = nil,
        destinationPermissions: UInt16 = 0o600
    ) {
        self.format = format
        self.compression = compression
        self.compressionLevel = compressionLevel
        self.metadataPolicy = metadataPolicy
        self.pathPrefix = pathPrefix
        self.archiveComment = archiveComment
        self.destinationPermissions = destinationPermissions
    }
}

public struct ArchiveGenerationCanonicalDestinationLocation: Hashable, Sendable {
    public let canonicalURL: URL
    public let parent: ArchiveGenerationCanonicalDirectoryIdentity

    public init(
        canonicalURL: URL,
        parent: ArchiveGenerationCanonicalDirectoryIdentity
    ) {
        self.canonicalURL = canonicalURL
        self.parent = parent
    }
}

public enum ArchiveGenerationDestinationIntent: Hashable, Sendable {
    /// Publish only if the leaf is absent under this exact parent identity.
    case createNew(ArchiveGenerationCanonicalDestinationLocation)
    /// Replace only this exact regular-file revision.
    case replaceExisting(ArchiveGenerationSourceRevision)

    public var canonicalURL: URL {
        switch self {
        case .createNew(let location): location.canonicalURL
        case .replaceExisting(let revision): revision.identity.canonicalURL
        }
    }

    public var canonicalParent: ArchiveGenerationCanonicalDirectoryIdentity {
        switch self {
        case .createNew(let location): location.parent
        case .replaceExisting(let revision): revision.identity.root
        }
    }
}

public struct ArchiveGenerationDestination: Hashable, Sendable {
    /// Original URL retained for sandbox authorization. Executor verifies its canonical binding.
    public let requestedURL: URL
    public let intent: ArchiveGenerationDestinationIntent
    public let accessAuthority: ArchiveGenerationAccessAuthority

    public init(
        requestedURL: URL,
        intent: ArchiveGenerationDestinationIntent,
        accessAuthority: ArchiveGenerationAccessAuthority = .callerManagedWhenRequired
    ) {
        self.requestedURL = requestedURL
        self.intent = intent
        self.accessAuthority = accessAuthority
    }
}

public enum ArchiveGenerationLimit: String, CaseIterable, Hashable, Sendable {
    case snapshotEntries
    case selectedEntries
    case filterRules
    case identifierUTF8Bytes
    case pathUTF8Bytes
    case pathDepth
    case totalPathUTF8Bytes
    case totalPathComponents
    case itemBytes
    case totalSourceBytes
    case metadataBytes
    case archiveBytes
    case optionUTF8Bytes
    case retainedPlanBytes
    case workUnits
    case cancellationCheckInterval
}

public struct ArchiveGenerationLimits: Hashable, Sendable {
    public static let hardMaximumSnapshotEntries = 65_536
    public static let hardMaximumSelectedEntries = 65_536
    public static let hardMaximumFilterRules = 4_096
    public static let hardMaximumIdentifierUTF8Bytes = 4_096
    public static let hardMaximumPathUTF8Bytes = 16 * 1_024
    public static let hardMaximumPathDepth = 256
    public static let hardMaximumTotalPathUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumTotalPathComponents: UInt64 = 4_000_000
    public static let hardMaximumItemBytes: UInt64 = 1 * 1_024 * 1_024 * 1_024 * 1_024
    public static let hardMaximumTotalSourceBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024 * 1_024
    public static let hardMaximumMetadataBytes: UInt64 = 1 * 1_024 * 1_024 * 1_024
    public static let hardMaximumArchiveBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024 * 1_024
    public static let hardMaximumOptionUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumRetainedPlanBytes = 256 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 42
    public static let `default` = ArchiveGenerationLimits()

    public let maximumSnapshotEntries: Int
    public let maximumSelectedEntries: Int
    public let maximumFilterRules: Int
    public let maximumIdentifierUTF8Bytes: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumPathDepth: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumTotalPathComponents: UInt64
    public let maximumItemBytes: UInt64
    public let maximumTotalSourceBytes: UInt64
    public let maximumMetadataBytes: UInt64
    public let maximumArchiveBytes: UInt64
    public let maximumOptionUTF8Bytes: Int
    public let maximumRetainedPlanBytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: Int

    public init(
        maximumSnapshotEntries: Int = 32_768,
        maximumSelectedEntries: Int = 32_768,
        maximumFilterRules: Int = 1_024,
        maximumIdentifierUTF8Bytes: Int = 1_024,
        maximumPathUTF8Bytes: Int = 4_096,
        maximumPathDepth: Int = 128,
        maximumTotalPathUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumTotalPathComponents: UInt64 = 1_000_000,
        maximumItemBytes: UInt64 = 64 * 1_024 * 1_024 * 1_024,
        maximumTotalSourceBytes: UInt64 = 512 * 1_024 * 1_024 * 1_024,
        maximumMetadataBytes: UInt64 = 256 * 1_024 * 1_024,
        maximumArchiveBytes: UInt64 = 512 * 1_024 * 1_024 * 1_024,
        maximumOptionUTF8Bytes: Int = 256 * 1_024,
        maximumRetainedPlanBytes: Int = 128 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 16 * 1_024 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 256
    ) {
        self.maximumSnapshotEntries = maximumSnapshotEntries
        self.maximumSelectedEntries = maximumSelectedEntries
        self.maximumFilterRules = maximumFilterRules
        self.maximumIdentifierUTF8Bytes = maximumIdentifierUTF8Bytes
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumPathDepth = maximumPathDepth
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumTotalPathComponents = maximumTotalPathComponents
        self.maximumItemBytes = maximumItemBytes
        self.maximumTotalSourceBytes = maximumTotalSourceBytes
        self.maximumMetadataBytes = maximumMetadataBytes
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumOptionUTF8Bytes = maximumOptionUTF8Bytes
        self.maximumRetainedPlanBytes = maximumRetainedPlanBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct ArchiveGenerationRequest: Hashable, Sendable {
    public let snapshot: ArchiveGenerationComparisonSnapshot
    public let selection: ArchiveGenerationSelection
    public let inclusionPolicy: ArchiveGenerationInclusionPolicy
    public let outputOptions: ArchiveGenerationOutputOptions
    public let destination: ArchiveGenerationDestination
    public let executorCapabilities: ArchiveGenerationExecutorCapabilities
    public let limits: ArchiveGenerationLimits

    public init(
        snapshot: ArchiveGenerationComparisonSnapshot,
        selection: ArchiveGenerationSelection,
        inclusionPolicy: ArchiveGenerationInclusionPolicy = .secureDefault,
        outputOptions: ArchiveGenerationOutputOptions = ArchiveGenerationOutputOptions(),
        destination: ArchiveGenerationDestination,
        executorCapabilities: ArchiveGenerationExecutorCapabilities = .portableBaseline,
        limits: ArchiveGenerationLimits = .default
    ) {
        self.snapshot = snapshot
        self.selection = selection
        self.inclusionPolicy = inclusionPolicy
        self.outputOptions = outputOptions
        self.destination = destination
        self.executorCapabilities = executorCapabilities
        self.limits = limits
    }
}

public enum ArchiveGenerationPathRole: String, CaseIterable, Hashable, Sendable {
    case comparison
    case source
    case archive
    case prefix
    case filter
}

public enum ArchiveGenerationPathIssue: String, CaseIterable, Hashable, Sendable {
    case empty
    case absolute
    case containsBackslash
    case containsNull
    case emptyComponent
    case currentDirectoryComponent
    case parentTraversal
    case containsColon
    case containsPortableForbiddenCharacter
    case trailingDotOrSpace
    case reservedDeviceName
    case notNormalized
    case componentTooLong
    case pathTooLong
    case tooDeep
    case emptyPortableKey
    case unsupportedNonASCII
}

public enum ArchiveGenerationURLRole: Hashable, Sendable {
    case requestedSource(ArchiveGenerationEntryID, ArchiveGenerationSide)
    case canonicalSource(ArchiveGenerationEntryID, ArchiveGenerationSide)
    case canonicalSourceRoot(ArchiveGenerationEntryID, ArchiveGenerationSide)
    case requestedDestination
    case canonicalDestination
    case canonicalDestinationParent
    case securityScope
}

public enum ArchiveGenerationURLIssue: String, CaseIterable, Hashable, Sendable {
    case notFileURL
    case relativeURL
    case remoteHost
    case credentialsOrPort
    case queryOrFragment
    case nullByte
    case pathTooLong
    case notCanonical
    case rootMismatch
    case parentMismatch
    case insufficientAuthorityCoverage
}

public enum ArchiveGenerationPlanningError: Error, Hashable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(ArchiveGenerationLimit)
    case workLimitExceeded(maximumUnits: UInt64)
    case tooManySnapshotEntries(maximum: Int)
    case tooManySelectedEntries(maximum: Int)
    case tooManyFilterRules(maximum: Int)
    case invalidEntryIdentifier(String)
    case duplicateEntryIdentifier(ArchiveGenerationEntryID)
    case invalidComparisonEntry(ArchiveGenerationEntryID)
    case unknownEntryIdentifier(ArchiveGenerationEntryID)
    case duplicateSelection(ArchiveGenerationEntryID, ArchiveGenerationSide)
    case ambiguousSelection(ArchiveGenerationEntryID, ArchiveGenerationSide)
    case emptySelection
    case missingSide(ArchiveGenerationEntryID, ArchiveGenerationSide)
    case invalidPath(role: ArchiveGenerationPathRole, path: String, issue: ArchiveGenerationPathIssue)
    case invalidPathExtension(String)
    case invalidURL(role: ArchiveGenerationURLRole, issue: ArchiveGenerationURLIssue)
    case invalidRevision(path: String)
    case conflictingSourceRevision(path: String)
    case unsupportedItem(path: String, kind: ArchiveGenerationItemKind)
    case unsupportedCodec(ArchiveGenerationCodec)
    case invalidCompressionLevel
    case invalidArchiveComment
    case invalidPermissions(UInt16)
    case itemTooLarge(path: String, maximumBytes: UInt64)
    case sourceBytesTooLarge(maximumBytes: UInt64)
    case metadataTooLarge(maximumBytes: UInt64)
    case tooManyPathComponents(maximum: UInt64)
    case totalPathsTooLarge(maximumBytes: Int)
    case duplicateArchivePath(String)
    case portablePathCollision(first: String, second: String)
    case pathHierarchyConflict(ancestor: String, descendant: String)
    case destinationMatchesSource(String)
    case destinationInsideSource(String)
    case destinationDoesNotMatchIntent
    case archiveSizeLimitExceeded(maximumBytes: UInt64)
    case planTooLarge(maximumBytes: Int)
    case staleSnapshot(expected: ArchiveGenerationSnapshotReference, actual: ArchiveGenerationSnapshotReference)
    case snapshotContentsChanged
    case sourceSetChanged
    case sourceRevisionChanged(String)
    case destinationParentChanged
    case destinationChanged

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Archive generation planning was cancelled."
        case .invalidLimit(let limit):
            "Invalid archive-generation limit: \(limit.rawValue)."
        case .workLimitExceeded(let maximum):
            "Archive generation exceeds the \(maximum)-unit work limit."
        case .tooManySnapshotEntries(let maximum):
            "Archive snapshot exceeds the \(maximum)-entry limit."
        case .tooManySelectedEntries(let maximum):
            "Archive selection exceeds the \(maximum)-entry limit."
        case .tooManyFilterRules(let maximum):
            "Archive filtering exceeds the \(maximum)-rule limit."
        case .invalidEntryIdentifier(let identifier):
            "Invalid archive entry identifier: \(identifier)."
        case .duplicateEntryIdentifier(let identifier):
            "Duplicate archive entry identifier: \(identifier.rawValue)."
        case .invalidComparisonEntry(let identifier):
            "Archive comparison entry is inconsistent with its sources: \(identifier.rawValue)."
        case .unknownEntryIdentifier(let identifier):
            "Unknown archive entry identifier: \(identifier.rawValue)."
        case .duplicateSelection(let identifier, let side):
            "Archive selection repeats \(identifier.rawValue) on the \(side.rawValue) side."
        case .ambiguousSelection(let identifier, let side):
            "Archive selection maps \(identifier.rawValue) on the \(side.rawValue) side to conflicting paths."
        case .emptySelection:
            "Archive generation requires at least one included entry."
        case .missingSide(let identifier, let side):
            "Archive entry \(identifier.rawValue) has no \(side.rawValue) source."
        case .invalidPath(let role, let path, let issue):
            "Invalid archive-generation \(role.rawValue) path (\(issue.rawValue)): \(path)"
        case .invalidPathExtension(let value):
            "Invalid archive path-extension filter: \(value)."
        case .invalidURL(let role, let issue):
            "Invalid archive-generation URL for \(String(describing: role)): \(issue.rawValue)."
        case .invalidRevision(let path):
            "Invalid archive source revision: \(path)."
        case .conflictingSourceRevision(let path):
            "One archive source identity has conflicting revisions: \(path)."
        case .unsupportedItem(let path, let kind):
            "Archive source is an unsupported \(kind.rawValue): \(path)"
        case .unsupportedCodec(let codec):
            "Executor does not support \(codec.format.rawValue)/\(codec.compression.rawValue)."
        case .invalidCompressionLevel:
            "Archive compression level is invalid for the selected method."
        case .invalidArchiveComment:
            "Archive comment is invalid or too large."
        case .invalidPermissions(let permissions):
            "Archive destination permissions are invalid: \(permissions)."
        case .itemTooLarge(let path, let maximum):
            "Archive item exceeds \(maximum) bytes: \(path)"
        case .sourceBytesTooLarge(let maximum):
            "Archive sources exceed \(maximum) bytes."
        case .metadataTooLarge(let maximum):
            "Archive source metadata exceeds \(maximum) bytes."
        case .tooManyPathComponents(let maximum):
            "Archive paths exceed \(maximum) total components."
        case .totalPathsTooLarge(let maximum):
            "Archive paths exceed \(maximum) total UTF-8 bytes."
        case .duplicateArchivePath(let path):
            "Archive contains duplicate normalized path: \(path)"
        case .portablePathCollision(let first, let second):
            "Archive paths collide on portable filesystems: \(first), \(second)"
        case .pathHierarchyConflict(let ancestor, let descendant):
            "Archive file path is also an ancestor: \(ancestor), \(descendant)"
        case .destinationMatchesSource(let path):
            "Archive destination matches a selected source: \(path)"
        case .destinationInsideSource(let path):
            "Archive destination is inside a selected source directory: \(path)"
        case .destinationDoesNotMatchIntent:
            "Archive destination identity does not match its create/replace intent."
        case .archiveSizeLimitExceeded(let maximum):
            "Archive planning envelope exceeds \(maximum) bytes."
        case .planTooLarge(let maximum):
            "Archive plan exceeds \(maximum) retained bytes."
        case .staleSnapshot:
            "Archive plan belongs to a stale comparison snapshot."
        case .snapshotContentsChanged:
            "Archive comparison contents changed without advancing generation."
        case .sourceSetChanged:
            "Archive source set changed before execution."
        case .sourceRevisionChanged(let path):
            "Archive source revision changed before execution: \(path)"
        case .destinationParentChanged:
            "Archive destination parent changed before publication."
        case .destinationChanged:
            "Archive destination changed before publication."
        }
    }
}

public struct ArchiveGenerationManifestEntryMetadata: Hashable, Sendable {
    public static let reproducibleTimeSeconds: Int64 = 315_532_800

    public let permissions: UInt16
    public let modificationTimeSeconds: Int64
    public let modificationTimeNanoseconds: Int32

    fileprivate init(
        revision: ArchiveGenerationSourceRevision,
        policy: ArchiveGenerationMetadataPolicy
    ) {
        switch policy {
        case .reproducible:
            permissions = revision.identity.kind == .directory ? 0o700 : 0o600
            modificationTimeSeconds = Self.reproducibleTimeSeconds
            modificationTimeNanoseconds = 0
        case .preserveSource:
            permissions = revision.permissions
            modificationTimeSeconds = revision.modificationTimeSeconds
            modificationTimeNanoseconds = revision.modificationTimeNanoseconds
        }
    }
}

public struct ArchiveGenerationManifestEntry: Hashable, Sendable {
    public let selection: ArchiveGenerationSelectedEntry
    /// Byte-preserving, slash-separated, never directory-suffixed.
    public let archiveRelativePath: String
    public let source: ArchiveGenerationSourceItem
    public let metadata: ArchiveGenerationManifestEntryMetadata

    public var kind: ArchiveGenerationItemKind { source.revision.identity.kind }
    public var uncompressedByteCount: UInt64 {
        kind == .regularFile ? source.revision.byteCount : 0
    }

    fileprivate init(
        selection: ArchiveGenerationSelectedEntry,
        archiveRelativePath: String,
        source: ArchiveGenerationSourceItem,
        metadata: ArchiveGenerationManifestEntryMetadata
    ) {
        self.selection = selection
        self.archiveRelativePath = archiveRelativePath
        self.source = source
        self.metadata = metadata
    }
}

public enum ArchiveGenerationOmissionReason: String, CaseIterable, Hashable, Sendable {
    case filtered
    case missingSide
    case symbolicLink
    case specialFile
}

public struct ArchiveGenerationOmission: Hashable, Sendable {
    public let id: ArchiveGenerationEntryID
    public let side: ArchiveGenerationSide
    public let relativePath: String
    public let reason: ArchiveGenerationOmissionReason

    fileprivate init(
        id: ArchiveGenerationEntryID,
        side: ArchiveGenerationSide,
        relativePath: String,
        reason: ArchiveGenerationOmissionReason
    ) {
        self.id = id
        self.side = side
        self.relativePath = relativePath
        self.reason = reason
    }
}

/// Deterministic codec input. No source bytes are loaded and no directory is enumerated.
public struct ArchiveGenerationManifest: Hashable, Sendable {
    public static let version = 2

    public let pathPolicy: ArchiveGenerationPathPolicy
    public let options: ArchiveGenerationOutputOptions
    public let entries: [ArchiveGenerationManifestEntry]
    public let totalUncompressedByteCount: UInt64
    public let totalMetadataByteCount: UInt64
    public let totalPathUTF8ByteCount: Int
    public let totalPathComponentCount: UInt64
    /// Conservative planner envelope; executor must enforce `limits.maximumArchiveBytes` on output.
    public let planningArchiveByteEnvelope: UInt64
    public let manifestSHA256: [UInt8]

    fileprivate init(
        pathPolicy: ArchiveGenerationPathPolicy,
        options: ArchiveGenerationOutputOptions,
        entries: [ArchiveGenerationManifestEntry],
        totalUncompressedByteCount: UInt64,
        totalMetadataByteCount: UInt64,
        totalPathUTF8ByteCount: Int,
        totalPathComponentCount: UInt64,
        planningArchiveByteEnvelope: UInt64,
        manifestSHA256: [UInt8]
    ) {
        self.pathPolicy = pathPolicy
        self.options = options
        self.entries = entries
        self.totalUncompressedByteCount = totalUncompressedByteCount
        self.totalMetadataByteCount = totalMetadataByteCount
        self.totalPathUTF8ByteCount = totalPathUTF8ByteCount
        self.totalPathComponentCount = totalPathComponentCount
        self.planningArchiveByteEnvelope = planningArchiveByteEnvelope
        self.manifestSHA256 = manifestSHA256
    }
}

public enum ArchiveGenerationAuthorityPurpose: Hashable, Sendable {
    case readSource(ArchiveGenerationEntryID, ArchiveGenerationSide)
    case createDestination
    case replaceDestination
}

public struct ArchiveGenerationAuthorityRequirement: Hashable, Sendable {
    public let purpose: ArchiveGenerationAuthorityPurpose
    public let requestedURL: URL
    public let canonicalURL: URL
    public let requiredCoverage: ArchiveGenerationAuthorityCoverage
    public let authority: ArchiveGenerationAccessAuthority

    fileprivate init(
        purpose: ArchiveGenerationAuthorityPurpose,
        requestedURL: URL,
        canonicalURL: URL,
        requiredCoverage: ArchiveGenerationAuthorityCoverage,
        authority: ArchiveGenerationAccessAuthority
    ) {
        self.purpose = purpose
        self.requestedURL = requestedURL
        self.canonicalURL = canonicalURL
        self.requiredCoverage = requiredCoverage
        self.authority = authority
    }
}

public struct ArchiveGenerationPlanningReceipt: Hashable, Sendable {
    public static let version = 2

    public let snapshotCAS: ArchiveGenerationSnapshotCAS
    public let manifestSHA256: [UInt8]
    public let planSHA256: [UInt8]
    public let includedItemCount: Int
    public let omittedItemCount: Int
    public let sourceByteCount: UInt64
    public let planningArchiveByteEnvelope: UInt64
    public let estimatedWorkUnits: UInt64

    fileprivate init(
        snapshotCAS: ArchiveGenerationSnapshotCAS,
        manifestSHA256: [UInt8],
        planSHA256: [UInt8],
        includedItemCount: Int,
        omittedItemCount: Int,
        sourceByteCount: UInt64,
        planningArchiveByteEnvelope: UInt64,
        estimatedWorkUnits: UInt64
    ) {
        self.snapshotCAS = snapshotCAS
        self.manifestSHA256 = manifestSHA256
        self.planSHA256 = planSHA256
        self.includedItemCount = includedItemCount
        self.omittedItemCount = omittedItemCount
        self.sourceByteCount = sourceByteCount
        self.planningArchiveByteEnvelope = planningArchiveByteEnvelope
        self.estimatedWorkUnits = estimatedWorkUnits
    }
}

public enum ArchiveGenerationSourceAccessContract: String, Hashable, Sendable {
    case balancedAuthorityThenPinnedRootDescriptorRelativeNoFollow
}

public enum ArchiveGenerationSourceRevisionContract: String, Hashable, Sendable {
    case exactIdentityContentMetadataAndBoundedDirectoryRevisionHeldOrRevalidatedThroughEncoding
}

public enum ArchiveGenerationDestinationContract: String, Hashable, Sendable {
    case exactParentVacancyOrFullExistingRevisionCompareAndSwapRejectingSourceAliases
}

public enum ArchiveGenerationOverwriteContract: String, Hashable, Sendable {
    case privateStageThenAtomicCreateOrExactReplacementNeverInPlace
}

public enum ArchiveGenerationSandboxContract: String, Hashable, Sendable {
    case balanceEveryDeclaredScopeAroundValidationEncodingAndPublication
}

public enum ArchiveGenerationCodecContract: String, Hashable, Sendable {
    case exactCapabilityRevisionDeterministicDescriptorInputAndBoundedOutputWithoutShell
}

public enum ArchiveGenerationPathContract: String, Hashable, Sendable {
    case bytePreservingASCIIPortableV1ManifestNamesAndDescriptorPathsNeverURLWritePaths
}

public enum ArchiveGenerationCancellationContract: String, Hashable, Sendable {
    case noPublicationBeforeImmediateFinalCheckThenCommittedCompareMissOrUncertain
}

public enum ArchiveGenerationPlanUseContract: String, Hashable, Sendable {
    case consumePlanDigestOnceAfterSnapshotSourceAndDestinationCAS
}

public enum ArchiveGenerationStagingContract: String, Hashable, Sendable {
    case private0700Directory0600LeafBoundedSyncThenPublishAndSyncParent
}

/// Mandatory side-effect boundary. Implementations may not hand URL paths to a codec, recurse beyond
/// manifest entries, follow links, overwrite in place, or treat security-scope acquisition as identity.
public struct ArchiveGenerationExecutorContract: Hashable, Sendable {
    public static let required = ArchiveGenerationExecutorContract()
    public static let stagingDirectoryPermissions: UInt16 = 0o700
    public static let stagingFilePermissions: UInt16 = 0o600

    public let sourceAccess =
        ArchiveGenerationSourceAccessContract.balancedAuthorityThenPinnedRootDescriptorRelativeNoFollow
    public let sourceRevision =
        ArchiveGenerationSourceRevisionContract
        .exactIdentityContentMetadataAndBoundedDirectoryRevisionHeldOrRevalidatedThroughEncoding
    public let destination =
        ArchiveGenerationDestinationContract
        .exactParentVacancyOrFullExistingRevisionCompareAndSwapRejectingSourceAliases
    public let overwrite =
        ArchiveGenerationOverwriteContract.privateStageThenAtomicCreateOrExactReplacementNeverInPlace
    public let sandbox =
        ArchiveGenerationSandboxContract.balanceEveryDeclaredScopeAroundValidationEncodingAndPublication
    public let codec =
        ArchiveGenerationCodecContract
        .exactCapabilityRevisionDeterministicDescriptorInputAndBoundedOutputWithoutShell
    public let paths =
        ArchiveGenerationPathContract
        .bytePreservingASCIIPortableV1ManifestNamesAndDescriptorPathsNeverURLWritePaths
    public let cancellation =
        ArchiveGenerationCancellationContract
        .noPublicationBeforeImmediateFinalCheckThenCommittedCompareMissOrUncertain
    public let planUse =
        ArchiveGenerationPlanUseContract.consumePlanDigestOnceAfterSnapshotSourceAndDestinationCAS
    public let staging =
        ArchiveGenerationStagingContract.private0700Directory0600LeafBoundedSyncThenPublishAndSyncParent

    public init() {}
}

/// Complete immutable execution plan. Construction performs no filesystem, codec, UI, process, or
/// security-scope operation.
public struct ArchiveGenerationPlan: Hashable, Sendable {
    public let pathPolicy: ArchiveGenerationPathPolicy
    public let directoryRevisionPolicy: ArchiveGenerationDirectoryRevisionPolicy
    public let snapshotCAS: ArchiveGenerationSnapshotCAS
    public let selection: ArchiveGenerationSelection
    public let inclusionPolicy: ArchiveGenerationInclusionPolicy
    public let manifest: ArchiveGenerationManifest
    public let omissions: [ArchiveGenerationOmission]
    public let destination: ArchiveGenerationDestination
    public let executorCapabilities: ArchiveGenerationExecutorCapabilities
    public let authorityRequirements: [ArchiveGenerationAuthorityRequirement]
    public let receipt: ArchiveGenerationPlanningReceipt
    public let limits: ArchiveGenerationLimits
    public let executorContract: ArchiveGenerationExecutorContract

    fileprivate init(
        snapshotCAS: ArchiveGenerationSnapshotCAS,
        selection: ArchiveGenerationSelection,
        inclusionPolicy: ArchiveGenerationInclusionPolicy,
        manifest: ArchiveGenerationManifest,
        omissions: [ArchiveGenerationOmission],
        destination: ArchiveGenerationDestination,
        executorCapabilities: ArchiveGenerationExecutorCapabilities,
        authorityRequirements: [ArchiveGenerationAuthorityRequirement],
        receipt: ArchiveGenerationPlanningReceipt,
        limits: ArchiveGenerationLimits
    ) {
        pathPolicy = manifest.pathPolicy
        directoryRevisionPolicy = .required
        self.snapshotCAS = snapshotCAS
        self.selection = selection
        self.inclusionPolicy = inclusionPolicy
        self.manifest = manifest
        self.omissions = omissions
        self.destination = destination
        self.executorCapabilities = executorCapabilities
        self.authorityRequirements = authorityRequirements
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func validateCurrentSnapshot(
        _ snapshot: ArchiveGenerationComparisonSnapshot
    ) throws {
        do {
            let reference = ArchiveGenerationSnapshotReference(snapshot)
            guard reference == snapshotCAS.reference else {
                throw ArchiveGenerationPlanningError.staleSnapshot(
                    expected: snapshotCAS.reference,
                    actual: reference
                )
            }
            let current = try ArchiveGenerationWorkflow.snapshotCAS(snapshot, limits: limits)
            guard current.stateSHA256 == snapshotCAS.stateSHA256 else {
                throw ArchiveGenerationPlanningError.snapshotContentsChanged
            }
        } catch is CancellationError {
            throw ArchiveGenerationPlanningError.cancelled
        }
    }

    /// Executor calls this after staging and at its serialized commit boundary while holding source
    /// and destination leases. After return it performs no cancellable work before the publication
    /// syscall. `currentSources` contains one revision per unique planned source identity.
    public func validateForPublication(
        currentSnapshot: ArchiveGenerationComparisonSnapshot,
        currentSources: [ArchiveGenerationSourceRevision],
        currentDestinationParent: ArchiveGenerationCanonicalDirectoryIdentity,
        currentDestinationRevision: ArchiveGenerationSourceRevision?
    ) throws {
        do {
            try validateCurrentSnapshot(currentSnapshot)
            try Task.checkCancellation()

            var expected: [ArchiveGenerationSourceIdentityKey: ArchiveGenerationSourceRevision] = [:]
            for entry in manifest.entries {
                let revision = entry.source.revision
                let key = ArchiveGenerationSourceIdentityKey(revision.identity)
                if let prior = expected[key],
                    !archiveGenerationSourceRevisionEqual(prior, revision)
                {
                    throw ArchiveGenerationPlanningError.conflictingSourceRevision(
                        path: revision.identity.canonicalURL.path
                    )
                }
                expected[key] = revision
            }
            guard currentSources.count == expected.count else {
                throw ArchiveGenerationPlanningError.sourceSetChanged
            }
            var work = ArchiveGenerationWorkBudget(
                maximum: limits.maximumWorkUnits,
                cancellationCheckInterval: limits.cancellationCheckInterval
            )
            for revision in currentSources {
                try work.checkpoint()
                guard try archiveGenerationSourceRevisionIsBounded(revision, limits: limits) else {
                    throw ArchiveGenerationPlanningError.sourceRevisionChanged(
                        revision.identity.canonicalURL.path
                    )
                }
            }
            try work.consumeSortUTF8UpperBound(
                values: currentSources.flatMap(archiveGenerationSourceIdentitySortStrings)
            )
            try work.consumeSortUTF8UpperBound(
                values: expected.values.flatMap(archiveGenerationSourceIdentitySortStrings)
            )
            var actual = currentSources
            try archiveGenerationDeterministicSort(&actual) {
                try archiveGenerationSourceRevisionPrecedes($0, $1)
            }
            var orderedExpected = Array(expected.values)
            try archiveGenerationDeterministicSort(&orderedExpected) {
                try archiveGenerationSourceRevisionPrecedes($0, $1)
            }
            for index in actual.indices {
                try work.checkpoint()
                if index > actual.startIndex,
                    ArchiveGenerationSourceIdentityKey(actual[index - 1].identity)
                        == ArchiveGenerationSourceIdentityKey(actual[index].identity)
                {
                    throw ArchiveGenerationPlanningError.sourceSetChanged
                }
                guard
                    ArchiveGenerationSourceIdentityKey(orderedExpected[index].identity)
                        == ArchiveGenerationSourceIdentityKey(actual[index].identity)
                else {
                    throw ArchiveGenerationPlanningError.sourceSetChanged
                }
                guard
                    archiveGenerationSourceRevisionEqual(
                        orderedExpected[index],
                        actual[index]
                    )
                else {
                    throw ArchiveGenerationPlanningError.sourceRevisionChanged(
                        orderedExpected[index].identity.canonicalURL.path
                    )
                }
            }

            guard
                archiveGenerationDirectoryIdentityEqual(
                    currentDestinationParent,
                    destination.intent.canonicalParent
                )
            else {
                throw ArchiveGenerationPlanningError.destinationParentChanged
            }
            guard
                try archiveGenerationDirectoryIdentityIsBounded(
                    currentDestinationParent,
                    limits: limits
                )
            else {
                throw ArchiveGenerationPlanningError.destinationParentChanged
            }
            if let currentDestinationRevision {
                guard
                    try archiveGenerationSourceRevisionIsBounded(
                        currentDestinationRevision,
                        limits: limits
                    )
                else {
                    throw ArchiveGenerationPlanningError.destinationChanged
                }
            }
            let sourceNodes = Set(expected.values.map(\.identity.node))
            switch destination.intent {
            case .createNew:
                guard currentDestinationRevision == nil else {
                    throw ArchiveGenerationPlanningError.destinationChanged
                }
            case .replaceExisting(let expectedRevision):
                guard
                    currentDestinationRevision.map({
                        archiveGenerationSourceRevisionEqual($0, expectedRevision)
                    }) == true,
                    !sourceNodes.contains(expectedRevision.identity.node)
                else {
                    throw ArchiveGenerationPlanningError.destinationChanged
                }
            }
            // Last cancellable instruction in the executor's serialized commit boundary.
            try Task.checkCancellation()
        } catch is CancellationError {
            throw ArchiveGenerationPlanningError.cancelled
        }
    }
}

public enum ArchiveGenerationExecutionDisposition: String, CaseIterable, Hashable, Sendable {
    case created
    case replaced
}

/// Deterministic description of proven durable archive bytes. Filesystem publication identity is a
/// separate executor proof because inode and timestamps are intentionally nondeterministic.
public struct ArchiveGenerationExecutionReceipt: Hashable, Sendable {
    public static let version = 2

    public let planSHA256: [UInt8]
    public let disposition: ArchiveGenerationExecutionDisposition
    public let committedByteCount: UInt64
    public let archiveContentSHA256: [UInt8]
    public let archivedItemCount: Int
    public let archivedSourceByteCount: UInt64

    fileprivate init(
        planSHA256: [UInt8],
        disposition: ArchiveGenerationExecutionDisposition,
        committedByteCount: UInt64,
        archiveContentSHA256: [UInt8],
        archivedItemCount: Int,
        archivedSourceByteCount: UInt64
    ) {
        self.planSHA256 = planSHA256
        self.disposition = disposition
        self.committedByteCount = committedByteCount
        self.archiveContentSHA256 = archiveContentSHA256
        self.archivedItemCount = archivedItemCount
        self.archivedSourceByteCount = archivedSourceByteCount
    }
}

public enum ArchiveGenerationExecutionFailureCode: String, CaseIterable, Hashable, Sendable {
    case invalidPlan
    case staleSnapshot
    case sourceChanged
    case destinationChanged
    case authorityUnavailable
    case codecUnsupported
    case itemLimitExceeded
    case byteLimitExceeded
    case stagingFailed
    case publicationFailed
    case contractUnsupported
}

public struct ArchiveGenerationExecutionFailure: Hashable, Sendable {
    public let code: ArchiveGenerationExecutionFailureCode
    public let destinationURL: URL

    fileprivate init(code: ArchiveGenerationExecutionFailureCode, destinationURL: URL) {
        self.code = code
        self.destinationURL = destinationURL
    }
}

public struct ArchiveGenerationExecutionCancellation: Hashable, Sendable {
    /// Cancellation is reportable only while publication is proven not to have started.
    public let publicationStarted: Bool

    fileprivate init() {
        publicationStarted = false
    }
}

public struct ArchiveGenerationPublicationUncertainty: Hashable, Sendable {
    public let destinationURL: URL
    public let planSHA256: [UInt8]

    fileprivate init(destinationURL: URL, planSHA256: [UInt8]) {
        self.destinationURL = destinationURL
        self.planSHA256 = planSHA256
    }
}

public enum ArchiveGenerationExecutionOutcome: Hashable, Sendable {
    case completed(ArchiveGenerationExecutionReceipt)
    case failed(ArchiveGenerationExecutionFailure)
    case cancelled(ArchiveGenerationExecutionCancellation)
    case publicationUncertain(ArchiveGenerationPublicationUncertainty)
}

/// Constructs outcomes whose public fields cannot contradict the plan.
public enum ArchiveGenerationExecutionOutcomeFactory: Sendable {
    public static func completed(
        plan: ArchiveGenerationPlan,
        committedRevision: ArchiveGenerationSourceRevision,
        archiveContentSHA256: [UInt8]
    ) -> ArchiveGenerationExecutionOutcome {
        let expectedDisposition: ArchiveGenerationExecutionDisposition
        switch plan.destination.intent {
        case .createNew: expectedDisposition = .created
        case .replaceExisting: expectedDisposition = .replaced
        }
        let sourceNodes = Set(plan.manifest.entries.map(\.source.revision.identity.node))
        let replacedNode: ArchiveGenerationNodeIdentity?
        switch plan.destination.intent {
        case .createNew:
            replacedNode = nil
        case .replaceExisting(let revision):
            replacedNode = revision.identity.node
        }
        guard committedRevision.identity.kind == .regularFile,
            committedRevision.directoryChildCount == 0,
            committedRevision.directoryChildNameUTF8ByteCount == 0,
            archiveGenerationUTF8Equal(
                committedRevision.identity.canonicalURL.path,
                plan.destination.intent.canonicalURL.path
            ),
            archiveGenerationDirectoryIdentityEqual(
                committedRevision.identity.root,
                plan.destination.intent.canonicalParent
            ),
            archiveGenerationAbsolutePath(
                committedRevision.identity.relativePath,
                under: committedRevision.identity.root.canonicalURL.path
            ).utf8.elementsEqual(committedRevision.identity.canonicalURL.path.utf8),
            archiveGenerationIsStrictNormalizedRelativePath(
                committedRevision.identity.relativePath,
                maximumUTF8Bytes: plan.limits.maximumPathUTF8Bytes,
                maximumDepth: plan.limits.maximumPathDepth
            ),
            committedRevision.linkCount > 0,
            committedRevision.permissions == plan.manifest.options.destinationPermissions,
            committedRevision.modificationTimeNanoseconds >= 0,
            committedRevision.modificationTimeNanoseconds < 1_000_000_000,
            committedRevision.statusChangeTimeNanoseconds >= 0,
            committedRevision.statusChangeTimeNanoseconds < 1_000_000_000,
            committedRevision.byteCount <= plan.manifest.planningArchiveByteEnvelope,
            !sourceNodes.contains(committedRevision.identity.node),
            committedRevision.identity.node != replacedNode,
            committedRevision.contentSHA256.count == SHA256.Digest.byteCount,
            committedRevision.metadataSHA256.count == SHA256.Digest.byteCount,
            archiveContentSHA256.count == SHA256.Digest.byteCount,
            committedRevision.contentSHA256 == archiveContentSHA256
        else {
            return publicationUncertain(plan: plan)
        }
        return .completed(
            ArchiveGenerationExecutionReceipt(
                planSHA256: plan.receipt.planSHA256,
                disposition: expectedDisposition,
                committedByteCount: committedRevision.byteCount,
                archiveContentSHA256: archiveContentSHA256,
                archivedItemCount: plan.manifest.entries.count,
                archivedSourceByteCount: plan.manifest.totalUncompressedByteCount
            )
        )
    }

    public static func failed(
        plan: ArchiveGenerationPlan,
        code: ArchiveGenerationExecutionFailureCode
    ) -> ArchiveGenerationExecutionOutcome {
        .failed(
            ArchiveGenerationExecutionFailure(
                code: code,
                destinationURL: plan.destination.intent.canonicalURL
            )
        )
    }

    public static func cancelled(
        plan: ArchiveGenerationPlan
    ) -> ArchiveGenerationExecutionOutcome {
        .cancelled(ArchiveGenerationExecutionCancellation())
    }

    public static func publicationUncertain(
        plan: ArchiveGenerationPlan
    ) -> ArchiveGenerationExecutionOutcome {
        .publicationUncertain(
            ArchiveGenerationPublicationUncertainty(
                destinationURL: plan.destination.intent.canonicalURL,
                planSHA256: plan.receipt.planSHA256
            )
        )
    }
}

/// Side-effect implementation supplied by an app/platform layer. It must enforce
/// `ArchiveGenerationExecutorContract.required`, exact capability revision, and plan CAS checks.
public protocol ArchiveGenerationPlanExecutor: Sendable {
    func execute(
        _ plan: ArchiveGenerationPlan,
        /// Executor obtains this after staging while holding destination/source leases, then calls
        /// `plan.validateForPublication` in the same serialized commit boundary.
        currentSnapshot: @escaping @Sendable () async throws -> ArchiveGenerationComparisonSnapshot
    ) async -> ArchiveGenerationExecutionOutcome
}

public enum ArchiveGenerationWorkflow: Sendable {
    public static func plan(_ request: ArchiveGenerationRequest) throws -> ArchiveGenerationPlan {
        do {
            return try makePlan(request)
        } catch is CancellationError {
            throw ArchiveGenerationPlanningError.cancelled
        }
    }

    fileprivate static func snapshotCAS(
        _ snapshot: ArchiveGenerationComparisonSnapshot,
        limits: ArchiveGenerationLimits
    ) throws -> ArchiveGenerationSnapshotCAS {
        try validate(limits)
        var work = ArchiveGenerationWorkBudget(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval
        )
        let prepared = try validateSnapshot(snapshot, limits: limits, work: &work)
        return ArchiveGenerationSnapshotCAS(
            reference: ArchiveGenerationSnapshotReference(snapshot),
            stateSHA256: try snapshotDigest(
                snapshot,
                entries: prepared,
                limits: limits,
                work: &work
            )
        )
    }

    private static func makePlan(_ request: ArchiveGenerationRequest) throws -> ArchiveGenerationPlan {
        try Task.checkCancellation()
        try validate(request.limits)
        var work = ArchiveGenerationWorkBudget(
            maximum: request.limits.maximumWorkUnits,
            cancellationCheckInterval: request.limits.cancellationCheckInterval
        )
        let entries = try validateSnapshot(
            request.snapshot,
            limits: request.limits,
            work: &work
        )
        let snapshotCAS = ArchiveGenerationSnapshotCAS(
            reference: ArchiveGenerationSnapshotReference(request.snapshot),
            stateSHA256: try snapshotDigest(
                request.snapshot,
                entries: entries,
                limits: request.limits,
                work: &work
            )
        )
        let preparedFilter = try validate(
            request.inclusionPolicy.filter,
            limits: request.limits,
            work: &work
        )
        try validate(
            request.outputOptions,
            capabilities: request.executorCapabilities,
            limits: request.limits,
            work: &work
        )
        try validate(
            request.destination,
            limits: request.limits,
            work: &work
        )

        let candidates = try select(
            entries: entries,
            selection: request.selection,
            policy: request.inclusionPolicy,
            limits: request.limits,
            work: &work
        )
        let canonicalSelection = ArchiveGenerationSelection.only(
            candidates.map(\.selection)
        )
        let prefix = try request.outputOptions.pathPrefix.map {
            try normalizeArchivePath(
                $0,
                role: .prefix,
                limits: request.limits,
                work: &work
            )
        }
        let canonicalOptions = ArchiveGenerationOutputOptions(
            format: request.outputOptions.format,
            compression: request.outputOptions.compression,
            compressionLevel: request.outputOptions.compressionLevel,
            metadataPolicy: request.outputOptions.metadataPolicy,
            pathPrefix: prefix,
            archiveComment: request.outputOptions.archiveComment,
            destinationPermissions: request.outputOptions.destinationPermissions
        )
        var manifestEntries: [ArchiveGenerationManifestEntry] = []
        manifestEntries.reserveCapacity(candidates.count)
        var omissions: [ArchiveGenerationOmission] = []
        omissions.reserveCapacity(candidates.count)
        var totalSourceBytes: UInt64 = 0
        var totalMetadataBytes: UInt64 = 0
        var totalPathBytes = 0
        var totalPathComponents: UInt64 = 0

        for candidate in candidates {
            try work.checkpoint()
            let explicitArchivePath = try candidate.selection.archiveRelativePath.map {
                try normalizeArchivePath(
                    $0,
                    role: .archive,
                    limits: request.limits,
                    work: &work
                )
            }
            guard let source = candidate.entry.item(on: candidate.selection.side) else {
                switch request.inclusionPolicy.missingSide {
                case .reject:
                    throw ArchiveGenerationPlanningError.missingSide(
                        candidate.entry.id,
                        candidate.selection.side
                    )
                case .omit:
                    omissions.append(
                        ArchiveGenerationOmission(
                            id: candidate.entry.id,
                            side: candidate.selection.side,
                            relativePath: candidate.entry.relativePath,
                            reason: .missingSide
                        )
                    )
                    continue
                }
            }
            let kind = source.revision.identity.kind
            guard
                try preparedFilter.matches(
                    entry: candidate.entry,
                    sourcePath: source.revision.identity.relativePath,
                    kind: kind,
                    work: &work
                )
            else {
                omissions.append(
                    ArchiveGenerationOmission(
                        id: candidate.entry.id,
                        side: candidate.selection.side,
                        relativePath: candidate.entry.relativePath,
                        reason: .filtered
                    )
                )
                continue
            }
            if let reason = try omissionReason(
                for: kind,
                path: source.revision.identity.relativePath,
                policy: request.inclusionPolicy
            ) {
                omissions.append(
                    ArchiveGenerationOmission(
                        id: candidate.entry.id,
                        side: candidate.selection.side,
                        relativePath: candidate.entry.relativePath,
                        reason: reason
                    )
                )
                continue
            }

            let basePath =
                explicitArchivePath
                ?? source.revision.identity.relativePath
            let requestedArchivePath = prefix.map { "\($0)/\(basePath)" } ?? basePath
            let archivePath = try normalizeArchivePath(
                requestedArchivePath,
                role: .archive,
                limits: request.limits,
                work: &work
            )
            let pathByteCount = archivePath.utf8.count
            totalPathBytes = try add(
                pathByteCount,
                to: totalPathBytes,
                maximum: request.limits.maximumTotalPathUTF8Bytes,
                error: .totalPathsTooLarge(
                    maximumBytes: request.limits.maximumTotalPathUTF8Bytes
                )
            )
            let componentCount = UInt64(archiveGenerationUTF8PathComponents(archivePath).count)
            totalPathComponents = try add(
                componentCount,
                to: totalPathComponents,
                maximum: request.limits.maximumTotalPathComponents,
                error: .tooManyPathComponents(
                    maximum: request.limits.maximumTotalPathComponents
                )
            )
            let sourceBytes = kind == .regularFile ? source.revision.byteCount : 0
            guard sourceBytes <= request.limits.maximumItemBytes else {
                throw ArchiveGenerationPlanningError.itemTooLarge(
                    path: source.revision.identity.relativePath,
                    maximumBytes: request.limits.maximumItemBytes
                )
            }
            totalSourceBytes = try add(
                sourceBytes,
                to: totalSourceBytes,
                maximum: request.limits.maximumTotalSourceBytes,
                error: .sourceBytesTooLarge(
                    maximumBytes: request.limits.maximumTotalSourceBytes
                )
            )
            totalMetadataBytes = try add(
                source.revision.metadataByteCount,
                to: totalMetadataBytes,
                maximum: request.limits.maximumMetadataBytes,
                error: .metadataTooLarge(maximumBytes: request.limits.maximumMetadataBytes)
            )
            manifestEntries.append(
                ArchiveGenerationManifestEntry(
                    selection: ArchiveGenerationSelectedEntry(
                        id: candidate.entry.id,
                        side: candidate.selection.side,
                        archiveRelativePath: explicitArchivePath
                    ),
                    archiveRelativePath: archivePath,
                    source: source,
                    metadata: ArchiveGenerationManifestEntryMetadata(
                        revision: source.revision,
                        policy: canonicalOptions.metadataPolicy
                    )
                )
            )
        }
        guard !manifestEntries.isEmpty else {
            throw ArchiveGenerationPlanningError.emptySelection
        }
        try work.consumeSortUTF8UpperBound(values: manifestEntries.map(\.archiveRelativePath))
        try archiveGenerationDeterministicSort(&manifestEntries) {
            try archiveGenerationUTF8Precedes(
                $0.archiveRelativePath,
                $1.archiveRelativePath
            )
        }
        try work.consumeSortUTF8UpperBound(values: omissions.map(\.id.rawValue))
        try archiveGenerationDeterministicSort(&omissions, by: omissionPrecedes)
        try validateArchivePaths(manifestEntries, work: &work)
        try validateDestinationDoesNotOverlapSources(
            request.destination,
            entries: manifestEntries,
            work: &work
        )

        let archiveEnvelope = try archiveByteEnvelope(
            sourceBytes: totalSourceBytes,
            format: canonicalOptions.format,
            compression: canonicalOptions.compression,
            pathBytes: totalPathBytes,
            entryCount: manifestEntries.count,
            maximum: request.limits.maximumArchiveBytes
        )
        let manifestDigest = try manifestDigest(
            options: canonicalOptions,
            entries: manifestEntries,
            sourceBytes: totalSourceBytes,
            metadataBytes: totalMetadataBytes,
            pathBytes: totalPathBytes,
            pathComponents: totalPathComponents,
            archiveEnvelope: archiveEnvelope,
            limits: request.limits,
            work: &work
        )
        let manifest = ArchiveGenerationManifest(
            pathPolicy: .required,
            options: canonicalOptions,
            entries: manifestEntries,
            totalUncompressedByteCount: totalSourceBytes,
            totalMetadataByteCount: totalMetadataBytes,
            totalPathUTF8ByteCount: totalPathBytes,
            totalPathComponentCount: totalPathComponents,
            planningArchiveByteEnvelope: archiveEnvelope,
            manifestSHA256: manifestDigest
        )
        let authorities = authorityRequirements(
            entries: manifestEntries,
            destination: request.destination
        )
        let retainedBytes = try retainedPlanByteCount(
            selection: canonicalSelection,
            policy: request.inclusionPolicy,
            manifest: manifest,
            omissions: omissions,
            destination: request.destination,
            capabilities: request.executorCapabilities,
            authorities: authorities,
            maximum: request.limits.maximumRetainedPlanBytes
        )
        try work.consume(UInt64(retainedBytes))
        let planDigest = try planDigest(
            snapshotCAS: snapshotCAS,
            selection: canonicalSelection,
            policy: request.inclusionPolicy,
            manifestSHA256: manifestDigest,
            omissions: omissions,
            destination: request.destination,
            capabilities: request.executorCapabilities,
            limits: request.limits,
            work: &work
        )
        let receipt = ArchiveGenerationPlanningReceipt(
            snapshotCAS: snapshotCAS,
            manifestSHA256: manifestDigest,
            planSHA256: planDigest,
            includedItemCount: manifestEntries.count,
            omittedItemCount: omissions.count,
            sourceByteCount: totalSourceBytes,
            planningArchiveByteEnvelope: archiveEnvelope,
            estimatedWorkUnits: work.consumed
        )
        try Task.checkCancellation()
        return ArchiveGenerationPlan(
            snapshotCAS: snapshotCAS,
            selection: canonicalSelection,
            inclusionPolicy: request.inclusionPolicy,
            manifest: manifest,
            omissions: omissions,
            destination: request.destination,
            executorCapabilities: request.executorCapabilities,
            authorityRequirements: authorities,
            receipt: receipt,
            limits: request.limits
        )
    }

    private static func validate(_ limits: ArchiveGenerationLimits) throws {
        let boundedInts: [(ArchiveGenerationLimit, Int, Int)] = [
            (.snapshotEntries, limits.maximumSnapshotEntries, ArchiveGenerationLimits.hardMaximumSnapshotEntries),
            (.selectedEntries, limits.maximumSelectedEntries, ArchiveGenerationLimits.hardMaximumSelectedEntries),
            (.filterRules, limits.maximumFilterRules, ArchiveGenerationLimits.hardMaximumFilterRules),
            (.identifierUTF8Bytes, limits.maximumIdentifierUTF8Bytes, ArchiveGenerationLimits.hardMaximumIdentifierUTF8Bytes),
            (.pathUTF8Bytes, limits.maximumPathUTF8Bytes, ArchiveGenerationLimits.hardMaximumPathUTF8Bytes),
            (.pathDepth, limits.maximumPathDepth, ArchiveGenerationLimits.hardMaximumPathDepth),
            (.totalPathUTF8Bytes, limits.maximumTotalPathUTF8Bytes, ArchiveGenerationLimits.hardMaximumTotalPathUTF8Bytes),
            (.optionUTF8Bytes, limits.maximumOptionUTF8Bytes, ArchiveGenerationLimits.hardMaximumOptionUTF8Bytes),
            (.retainedPlanBytes, limits.maximumRetainedPlanBytes, ArchiveGenerationLimits.hardMaximumRetainedPlanBytes)
        ]
        for (name, value, hardMaximum) in boundedInts where value < 1 || value > hardMaximum {
            throw ArchiveGenerationPlanningError.invalidLimit(name)
        }
        let boundedUInts: [(ArchiveGenerationLimit, UInt64, UInt64)] = [
            (.totalPathComponents, limits.maximumTotalPathComponents, ArchiveGenerationLimits.hardMaximumTotalPathComponents),
            (.itemBytes, limits.maximumItemBytes, ArchiveGenerationLimits.hardMaximumItemBytes),
            (.totalSourceBytes, limits.maximumTotalSourceBytes, ArchiveGenerationLimits.hardMaximumTotalSourceBytes),
            (.metadataBytes, limits.maximumMetadataBytes, ArchiveGenerationLimits.hardMaximumMetadataBytes),
            (.archiveBytes, limits.maximumArchiveBytes, ArchiveGenerationLimits.hardMaximumArchiveBytes),
            (.workUnits, limits.maximumWorkUnits, ArchiveGenerationLimits.hardMaximumWorkUnits)
        ]
        for (name, value, hardMaximum) in boundedUInts where value < 1 || value > hardMaximum {
            throw ArchiveGenerationPlanningError.invalidLimit(name)
        }
        guard limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval <= 65_536
        else {
            throw ArchiveGenerationPlanningError.invalidLimit(.cancellationCheckInterval)
        }
    }

    private static func validateSnapshot(
        _ snapshot: ArchiveGenerationComparisonSnapshot,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> [ArchiveGenerationComparisonEntry] {
        guard snapshot.entries.count <= limits.maximumSnapshotEntries else {
            throw ArchiveGenerationPlanningError.tooManySnapshotEntries(
                maximum: limits.maximumSnapshotEntries
            )
        }
        var inputEntries = snapshot.entries
        try work.consumeSortUTF8UpperBound(values: inputEntries.map(\.id.rawValue))
        try work.consumeSortUTF8UpperBound(values: inputEntries.map(\.relativePath))
        try archiveGenerationDeterministicSort(&inputEntries) {
            if !archiveGenerationUTF8Equal($0.id.rawValue, $1.id.rawValue) {
                return try archiveGenerationUTF8Precedes($0.id.rawValue, $1.id.rawValue)
            }
            return try archiveGenerationUTF8Precedes($0.relativePath, $1.relativePath)
        }
        var identifiers: Set<[UInt8]> = []
        identifiers.reserveCapacity(snapshot.entries.count)
        var comparisonPaths: Set<[UInt8]> = []
        comparisonPaths.reserveCapacity(snapshot.entries.count)
        var revisionsByIdentity: [ArchiveGenerationSourceIdentityKey: ArchiveGenerationSourceRevision] = [:]
        var sourcesByLocation: [ArchiveGenerationSourceLocation: ArchiveGenerationLocatedSource] = [:]
        var prepared: [ArchiveGenerationComparisonEntry] = []
        prepared.reserveCapacity(snapshot.entries.count)
        for entry in inputEntries {
            try work.checkpoint()
            let identifierBytes = try boundedUTF8Count(
                entry.id.rawValue,
                maximum: limits.maximumIdentifierUTF8Bytes
            )
            guard identifierBytes > 0,
                identifierBytes <= limits.maximumIdentifierUTF8Bytes,
                !entry.id.rawValue.contains("\0")
            else {
                throw ArchiveGenerationPlanningError.invalidEntryIdentifier(entry.id.rawValue)
            }
            guard identifiers.insert(Array(entry.id.rawValue.utf8)).inserted else {
                throw ArchiveGenerationPlanningError.duplicateEntryIdentifier(entry.id)
            }
            let comparisonPath = try normalizeSourcePath(
                entry.relativePath,
                role: .comparison,
                limits: limits,
                work: &work
            )
            guard archiveGenerationUTF8Equal(comparisonPath, entry.relativePath) else {
                throw ArchiveGenerationPlanningError.invalidComparisonEntry(entry.id)
            }
            guard comparisonPaths.insert(Array(comparisonPath.utf8)).inserted else {
                throw ArchiveGenerationPlanningError.invalidComparisonEntry(entry.id)
            }
            for (side, item) in [
                (ArchiveGenerationSide.left, entry.left),
                (ArchiveGenerationSide.right, entry.right)
            ] {
                guard let item else { continue }
                try validate(
                    item,
                    entryID: entry.id,
                    side: side,
                    limits: limits,
                    work: &work
                )
                let identityKey = ArchiveGenerationSourceIdentityKey(item.revision.identity)
                if let existing = revisionsByIdentity[identityKey],
                    !archiveGenerationSourceRevisionEqual(existing, item.revision)
                {
                    throw ArchiveGenerationPlanningError.conflictingSourceRevision(
                        path: item.revision.identity.canonicalURL.path
                    )
                }
                revisionsByIdentity[identityKey] = item.revision
                let location = ArchiveGenerationSourceLocation(
                    side: side,
                    root: item.revision.identity.root,
                    relativePath: item.revision.identity.relativePath
                )
                guard
                    sourcesByLocation.updateValue(
                        ArchiveGenerationLocatedSource(entryID: entry.id, item: item),
                        forKey: location
                    ) == nil
                else {
                    throw ArchiveGenerationPlanningError.invalidComparisonEntry(entry.id)
                }
            }
            guard
                archiveGenerationComparisonEntryIsCoherent(
                    entry,
                    kind: snapshot.comparisonKind
                )
            else {
                throw ArchiveGenerationPlanningError.invalidComparisonEntry(entry.id)
            }
            prepared.append(entry)
        }
        try validateDirectoryEnumerations(
            sourcesByLocation,
            comparisonKind: snapshot.comparisonKind,
            limits: limits,
            work: &work
        )
        return prepared
    }

    private static func validateDirectoryEnumerations(
        _ sources: [ArchiveGenerationSourceLocation: ArchiveGenerationLocatedSource],
        comparisonKind: ArchiveGenerationComparisonKind,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        guard comparisonKind == .folder else { return }
        var locations = Array(sources.keys)
        try work.consumeSortUTF8UpperBound(
            values: locations.flatMap {
                [$0.root.canonicalURL.absoluteString, $0.relativePath]
            }
        )
        try archiveGenerationDeterministicSort(
            &locations,
            by: archiveGenerationSourceLocationPrecedes
        )
        var observed: [ArchiveGenerationSourceLocation: ArchiveGenerationDirectoryEnumeration] = [:]
        observed.reserveCapacity(sources.count)
        for location in locations {
            try work.checkpoint()
            guard let source = sources[location] else {
                throw ArchiveGenerationPlanningError.sourceSetChanged
            }
            guard
                let (parentPath, childName) = archiveGenerationParentAndLeaf(
                    location.relativePath
                )
            else {
                continue
            }
            let parentLocation = ArchiveGenerationSourceLocation(
                side: location.side,
                root: location.root,
                relativePath: parentPath
            )
            guard let parent = sources[parentLocation],
                parent.item.revision.identity.kind == .directory
            else {
                throw ArchiveGenerationPlanningError.invalidComparisonEntry(source.entryID)
            }
            if observed[parentLocation] == nil {
                observed[parentLocation] = ArchiveGenerationDirectoryEnumeration()
            }
            guard let childCount = observed[parentLocation]?.childCount,
                let childNameUTF8ByteCount = observed[parentLocation]?.childNameUTF8ByteCount
            else {
                throw ArchiveGenerationPlanningError.sourceSetChanged
            }
            observed[parentLocation]?.childCount = try add(
                1,
                to: childCount,
                maximum: UInt64(limits.maximumSnapshotEntries),
                error: .invalidRevision(path: parent.item.revision.identity.canonicalURL.path)
            )
            observed[parentLocation]?.childNameUTF8ByteCount = try add(
                UInt64(childName.utf8.count),
                to: childNameUTF8ByteCount,
                maximum: UInt64(limits.maximumTotalPathUTF8Bytes),
                error: .invalidRevision(path: parent.item.revision.identity.canonicalURL.path)
            )
            observed[parentLocation]?.children.append(
                ArchiveGenerationDirectoryChild(
                    name: childName,
                    kind: source.item.revision.identity.kind
                )
            )
        }
        for location in locations {
            try work.checkpoint()
            guard let source = sources[location] else {
                throw ArchiveGenerationPlanningError.sourceSetChanged
            }
            guard source.item.revision.identity.kind == .directory else { continue }
            let enumeration = observed[location, default: ArchiveGenerationDirectoryEnumeration()]
            let contentDigest = try directoryContentDigest(enumeration.children, work: &work)
            guard source.item.revision.directoryChildCount == enumeration.childCount,
                source.item.revision.directoryChildNameUTF8ByteCount
                    == enumeration.childNameUTF8ByteCount,
                source.item.revision.contentSHA256 == contentDigest
            else {
                throw ArchiveGenerationPlanningError.invalidRevision(
                    path: source.item.revision.identity.canonicalURL.path
                )
            }
        }
    }

    private static func directoryContentDigest(
        _ children: [ArchiveGenerationDirectoryChild],
        work: inout ArchiveGenerationWorkBudget
    ) throws -> [UInt8] {
        try work.consumeSortUTF8UpperBound(values: children.map(\.name))
        var sorted = children
        try archiveGenerationDeterministicSort(&sorted) { left, right in
            try archiveGenerationUTF8Precedes(left.name, right.name)
        }
        var digest = ArchiveGenerationDigest(
            domain: "ArchiveGenerationDirectoryChildren/v1"
        )
        digest.uint(UInt64(sorted.count))
        for child in sorted {
            try work.checkpoint()
            digest.string(child.name)
            digest.bytes([child.kind.directoryRevisionTag])
        }
        return digest.finalize()
    }

    private static func validate(
        _ item: ArchiveGenerationSourceItem,
        entryID: ArchiveGenerationEntryID,
        side: ArchiveGenerationSide,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        try validateFileURL(
            item.requestedURL,
            role: .requestedSource(entryID, side),
            canonical: false,
            limits: limits,
            work: &work
        )
        let revision = item.revision
        let identity = revision.identity
        try validateFileURL(
            identity.root.canonicalURL,
            role: .canonicalSourceRoot(entryID, side),
            canonical: true,
            limits: limits,
            work: &work
        )
        try validateFileURL(
            identity.canonicalURL,
            role: .canonicalSource(entryID, side),
            canonical: true,
            limits: limits,
            work: &work
        )
        let relativePath = try normalizeSourcePath(
            identity.relativePath,
            role: .source,
            limits: limits,
            work: &work
        )
        guard relativePath.utf8.elementsEqual(identity.relativePath.utf8) else {
            throw ArchiveGenerationPlanningError.invalidPath(
                role: .source,
                path: identity.relativePath,
                issue: .notNormalized
            )
        }
        let expectedPath = archiveGenerationAbsolutePath(
            relativePath,
            under: identity.root.canonicalURL.path
        )
        guard expectedPath.utf8.elementsEqual(identity.canonicalURL.path.utf8) else {
            throw ArchiveGenerationPlanningError.invalidURL(
                role: .canonicalSource(entryID, side),
                issue: .rootMismatch
            )
        }
        let validDirectoryEnumeration: Bool
        if identity.kind == .directory {
            validDirectoryEnumeration =
                revision.byteCount == 0
                && revision.directoryChildCount <= UInt64(limits.maximumSnapshotEntries)
                && revision.directoryChildNameUTF8ByteCount
                    <= UInt64(limits.maximumTotalPathUTF8Bytes)
        } else {
            validDirectoryEnumeration =
                revision.directoryChildCount == 0
                && revision.directoryChildNameUTF8ByteCount == 0
        }
        guard revision.linkCount > 0,
            revision.permissions & 0xF000 == 0,
            revision.modificationTimeNanoseconds >= 0,
            revision.modificationTimeNanoseconds < 1_000_000_000,
            revision.statusChangeTimeNanoseconds >= 0,
            revision.statusChangeTimeNanoseconds < 1_000_000_000,
            revision.contentSHA256.count == SHA256.Digest.byteCount,
            revision.metadataSHA256.count == SHA256.Digest.byteCount,
            validDirectoryEnumeration
        else {
            throw ArchiveGenerationPlanningError.invalidRevision(
                path: identity.canonicalURL.path
            )
        }
        try validateAuthority(
            item.accessAuthority,
            requestedURL: item.requestedURL,
            role: .requestedSource(entryID, side),
            limits: limits,
            work: &work
        )
    }

    private static func validate(
        _ filter: ArchiveGenerationFilterPolicy,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> ArchiveGenerationPreparedFilter {
        guard filter.pathRules.count <= limits.maximumFilterRules else {
            throw ArchiveGenerationPlanningError.tooManyFilterRules(
                maximum: limits.maximumFilterRules
            )
        }
        var rules: [ArchiveGenerationPreparedPathRule] = []
        rules.reserveCapacity(filter.pathRules.count)
        for rule in filter.pathRules {
            try work.checkpoint()
            let match: ArchiveGenerationPreparedPathMatch
            switch rule.match {
            case .exact(let path):
                let normalized = try normalizeSourcePath(
                    path,
                    role: .filter,
                    limits: limits,
                    work: &work
                )
                guard
                    filter.pathComparison == .caseSensitive
                        || archiveGenerationIsASCII(normalized)
                else {
                    throw pathError(.filter, path, .unsupportedNonASCII)
                }
                match = .exact(comparisonValue(normalized, policy: filter.pathComparison))
            case .subtree(let path):
                let normalized = try normalizeSourcePath(
                    path,
                    role: .filter,
                    limits: limits,
                    work: &work
                )
                guard
                    filter.pathComparison == .caseSensitive
                        || archiveGenerationIsASCII(normalized)
                else {
                    throw pathError(.filter, path, .unsupportedNonASCII)
                }
                match = .subtree(comparisonValue(normalized, policy: filter.pathComparison))
            case .pathExtension(let value):
                let rawCount = try boundedUTF8Count(value, maximum: 255)
                guard rawCount > 0, rawCount <= 255 else {
                    throw ArchiveGenerationPlanningError.invalidPathExtension(value)
                }
                let normalized = value
                let count = try boundedUTF8Count(normalized, maximum: 255)
                guard count > 0,
                    count <= 255,
                    !normalized.hasPrefix("."),
                    !normalized.utf8.contains(0x2F),
                    !normalized.utf8.contains(0x5C),
                    !normalized.utf8.contains(0),
                    filter.pathComparison == .caseSensitive
                        || archiveGenerationIsASCII(normalized)
                else {
                    throw ArchiveGenerationPlanningError.invalidPathExtension(value)
                }
                match = .pathExtension(
                    comparisonValue(normalized, policy: filter.pathComparison)
                )
            }
            rules.append(ArchiveGenerationPreparedPathRule(action: rule.action, match: match))
        }
        return ArchiveGenerationPreparedFilter(policy: filter, rules: rules)
    }

    private static func validate(
        _ options: ArchiveGenerationOutputOptions,
        capabilities: ArchiveGenerationExecutorCapabilities,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        let identifierCount = try boundedUTF8Count(
            capabilities.identifier,
            maximum: limits.maximumOptionUTF8Bytes
        )
        guard identifierCount > 0,
            identifierCount <= limits.maximumOptionUTF8Bytes,
            !capabilities.identifier.contains("\0"),
            capabilities.codecs.count <= 256
        else {
            throw ArchiveGenerationPlanningError.unsupportedCodec(
                ArchiveGenerationCodec(format: options.format, compression: options.compression)
            )
        }
        let codec = ArchiveGenerationCodec(
            format: options.format,
            compression: options.compression
        )
        guard capabilities.codecs.contains(codec) else {
            throw ArchiveGenerationPlanningError.unsupportedCodec(codec)
        }
        switch options.compression {
        case .store:
            guard options.compressionLevel == nil else {
                throw ArchiveGenerationPlanningError.invalidCompressionLevel
            }
        case .deflate, .bzip2, .lzma:
            guard let level = options.compressionLevel, (0...9).contains(level) else {
                throw ArchiveGenerationPlanningError.invalidCompressionLevel
            }
        case .zstandard:
            guard let level = options.compressionLevel, (1...22).contains(level) else {
                throw ArchiveGenerationPlanningError.invalidCompressionLevel
            }
        }
        guard options.destinationPermissions & 0xF000 == 0 else {
            throw ArchiveGenerationPlanningError.invalidPermissions(
                options.destinationPermissions
            )
        }
        if let comment = options.archiveComment {
            let count = try boundedUTF8Count(comment, maximum: limits.maximumOptionUTF8Bytes)
            guard count <= limits.maximumOptionUTF8Bytes,
                count <= 65_535,
                !comment.contains("\0")
            else {
                throw ArchiveGenerationPlanningError.invalidArchiveComment
            }
            try work.consume(UInt64(count))
        }
        try work.consume(UInt64(identifierCount + capabilities.codecs.count))
        try work.consumeProduct(UInt64(capabilities.codecs.count), 2)
        try Task.checkCancellation()
    }

    private static func validate(
        _ destination: ArchiveGenerationDestination,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        try validateFileURL(
            destination.requestedURL,
            role: .requestedDestination,
            canonical: false,
            limits: limits,
            work: &work
        )
        try validateFileURL(
            destination.intent.canonicalURL,
            role: .canonicalDestination,
            canonical: true,
            limits: limits,
            work: &work
        )
        try validateFileURL(
            destination.intent.canonicalParent.canonicalURL,
            role: .canonicalDestinationParent,
            canonical: true,
            limits: limits,
            work: &work
        )
        guard
            archiveGenerationUTF8Equal(
                destination.intent.canonicalURL.deletingLastPathComponent().path,
                destination.intent.canonicalParent.canonicalURL.path
            ),
            !archiveGenerationUTF8Equal(
                destination.intent.canonicalURL.path,
                destination.intent.canonicalParent.canonicalURL.path
            ),
            !destination.intent.canonicalURL.lastPathComponent.isEmpty
        else {
            throw ArchiveGenerationPlanningError.invalidURL(
                role: .canonicalDestination,
                issue: .parentMismatch
            )
        }
        switch destination.intent {
        case .createNew:
            break
        case .replaceExisting(let revision):
            let normalizedRelativePath = try normalizeSourcePath(
                revision.identity.relativePath,
                role: .source,
                limits: limits,
                work: &work
            )
            guard normalizedRelativePath.utf8.elementsEqual(revision.identity.relativePath.utf8),
                revision.identity.kind == .regularFile,
                revision.directoryChildCount == 0,
                revision.directoryChildNameUTF8ByteCount == 0,
                archiveGenerationUTF8Equal(
                    revision.identity.canonicalURL.path,
                    destination.intent.canonicalURL.path
                ),
                archiveGenerationDirectoryIdentityEqual(
                    revision.identity.root,
                    destination.intent.canonicalParent
                ),
                archiveGenerationAbsolutePath(
                    normalizedRelativePath,
                    under: revision.identity.root.canonicalURL.path
                ).utf8.elementsEqual(revision.identity.canonicalURL.path.utf8),
                revision.linkCount > 0,
                revision.permissions & 0xF000 == 0,
                revision.modificationTimeNanoseconds >= 0,
                revision.modificationTimeNanoseconds < 1_000_000_000,
                revision.statusChangeTimeNanoseconds >= 0,
                revision.statusChangeTimeNanoseconds < 1_000_000_000,
                revision.byteCount <= limits.maximumArchiveBytes,
                revision.metadataByteCount <= limits.maximumMetadataBytes,
                revision.contentSHA256.count == SHA256.Digest.byteCount,
                revision.metadataSHA256.count == SHA256.Digest.byteCount
            else {
                throw ArchiveGenerationPlanningError.destinationDoesNotMatchIntent
            }
        }
        try validateAuthority(
            destination.accessAuthority,
            requestedURL: destination.requestedURL.deletingLastPathComponent(),
            role: .requestedDestination,
            requiredCoverage: .directoryTree,
            limits: limits,
            work: &work
        )
    }

    private static func validateAuthority(
        _ authority: ArchiveGenerationAccessAuthority,
        requestedURL: URL,
        role: ArchiveGenerationURLRole,
        requiredCoverage: ArchiveGenerationAuthorityCoverage? = nil,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        guard case .securityScoped(let resourceURL, let coverage) = authority else { return }
        guard requiredCoverage != .directoryTree || coverage == .directoryTree else {
            throw ArchiveGenerationPlanningError.invalidURL(
                role: role,
                issue: .insufficientAuthorityCoverage
            )
        }
        try validateFileURL(
            resourceURL,
            role: .securityScope,
            canonical: true,
            limits: limits,
            work: &work
        )
        try validateFileURL(
            requestedURL,
            role: role,
            canonical: true,
            limits: limits,
            work: &work
        )
        let resourcePath = resourceURL.path
        let requestedPath = requestedURL.path
        let covered: Bool
        switch coverage {
        case .exactItem:
            covered = archiveGenerationUTF8Equal(resourcePath, requestedPath)
        case .directoryTree:
            covered =
                archiveGenerationUTF8Equal(requestedPath, resourcePath)
                || isLexicalDescendant(requestedPath, of: resourcePath)
        }
        guard covered else {
            throw ArchiveGenerationPlanningError.invalidURL(
                role: role,
                issue: .insufficientAuthorityCoverage
            )
        }
    }

    private static func validateFileURL(
        _ url: URL,
        role: ArchiveGenerationURLRole,
        canonical: Bool,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        let serializedCount = try boundedUTF8Count(
            url.absoluteString,
            maximum: limits.maximumPathUTF8Bytes * 3
        )
        guard serializedCount <= limits.maximumPathUTF8Bytes * 3 else {
            throw ArchiveGenerationPlanningError.invalidURL(role: role, issue: .pathTooLong)
        }
        try work.consume(UInt64(serializedCount))
        guard url.isFileURL else {
            throw ArchiveGenerationPlanningError.invalidURL(role: role, issue: .notFileURL)
        }
        guard url.baseURL == nil, url.path.utf8.first == 0x2F else {
            throw ArchiveGenerationPlanningError.invalidURL(role: role, issue: .relativeURL)
        }
        let host = url.host.map(archiveGenerationASCIILowercased)
        guard host == nil || host == "" || host == "localhost" else {
            throw ArchiveGenerationPlanningError.invalidURL(role: role, issue: .remoteHost)
        }
        guard url.user == nil, url.password == nil, url.port == nil else {
            throw ArchiveGenerationPlanningError.invalidURL(
                role: role,
                issue: .credentialsOrPort
            )
        }
        guard url.query == nil, url.fragment == nil else {
            throw ArchiveGenerationPlanningError.invalidURL(
                role: role,
                issue: .queryOrFragment
            )
        }
        let path = url.path
        guard !path.contains("\0") else {
            throw ArchiveGenerationPlanningError.invalidURL(role: role, issue: .nullByte)
        }
        let byteCount = try boundedUTF8Count(path, maximum: limits.maximumPathUTF8Bytes)
        guard byteCount <= limits.maximumPathUTF8Bytes else {
            throw ArchiveGenerationPlanningError.invalidURL(role: role, issue: .pathTooLong)
        }
        try work.consume(UInt64(byteCount))
        if canonical {
            let standardized = NSString(string: path).standardizingPath
            guard archiveGenerationUTF8Equal(standardized, path),
                !path.hasPrefix("//"),
                !path.contains("//")
            else {
                throw ArchiveGenerationPlanningError.invalidURL(role: role, issue: .notCanonical)
            }
        }
    }

    private static func select(
        entries: [ArchiveGenerationComparisonEntry],
        selection: ArchiveGenerationSelection,
        policy: ArchiveGenerationInclusionPolicy,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> [ArchiveGenerationSelectionCandidate] {
        var byID: [[UInt8]: ArchiveGenerationComparisonEntry] = [:]
        byID.reserveCapacity(entries.count)
        for entry in entries { byID[Array(entry.id.rawValue.utf8)] = entry }

        var candidates: [ArchiveGenerationSelectionKey: ArchiveGenerationSelectionCandidate] = [:]
        func insert(
            _ entry: ArchiveGenerationComparisonEntry,
            side: ArchiveGenerationSide,
            archivePath: String?
        ) throws {
            guard
                candidates.count < limits.maximumSelectedEntries
                    || candidates[ArchiveGenerationSelectionKey(id: entry.id, side: side)] != nil
            else {
                throw ArchiveGenerationPlanningError.tooManySelectedEntries(
                    maximum: limits.maximumSelectedEntries
                )
            }
            let normalizedArchivePath = try archivePath.map {
                try normalizeArchivePath(
                    $0,
                    role: .archive,
                    limits: limits,
                    work: &work
                )
            }
            let key = ArchiveGenerationSelectionKey(id: entry.id, side: side)
            let selection = ArchiveGenerationSelectedEntry(
                id: entry.id,
                side: side,
                archiveRelativePath: normalizedArchivePath
            )
            let candidate = ArchiveGenerationSelectionCandidate(entry: entry, selection: selection)
            if let existing = candidates[key] {
                guard
                    archiveGenerationOptionalUTF8Equal(
                        existing.selection.archiveRelativePath,
                        normalizedArchivePath
                    )
                else {
                    throw ArchiveGenerationPlanningError.ambiguousSelection(entry.id, side)
                }
                return
            }
            candidates[key] = candidate
        }

        switch selection {
        case .all(let side):
            guard entries.count <= limits.maximumSelectedEntries else {
                throw ArchiveGenerationPlanningError.tooManySelectedEntries(
                    maximum: limits.maximumSelectedEntries
                )
            }
            for entry in entries {
                try work.checkpoint()
                try insert(entry, side: side, archivePath: nil)
            }
        case .only(let selected):
            guard selected.count <= limits.maximumSelectedEntries else {
                throw ArchiveGenerationPlanningError.tooManySelectedEntries(
                    maximum: limits.maximumSelectedEntries
                )
            }
            var explicit: Set<ArchiveGenerationSelectionKey> = []
            for selectedEntry in selected {
                try work.checkpoint()
                let identifierCount = try boundedUTF8Count(
                    selectedEntry.id.rawValue,
                    maximum: limits.maximumIdentifierUTF8Bytes
                )
                guard identifierCount > 0,
                    identifierCount <= limits.maximumIdentifierUTF8Bytes,
                    !selectedEntry.id.rawValue.contains("\0")
                else {
                    throw ArchiveGenerationPlanningError.invalidEntryIdentifier(
                        selectedEntry.id.rawValue
                    )
                }
                try work.consume(UInt64(identifierCount))
                let key = ArchiveGenerationSelectionKey(
                    id: selectedEntry.id,
                    side: selectedEntry.side
                )
                guard explicit.insert(key).inserted else {
                    throw ArchiveGenerationPlanningError.duplicateSelection(
                        selectedEntry.id,
                        selectedEntry.side
                    )
                }
                guard let entry = byID[Array(selectedEntry.id.rawValue.utf8)] else {
                    throw ArchiveGenerationPlanningError.unknownEntryIdentifier(selectedEntry.id)
                }
                try insert(
                    entry,
                    side: selectedEntry.side,
                    archivePath: selectedEntry.archiveRelativePath
                )
                guard policy.directorySelection == .includeSnapshotDescendants,
                    let source = entry.item(on: selectedEntry.side),
                    source.revision.identity.kind == .directory
                else {
                    continue
                }
                let parentPath = source.revision.identity.relativePath
                try work.consumeProduct(UInt64(entries.count), 2)
                for descendant in entries {
                    try work.checkpoint()
                    guard let descendantSource = descendant.item(on: selectedEntry.side) else {
                        continue
                    }
                    try work.consume(
                        UInt64(
                            source.revision.identity.root.canonicalURL.absoluteString.utf8.count
                                + descendantSource.revision.identity.root.canonicalURL.absoluteString.utf8.count
                        )
                    )
                    guard
                        archiveGenerationDirectoryIdentityEqual(
                            descendantSource.revision.identity.root,
                            source.revision.identity.root
                        )
                    else {
                        continue
                    }
                    let descendantPath = descendantSource.revision.identity.relativePath
                    try work.consume(
                        UInt64(
                            parentPath.utf8.count + descendantPath.utf8.count
                        )
                    )
                    guard isRelativeDescendant(descendantPath, of: parentPath) else { continue }
                    guard
                        let suffix = archiveGenerationRelativeSuffix(
                            descendantPath,
                            after: parentPath
                        )
                    else {
                        continue
                    }
                    let mappedPath = selectedEntry.archiveRelativePath.map { "\($0)/\(suffix)" }
                    try insert(
                        descendant,
                        side: selectedEntry.side,
                        archivePath: mappedPath
                    )
                }
            }
        }
        guard candidates.count <= limits.maximumSelectedEntries else {
            throw ArchiveGenerationPlanningError.tooManySelectedEntries(
                maximum: limits.maximumSelectedEntries
            )
        }
        try work.consumeSortUTF8UpperBound(values: candidates.values.map(\.entry.id.rawValue))
        var orderedCandidates = Array(candidates.values)
        try archiveGenerationDeterministicSort(&orderedCandidates) { left, right in
            if !archiveGenerationUTF8Equal(
                left.entry.id.rawValue,
                right.entry.id.rawValue
            ) {
                return try archiveGenerationUTF8Precedes(
                    left.entry.id.rawValue,
                    right.entry.id.rawValue
                )
            }
            return left.selection.side.rawValue < right.selection.side.rawValue
        }
        return orderedCandidates
    }

    private static func omissionReason(
        for kind: ArchiveGenerationItemKind,
        path: String,
        policy: ArchiveGenerationInclusionPolicy
    ) throws -> ArchiveGenerationOmissionReason? {
        switch kind {
        case .regularFile, .directory:
            return nil
        case .symbolicLink:
            switch policy.symbolicLinks {
            case .reject:
                throw ArchiveGenerationPlanningError.unsupportedItem(
                    path: path,
                    kind: kind
                )
            case .omit:
                return .symbolicLink
            }
        case .specialFile:
            switch policy.specialFiles {
            case .reject:
                throw ArchiveGenerationPlanningError.unsupportedItem(
                    path: path,
                    kind: kind
                )
            case .omit:
                return .specialFile
            }
        }
    }

    private static func normalizeSourcePath(
        _ path: String,
        role: ArchiveGenerationPathRole,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> String {
        try normalizePath(
            path,
            role: role,
            portableArchiveName: false,
            limits: limits,
            work: &work
        )
    }

    private static func normalizeArchivePath(
        _ path: String,
        role: ArchiveGenerationPathRole,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> String {
        try normalizePath(
            path,
            role: role,
            portableArchiveName: true,
            limits: limits,
            work: &work
        )
    }

    private static func normalizePath(
        _ path: String,
        role: ArchiveGenerationPathRole,
        portableArchiveName: Bool,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> String {
        try Task.checkCancellation()
        let inputByteCount = try boundedUTF8Count(
            path,
            maximum: limits.maximumPathUTF8Bytes
        )
        guard inputByteCount <= limits.maximumPathUTF8Bytes else {
            throw pathError(role, path, .pathTooLong)
        }
        guard !path.isEmpty else { throw pathError(role, path, .empty) }
        let pathBytes = Array(path.utf8)
        guard pathBytes.first != 0x2F else { throw pathError(role, path, .absolute) }
        guard !pathBytes.contains(0x5C) else {
            throw pathError(role, path, .containsBackslash)
        }
        guard !pathBytes.contains(0) else { throw pathError(role, path, .containsNull) }
        let rawComponents = archiveGenerationUTF8PathComponents(path)
        guard rawComponents.count <= limits.maximumPathDepth else {
            throw pathError(role, path, .tooDeep)
        }
        var components: [String] = []
        components.reserveCapacity(rawComponents.count)
        var totalBytes = 0
        for raw in rawComponents {
            try work.checkpoint()
            guard !raw.isEmpty else { throw pathError(role, path, .emptyComponent) }
            guard !archiveGenerationUTF8Equal(raw, ".") else {
                throw pathError(role, path, .currentDirectoryComponent)
            }
            guard !archiveGenerationUTF8Equal(raw, "..") else {
                throw pathError(role, path, .parentTraversal)
            }
            let component = raw
            if portableArchiveName {
                guard archiveGenerationIsASCII(component) else {
                    throw pathError(role, path, .unsupportedNonASCII)
                }
                guard !component.contains(":") else {
                    throw pathError(role, path, .containsColon)
                }
                guard
                    !component.unicodeScalars.contains(where: {
                        $0.value < 0x20 || $0.value == 0x7F
                            || "<>\"|?*".unicodeScalars.contains($0)
                    })
                else {
                    throw pathError(role, path, .containsPortableForbiddenCharacter)
                }
                guard component.last != ".", component.last != " " else {
                    throw pathError(role, path, .trailingDotOrSpace)
                }
                guard !isReservedDeviceName(component) else {
                    throw pathError(role, path, .reservedDeviceName)
                }
                guard !portableCollisionKey(component).isEmpty else {
                    throw pathError(role, path, .emptyPortableKey)
                }
            }
            let componentBytes = try boundedUTF8Count(component, maximum: 255)
            guard componentBytes <= 255 else {
                throw pathError(role, path, .componentTooLong)
            }
            totalBytes = try add(
                componentBytes + (components.isEmpty ? 0 : 1),
                to: totalBytes,
                maximum: limits.maximumPathUTF8Bytes,
                error: pathError(role, path, .pathTooLong)
            )
            components.append(component)
        }
        guard !components.isEmpty else { throw pathError(role, path, .empty) }
        try work.consume(UInt64(totalBytes + components.count))
        return components.joined(separator: "/")
    }

    private static func validateArchivePaths(
        _ entries: [ArchiveGenerationManifestEntry],
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        let root = ArchiveGenerationPathTrieNode()
        for entry in entries {
            let components = archiveGenerationUTF8PathComponents(entry.archiveRelativePath)
            var node = root
            for (index, component) in components.enumerated() {
                try work.checkpoint()
                if node.kind == .regularFile {
                    let ancestor = components.prefix(index).joined(separator: "/")
                    throw ArchiveGenerationPlanningError.pathHierarchyConflict(
                        ancestor: ancestor,
                        descendant: entry.archiveRelativePath
                    )
                }
                let key = portableCollisionKey(component)
                if let child = node.children[key] {
                    guard child.spelling.map({ archiveGenerationUTF8Equal($0, component) }) == true else {
                        throw ArchiveGenerationPlanningError.portablePathCollision(
                            first: child.spelling ?? "",
                            second: component
                        )
                    }
                    node = child
                } else {
                    let child = ArchiveGenerationPathTrieNode(spelling: component)
                    node.children[key] = child
                    node = child
                }
            }
            guard node.kind == nil else {
                throw ArchiveGenerationPlanningError.duplicateArchivePath(
                    entry.archiveRelativePath
                )
            }
            if entry.kind == .regularFile, !node.children.isEmpty {
                throw ArchiveGenerationPlanningError.pathHierarchyConflict(
                    ancestor: entry.archiveRelativePath,
                    descendant: entry.archiveRelativePath + "/..."
                )
            }
            node.kind = entry.kind
        }
    }

    private static func validateDestinationDoesNotOverlapSources(
        _ destination: ArchiveGenerationDestination,
        entries: [ArchiveGenerationManifestEntry],
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        let destinationPath = destination.intent.canonicalURL.path
        let destinationNode: ArchiveGenerationNodeIdentity?
        switch destination.intent {
        case .createNew:
            destinationNode = nil
        case .replaceExisting(let revision):
            destinationNode = revision.identity.node
        }
        for entry in entries {
            try work.checkpoint()
            let identity = entry.source.revision.identity
            try work.consume(
                UInt64(destinationPath.utf8.count + identity.canonicalURL.path.utf8.count)
            )
            if archiveGenerationUTF8Equal(identity.canonicalURL.path, destinationPath)
                || destinationNode.map({ $0 == identity.node }) == true
            {
                throw ArchiveGenerationPlanningError.destinationMatchesSource(destinationPath)
            }
            if identity.kind == .directory,
                destination.intent.canonicalParent.node == identity.node
            {
                throw ArchiveGenerationPlanningError.destinationInsideSource(destinationPath)
            }
            if identity.kind == .directory,
                isLexicalDescendant(destinationPath, of: identity.canonicalURL.path)
            {
                throw ArchiveGenerationPlanningError.destinationInsideSource(destinationPath)
            }
        }
    }

    private static func archiveByteEnvelope(
        sourceBytes: UInt64,
        format: ArchiveGenerationContainerFormat,
        compression: ArchiveGenerationCompressionMethod,
        pathBytes: Int,
        entryCount: Int,
        maximum: UInt64
    ) throws -> UInt64 {
        // Stored output has an exact source-size contribution. Compressed codecs must stop before
        // the executor output cap, so that cap is the only format-independent conservative bound.
        if compression != .store || format != .zip { return maximum }
        var total = sourceBytes
        total = try add(
            UInt64(pathBytes) * 2,
            to: total,
            maximum: maximum,
            error: .archiveSizeLimitExceeded(maximumBytes: maximum)
        )
        let (entryOverhead, overflow) = UInt64(entryCount).multipliedReportingOverflow(by: 1_024)
        guard !overflow else {
            throw ArchiveGenerationPlanningError.archiveSizeLimitExceeded(maximumBytes: maximum)
        }
        total = try add(
            entryOverhead,
            to: total,
            maximum: maximum,
            error: .archiveSizeLimitExceeded(maximumBytes: maximum)
        )
        return try add(
            1_048_576,
            to: total,
            maximum: maximum,
            error: .archiveSizeLimitExceeded(maximumBytes: maximum)
        )
    }

    private static func retainedPlanByteCount(
        selection: ArchiveGenerationSelection,
        policy: ArchiveGenerationInclusionPolicy,
        manifest: ArchiveGenerationManifest,
        omissions: [ArchiveGenerationOmission],
        destination: ArchiveGenerationDestination,
        capabilities: ArchiveGenerationExecutorCapabilities,
        authorities: [ArchiveGenerationAuthorityRequirement],
        maximum: Int
    ) throws -> Int {
        var total = 1_024
        func addString(_ value: String) throws {
            total = try add(
                value.utf8.count + 16,
                to: total,
                maximum: maximum,
                error: .planTooLarge(maximumBytes: maximum)
            )
        }
        if case .only(let entries) = selection {
            for entry in entries {
                try addString(entry.id.rawValue)
                if let path = entry.archiveRelativePath { try addString(path) }
            }
        }
        if let prefix = manifest.options.pathPrefix { try addString(prefix) }
        if let comment = manifest.options.archiveComment { try addString(comment) }
        for rule in policy.filter.pathRules {
            switch rule.match {
            case .exact(let value), .subtree(let value), .pathExtension(let value):
                try addString(value)
            }
        }
        for entry in manifest.entries {
            total = try add(
                entry.archiveRelativePath.utf8.count
                    + entry.source.requestedURL.absoluteString.utf8.count
                    + entry.source.revision.identity.canonicalURL.absoluteString.utf8.count
                    + entry.source.revision.identity.root.canonicalURL.absoluteString.utf8.count
                    + entry.source.revision.identity.relativePath.utf8.count
                    + entry.selection.id.rawValue.utf8.count
                    + 512,
                to: total,
                maximum: maximum,
                error: .planTooLarge(maximumBytes: maximum)
            )
        }
        for omission in omissions {
            total = try add(
                omission.id.rawValue.utf8.count + omission.relativePath.utf8.count + 64,
                to: total,
                maximum: maximum,
                error: .planTooLarge(maximumBytes: maximum)
            )
        }
        for authority in authorities {
            total = try add(
                authority.requestedURL.absoluteString.utf8.count
                    + authority.canonicalURL.absoluteString.utf8.count
                    + 128,
                to: total,
                maximum: maximum,
                error: .planTooLarge(maximumBytes: maximum)
            )
        }
        try addString(destination.requestedURL.absoluteString)
        try addString(destination.intent.canonicalURL.absoluteString)
        try addString(destination.intent.canonicalParent.canonicalURL.absoluteString)
        if case .replaceExisting(let revision) = destination.intent {
            try addString(revision.identity.relativePath)
            total = try add(
                512,
                to: total,
                maximum: maximum,
                error: .planTooLarge(maximumBytes: maximum)
            )
        }
        try addString(capabilities.identifier)
        total = try add(
            capabilities.codecs.count * 64,
            to: total,
            maximum: maximum,
            error: .planTooLarge(maximumBytes: maximum)
        )
        for authority in authorities {
            if case .securityScoped(let resourceURL, _) = authority.authority {
                try addString(resourceURL.absoluteString)
            }
        }
        return total
    }

    private static func authorityRequirements(
        entries: [ArchiveGenerationManifestEntry],
        destination: ArchiveGenerationDestination
    ) -> [ArchiveGenerationAuthorityRequirement] {
        var requirements = entries.map { entry in
            ArchiveGenerationAuthorityRequirement(
                purpose: .readSource(entry.selection.id, entry.selection.side),
                requestedURL: entry.source.requestedURL,
                canonicalURL: entry.source.revision.identity.canonicalURL,
                requiredCoverage: .exactItem,
                authority: entry.source.accessAuthority
            )
        }
        let destinationPurpose: ArchiveGenerationAuthorityPurpose
        switch destination.intent {
        case .createNew: destinationPurpose = .createDestination
        case .replaceExisting: destinationPurpose = .replaceDestination
        }
        requirements.append(
            ArchiveGenerationAuthorityRequirement(
                purpose: destinationPurpose,
                requestedURL: destination.requestedURL.deletingLastPathComponent(),
                canonicalURL: destination.intent.canonicalParent.canonicalURL,
                requiredCoverage: .directoryTree,
                authority: destination.accessAuthority
            )
        )
        return requirements
    }

    private static func snapshotDigest(
        _ snapshot: ArchiveGenerationComparisonSnapshot,
        entries: [ArchiveGenerationComparisonEntry],
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> [UInt8] {
        try work.consumeProduct(UInt64(entries.count), 256)
        try work.consume(UInt64(limits.maximumTotalPathUTF8Bytes))
        var digest = ArchiveGenerationDigest(domain: "ArchiveGenerationSnapshot/v2")
        digest.version(ArchiveGenerationPlanningReceipt.version)
        digest.string(ArchiveGenerationPathPolicy.required.rawValue)
        digest.string(ArchiveGenerationDirectoryRevisionPolicy.required.rawValue)
        digest.uuid(snapshot.identity.rawValue)
        digest.uint(snapshot.generation)
        digest.string(snapshot.comparisonKind.rawValue)
        digest.uint(UInt64(entries.count))
        for entry in entries {
            try work.checkpoint()
            try work.consume(
                UInt64(
                    entry.id.rawValue.utf8.count + entry.relativePath.utf8.count
                        + sourceItemDigestByteCount(entry.left)
                        + sourceItemDigestByteCount(entry.right) + 128
                )
            )
            digest.string(entry.id.rawValue)
            digest.string(entry.relativePath)
            digest.string(entry.status.rawValue)
            digest.bool(entry.isHidden)
            digest.sourceItem(entry.left)
            digest.sourceItem(entry.right)
        }
        return digest.finalize()
    }

    private static func manifestDigest(
        options: ArchiveGenerationOutputOptions,
        entries: [ArchiveGenerationManifestEntry],
        sourceBytes: UInt64,
        metadataBytes: UInt64,
        pathBytes: Int,
        pathComponents: UInt64,
        archiveEnvelope: UInt64,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> [UInt8] {
        try work.consumeProduct(UInt64(entries.count), 256)
        try work.consume(UInt64(limits.maximumTotalPathUTF8Bytes))
        var digest = ArchiveGenerationDigest(domain: "ArchiveGenerationManifest/v2")
        digest.version(ArchiveGenerationManifest.version)
        digest.string(ArchiveGenerationPathPolicy.required.rawValue)
        digest.string(ArchiveGenerationDirectoryRevisionPolicy.required.rawValue)
        digest.outputOptions(options)
        digest.uint(UInt64(entries.count))
        for entry in entries {
            try work.checkpoint()
            try work.consume(
                UInt64(
                    entry.selection.id.rawValue.utf8.count
                        + (entry.selection.archiveRelativePath?.utf8.count ?? 0)
                        + entry.archiveRelativePath.utf8.count
                        + sourceItemDigestByteCount(entry.source) + 128
                )
            )
            digest.string(entry.selection.id.rawValue)
            digest.string(entry.selection.side.rawValue)
            digest.optionalString(entry.selection.archiveRelativePath)
            digest.string(entry.archiveRelativePath)
            digest.sourceItem(entry.source)
            digest.uint(UInt64(entry.metadata.permissions))
            digest.int(entry.metadata.modificationTimeSeconds)
            digest.int(Int64(entry.metadata.modificationTimeNanoseconds))
        }
        digest.uint(sourceBytes)
        digest.uint(metadataBytes)
        digest.uint(UInt64(pathBytes))
        digest.uint(pathComponents)
        digest.uint(archiveEnvelope)
        return digest.finalize()
    }

    private static func planDigest(
        snapshotCAS: ArchiveGenerationSnapshotCAS,
        selection: ArchiveGenerationSelection,
        policy: ArchiveGenerationInclusionPolicy,
        manifestSHA256: [UInt8],
        omissions: [ArchiveGenerationOmission],
        destination: ArchiveGenerationDestination,
        capabilities: ArchiveGenerationExecutorCapabilities,
        limits: ArchiveGenerationLimits,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> [UInt8] {
        try work.consume(UInt64(limits.maximumRetainedPlanBytes))
        try Task.checkCancellation()
        var digest = ArchiveGenerationDigest(domain: "ArchiveGenerationPlan/v2")
        digest.version(ArchiveGenerationPlanningReceipt.version)
        digest.string(ArchiveGenerationPathPolicy.required.rawValue)
        digest.string(ArchiveGenerationDirectoryRevisionPolicy.required.rawValue)
        digest.uuid(snapshotCAS.reference.identity.rawValue)
        digest.uint(snapshotCAS.reference.generation)
        digest.bytes(snapshotCAS.stateSHA256)
        try digest.selection(selection, work: &work)
        digest.inclusionPolicy(policy)
        digest.bytes(manifestSHA256)
        digest.uint(UInt64(omissions.count))
        for omission in omissions {
            try work.checkpoint()
            digest.string(omission.id.rawValue)
            digest.string(omission.side.rawValue)
            digest.string(omission.relativePath)
            digest.string(omission.reason.rawValue)
        }
        digest.destination(destination)
        digest.capabilities(capabilities)
        digest.limits(limits)
        return digest.finalize()
    }

    private static func omissionPrecedes(
        _ left: ArchiveGenerationOmission,
        _ right: ArchiveGenerationOmission
    ) throws -> Bool {
        if !archiveGenerationUTF8Equal(left.id.rawValue, right.id.rawValue) {
            return try archiveGenerationUTF8Precedes(
                left.id.rawValue,
                right.id.rawValue
            )
        }
        if left.side != right.side { return left.side.rawValue < right.side.rawValue }
        return left.reason.rawValue < right.reason.rawValue
    }

    private static func sourceItemDigestByteCount(
        _ item: ArchiveGenerationSourceItem?
    ) -> Int {
        guard let item else { return 1 }
        let identity = item.revision.identity
        var count =
            item.requestedURL.absoluteString.utf8.count
            + identity.canonicalURL.absoluteString.utf8.count
            + identity.root.canonicalURL.absoluteString.utf8.count
            + identity.relativePath.utf8.count + 512
        if case .securityScoped(let resourceURL, _) = item.accessAuthority {
            count += resourceURL.absoluteString.utf8.count
        }
        return count
    }

    private static func pathError(
        _ role: ArchiveGenerationPathRole,
        _ path: String,
        _ issue: ArchiveGenerationPathIssue
    ) -> ArchiveGenerationPlanningError {
        .invalidPath(role: role, path: path, issue: issue)
    }

    private static func add(
        _ value: Int,
        to total: Int,
        maximum: Int,
        error: ArchiveGenerationPlanningError
    ) throws -> Int {
        let (next, overflow) = total.addingReportingOverflow(value)
        guard !overflow, next <= maximum else { throw error }
        return next
    }

    private static func add(
        _ value: UInt64,
        to total: UInt64,
        maximum: UInt64,
        error: ArchiveGenerationPlanningError
    ) throws -> UInt64 {
        let (next, overflow) = total.addingReportingOverflow(value)
        guard !overflow, next <= maximum else { throw error }
        return next
    }
}

private struct ArchiveGenerationSelectionKey: Hashable {
    let id: ArchiveGenerationEntryID
    let side: ArchiveGenerationSide

    private let idUTF8: [UInt8]

    init(id: ArchiveGenerationEntryID, side: ArchiveGenerationSide) {
        self.id = id
        self.side = side
        idUTF8 = Array(id.rawValue.utf8)
    }

    static func == (left: Self, right: Self) -> Bool {
        left.side == right.side && left.idUTF8 == right.idUTF8
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(idUTF8)
        hasher.combine(side)
    }
}

private struct ArchiveGenerationSelectionCandidate {
    let entry: ArchiveGenerationComparisonEntry
    let selection: ArchiveGenerationSelectedEntry
}

private struct ArchiveGenerationSourceIdentityKey: Hashable {
    let canonicalURLUTF8: [UInt8]
    let rootURLUTF8: [UInt8]
    let rootNode: ArchiveGenerationNodeIdentity
    let relativePathUTF8: [UInt8]
    let kind: ArchiveGenerationItemKind
    let node: ArchiveGenerationNodeIdentity

    init(_ identity: ArchiveGenerationCanonicalItemIdentity) {
        canonicalURLUTF8 = Array(identity.canonicalURL.absoluteString.utf8)
        rootURLUTF8 = Array(identity.root.canonicalURL.absoluteString.utf8)
        rootNode = identity.root.node
        relativePathUTF8 = Array(identity.relativePath.utf8)
        kind = identity.kind
        node = identity.node
    }
}

private struct ArchiveGenerationSourceLocation: Hashable {
    let side: ArchiveGenerationSide
    let root: ArchiveGenerationCanonicalDirectoryIdentity
    let relativePath: String

    private let rootURLUTF8: [UInt8]
    private let relativePathUTF8: [UInt8]

    init(
        side: ArchiveGenerationSide,
        root: ArchiveGenerationCanonicalDirectoryIdentity,
        relativePath: String
    ) {
        self.side = side
        self.root = root
        self.relativePath = relativePath
        rootURLUTF8 = Array(root.canonicalURL.absoluteString.utf8)
        relativePathUTF8 = Array(relativePath.utf8)
    }

    static func == (left: Self, right: Self) -> Bool {
        left.side == right.side
            && left.root.node == right.root.node
            && left.rootURLUTF8 == right.rootURLUTF8
            && left.relativePathUTF8 == right.relativePathUTF8
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(side)
        hasher.combine(root.node)
        hasher.combine(rootURLUTF8)
        hasher.combine(relativePathUTF8)
    }
}

private struct ArchiveGenerationLocatedSource {
    let entryID: ArchiveGenerationEntryID
    let item: ArchiveGenerationSourceItem
}

private struct ArchiveGenerationDirectoryEnumeration {
    var childCount: UInt64 = 0
    var childNameUTF8ByteCount: UInt64 = 0
    var children: [ArchiveGenerationDirectoryChild] = []
}

private struct ArchiveGenerationDirectoryChild {
    let name: String
    let kind: ArchiveGenerationItemKind
}

private final class ArchiveGenerationPathTrieNode {
    let spelling: String?
    var kind: ArchiveGenerationItemKind?
    var children: [String: ArchiveGenerationPathTrieNode] = [:]

    init(spelling: String? = nil) {
        self.spelling = spelling
    }
}

private enum ArchiveGenerationPreparedPathMatch {
    case exact(String)
    case subtree(String)
    case pathExtension(String)
}

private struct ArchiveGenerationPreparedPathRule {
    let action: ArchiveGenerationPathRuleAction
    let match: ArchiveGenerationPreparedPathMatch

    var comparisonUTF8ByteCount: Int {
        switch match {
        case .exact(let value), .subtree(let value), .pathExtension(let value):
            value.utf8.count
        }
    }
}

private struct ArchiveGenerationPreparedFilter {
    let policy: ArchiveGenerationFilterPolicy
    let rules: [ArchiveGenerationPreparedPathRule]

    func matches(
        entry: ArchiveGenerationComparisonEntry,
        sourcePath: String,
        kind: ArchiveGenerationItemKind,
        work: inout ArchiveGenerationWorkBudget
    ) throws -> Bool {
        if !policy.statuses.isEmpty, !policy.statuses.contains(entry.status) { return false }
        if !policy.kinds.isEmpty, !policy.kinds.contains(kind) { return false }
        switch policy.hidden {
        case .include:
            break
        case .exclude where entry.isHidden:
            return false
        case .only where !entry.isHidden:
            return false
        default:
            break
        }
        if !rules.isEmpty,
            policy.pathComparison == .portableCaseInsensitive,
            !archiveGenerationIsASCII(sourcePath)
        {
            throw ArchiveGenerationPlanningError.invalidPath(
                role: .filter,
                path: sourcePath,
                issue: .unsupportedNonASCII
            )
        }
        let comparablePath = comparisonValue(sourcePath, policy: policy.pathComparison)
        var action = policy.defaultPathAction
        for rule in rules {
            try work.checkpoint()
            try work.consume(
                UInt64(comparablePath.utf8.count + rule.comparisonUTF8ByteCount)
            )
            if ruleMatches(rule.match, path: comparablePath) { action = rule.action }
        }
        return action == .include
    }

    private func ruleMatches(
        _ match: ArchiveGenerationPreparedPathMatch,
        path: String
    ) -> Bool {
        switch match {
        case .exact(let value):
            return archiveGenerationUTF8Equal(path, value)
        case .subtree(let value):
            return archiveGenerationUTF8Equal(path, value)
                || isRelativeDescendant(path, of: value)
        case .pathExtension(let value):
            let leaf = archiveGenerationParentAndLeaf(path)?.leaf ?? path
            let leafBytes = Array(leaf.utf8)
            guard let dot = leafBytes.lastIndex(of: 0x2E), dot != leafBytes.startIndex else {
                return false
            }
            let suffixStart = dot + 1
            guard suffixStart < leafBytes.endIndex else { return false }
            let extensionValue = String(decoding: leafBytes[suffixStart...], as: UTF8.self)
            return archiveGenerationUTF8Equal(
                comparisonValue(extensionValue, policy: policy.pathComparison),
                value
            )
        }
    }
}

private struct ArchiveGenerationWorkBudget {
    let maximum: UInt64
    let cancellationCheckInterval: UInt64
    private(set) var consumed: UInt64 = 0
    private var checkpoints: UInt64 = 0

    init(maximum: UInt64, cancellationCheckInterval: Int) {
        self.maximum = maximum
        self.cancellationCheckInterval = UInt64(cancellationCheckInterval)
    }

    mutating func consume(_ units: UInt64) throws {
        let (next, overflow) = consumed.addingReportingOverflow(units)
        guard !overflow, next <= maximum else {
            throw ArchiveGenerationPlanningError.workLimitExceeded(maximumUnits: maximum)
        }
        consumed = next
    }

    mutating func consumeProduct(_ left: UInt64, _ right: UInt64) throws {
        let (product, overflow) = left.multipliedReportingOverflow(by: right)
        guard !overflow else {
            throw ArchiveGenerationPlanningError.workLimitExceeded(maximumUnits: maximum)
        }
        try consume(product)
    }

    mutating func consumeProduct(_ first: UInt64, _ second: UInt64, _ third: UInt64) throws {
        let (partial, firstOverflow) = first.multipliedReportingOverflow(by: second)
        let (product, secondOverflow) = partial.multipliedReportingOverflow(by: third)
        guard !firstOverflow, !secondOverflow else {
            throw ArchiveGenerationPlanningError.workLimitExceeded(maximumUnits: maximum)
        }
        try consume(product)
    }

    mutating func consumeSortUTF8UpperBound(values: [String]) throws {
        var maximumValueBytes: UInt64 = 0
        for value in values {
            try checkpoint()
            maximumValueBytes = max(maximumValueBytes, UInt64(value.utf8.count))
        }
        guard values.count > 1 else { return }
        let comparisonPasses = UInt64(Int.bitWidth - (values.count - 1).leadingZeroBitCount)
        try consumeProduct(UInt64(values.count), comparisonPasses)
        try consumeProduct(maximumValueBytes, UInt64(values.count), comparisonPasses)
        try consumeProduct(maximumValueBytes, UInt64(values.count), comparisonPasses)
        try Task.checkCancellation()
    }

    mutating func checkpoint() throws {
        try consume(1)
        checkpoints &+= 1
        if checkpoints % cancellationCheckInterval == 0 { try Task.checkCancellation() }
    }
}

private struct ArchiveGenerationDigest {
    private var hasher = SHA256()

    init(domain: String) {
        string(domain)
    }

    mutating func version(_ value: Int) {
        uint(UInt64(value))
    }

    mutating func bool(_ value: Bool) {
        bytes([value ? 1 : 0])
    }

    mutating func uint(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer in
            bytes(Array(buffer))
        }
    }

    mutating func int(_ value: Int64) {
        uint(UInt64(bitPattern: value))
    }

    mutating func uuid(_ value: UUID) {
        var raw = value.uuid
        withUnsafeBytes(of: &raw) { buffer in
            bytes(Array(buffer))
        }
    }

    mutating func string(_ value: String) {
        bytes(Array(value.utf8))
    }

    mutating func optionalString(_ value: String?) {
        bool(value != nil)
        if let value { string(value) }
    }

    mutating func bytes(_ value: [UInt8]) {
        var length = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &length) { buffer in
            hasher.update(bufferPointer: buffer)
        }
        value.withUnsafeBytes { buffer in
            hasher.update(bufferPointer: buffer)
        }
    }

    mutating func sourceItem(_ item: ArchiveGenerationSourceItem?) {
        bool(item != nil)
        guard let item else { return }
        string(item.requestedURL.absoluteString)
        revision(item.revision)
        authority(item.accessAuthority)
    }

    mutating func revision(_ revision: ArchiveGenerationSourceRevision) {
        let identity = revision.identity
        string(identity.canonicalURL.absoluteString)
        string(identity.root.canonicalURL.absoluteString)
        node(identity.root.node)
        string(identity.relativePath)
        string(identity.kind.rawValue)
        node(identity.node)
        string(ArchiveGenerationDirectoryRevisionPolicy.required.rawValue)
        uint(revision.byteCount)
        uint(revision.directoryChildCount)
        uint(revision.directoryChildNameUTF8ByteCount)
        uint(revision.linkCount)
        uint(UInt64(revision.permissions))
        uint(UInt64(revision.ownerID))
        uint(UInt64(revision.groupID))
        uint(UInt64(revision.flags))
        uint(revision.metadataByteCount)
        int(revision.modificationTimeSeconds)
        int(Int64(revision.modificationTimeNanoseconds))
        int(revision.statusChangeTimeSeconds)
        int(Int64(revision.statusChangeTimeNanoseconds))
        bytes(revision.contentSHA256)
        bytes(revision.metadataSHA256)
    }

    mutating func node(_ node: ArchiveGenerationNodeIdentity) {
        uint(node.deviceID)
        uint(node.fileID)
        uint(UInt64(node.generation))
    }

    mutating func authority(_ authority: ArchiveGenerationAccessAuthority) {
        switch authority {
        case .ambient:
            string("ambient")
        case .callerManagedWhenRequired:
            string("callerManagedWhenRequired")
        case .securityScoped(let resourceURL, let coverage):
            string("securityScoped")
            string(resourceURL.absoluteString)
            string(coverage.rawValue)
        }
    }

    mutating func outputOptions(_ options: ArchiveGenerationOutputOptions) {
        string(options.format.rawValue)
        string(options.compression.rawValue)
        bool(options.compressionLevel != nil)
        if let level = options.compressionLevel { int(Int64(level)) }
        string(options.metadataPolicy.rawValue)
        optionalString(options.pathPrefix)
        optionalString(options.archiveComment)
        uint(UInt64(options.destinationPermissions))
    }

    mutating func selection(
        _ selection: ArchiveGenerationSelection,
        work: inout ArchiveGenerationWorkBudget
    ) throws {
        switch selection {
        case .all(let side):
            string("all")
            string(side.rawValue)
        case .only(let entries):
            string("only")
            try work.consumeSortUTF8UpperBound(values: entries.map(\.id.rawValue))
            try work.consumeSortUTF8UpperBound(
                values: entries.compactMap(\.archiveRelativePath)
            )
            var sorted = entries
            try archiveGenerationDeterministicSort(&sorted) { left, right in
                if !archiveGenerationUTF8Equal(left.id.rawValue, right.id.rawValue) {
                    return try archiveGenerationUTF8Precedes(
                        left.id.rawValue,
                        right.id.rawValue
                    )
                }
                if left.side != right.side { return left.side.rawValue < right.side.rawValue }
                return try archiveGenerationUTF8Precedes(
                    left.archiveRelativePath ?? "",
                    right.archiveRelativePath ?? ""
                )
            }
            uint(UInt64(sorted.count))
            for entry in sorted {
                string(entry.id.rawValue)
                string(entry.side.rawValue)
                optionalString(entry.archiveRelativePath)
            }
        }
    }

    mutating func inclusionPolicy(_ policy: ArchiveGenerationInclusionPolicy) {
        string(ArchiveGenerationPathPolicy.required.rawValue)
        uint(UInt64(policy.filter.statuses.count))
        let statuses = ArchiveGenerationComparisonStatus.allCases.filter {
            policy.filter.statuses.contains($0)
        }
        for status in statuses {
            string(status.rawValue)
        }
        uint(UInt64(policy.filter.kinds.count))
        let kinds = ArchiveGenerationItemKind.allCases.filter {
            policy.filter.kinds.contains($0)
        }
        for kind in kinds {
            string(kind.rawValue)
        }
        string(policy.filter.hidden.rawValue)
        string(policy.filter.defaultPathAction.rawValue)
        string(policy.filter.pathComparison.rawValue)
        uint(UInt64(policy.filter.pathRules.count))
        for rule in policy.filter.pathRules {
            string(rule.action.rawValue)
            switch rule.match {
            case .exact(let value):
                string("exact")
                string(value)
            case .subtree(let value):
                string("subtree")
                string(value)
            case .pathExtension(let value):
                string("extension")
                string(value)
            }
        }
        string(policy.directorySelection.rawValue)
        string(policy.missingSide.rawValue)
        string(policy.symbolicLinks.rawValue)
        string(policy.specialFiles.rawValue)
    }

    mutating func destination(_ destination: ArchiveGenerationDestination) {
        string(destination.requestedURL.absoluteString)
        switch destination.intent {
        case .createNew(let location):
            string("createNew")
            string(location.canonicalURL.absoluteString)
            string(location.parent.canonicalURL.absoluteString)
            node(location.parent.node)
        case .replaceExisting(let revision):
            string("replaceExisting")
            self.revision(revision)
        }
        authority(destination.accessAuthority)
    }

    mutating func capabilities(_ capabilities: ArchiveGenerationExecutorCapabilities) {
        string(capabilities.identifier)
        uint(capabilities.revision)
        let codecs = ArchiveGenerationContainerFormat.allCases.flatMap { format in
            ArchiveGenerationCompressionMethod.allCases.compactMap { compression in
                let codec = ArchiveGenerationCodec(format: format, compression: compression)
                return capabilities.codecs.contains(codec) ? codec : nil
            }
        }
        uint(UInt64(codecs.count))
        for codec in codecs {
            string(codec.format.rawValue)
            string(codec.compression.rawValue)
        }
    }

    mutating func limits(_ limits: ArchiveGenerationLimits) {
        uint(UInt64(limits.maximumSnapshotEntries))
        uint(UInt64(limits.maximumSelectedEntries))
        uint(UInt64(limits.maximumFilterRules))
        uint(UInt64(limits.maximumIdentifierUTF8Bytes))
        uint(UInt64(limits.maximumPathUTF8Bytes))
        uint(UInt64(limits.maximumPathDepth))
        uint(UInt64(limits.maximumTotalPathUTF8Bytes))
        uint(limits.maximumTotalPathComponents)
        uint(limits.maximumItemBytes)
        uint(limits.maximumTotalSourceBytes)
        uint(limits.maximumMetadataBytes)
        uint(limits.maximumArchiveBytes)
        uint(UInt64(limits.maximumOptionUTF8Bytes))
        uint(UInt64(limits.maximumRetainedPlanBytes))
        uint(limits.maximumWorkUnits)
        uint(UInt64(limits.cancellationCheckInterval))
    }

    mutating func finalize() -> [UInt8] {
        Array(hasher.finalize())
    }
}

private func archiveGenerationComparisonEntryIsCoherent(
    _ entry: ArchiveGenerationComparisonEntry,
    kind comparisonKind: ArchiveGenerationComparisonKind
) -> Bool {
    let items = [entry.left, entry.right].compactMap { $0 }
    guard
        items.allSatisfy({ item in
            archiveGenerationUTF8Equal(item.revision.identity.relativePath, entry.relativePath)
        })
    else {
        return false
    }
    if comparisonKind == .file,
        !items.allSatisfy({ $0.revision.identity.kind == .regularFile })
    {
        return false
    }
    switch entry.status {
    case .leftOnly:
        return entry.left != nil && entry.right == nil
    case .rightOnly:
        return entry.left == nil && entry.right != nil
    case .identical:
        guard let leftKind = entry.left?.revision.identity.kind,
            let leftRevision = entry.left?.revision,
            let rightKind = entry.right?.revision.identity.kind,
            let rightRevision = entry.right?.revision
        else {
            return false
        }
        return leftKind == rightKind
            && leftRevision.byteCount == rightRevision.byteCount
            && leftRevision.directoryChildCount == rightRevision.directoryChildCount
            && leftRevision.directoryChildNameUTF8ByteCount
                == rightRevision.directoryChildNameUTF8ByteCount
            && leftRevision.contentSHA256 == rightRevision.contentSHA256
    case .different:
        guard let leftKind = entry.left?.revision.identity.kind,
            let leftRevision = entry.left?.revision,
            let rightKind = entry.right?.revision.identity.kind,
            let rightRevision = entry.right?.revision
        else {
            return false
        }
        return leftKind == rightKind
            && (leftRevision.byteCount != rightRevision.byteCount
                || leftRevision.directoryChildCount != rightRevision.directoryChildCount
                || leftRevision.directoryChildNameUTF8ByteCount
                    != rightRevision.directoryChildNameUTF8ByteCount
                || leftRevision.contentSHA256 != rightRevision.contentSHA256)
    case .typeMismatch:
        guard let leftKind = entry.left?.revision.identity.kind,
            let rightKind = entry.right?.revision.identity.kind
        else {
            return false
        }
        return leftKind != rightKind
    case .skipped, .error:
        guard let firstKind = items.first?.revision.identity.kind else { return false }
        return items.allSatisfy { $0.revision.identity.kind == firstKind }
    }
}

private func boundedUTF8Count(_ value: String, maximum: Int) throws -> Int {
    var count = 0
    for _ in value.utf8 {
        if count == maximum {
            return maximum + 1
        }
        count += 1
        if count & 0xFFF == 0 { try Task.checkCancellation() }
    }
    return count
}

private func archiveGenerationDeterministicSort<Element>(
    _ values: inout [Element],
    by precedes: (Element, Element) throws -> Bool
) throws {
    guard values.count > 1 else { return }
    var source = values
    var destination = values
    var width = 1
    while width < values.count {
        try Task.checkCancellation()
        var start = 0
        while start < values.count {
            let middle = min(start + width, values.count)
            let end = min(start + width + width, values.count)
            var left = start
            var right = middle
            var output = start
            while left < middle || right < end {
                let takeLeft: Bool
                if right >= end {
                    takeLeft = true
                } else if left >= middle {
                    takeLeft = false
                } else {
                    takeLeft = try !precedes(source[right], source[left])
                }
                if takeLeft {
                    destination[output] = source[left]
                    left += 1
                } else {
                    destination[output] = source[right]
                    right += 1
                }
                output += 1
            }
            start = end
        }
        swap(&source, &destination)
        if width > values.count / 2 { break }
        width *= 2
    }
    values = source
}

private func archiveGenerationAbsolutePath(_ relativePath: String, under root: String) -> String {
    archiveGenerationUTF8Equal(root, "/") ? "/\(relativePath)" : "\(root)/\(relativePath)"
}

private func archiveGenerationIsStrictNormalizedRelativePath(
    _ path: String,
    maximumUTF8Bytes: Int,
    maximumDepth: Int
) -> Bool {
    guard !path.isEmpty,
        path.utf8.first != 0x2F,
        !path.utf8.contains(0x5C),
        !path.utf8.contains(0),
        path.utf8.count <= maximumUTF8Bytes
    else {
        return false
    }
    let components = archiveGenerationUTF8PathComponents(path)
    guard !components.isEmpty, components.count <= maximumDepth else { return false }
    return components.allSatisfy {
        !$0.isEmpty
            && !archiveGenerationUTF8Equal($0, ".")
            && !archiveGenerationUTF8Equal($0, "..")
            && $0.utf8.count <= 255
    }
}

private func archiveGenerationUTF8Equal(_ left: String, _ right: String) -> Bool {
    left.utf8.elementsEqual(right.utf8)
}

private func archiveGenerationUTF8PathComponents(_ path: String) -> [String] {
    path.utf8.split(separator: 0x2F, omittingEmptySubsequences: false).map {
        String(decoding: $0, as: UTF8.self)
    }
}

private func archiveGenerationParentAndLeaf(
    _ path: String
) -> (parent: String, leaf: String)? {
    let bytes = Array(path.utf8)
    guard let separator = bytes.lastIndex(of: 0x2F) else { return nil }
    return (
        String(decoding: bytes[..<separator], as: UTF8.self),
        String(decoding: bytes[(separator + 1)...], as: UTF8.self)
    )
}

private func archiveGenerationRelativeSuffix(_ path: String, after root: String) -> String? {
    let pathBytes = Array(path.utf8)
    let rootBytes = Array(root.utf8)
    guard pathBytes.count > rootBytes.count,
        pathBytes.starts(with: rootBytes),
        pathBytes[rootBytes.count] == 0x2F
    else {
        return nil
    }
    return String(decoding: pathBytes[(rootBytes.count + 1)...], as: UTF8.self)
}

private func archiveGenerationOptionalUTF8Equal(_ left: String?, _ right: String?) -> Bool {
    switch (left, right) {
    case (nil, nil): true
    case (.some(let left), .some(let right)): archiveGenerationUTF8Equal(left, right)
    default: false
    }
}

private func archiveGenerationDirectoryIdentityEqual(
    _ left: ArchiveGenerationCanonicalDirectoryIdentity,
    _ right: ArchiveGenerationCanonicalDirectoryIdentity
) -> Bool {
    left.node == right.node
        && archiveGenerationUTF8Equal(left.canonicalURL.absoluteString, right.canonicalURL.absoluteString)
}

private func archiveGenerationSourceRevisionEqual(
    _ left: ArchiveGenerationSourceRevision,
    _ right: ArchiveGenerationSourceRevision
) -> Bool {
    let leftIdentity = left.identity
    let rightIdentity = right.identity
    return ArchiveGenerationSourceIdentityKey(leftIdentity)
        == ArchiveGenerationSourceIdentityKey(rightIdentity)
        && left.byteCount == right.byteCount
        && left.directoryChildCount == right.directoryChildCount
        && left.directoryChildNameUTF8ByteCount == right.directoryChildNameUTF8ByteCount
        && left.linkCount == right.linkCount
        && left.permissions == right.permissions
        && left.ownerID == right.ownerID
        && left.groupID == right.groupID
        && left.flags == right.flags
        && left.metadataByteCount == right.metadataByteCount
        && left.modificationTimeSeconds == right.modificationTimeSeconds
        && left.modificationTimeNanoseconds == right.modificationTimeNanoseconds
        && left.statusChangeTimeSeconds == right.statusChangeTimeSeconds
        && left.statusChangeTimeNanoseconds == right.statusChangeTimeNanoseconds
        && left.contentSHA256 == right.contentSHA256
        && left.metadataSHA256 == right.metadataSHA256
}

private func archiveGenerationSourceRevisionIsBounded(
    _ revision: ArchiveGenerationSourceRevision,
    limits: ArchiveGenerationLimits
) throws -> Bool {
    let identity = revision.identity
    guard
        try boundedUTF8Count(
            identity.canonicalURL.absoluteString,
            maximum: limits.maximumPathUTF8Bytes * 3
        ) <= limits.maximumPathUTF8Bytes * 3,
        try boundedUTF8Count(
            identity.root.canonicalURL.absoluteString,
            maximum: limits.maximumPathUTF8Bytes * 3
        ) <= limits.maximumPathUTF8Bytes * 3,
        archiveGenerationIsStrictNormalizedRelativePath(
            identity.relativePath,
            maximumUTF8Bytes: limits.maximumPathUTF8Bytes,
            maximumDepth: limits.maximumPathDepth
        ),
        revision.contentSHA256.count == SHA256.Digest.byteCount,
        revision.metadataSHA256.count == SHA256.Digest.byteCount,
        revision.metadataByteCount <= limits.maximumMetadataBytes
    else {
        return false
    }
    if identity.kind == .directory {
        return revision.byteCount == 0
            && revision.directoryChildCount <= UInt64(limits.maximumSnapshotEntries)
            && revision.directoryChildNameUTF8ByteCount
                <= UInt64(limits.maximumTotalPathUTF8Bytes)
    }
    return revision.directoryChildCount == 0
        && revision.directoryChildNameUTF8ByteCount == 0
        && revision.byteCount <= limits.maximumItemBytes
}

private func archiveGenerationDirectoryIdentityIsBounded(
    _ identity: ArchiveGenerationCanonicalDirectoryIdentity,
    limits: ArchiveGenerationLimits
) throws -> Bool {
    try boundedUTF8Count(
        identity.canonicalURL.absoluteString,
        maximum: limits.maximumPathUTF8Bytes * 3
    ) <= limits.maximumPathUTF8Bytes * 3
}

private func isRelativeDescendant(_ path: String, of root: String) -> Bool {
    archiveGenerationIsUTF8Descendant(path, of: root, rootIsFilesystemRoot: false)
}

private func isLexicalDescendant(_ path: String, of root: String) -> Bool {
    archiveGenerationIsUTF8Descendant(path, of: root, rootIsFilesystemRoot: true)
}

private func archiveGenerationIsUTF8Descendant(
    _ path: String,
    of root: String,
    rootIsFilesystemRoot: Bool
) -> Bool {
    let pathBytes = Array(path.utf8)
    let rootBytes = Array(root.utf8)
    if rootIsFilesystemRoot, rootBytes == [0x2F] {
        return pathBytes.count > 1 && pathBytes.first == 0x2F
    }
    guard pathBytes.count > rootBytes.count,
        pathBytes.starts(with: rootBytes)
    else {
        return false
    }
    return pathBytes[rootBytes.count] == 0x2F
}

private func portableCollisionKey(_ path: String) -> String {
    archiveGenerationASCIILowercased(path)
}

private func comparisonValue(
    _ value: String,
    policy: ArchiveGenerationPathComparison
) -> String {
    switch policy {
    case .caseSensitive:
        value
    case .portableCaseInsensitive:
        portableCollisionKey(value)
    }
}

private func isReservedDeviceName(_ component: String) -> Bool {
    var stem = String(
        component.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
    )
    while stem.last == "." || stem.last == " " { stem.removeLast() }
    stem = archiveGenerationASCIILowercased(stem)
    if stem == "con" || stem == "prn" || stem == "aux" || stem == "nul"
        || stem == "clock$" || stem == "conin$" || stem == "conout$"
    {
        return true
    }
    guard stem.count == 4, let suffix = stem.last else { return false }
    return (stem.hasPrefix("com") || stem.hasPrefix("lpt"))
        && ("1"..."9").contains(String(suffix))
}

private func archiveGenerationIsASCII(_ value: String) -> Bool {
    value.utf8.allSatisfy { $0 < 0x80 }
}

private func archiveGenerationASCIILowercased(_ value: String) -> String {
    String(
        decoding: value.utf8.map { byte in
            (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
        }, as: UTF8.self)
}

private func archiveGenerationUTF8Precedes(
    _ left: String,
    _ right: String
) throws -> Bool {
    try Task.checkCancellation()
    return left.utf8.lexicographicallyPrecedes(right.utf8)
}

private func archiveGenerationSourceRevisionPrecedes(
    _ left: ArchiveGenerationSourceRevision,
    _ right: ArchiveGenerationSourceRevision
) throws -> Bool {
    try Task.checkCancellation()
    let leftIdentity = left.identity
    let rightIdentity = right.identity
    let leftRootURL = leftIdentity.root.canonicalURL.absoluteString
    let rightRootURL = rightIdentity.root.canonicalURL.absoluteString
    if !archiveGenerationUTF8Equal(leftRootURL, rightRootURL) {
        return try archiveGenerationUTF8Precedes(leftRootURL, rightRootURL)
    }
    if leftIdentity.root.node.deviceID != rightIdentity.root.node.deviceID {
        return leftIdentity.root.node.deviceID < rightIdentity.root.node.deviceID
    }
    if leftIdentity.root.node.fileID != rightIdentity.root.node.fileID {
        return leftIdentity.root.node.fileID < rightIdentity.root.node.fileID
    }
    if leftIdentity.root.node.generation != rightIdentity.root.node.generation {
        return leftIdentity.root.node.generation < rightIdentity.root.node.generation
    }
    if !archiveGenerationUTF8Equal(leftIdentity.relativePath, rightIdentity.relativePath) {
        return try archiveGenerationUTF8Precedes(
            leftIdentity.relativePath,
            rightIdentity.relativePath
        )
    }
    let leftURL = leftIdentity.canonicalURL.absoluteString
    let rightURL = rightIdentity.canonicalURL.absoluteString
    if !archiveGenerationUTF8Equal(leftURL, rightURL) {
        return try archiveGenerationUTF8Precedes(leftURL, rightURL)
    }
    if leftIdentity.kind != rightIdentity.kind {
        return leftIdentity.kind.rawValue < rightIdentity.kind.rawValue
    }
    if leftIdentity.node.deviceID != rightIdentity.node.deviceID {
        return leftIdentity.node.deviceID < rightIdentity.node.deviceID
    }
    if leftIdentity.node.fileID != rightIdentity.node.fileID {
        return leftIdentity.node.fileID < rightIdentity.node.fileID
    }
    return leftIdentity.node.generation < rightIdentity.node.generation
}

private func archiveGenerationSourceIdentitySortStrings(
    _ revision: ArchiveGenerationSourceRevision
) -> [String] {
    let identity = revision.identity
    return [
        identity.root.canonicalURL.absoluteString,
        identity.relativePath,
        identity.canonicalURL.absoluteString
    ]
}

private func archiveGenerationSourceLocationPrecedes(
    _ left: ArchiveGenerationSourceLocation,
    _ right: ArchiveGenerationSourceLocation
) throws -> Bool {
    if left.side != right.side { return left.side.rawValue < right.side.rawValue }
    let leftRoot = left.root.canonicalURL.absoluteString
    let rightRoot = right.root.canonicalURL.absoluteString
    if !archiveGenerationUTF8Equal(leftRoot, rightRoot) {
        return try archiveGenerationUTF8Precedes(leftRoot, rightRoot)
    }
    if left.root.node.deviceID != right.root.node.deviceID {
        return left.root.node.deviceID < right.root.node.deviceID
    }
    if left.root.node.fileID != right.root.node.fileID {
        return left.root.node.fileID < right.root.node.fileID
    }
    if left.root.node.generation != right.root.node.generation {
        return left.root.node.generation < right.root.node.generation
    }
    return try archiveGenerationUTF8Precedes(left.relativePath, right.relativePath)
}

extension ArchiveGenerationItemKind {
    fileprivate var directoryRevisionTag: UInt8 {
        switch self {
        case .regularFile: 0
        case .directory: 1
        case .symbolicLink: 2
        case .specialFile: 3
        }
    }
}
