import Foundation

public enum ThreePaneSaveSide: String, CaseIterable, Hashable, Sendable {
    case left
    case middle
    case right
}

public enum ThreePaneSaveCanonicalItemKind: String, Hashable, Sendable {
    case regularFile
    case directory
}

/// Caller-captured identity for one canonical filesystem object.
///
/// Planning never resolves this URL. Executors must pin the object and compare its stable identity
/// rather than treating the URL as authority.
public struct ThreePaneSaveCanonicalFileIdentity: Hashable, Sendable {
    public let canonicalURL: URL
    public let kind: ThreePaneSaveCanonicalItemKind
    public let volumeID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    public init(
        canonicalURL: URL,
        kind: ThreePaneSaveCanonicalItemKind,
        volumeID: UInt64,
        fileID: UInt64,
        generation: UInt32
    ) {
        self.canonicalURL = canonicalURL
        self.kind = kind
        self.volumeID = volumeID
        self.fileID = fileID
        self.generation = generation
    }
}

/// Exact caller-captured revision used by destination compare-and-swap.
public struct ThreePaneSaveFileRevision: Hashable, Sendable {
    public let identity: ThreePaneSaveCanonicalFileIdentity
    public let byteCount: UInt64
    public let metadataByteCount: UInt64
    public let modificationTimeSeconds: Int64
    public let modificationTimeNanoseconds: UInt32
    public let statusChangeTimeSeconds: Int64
    public let statusChangeTimeNanoseconds: UInt32
    public let contentSHA256: [UInt8]
    public let metadataSHA256: [UInt8]

    public init(
        identity: ThreePaneSaveCanonicalFileIdentity,
        byteCount: UInt64,
        metadataByteCount: UInt64,
        modificationTimeSeconds: Int64,
        modificationTimeNanoseconds: UInt32,
        statusChangeTimeSeconds: Int64,
        statusChangeTimeNanoseconds: UInt32,
        contentSHA256: [UInt8],
        metadataSHA256: [UInt8]
    ) {
        self.identity = identity
        self.byteCount = byteCount
        self.metadataByteCount = metadataByteCount
        self.modificationTimeSeconds = modificationTimeSeconds
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.statusChangeTimeSeconds = statusChangeTimeSeconds
        self.statusChangeTimeNanoseconds = statusChangeTimeNanoseconds
        self.contentSHA256 = contentSHA256
        self.metadataSHA256 = metadataSHA256
    }
}

public enum ThreePaneSaveTextEncoding: String, CaseIterable, Hashable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
    case shiftJIS
    case japaneseEUC
    case iso2022JP
    case windows1250
    case windows1251
    case windows1252
    case windows1253
    case windows1254
    case windows1255

    public init(_ encoding: TextFileEncoding) {
        switch encoding {
        case .utf8: self = .utf8
        case .utf16LittleEndian: self = .utf16LittleEndian
        case .utf16BigEndian: self = .utf16BigEndian
        case .shiftJIS: self = .shiftJIS
        case .japaneseEUC: self = .japaneseEUC
        case .iso2022JP: self = .iso2022JP
        case .windows1250: self = .windows1250
        case .windows1251: self = .windows1251
        case .windows1252: self = .windows1252
        case .windows1253: self = .windows1253
        case .windows1254: self = .windows1254
        case .windows1255: self = .windows1255
        }
    }

    public var textFileEncoding: TextFileEncoding {
        switch self {
        case .utf8: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        case .shiftJIS: .shiftJIS
        case .japaneseEUC: .japaneseEUC
        case .iso2022JP: .iso2022JP
        case .windows1250: .windows1250
        case .windows1251: .windows1251
        case .windows1252: .windows1252
        case .windows1253: .windows1253
        case .windows1254: .windows1254
        case .windows1255: .windows1255
        }
    }

}

/// Encoding metadata that must be retained when loaded content is saved or rebound by Save As.
public struct ThreePaneSaveEncodingMetadata: Hashable, Sendable {
    public let encoding: ThreePaneSaveTextEncoding
    public let hasByteOrderMark: Bool

    public init(encoding: ThreePaneSaveTextEncoding, hasByteOrderMark: Bool) {
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
    }

    public init(encoding: TextFileEncoding, hasByteOrderMark: Bool) {
        self.init(
            encoding: ThreePaneSaveTextEncoding(encoding),
            hasByteOrderMark: hasByteOrderMark
        )
    }
}

/// Exact owner revision of complete bytes ready for publication.
///
/// The owner must never reuse a `(documentID, revision)` pair for different bytes or metadata.
public struct ThreePaneSaveContentRevision: Hashable, Sendable {
    public let documentID: UUID
    public let revision: UInt64
    public let isDirty: Bool
    public let isReadOnly: Bool
    public let encodedByteCount: UInt64
    public let encodedContentSHA256: [UInt8]
    public let encoding: ThreePaneSaveEncodingMetadata

    public init(
        documentID: UUID,
        revision: UInt64,
        isDirty: Bool,
        isReadOnly: Bool,
        encodedByteCount: UInt64,
        encodedContentSHA256: [UInt8],
        encoding: ThreePaneSaveEncodingMetadata
    ) {
        self.documentID = documentID
        self.revision = revision
        self.isDirty = isDirty
        self.isReadOnly = isReadOnly
        self.encodedByteCount = encodedByteCount
        self.encodedContentSHA256 = encodedContentSHA256
        self.encoding = encoding
    }
}

public enum ThreePaneSaveResolvedPathKind: String, Hashable, Sendable {
    case direct
    case symbolicLink
    case finderAlias
}

/// Complete binding of a loaded pane to its exact persisted file and canonical directory slot.
public struct ThreePaneSaveFileBinding: Hashable, Sendable {
    public let revision: ThreePaneSaveFileRevision
    public let parentIdentity: ThreePaneSaveCanonicalFileIdentity
    /// Opaque, volume-aware identity for the leaf name. It must already include filesystem-specific
    /// case and Unicode normalization behavior.
    public let canonicalLeafIdentity: String
    public let resolvedPathKind: ThreePaneSaveResolvedPathKind

    public init(
        revision: ThreePaneSaveFileRevision,
        parentIdentity: ThreePaneSaveCanonicalFileIdentity,
        canonicalLeafIdentity: String,
        resolvedPathKind: ThreePaneSaveResolvedPathKind = .direct
    ) {
        self.revision = revision
        self.parentIdentity = parentIdentity
        self.canonicalLeafIdentity = canonicalLeafIdentity
        self.resolvedPathKind = resolvedPathKind
    }
}

public enum ThreePaneSavePaneState: Hashable, Sendable {
    case unloaded
    case untitled(ThreePaneSaveContentRevision)
    case loaded(content: ThreePaneSaveContentRevision, file: ThreePaneSaveFileBinding)

    public var content: ThreePaneSaveContentRevision? {
        switch self {
        case .unloaded:
            nil
        case .untitled(let content), .loaded(let content, _):
            content
        }
    }

    public var isUntitled: Bool {
        if case .untitled = self { return true }
        return false
    }
}

public struct ThreePaneSavePane: Hashable, Sendable {
    public let side: ThreePaneSaveSide
    public let state: ThreePaneSavePaneState

    public init(side: ThreePaneSaveSide, state: ThreePaneSavePaneState) {
        self.side = side
        self.state = state
    }
}

public enum ThreePaneSaveDestinationState: Hashable, Sendable {
    /// Publish only while the canonical leaf is absent under the exact parent identity.
    case vacant
    /// Replace only this exact existing file revision.
    case existing(ThreePaneSaveFileRevision)
}

/// Caller-resolved destination. Both aliases and links remain represented so planning can reject
/// them explicitly instead of silently trusting a resolved path.
public struct ThreePaneSaveDestinationIdentity: Hashable, Sendable {
    public let canonicalURL: URL
    public let parentIdentity: ThreePaneSaveCanonicalFileIdentity
    public let canonicalLeafIdentity: String
    public let resolvedPathKind: ThreePaneSaveResolvedPathKind
    public let state: ThreePaneSaveDestinationState

    public init(
        canonicalURL: URL,
        parentIdentity: ThreePaneSaveCanonicalFileIdentity,
        canonicalLeafIdentity: String,
        resolvedPathKind: ThreePaneSaveResolvedPathKind = .direct,
        state: ThreePaneSaveDestinationState
    ) {
        self.canonicalURL = canonicalURL
        self.parentIdentity = parentIdentity
        self.canonicalLeafIdentity = canonicalLeafIdentity
        self.resolvedPathKind = resolvedPathKind
        self.state = state
    }
}

public struct ThreePaneSaveDestination: Hashable, Sendable {
    public let side: ThreePaneSaveSide
    public let identity: ThreePaneSaveDestinationIdentity

    public init(side: ThreePaneSaveSide, identity: ThreePaneSaveDestinationIdentity) {
        self.side = side
        self.identity = identity
    }
}

public enum ThreePaneSaveAction: Hashable, Sendable {
    /// A loaded middle pane saves in place. An untitled middle pane requires one destination.
    case saveMiddle(destination: ThreePaneSaveDestination? = nil)
    case saveAsMiddle(destination: ThreePaneSaveDestination)
    /// Destinations are accepted only for dirty untitled panes. Loaded dirty panes save in place.
    case saveAll(destinations: [ThreePaneSaveDestination] = [])
}

public enum ThreePaneSavePlanningLimit: String, CaseIterable, Hashable, Sendable {
    case operations
    case pathUTF8Bytes
    case totalPathUTF8Bytes
    case canonicalLeafIdentityUTF8Bytes
    case encodedFileBytes
    case metadataBytes
    case workUnits
}

public struct ThreePaneSavePlanningLimits: Hashable, Sendable {
    public static let hardMaximumOperations = 3
    public static let hardMaximumPathUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 512 * 1_024
    public static let hardMaximumCanonicalLeafIdentityUTF8Bytes = 4 * 1_024
    public static let hardMaximumEncodedFileBytes: UInt64 = 64 * 1_024 * 1_024
    public static let hardMaximumMetadataBytes: UInt64 = 64 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1_000_000

    public static let `default`: ThreePaneSavePlanningLimits = {
        try! ThreePaneSavePlanningLimits()
    }()

    public let maximumOperations: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumCanonicalLeafIdentityUTF8Bytes: Int
    public let maximumEncodedFileBytes: UInt64
    public let maximumMetadataBytes: UInt64
    public let maximumWorkUnits: UInt64

    public init(
        maximumOperations: Int = 3,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 128 * 1_024,
        maximumCanonicalLeafIdentityUTF8Bytes: Int = 1_024,
        maximumEncodedFileBytes: UInt64 = 64 * 1_024 * 1_024,
        maximumMetadataBytes: UInt64 = 16 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 1_024
    ) throws {
        guard (1...Self.hardMaximumOperations).contains(maximumOperations) else {
            throw ThreePaneSavePlanningError.invalidLimit(.operations)
        }
        guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
            throw ThreePaneSavePlanningError.invalidLimit(.pathUTF8Bytes)
        }
        guard maximumTotalPathUTF8Bytes >= maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes <= Self.hardMaximumTotalPathUTF8Bytes
        else {
            throw ThreePaneSavePlanningError.invalidLimit(.totalPathUTF8Bytes)
        }
        guard
            (1...Self.hardMaximumCanonicalLeafIdentityUTF8Bytes)
                .contains(maximumCanonicalLeafIdentityUTF8Bytes)
        else {
            throw ThreePaneSavePlanningError.invalidLimit(.canonicalLeafIdentityUTF8Bytes)
        }
        guard maximumEncodedFileBytes > 0,
            maximumEncodedFileBytes <= Self.hardMaximumEncodedFileBytes
        else {
            throw ThreePaneSavePlanningError.invalidLimit(.encodedFileBytes)
        }
        guard maximumMetadataBytes <= Self.hardMaximumMetadataBytes else {
            throw ThreePaneSavePlanningError.invalidLimit(.metadataBytes)
        }
        guard maximumWorkUnits > 0, maximumWorkUnits <= Self.hardMaximumWorkUnits else {
            throw ThreePaneSavePlanningError.invalidLimit(.workUnits)
        }

        self.maximumOperations = maximumOperations
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumCanonicalLeafIdentityUTF8Bytes = maximumCanonicalLeafIdentityUTF8Bytes
        self.maximumEncodedFileBytes = maximumEncodedFileBytes
        self.maximumMetadataBytes = maximumMetadataBytes
        self.maximumWorkUnits = maximumWorkUnits
    }
}

public struct ThreePaneSaveRequest: Hashable, Sendable {
    public let panes: [ThreePaneSavePane]
    public let action: ThreePaneSaveAction
    public let limits: ThreePaneSavePlanningLimits

    public init(
        panes: [ThreePaneSavePane],
        action: ThreePaneSaveAction,
        limits: ThreePaneSavePlanningLimits = .default
    ) {
        self.panes = panes
        self.action = action
        self.limits = limits
    }

    public init(
        left: ThreePaneSavePaneState,
        middle: ThreePaneSavePaneState,
        right: ThreePaneSavePaneState,
        action: ThreePaneSaveAction,
        limits: ThreePaneSavePlanningLimits = .default
    ) {
        self.init(
            panes: [
                ThreePaneSavePane(side: .left, state: left),
                ThreePaneSavePane(side: .middle, state: middle),
                ThreePaneSavePane(side: .right, state: right)
            ],
            action: action,
            limits: limits
        )
    }
}

public enum ThreePaneSaveOperationKind: String, Hashable, Sendable {
    case saveInPlace
    case saveAsNewFile
    case saveAsReplacingFile
}

public enum ThreePaneSaveSourceRevisionContract: String, Hashable, Sendable {
    case exactOwnerRevisionLeaseHeldThroughPublication
}

public enum ThreePaneSaveDestinationCASContract: String, Hashable, Sendable {
    case descriptorRelativeExactParentAndVacancyOrFullRevisionCompareAndSwap
}

public enum ThreePaneSavePathContract: String, Hashable, Sendable {
    case canonicalDescriptorRelativeNoFollowWithAliasesRejected
}

public enum ThreePaneSavePublicationContract: String, Hashable, Sendable {
    case privateStageSyncAtomicPublishVerifyAndSyncParent
}

public enum ThreePaneSaveCancellationContract: String, Hashable, Sendable {
    case cancellableBeforePublicationCommittedOrUncertainAfterPublicationStarts
}

public enum ThreePaneSavePaneUpdateContract: String, Hashable, Sendable {
    case consumePlanIDOnceAndApplyOnlyIfExactOwnerRevisionAndBindingRemainCurrent
}

public enum ThreePaneSaveBatchPreflightContract: String, Hashable, Sendable {
    case leaseAllSourcesAndCASDestinationsBeforeFirstPublication
}

public enum ThreePaneSaveBatchOutcomeContract: String, Hashable, Sendable {
    case noCommitOnPreflightFailureAndExactPerOperationOutcomesAfterPublicationStarts
}

public struct ThreePaneSaveExecutorContract: Hashable, Sendable {
    public static let required = ThreePaneSaveExecutorContract()

    public let sourceRevision =
        ThreePaneSaveSourceRevisionContract.exactOwnerRevisionLeaseHeldThroughPublication
    public let destinationCAS =
        ThreePaneSaveDestinationCASContract
        .descriptorRelativeExactParentAndVacancyOrFullRevisionCompareAndSwap
    public let pathResolution =
        ThreePaneSavePathContract.canonicalDescriptorRelativeNoFollowWithAliasesRejected
    public let publication =
        ThreePaneSavePublicationContract.privateStageSyncAtomicPublishVerifyAndSyncParent
    public let cancellation =
        ThreePaneSaveCancellationContract
        .cancellableBeforePublicationCommittedOrUncertainAfterPublicationStarts
    public let paneUpdate =
        ThreePaneSavePaneUpdateContract
        .consumePlanIDOnceAndApplyOnlyIfExactOwnerRevisionAndBindingRemainCurrent
    public let batchPreflight =
        ThreePaneSaveBatchPreflightContract.leaseAllSourcesAndCASDestinationsBeforeFirstPublication
    public let batchOutcome =
        ThreePaneSaveBatchOutcomeContract
        .noCommitOnPreflightFailureAndExactPerOperationOutcomesAfterPublicationStarts

    public init() {}
}

public struct ThreePaneSaveOperation: Hashable, Sendable {
    /// Planner-issued freshness value prevents receipts from another structurally equal plan from
    /// authorizing a pane update.
    public let planID: UUID
    public let side: ThreePaneSaveSide
    public let kind: ThreePaneSaveOperationKind
    public let source: ThreePaneSaveContentRevision
    public let sourceFile: ThreePaneSaveFileBinding?
    public let destination: ThreePaneSaveDestinationIdentity
    public let preservesEncoding: ThreePaneSaveEncodingMetadata
    public let preservesReadOnlyState: Bool
    public let executorContract: ThreePaneSaveExecutorContract

    fileprivate init(
        planID: UUID,
        side: ThreePaneSaveSide,
        kind: ThreePaneSaveOperationKind,
        source: ThreePaneSaveContentRevision,
        sourceFile: ThreePaneSaveFileBinding?,
        destination: ThreePaneSaveDestinationIdentity
    ) {
        self.planID = planID
        self.side = side
        self.kind = kind
        self.source = source
        self.sourceFile = sourceFile
        self.destination = destination
        preservesEncoding = source.encoding
        preservesReadOnlyState = source.isReadOnly
        executorContract = .required
    }
}

public struct ThreePaneSavePlan: Hashable, Sendable {
    public let operations: [ThreePaneSaveOperation]
    public let estimatedWorkUnits: UInt64
    public let limits: ThreePaneSavePlanningLimits

    fileprivate init(
        operations: [ThreePaneSaveOperation],
        estimatedWorkUnits: UInt64,
        limits: ThreePaneSavePlanningLimits
    ) {
        self.operations = operations
        self.estimatedWorkUnits = estimatedWorkUnits
        self.limits = limits
    }

    public func validate(
        receipts: [ThreePaneSaveOperationReceipt]
    ) throws -> ThreePaneSaveExecutionReceipt {
        guard receipts.count == operations.count else {
            throw ThreePaneSaveReceiptError.receiptCountMismatch(
                expected: operations.count,
                actual: receipts.count
            )
        }
        var receiptsBySide: [ThreePaneSaveSide: ThreePaneSaveOperationReceipt] = [:]
        receiptsBySide.reserveCapacity(receipts.count)
        for receipt in receipts {
            let operation = receipt.operation
            guard operations.contains(operation) else {
                throw ThreePaneSaveReceiptError.unknownOperation(operation.side)
            }
            guard receiptsBySide.updateValue(receipt, forKey: operation.side) == nil else {
                throw ThreePaneSaveReceiptError.duplicateOperationReceipt(operation.side)
            }
            try validateCommittedReceipt(receipt)
        }
        let orderedReceipts = try operations.map { operation in
            guard let receipt = receiptsBySide[operation.side] else {
                throw ThreePaneSaveReceiptError.missingOperationReceipt(operation.side)
            }
            return receipt
        }
        let hasPreflightFailure = orderedReceipts.contains { receipt in
            guard case .notCommitted(let reason) = receipt.outcome else { return false }
            return switch reason {
            case .cancelled, .sourceRevisionChanged, .destinationCompareFailed,
                .safetyContractUnavailable:
                true
            case .publicationFailedBeforeMutation:
                false
            }
        }
        if hasPreflightFailure,
            orderedReceipts.contains(where: { receipt in
                switch receipt.outcome {
                case .committed, .commitUncertain:
                    true
                case .notCommitted(let reason):
                    reason == .publicationFailedBeforeMutation
                }
            })
        {
            throw ThreePaneSaveReceiptError.inconsistentBatchOutcome
        }
        return ThreePaneSaveExecutionReceipt(outcomes: orderedReceipts)
    }

    private func validateCommittedReceipt(
        _ receipt: ThreePaneSaveOperationReceipt
    ) throws {
        guard case .committed(let committed) = receipt.outcome else { return }
        let operation = receipt.operation
        guard committed.committedParentIdentity == operation.destination.parentIdentity else {
            throw ThreePaneSaveReceiptError.committedParentMismatch(operation.side)
        }
        do {
            try ThreePaneSavePlanner.validate(
                committed.committedRevision,
                limits: limits,
                side: operation.side
            )
        } catch {
            throw ThreePaneSaveReceiptError.invalidCommittedRevision(operation.side)
        }
        let committedIdentity = committed.committedRevision.identity
        guard committedIdentity.canonicalURL == operation.destination.canonicalURL,
            committedIdentity.kind == .regularFile
        else {
            throw ThreePaneSaveReceiptError.committedDestinationMismatch(operation.side)
        }
        guard committed.committedRevision.byteCount == operation.source.encodedByteCount,
            committed.committedRevision.contentSHA256 == operation.source.encodedContentSHA256,
            committed.encoding == operation.preservesEncoding,
            committed.paneReadOnly == operation.preservesReadOnlyState
        else {
            throw ThreePaneSaveReceiptError.committedPayloadMismatch(operation.side)
        }
    }
}

public enum ThreePaneSaveNonCommitReason: String, Hashable, Sendable {
    case cancelled
    case sourceRevisionChanged
    case destinationCompareFailed
    case safetyContractUnavailable
    case publicationFailedBeforeMutation
}

public enum ThreePaneSaveCommitUncertainty: String, Hashable, Sendable {
    case publicationStateUnknown
    case committedBytesUnverified
    case durabilityUnverified
    case recoveryStateUnknown
}

public struct ThreePaneSaveCommitReceipt: Hashable, Sendable {
    public let committedParentIdentity: ThreePaneSaveCanonicalFileIdentity
    public let committedRevision: ThreePaneSaveFileRevision
    public let encoding: ThreePaneSaveEncodingMetadata
    public let paneReadOnly: Bool

    public init(
        committedParentIdentity: ThreePaneSaveCanonicalFileIdentity,
        committedRevision: ThreePaneSaveFileRevision,
        encoding: ThreePaneSaveEncodingMetadata,
        paneReadOnly: Bool
    ) {
        self.committedParentIdentity = committedParentIdentity
        self.committedRevision = committedRevision
        self.encoding = encoding
        self.paneReadOnly = paneReadOnly
    }
}

public enum ThreePaneSaveOperationOutcome: Hashable, Sendable {
    case committed(ThreePaneSaveCommitReceipt)
    case notCommitted(ThreePaneSaveNonCommitReason)
    case commitUncertain(ThreePaneSaveCommitUncertainty)
}

public struct ThreePaneSaveOperationReceipt: Hashable, Sendable {
    public let operation: ThreePaneSaveOperation
    public let outcome: ThreePaneSaveOperationOutcome

    public init(operation: ThreePaneSaveOperation, outcome: ThreePaneSaveOperationOutcome) {
        self.operation = operation
        self.outcome = outcome
    }
}

public struct ThreePaneSaveExecutionReceipt: Hashable, Sendable {
    public let outcomes: [ThreePaneSaveOperationReceipt]

    public var committedSides: [ThreePaneSaveSide] {
        outcomes.compactMap { receipt in
            if case .committed = receipt.outcome { receipt.operation.side } else { nil }
        }
    }

    public var hasCommitUncertainty: Bool {
        outcomes.contains { receipt in
            if case .commitUncertain = receipt.outcome { true } else { false }
        }
    }

    fileprivate init(outcomes: [ThreePaneSaveOperationReceipt]) {
        self.outcomes = outcomes
    }
}

public enum ThreePaneSavePlanningError: Error, LocalizedError, Hashable, Sendable {
    case cancelled
    case invalidLimit(ThreePaneSavePlanningLimit)
    case invalidPaneCount(Int)
    case duplicatePane(ThreePaneSaveSide)
    case missingPane(ThreePaneSaveSide)
    case paneNotLoaded(ThreePaneSaveSide)
    case paneNotDirty(ThreePaneSaveSide)
    case paneReadOnly(ThreePaneSaveSide)
    case invalidContentRevision(ThreePaneSaveSide)
    case invalidEncodingMetadata(ThreePaneSaveSide)
    case invalidCanonicalIdentity(String)
    case invalidFileRevision(String)
    case invalidFileURL(String)
    case pathTooLarge(maximumBytes: Int)
    case totalPathsTooLarge(maximumBytes: Int)
    case invalidCanonicalLeafIdentity(ThreePaneSaveSide)
    case aliasedPath(side: ThreePaneSaveSide, kind: ThreePaneSaveResolvedPathKind)
    case paneFileCollision(first: ThreePaneSaveSide, second: ThreePaneSaveSide)
    case missingDestination(ThreePaneSaveSide)
    case unexpectedDestination(ThreePaneSaveSide)
    case wrongDestinationSide(expected: ThreePaneSaveSide, actual: ThreePaneSaveSide)
    case duplicateDestination(ThreePaneSaveSide)
    case invalidDestination(ThreePaneSaveSide)
    case destinationAliasesPane(destination: ThreePaneSaveSide, pane: ThreePaneSaveSide)
    case destinationCollision(first: ThreePaneSaveSide, second: ThreePaneSaveSide)
    case encodedFileTooLarge(side: ThreePaneSaveSide, maximumBytes: UInt64)
    case metadataTooLarge(side: ThreePaneSaveSide, maximumBytes: UInt64)
    case tooManyOperations(maximum: Int)
    case workLimitExceeded(maximumUnits: UInt64)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Three-pane save planning was cancelled."
        case .invalidLimit(let limit):
            "Invalid three-pane save planning limit: \(limit.rawValue)."
        case .invalidPaneCount(let count):
            "Three-pane save planning requires exactly three panes, not \(count)."
        case .duplicatePane(let side):
            "Three-pane save input repeats the \(side.rawValue) pane."
        case .missingPane(let side):
            "Three-pane save input is missing the \(side.rawValue) pane."
        case .paneNotLoaded(let side):
            "The \(side.rawValue) pane is not loaded."
        case .paneNotDirty(let side):
            "The \(side.rawValue) pane has no unsaved changes."
        case .paneReadOnly(let side):
            "The dirty \(side.rawValue) pane is read-only."
        case .invalidContentRevision(let side):
            "The \(side.rawValue) pane has invalid content revision metadata."
        case .invalidEncodingMetadata(let side):
            "The \(side.rawValue) pane has invalid encoding or byte-order-mark metadata."
        case .invalidCanonicalIdentity(let path):
            "Invalid canonical filesystem identity: \(path)"
        case .invalidFileRevision(let path):
            "Invalid exact file revision: \(path)"
        case .invalidFileURL(let value):
            "Three-pane save requires a strict canonical local file URL: \(value)"
        case .pathTooLarge(let maximumBytes):
            "A three-pane save path exceeds the \(maximumBytes)-byte limit."
        case .totalPathsTooLarge(let maximumBytes):
            "Three-pane save paths exceed the \(maximumBytes)-byte aggregate limit."
        case .invalidCanonicalLeafIdentity(let side):
            "The \(side.rawValue) save path has an invalid canonical leaf identity."
        case .aliasedPath(let side, let kind):
            "The \(side.rawValue) save path is not direct (\(kind.rawValue))."
        case .paneFileCollision(let first, let second):
            "The \(first.rawValue) and \(second.rawValue) panes identify the same file."
        case .missingDestination(let side):
            "The untitled \(side.rawValue) pane requires a save destination."
        case .unexpectedDestination(let side):
            "The loaded or clean \(side.rawValue) pane does not accept that destination for this action."
        case .wrongDestinationSide(let expected, let actual):
            "A \(expected.rawValue) save received a \(actual.rawValue) destination."
        case .duplicateDestination(let side):
            "Three-pane save input repeats the \(side.rawValue) destination."
        case .invalidDestination(let side):
            "The \(side.rawValue) save destination does not match its canonical identity."
        case .destinationAliasesPane(let destination, let pane):
            "The \(destination.rawValue) save destination aliases the \(pane.rawValue) pane."
        case .destinationCollision(let first, let second):
            "The \(first.rawValue) and \(second.rawValue) save destinations collide."
        case .encodedFileTooLarge(let side, let maximumBytes):
            "The \(side.rawValue) encoded file exceeds the \(maximumBytes)-byte limit."
        case .metadataTooLarge(let side, let maximumBytes):
            "The \(side.rawValue) file metadata exceeds the \(maximumBytes)-byte limit."
        case .tooManyOperations(let maximum):
            "Three-pane save exceeds the \(maximum)-operation limit."
        case .workLimitExceeded(let maximumUnits):
            "Three-pane save planning exceeds the \(maximumUnits)-unit work limit."
        }
    }
}

public enum ThreePaneSaveReceiptError: Error, LocalizedError, Hashable, Sendable {
    case receiptCountMismatch(expected: Int, actual: Int)
    case unknownOperation(ThreePaneSaveSide)
    case duplicateOperationReceipt(ThreePaneSaveSide)
    case missingOperationReceipt(ThreePaneSaveSide)
    case invalidCommittedRevision(ThreePaneSaveSide)
    case committedParentMismatch(ThreePaneSaveSide)
    case committedDestinationMismatch(ThreePaneSaveSide)
    case committedPayloadMismatch(ThreePaneSaveSide)
    case inconsistentBatchOutcome

    public var errorDescription: String? {
        switch self {
        case .receiptCountMismatch(let expected, let actual):
            "Three-pane save expected \(expected) operation receipts but received \(actual)."
        case .unknownOperation(let side):
            "Receipt references an unknown \(side.rawValue) save operation."
        case .duplicateOperationReceipt(let side):
            "Receipt repeats the \(side.rawValue) save operation."
        case .missingOperationReceipt(let side):
            "Receipt is missing the \(side.rawValue) save operation."
        case .invalidCommittedRevision(let side):
            "The \(side.rawValue) committed file revision is invalid."
        case .committedParentMismatch(let side):
            "The \(side.rawValue) commit receipt has a different parent identity."
        case .committedDestinationMismatch(let side):
            "The \(side.rawValue) commit receipt identifies a different destination."
        case .committedPayloadMismatch(let side):
            "The \(side.rawValue) commit receipt does not match planned bytes or encoding metadata."
        case .inconsistentBatchOutcome:
            "Three-pane save receipts report a commit despite a batch-wide preflight failure."
        }
    }
}

public enum ThreePaneSavePlanner: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static func plan(
        _ request: ThreePaneSaveRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ThreePaneSavePlan {
        do {
            var context = PlanningContext(
                limits: request.limits,
                cancellationCheck: cancellationCheck
            )
            return try context.plan(request)
        } catch is CancellationError {
            throw ThreePaneSavePlanningError.cancelled
        } catch let error as ThreePaneSavePlanningError {
            throw error
        } catch {
            throw ThreePaneSavePlanningError.cancelled
        }
    }

    fileprivate static func validate(
        _ revision: ThreePaneSaveFileRevision,
        limits: ThreePaneSavePlanningLimits?,
        side: ThreePaneSaveSide
    ) throws {
        try validate(revision.identity, expectedKind: .regularFile, limits: limits)
        guard revision.modificationTimeNanoseconds < 1_000_000_000,
            revision.statusChangeTimeNanoseconds < 1_000_000_000,
            revision.contentSHA256.count == 32,
            revision.metadataSHA256.count == 32
        else {
            throw ThreePaneSavePlanningError.invalidFileRevision(
                revision.identity.canonicalURL.path
            )
        }
        if let limits {
            guard revision.byteCount <= limits.maximumEncodedFileBytes else {
                throw ThreePaneSavePlanningError.encodedFileTooLarge(
                    side: side,
                    maximumBytes: limits.maximumEncodedFileBytes
                )
            }
            guard revision.metadataByteCount <= limits.maximumMetadataBytes else {
                throw ThreePaneSavePlanningError.metadataTooLarge(
                    side: side,
                    maximumBytes: limits.maximumMetadataBytes
                )
            }
        }
    }

    fileprivate static func validate(
        _ identity: ThreePaneSaveCanonicalFileIdentity,
        expectedKind: ThreePaneSaveCanonicalItemKind,
        limits: ThreePaneSavePlanningLimits?
    ) throws {
        let maximumPathBytes =
            limits?.maximumPathUTF8Bytes
            ?? ThreePaneSavePlanningLimits.hardMaximumPathUTF8Bytes
        guard decodedPathUTF8ByteCount(identity.canonicalURL) <= maximumPathBytes else {
            throw ThreePaneSavePlanningError.pathTooLarge(maximumBytes: maximumPathBytes)
        }
        guard identity.kind == expectedKind,
            identity.volumeID != 0,
            identity.fileID != 0,
            isCanonicalFileURL(identity.canonicalURL),
            expectedKind != .regularFile || isRegularFileURL(identity.canonicalURL)
        else {
            throw ThreePaneSavePlanningError.invalidCanonicalIdentity(
                identity.canonicalURL.path
            )
        }
    }

    fileprivate static func decodedPathUTF8ByteCount(_ url: URL) -> Int {
        url.path(percentEncoded: false).utf8.count
    }

    fileprivate static func isCanonicalFileURL(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        guard url.isFileURL,
            url.baseURL == nil,
            url.query == nil,
            url.fragment == nil,
            path.hasPrefix("/"),
            !path.utf8.contains(0),
            url == url.standardizedFileURL,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.caseInsensitiveCompare("file") == .orderedSame,
            components.user == nil,
            components.password == nil,
            components.port == nil
        else {
            return false
        }
        guard let host = components.host else { return true }
        return host.isEmpty || host.caseInsensitiveCompare("localhost") == .orderedSame
    }

    fileprivate static func isRegularFileURL(_ url: URL) -> Bool {
        url.path(percentEncoded: false) != "/" && !url.hasDirectoryPath
    }
}

private struct PlanningContext {
    let limits: ThreePaneSavePlanningLimits
    let cancellationCheck: ThreePaneSavePlanner.CancellationCheck
    var workUnits: UInt64 = 0
    var totalPathBytes = 0

    mutating func plan(_ request: ThreePaneSaveRequest) throws -> ThreePaneSavePlan {
        try checkCancellation()
        guard request.panes.count == ThreePaneSaveSide.allCases.count else {
            throw ThreePaneSavePlanningError.invalidPaneCount(request.panes.count)
        }

        var panes: [ThreePaneSaveSide: ThreePaneSavePaneState] = [:]
        panes.reserveCapacity(request.panes.count)
        for pane in request.panes {
            try consumeWork()
            guard panes.updateValue(pane.state, forKey: pane.side) == nil else {
                throw ThreePaneSavePlanningError.duplicatePane(pane.side)
            }
            try validate(pane)
        }
        for side in ThreePaneSaveSide.allCases where panes[side] == nil {
            throw ThreePaneSavePlanningError.missingPane(side)
        }
        try validatePaneCollisions(panes)

        let selectedDestinations: [ThreePaneSaveSide: ThreePaneSaveDestinationIdentity]
        let selectedSides: [ThreePaneSaveSide]
        let savesAs: Set<ThreePaneSaveSide>
        let planID = UUID()
        switch request.action {
        case .saveMiddle(let destination):
            guard let middle = panes[.middle], let content = middle.content else {
                throw ThreePaneSavePlanningError.paneNotLoaded(.middle)
            }
            guard middle.isUntitled || content.isDirty else {
                throw ThreePaneSavePlanningError.paneNotDirty(.middle)
            }
            guard !content.isReadOnly else {
                throw ThreePaneSavePlanningError.paneReadOnly(.middle)
            }
            if let destination, destination.side != .middle {
                throw ThreePaneSavePlanningError.wrongDestinationSide(
                    expected: .middle,
                    actual: destination.side
                )
            }
            selectedDestinations = try destinationsBySide(destination.map { [$0] } ?? [])
            if middle.isUntitled {
                guard selectedDestinations[.middle] != nil else {
                    throw ThreePaneSavePlanningError.missingDestination(.middle)
                }
            } else if selectedDestinations[.middle] != nil {
                throw ThreePaneSavePlanningError.unexpectedDestination(.middle)
            }
            selectedSides = [.middle]
            savesAs = middle.isUntitled ? [.middle] : []
        case .saveAsMiddle(let destination):
            guard destination.side == .middle else {
                throw ThreePaneSavePlanningError.wrongDestinationSide(
                    expected: .middle,
                    actual: destination.side
                )
            }
            guard panes[.middle]?.content != nil else {
                throw ThreePaneSavePlanningError.paneNotLoaded(.middle)
            }
            selectedDestinations = try destinationsBySide([destination])
            selectedSides = [.middle]
            savesAs = [.middle]
        case .saveAll(let destinations):
            selectedDestinations = try destinationsBySide(destinations)
            var dirtySides: [ThreePaneSaveSide] = []
            for side in ThreePaneSaveSide.allCases {
                guard let state = panes[side], let content = state.content else {
                    throw ThreePaneSavePlanningError.paneNotLoaded(side)
                }
                if content.isDirty {
                    guard !content.isReadOnly else {
                        throw ThreePaneSavePlanningError.paneReadOnly(side)
                    }
                    dirtySides.append(side)
                    if state.isUntitled, selectedDestinations[side] == nil {
                        throw ThreePaneSavePlanningError.missingDestination(side)
                    }
                    if !state.isUntitled, selectedDestinations[side] != nil {
                        throw ThreePaneSavePlanningError.unexpectedDestination(side)
                    }
                } else if selectedDestinations[side] != nil {
                    throw ThreePaneSavePlanningError.unexpectedDestination(side)
                }
            }
            selectedSides = dirtySides
            savesAs = Set(dirtySides.filter { panes[$0]?.isUntitled == true })
        }

        guard selectedSides.count <= limits.maximumOperations else {
            throw ThreePaneSavePlanningError.tooManyOperations(
                maximum: limits.maximumOperations
            )
        }
        var operations: [ThreePaneSaveOperation] = []
        operations.reserveCapacity(selectedSides.count)
        for side in selectedSides {
            try consumeWork()
            guard let state = panes[side], let content = state.content else {
                throw ThreePaneSavePlanningError.paneNotLoaded(side)
            }
            let sourceFile: ThreePaneSaveFileBinding?
            if case .loaded(_, let file) = state { sourceFile = file } else { sourceFile = nil }
            let destination: ThreePaneSaveDestinationIdentity
            if let selected = selectedDestinations[side] {
                destination = selected
            } else if let sourceFile {
                destination = ThreePaneSaveDestinationIdentity(
                    canonicalURL: sourceFile.revision.identity.canonicalURL,
                    parentIdentity: sourceFile.parentIdentity,
                    canonicalLeafIdentity: sourceFile.canonicalLeafIdentity,
                    state: .existing(sourceFile.revision)
                )
            } else {
                throw ThreePaneSavePlanningError.missingDestination(side)
            }
            let kind: ThreePaneSaveOperationKind
            if savesAs.contains(side) {
                switch destination.state {
                case .vacant: kind = .saveAsNewFile
                case .existing: kind = .saveAsReplacingFile
                }
            } else {
                kind = .saveInPlace
            }
            operations.append(
                ThreePaneSaveOperation(
                    planID: planID,
                    side: side,
                    kind: kind,
                    source: content,
                    sourceFile: sourceFile,
                    destination: destination
                ))
        }
        try validateDestinationCollisions(operations, panes: panes)
        try checkCancellation()
        return ThreePaneSavePlan(
            operations: operations,
            estimatedWorkUnits: workUnits,
            limits: limits
        )
    }

    mutating func validate(_ pane: ThreePaneSavePane) throws {
        guard let content = pane.state.content else {
            throw ThreePaneSavePlanningError.paneNotLoaded(pane.side)
        }
        try validate(content, side: pane.side)
        switch pane.state {
        case .unloaded:
            throw ThreePaneSavePlanningError.paneNotLoaded(pane.side)
        case .untitled:
            break
        case .loaded(_, let file):
            try validate(file, side: pane.side)
            if !content.isDirty {
                guard content.encodedByteCount == file.revision.byteCount,
                    content.encodedContentSHA256 == file.revision.contentSHA256
                else {
                    throw ThreePaneSavePlanningError.invalidContentRevision(pane.side)
                }
            }
        }
    }

    mutating func validate(
        _ content: ThreePaneSaveContentRevision,
        side: ThreePaneSaveSide
    ) throws {
        guard content.encodedContentSHA256.count == 32 else {
            throw ThreePaneSavePlanningError.invalidContentRevision(side)
        }
        let hasValidEncodingMetadata =
            switch content.encoding.encoding {
            case .utf8:
                !content.encoding.hasByteOrderMark || content.encodedByteCount >= 3
            case .utf16LittleEndian, .utf16BigEndian:
                content.encodedByteCount.isMultiple(of: 2)
                    && (!content.encoding.hasByteOrderMark || content.encodedByteCount >= 2)
            case .shiftJIS, .japaneseEUC, .iso2022JP, .windows1250, .windows1251,
                .windows1252, .windows1253, .windows1254, .windows1255:
                !content.encoding.hasByteOrderMark
            }
        guard hasValidEncodingMetadata else {
            throw ThreePaneSavePlanningError.invalidEncodingMetadata(side)
        }
        guard content.encodedByteCount <= limits.maximumEncodedFileBytes else {
            throw ThreePaneSavePlanningError.encodedFileTooLarge(
                side: side,
                maximumBytes: limits.maximumEncodedFileBytes
            )
        }
    }

    mutating func validate(
        _ binding: ThreePaneSaveFileBinding,
        side: ThreePaneSaveSide
    ) throws {
        guard binding.resolvedPathKind == .direct else {
            throw ThreePaneSavePlanningError.aliasedPath(
                side: side,
                kind: binding.resolvedPathKind
            )
        }
        try validateLeaf(binding.canonicalLeafIdentity, side: side)
        try ThreePaneSavePlanner.validate(binding.revision, limits: limits, side: side)
        try ThreePaneSavePlanner.validate(
            binding.parentIdentity,
            expectedKind: .directory,
            limits: limits
        )
        try accountPath(binding.revision.identity.canonicalURL)
        try accountPath(binding.parentIdentity.canonicalURL)
        guard
            binding.revision.identity.canonicalURL.deletingLastPathComponent()
                .standardizedFileURL == binding.parentIdentity.canonicalURL
        else {
            throw ThreePaneSavePlanningError.invalidCanonicalIdentity(
                binding.revision.identity.canonicalURL.path
            )
        }
    }

    mutating func destinationsBySide(
        _ destinations: [ThreePaneSaveDestination]
    ) throws -> [ThreePaneSaveSide: ThreePaneSaveDestinationIdentity] {
        guard destinations.count <= ThreePaneSavePlanningLimits.hardMaximumOperations else {
            throw ThreePaneSavePlanningError.tooManyOperations(
                maximum: ThreePaneSavePlanningLimits.hardMaximumOperations
            )
        }
        var result: [ThreePaneSaveSide: ThreePaneSaveDestinationIdentity] = [:]
        result.reserveCapacity(destinations.count)
        for destination in destinations {
            try consumeWork()
            guard result.updateValue(destination.identity, forKey: destination.side) == nil else {
                throw ThreePaneSavePlanningError.duplicateDestination(destination.side)
            }
            try validate(destination.identity, side: destination.side)
        }
        return result
    }

    mutating func validate(
        _ destination: ThreePaneSaveDestinationIdentity,
        side: ThreePaneSaveSide
    ) throws {
        guard destination.resolvedPathKind == .direct else {
            throw ThreePaneSavePlanningError.aliasedPath(
                side: side,
                kind: destination.resolvedPathKind
            )
        }
        guard
            ThreePaneSavePlanner.decodedPathUTF8ByteCount(destination.canonicalURL)
                <= limits.maximumPathUTF8Bytes
        else {
            throw ThreePaneSavePlanningError.pathTooLarge(
                maximumBytes: limits.maximumPathUTF8Bytes
            )
        }
        guard ThreePaneSavePlanner.isCanonicalFileURL(destination.canonicalURL),
            ThreePaneSavePlanner.isRegularFileURL(destination.canonicalURL)
        else {
            throw ThreePaneSavePlanningError.invalidFileURL(
                destination.canonicalURL.absoluteString
            )
        }
        try accountPath(destination.canonicalURL)
        try ThreePaneSavePlanner.validate(
            destination.parentIdentity,
            expectedKind: .directory,
            limits: limits
        )
        try accountPath(destination.parentIdentity.canonicalURL)
        try validateLeaf(destination.canonicalLeafIdentity, side: side)
        guard destination.canonicalURL.deletingLastPathComponent().standardizedFileURL == destination.parentIdentity.canonicalURL else {
            throw ThreePaneSavePlanningError.invalidDestination(side)
        }
        if case .existing(let revision) = destination.state {
            try ThreePaneSavePlanner.validate(revision, limits: limits, side: side)
            guard revision.identity.canonicalURL == destination.canonicalURL else {
                throw ThreePaneSavePlanningError.invalidDestination(side)
            }
        }
    }

    mutating func validatePaneCollisions(
        _ panes: [ThreePaneSaveSide: ThreePaneSavePaneState]
    ) throws {
        let loaded = ThreePaneSaveSide.allCases.compactMap { side -> (ThreePaneSaveSide, ThreePaneSaveFileBinding)? in
            guard case .loaded(_, let file) = panes[side] else { return nil }
            return (side, file)
        }
        for firstIndex in loaded.indices {
            for secondIndex in loaded.indices where secondIndex > firstIndex {
                try consumeWork()
                let first = loaded[firstIndex]
                let second = loaded[secondIndex]
                if sameResource(first.1.revision.identity, second.1.revision.identity) || sameSlot(first.1, second.1) {
                    throw ThreePaneSavePlanningError.paneFileCollision(
                        first: first.0,
                        second: second.0
                    )
                }
            }
        }
    }

    mutating func validateDestinationCollisions(
        _ operations: [ThreePaneSaveOperation],
        panes: [ThreePaneSaveSide: ThreePaneSavePaneState]
    ) throws {
        for operation in operations {
            for paneSide in ThreePaneSaveSide.allCases {
                try consumeWork()
                guard case .loaded(_, let paneFile) = panes[paneSide] else { continue }
                let destination = operation.destination
                let matchesResource: Bool
                switch destination.state {
                case .vacant:
                    matchesResource = false
                case .existing(let revision):
                    matchesResource = sameResource(revision.identity, paneFile.revision.identity)
                }
                let matchesSlot = sameSlot(destination, paneFile)
                guard matchesResource || matchesSlot else { continue }
                let isExactInPlaceDestination =
                    operation.side == paneSide && operation.kind == .saveInPlace && destination == destinationIdentity(for: paneFile)
                guard isExactInPlaceDestination else {
                    throw ThreePaneSavePlanningError.destinationAliasesPane(
                        destination: operation.side,
                        pane: paneSide
                    )
                }
            }
        }
        for firstIndex in operations.indices {
            for secondIndex in operations.indices where secondIndex > firstIndex {
                try consumeWork()
                let first = operations[firstIndex]
                let second = operations[secondIndex]
                if destinationsCollide(first.destination, second.destination) {
                    throw ThreePaneSavePlanningError.destinationCollision(
                        first: first.side,
                        second: second.side
                    )
                }
            }
        }
    }

    func destinationIdentity(
        for file: ThreePaneSaveFileBinding
    ) -> ThreePaneSaveDestinationIdentity {
        ThreePaneSaveDestinationIdentity(
            canonicalURL: file.revision.identity.canonicalURL,
            parentIdentity: file.parentIdentity,
            canonicalLeafIdentity: file.canonicalLeafIdentity,
            state: .existing(file.revision)
        )
    }

    func destinationsCollide(
        _ first: ThreePaneSaveDestinationIdentity,
        _ second: ThreePaneSaveDestinationIdentity
    ) -> Bool {
        if sameSlot(first, second) { return true }
        guard case .existing(let firstRevision) = first.state,
            case .existing(let secondRevision) = second.state
        else {
            return false
        }
        return sameResource(firstRevision.identity, secondRevision.identity)
    }

    func sameResource(
        _ first: ThreePaneSaveCanonicalFileIdentity,
        _ second: ThreePaneSaveCanonicalFileIdentity
    ) -> Bool {
        first.volumeID == second.volumeID && first.fileID == second.fileID && first.generation == second.generation
    }

    func sameSlot(
        _ first: ThreePaneSaveFileBinding,
        _ second: ThreePaneSaveFileBinding
    ) -> Bool {
        sameResource(first.parentIdentity, second.parentIdentity) && first.canonicalLeafIdentity == second.canonicalLeafIdentity
            || first.revision.identity.canonicalURL == second.revision.identity.canonicalURL
    }

    func sameSlot(
        _ destination: ThreePaneSaveDestinationIdentity,
        _ file: ThreePaneSaveFileBinding
    ) -> Bool {
        sameResource(destination.parentIdentity, file.parentIdentity) && destination.canonicalLeafIdentity == file.canonicalLeafIdentity
            || destination.canonicalURL == file.revision.identity.canonicalURL
    }

    func sameSlot(
        _ first: ThreePaneSaveDestinationIdentity,
        _ second: ThreePaneSaveDestinationIdentity
    ) -> Bool {
        sameResource(first.parentIdentity, second.parentIdentity) && first.canonicalLeafIdentity == second.canonicalLeafIdentity
            || first.canonicalURL == second.canonicalURL
    }

    mutating func validateLeaf(
        _ identity: String,
        side: ThreePaneSaveSide
    ) throws {
        guard !identity.isEmpty,
            !identity.utf8.contains(0),
            identity.utf8.count <= limits.maximumCanonicalLeafIdentityUTF8Bytes
        else {
            throw ThreePaneSavePlanningError.invalidCanonicalLeafIdentity(side)
        }
    }

    mutating func accountPath(_ url: URL) throws {
        let count = ThreePaneSavePlanner.decodedPathUTF8ByteCount(url)
        guard count <= limits.maximumPathUTF8Bytes else {
            throw ThreePaneSavePlanningError.pathTooLarge(
                maximumBytes: limits.maximumPathUTF8Bytes
            )
        }
        guard count <= limits.maximumTotalPathUTF8Bytes - totalPathBytes else {
            throw ThreePaneSavePlanningError.totalPathsTooLarge(
                maximumBytes: limits.maximumTotalPathUTF8Bytes
            )
        }
        totalPathBytes += count
    }

    mutating func consumeWork(_ amount: UInt64 = 1) throws {
        guard amount <= limits.maximumWorkUnits - workUnits else {
            throw ThreePaneSavePlanningError.workLimitExceeded(
                maximumUnits: limits.maximumWorkUnits
            )
        }
        workUnits += amount
        try checkCancellation()
    }

    func checkCancellation() throws {
        try cancellationCheck()
    }
}
