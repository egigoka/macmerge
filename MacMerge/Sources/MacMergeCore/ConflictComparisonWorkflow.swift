import CryptoKit
import Foundation

public enum ConflictComparisonRole: String, CaseIterable, Equatable, Hashable, Sendable {
    case base
    case theirs
    case mine
}

public enum ConflictComparisonTopology: String, CaseIterable, Equatable, Hashable, Sendable {
    case twoWay
    case diff3
}

/// Exact role mapping used by this workflow. Parser `current` is Mine and parser `incoming` is
/// Theirs. `ThreeWayTextMerge.left` is Theirs and `.right` is Mine.
public struct ConflictComparisonRoleMapping: Equatable, Hashable, Sendable {
    public static let twoWay = ConflictComparisonRoleMapping(
        topology: .twoWay,
        orderedRoles: [.theirs, .mine]
    )
    public static let diff3 = ConflictComparisonRoleMapping(
        topology: .diff3,
        orderedRoles: [.base, .theirs, .mine]
    )

    public let topology: ConflictComparisonTopology
    public let orderedRoles: [ConflictComparisonRole]

    private init(
        topology: ConflictComparisonTopology,
        orderedRoles: [ConflictComparisonRole]
    ) {
        self.topology = topology
        self.orderedRoles = orderedRoles
    }

    public var twoWayLeftRole: ConflictComparisonRole { .theirs }
    public var twoWayRightRole: ConflictComparisonRole { .mine }
    public var threeWayBaseRole: ConflictComparisonRole? {
        topology == .diff3 ? .base : nil
    }
    public var threeWayLeftRole: ConflictComparisonRole? {
        topology == .diff3 ? .theirs : nil
    }
    public var threeWayRightRole: ConflictComparisonRole? {
        topology == .diff3 ? .mine : nil
    }

    public func role(for marker: ConflictMarkerKind) -> ConflictComparisonRole? {
        switch marker {
        case .current: .mine
        case .base: topology == .diff3 ? .base : nil
        case .separator: nil
        case .incoming: .theirs
        }
    }

    public func role(for source: ThreeWayTextMergeSource) -> ConflictComparisonRole? {
        guard topology == .diff3 else { return nil }
        return switch source {
        case .base: ConflictComparisonRole.base
        case .left: ConflictComparisonRole.theirs
        case .right: ConflictComparisonRole.mine
        }
    }
}

/// Opaque owner-scoped identity. Owners must not reuse `(namespace, value)` for another source.
public struct ConflictComparisonSourceIdentity: Equatable, Hashable, Sendable {
    public let namespace: UUID
    public let value: String

    public init(namespace: UUID, value: String) {
        self.namespace = namespace
        self.value = value
    }
}

/// Exact immutable source revision. Digest is SHA-256 over complete UTF-8 bytes.
public struct ConflictComparisonSourceRevision: Equatable, Hashable, Sendable {
    public let identity: ConflictComparisonSourceIdentity
    public let revision: UInt64
    public let utf8ByteCount: Int
    public let contentSHA256: [UInt8]

    public init(
        identity: ConflictComparisonSourceIdentity,
        revision: UInt64,
        utf8ByteCount: Int,
        contentSHA256: [UInt8]
    ) {
        self.identity = identity
        self.revision = revision
        self.utf8ByteCount = utf8ByteCount
        self.contentSHA256 = contentSHA256
    }
}

/// Parsed projection paired with exact role and source revision.
public struct ConflictComparisonRoleSnapshot: Equatable, Sendable {
    public let role: ConflictComparisonRole
    public let sourceRevision: ConflictComparisonSourceRevision
    public let text: String

    public init(
        role: ConflictComparisonRole,
        sourceRevision: ConflictComparisonSourceRevision,
        text: String
    ) {
        self.role = role
        self.sourceRevision = sourceRevision
        self.text = text
    }
}

public struct ConflictComparisonCapability: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: UInt16

    public static let compare = ConflictComparisonCapability(rawValue: 1 << 0)
    public static let navigate = ConflictComparisonCapability(rawValue: 1 << 1)
    public static let chooseBase = ConflictComparisonCapability(rawValue: 1 << 2)
    public static let chooseTheirs = ConflictComparisonCapability(rawValue: 1 << 3)
    public static let chooseMine = ConflictComparisonCapability(rawValue: 1 << 4)
    public static let applyResolution = ConflictComparisonCapability(rawValue: 1 << 5)
    public static let all: ConflictComparisonCapability = [
        .compare, .navigate, .chooseBase, .chooseTheirs, .chooseMine, .applyResolution
    ]

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
}

public struct ConflictComparisonSnapshotIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Immutable parsed conflict-document state. Owners must advance `generation` whenever parser
/// output, any role source, source revision, read-only state, or capability changes.
public struct ConflictComparisonParsedDocumentSnapshot: Equatable, Sendable {
    public let identity: ConflictComparisonSnapshotIdentity
    public let generation: UInt64
    /// Exact revision of the original conflict-marked document. Its bytes are intentionally absent.
    public let documentSourceRevision: ConflictComparisonSourceRevision
    /// Exact document revision from which `parseResult` was produced.
    public let parseResultSourceRevision: ConflictComparisonSourceRevision
    public let parseResult: ConflictFileParseResult
    public let roleSnapshots: [ConflictComparisonRoleSnapshot]
    public let isReadOnly: Bool
    public let capabilities: ConflictComparisonCapability

    public init(
        identity: ConflictComparisonSnapshotIdentity,
        generation: UInt64,
        documentSourceRevision: ConflictComparisonSourceRevision,
        parseResultSourceRevision: ConflictComparisonSourceRevision,
        parseResult: ConflictFileParseResult,
        roleSnapshots: [ConflictComparisonRoleSnapshot],
        isReadOnly: Bool = false,
        capabilities: ConflictComparisonCapability = .all
    ) {
        self.identity = identity
        self.generation = generation
        self.documentSourceRevision = documentSourceRevision
        self.parseResultSourceRevision = parseResultSourceRevision
        self.parseResult = parseResult
        self.roleSnapshots = roleSnapshots
        self.isReadOnly = isReadOnly
        self.capabilities = capabilities
    }
}

public struct ConflictComparisonSnapshotReference: Equatable, Hashable, Sendable {
    public let identity: ConflictComparisonSnapshotIdentity
    public let generation: UInt64

    public init(identity: ConflictComparisonSnapshotIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }

    public init(_ snapshot: ConflictComparisonParsedDocumentSnapshot) {
        identity = snapshot.identity
        generation = snapshot.generation
    }
}

/// Exact owner-state compare-and-swap token. Digest detects changed contents under reused generation.
public struct ConflictComparisonSnapshotCAS: Equatable, Hashable, Sendable {
    public let reference: ConflictComparisonSnapshotReference
    public let stateSHA256: [UInt8]

    fileprivate init(
        reference: ConflictComparisonSnapshotReference,
        stateSHA256: [UInt8]
    ) {
        self.reference = reference
        self.stateSHA256 = stateSHA256
    }
}

public enum ConflictComparisonLimit: String, CaseIterable, Equatable, Hashable, Sendable {
    case documentBytes
    case roleBytes
    case combinedRoleBytes
    case sourceIdentityUTF8Bytes
    case markerLabelUTF8Bytes
    case optionItems
    case optionStringUTF8Bytes
    case totalOptionUTF8Bytes
    case conflictCount
    case comparisonItems
    case totalItems
    case retainedBytes
    case workUnits
    case cancellationCheckInterval
}

public struct ConflictComparisonLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumDocumentBytes = 64 * 1_024 * 1_024
    public static let hardMaximumRoleBytes = 64 * 1_024 * 1_024
    public static let hardMaximumCombinedRoleBytes = 192 * 1_024 * 1_024
    public static let hardMaximumSourceIdentityUTF8Bytes = 16 * 1_024
    public static let hardMaximumMarkerLabelUTF8Bytes = 64 * 1_024
    public static let hardMaximumOptionItems = 65_536
    public static let hardMaximumOptionStringUTF8Bytes = 256 * 1_024
    public static let hardMaximumTotalOptionUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumConflictCount = 100_000
    public static let hardMaximumComparisonItems = 3 * 1_024 * 1_024 + 1
    public static let hardMaximumTotalItems = 8 * 1_024 * 1_024
    public static let hardMaximumRetainedBytes = 512 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let hardMaximumCancellationCheckInterval = 4_096
    /// `LineDiff` bounds transformed native input at 64 MiB. This envelope covers both sides'
    /// transformed bytes, record copies, and native comparison buffers at their bounded peak.
    public static let maximumNativeComparisonInputBytes = 64 * 1_024 * 1_024
    public static let maximumAtomicComparisonInputBytes = 512 * 1_024 * 1_024
    public static let maximumAtomicComparisonInputLines = 1_024 * 1_024
    public static let maximumAtomicLinePairs: UInt64 = 64 * 1_024 * 1_024
    public static let `default` = ConflictComparisonLimits()

    public let maximumDocumentBytes: Int
    public let maximumRoleBytes: Int
    public let maximumCombinedRoleBytes: Int
    public let maximumSourceIdentityUTF8Bytes: Int
    public let maximumMarkerLabelUTF8Bytes: Int
    public let maximumOptionItems: Int
    public let maximumOptionStringUTF8Bytes: Int
    public let maximumTotalOptionUTF8Bytes: Int
    public let maximumConflictCount: Int
    public let maximumComparisonItems: Int
    public let maximumTotalItems: Int
    public let maximumRetainedBytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: Int

    public init(
        maximumDocumentBytes: Int = 64 * 1_024 * 1_024,
        maximumRoleBytes: Int = 8 * 1_024 * 1_024,
        maximumCombinedRoleBytes: Int = 16 * 1_024 * 1_024,
        maximumSourceIdentityUTF8Bytes: Int = 4 * 1_024,
        maximumMarkerLabelUTF8Bytes: Int = 64 * 1_024,
        maximumOptionItems: Int = 4_096,
        maximumOptionStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalOptionUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumConflictCount: Int = 65_536,
        maximumComparisonItems: Int = 1_048_576,
        maximumTotalItems: Int = 2 * 1_048_576,
        maximumRetainedBytes: Int = 128 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 2 * 1_024 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 1_024
    ) {
        self.maximumDocumentBytes = maximumDocumentBytes
        self.maximumRoleBytes = maximumRoleBytes
        self.maximumCombinedRoleBytes = maximumCombinedRoleBytes
        self.maximumSourceIdentityUTF8Bytes = maximumSourceIdentityUTF8Bytes
        self.maximumMarkerLabelUTF8Bytes = maximumMarkerLabelUTF8Bytes
        self.maximumOptionItems = maximumOptionItems
        self.maximumOptionStringUTF8Bytes = maximumOptionStringUTF8Bytes
        self.maximumTotalOptionUTF8Bytes = maximumTotalOptionUTF8Bytes
        self.maximumConflictCount = maximumConflictCount
        self.maximumComparisonItems = maximumComparisonItems
        self.maximumTotalItems = maximumTotalItems
        self.maximumRetainedBytes = maximumRetainedBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct ConflictComparisonOptions: Equatable, Sendable {
    public let twoWay: LineDiffOptions
    public let diff3: ThreeWayTextMergeOptions

    public init(
        twoWay: LineDiffOptions = LineDiffOptions(),
        diff3: ThreeWayTextMergeOptions = ThreeWayTextMergeOptions()
    ) {
        self.twoWay = twoWay
        self.diff3 = diff3
    }
}

public struct ConflictComparisonRequest: Equatable, Sendable {
    public let snapshot: ConflictComparisonParsedDocumentSnapshot
    public let options: ConflictComparisonOptions
    public let limits: ConflictComparisonLimits

    public init(
        snapshot: ConflictComparisonParsedDocumentSnapshot,
        options: ConflictComparisonOptions = ConflictComparisonOptions(),
        limits: ConflictComparisonLimits = .default
    ) {
        self.snapshot = snapshot
        self.options = options
        self.limits = limits
    }
}

public struct ConflictComparisonRoleReference: Equatable, Hashable, Sendable {
    public let role: ConflictComparisonRole
    public let sourceRevision: ConflictComparisonSourceRevision

    fileprivate init(_ snapshot: ConflictComparisonRoleSnapshot) {
        role = snapshot.role
        sourceRevision = snapshot.sourceRevision
    }
}

public struct ConflictComparisonTwoWayResult: Equatable, Sendable {
    public let leftRole: ConflictComparisonRole
    public let rightRole: ConflictComparisonRole
    public let rows: [DiffRow]

    fileprivate init(rows: [DiffRow]) {
        leftRole = .theirs
        rightRole = .mine
        self.rows = rows
    }
}

public struct ConflictComparisonDiff3Result: Equatable, Sendable {
    public let baseRole: ConflictComparisonRole
    public let leftRole: ConflictComparisonRole
    public let rightRole: ConflictComparisonRole
    public let merge: ThreeWayTextMergeResult

    fileprivate init(merge: ThreeWayTextMergeResult) {
        baseRole = .base
        leftRole = .theirs
        rightRole = .mine
        self.merge = merge
    }
}

public enum ConflictComparisonResult: Equatable, Sendable {
    case twoWay(ConflictComparisonTwoWayResult)
    case diff3(ConflictComparisonDiff3Result)

    public var comparisonItemCount: Int {
        switch self {
        case .twoWay(let result): result.rows.count
        case .diff3(let result): result.merge.regions.count
        }
    }
}

public struct ConflictComparisonPlanningReceipt: Equatable, Hashable, Sendable {
    public let snapshot: ConflictComparisonSnapshotReference
    public let topology: ConflictComparisonTopology
    public let conflictCount: Int
    public let comparisonItemCount: Int
    public let documentUTF8ByteCount: Int
    public let roleUTF8ByteCount: Int
    public let retainedByteEstimate: Int
    public let estimatedWorkUnits: UInt64
    /// Canonical SHA-256 over exact source references, mapping, conflicts, and comparison output.
    public let planSHA256: [UInt8]

    fileprivate init(
        snapshot: ConflictComparisonSnapshotReference,
        topology: ConflictComparisonTopology,
        conflictCount: Int,
        comparisonItemCount: Int,
        documentUTF8ByteCount: Int,
        roleUTF8ByteCount: Int,
        retainedByteEstimate: Int,
        estimatedWorkUnits: UInt64,
        planSHA256: [UInt8]
    ) {
        self.snapshot = snapshot
        self.topology = topology
        self.conflictCount = conflictCount
        self.comparisonItemCount = comparisonItemCount
        self.documentUTF8ByteCount = documentUTF8ByteCount
        self.roleUTF8ByteCount = roleUTF8ByteCount
        self.retainedByteEstimate = retainedByteEstimate
        self.estimatedWorkUnits = estimatedWorkUnits
        self.planSHA256 = planSHA256
    }
}

public enum ConflictComparisonSourceLeaseContract: String, Equatable, Hashable, Sendable {
    case exactDocumentAndRoleRevisionsHeldThroughApplyCommit
}

public enum ConflictComparisonApplyContract: String, Equatable, Hashable, Sendable {
    case resolveExactlyOneTargetFromCurrentConflictDocumentWithoutReinterpretingPlan
}

public enum ConflictComparisonCASContract: String, Equatable, Hashable, Sendable {
    case serializedOwnerGenerationAndDocumentRevisionCompareAndSwap
}

public enum ConflictComparisonCapabilityContract: String, Equatable, Hashable, Sendable {
    case revalidateCapabilitiesAndReadOnlyStateBeforeMutation
}

public enum ConflictComparisonCancellationContract: String, Equatable, Hashable, Sendable {
    case cancellableBeforeMutationCommittedOrUncertainAfterCASStarts
}

/// Mandatory app-layer boundary. Workflow performs no document mutation, filesystem access, or UI.
public struct ConflictComparisonExecutorContract: Equatable, Hashable, Sendable {
    public static let required = ConflictComparisonExecutorContract()

    public let sourceLease =
        ConflictComparisonSourceLeaseContract.exactDocumentAndRoleRevisionsHeldThroughApplyCommit
    public let apply =
        ConflictComparisonApplyContract
        .resolveExactlyOneTargetFromCurrentConflictDocumentWithoutReinterpretingPlan
    public let compareAndSwap =
        ConflictComparisonCASContract.serializedOwnerGenerationAndDocumentRevisionCompareAndSwap
    public let capability =
        ConflictComparisonCapabilityContract.revalidateCapabilitiesAndReadOnlyStateBeforeMutation
    public let cancellation =
        ConflictComparisonCancellationContract
        .cancellableBeforeMutationCommittedOrUncertainAfterCASStarts

    public init() {}
}

/// Prepared immutable comparison. Building it calls existing parser-result navigation and text
/// comparison primitives only; it does not parse source bytes or perform effects.
public struct ConflictComparisonPlan: Equatable, Sendable {
    public let snapshotCAS: ConflictComparisonSnapshotCAS
    public let documentSourceRevision: ConflictComparisonSourceRevision
    public let isReadOnly: Bool
    public let capabilities: ConflictComparisonCapability
    public let mapping: ConflictComparisonRoleMapping
    public let roleReferences: [ConflictComparisonRoleReference]
    public let comparison: ConflictComparisonResult
    public let navigation: ConflictNavigationIndex
    public let receipt: ConflictComparisonPlanningReceipt
    public let limits: ConflictComparisonLimits
    public let executorContract: ConflictComparisonExecutorContract

    fileprivate init(
        snapshotCAS: ConflictComparisonSnapshotCAS,
        documentSourceRevision: ConflictComparisonSourceRevision,
        isReadOnly: Bool,
        capabilities: ConflictComparisonCapability,
        mapping: ConflictComparisonRoleMapping,
        roleReferences: [ConflictComparisonRoleReference],
        comparison: ConflictComparisonResult,
        navigation: ConflictNavigationIndex,
        receipt: ConflictComparisonPlanningReceipt,
        limits: ConflictComparisonLimits
    ) {
        self.snapshotCAS = snapshotCAS
        self.documentSourceRevision = documentSourceRevision
        self.isReadOnly = isReadOnly
        self.capabilities = capabilities
        self.mapping = mapping
        self.roleReferences = roleReferences
        self.comparison = comparison
        self.navigation = navigation
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func roleReference(
        for role: ConflictComparisonRole
    ) -> ConflictComparisonRoleReference? {
        roleReferences.first { $0.role == role }
    }

    public func validateCurrentSnapshot(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot
    ) throws {
        do {
            try ConflictComparisonWorkflow.validate(
                snapshot,
                against: snapshotCAS,
                limits: limits
            )
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
    }

    public func navigationPlan(
        _ request: ConflictComparisonNavigationRequest
    ) throws -> ConflictComparisonNavigationPlan {
        try ConflictComparisonWorkflow.planNavigation(request, in: self)
    }

    public func resolutionPlan(
        _ intent: ConflictComparisonResolutionIntent
    ) throws -> ConflictComparisonResolutionPlan {
        try ConflictComparisonWorkflow.planResolution(intent, in: self)
    }
}

public enum ConflictComparisonNavigationCommand:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case first
    case current
    case previous
    case next
    case last
}

public enum ConflictComparisonSelectionIntent: Equatable, Hashable, Sendable {
    case command(ConflictComparisonNavigationCommand)
    case select(ConflictNavigationTarget.ID)
    case clear
}

public struct ConflictComparisonSelectionState: Equatable, Hashable, Sendable {
    public let snapshot: ConflictComparisonSnapshotReference
    public let selectedConflictID: ConflictNavigationTarget.ID?
    /// One-based row in the original conflict-marked document.
    public let cursorSourceLine: Int?

    public var generation: UInt64 { snapshot.generation }

    public init(
        snapshot: ConflictComparisonSnapshotReference,
        selectedConflictID: ConflictNavigationTarget.ID? = nil,
        cursorSourceLine: Int? = nil
    ) {
        self.snapshot = snapshot
        self.selectedConflictID = selectedConflictID
        self.cursorSourceLine = cursorSourceLine
    }
}

public struct ConflictComparisonNavigationRequest: Equatable, Hashable, Sendable {
    public let state: ConflictComparisonSelectionState
    public let intent: ConflictComparisonSelectionIntent

    public init(
        state: ConflictComparisonSelectionState,
        intent: ConflictComparisonSelectionIntent
    ) {
        self.state = state
        self.intent = intent
    }
}

public struct ConflictComparisonNavigationReceipt: Equatable, Hashable, Sendable {
    public let snapshot: ConflictComparisonSnapshotReference
    public let intent: ConflictComparisonSelectionIntent
    public let selectedConflictID: ConflictNavigationTarget.ID?
    public let receiptSHA256: [UInt8]

    fileprivate init(
        snapshot: ConflictComparisonSnapshotReference,
        intent: ConflictComparisonSelectionIntent,
        selectedConflictID: ConflictNavigationTarget.ID?,
        receiptSHA256: [UInt8]
    ) {
        self.snapshot = snapshot
        self.intent = intent
        self.selectedConflictID = selectedConflictID
        self.receiptSHA256 = receiptSHA256
    }
}

public struct ConflictComparisonNavigationPlan: Equatable, Hashable, Sendable {
    public let snapshotCAS: ConflictComparisonSnapshotCAS
    public let priorState: ConflictComparisonSelectionState
    public let intent: ConflictComparisonSelectionIntent
    public let target: ConflictNavigationTarget?
    public let receipt: ConflictComparisonNavigationReceipt

    public var selectedConflictID: ConflictNavigationTarget.ID? { target?.id }
    public var canNavigate: Bool { target != nil }

    fileprivate init(
        snapshotCAS: ConflictComparisonSnapshotCAS,
        priorState: ConflictComparisonSelectionState,
        intent: ConflictComparisonSelectionIntent,
        target: ConflictNavigationTarget?,
        receipt: ConflictComparisonNavigationReceipt
    ) {
        self.snapshotCAS = snapshotCAS
        self.priorState = priorState
        self.intent = intent
        self.target = target
        self.receipt = receipt
    }
}

public enum ConflictComparisonResolutionChoice:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case base
    case theirs
    case mine

    public var role: ConflictComparisonRole {
        switch self {
        case .base: .base
        case .theirs: .theirs
        case .mine: .mine
        }
    }

    public var threeWayMergeChoice: ThreeWayTextMergeConflictChoice {
        switch self {
        case .base: .base
        case .theirs: .left
        case .mine: .right
        }
    }
}

public enum ConflictComparisonResolutionAction:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    /// Produce a deterministic choice plan without authorizing document mutation.
    case choose
    /// Authorize one executor attempt under exact snapshot and document CAS.
    case apply
}

public struct ConflictComparisonResolutionIntent: Equatable, Hashable, Sendable {
    public let snapshot: ConflictComparisonSnapshotReference
    public let targetID: ConflictNavigationTarget.ID
    public let choice: ConflictComparisonResolutionChoice
    public let action: ConflictComparisonResolutionAction

    public init(
        snapshot: ConflictComparisonSnapshotReference,
        targetID: ConflictNavigationTarget.ID,
        choice: ConflictComparisonResolutionChoice,
        action: ConflictComparisonResolutionAction
    ) {
        self.snapshot = snapshot
        self.targetID = targetID
        self.choice = choice
        self.action = action
    }
}

public struct ConflictComparisonResolutionReceipt: Equatable, Hashable, Sendable {
    public let snapshot: ConflictComparisonSnapshotReference
    public let targetID: ConflictNavigationTarget.ID
    public let choice: ConflictComparisonResolutionChoice
    public let action: ConflictComparisonResolutionAction
    public let selectedSourceRevision: ConflictComparisonSourceRevision
    public let planSHA256: [UInt8]

    fileprivate init(
        snapshot: ConflictComparisonSnapshotReference,
        targetID: ConflictNavigationTarget.ID,
        choice: ConflictComparisonResolutionChoice,
        action: ConflictComparisonResolutionAction,
        selectedSourceRevision: ConflictComparisonSourceRevision,
        planSHA256: [UInt8]
    ) {
        self.snapshot = snapshot
        self.targetID = targetID
        self.choice = choice
        self.action = action
        self.selectedSourceRevision = selectedSourceRevision
        self.planSHA256 = planSHA256
    }
}

public struct ConflictComparisonResolutionPlan: Equatable, Hashable, Sendable {
    public let snapshotCAS: ConflictComparisonSnapshotCAS
    public let documentSourceRevision: ConflictComparisonSourceRevision
    public let target: ConflictNavigationTarget
    public let choice: ConflictComparisonResolutionChoice
    public let action: ConflictComparisonResolutionAction
    public let selectedSourceRevision: ConflictComparisonSourceRevision
    public let receipt: ConflictComparisonResolutionReceipt
    public let limits: ConflictComparisonLimits
    public let executorContract: ConflictComparisonExecutorContract

    public var authorizesMutation: Bool { action == .apply }

    fileprivate init(
        plan: ConflictComparisonPlan,
        target: ConflictNavigationTarget,
        intent: ConflictComparisonResolutionIntent,
        selectedSourceRevision: ConflictComparisonSourceRevision,
        receipt: ConflictComparisonResolutionReceipt
    ) {
        snapshotCAS = plan.snapshotCAS
        documentSourceRevision = plan.documentSourceRevision
        self.target = target
        choice = intent.choice
        action = intent.action
        self.selectedSourceRevision = selectedSourceRevision
        self.receipt = receipt
        limits = plan.limits
        executorContract = .required
    }

    public func validateCurrentSnapshot(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot
    ) throws {
        do {
            try ConflictComparisonWorkflow.validateReference(
                snapshot,
                expected: snapshotCAS.reference
            )
            guard snapshot.documentSourceRevision == documentSourceRevision else {
                throw ConflictComparisonWorkflowError.documentSourceChanged
            }
            let choiceCapability: ConflictComparisonCapability =
                switch choice {
                case .base: .chooseBase
                case .theirs: .chooseTheirs
                case .mine: .chooseMine
                }
            guard snapshot.capabilities.contains(choiceCapability) else {
                throw ConflictComparisonWorkflowError.missingCapability(choiceCapability)
            }
            if action == .apply {
                guard !snapshot.isReadOnly else {
                    throw ConflictComparisonWorkflowError.readOnlyDocument
                }
                guard snapshot.capabilities.contains(.applyResolution) else {
                    throw ConflictComparisonWorkflowError.missingCapability(.applyResolution)
                }
            }
            try ConflictComparisonWorkflow.validate(
                snapshot,
                against: snapshotCAS,
                limits: limits
            )
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
    }

    /// Executor obtains this after entering its serialized owner/source lease and immediately before
    /// invoking document CAS. Cancellation after issuance must not be reported as definitely clean.
    public func authorizeApply(
        validating snapshot: ConflictComparisonParsedDocumentSnapshot
    ) throws -> ConflictComparisonApplyPermit {
        guard action == .apply else {
            throw ConflictComparisonWorkflowError.applyAuthorizationRequiresApplyIntent
        }
        try validateCurrentSnapshot(snapshot)
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
        return ConflictComparisonApplyPermit(
            planningReceipt: receipt,
            predecessorCAS: snapshotCAS,
            documentSourceRevision: documentSourceRevision
        )
    }

    public func authorizeChoice(
        validating snapshot: ConflictComparisonParsedDocumentSnapshot
    ) throws -> ConflictComparisonChoicePermit {
        guard action == .choose else {
            throw ConflictComparisonWorkflowError.choiceAuthorizationRequiresChooseIntent
        }
        try validateCurrentSnapshot(snapshot)
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
        return ConflictComparisonChoicePermit(
            planningReceipt: receipt,
            snapshotCAS: snapshotCAS
        )
    }
}

public enum ConflictComparisonWorkflowError:
    Error, Equatable, LocalizedError, Sendable
{
    case cancelled
    case invalidLimit(ConflictComparisonLimit)
    case staleSnapshotIdentity(
        expected: ConflictComparisonSnapshotIdentity,
        actual: ConflictComparisonSnapshotIdentity
    )
    case staleGeneration(expected: UInt64, actual: UInt64)
    case snapshotContentsChanged
    case invalidCapabilities(UInt16)
    case missingCapability(ConflictComparisonCapability)
    case invalidSourceIdentity(ConflictComparisonRole?)
    case invalidSourceRevision(ConflictComparisonRole?)
    case conflictingSourceRevision
    case parseResultSourceRevisionMismatch
    case documentTooLarge(maximumBytes: Int)
    case roleTooLarge(role: ConflictComparisonRole, maximumBytes: Int)
    case combinedRolesTooLarge(maximumBytes: Int)
    case roleRevisionByteCountMismatch(
        role: ConflictComparisonRole,
        expected: Int,
        actual: Int
    )
    case roleRevisionDigestMismatch(ConflictComparisonRole)
    case markerLabelTooLarge(maximumBytes: Int)
    case tooManyOptionItems(maximum: Int)
    case optionStringTooLarge(maximumBytes: Int)
    case optionsTooLarge(maximumBytes: Int)
    case unsafeSubstitutionReplacement
    case reservedTransformMarkerCollision
    case duplicateRole(ConflictComparisonRole)
    case missingRole(ConflictComparisonRole)
    case unexpectedRole(ConflictComparisonRole)
    case noConflicts
    case parsedRoleTextMismatch(ConflictComparisonRole)
    case tooManyConflicts(maximum: Int)
    case tooManyComparisonItems(maximum: Int)
    case tooManyItems(maximum: Int)
    case retainedDataTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumUnits: UInt64)
    case atomicComparisonLimitExceeded(maximumBytes: Int)
    case atomicComparisonWorkLimitExceeded(maximumLinePairs: UInt64)
    case invalidSelectionSourceLine(Int)
    case staleConflictGeneration(expected: UInt64, actual: UInt64)
    case staleConflictIdentity(ConflictNavigationTarget.ID)
    case baseUnavailableInTwoWayComparison
    case readOnlyDocument
    case documentSourceChanged
    case choiceAuthorizationRequiresChooseIntent
    case applyAuthorizationRequiresApplyIntent
    case successorGenerationExhausted
    case successorSourceRevisionExhausted
    case invalidSuccessorGeneration(expectedAfter: UInt64, actual: UInt64)
    case invalidSuccessorSourceRevision
    case conflictNavigation(ConflictNavigationError)
    case lineDiff(LineDiffError)
    case threeWayMerge(ThreeWayTextMergeError)
    case arithmeticOverflow

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Conflict comparison planning was cancelled."
        case .invalidLimit(let limit):
            "Invalid conflict comparison limit: \(limit.rawValue)."
        case .staleSnapshotIdentity:
            "Conflict comparison plan belongs to another document snapshot."
        case .staleGeneration(let expected, let actual):
            "Conflict comparison expected generation \(expected), not \(actual)."
        case .snapshotContentsChanged:
            "Conflict comparison snapshot changed without advancing generation."
        case .invalidCapabilities(let rawValue):
            "Conflict comparison capabilities contain unsupported bits: \(rawValue)."
        case .missingCapability(let capability):
            "Conflict comparison lacks required capability \(capability.rawValue)."
        case .invalidSourceIdentity(let role):
            "Invalid conflict comparison source identity for \(Self.roleDescription(role))."
        case .invalidSourceRevision(let role):
            "Invalid conflict comparison source revision for \(Self.roleDescription(role))."
        case .conflictingSourceRevision:
            "One conflict comparison source identity and revision has conflicting metadata."
        case .parseResultSourceRevisionMismatch:
            "Conflict parser output does not belong to the current document source revision."
        case .documentTooLarge(let maximum):
            "Conflict document exceeds the \(maximum)-byte workflow limit."
        case .roleTooLarge(let role, let maximum):
            "Conflict \(role.rawValue) text exceeds the \(maximum)-byte workflow limit."
        case .combinedRolesTooLarge(let maximum):
            "Conflict role text exceeds the \(maximum)-byte combined workflow limit."
        case .roleRevisionByteCountMismatch(let role, let expected, let actual):
            "Conflict \(role.rawValue) revision expects \(expected) bytes, not \(actual)."
        case .roleRevisionDigestMismatch(let role):
            "Conflict \(role.rawValue) text does not match its exact revision digest."
        case .markerLabelTooLarge(let maximum):
            "Conflict marker label exceeds the \(maximum)-byte workflow limit."
        case .tooManyOptionItems(let maximum):
            "Conflict comparison exceeds the \(maximum)-option-item limit."
        case .optionStringTooLarge(let maximum):
            "Conflict comparison option string exceeds the \(maximum)-byte limit."
        case .optionsTooLarge(let maximum):
            "Conflict comparison options exceed the \(maximum)-byte aggregate limit."
        case .unsafeSubstitutionReplacement:
            "Conflict comparison substitutions require literal single-line replacement text."
        case .reservedTransformMarkerCollision:
            "Conflict comparison input contains the reserved line-transform marker family."
        case .duplicateRole(let role):
            "Conflict comparison repeats the \(role.rawValue) role."
        case .missingRole(let role):
            "Conflict comparison is missing the \(role.rawValue) role."
        case .unexpectedRole(let role):
            "Conflict comparison has unexpected \(role.rawValue) text for its topology."
        case .noConflicts:
            "Conflict comparison requires at least one parsed conflict."
        case .parsedRoleTextMismatch(let role):
            "Conflict \(role.rawValue) snapshot does not match parser output."
        case .tooManyConflicts(let maximum):
            "Conflict comparison exceeds the \(maximum)-conflict limit."
        case .tooManyComparisonItems(let maximum):
            "Conflict comparison exceeds the \(maximum)-comparison-item limit."
        case .tooManyItems(let maximum):
            "Conflict comparison exceeds the \(maximum)-item aggregate limit."
        case .retainedDataTooLarge(let maximum):
            "Conflict comparison plan exceeds the \(maximum)-byte retained-data limit."
        case .workLimitExceeded(let maximum):
            "Conflict comparison exceeds the \(maximum)-unit work limit."
        case .atomicComparisonLimitExceeded(let maximum):
            "Conflict comparison exceeds the \(maximum)-byte cancellability envelope."
        case .atomicComparisonWorkLimitExceeded(let maximum):
            "Conflict comparison exceeds the \(maximum)-line-pair cancellability envelope."
        case .invalidSelectionSourceLine(let line):
            "Conflict selection source line must be positive: \(line)."
        case .staleConflictGeneration(let expected, let actual):
            "Conflict selection expected generation \(expected), not \(actual)."
        case .staleConflictIdentity:
            "Conflict selection identity is stale or forged."
        case .baseUnavailableInTwoWayComparison:
            "Base resolution is unavailable for a two-way conflict."
        case .readOnlyDocument:
            "Conflict resolution cannot be applied to a read-only document."
        case .documentSourceChanged:
            "Conflict document source revision changed after planning."
        case .choiceAuthorizationRequiresChooseIntent:
            "Conflict choice authorization requires a choose resolution plan."
        case .applyAuthorizationRequiresApplyIntent:
            "Conflict apply authorization requires an apply resolution plan."
        case .successorGenerationExhausted:
            "Conflict resolution cannot advance the maximum snapshot generation."
        case .successorSourceRevisionExhausted:
            "Conflict resolution cannot advance the maximum document source revision."
        case .invalidSuccessorGeneration(let expected, let actual):
            "Applied conflict successor generation must exceed \(expected), not \(actual)."
        case .invalidSuccessorSourceRevision:
            "Applied conflict successor source revision is invalid."
        case .conflictNavigation(let error):
            error.localizedDescription
        case .lineDiff(let error):
            error.localizedDescription
        case .threeWayMerge(let error):
            error.localizedDescription
        case .arithmeticOverflow:
            "Conflict comparison size calculation overflowed."
        }
    }

    private static func roleDescription(_ role: ConflictComparisonRole?) -> String {
        role?.rawValue ?? "conflict document"
    }
}

public enum ConflictComparisonExecutionFailureCode:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case staleSnapshot
    case sourceRevisionChanged
    case readOnly
    case missingCapability
    case invalidPlan
    case compareAndSwapFailed
    case contractUnsupported
    case applyFailedBeforeMutation
}

/// Core-issued proof that exact choice state passed validation immediately before recording.
public struct ConflictComparisonChoicePermit: Equatable, Hashable, Sendable {
    fileprivate let planningReceipt: ConflictComparisonResolutionReceipt
    fileprivate let snapshotCAS: ConflictComparisonSnapshotCAS
}

/// Core-issued proof that executor passed exact pre-CAS validation while holding required leases.
public struct ConflictComparisonApplyPermit: Equatable, Hashable, Sendable {
    fileprivate let planningReceipt: ConflictComparisonResolutionReceipt
    fileprivate let predecessorCAS: ConflictComparisonSnapshotCAS
    fileprivate let documentSourceRevision: ConflictComparisonSourceRevision
}

/// Executor attestation from one atomic owner/document compare-and-swap attempt. Core validates its
/// plan binding; executor remains trusted to report external CAS truthfully.
public struct ConflictComparisonApplyCASReceipt: Equatable, Hashable, Sendable {
    fileprivate let planningReceipt: ConflictComparisonResolutionReceipt
    fileprivate let predecessorCAS: ConflictComparisonSnapshotCAS
    public let successor: ConflictComparisonAppliedSuccessor

    private init(
        permit: ConflictComparisonApplyPermit,
        successor: ConflictComparisonAppliedSuccessor
    ) {
        planningReceipt = permit.planningReceipt
        predecessorCAS = permit.predecessorCAS
        self.successor = successor
    }

    /// Call only after matching atomic CAS commits chosen conflict resolution.
    public static func executorAttestedCommitted(
        permit: ConflictComparisonApplyPermit,
        successor: ConflictComparisonAppliedSuccessor
    ) -> ConflictComparisonApplyCASReceipt {
        ConflictComparisonApplyCASReceipt(permit: permit, successor: successor)
    }
}

public struct ConflictComparisonChoiceExecutionReceipt: Equatable, Hashable, Sendable {
    public let planningReceipt: ConflictComparisonResolutionReceipt

    fileprivate init(planningReceipt: ConflictComparisonResolutionReceipt) {
        self.planningReceipt = planningReceipt
    }
}

public struct ConflictComparisonAppliedSuccessor: Equatable, Hashable, Sendable {
    public let snapshot: ConflictComparisonSnapshotReference
    public let documentSourceRevision: ConflictComparisonSourceRevision

    public init(
        snapshot: ConflictComparisonSnapshotReference,
        documentSourceRevision: ConflictComparisonSourceRevision
    ) {
        self.snapshot = snapshot
        self.documentSourceRevision = documentSourceRevision
    }
}

public struct ConflictComparisonApplyExecutionReceipt: Equatable, Hashable, Sendable {
    public let planningReceipt: ConflictComparisonResolutionReceipt
    public let predecessorCAS: ConflictComparisonSnapshotCAS
    public let successor: ConflictComparisonAppliedSuccessor
    fileprivate init(
        planningReceipt: ConflictComparisonResolutionReceipt,
        predecessorCAS: ConflictComparisonSnapshotCAS,
        successor: ConflictComparisonAppliedSuccessor
    ) {
        self.planningReceipt = planningReceipt
        self.predecessorCAS = predecessorCAS
        self.successor = successor
    }
}

public enum ConflictComparisonExecutionSuccess: Equatable, Hashable, Sendable {
    case choiceRecorded(ConflictComparisonChoiceExecutionReceipt)
    case applied(ConflictComparisonApplyExecutionReceipt)
}

public struct ConflictComparisonExecutionFailure: Equatable, Hashable, Sendable {
    public let code: ConflictComparisonExecutionFailureCode

    fileprivate init(code: ConflictComparisonExecutionFailureCode) {
        self.code = code
    }
}

public struct ConflictComparisonMutationUncertainty: Equatable, Hashable, Sendable {
    public let planningReceipt: ConflictComparisonResolutionReceipt
    public let snapshot: ConflictComparisonSnapshotReference
    public let targetID: ConflictNavigationTarget.ID

    fileprivate init(planningReceipt: ConflictComparisonResolutionReceipt) {
        self.planningReceipt = planningReceipt
        snapshot = planningReceipt.snapshot
        targetID = planningReceipt.targetID
    }
}

public struct ConflictComparisonCancellationReceipt: Equatable, Hashable, Sendable {
    public let planningReceipt: ConflictComparisonResolutionReceipt

    fileprivate init(planningReceipt: ConflictComparisonResolutionReceipt) {
        self.planningReceipt = planningReceipt
    }
}

public enum ConflictComparisonExecutionOutcome: Equatable, Hashable, Sendable {
    case completed(ConflictComparisonExecutionSuccess)
    case failed(ConflictComparisonExecutionFailure)
    case cancelled(ConflictComparisonCancellationReceipt)
    case mutationUncertain(ConflictComparisonMutationUncertainty)
}

/// App/platform executor. It must enforce `ConflictComparisonExecutorContract.required` and call
/// `plan.validateCurrentSnapshot` before recording a choice or beginning an apply CAS.
public protocol ConflictComparisonResolutionPlanExecutor: Sendable {
    func execute(
        _ plan: ConflictComparisonResolutionPlan,
        validating currentSnapshot: ConflictComparisonParsedDocumentSnapshot
    ) async -> ConflictComparisonExecutionOutcome
}

/// Constructs only outcomes consistent with one immutable resolution plan.
public enum ConflictComparisonExecutionOutcomeFactory: Sendable {
    public static func choiceRecorded(
        plan: ConflictComparisonResolutionPlan,
        permit: ConflictComparisonChoicePermit
    ) -> ConflictComparisonExecutionOutcome {
        guard plan.action == .choose,
            permit.planningReceipt == plan.receipt,
            permit.snapshotCAS == plan.snapshotCAS
        else { return invalidPlan() }
        return .completed(
            .choiceRecorded(
                ConflictComparisonChoiceExecutionReceipt(planningReceipt: plan.receipt)
            )
        )
    }

    public static func applied(
        plan: ConflictComparisonResolutionPlan,
        casReceipt: ConflictComparisonApplyCASReceipt
    ) -> ConflictComparisonExecutionOutcome {
        guard plan.action == .apply,
            casReceipt.planningReceipt == plan.receipt,
            casReceipt.predecessorCAS == plan.snapshotCAS,
            casReceipt.planningReceipt.targetID == plan.target.id,
            casReceipt.planningReceipt.choice == plan.choice,
            casReceipt.planningReceipt.action == .apply,
            casReceipt.planningReceipt.selectedSourceRevision == plan.selectedSourceRevision
        else {
            return invalidPlan()
        }
        guard
            casReceipt.successor.documentSourceRevision.utf8ByteCount
                != plan.documentSourceRevision.utf8ByteCount
                || casReceipt.successor.documentSourceRevision.contentSHA256
                    != plan.documentSourceRevision.contentSHA256,
            casReceipt.successor.snapshot.identity == plan.snapshotCAS.reference.identity,
            casReceipt.successor.snapshot.generation > plan.snapshotCAS.reference.generation,
            casReceipt.successor.documentSourceRevision.identity
                == plan.documentSourceRevision.identity,
            casReceipt.successor.documentSourceRevision.revision
                > plan.documentSourceRevision.revision,
            casReceipt.successor.documentSourceRevision.contentSHA256.count == SHA256.byteCount,
            casReceipt.successor.documentSourceRevision.utf8ByteCount >= 0
        else {
            return .mutationUncertain(
                ConflictComparisonMutationUncertainty(
                    planningReceipt: plan.receipt
                )
            )
        }
        return .completed(
            .applied(
                ConflictComparisonApplyExecutionReceipt(
                    planningReceipt: plan.receipt,
                    predecessorCAS: plan.snapshotCAS,
                    successor: casReceipt.successor
                )
            )
        )
    }

    public static func failed(
        plan: ConflictComparisonResolutionPlan,
        code: ConflictComparisonExecutionFailureCode
    ) -> ConflictComparisonExecutionOutcome {
        if plan.action == .choose {
            guard
                code == .staleSnapshot
                    || code == .sourceRevisionChanged
                    || code == .missingCapability
                    || code == .invalidPlan
                    || code == .contractUnsupported
            else { return invalidPlan() }
        }
        return .failed(ConflictComparisonExecutionFailure(code: code))
    }

    public static func cancelledBeforeApplyAuthorization(
        plan: ConflictComparisonResolutionPlan
    ) -> ConflictComparisonExecutionOutcome {
        guard plan.action == .apply else { return invalidPlan() }
        return .cancelled(
            ConflictComparisonCancellationReceipt(planningReceipt: plan.receipt)
        )
    }

    public static func mutationUncertain(
        plan: ConflictComparisonResolutionPlan,
        permit: ConflictComparisonApplyPermit
    ) -> ConflictComparisonExecutionOutcome {
        guard plan.action == .apply,
            permit.planningReceipt == plan.receipt,
            permit.predecessorCAS == plan.snapshotCAS,
            permit.documentSourceRevision == plan.documentSourceRevision
        else { return invalidPlan() }
        return .mutationUncertain(
            ConflictComparisonMutationUncertainty(
                planningReceipt: plan.receipt
            )
        )
    }

    private static func invalidPlan() -> ConflictComparisonExecutionOutcome {
        .failed(ConflictComparisonExecutionFailure(code: .invalidPlan))
    }
}

public enum ConflictComparisonWorkflow: Sendable {
    public static func prepare(
        _ request: ConflictComparisonRequest,
        expecting expectedSnapshot: ConflictComparisonSnapshotReference? = nil
    ) throws -> ConflictComparisonPlan {
        do {
            return try makePlan(request, expecting: expectedSnapshot)
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
    }

    public static func planNavigation(
        _ request: ConflictComparisonNavigationRequest,
        in plan: ConflictComparisonPlan
    ) throws -> ConflictComparisonNavigationPlan {
        do {
            try Task.checkCancellation()
            guard plan.capabilities.contains(.navigate) else {
                throw ConflictComparisonWorkflowError.missingCapability(.navigate)
            }
            guard request.state.snapshot.identity == plan.snapshotCAS.reference.identity else {
                throw ConflictComparisonWorkflowError.staleSnapshotIdentity(
                    expected: plan.snapshotCAS.reference.identity,
                    actual: request.state.snapshot.identity
                )
            }
            guard request.state.generation == plan.navigation.generation else {
                throw ConflictComparisonWorkflowError.staleGeneration(
                    expected: plan.navigation.generation,
                    actual: request.state.generation
                )
            }
            let origin = try navigationOrigin(request.state, in: plan.navigation)
            let target: ConflictNavigationTarget?
            switch request.intent {
            case .clear:
                target = nil
            case .select(let id):
                target = try requiredValidatedTarget(id, in: plan.navigation)
            case .command(let command):
                switch command {
                case .first:
                    target = plan.navigation.first
                case .current:
                    target = plan.navigation.current(
                        selectedConflict: origin.selected,
                        cursorRow: origin.cursorSourceLine
                    )
                case .previous:
                    target = plan.navigation.previous(
                        before: origin.selected,
                        cursorRow: origin.cursorSourceLine
                    )
                case .next:
                    target = plan.navigation.next(
                        after: origin.selected,
                        cursorRow: origin.cursorSourceLine
                    )
                case .last:
                    target = plan.navigation.last
                }
            }
            var digest = ConflictComparisonDigest(domain: "ConflictComparisonNavigation.v1")
            digest.append(plan.receipt.planSHA256)
            append(request.state, to: &digest)
            append(request.intent, to: &digest)
            append(target?.id, to: &digest)
            let receiptSHA256 = digest.finalize()
            try Task.checkCancellation()
            let receipt = ConflictComparisonNavigationReceipt(
                snapshot: plan.snapshotCAS.reference,
                intent: request.intent,
                selectedConflictID: target?.id,
                receiptSHA256: receiptSHA256
            )
            return ConflictComparisonNavigationPlan(
                snapshotCAS: plan.snapshotCAS,
                priorState: request.state,
                intent: request.intent,
                target: target,
                receipt: receipt
            )
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
    }

    private static func navigationOrigin(
        _ state: ConflictComparisonSelectionState,
        in navigation: ConflictNavigationIndex
    ) throws -> (selected: ConflictNavigationTarget?, cursorSourceLine: Int?) {
        if let line = state.cursorSourceLine, line <= 0 {
            throw ConflictComparisonWorkflowError.invalidSelectionSourceLine(line)
        }
        return (
            try validatedTarget(state.selectedConflictID, in: navigation),
            state.cursorSourceLine
        )
    }

    public static func planResolution(
        _ intent: ConflictComparisonResolutionIntent,
        in plan: ConflictComparisonPlan
    ) throws -> ConflictComparisonResolutionPlan {
        do {
            try Task.checkCancellation()
            guard intent.snapshot.identity == plan.snapshotCAS.reference.identity else {
                throw ConflictComparisonWorkflowError.staleSnapshotIdentity(
                    expected: plan.snapshotCAS.reference.identity,
                    actual: intent.snapshot.identity
                )
            }
            guard intent.snapshot.generation == plan.snapshotCAS.reference.generation else {
                throw ConflictComparisonWorkflowError.staleGeneration(
                    expected: plan.snapshotCAS.reference.generation,
                    actual: intent.snapshot.generation
                )
            }
            let target = try requiredValidatedTarget(intent.targetID, in: plan.navigation)
            let choiceCapability: ConflictComparisonCapability
            switch intent.choice {
            case .base:
                guard plan.mapping.topology == .diff3 else {
                    throw ConflictComparisonWorkflowError.baseUnavailableInTwoWayComparison
                }
                choiceCapability = .chooseBase
            case .theirs:
                choiceCapability = .chooseTheirs
            case .mine:
                choiceCapability = .chooseMine
            }
            guard planCapability(plan, contains: choiceCapability) else {
                throw ConflictComparisonWorkflowError.missingCapability(choiceCapability)
            }
            if intent.action == .apply {
                guard planCapability(plan, contains: .applyResolution) else {
                    throw ConflictComparisonWorkflowError.missingCapability(.applyResolution)
                }
                guard !planIsReadOnly(plan) else {
                    throw ConflictComparisonWorkflowError.readOnlyDocument
                }
                guard plan.snapshotCAS.reference.generation < UInt64.max else {
                    throw ConflictComparisonWorkflowError.successorGenerationExhausted
                }
                guard plan.documentSourceRevision.revision < UInt64.max else {
                    throw ConflictComparisonWorkflowError.successorSourceRevisionExhausted
                }
            }
            guard let selectedSource = plan.roleReference(for: intent.choice.role) else {
                throw ConflictComparisonWorkflowError.missingRole(intent.choice.role)
            }
            var digest = ConflictComparisonDigest(domain: "ConflictComparisonResolution.v1")
            digest.append(plan.receipt.planSHA256)
            digest.append(intent.snapshot.identity.rawValue)
            digest.append(intent.snapshot.generation)
            append(intent.targetID, to: &digest)
            digest.append(intent.choice.rawValue)
            digest.append(intent.action.rawValue)
            append(selectedSource.sourceRevision, to: &digest)
            let planSHA256 = digest.finalize()
            try Task.checkCancellation()
            let receipt = ConflictComparisonResolutionReceipt(
                snapshot: plan.snapshotCAS.reference,
                targetID: intent.targetID,
                choice: intent.choice,
                action: intent.action,
                selectedSourceRevision: selectedSource.sourceRevision,
                planSHA256: planSHA256
            )
            return ConflictComparisonResolutionPlan(
                plan: plan,
                target: target,
                intent: intent,
                selectedSourceRevision: selectedSource.sourceRevision,
                receipt: receipt
            )
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
    }

    fileprivate static func validate(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot,
        against expected: ConflictComparisonSnapshotCAS,
        limits: ConflictComparisonLimits
    ) throws {
        try Task.checkCancellation()
        try validateReference(snapshot, expected: expected.reference)
        var work = ConflictComparisonWorkBudget(limits: limits)
        let validated = try validateSnapshot(snapshot, limits: limits, work: &work)
        let actual = try snapshotCAS(snapshot, validated: validated, work: &work)
        guard actual == expected else {
            throw ConflictComparisonWorkflowError.snapshotContentsChanged
        }
    }

    fileprivate static func validateReference(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot,
        expected: ConflictComparisonSnapshotReference
    ) throws {
        guard snapshot.identity == expected.identity else {
            throw ConflictComparisonWorkflowError.staleSnapshotIdentity(
                expected: expected.identity,
                actual: snapshot.identity
            )
        }
        guard snapshot.generation == expected.generation else {
            throw ConflictComparisonWorkflowError.staleGeneration(
                expected: expected.generation,
                actual: snapshot.generation
            )
        }
    }

    private static func makePlan(
        _ request: ConflictComparisonRequest,
        expecting expectedSnapshot: ConflictComparisonSnapshotReference?
    ) throws -> ConflictComparisonPlan {
        try Task.checkCancellation()
        try validate(request.limits)
        if let expectedSnapshot {
            guard request.snapshot.identity == expectedSnapshot.identity else {
                throw ConflictComparisonWorkflowError.staleSnapshotIdentity(
                    expected: expectedSnapshot.identity,
                    actual: request.snapshot.identity
                )
            }
            guard request.snapshot.generation == expectedSnapshot.generation else {
                throw ConflictComparisonWorkflowError.staleGeneration(
                    expected: expectedSnapshot.generation,
                    actual: request.snapshot.generation
                )
            }
        }
        var work = ConflictComparisonWorkBudget(limits: request.limits)
        let validated = try validateSnapshot(
            request.snapshot,
            limits: request.limits,
            work: &work
        )
        try validateOptions(request.options, limits: request.limits, work: &work)
        let twoWayAtomicBytes: Int?
        if validated.mapping.topology == .twoWay {
            twoWayAtomicBytes = try validateTwoWayTransformBounds(
                validated,
                options: request.options.twoWay,
                work: &work
            )
        } else {
            twoWayAtomicBytes = nil
        }
        guard request.snapshot.capabilities.contains(.compare) else {
            throw ConflictComparisonWorkflowError.missingCapability(.compare)
        }
        let snapshotCAS = try snapshotCAS(
            request.snapshot,
            validated: validated,
            work: &work
        )
        try Task.checkCancellation()

        let navigation: ConflictNavigationIndex
        do {
            navigation = try ConflictNavigationIndex(
                parseResult: request.snapshot.parseResult,
                generation: request.snapshot.generation
            )
        } catch let error as ConflictNavigationError {
            throw ConflictComparisonWorkflowError.conflictNavigation(error)
        }
        try Task.checkCancellation()

        let atomicBytes: Int =
            switch validated.mapping.topology {
            case .twoWay:
                twoWayAtomicBytes!
            case .diff3:
                validated.combinedByteCount
            }
        guard atomicBytes <= ConflictComparisonLimits.maximumAtomicComparisonInputBytes else {
            throw ConflictComparisonWorkflowError.atomicComparisonLimitExceeded(
                maximumBytes: ConflictComparisonLimits.maximumAtomicComparisonInputBytes
            )
        }
        let linePairCost: UInt64
        switch validated.mapping.topology {
        case .twoWay:
            let primaryCost = try checkedMultiply(
                UInt64(validated[.theirs].measurement.recordCount),
                UInt64(validated[.mine].measurement.recordCount)
            )
            linePairCost = try checkedMultiply(
                primaryCost,
                twoWayTransformIsActive(request.options.twoWay) ? 2 : 1
            )
        case .diff3:
            let baseLines = UInt64(validated[.base].measurement.recordCount)
            linePairCost = try checkedAdd(
                checkedMultiply(
                    baseLines,
                    UInt64(validated[.theirs].measurement.recordCount)
                ),
                checkedMultiply(
                    baseLines,
                    UInt64(validated[.mine].measurement.recordCount)
                )
            )
        }
        guard linePairCost <= ConflictComparisonLimits.maximumAtomicLinePairs else {
            throw ConflictComparisonWorkflowError.atomicComparisonWorkLimitExceeded(
                maximumLinePairs: ConflictComparisonLimits.maximumAtomicLinePairs
            )
        }
        try work.consume(linePairCost)
        try Task.checkCancellation()

        let comparison: ConflictComparisonResult
        switch validated.mapping.topology {
        case .twoWay:
            do {
                let rows = try LineDiff.compare(
                    left: validated[.theirs].snapshot.text,
                    right: validated[.mine].snapshot.text,
                    options: request.options.twoWay
                )
                comparison = .twoWay(ConflictComparisonTwoWayResult(rows: rows))
            } catch let error as LineDiffError {
                throw ConflictComparisonWorkflowError.lineDiff(error)
            }
        case .diff3:
            do {
                try validateDiff3Inputs(validated, options: request.options.diff3)
                let options = boundedDiff3Options(
                    request.options.diff3,
                    validated: validated,
                    limits: request.limits
                )
                let merge = try ThreeWayTextMerge.merge(
                    base: validated[.base].snapshot.text,
                    left: validated[.theirs].snapshot.text,
                    right: validated[.mine].snapshot.text,
                    options: options
                )
                comparison = .diff3(ConflictComparisonDiff3Result(merge: merge))
            } catch let error as ThreeWayTextMergeError {
                throw ConflictComparisonWorkflowError.threeWayMerge(error)
            } catch let error as LineDiffError {
                throw ConflictComparisonWorkflowError.lineDiff(error)
            }
        }
        try Task.checkCancellation()
        guard comparison.comparisonItemCount <= request.limits.maximumComparisonItems else {
            throw ConflictComparisonWorkflowError.tooManyComparisonItems(
                maximum: request.limits.maximumComparisonItems
            )
        }
        let totalItems = try checkedAdd(
            checkedAdd(validated.totalRecordCount, navigation.count),
            comparison.comparisonItemCount
        )
        guard totalItems <= request.limits.maximumTotalItems else {
            throw ConflictComparisonWorkflowError.tooManyItems(
                maximum: request.limits.maximumTotalItems
            )
        }
        try work.consume(UInt64(comparison.comparisonItemCount))
        try work.consume(UInt64(totalItems))
        let retainedBytes = try retainedByteEstimate(
            validated: validated,
            comparison: comparison,
            conflictCount: navigation.count,
            work: &work
        )
        guard retainedBytes <= request.limits.maximumRetainedBytes else {
            throw ConflictComparisonWorkflowError.retainedDataTooLarge(
                maximumBytes: request.limits.maximumRetainedBytes
            )
        }
        let roleReferences = validated.roles.map {
            ConflictComparisonRoleReference($0.snapshot)
        }
        let planSHA256 = try planDigest(
            snapshotCAS: snapshotCAS,
            mapping: validated.mapping,
            roleReferences: roleReferences,
            navigation: navigation,
            comparison: comparison,
            work: &work
        )
        try Task.checkCancellation()
        let receipt = ConflictComparisonPlanningReceipt(
            snapshot: snapshotCAS.reference,
            topology: validated.mapping.topology,
            conflictCount: navigation.count,
            comparisonItemCount: comparison.comparisonItemCount,
            documentUTF8ByteCount: request.snapshot.documentSourceRevision.utf8ByteCount,
            roleUTF8ByteCount: validated.combinedByteCount,
            retainedByteEstimate: retainedBytes,
            estimatedWorkUnits: work.consumed,
            planSHA256: planSHA256
        )
        return ConflictComparisonPlan(
            snapshotCAS: snapshotCAS,
            documentSourceRevision: request.snapshot.documentSourceRevision,
            isReadOnly: request.snapshot.isReadOnly,
            capabilities: request.snapshot.capabilities,
            mapping: validated.mapping,
            roleReferences: roleReferences,
            comparison: comparison,
            navigation: navigation,
            receipt: receipt,
            limits: request.limits
        )
    }

    private static func validate(
        _ limits: ConflictComparisonLimits
    ) throws {
        let valid =
            (0...ConflictComparisonLimits.hardMaximumDocumentBytes)
            .contains(limits.maximumDocumentBytes)
            && (0...ConflictComparisonLimits.hardMaximumRoleBytes)
                .contains(limits.maximumRoleBytes)
            && (0...ConflictComparisonLimits.hardMaximumCombinedRoleBytes)
                .contains(limits.maximumCombinedRoleBytes)
            && limits.maximumCombinedRoleBytes >= limits.maximumRoleBytes
            && (1...ConflictComparisonLimits.hardMaximumSourceIdentityUTF8Bytes)
                .contains(limits.maximumSourceIdentityUTF8Bytes)
            && (0...ConflictComparisonLimits.hardMaximumMarkerLabelUTF8Bytes)
                .contains(limits.maximumMarkerLabelUTF8Bytes)
            && (0...ConflictComparisonLimits.hardMaximumOptionItems)
                .contains(limits.maximumOptionItems)
            && (0...ConflictComparisonLimits.hardMaximumOptionStringUTF8Bytes)
                .contains(limits.maximumOptionStringUTF8Bytes)
            && (0...ConflictComparisonLimits.hardMaximumTotalOptionUTF8Bytes)
                .contains(limits.maximumTotalOptionUTF8Bytes)
            && limits.maximumTotalOptionUTF8Bytes >= limits.maximumOptionStringUTF8Bytes
            && (1...ConflictComparisonLimits.hardMaximumConflictCount)
                .contains(limits.maximumConflictCount)
            && (1...ConflictComparisonLimits.hardMaximumComparisonItems)
                .contains(limits.maximumComparisonItems)
            && (1...ConflictComparisonLimits.hardMaximumTotalItems)
                .contains(limits.maximumTotalItems)
            && limits.maximumTotalItems >= limits.maximumComparisonItems
            && (1...ConflictComparisonLimits.hardMaximumRetainedBytes)
                .contains(limits.maximumRetainedBytes)
            && limits.maximumWorkUnits > 0
            && limits.maximumWorkUnits <= ConflictComparisonLimits.hardMaximumWorkUnits
            && (1...ConflictComparisonLimits.hardMaximumCancellationCheckInterval)
                .contains(limits.cancellationCheckInterval)
        guard valid else {
            if !(0...ConflictComparisonLimits.hardMaximumDocumentBytes)
                .contains(limits.maximumDocumentBytes)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.documentBytes)
            }
            if !(0...ConflictComparisonLimits.hardMaximumRoleBytes)
                .contains(limits.maximumRoleBytes)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.roleBytes)
            }
            if !(0...ConflictComparisonLimits.hardMaximumCombinedRoleBytes)
                .contains(limits.maximumCombinedRoleBytes)
                || limits.maximumCombinedRoleBytes < limits.maximumRoleBytes
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.combinedRoleBytes)
            }
            if !(1...ConflictComparisonLimits.hardMaximumSourceIdentityUTF8Bytes)
                .contains(limits.maximumSourceIdentityUTF8Bytes)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.sourceIdentityUTF8Bytes)
            }
            if !(0...ConflictComparisonLimits.hardMaximumMarkerLabelUTF8Bytes)
                .contains(limits.maximumMarkerLabelUTF8Bytes)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.markerLabelUTF8Bytes)
            }
            if !(0...ConflictComparisonLimits.hardMaximumOptionItems)
                .contains(limits.maximumOptionItems)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.optionItems)
            }
            if !(0...ConflictComparisonLimits.hardMaximumOptionStringUTF8Bytes)
                .contains(limits.maximumOptionStringUTF8Bytes)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.optionStringUTF8Bytes)
            }
            if !(0...ConflictComparisonLimits.hardMaximumTotalOptionUTF8Bytes)
                .contains(limits.maximumTotalOptionUTF8Bytes)
                || limits.maximumTotalOptionUTF8Bytes < limits.maximumOptionStringUTF8Bytes
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.totalOptionUTF8Bytes)
            }
            if !(1...ConflictComparisonLimits.hardMaximumConflictCount)
                .contains(limits.maximumConflictCount)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.conflictCount)
            }
            if !(1...ConflictComparisonLimits.hardMaximumComparisonItems)
                .contains(limits.maximumComparisonItems)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.comparisonItems)
            }
            if !(1...ConflictComparisonLimits.hardMaximumTotalItems)
                .contains(limits.maximumTotalItems)
                || limits.maximumTotalItems < limits.maximumComparisonItems
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.totalItems)
            }
            if !(1...ConflictComparisonLimits.hardMaximumRetainedBytes)
                .contains(limits.maximumRetainedBytes)
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.retainedBytes)
            }
            if limits.maximumWorkUnits == 0
                || limits.maximumWorkUnits > ConflictComparisonLimits.hardMaximumWorkUnits
            {
                throw ConflictComparisonWorkflowError.invalidLimit(.workUnits)
            }
            throw ConflictComparisonWorkflowError.invalidLimit(.cancellationCheckInterval)
        }
    }

    private static func validateSnapshot(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot,
        limits: ConflictComparisonLimits,
        work: inout ConflictComparisonWorkBudget
    ) throws -> ConflictComparisonValidatedSnapshot {
        try work.checkCancellation()
        guard snapshot.capabilities.rawValue & ~ConflictComparisonCapability.all.rawValue == 0 else {
            throw ConflictComparisonWorkflowError.invalidCapabilities(snapshot.capabilities.rawValue)
        }
        try validate(
            snapshot.documentSourceRevision,
            role: nil,
            limits: limits,
            work: &work
        )
        guard snapshot.parseResultSourceRevision == snapshot.documentSourceRevision else {
            throw ConflictComparisonWorkflowError.parseResultSourceRevisionMismatch
        }
        var revisionsByKey = [
            ConflictComparisonSourceRevisionKey(snapshot.documentSourceRevision):
                snapshot.documentSourceRevision
        ]
        guard snapshot.documentSourceRevision.utf8ByteCount <= limits.maximumDocumentBytes else {
            throw ConflictComparisonWorkflowError.documentTooLarge(
                maximumBytes: limits.maximumDocumentBytes
            )
        }
        guard snapshot.parseResult.conflicts.count <= limits.maximumConflictCount else {
            throw ConflictComparisonWorkflowError.tooManyConflicts(
                maximum: limits.maximumConflictCount
            )
        }
        guard !snapshot.parseResult.conflicts.isEmpty else {
            throw ConflictComparisonWorkflowError.noConflicts
        }
        try work.consume(UInt64(snapshot.parseResult.conflicts.count))
        let mapping: ConflictComparisonRoleMapping =
            snapshot.parseResult.isThreeWay ? .diff3 : .twoWay
        let expectedRoles = Set(mapping.orderedRoles)
        var byRole: [ConflictComparisonRole: ConflictComparisonValidatedRole] = [:]
        byRole.reserveCapacity(expectedRoles.count)
        var combinedBytes = 0
        var totalRecords = 0
        var markerLabelBytes = 0
        var sourceIdentityBytes = snapshot.documentSourceRevision.identity.value.utf8.count

        for roleSnapshot in snapshot.roleSnapshots {
            try work.checkCancellation()
            guard expectedRoles.contains(roleSnapshot.role) else {
                throw ConflictComparisonWorkflowError.unexpectedRole(roleSnapshot.role)
            }
            guard byRole[roleSnapshot.role] == nil else {
                throw ConflictComparisonWorkflowError.duplicateRole(roleSnapshot.role)
            }
            try validate(
                roleSnapshot.sourceRevision,
                role: roleSnapshot.role,
                limits: limits,
                work: &work
            )
            sourceIdentityBytes = try checkedAdd(
                sourceIdentityBytes,
                roleSnapshot.sourceRevision.identity.value.utf8.count
            )
            let revisionKey = ConflictComparisonSourceRevisionKey(
                roleSnapshot.sourceRevision
            )
            if let existing = revisionsByKey[revisionKey],
                existing != roleSnapshot.sourceRevision
            {
                throw ConflictComparisonWorkflowError.conflictingSourceRevision
            }
            revisionsByKey[revisionKey] = roleSnapshot.sourceRevision
            let measurement = try measure(
                roleSnapshot.text,
                role: roleSnapshot.role,
                limits: limits,
                work: &work
            )
            guard measurement.byteCount == roleSnapshot.sourceRevision.utf8ByteCount else {
                throw ConflictComparisonWorkflowError.roleRevisionByteCountMismatch(
                    role: roleSnapshot.role,
                    expected: roleSnapshot.sourceRevision.utf8ByteCount,
                    actual: measurement.byteCount
                )
            }
            guard measurement.sha256 == roleSnapshot.sourceRevision.contentSHA256 else {
                throw ConflictComparisonWorkflowError.roleRevisionDigestMismatch(roleSnapshot.role)
            }
            combinedBytes = try checkedAdd(combinedBytes, measurement.byteCount)
            guard combinedBytes <= limits.maximumCombinedRoleBytes else {
                throw ConflictComparisonWorkflowError.combinedRolesTooLarge(
                    maximumBytes: limits.maximumCombinedRoleBytes
                )
            }
            totalRecords = try checkedAdd(totalRecords, measurement.recordCount)
            byRole[roleSnapshot.role] = ConflictComparisonValidatedRole(
                snapshot: roleSnapshot,
                measurement: measurement
            )
        }
        for role in mapping.orderedRoles where byRole[role] == nil {
            throw ConflictComparisonWorkflowError.missingRole(role)
        }
        let orderedRoles = mapping.orderedRoles.map { byRole[$0]! }
        for role in orderedRoles {
            let parsedText: String
            switch role.snapshot.role {
            case .base:
                guard let baseText = snapshot.parseResult.baseText else {
                    throw ConflictComparisonWorkflowError.missingRole(.base)
                }
                parsedText = baseText
            case .theirs:
                parsedText = snapshot.parseResult.incomingText
            case .mine:
                parsedText = snapshot.parseResult.currentText
            }
            guard
                try stringsExactlyEqual(
                    role.snapshot.text,
                    parsedText,
                    work: &work
                )
            else {
                throw ConflictComparisonWorkflowError.parsedRoleTextMismatch(role.snapshot.role)
            }
        }
        for conflict in snapshot.parseResult.conflicts {
            try work.consume()
            markerLabelBytes = try checkedAdd(
                markerLabelBytes,
                try measureLabel(conflict.currentLabel, limits: limits, work: &work)
            )
            markerLabelBytes = try checkedAdd(
                markerLabelBytes,
                try measureLabel(conflict.baseLabel, limits: limits, work: &work)
            )
            markerLabelBytes = try checkedAdd(
                markerLabelBytes,
                try measureLabel(conflict.incomingLabel, limits: limits, work: &work)
            )
        }
        let preflightRetainedByteCount = try validatePreflightBounds(
            mapping: mapping,
            combinedByteCount: combinedBytes,
            totalRecordCount: totalRecords,
            conflictCount: snapshot.parseResult.conflicts.count,
            markerLabelByteCount: markerLabelBytes,
            sourceIdentityByteCount: sourceIdentityBytes,
            limits: limits
        )
        return ConflictComparisonValidatedSnapshot(
            mapping: mapping,
            roles: orderedRoles,
            combinedByteCount: combinedBytes,
            totalRecordCount: totalRecords,
            markerLabelByteCount: markerLabelBytes,
            sourceIdentityByteCount: sourceIdentityBytes,
            preflightRetainedByteCount: preflightRetainedByteCount
        )
    }

    /// Reject requests whose minimum retained plan cannot fit before comparison APIs materialize it.
    private static func validatePreflightBounds(
        mapping: ConflictComparisonRoleMapping,
        combinedByteCount: Int,
        totalRecordCount: Int,
        conflictCount: Int,
        markerLabelByteCount: Int,
        sourceIdentityByteCount: Int,
        limits: ConflictComparisonLimits
    ) throws -> Int {
        let maximumComparisonItems =
            switch mapping.topology {
            case .twoWay: totalRecordCount
            case .diff3: try checkedAdd(totalRecordCount, 1)
            }
        guard maximumComparisonItems <= limits.maximumComparisonItems else {
            throw ConflictComparisonWorkflowError.tooManyComparisonItems(
                maximum: limits.maximumComparisonItems
            )
        }
        let minimumTotalItems = try checkedAdd(
            checkedAdd(totalRecordCount, conflictCount),
            maximumComparisonItems
        )
        guard minimumTotalItems <= limits.maximumTotalItems else {
            throw ConflictComparisonWorkflowError.tooManyItems(
                maximum: limits.maximumTotalItems
            )
        }
        var maximumRetainedBytes = try checkedAdd(
            try checkedMultiply(mapping.orderedRoles.count + 1, 256),
            try checkedMultiply(conflictCount, 256)
        )
        maximumRetainedBytes = try checkedAdd(maximumRetainedBytes, combinedByteCount)
        maximumRetainedBytes = try checkedAdd(maximumRetainedBytes, markerLabelByteCount)
        maximumRetainedBytes = try checkedAdd(maximumRetainedBytes, sourceIdentityByteCount)
        maximumRetainedBytes = try checkedAdd(
            maximumRetainedBytes,
            try checkedMultiply(maximumComparisonItems, 192)
        )
        if mapping.topology == .diff3 {
            maximumRetainedBytes = try checkedAdd(maximumRetainedBytes, combinedByteCount)
            maximumRetainedBytes = try checkedAdd(
                maximumRetainedBytes,
                try checkedMultiply(totalRecordCount, 128)
            )
            maximumRetainedBytes = try checkedAdd(
                maximumRetainedBytes,
                try checkedMultiply(maximumComparisonItems, 256)
            )
        }
        guard maximumRetainedBytes <= limits.maximumRetainedBytes else {
            throw ConflictComparisonWorkflowError.retainedDataTooLarge(
                maximumBytes: limits.maximumRetainedBytes
            )
        }
        return maximumRetainedBytes
    }

    private static func validate(
        _ revision: ConflictComparisonSourceRevision,
        role: ConflictComparisonRole?,
        limits: ConflictComparisonLimits,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        let identityBytes = revision.identity.value.utf8.count
        try work.consume(UInt64(identityBytes))
        guard !revision.identity.value.isEmpty,
            identityBytes <= limits.maximumSourceIdentityUTF8Bytes,
            !revision.identity.value.utf8.contains(0)
        else {
            throw ConflictComparisonWorkflowError.invalidSourceIdentity(role)
        }
        guard revision.utf8ByteCount >= 0,
            revision.contentSHA256.count == SHA256.byteCount
        else {
            throw ConflictComparisonWorkflowError.invalidSourceRevision(role)
        }
    }

    private static func measure(
        _ text: String,
        role: ConflictComparisonRole,
        limits: ConflictComparisonLimits,
        work: inout ConflictComparisonWorkBudget
    ) throws -> ConflictComparisonTextMeasurement {
        var sha256 = SHA256()
        var chunk = Data()
        chunk.reserveCapacity(limits.cancellationCheckInterval)
        var byteCount = 0
        var recordCount = 0
        var lineTerminatorByteCount = 0
        var pendingCarriageReturn = false
        var lastWasTerminator = false
        for byte in text.utf8 {
            guard byteCount < limits.maximumRoleBytes else {
                throw ConflictComparisonWorkflowError.roleTooLarge(
                    role: role,
                    maximumBytes: limits.maximumRoleBytes
                )
            }
            byteCount += 1
            chunk.append(byte)
            if pendingCarriageReturn {
                if byte == 0x0A {
                    recordCount = try checkedAdd(recordCount, 1)
                    lineTerminatorByteCount = try checkedAdd(lineTerminatorByteCount, 2)
                    pendingCarriageReturn = false
                    lastWasTerminator = true
                    if chunk.count >= limits.cancellationCheckInterval {
                        try update(&sha256, with: &chunk, work: &work)
                    }
                    continue
                }
                recordCount = try checkedAdd(recordCount, 1)
                lineTerminatorByteCount = try checkedAdd(lineTerminatorByteCount, 1)
                pendingCarriageReturn = false
            }
            if byte == 0x0D {
                pendingCarriageReturn = true
                lastWasTerminator = true
            } else if byte == 0x0A {
                recordCount = try checkedAdd(recordCount, 1)
                lineTerminatorByteCount = try checkedAdd(lineTerminatorByteCount, 1)
                lastWasTerminator = true
            } else {
                lastWasTerminator = false
            }
            if chunk.count >= limits.cancellationCheckInterval {
                try update(&sha256, with: &chunk, work: &work)
            }
        }
        if !chunk.isEmpty { try update(&sha256, with: &chunk, work: &work) }
        if pendingCarriageReturn {
            recordCount = try checkedAdd(recordCount, 1)
            lineTerminatorByteCount = try checkedAdd(lineTerminatorByteCount, 1)
        } else if byteCount > 0, !lastWasTerminator {
            recordCount = try checkedAdd(recordCount, 1)
        }
        let normalizedLineEndingByteCount = try checkedAdd(
            byteCount - lineTerminatorByteCount,
            recordCount
        )
        return ConflictComparisonTextMeasurement(
            byteCount: byteCount,
            recordCount: recordCount,
            normalizedLineEndingByteCount: normalizedLineEndingByteCount,
            sha256: Array(sha256.finalize())
        )
    }

    private static func update(
        _ sha256: inout SHA256,
        with chunk: inout Data,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        let byteCount = chunk.count
        sha256.update(data: chunk)
        chunk.removeAll(keepingCapacity: true)
        try work.consume(UInt64(byteCount))
    }

    private static func measureLabel(
        _ label: String?,
        limits: ConflictComparisonLimits,
        work: inout ConflictComparisonWorkBudget
    ) throws -> Int {
        guard let label else { return 0 }
        let byteCount = label.utf8.count
        guard byteCount <= limits.maximumMarkerLabelUTF8Bytes else {
            throw ConflictComparisonWorkflowError.markerLabelTooLarge(
                maximumBytes: limits.maximumMarkerLabelUTF8Bytes
            )
        }
        try work.consume(UInt64(byteCount))
        return byteCount
    }

    private static func validateOptions(
        _ options: ConflictComparisonOptions,
        limits: ConflictComparisonLimits,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        let itemCount = try checkedAdd(
            checkedAdd(options.twoWay.lineFilters.count, options.twoWay.substitutions.count),
            2
        )
        guard itemCount <= limits.maximumOptionItems else {
            throw ConflictComparisonWorkflowError.tooManyOptionItems(
                maximum: limits.maximumOptionItems
            )
        }
        var totalBytes = 0
        for filter in options.twoWay.lineFilters {
            try measureOptionString(
                filter.pattern,
                limits: limits,
                totalBytes: &totalBytes,
                work: &work
            )
        }
        for substitution in options.twoWay.substitutions {
            try measureOptionString(
                substitution.pattern,
                limits: limits,
                totalBytes: &totalBytes,
                work: &work
            )
            try measureOptionString(
                substitution.replacement,
                limits: limits,
                totalBytes: &totalBytes,
                work: &work
            )
            if options.twoWay.substitutionsEnabled, !substitution.pattern.isEmpty {
                guard !substitution.replacement.contains("$"),
                    !substitution.replacement.contains("\\"),
                    !substitution.replacement.contains("\n"),
                    !substitution.replacement.contains("\r")
                else {
                    throw ConflictComparisonWorkflowError.unsafeSubstitutionReplacement
                }
            }
        }
        try work.consume(UInt64(itemCount))
    }

    private static func validateDiff3Inputs(
        _ validated: ConflictComparisonValidatedSnapshot,
        options: ThreeWayTextMergeOptions
    ) throws {
        for role in validated.roles {
            let source: ThreeWayTextMergeSource =
                switch role.snapshot.role {
                case .base: .base
                case .theirs: .left
                case .mine: .right
                }
            guard role.measurement.byteCount <= options.maximumInputBytes else {
                throw ConflictComparisonWorkflowError.threeWayMerge(
                    .inputTooLarge(source: source, maximumBytes: options.maximumInputBytes)
                )
            }
            guard
                role.measurement.byteCount
                    <= ConflictComparisonLimits.maximumNativeComparisonInputBytes
            else {
                throw ConflictComparisonWorkflowError.threeWayMerge(
                    .inputTooLarge(
                        source: source,
                        maximumBytes: ConflictComparisonLimits.maximumNativeComparisonInputBytes
                    )
                )
            }
            guard
                role.measurement.normalizedLineEndingByteCount
                    <= ConflictComparisonLimits.maximumNativeComparisonInputBytes
            else {
                throw ConflictComparisonWorkflowError.lineDiff(
                    .inputTooLarge(
                        maximumBytes: ConflictComparisonLimits.maximumNativeComparisonInputBytes
                    )
                )
            }
            guard role.measurement.recordCount <= options.maximumInputLines else {
                throw ConflictComparisonWorkflowError.threeWayMerge(
                    .tooManyLines(source: source, maximumLines: options.maximumInputLines)
                )
            }
            guard
                role.measurement.recordCount
                    <= ConflictComparisonLimits.maximumAtomicComparisonInputLines
            else {
                throw ConflictComparisonWorkflowError.threeWayMerge(
                    .tooManyLines(
                        source: source,
                        maximumLines: ConflictComparisonLimits.maximumAtomicComparisonInputLines
                    )
                )
            }
        }
    }

    private static func validateTwoWayTransformBounds(
        _ validated: ConflictComparisonValidatedSnapshot,
        options: LineDiffOptions,
        work: inout ConflictComparisonWorkBudget
    ) throws -> Int {
        let activeFilters = options.lineFiltersEnabled ? options.lineFilters.count : 0
        let activeSubstitutions =
            options.substitutionsEnabled
            ? options.substitutions.lazy.filter { !$0.pattern.isEmpty }.count
            : 0
        let transformPrefixesContent =
            options.ignoreComments && options.commentSyntax != nil
            || activeFilters > 0
            || activeSubstitutions > 0
        let filterWork = try checkedMultiply(
            UInt64(activeFilters),
            UInt64(validated.combinedByteCount)
        )
        var substitutionWork: UInt64 = 0
        var maximumTransformedBytes = 0
        for role in [ConflictComparisonRole.theirs, .mine] {
            guard
                validated[role].measurement.recordCount
                    <= ConflictComparisonLimits.maximumAtomicComparisonInputLines
            else {
                throw ConflictComparisonWorkflowError.lineDiff(
                    .tooManyLines(
                        maximumLines: ConflictComparisonLimits.maximumAtomicComparisonInputLines
                    )
                )
            }
            let primaryByteCount =
                options.ignoreLineEndings
                ? validated[role].measurement.normalizedLineEndingByteCount
                : validated[role].measurement.byteCount
            guard
                primaryByteCount
                    <= ConflictComparisonLimits.maximumNativeComparisonInputBytes
            else {
                throw ConflictComparisonWorkflowError.lineDiff(
                    .inputTooLarge(
                        maximumBytes: ConflictComparisonLimits.maximumNativeComparisonInputBytes
                    )
                )
            }
            let markerExpansionBytes =
                transformPrefixesContent
                ? try checkedMultiply(validated[role].measurement.recordCount, 64)
                : 0
            var transformedByteCount = try checkedAdd(
                validated[role].measurement.byteCount,
                markerExpansionBytes
            )
            if activeSubstitutions > 0 {
                for substitution in options.substitutions
                where options.substitutionsEnabled && !substitution.pattern.isEmpty {
                    let outputBytes = min(
                        try maximumSubstitutionOutputByteCount(
                            inputBytes: transformedByteCount,
                            replacementBytes: substitution.replacement.utf8.count
                        ),
                        ConflictComparisonLimits.maximumNativeComparisonInputBytes
                    )
                    substitutionWork = try checkedAdd(
                        substitutionWork,
                        try checkedMultiply(
                            UInt64(transformedByteCount),
                            UInt64(outputBytes)
                        )
                    )
                    transformedByteCount = outputBytes
                }
            }
            if transformPrefixesContent {
                transformedByteCount = try checkedAdd(
                    transformedByteCount,
                    try checkedMultiply(validated[role].measurement.recordCount, 2)
                )
            }
            if options.ignoreLineEndings {
                transformedByteCount = try checkedAdd(
                    transformedByteCount,
                    validated[role].measurement.recordCount
                )
            }
            guard
                transformedByteCount
                    <= ConflictComparisonLimits.maximumNativeComparisonInputBytes
            else {
                throw ConflictComparisonWorkflowError.lineDiff(
                    .inputTooLarge(
                        maximumBytes: ConflictComparisonLimits.maximumNativeComparisonInputBytes
                    )
                )
            }
            maximumTransformedBytes = try checkedAdd(
                maximumTransformedBytes,
                transformedByteCount
            )
        }
        try work.consume(try checkedAdd(filterWork, substitutionWork))
        if twoWayTransformIsActive(options) {
            for role in [ConflictComparisonRole.theirs, .mine]
            where validated[role].snapshot.text.contains("!MACMERGE-FILTERED-") {
                throw ConflictComparisonWorkflowError.reservedTransformMarkerCollision
            }
        }
        return maximumTransformedBytes
    }

    private static func maximumSubstitutionOutputByteCount(
        inputBytes: Int,
        replacementBytes: Int
    ) throws -> Int {
        try checkedAdd(
            inputBytes,
            checkedMultiply(try checkedAdd(inputBytes, 1), replacementBytes)
        )
    }

    private static func twoWayTransformIsActive(_ options: LineDiffOptions) -> Bool {
        options.ignoreBlankLines
            || options.ignoreComments && options.commentSyntax != nil
            || options.lineFiltersEnabled && !options.lineFilters.isEmpty
            || options.substitutionsEnabled
                && options.substitutions.contains { !$0.pattern.isEmpty }
    }

    private static func boundedDiff3Options(
        _ options: ThreeWayTextMergeOptions,
        validated: ConflictComparisonValidatedSnapshot,
        limits: ConflictComparisonLimits
    ) -> ThreeWayTextMergeOptions {
        let maximumOutputBytes =
            limits.maximumRetainedBytes
            - validated.preflightRetainedByteCount
        return ThreeWayTextMergeOptions(
            diffAlgorithm: options.diffAlgorithm,
            maximumInputBytes: min(
                options.maximumInputBytes,
                ConflictComparisonLimits.maximumNativeComparisonInputBytes
            ),
            maximumInputLines: min(
                options.maximumInputLines,
                ConflictComparisonLimits.maximumAtomicComparisonInputLines
            ),
            maximumOutputBytes: min(options.maximumOutputBytes, maximumOutputBytes),
            maximumOutputLines: min(options.maximumOutputLines, limits.maximumComparisonItems),
            maximumRegions: min(options.maximumRegions, limits.maximumComparisonItems)
        )
    }

    private static func measureOptionString(
        _ value: String,
        limits: ConflictComparisonLimits,
        totalBytes: inout Int,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        let byteCount = value.utf8.count
        guard byteCount <= limits.maximumOptionStringUTF8Bytes else {
            throw ConflictComparisonWorkflowError.optionStringTooLarge(
                maximumBytes: limits.maximumOptionStringUTF8Bytes
            )
        }
        totalBytes = try checkedAdd(totalBytes, byteCount)
        guard totalBytes <= limits.maximumTotalOptionUTF8Bytes else {
            throw ConflictComparisonWorkflowError.optionsTooLarge(
                maximumBytes: limits.maximumTotalOptionUTF8Bytes
            )
        }
        try work.consume(UInt64(byteCount))
    }

    private static func stringsExactlyEqual(
        _ left: String,
        _ right: String,
        work: inout ConflictComparisonWorkBudget
    ) throws -> Bool {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        var compared = 0
        while true {
            let leftByte = leftIterator.next()
            let rightByte = rightIterator.next()
            guard leftByte == rightByte else { return false }
            guard leftByte != nil else {
                if compared > 0 { try work.consume(UInt64(compared)) }
                return true
            }
            compared += 1
            if compared >= work.cancellationCheckInterval {
                try work.consume(UInt64(compared))
                compared = 0
            }
        }
    }

    private static func snapshotCAS(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot,
        validated: ConflictComparisonValidatedSnapshot,
        work: inout ConflictComparisonWorkBudget
    ) throws -> ConflictComparisonSnapshotCAS {
        var digest = ConflictComparisonDigest(domain: "ConflictComparisonSnapshot.v1")
        digest.append(snapshot.identity.rawValue)
        digest.append(snapshot.generation)
        append(snapshot.documentSourceRevision, to: &digest)
        append(snapshot.parseResultSourceRevision, to: &digest)
        digest.append(snapshot.isReadOnly)
        digest.append(snapshot.capabilities.rawValue)
        digest.append(validated.mapping.topology.rawValue)
        for role in validated.roles {
            try work.consume()
            digest.append(role.snapshot.role.rawValue)
            append(role.snapshot.sourceRevision, to: &digest)
        }
        for conflict in snapshot.parseResult.conflicts {
            try append(conflict, to: &digest, work: &work)
        }
        return ConflictComparisonSnapshotCAS(
            reference: ConflictComparisonSnapshotReference(snapshot),
            stateSHA256: digest.finalize()
        )
    }

    private static func retainedByteEstimate(
        validated: ConflictComparisonValidatedSnapshot,
        comparison: ConflictComparisonResult,
        conflictCount: Int,
        work: inout ConflictComparisonWorkBudget
    ) throws -> Int {
        var result = validated.combinedByteCount
        result = try checkedAdd(result, try checkedMultiply(validated.roles.count + 1, 256))
        result = try checkedAdd(result, try checkedMultiply(conflictCount, 256))
        result = try checkedAdd(result, validated.markerLabelByteCount)
        result = try checkedAdd(result, validated.sourceIdentityByteCount)
        result = try checkedAdd(
            result,
            try checkedMultiply(comparison.comparisonItemCount, 192)
        )
        switch comparison {
        case .twoWay:
            break
        case .diff3(let resultValue):
            result = try checkedAdd(result, validated.combinedByteCount)
            if let mergedText = resultValue.merge.mergedText {
                result = try checkedAdd(result, mergedText.utf8.count)
            }
            let lineItems = try checkedAdd(
                checkedAdd(
                    resultValue.merge.base.lines.count,
                    resultValue.merge.left.lines.count
                ),
                resultValue.merge.right.lines.count
            )
            result = try checkedAdd(result, try checkedMultiply(lineItems, 64))
            var retainedRegionLines = 0
            for region in resultValue.merge.regions {
                try work.consume()
                retainedRegionLines = try checkedAdd(
                    retainedRegionLines,
                    try checkedAdd(
                        checkedAdd(region.baseLines.count, region.leftLines.count),
                        region.rightLines.count
                    )
                )
            }
            result = try checkedAdd(result, try checkedMultiply(retainedRegionLines, 64))
            result = try checkedAdd(
                result,
                try checkedMultiply(resultValue.merge.conflicts.count, 192)
            )
            if let mergedLines = resultValue.merge.mergedLines {
                result = try checkedAdd(result, try checkedMultiply(mergedLines.count, 64))
            }
        }
        return result
    }

    private static func planDigest(
        snapshotCAS: ConflictComparisonSnapshotCAS,
        mapping: ConflictComparisonRoleMapping,
        roleReferences: [ConflictComparisonRoleReference],
        navigation: ConflictNavigationIndex,
        comparison: ConflictComparisonResult,
        work: inout ConflictComparisonWorkBudget
    ) throws -> [UInt8] {
        var digest = ConflictComparisonDigest(domain: "ConflictComparisonPlan.v1")
        digest.append(snapshotCAS.stateSHA256)
        digest.append(mapping.topology.rawValue)
        for reference in roleReferences {
            try work.consume()
            digest.append(reference.role.rawValue)
            append(reference.sourceRevision, to: &digest)
        }
        for target in navigation.conflicts {
            try append(target.id, to: &digest, work: &work)
        }
        switch comparison {
        case .twoWay(let result):
            digest.append("twoWay")
            for row in result.rows {
                try work.consume()
                append(row, to: &digest)
            }
        case .diff3(let result):
            digest.append("diff3")
            for region in result.merge.regions {
                try work.consume()
                try append(region, to: &digest, work: &work)
            }
        }
        return digest.finalize()
    }

    private static func validatedTarget(
        _ id: ConflictNavigationTarget.ID?,
        in navigation: ConflictNavigationIndex
    ) throws -> ConflictNavigationTarget? {
        guard let id else { return nil }
        return try requiredValidatedTarget(id, in: navigation)
    }

    private static func requiredValidatedTarget(
        _ id: ConflictNavigationTarget.ID,
        in navigation: ConflictNavigationIndex
    ) throws -> ConflictNavigationTarget {
        guard id.generation == navigation.generation else {
            throw ConflictComparisonWorkflowError.staleConflictGeneration(
                expected: navigation.generation,
                actual: id.generation
            )
        }
        guard let target = navigation.conflict(at: id.ordinal), target.id == id else {
            throw ConflictComparisonWorkflowError.staleConflictIdentity(id)
        }
        return target
    }

    private static func planCapability(
        _ plan: ConflictComparisonPlan,
        contains capability: ConflictComparisonCapability
    ) -> Bool {
        plan.capabilities.contains(capability)
    }

    private static func planIsReadOnly(_ plan: ConflictComparisonPlan) -> Bool {
        plan.isReadOnly
    }

    private static func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
        let result = left.addingReportingOverflow(right)
        guard !result.overflow else { throw ConflictComparisonWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    private static func checkedAdd(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
        let result = left.addingReportingOverflow(right)
        guard !result.overflow else { throw ConflictComparisonWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    private static func checkedMultiply(_ left: Int, _ right: Int) throws -> Int {
        let result = left.multipliedReportingOverflow(by: right)
        guard !result.overflow else { throw ConflictComparisonWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    private static func checkedMultiply(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
        let result = left.multipliedReportingOverflow(by: right)
        guard !result.overflow else { throw ConflictComparisonWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    private static func append(
        _ revision: ConflictComparisonSourceRevision,
        to digest: inout ConflictComparisonDigest
    ) {
        digest.append(revision.identity.namespace)
        digest.append(revision.identity.value)
        digest.append(revision.revision)
        digest.append(revision.utf8ByteCount)
        digest.append(revision.contentSHA256)
    }

    private static func append(
        _ conflict: ConflictFileConflict,
        to digest: inout ConflictComparisonDigest,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        try work.consume()
        digest.append(conflict.sourceLineRange.lowerBound)
        digest.append(conflict.sourceLineRange.upperBound)
        digest.append(conflict.markerWidth)
        try digest.append(conflict.currentLabel, work: &work)
        try digest.append(conflict.baseLabel, work: &work)
        try digest.append(conflict.incomingLabel, work: &work)
        digest.append(conflict.hasCurrentContent)
        digest.append(conflict.hasBaseContent)
        digest.append(conflict.hasIncomingContent)
    }

    private static func append(
        _ id: ConflictNavigationTarget.ID,
        to digest: inout ConflictComparisonDigest,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        try work.consume()
        digest.append(id.generation)
        digest.append(id.ordinal)
        digest.append(id.sourceLineRange.lowerBound)
        digest.append(id.sourceLineRange.upperBound)
        digest.append(id.markerWidth)
        digest.append(id.topology.rawValue)
        try digest.append(id.currentLabel, work: &work)
        try digest.append(id.baseLabel, work: &work)
        try digest.append(id.incomingLabel, work: &work)
        digest.append(id.paneContributions.rawValue)
    }

    private static func append(
        _ id: ConflictNavigationTarget.ID?,
        to digest: inout ConflictComparisonDigest
    ) {
        guard let id else {
            digest.append(UInt8(0))
            return
        }
        digest.append(UInt8(1))
        append(id, to: &digest)
    }

    private static func append(
        _ id: ConflictNavigationTarget.ID,
        to digest: inout ConflictComparisonDigest
    ) {
        digest.append(id.generation)
        digest.append(id.ordinal)
        digest.append(id.sourceLineRange.lowerBound)
        digest.append(id.sourceLineRange.upperBound)
        digest.append(id.markerWidth)
        digest.append(id.topology.rawValue)
        digest.append(id.currentLabel)
        digest.append(id.baseLabel)
        digest.append(id.incomingLabel)
        digest.append(id.paneContributions.rawValue)
    }

    private static func append(
        _ state: ConflictComparisonSelectionState,
        to digest: inout ConflictComparisonDigest
    ) {
        digest.append(state.snapshot.identity.rawValue)
        digest.append(state.snapshot.generation)
        append(state.selectedConflictID, to: &digest)
        digest.append(state.cursorSourceLine)
    }

    private static func append(
        _ intent: ConflictComparisonSelectionIntent,
        to digest: inout ConflictComparisonDigest
    ) {
        switch intent {
        case .command(let command):
            digest.append("command")
            digest.append(command.rawValue)
        case .select(let id):
            digest.append("select")
            append(id, to: &digest)
        case .clear:
            digest.append("clear")
        }
    }

    private static func append(_ row: DiffRow, to digest: inout ConflictComparisonDigest) {
        switch row.kind {
        case .unchanged: digest.append("unchanged")
        case .modified: digest.append("modified")
        case .removed: digest.append("removed")
        case .added: digest.append("added")
        }
        digest.append(row.id.leftNumber)
        digest.append(row.id.rightNumber)
        digest.append(row.hasEqualSourceRecords)
    }

    private static func append(
        _ region: ThreeWayTextMergeRegion,
        to digest: inout ConflictComparisonDigest,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        digest.append(region.id)
        append(region.baseRange, to: &digest)
        append(region.leftRange, to: &digest)
        append(region.rightRange, to: &digest)
        switch region.resolution {
        case .unchanged: digest.append("unchanged")
        case .left: digest.append("left")
        case .right: digest.append("right")
        case .identical: digest.append("identical")
        case .conflict: digest.append("conflict")
        }
        try append(region.baseLines, to: &digest, work: &work)
        try append(region.leftLines, to: &digest, work: &work)
        try append(region.rightLines, to: &digest, work: &work)
    }

    private static func append(_ range: Range<Int>, to digest: inout ConflictComparisonDigest) {
        digest.append(range.lowerBound)
        digest.append(range.upperBound)
    }

    private static func append(
        _ lines: [ThreeWayTextMergeLine],
        to digest: inout ConflictComparisonDigest,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        digest.append(lines.count)
        for line in lines {
            try work.consume()
            digest.append(line.source.rawValue)
            digest.append(line.number)
            digest.append(line.lineEnding?.rawValue)
        }
    }
}

private struct ConflictComparisonTextMeasurement {
    let byteCount: Int
    let recordCount: Int
    let normalizedLineEndingByteCount: Int
    let sha256: [UInt8]
}

private struct ConflictComparisonSourceRevisionKey: Hashable {
    let identity: ConflictComparisonSourceIdentity
    let revision: UInt64

    init(_ revision: ConflictComparisonSourceRevision) {
        identity = revision.identity
        self.revision = revision.revision
    }
}

private struct ConflictComparisonValidatedRole {
    let snapshot: ConflictComparisonRoleSnapshot
    let measurement: ConflictComparisonTextMeasurement
}

private struct ConflictComparisonValidatedSnapshot {
    let mapping: ConflictComparisonRoleMapping
    let roles: [ConflictComparisonValidatedRole]
    let combinedByteCount: Int
    let totalRecordCount: Int
    let markerLabelByteCount: Int
    let sourceIdentityByteCount: Int
    let preflightRetainedByteCount: Int

    subscript(role: ConflictComparisonRole) -> ConflictComparisonValidatedRole {
        roles.first { $0.snapshot.role == role }!
    }
}

private struct ConflictComparisonWorkBudget {
    let maximum: UInt64
    let cancellationCheckInterval: Int
    private(set) var consumed: UInt64 = 0
    private var unitsSinceCheck: UInt64 = 0

    init(limits: ConflictComparisonLimits) {
        maximum = limits.maximumWorkUnits
        cancellationCheckInterval = limits.cancellationCheckInterval
    }

    mutating func consume(_ units: UInt64 = 1) throws {
        guard units <= maximum - consumed else {
            throw ConflictComparisonWorkflowError.workLimitExceeded(maximumUnits: maximum)
        }
        consumed += units
        let interval = UInt64(cancellationCheckInterval)
        unitsSinceCheck =
            units >= interval - unitsSinceCheck
            ? interval
            : unitsSinceCheck + units
        if unitsSinceCheck >= interval {
            try checkCancellation()
        }
    }

    mutating func checkCancellation() throws {
        unitsSinceCheck = 0
        try Task.checkCancellation()
    }
}

private struct ConflictComparisonDigest {
    private var sha256 = SHA256()

    init(domain: String) {
        append(domain)
    }

    mutating func append(_ value: Bool) {
        append(value ? UInt8(1) : UInt8(0))
    }

    mutating func append(_ value: UInt8) {
        appendBytes(Data([value]))
    }

    mutating func append(_ value: UInt16) {
        append(UInt64(value))
    }

    mutating func append(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { appendBytes(Data($0)) }
    }

    mutating func append(_ value: Int) {
        append(UInt64(bitPattern: Int64(value)))
    }

    mutating func append(_ value: Int?) {
        guard let value else {
            append(UInt8(0))
            return
        }
        append(UInt8(1))
        append(value)
    }

    mutating func append(_ value: UUID) {
        append(value.uuidString.lowercased())
    }

    mutating func append(_ value: String) {
        appendBytes(Data(value.utf8))
    }

    mutating func append(_ value: String?) {
        guard let value else {
            append(UInt8(0))
            return
        }
        append(UInt8(1))
        append(value)
    }

    mutating func append(
        _ value: String?,
        work: inout ConflictComparisonWorkBudget
    ) throws {
        guard let value else {
            append(UInt8(0))
            return
        }
        append(UInt8(1))
        var length = UInt64(value.utf8.count).bigEndian
        withUnsafeBytes(of: &length) { sha256.update(data: Data($0)) }
        var chunk = Data()
        chunk.reserveCapacity(work.cancellationCheckInterval)
        for byte in value.utf8 {
            chunk.append(byte)
            if chunk.count >= work.cancellationCheckInterval {
                try work.consume(UInt64(chunk.count))
                sha256.update(data: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            try work.consume(UInt64(chunk.count))
            sha256.update(data: chunk)
        }
    }

    mutating func append(_ value: [UInt8]) {
        appendBytes(Data(value))
    }

    mutating func finalize() -> [UInt8] {
        Array(sha256.finalize())
    }

    private mutating func appendBytes(_ data: Data) {
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { sha256.update(data: Data($0)) }
        sha256.update(data: data)
    }
}
