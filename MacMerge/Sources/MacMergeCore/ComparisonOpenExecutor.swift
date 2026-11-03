import CryptoKit
import Foundation

/// Plan-only unified comparison-open executor.
///
/// Binds an already-planned `ComparisonOpenPlan` (two/three-side Text, Table, Binary, Image, Webpage,
/// or Folder, including clipboard, scratchpad, remote-webpage, transform, and project-save inputs) to
/// exact sandbox-scope authorities, freshness checks, and a deterministic receipt. It performs no
/// filesystem, network, pasteboard, or UI work and creates no windows or views:
///
/// - Local reads, offline webpage bytes, clipboard revalidation, external-tool planning, alias
///   resolution, and project-save enforcement stay in `plan.materializationRequirements` for a future
///   native materializer.
/// - Conflict files route here as ordinary text-mode sides; `conflictCapable` only signals that the
///   downstream `ConflictFileParser` / `ConflictComparisonWorkflow` owns marker parsing.
/// - Clipboard pairs route as validated open sides; without caller-supplied `ClipboardComparisonInputs`
///   evidence the intent retains `clipboardPairValidation` for the native layer.
/// - Project inputs route as a retained save intent plus payload; destination enforcement stays with
///   the native saver under `projectSaveValidation`.
///
/// Swap handling re-plans through `ComparisonOpenRequestPlanner`, so the swapped request receives a
/// new identity and every intent bound to the older identity goes stale. View, materializer, and app
/// routing integration remain missing; this file claims none of them.
public enum ComparisonOpenExecutor: Sendable {
    public struct SandboxScope: Hashable, Sendable {
        /// Exact validated lexical paths the caller may read.
        public let readableNormalizedPaths: Set<String>
        /// Exact validated lexical paths the caller may create or replace.
        public let writableNormalizedPaths: Set<String>

        public init(
            readableNormalizedPaths: Set<String> = [],
            writableNormalizedPaths: Set<String> = []
        ) {
            self.readableNormalizedPaths = readableNormalizedPaths
            self.writableNormalizedPaths = writableNormalizedPaths
        }

        public func covers(_ requirement: ComparisonOpenLocalAccessRequirement) -> Bool {
            switch requirement.purpose {
            case .readRegularFile, .readDirectoryTree:
                readableNormalizedPaths.contains(requirement.normalizedPath)
            case .writeProjectFile:
                writableNormalizedPaths.contains(requirement.normalizedPath)
            }
        }
    }

    public struct Limits: Equatable, Sendable {
        public static let `default` = Limits()

        /// Bound on retained sandbox-scope entries the executor will honor.
        public let maximumCoveredPaths: Int
        /// Bound on executor-owned validation steps.
        public let maximumWorkUnits: Int

        public init(maximumCoveredPaths: Int = 16, maximumWorkUnits: Int = 4_096) {
            self.maximumCoveredPaths = maximumCoveredPaths
            self.maximumWorkUnits = maximumWorkUnits
        }
    }

    public enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case request(ComparisonOpenRequestError)
        /// A required local path has no exact sandbox-scope entry. The path itself is redacted.
        case sandboxScopeMissing
        /// Supplied clipboard evidence does not match the planned snapshots.
        case staleClipboardEvidence
        case receiptMismatch

        public var errorDescription: String? {
            switch self {
            case .request(let error):
                error.errorDescription
            case .sandboxScopeMissing:
                "Comparison open executor lacks sandbox scope for a required local path."
            case .staleClipboardEvidence:
                "Comparison open executor clipboard evidence does not match the planned snapshots."
            case .receiptMismatch:
                "Comparison open executor receipt does not match its plan."
            }
        }
    }

    /// Deterministic binding between an intent and the exact plan that produced it.
    public struct Receipt: Hashable, Sendable {
        public let requestIdentity: ComparisonOpenRequestIdentity
        public let mode: ComparisonProject.Mode
        public let isThreeWay: Bool
        public let digest: Data

        public init(
            requestIdentity: ComparisonOpenRequestIdentity,
            mode: ComparisonProject.Mode,
            isThreeWay: Bool,
            digest: Data
        ) {
            self.requestIdentity = requestIdentity
            self.mode = mode
            self.isThreeWay = isThreeWay
            self.digest = digest
        }
    }

    /// Mandatory contract for the future native materializer. This file supplies no executor beyond
    /// plan binding, so the contract only declares what publication must honor.
    public struct ExecutorContract: Hashable, Sendable {
        public static let required = ExecutorContract()

        public let pathResolution = "descriptorRelativeNoFollowFromPinnedCanonicalParent"
        public let authority = "reacquireExactScopeBeforeMaterialization"
        public let revision = "revalidateAllInputsBeforeMaterializationAndBeforeEveryPublication"
        public let publication = "serializeValidationAndEachEffectPublication"
        public let cancellation = "cancellationBeforeEffectsAndPublication"

        public init() {}
    }

    /// Validated open intent. It authorizes nothing by itself; the native layer must still fulfill
    /// `materializationRequirements` under `executorContract` before publishing any comparison.
    public struct OpenIntent: Equatable, Sendable {
        public let requestIdentity: ComparisonOpenRequestIdentity
        public let mode: ComparisonProject.Mode
        public let isThreeWay: Bool
        public let sides: [ComparisonOpenPlannedSide]
        public let modeOptions: ComparisonOpenModeOptions
        public let recursive: Bool
        public let filenameFilter: ComparisonOpenFilenameFilter?
        public let transforms: ComparisonOpenTransforms
        public let projectSaveIntent: ComparisonOpenProjectSaveIntent?
        public let normalizedProjectDestinationPath: String?
        public let hasProjectPayload: Bool
        public let materializationRequirements: [ComparisonOpenMaterializationRequirement]
        public let unsupportedFeatures: [ComparisonOpenUnsupportedFeature]
        /// True for text mode, where downstream conflict parsing may apply. No parsing happens here.
        public let conflictCapable: Bool
        /// Positions whose sources are clipboard snapshots, in pane order.
        public let clipboardSides: [ComparisonOpenSidePosition]
        public let receipt: Receipt
        public let executorContract = ExecutorContract.required

        public init(
            requestIdentity: ComparisonOpenRequestIdentity,
            mode: ComparisonProject.Mode,
            isThreeWay: Bool,
            sides: [ComparisonOpenPlannedSide],
            modeOptions: ComparisonOpenModeOptions,
            recursive: Bool,
            filenameFilter: ComparisonOpenFilenameFilter?,
            transforms: ComparisonOpenTransforms,
            projectSaveIntent: ComparisonOpenProjectSaveIntent?,
            normalizedProjectDestinationPath: String?,
            hasProjectPayload: Bool,
            materializationRequirements: [ComparisonOpenMaterializationRequirement],
            unsupportedFeatures: [ComparisonOpenUnsupportedFeature],
            conflictCapable: Bool,
            clipboardSides: [ComparisonOpenSidePosition],
            receipt: Receipt
        ) {
            self.requestIdentity = requestIdentity
            self.mode = mode
            self.isThreeWay = isThreeWay
            self.sides = sides
            self.modeOptions = modeOptions
            self.recursive = recursive
            self.filenameFilter = filenameFilter
            self.transforms = transforms
            self.projectSaveIntent = projectSaveIntent
            self.normalizedProjectDestinationPath = normalizedProjectDestinationPath
            self.hasProjectPayload = hasProjectPayload
            self.materializationRequirements = materializationRequirements
            self.unsupportedFeatures = unsupportedFeatures
            self.conflictCapable = conflictCapable
            self.clipboardSides = clipboardSides
            self.receipt = receipt
        }
    }

    /// Binds a validated plan to sandbox scope, freshness, and a receipt without materializing it.
    public static func execute(
        _ plan: ComparisonOpenPlan,
        currentRequest: ComparisonOpenRequest? = nil,
        expecting expectedIdentity: ComparisonOpenRequestIdentity? = nil,
        sandboxScope: SandboxScope,
        clipboardInputs: ClipboardComparisonInputs? = nil,
        limits: Limits = .default
    ) throws -> OpenIntent {
        try checkCancellation()
        if let expectedIdentity, expectedIdentity != plan.requestIdentity {
            throw Error.request(
                .staleRequest(expected: expectedIdentity, actual: plan.requestIdentity)
            )
        }
        if let currentRequest {
            do {
                try plan.requireCurrentRequest(currentRequest)
            } catch let error as ComparisonOpenRequestError {
                throw Error.request(error)
            }
        }
        var work = ExecutorWork(maximum: limits.maximumWorkUnits)
        try work.charge(plan.sides.count + plan.materializationRequirements.count + 1)
        try checkScopeSize(sandboxScope, limits: limits)
        try validateModeOptions(plan.modeOptions, for: plan.modeResolution.mode)
        try validateSideStructure(plan)
        for _ in plan.sides {
            try checkCancellation()
            try work.charge(1)
        }
        let clipboardSides = plan.sides.filter {
            if case .clipboard = $0.source { return true }
            return false
        }.map(\.position)
        try validateClipboardEvidence(clipboardSides: clipboardSides, plan: plan, inputs: clipboardInputs)
        for requirement in plan.materializationRequirements {
            try checkCancellation()
            try work.charge(1)
            try validateScope(requirement, plan: plan, sandboxScope: sandboxScope)
        }
        try checkCancellation()
        let receipt = makeReceipt(plan: plan)
        return OpenIntent(
            requestIdentity: plan.requestIdentity,
            mode: plan.modeResolution.mode,
            isThreeWay: plan.isThreeWay,
            sides: plan.sides,
            modeOptions: plan.modeOptions,
            recursive: plan.recursive,
            filenameFilter: plan.filenameFilter,
            transforms: plan.transforms,
            projectSaveIntent: plan.projectSaveIntent,
            normalizedProjectDestinationPath: plan.normalizedProjectDestinationPath,
            hasProjectPayload: plan.projectPayload != nil,
            materializationRequirements: plan.materializationRequirements,
            unsupportedFeatures: plan.unsupportedFeatures,
            conflictCapable: plan.modeResolution.mode == .text,
            clipboardSides: clipboardSides,
            receipt: receipt
        )
    }

    /// Swaps two complete side payloads, re-plans under a fresh identity, and binds the new plan.
    /// Intents bound to `plan` go stale once this returns.
    public static func executeSwapped(
        _ plan: ComparisonOpenPlan,
        _ first: ComparisonOpenSidePosition,
        _ second: ComparisonOpenSidePosition,
        currentRequest: ComparisonOpenRequest? = nil,
        expecting expectedIdentity: ComparisonOpenRequestIdentity? = nil,
        sandboxScope: SandboxScope,
        clipboardInputs: ClipboardComparisonInputs? = nil,
        limits: Limits = .default
    ) throws -> OpenIntent {
        try checkCancellation()
        let swappedRequest: ComparisonOpenRequest
        do {
            try checkCancellation()
            swappedRequest = try plan.sourceRequest.swapping(first, second)
        } catch let error as ComparisonOpenRequestError {
            throw Error.request(error)
        }
        let nextPlan: ComparisonOpenPlan
        do {
            try checkCancellation()
            nextPlan = try ComparisonOpenRequestPlanner.plan(
                swappedRequest,
                expecting: expectedIdentity
            )
        } catch let error as ComparisonOpenRequestError {
            throw Error.request(error)
        }
        return try execute(
            nextPlan,
            currentRequest: currentRequest,
            expecting: expectedIdentity,
            sandboxScope: sandboxScope,
            clipboardInputs: clipboardInputs,
            limits: limits
        )
    }

    /// Rejects an intent whose receipt or identity no longer matches its plan.
    public static func validate(_ intent: OpenIntent, against plan: ComparisonOpenPlan) throws {
        try checkCancellation()
        guard intent.requestIdentity == plan.requestIdentity else {
            throw Error.request(
                .staleRequest(expected: plan.requestIdentity, actual: intent.requestIdentity)
            )
        }
        let expected = makeReceipt(plan: plan)
        guard intent.receipt == expected else {
            throw Error.receiptMismatch
        }
    }

    private static func checkCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw Error.request(.cancelled)
        }
    }

    private static func checkScopeSize(_ scope: SandboxScope, limits: Limits) throws {
        let (total, overflow) = scope.readableNormalizedPaths.count.addingReportingOverflow(
            scope.writableNormalizedPaths.count
        )
        guard !overflow, total <= limits.maximumCoveredPaths else {
            throw Error.request(.tooManyOptionItems(maximum: limits.maximumCoveredPaths))
        }
    }

    private static func validateModeOptions(
        _ options: ComparisonOpenModeOptions,
        for mode: ComparisonProject.Mode
    ) throws {
        let actual: ComparisonProject.Mode?
        switch options {
        case .defaults:
            return
        case .text:
            actual = .text
        case .table:
            actual = .table
        case .binary:
            actual = .binary
        case .image:
            actual = .image
        case .webpage:
            actual = .webpage
        case .folder:
            actual = .folder
        }
        guard let actual, actual == mode else {
            throw Error.request(
                .modeOptionsMismatch(
                    expected: mode,
                    actual: actual ?? .automatic
                )
            )
        }
    }

    private static func validateSideStructure(_ plan: ComparisonOpenPlan) throws {
        let positions = plan.sides.map(\.position)
        let expected: Set<ComparisonOpenSidePosition> =
            plan.isThreeWay ? [.left, .middle, .right] : [.left, .right]
        guard plan.sides.count == expected.count, Set(positions) == expected else {
            throw Error.request(.invalidSideSet(positions))
        }
        guard plan.modeResolution.mode != .automatic else {
            throw Error.request(.modeInferenceRequiresExplicitSelection)
        }
    }

    private static func validateClipboardEvidence(
        clipboardSides: [ComparisonOpenSidePosition],
        plan: ComparisonOpenPlan,
        inputs: ClipboardComparisonInputs?
    ) throws {
        guard !clipboardSides.isEmpty else { return }
        guard let inputs else { return }
        switch (inputs.kind, plan.modeResolution.mode) {
        case (.text, .text), (.binary, .binary):
            break
        default:
            throw Error.request(.invalidClipboard(.mixedContentKinds))
        }
        guard let leftPlanned = plan.side(.left),
            case .clipboard(let leftSnapshot) = leftPlanned.source,
            let rightPlanned = plan.side(.right),
            case .clipboard(let rightSnapshot) = rightPlanned.source,
            leftSnapshot.stableID == inputs.left.stableID,
            rightSnapshot.stableID == inputs.right.stableID
        else {
            throw Error.staleClipboardEvidence
        }
    }

    private static func validateScope(
        _ requirement: ComparisonOpenMaterializationRequirement,
        plan: ComparisonOpenPlan,
        sandboxScope: SandboxScope
    ) throws {
        switch requirement {
        case .localAccess(let access):
            guard sandboxScope.covers(access) else {
                throw Error.sandboxScopeMissing
            }
        case .projectSaveValidation:
            guard let destination = plan.normalizedProjectDestinationPath,
                sandboxScope.writableNormalizedPaths.contains(destination)
            else {
                throw Error.sandboxScopeMissing
            }
        case .offlineWebPageContent, .clipboardPairValidation, .externalToolPlan,
            .distinctSourceIdentityValidation:
            break
        }
    }

    private static func makeReceipt(plan: ComparisonOpenPlan) -> Receipt {
        var digest = ComparisonOpenDigest(domain: "ComparisonOpenExecutor.v1")
        digest.append(plan.requestIdentity.rawValue)
        digest.append(plan.modeResolution.mode.rawValue)
        digest.append(plan.isThreeWay ? UInt8(1) : UInt8(0))
        for side in plan.sides {
            digest.append(side.position.rawValue)
            digest.append(side.source.sourceKindDigestLabel)
            switch side.source {
            case .localFile(let url), .localFolder(let url):
                digest.append(url.absoluteString)
            case .scratchpad(let text, let label):
                digest.append(text)
                if let label {
                    digest.append(UInt8(1))
                    digest.append(label)
                } else {
                    digest.append(UInt8(0))
                }
            case .clipboard(let snapshot):
                digest.append(snapshot.stableID)
                digest.append(snapshot.contentID)
            case .remoteWebPage(let url):
                digest.append(url.absoluteString)
            }
            if let normalizedPath = side.normalizedPath {
                digest.append(UInt8(1))
                digest.append(normalizedPath)
            } else {
                digest.append(UInt8(0))
            }
            digest.append(side.effectiveReadOnly ? UInt8(1) : UInt8(0))
        }
        digest.append(String(describing: plan.modeOptions))
        digest.append(plan.recursive ? UInt8(1) : UInt8(0))
        if let filenameFilter = plan.filenameFilter {
            digest.append(UInt8(1))
            digest.append(String(describing: filenameFilter))
        } else {
            digest.append(UInt8(0))
        }
        if let unpacker = plan.transforms.unpacker {
            digest.append(UInt8(1))
            digest.append(unpacker.ruleIdentifier)
        } else {
            digest.append(UInt8(0))
        }
        if let prediffer = plan.transforms.prediffer {
            digest.append(UInt8(1))
            digest.append(prediffer.ruleIdentifier)
        } else {
            digest.append(UInt8(0))
        }
        if let projectSaveIntent = plan.projectSaveIntent {
            digest.append(UInt8(1))
            digest.append(projectSaveIntent.destinationURL.absoluteString)
            digest.append(projectSaveIntent.format.rawValue)
            digest.append(projectSaveIntent.existingFilePolicy.rawValue)
        } else {
            digest.append(UInt8(0))
        }
        if let projectDestinationPath = plan.normalizedProjectDestinationPath {
            digest.append(UInt8(1))
            digest.append(projectDestinationPath)
        } else {
            digest.append(UInt8(0))
        }
        if let projectPayload = plan.projectPayload {
            digest.append(UInt8(1))
            switch projectPayload {
            case .macMerge(let data):
                digest.append("macMerge")
                digest.append(data: data)
            case .winMerge(let data):
                digest.append("winMerge")
                digest.append(data: data)
            }
        } else {
            digest.append(UInt8(0))
        }
        digest.append(UInt64(plan.materializationRequirements.count))
        for requirement in plan.materializationRequirements {
            digest.append(String(describing: requirement))
        }
        digest.append(UInt64(plan.unsupportedFeatures.count))
        for feature in plan.unsupportedFeatures {
            digest.append(String(describing: feature))
        }
        digest.append(plan.modeResolution.mode == .text ? UInt8(1) : UInt8(0))
        let clipboardSides = plan.sides.filter {
            if case .clipboard = $0.source { return true }
            return false
        }.map(\.position)
        digest.append(UInt64(clipboardSides.count))
        for position in clipboardSides {
            digest.append(position.rawValue)
        }
        return Receipt(
            requestIdentity: plan.requestIdentity,
            mode: plan.modeResolution.mode,
            isThreeWay: plan.isThreeWay,
            digest: digest.finalize()
        )
    }
}

private struct ExecutorWork {
    let maximum: Int
    var completed = 0

    mutating func charge(_ amount: Int) throws {
        guard amount >= 0,
            amount <= maximum,
            completed <= maximum - amount
        else {
            throw ComparisonOpenExecutor.Error.request(
                .planningWorkExceeded(maximumWorkUnits: maximum)
            )
        }
        completed += amount
    }
}

private struct ComparisonOpenDigest {
    var hasher = SHA256()

    init(domain: String) {
        append(domain)
    }

    mutating func append(_ value: String) {
        let bytes = Array(value.utf8)
        append(UInt64(bytes.count))
        hasher.update(data: bytes)
    }

    mutating func append(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { hasher.update(bufferPointer: $0) }
    }

    mutating func append(_ value: UInt8) {
        var byte = value
        withUnsafeBytes(of: &byte) { hasher.update(bufferPointer: $0) }
    }

    mutating func append(_ value: UUID) {
        append(value.uuidString)
    }

    mutating func append(data: Data) {
        append(UInt64(data.count))
        hasher.update(data: data)
    }

    mutating func finalize() -> Data {
        Data(hasher.finalize())
    }
}

extension ComparisonOpenSource {
    fileprivate var sourceKindDigestLabel: String {
        switch self {
        case .localFile:
            "localFile"
        case .localFolder:
            "localFolder"
        case .scratchpad:
            "scratchpad"
        case .clipboard:
            "clipboard"
        case .remoteWebPage:
            "remoteWebPage"
        }
    }
}
