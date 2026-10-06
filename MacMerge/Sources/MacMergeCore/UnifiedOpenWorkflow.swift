import Foundation

/// UI-independent planning for the Select Files or Folders workflow.
///
/// Callers resolve filesystem identities, revisions, selection provenance, and access authorities
/// before planning. This type performs no I/O and treats every supplied observation as stale until a
/// future executor revalidates it under `Plan.executorContract`.
public enum UnifiedOpenWorkflow: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public enum Side: String, CaseIterable, Hashable, Sendable {
        case left
        case middle
        case right

        fileprivate var order: Int {
            switch self {
            case .left: 0
            case .middle: 1
            case .right: 2
            }
        }
    }

    public enum NodeKind: String, CaseIterable, Hashable, Sendable {
        case regularFile
        case directory
    }

    /// Filesystem-stable node identity captured without following aliases during execution.
    public struct NodeIdentity: Hashable, Sendable {
        public let volumeID: UInt64
        public let nodeID: UInt64
        public let generation: UInt64

        public init(volumeID: UInt64, nodeID: UInt64, generation: UInt64) {
            self.volumeID = volumeID
            self.nodeID = nodeID
            self.generation = generation
        }
    }

    /// Exact caller-resolved canonical identity. `canonicalURL` is audit data, not authority.
    public struct CanonicalIdentity: Hashable, Sendable {
        public let kind: NodeKind
        public let canonicalURL: URL
        public let node: NodeIdentity

        public init(kind: NodeKind, canonicalURL: URL, node: NodeIdentity) {
            self.kind = kind
            self.canonicalURL = canonicalURL
            self.node = node
        }
    }

    /// Exact regular-file revision. Metadata digest covers omitted metadata, including ACLs and
    /// extended attributes. Content digest covers complete file bytes.
    public struct FileRevision: Hashable, Sendable {
        public let identity: CanonicalIdentity
        public let byteCount: UInt64
        public let modificationTimeSeconds: Int64
        public let modificationTimeNanoseconds: Int32
        public let statusChangeTimeSeconds: Int64
        public let statusChangeTimeNanoseconds: Int32
        public let contentSHA256: Data
        public let metadataSHA256: Data

        public init(
            identity: CanonicalIdentity,
            byteCount: UInt64,
            modificationTimeSeconds: Int64,
            modificationTimeNanoseconds: Int32,
            statusChangeTimeSeconds: Int64,
            statusChangeTimeNanoseconds: Int32,
            contentSHA256: Data,
            metadataSHA256: Data
        ) {
            self.identity = identity
            self.byteCount = byteCount
            self.modificationTimeSeconds = modificationTimeSeconds
            self.modificationTimeNanoseconds = modificationTimeNanoseconds
            self.statusChangeTimeSeconds = statusChangeTimeSeconds
            self.statusChangeTimeNanoseconds = statusChangeTimeNanoseconds
            self.contentSHA256 = contentSHA256
            self.metadataSHA256 = metadataSHA256
        }
    }

    /// Exact directory-tree revision. `treeSHA256` must cover names, kinds, identities, revisions,
    /// and ordering for the complete tree under the canonical directory.
    public struct FolderRevision: Hashable, Sendable {
        public let identity: CanonicalIdentity
        public let entryCount: UInt64
        public let treeSHA256: Data
        public let metadataSHA256: Data

        public init(
            identity: CanonicalIdentity,
            entryCount: UInt64,
            treeSHA256: Data,
            metadataSHA256: Data
        ) {
            self.identity = identity
            self.entryCount = entryCount
            self.treeSHA256 = treeSHA256
            self.metadataSHA256 = metadataSHA256
        }
    }

    public struct ScratchpadRevision: Hashable, Sendable {
        public let identity: UUID
        public let generation: UInt64
        public let contentSHA256: Data

        public init(identity: UUID, generation: UInt64, contentSHA256: Data) {
            self.identity = identity
            self.generation = generation
            self.contentSHA256 = contentSHA256
        }
    }

    public enum SourceRevision: Hashable, Sendable {
        case file(FileRevision)
        case folder(FolderRevision)
        case scratchpad(ScratchpadRevision)

        fileprivate var canonicalIdentity: CanonicalIdentity? {
            switch self {
            case .file(let revision): revision.identity
            case .folder(let revision): revision.identity
            case .scratchpad: nil
            }
        }
    }

    public struct AuthorityReference: Hashable, Sendable {
        public let identity: UUID
        public let generation: UInt64

        public init(identity: UUID, generation: UInt64) {
            self.identity = identity
            self.generation = generation
        }
    }

    public enum AuthorityCoverage: String, CaseIterable, Hashable, Sendable {
        case exactItem
        case directoryTree
    }

    public struct AuthorityPermissions: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8

        public static let read = AuthorityPermissions(rawValue: 1 << 0)
        public static let create = AuthorityPermissions(rawValue: 1 << 1)
        public static let replace = AuthorityPermissions(rawValue: 1 << 2)

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }

    /// Immutable reference to caller-owned access authority. It does not itself grant access.
    public struct AccessAuthority: Hashable, Sendable {
        public let reference: AuthorityReference
        public let resource: CanonicalIdentity
        public let coverage: AuthorityCoverage
        public let permissions: AuthorityPermissions

        public init(
            reference: AuthorityReference,
            resource: CanonicalIdentity,
            coverage: AuthorityCoverage,
            permissions: AuthorityPermissions
        ) {
            self.reference = reference
            self.resource = resource
            self.coverage = coverage
            self.permissions = permissions
        }
    }

    public enum SelectionOrigin: Hashable, Sendable {
        case browse(session: UUID, selectionIndex: UInt64)
        case history(entryIdentifier: String, revision: UInt64)
        case entered(editRevision: UInt64)
    }

    /// Attests how a requested path became bound to an exact revision and authority.
    public struct SourceSelectionAttestation: Hashable, Sendable {
        public let requestedURL: URL
        public let revision: SourceRevision
        public let authority: AuthorityReference
        public let origin: SelectionOrigin

        public init(
            requestedURL: URL,
            revision: SourceRevision,
            authority: AuthorityReference,
            origin: SelectionOrigin
        ) {
            self.requestedURL = requestedURL
            self.revision = revision
            self.authority = authority
            self.origin = origin
        }
    }

    /// Deliberately permits invalid enum/revision pairings so untrusted decoded input can be
    /// represented and then rejected by the planner.
    public struct LocalSource: Hashable, Sendable {
        public let requestedURL: URL
        public let revision: SourceRevision
        public let selection: SourceSelectionAttestation
        public let access: AccessAuthority

        public init(
            requestedURL: URL,
            revision: SourceRevision,
            selection: SourceSelectionAttestation,
            access: AccessAuthority
        ) {
            self.requestedURL = requestedURL
            self.revision = revision
            self.selection = selection
            self.access = access
        }
    }

    public struct ScratchpadSource: Hashable, Sendable {
        public let revision: ScratchpadRevision
        public let text: String
        public let label: String?

        public init(revision: ScratchpadRevision, text: String, label: String? = nil) {
            self.revision = revision
            self.text = text
            self.label = label
        }
    }

    public enum Source: Hashable, Sendable {
        case file(LocalSource)
        case folder(LocalSource)
        case scratchpad(ScratchpadSource)

        public var revision: SourceRevision {
            switch self {
            case .file(let source), .folder(let source): source.revision
            case .scratchpad(let source): .scratchpad(source.revision)
            }
        }
    }

    public struct SideInput: Hashable, Sendable {
        public let side: Side
        public let source: Source
        public let readOnly: Bool

        public init(side: Side, source: Source, readOnly: Bool = false) {
            self.side = side
            self.source = source
            self.readOnly = readOnly
        }
    }

    public enum ComparisonMode: String, CaseIterable, Hashable, Sendable {
        case automatic
        case text
        case table
        case binary
        case image
        case webpage
        case folder
    }

    public struct ExactComparisonOptions: Hashable, Sendable {
        public let mode: ComparisonMode
        public let schemaIdentifier: String
        public let schemaRevision: UInt64
        public let canonicalData: Data
        public let dataSHA256: Data

        public init(
            mode: ComparisonMode,
            schemaIdentifier: String,
            schemaRevision: UInt64,
            canonicalData: Data,
            dataSHA256: Data
        ) {
            self.mode = mode
            self.schemaIdentifier = schemaIdentifier
            self.schemaRevision = schemaRevision
            self.canonicalData = canonicalData
            self.dataSHA256 = dataSHA256
        }
    }

    public enum ComparisonOptions: Hashable, Sendable {
        case defaults(mode: ComparisonMode)
        case exact(ExactComparisonOptions)

        public var mode: ComparisonMode {
            switch self {
            case .defaults(let mode): mode
            case .exact(let options): options.mode
            }
        }
    }

    public struct FilterSelection: Hashable, Sendable {
        public let identifier: String
        public let revision: UInt64
        public let definitionSHA256: Data

        public init(identifier: String, revision: UInt64, definitionSHA256: Data) {
            self.identifier = identifier
            self.revision = revision
            self.definitionSHA256 = definitionSHA256
        }
    }

    public enum TransformCapability: String, CaseIterable, Hashable, Sendable {
        case unpacker
        case prediffer
    }

    public struct TransformSelection: Hashable, Sendable {
        public let capability: TransformCapability
        public let identifier: String
        public let revision: UInt64
        public let policySHA256: Data
        public let configurationSHA256: Data

        public init(
            capability: TransformCapability,
            identifier: String,
            revision: UInt64,
            policySHA256: Data,
            configurationSHA256: Data
        ) {
            self.capability = capability
            self.identifier = identifier
            self.revision = revision
            self.policySHA256 = policySHA256
            self.configurationSHA256 = configurationSHA256
        }
    }

    public struct TransformSelections: Hashable, Sendable {
        public let unpacker: TransformSelection?
        public let prediffer: TransformSelection?

        public init(
            unpacker: TransformSelection? = nil,
            prediffer: TransformSelection? = nil
        ) {
            self.unpacker = unpacker
            self.prediffer = prediffer
        }
    }

    public enum CompareButtonIntent: Hashable, Sendable {
        case primary
        case compareAs(ComparisonMode)
    }

    /// Canonical nonexistent file location under an exact parent directory.
    public struct CanonicalLocation: Hashable, Sendable {
        public let canonicalURL: URL
        public let parent: CanonicalIdentity

        public init(canonicalURL: URL, parent: CanonicalIdentity) {
            self.canonicalURL = canonicalURL
            self.parent = parent
        }
    }

    public enum ProjectDestinationState: Hashable, Sendable {
        case absent(CanonicalLocation)
        case existing(FileRevision)

        fileprivate var canonicalURL: URL {
            switch self {
            case .absent(let location): location.canonicalURL
            case .existing(let revision): revision.identity.canonicalURL
            }
        }
    }

    public struct DestinationAttestation: Hashable, Sendable {
        public let requestedURL: URL
        public let destination: ProjectDestinationState
        public let authority: AuthorityReference
        public let origin: SelectionOrigin

        public init(
            requestedURL: URL,
            destination: ProjectDestinationState,
            authority: AuthorityReference,
            origin: SelectionOrigin
        ) {
            self.requestedURL = requestedURL
            self.destination = destination
            self.authority = authority
            self.origin = origin
        }
    }

    public enum ProjectFormat: String, CaseIterable, Hashable, Sendable {
        case macMerge
        case winMerge
    }

    public struct ProjectSaveIntent: Hashable, Sendable {
        public let format: ProjectFormat
        public let requestedURL: URL
        public let destination: ProjectDestinationState
        public let selection: DestinationAttestation
        public let access: AccessAuthority

        public init(
            format: ProjectFormat,
            requestedURL: URL,
            destination: ProjectDestinationState,
            selection: DestinationAttestation,
            access: AccessAuthority
        ) {
            self.format = format
            self.requestedURL = requestedURL
            self.destination = destination
            self.selection = selection
            self.access = access
        }
    }

    public struct RequestReference: Hashable, Sendable {
        public let identity: UUID
        public let generation: UInt64

        public init(identity: UUID = UUID(), generation: UInt64 = 0) {
            self.identity = identity
            self.generation = generation
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case pathUTF8Bytes
        case totalPathUTF8Bytes
        case stringUTF8Bytes
        case totalStringUTF8Bytes
        case labelUTF8Bytes
        case scratchpadUTF8Bytes
        case combinedScratchpadUTF8Bytes
        case optionBytes
        case itemCount
        case declaredBytes
        case declaredItems
        case retainedBytes
        case workUnits
        case cancellationCheckInterval
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumPathUTF8Bytes = 64 * 1_024
        public static let hardMaximumTotalPathUTF8Bytes = 2 * 1_024 * 1_024
        public static let hardMaximumStringUTF8Bytes = 256 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 8 * 1_024 * 1_024
        public static let hardMaximumLabelUTF8Bytes = 16 * 1_024
        public static let hardMaximumScratchpadUTF8Bytes = 64 * 1_024 * 1_024
        public static let hardMaximumCombinedScratchpadUTF8Bytes = 192 * 1_024 * 1_024
        public static let hardMaximumOptionBytes = 16 * 1_024 * 1_024
        public static let hardMaximumItemCount = 4_096
        public static let hardMaximumDeclaredBytes: UInt64 = 1 << 50
        public static let hardMaximumDeclaredItems: UInt64 = 1_000_000_000
        public static let hardMaximumRetainedBytes: UInt64 = 256 * 1_024 * 1_024
        public static let hardMaximumWorkUnits: UInt64 = 512 * 1_024 * 1_024
        public static let hardMaximumCancellationCheckInterval: UInt64 = 4_096
        public static let `default` = Limits()

        public let maximumPathUTF8Bytes: Int
        public let maximumTotalPathUTF8Bytes: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumLabelUTF8Bytes: Int
        public let maximumScratchpadUTF8Bytes: Int
        public let maximumCombinedScratchpadUTF8Bytes: Int
        public let maximumOptionBytes: Int
        public let maximumItemCount: Int
        public let maximumDeclaredBytes: UInt64
        public let maximumDeclaredItems: UInt64
        public let maximumRetainedBytes: UInt64
        public let maximumWorkUnits: UInt64
        public let cancellationCheckInterval: UInt64

        public init(
            maximumPathUTF8Bytes: Int = 64 * 1_024,
            maximumTotalPathUTF8Bytes: Int = 512 * 1_024,
            maximumStringUTF8Bytes: Int = 64 * 1_024,
            maximumTotalStringUTF8Bytes: Int = 2 * 1_024 * 1_024,
            maximumLabelUTF8Bytes: Int = 4 * 1_024,
            maximumScratchpadUTF8Bytes: Int = 64 * 1_024 * 1_024,
            maximumCombinedScratchpadUTF8Bytes: Int = 192 * 1_024 * 1_024,
            maximumOptionBytes: Int = 4 * 1_024 * 1_024,
            maximumItemCount: Int = 1_024,
            maximumDeclaredBytes: UInt64 = 1 << 40,
            maximumDeclaredItems: UInt64 = 100_000_000,
            maximumRetainedBytes: UInt64 = 224 * 1_024 * 1_024,
            maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
            cancellationCheckInterval: UInt64 = 4_096
        ) {
            self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
            self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumLabelUTF8Bytes = maximumLabelUTF8Bytes
            self.maximumScratchpadUTF8Bytes = maximumScratchpadUTF8Bytes
            self.maximumCombinedScratchpadUTF8Bytes = maximumCombinedScratchpadUTF8Bytes
            self.maximumOptionBytes = maximumOptionBytes
            self.maximumItemCount = maximumItemCount
            self.maximumDeclaredBytes = maximumDeclaredBytes
            self.maximumDeclaredItems = maximumDeclaredItems
            self.maximumRetainedBytes = maximumRetainedBytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        fileprivate func validate() throws {
            guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
                throw PlanningError.invalidLimit(.pathUTF8Bytes)
            }
            guard
                maximumPathUTF8Bytes...Self.hardMaximumTotalPathUTF8Bytes
                    ~= maximumTotalPathUTF8Bytes
            else {
                throw PlanningError.invalidLimit(.totalPathUTF8Bytes)
            }
            guard (1...Self.hardMaximumStringUTF8Bytes).contains(maximumStringUTF8Bytes) else {
                throw PlanningError.invalidLimit(.stringUTF8Bytes)
            }
            guard
                maximumStringUTF8Bytes...Self.hardMaximumTotalStringUTF8Bytes
                    ~= maximumTotalStringUTF8Bytes
            else {
                throw PlanningError.invalidLimit(.totalStringUTF8Bytes)
            }
            guard (1...Self.hardMaximumLabelUTF8Bytes).contains(maximumLabelUTF8Bytes) else {
                throw PlanningError.invalidLimit(.labelUTF8Bytes)
            }
            guard (0...Self.hardMaximumScratchpadUTF8Bytes).contains(maximumScratchpadUTF8Bytes) else {
                throw PlanningError.invalidLimit(.scratchpadUTF8Bytes)
            }
            guard
                maximumScratchpadUTF8Bytes...Self.hardMaximumCombinedScratchpadUTF8Bytes
                    ~= maximumCombinedScratchpadUTF8Bytes
            else {
                throw PlanningError.invalidLimit(.combinedScratchpadUTF8Bytes)
            }
            guard (0...Self.hardMaximumOptionBytes).contains(maximumOptionBytes) else {
                throw PlanningError.invalidLimit(.optionBytes)
            }
            guard (1...Self.hardMaximumItemCount).contains(maximumItemCount) else {
                throw PlanningError.invalidLimit(.itemCount)
            }
            guard (1...Self.hardMaximumDeclaredBytes).contains(maximumDeclaredBytes) else {
                throw PlanningError.invalidLimit(.declaredBytes)
            }
            guard (1...Self.hardMaximumDeclaredItems).contains(maximumDeclaredItems) else {
                throw PlanningError.invalidLimit(.declaredItems)
            }
            guard (1...Self.hardMaximumRetainedBytes).contains(maximumRetainedBytes) else {
                throw PlanningError.invalidLimit(.retainedBytes)
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw PlanningError.invalidLimit(.workUnits)
            }
            guard
                (1...Self.hardMaximumCancellationCheckInterval)
                    .contains(cancellationCheckInterval)
            else {
                throw PlanningError.invalidLimit(.cancellationCheckInterval)
            }
        }
    }

    public struct Request: Hashable, Sendable {
        public let reference: RequestReference
        public let sides: [SideInput]
        public let recursive: Bool
        public let filter: FilterSelection?
        public let transforms: TransformSelections
        public let comparisonOptions: ComparisonOptions
        public let projectSaveIntent: ProjectSaveIntent?
        public let compareButtonIntent: CompareButtonIntent
        public let limits: Limits

        public init(
            reference: RequestReference = RequestReference(),
            sides: [SideInput],
            recursive: Bool = false,
            filter: FilterSelection? = nil,
            transforms: TransformSelections = TransformSelections(),
            comparisonOptions: ComparisonOptions = .defaults(mode: .automatic),
            projectSaveIntent: ProjectSaveIntent? = nil,
            compareButtonIntent: CompareButtonIntent = .primary,
            limits: Limits = .default
        ) {
            self.reference = reference
            self.sides = sides
            self.recursive = recursive
            self.filter = filter
            self.transforms = transforms
            self.comparisonOptions = comparisonOptions
            self.projectSaveIntent = projectSaveIntent
            self.compareButtonIntent = compareButtonIntent
            self.limits = limits
        }

        /// Swaps complete source/read-only payloads while retaining canonical pane positions.
        /// Generation advances so every plan for the prior ordering becomes stale.
        public func swapping(_ first: Side, _ second: Side) throws -> Request {
            guard first != second else { return self }
            guard let firstIndex = sides.firstIndex(where: { $0.side == first }) else {
                throw PlanningError.missingSide(first)
            }
            guard let secondIndex = sides.firstIndex(where: { $0.side == second }) else {
                throw PlanningError.missingSide(second)
            }
            let (nextGeneration, overflow) = reference.generation.addingReportingOverflow(1)
            guard !overflow else { throw PlanningError.requestGenerationOverflow }
            var result = sides
            let firstValue = result[firstIndex]
            let secondValue = result[secondIndex]
            result[firstIndex] = SideInput(
                side: first,
                source: secondValue.source,
                readOnly: secondValue.readOnly
            )
            result[secondIndex] = SideInput(
                side: second,
                source: firstValue.source,
                readOnly: firstValue.readOnly
            )
            return Request(
                reference: RequestReference(
                    identity: reference.identity,
                    generation: nextGeneration
                ),
                sides: result,
                recursive: recursive,
                filter: filter,
                transforms: transforms,
                comparisonOptions: comparisonOptions,
                projectSaveIntent: projectSaveIntent,
                compareButtonIntent: compareButtonIntent,
                limits: limits
            )
        }
    }

    public enum ExecutionStep: Hashable, Sendable {
        case validateExactState
        case acquireAuthority(AuthorityReference)
        case materializeSource(Side)
        case validateImmediatelyAfterMaterialization
        case applyFilter(FilterSelection)
        case runTransform(TransformSelection)
        case validateImmediatelyBeforePublication
        case compare(mode: ComparisonMode, intent: CompareButtonIntent)
        case saveProject(ProjectSaveIntent)
    }

    public struct PositionedRevision: Hashable, Sendable {
        public let side: Side
        public let revision: SourceRevision

        public init(side: Side, revision: SourceRevision) {
            self.side = side
            self.revision = revision
        }
    }

    /// Deterministic successful-planning receipt. No process-random hash, wall clock, or generated
    /// identifier participates in `planSHA256`.
    public struct Receipt: Hashable, Sendable {
        public let request: RequestReference
        public let sourceRevisions: [PositionedRevision]
        public let planSHA256: Data
        public var requestStateSHA256: Data { planSHA256 }
        public let retainedByteCount: UInt64
        public let planningWorkUnits: UInt64

        fileprivate init(
            request: RequestReference,
            sourceRevisions: [PositionedRevision],
            planSHA256: Data,
            retainedByteCount: UInt64,
            planningWorkUnits: UInt64
        ) {
            self.request = request
            self.sourceRevisions = sourceRevisions
            self.planSHA256 = planSHA256
            self.retainedByteCount = retainedByteCount
            self.planningWorkUnits = planningWorkUnits
        }
    }

    public enum PathResolutionContract: String, Hashable, Sendable {
        case descriptorRelativeNoFollowFromPinnedCanonicalParent
    }

    public enum AuthorityExecutionContract: String, Hashable, Sendable {
        case reacquireExactGenerationAndBalanceAccess
    }

    public enum RevisionExecutionContract: String, Hashable, Sendable {
        case revalidateAllExactRevisionsBeforeMaterializationImmediatelyAfterAndBeforeEveryPublication
    }

    public enum PublicationContract: String, Hashable, Sendable {
        case serializeImmediateValidationAndEachEffectPublication
    }

    public enum CancellationContract: String, Hashable, Sendable {
        case cancellationBeforeEffectsAndPublication
    }

    /// Mandatory contract for a future executor. This file intentionally supplies no executor.
    public struct ExecutorContract: Hashable, Sendable {
        public static let required = ExecutorContract()

        public let pathResolution =
            PathResolutionContract.descriptorRelativeNoFollowFromPinnedCanonicalParent
        public let authority =
            AuthorityExecutionContract.reacquireExactGenerationAndBalanceAccess
        public let revision =
            RevisionExecutionContract
            .revalidateAllExactRevisionsBeforeMaterializationImmediatelyAfterAndBeforeEveryPublication
        public let publication = PublicationContract.serializeImmediateValidationAndEachEffectPublication
        public let cancellation = CancellationContract.cancellationBeforeEffectsAndPublication

        public init() {}
    }

    /// Executor-supplied current observations. The complete current request is canonically digested
    /// during validation, making its reference plus digest an exact state CAS. Arrays are accepted
    /// in any order but must contain exactly one entry for each planned source and authority.
    public struct ExecutionValidation: Hashable, Sendable {
        public let request: Request
        public let sources: [PositionedRevision]
        public let authorities: [AccessAuthority]
        public let filter: FilterSelection?
        public let unpacker: TransformSelection?
        public let prediffer: TransformSelection?
        public let comparisonOptions: ComparisonOptions
        public let projectDestination: ProjectDestinationState?

        public init(
            request: Request,
            sources: [PositionedRevision],
            authorities: [AccessAuthority],
            filter: FilterSelection?,
            unpacker: TransformSelection?,
            prediffer: TransformSelection?,
            comparisonOptions: ComparisonOptions,
            projectDestination: ProjectDestinationState?
        ) {
            self.request = request
            self.sources = sources
            self.authorities = authorities
            self.filter = filter
            self.unpacker = unpacker
            self.prediffer = prediffer
            self.comparisonOptions = comparisonOptions
            self.projectDestination = projectDestination
        }
    }

    public struct Plan: Hashable, Sendable {
        public let request: Request
        public let sides: [SideInput]
        public let resolvedMode: ComparisonMode
        public let authorities: [AccessAuthority]
        public let steps: [ExecutionStep]
        public let receipt: Receipt
        public let executorContract: ExecutorContract

        public var isThreeWay: Bool { sides.count == 3 }

        fileprivate init(
            request: Request,
            sides: [SideInput],
            resolvedMode: ComparisonMode,
            authorities: [AccessAuthority],
            steps: [ExecutionStep],
            receipt: Receipt
        ) {
            self.request = request
            self.sides = sides
            self.resolvedMode = resolvedMode
            self.authorities = authorities
            self.steps = steps
            self.receipt = receipt
            executorContract = .required
        }

        public func side(_ side: Side) -> SideInput? {
            sides.first { $0.side == side }
        }

        public func validateForExecution(_ current: ExecutionValidation) throws {
            try Planner.validate(self, against: current)
        }

        /// Executor calls this again after materialization and immediately before publishing any
        /// comparison state or project file.
        public func validateForPublication(_ current: ExecutionValidation) throws {
            try Planner.validate(self, against: current)
        }
    }

    public enum URLRole: Hashable, Sendable {
        case requestedSource(Side)
        case canonicalSource(Side)
        case authorityResource
        case requestedProjectDestination
        case canonicalProjectDestination
        case projectParent
    }

    public enum URLIssue: String, CaseIterable, Hashable, Sendable {
        case notFileURL
        case relativeURL
        case authorityComponent
        case queryOrFragment
        case nullByte
        case missingPath
        case wrongDirectoryShape
        case notCanonical
        case parentMismatch
    }

    public enum StringField: String, CaseIterable, Hashable, Sendable {
        case path
        case label
        case identifier
        case historyIdentifier
        case schemaIdentifier
    }

    public enum DigestField: Hashable, Sendable {
        case fileContent(Side?)
        case fileMetadata(Side?)
        case folderTree(Side?)
        case folderMetadata(Side?)
        case scratchpad(Side)
        case filter
        case transformPolicy(TransformCapability)
        case transformConfiguration(TransformCapability)
        case comparisonOptions
        case receipt
    }

    public enum SourceShape: String, CaseIterable, Hashable, Sendable {
        case files
        case folders
        case scratchpads
        case filesAndScratchpads
    }

    public enum PlanningError: Swift.Error, Equatable, Hashable, LocalizedError, Sendable {
        case cancelled
        case invalidLimit(Limit)
        case workLimitExceeded(maximumUnits: UInt64)
        case itemLimitExceeded(maximumItems: Int)
        case stringLimitExceeded(field: StringField, maximumUTF8Bytes: Int)
        case totalPathLimitExceeded(maximumUTF8Bytes: Int)
        case totalStringLimitExceeded(maximumUTF8Bytes: Int)
        case scratchpadTooLarge(side: Side, maximumUTF8Bytes: Int)
        case combinedScratchpadsTooLarge(maximumUTF8Bytes: Int)
        case optionDataTooLarge(maximumBytes: Int)
        case declaredByteLimitExceeded(maximumBytes: UInt64)
        case declaredItemLimitExceeded(maximumItems: UInt64)
        case retainedDataTooLarge(maximumBytes: UInt64)
        case invalidSideCount(Int)
        case duplicateSide(Side)
        case missingSide(Side)
        case invalidSideSet([Side])
        case requestGenerationOverflow
        case invalidURL(role: URLRole, issue: URLIssue)
        case invalidRevision(side: Side?)
        case invalidDigest(DigestField)
        case scratchpadDigestMismatch(side: Side)
        case invalidSelectionAttestation(side: Side)
        case invalidSelectionOrigin
        case invalidAuthority(side: Side?)
        case duplicateAuthority(AuthorityReference)
        case duplicateSourceIdentity(first: Side, second: Side)
        case mixedSourceKinds
        case incompatibleMode(mode: ComparisonMode, shape: SourceShape)
        case automaticModeRequiresExplicitSelection
        case exactOptionsRequireExplicitMode
        case comparisonOptionsDigestMismatch
        case recursiveRequiresFolders
        case filterRequiresFolders
        case invalidFilterSelection
        case invalidTransformSelection(TransformCapability)
        case transformRequiresFiles(TransformCapability)
        case duplicateTransformIdentifier
        case compareAsRequiresExplicitMode
        case compareAsOptionsMismatch(expected: ComparisonMode, actual: ComparisonMode)
        case projectCannotRepresentScratchpads
        case invalidProjectDestination
        case projectDestinationAliasesSource(Side)
        case invalidExecutionValidation
        case staleRequest(expected: RequestReference, actual: RequestReference)
        case staleRequestState
        case staleSource(Side)
        case staleAuthority(AuthorityReference)
        case staleFilter
        case staleTransform(TransformCapability)
        case staleComparisonOptions
        case staleProjectDestination
        case receiptMismatch

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "Unified open workflow planning was cancelled."
            case .invalidLimit(let limit):
                "Invalid unified open workflow limit: \(limit.rawValue)."
            case .workLimitExceeded(let maximum):
                "Unified open workflow exceeds the \(maximum)-unit work limit."
            case .itemLimitExceeded(let maximum):
                "Unified open workflow exceeds the \(maximum)-item limit."
            case .stringLimitExceeded(let field, let maximum):
                "Unified open workflow \(field.rawValue) exceeds \(maximum) UTF-8 bytes."
            case .totalPathLimitExceeded(let maximum):
                "Unified open workflow paths exceed \(maximum) combined UTF-8 bytes."
            case .totalStringLimitExceeded(let maximum):
                "Unified open workflow strings exceed \(maximum) combined UTF-8 bytes."
            case .scratchpadTooLarge(let side, let maximum):
                "Unified open workflow \(side.rawValue) scratchpad exceeds \(maximum) UTF-8 bytes."
            case .combinedScratchpadsTooLarge(let maximum):
                "Unified open workflow scratchpads exceed \(maximum) combined UTF-8 bytes."
            case .optionDataTooLarge(let maximum):
                "Unified open workflow options exceed \(maximum) bytes."
            case .declaredByteLimitExceeded(let maximum):
                "Unified open workflow source exceeds the declared \(maximum)-byte limit."
            case .declaredItemLimitExceeded(let maximum):
                "Unified open workflow folder exceeds the declared \(maximum)-item limit."
            case .retainedDataTooLarge(let maximum):
                "Unified open workflow plan exceeds the \(maximum)-byte retained-data limit."
            case .invalidSideCount(let count):
                "Unified open workflow requires two or three sides, not \(count)."
            case .duplicateSide(let side):
                "Unified open workflow repeats the \(side.rawValue) side."
            case .missingSide(let side):
                "Unified open workflow is missing the \(side.rawValue) side."
            case .invalidSideSet(let sides):
                "Unified open workflow has invalid sides: \(sides.map(\.rawValue).joined(separator: ", "))."
            case .requestGenerationOverflow:
                "Unified open workflow request generation cannot advance."
            case .invalidURL(let role, let issue):
                "Invalid unified open workflow URL for \(String(describing: role)): \(issue.rawValue)."
            case .invalidRevision:
                "Unified open workflow contains an invalid exact source revision."
            case .invalidDigest:
                "Unified open workflow contains an invalid SHA-256 digest."
            case .scratchpadDigestMismatch(let side):
                "Unified open workflow \(side.rawValue) scratchpad no longer matches its revision."
            case .invalidSelectionAttestation(let side):
                "Unified open workflow \(side.rawValue) selection attestation does not match its source."
            case .invalidSelectionOrigin:
                "Unified open workflow contains an invalid selection-origin attestation."
            case .invalidAuthority:
                "Unified open workflow contains an invalid access authority."
            case .duplicateAuthority:
                "Unified open workflow repeats one access authority."
            case .duplicateSourceIdentity(let first, let second):
                "Unified open workflow repeats one canonical source on \(first.rawValue) and \(second.rawValue)."
            case .mixedSourceKinds:
                "Unified open workflow cannot mix folders with files or scratchpads."
            case .incompatibleMode(let mode, let shape):
                "Unified open workflow \(shape.rawValue) sources are incompatible with \(mode.rawValue) mode."
            case .automaticModeRequiresExplicitSelection:
                "Unified open workflow requires an explicit comparison mode for this source shape."
            case .exactOptionsRequireExplicitMode:
                "Exact comparison options require an explicit comparison mode."
            case .comparisonOptionsDigestMismatch:
                "Unified open workflow comparison options do not match their digest."
            case .recursiveRequiresFolders:
                "Recursive comparison requires folder sources."
            case .filterRequiresFolders:
                "Filename filtering requires folder sources."
            case .invalidFilterSelection:
                "Unified open workflow contains an invalid filter selection."
            case .invalidTransformSelection(let capability):
                "Unified open workflow contains an invalid \(capability.rawValue) selection."
            case .transformRequiresFiles(let capability):
                "Unified open workflow \(capability.rawValue) selection requires only file sources."
            case .duplicateTransformIdentifier:
                "Unified open workflow unpacker and prediffer identifiers must differ."
            case .compareAsRequiresExplicitMode:
                "Compare As requires an explicit comparison mode."
            case .compareAsOptionsMismatch(let expected, let actual):
                "Compare As \(expected.rawValue) cannot use \(actual.rawValue) options."
            case .projectCannotRepresentScratchpads:
                "Unified open workflow cannot save scratchpad contents as path-only project sources."
            case .invalidProjectDestination:
                "Unified open workflow contains an invalid project destination."
            case .projectDestinationAliasesSource(let side):
                "Unified open workflow project destination aliases the \(side.rawValue) source."
            case .invalidExecutionValidation:
                "Unified open workflow executor supplied malformed current state."
            case .staleRequest:
                "Unified open workflow request identity or generation is stale."
            case .staleRequestState:
                "Unified open workflow canonical request state is stale."
            case .staleSource(let side):
                "Unified open workflow \(side.rawValue) source revision is stale."
            case .staleAuthority:
                "Unified open workflow access authority is stale."
            case .staleFilter:
                "Unified open workflow filter selection is stale."
            case .staleTransform(let capability):
                "Unified open workflow \(capability.rawValue) selection is stale."
            case .staleComparisonOptions:
                "Unified open workflow comparison options are stale."
            case .staleProjectDestination:
                "Unified open workflow project destination is stale."
            case .receiptMismatch:
                "Unified open workflow plan receipt does not match its request."
            }
        }
    }

    public enum Planner: Sendable {
        public static func plan(
            _ request: Request,
            expecting expectedReference: RequestReference? = nil,
            cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
        ) throws -> Plan {
            do {
                do {
                    try cancellationCheck()
                } catch {
                    throw PlanningError.cancelled
                }
                try request.limits.validate()
                if let expectedReference, expectedReference != request.reference {
                    throw PlanningError.staleRequest(
                        expected: expectedReference,
                        actual: request.reference
                    )
                }
                var meter = Meter(limits: request.limits, cancellationCheck: cancellationCheck)
                let sides = try canonicalSides(request.sides, meter: &meter)
                var authorities: [AccessAuthority] = []
                var authorityReferences: Set<AuthorityReference> = []
                var sourceNodes: [(Side, NodeIdentity)] = []
                var sourceCanonicalPaths: [(Side, String)] = []
                var scratchpadIdentities: Set<UUID> = []
                var scratchpadBytes = 0
                var hasFiles = false
                var hasFolders = false
                var hasScratchpads = false

                for input in sides {
                    try meter.addItem()
                    switch input.source {
                    case .file(let source):
                        hasFiles = true
                        let revision = try requireFileRevision(source.revision, side: input.side)
                        try validateLocalSource(
                            source,
                            expectedKind: .regularFile,
                            side: input.side,
                            requiredCoverage: .exactItem,
                            meter: &meter
                        )
                        try addSourceNode(
                            revision.identity.node,
                            side: input.side,
                            existing: &sourceNodes
                        )
                        try addSourceCanonicalPath(
                            revision.identity.canonicalURL.path,
                            side: input.side,
                            existing: &sourceCanonicalPaths
                        )
                        try addAuthority(
                            source.access,
                            side: input.side,
                            references: &authorityReferences,
                            authorities: &authorities
                        )
                    case .folder(let source):
                        hasFolders = true
                        let revision = try requireFolderRevision(source.revision, side: input.side)
                        try validateLocalSource(
                            source,
                            expectedKind: .directory,
                            side: input.side,
                            requiredCoverage: .directoryTree,
                            meter: &meter
                        )
                        try addSourceNode(
                            revision.identity.node,
                            side: input.side,
                            existing: &sourceNodes
                        )
                        try addSourceCanonicalPath(
                            revision.identity.canonicalURL.path,
                            side: input.side,
                            existing: &sourceCanonicalPaths
                        )
                        try addAuthority(
                            source.access,
                            side: input.side,
                            references: &authorityReferences,
                            authorities: &authorities
                        )
                    case .scratchpad(let source):
                        hasScratchpads = true
                        guard scratchpadIdentities.insert(source.revision.identity).inserted else {
                            throw PlanningError.duplicateSourceIdentity(
                                first: sides.first(where: {
                                    if case .scratchpad(let value) = $0.source {
                                        value.revision.identity == source.revision.identity
                                    } else {
                                        false
                                    }
                                })?.side ?? input.side,
                                second: input.side
                            )
                        }
                        try validateDigest(
                            source.revision.contentSHA256,
                            field: .scratchpad(input.side)
                        )
                        let byteCount = try meter.stringByteCount(
                            source.text,
                            maximum: request.limits.maximumScratchpadUTF8Bytes,
                            field: .label,
                            limitError: .scratchpadTooLarge(
                                side: input.side,
                                maximumUTF8Bytes: request.limits.maximumScratchpadUTF8Bytes
                            )
                        )
                        guard scratchpadBytes <= request.limits.maximumCombinedScratchpadUTF8Bytes - byteCount else {
                            throw PlanningError.combinedScratchpadsTooLarge(
                                maximumUTF8Bytes: request.limits.maximumCombinedScratchpadUTF8Bytes
                            )
                        }
                        scratchpadBytes += byteCount
                        try meter.retain(UInt64(byteCount))
                        let digest = try hash(source.text, meter: &meter)
                        guard digest == source.revision.contentSHA256 else {
                            throw PlanningError.scratchpadDigestMismatch(side: input.side)
                        }
                        if let label = source.label {
                            try validateLabel(label, meter: &meter)
                        }
                    }
                }

                if hasFolders && (hasFiles || hasScratchpads) {
                    throw PlanningError.mixedSourceKinds
                }
                let shape: SourceShape
                if hasFolders {
                    shape = .folders
                } else if hasFiles && hasScratchpads {
                    shape = .filesAndScratchpads
                } else if hasScratchpads {
                    shape = .scratchpads
                } else {
                    shape = .files
                }

                let mode = try validateComparisonOptions(
                    request.comparisonOptions,
                    intent: request.compareButtonIntent,
                    shape: shape,
                    sides: sides,
                    meter: &meter
                )
                try validateShape(shape, mode: mode)
                if request.recursive, shape != .folders {
                    throw PlanningError.recursiveRequiresFolders
                }
                if let filter = request.filter {
                    guard shape == .folders else { throw PlanningError.filterRequiresFolders }
                    try meter.addItem()
                    try validateFilter(filter, meter: &meter)
                }
                try validateTransforms(request.transforms, shape: shape, meter: &meter)
                if let unpacker = request.transforms.unpacker,
                    let prediffer = request.transforms.prediffer,
                    unpacker.identifier == prediffer.identifier
                {
                    throw PlanningError.duplicateTransformIdentifier
                }

                if let save = request.projectSaveIntent {
                    guard !hasScratchpads else {
                        throw PlanningError.projectCannotRepresentScratchpads
                    }
                    try meter.addItem()
                    try validateProjectSaveIntent(save, meter: &meter)
                    try addAuthority(
                        save.access,
                        side: nil,
                        references: &authorityReferences,
                        authorities: &authorities
                    )
                    for input in sides {
                        guard let identity = input.source.revision.canonicalIdentity else { continue }
                        if case .existing(let revision) = save.destination,
                            sameNode(revision.identity.node, identity.node)
                        {
                            throw PlanningError.projectDestinationAliasesSource(input.side)
                        }
                        if save.destination.canonicalURL.path == identity.canonicalURL.path {
                            throw PlanningError.projectDestinationAliasesSource(input.side)
                        }
                    }
                }

                try meter.addItem()
                let sourceRevisions = sides.map {
                    PositionedRevision(side: $0.side, revision: $0.source.revision)
                }
                let steps = executionSteps(
                    request: request,
                    sides: sides,
                    mode: mode,
                    authorities: authorities
                )
                let digest = try planDigest(
                    request: request,
                    canonicalSides: sides,
                    resolvedMode: mode,
                    meter: &meter
                )
                try meter.checkCancellation()
                let receipt = Receipt(
                    request: request.reference,
                    sourceRevisions: sourceRevisions,
                    planSHA256: digest,
                    retainedByteCount: meter.retainedBytes,
                    planningWorkUnits: meter.completedWork
                )
                return Plan(
                    request: request,
                    sides: sides,
                    resolvedMode: mode,
                    authorities: authorities,
                    steps: steps,
                    receipt: receipt
                )
            } catch let error as PlanningError {
                throw error
            } catch is CancellationError {
                throw PlanningError.cancelled
            } catch {
                throw PlanningError.cancelled
            }
        }

        fileprivate static func validate(
            _ plan: Plan,
            against current: ExecutionValidation
        ) throws {
            do {
                try Task.checkCancellation()
                guard current.request.reference == plan.request.reference else {
                    throw PlanningError.staleRequest(
                        expected: plan.request.reference,
                        actual: current.request.reference
                    )
                }
                guard current.request.limits == plan.request.limits else {
                    throw PlanningError.staleRequestState
                }

                let currentPlan: Plan
                do {
                    currentPlan = try Self.plan(
                        current.request,
                        expecting: plan.request.reference,
                        cancellationCheck: { try Task.checkCancellation() }
                    )
                } catch PlanningError.cancelled {
                    throw PlanningError.cancelled
                } catch {
                    throw PlanningError.staleRequestState
                }
                guard currentPlan.receipt.requestStateSHA256 == plan.receipt.requestStateSHA256 else {
                    throw PlanningError.staleRequestState
                }

                var currentMeter = Meter(
                    limits: plan.request.limits,
                    cancellationCheck: { try Task.checkCancellation() }
                )
                guard current.sources.count == plan.sides.count else {
                    throw PlanningError.invalidExecutionValidation
                }
                for source in current.sources {
                    try Task.checkCancellation()
                    try validate(source.revision, side: source.side, meter: &currentMeter)
                    guard current.sources.count(where: { $0.side == source.side }) == 1 else {
                        throw PlanningError.invalidExecutionValidation
                    }
                }
                guard Set(current.sources.map(\.side)) == Set(plan.sides.map(\.side)) else {
                    throw PlanningError.invalidExecutionValidation
                }
                for side in plan.sides {
                    guard
                        current.sources.first(where: { $0.side == side.side })?.revision
                            == side.source.revision
                    else {
                        throw PlanningError.staleSource(side.side)
                    }
                }

                guard current.authorities.count == plan.authorities.count else {
                    throw PlanningError.invalidExecutionValidation
                }
                for authority in current.authorities {
                    try Task.checkCancellation()
                    try validateAuthority(authority, meter: &currentMeter)
                    guard
                        current.authorities.count(where: {
                            $0.reference == authority.reference
                        }) == 1
                    else {
                        throw PlanningError.invalidExecutionValidation
                    }
                }
                guard
                    Set(current.authorities.map(\.reference.identity))
                        == Set(plan.authorities.map(\.reference.identity))
                else {
                    throw PlanningError.invalidExecutionValidation
                }
                for authority in plan.authorities {
                    guard
                        current.authorities.first(where: {
                            $0.reference == authority.reference
                        }) == authority
                    else {
                        throw PlanningError.staleAuthority(authority.reference)
                    }
                }
                if let filter = current.filter {
                    try validateFilter(filter, meter: &currentMeter)
                }
                guard current.filter == plan.request.filter else { throw PlanningError.staleFilter }
                if let unpacker = current.unpacker {
                    try validateTransform(unpacker, expected: .unpacker, meter: &currentMeter)
                }
                guard current.unpacker == plan.request.transforms.unpacker else {
                    throw PlanningError.staleTransform(.unpacker)
                }
                if let prediffer = current.prediffer {
                    try validateTransform(prediffer, expected: .prediffer, meter: &currentMeter)
                }
                guard current.prediffer == plan.request.transforms.prediffer else {
                    throw PlanningError.staleTransform(.prediffer)
                }
                try validateComparisonOptionsPayload(
                    current.comparisonOptions,
                    meter: &currentMeter
                )
                guard
                    sameComparisonOptionsState(
                        current.comparisonOptions,
                        plan.request.comparisonOptions
                    )
                else {
                    throw PlanningError.staleComparisonOptions
                }
                if let projectDestination = current.projectDestination {
                    try validateProjectDestination(projectDestination, meter: &currentMeter)
                }
                guard current.projectDestination == plan.request.projectSaveIntent?.destination else {
                    throw PlanningError.staleProjectDestination
                }

                var meter = Meter(
                    limits: plan.request.limits,
                    cancellationCheck: { try Task.checkCancellation() }
                )
                let digest = try planDigest(
                    request: plan.request,
                    canonicalSides: plan.sides,
                    resolvedMode: plan.resolvedMode,
                    meter: &meter
                )
                guard digest == plan.receipt.planSHA256 else {
                    throw PlanningError.receiptMismatch
                }
                try Task.checkCancellation()
            } catch is CancellationError {
                throw PlanningError.cancelled
            }
        }

        private static func canonicalSides(
            _ sides: [SideInput],
            meter: inout Meter
        ) throws -> [SideInput] {
            guard sides.count == 2 || sides.count == 3 else {
                throw PlanningError.invalidSideCount(sides.count)
            }
            var seen: Set<Side> = []
            for side in sides {
                try meter.consume()
                guard seen.insert(side.side).inserted else {
                    throw PlanningError.duplicateSide(side.side)
                }
            }
            let expected: Set<Side> =
                sides.count == 2
                ? [.left, .right]
                : [.left, .middle, .right]
            guard seen == expected else {
                throw PlanningError.invalidSideSet(sides.map(\.side).sorted { $0.order < $1.order })
            }
            return sides.sorted { $0.side.order < $1.side.order }
        }

        private static func requireFileRevision(
            _ revision: SourceRevision,
            side: Side
        ) throws -> FileRevision {
            guard case .file(let value) = revision else {
                throw PlanningError.invalidRevision(side: side)
            }
            return value
        }

        private static func requireFolderRevision(
            _ revision: SourceRevision,
            side: Side
        ) throws -> FolderRevision {
            guard case .folder(let value) = revision else {
                throw PlanningError.invalidRevision(side: side)
            }
            return value
        }

        private static func validate(
            _ revision: SourceRevision,
            side: Side,
            meter: inout Meter
        ) throws {
            switch revision {
            case .file(let revision):
                try validate(revision, side: side, meter: &meter)
            case .folder(let revision):
                try validate(revision, side: side, meter: &meter)
            case .scratchpad(let revision):
                try validateDigest(revision.contentSHA256, field: .scratchpad(side))
                try meter.consume()
            }
        }

        private static func validateLocalSource(
            _ source: LocalSource,
            expectedKind: NodeKind,
            side: Side,
            requiredCoverage: AuthorityCoverage,
            meter: inout Meter
        ) throws {
            try validateRequestedURL(
                source.requestedURL,
                role: .requestedSource(side),
                meter: &meter
            )
            try validateRequestedURL(
                source.selection.requestedURL,
                role: .requestedSource(side),
                meter: &meter
            )
            switch source.selection.revision {
            case .file(let revision):
                guard expectedKind == .regularFile else {
                    throw PlanningError.invalidSelectionAttestation(side: side)
                }
                try validate(revision, side: side, meter: &meter)
            case .folder(let revision):
                guard expectedKind == .directory else {
                    throw PlanningError.invalidSelectionAttestation(side: side)
                }
                try validate(revision, side: side, meter: &meter)
            case .scratchpad:
                throw PlanningError.invalidSelectionAttestation(side: side)
            }
            switch source.revision {
            case .file(let revision):
                guard expectedKind == .regularFile else {
                    throw PlanningError.invalidRevision(side: side)
                }
                try validate(revision, side: side, meter: &meter)
            case .folder(let revision):
                guard expectedKind == .directory else {
                    throw PlanningError.invalidRevision(side: side)
                }
                try validate(revision, side: side, meter: &meter)
            case .scratchpad:
                throw PlanningError.invalidRevision(side: side)
            }
            try validateAuthority(source.access, meter: &meter)
            guard source.selection.requestedURL == source.requestedURL,
                source.selection.revision == source.revision,
                source.selection.authority == source.access.reference
            else {
                throw PlanningError.invalidSelectionAttestation(side: side)
            }
            try validateSelectionOrigin(source.selection.origin, meter: &meter)
            guard let identity = source.revision.canonicalIdentity,
                source.access.resource == identity,
                source.access.coverage == requiredCoverage,
                source.access.permissions.contains(.read)
            else {
                throw PlanningError.invalidAuthority(side: side)
            }
        }

        private static func validate(
            _ revision: FileRevision,
            side: Side?,
            meter: inout Meter
        ) throws {
            guard revision.identity.kind == .regularFile,
                (0..<1_000_000_000).contains(revision.modificationTimeNanoseconds),
                (0..<1_000_000_000).contains(revision.statusChangeTimeNanoseconds)
            else {
                throw PlanningError.invalidRevision(side: side)
            }
            try validateCanonicalIdentity(revision.identity, side: side, meter: &meter)
            try validateDigest(revision.contentSHA256, field: .fileContent(side))
            try validateDigest(revision.metadataSHA256, field: .fileMetadata(side))
            guard revision.byteCount <= meter.limits.maximumDeclaredBytes else {
                throw PlanningError.declaredByteLimitExceeded(
                    maximumBytes: meter.limits.maximumDeclaredBytes
                )
            }
            try meter.consume()
        }

        private static func validate(
            _ revision: FolderRevision,
            side: Side?,
            meter: inout Meter
        ) throws {
            guard revision.identity.kind == .directory else {
                throw PlanningError.invalidRevision(side: side)
            }
            try validateCanonicalIdentity(revision.identity, side: side, meter: &meter)
            try validateDigest(revision.treeSHA256, field: .folderTree(side))
            try validateDigest(revision.metadataSHA256, field: .folderMetadata(side))
            guard revision.entryCount <= meter.limits.maximumDeclaredItems else {
                throw PlanningError.declaredItemLimitExceeded(
                    maximumItems: meter.limits.maximumDeclaredItems
                )
            }
            try meter.consume()
        }

        private static func validateCanonicalIdentity(
            _ identity: CanonicalIdentity,
            side: Side?,
            meter: inout Meter
        ) throws {
            guard identity.node.volumeID != 0, identity.node.nodeID != 0 else {
                throw PlanningError.invalidRevision(side: side)
            }
            let role: URLRole = side.map(URLRole.canonicalSource) ?? .authorityResource
            try validateCanonicalURL(
                identity.canonicalURL,
                role: role,
                isDirectory: identity.kind == .directory,
                meter: &meter
            )
        }

        private static func validateRequestedURL(
            _ url: URL,
            role: URLRole,
            meter: inout Meter
        ) throws {
            try validateURLBase(url, role: role, meter: &meter)
        }

        private static func validateCanonicalURL(
            _ url: URL,
            role: URLRole,
            isDirectory: Bool,
            meter: inout Meter
        ) throws {
            try validateURLBase(url, role: role, meter: &meter)
            let rebuilt = URL(fileURLWithPath: url.path, isDirectory: isDirectory).standardizedFileURL
            guard rebuilt.absoluteString == url.absoluteString else {
                throw PlanningError.invalidURL(role: role, issue: .notCanonical)
            }
            guard url.hasDirectoryPath == isDirectory else {
                throw PlanningError.invalidURL(role: role, issue: .wrongDirectoryShape)
            }
            if !isDirectory, url.path == "/" {
                throw PlanningError.invalidURL(role: role, issue: .wrongDirectoryShape)
            }
        }

        private static func validateURLBase(
            _ url: URL,
            role: URLRole,
            meter: inout Meter
        ) throws {
            guard url.isFileURL else { throw PlanningError.invalidURL(role: role, issue: .notFileURL) }
            let absoluteString = url.absoluteString
            let maximumAbsoluteBytes = meter.limits.maximumPathUTF8Bytes * 3 + 128
            let absoluteByteCount = try meter.stringByteCount(
                absoluteString,
                maximum: maximumAbsoluteBytes,
                field: .path,
                limitError: .stringLimitExceeded(
                    field: .path,
                    maximumUTF8Bytes: maximumAbsoluteBytes
                )
            )
            try meter.retain(UInt64(absoluteByteCount))
            guard url.baseURL == nil, url.path.hasPrefix("/") else {
                throw PlanningError.invalidURL(role: role, issue: .relativeURL)
            }
            guard url.host == nil, url.user == nil, url.password == nil, url.port == nil else {
                throw PlanningError.invalidURL(role: role, issue: .authorityComponent)
            }
            guard url.query == nil, url.fragment == nil else {
                throw PlanningError.invalidURL(role: role, issue: .queryOrFragment)
            }
            guard !url.path.isEmpty else { throw PlanningError.invalidURL(role: role, issue: .missingPath) }
            guard !url.path.contains("\0") else {
                throw PlanningError.invalidURL(role: role, issue: .nullByte)
            }
            try meter.addPath(url.path)
        }

        private static func validateSelectionOrigin(
            _ origin: SelectionOrigin,
            meter: inout Meter
        ) throws {
            switch origin {
            case .browse:
                try meter.consume()
            case .history(let identifier, _):
                try validateIdentifier(identifier, field: .historyIdentifier, meter: &meter)
            case .entered:
                try meter.consume()
            }
        }

        private static func validateAuthority(
            _ authority: AccessAuthority,
            meter: inout Meter
        ) throws {
            let validBits =
                AuthorityPermissions.read.rawValue
                | AuthorityPermissions.create.rawValue
                | AuthorityPermissions.replace.rawValue
            guard authority.permissions.rawValue != 0,
                authority.permissions.rawValue & ~validBits == 0
            else {
                throw PlanningError.invalidAuthority(side: nil)
            }
            try validateCanonicalIdentity(authority.resource, side: nil, meter: &meter)
        }

        private static func addAuthority(
            _ authority: AccessAuthority,
            side: Side?,
            references: inout Set<AuthorityReference>,
            authorities: inout [AccessAuthority]
        ) throws {
            guard
                !authorities.contains(where: {
                    $0.reference.identity == authority.reference.identity
                }), references.insert(authority.reference).inserted
            else {
                throw PlanningError.duplicateAuthority(authority.reference)
            }
            authorities.append(authority)
        }

        private static func addSourceNode(
            _ node: NodeIdentity,
            side: Side,
            existing: inout [(Side, NodeIdentity)]
        ) throws {
            if let duplicate = existing.first(where: { sameNode($0.1, node) }) {
                throw PlanningError.duplicateSourceIdentity(first: duplicate.0, second: side)
            }
            existing.append((side, node))
        }

        private static func addSourceCanonicalPath(
            _ path: String,
            side: Side,
            existing: inout [(Side, String)]
        ) throws {
            if let duplicate = existing.first(where: { $0.1 == path }) {
                throw PlanningError.duplicateSourceIdentity(first: duplicate.0, second: side)
            }
            existing.append((side, path))
        }

        private static func sameNode(_ first: NodeIdentity, _ second: NodeIdentity) -> Bool {
            first.volumeID == second.volumeID && first.nodeID == second.nodeID
        }

        private static func validateLabel(_ label: String, meter: inout Meter) throws {
            _ = try meter.stringByteCount(
                label,
                maximum: meter.limits.maximumLabelUTF8Bytes,
                field: .label,
                limitError: .stringLimitExceeded(
                    field: .label,
                    maximumUTF8Bytes: meter.limits.maximumLabelUTF8Bytes
                )
            )
            guard !label.isEmpty, !label.contains("\0"), label.contains(where: { !$0.isWhitespace }) else {
                throw PlanningError.stringLimitExceeded(field: .label, maximumUTF8Bytes: meter.limits.maximumLabelUTF8Bytes)
            }
            try meter.addStringBytes(label, field: .label)
        }

        private static func validateIdentifier(
            _ value: String,
            field: StringField,
            meter: inout Meter
        ) throws {
            let count = try meter.stringByteCount(
                value,
                maximum: meter.limits.maximumStringUTF8Bytes,
                field: field,
                limitError: .stringLimitExceeded(
                    field: field,
                    maximumUTF8Bytes: meter.limits.maximumStringUTF8Bytes
                )
            )
            guard count > 0,
                value.utf8.allSatisfy({ byte in
                    (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)
                        || (0x61...0x7A).contains(byte) || byte == 0x2D || byte == 0x2E
                        || byte == 0x2F || byte == 0x3A || byte == 0x5F
                })
            else {
                throw PlanningError.stringLimitExceeded(
                    field: field,
                    maximumUTF8Bytes: meter.limits.maximumStringUTF8Bytes
                )
            }
            try meter.addStringByteCount(count)
        }

        private static func validateFilter(
            _ filter: FilterSelection,
            meter: inout Meter
        ) throws {
            do {
                try validateIdentifier(filter.identifier, field: .identifier, meter: &meter)
                try validateDigest(filter.definitionSHA256, field: .filter)
            } catch is CancellationError {
                throw PlanningError.cancelled
            } catch PlanningError.cancelled {
                throw PlanningError.cancelled
            } catch {
                throw PlanningError.invalidFilterSelection
            }
        }

        private static func validateTransforms(
            _ transforms: TransformSelections,
            shape: SourceShape,
            meter: inout Meter
        ) throws {
            for (expected, selection) in [
                (TransformCapability.unpacker, transforms.unpacker),
                (TransformCapability.prediffer, transforms.prediffer)
            ] {
                guard let selection else { continue }
                try meter.addItem()
                guard shape == .files else {
                    throw PlanningError.transformRequiresFiles(expected)
                }
                guard selection.capability == expected else {
                    throw PlanningError.invalidTransformSelection(expected)
                }
                do {
                    try validateTransform(selection, expected: expected, meter: &meter)
                } catch is CancellationError {
                    throw PlanningError.cancelled
                } catch PlanningError.cancelled {
                    throw PlanningError.cancelled
                } catch {
                    throw PlanningError.invalidTransformSelection(expected)
                }
            }
        }

        private static func validateTransform(
            _ selection: TransformSelection,
            expected: TransformCapability,
            meter: inout Meter
        ) throws {
            guard selection.capability == expected else {
                throw PlanningError.invalidTransformSelection(expected)
            }
            try validateIdentifier(selection.identifier, field: .identifier, meter: &meter)
            try validateDigest(selection.policySHA256, field: .transformPolicy(expected))
            try validateDigest(
                selection.configurationSHA256,
                field: .transformConfiguration(expected)
            )
        }

        private static func validateComparisonOptions(
            _ options: ComparisonOptions,
            intent: CompareButtonIntent,
            shape: SourceShape,
            sides: [SideInput],
            meter: inout Meter
        ) throws -> ComparisonMode {
            try validateComparisonOptionsPayload(options, meter: &meter)

            let requestedMode: ComparisonMode
            switch intent {
            case .primary:
                requestedMode = options.mode
            case .compareAs(let mode):
                guard mode != .automatic else {
                    throw PlanningError.compareAsRequiresExplicitMode
                }
                guard options.mode == .automatic || options.mode == mode else {
                    throw PlanningError.compareAsOptionsMismatch(
                        expected: mode,
                        actual: options.mode
                    )
                }
                requestedMode = mode
            }

            if requestedMode != .automatic { return requestedMode }
            switch shape {
            case .folders: return .folder
            case .scratchpads: return .text
            case .files:
                let modes = sides.compactMap { input -> ComparisonMode? in
                    guard case .file(let source) = input.source,
                        case .file(let revision) = source.revision
                    else {
                        return nil
                    }
                    return recognizedMode(
                        forExtension: revision.identity.canonicalURL.pathExtension.lowercased()
                    )
                }
                guard let first = modes.first,
                    modes.count == sides.count,
                    modes.allSatisfy({ $0 == first })
                else {
                    throw PlanningError.automaticModeRequiresExplicitSelection
                }
                return first
            case .filesAndScratchpads:
                throw PlanningError.automaticModeRequiresExplicitSelection
            }
        }

        private static func validateComparisonOptionsPayload(
            _ options: ComparisonOptions,
            meter: inout Meter
        ) throws {
            guard case .exact(let exact) = options else { return }
            guard exact.mode != .automatic else {
                throw PlanningError.exactOptionsRequireExplicitMode
            }
            try validateIdentifier(
                exact.schemaIdentifier,
                field: .schemaIdentifier,
                meter: &meter
            )
            guard exact.canonicalData.count <= meter.limits.maximumOptionBytes else {
                throw PlanningError.optionDataTooLarge(
                    maximumBytes: meter.limits.maximumOptionBytes
                )
            }
            try meter.retain(UInt64(exact.canonicalData.count))
            try validateDigest(exact.dataSHA256, field: .comparisonOptions)
            let digest = try hash(exact.canonicalData, meter: &meter)
            guard digest == exact.dataSHA256 else {
                throw PlanningError.comparisonOptionsDigestMismatch
            }
        }

        private static func sameComparisonOptionsState(
            _ first: ComparisonOptions,
            _ second: ComparisonOptions
        ) -> Bool {
            switch (first, second) {
            case (.defaults(let firstMode), .defaults(let secondMode)):
                firstMode == secondMode
            case (.exact(let firstOptions), .exact(let secondOptions)):
                firstOptions.mode == secondOptions.mode
                    && firstOptions.schemaIdentifier == secondOptions.schemaIdentifier
                    && firstOptions.schemaRevision == secondOptions.schemaRevision
                    && firstOptions.canonicalData.count == secondOptions.canonicalData.count
                    && firstOptions.dataSHA256 == secondOptions.dataSHA256
            default:
                false
            }
        }

        private static func recognizedMode(forExtension fileExtension: String) -> ComparisonMode? {
            let imageExtensions: Set<String> = [
                "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff"
            ]
            let tableExtensions: Set<String> = ["csv", "tsv"]
            let webpageExtensions: Set<String> = ["htm", "html", "shtml", "xhtml"]
            let binaryExtensions: Set<String> = [
                "7z", "a", "app", "bin", "bz2", "class", "dmg", "doc", "docx", "dylib",
                "eot", "epub", "exe", "gz", "ico", "jar", "macho", "mov", "mp3", "mp4",
                "o", "otf", "pdf", "pkg", "ppt", "pptx", "rar", "so", "tar", "ttf",
                "wav", "webp", "woff", "woff2", "xls", "xlsx", "xz", "zip"
            ]
            let textExtensions: Set<String> = [
                "adb", "ads", "ascx", "asp", "bat", "bas", "c", "cc", "cfg", "clo",
                "cmd", "conf", "cpp", "cppm", "cs", "css", "cxx", "d", "di", "diff",
                "dtd", "f", "f77", "f90", "for", "fs", "fsx", "go", "h", "hh", "hpp",
                "hxx", "ini", "inl", "ixx", "java", "js", "json", "jsx", "log", "lua",
                "m", "markdown", "md", "mkd", "mkdn", "mm", "nsh", "nsi", "patch", "php",
                "pl", "pm", "properties", "ps1", "psd1", "psm1", "py", "rb", "rc", "rs",
                "rst", "scss", "sh", "sql", "strings", "swift", "tcl", "tex", "toml", "ts",
                "tsx", "txt", "v", "vb", "vbs", "vhd", "vhdl", "vue", "xml", "yaml", "yml"
            ]
            if imageExtensions.contains(fileExtension) { return .image }
            if tableExtensions.contains(fileExtension) { return .table }
            if webpageExtensions.contains(fileExtension) { return .webpage }
            if binaryExtensions.contains(fileExtension) { return .binary }
            if textExtensions.contains(fileExtension) { return .text }
            return nil
        }

        private static func validateShape(_ shape: SourceShape, mode: ComparisonMode) throws {
            switch shape {
            case .folders:
                guard mode == .folder else {
                    throw PlanningError.incompatibleMode(mode: mode, shape: shape)
                }
            case .scratchpads, .filesAndScratchpads:
                guard mode == .text else {
                    throw PlanningError.incompatibleMode(mode: mode, shape: shape)
                }
            case .files:
                guard mode != .folder else {
                    throw PlanningError.incompatibleMode(mode: mode, shape: shape)
                }
            }
        }

        private static func validateProjectSaveIntent(
            _ intent: ProjectSaveIntent,
            meter: inout Meter
        ) throws {
            try validateRequestedURL(
                intent.requestedURL,
                role: .requestedProjectDestination,
                meter: &meter
            )
            try validateRequestedURL(
                intent.selection.requestedURL,
                role: .requestedProjectDestination,
                meter: &meter
            )
            try validateProjectDestination(intent.selection.destination, meter: &meter)
            try validateProjectDestination(intent.destination, meter: &meter)
            try validateAuthority(intent.access, meter: &meter)
            guard intent.selection.requestedURL == intent.requestedURL,
                intent.selection.destination == intent.destination,
                intent.selection.authority == intent.access.reference
            else {
                throw PlanningError.invalidProjectDestination
            }
            try validateSelectionOrigin(intent.selection.origin, meter: &meter)
            switch intent.destination {
            case .absent(let location):
                guard location.parent.kind == .directory,
                    intent.access.resource == location.parent,
                    intent.access.coverage == .directoryTree,
                    intent.access.permissions.contains(.create)
                else {
                    throw PlanningError.invalidProjectDestination
                }
            case .existing(let revision):
                guard intent.access.resource == revision.identity,
                    intent.access.coverage == .exactItem,
                    intent.access.permissions.contains([.read, .replace])
                else {
                    throw PlanningError.invalidProjectDestination
                }
            }
            guard
                intent.destination.canonicalURL.pathExtension.lowercased()
                    == (intent.format == .macMerge ? "macmerge" : "winmerge")
            else {
                throw PlanningError.invalidProjectDestination
            }
        }

        private static func validateProjectDestination(
            _ destination: ProjectDestinationState,
            meter: inout Meter
        ) throws {
            switch destination {
            case .absent(let location):
                guard location.parent.kind == .directory else {
                    throw PlanningError.invalidProjectDestination
                }
                try validateCanonicalIdentity(location.parent, side: nil, meter: &meter)
                try validateCanonicalURL(
                    location.canonicalURL,
                    role: .canonicalProjectDestination,
                    isDirectory: false,
                    meter: &meter
                )
                guard
                    location.canonicalURL.deletingLastPathComponent().path
                        == location.parent.canonicalURL.path
                else {
                    throw PlanningError.invalidURL(
                        role: .canonicalProjectDestination,
                        issue: .parentMismatch
                    )
                }
            case .existing(let revision):
                try validate(revision, side: nil, meter: &meter)
            }
        }

        private static func executionSteps(
            request: Request,
            sides: [SideInput],
            mode: ComparisonMode,
            authorities: [AccessAuthority]
        ) -> [ExecutionStep] {
            var steps: [ExecutionStep] = [.validateExactState]
            steps.append(contentsOf: authorities.map { .acquireAuthority($0.reference) })
            steps.append(contentsOf: sides.map { .materializeSource($0.side) })
            steps.append(.validateImmediatelyAfterMaterialization)
            if let filter = request.filter { steps.append(.applyFilter(filter)) }
            if let unpacker = request.transforms.unpacker { steps.append(.runTransform(unpacker)) }
            if let prediffer = request.transforms.prediffer { steps.append(.runTransform(prediffer)) }
            steps.append(.validateImmediatelyBeforePublication)
            steps.append(.compare(mode: mode, intent: request.compareButtonIntent))
            if let save = request.projectSaveIntent {
                steps.append(.validateImmediatelyBeforePublication)
                steps.append(.saveProject(save))
            }
            return steps
        }

        private static func validateDigest(_ digest: Data, field: DigestField) throws {
            guard digest.count == 32 else { throw PlanningError.invalidDigest(field) }
        }

        private static func hash(_ text: String, meter: inout Meter) throws -> Data {
            var hash = SHA256()
            var pendingWork: UInt64 = 0
            for byte in text.utf8 {
                hash.update(byte)
                pendingWork += 1
                if pendingWork == meter.limits.cancellationCheckInterval {
                    try meter.consume(pendingWork)
                    pendingWork = 0
                }
            }
            try meter.consume(pendingWork)
            return hash.finalize()
        }

        private static func hash(_ data: Data, meter: inout Meter) throws -> Data {
            var hash = SHA256()
            var pendingWork: UInt64 = 0
            for byte in data {
                hash.update(byte)
                pendingWork += 1
                if pendingWork == meter.limits.cancellationCheckInterval {
                    try meter.consume(pendingWork)
                    pendingWork = 0
                }
            }
            try meter.consume(pendingWork)
            return hash.finalize()
        }

        private static func planDigest(
            request: Request,
            canonicalSides: [SideInput],
            resolvedMode: ComparisonMode,
            meter: inout Meter
        ) throws -> Data {
            var encoder = DigestEncoder(meter: meter)
            try encoder.string("MacMerge.UnifiedOpenWorkflow.Plan.v1")
            try encoder.requestReference(request.reference)
            try encoder.unsigned(UInt64(canonicalSides.count))
            for side in canonicalSides { try encoder.sideInput(side) }
            try encoder.boolean(request.recursive)
            try encoder.optional(request.filter) { encoder, value in
                try encoder.filter(value)
            }
            try encoder.transforms(request.transforms)
            try encoder.options(request.comparisonOptions)
            try encoder.optional(request.projectSaveIntent) { encoder, value in
                try encoder.projectSave(value)
            }
            try encoder.compareIntent(request.compareButtonIntent)
            try encoder.string(resolvedMode.rawValue)
            try encoder.limits(request.limits)
            let result = encoder.finalize()
            meter = encoder.meter
            return result
        }
    }
}

extension UnifiedOpenWorkflow {
    fileprivate struct Meter {
        let limits: Limits
        let cancellationCheck: CancellationCheck
        private(set) var completedWork: UInt64 = 0
        private(set) var retainedBytes: UInt64 = 0
        private var itemCount = 0
        private var totalPathBytes = 0
        private var totalStringBytes = 0

        init(limits: Limits, cancellationCheck: @escaping CancellationCheck) {
            self.limits = limits
            self.cancellationCheck = cancellationCheck
        }

        mutating func consume(_ amount: UInt64 = 1) throws {
            guard amount <= limits.maximumWorkUnits,
                completedWork <= limits.maximumWorkUnits - amount
            else {
                throw PlanningError.workLimitExceeded(maximumUnits: limits.maximumWorkUnits)
            }
            let priorBucket = completedWork / limits.cancellationCheckInterval
            completedWork += amount
            if completedWork / limits.cancellationCheckInterval != priorBucket {
                try checkCancellation()
            }
        }

        func checkCancellation() throws {
            do {
                try cancellationCheck()
            } catch {
                throw PlanningError.cancelled
            }
        }

        mutating func addItem() throws {
            guard itemCount < limits.maximumItemCount else {
                throw PlanningError.itemLimitExceeded(maximumItems: limits.maximumItemCount)
            }
            itemCount += 1
            try consume()
        }

        mutating func retain(_ bytes: UInt64) throws {
            guard bytes <= limits.maximumRetainedBytes,
                retainedBytes <= limits.maximumRetainedBytes - bytes
            else {
                throw PlanningError.retainedDataTooLarge(maximumBytes: limits.maximumRetainedBytes)
            }
            retainedBytes += bytes
        }

        mutating func addPath(_ value: String) throws {
            let count = try stringByteCount(
                value,
                maximum: limits.maximumPathUTF8Bytes,
                field: .path,
                limitError: .stringLimitExceeded(
                    field: .path,
                    maximumUTF8Bytes: limits.maximumPathUTF8Bytes
                )
            )
            guard totalPathBytes <= limits.maximumTotalPathUTF8Bytes - count else {
                throw PlanningError.totalPathLimitExceeded(
                    maximumUTF8Bytes: limits.maximumTotalPathUTF8Bytes
                )
            }
            totalPathBytes += count
            try retain(UInt64(count))
        }

        mutating func addStringBytes(_ value: String, field: StringField) throws {
            let count = try stringByteCount(
                value,
                maximum: limits.maximumStringUTF8Bytes,
                field: field,
                limitError: .stringLimitExceeded(
                    field: field,
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            )
            try addStringByteCount(count)
        }

        mutating func addStringByteCount(_ count: Int) throws {
            guard totalStringBytes <= limits.maximumTotalStringUTF8Bytes - count else {
                throw PlanningError.totalStringLimitExceeded(
                    maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
                )
            }
            totalStringBytes += count
            try retain(UInt64(count))
        }

        mutating func stringByteCount(
            _ value: String,
            maximum: Int,
            field: StringField,
            limitError: PlanningError
        ) throws -> Int {
            var count = 0
            var pendingWork: UInt64 = 0
            for _ in value.utf8 {
                guard count < maximum else { throw limitError }
                count += 1
                pendingWork += 1
                if pendingWork == limits.cancellationCheckInterval {
                    try consume(pendingWork)
                    pendingWork = 0
                }
            }
            try consume(pendingWork)
            return count
        }
    }

    fileprivate struct DigestEncoder {
        var meter: Meter
        private var hash = SHA256()

        init(meter: Meter) {
            self.meter = meter
        }

        mutating func finalize() -> Data {
            hash.finalize()
        }

        mutating func byte(_ value: UInt8) throws {
            hash.update(value)
            try meter.consume()
        }

        mutating func boolean(_ value: Bool) throws {
            try byte(value ? 1 : 0)
        }

        mutating func unsigned(_ value: UInt64) throws {
            for shift in stride(from: 56, through: 0, by: -8) {
                try byte(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }

        mutating func signed(_ value: Int64) throws {
            try unsigned(UInt64(bitPattern: value))
        }

        mutating func signed32(_ value: Int32) throws {
            try unsigned(UInt64(UInt32(bitPattern: value)))
        }

        mutating func data(_ value: Data) throws {
            try unsigned(UInt64(value.count))
            for byteValue in value { try byte(byteValue) }
        }

        mutating func string(_ value: String) throws {
            try unsigned(UInt64(value.utf8.count))
            for byteValue in value.utf8 { try byte(byteValue) }
        }

        mutating func uuid(_ value: UUID) throws {
            try string(value.uuidString)
        }

        mutating func optional<Value>(
            _ value: Value?,
            encode: (inout DigestEncoder, Value) throws -> Void
        ) throws {
            guard let value else {
                try byte(0)
                return
            }
            try byte(1)
            try encode(&self, value)
        }

        mutating func requestReference(_ value: RequestReference) throws {
            try uuid(value.identity)
            try unsigned(value.generation)
        }

        mutating func node(_ value: NodeIdentity) throws {
            try unsigned(value.volumeID)
            try unsigned(value.nodeID)
            try unsigned(value.generation)
        }

        mutating func canonicalIdentity(_ value: CanonicalIdentity) throws {
            try string(value.kind.rawValue)
            try string(value.canonicalURL.absoluteString)
            try node(value.node)
        }

        mutating func fileRevision(_ value: FileRevision) throws {
            try canonicalIdentity(value.identity)
            try unsigned(value.byteCount)
            try signed(value.modificationTimeSeconds)
            try signed32(value.modificationTimeNanoseconds)
            try signed(value.statusChangeTimeSeconds)
            try signed32(value.statusChangeTimeNanoseconds)
            try data(value.contentSHA256)
            try data(value.metadataSHA256)
        }

        mutating func folderRevision(_ value: FolderRevision) throws {
            try canonicalIdentity(value.identity)
            try unsigned(value.entryCount)
            try data(value.treeSHA256)
            try data(value.metadataSHA256)
        }

        mutating func scratchpadRevision(_ value: ScratchpadRevision) throws {
            try uuid(value.identity)
            try unsigned(value.generation)
            try data(value.contentSHA256)
        }

        mutating func sourceRevision(_ value: SourceRevision) throws {
            switch value {
            case .file(let revision):
                try byte(0)
                try fileRevision(revision)
            case .folder(let revision):
                try byte(1)
                try folderRevision(revision)
            case .scratchpad(let revision):
                try byte(2)
                try scratchpadRevision(revision)
            }
        }

        mutating func authorityReference(_ value: AuthorityReference) throws {
            try uuid(value.identity)
            try unsigned(value.generation)
        }

        mutating func authority(_ value: AccessAuthority) throws {
            try authorityReference(value.reference)
            try canonicalIdentity(value.resource)
            try string(value.coverage.rawValue)
            try byte(value.permissions.rawValue)
        }

        mutating func selectionOrigin(_ value: SelectionOrigin) throws {
            switch value {
            case .browse(let session, let index):
                try byte(0)
                try uuid(session)
                try unsigned(index)
            case .history(let identifier, let revision):
                try byte(1)
                try string(identifier)
                try unsigned(revision)
            case .entered(let revision):
                try byte(2)
                try unsigned(revision)
            }
        }

        mutating func localSource(_ value: LocalSource) throws {
            try string(value.requestedURL.absoluteString)
            try sourceRevision(value.revision)
            try string(value.selection.requestedURL.absoluteString)
            try sourceRevision(value.selection.revision)
            try authorityReference(value.selection.authority)
            try selectionOrigin(value.selection.origin)
            try authority(value.access)
        }

        mutating func source(_ value: Source) throws {
            switch value {
            case .file(let source):
                try byte(0)
                try localSource(source)
            case .folder(let source):
                try byte(1)
                try localSource(source)
            case .scratchpad(let source):
                try byte(2)
                try scratchpadRevision(source.revision)
                try unsigned(UInt64(source.text.utf8.count))
                try data(source.revision.contentSHA256)
                try optional(source.label) { encoder, label in try encoder.string(label) }
            }
        }

        mutating func sideInput(_ value: SideInput) throws {
            try string(value.side.rawValue)
            try source(value.source)
            try boolean(value.readOnly)
        }

        mutating func filter(_ value: FilterSelection) throws {
            try string(value.identifier)
            try unsigned(value.revision)
            try data(value.definitionSHA256)
        }

        mutating func transform(_ value: TransformSelection) throws {
            try string(value.capability.rawValue)
            try string(value.identifier)
            try unsigned(value.revision)
            try data(value.policySHA256)
            try data(value.configurationSHA256)
        }

        mutating func transforms(_ value: TransformSelections) throws {
            try optional(value.unpacker) { encoder, selection in try encoder.transform(selection) }
            try optional(value.prediffer) { encoder, selection in try encoder.transform(selection) }
        }

        mutating func options(_ value: ComparisonOptions) throws {
            switch value {
            case .defaults(let mode):
                try byte(0)
                try string(mode.rawValue)
            case .exact(let options):
                try byte(1)
                try string(options.mode.rawValue)
                try string(options.schemaIdentifier)
                try unsigned(options.schemaRevision)
                try unsigned(UInt64(options.canonicalData.count))
                try data(options.dataSHA256)
            }
        }

        mutating func compareIntent(_ value: CompareButtonIntent) throws {
            switch value {
            case .primary:
                try byte(0)
            case .compareAs(let mode):
                try byte(1)
                try string(mode.rawValue)
            }
        }

        mutating func location(_ value: CanonicalLocation) throws {
            try string(value.canonicalURL.absoluteString)
            try canonicalIdentity(value.parent)
        }

        mutating func destination(_ value: ProjectDestinationState) throws {
            switch value {
            case .absent(let location):
                try byte(0)
                try self.location(location)
            case .existing(let revision):
                try byte(1)
                try fileRevision(revision)
            }
        }

        mutating func projectSave(_ value: ProjectSaveIntent) throws {
            try string(value.format.rawValue)
            try string(value.requestedURL.absoluteString)
            try destination(value.destination)
            try string(value.selection.requestedURL.absoluteString)
            try destination(value.selection.destination)
            try authorityReference(value.selection.authority)
            try selectionOrigin(value.selection.origin)
            try authority(value.access)
        }

        mutating func limits(_ value: Limits) throws {
            try unsigned(UInt64(value.maximumPathUTF8Bytes))
            try unsigned(UInt64(value.maximumTotalPathUTF8Bytes))
            try unsigned(UInt64(value.maximumStringUTF8Bytes))
            try unsigned(UInt64(value.maximumTotalStringUTF8Bytes))
            try unsigned(UInt64(value.maximumLabelUTF8Bytes))
            try unsigned(UInt64(value.maximumScratchpadUTF8Bytes))
            try unsigned(UInt64(value.maximumCombinedScratchpadUTF8Bytes))
            try unsigned(UInt64(value.maximumOptionBytes))
            try unsigned(UInt64(value.maximumItemCount))
            try unsigned(value.maximumDeclaredBytes)
            try unsigned(value.maximumDeclaredItems)
            try unsigned(value.maximumRetainedBytes)
            try unsigned(value.maximumWorkUnits)
            try unsigned(value.cancellationCheckInterval)
        }
    }

    fileprivate struct SHA256 {
        private static let initialState: [UInt32] = [
            0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A,
            0x510E_527F, 0x9B05_688C, 0x1F83_D9AB, 0x5BE0_CD19
        ]
        private static let constants: [UInt32] = [
            0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5,
            0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
            0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3,
            0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
            0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC,
            0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
            0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7,
            0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
            0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13,
            0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
            0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3,
            0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
            0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5,
            0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
            0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208,
            0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2
        ]

        private var state = initialState
        private var buffer: [UInt8] = []
        private var byteCount: UInt64 = 0

        init() {
            buffer.reserveCapacity(64)
        }

        mutating func update(_ byte: UInt8) {
            byteCount &+= 1
            buffer.append(byte)
            if buffer.count == 64 {
                compress(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        mutating func finalize() -> Data {
            let bitCount = byteCount &* 8
            buffer.append(0x80)
            if buffer.count > 56 {
                buffer.append(contentsOf: repeatElement(0, count: 64 - buffer.count))
                compress(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            buffer.append(contentsOf: repeatElement(0, count: 56 - buffer.count))
            for shift in stride(from: 56, through: 0, by: -8) {
                buffer.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
            }
            compress(buffer)
            var result = Data()
            result.reserveCapacity(32)
            for word in state {
                result.append(UInt8(truncatingIfNeeded: word >> 24))
                result.append(UInt8(truncatingIfNeeded: word >> 16))
                result.append(UInt8(truncatingIfNeeded: word >> 8))
                result.append(UInt8(truncatingIfNeeded: word))
            }
            return result
        }

        private mutating func compress(_ block: [UInt8]) {
            var schedule = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let offset = index * 4
                schedule[index] =
                    UInt32(block[offset]) << 24
                    | UInt32(block[offset + 1]) << 16
                    | UInt32(block[offset + 2]) << 8
                    | UInt32(block[offset + 3])
            }
            for index in 16..<64 {
                let first = schedule[index - 15]
                let second = schedule[index - 2]
                let sigma0 = rotateRight(first, by: 7) ^ rotateRight(first, by: 18) ^ (first >> 3)
                let sigma1 = rotateRight(second, by: 17) ^ rotateRight(second, by: 19) ^ (second >> 10)
                schedule[index] =
                    schedule[index - 16] &+ sigma0
                    &+ schedule[index - 7] &+ sigma1
            }

            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]
            for index in 0..<64 {
                let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ (~e & g)
                let temporary1 = h &+ sum1 &+ choice &+ Self.constants[index] &+ schedule[index]
                let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = sum0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }
            state[0] &+= a
            state[1] &+= b
            state[2] &+= c
            state[3] &+= d
            state[4] &+= e
            state[5] &+= f
            state[6] &+= g
            state[7] &+= h
        }

        private func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
            (value >> amount) | (value << (32 - amount))
        }
    }
}
