import CryptoKit
import Foundation

/// Bounded UI-independent commit/rollback planner for folder file operations.
///
/// Planning validates `FolderFileOperationPlan` values against caller-pinned descriptor-relative
/// state. It performs no filesystem access, no mutation, and no executor wiring. Executors must
/// hold every bound revision stable from planning through publication and enforce the accompanying
/// executor contract with descriptor-relative, no-follow access.
public enum FolderOperationCommitItemKind: String, CaseIterable, Hashable, Sendable {
    case file
    case directory
}

public struct FolderOperationCommitRootIdentity: Hashable, Sendable {
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

public struct FolderOperationCommitRootRevision: Hashable, Sendable {
    public let identity: FolderOperationCommitRootIdentity
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

    public init(
        identity: FolderOperationCommitRootIdentity,
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

public struct FolderOperationCommitPinnedRoot: Hashable, Sendable {
    public let requestedURL: URL
    public let revision: FolderOperationCommitRootRevision

    public init(requestedURL: URL, revision: FolderOperationCommitRootRevision) {
        self.requestedURL = requestedURL
        self.revision = revision
    }
}

public struct FolderOperationCommitItemIdentity: Hashable, Sendable {
    public let rootIdentity: FolderOperationCommitRootIdentity
    public let relativePath: String
    public let deviceID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    public init(
        rootIdentity: FolderOperationCommitRootIdentity,
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

public struct FolderOperationCommitItemRevision: Hashable, Sendable {
    public let identity: FolderOperationCommitItemIdentity
    public let kind: FolderOperationCommitItemKind
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
        identity: FolderOperationCommitItemIdentity,
        kind: FolderOperationCommitItemKind,
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
        contentSHA256: [UInt8]?
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

public struct FolderOperationCommitSnapshot: Hashable, Sendable {
    public let roots: [FolderOperationCommitPinnedRoot]
    public let items: [FolderOperationCommitItemRevision]

    public init(roots: [FolderOperationCommitPinnedRoot], items: [FolderOperationCommitItemRevision]) {
        self.roots = roots
        self.items = items
    }
}

public enum FolderOperationCommitLimit: String, CaseIterable, Hashable, Sendable {
    case steps
    case pinnedItems
    case pathBytes
    case totalPathBytes
    case workUnits
    case planOutputBytes
}

public struct FolderOperationCommitLimits: Hashable, Sendable {
    public static let hardMaximumSteps = 4_096
    public static let hardMaximumPinnedItems = 65_536
    public static let hardMaximumPathBytes = 64 * 1_024
    public static let hardMaximumTotalPathBytes = 16 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let hardMaximumPlanOutputBytes = 64 * 1_024 * 1_024
    public static let `default` = FolderOperationCommitLimits()

    public let maximumSteps: Int
    public let maximumPinnedItems: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumWorkUnits: UInt64
    public let maximumPlanOutputBytes: Int

    public init(
        maximumSteps: Int = 256,
        maximumPinnedItems: Int = 8_192,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 64 * 1_024 * 1_024,
        maximumPlanOutputBytes: Int = 4 * 1_024 * 1_024
    ) {
        self.maximumSteps = maximumSteps
        self.maximumPinnedItems = maximumPinnedItems
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumPlanOutputBytes = maximumPlanOutputBytes
    }
}

public enum FolderOperationCommitError: Error, LocalizedError, Equatable, Hashable, Sendable {
    case cancelled
    case invalidLimit(FolderOperationCommitLimit)
    case emptyPlan
    case tooManySteps(maximum: Int)
    case tooManyPinnedItems(maximum: Int)
    case pathTooLarge(maximumBytes: Int)
    case totalPathsTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumUnits: UInt64)
    case planOutputTooLarge(maximumBytes: Int)
    case invalidRootURL
    case unknownRoot
    case conflictingRootIdentity
    case invalidItemRevision
    case itemRevisionMismatch
    case missingSourceRevision(step: Int)
    case missingTargetRevision(step: Int)
    case missingDestinationParent(step: Int)
    case destinationCollision(step: Int)
    case sourceDestinationOverlap(step: Int)
    case conflictingPlan(firstStep: Int, secondStep: Int)
    case readDependencyViolation(firstStep: Int, secondStep: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Folder operation commit planning was cancelled before completion."
        case .invalidLimit(let limit):
            "Invalid folder operation commit limit: \(limit.rawValue)."
        case .emptyPlan:
            "Folder operation commit plan contains no steps."
        case .tooManySteps(let maximum):
            "Folder operation commit exceeds the \(maximum)-step limit."
        case .tooManyPinnedItems(let maximum):
            "Folder operation commit snapshot exceeds the \(maximum)-item limit."
        case .pathTooLarge(let maximumBytes):
            "A folder operation commit path exceeds the \(maximumBytes)-byte limit."
        case .totalPathsTooLarge(let maximumBytes):
            "Folder operation commit paths exceed the \(maximumBytes)-byte aggregate limit."
        case .workLimitExceeded(let maximumUnits):
            "Folder operation commit planning exceeds the \(maximumUnits)-unit work limit."
        case .planOutputTooLarge(let maximumBytes):
            "Folder operation commit output exceeds the \(maximumBytes)-byte limit."
        case .invalidRootURL:
            "Folder operation commit root is not a strict absolute local file URL: <redacted>."
        case .unknownRoot:
            "Folder operation commit references a root without a pinned revision: <redacted>."
        case .conflictingRootIdentity:
            "Folder operation commit snapshot contains conflicting root identities: <redacted>."
        case .invalidItemRevision:
            "Folder operation commit snapshot contains an invalid item revision: <redacted>."
        case .itemRevisionMismatch:
            "Folder operation commit snapshot revisions do not match their pinned roots: <redacted>."
        case .missingSourceRevision(let step):
            "Folder operation commit step \(step) has no pinned source revision: <redacted>."
        case .missingTargetRevision(let step):
            "Folder operation commit step \(step) has no pinned target revision: <redacted>."
        case .missingDestinationParent(let step):
            "Folder operation commit step \(step) has no pinned destination parent: <redacted>."
        case .destinationCollision(let step):
            "Folder operation commit step \(step) collides with an existing destination: <redacted>."
        case .sourceDestinationOverlap(let step):
            "Folder operation commit step \(step) overlaps its own source and destination: <redacted>."
        case .conflictingPlan(let firstStep, let secondStep):
            "Folder operation commit steps \(firstStep) and \(secondStep) write overlapping slots: <redacted>."
        case .readDependencyViolation(let firstStep, let secondStep):
            "Folder operation commit step \(secondStep) reads a slot written by step \(firstStep): <redacted>."
        }
    }
}

public struct FolderOperationCommitStep: Hashable, Sendable {
    public let index: Int
    public let kind: FolderFileOperationKind
    public let sourceRoot: FolderOperationCommitRootIdentity?
    public let sourceRelativePath: String?
    public let sourceExpected: FolderOperationCommitItemRevision?
    public let sourceParent: FolderOperationCommitItemRevision?
    public let destinationRoot: FolderOperationCommitRootIdentity
    public let destinationRelativePath: String
    public let destinationPrior: FolderOperationCommitItemRevision?
    public let destinationParent: FolderOperationCommitItemRevision?
    public let collisionPolicy: FolderFileCollisionPolicy?
    public let deletionPolicy: FolderFileDeletionPolicy?
    public let replacesExisting: Bool
    public let skipsExisting: Bool

    public init(
        index: Int,
        kind: FolderFileOperationKind,
        sourceRoot: FolderOperationCommitRootIdentity?,
        sourceRelativePath: String?,
        sourceExpected: FolderOperationCommitItemRevision?,
        sourceParent: FolderOperationCommitItemRevision?,
        destinationRoot: FolderOperationCommitRootIdentity,
        destinationRelativePath: String,
        destinationPrior: FolderOperationCommitItemRevision?,
        destinationParent: FolderOperationCommitItemRevision?,
        collisionPolicy: FolderFileCollisionPolicy?,
        deletionPolicy: FolderFileDeletionPolicy?,
        replacesExisting: Bool,
        skipsExisting: Bool
    ) {
        self.index = index
        self.kind = kind
        self.sourceRoot = sourceRoot
        self.sourceRelativePath = sourceRelativePath
        self.sourceExpected = sourceExpected
        self.sourceParent = sourceParent
        self.destinationRoot = destinationRoot
        self.destinationRelativePath = destinationRelativePath
        self.destinationPrior = destinationPrior
        self.destinationParent = destinationParent
        self.collisionPolicy = collisionPolicy
        self.deletionPolicy = deletionPolicy
        self.replacesExisting = replacesExisting
        self.skipsExisting = skipsExisting
    }
}

public enum FolderOperationRollbackAction: String, CaseIterable, Hashable, Sendable {
    case removePublishedDestination
    case restoreReplacedDestination
    case restoreMovedSource
    case restoreDeletedTarget
}

public struct FolderOperationRollbackStep: Hashable, Sendable {
    public let commitIndex: Int
    public let rollbackOrder: Int
    public let action: FolderOperationRollbackAction
    public let rootIdentity: FolderOperationCommitRootIdentity
    public let relativePath: String
    public let restored: FolderOperationCommitItemRevision?
    public let publishedContentSHA256: [UInt8]?

    public init(
        commitIndex: Int,
        rollbackOrder: Int,
        action: FolderOperationRollbackAction,
        rootIdentity: FolderOperationCommitRootIdentity,
        relativePath: String,
        restored: FolderOperationCommitItemRevision?,
        publishedContentSHA256: [UInt8]?
    ) {
        self.commitIndex = commitIndex
        self.rollbackOrder = rollbackOrder
        self.action = action
        self.rootIdentity = rootIdentity
        self.relativePath = relativePath
        self.restored = restored
        self.publishedContentSHA256 = publishedContentSHA256
    }
}

public struct FolderOperationCommitPlan: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let steps: [FolderOperationCommitStep]

    public init(steps: [FolderOperationCommitStep]) {
        self.steps = steps
    }

    public var description: String {
        "FolderOperationCommitPlan(steps: \(steps.count), paths: <redacted>)"
    }

    public var debugDescription: String {
        "FolderOperationCommitPlan(steps: \(steps.count), paths: <redacted>)"
    }
}

public struct FolderOperationRollbackPlan: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let steps: [FolderOperationRollbackStep]

    public init(steps: [FolderOperationRollbackStep]) {
        self.steps = steps
    }

    public var description: String {
        "FolderOperationRollbackPlan(steps: \(steps.count), paths: <redacted>)"
    }

    public var debugDescription: String {
        "FolderOperationRollbackPlan(steps: \(steps.count), paths: <redacted>)"
    }
}

public struct FolderOperationCommitReceipt: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let planDigestSHA256: [UInt8]
    public let stepDigestsSHA256: [[UInt8]]
    public let stepCount: Int
    public let skippedStepCount: Int
    public let rollbackStepCount: Int

    public init(
        planDigestSHA256: [UInt8],
        stepDigestsSHA256: [[UInt8]],
        stepCount: Int,
        skippedStepCount: Int,
        rollbackStepCount: Int
    ) {
        self.planDigestSHA256 = planDigestSHA256
        self.stepDigestsSHA256 = stepDigestsSHA256
        self.stepCount = stepCount
        self.skippedStepCount = skippedStepCount
        self.rollbackStepCount = rollbackStepCount
    }

    public var description: String {
        "FolderOperationCommitReceipt(steps: \(stepCount), skipped: \(skippedStepCount), rollback: \(rollbackStepCount), digestBytes: \(planDigestSHA256.count), paths: <redacted>)"
    }

    public var debugDescription: String {
        "FolderOperationCommitReceipt(steps: \(stepCount), skipped: \(skippedStepCount), rollback: \(rollbackStepCount), digestBytes: \(planDigestSHA256.count), paths: <redacted>)"
    }
}

public struct FolderOperationCommitBundle: Hashable, Sendable {
    public let commit: FolderOperationCommitPlan
    public let rollback: FolderOperationRollbackPlan
    public let receipt: FolderOperationCommitReceipt

    public init(
        commit: FolderOperationCommitPlan,
        rollback: FolderOperationRollbackPlan,
        receipt: FolderOperationCommitReceipt
    ) {
        self.commit = commit
        self.rollback = rollback
        self.receipt = receipt
    }
}

public enum FolderOperationCommitPathContract: String, Hashable, Sendable {
    case descriptorRelativeNoFollowFromPinnedRoot
}

public enum FolderOperationCommitPublicationContract: String, Hashable, Sendable {
    case privateStageSyncThenExactRevisionCASPublishAndSyncParent
}

public enum FolderOperationCommitTypeContract: String, Hashable, Sendable {
    case regularFileOrDirectoryOnly
}

public enum FolderOperationCommitCancellationContract: String, Hashable, Sendable {
    case noMutationBeforePublicationAndCommittedOrUncertainAfterPublicationStarts
}

public struct FolderOperationCommitExecutorContract: Hashable, Sendable {
    public static let required = FolderOperationCommitExecutorContract()
    public let pathResolution = FolderOperationCommitPathContract.descriptorRelativeNoFollowFromPinnedRoot
    public let publication = FolderOperationCommitPublicationContract.privateStageSyncThenExactRevisionCASPublishAndSyncParent
    public let itemType = FolderOperationCommitTypeContract.regularFileOrDirectoryOnly
    public let cancellation = FolderOperationCommitCancellationContract.noMutationBeforePublicationAndCommittedOrUncertainAfterPublicationStarts

    public init() {}
}

public enum FolderOperationCommitWorkflow: Sendable {
    public static func plan(
        _ operation: FolderFileOperationPlan,
        snapshot: FolderOperationCommitSnapshot,
        limits: FolderOperationCommitLimits = .default
    ) throws -> FolderOperationCommitBundle {
        try checkCancellation()
        try validateLimits(limits)
        var budget = FolderOperationCommitWorkBudget(maximum: limits.maximumWorkUnits)
        let indexed = try indexSnapshot(snapshot, limits: limits, budget: &budget)
        let normalized = try expandOperation(operation, limits: limits, budget: &budget)
        try checkCancellation()
        let steps = try buildSteps(normalized, indexed: indexed, limits: limits, budget: &budget)
        try validateCrossStepConflicts(steps, budget: &budget)
        var rollbackOrder = 0
        let rollback = deriveRollback(steps, order: &rollbackOrder)
        try checkCancellation()
        let receipt = try makeReceipt(steps: steps, rollback: rollback, limits: limits, budget: &budget)
        return FolderOperationCommitBundle(
            commit: FolderOperationCommitPlan(steps: steps),
            rollback: FolderOperationRollbackPlan(steps: rollback),
            receipt: receipt
        )
    }
}

private struct FolderOperationCommitWorkBudget {
    let maximum: UInt64
    var used: UInt64 = 0

    mutating func add(_ amount: UInt64, maximum: UInt64) throws {
        let (partial, overflow) = used.addingReportingOverflow(amount)
        guard !overflow, partial <= maximum else {
            throw FolderOperationCommitError.workLimitExceeded(maximumUnits: maximum)
        }
        used = partial
        if used % 256 == 0 {
            try FolderOperationCommitWorkflow.checkCancellation()
        }
    }
}

private struct FolderOperationCommitNormalizedOperation {
    let index: Int
    let kind: FolderFileOperationKind
    let sourceRoot: URL?
    let source: FolderRelativePath?
    let destinationRoot: URL
    let destination: FolderRelativePath
    let collisionPolicy: FolderFileCollisionPolicy?
    let deletionPolicy: FolderFileDeletionPolicy?
}

private struct FolderOperationCommitIndexedSnapshot {
    let roots: [FolderOperationCommitPinnedRoot]
    let items: [FolderOperationCommitItemRevision]
    let rootMatchKeys: [String]
    let itemsBySlot: [String: Int]
}

private struct FolderOperationCommitSlotAccess {
    let absoluteComponents: [String]
    let identityKey: String?
}

private struct FolderOperationCommitStepAccess {
    let step: Int
    let reads: [FolderOperationCommitSlotAccess]
    let writes: [FolderOperationCommitSlotAccess]
}

extension FolderOperationCommitWorkflow {
    fileprivate static func checkCancellation() throws {
        if Task<Never, Never>.isCancelled {
            throw FolderOperationCommitError.cancelled
        }
    }

    fileprivate static func validateLimits(_ limits: FolderOperationCommitLimits) throws {
        guard limits.maximumSteps >= 0, limits.maximumSteps <= FolderOperationCommitLimits.hardMaximumSteps else {
            throw FolderOperationCommitError.invalidLimit(.steps)
        }
        guard limits.maximumPinnedItems >= 0, limits.maximumPinnedItems <= FolderOperationCommitLimits.hardMaximumPinnedItems else {
            throw FolderOperationCommitError.invalidLimit(.pinnedItems)
        }
        guard limits.maximumPathUTF8Bytes >= 0, limits.maximumPathUTF8Bytes <= FolderOperationCommitLimits.hardMaximumPathBytes else {
            throw FolderOperationCommitError.invalidLimit(.pathBytes)
        }
        guard limits.maximumTotalPathUTF8Bytes >= 0, limits.maximumTotalPathUTF8Bytes <= FolderOperationCommitLimits.hardMaximumTotalPathBytes else {
            throw FolderOperationCommitError.invalidLimit(.totalPathBytes)
        }
        guard limits.maximumPlanOutputBytes >= 0, limits.maximumPlanOutputBytes <= FolderOperationCommitLimits.hardMaximumPlanOutputBytes else {
            throw FolderOperationCommitError.invalidLimit(.planOutputBytes)
        }
        guard limits.maximumWorkUnits <= FolderOperationCommitLimits.hardMaximumWorkUnits else {
            throw FolderOperationCommitError.invalidLimit(.workUnits)
        }
    }

    fileprivate static func validateRootURL(_ url: URL, limits: FolderOperationCommitLimits) throws {
        guard url.isFileURL else {
            throw FolderOperationCommitError.invalidRootURL
        }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= limits.maximumPathUTF8Bytes else {
            throw FolderOperationCommitError.invalidRootURL
        }
    }

    fileprivate static func rootMatchKey(_ url: URL) -> String {
        canonicalFolded(url.standardizedFileURL.path)
    }

    fileprivate static func canonicalFolded(_ value: String) -> String {
        value
            .decomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .decomposedStringWithCanonicalMapping
    }

    fileprivate static func foldedComponents(_ components: [String]) -> [String] {
        components.map { canonicalFolded($0) }
    }

    fileprivate static func absoluteComponents(rootURL: URL, relativeComponents: [String]) -> [String] {
        let rootParts = rootURL.standardizedFileURL.pathComponents.filter { $0 != "/" }.map { canonicalFolded($0) }
        return rootParts + foldedComponents(relativeComponents)
    }

    fileprivate static func isPrefixOrEqual(_ lhs: [String], _ rhs: [String]) -> Bool {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else {
            return true
        }
        for offset in 0..<count {
            if lhs[offset] != rhs[offset] {
                return false
            }
        }
        return true
    }

    fileprivate static func slotKey(rootIdentity: FolderOperationCommitRootIdentity, foldedRelative: String) -> String {
        "\(rootIdentity.deviceID):\(rootIdentity.fileID):\(foldedRelative)"
    }

    fileprivate static func identityKey(deviceID: UInt64, fileID: UInt64, generation: UInt32) -> String {
        "\(deviceID):\(fileID):\(generation)"
    }

    fileprivate static func itemIdentityKey(_ item: FolderOperationCommitItemRevision) -> String {
        identityKey(deviceID: item.identity.deviceID, fileID: item.identity.fileID, generation: item.identity.generation)
    }

    fileprivate static func indexSnapshot(
        _ snapshot: FolderOperationCommitSnapshot,
        limits: FolderOperationCommitLimits,
        budget: inout FolderOperationCommitWorkBudget
    ) throws -> FolderOperationCommitIndexedSnapshot {
        guard !snapshot.roots.isEmpty else {
            throw FolderOperationCommitError.unknownRoot
        }
        guard snapshot.roots.count <= limits.maximumSteps + 1 else {
            throw FolderOperationCommitError.tooManySteps(maximum: limits.maximumSteps)
        }
        guard snapshot.items.count <= limits.maximumPinnedItems else {
            throw FolderOperationCommitError.tooManyPinnedItems(maximum: limits.maximumPinnedItems)
        }
        var matchKeys: [String] = []
        matchKeys.reserveCapacity(snapshot.roots.count)
        var seenIdentities = Set<String>()
        var seenMatchKeys = Set<String>()
        for root in snapshot.roots {
            try budget.add(4, maximum: limits.maximumWorkUnits)
            try validateRootURL(root.revision.identity.canonicalURL, limits: limits)
            try validateRootURL(root.requestedURL, limits: limits)
            guard root.revision.metadataSHA256.count == 32 else {
                throw FolderOperationCommitError.invalidItemRevision
            }
            let identity = root.revision.identity
            let key = identityKey(deviceID: identity.deviceID, fileID: identity.fileID, generation: identity.generation)
            guard seenIdentities.insert(key).inserted else {
                throw FolderOperationCommitError.conflictingRootIdentity
            }
            let matchKey = rootMatchKey(identity.canonicalURL)
            guard seenMatchKeys.insert(matchKey).inserted else {
                throw FolderOperationCommitError.conflictingRootIdentity
            }
            matchKeys.append(matchKey)
        }
        var itemsBySlot: [String: Int] = [:]
        itemsBySlot.reserveCapacity(snapshot.items.count)
        for (offset, item) in snapshot.items.enumerated() {
            try budget.add(8, maximum: limits.maximumWorkUnits)
            if offset % 32 == 0 {
                try checkCancellation()
            }
            guard item.metadataSHA256.count == 32 else {
                throw FolderOperationCommitError.invalidItemRevision
            }
            switch item.kind {
            case .file:
                guard item.byteCount != nil, let digest = item.contentSHA256, digest.count == 32 else {
                    throw FolderOperationCommitError.invalidItemRevision
                }
            case .directory:
                guard item.byteCount == nil, item.contentSHA256 == nil else {
                    throw FolderOperationCommitError.invalidItemRevision
                }
            }
            guard snapshot.roots.contains(where: { $0.revision.identity == item.identity.rootIdentity }) else {
                throw FolderOperationCommitError.itemRevisionMismatch
            }
            guard let parsed = try? FolderRelativePath(item.identity.relativePath) else {
                throw FolderOperationCommitError.invalidItemRevision
            }
            guard item.identity.relativePath.utf8.count <= limits.maximumPathUTF8Bytes else {
                throw FolderOperationCommitError.pathTooLarge(maximumBytes: limits.maximumPathUTF8Bytes)
            }
            let folded = foldedComponents(parsed.components).joined(separator: "/")
            let key = slotKey(rootIdentity: item.identity.rootIdentity, foldedRelative: folded)
            guard itemsBySlot.updateValue(offset, forKey: key) == nil else {
                throw FolderOperationCommitError.itemRevisionMismatch
            }
        }
        return FolderOperationCommitIndexedSnapshot(
            roots: snapshot.roots,
            items: snapshot.items,
            rootMatchKeys: matchKeys,
            itemsBySlot: itemsBySlot
        )
    }

    fileprivate static func expandOperation(
        _ operation: FolderFileOperationPlan,
        limits: FolderOperationCommitLimits,
        budget: inout FolderOperationCommitWorkBudget
    ) throws -> [FolderOperationCommitNormalizedOperation] {
        var normalized: [FolderOperationCommitNormalizedOperation] = []
        switch operation {
        case .copy(let plan):
            normalized.append(
                FolderOperationCommitNormalizedOperation(
                    index: 0,
                    kind: .copy,
                    sourceRoot: plan.sourceRoot,
                    source: plan.source,
                    destinationRoot: plan.destinationRoot,
                    destination: plan.destination,
                    collisionPolicy: plan.collisionPolicy,
                    deletionPolicy: nil
                ))
        case .move(let plan):
            normalized.append(
                FolderOperationCommitNormalizedOperation(
                    index: 0,
                    kind: .move,
                    sourceRoot: plan.sourceRoot,
                    source: plan.source,
                    destinationRoot: plan.destinationRoot,
                    destination: plan.destination,
                    collisionPolicy: plan.collisionPolicy,
                    deletionPolicy: nil
                ))
        case .delete(let plan):
            normalized.append(
                FolderOperationCommitNormalizedOperation(
                    index: 0,
                    kind: .delete,
                    sourceRoot: nil,
                    source: nil,
                    destinationRoot: plan.root,
                    destination: plan.target,
                    collisionPolicy: nil,
                    deletionPolicy: plan.deletionPolicy
                ))
        case .synchronize(let plan):
            guard !plan.steps.isEmpty else {
                throw FolderOperationCommitError.emptyPlan
            }
            guard plan.steps.count <= limits.maximumSteps else {
                throw FolderOperationCommitError.tooManySteps(maximum: limits.maximumSteps)
            }
            normalized.reserveCapacity(plan.steps.count)
            for (offset, step) in plan.steps.enumerated() {
                try budget.add(2, maximum: limits.maximumWorkUnits)
                if offset % 32 == 0 {
                    try checkCancellation()
                }
                switch step {
                case .copy(let source, let destination, let collisionPolicy):
                    normalized.append(
                        FolderOperationCommitNormalizedOperation(
                            index: offset,
                            kind: .copy,
                            sourceRoot: plan.sourceRoot,
                            source: source,
                            destinationRoot: plan.destinationRoot,
                            destination: destination,
                            collisionPolicy: collisionPolicy,
                            deletionPolicy: nil
                        ))
                case .delete(let destination, let deletionPolicy):
                    normalized.append(
                        FolderOperationCommitNormalizedOperation(
                            index: offset,
                            kind: .delete,
                            sourceRoot: nil,
                            source: nil,
                            destinationRoot: plan.destinationRoot,
                            destination: destination,
                            collisionPolicy: nil,
                            deletionPolicy: deletionPolicy
                        ))
                }
            }
        }
        guard !normalized.isEmpty else {
            throw FolderOperationCommitError.emptyPlan
        }
        guard normalized.count <= limits.maximumSteps else {
            throw FolderOperationCommitError.tooManySteps(maximum: limits.maximumSteps)
        }
        var totalBytes = 0
        for item in normalized {
            try budget.add(4, maximum: limits.maximumWorkUnits)
            try validateRootURL(item.destinationRoot, limits: limits)
            if let sourceRoot = item.sourceRoot {
                try validateRootURL(sourceRoot, limits: limits)
                try budget.add(2, maximum: limits.maximumWorkUnits)
            }
            let sourceBytes = item.source?.rawValue.utf8.count ?? 0
            let destinationBytes = item.destination.rawValue.utf8.count
            guard sourceBytes <= limits.maximumPathUTF8Bytes, destinationBytes <= limits.maximumPathUTF8Bytes else {
                throw FolderOperationCommitError.pathTooLarge(maximumBytes: limits.maximumPathUTF8Bytes)
            }
            let (partial, overflow) = totalBytes.addingReportingOverflow(sourceBytes + destinationBytes + 64)
            guard !overflow, partial <= limits.maximumTotalPathUTF8Bytes else {
                throw FolderOperationCommitError.totalPathsTooLarge(maximumBytes: limits.maximumTotalPathUTF8Bytes)
            }
            totalBytes = partial
            try budget.add(UInt64(sourceBytes + destinationBytes + 64) / 256 + 1, maximum: limits.maximumWorkUnits)
        }
        return normalized
    }

    fileprivate static func pinnedRoot(
        for url: URL,
        indexed: FolderOperationCommitIndexedSnapshot
    ) throws -> FolderOperationCommitPinnedRoot {
        let key = rootMatchKey(url)
        var match: FolderOperationCommitPinnedRoot?
        for (offset, root) in indexed.roots.enumerated() {
            let canonicalMatch = indexed.rootMatchKeys[offset] == key
            let requestedMatch = rootMatchKey(root.requestedURL) == key
            if canonicalMatch || requestedMatch {
                guard match == nil else {
                    throw FolderOperationCommitError.conflictingRootIdentity
                }
                match = root
            }
        }
        guard let match else {
            throw FolderOperationCommitError.unknownRoot
        }
        return match
    }

    fileprivate static func lookupItem(
        rootIdentity: FolderOperationCommitRootIdentity,
        components: [String],
        indexed: FolderOperationCommitIndexedSnapshot
    ) -> FolderOperationCommitItemRevision? {
        let folded = foldedComponents(components).joined(separator: "/")
        let key = slotKey(rootIdentity: rootIdentity, foldedRelative: folded)
        guard let offset = indexed.itemsBySlot[key], indexed.items.indices.contains(offset) else {
            return nil
        }
        return indexed.items[offset]
    }

    fileprivate static func parentComponents(_ components: [String]) -> [String]? {
        guard components.count > 1 else {
            return nil
        }
        return Array(components.dropLast())
    }

    fileprivate static func sameRoot(
        _ lhs: FolderOperationCommitRootIdentity,
        _ rhs: FolderOperationCommitRootIdentity
    ) -> Bool {
        lhs.deviceID == rhs.deviceID && lhs.fileID == rhs.fileID
    }

    fileprivate static func buildSteps(
        _ normalized: [FolderOperationCommitNormalizedOperation],
        indexed: FolderOperationCommitIndexedSnapshot,
        limits: FolderOperationCommitLimits,
        budget: inout FolderOperationCommitWorkBudget
    ) throws -> [FolderOperationCommitStep] {
        var steps: [FolderOperationCommitStep] = []
        steps.reserveCapacity(normalized.count)
        for operation in normalized {
            try budget.add(8, maximum: limits.maximumWorkUnits)
            if operation.index % 16 == 0 {
                try checkCancellation()
            }
            switch operation.kind {
            case .copy, .move:
                steps.append(try buildTransfer(operation, indexed: indexed, limits: limits, budget: &budget))
            case .delete:
                steps.append(try buildDelete(operation, indexed: indexed, limits: limits, budget: &budget))
            }
        }
        return steps
    }

    fileprivate static func buildTransfer(
        _ operation: FolderOperationCommitNormalizedOperation,
        indexed: FolderOperationCommitIndexedSnapshot,
        limits: FolderOperationCommitLimits,
        budget: inout FolderOperationCommitWorkBudget
    ) throws -> FolderOperationCommitStep {
        guard let sourceRootURL = operation.sourceRoot, let sourcePath = operation.source else {
            throw FolderOperationCommitError.invalidItemRevision
        }
        guard let collisionPolicy = operation.collisionPolicy else {
            throw FolderOperationCommitError.invalidItemRevision
        }
        let sourcePinned = try pinnedRoot(for: sourceRootURL, indexed: indexed)
        let destinationPinned = try pinnedRoot(for: operation.destinationRoot, indexed: indexed)
        let sourceIdentity = sourcePinned.revision.identity
        let destinationIdentity = destinationPinned.revision.identity
        try budget.add(6, maximum: limits.maximumWorkUnits)
        guard let sourceItem = lookupItem(rootIdentity: sourceIdentity, components: sourcePath.components, indexed: indexed) else {
            throw FolderOperationCommitError.missingSourceRevision(step: operation.index)
        }
        var sourceParent: FolderOperationCommitItemRevision?
        if let parent = parentComponents(sourcePath.components) {
            guard let resolved = lookupItem(rootIdentity: sourceIdentity, components: parent, indexed: indexed) else {
                throw FolderOperationCommitError.missingSourceRevision(step: operation.index)
            }
            guard resolved.kind == .directory else {
                throw FolderOperationCommitError.missingSourceRevision(step: operation.index)
            }
            sourceParent = resolved
        }
        let destinationPrior = lookupItem(
            rootIdentity: destinationIdentity,
            components: operation.destination.components,
            indexed: indexed
        )
        var destinationParent: FolderOperationCommitItemRevision?
        if let parent = parentComponents(operation.destination.components) {
            guard let resolved = lookupItem(rootIdentity: destinationIdentity, components: parent, indexed: indexed) else {
                throw FolderOperationCommitError.missingDestinationParent(step: operation.index)
            }
            guard resolved.kind == .directory else {
                throw FolderOperationCommitError.missingDestinationParent(step: operation.index)
            }
            destinationParent = resolved
        }
        if sameRoot(sourceIdentity, destinationIdentity) {
            let sourceFolded = foldedComponents(sourcePath.components)
            let destinationFolded = foldedComponents(operation.destination.components)
            if isPrefixOrEqual(sourceFolded, destinationFolded) {
                throw FolderOperationCommitError.sourceDestinationOverlap(step: operation.index)
            }
        }
        if let prior = destinationPrior,
            sourceItem.identity.deviceID == prior.identity.deviceID,
            sourceItem.identity.fileID == prior.identity.fileID,
            sourceItem.identity.generation == prior.identity.generation
        {
            throw FolderOperationCommitError.sourceDestinationOverlap(step: operation.index)
        }
        var replacesExisting = false
        var skipsExisting = false
        if destinationPrior != nil {
            switch collisionPolicy {
            case .fail:
                throw FolderOperationCommitError.destinationCollision(step: operation.index)
            case .skip:
                skipsExisting = true
            case .replaceKeepingBackup:
                replacesExisting = true
            }
        }
        return FolderOperationCommitStep(
            index: operation.index,
            kind: operation.kind,
            sourceRoot: sourceIdentity,
            sourceRelativePath: sourcePath.rawValue,
            sourceExpected: sourceItem,
            sourceParent: sourceParent,
            destinationRoot: destinationIdentity,
            destinationRelativePath: operation.destination.rawValue,
            destinationPrior: destinationPrior,
            destinationParent: destinationParent,
            collisionPolicy: collisionPolicy,
            deletionPolicy: nil,
            replacesExisting: replacesExisting,
            skipsExisting: skipsExisting
        )
    }

    fileprivate static func buildDelete(
        _ operation: FolderOperationCommitNormalizedOperation,
        indexed: FolderOperationCommitIndexedSnapshot,
        limits: FolderOperationCommitLimits,
        budget: inout FolderOperationCommitWorkBudget
    ) throws -> FolderOperationCommitStep {
        guard let deletionPolicy = operation.deletionPolicy else {
            throw FolderOperationCommitError.invalidItemRevision
        }
        let pinned = try pinnedRoot(for: operation.destinationRoot, indexed: indexed)
        let identity = pinned.revision.identity
        try budget.add(6, maximum: limits.maximumWorkUnits)
        guard let target = lookupItem(rootIdentity: identity, components: operation.destination.components, indexed: indexed) else {
            throw FolderOperationCommitError.missingTargetRevision(step: operation.index)
        }
        var parent: FolderOperationCommitItemRevision?
        if let parentPath = parentComponents(operation.destination.components) {
            guard let resolved = lookupItem(rootIdentity: identity, components: parentPath, indexed: indexed) else {
                throw FolderOperationCommitError.missingDestinationParent(step: operation.index)
            }
            guard resolved.kind == .directory else {
                throw FolderOperationCommitError.missingDestinationParent(step: operation.index)
            }
            parent = resolved
        }
        return FolderOperationCommitStep(
            index: operation.index,
            kind: .delete,
            sourceRoot: nil,
            sourceRelativePath: nil,
            sourceExpected: nil,
            sourceParent: nil,
            destinationRoot: identity,
            destinationRelativePath: operation.destination.rawValue,
            destinationPrior: target,
            destinationParent: parent,
            collisionPolicy: nil,
            deletionPolicy: deletionPolicy,
            replacesExisting: false,
            skipsExisting: false
        )
    }

    fileprivate static func stepAccess(_ step: FolderOperationCommitStep) -> FolderOperationCommitStepAccess {
        var reads: [FolderOperationCommitSlotAccess] = []
        var writes: [FolderOperationCommitSlotAccess] = []
        if let sourceRoot = step.sourceRoot,
            let sourcePath = step.sourceRelativePath,
            let sourceExpected = step.sourceExpected,
            let parsed = try? FolderRelativePath(sourcePath)
        {
            let absolute = absoluteComponents(rootURL: sourceRoot.canonicalURL, relativeComponents: parsed.components)
            reads.append(FolderOperationCommitSlotAccess(absoluteComponents: absolute, identityKey: itemIdentityKey(sourceExpected)))
        }
        guard let parsedDestination = try? FolderRelativePath(step.destinationRelativePath) else {
            return FolderOperationCommitStepAccess(step: step.index, reads: reads, writes: writes)
        }
        let destinationAbsolute = absoluteComponents(
            rootURL: step.destinationRoot.canonicalURL,
            relativeComponents: parsedDestination.components
        )
        let priorKey = step.destinationPrior.map { itemIdentityKey($0) }
        if step.skipsExisting {
            reads.append(FolderOperationCommitSlotAccess(absoluteComponents: destinationAbsolute, identityKey: priorKey))
        } else {
            writes.append(FolderOperationCommitSlotAccess(absoluteComponents: destinationAbsolute, identityKey: priorKey))
        }
        return FolderOperationCommitStepAccess(step: step.index, reads: reads, writes: writes)
    }

    fileprivate static func validateCrossStepConflicts(
        _ steps: [FolderOperationCommitStep],
        budget: inout FolderOperationCommitWorkBudget
    ) throws {
        let accesses = steps.map { stepAccess($0) }
        for first in 0..<accesses.count {
            for second in (first + 1)..<accesses.count {
                try budget.add(4, maximum: budget.maximum)
                if (first + second) % 64 == 0 {
                    try checkCancellation()
                }
                let lhs = accesses[first]
                let rhs = accesses[second]
                if overlaps(lhs.writes, rhs.writes) {
                    throw FolderOperationCommitError.conflictingPlan(firstStep: lhs.step, secondStep: rhs.step)
                }
                if overlaps(lhs.writes, rhs.reads) || overlaps(lhs.reads, rhs.writes) {
                    throw FolderOperationCommitError.readDependencyViolation(firstStep: lhs.step, secondStep: rhs.step)
                }
                if overlapsIdentity(lhs.writes, rhs.writes) {
                    throw FolderOperationCommitError.conflictingPlan(firstStep: lhs.step, secondStep: rhs.step)
                }
                if overlapsIdentity(lhs.writes, rhs.reads) || overlapsIdentity(lhs.reads, rhs.writes) {
                    throw FolderOperationCommitError.readDependencyViolation(firstStep: lhs.step, secondStep: rhs.step)
                }
            }
        }
    }

    fileprivate static func overlaps(
        _ lhs: [FolderOperationCommitSlotAccess],
        _ rhs: [FolderOperationCommitSlotAccess]
    ) -> Bool {
        for left in lhs {
            for right in rhs {
                if isPrefixOrEqual(left.absoluteComponents, right.absoluteComponents) {
                    return true
                }
            }
        }
        return false
    }

    fileprivate static func overlapsIdentity(
        _ lhs: [FolderOperationCommitSlotAccess],
        _ rhs: [FolderOperationCommitSlotAccess]
    ) -> Bool {
        for left in lhs {
            for right in rhs {
                if let leftKey = left.identityKey, let rightKey = right.identityKey, leftKey == rightKey {
                    return true
                }
            }
        }
        return false
    }

    fileprivate static func deriveRollback(
        _ steps: [FolderOperationCommitStep],
        order: inout Int
    ) -> [FolderOperationRollbackStep] {
        var rollback: [FolderOperationRollbackStep] = []
        for step in steps.reversed() {
            if step.skipsExisting {
                continue
            }
            switch step.kind {
            case .copy:
                if step.replacesExisting {
                    rollback.append(
                        FolderOperationRollbackStep(
                            commitIndex: step.index,
                            rollbackOrder: order,
                            action: .restoreReplacedDestination,
                            rootIdentity: step.destinationRoot,
                            relativePath: step.destinationRelativePath,
                            restored: step.destinationPrior,
                            publishedContentSHA256: step.sourceExpected?.contentSHA256
                        ))
                    order += 1
                } else {
                    rollback.append(
                        FolderOperationRollbackStep(
                            commitIndex: step.index,
                            rollbackOrder: order,
                            action: .removePublishedDestination,
                            rootIdentity: step.destinationRoot,
                            relativePath: step.destinationRelativePath,
                            restored: nil,
                            publishedContentSHA256: step.sourceExpected?.contentSHA256
                        ))
                    order += 1
                }
            case .move:
                if step.replacesExisting {
                    rollback.append(
                        FolderOperationRollbackStep(
                            commitIndex: step.index,
                            rollbackOrder: order,
                            action: .restoreReplacedDestination,
                            rootIdentity: step.destinationRoot,
                            relativePath: step.destinationRelativePath,
                            restored: step.destinationPrior,
                            publishedContentSHA256: step.sourceExpected?.contentSHA256
                        ))
                    order += 1
                } else {
                    rollback.append(
                        FolderOperationRollbackStep(
                            commitIndex: step.index,
                            rollbackOrder: order,
                            action: .removePublishedDestination,
                            rootIdentity: step.destinationRoot,
                            relativePath: step.destinationRelativePath,
                            restored: nil,
                            publishedContentSHA256: step.sourceExpected?.contentSHA256
                        ))
                    order += 1
                }
                if let sourceRoot = step.sourceRoot,
                    let sourcePath = step.sourceRelativePath,
                    let sourceExpected = step.sourceExpected
                {
                    rollback.append(
                        FolderOperationRollbackStep(
                            commitIndex: step.index,
                            rollbackOrder: order,
                            action: .restoreMovedSource,
                            rootIdentity: sourceRoot,
                            relativePath: sourcePath,
                            restored: sourceExpected,
                            publishedContentSHA256: nil
                        ))
                    order += 1
                }
            case .delete:
                rollback.append(
                    FolderOperationRollbackStep(
                        commitIndex: step.index,
                        rollbackOrder: order,
                        action: .restoreDeletedTarget,
                        rootIdentity: step.destinationRoot,
                        relativePath: step.destinationRelativePath,
                        restored: step.destinationPrior,
                        publishedContentSHA256: nil
                    ))
                order += 1
            }
        }
        return rollback
    }

    fileprivate static func canonicalStepData(_ step: FolderOperationCommitStep) -> Data {
        var text = "mm-commit/v1|\(step.index)|\(step.kind.receiptToken)|"
        if let sourceRoot = step.sourceRoot, let sourcePath = step.sourceRelativePath {
            text += "\(sourceRoot.deviceID):\(sourceRoot.fileID):\(sourceRoot.generation)|\(canonicalFolded(sourcePath))|"
        } else {
            text += "nil|nil|"
        }
        text += "\(step.destinationRoot.deviceID):\(step.destinationRoot.fileID):\(step.destinationRoot.generation)|"
        text += "\(canonicalFolded(step.destinationRelativePath))|\(step.replacesExisting)|\(step.skipsExisting)|"
        var data = Data(text.utf8)
        if let sourceExpected = step.sourceExpected {
            data.append(contentsOf: sourceExpected.metadataSHA256)
            if let digest = sourceExpected.contentSHA256 {
                data.append(contentsOf: digest)
            }
        }
        if let prior = step.destinationPrior {
            data.append(contentsOf: prior.metadataSHA256)
            if let digest = prior.contentSHA256 {
                data.append(contentsOf: digest)
            }
        }
        return data
    }

    fileprivate static func makeReceipt(
        steps: [FolderOperationCommitStep],
        rollback: [FolderOperationRollbackStep],
        limits: FolderOperationCommitLimits,
        budget: inout FolderOperationCommitWorkBudget
    ) throws -> FolderOperationCommitReceipt {
        var estimated = 128 + rollback.count * 128
        for step in steps {
            let sourceBytes = step.sourceRelativePath?.utf8.count ?? 0
            let destinationBytes = step.destinationRelativePath.utf8.count
            let (partial, overflow) = estimated.addingReportingOverflow(sourceBytes + destinationBytes + 256)
            guard !overflow, partial <= limits.maximumPlanOutputBytes else {
                throw FolderOperationCommitError.planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
            }
            estimated = partial
        }
        guard estimated <= limits.maximumPlanOutputBytes else {
            throw FolderOperationCommitError.planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
        }
        var stepDigests: [[UInt8]] = []
        stepDigests.reserveCapacity(steps.count)
        var combined = Data("mm-commit/v1|steps:\(steps.count)|rollback:\(rollback.count)|".utf8)
        for step in steps {
            try budget.add(8, maximum: limits.maximumWorkUnits)
            let data = canonicalStepData(step)
            try budget.add(UInt64(data.count) / 256 + 1, maximum: limits.maximumWorkUnits)
            let digest = Array(SHA256.hash(data: data))
            stepDigests.append(digest)
            combined.append(contentsOf: digest)
        }
        for entry in rollback {
            try budget.add(2, maximum: limits.maximumWorkUnits)
            var text = "rollback|\(entry.rollbackOrder)|\(entry.commitIndex)|\(entry.action.rawValue)|"
            text += "\(entry.rootIdentity.deviceID):\(entry.rootIdentity.fileID):\(entry.rootIdentity.generation)|"
            text += "\(canonicalFolded(entry.relativePath))|"
            combined.append(contentsOf: Data(text.utf8))
            if let restored = entry.restored {
                combined.append(contentsOf: restored.metadataSHA256)
            }
            if let published = entry.publishedContentSHA256 {
                combined.append(contentsOf: published)
            }
        }
        guard combined.count <= limits.maximumPlanOutputBytes else {
            throw FolderOperationCommitError.planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
        }
        let planDigest = Array(SHA256.hash(data: combined))
        let skipped = steps.filter { $0.skipsExisting }.count
        return FolderOperationCommitReceipt(
            planDigestSHA256: planDigest,
            stepDigestsSHA256: stepDigests,
            stepCount: steps.count,
            skippedStepCount: skipped,
            rollbackStepCount: rollback.count
        )
    }
}

extension FolderFileOperationKind {
    fileprivate var receiptToken: String {
        switch self {
        case .copy: "copy"
        case .move: "move"
        case .delete: "delete"
        }
    }
}
