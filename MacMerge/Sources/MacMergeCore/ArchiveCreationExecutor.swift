import Darwin
import Foundation

/// UI-independent archive creation executor stub.
///
/// Binds an already-planned `ComparisonArchivePlan` plus bounded in-memory
/// report/patch/project supplements to a file or clipboard destination. It
/// revalidates selected sources through their pinned root descriptors,
/// enforces strict cross-platform archive paths, bounded digest/work/output
/// rules, and secure extraction permissions, then checks stale state and
/// cancellation. Plan-only: it never encodes, stages, publishes, or writes
/// archive bytes and never touches the pasteboard, filesystem, UI, or
/// processes, so every outcome is a pre-publication non-commit. A future
/// native layer owns real descriptor-relative reads, deterministic encoding,
/// and staged compare-and-swap publication under
/// `ComparisonArchiveCreationExecutorContract.required`.
public struct ComparisonArchiveCreationSandboxAuthority: Equatable, Hashable, Sendable {
    /// Exact percent-decoded absolute parent directory paths the executor may target.
    public let writableParentPaths: Set<String>
    public let allowsClipboard: Bool

    public init(writableParentPaths: Set<String> = [], allowsClipboard: Bool = false) {
        self.writableParentPaths = writableParentPaths
        self.allowsClipboard = allowsClipboard
    }

    public func authorizes(_ request: ComparisonArchiveCreationRequest) -> Bool {
        switch request.destination {
        case .clipboard:
            return allowsClipboard
        case .file(let url):
            return writableParentPaths.contains(
                url.deletingLastPathComponent().path(percentEncoded: false)
            )
        }
    }
}

/// Caller-supplied liveness probes. The stub performs no source or destination
/// reads itself beyond duplicating pinned root descriptors; owners with
/// revision leases answer whether plan inputs are current.
public struct ComparisonArchiveCreationRevalidation: Sendable {
    public let sourcesCurrent: @Sendable (ComparisonArchiveCreationRequest) async -> Bool
    public let destinationCurrent: @Sendable (ComparisonArchiveCreationRequest) async -> Bool

    public init(
        sourcesCurrent: @escaping @Sendable (ComparisonArchiveCreationRequest) async -> Bool,
        destinationCurrent: @escaping @Sendable (ComparisonArchiveCreationRequest) async -> Bool
    ) {
        self.sourcesCurrent = sourcesCurrent
        self.destinationCurrent = destinationCurrent
    }

    public static var assumeCurrent: ComparisonArchiveCreationRevalidation {
        ComparisonArchiveCreationRevalidation(
            sourcesCurrent: { _ in true },
            destinationCurrent: { _ in true }
        )
    }

    public static var stale: ComparisonArchiveCreationRevalidation {
        ComparisonArchiveCreationRevalidation(
            sourcesCurrent: { _ in false },
            destinationCurrent: { _ in false }
        )
    }
}

public enum ComparisonArchiveSupplementKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case report
    case patch
    case project
}

/// In-memory payload (generated report, patch, or project document) included
/// as one archive entry. The executor never encodes it; it only bounds it.
public struct ComparisonArchiveSupplement: Equatable, Hashable, Sendable {
    public let kind: ComparisonArchiveSupplementKind
    public let archiveRelativePath: String
    public let bytes: Data

    public init(kind: ComparisonArchiveSupplementKind, archiveRelativePath: String, bytes: Data) {
        self.kind = kind
        self.archiveRelativePath = archiveRelativePath
        self.bytes = bytes
    }
}

public enum ComparisonArchiveCreationDestination: Equatable, Hashable, Sendable {
    case file(URL)
    case clipboard
}

public struct ComparisonArchiveCreationRequest: Equatable, Sendable {
    public let plan: ComparisonArchivePlan
    public let supplements: [ComparisonArchiveSupplement]
    public let destination: ComparisonArchiveCreationDestination

    public init(
        plan: ComparisonArchivePlan,
        supplements: [ComparisonArchiveSupplement] = [],
        destination: ComparisonArchiveCreationDestination
    ) {
        self.plan = plan
        self.supplements = supplements
        self.destination = destination
    }
}

public enum ComparisonArchiveCreationDestinationSummary: String, Equatable, Hashable, Sendable {
    case file
    case clipboard
}

public enum ComparisonArchiveCreationSourceContract: String, Equatable, Hashable, Sendable {
    case pinnedRootDescriptorRelativeNoFollowExactRevision
}

public enum ComparisonArchiveCreationStagingContract: String, Equatable, Hashable, Sendable {
    case private0700Directory0600LeafBoundedSyncThenPublish
}

public enum ComparisonArchiveCreationCancellationContract: String, Equatable, Hashable, Sendable {
    case noPublicationBeforeImmediateFinalCheckThenNotExecuted
}

public struct ComparisonArchiveCreationExecutorContract: Equatable, Hashable, Sendable {
    public static let required = ComparisonArchiveCreationExecutorContract()

    public let sourceAccess =
        ComparisonArchiveCreationSourceContract.pinnedRootDescriptorRelativeNoFollowExactRevision
    public let staging =
        ComparisonArchiveCreationStagingContract.private0700Directory0600LeafBoundedSyncThenPublish
    public let cancellation =
        ComparisonArchiveCreationCancellationContract.noPublicationBeforeImmediateFinalCheckThenNotExecuted

    public init() {}
}

/// Execution receipt. Construction performs no mutation; it echoes the exact
/// request the executor validated. `estimatedArchiveByteCount` echoes the plan
/// estimate; supplements are bounded separately, not re-estimated.
public struct ComparisonArchiveCreationStubReceipt: Equatable, Sendable {
    public let manifestVersion: Int
    public let entryCount: Int
    public let supplementCount: Int
    public let totalSourceByteCount: UInt64
    public let estimatedArchiveByteCount: UInt64
    public let destination: ComparisonArchiveCreationDestinationSummary
    public let executorContract = ComparisonArchiveCreationExecutorContract.required

    fileprivate init(
        entryCount: Int,
        supplementCount: Int,
        totalSourceByteCount: UInt64,
        estimatedArchiveByteCount: UInt64,
        destination: ComparisonArchiveCreationDestinationSummary
    ) {
        manifestVersion = ComparisonArchivePlan.manifestVersion
        self.entryCount = entryCount
        self.supplementCount = supplementCount
        self.totalSourceByteCount = totalSourceByteCount
        self.estimatedArchiveByteCount = estimatedArchiveByteCount
        self.destination = destination
    }
}

public enum ComparisonArchiveCreationNonCommitReason: Equatable, Sendable {
    case cancelled
    case sourceChanged
    case destinationChanged
    case securityContractUnavailable
    case rejected(String)
}

public struct ComparisonArchiveCreationNotExecuted: Equatable, Sendable {
    public let receipt: ComparisonArchiveCreationStubReceipt
    public let reason: ComparisonArchiveCreationNonCommitReason

    fileprivate init(receipt: ComparisonArchiveCreationStubReceipt, reason: ComparisonArchiveCreationNonCommitReason) {
        self.receipt = receipt
        self.reason = reason
    }
}

public enum ComparisonArchiveCreationExecutionOutcome: Equatable, Sendable {
    case notExecuted(ComparisonArchiveCreationNotExecuted)
}

/// Plan-only stub executor: validates binding, paths, bounds, permissions,
/// pinned-root liveness, authority, staleness, and cancellation, then returns
/// a pre-publication non-commit without mutating.
public struct ComparisonArchiveCreationStubExecutor: Sendable {
    /// Upper bound on in-memory report/patch/project payloads per request.
    public static let maximumSupplementCount = 64

    public let authority: ComparisonArchiveCreationSandboxAuthority
    public let revalidation: ComparisonArchiveCreationRevalidation

    public init(
        authority: ComparisonArchiveCreationSandboxAuthority = ComparisonArchiveCreationSandboxAuthority(),
        revalidation: ComparisonArchiveCreationRevalidation = .assumeCurrent
    ) {
        self.authority = authority
        self.revalidation = revalidation
    }

    public func describe(_ request: ComparisonArchiveCreationRequest) -> ComparisonArchiveCreationStubReceipt {
        var total = request.plan.totalUncompressedByteCount
        for supplement in request.supplements {
            let (next, overflow) = total.addingReportingOverflow(UInt64(supplement.bytes.count))
            total = overflow ? .max : next
        }
        return ComparisonArchiveCreationStubReceipt(
            entryCount: request.plan.entries.count,
            supplementCount: request.supplements.count,
            totalSourceByteCount: total,
            estimatedArchiveByteCount: request.plan.estimatedArchiveByteCount,
            destination: summary(request.destination)
        )
    }

    public func execute(_ request: ComparisonArchiveCreationRequest) async -> ComparisonArchiveCreationExecutionOutcome {
        let receipt = describe(request)
        if Task.isCancelled {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .cancelled))
        }
        if let reason = structuralRejection(request) {
            if Task.isCancelled {
                return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .cancelled))
            }
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .rejected(reason)))
        }
        if Task.isCancelled {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .cancelled))
        }
        if let reason = bindingRejection(request) {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .rejected(reason)))
        }
        guard authority.authorizes(request) else {
            return .notExecuted(
                ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .securityContractUnavailable)
            )
        }
        if Task.isCancelled {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .cancelled))
        }
        do {
            try provePinnedRootsAlive(request.plan)
        } catch is CancellationError {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .cancelled))
        } catch {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .sourceChanged))
        }
        if Task.isCancelled {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .cancelled))
        }
        guard await revalidation.sourcesCurrent(request) else {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .sourceChanged))
        }
        if Task.isCancelled {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .cancelled))
        }
        guard await revalidation.destinationCurrent(request) else {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .destinationChanged))
        }
        if Task.isCancelled {
            return .notExecuted(ComparisonArchiveCreationNotExecuted(receipt: receipt, reason: .cancelled))
        }
        // Never begins publication: no encoding, staging, filesystem, pasteboard, or UI mutation.
        return .notExecuted(
            ComparisonArchiveCreationNotExecuted(
                receipt: receipt,
                reason: .rejected("Stub executor performs no archive, filesystem, pasteboard, or UI mutation.")
            )
        )
    }

    private func summary(_ destination: ComparisonArchiveCreationDestination) -> ComparisonArchiveCreationDestinationSummary {
        switch destination {
        case .file: .file
        case .clipboard: .clipboard
        }
    }

    private func structuralRejection(_ request: ComparisonArchiveCreationRequest) -> String? {
        let plan = request.plan
        let limits = plan.limits
        guard plan.format == .zip else {
            return "Stub executor supports only the ZIP container format."
        }
        guard plan.compression == .store else {
            return "Stub executor supports only stored compression."
        }
        let maximumEntries = min(limits.maximumEntryCount, 65534)
        guard plan.entries.count <= maximumEntries else {
            return "Stub executor found more entries than the plan limit allows."
        }
        let (combinedCount, countOverflow) = plan.entries.count.addingReportingOverflow(request.supplements.count)
        guard !countOverflow, combinedCount <= maximumEntries else {
            return "Stub executor found more entries and supplements than the plan limit allows."
        }
        guard request.supplements.count <= Self.maximumSupplementCount else {
            return "Stub executor found more supplements than the \(Self.maximumSupplementCount)-payload limit allows."
        }
        var total = UInt64(0)
        var recomputedPathBytes = UInt64(0)
        var recomputedPathComponents = UInt64(0)
        for entry in plan.entries {
            if Task.isCancelled { return "Stub executor was cancelled." }
            let (next, overflow) = total.addingReportingOverflow(entry.uncompressedByteCount)
            guard !overflow else { return "Stub executor found entry totals that overflow." }
            total = next
            let (nextPathBytes, pathBytesOverflow) = recomputedPathBytes.addingReportingOverflow(UInt64(entry.relativePath.utf8.count))
            guard !pathBytesOverflow else { return "Stub executor found path totals that overflow." }
            recomputedPathBytes = nextPathBytes
            let (nextComponents, componentsOverflow) = recomputedPathComponents.addingReportingOverflow(UInt64(entry.relativePath.split(separator: "/").count))
            guard !componentsOverflow else { return "Stub executor found path totals that overflow." }
            recomputedPathComponents = nextComponents
        }
        guard recomputedPathBytes == plan.totalPathUTF8ByteCount else {
            return "Stub executor found path bytes inconsistent with the plan."
        }
        guard recomputedPathComponents == plan.totalPathComponentCount else {
            return "Stub executor found path components inconsistent with the plan."
        }
        guard recomputedPathBytes <= limits.maximumTotalPathUTF8Bytes else {
            return "Stub executor found paths above the total path size limit."
        }
        guard recomputedPathComponents <= limits.maximumTotalPathComponents else {
            return "Stub executor found paths above the total component limit."
        }
        guard total == plan.totalUncompressedByteCount else {
            return "Stub executor found entry totals inconsistent with the plan."
        }
        guard total <= limits.maximumTotalUncompressedBytes else {
            return "Stub executor found sources above the total uncompressed limit."
        }
        guard plan.estimatedArchiveByteCount <= limits.maximumArchiveBytes else {
            return "Stub executor found an archive estimate above the archive limit."
        }
        for entry in plan.entries {
            if Task.isCancelled { return "Stub executor was cancelled." }
            guard entry.uncompressedByteCount <= limits.maximumEntryUncompressedBytes else {
                return "Stub executor found a planned entry above the per-entry limit: \(entry.relativePath)"
            }
            if let reason = archivePathRejection(entry.relativePath, limits: limits) {
                return "Stub executor found an invalid planned path (\(reason)): \(entry.relativePath)"
            }
            if let reason = metadataRejection(entry) {
                return "Stub executor found insecure extraction metadata (\(reason)): \(entry.relativePath)"
            }
            if let reason = digestRejection(entry) {
                return "Stub executor found an unbounded digest (\(reason)): \(entry.relativePath)"
            }
        }
        var supplementBytes = UInt64(0)
        var combinedPathBytes = recomputedPathBytes
        var combinedPathComponents = recomputedPathComponents
        var combinedEstimate = plan.estimatedArchiveByteCount
        var planKeys = Set<String>()
        for entry in plan.entries {
            let key = portableCollisionKey(entry.relativePath)
            guard !key.isEmpty else {
                return "Stub executor found an empty collision key: \(entry.relativePath)"
            }
            planKeys.insert(key)
        }
        var supplementKeys = Set<String>()
        var priorSupplementPaths: [String] = []
        for supplement in request.supplements {
            if Task.isCancelled { return "Stub executor was cancelled." }
            guard UInt64(supplement.bytes.count) <= limits.maximumEntryUncompressedBytes else {
                return "Stub executor found a supplement above the per-entry limit: \(supplement.archiveRelativePath)"
            }
            let (next, overflow) = supplementBytes.addingReportingOverflow(UInt64(supplement.bytes.count))
            guard !overflow else { return "Stub executor found supplement totals that overflow." }
            supplementBytes = next
            if let reason = archivePathRejection(supplement.archiveRelativePath, limits: limits) {
                return "Stub executor found an invalid supplement path (\(reason)): \(supplement.archiveRelativePath)"
            }
            let supplementPathBytes = UInt64(supplement.archiveRelativePath.utf8.count)
            let (nextCombinedPathBytes, pathOverflow) = combinedPathBytes.addingReportingOverflow(supplementPathBytes)
            guard !pathOverflow, nextCombinedPathBytes <= limits.maximumTotalPathUTF8Bytes else {
                return "Stub executor found paths above the total path size limit."
            }
            combinedPathBytes = nextCombinedPathBytes
            let supplementComponents = UInt64(supplement.archiveRelativePath.split(separator: "/").count)
            let (nextCombinedComponents, combinedComponentsOverflow) = combinedPathComponents.addingReportingOverflow(supplementComponents)
            guard !combinedComponentsOverflow, nextCombinedComponents <= limits.maximumTotalPathComponents else {
                return "Stub executor found paths above the total component limit."
            }
            combinedPathComponents = nextCombinedComponents
            let (doubledPathBytes, doubleOverflow) = supplementPathBytes.multipliedReportingOverflow(by: 2)
            guard !doubleOverflow else { return "Stub executor found an archive estimate that overflows." }
            let (headerBytes, headerOverflow) = doubledPathBytes.addingReportingOverflow(76)
            guard !headerOverflow else { return "Stub executor found an archive estimate that overflows." }
            let (supplementEntrySize, entryOverflow) = headerBytes.addingReportingOverflow(UInt64(supplement.bytes.count))
            guard !entryOverflow else { return "Stub executor found an archive estimate that overflows." }
            let (nextEstimate, estimateOverflow) = combinedEstimate.addingReportingOverflow(supplementEntrySize)
            guard !estimateOverflow, nextEstimate <= limits.maximumArchiveBytes, nextEstimate <= UInt64(UInt32.max) else {
                return "Stub executor found an archive estimate above the archive limit."
            }
            combinedEstimate = nextEstimate
            let key = portableCollisionKey(supplement.archiveRelativePath)
            guard !key.isEmpty else {
                return "Stub executor found an empty collision key: \(supplement.archiveRelativePath)"
            }
            if planKeys.contains(key) {
                return "Stub executor found a supplement colliding with a planned path: \(supplement.archiveRelativePath)"
            }
            guard !supplementKeys.contains(key) else {
                return "Stub executor found a supplement colliding with an earlier supplement: \(supplement.archiveRelativePath)"
            }
            supplementKeys.insert(key)
            for prior in priorSupplementPaths {
                if Task.isCancelled { return "Stub executor was cancelled." }
                let priorKey = portableCollisionKey(prior)
                if key.hasPrefix(priorKey + "/") {
                    return "Stub executor found a supplement inside an earlier supplement file: \(supplement.archiveRelativePath)"
                }
                if priorKey.hasPrefix(key + "/") {
                    return "Stub executor found a supplement shadowing an earlier supplement: \(supplement.archiveRelativePath)"
                }
            }
            if let reason = hierarchyRejection(supplementPath: supplement.archiveRelativePath, plan: plan) {
                return "Stub executor found a supplement hierarchy conflict (\(reason)): \(supplement.archiveRelativePath)"
            }
            priorSupplementPaths.append(supplement.archiveRelativePath)
        }
        let (combined, combinedOverflow) = total.addingReportingOverflow(supplementBytes)
        guard !combinedOverflow, combined <= limits.maximumTotalUncompressedBytes else {
            return "Stub executor found combined sources above the total uncompressed limit."
        }
        return nil
    }

    /// Exact string binding only: no URL resolution and no filesystem access.
    /// Sandbox scope is checked separately through `authority`.
    private func bindingRejection(_ request: ComparisonArchiveCreationRequest) -> String? {
        guard case .file(let url) = request.destination else { return nil }
        guard url.isFileURL,
            url.baseURL == nil,
            isLocalHost(url.host),
            url.user == nil,
            url.password == nil,
            url.port == nil,
            url.query == nil,
            url.fragment == nil
        else {
            return "Stub executor requires an absolute local file URL destination."
        }
        guard !url.hasDirectoryPath,
            !url.lastPathComponent.isEmpty,
            !url.lastPathComponent.contains("/")
        else {
            return "Stub executor requires a leaf file destination URL."
        }
        let parent = url.deletingLastPathComponent()
        guard parent.path.hasPrefix("/"), !parent.path.contains("\0") else {
            return "Stub executor requires a local parent directory destination."
        }
        return nil
    }

    /// Duplicates every planned source-root descriptor without reading sources.
    /// A dead root proves the plan is stale before any encoding could start.
    private func provePinnedRootsAlive(_ plan: ComparisonArchivePlan) throws {
        for entry in plan.entries {
            try Task.checkCancellation()
            try entry.source.withPinnedRootDescriptor { descriptor in
                var current = stat()
                guard Darwin.fstat(descriptor, &current) == 0 else {
                    throw ComparisonArchivePlanError.sourceUnavailable(
                        path: entry.source.relativePath,
                        errorCode: errno
                    )
                }
                let currentDeviceID = UInt64(bitPattern: Int64(current.st_dev))
                let currentFileID = UInt64(current.st_ino)
                guard currentDeviceID == entry.source.rootIdentity.deviceID,
                    currentFileID == entry.source.rootIdentity.fileID,
                    current.st_gen == entry.source.rootIdentity.generation
                else {
                    throw ComparisonArchivePlanError.sourceChangedDuringPlanning(entry.source.relativePath)
                }
            }
        }
    }

    private func metadataRejection(_ entry: ComparisonArchivePlannedEntry) -> String? {
        let expectedPermissions: UInt16 = entry.kind == .directory ? 0o700 : 0o600
        guard entry.metadata.unixPermissions == expectedPermissions else {
            return "permissions must be 0600 for files and 0700 for directories"
        }
        guard entry.metadata.modificationTime == ComparisonArchiveEntryMetadata.reproducibleModificationTime else {
            return "modification time must be the reproducible portable timestamp"
        }
        return nil
    }

    private func digestRejection(_ entry: ComparisonArchivePlannedEntry) -> String? {
        guard let digest = entry.source.snapshot.contentDigest else { return nil }
        let algorithm = digest.algorithm
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard algorithm == "sha256" || algorithm == "sha-256" else {
            return "unsupported algorithm \(digest.algorithm)"
        }
        guard digest.bytes.count == 32 else {
            return "digest must carry 32 SHA-256 bytes"
        }
        return nil
    }

    private func archivePathRejection(_ path: String, limits: ComparisonArchivePlanLimits) -> String? {
        guard !path.isEmpty else { return "empty" }
        guard !path.hasPrefix("/") else { return "absolute" }
        guard !path.contains("\\") else { return "contains backslash" }
        guard !path.contains("\0") else { return "contains null" }
        guard path.utf8.count <= limits.maximumPathUTF8Bytes else { return "path too long" }
        let rawComponents = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard rawComponents.count <= limits.maximumPathDepth else { return "too deep" }
        for rawComponent in rawComponents {
            guard !rawComponent.isEmpty else { return "empty component" }
            guard rawComponent != "." else { return "current directory component" }
            guard rawComponent != ".." else { return "parent traversal" }
            let component = rawComponent.precomposedStringWithCanonicalMapping
            guard component == rawComponent else { return "not normalized" }
            guard !component.contains(":") else { return "contains colon" }
            guard component.last != ".", component.last != " " else { return "trailing dot or space" }
            guard !isReservedDOSDeviceName(component) else { return "reserved device name" }
            guard !portableCollisionKey(component).isEmpty else { return "empty collision key" }
            guard component.utf8.count <= 255 else { return "component too long" }
        }
        return nil
    }

    private func hierarchyRejection(supplementPath: String, plan: ComparisonArchivePlan) -> String? {
        let supplementKey = portableCollisionKey(supplementPath)
        for entry in plan.entries {
            if Task.isCancelled { return "cancelled" }
            let plannedKey = portableCollisionKey(entry.relativePath)
            if entry.kind == .file, supplementKey.hasPrefix(plannedKey + "/") {
                return "supplement is inside a planned file"
            }
            if plannedKey.hasPrefix(supplementKey + "/") {
                return "supplement shadows a planned path"
            }
        }
        return nil
    }

    private func portableCollisionKey(_ path: String) -> String {
        let hfsPlusFiltered = String(
            path.unicodeScalars.filter { scalar in
                switch scalar.value {
                case 0x200C...0x200F, 0x202A...0x202E, 0x206A...0x206F, 0xFEFF:
                    false
                default:
                    true
                }
            }
        )
        return hfsPlusFiltered.precomposedStringWithCanonicalMapping.folding(
            options: .caseInsensitive,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func isLocalHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return true }
        return host.lowercased() == "localhost"
    }

    private func isReservedDOSDeviceName(_ component: String) -> Bool {
        var stem = String(component.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0])
        while stem.last == "." || stem.last == " " { stem.removeLast() }
        stem = stem.lowercased(with: Locale(identifier: "en_US_POSIX"))
        if stem == "con" || stem == "prn" || stem == "aux" || stem == "nul"
            || stem == "clock$" || stem == "conin$" || stem == "conout$"
        {
            return true
        }
        guard stem.count == 4, let suffix = stem.last else { return false }
        let hasReservedPrefix = stem.hasPrefix("com") || stem.hasPrefix("lpt")
        return hasReservedPrefix
            && (("1"..."9").contains(String(suffix)) || suffix == "¹" || suffix == "²" || suffix == "³")
    }
}
