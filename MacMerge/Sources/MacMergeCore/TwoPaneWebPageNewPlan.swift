import CryptoKit
import Foundation

/// UI-independent planning for `ID_FILE_NEW_WEBPAGE` two-pane webpage comparison.
///
/// Planning only. No WebKit, no network, no screenshots, no AppKit, and no filesystem I/O.
/// Callers supply normalized file URLs plus offline snapshot revisions (byte counts and SHA-256
/// digests). The planner binds exact revisions, binds `WebPageComparisonOptions` mode and limits,
/// and emits a deterministic receipt plus an executor contract. Rendered comparison stays
/// executor-side via `WebPageComparison`, `WebPageComparisonMode`, `WebPageComparisonOptions`,
/// and `WebPageComparisonLimits` (referenced here, never redeclared).
public enum TwoPaneWebPageNewPlanSide: String, CaseIterable, Hashable, Sendable {
    case left
    case right
}

/// Normalized offline source plus its snapshot revision.
///
/// `normalizedURL` must already be a canonical file URL (standardized, no query or fragment).
/// `byteCount` is the observed markup byte count. `digest` is the SHA-256 revision of the exact
/// bytes the executor must pin. Planning never reads the URL.
public struct TwoPaneWebPageNewPlanSnapshot: Equatable, Hashable, Sendable {
    public let normalizedURL: URL
    public let byteCount: Int
    public let digest: Data

    public init(normalizedURL: URL, byteCount: Int, digest: Data) {
        self.normalizedURL = normalizedURL
        self.byteCount = byteCount
        self.digest = digest
    }
}

extension TwoPaneWebPageNewPlanSnapshot: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "TwoPaneWebPageNewPlanSnapshot(bytes: \(byteCount), digest: \(TwoPaneWebPageNewPlanDigestHex.prefix(of: digest)), url: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "byteCount": byteCount,
                "digestByteCount": digest.count,
                "digestPrefix": TwoPaneWebPageNewPlanDigestHex.prefix(of: digest),
                "url": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Comparison flags bound into the receipt.
///
/// Currently the mode selects source versus rendered-text comparison. The struct exists so the
/// receipt can check flags explicitly without conflating them with byte counts or work units.
public struct TwoPaneWebPageNewPlanFlags: Equatable, Hashable, Sendable {
    public let mode: WebPageComparisonMode

    public init(mode: WebPageComparisonMode) {
        self.mode = mode
    }
}

/// Planning bounds. All maxima are enforced before any receipt is issued.
/// `urlPathBytes` bounds each normalized URL path, `markupBytes` bounds each snapshot revision,
/// and `workUnits` bounds the planning ledger.
public enum TwoPaneWebPageNewPlanLimit: String, CaseIterable, Hashable, Sendable {
    case urlPathBytes
    case markupBytes
    case workUnits
    case cancellationCheckInterval
}

public struct TwoPaneWebPageNewPlanLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumURLPathBytes = 64 * 1_024
    public static let hardMaximumMarkupBytes = 64 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 512 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval: UInt64 = 65_536
    public static let `default` = TwoPaneWebPageNewPlanLimits()

    public let maximumURLPathBytes: Int
    public let maximumMarkupBytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: UInt64

    public init(
        maximumURLPathBytes: Int = 16 * 1_024,
        maximumMarkupBytes: Int = 64 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 256 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 256
    ) {
        self.maximumURLPathBytes = maximumURLPathBytes
        self.maximumMarkupBytes = maximumMarkupBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }

    public func validate() throws {
        guard maximumURLPathBytes >= 1, maximumURLPathBytes <= Self.hardMaximumURLPathBytes else {
            throw TwoPaneWebPageNewPlanError.invalidLimit(.urlPathBytes)
        }
        guard maximumMarkupBytes >= 1, maximumMarkupBytes <= Self.hardMaximumMarkupBytes else {
            throw TwoPaneWebPageNewPlanError.invalidLimit(.markupBytes)
        }
        guard maximumWorkUnits >= 1, maximumWorkUnits <= Self.hardMaximumWorkUnits else {
            throw TwoPaneWebPageNewPlanError.invalidLimit(.workUnits)
        }
        guard cancellationCheckInterval >= 1, cancellationCheckInterval <= Self.hardMaximumCancellationCheckInterval else {
            throw TwoPaneWebPageNewPlanError.invalidLimit(.cancellationCheckInterval)
        }
    }
}

/// Typed planning failures. Summaries carry counts and digest prefixes only, never full URLs,
/// markup bytes, or full digests.
public enum TwoPaneWebPageNewPlanError: Error, Equatable, Hashable, Sendable {
    case cancelled
    case invalidLimit(TwoPaneWebPageNewPlanLimit)
    case workLimitExceeded(limit: TwoPaneWebPageNewPlanLimit, maximum: UInt64)
    case invalidNormalizedURL(side: TwoPaneWebPageNewPlanSide)
    case urlPathTooLarge(side: TwoPaneWebPageNewPlanSide, maximum: Int)
    case markupTooLarge(side: TwoPaneWebPageNewPlanSide, maximum: Int)
    case invalidDigest(side: TwoPaneWebPageNewPlanSide)
    case duplicateSnapshot
    case invalidComparisonOptions
    case receiptMismatch
}

extension TwoPaneWebPageNewPlanError: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Two-pane webpage planning was cancelled."
        case .invalidLimit(let limit):
            "Two-pane webpage planning has an invalid \(limit.rawValue) limit."
        case .workLimitExceeded(let limit, let maximum):
            "Two-pane webpage planning exceeds the \(maximum)-unit \(limit.rawValue) limit."
        case .invalidNormalizedURL(let side):
            "Two-pane webpage \(side.rawValue) source is not a normalized file URL."
        case .urlPathTooLarge(let side, let maximum):
            "Two-pane webpage \(side.rawValue) URL exceeds the \(maximum)-byte urlPathBytes limit."
        case .markupTooLarge(let side, let maximum):
            "Two-pane webpage \(side.rawValue) snapshot exceeds the \(maximum)-byte markupBytes limit."
        case .invalidDigest(let side):
            "Two-pane webpage \(side.rawValue) revision digest is not a 32-byte SHA-256 value."
        case .duplicateSnapshot:
            "Two-pane webpage sides bind the same snapshot revision."
        case .invalidComparisonOptions:
            "Two-pane webpage comparison options exceed planning markup or work bounds."
        case .receiptMismatch:
            "Two-pane webpage plan receipt is invalid."
        }
    }

    public var description: String {
        "TwoPaneWebPageNewPlanError(code: <redacted>, detail: \(errorDescription ?? "failed"))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["detail": "<redacted>"], displayStyle: .enum)
    }
}

/// Deterministic receipt binding exact revisions.
///
/// Checks leftDigest and rightDigest plus byteCounts (leftByteCount and rightByteCount) plus
/// flags and workUnits plus planSHA256. `validateReceipt` rejects tampered fields with
/// `receiptMismatch` and inflated work with `workLimitExceeded`.
public struct TwoPaneWebPageNewPlanReceipt: Equatable, Hashable, Sendable {
    public let leftDigest: Data
    public let rightDigest: Data
    public let leftByteCount: Int
    public let rightByteCount: Int
    public let flags: TwoPaneWebPageNewPlanFlags
    public let workUnits: UInt64
    public let planSHA256: Data

    public init(
        leftDigest: Data,
        rightDigest: Data,
        leftByteCount: Int,
        rightByteCount: Int,
        flags: TwoPaneWebPageNewPlanFlags,
        workUnits: UInt64,
        planSHA256: Data
    ) {
        self.leftDigest = leftDigest
        self.rightDigest = rightDigest
        self.leftByteCount = leftByteCount
        self.rightByteCount = rightByteCount
        self.flags = flags
        self.workUnits = workUnits
        self.planSHA256 = planSHA256
    }

    /// Combined byteCounts convenience for ledger-style checks.
    public var byteCounts: (left: Int, right: Int) {
        (leftByteCount, rightByteCount)
    }
}

extension TwoPaneWebPageNewPlanReceipt: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "TwoPaneWebPageNewPlanReceipt(bytes: \(leftByteCount)+\(rightByteCount), workUnits: \(workUnits), flags: \(flags.mode.rawValue), digests: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "leftByteCount": leftByteCount,
                "rightByteCount": rightByteCount,
                "flags": flags.mode.rawValue,
                "workUnits": workUnits,
                "digests": "<redacted>",
                "planSHA256": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// One bound side: normalized URL pinned to its exact snapshot revision digest.
public struct TwoPaneWebPageNewPlanBoundSource: Equatable, Hashable, Sendable {
    public let side: TwoPaneWebPageNewPlanSide
    public let normalizedURL: URL
    public let byteCount: Int
    public let digest: Data

    public init(side: TwoPaneWebPageNewPlanSide, normalizedURL: URL, byteCount: Int, digest: Data) {
        self.side = side
        self.normalizedURL = normalizedURL
        self.byteCount = byteCount
        self.digest = digest
    }
}

extension TwoPaneWebPageNewPlanBoundSource: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "TwoPaneWebPageNewPlanBoundSource(side: \(side.rawValue), bytes: \(byteCount), digest: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "side": side.rawValue,
                "byteCount": byteCount,
                "digest": "<redacted>",
                "url": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Plan-only executor contract. Data only; the executor performs loading and comparison off-plan.
public struct TwoPaneWebPageNewPlanExecutorContract: Equatable, Hashable, Sendable {
    public static let required = TwoPaneWebPageNewPlanExecutorContract()

    public let comparisonCoreName: String
    public let planOnlyWithoutIO: Bool

    public init(comparisonCoreName: String = "WebPageComparison", planOnlyWithoutIO: Bool = true) {
        self.comparisonCoreName = comparisonCoreName
        self.planOnlyWithoutIO = planOnlyWithoutIO
    }
}

/// Caller request: two snapshot revisions plus bound comparison options and planning limits.
public struct TwoPaneWebPageNewPlanRequest: Equatable, Sendable {
    public let left: TwoPaneWebPageNewPlanSnapshot
    public let right: TwoPaneWebPageNewPlanSnapshot
    public let comparisonOptions: WebPageComparisonOptions
    public let limits: TwoPaneWebPageNewPlanLimits

    public init(
        left: TwoPaneWebPageNewPlanSnapshot,
        right: TwoPaneWebPageNewPlanSnapshot,
        comparisonOptions: WebPageComparisonOptions = WebPageComparisonOptions(),
        limits: TwoPaneWebPageNewPlanLimits = .default
    ) {
        self.left = left
        self.right = right
        self.comparisonOptions = comparisonOptions
        self.limits = limits
    }

    public var mode: WebPageComparisonMode {
        comparisonOptions.mode
    }

    /// Resolved executor options. Throws after `try validate` when planning limits are invalid
    /// or when bound comparison limits exceed planning markup and work bounds.
    /// Token/attribute/depth comparison limits (maximumTokenCount, maximumAttributeCount,
    /// maximumAttributesPerTag, maximumElementDepth) are intentionally unbound here: planning
    /// budgets markup bytes and work units only, while tokenization stays executor-side and is
    /// pinned into the receipt SHA so drift is still detected.
    public func resolvedComparisonOptions() throws -> WebPageComparisonOptions {
        try limits.validate()
        guard comparisonOptions.limits.maximumInputBytes >= 0, comparisonOptions.limits.maximumInputBytes <= limits.maximumMarkupBytes else {
            throw TwoPaneWebPageNewPlanError.invalidComparisonOptions
        }
        guard comparisonOptions.limits.maximumOutputBytes >= 0, comparisonOptions.limits.maximumOutputBytes <= limits.maximumMarkupBytes else {
            throw TwoPaneWebPageNewPlanError.invalidComparisonOptions
        }
        guard comparisonOptions.limits.maximumWorkUnits >= 0, comparisonOptions.limits.maximumWorkUnits <= limits.maximumWorkUnits else {
            throw TwoPaneWebPageNewPlanError.invalidComparisonOptions
        }
        return comparisonOptions
    }
}

extension TwoPaneWebPageNewPlanRequest: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "TwoPaneWebPageNewPlanRequest(mode: \(comparisonOptions.mode.rawValue), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "mode": comparisonOptions.mode.rawValue,
                "leftByteCount": left.byteCount,
                "rightByteCount": right.byteCount,
                "details": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Bound two-pane webpage comparison plan for `ID_FILE_NEW_WEBPAGE`.
///
/// Binds normalized URLs, snapshot revisions, and `WebPageComparisonOptions` mode and limits.
/// Planning is bounded by a work ledger, cancellable during planning, and fully redacted.
public struct TwoPaneWebPageNewPlan: Equatable, Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let commandID = "ID_FILE_NEW_WEBPAGE"

    public let left: TwoPaneWebPageNewPlanBoundSource
    public let right: TwoPaneWebPageNewPlanBoundSource
    public let comparisonOptions: WebPageComparisonOptions
    public let limits: TwoPaneWebPageNewPlanLimits
    public let receipt: TwoPaneWebPageNewPlanReceipt
    public let executorContract: TwoPaneWebPageNewPlanExecutorContract

    public init(
        left: TwoPaneWebPageNewPlanBoundSource,
        right: TwoPaneWebPageNewPlanBoundSource,
        comparisonOptions: WebPageComparisonOptions,
        limits: TwoPaneWebPageNewPlanLimits,
        receipt: TwoPaneWebPageNewPlanReceipt
    ) {
        self.left = left
        self.right = right
        self.comparisonOptions = comparisonOptions
        self.limits = limits
        self.receipt = receipt
        self.executorContract = .required
    }

    public var mode: WebPageComparisonMode {
        comparisonOptions.mode
    }

    public var flags: TwoPaneWebPageNewPlanFlags {
        TwoPaneWebPageNewPlanFlags(mode: comparisonOptions.mode)
    }

    /// Resolved executor options. Throws after `try validate` when planning limits drift.
    /// Token/attribute/depth comparison limits are intentionally unbound here for the same
    /// reason as `TwoPaneWebPageNewPlanRequest.resolvedComparisonOptions`: planning budgets
    /// markup bytes and work units only; tokenization stays executor-side and is pinned into
    /// the receipt SHA.
    public func resolvedComparisonOptions() throws -> WebPageComparisonOptions {
        try limits.validate()
        guard comparisonOptions.limits.maximumInputBytes >= 0, comparisonOptions.limits.maximumInputBytes <= limits.maximumMarkupBytes else {
            throw TwoPaneWebPageNewPlanError.invalidComparisonOptions
        }
        guard comparisonOptions.limits.maximumOutputBytes >= 0, comparisonOptions.limits.maximumOutputBytes <= limits.maximumMarkupBytes else {
            throw TwoPaneWebPageNewPlanError.invalidComparisonOptions
        }
        guard comparisonOptions.limits.maximumWorkUnits >= 0, comparisonOptions.limits.maximumWorkUnits <= limits.maximumWorkUnits else {
            throw TwoPaneWebPageNewPlanError.invalidComparisonOptions
        }
        return comparisonOptions
    }

    /// Exact compare-and-swap: rejects tampered digests, byteCounts, flags, or planSHA256 with
    /// `receiptMismatch`, and inflated work with `workLimitExceeded`.
    public func validateReceipt() throws {
        try limits.validate()
        try Self.validateBoundSource(left, expectedSide: .left, limits: limits)
        try Self.validateBoundSource(right, expectedSide: .right, limits: limits)
        guard receipt.leftDigest == left.digest else {
            throw TwoPaneWebPageNewPlanError.receiptMismatch
        }
        guard receipt.rightDigest == right.digest else {
            throw TwoPaneWebPageNewPlanError.receiptMismatch
        }
        guard receipt.leftByteCount == left.byteCount else {
            throw TwoPaneWebPageNewPlanError.receiptMismatch
        }
        guard receipt.rightByteCount == right.byteCount else {
            throw TwoPaneWebPageNewPlanError.receiptMismatch
        }
        guard receipt.flags == flags else {
            throw TwoPaneWebPageNewPlanError.receiptMismatch
        }
        guard receipt.workUnits <= limits.maximumWorkUnits else {
            throw TwoPaneWebPageNewPlanError.workLimitExceeded(limit: .workUnits, maximum: limits.maximumWorkUnits)
        }
        let expected = Self.canonicalPlanSHA256(
            left: left,
            right: right,
            flags: flags,
            comparisonLimits: comparisonOptions.limits,
            limits: limits,
            workUnits: receipt.workUnits
        )
        guard expected == receipt.planSHA256 else {
            throw TwoPaneWebPageNewPlanError.receiptMismatch
        }
    }

    public static func plan(
        _ request: TwoPaneWebPageNewPlanRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> TwoPaneWebPageNewPlan {
        try make(request, cancellationCheck: cancellationCheck)
    }

    public static func make(
        _ request: TwoPaneWebPageNewPlanRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> TwoPaneWebPageNewPlan {
        try request.limits.validate()
        var ledger = TwoPaneWebPageNewPlanLedger(
            maximumWorkUnits: request.limits.maximumWorkUnits,
            cancellationCheckInterval: request.limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try ledger.checkpoint()
        try ledger.consume(1)
        let left = try bind(request.left, side: .left, limits: request.limits, ledger: &ledger)
        let right = try bind(request.right, side: .right, limits: request.limits, ledger: &ledger)
        // Duplicate means same target or same pinned revision: identical URLs compare
        // nothing, and identical digest plus identical byteCount pins the exact same bytes
        // on both sides. Digest alone is not checked without byteCount so the ledger count
        // and the pinned revision stay in lockstep and tampering with either is rejected.
        if left.normalizedURL == right.normalizedURL || (left.digest == right.digest && left.byteCount == right.byteCount) {
            throw TwoPaneWebPageNewPlanError.duplicateSnapshot
        }
        try ledger.consume(1)
        _ = try request.resolvedComparisonOptions()
        try ledger.consume(1)
        try ledger.checkpoint()
        let flags = TwoPaneWebPageNewPlanFlags(mode: request.comparisonOptions.mode)
        let digest = canonicalPlanSHA256(
            left: left,
            right: right,
            flags: flags,
            comparisonLimits: request.comparisonOptions.limits,
            limits: request.limits,
            workUnits: ledger.spent
        )
        let receipt = TwoPaneWebPageNewPlanReceipt(
            leftDigest: left.digest,
            rightDigest: right.digest,
            leftByteCount: left.byteCount,
            rightByteCount: right.byteCount,
            flags: flags,
            workUnits: ledger.spent,
            planSHA256: digest
        )
        try ledger.checkpoint()
        return TwoPaneWebPageNewPlan(
            left: left,
            right: right,
            comparisonOptions: request.comparisonOptions,
            limits: request.limits,
            receipt: receipt
        )
    }

    private static func validateBoundSource(
        _ bound: TwoPaneWebPageNewPlanBoundSource,
        expectedSide: TwoPaneWebPageNewPlanSide,
        limits: TwoPaneWebPageNewPlanLimits
    ) throws {
        guard bound.side == expectedSide else {
            throw TwoPaneWebPageNewPlanError.receiptMismatch
        }
        guard isCanonicalFileURL(bound.normalizedURL) else {
            throw TwoPaneWebPageNewPlanError.invalidNormalizedURL(side: expectedSide)
        }
        let pathBytes = bound.normalizedURL.path(percentEncoded: false).utf8.count
        guard pathBytes <= limits.maximumURLPathBytes else {
            throw TwoPaneWebPageNewPlanError.urlPathTooLarge(side: expectedSide, maximum: limits.maximumURLPathBytes)
        }
        guard bound.byteCount >= 0, bound.byteCount <= limits.maximumMarkupBytes else {
            throw TwoPaneWebPageNewPlanError.markupTooLarge(side: expectedSide, maximum: limits.maximumMarkupBytes)
        }
        guard bound.digest.count == 32, !bound.digest.allSatisfy({ $0 == 0 }) else {
            throw TwoPaneWebPageNewPlanError.invalidDigest(side: expectedSide)
        }
    }

    private static func bind(
        _ snapshot: TwoPaneWebPageNewPlanSnapshot,
        side: TwoPaneWebPageNewPlanSide,
        limits: TwoPaneWebPageNewPlanLimits,
        ledger: inout TwoPaneWebPageNewPlanLedger
    ) throws -> TwoPaneWebPageNewPlanBoundSource {
        guard isCanonicalFileURL(snapshot.normalizedURL) else {
            throw TwoPaneWebPageNewPlanError.invalidNormalizedURL(side: side)
        }
        let pathBytes = snapshot.normalizedURL.path(percentEncoded: false).utf8.count
        guard pathBytes <= limits.maximumURLPathBytes else {
            throw TwoPaneWebPageNewPlanError.urlPathTooLarge(side: side, maximum: limits.maximumURLPathBytes)
        }
        try ledger.consume(UInt64(pathBytes / 512 + 1))
        guard snapshot.byteCount >= 0, snapshot.byteCount <= limits.maximumMarkupBytes else {
            throw TwoPaneWebPageNewPlanError.markupTooLarge(side: side, maximum: limits.maximumMarkupBytes)
        }
        try ledger.consume(UInt64(snapshot.byteCount / 1_024 + 1))
        guard snapshot.digest.count == 32, !snapshot.digest.allSatisfy({ $0 == 0 }) else {
            throw TwoPaneWebPageNewPlanError.invalidDigest(side: side)
        }
        try ledger.consume(UInt64(snapshot.digest.count))
        return TwoPaneWebPageNewPlanBoundSource(
            side: side,
            normalizedURL: snapshot.normalizedURL,
            byteCount: snapshot.byteCount,
            digest: snapshot.digest
        )
    }

    // Content-addressed plus URL-bound: includes normalized URLs for stale-target rejection,
    // snapshot revisions for exact pinning, flags for mode, planning limits, comparison limits,
    // and workUnits for ledger binding.
    // byteCounts (leftByteCount and rightByteCount) are part of the hashed canonical form.
    static func canonicalPlanSHA256(
        left: TwoPaneWebPageNewPlanBoundSource,
        right: TwoPaneWebPageNewPlanBoundSource,
        flags: TwoPaneWebPageNewPlanFlags,
        comparisonLimits: WebPageComparisonLimits,
        limits: TwoPaneWebPageNewPlanLimits,
        workUnits: UInt64
    ) -> Data {
        let canonical = [
            "TwoPaneWebPageNewPlan/v1",
            "command:\(commandID)",
            "left:\(left.normalizedURL.absoluteString):\(left.byteCount):\(TwoPaneWebPageNewPlanDigestHex.hex(of: left.digest))",
            "right:\(right.normalizedURL.absoluteString):\(right.byteCount):\(TwoPaneWebPageNewPlanDigestHex.hex(of: right.digest))",
            "mode:\(flags.mode.rawValue)",
            "flags:\(flags.mode.rawValue)",
            "inputBytes:\(comparisonLimits.maximumInputBytes)",
            "tokens:\(comparisonLimits.maximumTokenCount)",
            "attributes:\(comparisonLimits.maximumAttributeCount)",
            "attributesPerTag:\(comparisonLimits.maximumAttributesPerTag)",
            "elementDepth:\(comparisonLimits.maximumElementDepth)",
            "comparisonWork:\(comparisonLimits.maximumWorkUnits)",
            "outputBytes:\(comparisonLimits.maximumOutputBytes)",
            "urlPathBytes:\(limits.maximumURLPathBytes)",
            "markupBytes:\(limits.maximumMarkupBytes)",
            "workUnits:\(limits.maximumWorkUnits)",
            "interval:\(limits.cancellationCheckInterval)",
            "spent:\(workUnits)"
        ].joined(separator: "|")
        return Data(SHA256.hash(data: Data(canonical.utf8)))
    }

    private static func isCanonicalFileURL(_ url: URL) -> Bool {
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
        guard let host = components.host else {
            return true
        }
        return host.isEmpty || host.caseInsensitiveCompare("localhost") == .orderedSame
    }
}

extension TwoPaneWebPageNewPlan: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "TwoPaneWebPageNewPlan(mode: \(mode.rawValue), bytes: \(left.byteCount)+\(right.byteCount), workUnits: \(receipt.workUnits), details: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "mode": mode.rawValue,
                "leftByteCount": left.byteCount,
                "rightByteCount": right.byteCount,
                "workUnits": receipt.workUnits,
                "details": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

private enum TwoPaneWebPageNewPlanDigestHex {
    static func hex(of data: Data) -> String {
        var result = ""
        result.reserveCapacity(data.count * 2)
        let digits = Array("0123456789abcdef")
        for byte in data {
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 0x0F)])
        }
        return result
    }

    static func prefix(of data: Data) -> String {
        hex(of: data.prefix(8))
    }
}

/// Bounded planning ledger with periodic cancellation checks.
private struct TwoPaneWebPageNewPlanLedger: Sendable {
    let maximumWorkUnits: UInt64
    let cancellationCheckInterval: UInt64
    let cancellationCheck: TwoPaneWebPageNewPlan.CancellationCheck
    private(set) var spent: UInt64 = 0
    private var nextCheckAt: UInt64

    init(
        maximumWorkUnits: UInt64,
        cancellationCheckInterval: UInt64,
        cancellationCheck: @escaping TwoPaneWebPageNewPlan.CancellationCheck
    ) {
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
        self.nextCheckAt = cancellationCheckInterval
    }

    mutating func consume(_ amount: UInt64) throws {
        guard amount <= maximumWorkUnits, spent <= maximumWorkUnits - amount else {
            try checkpoint()
            throw TwoPaneWebPageNewPlanError.workLimitExceeded(limit: .workUnits, maximum: maximumWorkUnits)
        }
        spent += amount
        if spent >= nextCheckAt {
            nextCheckAt = nextCheckAt &+ cancellationCheckInterval
            try checkpoint()
        }
    }

    func checkpoint() throws {
        do {
            try cancellationCheck()
        } catch is CancellationError {
            throw TwoPaneWebPageNewPlanError.cancelled
        }
    }
}
