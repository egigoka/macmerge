import CryptoKit
import Foundation

/// UI-independent planning for opening selected folder-result file pairs as read-only text
/// comparisons. Planning performs no filesystem access, comparison materialization, publication,
/// window creation, or AppKit work.
public enum SelectedFilePairOpenWorkflow: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public enum Side: String, CaseIterable, Hashable, Sendable {
        case left
        case right

        fileprivate var navigationSide: ComparedFileNavigationSide {
            switch self {
            case .left: .left
            case .right: .right
            }
        }

        fileprivate var folderSide: FolderComparisonWorkflowSide {
            switch self {
            case .left: .left
            case .right: .right
            }
        }
    }

    public enum Intent: String, Hashable, Sendable {
        case readOnlyTextComparison
    }

    public enum FailurePolicy: String, Hashable, Sendable {
        /// Every selected row is represented in execution evidence. Comparisons are staged without
        /// publication, then the complete ordered batch is published once or not at all.
        case stageAllThenPublishAllOrNone
    }

    public struct PublicationTarget: Hashable, Sendable {
        public let identity: UUID
        /// Opaque, monotonically advancing CAS revision for the comparison-publication collection.
        public let revision: UInt64

        public init(identity: UUID, revision: UInt64) {
            self.identity = identity
            self.revision = revision
        }
    }

    public enum ExecutorFeature: String, CaseIterable, Hashable, Sendable {
        case stageReadOnlyTextComparison
        case publishAtomicComparisonBatch
        case reportEverySelectedItem
    }

    public struct ExecutorCapabilities: Hashable, Sendable {
        public let identity: UUID
        /// Opaque, monotonically advancing, never-reused capability revision.
        public let revision: UInt64
        public let features: Set<ExecutorFeature>

        public init(identity: UUID, revision: UInt64, features: Set<ExecutorFeature>) {
            self.identity = identity
            self.revision = revision
            self.features = features
        }
    }

    /// Explicit bridge between folder-workflow authority and navigation authority for one side.
    public struct AuthorityBinding: Hashable, Sendable {
        public let side: Side
        public let folderAuthorityIdentity: UUID
        public let folderAuthorityRevision: UInt64
        public let navigationAuthorityIdentity: ComparedFileNavigationAuthorityIdentity

        public init(
            side: Side,
            folderAuthorityIdentity: UUID,
            folderAuthorityRevision: UInt64,
            navigationAuthorityIdentity: ComparedFileNavigationAuthorityIdentity
        ) {
            self.side = side
            self.folderAuthorityIdentity = folderAuthorityIdentity
            self.folderAuthorityRevision = folderAuthorityRevision
            self.navigationAuthorityIdentity = navigationAuthorityIdentity
        }
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumSnapshotItems = 1_000_000
        public static let hardMaximumSelectedItems = 100_000
        public static let hardMaximumStringUTF8Bytes = 64 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 128 * 1_024 * 1_024
        public static let hardMaximumWorkUnits: UInt64 = 512 * 1_024 * 1_024
        public static let hardMaximumCancellationCheckInterval: UInt64 = 65_536
        public static let `default` = Limits()

        public let maximumSnapshotItems: Int
        public let maximumSelectedItems: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumWorkUnits: UInt64
        public let cancellationCheckInterval: UInt64

        public init(
            maximumSnapshotItems: Int = 100_000,
            maximumSelectedItems: Int = 1_024,
            maximumStringUTF8Bytes: Int = 16 * 1_024,
            maximumTotalStringUTF8Bytes: Int = 16 * 1_024 * 1_024,
            maximumWorkUnits: UInt64 = 64 * 1_024 * 1_024,
            cancellationCheckInterval: UInt64 = 1_024
        ) {
            self.maximumSnapshotItems = maximumSnapshotItems
            self.maximumSelectedItems = maximumSelectedItems
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case snapshotItems
        case selectedItems
        case stringUTF8Bytes
        case totalStringUTF8Bytes
        case workUnits
        case cancellationCheckInterval
    }

    public enum ErrorCode: String, CaseIterable, Hashable, Sendable {
        case cancelled
        case invalidLimit
        case workLimitExceeded
        case stringLimitExceeded
        case totalStringLimitExceeded
        case tooManySnapshotItems
        case emptySelection
        case tooManySelectedItems
        case duplicateSelection
        case selectionMismatch
        case unknownSelection
        case selectedItemNotVisible
        case selectedItemIneligible
        case duplicateVisibleOrder
        case invalidFolderSnapshot
        case invalidNavigationSnapshot
        case staleFolderSnapshot
        case staleNavigationSnapshot
        case staleCapabilities
        case staleAuthorityBinding
        case stalePublicationTarget
        case unsupportedCapability
        case invalidRootBinding
        case invalidResultBinding
        case invalidItemRevision
        case invalidAuthorityBinding
        case duplicateAuthorityBinding
        case duplicateSourceAlias
        case publicationRevisionOverflow
        case receiptMismatch
        case invalidExecutionEvidence
    }

    /// Typed planning/validation failure. Paths, URLs, metadata, and underlying errors are omitted.
    public struct Error: Swift.Error, Hashable, LocalizedError, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible
    {
        public let code: ErrorCode
        public let itemIdentity: ComparedFileNavigationItemIdentity?
        public let side: Side?
        public let limit: Limit?
        public let maximum: UInt64?

        fileprivate init(
            _ code: ErrorCode,
            itemIdentity: ComparedFileNavigationItemIdentity? = nil,
            side: Side? = nil,
            limit: Limit? = nil,
            maximum: UInt64? = nil
        ) {
            self.code = code
            self.itemIdentity = itemIdentity
            self.side = side
            self.limit = limit
            self.maximum = maximum
        }

        public var errorDescription: String? {
            switch code {
            case .cancelled:
                "Selected file-pair opening was cancelled."
            case .invalidLimit:
                "Selected file-pair opening has an invalid limit."
            case .workLimitExceeded:
                "Selected file-pair opening exceeded its work limit."
            case .stringLimitExceeded, .totalStringLimitExceeded:
                "Selected file-pair opening exceeded a string limit."
            case .tooManySnapshotItems:
                "Selected file-pair opening exceeds its snapshot-item limit."
            case .emptySelection:
                "Selected file-pair opening requires at least one selected row."
            case .tooManySelectedItems:
                "Selected file-pair opening exceeds its selection limit."
            case .duplicateSelection:
                "Selected file-pair opening repeats a selected row."
            case .selectionMismatch:
                "Selected file-pair opening does not match the exact folder-results selection."
            case .unknownSelection:
                "Selected file-pair opening references an unknown row."
            case .selectedItemNotVisible:
                "Selected file-pair opening requires every selected row to be visible."
            case .selectedItemIneligible:
                "Selected file-pair opening supports only eligible paired regular files."
            case .duplicateVisibleOrder:
                "Selected file-pair opening contains an ambiguous visible row order."
            case .invalidFolderSnapshot:
                "Selected file-pair opening received an invalid folder-comparison snapshot."
            case .invalidNavigationSnapshot:
                "Selected file-pair opening received an invalid navigation snapshot."
            case .staleFolderSnapshot:
                "Selected file-pair opening folder-comparison state is stale."
            case .staleNavigationSnapshot:
                "Selected file-pair opening folder-results state is stale."
            case .staleCapabilities:
                "Selected file-pair opening executor capabilities are stale."
            case .staleAuthorityBinding:
                "Selected file-pair opening authority bindings are stale."
            case .stalePublicationTarget:
                "Selected file-pair opening publication target is stale."
            case .unsupportedCapability:
                "Selected file-pair opening requires an unsupported executor capability."
            case .invalidRootBinding:
                "Selected file-pair opening roots do not identify the same result source."
            case .invalidResultBinding:
                "Selected file-pair opening row does not match its exact comparison result."
            case .invalidItemRevision:
                "Selected file-pair opening row does not match exact regular-file revisions."
            case .invalidAuthorityBinding:
                "Selected file-pair opening has an invalid source-authority binding."
            case .duplicateAuthorityBinding:
                "Selected file-pair opening repeats an authority binding."
            case .duplicateSourceAlias:
                "Selected file-pair opening repeats or aliases a physical source file."
            case .publicationRevisionOverflow:
                "Selected file-pair opening cannot advance the publication revision."
            case .receiptMismatch:
                "Selected file-pair opening plan receipt is invalid."
            case .invalidExecutionEvidence:
                "Selected file-pair opening execution evidence contradicts its plan."
            }
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.Error(code: \(code.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }
    }

    /// Exact structural navigation reference. Digest includes roots, row order and payloads,
    /// filtering, sorting, selection, cursor, authorities, capabilities, and limits.
    public struct NavigationSnapshotReference: Hashable, Sendable {
        public let folderResults: ComparedFileFolderResultsReference
        public let stateSHA256: Data

        fileprivate init(
            folderResults: ComparedFileFolderResultsReference,
            stateSHA256: Data
        ) {
            self.folderResults = folderResults
            self.stateSHA256 = stateSHA256
        }
    }

    public struct SourceBinding: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let side: Side
        public let root: FolderComparisonRoot
        public let relativePath: String
        public let revision: FolderComparisonItemRevision
        public let authority: AuthorityBinding
        public let navigationAuthority: ComparedFileNavigationRootAuthority
        public let readOnly: Bool

        fileprivate init(
            side: Side,
            root: FolderComparisonRoot,
            relativePath: String,
            revision: FolderComparisonItemRevision,
            authority: AuthorityBinding,
            navigationAuthority: ComparedFileNavigationRootAuthority
        ) {
            self.side = side
            self.root = root
            self.relativePath = relativePath
            self.revision = revision
            self.authority = authority
            self.navigationAuthority = navigationAuthority
            readOnly = true
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.SourceBinding(side: \(side.rawValue), readOnly: true, source: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["side": side, "readOnly": readOnly, "source": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct Action: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let index: Int
        public let visibleOrdinal: Int
        public let itemIdentity: ComparedFileNavigationItemIdentity
        public let resultID: DirectoryResult.ID
        public let intent: Intent
        public let comparisonMode: UnifiedOpenWorkflow.ComparisonMode
        public let left: SourceBinding
        public let right: SourceBinding
        public let actionSHA256: Data

        fileprivate init(
            index: Int,
            visibleOrdinal: Int,
            itemIdentity: ComparedFileNavigationItemIdentity,
            resultID: DirectoryResult.ID,
            left: SourceBinding,
            right: SourceBinding,
            actionSHA256: Data
        ) {
            self.index = index
            self.visibleOrdinal = visibleOrdinal
            self.itemIdentity = itemIdentity
            self.resultID = resultID
            intent = .readOnlyTextComparison
            comparisonMode = .text
            self.left = left
            self.right = right
            self.actionSHA256 = actionSHA256
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.Action(index: \(index), visibleOrdinal: \(visibleOrdinal), intent: \(intent.rawValue), sources: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "index": index,
                    "visibleOrdinal": visibleOrdinal,
                    "intent": intent,
                    "sources": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct PlanningReceipt: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let planSHA256: Data
        public let folderSnapshot: FolderComparisonWorkflowSnapshotReference
        public let navigationSnapshot: NavigationSnapshotReference
        public let selectedItemCount: Int
        public let actionSHA256s: [Data]
        public let planningWorkUnits: UInt64

        fileprivate init(
            planSHA256: Data,
            folderSnapshot: FolderComparisonWorkflowSnapshotReference,
            navigationSnapshot: NavigationSnapshotReference,
            selectedItemCount: Int,
            actionSHA256s: [Data],
            planningWorkUnits: UInt64
        ) {
            self.planSHA256 = planSHA256
            self.folderSnapshot = folderSnapshot
            self.navigationSnapshot = navigationSnapshot
            self.selectedItemCount = selectedItemCount
            self.actionSHA256s = actionSHA256s
            self.planningWorkUnits = planningWorkUnits
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.PlanningReceipt(selectedItems: \(selectedItemCount), workUnits: \(planningWorkUnits), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "selectedItemCount": selectedItemCount,
                    "actionCount": actionSHA256s.count,
                    "planningWorkUnits": planningWorkUnits,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum ValidationContract: String, Hashable, Sendable {
        case exactFolderNavigationSelectionCapabilityAuthorityAndPublicationCAS
    }

    public enum SourceAccessContract: String, Hashable, Sendable {
        case acquireBothBoundAuthoritiesAndOpenPinnedDescriptorRelativeRegularFilesWithoutFollowingLinks
    }

    public enum StagingContract: String, Hashable, Sendable {
        case stageEveryOrderedPairReadOnlyBeforePublicationAndReportEveryRow
    }

    public enum PublicationContract: String, Hashable, Sendable {
        case publishCompleteOrderedBatchAtomicallyExactlyOnceOrPublishNothing
    }

    public enum CancellationContract: String, Hashable, Sendable {
        case checkPeriodicallyDuringPlanningAndBeforeEachStageAndImmediatelyBeforePublication
    }

    public enum UIContract: String, Hashable, Sendable {
        case noAppKitWindowCreationOrUIParityClaim
    }

    /// Mandatory contract for a future app/platform executor. This file supplies no executor.
    public struct ExecutorContract: Hashable, Sendable {
        public static let required = ExecutorContract()

        public let validation =
            ValidationContract.exactFolderNavigationSelectionCapabilityAuthorityAndPublicationCAS
        public let sourceAccess =
            SourceAccessContract
            .acquireBothBoundAuthoritiesAndOpenPinnedDescriptorRelativeRegularFilesWithoutFollowingLinks
        public let staging =
            StagingContract.stageEveryOrderedPairReadOnlyBeforePublicationAndReportEveryRow
        public let publication =
            PublicationContract.publishCompleteOrderedBatchAtomicallyExactlyOnceOrPublishNothing
        public let cancellation =
            CancellationContract
            .checkPeriodicallyDuringPlanningAndBeforeEachStageAndImmediatelyBeforePublication
        public let ui = UIContract.noAppKitWindowCreationOrUIParityClaim

        public init() {}
    }

    /// Snapshots are immutable value inputs but intentionally inherit no stronger equality claim
    /// than their existing public types provide.
    public struct Request: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let expectedFolderSnapshot: FolderComparisonWorkflowSnapshotReference
        public let expectedNavigationSnapshot: NavigationSnapshotReference
        public let folderSnapshot: FolderComparisonWorkflowSnapshot
        public let navigationSnapshot: ComparedFileNavigationSnapshot
        public let selectedItemIdentities: [ComparedFileNavigationItemIdentity]
        public let authorityBindings: [AuthorityBinding]
        public let folderCapabilities: FolderComparisonWorkflowCapabilities
        public let executorCapabilities: ExecutorCapabilities
        public let publicationTarget: PublicationTarget
        public let folderValidationLimits: FolderComparisonWorkflowLimits
        public let limits: Limits

        public init(
            expectedFolderSnapshot: FolderComparisonWorkflowSnapshotReference,
            expectedNavigationSnapshot: NavigationSnapshotReference,
            folderSnapshot: FolderComparisonWorkflowSnapshot,
            navigationSnapshot: ComparedFileNavigationSnapshot,
            selectedItemIdentities: [ComparedFileNavigationItemIdentity],
            authorityBindings: [AuthorityBinding],
            folderCapabilities: FolderComparisonWorkflowCapabilities,
            executorCapabilities: ExecutorCapabilities,
            publicationTarget: PublicationTarget,
            folderValidationLimits: FolderComparisonWorkflowLimits = .default,
            limits: Limits = .default
        ) {
            self.expectedFolderSnapshot = expectedFolderSnapshot
            self.expectedNavigationSnapshot = expectedNavigationSnapshot
            self.folderSnapshot = folderSnapshot
            self.navigationSnapshot = navigationSnapshot
            self.selectedItemIdentities = selectedItemIdentities
            self.authorityBindings = authorityBindings
            self.folderCapabilities = folderCapabilities
            self.executorCapabilities = executorCapabilities
            self.publicationTarget = publicationTarget
            self.folderValidationLimits = folderValidationLimits
            self.limits = limits
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.Request(selectedItems: \(selectedItemIdentities.count), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "selectedItemCount": selectedItemIdentities.count,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Plan: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let folderSnapshot: FolderComparisonWorkflowSnapshotReference
        public let navigationSnapshot: NavigationSnapshotReference
        public let actions: [Action]
        public let authorityBindings: [AuthorityBinding]
        public let folderCapabilities: FolderComparisonWorkflowCapabilities
        public let executorCapabilities: ExecutorCapabilities
        public let publicationTarget: PublicationTarget
        public let failurePolicy: FailurePolicy
        public let folderValidationLimits: FolderComparisonWorkflowLimits
        public let limits: Limits
        public let receipt: PlanningReceipt
        public let executorContract: ExecutorContract

        fileprivate init(
            folderSnapshot: FolderComparisonWorkflowSnapshotReference,
            navigationSnapshot: NavigationSnapshotReference,
            actions: [Action],
            authorityBindings: [AuthorityBinding],
            folderCapabilities: FolderComparisonWorkflowCapabilities,
            executorCapabilities: ExecutorCapabilities,
            publicationTarget: PublicationTarget,
            folderValidationLimits: FolderComparisonWorkflowLimits,
            limits: Limits,
            receipt: PlanningReceipt
        ) {
            self.folderSnapshot = folderSnapshot
            self.navigationSnapshot = navigationSnapshot
            self.actions = actions
            self.authorityBindings = authorityBindings
            self.folderCapabilities = folderCapabilities
            self.executorCapabilities = executorCapabilities
            self.publicationTarget = publicationTarget
            failurePolicy = .stageAllThenPublishAllOrNone
            self.folderValidationLimits = folderValidationLimits
            self.limits = limits
            self.receipt = receipt
            executorContract = .required
        }

        public func validateForExecution(
            _ current: ExecutionValidation,
            cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
        ) throws -> ExecutionLease {
            return try Planner.validateCurrent(
                self,
                against: current,
                phase: .staging,
                cancellationCheck: cancellationCheck
            )
        }

        /// Executor calls this with fresh current observations immediately before its single atomic
        /// publication attempt. Returned lease is one-shot and valid only for publication evidence.
        public func validateForPublication(
            _ current: ExecutionValidation,
            staging: StagingReceipt,
            cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
        ) throws -> ExecutionLease {
            guard staging.planningReceipt == receipt,
                staging.itemEvidence.count == actions.count,
                staging.itemEvidence.allSatisfy({
                    if case .stagedReadOnly = $0.disposition { return true }
                    return false
                })
            else {
                throw Error(.invalidExecutionEvidence)
            }
            let lease = try Planner.validateCurrent(
                self,
                against: current,
                phase: .publication,
                stagingAttemptIdentity: staging.attemptIdentity,
                cancellationCheck: cancellationCheck
            )
            try staging.claimPublication()
            return lease
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.Plan(actions: \(actions.count), policy: \(failurePolicy.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "actionCount": actions.count,
                    "failurePolicy": failurePolicy,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct ExecutionValidation: Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let folderSnapshot: FolderComparisonWorkflowSnapshot
        public let navigationSnapshot: ComparedFileNavigationSnapshot
        public let authorityBindings: [AuthorityBinding]
        public let folderCapabilities: FolderComparisonWorkflowCapabilities
        public let executorCapabilities: ExecutorCapabilities
        public let publicationTarget: PublicationTarget

        public init(
            folderSnapshot: FolderComparisonWorkflowSnapshot,
            navigationSnapshot: ComparedFileNavigationSnapshot,
            authorityBindings: [AuthorityBinding],
            folderCapabilities: FolderComparisonWorkflowCapabilities,
            executorCapabilities: ExecutorCapabilities,
            publicationTarget: PublicationTarget
        ) {
            self.folderSnapshot = folderSnapshot
            self.navigationSnapshot = navigationSnapshot
            self.authorityBindings = authorityBindings
            self.folderCapabilities = folderCapabilities
            self.executorCapabilities = executorCapabilities
            self.publicationTarget = publicationTarget
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.ExecutionValidation(details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["details": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    /// Core-issued proof that exact current state was validated against one plan. Executors must
    /// obtain this immediately before staging and obtain a fresh lease after any state change.
    public enum ExecutionPhase: String, Hashable, Sendable {
        case staging
        case publication
    }

    public final class ExecutionLease: @unchecked Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let attemptIdentity: UUID
        public let folderSnapshot: FolderComparisonWorkflowSnapshotReference
        public let navigationSnapshot: NavigationSnapshotReference
        public let publicationTarget: PublicationTarget
        public let phase: ExecutionPhase
        fileprivate let planSHA256: Data
        fileprivate let stagingAttemptIdentity: UUID?
        private let lock = NSLock()
        private var isConsumed = false

        fileprivate init(
            plan: Plan,
            phase: ExecutionPhase,
            stagingAttemptIdentity: UUID? = nil
        ) {
            attemptIdentity = UUID()
            folderSnapshot = plan.folderSnapshot
            navigationSnapshot = plan.navigationSnapshot
            publicationTarget = plan.publicationTarget
            self.phase = phase
            planSHA256 = plan.receipt.planSHA256
            self.stagingAttemptIdentity = stagingAttemptIdentity
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.ExecutionLease(phase: \(phase.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["phase": phase, "details": "<redacted>"],
                displayStyle: .class
            )
        }

        fileprivate func consume(for plan: Plan, requiredPhase: ExecutionPhase) throws {
            lock.lock()
            defer { lock.unlock() }
            guard !isConsumed,
                phase == requiredPhase,
                folderSnapshot == plan.folderSnapshot,
                navigationSnapshot == plan.navigationSnapshot,
                publicationTarget == plan.publicationTarget,
                planSHA256 == plan.receipt.planSHA256
            else {
                throw Error(.invalidExecutionEvidence)
            }
            isConsumed = true
        }
    }

    public enum ExecutionDiagnosticCode: String, CaseIterable, Hashable, Sendable {
        case staleFolderSnapshot
        case staleNavigationSnapshot
        case staleCapabilities
        case staleAuthority
        case stalePublicationTarget
        case sourceChanged
        case authorityUnavailable
        case sourceOpenFailed
        case comparisonStagingFailed
        case publicationFailed
        case cancelledBeforePublication
        case contractUnsupported
        case limitExceeded
        case inputRejected
        case blockedByEarlierFailure
        case publicationOutcomeUncertain
    }

    /// Redacted executor diagnostic. It identifies an ordered action and side, never a path or URL.
    public struct ExecutionDiagnostic: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible
    {
        public let code: ExecutionDiagnosticCode
        public let actionIndex: Int?
        public let side: Side?

        public init(
            code: ExecutionDiagnosticCode,
            actionIndex: Int? = nil,
            side: Side? = nil
        ) {
            self.code = code
            self.actionIndex = actionIndex
            self.side = side
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.ExecutionDiagnostic(code: \(code.rawValue), actionIndex: \(actionIndex.map(String.init) ?? "none"), details: <redacted>)"
        }

        public var debugDescription: String { description }
    }

    public enum ItemExecutionDisposition: Hashable, Sendable {
        /// Both exact sources were opened read-only and comparison state was staged but unpublished.
        case stagedReadOnly
        case failed(ExecutionDiagnostic)
        case notAttempted(ExecutionDiagnostic)
    }

    public struct ItemExecutionEvidence: Hashable, Sendable {
        public let actionIndex: Int
        public let actionSHA256: Data
        public let disposition: ItemExecutionDisposition

        public init(
            actionIndex: Int,
            actionSHA256: Data,
            disposition: ItemExecutionDisposition
        ) {
            self.actionIndex = actionIndex
            self.actionSHA256 = actionSHA256
            self.disposition = disposition
        }
    }

    /// One-shot proof that every item disposition was staged read-only before publication.
    public struct StagingReceipt: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let planningReceipt: PlanningReceipt
        public let itemEvidence: [ItemExecutionEvidence]
        fileprivate let attemptIdentity: UUID
        private let publicationGate: PublicationGate

        fileprivate init(
            plan: Plan,
            itemEvidence: [ItemExecutionEvidence],
            attemptIdentity: UUID
        ) {
            planningReceipt = plan.receipt
            self.itemEvidence = itemEvidence
            self.attemptIdentity = attemptIdentity
            publicationGate = PublicationGate()
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.StagingReceipt(items: \(itemEvidence.count), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["itemCount": itemEvidence.count, "details": "<redacted>"],
                displayStyle: .struct
            )
        }

        fileprivate func claimPublication() throws {
            try publicationGate.claim()
        }
    }

    private final class PublicationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isClaimed = false

        func claim() throws {
            lock.lock()
            defer { lock.unlock() }
            guard !isClaimed else {
                throw Error(.invalidExecutionEvidence)
            }
            isClaimed = true
        }
    }

    /// Evidence for one successful all-or-none commit. No field represents or claims a UI window.
    public struct PublicationEvidence: Hashable, Sendable {
        public let attemptIdentity: UUID
        public let expectedTarget: PublicationTarget
        public let successorTarget: PublicationTarget
        public let publicationCount: Int
        public let actionSHA256s: [Data]

        public init(
            attemptIdentity: UUID,
            expectedTarget: PublicationTarget,
            successorTarget: PublicationTarget,
            publicationCount: Int,
            actionSHA256s: [Data]
        ) {
            self.attemptIdentity = attemptIdentity
            self.expectedTarget = expectedTarget
            self.successorTarget = successorTarget
            self.publicationCount = publicationCount
            self.actionSHA256s = actionSHA256s
        }
    }

    /// Evidence that an attempted or abandoned execution left the publication CAS unchanged.
    public struct NonPublicationEvidence: Hashable, Sendable {
        public let expectedTarget: PublicationTarget
        public let observedTargetAfterFailure: PublicationTarget
        public let publicationAttemptCount: Int
        public let attemptIdentity: UUID?
        public let actionSHA256s: [Data]

        public init(
            expectedTarget: PublicationTarget,
            observedTargetAfterFailure: PublicationTarget,
            publicationAttemptCount: Int,
            attemptIdentity: UUID? = nil,
            actionSHA256s: [Data]
        ) {
            self.expectedTarget = expectedTarget
            self.observedTargetAfterFailure = observedTargetAfterFailure
            self.publicationAttemptCount = publicationAttemptCount
            self.attemptIdentity = attemptIdentity
            self.actionSHA256s = actionSHA256s
        }
    }

    /// Evidence that publication was attempted once but its atomic outcome could not be proved.
    public struct UncertainPublicationEvidence: Hashable, Sendable {
        public let attemptIdentity: UUID
        public let expectedTarget: PublicationTarget
        public let attemptCount: Int
        public let actionSHA256s: [Data]

        public init(
            attemptIdentity: UUID,
            expectedTarget: PublicationTarget,
            attemptCount: Int,
            actionSHA256s: [Data]
        ) {
            self.attemptIdentity = attemptIdentity
            self.expectedTarget = expectedTarget
            self.attemptCount = attemptCount
            self.actionSHA256s = actionSHA256s
        }
    }

    public struct ExecutionReceipt: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let planningReceipt: PlanningReceipt
        public let itemEvidence: [ItemExecutionEvidence]
        public let publication: PublicationEvidence

        fileprivate init(
            plan: Plan,
            itemEvidence: [ItemExecutionEvidence],
            publication: PublicationEvidence
        ) {
            planningReceipt = plan.receipt
            self.itemEvidence = itemEvidence
            self.publication = publication
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.ExecutionReceipt(items: \(itemEvidence.count), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["itemCount": itemEvidence.count, "details": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct NonPublicationReceipt: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let planningReceipt: PlanningReceipt
        public let itemEvidence: [ItemExecutionEvidence]
        public let diagnostic: ExecutionDiagnostic
        public let nonPublication: NonPublicationEvidence

        fileprivate init(
            plan: Plan,
            itemEvidence: [ItemExecutionEvidence],
            diagnostic: ExecutionDiagnostic,
            nonPublication: NonPublicationEvidence
        ) {
            planningReceipt = plan.receipt
            self.itemEvidence = itemEvidence
            self.diagnostic = diagnostic
            self.nonPublication = nonPublication
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.NonPublicationReceipt(items: \(itemEvidence.count), diagnostic: \(diagnostic.code.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "itemCount": itemEvidence.count,
                    "diagnosticCode": diagnostic.code,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct UncertainExecutionReceipt: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let planningReceipt: PlanningReceipt
        public let itemEvidence: [ItemExecutionEvidence]
        public let diagnostic: ExecutionDiagnostic
        public let publicationAttempt: UncertainPublicationEvidence

        fileprivate init(
            plan: Plan,
            itemEvidence: [ItemExecutionEvidence],
            diagnostic: ExecutionDiagnostic,
            publicationAttempt: UncertainPublicationEvidence
        ) {
            planningReceipt = plan.receipt
            self.itemEvidence = itemEvidence
            self.diagnostic = diagnostic
            self.publicationAttempt = publicationAttempt
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.UncertainExecutionReceipt(items: \(itemEvidence.count), diagnostic: \(diagnostic.code.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "itemCount": itemEvidence.count,
                    "diagnosticCode": diagnostic.code,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum ExecutionOutcome: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case completed(ExecutionReceipt)
        case notPublished(NonPublicationReceipt)
        case publicationUncertain(UncertainExecutionReceipt)

        private var kind: String {
            switch self {
            case .completed: "completed"
            case .notPublished: "notPublished"
            case .publicationUncertain: "publicationUncertain"
            }
        }

        public var description: String {
            "SelectedFilePairOpenWorkflow.ExecutionOutcome(kind: \(kind), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["kind": kind, "details": "<redacted>"],
                displayStyle: .enum
            )
        }
    }

    /// Validates complete, ordered evidence so no selected row can disappear from an outcome.
    public enum ExecutionOutcomeFactory: Sendable {
        /// Records rejection before staging validation produced a lease. No source was opened.
        public static func rejectedBeforeStaging(
            plan: Plan,
            diagnostic: ExecutionDiagnostic,
            nonPublication: NonPublicationEvidence
        ) throws -> ExecutionOutcome {
            try validateGlobalRejection(diagnostic, actionCount: plan.actions.count)
            try validateZeroAttemptNonPublication(
                nonPublication,
                for: plan,
                diagnostic: diagnostic
            )
            let itemEvidence = plan.actions.map {
                ItemExecutionEvidence(
                    actionIndex: $0.index,
                    actionSHA256: $0.actionSHA256,
                    disposition: .notAttempted(diagnostic)
                )
            }
            try validateItemEvidence(itemEvidence, for: plan)
            return .notPublished(
                NonPublicationReceipt(
                    plan: plan,
                    itemEvidence: itemEvidence,
                    diagnostic: diagnostic,
                    nonPublication: nonPublication
                )
            )
        }

        public static func staged(
            plan: Plan,
            lease: ExecutionLease,
            itemEvidence: [ItemExecutionEvidence]
        ) throws -> StagingReceipt {
            try validateItemEvidence(itemEvidence, for: plan)
            guard
                itemEvidence.allSatisfy({
                    if case .stagedReadOnly = $0.disposition { return true }
                    return false
                })
            else {
                throw Error(.invalidExecutionEvidence)
            }
            try lease.consume(for: plan, requiredPhase: .staging)
            return StagingReceipt(
                plan: plan,
                itemEvidence: itemEvidence,
                attemptIdentity: lease.attemptIdentity
            )
        }

        /// Finalizes staged work when fresh publication validation rejects current state.
        public static func rejectedBeforePublicationValidation(
            plan: Plan,
            staging: StagingReceipt,
            diagnostic: ExecutionDiagnostic,
            nonPublication: NonPublicationEvidence
        ) throws -> ExecutionOutcome {
            try validate(staging, for: plan)
            try validateGlobalRejection(diagnostic, actionCount: plan.actions.count)
            try validateZeroAttemptNonPublication(
                nonPublication,
                for: plan,
                diagnostic: diagnostic
            )
            try staging.claimPublication()
            return .notPublished(
                NonPublicationReceipt(
                    plan: plan,
                    itemEvidence: staging.itemEvidence,
                    diagnostic: diagnostic,
                    nonPublication: nonPublication
                )
            )
        }

        /// Consumes a publication lease when execution is cancelled before its atomic CAS attempt.
        public static func abandonedBeforePublicationAttempt(
            plan: Plan,
            lease: ExecutionLease,
            staging: StagingReceipt,
            diagnostic: ExecutionDiagnostic,
            nonPublication: NonPublicationEvidence
        ) throws -> ExecutionOutcome {
            try validate(staging, for: plan)
            try validate(diagnostic, actionCount: plan.actions.count)
            try validateZeroAttemptNonPublication(
                nonPublication,
                for: plan,
                diagnostic: diagnostic
            )
            guard lease.stagingAttemptIdentity == staging.attemptIdentity,
                diagnostic.code == .cancelledBeforePublication
            else {
                throw Error(.invalidExecutionEvidence)
            }
            try lease.consume(for: plan, requiredPhase: .publication)
            return .notPublished(
                NonPublicationReceipt(
                    plan: plan,
                    itemEvidence: staging.itemEvidence,
                    diagnostic: diagnostic,
                    nonPublication: nonPublication
                )
            )
        }

        public static func completed(
            plan: Plan,
            lease: ExecutionLease,
            staging: StagingReceipt,
            publication: PublicationEvidence
        ) throws -> ExecutionOutcome {
            try validate(staging, for: plan)
            try validateMonotonicPublicationTransition(
                from: publication.expectedTarget,
                to: publication.successorTarget
            )
            let nextRevision = plan.publicationTarget.revision.addingReportingOverflow(1)
            guard lease.stagingAttemptIdentity == staging.attemptIdentity,
                publication.attemptIdentity == lease.attemptIdentity,
                publication.expectedTarget == plan.publicationTarget,
                !nextRevision.overflow,
                publication.successorTarget.revision == nextRevision.partialValue,
                publication.publicationCount == 1,
                publication.actionSHA256s == plan.actions.map(\.actionSHA256)
            else {
                throw Error(.invalidExecutionEvidence)
            }
            try lease.consume(for: plan, requiredPhase: .publication)
            return .completed(
                ExecutionReceipt(
                    plan: plan,
                    itemEvidence: staging.itemEvidence,
                    publication: publication
                )
            )
        }

        public static func notPublished(
            plan: Plan,
            lease: ExecutionLease,
            itemEvidence: [ItemExecutionEvidence],
            diagnostic: ExecutionDiagnostic,
            nonPublication: NonPublicationEvidence
        ) throws -> ExecutionOutcome {
            try validateItemEvidence(itemEvidence, for: plan)
            try validate(diagnostic, actionCount: plan.actions.count)
            let matchingFailure: Bool
            if diagnostic.actionIndex != nil {
                matchingFailure = itemEvidence.contains { item in
                    if case .failed(let itemDiagnostic) = item.disposition {
                        return itemDiagnostic == diagnostic
                    }
                    return false
                }
            } else {
                var foundMatchingFailure = false
                var stagingStopped = false
                matchingFailure =
                    itemEvidence.allSatisfy { item in
                        switch item.disposition {
                        case .stagedReadOnly:
                            return !stagingStopped
                        case .notAttempted(let itemDiagnostic):
                            stagingStopped = true
                            let matches = itemDiagnostic == diagnostic
                            foundMatchingFailure = foundMatchingFailure || matches
                            return matches
                        case .failed:
                            return false
                        }
                    } && foundMatchingFailure
            }
            try validateMonotonicPublicationTransition(
                from: nonPublication.expectedTarget,
                to: nonPublication.observedTargetAfterFailure
            )
            try validateNonPublicationDiagnostic(
                diagnostic,
                expectedTarget: nonPublication.expectedTarget,
                observedTarget: nonPublication.observedTargetAfterFailure
            )
            guard diagnostic.code != .publicationOutcomeUncertain,
                nonPublication.expectedTarget == plan.publicationTarget,
                nonPublication.actionSHA256s == plan.actions.map(\.actionSHA256),
                nonPublication.publicationAttemptCount == 0,
                nonPublication.attemptIdentity == nil,
                diagnostic.code != .publicationFailed,
                matchingFailure
            else {
                throw Error(.invalidExecutionEvidence)
            }
            try lease.consume(for: plan, requiredPhase: .staging)
            return .notPublished(
                NonPublicationReceipt(
                    plan: plan,
                    itemEvidence: itemEvidence,
                    diagnostic: diagnostic,
                    nonPublication: nonPublication
                )
            )
        }

        /// Finalizes a failed atomic publication attempt for one exact staged execution session.
        public static func notPublished(
            plan: Plan,
            lease: ExecutionLease,
            staging: StagingReceipt,
            diagnostic: ExecutionDiagnostic,
            nonPublication: NonPublicationEvidence
        ) throws -> ExecutionOutcome {
            try validate(staging, for: plan)
            try validate(diagnostic, actionCount: plan.actions.count)
            try validateMonotonicPublicationTransition(
                from: nonPublication.expectedTarget,
                to: nonPublication.observedTargetAfterFailure
            )
            try validateNonPublicationDiagnostic(
                diagnostic,
                expectedTarget: nonPublication.expectedTarget,
                observedTarget: nonPublication.observedTargetAfterFailure
            )
            guard lease.stagingAttemptIdentity == staging.attemptIdentity,
                nonPublication.expectedTarget == plan.publicationTarget,
                nonPublication.publicationAttemptCount == 1,
                nonPublication.attemptIdentity == lease.attemptIdentity,
                nonPublication.actionSHA256s == plan.actions.map(\.actionSHA256),
                [.publicationFailed, .stalePublicationTarget].contains(diagnostic.code),
                diagnostic.actionIndex == nil,
                diagnostic.side == nil
            else {
                throw Error(.invalidExecutionEvidence)
            }
            try lease.consume(for: plan, requiredPhase: .publication)
            return .notPublished(
                NonPublicationReceipt(
                    plan: plan,
                    itemEvidence: staging.itemEvidence,
                    diagnostic: diagnostic,
                    nonPublication: nonPublication
                )
            )
        }

        public static func publicationUncertain(
            plan: Plan,
            lease: ExecutionLease,
            staging: StagingReceipt,
            diagnostic: ExecutionDiagnostic,
            publicationAttempt: UncertainPublicationEvidence
        ) throws -> ExecutionOutcome {
            try validate(staging, for: plan)
            try validate(diagnostic, actionCount: plan.actions.count)
            guard lease.stagingAttemptIdentity == staging.attemptIdentity,
                diagnostic.code == .publicationOutcomeUncertain,
                publicationAttempt.attemptIdentity == lease.attemptIdentity,
                publicationAttempt.expectedTarget == plan.publicationTarget,
                publicationAttempt.attemptCount == 1,
                publicationAttempt.actionSHA256s == plan.actions.map(\.actionSHA256)
            else {
                throw Error(.invalidExecutionEvidence)
            }
            try lease.consume(for: plan, requiredPhase: .publication)
            return .publicationUncertain(
                UncertainExecutionReceipt(
                    plan: plan,
                    itemEvidence: staging.itemEvidence,
                    diagnostic: diagnostic,
                    publicationAttempt: publicationAttempt
                )
            )
        }

        private static func validateItemEvidence(
            _ evidence: [ItemExecutionEvidence],
            for plan: Plan
        ) throws {
            guard evidence.count == plan.actions.count else {
                throw Error(.invalidExecutionEvidence)
            }
            var hasPriorFailure = false
            var reachedNotAttempted = false
            for (action, item) in zip(plan.actions, evidence) {
                guard item.actionIndex == action.index,
                    item.actionSHA256 == action.actionSHA256
                else {
                    throw Error(.invalidExecutionEvidence)
                }
                switch item.disposition {
                case .stagedReadOnly:
                    guard !reachedNotAttempted else {
                        throw Error(.invalidExecutionEvidence)
                    }
                case .failed(let diagnostic):
                    guard !reachedNotAttempted else {
                        throw Error(.invalidExecutionEvidence)
                    }
                    try validate(diagnostic, actionCount: plan.actions.count)
                    guard diagnostic.actionIndex == action.index,
                        diagnostic.code != .blockedByEarlierFailure
                    else {
                        throw Error(.invalidExecutionEvidence)
                    }
                    hasPriorFailure = true
                case .notAttempted(let diagnostic):
                    try validate(diagnostic, actionCount: plan.actions.count)
                    let blockedByFailure =
                        diagnostic.actionIndex == action.index
                        && diagnostic.code == .blockedByEarlierFailure
                        && diagnostic.side == nil
                        && hasPriorFailure
                    let globallyRejected =
                        diagnostic.actionIndex == nil
                        && diagnostic.side == nil
                        && isGlobalRejection(diagnostic.code)
                    guard blockedByFailure || globallyRejected
                    else {
                        throw Error(.invalidExecutionEvidence)
                    }
                    reachedNotAttempted = true
                }
            }
        }

        private static func validateGlobalRejection(
            _ diagnostic: ExecutionDiagnostic,
            actionCount: Int
        ) throws {
            try validate(diagnostic, actionCount: actionCount)
            guard diagnostic.actionIndex == nil,
                diagnostic.side == nil,
                isGlobalRejection(diagnostic.code)
            else {
                throw Error(.invalidExecutionEvidence)
            }
        }

        private static func validateZeroAttemptNonPublication(
            _ evidence: NonPublicationEvidence,
            for plan: Plan,
            diagnostic: ExecutionDiagnostic
        ) throws {
            try validateMonotonicPublicationTransition(
                from: evidence.expectedTarget,
                to: evidence.observedTargetAfterFailure
            )
            try validateNonPublicationDiagnostic(
                diagnostic,
                expectedTarget: evidence.expectedTarget,
                observedTarget: evidence.observedTargetAfterFailure
            )
            guard evidence.expectedTarget == plan.publicationTarget,
                evidence.publicationAttemptCount == 0,
                evidence.attemptIdentity == nil,
                evidence.actionSHA256s == plan.actions.map(\.actionSHA256)
            else {
                throw Error(.invalidExecutionEvidence)
            }
        }

        private static func validateMonotonicPublicationTransition(
            from expected: PublicationTarget,
            to observed: PublicationTarget
        ) throws {
            guard observed.identity == expected.identity,
                observed.revision >= expected.revision
            else {
                throw Error(.invalidExecutionEvidence)
            }
        }

        private static func validateNonPublicationDiagnostic(
            _ diagnostic: ExecutionDiagnostic,
            expectedTarget: PublicationTarget,
            observedTarget: PublicationTarget
        ) throws {
            guard
                diagnostic.code != .stalePublicationTarget
                    || observedTarget != expectedTarget
            else {
                throw Error(.invalidExecutionEvidence)
            }
        }

        private static func isGlobalRejection(_ code: ExecutionDiagnosticCode) -> Bool {
            [
                .staleFolderSnapshot,
                .staleNavigationSnapshot,
                .staleCapabilities,
                .staleAuthority,
                .stalePublicationTarget,
                .cancelledBeforePublication,
                .contractUnsupported,
                .limitExceeded,
                .inputRejected
            ].contains(code)
        }

        private static func validate(_ staging: StagingReceipt, for plan: Plan) throws {
            try validateItemEvidence(staging.itemEvidence, for: plan)
            guard staging.planningReceipt == plan.receipt,
                staging.itemEvidence.count == plan.actions.count,
                staging.itemEvidence.allSatisfy({
                    if case .stagedReadOnly = $0.disposition { return true }
                    return false
                })
            else {
                throw Error(.invalidExecutionEvidence)
            }
        }

        private static func validate(
            _ diagnostic: ExecutionDiagnostic,
            actionCount: Int
        ) throws {
            let rowScoped: Set<ExecutionDiagnosticCode> = [
                .sourceChanged,
                .authorityUnavailable,
                .sourceOpenFailed,
                .comparisonStagingFailed,
                .blockedByEarlierFailure
            ]
            let sourceScoped: Set<ExecutionDiagnosticCode> = [
                .sourceChanged,
                .authorityUnavailable,
                .sourceOpenFailed
            ]
            guard diagnostic.actionIndex.map({ (0..<actionCount).contains($0) }) ?? true,
                rowScoped.contains(diagnostic.code) == (diagnostic.actionIndex != nil),
                sourceScoped.contains(diagnostic.code) == (diagnostic.side != nil)
            else {
                throw Error(.invalidExecutionEvidence)
            }
        }

    }

    /// App/platform implementation. It must return validated evidence for every planned action.
    public protocol PlanExecutor: Sendable {
        func execute(
            _ plan: Plan,
            validating current: ExecutionValidation
        ) async -> ExecutionOutcome
    }

    public enum Planner: Sendable {
        public static func plan(
            _ request: Request,
            cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
        ) throws -> Plan {
            do {
                try checkCancellation(cancellationCheck)
                try validate(request.limits)
                guard request.folderSnapshot.results.count <= request.limits.maximumSnapshotItems,
                    request.navigationSnapshot.items.count <= request.limits.maximumSnapshotItems
                else {
                    throw Error(
                        .tooManySnapshotItems,
                        limit: .snapshotItems,
                        maximum: UInt64(request.limits.maximumSnapshotItems)
                    )
                }
                guard !request.selectedItemIdentities.isEmpty else {
                    throw Error(.emptySelection)
                }
                guard request.selectedItemIdentities.count <= request.limits.maximumSelectedItems else {
                    throw Error(
                        .tooManySelectedItems,
                        limit: .selectedItems,
                        maximum: UInt64(request.limits.maximumSelectedItems)
                    )
                }
                guard request.publicationTarget.revision < UInt64.max else {
                    throw Error(.publicationRevisionOverflow)
                }
                try validateSelection(
                    request.selectedItemIdentities,
                    snapshot: request.navigationSnapshot,
                    cancellationCheckInterval: request.limits.cancellationCheckInterval,
                    cancellationCheck: cancellationCheck
                )

                try validateCapabilities(
                    folder: request.folderCapabilities,
                    executor: request.executorCapabilities
                )
                var meter = WorkMeter(
                    limits: request.limits,
                    cancellationCheck: cancellationCheck
                )
                for _ in request.selectedItemIdentities {
                    try meter.consume()
                }
                let folderReference = try folderReference(
                    request.folderSnapshot,
                    limits: request.folderValidationLimits,
                    cancellationCheck: cancellationCheck,
                    meter: &meter
                )
                guard folderReference == request.expectedFolderSnapshot else {
                    throw Error(.staleFolderSnapshot)
                }
                let navigationReference = try navigationReference(
                    request.navigationSnapshot,
                    meter: &meter
                )
                guard navigationReference == request.expectedNavigationSnapshot else {
                    throw Error(.staleNavigationSnapshot)
                }
                let authorityState = try canonicalAuthorityBindings(
                    request.authorityBindings,
                    folderSnapshot: request.folderSnapshot,
                    navigationSnapshot: request.navigationSnapshot,
                    meter: &meter
                )
                let authorityBindings = authorityState.bindings
                try validateRootBinding(
                    folderSnapshot: request.folderSnapshot,
                    navigationSnapshot: request.navigationSnapshot,
                    meter: &meter
                )
                var folderIndicesByResultID: [SelectedFilePairOpenExactResultID: Int] = [:]
                folderIndicesByResultID.reserveCapacity(request.folderSnapshot.results.count)
                for index in request.folderSnapshot.results.indices {
                    try meter.consume()
                    let resultID = request.folderSnapshot.results[index].id
                    try account(resultID, meter: &meter)
                    let id = SelectedFilePairOpenExactResultID(resultID)
                    guard folderIndicesByResultID.updateValue(index, forKey: id) == nil else {
                        throw Error(.invalidFolderSnapshot)
                    }
                }
                var itemsByIdentity: [ComparedFileNavigationItemIdentity: ComparedFileNavigationItem] = [:]
                itemsByIdentity.reserveCapacity(request.navigationSnapshot.items.count)
                for item in request.navigationSnapshot.items {
                    try meter.consume()
                    guard itemsByIdentity.updateValue(item, forKey: item.identity) == nil else {
                        throw Error(.invalidNavigationSnapshot)
                    }
                }

                var selectedItemsByIdentity: [ComparedFileNavigationItemIdentity: ComparedFileNavigationItem] = [:]
                selectedItemsByIdentity.reserveCapacity(request.selectedItemIdentities.count)
                for identity in request.selectedItemIdentities {
                    try meter.consume()
                    guard let item = itemsByIdentity[identity] else {
                        throw Error(.unknownSelection, itemIdentity: identity)
                    }
                    selectedItemsByIdentity[identity] = item
                }
                var selectedItems: [ComparedFileNavigationItem] = []
                selectedItems.reserveCapacity(selectedItemsByIdentity.count)
                for item in request.navigationSnapshot.items {
                    try meter.consume()
                    if selectedItemsByIdentity[item.identity] != nil {
                        selectedItems.append(item)
                    }
                }
                guard selectedItems.count == selectedItemsByIdentity.count else {
                    throw Error(.unknownSelection)
                }

                let bindingsBySide = Dictionary(
                    uniqueKeysWithValues: authorityBindings.map { ($0.side, $0) }
                )
                var physicalSources: Set<PhysicalSourceIdentity> = []
                var visibleOrdinals: Set<Int> = []
                var actions: [Action] = []
                actions.reserveCapacity(selectedItems.count)
                for item in selectedItems {
                    try meter.consume()
                    guard item.visibility == .visible, let visibleOrdinal = item.visibleOrdinal else {
                        throw Error(.selectedItemNotVisible, itemIdentity: item.identity)
                    }
                    guard visibleOrdinals.insert(visibleOrdinal).inserted else {
                        throw Error(.duplicateVisibleOrder, itemIdentity: item.identity)
                    }
                    guard
                        let folderIndex = folderIndicesByResultID[
                            SelectedFilePairOpenExactResultID(item.resultID)
                        ],
                        request.folderSnapshot.results.indices.contains(folderIndex),
                        request.folderSnapshot.resultRevisions.indices.contains(folderIndex)
                    else {
                        throw Error(.invalidResultBinding, itemIdentity: item.identity)
                    }
                    let result = request.folderSnapshot.results[folderIndex]
                    let resultRevision = request.folderSnapshot.resultRevisions[folderIndex]
                    try validateEligible(
                        item,
                        result: result,
                        revision: resultRevision,
                        roots: request.folderSnapshot.roots,
                        meter: &meter
                    )
                    guard let leftMetadata = result.left,
                        let rightMetadata = result.right,
                        let leftRevision = resultRevision.left,
                        let rightRevision = resultRevision.right,
                        let leftAuthority = bindingsBySide[.left],
                        let rightAuthority = bindingsBySide[.right],
                        let leftNavigationAuthority = authorityState.navigationAuthorities[.left],
                        let rightNavigationAuthority = authorityState.navigationAuthorities[.right]
                    else {
                        throw Error(.invalidAuthorityBinding, itemIdentity: item.identity)
                    }
                    for revision in [leftRevision, rightRevision] {
                        try meter.consume()
                        let physical = PhysicalSourceIdentity(revision)
                        guard physicalSources.insert(physical).inserted else {
                            throw Error(.duplicateSourceAlias, itemIdentity: item.identity)
                        }
                    }
                    let left = SourceBinding(
                        side: .left,
                        root: request.folderSnapshot.roots.left,
                        relativePath: leftMetadata.relativePath,
                        revision: leftRevision,
                        authority: leftAuthority,
                        navigationAuthority: leftNavigationAuthority
                    )
                    let right = SourceBinding(
                        side: .right,
                        root: request.folderSnapshot.roots.right,
                        relativePath: rightMetadata.relativePath,
                        revision: rightRevision,
                        authority: rightAuthority,
                        navigationAuthority: rightNavigationAuthority
                    )
                    try account(left, meter: &meter)
                    try account(right, meter: &meter)
                    let actionIndex = actions.count
                    let actionDigest = try actionSHA256(
                        index: actionIndex,
                        visibleOrdinal: visibleOrdinal,
                        itemIdentity: item.identity,
                        resultID: item.resultID,
                        left: left,
                        right: right,
                        meter: &meter
                    )
                    actions.append(
                        Action(
                            index: actionIndex,
                            visibleOrdinal: visibleOrdinal,
                            itemIdentity: item.identity,
                            resultID: item.resultID,
                            left: left,
                            right: right,
                            actionSHA256: actionDigest
                        )
                    )
                }
                let planSHA256 = try planSHA256(
                    folderSnapshot: folderReference,
                    navigationSnapshot: navigationReference,
                    actions: actions,
                    authorityBindings: authorityBindings,
                    folderCapabilities: request.folderCapabilities,
                    executorCapabilities: request.executorCapabilities,
                    publicationTarget: request.publicationTarget,
                    folderValidationLimits: request.folderValidationLimits,
                    limits: request.limits,
                    meter: &meter
                )
                try meter.finish()
                let receipt = PlanningReceipt(
                    planSHA256: planSHA256,
                    folderSnapshot: folderReference,
                    navigationSnapshot: navigationReference,
                    selectedItemCount: actions.count,
                    actionSHA256s: actions.map(\.actionSHA256),
                    planningWorkUnits: meter.consumed
                )
                return Plan(
                    folderSnapshot: folderReference,
                    navigationSnapshot: navigationReference,
                    actions: actions,
                    authorityBindings: authorityBindings,
                    folderCapabilities: request.folderCapabilities,
                    executorCapabilities: request.executorCapabilities,
                    publicationTarget: request.publicationTarget,
                    folderValidationLimits: request.folderValidationLimits,
                    limits: request.limits,
                    receipt: receipt
                )
            } catch let error as Error {
                throw error
            } catch is CancellationError {
                throw Error(.cancelled)
            } catch {
                throw Error(.invalidFolderSnapshot)
            }
        }

        public static func validate(
            _ plan: Plan,
            against current: ExecutionValidation,
            cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
        ) throws -> ExecutionLease {
            try validateCurrent(
                plan,
                against: current,
                phase: .staging,
                cancellationCheck: cancellationCheck
            )
        }

        fileprivate static func validateCurrent(
            _ plan: Plan,
            against current: ExecutionValidation,
            phase: ExecutionPhase,
            stagingAttemptIdentity: UUID? = nil,
            cancellationCheck: @escaping CancellationCheck
        ) throws -> ExecutionLease {
            do {
                try checkCancellation(cancellationCheck)
                try validate(plan.limits)
                guard current.folderCapabilities == plan.folderCapabilities,
                    current.executorCapabilities == plan.executorCapabilities
                else {
                    throw Error(.staleCapabilities)
                }
                guard current.publicationTarget == plan.publicationTarget else {
                    throw Error(.stalePublicationTarget)
                }
                guard current.folderSnapshot.results.count <= plan.limits.maximumSnapshotItems,
                    current.navigationSnapshot.items.count <= plan.limits.maximumSnapshotItems
                else {
                    throw Error(
                        .tooManySnapshotItems,
                        limit: .snapshotItems,
                        maximum: UInt64(plan.limits.maximumSnapshotItems)
                    )
                }
                var meter = WorkMeter(
                    limits: plan.limits,
                    cancellationCheck: cancellationCheck
                )
                let currentFolder = try folderReference(
                    current.folderSnapshot,
                    limits: plan.folderValidationLimits,
                    cancellationCheck: cancellationCheck,
                    meter: &meter
                )
                guard currentFolder == plan.folderSnapshot else {
                    throw Error(.staleFolderSnapshot)
                }
                let currentNavigation = try navigationReference(
                    current.navigationSnapshot,
                    meter: &meter
                )
                guard currentNavigation == plan.navigationSnapshot else {
                    throw Error(.staleNavigationSnapshot)
                }
                let currentBindings = try canonicalAuthorityBindings(
                    current.authorityBindings,
                    folderSnapshot: current.folderSnapshot,
                    navigationSnapshot: current.navigationSnapshot,
                    meter: &meter
                ).bindings
                guard currentBindings == plan.authorityBindings else {
                    throw Error(.staleAuthorityBinding)
                }
                try validateRootBinding(
                    folderSnapshot: current.folderSnapshot,
                    navigationSnapshot: current.navigationSnapshot,
                    meter: &meter
                )
                try validateReceipt(plan, meter: &meter)
                try meter.finish()
                guard (phase == .staging) == (stagingAttemptIdentity == nil) else {
                    throw Error(.invalidExecutionEvidence)
                }
                return ExecutionLease(
                    plan: plan,
                    phase: phase,
                    stagingAttemptIdentity: stagingAttemptIdentity
                )
            } catch let error as Error {
                throw error
            } catch is CancellationError {
                throw Error(.cancelled)
            } catch {
                throw Error(.staleFolderSnapshot)
            }
        }

        public static func navigationReference(
            to snapshot: ComparedFileNavigationSnapshot,
            limits: Limits = .default,
            cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
        ) throws -> NavigationSnapshotReference {
            do {
                try checkCancellation(cancellationCheck)
                try validate(limits)
                var meter = WorkMeter(limits: limits, cancellationCheck: cancellationCheck)
                let reference = try navigationReference(snapshot, meter: &meter)
                try meter.finish()
                return reference
            } catch let error as Error {
                throw error
            } catch is CancellationError {
                throw Error(.cancelled)
            } catch {
                throw Error(.invalidNavigationSnapshot)
            }
        }
    }
}

extension FolderComparisonWorkflowPlanner {
    fileprivate static func reference(
        to snapshot: FolderComparisonWorkflowSnapshot,
        limits: FolderComparisonWorkflowLimits,
        cancellationCheck: SelectedFilePairOpenWorkflow.CancellationCheck
    ) throws -> FolderComparisonWorkflowSnapshotReference {
        try SelectedFilePairOpenWorkflow.Planner.checkCancellation(cancellationCheck)
        let state = SelectedFilePairOpenFolderReferenceState()
        let task = Task.detached {
            do {
                let reference = try FolderComparisonWorkflowPlanner.reference(
                    to: snapshot,
                    limits: limits
                )
                state.complete(with: .success(reference))
            } catch {
                state.complete(with: .failure(error))
            }
        }
        do {
            while true {
                if let result = state.waitForResult() {
                    try SelectedFilePairOpenWorkflow.Planner.checkCancellation(cancellationCheck)
                    return try result.get()
                }
                try SelectedFilePairOpenWorkflow.Planner.checkCancellation(cancellationCheck)
            }
        } catch {
            task.cancel()
            throw error
        }
    }
}

extension SelectedFilePairOpenWorkflow.Planner {
    fileprivate typealias Workflow = SelectedFilePairOpenWorkflow

    fileprivate static func validate(_ limits: Workflow.Limits) throws {
        guard (1...Workflow.Limits.hardMaximumSnapshotItems).contains(limits.maximumSnapshotItems) else {
            throw Workflow.Error(.invalidLimit, limit: .snapshotItems)
        }
        guard (1...Workflow.Limits.hardMaximumSelectedItems).contains(limits.maximumSelectedItems),
            limits.maximumSelectedItems <= limits.maximumSnapshotItems
        else {
            throw Workflow.Error(.invalidLimit, limit: .selectedItems)
        }
        guard (1...Workflow.Limits.hardMaximumStringUTF8Bytes).contains(limits.maximumStringUTF8Bytes) else {
            throw Workflow.Error(.invalidLimit, limit: .stringUTF8Bytes)
        }
        guard limits.maximumTotalStringUTF8Bytes >= limits.maximumStringUTF8Bytes,
            limits.maximumTotalStringUTF8Bytes <= Workflow.Limits.hardMaximumTotalStringUTF8Bytes
        else {
            throw Workflow.Error(.invalidLimit, limit: .totalStringUTF8Bytes)
        }
        guard (1...Workflow.Limits.hardMaximumWorkUnits).contains(limits.maximumWorkUnits) else {
            throw Workflow.Error(.invalidLimit, limit: .workUnits)
        }
        guard
            (1...Workflow.Limits.hardMaximumCancellationCheckInterval)
                .contains(limits.cancellationCheckInterval)
        else {
            throw Workflow.Error(.invalidLimit, limit: .cancellationCheckInterval)
        }
    }

    fileprivate static func validateCapabilities(
        folder: FolderComparisonWorkflowCapabilities,
        executor: Workflow.ExecutorCapabilities
    ) throws {
        guard folder.features.contains(.openFilePair) else {
            throw Workflow.Error(.unsupportedCapability)
        }
        let required: Set<Workflow.ExecutorFeature> = [
            .stageReadOnlyTextComparison,
            .publishAtomicComparisonBatch,
            .reportEverySelectedItem
        ]
        guard executor.features.isSuperset(of: required) else {
            throw Workflow.Error(.unsupportedCapability)
        }
    }

    fileprivate static func folderReference(
        _ snapshot: FolderComparisonWorkflowSnapshot,
        limits: FolderComparisonWorkflowLimits,
        cancellationCheck: Workflow.CancellationCheck,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws -> FolderComparisonWorkflowSnapshotReference {
        do {
            try checkCancellation(cancellationCheck)
            try meter.consume(UInt64(snapshot.results.count + snapshot.resultRevisions.count + 1))
            for result in snapshot.results {
                try meter.consume()
                try account(result.id, meter: &meter)
                if let left = result.left { try meter.measure(left.relativePath) }
                if let right = result.right { try meter.measure(right.relativePath) }
            }
            let reference = try FolderComparisonWorkflowPlanner.reference(
                to: snapshot,
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try checkCancellation(cancellationCheck)
            return reference
        } catch let error as Workflow.Error {
            throw error
        } catch FolderComparisonWorkflowError.cancelled {
            throw Workflow.Error(.cancelled)
        } catch FolderComparisonWorkflowError.invalidLimit(let limit, _) {
            throw Workflow.Error(.invalidLimit, limit: workflowLimit(limit))
        } catch FolderComparisonWorkflowError.workLimitExceeded(let maximum) {
            throw Workflow.Error(.workLimitExceeded, limit: .workUnits, maximum: maximum)
        } catch FolderComparisonWorkflowError.tooManyResults(let maximum) {
            throw Workflow.Error(
                .tooManySnapshotItems,
                limit: .snapshotItems,
                maximum: UInt64(maximum)
            )
        } catch FolderComparisonWorkflowError.stringTooLarge(let maximum) {
            throw Workflow.Error(
                .stringLimitExceeded,
                limit: .stringUTF8Bytes,
                maximum: UInt64(maximum)
            )
        } catch FolderComparisonWorkflowError.totalStringsTooLarge(let maximum) {
            throw Workflow.Error(
                .totalStringLimitExceeded,
                limit: .totalStringUTF8Bytes,
                maximum: UInt64(maximum)
            )
        } catch {
            throw Workflow.Error(.invalidFolderSnapshot)
        }
    }

    fileprivate static func workflowLimit(
        _ limit: FolderComparisonWorkflowLimit
    ) -> Workflow.Limit? {
        switch limit {
        case .resultItems: .snapshotItems
        case .selectedItems: .selectedItems
        case .stringUTF8Bytes: .stringUTF8Bytes
        case .totalStringUTF8Bytes: .totalStringUTF8Bytes
        case .workUnits: .workUnits
        case .cancellationCheckInterval: .cancellationCheckInterval
        case .operationActions, .presentationRows, .columns, .sortDescriptors, .filterRules,
            .metadataDigestBytes:
            nil
        }
    }

    fileprivate static func validateRootBinding(
        folderSnapshot: FolderComparisonWorkflowSnapshot,
        navigationSnapshot: ComparedFileNavigationSnapshot,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws {
        let pairs = [
            (Workflow.Side.left, folderSnapshot.roots.left.requestedURL, navigationSnapshot.leftRoot),
            (Workflow.Side.right, folderSnapshot.roots.right.requestedURL, navigationSnapshot.rightRoot)
        ]
        for (side, folderURL, navigationURL) in pairs {
            guard try exactURL(folderURL, navigationURL, meter: &meter) else {
                throw Workflow.Error(.invalidRootBinding, side: side)
            }
        }
    }

    fileprivate static func canonicalAuthorityBindings(
        _ bindings: [Workflow.AuthorityBinding],
        folderSnapshot: FolderComparisonWorkflowSnapshot,
        navigationSnapshot: ComparedFileNavigationSnapshot,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws -> (
        bindings: [Workflow.AuthorityBinding],
        navigationAuthorities: [Workflow.Side: ComparedFileNavigationRootAuthority]
    ) {
        guard bindings.count == Workflow.Side.allCases.count else {
            throw Workflow.Error(.invalidAuthorityBinding)
        }
        let navigationAuthorities = try canonicalNavigationAuthorities(
            navigationSnapshot.authorities,
            meter: &meter
        )
        var seenSides: Set<Workflow.Side> = []
        var seenFolderAuthorities: Set<UUID> = []
        var seenNavigationAuthorities: Set<ComparedFileNavigationAuthorityIdentity> = []
        var bindingsBySide: [Workflow.Side: Workflow.AuthorityBinding] = [:]
        for binding in bindings {
            try meter.consume()
            guard seenSides.insert(binding.side).inserted,
                seenFolderAuthorities.insert(binding.folderAuthorityIdentity).inserted,
                seenNavigationAuthorities.insert(binding.navigationAuthorityIdentity).inserted
            else {
                throw Workflow.Error(.duplicateAuthorityBinding, side: binding.side)
            }
            let root = folderSnapshot.roots[binding.side.folderSide]
            guard root.authority.identity == binding.folderAuthorityIdentity,
                root.authority.revision == binding.folderAuthorityRevision,
                root.authority.permissions.contains(.readContent),
                root.authority.coverage == .directoryTree,
                let navigationAuthority = navigationAuthorities[binding.side],
                navigationAuthority.identity == binding.navigationAuthorityIdentity,
                navigationAuthority.capabilities.contains(.readRegularFile),
                try exactURL(
                    navigationAuthority.rootURL,
                    root.requestedURL,
                    meter: &meter
                )
            else {
                throw Workflow.Error(.invalidAuthorityBinding, side: binding.side)
            }
            bindingsBySide[binding.side] = binding
        }
        return (
            Workflow.Side.allCases.compactMap { bindingsBySide[$0] },
            navigationAuthorities
        )
    }

    fileprivate static func canonicalNavigationAuthorities(
        _ authorities: [ComparedFileNavigationRootAuthority],
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws -> [Workflow.Side: ComparedFileNavigationRootAuthority] {
        guard authorities.count == Workflow.Side.allCases.count else {
            throw Workflow.Error(.invalidAuthorityBinding)
        }
        var seenIdentities: Set<ComparedFileNavigationAuthorityIdentity> = []
        var authoritiesBySide: [Workflow.Side: ComparedFileNavigationRootAuthority] = [:]
        for authority in authorities {
            try meter.consume(UInt64(authority.capabilities.count + 1))
            try meter.measure(authority.rootURL.absoluteString)
            let side: Workflow.Side = authority.side == .left ? .left : .right
            guard seenIdentities.insert(authority.identity).inserted,
                authoritiesBySide.updateValue(authority, forKey: side) == nil
            else {
                throw Workflow.Error(.duplicateAuthorityBinding, side: side)
            }
        }
        guard authoritiesBySide.count == Workflow.Side.allCases.count else {
            throw Workflow.Error(.invalidAuthorityBinding)
        }
        return authoritiesBySide
    }

    fileprivate static func validateSelection(
        _ selection: [ComparedFileNavigationItemIdentity],
        snapshot: ComparedFileNavigationSnapshot,
        cancellationCheckInterval: UInt64,
        cancellationCheck: Workflow.CancellationCheck
    ) throws {
        var seen: Set<ComparedFileNavigationItemIdentity> = []
        seen.reserveCapacity(selection.count)
        var unitsSinceCancellation: UInt64 = 0
        for identity in selection {
            unitsSinceCancellation += 1
            if unitsSinceCancellation == cancellationCheckInterval {
                try checkCancellation(cancellationCheck)
                unitsSinceCancellation = 0
            }
            guard seen.insert(identity).inserted else {
                throw Workflow.Error(.duplicateSelection, itemIdentity: identity)
            }
        }
        if seen != snapshot.selectedItemIdentities {
            var unmatched = seen
            for item in snapshot.items {
                unitsSinceCancellation += 1
                if unitsSinceCancellation == cancellationCheckInterval {
                    try checkCancellation(cancellationCheck)
                    unitsSinceCancellation = 0
                }
                unmatched.remove(item.identity)
                if unmatched.isEmpty { break }
            }
            if let identity = selection.first(where: unmatched.contains) {
                throw Workflow.Error(.unknownSelection, itemIdentity: identity)
            }
            throw Workflow.Error(.selectionMismatch)
        }
    }

    fileprivate static func validateEligible(
        _ item: ComparedFileNavigationItem,
        result: DirectoryResult,
        revision: FolderComparisonResultRevision,
        roots: FolderComparisonRootPair,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws {
        guard exactID(item.resultID, result.id),
            exactID(result.id, revision.id),
            exactMetadata(item.left, result.left),
            exactMetadata(item.right, result.right),
            item.status == result.status
        else {
            throw Workflow.Error(.invalidResultBinding, itemIdentity: item.identity)
        }
        guard item.visibility == .visible,
            item.visibleOrdinal != nil,
            item.isNavigable,
            result.left?.kind == .file,
            result.right?.kind == .file
        else {
            throw Workflow.Error(.selectedItemIneligible, itemIdentity: item.identity)
        }
        switch (item.comparisonState, item.availability.requiredCapability, result.status) {
        case (.identical, .identicalRegularFilePair, .identical),
            (.different, .differentRegularFilePair, .different):
            break
        default:
            throw Workflow.Error(.selectedItemIneligible, itemIdentity: item.identity)
        }
        guard let left = result.left,
            let right = result.right,
            let leftRevision = revision.left,
            let rightRevision = revision.right,
            leftRevision.kind == .file,
            rightRevision.kind == .file,
            leftRevision.identity.relativePath.utf8.elementsEqual(left.relativePath.utf8),
            rightRevision.identity.relativePath.utf8.elementsEqual(right.relativePath.utf8),
            leftRevision.identity.rootIdentity == roots.left.revision.identity,
            rightRevision.identity.rootIdentity == roots.right.revision.identity
        else {
            throw Workflow.Error(.invalidItemRevision, itemIdentity: item.identity)
        }
        try meter.consume(UInt64(left.relativePath.utf8.count + right.relativePath.utf8.count + 1))
    }

    fileprivate static func account(
        _ source: Workflow.SourceBinding,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws {
        try meter.measure(source.relativePath)
        try meter.measure(source.root.requestedURL.absoluteString)
        try meter.measure(source.root.revision.identity.canonicalURL.absoluteString)
        try meter.measure(source.revision.identity.relativePath)
        try meter.measure(source.navigationAuthority.rootURL.absoluteString)
        if case .securityScoped(let resourceURL, _) = source.root.authority.acquisition {
            try meter.measure(resourceURL.absoluteString)
        }
        let digestBytes =
            source.root.revision.metadataSHA256.count
            + source.revision.metadataSHA256.count
            + (source.revision.contentSHA256?.count ?? 0)
        try meter.consume(UInt64(digestBytes + 256))
    }

    fileprivate static func account(
        _ id: DirectoryResult.ID,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws {
        if let left = id.leftRelativePath { try meter.measure(left) }
        if let right = id.rightRelativePath { try meter.measure(right) }
    }

    fileprivate static func accountHash(
        _ source: Workflow.SourceBinding,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws {
        var strings = [
            source.relativePath,
            source.root.requestedURL.absoluteString,
            source.root.revision.identity.canonicalURL.absoluteString,
            source.revision.identity.relativePath,
            source.navigationAuthority.rootURL.absoluteString
        ]
        if case .securityScoped(let resourceURL, _) = source.root.authority.acquisition {
            strings.append(resourceURL.absoluteString)
        }
        for string in strings {
            for _ in string.utf8 { try meter.consume() }
        }
        try meter.consume(
            UInt64(
                source.root.revision.metadataSHA256.count
                    + source.revision.metadataSHA256.count
                    + (source.revision.contentSHA256?.count ?? 0)
                    + 512
            )
        )
    }

    fileprivate static func navigationReference(
        _ snapshot: ComparedFileNavigationSnapshot,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws -> Workflow.NavigationSnapshotReference {
        try validateNavigationSnapshot(
            snapshot,
            cancellationCheck: meter.cancellationCheck
        )
        guard snapshot.items.count <= meter.limits.maximumSnapshotItems else {
            throw Workflow.Error(
                .tooManySnapshotItems,
                limit: .snapshotItems,
                maximum: UInt64(meter.limits.maximumSnapshotItems)
            )
        }
        var digest = SelectedFilePairOpenCanonicalDigest()
        digest.append("selected-file-pair-navigation-snapshot-v1")
        append(snapshot.reference, to: &digest)
        try append(snapshot.leftRoot, to: &digest, meter: &meter)
        try append(snapshot.rightRoot, to: &digest, meter: &meter)
        digest.append(snapshot.items.count)
        var visibleOrdinal = 0
        var itemIdentities: Set<ComparedFileNavigationItemIdentity> = []
        var resultIDs: Set<SelectedFilePairOpenExactResultID> = []
        for (index, item) in snapshot.items.enumerated() {
            try meter.consume()
            try account(item.resultID, meter: &meter)
            guard item.ordinal == index,
                itemIdentities.insert(item.identity).inserted,
                resultIDs.insert(SelectedFilePairOpenExactResultID(item.resultID)).inserted
            else {
                throw Workflow.Error(.invalidNavigationSnapshot, itemIdentity: item.identity)
            }
            if item.visibility == .visible {
                guard item.visibleOrdinal == visibleOrdinal else {
                    throw Workflow.Error(.duplicateVisibleOrder, itemIdentity: item.identity)
                }
                visibleOrdinal += 1
            } else if item.visibleOrdinal != nil {
                throw Workflow.Error(.invalidNavigationSnapshot, itemIdentity: item.identity)
            }
            try append(item, to: &digest, meter: &meter)
        }
        let statusValues = snapshot.filter.statuses.sorted { $0.rawValue < $1.rawValue }
        digest.append(statusValues.count)
        for status in statusValues { digest.append(status.rawValue) }
        try digest.append(snapshot.filter.pathQuery, meter: &meter)
        let kindValues = snapshot.filter.kinds.sorted { $0.rawValue < $1.rawValue }
        digest.append(kindValues.count)
        for kind in kindValues { digest.append(kind.rawValue) }
        append(snapshot.filter.hidden, to: &digest)
        guard snapshot.sortDescriptors.count <= snapshot.limits.maximumSortDescriptorCount,
            snapshot.sortDescriptors.count
                <= ComparedFileNavigationLimits.hardMaximumSortDescriptorCount
        else {
            throw Workflow.Error(.invalidNavigationSnapshot)
        }
        digest.append(snapshot.sortDescriptors.count)
        for descriptor in snapshot.sortDescriptors {
            try meter.consume()
            append(descriptor.key, to: &digest)
            append(descriptor.order, to: &digest)
        }
        guard snapshot.selectedItemIdentities.count <= snapshot.items.count,
            snapshot.selectedItemIdentities.count <= snapshot.limits.maximumItemCount,
            snapshot.selectedItemIdentities.count <= meter.limits.maximumSnapshotItems
        else {
            throw Workflow.Error(.invalidNavigationSnapshot)
        }
        var orderedSelected: [ComparedFileNavigationItemIdentity] = []
        orderedSelected.reserveCapacity(snapshot.selectedItemIdentities.count)
        for item in snapshot.items {
            try meter.consume()
            if snapshot.selectedItemIdentities.contains(item.identity) {
                orderedSelected.append(item.identity)
            }
        }
        guard orderedSelected.count == snapshot.selectedItemIdentities.count else {
            throw Workflow.Error(.invalidNavigationSnapshot)
        }
        digest.append(orderedSelected.count)
        for identity in orderedSelected { digest.append(identity.rawValue) }
        digest.append(snapshot.cursorItemIdentity != nil)
        if let cursor = snapshot.cursorItemIdentity { digest.append(cursor.rawValue) }
        digest.append(snapshot.authorities.count)
        var authorityIdentities: Set<ComparedFileNavigationAuthorityIdentity> = []
        var authoritySides: Set<ComparedFileNavigationSide> = []
        for authority in snapshot.authorities {
            try meter.consume(UInt64(authority.capabilities.count + 1))
            guard authorityIdentities.insert(authority.identity).inserted,
                authoritySides.insert(authority.side).inserted
            else {
                throw Workflow.Error(.invalidNavigationSnapshot)
            }
            digest.append(authority.identity.rawValue)
            digest.append(authority.side.rawValue)
            try append(authority.rootURL, to: &digest, meter: &meter)
            let capabilities = authority.capabilities.sorted { $0.rawValue < $1.rawValue }
            digest.append(capabilities.count)
            for capability in capabilities { digest.append(capability.rawValue) }
        }
        guard authoritySides == Set(ComparedFileNavigationSide.allCases) else {
            throw Workflow.Error(.invalidNavigationSnapshot)
        }
        let openCapabilities = snapshot.openCapabilities.sorted { $0.rawValue < $1.rawValue }
        digest.append(openCapabilities.count)
        for capability in openCapabilities { digest.append(capability.rawValue) }
        append(snapshot.limits, to: &digest)
        return Workflow.NavigationSnapshotReference(
            folderResults: snapshot.reference,
            stateSHA256: digest.finalize()
        )
    }

    fileprivate static func validateNavigationSnapshot(
        _ snapshot: ComparedFileNavigationSnapshot,
        cancellationCheck: @escaping Workflow.CancellationCheck
    ) throws {
        let limits = snapshot.limits
        guard
            (0...ComparedFileNavigationLimits.hardMaximumItemCount)
                .contains(limits.maximumItemCount),
            (0...ComparedFileNavigationLimits.hardMaximumSortDescriptorCount)
                .contains(limits.maximumSortDescriptorCount),
            (1...ComparedFileNavigationLimits.hardMaximumStringUTF8Bytes)
                .contains(limits.maximumStringUTF8Bytes),
            limits.maximumTotalStringUTF8Bytes >= limits.maximumStringUTF8Bytes,
            limits.maximumTotalStringUTF8Bytes
                <= ComparedFileNavigationLimits.hardMaximumTotalStringUTF8Bytes,
            (1...ComparedFileNavigationLimits.hardMaximumWorkUnits)
                .contains(limits.maximumWorkUnits),
            (1...ComparedFileNavigationLimits.hardMaximumCancellationCheckInterval)
                .contains(limits.cancellationCheckInterval),
            snapshot.items.count <= limits.maximumItemCount,
            snapshot.sortDescriptors.count <= limits.maximumSortDescriptorCount,
            snapshot.selectedItemIdentities.count <= snapshot.items.count,
            snapshot.authorities.count == Workflow.Side.allCases.count
        else {
            throw Workflow.Error(.invalidNavigationSnapshot)
        }

        var meter = SelectedFilePairOpenNavigationWorkMeter(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try meter.measure(snapshot.leftRoot.absoluteString)
        try meter.measure(snapshot.rightRoot.absoluteString)
        try meter.consume(3)
        for item in snapshot.items {
            try meter.consume(14)
            try meter.measure(item.resultID.leftRelativePath)
            try meter.measure(item.resultID.rightRelativePath)
            try meter.measure(item.left?.relativePath)
            try meter.measure(item.right?.relativePath)
        }
        try meter.measure(snapshot.filter.pathQuery)
        var collectionWork = snapshot.filter.statuses.count
        collectionWork += snapshot.filter.kinds.count
        collectionWork += snapshot.sortDescriptors.count * 2
        collectionWork += snapshot.selectedItemIdentities.count
        collectionWork += snapshot.cursorItemIdentity == nil ? 0 : 1
        try meter.consume(collectionWork)
        for authority in snapshot.authorities {
            try meter.consume(authority.capabilities.count + 2)
            try meter.measure(authority.rootURL.absoluteString)
        }
        try meter.consume(snapshot.openCapabilities.count + 6)
        try meter.finish()
    }

    fileprivate static func actionSHA256(
        index: Int,
        visibleOrdinal: Int,
        itemIdentity: ComparedFileNavigationItemIdentity,
        resultID: DirectoryResult.ID,
        left: Workflow.SourceBinding,
        right: Workflow.SourceBinding,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws -> Data {
        try accountHash(left, meter: &meter)
        try accountHash(right, meter: &meter)
        var digest = SelectedFilePairOpenCanonicalDigest()
        digest.append("selected-file-pair-open-action-v1")
        digest.append(index)
        digest.append(visibleOrdinal)
        digest.append(itemIdentity.rawValue)
        append(resultID, to: &digest)
        digest.append(Workflow.Intent.readOnlyTextComparison.rawValue)
        digest.append(UnifiedOpenWorkflow.ComparisonMode.text.rawValue)
        append(left, to: &digest)
        append(right, to: &digest)
        return digest.finalize()
    }

    fileprivate static func planSHA256(
        folderSnapshot: FolderComparisonWorkflowSnapshotReference,
        navigationSnapshot: Workflow.NavigationSnapshotReference,
        actions: [Workflow.Action],
        authorityBindings: [Workflow.AuthorityBinding],
        folderCapabilities: FolderComparisonWorkflowCapabilities,
        executorCapabilities: Workflow.ExecutorCapabilities,
        publicationTarget: Workflow.PublicationTarget,
        folderValidationLimits: FolderComparisonWorkflowLimits,
        limits: Workflow.Limits,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws -> Data {
        try meter.consume(1_024)
        var digest = SelectedFilePairOpenCanonicalDigest()
        digest.append("selected-file-pair-open-plan-v1")
        append(folderSnapshot, to: &digest)
        append(navigationSnapshot, to: &digest)
        digest.append(actions.count)
        for action in actions {
            try meter.consume(UInt64(action.actionSHA256.count + 1))
            digest.append(action.actionSHA256)
        }
        digest.append(authorityBindings.count)
        for binding in authorityBindings {
            try meter.consume(4)
            append(binding, to: &digest)
        }
        append(folderCapabilities, to: &digest)
        append(executorCapabilities, to: &digest)
        append(publicationTarget, to: &digest)
        digest.append(Workflow.FailurePolicy.stageAllThenPublishAllOrNone.rawValue)
        append(folderValidationLimits, to: &digest)
        append(limits, to: &digest)
        append(Workflow.ExecutorContract.required, to: &digest)
        return digest.finalize()
    }

    fileprivate static func validateReceipt(
        _ plan: Workflow.Plan,
        meter: inout SelectedFilePairOpenWorkMeter
    ) throws {
        let expectedSHA256 = try planSHA256(
            folderSnapshot: plan.folderSnapshot,
            navigationSnapshot: plan.navigationSnapshot,
            actions: plan.actions,
            authorityBindings: plan.authorityBindings,
            folderCapabilities: plan.folderCapabilities,
            executorCapabilities: plan.executorCapabilities,
            publicationTarget: plan.publicationTarget,
            folderValidationLimits: plan.folderValidationLimits,
            limits: plan.limits,
            meter: &meter
        )
        guard plan.actions.count == plan.receipt.selectedItemCount,
            plan.actions.map(\.actionSHA256) == plan.receipt.actionSHA256s,
            plan.folderSnapshot == plan.receipt.folderSnapshot,
            plan.navigationSnapshot == plan.receipt.navigationSnapshot,
            plan.receipt.planSHA256 == expectedSHA256
        else {
            throw Workflow.Error(.receiptMismatch)
        }
    }

    fileprivate static func checkCancellation(_ cancellationCheck: Workflow.CancellationCheck) throws {
        do {
            try cancellationCheck()
        } catch {
            throw Workflow.Error(.cancelled)
        }
    }
}

private struct SelectedFilePairOpenWorkMeter {
    typealias Workflow = SelectedFilePairOpenWorkflow

    let limits: Workflow.Limits
    let cancellationCheck: Workflow.CancellationCheck
    private(set) var consumed: UInt64 = 0
    private(set) var totalStringUTF8Bytes = 0

    mutating func consume(_ amount: UInt64 = 1) throws {
        let (next, overflow) = consumed.addingReportingOverflow(amount)
        guard !overflow, next <= limits.maximumWorkUnits else {
            throw Workflow.Error(
                .workLimitExceeded,
                limit: .workUnits,
                maximum: limits.maximumWorkUnits
            )
        }
        let previousCheck = consumed / limits.cancellationCheckInterval
        consumed = next
        if consumed / limits.cancellationCheckInterval != previousCheck {
            try Workflow.Planner.checkCancellation(cancellationCheck)
        }
    }

    mutating func measure(_ string: String) throws {
        var byteCount = 0
        for _ in string.utf8 {
            try consume()
            guard byteCount < limits.maximumStringUTF8Bytes else {
                throw Workflow.Error(
                    .stringLimitExceeded,
                    limit: .stringUTF8Bytes,
                    maximum: UInt64(limits.maximumStringUTF8Bytes)
                )
            }
            byteCount += 1
        }
        guard totalStringUTF8Bytes <= limits.maximumTotalStringUTF8Bytes - byteCount else {
            throw Workflow.Error(
                .totalStringLimitExceeded,
                limit: .totalStringUTF8Bytes,
                maximum: UInt64(limits.maximumTotalStringUTF8Bytes)
            )
        }
        totalStringUTF8Bytes += byteCount
    }

    func finish() throws {
        try Workflow.Planner.checkCancellation(cancellationCheck)
    }
}

private struct SelectedFilePairOpenNavigationWorkMeter {
    typealias Workflow = SelectedFilePairOpenWorkflow

    let limits: ComparedFileNavigationLimits
    let cancellationCheck: Workflow.CancellationCheck
    private var consumed = 0
    private var totalStringUTF8Bytes = 0

    init(
        limits: ComparedFileNavigationLimits,
        cancellationCheck: @escaping Workflow.CancellationCheck
    ) {
        self.limits = limits
        self.cancellationCheck = cancellationCheck
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            throw Workflow.Error(.invalidNavigationSnapshot)
        }
        let next = consumed.addingReportingOverflow(amount)
        guard !next.overflow, next.partialValue <= limits.maximumWorkUnits else {
            throw Workflow.Error(
                .workLimitExceeded,
                limit: .workUnits,
                maximum: UInt64(limits.maximumWorkUnits)
            )
        }
        let previousCheck = consumed / limits.cancellationCheckInterval
        consumed = next.partialValue
        if consumed / limits.cancellationCheckInterval != previousCheck {
            try Workflow.Planner.checkCancellation(cancellationCheck)
        }
    }

    mutating func measure(_ string: String?) throws {
        guard let string else { return }
        var byteCount = 0
        for _ in string.utf8 {
            try consume()
            guard byteCount < limits.maximumStringUTF8Bytes else {
                throw Workflow.Error(
                    .stringLimitExceeded,
                    limit: .stringUTF8Bytes,
                    maximum: UInt64(limits.maximumStringUTF8Bytes)
                )
            }
            byteCount += 1
        }
        guard totalStringUTF8Bytes <= limits.maximumTotalStringUTF8Bytes - byteCount else {
            throw Workflow.Error(
                .totalStringLimitExceeded,
                limit: .totalStringUTF8Bytes,
                maximum: UInt64(limits.maximumTotalStringUTF8Bytes)
            )
        }
        totalStringUTF8Bytes += byteCount
    }

    func finish() throws {
        try Workflow.Planner.checkCancellation(cancellationCheck)
    }
}

private final class SelectedFilePairOpenFolderReferenceState: @unchecked Sendable {
    typealias Reference = FolderComparisonWorkflowSnapshotReference

    private let condition = NSCondition()
    private var result: Result<Reference, Swift.Error>?

    func complete(with result: Result<Reference, Swift.Error>) {
        condition.lock()
        self.result = result
        condition.broadcast()
        condition.unlock()
    }

    func waitForResult() -> Result<Reference, Swift.Error>? {
        condition.lock()
        defer { condition.unlock() }
        guard result == nil else { return result }
        _ = condition.wait(until: Date(timeIntervalSinceNow: 0.01))
        return result
    }
}

private struct SelectedFilePairOpenPhysicalSourceIdentity: Hashable {
    let deviceID: UInt64
    let fileID: UInt64
    let generation: UInt32

    init(_ revision: FolderComparisonItemRevision) {
        deviceID = revision.identity.deviceID
        fileID = revision.identity.fileID
        generation = revision.identity.generation
    }
}

private struct SelectedFilePairOpenExactResultID: Hashable {
    private let leftRelativePath: String?
    private let rightRelativePath: String?

    init(_ id: DirectoryResult.ID) {
        leftRelativePath = id.leftRelativePath
        rightRelativePath = id.rightRelativePath
    }

    static func == (left: Self, right: Self) -> Bool {
        exactOptionalString(left.leftRelativePath, right.leftRelativePath)
            && exactOptionalString(left.rightRelativePath, right.rightRelativePath)
    }

    func hash(into hasher: inout Hasher) {
        hashExactOptionalString(leftRelativePath, into: &hasher)
        hashExactOptionalString(rightRelativePath, into: &hasher)
    }
}

private typealias WorkMeter = SelectedFilePairOpenWorkMeter
private typealias PhysicalSourceIdentity = SelectedFilePairOpenPhysicalSourceIdentity

private struct SelectedFilePairOpenCanonicalDigest {
    private var hasher = SHA256()

    mutating func append(_ value: Bool) {
        appendByte(value ? 1 : 0)
    }

    mutating func append<T: RawRepresentable>(_ value: T) where T.RawValue == String {
        append(value.rawValue)
    }

    mutating func append<T: RawRepresentable>(_ value: T) where T.RawValue == Int {
        append(value.rawValue)
    }

    mutating func append(_ value: Int) {
        append(Int64(value))
    }

    mutating func append(_ value: Int32) {
        append(Int64(value))
    }

    mutating func append(_ value: Int64) {
        appendFixedWidth(UInt64(bitPattern: value))
    }

    mutating func append(_ value: UInt16) {
        append(UInt64(value))
    }

    mutating func append(_ value: UInt32) {
        append(UInt64(value))
    }

    mutating func append(_ value: UInt64) {
        appendFixedWidth(value)
    }

    mutating func append(_ value: UUID) {
        append(value.uuidString)
    }

    mutating func append(_ value: String) {
        append(UInt64(value.utf8.count))
        hasher.update(data: Data(value.utf8))
    }

    mutating func append(_ value: String, meter: inout WorkMeter) throws {
        try meter.measure(value)
        append(value)
    }

    mutating func append(_ value: Data) {
        append(UInt64(value.count))
        hasher.update(data: value)
    }

    mutating func append(_ value: [UInt8]) {
        append(Data(value))
    }

    mutating func appendOptional(_ value: String?) {
        append(value != nil)
        if let value { append(value) }
    }

    mutating func appendOptional(_ value: UInt64?) {
        append(value != nil)
        if let value { append(value) }
    }

    mutating func appendOptional(_ value: Int?) {
        append(value != nil)
        if let value { append(value) }
    }

    mutating func appendOptional(_ value: Date?) {
        append(value != nil)
        if let value { append(value.timeIntervalSinceReferenceDate.bitPattern) }
    }

    mutating func finalize() -> Data {
        Data(hasher.finalize())
    }

    private mutating func appendByte(_ value: UInt8) {
        var value = value
        withUnsafeBytes(of: &value) { hasher.update(bufferPointer: $0) }
    }

    private mutating func appendFixedWidth(_ value: UInt64) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { hasher.update(bufferPointer: $0) }
    }
}

private func append(
    _ reference: ComparedFileFolderResultsReference,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(reference.identity.rawValue)
    digest.append(reference.revision.rawValue)
    digest.append(reference.generation.rawValue)
}

private func append(
    _ url: URL,
    to digest: inout SelectedFilePairOpenCanonicalDigest,
    meter: inout WorkMeter
) throws {
    try digest.append(url.absoluteString, meter: &meter)
}

private func append(
    _ item: ComparedFileNavigationItem,
    to digest: inout SelectedFilePairOpenCanonicalDigest,
    meter: inout WorkMeter
) throws {
    digest.append(item.identity.rawValue)
    try append(item.resultID, to: &digest, meter: &meter)
    try append(item.left, to: &digest, meter: &meter)
    try append(item.right, to: &digest, meter: &meter)
    digest.append(item.status)
    digest.append(item.comparisonState)
    digest.append(item.visibility)
    switch item.availability {
    case .available(let capability):
        digest.append("available")
        digest.append(capability)
    case .unavailable(let reason):
        digest.append("unavailable")
        append(reason, to: &digest)
    }
    digest.append(item.ordinal)
    digest.appendOptional(item.visibleOrdinal)
}

private func append(
    _ reason: ComparedFileNavigationItemUnavailabilityReason,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    switch reason {
    case .filtered: digest.append("filtered")
    case .hidden: digest.append("hidden")
    case .pending: digest.append("pending")
    case .notRegularFile: digest.append("not-regular-file")
    case .typeMismatch: digest.append("type-mismatch")
    case .skipped: digest.append("skipped")
    case .comparisonError: digest.append("comparison-error")
    case .missingOpenCapability(let capability):
        digest.append("missing-open-capability")
        digest.append(capability)
    case .missingAuthority(let side):
        digest.append("missing-authority")
        digest.append(side)
    case .missingAuthorityCapability(let side, let capability):
        digest.append("missing-authority-capability")
        digest.append(side)
        digest.append(capability)
    }
}

private func append(
    _ metadata: DirectoryEntryMetadata?,
    to digest: inout SelectedFilePairOpenCanonicalDigest,
    meter: inout WorkMeter
) throws {
    digest.append(metadata != nil)
    guard let metadata else { return }
    try digest.append(metadata.relativePath, meter: &meter)
    digest.append(metadata.kind)
    digest.appendOptional(metadata.byteCount)
    digest.appendOptional(metadata.modificationDate)
    digest.append(metadata.isHidden)
}

private func append(
    _ id: DirectoryResult.ID,
    to digest: inout SelectedFilePairOpenCanonicalDigest,
    meter: inout WorkMeter
) throws {
    if let left = id.leftRelativePath {
        digest.append(true)
        try digest.append(left, meter: &meter)
    } else {
        digest.append(false)
    }
    if let right = id.rightRelativePath {
        digest.append(true)
        try digest.append(right, meter: &meter)
    } else {
        digest.append(false)
    }
}

private func append(
    _ id: DirectoryResult.ID,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.appendOptional(id.leftRelativePath)
    digest.appendOptional(id.rightRelativePath)
}

private func append(
    _ limits: ComparedFileNavigationLimits,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(limits.maximumItemCount)
    digest.append(limits.maximumSortDescriptorCount)
    digest.append(limits.maximumStringUTF8Bytes)
    digest.append(limits.maximumTotalStringUTF8Bytes)
    digest.append(limits.maximumWorkUnits)
    digest.append(limits.cancellationCheckInterval)
}

private func append(
    _ hidden: DirectoryHiddenFilter,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    switch hidden {
    case .include: digest.append("include")
    case .exclude: digest.append("exclude")
    case .only: digest.append("only")
    }
}

private func append(
    _ key: DirectoryResultSortKey,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    switch key {
    case .path: digest.append("path")
    case .status: digest.append("status")
    case .kind: digest.append("kind")
    case .leftSize: digest.append("left-size")
    case .rightSize: digest.append("right-size")
    case .leftModificationDate: digest.append("left-modification-date")
    case .rightModificationDate: digest.append("right-modification-date")
    }
}

private func append(
    _ order: DirectoryResultSortOrder,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    switch order {
    case .ascending: digest.append("ascending")
    case .descending: digest.append("descending")
    }
}

private func append(
    _ reference: FolderComparisonWorkflowSnapshotReference,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(reference.identity.rawValue)
    digest.append(reference.generation)
    digest.append(reference.owner.identity)
    digest.append(reference.owner.revision)
    digest.append(reference.contentSHA256)
    append(reference.roots.left, to: &digest)
    append(reference.roots.right, to: &digest)
}

private func append(
    _ root: FolderComparisonRoot,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(root.requestedURL.absoluteString)
    append(root.revision, to: &digest)
    append(root.authority, to: &digest)
    digest.append(root.pathCaseSensitivity)
}

private func append(
    _ revision: FolderComparisonRootRevision,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    append(revision.identity, to: &digest)
    digest.append(revision.linkCount)
    digest.append(revision.permissions)
    digest.append(revision.ownerID)
    digest.append(revision.groupID)
    digest.append(revision.flags)
    digest.append(revision.modificationTimeSeconds)
    digest.append(revision.modificationTimeNanoseconds)
    digest.append(revision.statusChangeTimeSeconds)
    digest.append(revision.statusChangeTimeNanoseconds)
    digest.append(revision.metadataSHA256)
}

private func append(
    _ identity: FolderComparisonRootIdentity,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(identity.canonicalURL.absoluteString)
    digest.append(identity.deviceID)
    digest.append(identity.fileID)
    digest.append(identity.generation)
}

private func append(
    _ authority: FolderComparisonAccessAuthority,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(authority.identity)
    digest.append(authority.revision)
    append(authority.rootIdentity, to: &digest)
    let permissions = authority.permissions.sorted { $0.rawValue < $1.rawValue }
    digest.append(permissions.count)
    for permission in permissions { digest.append(permission) }
    digest.append(authority.coverage)
    switch authority.acquisition {
    case .ambient:
        digest.append("ambient")
    case .callerManagedWhenRequired:
        digest.append("caller-managed")
    case .securityScoped(let resourceURL, let coverage):
        digest.append("security-scoped")
        digest.append(resourceURL.absoluteString)
        digest.append(coverage)
    }
}

private func append(
    _ revision: FolderComparisonItemRevision,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    append(revision.identity.rootIdentity, to: &digest)
    digest.append(revision.identity.relativePath)
    digest.append(revision.identity.deviceID)
    digest.append(revision.identity.fileID)
    digest.append(revision.identity.generation)
    digest.append(revision.kind)
    digest.appendOptional(revision.byteCount)
    digest.append(revision.linkCount)
    digest.append(revision.permissions)
    digest.append(revision.ownerID)
    digest.append(revision.groupID)
    digest.append(revision.flags)
    digest.append(revision.modificationTimeSeconds)
    digest.append(revision.modificationTimeNanoseconds)
    digest.append(revision.statusChangeTimeSeconds)
    digest.append(revision.statusChangeTimeNanoseconds)
    digest.append(revision.metadataSHA256)
    digest.append(revision.contentSHA256 != nil)
    if let contentSHA256 = revision.contentSHA256 { digest.append(contentSHA256) }
}

private func append(
    _ binding: SelectedFilePairOpenWorkflow.SourceBinding,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(binding.side)
    append(binding.root, to: &digest)
    digest.append(binding.relativePath)
    append(binding.revision, to: &digest)
    append(binding.authority, to: &digest)
    append(binding.navigationAuthority, to: &digest)
    digest.append(binding.readOnly)
}

private func append(
    _ binding: SelectedFilePairOpenWorkflow.AuthorityBinding,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(binding.side)
    digest.append(binding.folderAuthorityIdentity)
    digest.append(binding.folderAuthorityRevision)
    digest.append(binding.navigationAuthorityIdentity.rawValue)
}

private func append(
    _ authority: ComparedFileNavigationRootAuthority,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(authority.identity.rawValue)
    digest.append(authority.side)
    digest.append(authority.rootURL.absoluteString)
    let capabilities = authority.capabilities.sorted { $0.rawValue < $1.rawValue }
    digest.append(capabilities.count)
    for capability in capabilities { digest.append(capability) }
}

private func append(
    _ reference: SelectedFilePairOpenWorkflow.NavigationSnapshotReference,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    append(reference.folderResults, to: &digest)
    digest.append(reference.stateSHA256)
}

private func append(
    _ capabilities: FolderComparisonWorkflowCapabilities,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(capabilities.identity)
    digest.append(capabilities.revision)
    let features = capabilities.features.sorted { $0.rawValue < $1.rawValue }
    digest.append(features.count)
    for feature in features { digest.append(feature) }
}

private func append(
    _ capabilities: SelectedFilePairOpenWorkflow.ExecutorCapabilities,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(capabilities.identity)
    digest.append(capabilities.revision)
    let features = capabilities.features.sorted { $0.rawValue < $1.rawValue }
    digest.append(features.count)
    for feature in features { digest.append(feature) }
}

private func append(
    _ target: SelectedFilePairOpenWorkflow.PublicationTarget,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(target.identity)
    digest.append(target.revision)
}

private func append(
    _ limits: FolderComparisonWorkflowLimits,
    to digest: inout SelectedFilePairOpenCanonicalDigest
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
    _ limits: SelectedFilePairOpenWorkflow.Limits,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(limits.maximumSnapshotItems)
    digest.append(limits.maximumSelectedItems)
    digest.append(limits.maximumStringUTF8Bytes)
    digest.append(limits.maximumTotalStringUTF8Bytes)
    digest.append(limits.maximumWorkUnits)
    digest.append(limits.cancellationCheckInterval)
}

private func append(
    _ contract: SelectedFilePairOpenWorkflow.ExecutorContract,
    to digest: inout SelectedFilePairOpenCanonicalDigest
) {
    digest.append(contract.validation)
    digest.append(contract.sourceAccess)
    digest.append(contract.staging)
    digest.append(contract.publication)
    digest.append(contract.cancellation)
    digest.append(contract.ui)
}

private func exactID(_ left: DirectoryResult.ID, _ right: DirectoryResult.ID) -> Bool {
    exactOptionalString(left.leftRelativePath, right.leftRelativePath)
        && exactOptionalString(left.rightRelativePath, right.rightRelativePath)
}

private func exactOptionalString(_ left: String?, _ right: String?) -> Bool {
    switch (left, right) {
    case (nil, nil): true
    case (let left?, let right?): left.utf8.elementsEqual(right.utf8)
    default: false
    }
}

private func hashExactOptionalString(_ value: String?, into hasher: inout Hasher) {
    guard let value else {
        hasher.combine(false)
        return
    }
    hasher.combine(true)
    hasher.combine(value.utf8.count)
    for byte in value.utf8 { hasher.combine(byte) }
}

private func exactMetadata(
    _ left: DirectoryEntryMetadata?,
    _ right: DirectoryEntryMetadata?
) -> Bool {
    switch (left, right) {
    case (nil, nil): true
    case (let left?, let right?):
        left.relativePath.utf8.elementsEqual(right.relativePath.utf8)
            && left.kind == right.kind
            && left.byteCount == right.byteCount
            && exactDate(left.modificationDate, right.modificationDate)
            && left.isHidden == right.isHidden
    default: false
    }
}

private func exactDate(_ left: Date?, _ right: Date?) -> Bool {
    switch (left, right) {
    case (nil, nil): true
    case (let left?, let right?):
        left.timeIntervalSinceReferenceDate.bitPattern
            == right.timeIntervalSinceReferenceDate.bitPattern
    default: false
    }
}

private func exactURL(
    _ left: URL,
    _ right: URL,
    meter: inout WorkMeter
) throws -> Bool {
    try meter.measure(left.absoluteString)
    try meter.measure(right.absoluteString)
    return left.absoluteString.utf8.elementsEqual(right.absoluteString.utf8)
}
