import CoreFoundation
import CryptoKit
import Darwin
import Foundation

public struct PatchGenerationSourceID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum PatchGenerationCanonicalItemKind: String, Equatable, Hashable, Sendable {
    case regularFile
    case directory
}

/// Caller-captured identity for one canonical filesystem node.
///
/// Planning never resolves this URL or accesses the node. Executors must pin and compare the
/// descriptor identity rather than trusting the URL as authority.
public struct PatchGenerationCanonicalFileIdentity: Equatable, Hashable, Sendable {
    public let canonicalURL: URL
    public let kind: PatchGenerationCanonicalItemKind
    public let deviceID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    public init(
        canonicalURL: URL,
        kind: PatchGenerationCanonicalItemKind,
        deviceID: UInt64,
        fileID: UInt64,
        generation: UInt32
    ) {
        self.canonicalURL = canonicalURL
        self.kind = kind
        self.deviceID = deviceID
        self.fileID = fileID
        self.generation = generation
    }
}

/// Exact caller-captured revision of an existing regular file.
public struct PatchGenerationFileRevision: Equatable, Hashable, Sendable {
    public let identity: PatchGenerationCanonicalFileIdentity
    public let byteCount: UInt64
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
    /// Digest of executor-defined complete preserved metadata, including ACLs and extended attributes.
    public let metadataSHA256: [UInt8]

    public init(
        identity: PatchGenerationCanonicalFileIdentity,
        byteCount: UInt64,
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

public enum PatchGenerationSnapshotIdentity: Equatable, Hashable, Sendable {
    case document(UUID)
    case scratchpad(UUID)
    case clipboard(contentID: String)
    case file(PatchGenerationCanonicalFileIdentity)
}

/// Immutable decoded text and exact owner revision used for generation.
///
/// For each identity, owners must issue opaque, monotonically advancing, never-reused revisions.
public struct PatchGenerationTextSnapshot: Equatable, Sendable {
    public let identity: PatchGenerationSnapshotIdentity
    public let revision: UInt64
    public let text: String

    public init(
        identity: PatchGenerationSnapshotIdentity,
        revision: UInt64,
        text: String
    ) {
        self.identity = identity
        self.revision = revision
        self.text = text
    }
}

public struct PatchGenerationSource: Equatable, Sendable {
    public let id: PatchGenerationSourceID
    public let oldSnapshot: PatchGenerationTextSnapshot
    public let newSnapshot: PatchGenerationTextSnapshot
    public let oldPath: String
    public let newPath: String

    public init(
        id: PatchGenerationSourceID,
        oldSnapshot: PatchGenerationTextSnapshot,
        newSnapshot: PatchGenerationTextSnapshot,
        oldPath: String,
        newPath: String
    ) {
        self.id = id
        self.oldSnapshot = oldSnapshot
        self.newSnapshot = newSnapshot
        self.oldPath = oldPath
        self.newPath = newPath
    }
}

public enum PatchGenerationSourceSelection: Equatable, Sendable {
    case all
    /// Explicit output order. Duplicate or unknown identifiers are rejected.
    case only([PatchGenerationSourceID])
}

/// Strict format supported by `PatchGenerator`.
public enum PatchGenerationStyle: String, CaseIterable, Equatable, Hashable, Sendable {
    case unified
}

public enum PatchGenerationDirection: String, CaseIterable, Equatable, Hashable, Sendable {
    case forward
    case reverse
}

/// Existing bytes accompany their exact revision so append planning needs no filesystem read.
public struct PatchGenerationExistingFileSnapshot: Equatable, Sendable {
    public let revision: PatchGenerationFileRevision
    /// Planner-owned bytes. Construction always detaches caller-provided storage in checked chunks.
    public let data: Data

    public init(revision: PatchGenerationFileRevision, data: Data) throws {
        guard data.count <= PatchGenerationPlanningLimits.hardMaximumExistingFileBytes else {
            throw PatchGenerationPlanningError.existingFileTooLarge(
                maximumBytes: PatchGenerationPlanningLimits.hardMaximumExistingFileBytes
            )
        }
        self.revision = revision
        self.data = try patchGenerationOwnedData(data)
    }
}

public enum PatchGenerationFileDisposition: Equatable, Sendable {
    /// Publish only if the leaf is absent under this exact parent identity.
    case createNew(parentIdentity: PatchGenerationCanonicalFileIdentity)
    /// Replace only this exact existing revision.
    case overwrite(
        expectedParent: PatchGenerationCanonicalFileIdentity,
        expected: PatchGenerationFileRevision
    )
    /// Compose complete successor bytes and replace only this exact existing revision.
    case append(
        expectedParent: PatchGenerationCanonicalFileIdentity,
        expected: PatchGenerationExistingFileSnapshot,
        lineEnding: LineEnding
    )
}

public struct PatchGenerationFileDestination: Equatable, Sendable {
    public let url: URL
    public let disposition: PatchGenerationFileDisposition

    public init(url: URL, disposition: PatchGenerationFileDisposition) {
        self.url = url
        self.disposition = disposition
    }
}

public struct PatchGenerationClipboardBrokerIdentifier: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct PatchGenerationClipboardBrokerEpoch: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Broker-scoped revision. Epoch rotation prevents a restarted pasteboard service from reusing an
/// otherwise equal platform change count.
public struct PatchGenerationClipboardRevision: Equatable, Hashable, Sendable {
    public let brokerIdentifier: PatchGenerationClipboardBrokerIdentifier
    public let epoch: PatchGenerationClipboardBrokerEpoch
    public let value: UInt64

    public init(
        brokerIdentifier: PatchGenerationClipboardBrokerIdentifier,
        epoch: PatchGenerationClipboardBrokerEpoch,
        value: UInt64
    ) {
        self.brokerIdentifier = brokerIdentifier
        self.epoch = epoch
        self.value = value
    }
}

/// Revision issued by the same exclusive broker that will perform publication.
public struct PatchGenerationClipboardDestination: Equatable, Sendable {
    public let expectedRevision: PatchGenerationClipboardRevision

    public init(expectedRevision: PatchGenerationClipboardRevision) {
        self.expectedRevision = expectedRevision
    }
}

public enum PatchGenerationDestination: Equatable, Sendable {
    case file(PatchGenerationFileDestination)
    case clipboard(PatchGenerationClipboardDestination)
}

/// Display or provenance metadata only. It is structurally unavailable to publication and editor
/// dispatch executors. Entries remain argv-shaped values and are never joined as a shell command.
public enum PatchGenerationCommandLineIntent: Equatable, Sendable {
    case none
    case record(arguments: [String])
}

/// Advisory intent only. It identifies a separately configured `ExternalToolPolicy` rule. The rule
/// receives only a descriptor-bound committed-file authorization, never command-line metadata.
public enum PatchGenerationExternalEditorIntent: Equatable, Sendable {
    case none
    case openFile(ruleIdentifier: String)
}

public struct PatchGenerationPresentationIntent: Equatable, Sendable {
    public static let none = PatchGenerationPresentationIntent()

    public let commandLine: PatchGenerationCommandLineIntent
    public let externalEditor: PatchGenerationExternalEditorIntent

    public init(
        commandLine: PatchGenerationCommandLineIntent = .none,
        externalEditor: PatchGenerationExternalEditorIntent = .none
    ) {
        self.commandLine = commandLine
        self.externalEditor = externalEditor
    }
}

public enum PatchGenerationPlanningLimit: String, CaseIterable, Equatable, Hashable, Sendable {
    case sources
    case selectedSources
    case sourceIdentifierUTF8Bytes
    case pathUTF8Bytes
    case totalPathUTF8Bytes
    case inputBytes
    case combinedInputBytes
    case existingFileBytes
    case existingFileMetadataBytes
    case patchBytes
    case destinationPayloadBytes
    case planOutputBytes
    case contextLines
    case commandLineArguments
    case commandLineArgumentUTF8Bytes
    case totalCommandLineUTF8Bytes
    case externalRuleIdentifierUTF8Bytes
    case workUnits
}

public struct PatchGenerationPlanningLimits: Equatable, Sendable {
    public static let hardMaximumSourceCount = 4_096
    public static let hardMaximumSourceIdentifierUTF8Bytes = 256
    public static let hardMaximumPathUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumInputBytes = 64 * 1_024 * 1_024
    public static let hardMaximumCombinedInputBytes = 128 * 1_024 * 1_024
    public static let hardMaximumExistingFileBytes = 256 * 1_024 * 1_024
    public static let hardMaximumExistingFileMetadataBytes = 64 * 1_024 * 1_024
    public static let hardMaximumPatchBytes = 256 * 1_024 * 1_024
    public static let hardMaximumDestinationPayloadBytes = 512 * 1_024 * 1_024
    public static let hardMaximumPlanOutputBytes = 768 * 1_024 * 1_024
    public static let hardMaximumContextLines = 1_048_576
    public static let hardMaximumCommandLineArgumentCount = 4_096
    public static let hardMaximumCommandLineArgumentUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalCommandLineUTF8Bytes = 4 * 1_024 * 1_024
    public static let hardMaximumExternalRuleIdentifierUTF8Bytes = 128
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let `default` = PatchGenerationPlanningLimits()

    public let maximumSources: Int
    public let maximumSelectedSources: Int
    public let maximumSourceIdentifierUTF8Bytes: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumInputBytes: Int
    public let maximumCombinedInputBytes: Int
    public let maximumExistingFileBytes: Int
    public let maximumExistingFileMetadataBytes: Int
    public let maximumPatchBytes: Int
    public let maximumDestinationPayloadBytes: Int
    public let maximumPlanOutputBytes: Int
    public let maximumContextLines: Int
    public let maximumCommandLineArgumentCount: Int
    public let maximumCommandLineArgumentUTF8Bytes: Int
    public let maximumTotalCommandLineUTF8Bytes: Int
    public let maximumExternalRuleIdentifierUTF8Bytes: Int
    /// Includes bounded scans, digesting, output materialization, and a conservative line-pair cost.
    public let maximumWorkUnits: UInt64

    public init(
        maximumSources: Int = 1_024,
        maximumSelectedSources: Int = 1_024,
        maximumSourceIdentifierUTF8Bytes: Int = 256,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumInputBytes: Int = 64 * 1_024 * 1_024,
        maximumCombinedInputBytes: Int = 128 * 1_024 * 1_024,
        maximumExistingFileBytes: Int = 64 * 1_024 * 1_024,
        maximumExistingFileMetadataBytes: Int = 16 * 1_024 * 1_024,
        maximumPatchBytes: Int = 64 * 1_024 * 1_024,
        maximumDestinationPayloadBytes: Int = 128 * 1_024 * 1_024,
        maximumPlanOutputBytes: Int = 192 * 1_024 * 1_024,
        maximumContextLines: Int = 1_048_576,
        maximumCommandLineArgumentCount: Int = 256,
        maximumCommandLineArgumentUTF8Bytes: Int = 64 * 1_024,
        maximumTotalCommandLineUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumExternalRuleIdentifierUTF8Bytes: Int = 128,
        maximumWorkUnits: UInt64 = 2 * 1_024 * 1_024 * 1_024
    ) {
        self.maximumSources = maximumSources
        self.maximumSelectedSources = maximumSelectedSources
        self.maximumSourceIdentifierUTF8Bytes = maximumSourceIdentifierUTF8Bytes
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumInputBytes = maximumInputBytes
        self.maximumCombinedInputBytes = maximumCombinedInputBytes
        self.maximumExistingFileBytes = maximumExistingFileBytes
        self.maximumExistingFileMetadataBytes = maximumExistingFileMetadataBytes
        self.maximumPatchBytes = maximumPatchBytes
        self.maximumDestinationPayloadBytes = maximumDestinationPayloadBytes
        self.maximumPlanOutputBytes = maximumPlanOutputBytes
        self.maximumContextLines = maximumContextLines
        self.maximumCommandLineArgumentCount = maximumCommandLineArgumentCount
        self.maximumCommandLineArgumentUTF8Bytes = maximumCommandLineArgumentUTF8Bytes
        self.maximumTotalCommandLineUTF8Bytes = maximumTotalCommandLineUTF8Bytes
        self.maximumExternalRuleIdentifierUTF8Bytes = maximumExternalRuleIdentifierUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
    }
}

public struct PatchGenerationRequest: Equatable, Sendable {
    public let sources: [PatchGenerationSource]
    public let selection: PatchGenerationSourceSelection
    public let style: PatchGenerationStyle
    public let contextLines: Int
    public let direction: PatchGenerationDirection
    public let destination: PatchGenerationDestination
    public let presentationIntent: PatchGenerationPresentationIntent
    public let limits: PatchGenerationPlanningLimits

    public init(
        sources: [PatchGenerationSource],
        selection: PatchGenerationSourceSelection = .all,
        style: PatchGenerationStyle = .unified,
        contextLines: Int = 3,
        direction: PatchGenerationDirection = .forward,
        destination: PatchGenerationDestination,
        presentationIntent: PatchGenerationPresentationIntent = .none,
        limits: PatchGenerationPlanningLimits = .default
    ) {
        self.sources = sources
        self.selection = selection
        self.style = style
        self.contextLines = contextLines
        self.direction = direction
        self.destination = destination
        self.presentationIntent = presentationIntent
        self.limits = limits
    }
}

public enum PatchGenerationPlanningError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(PatchGenerationPlanningLimit)
    case tooManySources(maximum: Int)
    case tooManySelectedSources(maximum: Int)
    case invalidSourceIdentifier(String)
    case duplicateSourceIdentifier(String)
    case duplicateSelectionIdentifier(String)
    case unknownSourceIdentifier(String)
    case emptySelection
    case invalidSnapshotMetadata
    case conflictingSnapshotRevision
    case invalidPatchPath(String)
    case pathTooLarge(maximumBytes: Int)
    case totalPathsTooLarge(maximumBytes: Int)
    case inputTooLarge(source: PatchGenerationSourceID, maximumBytes: Int)
    case combinedInputTooLarge(maximumBytes: Int)
    case invalidContextLines(Int)
    case unsupportedStyle(PatchGenerationStyle)
    case workLimitExceeded(maximumUnits: UInt64)
    case patchTooLarge(maximumBytes: Int)
    case noDifferences
    case invalidFileURL(String)
    case invalidCanonicalFileIdentity(String)
    case invalidFileRevision(String)
    case destinationIdentityMismatch(String)
    case existingFileTooLarge(maximumBytes: Int)
    case existingFileMetadataTooLarge(maximumBytes: Int)
    case existingFileSnapshotMismatch(String)
    case destinationPayloadTooLarge(maximumBytes: Int)
    case planOutputTooLarge(maximumBytes: Int)
    case invalidCommandLineIntent
    case commandLineIntentTooLarge(maximumBytes: Int)
    case invalidExternalEditorIntent
    case externalEditorRequiresFileDestination
    case ambiguousSourcePathDependency(first: PatchGenerationSourceID, second: PatchGenerationSourceID)
    case sourcePathDependencySnapshotMismatch(first: PatchGenerationSourceID, second: PatchGenerationSourceID)
    case sourcePathDependencyCycle
    case sourcePathDependencyOrderConflict(first: PatchGenerationSourceID, second: PatchGenerationSourceID)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Patch generation was cancelled."
        case .invalidLimit(let limit):
            "Invalid patch-generation limit: \(limit.rawValue)."
        case .tooManySources(let maximum):
            "Patch generation exceeds the \(maximum)-source limit."
        case .tooManySelectedSources(let maximum):
            "Patch generation exceeds the \(maximum)-selected-source limit."
        case .invalidSourceIdentifier(let identifier):
            "Invalid patch source identifier: \(identifier)."
        case .duplicateSourceIdentifier(let identifier):
            "Duplicate patch source identifier: \(identifier)."
        case .duplicateSelectionIdentifier(let identifier):
            "Duplicate selected patch source identifier: \(identifier)."
        case .unknownSourceIdentifier(let identifier):
            "Unknown selected patch source identifier: \(identifier)."
        case .emptySelection:
            "Patch generation requires at least one selected source."
        case .invalidSnapshotMetadata:
            "Patch source snapshot metadata is invalid."
        case .conflictingSnapshotRevision:
            "One patch snapshot identity and revision has conflicting text."
        case .invalidPatchPath(let path):
            "Invalid patch header path: \(path)."
        case .pathTooLarge(let maximumBytes):
            "A patch-generation path exceeds the \(maximumBytes)-byte limit."
        case .totalPathsTooLarge(let maximumBytes):
            "Patch-generation paths exceed the \(maximumBytes)-byte aggregate limit."
        case .inputTooLarge(let source, let maximumBytes):
            "Patch source \(source.rawValue) exceeds the \(maximumBytes)-byte input limit."
        case .combinedInputTooLarge(let maximumBytes):
            "Patch source text exceeds the \(maximumBytes)-byte combined input limit."
        case .invalidContextLines(let value):
            "Patch context line count is invalid: \(value)."
        case .unsupportedStyle(let style):
            "Unsupported patch style: \(style.rawValue)."
        case .workLimitExceeded(let maximumUnits):
            "Patch planning exceeds the \(maximumUnits)-unit work limit."
        case .patchTooLarge(let maximumBytes):
            "Generated patch exceeds the \(maximumBytes)-byte limit."
        case .noDifferences:
            "Selected sources contain no differences."
        case .invalidFileURL(let value):
            "Patch destination is not a strict absolute local file URL: \(value)."
        case .invalidCanonicalFileIdentity(let path):
            "Patch file identity is not canonical: \(path)."
        case .invalidFileRevision(let path):
            "Patch file revision is invalid: \(path)."
        case .destinationIdentityMismatch(let path):
            "Patch destination does not match its expected identity: \(path)."
        case .existingFileTooLarge(let maximumBytes):
            "Existing patch file exceeds the \(maximumBytes)-byte limit."
        case .existingFileMetadataTooLarge(let maximumBytes):
            "Existing patch file metadata exceeds the \(maximumBytes)-byte limit."
        case .existingFileSnapshotMismatch(let path):
            "Existing patch bytes do not match their exact revision: \(path)."
        case .destinationPayloadTooLarge(let maximumBytes):
            "Patch destination payload exceeds the \(maximumBytes)-byte limit."
        case .planOutputTooLarge(let maximumBytes):
            "Patch plan output exceeds the \(maximumBytes)-byte limit."
        case .invalidCommandLineIntent:
            "Patch command-line intent must contain bounded, NUL-free argv values."
        case .commandLineIntentTooLarge(let maximumBytes):
            "Patch command-line intent exceeds the \(maximumBytes)-byte limit."
        case .invalidExternalEditorIntent:
            "Patch external-editor intent must reference a valid policy rule identifier."
        case .externalEditorRequiresFileDestination:
            "Patch external-editor intent requires a file destination."
        case .ambiguousSourcePathDependency(let first, let second):
            "Patch sources \(first.rawValue) and \(second.rawValue) have an ambiguous path dependency."
        case .sourcePathDependencySnapshotMismatch(let first, let second):
            "Patch sources \(first.rawValue) and \(second.rawValue) share a path without an identical boundary snapshot."
        case .sourcePathDependencyCycle:
            "Patch source path dependencies contain a cycle."
        case .sourcePathDependencyOrderConflict(let first, let second):
            "Patch source \(first.rawValue) must precede dependent source \(second.rawValue)."
        }
    }
}

public struct PatchGenerationSnapshotReference: Equatable, Sendable {
    public let identity: PatchGenerationSnapshotIdentity
    public let revision: UInt64
    public let utf8ByteCount: Int
    public let contentSHA256: [UInt8]

    fileprivate init(
        snapshot: PatchGenerationTextSnapshot,
        utf8ByteCount: Int,
        contentSHA256: [UInt8]
    ) {
        identity = snapshot.identity
        revision = snapshot.revision
        self.utf8ByteCount = utf8ByteCount
        self.contentSHA256 = contentSHA256
    }
}

public struct PatchGenerationPlannedSource: Equatable, Sendable {
    public let id: PatchGenerationSourceID
    public let oldSnapshot: PatchGenerationSnapshotReference
    public let newSnapshot: PatchGenerationSnapshotReference
    public let oldPath: String
    public let newPath: String

    fileprivate init(
        source: PatchGenerationSource,
        oldSnapshot: PatchGenerationSnapshotReference,
        newSnapshot: PatchGenerationSnapshotReference
    ) {
        id = source.id
        self.oldSnapshot = oldSnapshot
        self.newSnapshot = newSnapshot
        oldPath = source.oldPath
        newPath = source.newPath
    }
}

public enum PatchGenerationPlannedFileOperation: Equatable, Sendable {
    case createNew(expectedParent: PatchGenerationCanonicalFileIdentity)
    case overwrite(
        expectedParent: PatchGenerationCanonicalFileIdentity,
        expected: PatchGenerationFileRevision
    )
    case append(
        expectedParent: PatchGenerationCanonicalFileIdentity,
        expected: PatchGenerationFileRevision
    )
}

public struct PatchGenerationPlannedFileDestination: Equatable, Sendable {
    public let url: URL
    public let operation: PatchGenerationPlannedFileOperation
    /// Complete successor bytes. Append executors must replace with these bytes, never append in place.
    public let payload: Data
    /// Staging always starts at `0600`. This mode is applied only after complete staging and metadata
    /// verification, immediately before publication.
    public let finalPermissions: UInt16

    fileprivate init(
        url: URL,
        operation: PatchGenerationPlannedFileOperation,
        payload: Data,
        finalPermissions: UInt16
    ) {
        self.url = url
        self.operation = operation
        self.payload = payload
        self.finalPermissions = finalPermissions
    }
}

public enum PatchGenerationPlannedDestination: Equatable, Sendable {
    case file(PatchGenerationPlannedFileDestination)
    case clipboard(expectedRevision: PatchGenerationClipboardRevision, text: String)
}

public enum PatchGenerationSourceRevalidationContract: String, Equatable, Hashable, Sendable {
    case immutablePinOrRevisionLeaseHeldThroughCommit
}

public enum PatchGenerationPathResolutionContract: String, Equatable, Hashable, Sendable {
    case descriptorRelativeNoFollowFromPinnedCanonicalParent
}

public enum PatchGenerationFilePublicationContract: String, Equatable, Hashable, Sendable {
    case privateStageSyncThenLeaseOrFullRevisionCASPublishAndSyncParent
}

public enum PatchGenerationFileTypeContract: String, Equatable, Hashable, Sendable {
    case regularFileOnlyAndNonBlockingDescriptorAccess
}

public enum PatchGenerationMetadataContract: String, Equatable, Hashable, Sendable {
    case preserveAndVerifyModeOwnerGroupFlagsACLsAndExtendedAttributes
}

public enum PatchGenerationExistingDestinationContract: String, Equatable, Hashable, Sendable {
    case exactIdentityRevisionAndDigestHeldThroughPublication
}

public enum PatchGenerationNewDestinationContract: String, Equatable, Hashable, Sendable {
    case exactParentIdentityAndExclusiveCreate
}

public enum PatchGenerationClipboardPublicationContract: String, Equatable, Hashable, Sendable {
    case exclusiveBrokerEpochRevisionCompareAndReplaceAtomically
}

public enum PatchGenerationCancellationContract: String, Equatable, Hashable, Sendable {
    case noMutationBeforePublicationAndCommittedOrUncertainAfterPublicationStarts
    case noMutationBeforePublicationAndCommittedSealedCompareMissOrUncertainAfterPublicationStarts
}

public enum PatchGenerationIntentExecutionContract: String, Equatable, Hashable, Sendable {
    case displayArgvNeverExecutedAndEditorUsesDescriptorReceiptAfterCommit
}

public enum PatchGenerationStagingProtectionContract: String, Equatable, Hashable, Sendable {
    case privateDirectory0700AndLeaf0600WithoutBroadInheritedACL
}

public enum PatchGenerationStagingCleanupContract: String, Equatable, Hashable, Sendable {
    case descriptorAndStableIdentityBoundBeforePublicationOnly
}

public enum PatchGenerationDestinationMutationContract: String, Equatable, Hashable, Sendable {
    case continuousRevisionLeaseOrAtomicDescriptorRelativeFullRevisionCAS
}

/// Mandatory mutation-boundary behavior. URL validate-then-write and in-place append are nonconforming.
public struct PatchGenerationExecutorContract: Equatable, Hashable, Sendable {
    public static let required = PatchGenerationExecutorContract()
    public static let stagingDirectoryPermissions: UInt16 = 0o700
    public static let stagingFilePermissions: UInt16 = 0o600

    public let sourceRevalidation =
        PatchGenerationSourceRevalidationContract.immutablePinOrRevisionLeaseHeldThroughCommit
    public let pathResolution =
        PatchGenerationPathResolutionContract.descriptorRelativeNoFollowFromPinnedCanonicalParent
    public let filePublication =
        PatchGenerationFilePublicationContract.privateStageSyncThenLeaseOrFullRevisionCASPublishAndSyncParent
    public let fileType =
        PatchGenerationFileTypeContract.regularFileOnlyAndNonBlockingDescriptorAccess
    public let metadata =
        PatchGenerationMetadataContract.preserveAndVerifyModeOwnerGroupFlagsACLsAndExtendedAttributes
    public let existingDestination =
        PatchGenerationExistingDestinationContract.exactIdentityRevisionAndDigestHeldThroughPublication
    public let newDestination =
        PatchGenerationNewDestinationContract.exactParentIdentityAndExclusiveCreate
    public let clipboardPublication =
        PatchGenerationClipboardPublicationContract.exclusiveBrokerEpochRevisionCompareAndReplaceAtomically
    public let cancellation =
        PatchGenerationCancellationContract.noMutationBeforePublicationAndCommittedSealedCompareMissOrUncertainAfterPublicationStarts
    public let intentExecution =
        PatchGenerationIntentExecutionContract.displayArgvNeverExecutedAndEditorUsesDescriptorReceiptAfterCommit
    public let stagingProtection =
        PatchGenerationStagingProtectionContract.privateDirectory0700AndLeaf0600WithoutBroadInheritedACL
    public let stagingCleanup =
        PatchGenerationStagingCleanupContract.descriptorAndStableIdentityBoundBeforePublicationOnly
    public let destinationMutation =
        PatchGenerationDestinationMutationContract.continuousRevisionLeaseOrAtomicDescriptorRelativeFullRevisionCAS

    public init() {}
}

/// Display-only metadata. No executor or dispatcher API accepts this type.
public struct PatchGenerationDisplayMetadata: Equatable, Sendable {
    public let commandLine: PatchGenerationCommandLineIntent

    fileprivate init(commandLine: PatchGenerationCommandLineIntent) {
        self.commandLine = commandLine
    }
}

/// Editor rule selected during planning. It becomes dispatchable only when combined with a matching
/// committed-file authorization issued from a verified publication receipt.
public struct PatchGenerationPlannedEditor: Equatable, Sendable {
    public let ruleIdentifier: String

    fileprivate init(ruleIdentifier: String) {
        self.ruleIdentifier = ruleIdentifier
    }
}

/// Mutation-only view. Publication executors cannot access display command-line metadata.
public struct PatchGenerationMutationPlan: Equatable, Sendable {
    public let sources: [PatchGenerationPlannedSource]
    public let style: PatchGenerationStyle
    public let contextLines: Int
    public let direction: PatchGenerationDirection
    public let generatedPatch: String
    public let generatedPatchUTF8ByteCount: Int
    public let generatedPatchSHA256: [UInt8]
    /// Canonical length-framed digest of execution-relevant plan fields.
    public let planSHA256: [UInt8]
    public let destination: PatchGenerationPlannedDestination
    public let editor: PatchGenerationPlannedEditor?
    public let executorContract: PatchGenerationExecutorContract
    public let estimatedWorkUnits: UInt64
    public let limits: PatchGenerationPlanningLimits

    fileprivate init(
        sources: [PatchGenerationPlannedSource],
        style: PatchGenerationStyle,
        contextLines: Int,
        direction: PatchGenerationDirection,
        generatedPatch: String,
        generatedPatchUTF8ByteCount: Int,
        generatedPatchSHA256: [UInt8],
        planSHA256: [UInt8],
        destination: PatchGenerationPlannedDestination,
        editor: PatchGenerationPlannedEditor?,
        estimatedWorkUnits: UInt64,
        limits: PatchGenerationPlanningLimits
    ) {
        self.sources = sources
        self.style = style
        self.contextLines = contextLines
        self.direction = direction
        self.generatedPatch = generatedPatch
        self.generatedPatchUTF8ByteCount = generatedPatchUTF8ByteCount
        self.generatedPatchSHA256 = generatedPatchSHA256
        self.planSHA256 = planSHA256
        self.destination = destination
        self.editor = editor
        executorContract = .required
        self.estimatedWorkUnits = estimatedWorkUnits
        self.limits = limits
    }
}

/// Complete immutable output. Creating this value performs no filesystem, pasteboard, UI, or process mutation.
public struct PatchGenerationPlan: Equatable, Sendable {
    public let mutation: PatchGenerationMutationPlan
    public let displayMetadata: PatchGenerationDisplayMetadata

    public var sources: [PatchGenerationPlannedSource] { mutation.sources }
    public var style: PatchGenerationStyle { mutation.style }
    public var contextLines: Int { mutation.contextLines }
    public var direction: PatchGenerationDirection { mutation.direction }
    public var generatedPatch: String { mutation.generatedPatch }
    public var generatedPatchUTF8ByteCount: Int { mutation.generatedPatchUTF8ByteCount }
    public var destination: PatchGenerationPlannedDestination { mutation.destination }
    public var editor: PatchGenerationPlannedEditor? { mutation.editor }
    public var executorContract: PatchGenerationExecutorContract { mutation.executorContract }
    public var estimatedWorkUnits: UInt64 { mutation.estimatedWorkUnits }
    public var limits: PatchGenerationPlanningLimits { mutation.limits }

    fileprivate init(
        sources: [PatchGenerationPlannedSource],
        style: PatchGenerationStyle,
        contextLines: Int,
        direction: PatchGenerationDirection,
        generatedPatch: String,
        generatedPatchUTF8ByteCount: Int,
        generatedPatchSHA256: [UInt8],
        planSHA256: [UInt8],
        destination: PatchGenerationPlannedDestination,
        presentationIntent: PatchGenerationPresentationIntent,
        estimatedWorkUnits: UInt64,
        limits: PatchGenerationPlanningLimits
    ) {
        let editor: PatchGenerationPlannedEditor?
        switch presentationIntent.externalEditor {
        case .none:
            editor = nil
        case .openFile(let ruleIdentifier):
            editor = PatchGenerationPlannedEditor(ruleIdentifier: ruleIdentifier)
        }
        mutation = PatchGenerationMutationPlan(
            sources: sources,
            style: style,
            contextLines: contextLines,
            direction: direction,
            generatedPatch: generatedPatch,
            generatedPatchUTF8ByteCount: generatedPatchUTF8ByteCount,
            generatedPatchSHA256: generatedPatchSHA256,
            planSHA256: planSHA256,
            destination: destination,
            editor: editor,
            estimatedWorkUnits: estimatedWorkUnits,
            limits: limits
        )
        displayMetadata = PatchGenerationDisplayMetadata(commandLine: presentationIntent.commandLine)
    }
}

public enum PatchGenerationWorkflow: Sendable {
    // PatchGenerator has no cancellation callback. Keep its complete parse and native diff call
    // inside this fixed, request-independent envelope; all larger work fails before entering it.
    private static let maximumAtomicGeneratorInputBytes = 1 * 1_024 * 1_024
    private static let maximumAtomicGeneratorLinePairs: UInt64 = 4 * 1_024 * 1_024

    public static func plan(_ request: PatchGenerationRequest) throws -> PatchGenerationPlan {
        do {
            return try makePlan(request)
        } catch is CancellationError {
            throw PatchGenerationPlanningError.cancelled
        }
    }

    private static func makePlan(_ request: PatchGenerationRequest) throws -> PatchGenerationPlan {
        try Task.checkCancellation()
        try validate(request.limits)
        guard request.contextLines >= 0,
            request.contextLines <= request.limits.maximumContextLines
        else {
            throw PatchGenerationPlanningError.invalidContextLines(request.contextLines)
        }
        guard request.style == .unified else {
            throw PatchGenerationPlanningError.unsupportedStyle(request.style)
        }

        var work = PatchGenerationWorkBudget(maximum: request.limits.maximumWorkUnits)
        try work.consume(UInt64(request.limits.maximumTotalPathUTF8Bytes))
        let selectedSources = try selectSources(
            request.sources,
            selection: request.selection,
            limits: request.limits,
            work: &work
        )
        var retainedPlanBytes = try addBounded(
            try validatePresentationIntent(
                request.presentationIntent,
                destination: request.destination,
                limits: request.limits,
                work: &work
            ),
            to: 512,
            maximum: request.limits.maximumPlanOutputBytes,
            error: .planOutputTooLarge(maximumBytes: request.limits.maximumPlanOutputBytes)
        )
        // Reserve worst-case materialization before generation and successor composition.
        try work.consume(UInt64(request.limits.maximumPatchBytes))
        try work.consume(UInt64(request.limits.maximumDestinationPayloadBytes))

        var totalInputBytes = 0
        var totalPathBytes = 0
        var preparedSources: [PreparedSource] = []
        preparedSources.reserveCapacity(selectedSources.count)
        var referencesByRevision: [PatchGenerationSnapshotKey: PatchGenerationSnapshotReference] = [:]
        referencesByRevision.reserveCapacity(selectedSources.count * 2)

        for source in selectedSources {
            try Task.checkCancellation()
            let oldIdentityPathBytes = try validate(
                snapshotIdentity: source.oldSnapshot.identity,
                limits: request.limits,
                work: &work
            )
            let newIdentityPathBytes = try validate(
                snapshotIdentity: source.newSnapshot.identity,
                limits: request.limits,
                work: &work
            )
            let oldPathBytes = try validatePatchPath(
                source.oldPath,
                limits: request.limits,
                work: &work
            )
            let newPathBytes = try validatePatchPath(
                source.newPath,
                limits: request.limits,
                work: &work
            )
            for pathBytes in [oldIdentityPathBytes, newIdentityPathBytes, oldPathBytes, newPathBytes] {
                totalPathBytes = try addBounded(
                    pathBytes,
                    to: totalPathBytes,
                    maximum: request.limits.maximumTotalPathUTF8Bytes,
                    error: .totalPathsTooLarge(
                        maximumBytes: request.limits.maximumTotalPathUTF8Bytes
                    )
                )
            }

            let remainingInputBytes = request.limits.maximumCombinedInputBytes - totalInputBytes
            let oldMeasurement = try measure(
                source.oldSnapshot.text,
                maximumBytes: min(request.limits.maximumInputBytes, remainingInputBytes),
                sourceID: source.id,
                limits: request.limits,
                work: &work
            )
            totalInputBytes += oldMeasurement.byteCount
            let newRemainingInputBytes = request.limits.maximumCombinedInputBytes - totalInputBytes
            let newMeasurement = try measure(
                source.newSnapshot.text,
                maximumBytes: min(request.limits.maximumInputBytes, newRemainingInputBytes),
                sourceID: source.id,
                limits: request.limits,
                work: &work
            )
            totalInputBytes += newMeasurement.byteCount
            try validateAtomicGeneratorBound(
                oldByteCount: oldMeasurement.byteCount,
                newByteCount: newMeasurement.byteCount,
                oldRecordCount: oldMeasurement.recordCount,
                newRecordCount: newMeasurement.recordCount
            )
            let oldReference = PatchGenerationSnapshotReference(
                snapshot: source.oldSnapshot,
                utf8ByteCount: oldMeasurement.byteCount,
                contentSHA256: oldMeasurement.sha256
            )
            let newReference = PatchGenerationSnapshotReference(
                snapshot: source.newSnapshot,
                utf8ByteCount: newMeasurement.byteCount,
                contentSHA256: newMeasurement.sha256
            )
            try record(oldReference, in: &referencesByRevision)
            try record(newReference, in: &referencesByRevision)
            retainedPlanBytes = try addBounded(
                try retainedBytes(source: source, old: oldReference, new: newReference),
                to: retainedPlanBytes,
                maximum: request.limits.maximumPlanOutputBytes,
                error: .planOutputTooLarge(maximumBytes: request.limits.maximumPlanOutputBytes)
            )
            try work.consumeLinePairCost(
                oldRecordCount: oldMeasurement.recordCount,
                newRecordCount: newMeasurement.recordCount
            )

            preparedSources.append(
                PreparedSource(
                    source: source,
                    oldReference: oldReference,
                    newReference: newReference,
                    oldPathUTF8: Array(source.oldPath.utf8),
                    newPathUTF8: Array(source.newPath.utf8),
                    oldRecordCount: oldMeasurement.recordCount,
                    newRecordCount: newMeasurement.recordCount
                )
            )
        }

        let orderedSources = try orderPreparedSources(
            preparedSources,
            direction: request.direction,
            work: &work
        )
        var generatedPatchData = Data()
        generatedPatchData.reserveCapacity(min(request.limits.maximumPatchBytes, 64 * 1_024))
        var generatedPatch = ""
        generatedPatch.reserveCapacity(min(request.limits.maximumPatchBytes, 64 * 1_024))
        var plannedSources: [PatchGenerationPlannedSource] = []
        plannedSources.reserveCapacity(orderedSources.count)

        for prepared in orderedSources {
            try Task.checkCancellation()
            let source = prepared.source
            let remainingPatchBytes = request.limits.maximumPatchBytes - generatedPatchData.count
            let piece: String
            do {
                try Task.checkCancellation()
                try validateAtomicGeneratorBound(
                    oldByteCount: prepared.oldReference.utf8ByteCount,
                    newByteCount: prepared.newReference.utf8ByteCount,
                    oldRecordCount: prepared.oldRecordCount,
                    newRecordCount: prepared.newRecordCount
                )
                piece = try PatchGenerator.generate(
                    old: source.oldSnapshot.text,
                    new: source.newSnapshot.text,
                    options: PatchGeneratorOptions(
                        oldPath: source.oldPath,
                        newPath: source.newPath,
                        contextLines: request.contextLines,
                        reverse: request.direction == .reverse,
                        maximumOutputBytes: remainingPatchBytes
                    )
                )
            } catch PatchGeneratorError.outputTooLarge {
                throw PatchGenerationPlanningError.patchTooLarge(
                    maximumBytes: request.limits.maximumPatchBytes
                )
            }
            try Task.checkCancellation()
            let pieceBytes = piece.utf8.count
            guard pieceBytes <= remainingPatchBytes else {
                throw PatchGenerationPlanningError.patchTooLarge(
                    maximumBytes: request.limits.maximumPatchBytes
                )
            }
            try appendUTF8(piece, to: &generatedPatchData)
            try appendString(piece, to: &generatedPatch)
            plannedSources.append(
                PatchGenerationPlannedSource(
                    source: source,
                    oldSnapshot: prepared.oldReference,
                    newSnapshot: prepared.newReference
                ))
        }
        try Task.checkCancellation()
        guard !generatedPatchData.isEmpty else {
            throw PatchGenerationPlanningError.noDifferences
        }
        try Task.checkCancellation()
        let generatedPatchSHA256 = try sha256(generatedPatchData, work: &work)

        let plannedDestination = try planDestination(
            request.destination,
            generatedPatch: generatedPatch,
            generatedPatchData: generatedPatchData,
            limits: request.limits,
            totalPathBytes: &totalPathBytes,
            retainedPlanBytes: retainedPlanBytes,
            work: &work
        )
        try Task.checkCancellation()
        let planSHA256 = try executionPlanSHA256(
            sources: plannedSources,
            style: request.style,
            contextLines: request.contextLines,
            direction: request.direction,
            generatedPatchSHA256: generatedPatchSHA256,
            destination: plannedDestination,
            editor: request.presentationIntent.externalEditor,
            work: &work
        )
        return PatchGenerationPlan(
            sources: plannedSources,
            style: request.style,
            contextLines: request.contextLines,
            direction: request.direction,
            generatedPatch: generatedPatch,
            generatedPatchUTF8ByteCount: generatedPatchData.count,
            generatedPatchSHA256: generatedPatchSHA256,
            planSHA256: planSHA256,
            destination: plannedDestination,
            presentationIntent: request.presentationIntent,
            estimatedWorkUnits: work.consumed,
            limits: request.limits
        )
    }
}

public enum PatchGenerationCommittedDestination: Equatable, Sendable {
    case file(PatchGenerationFileRevision)
    case clipboard(revision: PatchGenerationClipboardRevision)
}

/// Owned read-only descriptor for exact bytes proven committed. URL remains audit metadata only.
public final class PatchGenerationCommittedFileAuthorization: @unchecked Sendable, Equatable {
    public let revision: PatchGenerationFileRevision
    public let payloadSHA256: [UInt8]
    public let payloadByteCount: Int

    private let fileDescriptor: Int32

    fileprivate init(
        revision: PatchGenerationFileRevision,
        payloadSHA256: [UInt8],
        payloadByteCount: Int,
        consumingFileDescriptor fileDescriptor: Int32
    ) {
        self.revision = revision
        self.payloadSHA256 = payloadSHA256
        self.payloadByteCount = payloadByteCount
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        Darwin.close(fileDescriptor)
    }

    public static func == (
        left: PatchGenerationCommittedFileAuthorization,
        right: PatchGenerationCommittedFileAuthorization
    ) -> Bool {
        left === right
    }

    /// Returns a close-on-exec descriptor owned by caller.
    public func duplicateReadOnlyFileDescriptor() throws -> Int32 {
        let descriptor = Darwin.fcntl(fileDescriptor, F_DUPFD_CLOEXEC, 3)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return descriptor
    }
}

public struct PatchGenerationCommitReceipt: Equatable, Sendable {
    public let destination: PatchGenerationCommittedDestination
    public let committedByteCount: Int
    public let generatedPatchSHA256: [UInt8]
    public let planSHA256: [UInt8]
    public let fileAuthorization: PatchGenerationCommittedFileAuthorization?

    fileprivate init(
        destination: PatchGenerationCommittedDestination,
        committedByteCount: Int,
        generatedPatchSHA256: [UInt8],
        planSHA256: [UInt8],
        fileAuthorization: PatchGenerationCommittedFileAuthorization?
    ) {
        self.destination = destination
        self.committedByteCount = committedByteCount
        self.generatedPatchSHA256 = generatedPatchSHA256
        self.planSHA256 = planSHA256
        self.fileAuthorization = fileAuthorization
    }
}

public enum PatchGenerationNonCommitReason: Equatable, Sendable {
    case cancelled
    case sourceChanged
    case destinationChanged
    case securityContractUnavailable
    case rejected(String)
    case failed(String)
}

public struct PatchGenerationCommitUncertainty: Equatable, Sendable {
    public let destinationURL: URL?
    public let reason: String

    fileprivate init(destinationURL: URL?, reason: String) {
        self.destinationURL = destinationURL
        self.reason = reason
    }
}

/// One terminal atomic destination result. Fileprivate construction prevents contradictory public
/// states; executors use `PatchGenerationExecutionOutcomeFactory`.
public struct PatchGenerationExecutionOutcome: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case committed(PatchGenerationCommitReceipt)
        case notCommitted(PatchGenerationNonCommitReason)
        case commitUncertain(PatchGenerationCommitUncertainty)
    }

    public let state: State
    fileprivate let sessionIdentifier: UUID

    fileprivate init(sessionIdentifier: UUID, state: State) {
        self.sessionIdentifier = sessionIdentifier
        self.state = state
    }
}

public struct PatchGenerationClipboardPublicationReceipt: Equatable, Sendable {
    public let expectedRevision: PatchGenerationClipboardRevision
    public let committedRevision: PatchGenerationClipboardRevision
    public let planSHA256: [UInt8]
    public let payloadSHA256: [UInt8]

    fileprivate let sessionIdentifier: UUID

    fileprivate init(
        token: PatchGenerationPublicationToken,
        expectedRevision: PatchGenerationClipboardRevision,
        committedRevision: PatchGenerationClipboardRevision,
        planSHA256: [UInt8],
        payloadSHA256: [UInt8]
    ) {
        sessionIdentifier = token.sessionIdentifier
        self.expectedRevision = expectedRevision
        self.committedRevision = committedRevision
        self.planSHA256 = planSHA256
        self.payloadSHA256 = payloadSHA256
    }
}

public enum PatchGenerationClipboardBrokerOutcome: Equatable, Sendable {
    case replaced(PatchGenerationClipboardPublicationReceipt)
    case notReplaced
    case notCommitted(PatchGenerationClipboardNonPublicationReceipt)
    case replacementUncertain(String)
}

/// Broker-sealed proof that one atomic compare-and-replace made no mutation.
public struct PatchGenerationClipboardNonPublicationReceipt: Equatable, Sendable {
    public let expectedRevision: PatchGenerationClipboardRevision
    public let observedRevision: PatchGenerationClipboardRevision
    public let planSHA256: [UInt8]
    public let payloadSHA256: [UInt8]

    fileprivate let sessionIdentifier: UUID

    fileprivate init(
        token: PatchGenerationPublicationToken,
        expectedRevision: PatchGenerationClipboardRevision,
        observedRevision: PatchGenerationClipboardRevision,
        planSHA256: [UInt8],
        payloadSHA256: [UInt8]
    ) {
        sessionIdentifier = token.sessionIdentifier
        self.expectedRevision = expectedRevision
        self.observedRevision = observedRevision
        self.planSHA256 = planSHA256
        self.payloadSHA256 = payloadSHA256
    }
}

public enum PatchGenerationClipboardPlatformResult: Equatable, Sendable {
    case replaced(revision: UInt64)
    case notReplaced(observedRevision: UInt64)
    case replacementUncertain(String)
}

/// Single actor owns all application pasteboard publication. Platform adapter must compare and replace
/// atomically in its callback; actor serializes every application request and issues sealed receipts.
public actor PatchGenerationExclusiveClipboardBroker {
    public typealias AtomicCompareAndReplace =
        @Sendable (
            _ expected: PatchGenerationClipboardRevision,
            _ text: String
        ) async -> PatchGenerationClipboardPlatformResult

    public nonisolated let brokerIdentifier: PatchGenerationClipboardBrokerIdentifier
    public nonisolated let epoch: PatchGenerationClipboardBrokerEpoch
    private var revision: UInt64
    private var publicationInFlight = false
    private var invalidated = false
    private let atomicCompareAndReplace: AtomicCompareAndReplace

    fileprivate init(
        brokerIdentifier: PatchGenerationClipboardBrokerIdentifier,
        epoch: PatchGenerationClipboardBrokerEpoch,
        initialRevision: UInt64,
        atomicCompareAndReplace: @escaping AtomicCompareAndReplace
    ) {
        self.brokerIdentifier = brokerIdentifier
        self.epoch = epoch
        revision = initialRevision
        self.atomicCompareAndReplace = atomicCompareAndReplace
    }

    public var currentRevision: PatchGenerationClipboardRevision {
        PatchGenerationClipboardRevision(
            brokerIdentifier: brokerIdentifier,
            epoch: epoch,
            value: revision
        )
    }

    public func publish(
        _ plan: PatchGenerationMutationPlan,
        token: PatchGenerationPublicationToken
    ) async -> PatchGenerationClipboardBrokerOutcome {
        guard !invalidated else {
            return .replacementUncertain(
                "Pasteboard broker epoch is invalid; recreate broker to rotate epoch."
            )
        }
        guard !publicationInFlight,
            case .clipboard(let expected, let text) = plan.destination,
            PatchGenerationWorkflow.constantTimeEqual(token.planSHA256, plan.planSHA256),
            expected.brokerIdentifier == brokerIdentifier,
            expected.epoch == epoch,
            expected.value == revision
        else { return .notReplaced }

        publicationInFlight = true
        guard token.claimForPublication() else {
            publicationInFlight = false
            return .notReplaced
        }
        let result = await atomicCompareAndReplace(expected, text)
        publicationInFlight = false
        switch result {
        case .notReplaced(let observedRevision):
            guard observedRevision >= revision else {
                invalidated = true
                return .replacementUncertain(
                    "Pasteboard revision regressed; recreate broker to rotate epoch."
                )
            }
            let observed = PatchGenerationClipboardRevision(
                brokerIdentifier: brokerIdentifier,
                epoch: epoch,
                value: observedRevision
            )
            revision = observedRevision
            return .notCommitted(
                PatchGenerationClipboardNonPublicationReceipt(
                    token: token,
                    expectedRevision: expected,
                    observedRevision: observed,
                    planSHA256: plan.planSHA256,
                    payloadSHA256: plan.generatedPatchSHA256
                )
            )
        case .replacementUncertain(let reason):
            invalidated = true
            return .replacementUncertain(reason)
        case .replaced(let committedValue):
            guard committedValue > revision else {
                invalidated = true
                return .replacementUncertain("Pasteboard returned a non-advancing revision.")
            }
            let committed = PatchGenerationClipboardRevision(
                brokerIdentifier: brokerIdentifier,
                epoch: epoch,
                value: committedValue
            )
            revision = committedValue
            return .replaced(
                PatchGenerationClipboardPublicationReceipt(
                    token: token,
                    expectedRevision: expected,
                    committedRevision: committed,
                    planSHA256: plan.planSHA256,
                    payloadSHA256: plan.generatedPatchSHA256
                )
            )
        }
    }
}

extension PatchGenerationWorkflow {
    /// Creates a uniquely identified broker. Call once for process pasteboard ownership and retain it;
    /// every patch and non-patch pasteboard writer must route through same broker instance.
    public static func makeExclusiveClipboardBroker(
        initialRevision: UInt64,
        atomicCompareAndReplace: @escaping PatchGenerationExclusiveClipboardBroker.AtomicCompareAndReplace
    ) -> PatchGenerationExclusiveClipboardBroker {
        PatchGenerationExclusiveClipboardBroker(
            brokerIdentifier: PatchGenerationClipboardBrokerIdentifier(rawValue: UUID()),
            epoch: PatchGenerationClipboardBrokerEpoch(rawValue: UUID()),
            initialRevision: initialRevision,
            atomicCompareAndReplace: atomicCompareAndReplace
        )
    }
}

public enum PatchGenerationDestinationMutationGuarantee: String, Equatable, Hashable, Sendable {
    case continuouslyHeldRevisionLease
    case atomicDescriptorRelativeFullRevisionCompareAndSwap
}

public final class PatchGenerationPublicationToken: @unchecked Sendable {
    fileprivate let sessionIdentifier: UUID
    fileprivate let planSHA256: [UInt8]
    fileprivate let maximumFileMetadataBytes: Int

    private let lock = NSLock()
    private var claimed = false

    fileprivate init(
        sessionIdentifier: UUID,
        planSHA256: [UInt8],
        maximumFileMetadataBytes: Int
    ) {
        self.sessionIdentifier = sessionIdentifier
        self.planSHA256 = planSHA256
        self.maximumFileMetadataBytes = maximumFileMetadataBytes
    }

    fileprivate func claimForPublication() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// Core-only proof that one file CAS was authorized before its mutation primitive was invoked.
/// Issuance permanently consumes the publication token; terminal evidence consumes this permit.
final class PatchGenerationFileCompareAndSwapPermit: @unchecked Sendable {
    fileprivate let sessionIdentifier: UUID
    fileprivate let planSHA256: [UInt8]
    fileprivate let maximumMetadataBytes: Int

    private let lock = NSLock()
    private var compareAndSwapStarted = false
    private var terminalEvidenceClaimed = false

    fileprivate init(token: PatchGenerationPublicationToken, maximumMetadataBytes: Int) {
        sessionIdentifier = token.sessionIdentifier
        planSHA256 = token.planSHA256
        self.maximumMetadataBytes = maximumMetadataBytes
    }

    /// Core publisher calls this immediately before its atomic descriptor-relative CAS primitive.
    fileprivate func claimForCompareAndSwap() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !compareAndSwapStarted, !terminalEvidenceClaimed else { return false }
        compareAndSwapStarted = true
        return true
    }

    fileprivate func claimForTerminalEvidence() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard compareAndSwapStarted, !terminalEvidenceClaimed else { return false }
        terminalEvidenceClaimed = true
        return true
    }
}

public final class PatchGenerationFilePublicationReceipt: @unchecked Sendable {
    public let revision: PatchGenerationFileRevision
    public let planSHA256: [UInt8]
    public let payloadSHA256: [UInt8]
    public let guarantee: PatchGenerationDestinationMutationGuarantee

    fileprivate let sessionIdentifier: UUID
    fileprivate let parentIdentity: PatchGenerationCanonicalFileIdentity
    fileprivate let leafName: String
    fileprivate let metadataSHA256: [UInt8]
    private let descriptorLock = NSLock()
    private var fileDescriptor: Int32?

    /// Core publisher transfers a read-only close-on-exec descriptor after private-stage cleanup,
    /// full metadata verification, publication, file sync, and parent sync complete.
    fileprivate init(
        permit: PatchGenerationFileCompareAndSwapPermit,
        revision: PatchGenerationFileRevision,
        payloadSHA256: [UInt8],
        guarantee: PatchGenerationDestinationMutationGuarantee,
        parentIdentity: PatchGenerationCanonicalFileIdentity,
        leafName: String,
        metadataSHA256: [UInt8],
        consumingReadOnlyFileDescriptor fileDescriptor: Int32
    ) {
        self.revision = revision
        planSHA256 = permit.planSHA256
        self.payloadSHA256 = payloadSHA256
        self.guarantee = guarantee
        sessionIdentifier = permit.sessionIdentifier
        self.parentIdentity = parentIdentity
        self.leafName = leafName
        self.metadataSHA256 = metadataSHA256
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        descriptorLock.lock()
        let descriptor = fileDescriptor
        fileDescriptor = nil
        descriptorLock.unlock()
        if let descriptor { Darwin.close(descriptor) }
    }

    fileprivate func takeFileDescriptor() -> Int32? {
        descriptorLock.lock()
        defer { descriptorLock.unlock() }
        let descriptor = fileDescriptor
        fileDescriptor = nil
        return descriptor
    }
}

/// Core-sealed proof that one token-bound atomic file compare-and-swap made no mutation.
public struct PatchGenerationFileNonPublicationReceipt: Equatable, Sendable {
    public let planSHA256: [UInt8]

    fileprivate let sessionIdentifier: UUID

    fileprivate init(permit: PatchGenerationFileCompareAndSwapPermit) {
        planSHA256 = permit.planSHA256
        sessionIdentifier = permit.sessionIdentifier
    }
}

/// Only core publication backend can seal file evidence. Implementation must create `0700` private
/// staging container and `0600` leaf without broad inherited ACL, then cleanup only through held
/// staging descriptors plus stable identities on prepublication exits.
enum PatchGenerationFilePublicationReceiptFactory: Sendable {
    /// Must be called before the file CAS. Failure, cancellation, or a compare miss cannot reissue
    /// another permit from the same publication token.
    static func makeCompareAndSwapPermit(
        token: PatchGenerationPublicationToken,
        plan: PatchGenerationMutationPlan
    ) -> PatchGenerationFileCompareAndSwapPermit? {
        guard case .file = plan.destination,
            PatchGenerationWorkflow.constantTimeEqual(token.planSHA256, plan.planSHA256),
            token.claimForPublication()
        else { return nil }
        return PatchGenerationFileCompareAndSwapPermit(
            token: token,
            maximumMetadataBytes: token.maximumFileMetadataBytes
        )
    }

    /// Core publisher calls this immediately before invoking its file CAS primitive.
    static func beginCompareAndSwap(
        permit: PatchGenerationFileCompareAndSwapPermit,
        plan: PatchGenerationMutationPlan
    ) -> Bool {
        guard case .file = plan.destination,
            PatchGenerationWorkflow.constantTimeEqual(permit.planSHA256, plan.planSHA256)
        else { return false }
        return permit.claimForCompareAndSwap()
    }

    static func seal(
        permit: PatchGenerationFileCompareAndSwapPermit,
        plan: PatchGenerationMutationPlan,
        revision: PatchGenerationFileRevision,
        guarantee: PatchGenerationDestinationMutationGuarantee,
        parentIdentity: PatchGenerationCanonicalFileIdentity,
        leafName: String,
        parentDirectoryDescriptor: Int32,
        consumingReadOnlyFileDescriptor descriptor: Int32
    ) throws -> PatchGenerationFilePublicationReceipt? {
        var descriptorOwned = descriptor >= 0
        defer {
            if descriptorOwned { Darwin.close(descriptor) }
        }
        guard permit.claimForTerminalEvidence(),
            PatchGenerationWorkflow.constantTimeEqual(permit.planSHA256, plan.planSHA256),
            case .file(let destination) = plan.destination,
            descriptor >= 0,
            parentDirectoryDescriptor >= 0,
            leafName == destination.url.lastPathComponent,
            PatchGenerationWorkflow.exactPath(
                parentIdentity.canonicalURL,
                destination.url.deletingLastPathComponent()
            ),
            destinationParentIdentity(destination.operation) == parentIdentity,
            revision.linkCount == 1,
            revision.permissions == destination.finalPermissions,
            parentDescriptorMatches(parentDirectoryDescriptor, identity: parentIdentity),
            descriptorIsExactLeaf(
                descriptor,
                parentDirectoryDescriptor: parentDirectoryDescriptor,
                leafName: leafName
            ),
            descriptorIsReadOnlyAndCloseOnExec(descriptor),
            PatchGenerationWorkflow.constantTimeEqual(
                revision.contentSHA256,
                try sha256Descriptor(descriptor, expectedByteCount: destination.payload.count)
            ),
            PatchGenerationWorkflow.constantTimeEqual(
                revision.contentSHA256,
                try PatchGenerationWorkflow.sha256(destination.payload)
            )
        else {
            return nil
        }
        let maximumMetadataBytes = min(
            permit.maximumMetadataBytes,
            plan.limits.maximumExistingFileMetadataBytes
        )
        guard revision.metadataByteCount <= UInt64(maximumMetadataBytes) else {
            return nil
        }
        let metadata = try descriptorMetadataDigest(
            descriptor,
            maximumBytes: Int(revision.metadataByteCount)
        )
        guard revision.metadataByteCount == UInt64(metadata.byteCount),
            PatchGenerationWorkflow.constantTimeEqual(
                revision.metadataSHA256,
                metadata.sha256
            ),
            descriptorMatchesRevision(descriptor, revision: revision)
        else {
            return nil
        }
        let receipt = PatchGenerationFilePublicationReceipt(
            permit: permit,
            revision: revision,
            payloadSHA256: revision.contentSHA256,
            guarantee: guarantee,
            parentIdentity: parentIdentity,
            leafName: leafName,
            metadataSHA256: metadata.sha256,
            consumingReadOnlyFileDescriptor: descriptor
        )
        descriptorOwned = false
        return receipt
    }

    static func sealCompareMiss(
        permit: PatchGenerationFileCompareAndSwapPermit,
        plan: PatchGenerationMutationPlan
    ) -> PatchGenerationFileNonPublicationReceipt? {
        guard permit.claimForTerminalEvidence(),
            case .file = plan.destination,
            PatchGenerationWorkflow.constantTimeEqual(permit.planSHA256, plan.planSHA256)
        else { return nil }
        return PatchGenerationFileNonPublicationReceipt(permit: permit)
    }

    private static func destinationParentIdentity(
        _ operation: PatchGenerationPlannedFileOperation
    ) -> PatchGenerationCanonicalFileIdentity {
        switch operation {
        case .createNew(let parent),
            .overwrite(let parent, _),
            .append(let parent, _):
            return parent
        }
    }
}

/// Core-issued one-shot state machine. It is created before executor invocation. After publication
/// starts, `.notCommitted` requires sealed proof that an atomic compare-and-replace made no mutation.
public final class PatchGenerationExecutionSession: @unchecked Sendable {
    private enum Phase {
        case beforePublication
        case publicationStarted
        case terminal
    }

    private let identifier = UUID()
    private let planSHA256: [UInt8]
    private let maximumFileMetadataBytes: Int
    private let lock = NSLock()
    private var phase = Phase.beforePublication
    private var terminalOutcome: PatchGenerationExecutionOutcome?

    fileprivate init(plan: PatchGenerationMutationPlan) {
        planSHA256 = plan.planSHA256
        maximumFileMetadataBytes = plan.limits.maximumExistingFileMetadataBytes
    }

    public func beginPublication() -> PatchGenerationPublicationToken? {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .beforePublication else { return nil }
        phase = .publicationStarted
        return PatchGenerationPublicationToken(
            sessionIdentifier: identifier,
            planSHA256: planSHA256,
            maximumFileMetadataBytes: maximumFileMetadataBytes
        )
    }

    fileprivate func finishBeforePublication(
        _ reason: PatchGenerationNonCommitReason
    ) -> PatchGenerationExecutionOutcome {
        lock.lock()
        defer { lock.unlock() }
        if let terminalOutcome { return terminalOutcome }
        guard phase == .beforePublication else {
            let outcome = PatchGenerationExecutionOutcome(
                sessionIdentifier: identifier,
                state: .commitUncertain(
                    PatchGenerationCommitUncertainty(
                        destinationURL: nil,
                        reason: "Non-commit result requested after publication started."
                    )
                )
            )
            terminalOutcome = outcome
            phase = .terminal
            return outcome
        }
        phase = .terminal
        let outcome = PatchGenerationExecutionOutcome(
            sessionIdentifier: identifier,
            state: .notCommitted(reason)
        )
        terminalOutcome = outcome
        return outcome
    }

    fileprivate func finishAfterPublication(
        token: PatchGenerationPublicationToken,
        state: PatchGenerationExecutionOutcome.State
    ) -> PatchGenerationExecutionOutcome {
        lock.lock()
        defer { lock.unlock() }
        if let terminalOutcome { return terminalOutcome }
        guard phase == .publicationStarted,
            token.sessionIdentifier == identifier,
            PatchGenerationWorkflow.constantTimeEqual(token.planSHA256, planSHA256)
        else {
            let outcome = PatchGenerationExecutionOutcome(
                sessionIdentifier: identifier,
                state: .commitUncertain(
                    PatchGenerationCommitUncertainty(
                        destinationURL: nil,
                        reason: "Publication token is stale, foreign, or already consumed."
                    )
                )
            )
            terminalOutcome = outcome
            phase = .terminal
            return outcome
        }
        phase = .terminal
        let outcome = PatchGenerationExecutionOutcome(sessionIdentifier: identifier, state: state)
        terminalOutcome = outcome
        return outcome
    }

    fileprivate func normalizeReturnedOutcome(
        _ outcome: PatchGenerationExecutionOutcome
    ) -> PatchGenerationExecutionOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .terminal,
            outcome.sessionIdentifier == identifier,
            terminalOutcome == outcome
        else {
            phase = .terminal
            if let terminalOutcome { return terminalOutcome }
            let normalized = PatchGenerationExecutionOutcome(
                sessionIdentifier: identifier,
                state: .commitUncertain(
                    PatchGenerationCommitUncertainty(
                        destinationURL: nil,
                        reason: "Executor returned a foreign or nonterminal outcome."
                    )
                )
            )
            terminalOutcome = normalized
            return normalized
        }
        return outcome
    }
}

/// Side-effect boundary. Implementations must enforce `PatchGenerationExecutorContract.required`.
/// It receives a mutation-only plan; display command-line metadata is structurally unavailable.
public protocol PatchGenerationPlanExecutor: Sendable {
    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome
}

extension PatchGenerationWorkflow {
    public static func execute(
        _ plan: PatchGenerationPlan,
        with executor: any PatchGenerationPlanExecutor
    ) async -> PatchGenerationExecutionOutcome {
        let session = PatchGenerationExecutionSession(plan: plan.mutation)
        let outcome = await executor.execute(plan.mutation, session: session)
        return session.normalizeReturnedOutcome(outcome)
    }
}

/// Editor dispatch receives only rule and descriptor authorization bound to verified committed bytes.
public struct PatchGenerationEditorDispatch: Sendable {
    public let ruleIdentifier: String
    public let authorization: PatchGenerationCommittedFileAuthorization

    fileprivate init(
        ruleIdentifier: String,
        authorization: PatchGenerationCommittedFileAuthorization
    ) {
        self.ruleIdentifier = ruleIdentifier
        self.authorization = authorization
    }
}

public protocol PatchGenerationEditorDispatcher: Sendable {
    func dispatch(_ request: PatchGenerationEditorDispatch) async throws
}

/// Validates executor evidence and constructs terminal outcomes. After publication starts, callers
/// must prove commit, prove an atomic compare miss, or report uncertainty.
public enum PatchGenerationExecutionOutcomeFactory: Sendable {
    /// Valid only before any publish/CAS/replace primitive is invoked. After an atomic compare miss,
    /// use the token-bound clipboard non-commit factory instead.
    public static func notCommittedBeforePublication(
        session: PatchGenerationExecutionSession,
        reason: PatchGenerationNonCommitReason
    ) -> PatchGenerationExecutionOutcome {
        session.finishBeforePublication(reason)
    }

    public static func uncertain(
        session: PatchGenerationExecutionSession,
        token: PatchGenerationPublicationToken,
        destinationURL: URL?,
        reason: String
    ) -> PatchGenerationExecutionOutcome {
        session.finishAfterPublication(
            token: token,
            state:
                .commitUncertain(
                    PatchGenerationCommitUncertainty(destinationURL: destinationURL, reason: reason)
                )
        )
    }

    public static func committedClipboard(
        plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession,
        token: PatchGenerationPublicationToken,
        receipt: PatchGenerationClipboardPublicationReceipt
    ) -> PatchGenerationExecutionOutcome {
        guard case .clipboard(let expected, _) = plan.destination,
            receipt.sessionIdentifier == token.sessionIdentifier,
            receipt.expectedRevision == expected,
            receipt.committedRevision.brokerIdentifier == expected.brokerIdentifier,
            receipt.committedRevision.epoch == expected.epoch,
            receipt.committedRevision.value > expected.value,
            PatchGenerationWorkflow.constantTimeEqual(receipt.planSHA256, plan.planSHA256),
            PatchGenerationWorkflow.constantTimeEqual(
                receipt.payloadSHA256,
                plan.generatedPatchSHA256
            )
        else {
            return uncertain(
                session: session,
                token: token,
                destinationURL: nil,
                reason: "Clipboard commit evidence does not match plan."
            )
        }
        return session.finishAfterPublication(
            token: token,
            state:
                .committed(
                    PatchGenerationCommitReceipt(
                        destination: .clipboard(revision: receipt.committedRevision),
                        committedByteCount: plan.generatedPatchUTF8ByteCount,
                        generatedPatchSHA256: plan.generatedPatchSHA256,
                        planSHA256: plan.planSHA256,
                        fileAuthorization: nil
                    )
                )
        )
    }

    public static func notCommittedClipboard(
        plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession,
        token: PatchGenerationPublicationToken,
        receipt: PatchGenerationClipboardNonPublicationReceipt
    ) -> PatchGenerationExecutionOutcome {
        guard case .clipboard(let expected, _) = plan.destination,
            receipt.sessionIdentifier == token.sessionIdentifier,
            receipt.expectedRevision == expected,
            receipt.observedRevision.brokerIdentifier == expected.brokerIdentifier,
            receipt.observedRevision.epoch == expected.epoch,
            receipt.observedRevision.value >= expected.value,
            PatchGenerationWorkflow.constantTimeEqual(receipt.planSHA256, plan.planSHA256),
            PatchGenerationWorkflow.constantTimeEqual(
                receipt.payloadSHA256,
                plan.generatedPatchSHA256
            )
        else {
            return uncertain(
                session: session,
                token: token,
                destinationURL: nil,
                reason: "Clipboard non-commit evidence does not match plan."
            )
        }
        let reason: PatchGenerationNonCommitReason =
            receipt.observedRevision.value == expected.value
            ? .rejected("Atomic clipboard compare-and-replace declined publication.")
            : .destinationChanged
        return session.finishAfterPublication(token: token, state: .notCommitted(reason))
    }

    /// Executor transfers ownership of descriptor on success. Descriptor must already be read-only,
    /// close-on-exec, positioned arbitrarily, and pinned to exact committed revision and payload.
    public static func committedFile(
        plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession,
        token: PatchGenerationPublicationToken,
        receipt: PatchGenerationFilePublicationReceipt
    ) -> PatchGenerationExecutionOutcome {
        let revision = receipt.revision
        guard let descriptor = receipt.takeFileDescriptor() else {
            return uncertain(
                session: session,
                token: token,
                destinationURL: destinationURL(plan),
                reason: "File publication receipt was already consumed."
            )
        }
        defer { Darwin.close(descriptor) }
        guard case .file(let destination) = plan.destination,
            descriptor >= 0,
            receipt.sessionIdentifier == token.sessionIdentifier,
            PatchGenerationWorkflow.constantTimeEqual(receipt.planSHA256, plan.planSHA256),
            receipt.leafName == destination.url.lastPathComponent,
            PatchGenerationWorkflow.exactPath(
                receipt.parentIdentity.canonicalURL,
                destination.url.deletingLastPathComponent()
            ),
            PatchGenerationWorkflow.exactPath(
                revision.identity.canonicalURL,
                destination.url
            ),
            revision.byteCount == UInt64(destination.payload.count),
            revision.permissions == destination.finalPermissions,
            committedRevisionMatchesOperation(revision, operation: destination.operation),
            PatchGenerationWorkflow.constantTimeEqual(
                revision.contentSHA256,
                receipt.payloadSHA256
            ),
            PatchGenerationWorkflow.constantTimeEqual(
                receipt.payloadSHA256,
                (try? PatchGenerationWorkflow.sha256(destination.payload)) ?? []
            ),
            PatchGenerationWorkflow.constantTimeEqual(
                receipt.metadataSHA256,
                revision.metadataSHA256
            ),
            descriptorIsReadOnlyAndCloseOnExec(descriptor),
            (try? descriptorMatches(
                descriptor,
                revision: revision,
                payload: destination.payload
            )) == true
        else {
            return uncertain(
                session: session,
                token: token,
                destinationURL: destinationURL(plan),
                reason: "File commit evidence does not match plan."
            )
        }
        let authorization: PatchGenerationCommittedFileAuthorization?
        if plan.editor != nil,
            let snapshotDescriptor = try? immutableSnapshotDescriptor(
                from: descriptor,
                expectedByteCount: destination.payload.count,
                expectedSHA256: revision.contentSHA256
            )
        {
            authorization = PatchGenerationCommittedFileAuthorization(
                revision: revision,
                payloadSHA256: revision.contentSHA256,
                payloadByteCount: destination.payload.count,
                consumingFileDescriptor: snapshotDescriptor
            )
        } else {
            authorization = nil
        }
        return session.finishAfterPublication(
            token: token,
            state:
                .committed(
                    PatchGenerationCommitReceipt(
                        destination: .file(revision),
                        committedByteCount: destination.payload.count,
                        generatedPatchSHA256: plan.generatedPatchSHA256,
                        planSHA256: plan.planSHA256,
                        fileAuthorization: authorization
                    )
                )
        )
    }

    public static func notCommittedFile(
        plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession,
        token: PatchGenerationPublicationToken,
        receipt: PatchGenerationFileNonPublicationReceipt
    ) -> PatchGenerationExecutionOutcome {
        guard case .file = plan.destination,
            receipt.sessionIdentifier == token.sessionIdentifier,
            PatchGenerationWorkflow.constantTimeEqual(receipt.planSHA256, plan.planSHA256),
            PatchGenerationWorkflow.constantTimeEqual(token.planSHA256, plan.planSHA256)
        else {
            return uncertain(
                session: session,
                token: token,
                destinationURL: destinationURL(plan),
                reason: "File non-commit evidence does not match plan."
            )
        }
        return session.finishAfterPublication(token: token, state: .notCommitted(.destinationChanged))
    }

    public static func editorDispatch(
        plan: PatchGenerationMutationPlan,
        receipt: PatchGenerationCommitReceipt
    ) -> PatchGenerationEditorDispatch? {
        guard let editor = plan.editor,
            let authorization = receipt.fileAuthorization,
            case .file(let committedRevision) = receipt.destination,
            case .file(let destination) = plan.destination,
            receipt.committedByteCount == destination.payload.count,
            PatchGenerationWorkflow.constantTimeEqual(
                receipt.generatedPatchSHA256,
                plan.generatedPatchSHA256
            ),
            PatchGenerationWorkflow.constantTimeEqual(receipt.planSHA256, plan.planSHA256),
            committedRevision == authorization.revision,
            authorization.payloadByteCount == destination.payload.count,
            PatchGenerationWorkflow.constantTimeEqual(
                authorization.payloadSHA256,
                committedRevision.contentSHA256
            )
        else { return nil }
        return PatchGenerationEditorDispatch(
            ruleIdentifier: editor.ruleIdentifier,
            authorization: authorization
        )
    }

    private static func destinationURL(_ plan: PatchGenerationMutationPlan) -> URL? {
        guard case .file(let destination) = plan.destination else { return nil }
        return destination.url
    }

    private static func committedRevisionMatchesOperation(
        _ committed: PatchGenerationFileRevision,
        operation: PatchGenerationPlannedFileOperation
    ) -> Bool {
        switch operation {
        case .createNew:
            return committed.linkCount == 1
        case .overwrite(_, let expected), .append(_, let expected):
            return committed.linkCount == 1
                && committed.identity.deviceID == expected.identity.deviceID
                && committed.metadataByteCount == expected.metadataByteCount
                && PatchGenerationWorkflow.constantTimeEqual(
                    committed.metadataSHA256,
                    expected.metadataSHA256
                )
        }
    }
}

extension PatchGenerationWorkflow {
    fileprivate enum PatchGenerationSnapshotKey: Equatable, Hashable {
        case document(UUID, revision: UInt64)
        case scratchpad(UUID, revision: UInt64)
        case clipboard(String, revision: UInt64)
        case file(deviceID: UInt64, fileID: UInt64, generation: UInt32, revision: UInt64)
    }

    fileprivate struct TextMeasurement {
        let byteCount: Int
        let recordCount: Int
        let sha256: [UInt8]
    }

    fileprivate struct PreparedSource {
        let source: PatchGenerationSource
        let oldReference: PatchGenerationSnapshotReference
        let newReference: PatchGenerationSnapshotReference
        let oldPathUTF8: [UInt8]
        let newPathUTF8: [UInt8]
        let oldRecordCount: Int
        let newRecordCount: Int
    }

    fileprivate static func orderPreparedSources(
        _ sources: [PreparedSource],
        direction: PatchGenerationDirection,
        work: inout PatchGenerationWorkBudget
    ) throws -> [PreparedSource] {
        var forwardEdges = Array(repeating: Set<Int>(), count: sources.count)
        var oldPathIndices: [[UInt8]: Int] = [:]
        var newPathIndices: [[UInt8]: Int] = [:]
        oldPathIndices.reserveCapacity(sources.count)
        newPathIndices.reserveCapacity(sources.count)
        for index in sources.indices {
            try Task.checkCancellation()
            let source = sources[index]
            let priorOld = oldPathIndices[source.oldPathUTF8]
            let priorNew = newPathIndices[source.newPathUTF8]
            if let prior = [priorOld, priorNew].compactMap({ $0 }).min() {
                throw PatchGenerationPlanningError.ambiguousSourcePathDependency(
                    first: sources[prior].source.id,
                    second: source.source.id
                )
            }
            oldPathIndices[source.oldPathUTF8] = index
            newPathIndices[source.newPathUTF8] = index
            try work.consume(UInt64(source.oldPathUTF8.count + source.newPathUTF8.count))
        }

        for predecessorIndex in sources.indices {
            try Task.checkCancellation()
            let predecessor = sources[predecessorIndex]
            try work.consume(UInt64(predecessor.newPathUTF8.count))
            guard let successorIndex = oldPathIndices[predecessor.newPathUTF8],
                successorIndex != predecessorIndex
            else { continue }
            let successor = sources[successorIndex]
            guard predecessor.newReference == successor.oldReference else {
                throw PatchGenerationPlanningError.sourcePathDependencySnapshotMismatch(
                    first: predecessor.source.id,
                    second: successor.source.id
                )
            }
            forwardEdges[predecessorIndex].insert(successorIndex)
        }

        _ = try stableTopologicalOrder(edges: forwardEdges, work: &work)
        switch direction {
        case .forward:
            for predecessor in forwardEdges.indices {
                for successor in forwardEdges[predecessor] where predecessor >= successor {
                    throw PatchGenerationPlanningError.sourcePathDependencyOrderConflict(
                        first: sources[predecessor].source.id,
                        second: sources[successor].source.id
                    )
                }
            }
            return sources
        case .reverse:
            var reverseEdges = Array(repeating: Set<Int>(), count: sources.count)
            for predecessor in forwardEdges.indices {
                for successor in forwardEdges[predecessor] {
                    reverseEdges[successor].insert(predecessor)
                }
            }
            return try stableTopologicalOrder(edges: reverseEdges, work: &work).map {
                sources[$0]
            }
        }
    }

    fileprivate static func stableTopologicalOrder(
        edges: [Set<Int>],
        work: inout PatchGenerationWorkBudget
    ) throws -> [Int] {
        var incoming = Array(repeating: 0, count: edges.count)
        for (index, successors) in edges.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            for successor in successors {
                try work.consume(1)
                incoming[successor] += 1
            }
        }
        var ready = PatchGenerationStableReadyQueue(capacity: edges.count)
        for index in incoming.indices {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            try work.consume(1)
            if incoming[index] == 0 { try ready.insert(index, work: &work) }
        }
        var order: [Int] = []
        order.reserveCapacity(edges.count)
        while order.count < edges.count {
            try Task.checkCancellation()
            guard let next = try ready.removeMinimum(work: &work) else {
                throw PatchGenerationPlanningError.sourcePathDependencyCycle
            }
            order.append(next)
            for successor in edges[next] {
                try work.consume(1)
                incoming[successor] -= 1
                if incoming[successor] == 0 { try ready.insert(successor, work: &work) }
            }
        }
        return order
    }

    fileprivate static func selectSources(
        _ sources: [PatchGenerationSource],
        selection: PatchGenerationSourceSelection,
        limits: PatchGenerationPlanningLimits,
        work: inout PatchGenerationWorkBudget
    ) throws -> [PatchGenerationSource] {
        guard sources.count <= limits.maximumSources else {
            throw PatchGenerationPlanningError.tooManySources(maximum: limits.maximumSources)
        }
        var indices: [PatchGenerationSourceID: Int] = [:]
        indices.reserveCapacity(sources.count)
        for (index, source) in sources.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            try validateIdentifier(
                source.id.rawValue,
                maximumBytes: limits.maximumSourceIdentifierUTF8Bytes,
                error: .invalidSourceIdentifier(source.id.rawValue),
                work: &work
            )
            guard indices.updateValue(index, forKey: source.id) == nil else {
                throw PatchGenerationPlanningError.duplicateSourceIdentifier(source.id.rawValue)
            }
        }

        let selected: [PatchGenerationSource]
        switch selection {
        case .all:
            selected = sources
        case .only(let identifiers):
            guard identifiers.count <= limits.maximumSelectedSources else {
                throw PatchGenerationPlanningError.tooManySelectedSources(
                    maximum: limits.maximumSelectedSources
                )
            }
            var seen: Set<PatchGenerationSourceID> = []
            seen.reserveCapacity(identifiers.count)
            var result: [PatchGenerationSource] = []
            result.reserveCapacity(identifiers.count)
            for identifier in identifiers {
                try validateIdentifier(
                    identifier.rawValue,
                    maximumBytes: limits.maximumSourceIdentifierUTF8Bytes,
                    error: .invalidSourceIdentifier(identifier.rawValue),
                    work: &work
                )
                guard seen.insert(identifier).inserted else {
                    throw PatchGenerationPlanningError.duplicateSelectionIdentifier(
                        identifier.rawValue
                    )
                }
                guard let index = indices[identifier] else {
                    throw PatchGenerationPlanningError.unknownSourceIdentifier(identifier.rawValue)
                }
                result.append(sources[index])
            }
            selected = result
        }
        guard !selected.isEmpty else { throw PatchGenerationPlanningError.emptySelection }
        guard selected.count <= limits.maximumSelectedSources else {
            throw PatchGenerationPlanningError.tooManySelectedSources(
                maximum: limits.maximumSelectedSources
            )
        }
        try Task.checkCancellation()
        return selected
    }

    fileprivate static func validatePresentationIntent(
        _ intent: PatchGenerationPresentationIntent,
        destination: PatchGenerationDestination,
        limits: PatchGenerationPlanningLimits,
        work: inout PatchGenerationWorkBudget
    ) throws -> Int {
        var retainedBytes = 0
        switch intent.commandLine {
        case .none:
            break
        case .record(let arguments):
            guard arguments.count <= limits.maximumCommandLineArgumentCount else {
                throw PatchGenerationPlanningError.invalidCommandLineIntent
            }
            let pointerBytes = MemoryLayout<UnsafePointer<CChar>?>.size
            let pointerCount = arguments.count + 1
            guard pointerCount > arguments.count,
                pointerCount <= limits.maximumTotalCommandLineUTF8Bytes / pointerBytes
            else {
                throw PatchGenerationPlanningError.commandLineIntentTooLarge(
                    maximumBytes: limits.maximumTotalCommandLineUTF8Bytes
                )
            }
            var totalBytes = pointerCount * pointerBytes
            try work.consume(UInt64(totalBytes))
            for argument in arguments {
                var count = 0
                for byte in argument.utf8 {
                    guard byte != 0,
                        count < limits.maximumCommandLineArgumentUTF8Bytes
                    else {
                        throw PatchGenerationPlanningError.invalidCommandLineIntent
                    }
                    count += 1
                    try work.consume(1)
                }
                totalBytes = try addBounded(
                    count + 1,
                    to: totalBytes,
                    maximum: limits.maximumTotalCommandLineUTF8Bytes,
                    error: .commandLineIntentTooLarge(
                        maximumBytes: limits.maximumTotalCommandLineUTF8Bytes
                    )
                )
            }
            retainedBytes = totalBytes
        }

        switch intent.externalEditor {
        case .none:
            break
        case .openFile(let ruleIdentifier):
            guard case .file = destination else {
                throw PatchGenerationPlanningError.externalEditorRequiresFileDestination
            }
            try validateIdentifier(
                ruleIdentifier,
                maximumBytes: limits.maximumExternalRuleIdentifierUTF8Bytes,
                error: .invalidExternalEditorIntent,
                work: &work
            )
            retainedBytes = try addBounded(
                ruleIdentifier.utf8.count,
                to: retainedBytes,
                maximum: limits.maximumPlanOutputBytes,
                error: .planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
            )
        }
        return retainedBytes
    }

    fileprivate static func measure(
        _ text: String,
        maximumBytes: Int,
        sourceID: PatchGenerationSourceID,
        limits: PatchGenerationPlanningLimits,
        work: inout PatchGenerationWorkBudget
    ) throws -> TextMeasurement {
        guard maximumBytes >= 0 else {
            throw PatchGenerationPlanningError.combinedInputTooLarge(
                maximumBytes: limits.maximumCombinedInputBytes
            )
        }
        var hasher = SHA256()
        var chunk: [UInt8] = []
        chunk.reserveCapacity(64 * 1_024)
        var byteCount = 0
        var lineFeedCount = 0
        var finalByte: UInt8?
        for byte in text.utf8 {
            guard byteCount < maximumBytes else {
                if maximumBytes < limits.maximumInputBytes {
                    throw PatchGenerationPlanningError.combinedInputTooLarge(
                        maximumBytes: limits.maximumCombinedInputBytes
                    )
                }
                throw PatchGenerationPlanningError.inputTooLarge(
                    source: sourceID,
                    maximumBytes: limits.maximumInputBytes
                )
            }
            byteCount += 1
            finalByte = byte
            if byte == 0x0A { lineFeedCount += 1 }
            chunk.append(byte)
            try work.consume(1)
            if chunk.count == chunk.capacity {
                chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
                chunk.removeAll(keepingCapacity: true)
                try Task.checkCancellation()
            }
        }
        if !chunk.isEmpty {
            chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
        let recordCount = lineFeedCount + ((finalByte != nil && finalByte != 0x0A) ? 1 : 0)
        try Task.checkCancellation()
        return TextMeasurement(
            byteCount: byteCount,
            recordCount: recordCount,
            sha256: Array(hasher.finalize())
        )
    }

    fileprivate static func validateAtomicGeneratorBound(
        oldByteCount: Int,
        newByteCount: Int,
        oldRecordCount: Int,
        newRecordCount: Int
    ) throws {
        _ = try addBounded(
            oldByteCount,
            to: newByteCount,
            maximum: maximumAtomicGeneratorInputBytes,
            error: .combinedInputTooLarge(maximumBytes: maximumAtomicGeneratorInputBytes)
        )
        let old = UInt64(oldRecordCount) + 1
        let new = UInt64(newRecordCount) + 1
        let (linePairs, overflow) = old.multipliedReportingOverflow(by: new)
        guard !overflow, linePairs <= maximumAtomicGeneratorLinePairs else {
            throw PatchGenerationPlanningError.workLimitExceeded(
                maximumUnits: maximumAtomicGeneratorLinePairs
            )
        }
        try Task.checkCancellation()
    }

    fileprivate static func planDestination(
        _ destination: PatchGenerationDestination,
        generatedPatch: String,
        generatedPatchData: Data,
        limits: PatchGenerationPlanningLimits,
        totalPathBytes: inout Int,
        retainedPlanBytes: Int,
        work: inout PatchGenerationWorkBudget
    ) throws -> PatchGenerationPlannedDestination {
        switch destination {
        case .clipboard(let clipboard):
            let generatedPatchBytes = generatedPatchData.count
            guard generatedPatchBytes <= limits.maximumDestinationPayloadBytes else {
                throw PatchGenerationPlanningError.destinationPayloadTooLarge(
                    maximumBytes: limits.maximumDestinationPayloadBytes
                )
            }
            _ = try addBounded(
                generatedPatchBytes,
                to: try addBounded(
                    generatedPatchBytes,
                    to: retainedPlanBytes,
                    maximum: limits.maximumPlanOutputBytes,
                    error: .planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
                ),
                maximum: limits.maximumPlanOutputBytes,
                error: .planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
            )
            return .clipboard(
                expectedRevision: clipboard.expectedRevision,
                text: generatedPatch
            )
        case .file(let file):
            let generatedPatchBytes = generatedPatchData.count
            try validateFileURL(
                file.url,
                maximumPathBytes: limits.maximumPathUTF8Bytes,
                allowsRoot: false
            )
            guard !file.url.hasDirectoryPath else {
                throw PatchGenerationPlanningError.invalidFileURL(file.url.absoluteString)
            }
            totalPathBytes = try addPath(
                file.url,
                to: totalPathBytes,
                limits: limits
            )
            let operation: PatchGenerationPlannedFileOperation
            let payload: Data
            let finalPermissions: UInt16
            switch file.disposition {
            case .createNew(let parentIdentity):
                try validateCanonicalIdentity(
                    parentIdentity,
                    expectedKind: .directory,
                    maximumPathBytes: limits.maximumPathUTF8Bytes
                )
                totalPathBytes = try addPath(
                    parentIdentity.canonicalURL,
                    to: totalPathBytes,
                    limits: limits
                )
                let destinationParent = file.url.deletingLastPathComponent()
                guard exactPath(destinationParent, parentIdentity.canonicalURL) else {
                    throw PatchGenerationPlanningError.destinationIdentityMismatch(file.url.path)
                }
                operation = .createNew(expectedParent: parentIdentity)
                payload = generatedPatchData
                finalPermissions = 0o600
            case .overwrite(let expectedParent, let expected):
                try validateCanonicalIdentity(
                    expectedParent,
                    expectedKind: .directory,
                    maximumPathBytes: limits.maximumPathUTF8Bytes
                )
                try validateFileRevision(expected, maximumPathBytes: limits.maximumPathUTF8Bytes)
                try validateExistingRevisionLimits(expected, limits: limits)
                guard exactPath(file.url.deletingLastPathComponent(), expectedParent.canonicalURL) else {
                    throw PatchGenerationPlanningError.destinationIdentityMismatch(file.url.path)
                }
                totalPathBytes = try addPath(
                    expectedParent.canonicalURL,
                    to: totalPathBytes,
                    limits: limits
                )
                totalPathBytes = try addPath(
                    expected.identity.canonicalURL,
                    to: totalPathBytes,
                    limits: limits
                )
                guard exactPath(file.url, expected.identity.canonicalURL) else {
                    throw PatchGenerationPlanningError.destinationIdentityMismatch(file.url.path)
                }
                operation = .overwrite(expectedParent: expectedParent, expected: expected)
                payload = generatedPatchData
                finalPermissions = expected.permissions
            case .append(let expectedParent, let expected, let lineEnding):
                try validateCanonicalIdentity(
                    expectedParent,
                    expectedKind: .directory,
                    maximumPathBytes: limits.maximumPathUTF8Bytes
                )
                try validateFileRevision(
                    expected.revision,
                    maximumPathBytes: limits.maximumPathUTF8Bytes
                )
                try validateExistingRevisionLimits(expected.revision, limits: limits)
                guard exactPath(file.url.deletingLastPathComponent(), expectedParent.canonicalURL) else {
                    throw PatchGenerationPlanningError.destinationIdentityMismatch(file.url.path)
                }
                totalPathBytes = try addPath(
                    expectedParent.canonicalURL,
                    to: totalPathBytes,
                    limits: limits
                )
                totalPathBytes = try addPath(
                    expected.revision.identity.canonicalURL,
                    to: totalPathBytes,
                    limits: limits
                )
                guard exactPath(file.url, expected.revision.identity.canonicalURL) else {
                    throw PatchGenerationPlanningError.destinationIdentityMismatch(file.url.path)
                }
                guard expected.data.count <= limits.maximumExistingFileBytes else {
                    throw PatchGenerationPlanningError.existingFileTooLarge(
                        maximumBytes: limits.maximumExistingFileBytes
                    )
                }
                guard expected.revision.byteCount == UInt64(expected.data.count) else {
                    throw PatchGenerationPlanningError.existingFileSnapshotMismatch(file.url.path)
                }
                let digest = try sha256(expected.data, work: &work)
                guard constantTimeEqual(digest, expected.revision.contentSHA256) else {
                    throw PatchGenerationPlanningError.existingFileSnapshotMismatch(file.url.path)
                }
                try Task.checkCancellation()
                payload = try composeAppend(
                    generatedPatch: generatedPatch,
                    existingData: expected.data,
                    lineEnding: lineEnding,
                    maximumBytes: limits.maximumDestinationPayloadBytes,
                    work: &work
                )
                operation = .append(
                    expectedParent: expectedParent,
                    expected: expected.revision
                )
                finalPermissions = expected.revision.permissions
            }
            try Task.checkCancellation()
            guard payload.count <= limits.maximumDestinationPayloadBytes else {
                throw PatchGenerationPlanningError.destinationPayloadTooLarge(
                    maximumBytes: limits.maximumDestinationPayloadBytes
                )
            }
            let destinationMetadataBytes =
                file.url.path(percentEncoded: false).utf8.count
                + fileOperationMetadataByteCount(operation)
            let planOutputBytes = try addBounded(
                generatedPatchBytes,
                to: try addBounded(
                    payload.count,
                    to: try addBounded(
                        destinationMetadataBytes,
                        to: retainedPlanBytes,
                        maximum: limits.maximumPlanOutputBytes,
                        error: .planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
                    ),
                    maximum: limits.maximumPlanOutputBytes,
                    error: .planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
                ),
                maximum: limits.maximumPlanOutputBytes,
                error: .planOutputTooLarge(maximumBytes: limits.maximumPlanOutputBytes)
            )
            _ = planOutputBytes
            return .file(
                PatchGenerationPlannedFileDestination(
                    url: file.url,
                    operation: operation,
                    payload: payload,
                    finalPermissions: finalPermissions
                ))
        }
    }

    fileprivate static func validate(_ limits: PatchGenerationPlanningLimits) throws {
        let hardMaximumTotalPathUTF8Bytes =
            PatchGenerationPlanningLimits.hardMaximumTotalPathUTF8Bytes
        let hardMaximumCombinedInputBytes =
            PatchGenerationPlanningLimits.hardMaximumCombinedInputBytes
        let hardMaximumDestinationPayloadBytes =
            PatchGenerationPlanningLimits.hardMaximumDestinationPayloadBytes
        let hardMaximumPlanOutputBytes =
            PatchGenerationPlanningLimits.hardMaximumPlanOutputBytes
        try require(
            limits.maximumSources,
            in: 1...PatchGenerationPlanningLimits.hardMaximumSourceCount,
            limit: .sources
        )
        try require(
            limits.maximumSelectedSources,
            in: 1...limits.maximumSources,
            limit: .selectedSources
        )
        try require(
            limits.maximumSourceIdentifierUTF8Bytes,
            in: 1...PatchGenerationPlanningLimits.hardMaximumSourceIdentifierUTF8Bytes,
            limit: .sourceIdentifierUTF8Bytes
        )
        try require(
            limits.maximumPathUTF8Bytes,
            in: 1...PatchGenerationPlanningLimits.hardMaximumPathUTF8Bytes,
            limit: .pathUTF8Bytes
        )
        try require(
            limits.maximumTotalPathUTF8Bytes,
            in: limits.maximumPathUTF8Bytes...hardMaximumTotalPathUTF8Bytes,
            limit: .totalPathUTF8Bytes
        )
        try require(
            limits.maximumInputBytes,
            in: 0...PatchGenerationPlanningLimits.hardMaximumInputBytes,
            limit: .inputBytes
        )
        try require(
            limits.maximumCombinedInputBytes,
            in: limits.maximumInputBytes...hardMaximumCombinedInputBytes,
            limit: .combinedInputBytes
        )
        try require(
            limits.maximumExistingFileBytes,
            in: 0...PatchGenerationPlanningLimits.hardMaximumExistingFileBytes,
            limit: .existingFileBytes
        )
        try require(
            limits.maximumExistingFileMetadataBytes,
            in: 0...PatchGenerationPlanningLimits.hardMaximumExistingFileMetadataBytes,
            limit: .existingFileMetadataBytes
        )
        try require(
            limits.maximumPatchBytes,
            in: 0...PatchGenerationPlanningLimits.hardMaximumPatchBytes,
            limit: .patchBytes
        )
        try require(
            limits.maximumDestinationPayloadBytes,
            in: max(
                limits.maximumExistingFileBytes,
                limits.maximumPatchBytes
            )...hardMaximumDestinationPayloadBytes,
            limit: .destinationPayloadBytes
        )
        try require(
            limits.maximumPlanOutputBytes,
            in: limits.maximumDestinationPayloadBytes...hardMaximumPlanOutputBytes,
            limit: .planOutputBytes
        )
        try require(
            limits.maximumContextLines,
            in: 0...PatchGenerationPlanningLimits.hardMaximumContextLines,
            limit: .contextLines
        )
        try require(
            limits.maximumCommandLineArgumentCount,
            in: 0...PatchGenerationPlanningLimits.hardMaximumCommandLineArgumentCount,
            limit: .commandLineArguments
        )
        try require(
            limits.maximumCommandLineArgumentUTF8Bytes,
            in: 1...PatchGenerationPlanningLimits.hardMaximumCommandLineArgumentUTF8Bytes,
            limit: .commandLineArgumentUTF8Bytes
        )
        try require(
            limits.maximumTotalCommandLineUTF8Bytes,
            in: 0...PatchGenerationPlanningLimits.hardMaximumTotalCommandLineUTF8Bytes,
            limit: .totalCommandLineUTF8Bytes
        )
        try require(
            limits.maximumExternalRuleIdentifierUTF8Bytes,
            in: 1...PatchGenerationPlanningLimits.hardMaximumExternalRuleIdentifierUTF8Bytes,
            limit: .externalRuleIdentifierUTF8Bytes
        )
        guard limits.maximumWorkUnits <= PatchGenerationPlanningLimits.hardMaximumWorkUnits else {
            throw PatchGenerationPlanningError.invalidLimit(.workUnits)
        }
    }

    fileprivate static func require(
        _ value: Int,
        in range: ClosedRange<Int>,
        limit: PatchGenerationPlanningLimit
    ) throws {
        guard range.contains(value) else {
            throw PatchGenerationPlanningError.invalidLimit(limit)
        }
    }

    fileprivate static func validatePatchPath(
        _ path: String,
        limits: PatchGenerationPlanningLimits,
        work: inout PatchGenerationWorkBudget
    ) throws -> Int {
        guard !path.isEmpty else {
            throw PatchGenerationPlanningError.invalidPatchPath(path)
        }
        var byteCount = 0
        for byte in path.utf8 {
            guard byte != 0,
                byte != 0x0A,
                byte != 0x0D
            else {
                throw PatchGenerationPlanningError.invalidPatchPath(path)
            }
            guard byteCount < limits.maximumPathUTF8Bytes else {
                throw PatchGenerationPlanningError.pathTooLarge(
                    maximumBytes: limits.maximumPathUTF8Bytes
                )
            }
            byteCount += 1
            try work.consume(1)
        }
        return byteCount
    }

    fileprivate static func validate(
        snapshotIdentity: PatchGenerationSnapshotIdentity,
        limits: PatchGenerationPlanningLimits,
        work: inout PatchGenerationWorkBudget
    ) throws -> Int {
        switch snapshotIdentity {
        case .document, .scratchpad:
            return 0
        case .clipboard(let contentID):
            var count = 0
            for byte in contentID.utf8 {
                guard byte != 0, count < 1_024 else {
                    throw PatchGenerationPlanningError.invalidSnapshotMetadata
                }
                count += 1
                try work.consume(1)
            }
            guard count > 0 else {
                throw PatchGenerationPlanningError.invalidSnapshotMetadata
            }
            return 0
        case .file(let identity):
            try validateCanonicalIdentity(
                identity,
                expectedKind: .regularFile,
                maximumPathBytes: limits.maximumPathUTF8Bytes
            )
            let count = identity.canonicalURL.path(percentEncoded: false).utf8.count
            try work.consume(UInt64(count))
            return count
        }
    }

    fileprivate static func validateCanonicalIdentity(
        _ identity: PatchGenerationCanonicalFileIdentity,
        expectedKind: PatchGenerationCanonicalItemKind,
        maximumPathBytes: Int
    ) throws {
        do {
            try validateFileURL(identity.canonicalURL, maximumPathBytes: maximumPathBytes)
        } catch {
            throw PatchGenerationPlanningError.invalidCanonicalFileIdentity(
                identity.canonicalURL.path
            )
        }
        guard exactPath(identity.canonicalURL, identity.canonicalURL.standardizedFileURL) else {
            throw PatchGenerationPlanningError.invalidCanonicalFileIdentity(
                identity.canonicalURL.path
            )
        }
        guard identity.kind == expectedKind else {
            throw PatchGenerationPlanningError.invalidCanonicalFileIdentity(
                identity.canonicalURL.path
            )
        }
        guard identity.canonicalURL.hasDirectoryPath == (expectedKind == .directory) else {
            throw PatchGenerationPlanningError.invalidCanonicalFileIdentity(
                identity.canonicalURL.path
            )
        }
    }

    fileprivate static func validateFileRevision(
        _ revision: PatchGenerationFileRevision,
        maximumPathBytes: Int
    ) throws {
        try validateCanonicalIdentity(
            revision.identity,
            expectedKind: .regularFile,
            maximumPathBytes: maximumPathBytes
        )
        guard revision.byteCount <= UInt64(Int.max),
            revision.linkCount == 1,
            revision.permissions & ~UInt16(0o7777) == 0,
            (0..<1_000_000_000).contains(revision.modificationTimeNanoseconds),
            (0..<1_000_000_000).contains(revision.statusChangeTimeNanoseconds),
            revision.contentSHA256.count == SHA256.Digest.byteCount,
            revision.metadataSHA256.count == SHA256.Digest.byteCount
        else {
            throw PatchGenerationPlanningError.invalidFileRevision(
                revision.identity.canonicalURL.path
            )
        }
    }

    fileprivate static func validateExistingRevisionLimits(
        _ revision: PatchGenerationFileRevision,
        limits: PatchGenerationPlanningLimits
    ) throws {
        guard revision.byteCount <= UInt64(limits.maximumExistingFileBytes) else {
            throw PatchGenerationPlanningError.existingFileTooLarge(
                maximumBytes: limits.maximumExistingFileBytes
            )
        }
        guard revision.metadataByteCount <= UInt64(limits.maximumExistingFileMetadataBytes) else {
            throw PatchGenerationPlanningError.existingFileMetadataTooLarge(
                maximumBytes: limits.maximumExistingFileMetadataBytes
            )
        }
    }

    fileprivate static func validateFileURL(
        _ url: URL,
        maximumPathBytes: Int,
        allowsRoot: Bool = true
    ) throws {
        let maximumSerializedBytes = maximumPathBytes * 3 + 32
        var serializedBytes = [UInt8](repeating: 0, count: maximumSerializedBytes + 1)
        let serializedCount = CFURLGetBytes(
            url as CFURL,
            &serializedBytes,
            serializedBytes.count
        )
        guard serializedCount >= 0, serializedCount <= maximumSerializedBytes else {
            throw PatchGenerationPlanningError.invalidFileURL("<oversized-file-url>")
        }
        let serialized = String(decoding: serializedBytes[..<serializedCount], as: UTF8.self)
        let path = url.path(percentEncoded: false)
        let components = url.pathComponents
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard url.isFileURL,
            url.baseURL == nil,
            url.query == nil,
            url.fragment == nil,
            urlComponents?.scheme?.caseInsensitiveCompare("file") == .orderedSame,
            urlComponents?.host == nil || urlComponents?.host == "",
            urlComponents?.user == nil,
            urlComponents?.password == nil,
            urlComponents?.port == nil,
            path.hasPrefix("/"),
            !path.hasPrefix("//"),
            !path.contains("//"),
            !path.utf8.contains(0),
            path.utf8.count <= maximumPathBytes,
            components.first == "/",
            allowsRoot || components.count > 1,
            components.dropFirst().allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/")
            }),
            canonicalFileURLString(url, decodedPath: path) == serialized
        else {
            throw PatchGenerationPlanningError.invalidFileURL(serialized)
        }
    }

    fileprivate static func canonicalFileURLString(_ url: URL, decodedPath: String) -> String? {
        URL(
            fileURLWithPath: decodedPath,
            isDirectory: url.hasDirectoryPath
        ).absoluteString
    }

    fileprivate static func record(
        _ reference: PatchGenerationSnapshotReference,
        in references: inout [PatchGenerationSnapshotKey: PatchGenerationSnapshotReference]
    ) throws {
        let key: PatchGenerationSnapshotKey
        switch reference.identity {
        case .document(let id):
            key = .document(id, revision: reference.revision)
        case .scratchpad(let id):
            key = .scratchpad(id, revision: reference.revision)
        case .clipboard(let contentID):
            key = .clipboard(contentID, revision: reference.revision)
        case .file(let identity):
            key = .file(
                deviceID: identity.deviceID,
                fileID: identity.fileID,
                generation: identity.generation,
                revision: reference.revision
            )
        }
        if let existing = references[key] {
            guard existing.utf8ByteCount == reference.utf8ByteCount,
                constantTimeEqual(existing.contentSHA256, reference.contentSHA256)
            else {
                throw PatchGenerationPlanningError.conflictingSnapshotRevision
            }
            return
        }
        references[key] = reference
    }

    fileprivate static func retainedBytes(
        source: PatchGenerationSource,
        old: PatchGenerationSnapshotReference,
        new: PatchGenerationSnapshotReference
    ) throws -> Int {
        var total = source.id.rawValue.utf8.count
        for count in [
            source.oldPath.utf8.count,
            source.newPath.utf8.count,
            old.contentSHA256.count,
            new.contentSHA256.count,
            snapshotIdentityByteCount(old.identity),
            snapshotIdentityByteCount(new.identity),
            MemoryLayout<UInt64>.size * 2,
            MemoryLayout<Int>.size * 2
        ] {
            let (next, overflow) = total.addingReportingOverflow(count)
            guard !overflow else {
                throw PatchGenerationPlanningError.planOutputTooLarge(maximumBytes: .max)
            }
            total = next
        }
        return total
    }

    fileprivate static func snapshotIdentityByteCount(
        _ identity: PatchGenerationSnapshotIdentity
    ) -> Int {
        switch identity {
        case .document, .scratchpad:
            MemoryLayout<UUID>.size
        case .clipboard(let contentID):
            contentID.utf8.count
        case .file(let fileIdentity):
            fileIdentity.canonicalURL.path(percentEncoded: false).utf8.count
                + MemoryLayout<UInt64>.size * 2
                + MemoryLayout<UInt32>.size
                + MemoryLayout<UInt8>.size
        }
    }

    fileprivate static func addPath(
        _ url: URL,
        to total: Int,
        limits: PatchGenerationPlanningLimits
    ) throws -> Int {
        try addBounded(
            url.path(percentEncoded: false).utf8.count,
            to: total,
            maximum: limits.maximumTotalPathUTF8Bytes,
            error: .totalPathsTooLarge(maximumBytes: limits.maximumTotalPathUTF8Bytes)
        )
    }

    fileprivate static func fileOperationMetadataByteCount(
        _ operation: PatchGenerationPlannedFileOperation
    ) -> Int {
        switch operation {
        case .createNew(let parent):
            return parent.canonicalURL.path(percentEncoded: false).utf8.count + 32
        case .overwrite(let parent, let revision), .append(let parent, let revision):
            return parent.canonicalURL.path(percentEncoded: false).utf8.count
                + revision.identity.canonicalURL.path(percentEncoded: false).utf8.count
                + revision.contentSHA256.count
                + revision.metadataSHA256.count
                + 160
        }
    }

    fileprivate static func appendUTF8(_ value: String, to output: inout Data) throws {
        var chunk: [UInt8] = []
        chunk.reserveCapacity(64 * 1_024)
        for byte in value.utf8 {
            chunk.append(byte)
            if chunk.count == chunk.capacity {
                output.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                try Task.checkCancellation()
            }
        }
        if !chunk.isEmpty { output.append(contentsOf: chunk) }
        try Task.checkCancellation()
    }

    fileprivate static func appendString(_ value: String, to output: inout String) throws {
        var bytesSinceCancellation = 0
        for scalar in value.unicodeScalars {
            output.unicodeScalars.append(scalar)
            bytesSinceCancellation += scalar.utf8.count
            if bytesSinceCancellation >= 64 * 1_024 {
                try Task.checkCancellation()
                bytesSinceCancellation = 0
            }
        }
        try Task.checkCancellation()
    }

    fileprivate static func appendData(
        _ source: Data,
        to output: inout Data,
        work: inout PatchGenerationWorkBudget
    ) throws {
        try source.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + 64 * 1_024, bytes.count)
                output.append(contentsOf: bytes.bindMemory(to: UInt8.self)[offset..<end])
                try work.consume(UInt64(end - offset))
                try Task.checkCancellation()
                offset = end
            }
        }
    }

    fileprivate static func composeAppend(
        generatedPatch: String,
        existingData: Data,
        lineEnding: LineEnding,
        maximumBytes: Int,
        work: inout PatchGenerationWorkBudget
    ) throws -> Data {
        let ending = Array(lineEnding.rawValue.utf8)
        let needsSeparator = existingData.last.map { $0 != 0x0A && $0 != 0x0D } ?? false
        var translatedPatchBytes = 0
        var bytesSinceCancellation = 0
        for byte in generatedPatch.utf8 {
            translatedPatchBytes = try addBounded(
                byte == 0x0A ? ending.count : 1,
                to: translatedPatchBytes,
                maximum: maximumBytes,
                error: .destinationPayloadTooLarge(maximumBytes: maximumBytes)
            )
            bytesSinceCancellation += 1
            if bytesSinceCancellation >= 64 * 1_024 {
                try Task.checkCancellation()
                bytesSinceCancellation = 0
            }
        }
        var outputCount = try addBounded(
            translatedPatchBytes,
            to: existingData.count,
            maximum: maximumBytes,
            error: .destinationPayloadTooLarge(maximumBytes: maximumBytes)
        )
        if needsSeparator {
            outputCount = try addBounded(
                ending.count,
                to: outputCount,
                maximum: maximumBytes,
                error: .destinationPayloadTooLarge(maximumBytes: maximumBytes)
            )
        }

        var output = Data()
        output.reserveCapacity(outputCount)
        try appendData(existingData, to: &output, work: &work)
        if needsSeparator { output.append(contentsOf: ending) }
        var chunk: [UInt8] = []
        chunk.reserveCapacity(64 * 1_024)
        for byte in generatedPatch.utf8 {
            if byte == 0x0A {
                chunk.append(contentsOf: ending)
            } else {
                chunk.append(byte)
            }
            if chunk.count >= 64 * 1_024 {
                output.append(contentsOf: chunk)
                try work.consume(UInt64(chunk.count))
                chunk.removeAll(keepingCapacity: true)
                try Task.checkCancellation()
            }
        }
        if !chunk.isEmpty {
            output.append(contentsOf: chunk)
            try work.consume(UInt64(chunk.count))
        }
        guard output.count == outputCount else {
            throw PatchGenerationPlanningError.destinationPayloadTooLarge(maximumBytes: maximumBytes)
        }
        try Task.checkCancellation()
        return output
    }

    fileprivate static func executionPlanSHA256(
        sources: [PatchGenerationPlannedSource],
        style: PatchGenerationStyle,
        contextLines: Int,
        direction: PatchGenerationDirection,
        generatedPatchSHA256: [UInt8],
        destination: PatchGenerationPlannedDestination,
        editor: PatchGenerationExternalEditorIntent,
        work: inout PatchGenerationWorkBudget
    ) throws -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(1_024)
        appendFramed(Array("macmerge-patch-plan-v1".utf8), to: &bytes)
        appendFramed(Array(style.rawValue.utf8), to: &bytes)
        appendUInt64(UInt64(contextLines), to: &bytes)
        appendFramed(Array(direction.rawValue.utf8), to: &bytes)
        appendFramed(generatedPatchSHA256, to: &bytes)
        appendUInt64(UInt64(sources.count), to: &bytes)
        for source in sources {
            appendFramed(Array(source.id.rawValue.utf8), to: &bytes)
            appendFramed(Array(source.oldPath.utf8), to: &bytes)
            appendFramed(Array(source.newPath.utf8), to: &bytes)
            appendSnapshotReference(source.oldSnapshot, to: &bytes)
            appendSnapshotReference(source.newSnapshot, to: &bytes)
            try Task.checkCancellation()
        }
        switch destination {
        case .clipboard(let revision, _):
            appendFramed([0], to: &bytes)
            appendFramed(withUnsafeBytes(of: revision.brokerIdentifier.rawValue.uuid) { Array($0) }, to: &bytes)
            appendFramed(withUnsafeBytes(of: revision.epoch.rawValue.uuid) { Array($0) }, to: &bytes)
            appendUInt64(revision.value, to: &bytes)
        case .file(let file):
            appendFramed([1], to: &bytes)
            appendFramed(Array(file.url.path(percentEncoded: false).utf8), to: &bytes)
            appendFramed(try sha256(file.payload, work: &work), to: &bytes)
            appendUInt64(UInt64(file.finalPermissions), to: &bytes)
            switch file.operation {
            case .createNew(let parent):
                appendFramed([0], to: &bytes)
                appendCanonicalIdentity(parent, to: &bytes)
            case .overwrite(let parent, let revision):
                appendFramed([1], to: &bytes)
                appendCanonicalIdentity(parent, to: &bytes)
                appendFileRevision(revision, to: &bytes)
            case .append(let parent, let revision):
                appendFramed([2], to: &bytes)
                appendCanonicalIdentity(parent, to: &bytes)
                appendFileRevision(revision, to: &bytes)
            }
        }
        switch editor {
        case .none:
            appendFramed([], to: &bytes)
        case .openFile(let identifier):
            appendFramed(Array(identifier.utf8), to: &bytes)
        }
        try work.consume(UInt64(bytes.count))
        try Task.checkCancellation()
        return try sha256(bytes)
    }

    fileprivate static func appendFramed(_ field: [UInt8], to output: inout [UInt8]) {
        appendUInt64(UInt64(field.count), to: &output)
        output.append(contentsOf: field)
    }

    fileprivate static func appendUInt64(_ value: UInt64, to output: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { output.append(contentsOf: $0) }
    }

    fileprivate static func appendCanonicalIdentity(
        _ identity: PatchGenerationCanonicalFileIdentity,
        to output: inout [UInt8]
    ) {
        appendFramed(Array(identity.canonicalURL.path(percentEncoded: false).utf8), to: &output)
        appendFramed(Array(identity.kind.rawValue.utf8), to: &output)
        appendUInt64(identity.deviceID, to: &output)
        appendUInt64(identity.fileID, to: &output)
        appendUInt64(UInt64(identity.generation), to: &output)
    }

    fileprivate static func appendSnapshotReference(
        _ reference: PatchGenerationSnapshotReference,
        to output: inout [UInt8]
    ) {
        switch reference.identity {
        case .document(let identifier):
            appendFramed([0], to: &output)
            appendFramed(withUnsafeBytes(of: identifier.uuid) { Array($0) }, to: &output)
        case .scratchpad(let identifier):
            appendFramed([1], to: &output)
            appendFramed(withUnsafeBytes(of: identifier.uuid) { Array($0) }, to: &output)
        case .clipboard(let contentIdentifier):
            appendFramed([2], to: &output)
            appendFramed(Array(contentIdentifier.utf8), to: &output)
        case .file(let identity):
            appendFramed([3], to: &output)
            appendCanonicalIdentity(identity, to: &output)
        }
        appendUInt64(reference.revision, to: &output)
        appendUInt64(UInt64(reference.utf8ByteCount), to: &output)
        appendFramed(reference.contentSHA256, to: &output)
    }

    fileprivate static func appendFileRevision(
        _ revision: PatchGenerationFileRevision,
        to output: inout [UInt8]
    ) {
        appendCanonicalIdentity(revision.identity, to: &output)
        for value in [
            revision.byteCount,
            revision.linkCount,
            UInt64(revision.permissions),
            UInt64(revision.ownerID),
            UInt64(revision.groupID),
            UInt64(revision.flags),
            revision.metadataByteCount,
            UInt64(bitPattern: revision.modificationTimeSeconds),
            UInt64(UInt32(bitPattern: revision.modificationTimeNanoseconds)),
            UInt64(bitPattern: revision.statusChangeTimeSeconds),
            UInt64(UInt32(bitPattern: revision.statusChangeTimeNanoseconds))
        ] {
            appendUInt64(value, to: &output)
        }
        appendFramed(revision.contentSHA256, to: &output)
        appendFramed(revision.metadataSHA256, to: &output)
    }

    fileprivate static func validateIdentifier(
        _ value: String,
        maximumBytes: Int,
        error: PatchGenerationPlanningError,
        work: inout PatchGenerationWorkBudget
    ) throws {
        var count = 0
        for byte in value.utf8 {
            guard count < maximumBytes,
                isASCIIAlphaNumeric(byte) || byte == 0x2D || byte == 0x2E || byte == 0x5F
            else { throw error }
            count += 1
            try work.consume(1)
        }
        guard count > 0,
            let first = value.utf8.first,
            isASCIIAlphaNumeric(first)
        else { throw error }
    }

    fileprivate static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x5A).contains(byte)
            || (0x61...0x7A).contains(byte)
    }

    fileprivate static func exactPath(_ left: URL, _ right: URL) -> Bool {
        left.path(percentEncoded: false).utf8.elementsEqual(
            right.path(percentEncoded: false).utf8
        )
    }

    fileprivate static func sha256(
        _ data: Data,
        work: inout PatchGenerationWorkBudget
    ) throws -> [UInt8] {
        var hasher = SHA256()
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + 64 * 1_024, bytes.count)
                hasher.update(
                    bufferPointer: UnsafeRawBufferPointer(rebasing: bytes[offset..<end])
                )
                try work.consume(UInt64(end - offset))
                try Task.checkCancellation()
                offset = end
            }
        }
        return Array(hasher.finalize())
    }

    fileprivate static func sha256(_ bytes: [UInt8]) throws -> [UInt8] {
        var hasher = SHA256()
        try bytes.withUnsafeBytes { storage in
            var offset = 0
            while offset < storage.count {
                let end = min(offset + 64 * 1_024, storage.count)
                hasher.update(
                    bufferPointer: UnsafeRawBufferPointer(rebasing: storage[offset..<end])
                )
                try Task.checkCancellation()
                offset = end
            }
        }
        return Array(hasher.finalize())
    }

    fileprivate static func sha256(_ data: Data) throws -> [UInt8] {
        var hasher = SHA256()
        try data.withUnsafeBytes { storage in
            var offset = 0
            while offset < storage.count {
                let end = min(offset + 64 * 1_024, storage.count)
                hasher.update(
                    bufferPointer: UnsafeRawBufferPointer(rebasing: storage[offset..<end])
                )
                try Task.checkCancellation()
                offset = end
            }
        }
        return Array(hasher.finalize())
    }

    fileprivate static func constantTimeEqual(_ left: [UInt8], _ right: [UInt8]) -> Bool {
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    fileprivate static func addBounded(
        _ value: Int,
        to total: Int,
        maximum: Int,
        error: PatchGenerationPlanningError
    ) throws -> Int {
        guard value >= 0,
            total >= 0,
            value <= maximum,
            total <= maximum - value
        else { throw error }
        return total + value
    }
}

private func patchGenerationOwnedData(_ source: Data) throws -> Data {
    var result = Data()
    result.reserveCapacity(source.count)
    try source.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 64 * 1_024, bytes.count)
            result.append(contentsOf: bytes.bindMemory(to: UInt8.self)[offset..<end])
            try Task.checkCancellation()
            offset = end
        }
    }
    try Task.checkCancellation()
    return result
}

private func descriptorIsReadOnlyAndCloseOnExec(_ descriptor: Int32) -> Bool {
    let statusFlags = Darwin.fcntl(descriptor, F_GETFL)
    let descriptorFlags = Darwin.fcntl(descriptor, F_GETFD)
    return statusFlags >= 0
        && descriptorFlags >= 0
        && statusFlags & O_ACCMODE == O_RDONLY
        && descriptorFlags & FD_CLOEXEC != 0
}

private func parentDescriptorMatches(
    _ descriptor: Int32,
    identity: PatchGenerationCanonicalFileIdentity
) -> Bool {
    var information = stat()
    return Darwin.fstat(descriptor, &information) == 0
        && information.st_mode & S_IFMT == S_IFDIR
        && UInt64(information.st_dev) == identity.deviceID
        && UInt64(information.st_ino) == identity.fileID
        && UInt32(information.st_gen) == identity.generation
}

private func descriptorIsExactLeaf(
    _ descriptor: Int32,
    parentDirectoryDescriptor: Int32,
    leafName: String
) -> Bool {
    var descriptorInformation = stat()
    var leafInformation = stat()
    guard Darwin.fstat(descriptor, &descriptorInformation) == 0 else { return false }
    let status = leafName.withCString {
        Darwin.fstatat(parentDirectoryDescriptor, $0, &leafInformation, AT_SYMLINK_NOFOLLOW)
    }
    return status == 0
        && leafInformation.st_mode & S_IFMT == S_IFREG
        && descriptorInformation.st_dev == leafInformation.st_dev
        && descriptorInformation.st_ino == leafInformation.st_ino
        && descriptorInformation.st_gen == leafInformation.st_gen
}

private func sha256Descriptor(
    _ descriptor: Int32,
    expectedByteCount: Int
) throws -> [UInt8] {
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    var offset = 0
    while offset < expectedByteCount {
        try Task.checkCancellation()
        let requested = min(buffer.count, expectedByteCount - offset)
        let count = buffer.withUnsafeMutableBytes { storage -> Int in
            guard let baseAddress = storage.baseAddress else { return 0 }
            while true {
                let result = Darwin.pread(descriptor, baseAddress, requested, off_t(offset))
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard count == requested else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(count < 0 ? errno : EIO))
        }
        buffer.withUnsafeBytes {
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count]))
        }
        offset += count
    }
    var extra: UInt8 = 0
    let extraCount = Darwin.pread(descriptor, &extra, 1, off_t(expectedByteCount))
    guard extraCount == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(extraCount < 0 ? errno : EFBIG))
    }
    return Array(hasher.finalize())
}

private func descriptorMetadataDigest(
    _ descriptor: Int32,
    maximumBytes: Int
) throws -> (byteCount: Int, sha256: [UInt8]) {
    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    var metadata: [UInt8] = []
    metadata.reserveCapacity(128)
    func reserve(_ count: Int) throws {
        guard count >= 0, count <= maximumBytes - metadata.count else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EFBIG))
        }
    }
    func append(_ value: UInt64) throws {
        try reserve(MemoryLayout<UInt64>.size)
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { metadata.append(contentsOf: $0) }
    }
    func append(_ bytes: [UInt8]) throws {
        try reserve(bytes.count)
        metadata.append(contentsOf: bytes)
    }
    try append(UInt64(information.st_mode & mode_t(0o7777)))
    try append(UInt64(information.st_uid))
    try append(UInt64(information.st_gid))
    try append(UInt64(information.st_flags))

    errno = 0
    if let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
        defer { _ = Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        let aclBufferSize = Darwin.acl_size(acl)
        guard aclBufferSize >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try append(UInt64(aclBufferSize))
        try reserve(aclBufferSize)
        var aclBytes = [UInt8](repeating: 0, count: aclBufferSize)
        let copiedSize = aclBytes.withUnsafeMutableBytes {
            Darwin.acl_copy_ext($0.baseAddress, acl, aclBufferSize)
        }
        guard copiedSize == aclBufferSize else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno == 0 ? EIO : errno))
        }
        try append(aclBytes)
    } else if errno == ENOENT || errno == ENOTSUP {
        try append(0)
    } else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    let initialStatus = information
    let nameByteCount = Darwin.flistxattr(descriptor, nil, 0, 0)
    guard nameByteCount >= 0,
        nameByteCount <= maximumBytes
    else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(nameByteCount < 0 ? errno : EFBIG))
    }
    if nameByteCount > 0 {
        var names = [CChar](repeating: 0, count: nameByteCount)
        guard Darwin.flistxattr(descriptor, &names, names.count, 0) == nameByteCount else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var attributeNames: [[UInt8]] = []
        var index = 0
        while index < names.count {
            try Task.checkCancellation()
            let end = names[index...].firstIndex(of: 0) ?? names.endIndex
            guard end > index else { break }
            attributeNames.append(names[index..<end].map(UInt8.init(bitPattern:)))
            index = end + 1
        }
        for nameBytes in attributeNames.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            try Task.checkCancellation()
            try append(UInt64(nameBytes.count))
            try append(nameBytes)
            let name = String(decoding: nameBytes, as: UTF8.self)
            let valueByteCount = name.withCString {
                Darwin.fgetxattr(descriptor, $0, nil, 0, 0, 0)
            }
            guard valueByteCount >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            try append(UInt64(valueByteCount))
            try reserve(valueByteCount)
            if valueByteCount > 0 {
                var value = [UInt8](repeating: 0, count: valueByteCount)
                let readCount = name.withCString {
                    Darwin.fgetxattr(descriptor, $0, &value, value.count, 0, 0)
                }
                guard readCount == valueByteCount else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                try append(value)
            }
        }
    }
    var finalStatus = stat()
    guard Darwin.fstat(descriptor, &finalStatus) == 0,
        finalStatus.st_dev == initialStatus.st_dev,
        finalStatus.st_ino == initialStatus.st_ino,
        finalStatus.st_gen == initialStatus.st_gen,
        finalStatus.st_mode == initialStatus.st_mode,
        finalStatus.st_nlink == initialStatus.st_nlink,
        finalStatus.st_uid == initialStatus.st_uid,
        finalStatus.st_gid == initialStatus.st_gid,
        finalStatus.st_size == initialStatus.st_size,
        finalStatus.st_flags == initialStatus.st_flags,
        finalStatus.st_mtimespec.tv_sec == initialStatus.st_mtimespec.tv_sec,
        finalStatus.st_mtimespec.tv_nsec == initialStatus.st_mtimespec.tv_nsec,
        finalStatus.st_ctimespec.tv_sec == initialStatus.st_ctimespec.tv_sec,
        finalStatus.st_ctimespec.tv_nsec == initialStatus.st_ctimespec.tv_nsec
    else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ESTALE))
    }
    return (metadata.count, try PatchGenerationWorkflow.sha256(metadata))
}

private func descriptorMatchesRevision(
    _ descriptor: Int32,
    revision: PatchGenerationFileRevision
) -> Bool {
    var information = stat()
    return Darwin.fstat(descriptor, &information) == 0
        && information.st_mode & S_IFMT == S_IFREG
        && UInt64(information.st_dev) == revision.identity.deviceID
        && UInt64(information.st_ino) == revision.identity.fileID
        && UInt32(information.st_gen) == revision.identity.generation
        && UInt64(information.st_size) == revision.byteCount
        && UInt64(information.st_nlink) == revision.linkCount
        && UInt16(information.st_mode & mode_t(0o7777)) == revision.permissions
        && information.st_uid == revision.ownerID
        && information.st_gid == revision.groupID
        && information.st_flags == revision.flags
        && information.st_mtimespec.tv_sec == revision.modificationTimeSeconds
        && information.st_mtimespec.tv_nsec == revision.modificationTimeNanoseconds
        && information.st_ctimespec.tv_sec == revision.statusChangeTimeSeconds
        && information.st_ctimespec.tv_nsec == revision.statusChangeTimeNanoseconds
}

private func immutableSnapshotDescriptor(
    from sourceDescriptor: Int32,
    expectedByteCount: Int,
    expectedSHA256: [UInt8]
) throws -> Int32 {
    _ = sourceDescriptor
    _ = expectedByteCount
    _ = expectedSHA256
    // Darwin exposes neither anonymous regular files nor revocable write handles. A named inode can
    // be opened for writing by another same-user process before unlink, so editor authorization must
    // fail closed instead of claiming that such a snapshot is immutable.
    throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP))
}

private func descriptorMatches(
    _ descriptor: Int32,
    revision: PatchGenerationFileRevision,
    payload: Data
) throws -> Bool {
    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0,
        information.st_mode & S_IFMT == S_IFREG,
        UInt64(information.st_dev) == revision.identity.deviceID,
        UInt64(information.st_ino) == revision.identity.fileID,
        UInt32(information.st_gen) == revision.identity.generation,
        UInt64(information.st_nlink) == revision.linkCount,
        information.st_size == off_t(payload.count),
        UInt16(information.st_mode & mode_t(0o7777)) == revision.permissions,
        information.st_uid == revision.ownerID,
        information.st_gid == revision.groupID,
        information.st_flags == revision.flags
    else { return false }

    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    var offset: off_t = 0
    while offset < information.st_size {
        try Task.checkCancellation()
        let requested = min(buffer.count, Int(information.st_size - offset))
        let count = buffer.withUnsafeMutableBytes { storage -> Int in
            guard let baseAddress = storage.baseAddress else { return 0 }
            while true {
                let result = Darwin.pread(descriptor, baseAddress, requested, offset)
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard count > 0 else { return false }
        buffer.withUnsafeBytes {
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count]))
        }
        offset += off_t(count)
    }
    var finalInformation = stat()
    guard Darwin.fstat(descriptor, &finalInformation) == 0,
        finalInformation.st_dev == information.st_dev,
        finalInformation.st_ino == information.st_ino,
        finalInformation.st_gen == information.st_gen,
        finalInformation.st_mode == information.st_mode,
        finalInformation.st_nlink == information.st_nlink,
        finalInformation.st_uid == information.st_uid,
        finalInformation.st_gid == information.st_gid,
        finalInformation.st_size == information.st_size,
        finalInformation.st_flags == information.st_flags,
        finalInformation.st_mtimespec.tv_sec == revision.modificationTimeSeconds,
        finalInformation.st_mtimespec.tv_nsec == revision.modificationTimeNanoseconds,
        finalInformation.st_ctimespec.tv_sec == revision.statusChangeTimeSeconds,
        finalInformation.st_ctimespec.tv_nsec == revision.statusChangeTimeNanoseconds
    else { return false }
    guard
        PatchGenerationWorkflow.constantTimeEqual(
            Array(hasher.finalize()),
            revision.contentSHA256
        )
    else { return false }
    return PatchGenerationWorkflow.constantTimeEqual(
        revision.contentSHA256,
        try PatchGenerationWorkflow.sha256(payload)
    )
}

private struct PatchGenerationWorkBudget {
    let maximum: UInt64
    private(set) var consumed: UInt64 = 0

    mutating func consume(_ amount: UInt64) throws {
        guard amount <= maximum, consumed <= maximum - amount else {
            throw PatchGenerationPlanningError.workLimitExceeded(maximumUnits: maximum)
        }
        consumed += amount
        if consumed.isMultiple(of: 64 * 1_024) {
            try Task.checkCancellation()
        }
    }

    mutating func consumeLinePairCost(
        oldRecordCount: Int,
        newRecordCount: Int
    ) throws {
        let old = UInt64(oldRecordCount) + 1
        let new = UInt64(newRecordCount) + 1
        let (cost, overflow) = old.multipliedReportingOverflow(by: new)
        guard !overflow else {
            throw PatchGenerationPlanningError.workLimitExceeded(maximumUnits: maximum)
        }
        try consume(cost)
    }
}

private struct PatchGenerationStableReadyQueue {
    private var heap: [Int] = []

    init(capacity: Int) {
        heap.reserveCapacity(capacity)
    }

    mutating func insert(_ value: Int, work: inout PatchGenerationWorkBudget) throws {
        heap.append(value)
        var index = heap.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            try work.consume(1)
            guard heap[index] < heap[parent] else { break }
            heap.swapAt(index, parent)
            index = parent
        }
    }

    mutating func removeMinimum(
        work: inout PatchGenerationWorkBudget
    ) throws -> Int? {
        try work.consume(1)
        guard let last = heap.popLast() else { return nil }
        guard !heap.isEmpty else { return last }

        let minimum = heap[0]
        heap[0] = last
        var index = 0
        while true {
            let left = index * 2 + 1
            try work.consume(1)
            guard left < heap.count else { break }

            let right = left + 1
            var smallerChild = left
            if right < heap.count {
                try work.consume(1)
                if heap[right] < heap[left] { smallerChild = right }
            }
            try work.consume(1)
            guard heap[smallerChild] < heap[index] else { break }
            heap.swapAt(index, smallerChild)
            index = smallerChild
        }
        return minimum
    }
}
