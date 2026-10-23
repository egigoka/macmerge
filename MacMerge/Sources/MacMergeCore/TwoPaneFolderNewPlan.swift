import CryptoKit
import Foundation

/// UI-independent planning for two-pane folder comparison creation (`ID_FILE_NEW_FOLDER`).
///
/// Planning only: never enumerates directories, never touches the filesystem, and performs no I/O.
/// Caller pins exact root revisions out of band (SHA-256 plus stat identity) and the host
/// materializes the comparison. Capability authority remains with `FolderComparisonWorkflowCapabilities`
/// and `FolderComparisonWorkflowFeature`. Scan execution remains with `FolderScanner`.
/// Visible-order navigation remains with `DirectoryPairNavigationCommand`.
public enum TwoPaneFolderNewPlanner: Sendable {
    public static let commandID = "ID_FILE_NEW_FOLDER"

    public static var requiredFolderFeatures: Set<FolderComparisonWorkflowFeature> {
        [.recursiveScan, .metadataComparison]
    }

    public static func plan(
        _ request: TwoPaneFolderNewRequest,
        cancellationCheck: @escaping TwoPaneFolderNewCancellationCheck = { try Task.checkCancellation() }
    ) throws -> TwoPaneFolderNewPlan {
        do {
            try checkCancellation(cancellationCheck)
            try validate(request.limits)
            var meter = TwoPaneFolderNewWorkMeter(limits: request.limits, cancellationCheck: cancellationCheck)
            try meter.consume(16)
            try meter.measure(request.leftRoot.canonicalPath)
            try meter.measure(request.rightRoot.canonicalPath)
            // Duplicate check before canonical gate: preserves duplicateRoot for
            // normalized duplicates (trailing slash, dot-dot) demanded by tests,
            // while distinct non-canonical paths still fail the strict gate below
            // as invalidRoot. Duplicate only rejects, never accepts.
            let leftStandardized = (request.leftRoot.canonicalPath as NSString).standardizingPath
            let rightStandardized = (request.rightRoot.canonicalPath as NSString).standardizingPath
            let leftNormalized = canonicalFolded(leftStandardized)
            let rightNormalized = canonicalFolded(rightStandardized)
            guard leftNormalized != rightNormalized else {
                throw TwoPaneFolderNewError(.duplicateRoot)
            }
            if isStrictAncestor(ancestor: leftNormalized, descendant: rightNormalized)
                || isStrictAncestor(ancestor: rightNormalized, descendant: leftNormalized)
            {
                throw TwoPaneFolderNewError(.duplicateRoot)
            }
            guard isValidCanonicalDirectoryPath(request.leftRoot.canonicalPath) else {
                throw TwoPaneFolderNewError(.invalidRoot, side: .left)
            }
            guard isValidCanonicalDirectoryPath(request.rightRoot.canonicalPath) else {
                throw TwoPaneFolderNewError(.invalidRoot, side: .right)
            }
            guard request.leftRoot.isDirectory else {
                throw TwoPaneFolderNewError(.rootNotDirectory, side: .left)
            }
            guard request.rightRoot.isDirectory else {
                throw TwoPaneFolderNewError(.rootNotDirectory, side: .right)
            }
            // Fail closed on unbound stat identity: executor cannot detect dir swap
            // (delete + recreate at same path) without device/fileID. Caller must
            // fstat the pinned descriptor out of band and provide st_dev/st_ino here.
            // Generation alone is an opaque CAS; executor must re-stat and compare
            // device/fileID/generation before entry access. Zero is the unbound
            // sentinel for deviceID/fileID (defaults are 0 for source compatibility)
            // and for generation; planning rejects 0 for all three.
            guard request.leftRoot.deviceID != 0, request.leftRoot.fileID != 0, request.leftRoot.generation != 0 else {
                throw TwoPaneFolderNewError(.invalidRoot, side: .left)
            }
            guard request.rightRoot.deviceID != 0, request.rightRoot.fileID != 0, request.rightRoot.generation != 0 else {
                throw TwoPaneFolderNewError(.invalidRoot, side: .right)
            }
            try meter.consume(4)
            guard (0...request.limits.maximumDepth).contains(request.recursionDepth) else {
                throw TwoPaneFolderNewError(.invalidDepth, limit: .depth, maximum: UInt64(request.limits.maximumDepth))
            }
            guard !request.showFlags.isEmpty else {
                throw TwoPaneFolderNewError(.invalidShowFlags)
            }
            try meter.consume(UInt64(request.showFlags.count + 1))
            guard request.nameFilter.ruleCount >= 0,
                request.nameFilter.ruleCount <= Int(TwoPaneFolderNewLimits.hardMaximumWorkUnits)
            else {
                throw TwoPaneFolderNewError(.invalidNameFilter)
            }
            guard request.nameFilter.rulesSHA256.count == 32 else {
                throw TwoPaneFolderNewError(.invalidNameFilter)
            }
            try meter.consume(UInt64(request.nameFilter.ruleCount) + 1)
            guard request.requiredFolderFeatures.isSuperset(of: requiredFolderFeatures) else {
                throw TwoPaneFolderNewError(.unsupportedCapability)
            }
            guard request.folderCapabilities.features.isSuperset(of: request.requiredFolderFeatures) else {
                throw TwoPaneFolderNewError(.unsupportedCapability)
            }
            try meter.consume(UInt64(request.folderCapabilities.features.count + 1))
            let leftDigest = try revisionDigest(for: request.leftRoot, meter: &meter)
            let rightDigest = try revisionDigest(for: request.rightRoot, meter: &meter)
            let leftRevision = TwoPaneFolderNewRootRevision(identity: request.leftRoot, revisionSHA256: leftDigest)
            let rightRevision = TwoPaneFolderNewRootRevision(identity: request.rightRoot, revisionSHA256: rightDigest)
            let planDigest = try planSHA256(
                leftRevision: leftRevision,
                rightRevision: rightRevision,
                recursionDepth: request.recursionDepth,
                showFlags: request.showFlags,
                nameFilter: request.nameFilter,
                folderCapabilities: request.folderCapabilities,
                requiredFolderFeatures: request.requiredFolderFeatures,
                limits: request.limits,
                meter: &meter
            )
            let receipt = TwoPaneFolderNewPlanningReceipt(
                planSHA256: planDigest,
                leftRevisionSHA256: leftDigest,
                rightRevisionSHA256: rightDigest,
                showFlagCount: request.showFlags.count,
                planningWorkUnits: meter.consumed
            )
            let plan = TwoPaneFolderNewPlan(
                leftRevision: leftRevision,
                rightRevision: rightRevision,
                recursionDepth: request.recursionDepth,
                showFlags: request.showFlags,
                nameFilter: request.nameFilter,
                folderCapabilities: request.folderCapabilities,
                requiredFolderFeatures: request.requiredFolderFeatures,
                limits: request.limits,
                receipt: receipt
            )
            var validationMeter = TwoPaneFolderNewWorkMeter(limits: request.limits, cancellationCheck: cancellationCheck)
            try validateReceipt(plan, meter: &validationMeter)
            try meter.finish()
            try validationMeter.finish()
            return plan
        } catch let error as TwoPaneFolderNewError {
            throw error
        } catch is CancellationError {
            throw TwoPaneFolderNewError(.cancelled)
        } catch {
            throw error
        }
    }

    static func validate(_ limits: TwoPaneFolderNewLimits) throws {
        guard limits.maximumRoots == TwoPaneFolderNewLimits.hardMaximumRoots else {
            throw TwoPaneFolderNewError(.invalidLimit, limit: .roots, maximum: UInt64(TwoPaneFolderNewLimits.hardMaximumRoots))
        }
        guard (1...TwoPaneFolderNewLimits.hardMaximumPathUTF8Bytes).contains(limits.maximumPathUTF8Bytes) else {
            throw TwoPaneFolderNewError(.invalidLimit, limit: .pathUTF8Bytes, maximum: UInt64(TwoPaneFolderNewLimits.hardMaximumPathUTF8Bytes))
        }
        guard limits.maximumTotalPathUTF8Bytes >= limits.maximumPathUTF8Bytes else {
            throw TwoPaneFolderNewError(
                .invalidLimit,
                limit: .totalPathUTF8Bytes,
                maximum: UInt64(TwoPaneFolderNewLimits.hardMaximumTotalPathUTF8Bytes)
            )
        }
        guard limits.maximumTotalPathUTF8Bytes <= TwoPaneFolderNewLimits.hardMaximumTotalPathUTF8Bytes else {
            throw TwoPaneFolderNewError(
                .invalidLimit,
                limit: .totalPathUTF8Bytes,
                maximum: UInt64(TwoPaneFolderNewLimits.hardMaximumTotalPathUTF8Bytes)
            )
        }
        guard (0...TwoPaneFolderNewLimits.hardMaximumDepth).contains(limits.maximumDepth) else {
            throw TwoPaneFolderNewError(.invalidLimit, limit: .depth, maximum: UInt64(TwoPaneFolderNewLimits.hardMaximumDepth))
        }
        guard (1...TwoPaneFolderNewLimits.hardMaximumWorkUnits).contains(limits.maximumWorkUnits) else {
            throw TwoPaneFolderNewError(.invalidLimit, limit: .workUnits, maximum: TwoPaneFolderNewLimits.hardMaximumWorkUnits)
        }
        guard (1...TwoPaneFolderNewLimits.hardMaximumCancellationCheckInterval).contains(limits.cancellationCheckInterval) else {
            throw TwoPaneFolderNewError(
                .invalidLimit,
                limit: .cancellationCheckInterval,
                maximum: TwoPaneFolderNewLimits.hardMaximumCancellationCheckInterval
            )
        }
    }

    static func isValidCanonicalDirectoryPath(_ path: String) -> Bool {
        guard !path.isEmpty, path.hasPrefix("/"), !path.hasPrefix("//"), !path.utf8.contains(0) else {
            return false
        }
        // Enforce canonical form: reject interior //, /./, /../, and trailing
        // slash (except root "/"). Caller must pass already-standardized paths.
        // Standardization is only used for duplicate comparison, not to accept
        // non-canonical inputs as distinct roots. Manual component checks (not
        // standardizingPath equality): standardizingPath truncates at MAXPATHLEN
        // 1024 and would reject valid long paths up to the 64 KiB limit.
        if path != "/" {
            guard !path.hasSuffix("/") else {
                return false
            }
        }
        guard !path.contains("//") else {
            return false
        }
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            if component == "." || component == ".." {
                return false
            }
        }
        return true
    }

    static func canonicalFolded(_ value: String) -> String {
        value.decomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .decomposedStringWithCanonicalMapping
    }

    static func isStrictAncestor(ancestor: String, descendant: String) -> Bool {
        if ancestor == descendant { return false }
        // Empty paths are never ancestors: without this, "" + "/" == "/" prefixes
        // every absolute path and empty inputs would report duplicateRoot instead
        // of invalidRoot.
        guard !ancestor.isEmpty, !descendant.isEmpty else { return false }
        if ancestor == "/" { return descendant.hasPrefix("/") && descendant.count > 1 }
        return descendant.hasPrefix(ancestor + "/")
    }

    static func revisionDigest(
        for identity: TwoPaneFolderNewRootIdentity,
        meter: inout TwoPaneFolderNewWorkMeter
    ) throws -> Data {
        try meter.consume(64)
        var digest = TwoPaneFolderNewCanonicalDigest()
        digest.append("two-pane-folder-new-root-v1")
        digest.append(identity.canonicalPath)
        digest.append(identity.generation)
        digest.append(identity.isDirectory)
        digest.append(identity.deviceID)
        digest.append(identity.fileID)
        return digest.finalize()
    }

    static func planSHA256(
        leftRevision: TwoPaneFolderNewRootRevision,
        rightRevision: TwoPaneFolderNewRootRevision,
        recursionDepth: Int,
        showFlags: Set<TwoPaneFolderNewShowFlag>,
        nameFilter: TwoPaneFolderNewNameFilterReference,
        folderCapabilities: FolderComparisonWorkflowCapabilities,
        requiredFolderFeatures: Set<FolderComparisonWorkflowFeature>,
        limits: TwoPaneFolderNewLimits,
        meter: inout TwoPaneFolderNewWorkMeter
    ) throws -> Data {
        try meter.consume(1_024)
        var digest = TwoPaneFolderNewCanonicalDigest()
        digest.append("two-pane-folder-new-plan-v1")
        digest.append(leftRevision.revisionSHA256)
        digest.append(rightRevision.revisionSHA256)
        digest.append(recursionDepth)
        let orderedFlags = showFlags.sorted { $0.rawValue < $1.rawValue }
        digest.append(orderedFlags.count)
        for flag in orderedFlags {
            try meter.consume()
            digest.append(flag.rawValue)
        }
        digest.append(nameFilter.ruleCount)
        digest.append(nameFilter.rulesSHA256)
        digest.append(folderCapabilities.identity)
        digest.append(folderCapabilities.revision)
        let orderedFeatures = folderCapabilities.features.sorted { $0.rawValue < $1.rawValue }
        digest.append(orderedFeatures.count)
        for feature in orderedFeatures {
            try meter.consume()
            digest.append(feature.rawValue)
        }
        let orderedRequired = requiredFolderFeatures.sorted { $0.rawValue < $1.rawValue }
        digest.append(orderedRequired.count)
        for feature in orderedRequired {
            try meter.consume()
            digest.append(feature.rawValue)
        }
        digest.append(limits.maximumRoots)
        digest.append(limits.maximumPathUTF8Bytes)
        digest.append(limits.maximumTotalPathUTF8Bytes)
        digest.append(limits.maximumDepth)
        digest.append(limits.maximumWorkUnits)
        digest.append(limits.cancellationCheckInterval)
        digest.append(TwoPaneFolderNewValidationContract.exactRootRevisionCapabilityDepthAndFilter.rawValue)
        digest.append(TwoPaneFolderNewSourceAccessContract.openPinnedDescriptorRelativeEntriesWithoutFollowingLinks.rawValue)
        digest.append(TwoPaneFolderNewPlanningContract.planOnlyWithoutEnumerationOrIO.rawValue)
        digest.append(TwoPaneFolderNewUIContract.noAppKitWindowCreationOrUIParityClaim.rawValue)
        return digest.finalize()
    }

    static func validateReceipt(
        _ plan: TwoPaneFolderNewPlan,
        meter: inout TwoPaneFolderNewWorkMeter
    ) throws {
        try validate(plan.limits)
        // Tolerance is intentional: planningWorkUnits is accounting telemetry, not
        // executor authority, so it is not bound into planSHA256 (which would make
        // the digest fragile across metering changes). Upper-bound check suffices:
        // understating workUnits grants no capability, overstating fails closed.
        // Exact determinism (same inputs yield same workUnits) is covered by tests
        // but not enforced here to allow metering evolution.
        guard plan.receipt.planningWorkUnits <= plan.limits.maximumWorkUnits else {
            throw TwoPaneFolderNewError(.workLimitExceeded, limit: .workUnits, maximum: plan.limits.maximumWorkUnits)
        }
        let expectedLeftRevision = try revisionDigest(for: plan.leftRevision.identity, meter: &meter)
        guard expectedLeftRevision == plan.leftRevision.revisionSHA256 else {
            throw TwoPaneFolderNewError(.receiptMismatch, side: .left)
        }
        let expectedRightRevision = try revisionDigest(for: plan.rightRevision.identity, meter: &meter)
        guard expectedRightRevision == plan.rightRevision.revisionSHA256 else {
            throw TwoPaneFolderNewError(.receiptMismatch, side: .right)
        }
        let expected = try planSHA256(
            leftRevision: plan.leftRevision,
            rightRevision: plan.rightRevision,
            recursionDepth: plan.recursionDepth,
            showFlags: plan.showFlags,
            nameFilter: plan.nameFilter,
            folderCapabilities: plan.folderCapabilities,
            requiredFolderFeatures: plan.requiredFolderFeatures,
            limits: plan.limits,
            meter: &meter
        )
        guard expected == plan.receipt.planSHA256 else {
            throw TwoPaneFolderNewError(.receiptMismatch)
        }
        guard plan.receipt.leftRevisionSHA256 == plan.leftRevision.revisionSHA256 else {
            throw TwoPaneFolderNewError(.receiptMismatch, side: .left)
        }
        guard plan.receipt.rightRevisionSHA256 == plan.rightRevision.revisionSHA256 else {
            throw TwoPaneFolderNewError(.receiptMismatch, side: .right)
        }
        guard plan.receipt.showFlagCount == plan.showFlags.count else {
            throw TwoPaneFolderNewError(.receiptMismatch)
        }
    }

    static func checkCancellation(_ cancellationCheck: TwoPaneFolderNewCancellationCheck) throws {
        do {
            try cancellationCheck()
        } catch let newError as TwoPaneFolderNewError {
            throw newError
        } catch {
            throw TwoPaneFolderNewError(.cancelled)
        }
    }
}

public typealias TwoPaneFolderNewCancellationCheck = @Sendable () throws -> Void

public enum TwoPaneFolderNewSide: String, CaseIterable, Hashable, Sendable {
    case left
    case right
}

public struct TwoPaneFolderNewRootIdentity: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let canonicalPath: String
    public let generation: UInt32
    public let isDirectory: Bool
    /// stat-derived device ID (st_dev). Zero means unbound and fails closed at planning.
    public let deviceID: UInt64
    /// stat-derived file ID (st_ino). Zero means unbound and fails closed at planning.
    public let fileID: UInt64

    public init(canonicalPath: String, generation: UInt32, isDirectory: Bool, deviceID: UInt64 = 0, fileID: UInt64 = 0) {
        self.canonicalPath = canonicalPath
        self.generation = generation
        self.isDirectory = isDirectory
        self.deviceID = deviceID
        self.fileID = fileID
    }

    public var description: String {
        "TwoPaneFolderNewRootIdentity(isDirectory: \(isDirectory), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["isDirectory": isDirectory, "details": "<redacted>"], displayStyle: .struct)
    }
}

public struct TwoPaneFolderNewRootRevision: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let identity: TwoPaneFolderNewRootIdentity
    public let revisionSHA256: Data

    public init(identity: TwoPaneFolderNewRootIdentity, revisionSHA256: Data) {
        self.identity = identity
        self.revisionSHA256 = revisionSHA256
    }

    public var description: String {
        "TwoPaneFolderNewRootRevision(digestBytes: \(revisionSHA256.count), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["digestBytes": revisionSHA256.count, "details": "<redacted>"], displayStyle: .struct)
    }
}

public enum TwoPaneFolderNewShowFlag: String, CaseIterable, Hashable, Sendable {
    case identical
    case different
    case leftOnly
    case rightOnly
}

public struct TwoPaneFolderNewNameFilterReference: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let ruleCount: Int
    public let rulesSHA256: Data

    public init(ruleCount: Int, rulesSHA256: Data) {
        self.ruleCount = ruleCount
        self.rulesSHA256 = rulesSHA256
    }

    public var description: String {
        "TwoPaneFolderNewNameFilterReference(rules: \(ruleCount), digestBytes: \(rulesSHA256.count), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["ruleCount": ruleCount, "digestBytes": rulesSHA256.count, "details": "<redacted>"], displayStyle: .struct)
    }
}

public struct TwoPaneFolderNewLimits: Hashable, Sendable {
    public static let hardMaximumRoots = 2
    public static let hardMaximumPathUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 256 * 1_024
    public static let hardMaximumDepth = 256
    public static let hardMaximumWorkUnits: UInt64 = 16 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval: UInt64 = 4_096
    public static let `default` = TwoPaneFolderNewLimits()

    public let maximumRoots: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumDepth: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: UInt64

    public init(
        maximumRoots: Int = 2,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 64 * 1_024,
        maximumDepth: Int = 64,
        maximumWorkUnits: UInt64 = 1 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 256
    ) {
        self.maximumRoots = maximumRoots
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumDepth = maximumDepth
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum TwoPaneFolderNewLimit: String, CaseIterable, Hashable, Sendable {
    case roots
    case pathUTF8Bytes
    case totalPathUTF8Bytes
    case depth
    case workUnits
    case cancellationCheckInterval
}

public enum TwoPaneFolderNewErrorCode: String, CaseIterable, Hashable, Sendable {
    case cancelled
    case invalidLimit
    case workLimitExceeded
    case pathTooLarge
    case totalPathsTooLarge
    case invalidRoot
    case rootNotDirectory
    case duplicateRoot
    case invalidDepth
    case invalidShowFlags
    case invalidNameFilter
    case unsupportedCapability
    case receiptMismatch
    case staleGeneration
}

public struct TwoPaneFolderNewError: Swift.Error, Hashable, LocalizedError, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let code: TwoPaneFolderNewErrorCode
    public let limit: TwoPaneFolderNewLimit?
    public let maximum: UInt64?
    public let side: TwoPaneFolderNewSide?
    public let expectedGeneration: UInt32?
    public let actualGeneration: UInt32?

    public init(
        _ code: TwoPaneFolderNewErrorCode,
        limit: TwoPaneFolderNewLimit? = nil,
        maximum: UInt64? = nil,
        side: TwoPaneFolderNewSide? = nil,
        expectedGeneration: UInt32? = nil,
        actualGeneration: UInt32? = nil
    ) {
        self.code = code
        self.limit = limit
        self.maximum = maximum
        self.side = side
        self.expectedGeneration = expectedGeneration
        self.actualGeneration = actualGeneration
    }

    public var errorDescription: String? {
        switch code {
        case .cancelled:
            "Two-pane folder creation was cancelled."
        case .invalidLimit:
            "Two-pane folder creation has an invalid limit."
        case .workLimitExceeded:
            "Two-pane folder creation exceeded its work limit."
        case .pathTooLarge:
            "Two-pane folder creation root path exceeds its per-path limit."
        case .totalPathsTooLarge:
            "Two-pane folder creation root paths exceed their total limit."
        case .invalidRoot:
            "Two-pane folder creation received an invalid directory root."
        case .rootNotDirectory:
            "Two-pane folder creation requires both roots to be directories."
        case .duplicateRoot:
            "Two-pane folder creation roots must have distinct canonical paths."
        case .invalidDepth:
            "Two-pane folder creation recursion depth is out of bounds."
        case .invalidShowFlags:
            "Two-pane folder creation requires at least one show flag."
        case .invalidNameFilter:
            "Two-pane folder creation name-filter reference is invalid."
        case .unsupportedCapability:
            "Two-pane folder creation requires an unsupported folder capability."
        case .receiptMismatch:
            "Two-pane folder creation plan receipt is invalid."
        case .staleGeneration:
            "Two-pane folder creation root generation is stale."
        }
    }

    public var description: String {
        "TwoPaneFolderNewError(code: \(code.rawValue), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["code": code, "details": "<redacted>"], displayStyle: .struct)
    }
}

public struct TwoPaneFolderNewRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let leftRoot: TwoPaneFolderNewRootIdentity
    public let rightRoot: TwoPaneFolderNewRootIdentity
    public let recursionDepth: Int
    public let nameFilter: TwoPaneFolderNewNameFilterReference
    public let showFlags: Set<TwoPaneFolderNewShowFlag>
    public let folderCapabilities: FolderComparisonWorkflowCapabilities
    public let requiredFolderFeatures: Set<FolderComparisonWorkflowFeature>
    public let limits: TwoPaneFolderNewLimits

    public init(
        leftRoot: TwoPaneFolderNewRootIdentity,
        rightRoot: TwoPaneFolderNewRootIdentity,
        recursionDepth: Int,
        nameFilter: TwoPaneFolderNewNameFilterReference,
        showFlags: Set<TwoPaneFolderNewShowFlag>,
        folderCapabilities: FolderComparisonWorkflowCapabilities,
        requiredFolderFeatures: Set<FolderComparisonWorkflowFeature>,
        limits: TwoPaneFolderNewLimits = .default
    ) {
        self.leftRoot = leftRoot
        self.rightRoot = rightRoot
        self.recursionDepth = recursionDepth
        self.nameFilter = nameFilter
        self.showFlags = showFlags
        self.folderCapabilities = folderCapabilities
        self.requiredFolderFeatures = requiredFolderFeatures
        self.limits = limits
    }

    public var description: String {
        "TwoPaneFolderNewRequest(depth: \(recursionDepth), showFlags: \(showFlags.count), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["depth": recursionDepth, "showFlagCount": showFlags.count, "details": "<redacted>"], displayStyle: .struct)
    }
}

public struct TwoPaneFolderNewPlanningReceipt: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let planSHA256: Data
    public let leftRevisionSHA256: Data
    public let rightRevisionSHA256: Data
    public let showFlagCount: Int
    /// Accounting telemetry only: not bound into planSHA256, validated by
    /// upper-bound against limits (not exact). Understating grants no authority.
    public let planningWorkUnits: UInt64

    public init(
        planSHA256: Data,
        leftRevisionSHA256: Data,
        rightRevisionSHA256: Data,
        showFlagCount: Int,
        planningWorkUnits: UInt64
    ) {
        self.planSHA256 = planSHA256
        self.leftRevisionSHA256 = leftRevisionSHA256
        self.rightRevisionSHA256 = rightRevisionSHA256
        self.showFlagCount = showFlagCount
        self.planningWorkUnits = planningWorkUnits
    }

    public var description: String {
        "TwoPaneFolderNewPlanningReceipt(flags: \(showFlagCount), workUnits: \(planningWorkUnits), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["showFlagCount": showFlagCount, "planningWorkUnits": planningWorkUnits, "details": "<redacted>"], displayStyle: .struct)
    }
}

public enum TwoPaneFolderNewValidationContract: String, Hashable, Sendable {
    case exactRootRevisionCapabilityDepthAndFilter
}

public enum TwoPaneFolderNewSourceAccessContract: String, Hashable, Sendable {
    case openPinnedDescriptorRelativeEntriesWithoutFollowingLinks
}

public enum TwoPaneFolderNewPlanningContract: String, Hashable, Sendable {
    case planOnlyWithoutEnumerationOrIO
}

public enum TwoPaneFolderNewUIContract: String, Hashable, Sendable {
    case noAppKitWindowCreationOrUIParityClaim
}

public struct TwoPaneFolderNewExecutorContract: Hashable, Sendable {
    public static let required = TwoPaneFolderNewExecutorContract()

    public let validation = TwoPaneFolderNewValidationContract.exactRootRevisionCapabilityDepthAndFilter
    public let sourceAccess = TwoPaneFolderNewSourceAccessContract.openPinnedDescriptorRelativeEntriesWithoutFollowingLinks
    public let planning = TwoPaneFolderNewPlanningContract.planOnlyWithoutEnumerationOrIO
    public let ui = TwoPaneFolderNewUIContract.noAppKitWindowCreationOrUIParityClaim

    public init() {}
}

public struct TwoPaneFolderNewPlan: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let leftRevision: TwoPaneFolderNewRootRevision
    public let rightRevision: TwoPaneFolderNewRootRevision
    public let recursionDepth: Int
    public let showFlags: Set<TwoPaneFolderNewShowFlag>
    public let nameFilter: TwoPaneFolderNewNameFilterReference
    public let folderCapabilities: FolderComparisonWorkflowCapabilities
    public let requiredFolderFeatures: Set<FolderComparisonWorkflowFeature>
    public let limits: TwoPaneFolderNewLimits
    public let receipt: TwoPaneFolderNewPlanningReceipt
    public let executorContract: TwoPaneFolderNewExecutorContract

    fileprivate init(
        leftRevision: TwoPaneFolderNewRootRevision,
        rightRevision: TwoPaneFolderNewRootRevision,
        recursionDepth: Int,
        showFlags: Set<TwoPaneFolderNewShowFlag>,
        nameFilter: TwoPaneFolderNewNameFilterReference,
        folderCapabilities: FolderComparisonWorkflowCapabilities,
        requiredFolderFeatures: Set<FolderComparisonWorkflowFeature>,
        limits: TwoPaneFolderNewLimits,
        receipt: TwoPaneFolderNewPlanningReceipt
    ) {
        self.leftRevision = leftRevision
        self.rightRevision = rightRevision
        self.recursionDepth = recursionDepth
        self.showFlags = showFlags
        self.nameFilter = nameFilter
        self.folderCapabilities = folderCapabilities
        self.requiredFolderFeatures = requiredFolderFeatures
        self.limits = limits
        self.receipt = receipt
        executorContract = .required
    }

    public func validateReceipt(
        cancellationCheck: @escaping TwoPaneFolderNewCancellationCheck = { try Task.checkCancellation() }
    ) throws {
        var meter = TwoPaneFolderNewWorkMeter(limits: limits, cancellationCheck: cancellationCheck)
        try TwoPaneFolderNewPlanner.validateReceipt(self, meter: &meter)
        try meter.finish()
    }

    public func requireReceipt(_ other: TwoPaneFolderNewPlanningReceipt) throws {
        guard other == receipt else {
            throw TwoPaneFolderNewError(.receiptMismatch)
        }
    }

    /// Generation-only compare-and-swap: insufficient alone to detect
    /// delete-recreate swap that reuses generations. Caller must also compare
    /// device/fileID out of band; prefer requireCurrentIdentities which checks
    /// device/fileID/generation together. Kept for source compatibility.
    /// Executor must present the generations it re-statted before entry access.
    /// Any drift from the bound plan is stale.
    public func requireCurrentGenerations(leftGeneration: UInt32, rightGeneration: UInt32) throws {
        guard leftGeneration == leftRevision.identity.generation else {
            throw TwoPaneFolderNewError(
                .staleGeneration,
                side: .left,
                expectedGeneration: leftRevision.identity.generation,
                actualGeneration: leftGeneration
            )
        }
        guard rightGeneration == rightRevision.identity.generation else {
            throw TwoPaneFolderNewError(
                .staleGeneration,
                side: .right,
                expectedGeneration: rightRevision.identity.generation,
                actualGeneration: rightGeneration
            )
        }
    }

    /// Exact device/fileID/generation compare-and-swap: executor must present the
    /// device/fileID/generation it re-statted before entry access. Any drift from
    /// the bound plan is stale. Generation alone can miss delete-recreate swap at
    /// the same path that reuses the generation counter, so all three must be
    /// compared together. For device/fileID drift with matching generations,
    /// expectedGeneration may equal actualGeneration yet the root is still stale.
    public func requireCurrentIdentities(
        leftDeviceID: UInt64,
        leftFileID: UInt64,
        leftGeneration: UInt32,
        rightDeviceID: UInt64,
        rightFileID: UInt64,
        rightGeneration: UInt32
    ) throws {
        try requireCurrentGenerations(leftGeneration: leftGeneration, rightGeneration: rightGeneration)
        guard leftDeviceID == leftRevision.identity.deviceID else {
            throw TwoPaneFolderNewError(
                .staleGeneration,
                side: .left,
                expectedGeneration: leftRevision.identity.generation,
                actualGeneration: leftGeneration
            )
        }
        guard leftFileID == leftRevision.identity.fileID else {
            throw TwoPaneFolderNewError(
                .staleGeneration,
                side: .left,
                expectedGeneration: leftRevision.identity.generation,
                actualGeneration: leftGeneration
            )
        }
        guard rightDeviceID == rightRevision.identity.deviceID else {
            throw TwoPaneFolderNewError(
                .staleGeneration,
                side: .right,
                expectedGeneration: rightRevision.identity.generation,
                actualGeneration: rightGeneration
            )
        }
        guard rightFileID == rightRevision.identity.fileID else {
            throw TwoPaneFolderNewError(
                .staleGeneration,
                side: .right,
                expectedGeneration: rightRevision.identity.generation,
                actualGeneration: rightGeneration
            )
        }
    }

    public var description: String {
        "TwoPaneFolderNewPlan(depth: \(recursionDepth), flags: \(showFlags.count), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["depth": recursionDepth, "showFlagCount": showFlags.count, "details": "<redacted>"], displayStyle: .struct)
    }
}

struct TwoPaneFolderNewWorkMeter {
    let limits: TwoPaneFolderNewLimits
    let cancellationCheck: TwoPaneFolderNewCancellationCheck
    private(set) var consumed: UInt64 = 0
    private(set) var totalPathUTF8Bytes = 0

    init(limits: TwoPaneFolderNewLimits, cancellationCheck: @escaping TwoPaneFolderNewCancellationCheck) {
        self.limits = limits
        self.cancellationCheck = cancellationCheck
    }

    mutating func consume(_ amount: UInt64 = 1) throws {
        let (next, overflow) = consumed.addingReportingOverflow(amount)
        guard !overflow, next <= limits.maximumWorkUnits else {
            throw TwoPaneFolderNewError(.workLimitExceeded, limit: .workUnits, maximum: limits.maximumWorkUnits)
        }
        let previousCheck = consumed / limits.cancellationCheckInterval
        consumed = next
        if consumed / limits.cancellationCheckInterval != previousCheck {
            try TwoPaneFolderNewPlanner.checkCancellation(cancellationCheck)
        }
    }

    mutating func measure(_ string: String) throws {
        // Bound work first: only inspect up to max+1 UTF-8 bytes so huge inputs
        // fail without scanning the full string. Exact count below is then
        // bounded by maximumPathUTF8Bytes (hard max 64 KiB).
        let maxBytes = limits.maximumPathUTF8Bytes
        if string.utf8.prefix(maxBytes + 1).count > maxBytes {
            throw TwoPaneFolderNewError(.pathTooLarge, limit: .pathUTF8Bytes, maximum: UInt64(maxBytes))
        }
        let byteCount = string.utf8.count
        guard byteCount <= maxBytes else {
            throw TwoPaneFolderNewError(.pathTooLarge, limit: .pathUTF8Bytes, maximum: UInt64(limits.maximumPathUTF8Bytes))
        }
        // Bill coarsely (per-KiB + 1) after the limit guard so over-long paths
        // report pathTooLarge instead of burning per-byte work first. Overflow-safe:
        // (bytes + 1023) / 1024 + 1 with checked arithmetic.
        let bytes = UInt64(byteCount)
        let (plus, plusOverflow) = bytes.addingReportingOverflow(1_023)
        guard !plusOverflow else {
            throw TwoPaneFolderNewError(.workLimitExceeded, limit: .workUnits, maximum: limits.maximumWorkUnits)
        }
        let kib = plus / 1_024
        let (charge, chargeOverflow) = kib.addingReportingOverflow(1)
        guard !chargeOverflow else {
            throw TwoPaneFolderNewError(.workLimitExceeded, limit: .workUnits, maximum: limits.maximumWorkUnits)
        }
        // Total-paths guard before consume so total overflow reports
        // totalPathsTooLarge without burning per-path work first, mirroring the
        // per-path precheck above.
        let (nextTotal, overflow) = totalPathUTF8Bytes.addingReportingOverflow(byteCount)
        guard !overflow, nextTotal <= limits.maximumTotalPathUTF8Bytes else {
            throw TwoPaneFolderNewError(.totalPathsTooLarge, limit: .totalPathUTF8Bytes, maximum: UInt64(limits.maximumTotalPathUTF8Bytes))
        }
        try consume(charge)
        totalPathUTF8Bytes = nextTotal
    }

    func finish() throws {
        try TwoPaneFolderNewPlanner.checkCancellation(cancellationCheck)
    }
}

struct TwoPaneFolderNewCanonicalDigest {
    private var hasher = SHA256()

    mutating func append(_ value: Bool) {
        appendByte(value ? 1 : 0)
    }

    mutating func append(_ value: Int) {
        append(Int64(value))
    }

    mutating func append(_ value: Int64) {
        appendFixedWidth(UInt64(bitPattern: value))
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

    mutating func append(_ value: Data) {
        append(UInt64(value.count))
        hasher.update(data: value)
    }

    mutating func finalize() -> Data {
        Data(hasher.finalize())
    }

    private mutating func appendByte(_ byte: UInt8) {
        hasher.update(data: Data([byte]))
    }

    private mutating func appendFixedWidth(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { hasher.update(data: Data($0)) }
    }
}
