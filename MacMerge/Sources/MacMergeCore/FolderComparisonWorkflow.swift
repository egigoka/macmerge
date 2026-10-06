import CryptoKit
import Foundation

public enum FolderComparisonWorkflowSide: String, CaseIterable, Hashable, Sendable {
    case left
    case right

    fileprivate var comparisonSide: FolderComparisonSide {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}

/// Descriptor identity for one caller-resolved canonical directory. URLs remain audit and access
/// metadata; executors compare this identity through pinned descriptors.
public struct FolderComparisonRootIdentity: Hashable, Sendable {
    public let canonicalURL: URL
    public let deviceID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    public init(canonicalURL: URL, deviceID: UInt64, fileID: UInt64, generation: UInt32) {
        self.canonicalURL = canonicalURL
        self.deviceID = deviceID
        self.fileID = fileID
        self.generation = generation
    }
}

/// Exact caller-captured root revision. Executors must hold this revision stable for the complete
/// scan, comparison materialization, file operation, or file-pair open transaction.
public struct FolderComparisonRootRevision: Hashable, Sendable {
    public let identity: FolderComparisonRootIdentity
    public let linkCount: UInt64
    public let permissions: UInt16
    public let ownerID: UInt32
    public let groupID: UInt32
    public let flags: UInt32
    public let modificationTimeSeconds: Int64
    public let modificationTimeNanoseconds: Int32
    public let statusChangeTimeSeconds: Int64
    public let statusChangeTimeNanoseconds: Int32
    /// Executor-defined digest of root ACLs, extended attributes, and other relevant metadata.
    public let metadataSHA256: [UInt8]

    public init(
        identity: FolderComparisonRootIdentity,
        linkCount: UInt64,
        permissions: UInt16,
        ownerID: UInt32,
        groupID: UInt32,
        flags: UInt32,
        modificationTimeSeconds: Int64,
        modificationTimeNanoseconds: Int32,
        statusChangeTimeSeconds: Int64,
        statusChangeTimeNanoseconds: Int32,
        metadataSHA256: [UInt8]
    ) {
        self.identity = identity
        self.linkCount = linkCount
        self.permissions = permissions
        self.ownerID = ownerID
        self.groupID = groupID
        self.flags = flags
        self.modificationTimeSeconds = modificationTimeSeconds
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.statusChangeTimeSeconds = statusChangeTimeSeconds
        self.statusChangeTimeNanoseconds = statusChangeTimeNanoseconds
        self.metadataSHA256 = metadataSHA256
    }
}

public enum FolderComparisonAuthorityPermission: String, CaseIterable, Hashable, Sendable {
    case enumerate
    case readContent
    case mutate
}

public enum FolderComparisonAuthorityCoverage: String, CaseIterable, Hashable, Sendable {
    case exactRoot
    case directoryTree
}

/// Access acquisition intent only. An executor proves access availability and scope coverage while
/// the matching root descriptor remains pinned.
public enum FolderComparisonAuthorityAcquisition: Hashable, Sendable {
    case ambient
    case callerManagedWhenRequired
    case securityScoped(resourceURL: URL, coverage: FolderComparisonAuthorityCoverage)
}

public struct FolderComparisonAccessAuthority: Hashable, Sendable {
    public let identity: UUID
    /// Opaque, monotonically advancing, never-reused authority revision.
    public let revision: UInt64
    public let rootIdentity: FolderComparisonRootIdentity
    public let permissions: Set<FolderComparisonAuthorityPermission>
    /// Scope proved by the authority while the root descriptor remains pinned.
    public let coverage: FolderComparisonAuthorityCoverage
    public let acquisition: FolderComparisonAuthorityAcquisition

    public init(
        identity: UUID,
        revision: UInt64,
        rootIdentity: FolderComparisonRootIdentity,
        permissions: Set<FolderComparisonAuthorityPermission>,
        coverage: FolderComparisonAuthorityCoverage,
        acquisition: FolderComparisonAuthorityAcquisition
    ) {
        self.identity = identity
        self.revision = revision
        self.rootIdentity = rootIdentity
        self.permissions = permissions
        self.coverage = coverage
        self.acquisition = acquisition
    }
}

public struct FolderComparisonRoot: Hashable, Sendable {
    /// Original caller-owned URL, retained because it may carry sandbox authority.
    public let requestedURL: URL
    public let revision: FolderComparisonRootRevision
    public let authority: FolderComparisonAccessAuthority
    /// Filesystem slot comparison behavior proved for this pinned root.
    public let pathCaseSensitivity: FolderPathCaseSensitivitySelection

    public init(
        requestedURL: URL,
        revision: FolderComparisonRootRevision,
        authority: FolderComparisonAccessAuthority,
        pathCaseSensitivity: FolderPathCaseSensitivitySelection
    ) {
        self.requestedURL = requestedURL
        self.revision = revision
        self.authority = authority
        self.pathCaseSensitivity = pathCaseSensitivity
    }
}

public struct FolderComparisonRootPair: Hashable, Sendable {
    public let left: FolderComparisonRoot
    public let right: FolderComparisonRoot

    public init(left: FolderComparisonRoot, right: FolderComparisonRoot) {
        self.left = left
        self.right = right
    }

    public subscript(side: FolderComparisonWorkflowSide) -> FolderComparisonRoot {
        switch side {
        case .left: left
        case .right: right
        }
    }
}

public struct FolderComparisonItemIdentity: Hashable, Sendable {
    public let rootIdentity: FolderComparisonRootIdentity
    public let relativePath: String
    public let deviceID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    public init(
        rootIdentity: FolderComparisonRootIdentity,
        relativePath: String,
        deviceID: UInt64,
        fileID: UInt64,
        generation: UInt32
    ) {
        self.rootIdentity = rootIdentity
        self.relativePath = relativePath
        self.deviceID = deviceID
        self.fileID = fileID
        self.generation = generation
    }
}

/// Exact item revision captured through descriptor-relative, no-follow access under its pinned root.
public struct FolderComparisonItemRevision: Hashable, Sendable {
    public let identity: FolderComparisonItemIdentity
    public let kind: DirectoryEntryKind
    public let byteCount: UInt64?
    public let linkCount: UInt64
    public let permissions: UInt16
    public let ownerID: UInt32
    public let groupID: UInt32
    public let flags: UInt32
    public let modificationTimeSeconds: Int64
    public let modificationTimeNanoseconds: Int32
    public let statusChangeTimeSeconds: Int64
    public let statusChangeTimeNanoseconds: Int32
    public let metadataSHA256: [UInt8]
    public let contentSHA256: [UInt8]?

    public init(
        identity: FolderComparisonItemIdentity,
        kind: DirectoryEntryKind,
        byteCount: UInt64?,
        linkCount: UInt64,
        permissions: UInt16,
        ownerID: UInt32,
        groupID: UInt32,
        flags: UInt32,
        modificationTimeSeconds: Int64,
        modificationTimeNanoseconds: Int32,
        statusChangeTimeSeconds: Int64,
        statusChangeTimeNanoseconds: Int32,
        metadataSHA256: [UInt8],
        contentSHA256: [UInt8]? = nil
    ) {
        self.identity = identity
        self.kind = kind
        self.byteCount = byteCount
        self.linkCount = linkCount
        self.permissions = permissions
        self.ownerID = ownerID
        self.groupID = groupID
        self.flags = flags
        self.modificationTimeSeconds = modificationTimeSeconds
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.statusChangeTimeSeconds = statusChangeTimeSeconds
        self.statusChangeTimeNanoseconds = statusChangeTimeNanoseconds
        self.metadataSHA256 = metadataSHA256
        self.contentSHA256 = contentSHA256
    }
}

public struct FolderComparisonResultRevision: Hashable, Sendable {
    public let id: DirectoryResult.ID
    public let left: FolderComparisonItemRevision?
    public let right: FolderComparisonItemRevision?

    public init(
        id: DirectoryResult.ID,
        left: FolderComparisonItemRevision?,
        right: FolderComparisonItemRevision?
    ) {
        self.id = id
        self.left = left
        self.right = right
    }

    public subscript(side: FolderComparisonWorkflowSide) -> FolderComparisonItemRevision? {
        switch side {
        case .left: left
        case .right: right
        }
    }
}

public enum FolderComparisonWorkflowFeature: String, CaseIterable, Hashable, Sendable {
    case nonrecursiveScan
    case recursiveScan
    case metadataComparison
    case contentComparison
    case tablePresentation
    case treePresentation
    case copyItems
    case moveItems
    case deleteItems
    case synchronizeItems
    case progressReporting
    case pause
    case resume
    case cancel
    case openFilePair
}

/// Exact executor capability revision used during planning. Executors reject plans after capability
/// identity, revision, or feature membership changes.
public struct FolderComparisonWorkflowCapabilities: Hashable, Sendable {
    public let identity: UUID
    public let revision: UInt64
    public let features: Set<FolderComparisonWorkflowFeature>

    public init(
        identity: UUID,
        revision: UInt64,
        features: Set<FolderComparisonWorkflowFeature>
    ) {
        self.identity = identity
        self.revision = revision
        self.features = features
    }
}

public enum FolderComparisonMethodSelection: String, CaseIterable, Hashable, Sendable {
    case metadataOnly
    case contentIfAvailable
    case contentRequired

    public var comparatorMethod: FolderComparisonMethod {
        switch self {
        case .metadataOnly: .metadataOnly
        case .contentIfAvailable: .contentIfAvailable
        case .contentRequired: .contentRequired
        }
    }
}

public struct FolderComparisonSettings: Hashable, Sendable {
    public let method: FolderComparisonMethodSelection
    public let pathCaseSensitivity: FolderPathCaseSensitivitySelection
    public let modificationDateTolerance: TimeInterval

    public init(
        method: FolderComparisonMethodSelection = .metadataOnly,
        pathCaseSensitivity: FolderPathCaseSensitivitySelection = .sensitive,
        modificationDateTolerance: TimeInterval = 0
    ) {
        self.method = method
        self.pathCaseSensitivity = pathCaseSensitivity
        self.modificationDateTolerance = modificationDateTolerance
    }

    public var comparatorOptions: FolderComparisonOptions {
        FolderComparisonOptions(
            method: method.comparatorMethod,
            pathCaseSensitivity: pathCaseSensitivity.comparatorValue,
            modificationDateTolerance: modificationDateTolerance
        )
    }
}

public enum FolderPathCaseSensitivitySelection: String, CaseIterable, Hashable, Sendable {
    case sensitive
    case insensitive

    public var comparatorValue: FolderPathCaseSensitivity {
        switch self {
        case .sensitive: .sensitive
        case .insensitive: .insensitive
        }
    }
}

public struct FolderComparisonScanFilter: Hashable, Sendable {
    public let rules: [FilenameFilterRule]
    public let defaultDecision: FilenameFilterDecision
    public let matchSemantics: FilenameFilterMatchSemantics
    public let casePolicy: FilenameFilterCasePolicy
    public let limits: FilenameFilterLimits

    public init(
        rules: [FilenameFilterRule],
        defaultDecision: FilenameFilterDecision = .include,
        matchSemantics: FilenameFilterMatchSemantics = .lastMatchWins,
        casePolicy: FilenameFilterCasePolicy = .sensitive,
        limits: FilenameFilterLimits = .default
    ) {
        self.rules = rules
        self.defaultDecision = defaultDecision
        self.matchSemantics = matchSemantics
        self.casePolicy = casePolicy
        self.limits = limits
    }
}

public struct FolderComparisonScanIntent: Hashable, Sendable {
    public let recursive: Bool
    public let options: FolderScanOptions
    public let filenameFilter: FolderComparisonScanFilter?

    public init(
        recursive: Bool = true,
        options: FolderScanOptions = FolderScanOptions(),
        filenameFilter: FolderComparisonScanFilter? = nil
    ) {
        self.recursive = recursive
        self.options = options
        self.filenameFilter = filenameFilter
    }
}

public struct FolderComparisonWorkflowSnapshotIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct FolderComparisonWorkflowSnapshotTarget: Hashable, Sendable {
    public let identity: FolderComparisonWorkflowSnapshotIdentity
    public let generation: UInt64
    public let owner: FolderComparisonWorkflowSnapshotOwner

    public init(
        identity: FolderComparisonWorkflowSnapshotIdentity,
        generation: UInt64,
        owner: FolderComparisonWorkflowSnapshotOwner
    ) {
        self.identity = identity
        self.generation = generation
        self.owner = owner
    }
}

/// CAS token for the store slot that owns one comparison snapshot lineage.
public struct FolderComparisonWorkflowSnapshotOwner: Hashable, Sendable {
    public let identity: UUID
    public let revision: UInt64

    public init(identity: UUID, revision: UInt64) {
        self.identity = identity
        self.revision = revision
    }
}

/// Immutable comparison result state. Owners issue exactly one successor generation whenever roots,
/// scan intent, comparison settings, result order, or any result field changes.
public struct FolderComparisonWorkflowSnapshot: Hashable, Sendable {
    public let identity: FolderComparisonWorkflowSnapshotIdentity
    public let generation: UInt64
    public let owner: FolderComparisonWorkflowSnapshotOwner
    public let roots: FolderComparisonRootPair
    public let scanIntent: FolderComparisonScanIntent
    public let comparisonSettings: FolderComparisonSettings
    /// True only when both scans completed untruncated with no collected issues.
    public let isComplete: Bool
    public let results: [DirectoryResult]
    /// Same count and order as `results`; binds every present side to an exact filesystem revision.
    public let resultRevisions: [FolderComparisonResultRevision]

    public init(
        identity: FolderComparisonWorkflowSnapshotIdentity,
        generation: UInt64,
        owner: FolderComparisonWorkflowSnapshotOwner,
        roots: FolderComparisonRootPair,
        scanIntent: FolderComparisonScanIntent,
        comparisonSettings: FolderComparisonSettings,
        isComplete: Bool,
        results: [DirectoryResult],
        resultRevisions: [FolderComparisonResultRevision]
    ) {
        self.identity = identity
        self.generation = generation
        self.owner = owner
        self.roots = roots
        self.scanIntent = scanIntent
        self.comparisonSettings = comparisonSettings
        self.isComplete = isComplete
        self.results = results
        self.resultRevisions = resultRevisions
    }
}

/// Exact snapshot CAS token. Digest is canonical SHA-256, independent of `Hasher` randomization.
public struct FolderComparisonWorkflowSnapshotReference: Hashable, Sendable {
    public let identity: FolderComparisonWorkflowSnapshotIdentity
    public let generation: UInt64
    public let owner: FolderComparisonWorkflowSnapshotOwner
    public let roots: FolderComparisonRootPair
    public let scanIntent: FolderComparisonScanIntent
    public let comparisonSettings: FolderComparisonSettings
    public let contentSHA256: [UInt8]

    fileprivate init(
        identity: FolderComparisonWorkflowSnapshotIdentity,
        generation: UInt64,
        owner: FolderComparisonWorkflowSnapshotOwner,
        roots: FolderComparisonRootPair,
        scanIntent: FolderComparisonScanIntent,
        comparisonSettings: FolderComparisonSettings,
        contentSHA256: [UInt8]
    ) {
        self.identity = identity
        self.generation = generation
        self.owner = owner
        self.roots = roots
        self.scanIntent = scanIntent
        self.comparisonSettings = comparisonSettings
        self.contentSHA256 = contentSHA256
    }
}

public enum FolderComparisonPresentationMode: String, CaseIterable, Hashable, Sendable {
    case table
    case tree
}

public enum FolderComparisonPresentationColumn: String, CaseIterable, Hashable, Sendable {
    case stateIcon
    case relativePath
    case status
    case kind
    case leftSize
    case rightSize
    case leftModificationDate
    case rightModificationDate
}

public enum FolderComparisonStateIcon: String, CaseIterable, Hashable, Sendable {
    case pending
    case identical
    case different
    case leftOnly
    case rightOnly
    case typeMismatch
    case skipped
    case error

    public init(status: DirectoryComparisonStatus) {
        switch status {
        case .pending: self = .pending
        case .identical: self = .identical
        case .different: self = .different
        case .leftOnly: self = .leftOnly
        case .rightOnly: self = .rightOnly
        case .typeMismatch: self = .typeMismatch
        case .skipped: self = .skipped
        case .error: self = .error
        }
    }
}

public enum FolderComparisonHiddenFilter: String, CaseIterable, Hashable, Sendable {
    case include
    case exclude
    case only
}

public struct FolderComparisonPresentationFilter: Hashable, Sendable {
    public let statuses: Set<DirectoryComparisonStatus>
    public let kinds: Set<DirectoryEntryKind>
    public let hidden: FolderComparisonHiddenFilter
    public let pathQuery: String

    public init(
        statuses: Set<DirectoryComparisonStatus> = [],
        kinds: Set<DirectoryEntryKind> = [],
        hidden: FolderComparisonHiddenFilter = .include,
        pathQuery: String = ""
    ) {
        self.statuses = statuses
        self.kinds = kinds
        self.hidden = hidden
        self.pathQuery = pathQuery
    }
}

public enum FolderComparisonPresentationSortKey: String, CaseIterable, Hashable, Sendable {
    case path
    case status
    case kind
    case leftSize
    case rightSize
    case leftModificationDate
    case rightModificationDate
}

public enum FolderComparisonPresentationSortOrder: String, CaseIterable, Hashable, Sendable {
    case ascending
    case descending
}

public struct FolderComparisonPresentationSortDescriptor: Hashable, Sendable {
    public let key: FolderComparisonPresentationSortKey
    public let order: FolderComparisonPresentationSortOrder

    public init(
        key: FolderComparisonPresentationSortKey,
        order: FolderComparisonPresentationSortOrder = .ascending
    ) {
        self.key = key
        self.order = order
    }
}

public struct FolderComparisonPresentationConfiguration: Hashable, Sendable {
    public let mode: FolderComparisonPresentationMode
    public let columns: [FolderComparisonPresentationColumn]
    public let filter: FolderComparisonPresentationFilter
    public let sortDescriptors: [FolderComparisonPresentationSortDescriptor]

    public init(
        mode: FolderComparisonPresentationMode = .table,
        columns: [FolderComparisonPresentationColumn] = [
            .stateIcon, .relativePath, .status, .leftSize, .rightSize
        ],
        filter: FolderComparisonPresentationFilter = FolderComparisonPresentationFilter(),
        sortDescriptors: [FolderComparisonPresentationSortDescriptor] = [
            FolderComparisonPresentationSortDescriptor(key: .path)
        ]
    ) {
        self.mode = mode
        self.columns = columns
        self.filter = filter
        self.sortDescriptors = sortDescriptors
    }
}

public struct FolderComparisonPresentationSideValue: Hashable, Sendable {
    public let relativePath: String
    public let kind: DirectoryEntryKind
    public let byteCount: UInt64?
    public let modificationDate: Date?
    public let isHidden: Bool

    fileprivate init(_ metadata: DirectoryEntryMetadata) {
        relativePath = metadata.relativePath
        kind = metadata.kind
        byteCount = metadata.byteCount
        modificationDate = metadata.modificationDate
        isHidden = metadata.isHidden
    }
}

public struct FolderComparisonPresentationRow: Identifiable, Hashable, Sendable {
    public let id: DirectoryResult.ID
    public let relativePath: String
    /// Nearest admitted directory ancestor. Nil means this row is a tree root.
    public let treeParentRelativePath: String?
    public let treeParentID: DirectoryResult.ID?
    public let treeDepth: Int
    public let stateIcon: FolderComparisonStateIcon
    public let status: DirectoryComparisonStatus
    public let kind: DirectoryEntryKind?
    public let left: FolderComparisonPresentationSideValue?
    public let right: FolderComparisonPresentationSideValue?

    fileprivate init(
        result: DirectoryResult,
        mode: FolderComparisonPresentationMode,
        treeParentRelativePath: String? = nil,
        treeParentID: DirectoryResult.ID? = nil,
        treeDepth: Int = 0
    ) {
        id = result.id
        relativePath = result.relativePath
        stateIcon = FolderComparisonStateIcon(status: result.status)
        status = result.status
        kind = result.kind
        left = result.left.map(FolderComparisonPresentationSideValue.init)
        right = result.right.map(FolderComparisonPresentationSideValue.init)
        self.treeParentRelativePath = mode == .tree ? treeParentRelativePath : nil
        self.treeParentID = mode == .tree ? treeParentID : nil
        self.treeDepth = mode == .tree ? treeDepth : 0
    }
}

public struct FolderComparisonCompareRequest: Hashable, Sendable {
    public let target: FolderComparisonWorkflowSnapshotTarget
    /// Present for refresh or method changes. Target must be its exact next generation.
    public let replacing: FolderComparisonWorkflowSnapshot?
    public let roots: FolderComparisonRootPair
    public let scanIntent: FolderComparisonScanIntent
    public let comparisonSettings: FolderComparisonSettings
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let limits: FolderComparisonWorkflowLimits

    public init(
        target: FolderComparisonWorkflowSnapshotTarget,
        replacing: FolderComparisonWorkflowSnapshot? = nil,
        roots: FolderComparisonRootPair,
        scanIntent: FolderComparisonScanIntent,
        comparisonSettings: FolderComparisonSettings,
        capabilities: FolderComparisonWorkflowCapabilities,
        limits: FolderComparisonWorkflowLimits = .default
    ) {
        self.target = target
        self.replacing = replacing
        self.roots = roots
        self.scanIntent = scanIntent
        self.comparisonSettings = comparisonSettings
        self.capabilities = capabilities
        self.limits = limits
    }
}

public struct FolderComparisonPresentationRequest: Hashable, Sendable {
    public let snapshot: FolderComparisonWorkflowSnapshot
    public let configuration: FolderComparisonPresentationConfiguration
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let limits: FolderComparisonWorkflowLimits

    public init(
        snapshot: FolderComparisonWorkflowSnapshot,
        configuration: FolderComparisonPresentationConfiguration = FolderComparisonPresentationConfiguration(),
        capabilities: FolderComparisonWorkflowCapabilities,
        limits: FolderComparisonWorkflowLimits = .default
    ) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.capabilities = capabilities
        self.limits = limits
    }
}

public enum FolderComparisonFileCollisionSelection: String, CaseIterable, Hashable, Sendable {
    case fail
    case skip
    case replaceKeepingBackup

    public var operationPolicy: FolderFileCollisionPolicy {
        switch self {
        case .fail: .fail
        case .skip: .skip
        case .replaceKeepingBackup: .replaceKeepingBackup
        }
    }
}

public enum FolderComparisonFileOperationSelection: Hashable, Sendable {
    case copy(
        ids: [DirectoryResult.ID],
        from: FolderComparisonWorkflowSide,
        collision: FolderComparisonFileCollisionSelection
    )
    case move(
        ids: [DirectoryResult.ID],
        from: FolderComparisonWorkflowSide,
        collision: FolderComparisonFileCollisionSelection
    )
    case delete(ids: [DirectoryResult.ID], side: FolderComparisonWorkflowSide)
    case synchronize(
        ids: [DirectoryResult.ID],
        from: FolderComparisonWorkflowSide,
        collision: FolderComparisonFileCollisionSelection,
        deleteExtraneous: Bool
    )
}

public struct FolderComparisonFileOperationRequest: Hashable, Sendable {
    public let snapshot: FolderComparisonWorkflowSnapshot
    public let selection: FolderComparisonFileOperationSelection
    /// Required only when an action may replace an existing destination and allocate a backup.
    public let replacementOwner: FolderComparisonReplacementOwner?
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let limits: FolderComparisonWorkflowLimits

    public init(
        snapshot: FolderComparisonWorkflowSnapshot,
        selection: FolderComparisonFileOperationSelection,
        replacementOwner: FolderComparisonReplacementOwner? = nil,
        capabilities: FolderComparisonWorkflowCapabilities,
        limits: FolderComparisonWorkflowLimits = .default
    ) {
        self.snapshot = snapshot
        self.selection = selection
        self.replacementOwner = replacementOwner
        self.capabilities = capabilities
        self.limits = limits
    }
}

/// CAS token for the executor-owned namespace used to allocate durable replacement backups.
public struct FolderComparisonReplacementOwner: Hashable, Sendable {
    public let identity: UUID
    public let revision: UInt64

    public init(identity: UUID, revision: UInt64) {
        self.identity = identity
        self.revision = revision
    }
}

public enum FolderComparisonActivityKind: String, CaseIterable, Hashable, Sendable {
    case scanning
    case comparing
    case fileOperation
    case openingFilePair
}

public enum FolderComparisonActivityState: String, CaseIterable, Hashable, Sendable {
    case running
    case paused
    case cancelling
    case completed
    case cancelled
    case failed
}

public enum FolderComparisonActivityControl: String, CaseIterable, Hashable, Sendable {
    case pause
    case resume
    case cancel
}

public struct FolderComparisonActivityProgress: Hashable, Sendable {
    public let completedUnits: UInt64
    public let totalUnits: UInt64?
    public let completedItems: Int
    public let totalItems: Int?
    public let currentRelativePath: String?

    public init(
        completedUnits: UInt64,
        totalUnits: UInt64? = nil,
        completedItems: Int,
        totalItems: Int? = nil,
        currentRelativePath: String? = nil
    ) {
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.completedItems = completedItems
        self.totalItems = totalItems
        self.currentRelativePath = currentRelativePath
    }
}

/// Exact executor-issued activity state. Revision advances for every state or progress change.
public struct FolderComparisonActivitySnapshot: Hashable, Sendable {
    public let identity: UUID
    public let revision: UInt64
    public let kind: FolderComparisonActivityKind
    public let state: FolderComparisonActivityState
    public let supportedControls: Set<FolderComparisonActivityControl>
    public let progress: FolderComparisonActivityProgress

    public init(
        identity: UUID,
        revision: UInt64,
        kind: FolderComparisonActivityKind,
        state: FolderComparisonActivityState,
        supportedControls: Set<FolderComparisonActivityControl>,
        progress: FolderComparisonActivityProgress
    ) {
        self.identity = identity
        self.revision = revision
        self.kind = kind
        self.state = state
        self.supportedControls = supportedControls
        self.progress = progress
    }
}

public struct FolderComparisonActivityControlRequest: Hashable, Sendable {
    public let activity: FolderComparisonActivitySnapshot
    public let control: FolderComparisonActivityControl
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let limits: FolderComparisonWorkflowLimits

    public init(
        activity: FolderComparisonActivitySnapshot,
        control: FolderComparisonActivityControl,
        capabilities: FolderComparisonWorkflowCapabilities,
        limits: FolderComparisonWorkflowLimits = .default
    ) {
        self.activity = activity
        self.control = control
        self.capabilities = capabilities
        self.limits = limits
    }
}

public struct FolderComparisonOpenFilePairRequest: Hashable, Sendable {
    public let snapshot: FolderComparisonWorkflowSnapshot
    public let id: DirectoryResult.ID
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let limits: FolderComparisonWorkflowLimits

    public init(
        snapshot: FolderComparisonWorkflowSnapshot,
        id: DirectoryResult.ID,
        capabilities: FolderComparisonWorkflowCapabilities,
        limits: FolderComparisonWorkflowLimits = .default
    ) {
        self.snapshot = snapshot
        self.id = id
        self.capabilities = capabilities
        self.limits = limits
    }
}

public enum FolderComparisonWorkflowRequest: Hashable, Sendable {
    case compare(FolderComparisonCompareRequest)
    case present(FolderComparisonPresentationRequest)
    case fileOperation(FolderComparisonFileOperationRequest)
    case controlActivity(FolderComparisonActivityControlRequest)
    case openFilePair(FolderComparisonOpenFilePairRequest)
}

public enum FolderComparisonWorkflowLimit: String, CaseIterable, Hashable, Sendable {
    case resultItems
    case selectedItems
    case operationActions
    case presentationRows
    case columns
    case sortDescriptors
    case filterRules
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case metadataDigestBytes
    case workUnits
    case cancellationCheckInterval
}

public struct FolderComparisonWorkflowLimits: Hashable, Sendable {
    public static let hardMaximumResultItems = 10_000_000
    public static let hardMaximumSelectedItems = 1_000_000
    public static let hardMaximumOperationActions = 2_000_000
    public static let hardMaximumPresentationRows = 2_000_000
    public static let hardMaximumColumns = 64
    public static let hardMaximumSortDescriptors = 64
    public static let hardMaximumFilterRules = 4_096
    public static let hardMaximumStringUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 256 * 1_024 * 1_024
    public static let hardMaximumMetadataDigestBytes = 4_096
    public static let hardMaximumWorkUnits: UInt64 = 4 * 1_024 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 4_096
    public static let `default` = FolderComparisonWorkflowLimits()

    public let maximumResultItems: Int
    public let maximumSelectedItems: Int
    public let maximumOperationActions: Int
    public let maximumPresentationRows: Int
    public let maximumColumns: Int
    public let maximumSortDescriptors: Int
    public let maximumFilterRules: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumMetadataDigestBytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: Int

    public init(
        maximumResultItems: Int = 1_000_000,
        maximumSelectedItems: Int = 100_000,
        maximumOperationActions: Int = 200_000,
        maximumPresentationRows: Int = 1_000_000,
        maximumColumns: Int = FolderComparisonPresentationColumn.allCases.count,
        maximumSortDescriptors: Int = 8,
        maximumFilterRules: Int = 1_024,
        maximumStringUTF8Bytes: Int = 16 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumMetadataDigestBytes: Int = 1_024,
        maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 1_024
    ) {
        self.maximumResultItems = maximumResultItems
        self.maximumSelectedItems = maximumSelectedItems
        self.maximumOperationActions = maximumOperationActions
        self.maximumPresentationRows = maximumPresentationRows
        self.maximumColumns = maximumColumns
        self.maximumSortDescriptors = maximumSortDescriptors
        self.maximumFilterRules = maximumFilterRules
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumMetadataDigestBytes = maximumMetadataDigestBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum FolderComparisonWorkflowURLRole: Hashable, Sendable {
    case requestedRoot(FolderComparisonWorkflowSide)
    case canonicalRoot(FolderComparisonWorkflowSide)
    case securityScope(FolderComparisonWorkflowSide)
}

public enum FolderComparisonWorkflowURLIssue: String, CaseIterable, Hashable, Sendable {
    case notFileURL
    case relativeURL
    case remoteHost
    case credentialsOrPort
    case queryOrFragment
    case nullByte
    case pathTooLong
    case notCanonical
    case insufficientCoverage
}

public enum FolderComparisonWorkflowError: Error, Equatable, Hashable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(FolderComparisonWorkflowLimit, value: String)
    case workLimitExceeded(maximumUnits: UInt64)
    case invalidURL(role: FolderComparisonWorkflowURLRole, issue: FolderComparisonWorkflowURLIssue)
    case invalidRootRevision(FolderComparisonWorkflowSide)
    case duplicateRootIdentity
    case duplicateItemIdentity(DirectoryResult.ID)
    case authorityRootMismatch(FolderComparisonWorkflowSide)
    case authorityPermissionMissing(
        side: FolderComparisonWorkflowSide,
        permission: FolderComparisonAuthorityPermission
    )
    case staleCapabilityRevision
    case unsupportedCapability(FolderComparisonWorkflowFeature)
    case invalidComparisonSettings
    case invalidScanOptions
    case invalidFilenameFilter(FilenameFilterDiagnostic)
    case invalidSnapshotGeneration(expected: UInt64, actual: UInt64)
    case staleSnapshot
    case snapshotContentsChanged
    case tooManyResults(maximum: Int)
    case duplicateResultID(DirectoryResult.ID)
    case duplicateResultPath(side: FolderComparisonWorkflowSide, relativePath: String)
    case invalidResultPath(DirectoryResult.ID)
    case invalidResultRevision(DirectoryResult.ID)
    case stringTooLarge(maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case tooManyColumns(maximum: Int)
    case duplicateColumn(FolderComparisonPresentationColumn)
    case missingRequiredColumn(FolderComparisonPresentationColumn)
    case tooManySortDescriptors(maximum: Int)
    case duplicateSortKey(FolderComparisonPresentationSortKey)
    case unsupportedTreeSort
    case unsupportedTreeResult(DirectoryResult.ID)
    case tooManyPresentationRows(maximum: Int)
    case emptySelection
    case tooManySelectedItems(maximum: Int)
    case duplicateSelectedResult(DirectoryResult.ID)
    case unknownResult(DirectoryResult.ID)
    case unsupportedResultItem(DirectoryResult.ID)
    case destinationCollision(side: FolderComparisonWorkflowSide, relativePath: String)
    case missingDestinationParent(side: FolderComparisonWorkflowSide, relativePath: String)
    case replacementOwnerRequired
    case absenceNotProvable(side: FolderComparisonWorkflowSide, relativePath: String)
    case unsupportedOperationBatch
    case missingOperationSource(id: DirectoryResult.ID, side: FolderComparisonWorkflowSide)
    case tooManyOperationActions(maximum: Int)
    case filePairUnavailable(DirectoryResult.ID)
    case invalidActivityProgress
    case unsupportedActivityControl(FolderComparisonActivityControl)
    case invalidActivityTransition(
        state: FolderComparisonActivityState,
        control: FolderComparisonActivityControl
    )
    case staleActivity
    case staleReplacementOwner
    case invalidExecutionReceipt

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Folder comparison workflow planning was cancelled."
        case .invalidLimit(let limit, let value):
            "Invalid folder comparison workflow limit \(limit.rawValue): \(value)."
        case .workLimitExceeded(let maximum):
            "Folder comparison workflow exceeds the \(maximum)-unit work limit."
        case .invalidURL(let role, let issue):
            "Invalid folder comparison URL for \(String(describing: role)): \(issue.rawValue)."
        case .invalidRootRevision(let side):
            "Folder comparison \(side.rawValue) root revision is invalid."
        case .duplicateRootIdentity:
            "Folder comparison roots resolve to the same filesystem identity."
        case .duplicateItemIdentity:
            "Folder comparison results repeat a physical filesystem identity."
        case .authorityRootMismatch(let side):
            "Folder comparison \(side.rawValue) authority belongs to another root."
        case .authorityPermissionMissing(let side, let permission):
            "Folder comparison \(side.rawValue) authority lacks \(permission.rawValue) permission."
        case .staleCapabilityRevision:
            "Folder comparison executor capabilities changed after planning."
        case .unsupportedCapability(let capability):
            "Folder comparison executor does not support \(capability.rawValue)."
        case .invalidComparisonSettings:
            "Folder comparison settings are invalid."
        case .invalidScanOptions:
            "Folder comparison scan options are invalid."
        case .invalidFilenameFilter(let diagnostic):
            diagnostic.localizedDescription
        case .invalidSnapshotGeneration(let expected, let actual):
            "Folder comparison expected result generation \(expected), not \(actual)."
        case .staleSnapshot:
            "Folder comparison result identity or generation is stale."
        case .snapshotContentsChanged:
            "Folder comparison results changed without advancing generation."
        case .tooManyResults(let maximum):
            "Folder comparison exceeds the \(maximum)-result limit."
        case .duplicateResultID:
            "Folder comparison results contain a duplicate identity."
        case .duplicateResultPath(let side, let path):
            "Folder comparison contains a duplicate normalized \(side.rawValue) path: \(path)."
        case .invalidResultPath:
            "Folder comparison result contains an invalid relative path."
        case .invalidResultRevision:
            "Folder comparison result revision does not match its result or root."
        case .stringTooLarge(let maximum):
            "Folder comparison string exceeds \(maximum) UTF-8 bytes."
        case .totalStringsTooLarge(let maximum):
            "Folder comparison strings exceed \(maximum) combined UTF-8 bytes."
        case .tooManyColumns(let maximum):
            "Folder comparison presentation exceeds the \(maximum)-column limit."
        case .duplicateColumn(let column):
            "Folder comparison presentation repeats the \(column.rawValue) column."
        case .missingRequiredColumn(let column):
            "Folder comparison presentation requires the \(column.rawValue) column."
        case .tooManySortDescriptors(let maximum):
            "Folder comparison presentation exceeds the \(maximum)-sort limit."
        case .duplicateSortKey(let key):
            "Folder comparison presentation repeats the \(key.rawValue) sort key."
        case .unsupportedTreeSort:
            "Folder comparison tree presentation supports only ascending path order."
        case .unsupportedTreeResult:
            "Folder comparison tree presentation cannot safely parent a path-substitution result."
        case .tooManyPresentationRows(let maximum):
            "Folder comparison presentation exceeds the \(maximum)-row limit."
        case .emptySelection:
            "Folder comparison operation requires a selection."
        case .tooManySelectedItems(let maximum):
            "Folder comparison operation exceeds the \(maximum)-selection limit."
        case .duplicateSelectedResult:
            "Folder comparison operation repeats a selected result."
        case .unknownResult:
            "Folder comparison operation references an unknown result."
        case .unsupportedResultItem:
            "Folder comparison operation supports only regular files; directory actions require a subtree manifest."
        case .destinationCollision(let side, let path):
            "Folder comparison operation has a normalized \(side.rawValue) destination collision at \(path)."
        case .missingDestinationParent(let side, let path):
            "Folder comparison operation lacks an exact \(side.rawValue) destination-parent revision for \(path)."
        case .replacementOwnerRequired:
            "Folder comparison replacement requires an exact backup-owner CAS token."
        case .absenceNotProvable(let side, let path):
            "Folder comparison cannot prove \(side.rawValue) destination absence at \(path)."
        case .unsupportedOperationBatch:
            "Folder comparison rejects multi-action mutation batches without chained CAS revisions."
        case .missingOperationSource(_, let side):
            "Folder comparison operation has no \(side.rawValue) source item."
        case .tooManyOperationActions(let maximum):
            "Folder comparison operation exceeds the \(maximum)-action limit."
        case .filePairUnavailable:
            "Folder comparison result is not an openable regular-file pair."
        case .invalidActivityProgress:
            "Folder comparison activity progress is invalid."
        case .unsupportedActivityControl(let control):
            "Folder comparison activity does not support \(control.rawValue)."
        case .invalidActivityTransition(let state, let control):
            "Folder comparison cannot \(control.rawValue) an activity in \(state.rawValue) state."
        case .staleActivity:
            "Folder comparison activity changed after control planning."
        case .staleReplacementOwner:
            "Folder comparison replacement owner changed after planning."
        case .invalidExecutionReceipt:
            "Folder comparison executor produced a receipt that contradicts its plan."
        }
    }
}

public struct FolderComparisonPlanningReceipt: Hashable, Sendable {
    public let planSHA256: [UInt8]
    public let inputItemCount: Int
    public let outputItemCount: Int
    public let estimatedWorkUnits: UInt64

    fileprivate init(
        planSHA256: [UInt8],
        inputItemCount: Int,
        outputItemCount: Int,
        estimatedWorkUnits: UInt64
    ) {
        self.planSHA256 = planSHA256
        self.inputItemCount = inputItemCount
        self.outputItemCount = outputItemCount
        self.estimatedWorkUnits = estimatedWorkUnits
    }
}

public enum FolderComparisonPathResolutionContract: String, Hashable, Sendable {
    case descriptorRelativeNoFollowFromPinnedCanonicalRoots
}

public enum FolderComparisonScanExecutionContract: String, Hashable, Sendable {
    case boundedEnumerationWithExactRootRevisionHeldBeforeDuringAndAfterScan
}

public enum FolderComparisonComparisonExecutionContract: String, Hashable, Sendable {
    case immutableSnapshotsAndBoundedDigestProviderWithExactResultGenerationPublish
}

public enum FolderComparisonAuthorityExecutionContract: String, Hashable, Sendable {
    case balancedAuthorityAcquisitionAroundValidationAndEffects
}

public enum FolderComparisonFileOperationExecutionContract: String, Hashable, Sendable {
    case executeExactOrderedActionsWithRootAndItemCASAndDurableBackedUpMutation
}

public enum FolderComparisonProgressExecutionContract: String, Hashable, Sendable {
    case monotonicRevisionedProgressWithAcknowledgedPauseResumeAndCancel
}

public enum FolderComparisonOpenExecutionContract: String, Hashable, Sendable {
    case openRegularPairByDescriptorWithoutFollowingLinksAndHoldRevisionsThroughDispatch
}

public enum FolderComparisonPresentationExecutionContract: String, Hashable, Sendable {
    case consumeExactOrderedRowsWithoutFilesystemOrWorkflowMutation
}

public enum FolderComparisonCancellationExecutionContract: String, Hashable, Sendable {
    case cooperativeBeforeEffectsAndCompletedFailedCancelledOrUncertainAfterEffectsStart
}

/// Mandatory boundary for future app/platform executors. This file intentionally supplies none.
public struct FolderComparisonWorkflowExecutorContract: Hashable, Sendable {
    public static let required = FolderComparisonWorkflowExecutorContract()

    public let pathResolution =
        FolderComparisonPathResolutionContract.descriptorRelativeNoFollowFromPinnedCanonicalRoots
    public let scanning =
        FolderComparisonScanExecutionContract
        .boundedEnumerationWithExactRootRevisionHeldBeforeDuringAndAfterScan
    public let comparison =
        FolderComparisonComparisonExecutionContract
        .immutableSnapshotsAndBoundedDigestProviderWithExactResultGenerationPublish
    public let authority =
        FolderComparisonAuthorityExecutionContract
        .balancedAuthorityAcquisitionAroundValidationAndEffects
    public let fileOperations =
        FolderComparisonFileOperationExecutionContract
        .executeExactOrderedActionsWithRootAndItemCASAndDurableBackedUpMutation
    public let progress =
        FolderComparisonProgressExecutionContract
        .monotonicRevisionedProgressWithAcknowledgedPauseResumeAndCancel
    public let opening =
        FolderComparisonOpenExecutionContract
        .openRegularPairByDescriptorWithoutFollowingLinksAndHoldRevisionsThroughDispatch
    public let presentation =
        FolderComparisonPresentationExecutionContract
        .consumeExactOrderedRowsWithoutFilesystemOrWorkflowMutation
    public let cancellation =
        FolderComparisonCancellationExecutionContract
        .cooperativeBeforeEffectsAndCompletedFailedCancelledOrUncertainAfterEffectsStart

    public init() {}
}

public struct FolderComparisonComparePlan: Hashable, Sendable {
    public let target: FolderComparisonWorkflowSnapshotTarget
    public let replacing: FolderComparisonWorkflowSnapshotReference?
    public let roots: FolderComparisonRootPair
    public let scanIntent: FolderComparisonScanIntent
    public let comparisonSettings: FolderComparisonSettings
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let receipt: FolderComparisonPlanningReceipt
    public let limits: FolderComparisonWorkflowLimits
    public let executorContract: FolderComparisonWorkflowExecutorContract

    fileprivate init(
        request: FolderComparisonCompareRequest,
        replacing: FolderComparisonWorkflowSnapshotReference?,
        receipt: FolderComparisonPlanningReceipt
    ) {
        target = request.target
        self.replacing = replacing
        roots = request.roots
        scanIntent = request.scanIntent
        comparisonSettings = request.comparisonSettings
        capabilities = request.capabilities
        self.receipt = receipt
        limits = request.limits
        executorContract = .required
    }

    public func validateCurrentRoots(_ roots: FolderComparisonRootPair) throws {
        guard roots == self.roots else { throw FolderComparisonWorkflowError.staleSnapshot }
    }

    public func validateCurrentCapabilities(
        _ capabilities: FolderComparisonWorkflowCapabilities
    ) throws {
        guard capabilities == self.capabilities else {
            throw FolderComparisonWorkflowError.staleCapabilityRevision
        }
    }
}

public struct FolderComparisonPresentationPlan: Hashable, Sendable {
    public let snapshot: FolderComparisonWorkflowSnapshotReference
    public let configuration: FolderComparisonPresentationConfiguration
    public let rows: [FolderComparisonPresentationRow]
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let receipt: FolderComparisonPlanningReceipt
    public let limits: FolderComparisonWorkflowLimits
    public let executorContract: FolderComparisonWorkflowExecutorContract

    fileprivate init(
        snapshot: FolderComparisonWorkflowSnapshotReference,
        configuration: FolderComparisonPresentationConfiguration,
        rows: [FolderComparisonPresentationRow],
        capabilities: FolderComparisonWorkflowCapabilities,
        receipt: FolderComparisonPlanningReceipt,
        limits: FolderComparisonWorkflowLimits
    ) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.rows = rows
        self.capabilities = capabilities
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func validateCurrentSnapshot(_ current: FolderComparisonWorkflowSnapshot) throws {
        try FolderComparisonWorkflowPlanner.validate(current, against: snapshot, limits: limits)
    }

    public func validateCurrentCapabilities(
        _ capabilities: FolderComparisonWorkflowCapabilities
    ) throws {
        guard capabilities == self.capabilities else {
            throw FolderComparisonWorkflowError.staleCapabilityRevision
        }
    }
}

public enum FolderComparisonPlannedActionKind: String, CaseIterable, Hashable, Sendable {
    case copy
    case move
    case delete
}

public enum FolderComparisonParentRevision: Hashable, Sendable {
    case root(FolderComparisonRootRevision)
    case directory(FolderComparisonItemRevision)
}

/// Proves that a destination slot was absent under an exact pinned parent revision.
public struct FolderComparisonAbsenceWitness: Hashable, Sendable {
    public let parent: FolderComparisonParentRevision
    public let relativePath: String
    public let normalizedRelativePath: String

    fileprivate init(
        parent: FolderComparisonParentRevision,
        relativePath: String,
        normalizedRelativePath: String
    ) {
        self.parent = parent
        self.relativePath = relativePath
        self.normalizedRelativePath = normalizedRelativePath
    }
}

public enum FolderComparisonDestinationPrecondition: Hashable, Sendable {
    case existing(FolderComparisonItemRevision)
    case absent(FolderComparisonAbsenceWitness)
}

/// Roots need exact pre-effect CAS, but mutations are allowed to change root metadata afterward.
public struct FolderComparisonActionRootBinding: Hashable, Sendable {
    public let identity: FolderComparisonRootIdentity
    public let preEffectRevision: FolderComparisonRootRevision
    public let authorityIdentity: UUID
    public let authorityRevision: UInt64

    fileprivate init(root: FolderComparisonRoot) {
        identity = root.revision.identity
        preEffectRevision = root.revision
        authorityIdentity = root.authority.identity
        authorityRevision = root.authority.revision
    }
}

public struct FolderComparisonPlannedFileAction: Hashable, Sendable {
    public let resultID: DirectoryResult.ID
    public let kind: FolderComparisonPlannedActionKind
    public let sourceSide: FolderComparisonWorkflowSide?
    public let sourceRoot: FolderComparisonActionRootBinding?
    public let source: DirectoryEntryMetadata?
    public let sourceRevision: FolderComparisonItemRevision?
    public let destinationSide: FolderComparisonWorkflowSide
    public let destinationRoot: FolderComparisonActionRootBinding
    public let destination: DirectoryEntryMetadata?
    public let destinationPrecondition: FolderComparisonDestinationPrecondition
    public let destinationRelativePath: String
    public let collision: FolderComparisonFileCollisionSelection?
    public let replacementOwner: FolderComparisonReplacementOwner?

    fileprivate init(
        resultID: DirectoryResult.ID,
        kind: FolderComparisonPlannedActionKind,
        sourceSide: FolderComparisonWorkflowSide?,
        sourceRoot: FolderComparisonActionRootBinding?,
        source: DirectoryEntryMetadata?,
        sourceRevision: FolderComparisonItemRevision?,
        destinationSide: FolderComparisonWorkflowSide,
        destinationRoot: FolderComparisonActionRootBinding,
        destination: DirectoryEntryMetadata?,
        destinationPrecondition: FolderComparisonDestinationPrecondition,
        destinationRelativePath: String,
        collision: FolderComparisonFileCollisionSelection?,
        replacementOwner: FolderComparisonReplacementOwner?
    ) {
        self.resultID = resultID
        self.kind = kind
        self.sourceSide = sourceSide
        self.sourceRoot = sourceRoot
        self.source = source
        self.sourceRevision = sourceRevision
        self.destinationSide = destinationSide
        self.destinationRoot = destinationRoot
        self.destination = destination
        self.destinationPrecondition = destinationPrecondition
        self.destinationRelativePath = destinationRelativePath
        self.collision = collision
        self.replacementOwner = replacementOwner
    }

}

public struct FolderComparisonFileOperationPlan: Hashable, Sendable {
    public let preEffectResults: [DirectoryResult]
    public let preEffectResultRevisions: [FolderComparisonResultRevision]
    public let snapshot: FolderComparisonWorkflowSnapshotReference
    /// Stable raw-UTF-8 order, independent of selection and hash-table order.
    public let actions: [FolderComparisonPlannedFileAction]
    public let replacementOwner: FolderComparisonReplacementOwner?
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let receipt: FolderComparisonPlanningReceipt
    public let limits: FolderComparisonWorkflowLimits
    public let executorContract: FolderComparisonWorkflowExecutorContract

    fileprivate init(
        snapshot: FolderComparisonWorkflowSnapshotReference,
        preEffectResults: [DirectoryResult],
        preEffectResultRevisions: [FolderComparisonResultRevision],
        actions: [FolderComparisonPlannedFileAction],
        replacementOwner: FolderComparisonReplacementOwner?,
        capabilities: FolderComparisonWorkflowCapabilities,
        receipt: FolderComparisonPlanningReceipt,
        limits: FolderComparisonWorkflowLimits
    ) {
        self.snapshot = snapshot
        self.preEffectResults = preEffectResults
        self.preEffectResultRevisions = preEffectResultRevisions
        self.actions = actions
        self.replacementOwner = replacementOwner
        self.capabilities = capabilities
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func validateCurrentSnapshot(_ current: FolderComparisonWorkflowSnapshot) throws {
        try FolderComparisonWorkflowPlanner.validate(current, against: snapshot, limits: limits)
    }

    public func validateCurrentCapabilities(
        _ capabilities: FolderComparisonWorkflowCapabilities
    ) throws {
        guard capabilities == self.capabilities else {
            throw FolderComparisonWorkflowError.staleCapabilityRevision
        }
    }

    public func validateCurrentReplacementOwner(
        _ owner: FolderComparisonReplacementOwner?
    ) throws {
        guard owner == replacementOwner else {
            throw FolderComparisonWorkflowError.staleReplacementOwner
        }
    }
}

public struct FolderComparisonActivityControlPlan: Hashable, Sendable {
    public let expectedActivity: FolderComparisonActivitySnapshot
    public let control: FolderComparisonActivityControl
    public let expectedSuccessorRevision: UInt64
    public let expectedSuccessorState: FolderComparisonActivityState
    public let expectedSuccessorSupportedControls: Set<FolderComparisonActivityControl>
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let receipt: FolderComparisonPlanningReceipt
    public let limits: FolderComparisonWorkflowLimits
    public let executorContract: FolderComparisonWorkflowExecutorContract

    fileprivate init(
        expectedActivity: FolderComparisonActivitySnapshot,
        control: FolderComparisonActivityControl,
        expectedSuccessorRevision: UInt64,
        expectedSuccessorState: FolderComparisonActivityState,
        expectedSuccessorSupportedControls: Set<FolderComparisonActivityControl>,
        capabilities: FolderComparisonWorkflowCapabilities,
        receipt: FolderComparisonPlanningReceipt,
        limits: FolderComparisonWorkflowLimits
    ) {
        self.expectedActivity = expectedActivity
        self.control = control
        self.expectedSuccessorRevision = expectedSuccessorRevision
        self.expectedSuccessorState = expectedSuccessorState
        self.expectedSuccessorSupportedControls = expectedSuccessorSupportedControls
        self.capabilities = capabilities
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func validateCurrentActivity(_ activity: FolderComparisonActivitySnapshot) throws {
        guard activity == expectedActivity else { throw FolderComparisonWorkflowError.staleActivity }
    }

    public func validateCurrentCapabilities(
        _ capabilities: FolderComparisonWorkflowCapabilities
    ) throws {
        guard capabilities == self.capabilities else {
            throw FolderComparisonWorkflowError.staleCapabilityRevision
        }
    }
}

public struct FolderComparisonOpenFilePairPlan: Hashable, Sendable {
    public let snapshot: FolderComparisonWorkflowSnapshotReference
    public let resultID: DirectoryResult.ID
    public let leftRelativePath: String
    public let rightRelativePath: String
    public let leftRevision: FolderComparisonItemRevision
    public let rightRevision: FolderComparisonItemRevision
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let receipt: FolderComparisonPlanningReceipt
    public let limits: FolderComparisonWorkflowLimits
    public let executorContract: FolderComparisonWorkflowExecutorContract

    fileprivate init(
        snapshot: FolderComparisonWorkflowSnapshotReference,
        resultID: DirectoryResult.ID,
        leftRelativePath: String,
        rightRelativePath: String,
        leftRevision: FolderComparisonItemRevision,
        rightRevision: FolderComparisonItemRevision,
        capabilities: FolderComparisonWorkflowCapabilities,
        receipt: FolderComparisonPlanningReceipt,
        limits: FolderComparisonWorkflowLimits
    ) {
        self.snapshot = snapshot
        self.resultID = resultID
        self.leftRelativePath = leftRelativePath
        self.rightRelativePath = rightRelativePath
        self.leftRevision = leftRevision
        self.rightRevision = rightRevision
        self.capabilities = capabilities
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func validateCurrentSnapshot(_ current: FolderComparisonWorkflowSnapshot) throws {
        try FolderComparisonWorkflowPlanner.validate(current, against: snapshot, limits: limits)
    }

    public func validateCurrentCapabilities(
        _ capabilities: FolderComparisonWorkflowCapabilities
    ) throws {
        guard capabilities == self.capabilities else {
            throw FolderComparisonWorkflowError.staleCapabilityRevision
        }
    }
}

public enum FolderComparisonWorkflowPlan: Hashable, Sendable {
    case compare(FolderComparisonComparePlan)
    case presentation(FolderComparisonPresentationPlan)
    case fileOperation(FolderComparisonFileOperationPlan)
    case activityControl(FolderComparisonActivityControlPlan)
    case openFilePair(FolderComparisonOpenFilePairPlan)

    public var receipt: FolderComparisonPlanningReceipt {
        switch self {
        case .compare(let plan): plan.receipt
        case .presentation(let plan): plan.receipt
        case .fileOperation(let plan): plan.receipt
        case .activityControl(let plan): plan.receipt
        case .openFilePair(let plan): plan.receipt
        }
    }
}

public enum FolderComparisonExecutionFailureCode: String, CaseIterable, Hashable, Sendable {
    case staleRoot
    case staleResult
    case staleAuthority
    case staleReplacementOwner
    case staleCapabilities
    case staleActivity
    case contractUnsupported
    case inputRejected
    case limitExceeded
    case cancelledBeforeEffects
    case changedDuringOperation
    case scanFailed
    case comparisonFailed
    case fileOperationFailed
    case openFailed
    case outcomeUncertain
}

public enum FolderComparisonFileActionDisposition: String, CaseIterable, Hashable, Sendable {
    case completed
    case skipped
}

public struct FolderComparisonFileActionReceipt: Hashable, Sendable {
    public let actionIndex: Int
    public let actionSHA256: [UInt8]
    public let disposition: FolderComparisonFileActionDisposition
    /// Exact post-effect destination state; nil only after delete or skipped absent create.
    public let destinationPostRevision: FolderComparisonItemRevision?
    /// Exact post-effect source state for copy. Nil after move/delete or when source was absent.
    public let sourcePostRevision: FolderComparisonItemRevision?
    public let sourceRootPostRevision: FolderComparisonRootRevision?
    public let destinationRootPostRevision: FolderComparisonRootRevision
    public let replacementOwnerRevision: UInt64?

    public init(
        actionIndex: Int,
        actionSHA256: [UInt8],
        disposition: FolderComparisonFileActionDisposition,
        destinationPostRevision: FolderComparisonItemRevision?,
        sourcePostRevision: FolderComparisonItemRevision?,
        sourceRootPostRevision: FolderComparisonRootRevision?,
        destinationRootPostRevision: FolderComparisonRootRevision,
        replacementOwnerRevision: UInt64? = nil
    ) {
        self.actionIndex = actionIndex
        self.actionSHA256 = actionSHA256
        self.disposition = disposition
        self.destinationPostRevision = destinationPostRevision
        self.sourcePostRevision = sourcePostRevision
        self.sourceRootPostRevision = sourceRootPostRevision
        self.destinationRootPostRevision = destinationRootPostRevision
        self.replacementOwnerRevision = replacementOwnerRevision
    }
}

public struct FolderComparisonExecutionFailure: Hashable, Sendable {
    public let planSHA256: [UInt8]
    public let code: FolderComparisonExecutionFailureCode
    public let completedActionCount: Int
    public let actionReceipts: [FolderComparisonFileActionReceipt]
    public let postEffectSnapshot: FolderComparisonWorkflowSnapshotReference?

    fileprivate init(
        planSHA256: [UInt8],
        code: FolderComparisonExecutionFailureCode,
        completedActionCount: Int = 0,
        actionReceipts: [FolderComparisonFileActionReceipt] = [],
        postEffectSnapshot: FolderComparisonWorkflowSnapshotReference? = nil
    ) {
        self.planSHA256 = planSHA256
        self.code = code
        self.completedActionCount = completedActionCount
        self.actionReceipts = actionReceipts
        self.postEffectSnapshot = postEffectSnapshot
    }
}

public struct FolderComparisonExecutionReceipt: Hashable, Sendable {
    public let planSHA256: [UInt8]
    public let preEffectSnapshot: FolderComparisonWorkflowSnapshotReference?
    public let postEffectSnapshot: FolderComparisonWorkflowSnapshotReference?
    public let completedActionCount: Int
    public let actionReceipts: [FolderComparisonFileActionReceipt]
    public let activity: FolderComparisonActivitySnapshot?
    public let openedResultID: DirectoryResult.ID?

    fileprivate init(
        planSHA256: [UInt8],
        preEffectSnapshot: FolderComparisonWorkflowSnapshotReference? = nil,
        postEffectSnapshot: FolderComparisonWorkflowSnapshotReference? = nil,
        completedActionCount: Int = 0,
        actionReceipts: [FolderComparisonFileActionReceipt] = [],
        activity: FolderComparisonActivitySnapshot? = nil,
        openedResultID: DirectoryResult.ID? = nil
    ) {
        self.planSHA256 = planSHA256
        self.preEffectSnapshot = preEffectSnapshot
        self.postEffectSnapshot = postEffectSnapshot
        self.completedActionCount = completedActionCount
        self.actionReceipts = actionReceipts
        self.activity = activity
        self.openedResultID = openedResultID
    }
}

public enum FolderComparisonExecutionOutcome: Hashable, Sendable {
    case completed(FolderComparisonExecutionReceipt)
    case failed(FolderComparisonExecutionFailure)
    case cancelled(FolderComparisonExecutionReceipt)
    case uncertain(FolderComparisonExecutionFailure)
}

/// Creates noncontradictory deterministic receipts. No wall-clock or random value enters a receipt.
public enum FolderComparisonExecutionReceiptFactory: Sendable {
    public static func completedComparison(
        plan: FolderComparisonComparePlan,
        snapshot: FolderComparisonWorkflowSnapshot
    ) throws -> FolderComparisonExecutionOutcome {
        guard snapshot.identity == plan.target.identity,
            snapshot.generation == plan.target.generation,
            snapshot.owner.identity == plan.target.owner.identity,
            snapshot.owner.revision == plan.target.owner.revision,
            snapshot.roots == plan.roots,
            snapshot.scanIntent == plan.scanIntent,
            snapshot.comparisonSettings == plan.comparisonSettings,
            snapshot.isComplete,
            !snapshot.results.contains(where: { $0.status == .pending })
        else {
            throw FolderComparisonWorkflowError.invalidExecutionReceipt
        }
        let reference = try FolderComparisonWorkflowPlanner.reference(
            to: snapshot,
            limits: plan.limits
        )
        return .completed(
            FolderComparisonExecutionReceipt(
                planSHA256: plan.receipt.planSHA256,
                preEffectSnapshot: plan.replacing,
                postEffectSnapshot: reference
            )
        )
    }

    public static func completedFileOperation(
        plan: FolderComparisonFileOperationPlan,
        actionReceipts: [FolderComparisonFileActionReceipt],
        postEffectSnapshot: FolderComparisonWorkflowSnapshot
    ) throws -> FolderComparisonExecutionOutcome {
        guard actionReceipts.count == plan.actions.count else {
            throw FolderComparisonWorkflowError.invalidExecutionReceipt
        }
        for index in plan.actions.indices {
            let actionReceipt = actionReceipts[index]
            var actionDigest = FolderComparisonCanonicalDigest()
            append(plan.actions[index], to: &actionDigest)
            guard actionReceipt.actionIndex == index,
                actionReceipt.actionSHA256 == actionDigest.finalize(),
                valid(actionReceipt, for: plan.actions[index], replacementOwner: plan.replacementOwner)
            else {
                throw FolderComparisonWorkflowError.invalidExecutionReceipt
            }
        }
        guard postEffectSnapshot.owner.identity == plan.snapshot.owner.identity,
            plan.snapshot.owner.revision < UInt64.max,
            postEffectSnapshot.owner.revision == plan.snapshot.owner.revision + 1,
            postEffectSnapshot.identity == plan.snapshot.identity,
            plan.snapshot.generation < UInt64.max,
            postEffectSnapshot.generation == plan.snapshot.generation + 1,
            postEffectSnapshot.scanIntent == plan.snapshot.scanIntent,
            postEffectSnapshot.comparisonSettings == plan.snapshot.comparisonSettings,
            validPostEffectRoots(postEffectSnapshot.roots, for: plan, receipts: actionReceipts),
            validPostEffectResults(postEffectSnapshot, for: plan, receipts: actionReceipts)
        else {
            throw FolderComparisonWorkflowError.invalidExecutionReceipt
        }
        let postEffectReference = try FolderComparisonWorkflowPlanner.reference(
            to: postEffectSnapshot,
            limits: plan.limits
        )
        return .completed(
            FolderComparisonExecutionReceipt(
                planSHA256: plan.receipt.planSHA256,
                preEffectSnapshot: plan.snapshot,
                postEffectSnapshot: postEffectReference,
                completedActionCount: actionReceipts.count,
                actionReceipts: actionReceipts
            )
        )
    }

    public static func completedActivityControl(
        plan: FolderComparisonActivityControlPlan,
        activity: FolderComparisonActivitySnapshot
    ) throws -> FolderComparisonExecutionOutcome {
        guard activity.identity == plan.expectedActivity.identity,
            activity.revision == plan.expectedSuccessorRevision,
            activity.state == plan.expectedSuccessorState,
            activity.supportedControls == plan.expectedSuccessorSupportedControls,
            validActivitySnapshot(activity, limits: plan.limits),
            validActivitySuccessor(activity, after: plan.expectedActivity, control: plan.control)
        else {
            throw FolderComparisonWorkflowError.invalidExecutionReceipt
        }
        return .completed(
            FolderComparisonExecutionReceipt(
                planSHA256: plan.receipt.planSHA256,
                activity: activity
            )
        )
    }

    public static func completedOpen(
        plan: FolderComparisonOpenFilePairPlan
    ) -> FolderComparisonExecutionOutcome {
        .completed(
            FolderComparisonExecutionReceipt(
                planSHA256: plan.receipt.planSHA256,
                preEffectSnapshot: plan.snapshot,
                openedResultID: plan.resultID
            )
        )
    }

    public static func failed(
        plan: FolderComparisonWorkflowPlan,
        code: FolderComparisonExecutionFailureCode
    ) throws -> FolderComparisonExecutionOutcome {
        let completedActionCount = 0
        guard validCompletedActionCount(completedActionCount, for: plan),
            validFailureCode(code, for: plan, completedActionCount: completedActionCount)
        else {
            throw FolderComparisonWorkflowError.invalidExecutionReceipt
        }
        return .failed(
            FolderComparisonExecutionFailure(
                planSHA256: plan.receipt.planSHA256,
                code: code,
                completedActionCount: completedActionCount
            )
        )
    }

    public static func cancelled(
        plan: FolderComparisonWorkflowPlan
    ) throws -> FolderComparisonExecutionOutcome {
        let completedActionCount = 0
        guard validCompletedActionCount(completedActionCount, for: plan),
            completedActionCount < actionCount(for: plan)
        else {
            throw FolderComparisonWorkflowError.invalidExecutionReceipt
        }
        return .cancelled(
            FolderComparisonExecutionReceipt(
                planSHA256: plan.receipt.planSHA256,
                preEffectSnapshot: snapshotReference(for: plan),
                completedActionCount: completedActionCount
            )
        )
    }

    public static func uncertain(
        plan: FolderComparisonWorkflowPlan
    ) throws -> FolderComparisonExecutionOutcome {
        let completedActionCount = 0
        guard validCompletedActionCount(completedActionCount, for: plan),
            completedActionCount < actionCount(for: plan)
        else {
            throw FolderComparisonWorkflowError.invalidExecutionReceipt
        }
        guard case .fileOperation = plan else {
            throw FolderComparisonWorkflowError.invalidExecutionReceipt
        }
        return .uncertain(
            FolderComparisonExecutionFailure(
                planSHA256: plan.receipt.planSHA256,
                code: .outcomeUncertain,
                completedActionCount: completedActionCount
            )
        )
    }

    private static func validCompletedActionCount(
        _ completedActionCount: Int,
        for plan: FolderComparisonWorkflowPlan
    ) -> Bool {
        (0...actionCount(for: plan)).contains(completedActionCount)
    }

    private static func actionCount(for plan: FolderComparisonWorkflowPlan) -> Int {
        switch plan {
        case .fileOperation(let plan): plan.actions.count
        case .compare, .presentation, .activityControl, .openFilePair: 1
        }
    }

    private static func snapshotReference(
        for plan: FolderComparisonWorkflowPlan
    ) -> FolderComparisonWorkflowSnapshotReference? {
        switch plan {
        case .compare(let plan): plan.replacing
        case .presentation(let plan): plan.snapshot
        case .fileOperation(let plan): plan.snapshot
        case .activityControl: nil
        case .openFilePair(let plan): plan.snapshot
        }
    }

    private static func valid(
        _ receipt: FolderComparisonFileActionReceipt,
        for action: FolderComparisonPlannedFileAction,
        replacementOwner: FolderComparisonReplacementOwner?
    ) -> Bool {
        if receipt.disposition == .skipped {
            return action.destination != nil
                && action.collision == .skip
                && receipt.destinationPostRevision == action.destinationPrecondition.existingRevision
                && receipt.sourcePostRevision == action.sourceRevision
                && receipt.sourceRootPostRevision == action.sourceRoot?.preEffectRevision
                && receipt.destinationRootPostRevision == action.destinationRoot.preEffectRevision
                && receipt.replacementOwnerRevision == nil
        }
        guard validItemPostRevision(receipt.destinationPostRevision),
            receipt.destinationRootPostRevision.identity == action.destinationRoot.identity,
            receipt.sourceRootPostRevision?.identity == action.sourceRoot?.identity
        else { return false }
        let destinationMatches =
            receipt.destinationPostRevision.map {
                $0.identity.rootIdentity == action.destinationRoot.identity
                    && $0.identity.relativePath == action.destinationRelativePath
                    && $0.kind == action.sourceRevision?.kind
                    && $0.byteCount == action.sourceRevision?.byteCount
            } ?? false
        switch action.kind {
        case .copy:
            guard action.destination == nil || action.collision != .fail,
                destinationMatches,
                receipt.sourcePostRevision == action.sourceRevision,
                receipt.sourceRootPostRevision == action.sourceRoot?.preEffectRevision
            else { return false }
        case .move:
            guard action.destination == nil || action.collision != .fail,
                destinationMatches,
                receipt.sourcePostRevision == nil
            else { return false }
        case .delete:
            guard receipt.destinationPostRevision == nil,
                receipt.sourcePostRevision == nil,
                receipt.sourceRootPostRevision == nil
            else { return false }
        }
        if action.kind == .copy || action.kind == .move {
            guard let sourceRevision = action.sourceRevision,
                sourceRevision.contentSHA256 != nil,
                receipt.destinationPostRevision?.contentSHA256 == sourceRevision.contentSHA256
            else { return false }
        }
        if action.replacementOwner != nil {
            guard let replacementOwner,
                replacementOwner.revision < UInt64.max,
                receipt.replacementOwnerRevision == replacementOwner.revision + 1
            else { return false }
        } else if receipt.replacementOwnerRevision != nil {
            return false
        }
        return true
    }

    private static func validItemPostRevision(_ revision: FolderComparisonItemRevision?) -> Bool {
        guard let revision else { return true }
        return revision.linkCount > 0
            && (0...999_999_999).contains(revision.modificationTimeNanoseconds)
            && (0...999_999_999).contains(revision.statusChangeTimeNanoseconds)
            && revision.metadataSHA256.count == 32
            && (revision.contentSHA256 == nil || revision.contentSHA256?.count == 32)
    }

    private static func validRootPostRevision(_ revision: FolderComparisonRootRevision) -> Bool {
        revision.linkCount > 0
            && (0...999_999_999).contains(revision.modificationTimeNanoseconds)
            && (0...999_999_999).contains(revision.statusChangeTimeNanoseconds)
            && revision.metadataSHA256.count == 32
    }

    private static func validPostEffectRoots(
        _ roots: FolderComparisonRootPair,
        for plan: FolderComparisonFileOperationPlan,
        receipts: [FolderComparisonFileActionReceipt]
    ) -> Bool {
        let mutatedSides = Set(plan.actions.map(\.destinationSide)).union(
            plan.actions.compactMap { $0.kind == .move ? $0.sourceSide : nil }
        )
        for side in FolderComparisonWorkflowSide.allCases {
            let preEffectRoot = plan.snapshot.roots[side]
            let postEffectRoot = roots[side]
            guard postEffectRoot.requestedURL == preEffectRoot.requestedURL,
                postEffectRoot.authority == preEffectRoot.authority,
                postEffectRoot.revision.identity == preEffectRoot.revision.identity,
                postEffectRoot.pathCaseSensitivity == preEffectRoot.pathCaseSensitivity
            else { return false }
            let expectedRevision =
                side == plan.actions[0].destinationSide
                ? receipts[0].destinationRootPostRevision
                : receipts[0].sourceRootPostRevision ?? preEffectRoot.revision
            guard validRootPostRevision(expectedRevision),
                postEffectRoot.revision == expectedRevision
            else { return false }
            if !mutatedSides.contains(side), expectedRevision != preEffectRoot.revision { return false }
        }
        return true
    }

    private static func validPostEffectResults(
        _ snapshot: FolderComparisonWorkflowSnapshot,
        for plan: FolderComparisonFileOperationPlan,
        receipts: [FolderComparisonFileActionReceipt]
    ) -> Bool {
        guard plan.actions.count == 1, receipts.count == 1 else { return false }
        let action = plan.actions[0]
        let receipt = receipts[0]
        guard plan.preEffectResults.count == plan.preEffectResultRevisions.count,
            snapshot.results.count == snapshot.resultRevisions.count
        else { return false }
        var postEffectIndicesByID: [DirectoryResult.ID: Int] = [:]
        postEffectIndicesByID.reserveCapacity(snapshot.results.count)
        for index in snapshot.results.indices {
            guard postEffectIndicesByID.updateValue(index, forKey: snapshot.results[index].id) == nil else {
                return false
            }
        }
        for index in plan.preEffectResults.indices {
            let result = plan.preEffectResults[index]
            guard
                result.id == action.resultID
                    || postEffectIndicesByID[result.id].map({ postEffectIndex in
                        snapshot.results[postEffectIndex] == result
                            && snapshot.resultRevisions[postEffectIndex]
                                == plan.preEffectResultRevisions[index]
                    }) == true
            else { return false }
        }
        var expectedByPhysicalIdentity: [FolderComparisonPhysicalIdentity: FolderComparisonItemRevision] = [:]
        for revision in plan.preEffectResultRevisions {
            for side in FolderComparisonWorkflowSide.allCases {
                if let item = revision[side] {
                    expectedByPhysicalIdentity[FolderComparisonPhysicalIdentity(item.identity)] = item
                }
            }
        }
        if let sourceRevision = action.sourceRevision {
            expectedByPhysicalIdentity.removeValue(
                forKey: FolderComparisonPhysicalIdentity(sourceRevision.identity)
            )
            if let sourcePostRevision = receipt.sourcePostRevision {
                expectedByPhysicalIdentity[FolderComparisonPhysicalIdentity(sourcePostRevision.identity)] =
                    sourcePostRevision
            }
        }
        if case .existing(let destinationRevision) = action.destinationPrecondition {
            expectedByPhysicalIdentity.removeValue(
                forKey: FolderComparisonPhysicalIdentity(destinationRevision.identity)
            )
        }
        if let destinationPostRevision = receipt.destinationPostRevision {
            expectedByPhysicalIdentity[FolderComparisonPhysicalIdentity(destinationPostRevision.identity)] =
                destinationPostRevision
        }
        var actualByPhysicalIdentity: [FolderComparisonPhysicalIdentity: FolderComparisonItemRevision] = [:]
        for revision in snapshot.resultRevisions {
            for side in FolderComparisonWorkflowSide.allCases {
                if let item = revision[side] {
                    actualByPhysicalIdentity[FolderComparisonPhysicalIdentity(item.identity)] = item
                }
            }
        }
        guard actualByPhysicalIdentity == expectedByPhysicalIdentity else { return false }
        if receipt.disposition == .skipped {
            return snapshot.resultRevisions.contains { revision in
                let sourceMatches =
                    action.sourceSide.map { side in
                        revision[side] == action.sourceRevision
                    } ?? true
                return revision[action.destinationSide] == action.destinationPrecondition.existingRevision
                    && sourceMatches
            }
        }
        if action.kind == .delete {
            guard case .existing(let deletedRevision) = action.destinationPrecondition else { return false }
            return !snapshot.resultRevisions.contains {
                $0[action.destinationSide]?.identity.deviceID == deletedRevision.identity.deviceID
                    && $0[action.destinationSide]?.identity.fileID == deletedRevision.identity.fileID
                    && $0[action.destinationSide]?.identity.generation == deletedRevision.identity.generation
            }
        }
        guard
            snapshot.resultRevisions.contains(where: {
                $0[action.destinationSide] == receipt.destinationPostRevision
            })
        else { return false }
        guard let sourceSide = action.sourceSide else { return true }
        if let sourcePostRevision = receipt.sourcePostRevision {
            return snapshot.resultRevisions.contains { $0[sourceSide] == sourcePostRevision }
        }
        guard let sourceRevision = action.sourceRevision else { return false }
        return !snapshot.resultRevisions.contains {
            $0[sourceSide]?.identity.deviceID == sourceRevision.identity.deviceID
                && $0[sourceSide]?.identity.fileID == sourceRevision.identity.fileID
                && $0[sourceSide]?.identity.generation == sourceRevision.identity.generation
        }
    }

    private static func validActivitySuccessor(
        _ successor: FolderComparisonActivitySnapshot,
        after predecessor: FolderComparisonActivitySnapshot,
        control: FolderComparisonActivityControl
    ) -> Bool {
        guard successor.kind == predecessor.kind,
            successor.progress.completedUnits >= predecessor.progress.completedUnits,
            successor.progress.completedItems >= predecessor.progress.completedItems,
            successor.progress.totalUnits == predecessor.progress.totalUnits,
            successor.progress.totalItems == predecessor.progress.totalItems
        else { return false }
        switch control {
        case .pause:
            return successor.supportedControls.contains(.resume)
                && !successor.supportedControls.contains(.pause)
        case .resume:
            return successor.supportedControls.contains(.pause)
                && !successor.supportedControls.contains(.resume)
        case .cancel:
            return successor.supportedControls.isEmpty
        }
    }

    private static func validActivitySnapshot(
        _ activity: FolderComparisonActivitySnapshot,
        limits: FolderComparisonWorkflowLimits
    ) -> Bool {
        var work = FolderComparisonWorkflowWork(limits: limits)
        return
            (try? FolderComparisonWorkflowPlanner.validateActivity(
                activity,
                limits: limits,
                work: &work
            )) != nil
    }

    private static func validFailureCode(
        _ code: FolderComparisonExecutionFailureCode,
        for plan: FolderComparisonWorkflowPlan,
        completedActionCount: Int
    ) -> Bool {
        if completedActionCount > 0 {
            return code == .changedDuringOperation
                || code == .fileOperationFailed
        }
        switch plan {
        case .compare:
            return [
                .staleRoot, .staleResult, .staleAuthority, .staleCapabilities, .contractUnsupported,
                .inputRejected, .limitExceeded, .scanFailed,
                .comparisonFailed
            ].contains(code)
        case .presentation:
            return [
                .staleResult, .staleCapabilities, .contractUnsupported, .inputRejected,
                .limitExceeded
            ].contains(code)
        case .fileOperation:
            let allowed: [FolderComparisonExecutionFailureCode] = [
                .staleRoot, .staleResult, .staleAuthority, .staleCapabilities,
                .contractUnsupported, .inputRejected, .limitExceeded,
                .changedDuringOperation,
                .fileOperationFailed
            ]
            if case .fileOperation(let operation) = plan,
                operation.replacementOwner != nil,
                code == .staleReplacementOwner
            {
                return true
            }
            return allowed.contains(code)
        case .activityControl:
            return [
                .staleCapabilities, .staleActivity, .contractUnsupported, .inputRejected
            ].contains(code)
        case .openFilePair:
            return [
                .staleRoot, .staleResult, .staleAuthority, .staleCapabilities,
                .contractUnsupported, .inputRejected, .limitExceeded,
                .openFailed
            ].contains(code)
        }
    }
}

extension FolderComparisonDestinationPrecondition {
    fileprivate var existingRevision: FolderComparisonItemRevision? {
        if case .existing(let revision) = self { return revision }
        return nil
    }
}

/// Side-effect implementation supplied by an app/platform layer. Implementations enforce
/// `FolderComparisonWorkflowExecutorContract.required`; this module provides no executor.
public protocol FolderComparisonComparePlanExecutor: Sendable {
    func execute(
        _ plan: FolderComparisonComparePlan,
        validatingCurrentRoots roots: FolderComparisonRootPair,
        capabilities: FolderComparisonWorkflowCapabilities
    ) async -> FolderComparisonExecutionOutcome
}

public protocol FolderComparisonFileOperationPlanExecutor: Sendable {
    func execute(
        _ plan: FolderComparisonFileOperationPlan,
        validatingCurrentSnapshot snapshot: FolderComparisonWorkflowSnapshot,
        capabilities: FolderComparisonWorkflowCapabilities
    ) async -> FolderComparisonExecutionOutcome
}

public protocol FolderComparisonActivityControlPlanExecutor: Sendable {
    func execute(
        _ plan: FolderComparisonActivityControlPlan,
        validatingCurrentActivity activity: FolderComparisonActivitySnapshot,
        capabilities: FolderComparisonWorkflowCapabilities
    ) async -> FolderComparisonExecutionOutcome
}

public protocol FolderComparisonOpenFilePairPlanExecutor: Sendable {
    func execute(
        _ plan: FolderComparisonOpenFilePairPlan,
        validatingCurrentSnapshot snapshot: FolderComparisonWorkflowSnapshot,
        capabilities: FolderComparisonWorkflowCapabilities
    ) async -> FolderComparisonExecutionOutcome
}

/// UI-independent bounded policy and planner. It performs no filesystem, security-scope, scanner,
/// comparator, file-operation, process-launch, or UI work.
public enum FolderComparisonWorkflowPlanner: Sendable {
    public static func plan(_ request: FolderComparisonWorkflowRequest) throws -> FolderComparisonWorkflowPlan {
        do {
            return switch request {
            case .compare(let request): .compare(try planComparison(request))
            case .present(let request): .presentation(try planPresentation(request))
            case .fileOperation(let request): .fileOperation(try planFileOperation(request))
            case .controlActivity(let request): .activityControl(try planActivityControl(request))
            case .openFilePair(let request): .openFilePair(try planOpenFilePair(request))
            }
        } catch is CancellationError {
            throw FolderComparisonWorkflowError.cancelled
        }
    }

    public static func planComparison(
        _ request: FolderComparisonCompareRequest
    ) throws -> FolderComparisonComparePlan {
        do {
            try validate(request.limits)
            var work = FolderComparisonWorkflowWork(limits: request.limits)
            try validateRoots(request.roots, recursive: request.scanIntent.recursive, work: &work)
            try validateScanIntent(request.scanIntent, limits: request.limits, work: &work)
            try validateComparisonSettings(request.comparisonSettings)
            try require(
                request.scanIntent.recursive ? .recursiveScan : .nonrecursiveScan,
                in: request.capabilities
            )
            try require(.metadataComparison, in: request.capabilities)
            if request.comparisonSettings.method != .metadataOnly {
                try require(.contentComparison, in: request.capabilities)
                try requireAuthority(.readContent, side: .left, roots: request.roots)
                try requireAuthority(.readContent, side: .right, roots: request.roots)
                try requireTreeAuthority(side: .left, roots: request.roots)
                try requireTreeAuthority(side: .right, roots: request.roots)
            }

            let replacingReference: FolderComparisonWorkflowSnapshotReference?
            if let replacing = request.replacing {
                let expectedGeneration = replacing.generation.addingReportingOverflow(1)
                let expectedOwnerRevision = replacing.owner.revision.addingReportingOverflow(1)
                guard !expectedGeneration.overflow,
                    !expectedOwnerRevision.overflow,
                    request.target.identity == replacing.identity,
                    request.target.generation == expectedGeneration.partialValue,
                    request.target.owner.identity == replacing.owner.identity,
                    request.target.owner.revision == expectedOwnerRevision.partialValue
                else {
                    throw FolderComparisonWorkflowError.invalidSnapshotGeneration(
                        expected: expectedGeneration.partialValue,
                        actual: request.target.generation
                    )
                }
                replacingReference = try makeReference(replacing, limits: request.limits, work: &work)
            } else {
                guard request.target.generation == 0, request.target.owner.revision == 0 else {
                    throw FolderComparisonWorkflowError.invalidSnapshotGeneration(
                        expected: 0,
                        actual: request.target.generation
                    )
                }
                replacingReference = nil
            }

            var digest = FolderComparisonCanonicalDigest()
            digest.append("compare")
            digest.append(request.target.identity.rawValue)
            digest.append(request.target.generation)
            append(request.target.owner, to: &digest)
            append(request.roots, to: &digest)
            append(request.scanIntent, to: &digest)
            append(request.comparisonSettings, to: &digest)
            append(request.capabilities, to: &digest)
            append(request.limits, to: &digest)
            if let replacingReference {
                digest.append(true)
                append(replacingReference, to: &digest)
            } else {
                digest.append(false)
            }
            try work.checkCancellation()
            let receipt = FolderComparisonPlanningReceipt(
                planSHA256: digest.finalize(),
                inputItemCount: request.replacing?.results.count ?? 0,
                outputItemCount: 2,
                estimatedWorkUnits: work.consumed
            )
            return FolderComparisonComparePlan(
                request: request,
                replacing: replacingReference,
                receipt: receipt
            )
        } catch is CancellationError {
            throw FolderComparisonWorkflowError.cancelled
        }
    }

    public static func planPresentation(
        _ request: FolderComparisonPresentationRequest
    ) throws -> FolderComparisonPresentationPlan {
        do {
            try validate(request.limits)
            var work = FolderComparisonWorkflowWork(limits: request.limits)
            let snapshot = try makeReference(request.snapshot, limits: request.limits, work: &work)
            try require(
                request.configuration.mode == .table ? .tablePresentation : .treePresentation,
                in: request.capabilities
            )
            try validatePresentation(request.configuration, limits: request.limits, work: &work)

            var admitted: [(offset: Int, result: DirectoryResult)] = []
            admitted.reserveCapacity(min(request.snapshot.results.count, request.limits.maximumPresentationRows))
            for (offset, result) in request.snapshot.results.enumerated() {
                try work.consume(1)
                if try matches(
                    result,
                    filter: request.configuration.filter,
                    limits: request.limits,
                    work: &work
                ) {
                    guard admitted.count < request.limits.maximumPresentationRows else {
                        throw FolderComparisonWorkflowError.tooManyPresentationRows(
                            maximum: request.limits.maximumPresentationRows
                        )
                    }
                    admitted.append((offset, result))
                }
            }
            let sorted = try stableSort(
                admitted,
                descriptors: request.configuration.sortDescriptors,
                work: &work
            )
            let rows = try makeRows(
                sorted,
                mode: request.configuration.mode,
                roots: request.snapshot.roots,
                limits: request.limits,
                work: &work
            )

            var digest = FolderComparisonCanonicalDigest()
            digest.append("presentation")
            append(snapshot, to: &digest)
            append(request.configuration, to: &digest)
            append(request.capabilities, to: &digest)
            append(request.limits, to: &digest)
            for row in rows {
                try work.consume(row.relativePath.utf8.count)
                if let parent = row.treeParentRelativePath {
                    try work.consume(parent.utf8.count)
                }
                if let left = row.left { try work.consume(left.relativePath.utf8.count) }
                if let right = row.right { try work.consume(right.relativePath.utf8.count) }
                append(row, to: &digest)
            }
            let receipt = FolderComparisonPlanningReceipt(
                planSHA256: digest.finalize(),
                inputItemCount: request.snapshot.results.count,
                outputItemCount: rows.count,
                estimatedWorkUnits: work.consumed
            )
            return FolderComparisonPresentationPlan(
                snapshot: snapshot,
                configuration: request.configuration,
                rows: rows,
                capabilities: request.capabilities,
                receipt: receipt,
                limits: request.limits
            )
        } catch is CancellationError {
            throw FolderComparisonWorkflowError.cancelled
        }
    }

    public static func planFileOperation(
        _ request: FolderComparisonFileOperationRequest
    ) throws -> FolderComparisonFileOperationPlan {
        do {
            try validate(request.limits)
            var work = FolderComparisonWorkflowWork(limits: request.limits)
            let snapshot = try makeReference(request.snapshot, limits: request.limits, work: &work)
            let ids = selectedIDs(request.selection)
            guard !ids.isEmpty else { throw FolderComparisonWorkflowError.emptySelection }
            guard ids.count <= request.limits.maximumSelectedItems else {
                throw FolderComparisonWorkflowError.tooManySelectedItems(
                    maximum: request.limits.maximumSelectedItems
                )
            }
            var seen: Set<DirectoryResult.ID> = []
            for id in ids {
                try measure(id, work: &work)
                guard seen.insert(id).inserted else {
                    throw FolderComparisonWorkflowError.duplicateSelectedResult(id)
                }
            }
            var resultsByID: [DirectoryResult.ID: DirectoryResult] = [:]
            var revisionsByID: [DirectoryResult.ID: FolderComparisonResultRevision] = [:]
            resultsByID.reserveCapacity(request.snapshot.results.count)
            revisionsByID.reserveCapacity(request.snapshot.resultRevisions.count)
            for index in request.snapshot.results.indices {
                try measure(request.snapshot.results[index].id, work: &work)
                resultsByID[request.snapshot.results[index].id] = request.snapshot.results[index]
                revisionsByID[request.snapshot.resultRevisions[index].id] =
                    request.snapshot.resultRevisions[index]
            }
            var selected: [DirectoryResult] = []
            selected.reserveCapacity(ids.count)
            for id in ids {
                guard let result = resultsByID[id] else {
                    throw FolderComparisonWorkflowError.unknownResult(id)
                }
                selected.append(result)
            }
            selected = try stableSortResultsByPath(selected, work: &work)

            let actions = try plannedActions(
                selected,
                revisionsByID: revisionsByID,
                selection: request.selection,
                replacementOwner: request.replacementOwner,
                roots: request.snapshot.roots,
                capabilities: request.capabilities,
                limits: request.limits,
                work: &work
            )
            guard actions.count <= request.limits.maximumOperationActions else {
                throw FolderComparisonWorkflowError.tooManyOperationActions(
                    maximum: request.limits.maximumOperationActions
                )
            }

            var digest = FolderComparisonCanonicalDigest()
            digest.append("file-operation")
            append(snapshot, to: &digest)
            append(request.capabilities, to: &digest)
            append(request.limits, to: &digest)
            append(request.replacementOwner, to: &digest)
            for action in actions {
                try work.consume(1)
                append(action, to: &digest)
            }
            let receipt = FolderComparisonPlanningReceipt(
                planSHA256: digest.finalize(),
                inputItemCount: selected.count,
                outputItemCount: actions.count,
                estimatedWorkUnits: work.consumed
            )
            return FolderComparisonFileOperationPlan(
                snapshot: snapshot,
                preEffectResults: request.snapshot.results,
                preEffectResultRevisions: request.snapshot.resultRevisions,
                actions: actions,
                replacementOwner: request.replacementOwner,
                capabilities: request.capabilities,
                receipt: receipt,
                limits: request.limits
            )
        } catch is CancellationError {
            throw FolderComparisonWorkflowError.cancelled
        }
    }

    public static func planActivityControl(
        _ request: FolderComparisonActivityControlRequest
    ) throws -> FolderComparisonActivityControlPlan {
        do {
            try validate(request.limits)
            var work = FolderComparisonWorkflowWork(limits: request.limits)
            try validateActivity(request.activity, limits: request.limits, work: &work)
            try require(.progressReporting, in: request.capabilities)
            guard request.activity.supportedControls.contains(request.control) else {
                throw FolderComparisonWorkflowError.unsupportedActivityControl(request.control)
            }
            let feature: FolderComparisonWorkflowFeature
            let successorState: FolderComparisonActivityState
            let successorControls: Set<FolderComparisonActivityControl>
            switch request.control {
            case .pause:
                guard request.activity.state == .running else {
                    throw FolderComparisonWorkflowError.invalidActivityTransition(
                        state: request.activity.state,
                        control: request.control
                    )
                }
                feature = .pause
                successorState = .paused
                successorControls = request.activity.supportedControls
                    .subtracting([.pause])
                    .union([.resume])
            case .resume:
                guard request.activity.state == .paused else {
                    throw FolderComparisonWorkflowError.invalidActivityTransition(
                        state: request.activity.state,
                        control: request.control
                    )
                }
                feature = .resume
                successorState = .running
                successorControls = request.activity.supportedControls
                    .subtracting([.resume])
                    .union([.pause])
            case .cancel:
                guard request.activity.state == .running || request.activity.state == .paused else {
                    throw FolderComparisonWorkflowError.invalidActivityTransition(
                        state: request.activity.state,
                        control: request.control
                    )
                }
                feature = .cancel
                successorState = .cancelling
                successorControls = []
            }
            try require(feature, in: request.capabilities)
            let successor = request.activity.revision.addingReportingOverflow(1)
            guard !successor.overflow else {
                throw FolderComparisonWorkflowError.invalidActivityProgress
            }

            var digest = FolderComparisonCanonicalDigest()
            digest.append("activity-control")
            append(request.activity, to: &digest)
            digest.append(request.control.rawValue)
            digest.append(successor.partialValue)
            digest.append(successorState.rawValue)
            let orderedSuccessorControls = successorControls.sorted { $0.rawValue < $1.rawValue }
            digest.append(orderedSuccessorControls.count)
            for control in orderedSuccessorControls { digest.append(control.rawValue) }
            append(request.capabilities, to: &digest)
            append(request.limits, to: &digest)
            let receipt = FolderComparisonPlanningReceipt(
                planSHA256: digest.finalize(),
                inputItemCount: 1,
                outputItemCount: 1,
                estimatedWorkUnits: work.consumed
            )
            return FolderComparisonActivityControlPlan(
                expectedActivity: request.activity,
                control: request.control,
                expectedSuccessorRevision: successor.partialValue,
                expectedSuccessorState: successorState,
                expectedSuccessorSupportedControls: successorControls,
                capabilities: request.capabilities,
                receipt: receipt,
                limits: request.limits
            )
        } catch is CancellationError {
            throw FolderComparisonWorkflowError.cancelled
        }
    }

    public static func planOpenFilePair(
        _ request: FolderComparisonOpenFilePairRequest
    ) throws -> FolderComparisonOpenFilePairPlan {
        do {
            try validate(request.limits)
            var work = FolderComparisonWorkflowWork(limits: request.limits)
            let snapshot = try makeReference(request.snapshot, limits: request.limits, work: &work)
            try require(.openFilePair, in: request.capabilities)
            try requireAuthority(.readContent, side: .left, roots: request.snapshot.roots)
            try requireAuthority(.readContent, side: .right, roots: request.snapshot.roots)
            try requireTreeAuthority(side: .left, roots: request.snapshot.roots)
            try requireTreeAuthority(side: .right, roots: request.snapshot.roots)
            var resultIndex: Int?
            for index in request.snapshot.results.indices {
                try work.consume(request.snapshot.results[index].relativePath.utf8.count + 1)
                if request.snapshot.results[index].id == request.id {
                    resultIndex = index
                    break
                }
            }
            guard let resultIndex,
                request.snapshot.results.indices.contains(resultIndex)
            else {
                throw FolderComparisonWorkflowError.filePairUnavailable(request.id)
            }
            let result = request.snapshot.results[resultIndex]
            guard
                let left = result.left,
                let right = result.right,
                left.kind == .file,
                right.kind == .file,
                request.snapshot.resultRevisions.indices.contains(resultIndex),
                let leftRevision = request.snapshot.resultRevisions[resultIndex].left,
                let rightRevision = request.snapshot.resultRevisions[resultIndex].right
            else {
                throw FolderComparisonWorkflowError.filePairUnavailable(request.id)
            }
            try validateRelativePath(left.relativePath, id: result.id, limits: request.limits, work: &work)
            try validateRelativePath(right.relativePath, id: result.id, limits: request.limits, work: &work)

            var digest = FolderComparisonCanonicalDigest()
            digest.append("open-file-pair")
            append(snapshot, to: &digest)
            append(request.id, to: &digest)
            digest.append(left.relativePath)
            digest.append(right.relativePath)
            append(leftRevision, to: &digest)
            append(rightRevision, to: &digest)
            append(request.capabilities, to: &digest)
            append(request.limits, to: &digest)
            let receipt = FolderComparisonPlanningReceipt(
                planSHA256: digest.finalize(),
                inputItemCount: 1,
                outputItemCount: 1,
                estimatedWorkUnits: work.consumed
            )
            return FolderComparisonOpenFilePairPlan(
                snapshot: snapshot,
                resultID: request.id,
                leftRelativePath: left.relativePath,
                rightRelativePath: right.relativePath,
                leftRevision: leftRevision,
                rightRevision: rightRevision,
                capabilities: request.capabilities,
                receipt: receipt,
                limits: request.limits
            )
        } catch is CancellationError {
            throw FolderComparisonWorkflowError.cancelled
        }
    }

    public static func reference(
        to snapshot: FolderComparisonWorkflowSnapshot,
        limits: FolderComparisonWorkflowLimits = .default
    ) throws -> FolderComparisonWorkflowSnapshotReference {
        do {
            try validate(limits)
            var work = FolderComparisonWorkflowWork(limits: limits)
            return try makeReference(snapshot, limits: limits, work: &work)
        } catch is CancellationError {
            throw FolderComparisonWorkflowError.cancelled
        }
    }

    fileprivate static func validate(
        _ snapshot: FolderComparisonWorkflowSnapshot,
        against reference: FolderComparisonWorkflowSnapshotReference,
        limits: FolderComparisonWorkflowLimits
    ) throws {
        guard snapshot.identity == reference.identity,
            snapshot.generation == reference.generation,
            snapshot.owner == reference.owner,
            snapshot.roots == reference.roots
        else {
            throw FolderComparisonWorkflowError.staleSnapshot
        }
        let current = try self.reference(to: snapshot, limits: limits)
        guard current.contentSHA256 == reference.contentSHA256 else {
            throw FolderComparisonWorkflowError.snapshotContentsChanged
        }
    }
}

extension FolderComparisonWorkflowPlanner {
    fileprivate static func validate(_ limits: FolderComparisonWorkflowLimits) throws {
        let intLimits: [(FolderComparisonWorkflowLimit, Int, ClosedRange<Int>)] = [
            (.resultItems, limits.maximumResultItems, 0...FolderComparisonWorkflowLimits.hardMaximumResultItems),
            (.selectedItems, limits.maximumSelectedItems, 0...FolderComparisonWorkflowLimits.hardMaximumSelectedItems),
            (.operationActions, limits.maximumOperationActions, 0...FolderComparisonWorkflowLimits.hardMaximumOperationActions),
            (.presentationRows, limits.maximumPresentationRows, 0...FolderComparisonWorkflowLimits.hardMaximumPresentationRows),
            (.columns, limits.maximumColumns, 1...FolderComparisonWorkflowLimits.hardMaximumColumns),
            (.sortDescriptors, limits.maximumSortDescriptors, 1...FolderComparisonWorkflowLimits.hardMaximumSortDescriptors),
            (.filterRules, limits.maximumFilterRules, 0...FolderComparisonWorkflowLimits.hardMaximumFilterRules),
            (.stringUTF8Bytes, limits.maximumStringUTF8Bytes, 1...FolderComparisonWorkflowLimits.hardMaximumStringUTF8Bytes),
            (.totalStringUTF8Bytes, limits.maximumTotalStringUTF8Bytes, 1...FolderComparisonWorkflowLimits.hardMaximumTotalStringUTF8Bytes),
            (.metadataDigestBytes, limits.maximumMetadataDigestBytes, 32...FolderComparisonWorkflowLimits.hardMaximumMetadataDigestBytes),
            (.cancellationCheckInterval, limits.cancellationCheckInterval, 1...FolderComparisonWorkflowLimits.hardMaximumCancellationCheckInterval)
        ]
        for (limit, value, range) in intLimits where !range.contains(value) {
            throw FolderComparisonWorkflowError.invalidLimit(limit, value: String(value))
        }
        guard limits.maximumSelectedItems <= limits.maximumResultItems else {
            throw FolderComparisonWorkflowError.invalidLimit(
                .selectedItems,
                value: String(limits.maximumSelectedItems)
            )
        }
        guard limits.maximumPresentationRows <= limits.maximumResultItems else {
            throw FolderComparisonWorkflowError.invalidLimit(
                .presentationRows,
                value: String(limits.maximumPresentationRows)
            )
        }
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= FolderComparisonWorkflowLimits.hardMaximumWorkUnits
        else {
            throw FolderComparisonWorkflowError.invalidLimit(
                .workUnits,
                value: String(limits.maximumWorkUnits)
            )
        }
    }

    fileprivate static func validateRoots(
        _ roots: FolderComparisonRootPair,
        recursive: Bool,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        for side in FolderComparisonWorkflowSide.allCases {
            try work.consume(1)
            let root = roots[side]
            try validateLocalURL(
                root.requestedURL,
                role: .requestedRoot(side),
                canonical: false,
                work: &work
            )
            try validateLocalURL(
                root.revision.identity.canonicalURL,
                role: .canonicalRoot(side),
                canonical: true,
                work: &work
            )
            try validateRootRevision(root.revision, side: side, work: &work)
            guard root.authority.rootIdentity == root.revision.identity else {
                throw FolderComparisonWorkflowError.authorityRootMismatch(side)
            }
            try requireAuthority(.enumerate, side: side, roots: roots)
            guard root.authority.coverage == .directoryTree else {
                throw FolderComparisonWorkflowError.invalidURL(
                    role: .requestedRoot(side),
                    issue: .insufficientCoverage
                )
            }
            if case .securityScoped(let resourceURL, let coverage) = root.authority.acquisition {
                try validateLocalURL(
                    resourceURL,
                    role: .securityScope(side),
                    canonical: false,
                    work: &work
                )
                guard coverage == .directoryTree else {
                    throw FolderComparisonWorkflowError.invalidURL(
                        role: .securityScope(side),
                        issue: .insufficientCoverage
                    )
                }
                guard coverage == root.authority.coverage else {
                    throw FolderComparisonWorkflowError.invalidURL(
                        role: .securityScope(side),
                        issue: .insufficientCoverage
                    )
                }
            }
        }
        guard
            !samePhysicalIdentity(
                roots.left.revision.identity,
                roots.right.revision.identity
            )
        else {
            throw FolderComparisonWorkflowError.duplicateRootIdentity
        }
    }

    fileprivate static func validateRootRevision(
        _ revision: FolderComparisonRootRevision,
        side: FolderComparisonWorkflowSide,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        guard revision.linkCount > 0,
            (0...999_999_999).contains(revision.modificationTimeNanoseconds),
            (0...999_999_999).contains(revision.statusChangeTimeNanoseconds),
            revision.metadataSHA256.count == 32
        else {
            throw FolderComparisonWorkflowError.invalidRootRevision(side)
        }
        try work.consume(revision.metadataSHA256.count)
    }

    fileprivate static func validateLocalURL(
        _ url: URL,
        role: FolderComparisonWorkflowURLRole,
        canonical: Bool,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        guard url.isFileURL else {
            throw FolderComparisonWorkflowError.invalidURL(role: role, issue: .notFileURL)
        }
        guard url.path.hasPrefix("/") else {
            throw FolderComparisonWorkflowError.invalidURL(role: role, issue: .relativeURL)
        }
        guard url.host == nil || url.host == "localhost" else {
            throw FolderComparisonWorkflowError.invalidURL(role: role, issue: .remoteHost)
        }
        guard url.user == nil, url.password == nil, url.port == nil else {
            throw FolderComparisonWorkflowError.invalidURL(role: role, issue: .credentialsOrPort)
        }
        guard url.query == nil, url.fragment == nil else {
            throw FolderComparisonWorkflowError.invalidURL(role: role, issue: .queryOrFragment)
        }
        guard !url.path.contains("\0") else {
            throw FolderComparisonWorkflowError.invalidURL(role: role, issue: .nullByte)
        }
        guard try work.measure(url.path) <= work.limits.maximumStringUTF8Bytes else {
            throw FolderComparisonWorkflowError.invalidURL(role: role, issue: .pathTooLong)
        }
        if canonical {
            guard url.baseURL == nil, url.standardizedFileURL == url else {
                throw FolderComparisonWorkflowError.invalidURL(role: role, issue: .notCanonical)
            }
        }
    }

    fileprivate static func validateScanIntent(
        _ intent: FolderComparisonScanIntent,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        let values: [Int] = [
            intent.options.limits.maximumDepth,
            intent.options.limits.maximumEntries,
            intent.options.limits.maximumExaminedEntries,
            intent.options.limits.maximumIssues,
            intent.options.limits.maximumOpenDirectoryDescriptors,
            intent.options.limits.maximumPendingEntryNames,
            intent.options.limits.maximumRelativePathUTF8Bytes
        ]
        guard values.allSatisfy({ $0 >= 0 }),
            intent.options.limits.maximumTotalAccountedBytes >= 0,
            intent.options.limits.maximumEntries <= limits.maximumResultItems,
            intent.options.limits.maximumRelativePathUTF8Bytes <= limits.maximumStringUTF8Bytes
        else {
            throw FolderComparisonWorkflowError.invalidScanOptions
        }
        guard let filter = intent.filenameFilter else { return }
        guard filter.rules.count <= limits.maximumFilterRules else {
            throw FolderComparisonWorkflowError.invalidLimit(
                .filterRules,
                value: String(filter.rules.count)
            )
        }
        guard filter.rules.count <= filter.limits.maximumRuleCount,
            filter.limits.maximumPatternUTF8Bytes <= limits.maximumStringUTF8Bytes,
            filter.limits.maximumTotalPatternUTF8Bytes <= limits.maximumTotalStringUTF8Bytes,
            filter.limits.maximumRelativePathUTF8Bytes <= limits.maximumStringUTF8Bytes,
            filter.limits.maximumCompiledStateCount <= 65_536,
            filter.limits.maximumMatchWork <= 1_000_000,
            filter.limits.maximumRegularExpressionNestingDepth <= 64,
            filter.limits.maximumRegularExpressionRepetition <= 1_024
        else {
            throw FolderComparisonWorkflowError.invalidLimit(
                .filterRules,
                value: String(filter.rules.count)
            )
        }
        let aggregateMatchWork = UInt64(intent.options.limits.maximumExaminedEntries)
            .multipliedReportingOverflow(by: UInt64(filter.limits.maximumMatchWork))
        let pairMatchWork = aggregateMatchWork.partialValue.multipliedReportingOverflow(by: 2)
        guard !aggregateMatchWork.overflow,
            !pairMatchWork.overflow,
            pairMatchWork.partialValue <= limits.maximumWorkUnits
        else {
            throw FolderComparisonWorkflowError.workLimitExceeded(
                maximumUnits: limits.maximumWorkUnits
            )
        }
        var totalPatternBytes = 0
        for rule in filter.rules {
            let bytes = try work.measure(rule.pattern.source)
            guard bytes <= filter.limits.maximumPatternUTF8Bytes,
                totalPatternBytes <= filter.limits.maximumTotalPatternUTF8Bytes - bytes
            else {
                throw FolderComparisonWorkflowError.stringTooLarge(
                    maximumUTF8Bytes: filter.limits.maximumPatternUTF8Bytes
                )
            }
            totalPatternBytes += bytes
        }
        try work.consume(filter.limits.maximumCompiledStateCount)
        let compiled = try FilenameFilter(
            rules: filter.rules,
            defaultDecision: filter.defaultDecision,
            matchSemantics: filter.matchSemantics,
            casePolicy: filter.casePolicy,
            limits: filter.limits
        )
        if let diagnostic = compiled.diagnostics.first {
            throw FolderComparisonWorkflowError.invalidFilenameFilter(diagnostic)
        }
    }

    fileprivate static func validateComparisonSettings(_ settings: FolderComparisonSettings) throws {
        guard settings.modificationDateTolerance.isFinite,
            settings.modificationDateTolerance >= 0
        else {
            throw FolderComparisonWorkflowError.invalidComparisonSettings
        }
    }

    fileprivate static func require(
        _ feature: FolderComparisonWorkflowFeature,
        in capabilities: FolderComparisonWorkflowCapabilities
    ) throws {
        guard capabilities.features.contains(feature) else {
            throw FolderComparisonWorkflowError.unsupportedCapability(feature)
        }
    }

    fileprivate static func requireAuthority(
        _ permission: FolderComparisonAuthorityPermission,
        side: FolderComparisonWorkflowSide,
        roots: FolderComparisonRootPair
    ) throws {
        guard roots[side].authority.permissions.contains(permission) else {
            throw FolderComparisonWorkflowError.authorityPermissionMissing(
                side: side,
                permission: permission
            )
        }
    }

    fileprivate static func requireTreeAuthority(
        side: FolderComparisonWorkflowSide,
        roots: FolderComparisonRootPair
    ) throws {
        guard roots[side].authority.coverage == .directoryTree else {
            throw FolderComparisonWorkflowError.invalidURL(
                role: .requestedRoot(side),
                issue: .insufficientCoverage
            )
        }
    }

    fileprivate static func makeReference(
        _ snapshot: FolderComparisonWorkflowSnapshot,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws -> FolderComparisonWorkflowSnapshotReference {
        try validateRoots(snapshot.roots, recursive: snapshot.scanIntent.recursive, work: &work)
        try validateScanIntent(snapshot.scanIntent, limits: limits, work: &work)
        try validateComparisonSettings(snapshot.comparisonSettings)
        guard snapshot.results.count <= limits.maximumResultItems else {
            throw FolderComparisonWorkflowError.tooManyResults(maximum: limits.maximumResultItems)
        }
        guard snapshot.isComplete else {
            throw FolderComparisonWorkflowError.invalidResultRevision(
                snapshot.results.first?.id
                    ?? DirectoryResult.ID(leftRelativePath: "?", rightRelativePath: nil)
            )
        }
        guard snapshot.resultRevisions.count == snapshot.results.count else {
            let id = snapshot.results.first?.id ?? DirectoryResult.ID(leftRelativePath: "?", rightRelativePath: nil)
            throw FolderComparisonWorkflowError.invalidResultRevision(id)
        }
        var seen: Set<DirectoryResult.ID> = []
        var leftPaths: Set<String> = []
        var rightPaths: Set<String> = []
        var normalizedResultIDs: Set<FolderComparisonNormalizedResultID> = []
        var comparisonPaths: [String: DirectoryResult.ID] = [:]
        var physicalIdentities: Set<FolderComparisonPhysicalIdentity> = [
            FolderComparisonPhysicalIdentity(snapshot.roots.left.revision.identity),
            FolderComparisonPhysicalIdentity(snapshot.roots.right.revision.identity)
        ]
        var digest = FolderComparisonCanonicalDigest()
        digest.append("folder-comparison-snapshot")
        digest.append(snapshot.identity.rawValue)
        digest.append(snapshot.generation)
        append(snapshot.owner, to: &digest)
        append(snapshot.roots, to: &digest)
        append(snapshot.scanIntent, to: &digest)
        append(snapshot.comparisonSettings, to: &digest)
        digest.append(snapshot.isComplete)
        digest.append(snapshot.results.count)
        for index in snapshot.results.indices {
            try work.consume(1)
            let result = snapshot.results[index]
            let revision = snapshot.resultRevisions[index]
            guard seen.insert(result.id).inserted else {
                throw FolderComparisonWorkflowError.duplicateResultID(result.id)
            }
            try validateResult(
                result,
                revision: revision,
                roots: snapshot.roots,
                limits: limits,
                work: &work
            )
            try validateUniqueResultSide(
                result.left,
                revision: revision.left,
                side: .left,
                caseSensitivity: snapshot.roots.left.pathCaseSensitivity,
                paths: &leftPaths,
                physicalIdentities: &physicalIdentities,
                id: result.id,
                work: &work
            )
            let normalizedID = try FolderComparisonNormalizedResultID(
                result: result,
                caseSensitivity: snapshot.comparisonSettings.pathCaseSensitivity,
                work: &work
            )
            guard normalizedResultIDs.insert(normalizedID).inserted else {
                throw FolderComparisonWorkflowError.duplicateResultID(result.id)
            }
            for path in [normalizedID.left, normalizedID.right].compactMap({ $0 }) {
                try work.consume(path.utf8.count + 1)
                if let existing = comparisonPaths[path], existing != result.id {
                    throw FolderComparisonWorkflowError.duplicateResultID(result.id)
                }
                comparisonPaths[path] = result.id
            }
            try validateComparisonStatus(
                result,
                revision: revision,
                settings: snapshot.comparisonSettings
            )
            try validateUniqueResultSide(
                result.right,
                revision: revision.right,
                side: .right,
                caseSensitivity: snapshot.roots.right.pathCaseSensitivity,
                paths: &rightPaths,
                physicalIdentities: &physicalIdentities,
                id: result.id,
                work: &work
            )
            append(result, to: &digest)
            append(revision, to: &digest)
        }
        return FolderComparisonWorkflowSnapshotReference(
            identity: snapshot.identity,
            generation: snapshot.generation,
            owner: snapshot.owner,
            roots: snapshot.roots,
            scanIntent: snapshot.scanIntent,
            comparisonSettings: snapshot.comparisonSettings,
            contentSHA256: digest.finalize()
        )
    }

    fileprivate static func validateResult(
        _ result: DirectoryResult,
        revision: FolderComparisonResultRevision,
        roots: FolderComparisonRootPair,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        guard result.id == revision.id else {
            throw FolderComparisonWorkflowError.invalidResultRevision(result.id)
        }
        try validateResultSide(
            result.left,
            revision: revision.left,
            side: .left,
            id: result.id,
            roots: roots,
            limits: limits,
            work: &work
        )
        try validateResultSide(
            result.right,
            revision: revision.right,
            side: .right,
            id: result.id,
            roots: roots,
            limits: limits,
            work: &work
        )
    }

    fileprivate static func validateResultSide(
        _ metadata: DirectoryEntryMetadata?,
        revision: FolderComparisonItemRevision?,
        side: FolderComparisonWorkflowSide,
        id: DirectoryResult.ID,
        roots: FolderComparisonRootPair,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        guard let metadata else {
            guard revision == nil else {
                throw FolderComparisonWorkflowError.invalidResultRevision(id)
            }
            return
        }
        guard let revision else {
            throw FolderComparisonWorkflowError.invalidResultRevision(id)
        }
        guard let modificationDate = metadata.modificationDate else {
            throw FolderComparisonWorkflowError.invalidResultRevision(id)
        }
        let timestampIsValid = {
            timestampMatches(
                modificationDate,
                seconds: revision.modificationTimeSeconds,
                nanoseconds: revision.modificationTimeNanoseconds
            )
        }()
        guard
            revision.identity.rootIdentity == roots[side].revision.identity,
            revision.identity.relativePath == metadata.relativePath,
            revision.kind == metadata.kind,
            revision.byteCount == metadata.byteCount,
            timestampIsValid,
            revision.linkCount > 0,
            (0...999_999_999).contains(revision.modificationTimeNanoseconds),
            (0...999_999_999).contains(revision.statusChangeTimeNanoseconds),
            revision.metadataSHA256.count == 32,
            revision.contentSHA256?.count == 32 || revision.contentSHA256 == nil,
            revision.metadataSHA256.count <= limits.maximumMetadataDigestBytes
        else {
            throw FolderComparisonWorkflowError.invalidResultRevision(id)
        }
        try work.consume(revision.metadataSHA256.count + (revision.contentSHA256?.count ?? 0))
        try validateRelativePath(metadata.relativePath, id: id, limits: limits, work: &work)
    }

    fileprivate static func validateUniqueResultSide(
        _ metadata: DirectoryEntryMetadata?,
        revision: FolderComparisonItemRevision?,
        side: FolderComparisonWorkflowSide,
        caseSensitivity: FolderPathCaseSensitivitySelection,
        paths: inout Set<String>,
        physicalIdentities: inout Set<FolderComparisonPhysicalIdentity>,
        id: DirectoryResult.ID,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        guard let metadata, let revision else { return }
        let normalized = try normalizedPath(
            metadata.relativePath,
            caseSensitivity: caseSensitivity,
            work: &work
        )
        guard paths.insert(normalized).inserted else {
            throw FolderComparisonWorkflowError.duplicateResultPath(
                side: side,
                relativePath: metadata.relativePath
            )
        }
        guard physicalIdentities.insert(FolderComparisonPhysicalIdentity(revision.identity)).inserted else {
            throw FolderComparisonWorkflowError.duplicateItemIdentity(id)
        }
    }

    fileprivate static func validateComparisonStatus(
        _ result: DirectoryResult,
        revision: FolderComparisonResultRevision,
        settings: FolderComparisonSettings
    ) throws {
        switch (result.left, result.right, revision.left, revision.right, result.status) {
        case (.some, nil, .some, nil, .leftOnly),
            (nil, .some, nil, .some, .rightOnly):
            return
        case (let left?, let right?, let leftRevision?, let rightRevision?, .typeMismatch)
        where left.kind != right.kind && leftRevision.kind != rightRevision.kind:
            return
        case (let left?, let right?, let leftRevision?, let rightRevision?, .identical),
            (let left?, let right?, let leftRevision?, let rightRevision?, .different):
            let metadataEqual =
                left.kind == right.kind
                && left.byteCount == right.byteCount
                && timestampsWithinTolerance(
                    leftRevision,
                    rightRevision,
                    tolerance: settings.modificationDateTolerance
                )
            let contentEqual =
                leftRevision.contentSHA256 != nil
                && leftRevision.contentSHA256 == rightRevision.contentSHA256
            let expectsIdentical = result.status == .identical
            switch settings.method {
            case .metadataOnly:
                guard metadataEqual == expectsIdentical else { break }
                return
            case .contentRequired:
                if left.kind == .file, right.kind == .file {
                    guard leftRevision.contentSHA256 != nil,
                        rightRevision.contentSHA256 != nil,
                        (metadataEqual && contentEqual) == expectsIdentical
                    else { break }
                } else {
                    guard metadataEqual == expectsIdentical else { break }
                }
                return
            case .contentIfAvailable:
                let equal =
                    leftRevision.contentSHA256 != nil && rightRevision.contentSHA256 != nil
                    ? metadataEqual && contentEqual
                    : metadataEqual
                guard equal == expectsIdentical else { break }
                return
            }
            break
        case (.some, .some, .some, .some, .skipped),
            (.some, .some, .some, .some, .error):
            return
        default:
            break
        }
        throw FolderComparisonWorkflowError.invalidResultRevision(result.id)
    }

    fileprivate static func timestampsWithinTolerance(
        _ left: FolderComparisonItemRevision,
        _ right: FolderComparisonItemRevision,
        tolerance: TimeInterval
    ) -> Bool {
        let seconds = Double(left.modificationTimeSeconds) - Double(right.modificationTimeSeconds)
        let nanoseconds =
            Double(left.modificationTimeNanoseconds - right.modificationTimeNanoseconds)
            / 1_000_000_000
        return abs(seconds + nanoseconds) <= tolerance
    }

    fileprivate static func validateRelativePath(
        _ path: String,
        id: DirectoryResult.ID,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        guard try work.measure(path) <= limits.maximumStringUTF8Bytes,
            !path.isEmpty,
            !path.hasPrefix("/"),
            !path.contains("\0")
        else {
            throw FolderComparisonWorkflowError.invalidResultPath(id)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw FolderComparisonWorkflowError.invalidResultPath(id)
        }
    }

    fileprivate static func validatePresentation(
        _ configuration: FolderComparisonPresentationConfiguration,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        guard configuration.columns.count <= limits.maximumColumns else {
            throw FolderComparisonWorkflowError.tooManyColumns(maximum: limits.maximumColumns)
        }
        var columns: Set<FolderComparisonPresentationColumn> = []
        for column in configuration.columns {
            try work.consume(1)
            guard columns.insert(column).inserted else {
                throw FolderComparisonWorkflowError.duplicateColumn(column)
            }
        }
        for required in [FolderComparisonPresentationColumn.stateIcon, .relativePath]
        where !columns.contains(required) {
            throw FolderComparisonWorkflowError.missingRequiredColumn(required)
        }
        guard configuration.sortDescriptors.count <= limits.maximumSortDescriptors else {
            throw FolderComparisonWorkflowError.tooManySortDescriptors(
                maximum: limits.maximumSortDescriptors
            )
        }
        var sortKeys: Set<FolderComparisonPresentationSortKey> = []
        for descriptor in configuration.sortDescriptors {
            try work.consume(1)
            guard sortKeys.insert(descriptor.key).inserted else {
                throw FolderComparisonWorkflowError.duplicateSortKey(descriptor.key)
            }
        }
        guard !configuration.sortDescriptors.isEmpty else {
            throw FolderComparisonWorkflowError.invalidLimit(.sortDescriptors, value: "0")
        }
        if configuration.mode == .tree {
            guard
                configuration.sortDescriptors == [
                    FolderComparisonPresentationSortDescriptor(key: .path, order: .ascending)
                ]
            else {
                throw FolderComparisonWorkflowError.unsupportedTreeSort
            }
        }
        guard try work.measure(configuration.filter.pathQuery) <= limits.maximumStringUTF8Bytes else {
            throw FolderComparisonWorkflowError.stringTooLarge(
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        guard !configuration.filter.pathQuery.contains("\0") else {
            throw FolderComparisonWorkflowError.invalidResultPath(
                DirectoryResult.ID(leftRelativePath: "?", rightRelativePath: nil)
            )
        }
    }

    fileprivate static func matches(
        _ result: DirectoryResult,
        filter: FolderComparisonPresentationFilter,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws -> Bool {
        if !filter.statuses.isEmpty, !filter.statuses.contains(result.status) { return false }
        if !filter.kinds.isEmpty {
            let leftMatches = result.left.map { filter.kinds.contains($0.kind) } == true
            let rightMatches = result.right.map { filter.kinds.contains($0.kind) } == true
            if !leftMatches && !rightMatches { return false }
        }
        switch filter.hidden {
        case .include: break
        case .exclude where result.isHidden: return false
        case .only where !result.isHidden: return false
        default: break
        }
        guard !filter.pathQuery.isEmpty else { return true }
        for path in [result.left?.relativePath, result.right?.relativePath].compactMap({ $0 }) {
            try work.consume(min(path.utf8.count, limits.maximumStringUTF8Bytes))
            if path.range(
                of: filter.pathQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ) != nil {
                return true
            }
        }
        return false
    }

    fileprivate static func makeRows(
        _ values: [(offset: Int, result: DirectoryResult)],
        mode: FolderComparisonPresentationMode,
        roots: FolderComparisonRootPair,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws -> [FolderComparisonPresentationRow] {
        guard mode == .tree else {
            var rows: [FolderComparisonPresentationRow] = []
            rows.reserveCapacity(values.count)
            for value in values {
                try work.consume(1)
                rows.append(FolderComparisonPresentationRow(result: value.result, mode: mode))
            }
            return rows
        }

        var directoryPaths: [FolderComparisonTreePath: DirectoryResult.ID] = [:]
        for value in values {
            try work.consume(1)
            guard
                value.result.id.leftRelativePath == nil
                    || value.result.id.rightRelativePath == nil
                    || value.result.id.leftRelativePath == value.result.id.rightRelativePath
            else {
                throw FolderComparisonWorkflowError.unsupportedTreeResult(value.result.id)
            }
            for side in FolderComparisonWorkflowSide.allCases {
                if let sideMetadata = metadata(value.result, side: side),
                    sideMetadata.kind == .directory
                {
                    let path = sideMetadata.relativePath
                    let normalized = try normalizedPath(
                        path,
                        caseSensitivity: roots[side].pathCaseSensitivity,
                        work: &work
                    )
                    directoryPaths[FolderComparisonTreePath(side: side, relativePath: normalized)] =
                        value.result.id
                }
            }
        }
        var rows: [FolderComparisonPresentationRow] = []
        rows.reserveCapacity(values.count)
        var parents: [DirectoryResult.ID: FolderComparisonTreeParent] = [:]
        for value in values {
            try work.consume(1)
            let result = value.result
            guard
                result.id.leftRelativePath == nil
                    || result.id.rightRelativePath == nil
                    || result.id.leftRelativePath == result.id.rightRelativePath
            else {
                throw FolderComparisonWorkflowError.unsupportedTreeResult(result.id)
            }
            let side = result.left != nil ? FolderComparisonWorkflowSide.left : .right
            let parent = try nearestAdmittedParent(
                of: metadata(result, side: side)!.relativePath,
                side: side,
                directoryPaths: directoryPaths,
                roots: roots,
                limits: limits,
                work: &work
            )
            if let parent {
                parents[result.id] = FolderComparisonTreeParent(
                    id: parent.id,
                    relativePath: parent.relativePath
                )
            }
        }
        for value in values {
            try work.consume(1)
            let result = value.result
            let parent = parents[result.id]
            let depth = try treeDepth(of: result.id, parents: parents, work: &work)
            rows.append(
                FolderComparisonPresentationRow(
                    result: result,
                    mode: mode,
                    treeParentRelativePath: parent?.relativePath,
                    treeParentID: parent?.id,
                    treeDepth: depth
                )
            )
        }
        return try treePreorder(rows, work: &work)
    }

    fileprivate static func treeDepth(
        of id: DirectoryResult.ID,
        parents: [DirectoryResult.ID: FolderComparisonTreeParent],
        work: inout FolderComparisonWorkflowWork
    ) throws -> Int {
        var depth = 0
        var current = id
        var seen: Set<DirectoryResult.ID> = []
        while let parent = parents[current] {
            try work.consume(parent.relativePath.utf8.count + 1)
            guard seen.insert(parent.id).inserted else {
                throw FolderComparisonWorkflowError.unsupportedTreeResult(id)
            }
            depth += 1
            current = parent.id
        }
        return depth
    }

    fileprivate static func treePreorder(
        _ rows: [FolderComparisonPresentationRow],
        work: inout FolderComparisonWorkflowWork
    ) throws -> [FolderComparisonPresentationRow] {
        var children: [DirectoryResult.ID?: [FolderComparisonPresentationRow]] = [:]
        for row in rows {
            try work.consume(row.relativePath.utf8.count + 1)
            children[row.treeParentID, default: []].append(row)
        }
        var ordered: [FolderComparisonPresentationRow] = []
        var stack = Array((children[nil] ?? []).reversed())
        while let row = stack.popLast() {
            try work.consume(1)
            ordered.append(row)
            stack.append(contentsOf: (children[row.id] ?? []).reversed())
        }
        guard ordered.count == rows.count else {
            throw FolderComparisonWorkflowError.unsupportedTreeResult(
                rows.first?.id ?? DirectoryResult.ID(leftRelativePath: "?", rightRelativePath: nil)
            )
        }
        return ordered
    }

    fileprivate static func nearestAdmittedParent(
        of path: String,
        side: FolderComparisonWorkflowSide,
        directoryPaths: [FolderComparisonTreePath: DirectoryResult.ID],
        roots: FolderComparisonRootPair,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws -> (id: DirectoryResult.ID, relativePath: String)? {
        var components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count > 1 else { return nil }
        components.removeLast()
        while !components.isEmpty {
            let candidate = components.joined(separator: "/")
            try work.consume(candidate.utf8.count + 1)
            guard candidate.utf8.count <= limits.maximumStringUTF8Bytes else {
                throw FolderComparisonWorkflowError.stringTooLarge(
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            let normalized = try normalizedPath(
                candidate,
                caseSensitivity: roots[side].pathCaseSensitivity,
                work: &work
            )
            if let id = directoryPaths[FolderComparisonTreePath(side: side, relativePath: normalized)] {
                return (id, candidate)
            }
            components.removeLast()
        }
        return nil
    }

    fileprivate static func selectedIDs(_ selection: FolderComparisonFileOperationSelection) -> [DirectoryResult.ID] {
        switch selection {
        case .copy(let ids, _, _), .move(let ids, _, _), .delete(let ids, _),
            .synchronize(let ids, _, _, _):
            ids
        }
    }

    fileprivate static func measure(
        _ id: DirectoryResult.ID,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        if let left = id.leftRelativePath { try work.consume(left.utf8.count + 1) }
        if let right = id.rightRelativePath { try work.consume(right.utf8.count + 1) }
    }

    fileprivate static func plannedActions(
        _ results: [DirectoryResult],
        revisionsByID: [DirectoryResult.ID: FolderComparisonResultRevision],
        selection: FolderComparisonFileOperationSelection,
        replacementOwner: FolderComparisonReplacementOwner?,
        roots: FolderComparisonRootPair,
        capabilities: FolderComparisonWorkflowCapabilities,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws -> [FolderComparisonPlannedFileAction] {
        try work.consume(results.count)
        guard results.count == 1 else {
            throw FolderComparisonWorkflowError.unsupportedOperationBatch
        }
        let sideRevisionsByPath = try sideRevisionIndex(
            revisionsByID.values,
            roots: roots,
            work: &work
        )
        let sourceSide: FolderComparisonWorkflowSide?
        let destinationSide: FolderComparisonWorkflowSide
        let kind: FolderComparisonPlannedActionKind
        let collision: FolderComparisonFileCollisionSelection?
        let deletesExtraneous: Bool
        let synchronizes: Bool
        switch selection {
        case .copy(_, let source, let policy):
            try require(.copyItems, in: capabilities)
            sourceSide = source
            destinationSide = opposite(source)
            kind = .copy
            collision = policy
            deletesExtraneous = false
            synchronizes = false
        case .move(_, let source, let policy):
            try require(.moveItems, in: capabilities)
            sourceSide = source
            destinationSide = opposite(source)
            kind = .move
            collision = policy
            deletesExtraneous = false
            synchronizes = false
        case .delete(_, let side):
            try require(.deleteItems, in: capabilities)
            sourceSide = nil
            destinationSide = side
            kind = .delete
            collision = nil
            deletesExtraneous = false
            synchronizes = false
        case .synchronize(_, let source, let policy, let deleteExtraneous):
            try require(.synchronizeItems, in: capabilities)
            sourceSide = source
            destinationSide = opposite(source)
            kind = .copy
            collision = policy
            deletesExtraneous = deleteExtraneous
            synchronizes = true
        }
        try requireAuthority(.mutate, side: destinationSide, roots: roots)
        if kind == .move, let sourceSide {
            try requireAuthority(.mutate, side: sourceSide, roots: roots)
        }
        if sourceSide != nil { try requireAuthority(.readContent, side: sourceSide!, roots: roots) }
        let sourceHasTreeCoverage =
            sourceSide.map({
                roots[$0].authority.coverage == .directoryTree
            }) ?? true
        guard roots[destinationSide].authority.coverage == .directoryTree,
            sourceHasTreeCoverage
        else {
            throw FolderComparisonWorkflowError.invalidURL(
                role: .requestedRoot(destinationSide),
                issue: .insufficientCoverage
            )
        }

        var actions: [FolderComparisonPlannedFileAction] = []
        var destinationPaths: Set<String> = []
        actions.reserveCapacity(min(results.count * (deletesExtraneous ? 2 : 1), limits.maximumOperationActions))
        for result in results {
            try work.consume(1)
            guard let revisions = revisionsByID[result.id] else {
                throw FolderComparisonWorkflowError.invalidResultRevision(result.id)
            }
            if kind == .delete {
                guard let destination = metadata(result, side: destinationSide),
                    let destinationRevision = revisions[destinationSide]
                else {
                    throw FolderComparisonWorkflowError.missingOperationSource(
                        id: result.id,
                        side: destinationSide
                    )
                }
                try validateOperable(destination, id: result.id)
                let normalizedDestination = try normalizedPath(
                    destination.relativePath,
                    caseSensitivity: roots[destinationSide].pathCaseSensitivity,
                    work: &work
                )
                guard destinationPaths.insert(normalizedDestination).inserted else {
                    throw FolderComparisonWorkflowError.destinationCollision(
                        side: destinationSide,
                        relativePath: destination.relativePath
                    )
                }
                guard let actionOwner = replacementOwner else {
                    throw FolderComparisonWorkflowError.replacementOwnerRequired
                }
                actions.append(
                    FolderComparisonPlannedFileAction(
                        resultID: result.id,
                        kind: .delete,
                        sourceSide: nil,
                        sourceRoot: nil,
                        source: nil,
                        sourceRevision: nil,
                        destinationSide: destinationSide,
                        destinationRoot: FolderComparisonActionRootBinding(root: roots[destinationSide]),
                        destination: destination,
                        destinationPrecondition: .existing(destinationRevision),
                        destinationRelativePath: destination.relativePath,
                        collision: nil,
                        replacementOwner: actionOwner
                    )
                )
                continue
            }
            if synchronizes,
                metadata(result, side: sourceSide!) == nil
            {
                guard deletesExtraneous else { continue }
                guard let destination = metadata(result, side: destinationSide),
                    let destinationRevision = revisions[destinationSide]
                else {
                    throw FolderComparisonWorkflowError.invalidResultRevision(result.id)
                }
                try validateOperable(destination, id: result.id)
                let normalizedDestination = try normalizedPath(
                    destination.relativePath,
                    caseSensitivity: roots[destinationSide].pathCaseSensitivity,
                    work: &work
                )
                guard destinationPaths.insert(normalizedDestination).inserted else {
                    throw FolderComparisonWorkflowError.destinationCollision(
                        side: destinationSide,
                        relativePath: destination.relativePath
                    )
                }
                guard let actionOwner = replacementOwner else {
                    throw FolderComparisonWorkflowError.replacementOwnerRequired
                }
                actions.append(
                    FolderComparisonPlannedFileAction(
                        resultID: result.id,
                        kind: .delete,
                        sourceSide: nil,
                        sourceRoot: nil,
                        source: nil,
                        sourceRevision: nil,
                        destinationSide: destinationSide,
                        destinationRoot: FolderComparisonActionRootBinding(root: roots[destinationSide]),
                        destination: destination,
                        destinationPrecondition: .existing(destinationRevision),
                        destinationRelativePath: destination.relativePath,
                        collision: nil,
                        replacementOwner: actionOwner
                    )
                )
                continue
            }
            guard let sourceSide,
                let source = metadata(result, side: sourceSide),
                let sourceRevision = revisions[sourceSide]
            else {
                throw FolderComparisonWorkflowError.missingOperationSource(
                    id: result.id,
                    side: sourceSide ?? destinationSide
                )
            }
            try validateOperable(source, id: result.id)
            guard sourceRevision.contentSHA256 != nil else {
                throw FolderComparisonWorkflowError.invalidResultRevision(result.id)
            }
            let destination = metadata(result, side: destinationSide)
            let destinationRevision = revisions[destinationSide]
            if let destination {
                try validateOperable(destination, id: result.id)
            }
            let destinationRelativePath = destination?.relativePath ?? source.relativePath
            let normalizedDestination = try normalizedPath(
                destinationRelativePath,
                caseSensitivity: roots[destinationSide].pathCaseSensitivity,
                work: &work
            )
            guard destinationPaths.insert(normalizedDestination).inserted else {
                throw FolderComparisonWorkflowError.destinationCollision(
                    side: destinationSide,
                    relativePath: destinationRelativePath
                )
            }
            let destinationPrecondition: FolderComparisonDestinationPrecondition
            if let destinationRevision {
                guard collision != .fail else {
                    throw FolderComparisonWorkflowError.destinationCollision(
                        side: destinationSide,
                        relativePath: destinationRelativePath
                    )
                }
                destinationPrecondition = .existing(destinationRevision)
            } else {
                guard
                    try provesAbsent(
                        destinationRelativePath,
                        side: destinationSide,
                        sideRevisionsByPath: sideRevisionsByPath,
                        roots: roots,
                        work: &work
                    )
                else {
                    throw FolderComparisonWorkflowError.absenceNotProvable(
                        side: destinationSide,
                        relativePath: destinationRelativePath
                    )
                }
                destinationPrecondition = .absent(
                    try absenceWitness(
                        for: destinationRelativePath,
                        destinationSide: destinationSide,
                        sideRevisionsByPath: sideRevisionsByPath,
                        roots: roots,
                        caseSensitivity: roots[destinationSide].pathCaseSensitivity,
                        work: &work
                    )
                )
            }
            let actionReplacementOwner: FolderComparisonReplacementOwner?
            if collision == .replaceKeepingBackup, destination != nil {
                guard let replacementOwner else {
                    throw FolderComparisonWorkflowError.replacementOwnerRequired
                }
                actionReplacementOwner = replacementOwner
            } else {
                actionReplacementOwner = nil
            }
            actions.append(
                FolderComparisonPlannedFileAction(
                    resultID: result.id,
                    kind: kind,
                    sourceSide: sourceSide,
                    sourceRoot: FolderComparisonActionRootBinding(root: roots[sourceSide]),
                    source: source,
                    sourceRevision: sourceRevision,
                    destinationSide: destinationSide,
                    destinationRoot: FolderComparisonActionRootBinding(root: roots[destinationSide]),
                    destination: destination,
                    destinationPrecondition: destinationPrecondition,
                    destinationRelativePath: destinationRelativePath,
                    collision: collision,
                    replacementOwner: actionReplacementOwner
                )
            )
        }
        guard actions.count <= limits.maximumOperationActions else {
            throw FolderComparisonWorkflowError.tooManyOperationActions(
                maximum: limits.maximumOperationActions
            )
        }
        guard actions.count == 1 else {
            throw FolderComparisonWorkflowError.unsupportedOperationBatch
        }
        return actions
    }

    fileprivate static func validateOperable(_ metadata: DirectoryEntryMetadata, id: DirectoryResult.ID) throws {
        guard metadata.kind == .file else {
            throw FolderComparisonWorkflowError.unsupportedResultItem(id)
        }
    }

    fileprivate static func absenceWitness(
        for relativePath: String,
        destinationSide: FolderComparisonWorkflowSide,
        sideRevisionsByPath: [FolderComparisonWorkflowSide: [String: FolderComparisonItemRevision]],
        roots: FolderComparisonRootPair,
        caseSensitivity: FolderPathCaseSensitivitySelection,
        work: inout FolderComparisonWorkflowWork
    ) throws -> FolderComparisonAbsenceWitness {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        let parent: FolderComparisonParentRevision
        if components.count == 1 {
            parent = .root(roots[destinationSide].revision)
        } else {
            let parentPath = components.dropLast().joined(separator: "/")
            let normalizedParentPath = try normalizedPath(
                parentPath,
                caseSensitivity: caseSensitivity,
                work: &work
            )
            guard let parentRevision = sideRevisionsByPath[destinationSide]?[normalizedParentPath],
                parentRevision.kind == .directory,
                parentRevision.identity.rootIdentity == roots[destinationSide].revision.identity
            else {
                throw FolderComparisonWorkflowError.missingDestinationParent(
                    side: destinationSide,
                    relativePath: relativePath
                )
            }
            parent = .directory(parentRevision)
        }
        return FolderComparisonAbsenceWitness(
            parent: parent,
            relativePath: relativePath,
            normalizedRelativePath: try normalizedPath(
                relativePath,
                caseSensitivity: caseSensitivity,
                work: &work
            )
        )
    }

    fileprivate static func sideRevisionIndex(
        _ revisions: Dictionary<DirectoryResult.ID, FolderComparisonResultRevision>.Values,
        roots: FolderComparisonRootPair,
        work: inout FolderComparisonWorkflowWork
    ) throws -> [FolderComparisonWorkflowSide: [String: FolderComparisonItemRevision]] {
        var index: [FolderComparisonWorkflowSide: [String: FolderComparisonItemRevision]] = [
            .left: [:], .right: [:]
        ]
        for revision in revisions {
            try work.consume(1)
            for side in FolderComparisonWorkflowSide.allCases {
                if let item = revision[side] {
                    let key = try normalizedPath(
                        item.identity.relativePath,
                        caseSensitivity: roots[side].pathCaseSensitivity,
                        work: &work
                    )
                    index[side]![key] = item
                }
            }
        }
        return index
    }

    fileprivate static func provesAbsent(
        _ relativePath: String,
        side: FolderComparisonWorkflowSide,
        sideRevisionsByPath: [FolderComparisonWorkflowSide: [String: FolderComparisonItemRevision]],
        roots: FolderComparisonRootPair,
        work: inout FolderComparisonWorkflowWork
    ) throws -> Bool {
        let key = try normalizedPath(
            relativePath,
            caseSensitivity: roots[side].pathCaseSensitivity,
            work: &work
        )
        return sideRevisionsByPath[side]?[key] == nil
    }

    fileprivate static func normalizedPath(
        _ path: String,
        caseSensitivity: FolderPathCaseSensitivitySelection,
        work: inout FolderComparisonWorkflowWork
    ) throws -> String {
        try work.consume(path.utf8.count)
        do {
            return try FolderComparator.normalize(
                relativePath: path,
                caseSensitivity: caseSensitivity.comparatorValue
            )
        } catch {
            throw FolderComparisonWorkflowError.invalidResultPath(
                DirectoryResult.ID(leftRelativePath: path, rightRelativePath: nil)
            )
        }
    }

    fileprivate static func timestampMatches(_ date: Date, seconds: Int64, nanoseconds: Int32) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite,
            (0...999_999_999).contains(nanoseconds)
        else { return false }
        let unixTime = date.timeIntervalSince1970
        let wholeSeconds = floor(unixTime)
        guard let expectedSeconds = Int64(exactly: wholeSeconds) else { return false }
        let fractionalNanoseconds = (unixTime - wholeSeconds) * 1_000_000_000
        guard let expectedNanoseconds = Int64(exactly: fractionalNanoseconds.rounded()) else {
            return false
        }
        return seconds == expectedSeconds
            && abs(expectedNanoseconds - Int64(nanoseconds)) <= 1_000
    }

    fileprivate static func samePhysicalIdentity(
        _ left: FolderComparisonRootIdentity,
        _ right: FolderComparisonRootIdentity
    ) -> Bool {
        left.deviceID == right.deviceID
            && left.fileID == right.fileID
            && left.generation == right.generation
    }

    fileprivate static func metadata(
        _ result: DirectoryResult,
        side: FolderComparisonWorkflowSide
    ) -> DirectoryEntryMetadata? {
        switch side {
        case .left: result.left
        case .right: result.right
        }
    }

    fileprivate static func opposite(_ side: FolderComparisonWorkflowSide) -> FolderComparisonWorkflowSide {
        side == .left ? .right : .left
    }

    fileprivate static func validateActivity(
        _ activity: FolderComparisonActivitySnapshot,
        limits: FolderComparisonWorkflowLimits,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        let progress = activity.progress
        guard progress.completedUnits <= limits.maximumWorkUnits,
            progress.totalUnits.map({ $0 <= limits.maximumWorkUnits && progress.completedUnits <= $0 }) ?? true,
            progress.completedItems >= 0,
            progress.completedItems <= limits.maximumResultItems,
            progress.totalItems.map({
                $0 >= 0 && $0 <= limits.maximumResultItems && progress.completedItems <= $0
            }) ?? true
        else {
            throw FolderComparisonWorkflowError.invalidActivityProgress
        }
        if let path = progress.currentRelativePath {
            guard try work.measure(path) <= limits.maximumStringUTF8Bytes,
                !path.contains("\0")
            else {
                throw FolderComparisonWorkflowError.invalidActivityProgress
            }
        }
    }

    fileprivate static func stableSort(
        _ values: [(offset: Int, result: DirectoryResult)],
        descriptors: [FolderComparisonPresentationSortDescriptor],
        work: inout FolderComparisonWorkflowWork
    ) throws -> [(offset: Int, result: DirectoryResult)] {
        try stableMergeSort(values, work: &work) { left, right, work in
            for descriptor in descriptors {
                let ordering = try compare(
                    left.result,
                    right.result,
                    key: descriptor.key,
                    work: &work
                )
                guard ordering != .same else { continue }
                return descriptor.order == .ascending
                    ? ordering == .before
                    : ordering == .after
            }
            return left.offset < right.offset
        }
    }

    fileprivate static func stableSortResultsByPath(
        _ values: [DirectoryResult],
        work: inout FolderComparisonWorkflowWork
    ) throws -> [DirectoryResult] {
        try stableMergeSort(values, work: &work) { left, right, work in
            let path = try compareUTF8(left.relativePath, right.relativePath, work: &work)
            guard path == .same else { return path == .before }
            let leftPath = try compareOptionalUTF8(
                left.id.leftRelativePath,
                right.id.leftRelativePath,
                work: &work
            )
            guard leftPath == .same else { return leftPath == .before }
            return try compareOptionalUTF8(
                left.id.rightRelativePath,
                right.id.rightRelativePath,
                work: &work
            ) == .before
        }
    }

    fileprivate static func stableMergeSort<Element>(
        _ values: [Element],
        work: inout FolderComparisonWorkflowWork,
        precedes: (Element, Element, inout FolderComparisonWorkflowWork) throws -> Bool
    ) throws -> [Element] {
        guard values.count > 1 else { return values }
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
                while left < middle, right < upper {
                    try work.consume(1)
                    if try precedes(source[right], source[left], &work) {
                        destination[output] = source[right]
                        right += 1
                    } else {
                        destination[output] = source[left]
                        left += 1
                    }
                    output += 1
                }
                while left < middle {
                    try work.consume(1)
                    destination[output] = source[left]
                    left += 1
                    output += 1
                }
                while right < upper {
                    try work.consume(1)
                    destination[output] = source[right]
                    right += 1
                    output += 1
                }
                lower = upper
            }
            swap(&source, &destination)
            let roundedHalf = source.count / 2 + source.count % 2
            width = width >= roundedHalf ? source.count : width * 2
        }
        return source
    }

    fileprivate static func compare(
        _ left: DirectoryResult,
        _ right: DirectoryResult,
        key: FolderComparisonPresentationSortKey,
        work: inout FolderComparisonWorkflowWork
    ) throws -> FolderComparisonOrdering {
        switch key {
        case .path:
            return try compareUTF8(left.relativePath, right.relativePath, work: &work)
        case .status:
            try work.consume(1)
            return compareOptional(left.status.rawValue, right.status.rawValue)
        case .kind:
            try work.consume(1)
            return compareOptional(left.kind?.rawValue, right.kind?.rawValue)
        case .leftSize:
            try work.consume(1)
            return compareOptional(left.left?.byteCount, right.left?.byteCount)
        case .rightSize:
            try work.consume(1)
            return compareOptional(left.right?.byteCount, right.right?.byteCount)
        case .leftModificationDate:
            try work.consume(1)
            return compareDates(left.left?.modificationDate, right.left?.modificationDate)
        case .rightModificationDate:
            try work.consume(1)
            return compareDates(left.right?.modificationDate, right.right?.modificationDate)
        }
    }

    fileprivate static func compareOptional<T: Comparable>(_ left: T?, _ right: T?) -> FolderComparisonOrdering {
        switch (left, right) {
        case (nil, nil): .same
        case (nil, .some): .after
        case (.some, nil): .before
        case (let left?, let right?) where left < right: .before
        case (let left?, let right?) where left > right: .after
        default: .same
        }
    }

    fileprivate static func compareDates(_ left: Date?, _ right: Date?) -> FolderComparisonOrdering {
        compareOptional(left.map(dateOrderKey), right.map(dateOrderKey))
    }

    fileprivate static func dateOrderKey(_ date: Date) -> UInt64 {
        let bits = date.timeIntervalSinceReferenceDate.bitPattern
        let signMask = UInt64(1) << 63
        return bits & signMask == 0 ? bits | signMask : ~bits
    }

    fileprivate static func compareOptionalUTF8(
        _ left: String?,
        _ right: String?,
        work: inout FolderComparisonWorkflowWork
    ) throws -> FolderComparisonOrdering {
        switch (left, right) {
        case (nil, nil): return .same
        case (nil, .some): return .after
        case (.some, nil): return .before
        case (let left?, let right?): return try compareUTF8(left, right, work: &work)
        }
    }

    fileprivate static func compareUTF8(
        _ left: String,
        _ right: String,
        work: inout FolderComparisonWorkflowWork
    ) throws -> FolderComparisonOrdering {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        while true {
            try work.consume(1)
            switch (leftIterator.next(), rightIterator.next()) {
            case (nil, nil): return .same
            case (nil, .some): return .before
            case (.some, nil): return .after
            case (let leftByte?, let rightByte?) where leftByte < rightByte: return .before
            case (let leftByte?, let rightByte?) where leftByte > rightByte: return .after
            default: continue
            }
        }
    }
}

private enum FolderComparisonOrdering {
    case before
    case same
    case after
}

private struct FolderComparisonPhysicalIdentity: Hashable {
    let deviceID: UInt64
    let fileID: UInt64
    let generation: UInt32

    init(_ identity: FolderComparisonItemIdentity) {
        deviceID = identity.deviceID
        fileID = identity.fileID
        generation = identity.generation
    }

    init(_ identity: FolderComparisonRootIdentity) {
        deviceID = identity.deviceID
        fileID = identity.fileID
        generation = identity.generation
    }
}

private struct FolderComparisonNormalizedResultID: Hashable {
    let left: String?
    let right: String?

    init(
        result: DirectoryResult,
        caseSensitivity: FolderPathCaseSensitivitySelection,
        work: inout FolderComparisonWorkflowWork
    ) throws {
        left = try result.left.map {
            try FolderComparisonWorkflowPlanner.normalizedPath(
                $0.relativePath,
                caseSensitivity: caseSensitivity,
                work: &work
            )
        }
        right = try result.right.map {
            try FolderComparisonWorkflowPlanner.normalizedPath(
                $0.relativePath,
                caseSensitivity: caseSensitivity,
                work: &work
            )
        }
    }
}

private struct FolderComparisonTreePath: Hashable {
    let side: FolderComparisonWorkflowSide
    let relativePath: String
}

private struct FolderComparisonTreeParent {
    let id: DirectoryResult.ID
    let relativePath: String
}

private struct FolderComparisonWorkflowWork {
    let limits: FolderComparisonWorkflowLimits
    private(set) var consumed: UInt64 = 0
    private var stringsUTF8Bytes = 0
    private var unitsSinceCancellation = 0

    init(limits: FolderComparisonWorkflowLimits) {
        self.limits = limits
    }

    mutating func consume(_ units: Int) throws {
        guard units >= 0, let units = UInt64(exactly: units) else {
            throw FolderComparisonWorkflowError.workLimitExceeded(
                maximumUnits: limits.maximumWorkUnits
            )
        }
        let sum = consumed.addingReportingOverflow(units)
        guard !sum.overflow, sum.partialValue <= limits.maximumWorkUnits else {
            throw FolderComparisonWorkflowError.workLimitExceeded(
                maximumUnits: limits.maximumWorkUnits
            )
        }
        consumed = sum.partialValue
        unitsSinceCancellation += min(Int(units), limits.cancellationCheckInterval)
        if unitsSinceCancellation >= limits.cancellationCheckInterval {
            try checkCancellation()
            unitsSinceCancellation = 0
        }
    }

    mutating func measure(_ value: String) throws -> Int {
        var count = 0
        for _ in value.utf8 {
            guard count < limits.maximumStringUTF8Bytes else {
                return limits.maximumStringUTF8Bytes + 1
            }
            count += 1
            try consume(1)
        }
        let total = stringsUTF8Bytes.addingReportingOverflow(count)
        guard !total.overflow, total.partialValue <= limits.maximumTotalStringUTF8Bytes else {
            throw FolderComparisonWorkflowError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        stringsUTF8Bytes = total.partialValue
        return count
    }

    mutating func checkCancellation() throws {
        try Task.checkCancellation()
    }
}

private struct FolderComparisonCanonicalDigest {
    private var digest = SHA256()

    mutating func append(_ value: Bool) {
        appendByte(value ? 1 : 0)
    }

    mutating func append(_ value: Int) {
        append(Int64(value))
    }

    mutating func append(_ value: UInt32) {
        append(UInt64(value))
    }

    mutating func append(_ value: UInt64) {
        appendFixedWidth(value.bigEndian)
    }

    mutating func append(_ value: Int64) {
        appendFixedWidth(UInt64(bitPattern: value).bigEndian)
    }

    mutating func append(_ value: Double) {
        append(value.bitPattern)
    }

    mutating func append(_ value: UUID) {
        var uuid = value.uuid
        withUnsafeBytes(of: &uuid) { digest.update(bufferPointer: $0) }
    }

    mutating func append(_ value: String) {
        let bytes = Array(value.utf8)
        append(UInt64(bytes.count))
        digest.update(data: Data(bytes))
    }

    mutating func append(_ value: [UInt8]) {
        append(UInt64(value.count))
        digest.update(data: Data(value))
    }

    mutating func appendOptional(_ value: String?) {
        append(value != nil)
        if let value { append(value) }
    }

    mutating func appendOptional(_ value: UInt64?) {
        append(value != nil)
        if let value { append(value) }
    }

    mutating func appendOptional(_ value: Date?) {
        append(value != nil)
        if let value { append(value.timeIntervalSinceReferenceDate) }
    }

    mutating func finalize() -> [UInt8] {
        Array(digest.finalize())
    }

    private mutating func appendByte(_ value: UInt8) {
        var value = value
        withUnsafeBytes(of: &value) { digest.update(bufferPointer: $0) }
    }

    private mutating func appendFixedWidth(_ value: UInt64) {
        var value = value
        withUnsafeBytes(of: &value) { digest.update(bufferPointer: $0) }
    }
}

private func append(_ roots: FolderComparisonRootPair, to digest: inout FolderComparisonCanonicalDigest) {
    append(roots.left, to: &digest)
    append(roots.right, to: &digest)
}

private func append(_ root: FolderComparisonRoot, to digest: inout FolderComparisonCanonicalDigest) {
    digest.append(root.requestedURL.absoluteString)
    append(root.revision, to: &digest)
    append(root.authority, to: &digest)
    digest.append(root.pathCaseSensitivity.rawValue)
}

private func append(
    _ identity: FolderComparisonRootIdentity,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(identity.canonicalURL.absoluteString)
    digest.append(identity.deviceID)
    digest.append(identity.fileID)
    digest.append(identity.generation)
}

private func append(
    _ revision: FolderComparisonRootRevision,
    to digest: inout FolderComparisonCanonicalDigest
) {
    append(revision.identity, to: &digest)
    digest.append(revision.linkCount)
    digest.append(UInt64(revision.permissions))
    digest.append(UInt64(revision.ownerID))
    digest.append(UInt64(revision.groupID))
    digest.append(UInt64(revision.flags))
    digest.append(revision.modificationTimeSeconds)
    digest.append(Int64(revision.modificationTimeNanoseconds))
    digest.append(revision.statusChangeTimeSeconds)
    digest.append(Int64(revision.statusChangeTimeNanoseconds))
    digest.append(revision.metadataSHA256)
}

private func append(
    _ authority: FolderComparisonAccessAuthority,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(authority.identity)
    digest.append(authority.revision)
    append(authority.rootIdentity, to: &digest)
    let permissions = authority.permissions.sorted { $0.rawValue < $1.rawValue }
    digest.append(permissions.count)
    for permission in permissions { digest.append(permission.rawValue) }
    digest.append(authority.coverage.rawValue)
    switch authority.acquisition {
    case .ambient:
        digest.append("ambient")
    case .callerManagedWhenRequired:
        digest.append("caller-managed")
    case .securityScoped(let resourceURL, let coverage):
        digest.append("security-scoped")
        digest.append(resourceURL.absoluteString)
        digest.append(coverage.rawValue)
    }
}

private func append(
    _ intent: FolderComparisonScanIntent,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(intent.recursive)
    digest.append(intent.options.hiddenFilePolicy.rawValue)
    digest.append(intent.options.symbolicLinkPolicy.rawValue)
    digest.append(intent.options.errorPolicy.rawValue)
    let limits = intent.options.limits
    digest.append(limits.maximumDepth)
    digest.append(limits.maximumEntries)
    digest.append(limits.maximumExaminedEntries)
    digest.append(limits.maximumIssues)
    digest.append(limits.maximumOpenDirectoryDescriptors)
    digest.append(limits.maximumPendingEntryNames)
    digest.append(limits.maximumRelativePathUTF8Bytes)
    digest.append(limits.maximumTotalAccountedBytes)
    digest.append(intent.filenameFilter != nil)
    if let filter = intent.filenameFilter { append(filter, to: &digest) }
}

private func append(
    _ filter: FolderComparisonScanFilter,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(filter.defaultDecision.rawValue)
    digest.append(filter.matchSemantics.rawValue)
    digest.append(filter.casePolicy.rawValue)
    digest.append(filter.rules.count)
    for rule in filter.rules {
        digest.append(rule.decision.rawValue)
        switch rule.pattern {
        case .glob(let source):
            digest.append("glob")
            digest.append(source)
        case .regularExpression(let source):
            digest.append("regular-expression")
            digest.append(source)
        }
        digest.append(rule.applicability.rawValue)
    }
    let limits = filter.limits
    digest.append(limits.maximumRuleCount)
    digest.append(limits.maximumPatternUTF8Bytes)
    digest.append(limits.maximumTotalPatternUTF8Bytes)
    digest.append(limits.maximumRelativePathUTF8Bytes)
    digest.append(limits.maximumCompiledStateCount)
    digest.append(limits.maximumMatchWork)
    digest.append(limits.maximumRegularExpressionNestingDepth)
    digest.append(limits.maximumRegularExpressionRepetition)
}

private func append(
    _ settings: FolderComparisonSettings,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(settings.method.rawValue)
    digest.append(settings.pathCaseSensitivity.rawValue)
    digest.append(settings.modificationDateTolerance)
}

private func append(
    _ capabilities: FolderComparisonWorkflowCapabilities,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(capabilities.identity)
    digest.append(capabilities.revision)
    let features = capabilities.features.sorted { $0.rawValue < $1.rawValue }
    digest.append(features.count)
    for feature in features { digest.append(feature.rawValue) }
}

private func append(
    _ reference: FolderComparisonWorkflowSnapshotReference,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(reference.identity.rawValue)
    digest.append(reference.generation)
    append(reference.owner, to: &digest)
    append(reference.roots, to: &digest)
    append(reference.scanIntent, to: &digest)
    append(reference.comparisonSettings, to: &digest)
    digest.append(reference.contentSHA256)
}

private func append(_ result: DirectoryResult, to digest: inout FolderComparisonCanonicalDigest) {
    append(result.id, to: &digest)
    append(result.left, to: &digest)
    append(result.right, to: &digest)
    digest.append(UInt64(result.status.rawValue))
}

private func append(_ id: DirectoryResult.ID, to digest: inout FolderComparisonCanonicalDigest) {
    digest.appendOptional(id.leftRelativePath)
    digest.appendOptional(id.rightRelativePath)
}

private func append(
    _ metadata: DirectoryEntryMetadata?,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(metadata != nil)
    guard let metadata else { return }
    digest.append(metadata.relativePath)
    digest.append(UInt64(metadata.kind.rawValue))
    digest.appendOptional(metadata.byteCount)
    digest.appendOptional(metadata.modificationDate)
    digest.append(metadata.isHidden)
}

private func append(
    _ revision: FolderComparisonResultRevision,
    to digest: inout FolderComparisonCanonicalDigest
) {
    append(revision.id, to: &digest)
    append(revision.left, to: &digest)
    append(revision.right, to: &digest)
}

private func append(
    _ revision: FolderComparisonItemRevision?,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(revision != nil)
    if let revision { append(revision, to: &digest) }
}

private func append(
    _ revision: FolderComparisonItemRevision,
    to digest: inout FolderComparisonCanonicalDigest
) {
    append(revision.identity.rootIdentity, to: &digest)
    digest.append(revision.identity.relativePath)
    digest.append(revision.identity.deviceID)
    digest.append(revision.identity.fileID)
    digest.append(revision.identity.generation)
    digest.append(UInt64(revision.kind.rawValue))
    digest.appendOptional(revision.byteCount)
    digest.append(revision.linkCount)
    digest.append(UInt64(revision.permissions))
    digest.append(UInt64(revision.ownerID))
    digest.append(UInt64(revision.groupID))
    digest.append(UInt64(revision.flags))
    digest.append(revision.modificationTimeSeconds)
    digest.append(Int64(revision.modificationTimeNanoseconds))
    digest.append(revision.statusChangeTimeSeconds)
    digest.append(Int64(revision.statusChangeTimeNanoseconds))
    digest.append(revision.metadataSHA256)
    digest.append(revision.contentSHA256 != nil)
    if let contentSHA256 = revision.contentSHA256 { digest.append(contentSHA256) }
}

private func append(
    _ configuration: FolderComparisonPresentationConfiguration,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(configuration.mode.rawValue)
    digest.append(configuration.columns.count)
    for column in configuration.columns { digest.append(column.rawValue) }
    let statuses = configuration.filter.statuses.sorted { $0.rawValue < $1.rawValue }
    digest.append(statuses.count)
    for status in statuses { digest.append(UInt64(status.rawValue)) }
    let kinds = configuration.filter.kinds.sorted { $0.rawValue < $1.rawValue }
    digest.append(kinds.count)
    for kind in kinds { digest.append(UInt64(kind.rawValue)) }
    digest.append(configuration.filter.hidden.rawValue)
    digest.append(configuration.filter.pathQuery)
    digest.append(configuration.sortDescriptors.count)
    for descriptor in configuration.sortDescriptors {
        digest.append(descriptor.key.rawValue)
        digest.append(descriptor.order.rawValue)
    }
}

private func append(
    _ row: FolderComparisonPresentationRow,
    to digest: inout FolderComparisonCanonicalDigest
) {
    append(row.id, to: &digest)
    digest.append(row.relativePath)
    digest.appendOptional(row.treeParentRelativePath)
    digest.append(row.treeParentID != nil)
    if let parentID = row.treeParentID { append(parentID, to: &digest) }
    digest.append(row.treeDepth)
    digest.append(row.stateIcon.rawValue)
    digest.append(UInt64(row.status.rawValue))
    digest.append(row.kind != nil)
    if let kind = row.kind { digest.append(UInt64(kind.rawValue)) }
    append(row.left, to: &digest)
    append(row.right, to: &digest)
}

private func append(
    _ value: FolderComparisonPresentationSideValue?,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(value != nil)
    guard let value else { return }
    digest.append(value.relativePath)
    digest.append(UInt64(value.kind.rawValue))
    digest.appendOptional(value.byteCount)
    digest.appendOptional(value.modificationDate)
    digest.append(value.isHidden)
}

private func append(
    _ action: FolderComparisonPlannedFileAction,
    to digest: inout FolderComparisonCanonicalDigest
) {
    append(action.resultID, to: &digest)
    digest.append(action.kind.rawValue)
    digest.appendOptional(action.sourceSide?.rawValue)
    append(action.sourceRoot, to: &digest)
    append(action.source, to: &digest)
    append(action.sourceRevision, to: &digest)
    digest.append(action.destinationSide.rawValue)
    append(action.destinationRoot, to: &digest)
    append(action.destination, to: &digest)
    append(action.destinationPrecondition, to: &digest)
    digest.append(action.destinationRelativePath)
    digest.appendOptional(action.collision?.rawValue)
    append(action.replacementOwner, to: &digest)
}

private func append(
    _ binding: FolderComparisonActionRootBinding?,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(binding != nil)
    if let binding { append(binding, to: &digest) }
}

private func append(
    _ binding: FolderComparisonActionRootBinding,
    to digest: inout FolderComparisonCanonicalDigest
) {
    append(binding.identity, to: &digest)
    append(binding.preEffectRevision, to: &digest)
    digest.append(binding.authorityIdentity)
    digest.append(binding.authorityRevision)
}

private func append(
    _ precondition: FolderComparisonDestinationPrecondition,
    to digest: inout FolderComparisonCanonicalDigest
) {
    switch precondition {
    case .existing(let revision):
        digest.append("existing")
        append(revision, to: &digest)
    case .absent(let witness):
        digest.append("absent")
        switch witness.parent {
        case .root(let revision):
            digest.append("root")
            append(revision, to: &digest)
        case .directory(let revision):
            digest.append("directory")
            append(revision, to: &digest)
        }
        digest.append(witness.relativePath)
        digest.append(witness.normalizedRelativePath)
    }
}

private func append(
    _ owner: FolderComparisonWorkflowSnapshotOwner,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(owner.identity)
    digest.append(owner.revision)
}

private func append(
    _ owner: FolderComparisonReplacementOwner?,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(owner != nil)
    guard let owner else { return }
    digest.append(owner.identity)
    digest.append(owner.revision)
}

private func append(
    _ limits: FolderComparisonWorkflowLimits,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(limits.maximumResultItems)
    digest.append(limits.maximumSelectedItems)
    digest.append(limits.maximumOperationActions)
    digest.append(limits.maximumPresentationRows)
    digest.append(limits.maximumColumns)
    digest.append(limits.maximumSortDescriptors)
    digest.append(limits.maximumFilterRules)
    digest.append(limits.maximumStringUTF8Bytes)
    digest.append(limits.maximumTotalStringUTF8Bytes)
    digest.append(limits.maximumMetadataDigestBytes)
    digest.append(limits.maximumWorkUnits)
    digest.append(limits.cancellationCheckInterval)
}

private func append(
    _ activity: FolderComparisonActivitySnapshot,
    to digest: inout FolderComparisonCanonicalDigest
) {
    digest.append(activity.identity)
    digest.append(activity.revision)
    digest.append(activity.kind.rawValue)
    digest.append(activity.state.rawValue)
    let controls = activity.supportedControls.sorted { $0.rawValue < $1.rawValue }
    digest.append(controls.count)
    for control in controls { digest.append(control.rawValue) }
    digest.append(activity.progress.completedUnits)
    digest.append(activity.progress.totalUnits != nil)
    if let total = activity.progress.totalUnits { digest.append(total) }
    digest.append(activity.progress.completedItems)
    digest.append(activity.progress.totalItems != nil)
    if let total = activity.progress.totalItems { digest.append(total) }
    digest.appendOptional(activity.progress.currentRelativePath)
}
