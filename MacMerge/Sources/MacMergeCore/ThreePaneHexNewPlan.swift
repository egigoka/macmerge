import CryptoKit
import Foundation

/// Bounded UI-independent three-pane binary/hex new comparison core.
///
/// Groundwork for `ID_FILE_NEW3_HEX`. Planning only: never reads files,
/// creates documents, opens pickers, touches the filesystem, performs
/// hex-view rendering, or mutates bytes. A document host must materialize
/// the bound sources and provide all UI. Comparison semantics defer to
/// `BinaryComparison` / `BinaryComparisonOptions` and
/// `ThreeWayBinaryComparison` / `ThreeWayBinaryComparisonOptions`.
/// This file redeclares none of those cores.
public enum ThreePaneHexNewSide: String, CaseIterable, Hashable, Sendable {
    case left
    case middle
    case right

    fileprivate var sortOrder: Int {
        switch self {
        case .left: 0
        case .middle: 1
        case .right: 2
        }
    }
}

public enum ThreePaneHexNewLimit: String, CaseIterable, Hashable, Sendable {
    case sources
    case pathUTF8Bytes
    case totalPathUTF8Bytes
    case byteSize
    case windowLength
    case bytesPerRow
    case stringBytes
    case findings
    case workUnits
    case cancellationCheckInterval
}

/// Dual-tier source budget: this type accepts `maximumSources` in
/// `1...hardMaximumSources` so restricted configurations validate, but
/// `ThreePaneHexNewPlanningWork.plan(_:)` additionally requires
/// `maximumSources == 3`. A three-pane plan always binds exactly three panes;
/// fewer sources are modeled with `.empty` panes, never with a smaller array.
public struct ThreePaneHexNewLimits: Equatable, Sendable {
    public static let hardMaximumSources = 3
    public static let hardMaximumPathUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 512 * 1_024
    public static let hardMaximumByteSize: UInt64 = 64 * 1_024 * 1_024
    public static let hardMaximumWindowLength: UInt64 = 64 * 1_024 * 1_024
    public static let hardMaximumBytesPerRow = 64
    public static let hardMaximumStringBytes = 16 * 1_024
    public static let hardMaximumFindings = 16
    public static let hardMaximumWorkUnits: UInt64 = 1_000_000
    public static let hardMaximumCancellationCheckInterval = 4_096

    public static let `default`: ThreePaneHexNewLimits = {
        do {
            return try ThreePaneHexNewLimits()
        } catch {
            preconditionFailure("ThreePaneHexNewLimits default invalid: \(error)")
        }
    }()

    public let maximumSources: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumByteSize: UInt64
    public let maximumWindowLength: UInt64
    public let maximumBytesPerRow: Int
    public let maximumStringBytes: Int
    public let maximumFindings: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: Int

    public init(
        maximumSources: Int = 3,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 128 * 1_024,
        maximumByteSize: UInt64 = 64 * 1_024 * 1_024,
        maximumWindowLength: UInt64 = 8 * 1_024 * 1_024,
        maximumBytesPerRow: Int = 16,
        maximumStringBytes: Int = 4 * 1_024,
        maximumFindings: Int = 8,
        maximumWorkUnits: UInt64 = 1_024,
        cancellationCheckInterval: Int = 64
    ) throws {
        guard (1...Self.hardMaximumSources).contains(maximumSources) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.sources)
        }
        guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.pathUTF8Bytes)
        }
        guard maximumTotalPathUTF8Bytes >= maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes <= Self.hardMaximumTotalPathUTF8Bytes,
            maximumTotalPathUTF8Bytes >= 1
        else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.totalPathUTF8Bytes)
        }
        guard maximumByteSize >= 1 && maximumByteSize <= Self.hardMaximumByteSize else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.byteSize)
        }
        guard maximumWindowLength >= 1 && maximumWindowLength <= Self.hardMaximumWindowLength else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.windowLength)
        }
        guard (1...Self.hardMaximumBytesPerRow).contains(maximumBytesPerRow) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.bytesPerRow)
        }
        guard (1...Self.hardMaximumStringBytes).contains(maximumStringBytes) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.stringBytes)
        }
        guard (1...Self.hardMaximumFindings).contains(maximumFindings) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.findings)
        }
        guard maximumWorkUnits >= 1 && maximumWorkUnits <= Self.hardMaximumWorkUnits else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.workUnits)
        }
        guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.cancellationCheckInterval)
        }
        self.maximumSources = maximumSources
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumByteSize = maximumByteSize
        self.maximumWindowLength = maximumWindowLength
        self.maximumBytesPerRow = maximumBytesPerRow
        self.maximumStringBytes = maximumStringBytes
        self.maximumFindings = maximumFindings
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }

    public func validate() throws {
        guard (1...Self.hardMaximumSources).contains(maximumSources) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.sources)
        }
        guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.pathUTF8Bytes)
        }
        guard maximumTotalPathUTF8Bytes >= maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes <= Self.hardMaximumTotalPathUTF8Bytes,
            maximumTotalPathUTF8Bytes >= 1
        else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.totalPathUTF8Bytes)
        }
        guard maximumByteSize >= 1 && maximumByteSize <= Self.hardMaximumByteSize else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.byteSize)
        }
        guard maximumWindowLength >= 1 && maximumWindowLength <= Self.hardMaximumWindowLength else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.windowLength)
        }
        guard (1...Self.hardMaximumBytesPerRow).contains(maximumBytesPerRow) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.bytesPerRow)
        }
        guard (1...Self.hardMaximumStringBytes).contains(maximumStringBytes) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.stringBytes)
        }
        guard (1...Self.hardMaximumFindings).contains(maximumFindings) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.findings)
        }
        guard maximumWorkUnits >= 1 && maximumWorkUnits <= Self.hardMaximumWorkUnits else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.workUnits)
        }
        guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.cancellationCheckInterval)
        }
    }
}

/// Caller-captured identity for one canonical file plus its exact revision.
///
/// Planning never resolves this URL. Executors must pin the object by its
/// SHA-256 digest rather than treating the URL as authority.
///
/// Zero-byte exclusion: `byteSize >= 1` is required. An empty slot must be
/// modeled as `ThreePaneHexNewPaneSource.empty`, never as a zero-byte file
/// identity, so `sourceCount`, window-bounds checks, and receipt binding stay
/// unambiguous between "no source bound" and "a source with no bytes".
public struct ThreePaneHexNewFileIdentity: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let canonicalURL: URL
    public let canonicalPath: String
    public let byteSize: UInt64
    public let contentSHA256: [UInt8]

    public init(canonicalURL: URL, canonicalPath: String, byteSize: UInt64, contentSHA256: [UInt8]) {
        self.canonicalURL = canonicalURL
        self.canonicalPath = canonicalPath
        self.byteSize = byteSize
        self.contentSHA256 = contentSHA256
    }

    public var description: String {
        "ThreePaneHexNewFileIdentity(bytes: \(byteSize), pathBytes: \(canonicalPath.utf8.count), digest: \(ThreePaneHexNewDigestHex.prefix(of: contentSHA256)))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "byteSize": byteSize,
                "pathByteCount": canonicalPath.utf8.count,
                "digestByteCount": contentSHA256.count,
                "digestPrefix": ThreePaneHexNewDigestHex.prefix(of: contentSHA256)
            ],
            displayStyle: .struct
        )
    }
}

public enum ThreePaneHexNewPaneSource: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case empty
    case file(ThreePaneHexNewFileIdentity)

    public var isEmpty: Bool {
        if case .empty = self { true } else { false }
    }

    public var description: String {
        switch self {
        case .empty:
            "ThreePaneHexNewPaneSource(empty)"
        case .file(let identity):
            "ThreePaneHexNewPaneSource(file bytes: \(identity.byteSize), digest: \(ThreePaneHexNewDigestHex.prefix(of: identity.contentSHA256)))"
        }
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "isEmpty": isEmpty,
                "detail": "<redacted>"
            ],
            displayStyle: .enum
        )
    }
}

public struct ThreePaneHexNewPane: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let side: ThreePaneHexNewSide
    public let source: ThreePaneHexNewPaneSource
    public let isReadOnly: Bool

    public init(side: ThreePaneHexNewSide, source: ThreePaneHexNewPaneSource, isReadOnly: Bool = true) {
        self.side = side
        self.source = source
        self.isReadOnly = isReadOnly
    }

    public var isEmpty: Bool { source.isEmpty }

    public var description: String {
        "ThreePaneHexNewPane(\(side.rawValue), empty: \(isEmpty), readOnly: \(isReadOnly))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "side": side.rawValue,
                "isEmpty": isEmpty,
                "isReadOnly": isReadOnly,
                "source": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct ThreePaneHexNewByteWindow: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let offset: UInt64
    public let length: UInt64

    public init(offset: UInt64, length: UInt64) {
        self.offset = offset
        self.length = length
    }

    public var description: String {
        "ThreePaneHexNewByteWindow(offset: \(offset), length: \(length))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "offset": offset,
                "length": length
            ],
            displayStyle: .struct
        )
    }
}

/// Capability requirement naming the existing binary comparison cores.
///
/// Values are carried through so the host configures the same cores the
/// plan was validated against. Nothing here redeclares those cores.
///
/// Non-negative carry-through: every bound must be `>= 0`; planning rejects
/// negatives with `unsupportedCapability` and never clamps them, so the
/// receipt always binds the exact core configuration the host must honor.
public struct ThreePaneHexNewCapabilityRequirement: Equatable, Sendable {
    public let twoWay: BinaryComparisonOptions
    public let threeWay: ThreeWayBinaryComparisonOptions

    public init(twoWay: BinaryComparisonOptions = BinaryComparisonOptions(), threeWay: ThreeWayBinaryComparisonOptions = .default) {
        self.twoWay = twoWay
        self.threeWay = threeWay
    }
}

/// A new-comparison request. All three panes must be present; unbound slots
/// use `.empty`. `sourceCount == 0` with a non-empty window is intentional:
/// it describes a fresh window with nothing bound yet (findings all
/// `.windowedView`), ready for later binding without changing window shape.
public struct ThreePaneHexNewRequest: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let minimumBytesPerRow = 1
    public static let maximumBytesPerRow = 64
    public static let defaultBytesPerRow = 16

    public let panes: [ThreePaneHexNewPane]
    public let window: ThreePaneHexNewByteWindow
    public let bytesPerRow: Int
    public let capability: ThreePaneHexNewCapabilityRequirement
    public let limits: ThreePaneHexNewLimits

    public init(
        panes: [ThreePaneHexNewPane],
        window: ThreePaneHexNewByteWindow,
        bytesPerRow: Int = 16,
        capability: ThreePaneHexNewCapabilityRequirement = ThreePaneHexNewCapabilityRequirement(),
        limits: ThreePaneHexNewLimits = .default
    ) {
        self.panes = panes
        self.window = window
        self.bytesPerRow = bytesPerRow
        self.capability = capability
        self.limits = limits
    }

    public init(
        left: ThreePaneHexNewPaneSource,
        middle: ThreePaneHexNewPaneSource,
        right: ThreePaneHexNewPaneSource,
        window: ThreePaneHexNewByteWindow,
        bytesPerRow: Int = 16,
        capability: ThreePaneHexNewCapabilityRequirement = ThreePaneHexNewCapabilityRequirement(),
        limits: ThreePaneHexNewLimits = .default,
        isReadOnly: Bool = true
    ) {
        self.init(
            panes: [
                ThreePaneHexNewPane(side: .left, source: left, isReadOnly: isReadOnly),
                ThreePaneHexNewPane(side: .middle, source: middle, isReadOnly: isReadOnly),
                ThreePaneHexNewPane(side: .right, source: right, isReadOnly: isReadOnly)
            ],
            window: window,
            bytesPerRow: bytesPerRow,
            capability: capability,
            limits: limits
        )
    }

    public var description: String {
        "ThreePaneHexNewRequest(panes: \(panes.count), offset: \(window.offset), length: \(window.length), bytesPerRow: \(bytesPerRow))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "paneCount": panes.count,
                "windowOffset": window.offset,
                "windowLength": window.length,
                "bytesPerRow": bytesPerRow,
                "sources": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum ThreePaneHexNewSourceRevisionContract: String, Hashable, Sendable {
    case exactDigestPinnedThroughExecution
}

public enum ThreePaneHexNewRangeContract: String, Hashable, Sendable {
    case windowedReadOnlyNoMutation
}

public enum ThreePaneHexNewIOContract: String, Hashable, Sendable {
    case planOnlyNoFileSystemAccess
}

public enum ThreePaneHexNewCancellationContract: String, Hashable, Sendable {
    case cancellableDuringPlanningOnly
}

public struct ThreePaneHexNewExecutorContract: Equatable, Sendable {
    public static let required = ThreePaneHexNewExecutorContract()

    public let sourceRevision = ThreePaneHexNewSourceRevisionContract.exactDigestPinnedThroughExecution
    public let range = ThreePaneHexNewRangeContract.windowedReadOnlyNoMutation
    public let fileSystem = ThreePaneHexNewIOContract.planOnlyNoFileSystemAccess
    public let cancellation = ThreePaneHexNewCancellationContract.cancellableDuringPlanningOnly
    public let readOnly = true

    public init() {}
}

public enum ThreePaneHexNewFinding: String, CaseIterable, Hashable, Sendable {
    case fullCoverage
    case windowedView
}

public struct ThreePaneHexNewReceipt: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let value: String
    public let sourceCount: Int
    public let windowOffset: UInt64
    public let windowLength: UInt64
    public let bytesPerRow: Int
    public let workUnits: UInt64

    public init(value: String, sourceCount: Int, windowOffset: UInt64, windowLength: UInt64, bytesPerRow: Int, workUnits: UInt64) {
        self.value = value
        self.sourceCount = sourceCount
        self.windowOffset = windowOffset
        self.windowLength = windowLength
        self.bytesPerRow = bytesPerRow
        self.workUnits = workUnits
    }

    public var description: String {
        "ThreePaneHexNewReceipt(\(value), sources: \(sourceCount), offset: \(windowOffset), length: \(windowLength), bytesPerRow: \(bytesPerRow), work: \(workUnits))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "value": value,
                "sourceCount": sourceCount,
                "windowOffset": windowOffset,
                "windowLength": windowLength,
                "bytesPerRow": bytesPerRow,
                "workUnits": workUnits
            ],
            displayStyle: .struct
        )
    }
}

public struct ThreePaneHexNewPlan: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let panes: [ThreePaneHexNewPane]
    public let window: ThreePaneHexNewByteWindow
    public let bytesPerRow: Int
    public let capability: ThreePaneHexNewCapabilityRequirement
    public let findings: [ThreePaneHexNewFinding]
    public let receipt: ThreePaneHexNewReceipt
    public let executorContract: ThreePaneHexNewExecutorContract
    public let limits: ThreePaneHexNewLimits
    public let estimatedWorkUnits: UInt64

    fileprivate init(
        panes: [ThreePaneHexNewPane],
        window: ThreePaneHexNewByteWindow,
        bytesPerRow: Int,
        capability: ThreePaneHexNewCapabilityRequirement,
        findings: [ThreePaneHexNewFinding],
        receipt: ThreePaneHexNewReceipt,
        limits: ThreePaneHexNewLimits,
        estimatedWorkUnits: UInt64
    ) {
        self.panes = panes
        self.window = window
        self.bytesPerRow = bytesPerRow
        self.capability = capability
        self.findings = findings
        self.receipt = receipt
        executorContract = .required
        self.limits = limits
        self.estimatedWorkUnits = estimatedWorkUnits
    }

    public func requireReceipt(_ receipt: ThreePaneHexNewReceipt) throws {
        guard receipt == self.receipt else {
            throw ThreePaneHexNewPlanningError.receiptMismatch
        }
    }

    public var description: String {
        "ThreePaneHexNewPlan(panes: \(panes.count), findings: \(findings.count), length: \(window.length), bytesPerRow: \(bytesPerRow), receipt: \(receipt.value))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "paneCount": panes.count,
                "findingCount": findings.count,
                "windowOffset": window.offset,
                "windowLength": window.length,
                "bytesPerRow": bytesPerRow,
                "receipt": receipt.value,
                "workUnits": estimatedWorkUnits,
                "sources": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum ThreePaneHexNewPlanningError: Error, LocalizedError, Equatable, Sendable, CustomDebugStringConvertible, CustomReflectable {
    case cancelled
    case invalidLimit(ThreePaneHexNewLimit)
    case invalidPaneCount(actual: Int)
    case duplicatePane(ThreePaneHexNewSide)
    case missingPane(ThreePaneHexNewSide)
    case invalidCanonicalURL(ThreePaneHexNewSide)
    case canonicalPathMismatch(ThreePaneHexNewSide)
    case pathTooLarge(side: ThreePaneHexNewSide, maximumBytes: Int)
    case totalPathTooLarge(maximumBytes: Int)
    case byteSizeTooLarge(side: ThreePaneHexNewSide, maximumBytes: UInt64)
    case invalidDigest(ThreePaneHexNewSide)
    case invalidBytesPerRow(actual: Int)
    case emptyByteRange
    case byteRangeTooLarge(maximumBytes: UInt64)
    case invalidByteRange
    case rangeOutOfBounds(ThreePaneHexNewSide)
    case duplicateSourceRevision(first: ThreePaneHexNewSide, second: ThreePaneHexNewSide)
    case notReadOnly(ThreePaneHexNewSide)
    case unsupportedCapability
    case stringBudgetExceeded(maximumBytes: Int)
    case tooManyFindings(maximum: Int)
    case receiptMismatch
    case workLimitExceeded(maximumUnits: UInt64)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Three-pane hex new planning was cancelled."
        case .invalidLimit(let limit):
            "Invalid three-pane hex new limit: \(limit.rawValue)."
        case .invalidPaneCount(let actual):
            "Three-pane hex new requires exactly three panes, not \(actual)."
        case .duplicatePane(let side):
            "Three-pane hex new repeats the \(side.rawValue) pane."
        case .missingPane(let side):
            "Three-pane hex new is missing the \(side.rawValue) pane."
        case .invalidCanonicalURL(let side):
            "Three-pane hex new \(side.rawValue) source is not a canonical local file URL."
        case .canonicalPathMismatch(let side):
            "Three-pane hex new \(side.rawValue) canonical path does not match its URL."
        case .pathTooLarge(let side, let maximumBytes):
            "Three-pane hex new \(side.rawValue) path exceeds the \(maximumBytes)-byte limit."
        case .totalPathTooLarge(let maximumBytes):
            "Three-pane hex new paths exceed the \(maximumBytes)-byte total limit."
        case .byteSizeTooLarge(let side, let maximumBytes):
            "Three-pane hex new \(side.rawValue) file exceeds the \(maximumBytes)-byte limit."
        case .invalidDigest(let side):
            "Three-pane hex new \(side.rawValue) digest is not a 32-byte SHA-256 value."
        case .invalidBytesPerRow(let actual):
            "Three-pane hex new bytes-per-row \(actual) is outside 1 through 64."
        case .emptyByteRange:
            "Three-pane hex new byte window must not be empty."
        case .byteRangeTooLarge(let maximumBytes):
            "Three-pane hex new byte window exceeds the \(maximumBytes)-byte limit."
        case .invalidByteRange:
            "Three-pane hex new byte window offset plus length overflows."
        case .rangeOutOfBounds(let side):
            "Three-pane hex new byte window extends past the \(side.rawValue) file end."
        case .duplicateSourceRevision(let first, let second):
            "Three-pane hex new \(first.rawValue) and \(second.rawValue) panes bind the same revision."
        case .notReadOnly(let side):
            "Three-pane hex new \(side.rawValue) pane must stay read-only."
        case .unsupportedCapability:
            "Three-pane hex new capability is not supported."
        case .stringBudgetExceeded(let maximumBytes):
            "Three-pane hex new canonical encoding exceeds the \(maximumBytes)-byte string budget."
        case .tooManyFindings(let maximum):
            "Three-pane hex new exceeds the \(maximum)-finding limit."
        case .receiptMismatch:
            "Three-pane hex new receipt does not match the plan."
        case .workLimitExceeded(let maximumUnits):
            "Three-pane hex new planning exceeds the \(maximumUnits)-unit work limit."
        }
    }

    public var debugDescription: String { errorDescription ?? "Three-pane hex new planning failed." }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": "<redacted>",
                "detail": debugDescription
            ],
            displayStyle: .enum
        )
    }
}

public enum ThreePaneHexNewPlanner: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let commandID = "ID_FILE_NEW3_HEX"

    public static func plan(
        _ request: ThreePaneHexNewRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ThreePaneHexNewPlan {
        do {
            try request.limits.validate()
            var work = ThreePaneHexNewPlanningWork(limits: request.limits, cancellationCheck: cancellationCheck)
            return try work.plan(request)
        } catch is CancellationError {
            throw ThreePaneHexNewPlanningError.cancelled
        } catch let error as ThreePaneHexNewPlanningError {
            throw error
        } catch {
            throw error
        }
    }

    /// Re-validates a materialized plan against both its embedded limits and
    /// the hard maxima. Trust boundary: a plan is never trusted on receipt
    /// equality alone. This re-checks pane identity (canonical URL, path
    /// budgets, digests), duplicate revisions, and capability carry-through,
    /// so a mutated plan cannot smuggle a wider window, larger file, extra
    /// work, aliased duplicate, or unsupported capability past `plan(_:)`.
    public static func validate(_ plan: ThreePaneHexNewPlan) throws {
        do {
            try plan.limits.validate()
            guard plan.panes.count == ThreePaneHexNewSide.allCases.count else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.panes.map(\.side) == ThreePaneHexNewSide.allCases else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            for pane in plan.panes {
                guard pane.isReadOnly else {
                    throw ThreePaneHexNewPlanningError.receiptMismatch
                }
            }
            guard plan.window.length >= 1 else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.window.length <= ThreePaneHexNewLimits.hardMaximumWindowLength else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.window.length <= plan.limits.maximumWindowLength else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            let (windowEnd, windowOverflow) = plan.window.offset.addingReportingOverflow(plan.window.length)
            guard !windowOverflow else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard (ThreePaneHexNewRequest.minimumBytesPerRow...ThreePaneHexNewRequest.maximumBytesPerRow).contains(plan.bytesPerRow) else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.bytesPerRow >= 1 && plan.bytesPerRow <= plan.limits.maximumBytesPerRow else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.findings.count <= plan.limits.maximumFindings else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            var totalPathBytes = 0
            for pane in plan.panes {
                switch pane.source {
                case .empty:
                    continue
                case .file(let identity):
                    guard isCanonicalFileURL(identity.canonicalURL) else {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    guard identity.canonicalPath == identity.canonicalURL.path(percentEncoded: false) else {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    guard identity.canonicalPath.utf8.count <= plan.limits.maximumPathUTF8Bytes else {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    let pathBytes = identity.canonicalPath.utf8.count
                    let (nextTotal, totalOverflow) = totalPathBytes.addingReportingOverflow(pathBytes)
                    guard !totalOverflow, nextTotal <= plan.limits.maximumTotalPathUTF8Bytes else {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    totalPathBytes = nextTotal
                    guard identity.byteSize >= 1 && identity.byteSize <= ThreePaneHexNewLimits.hardMaximumByteSize else {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    guard identity.byteSize <= plan.limits.maximumByteSize else {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    guard identity.contentSHA256.count == 32 else {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    guard windowEnd <= identity.byteSize else {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                }
            }
            guard plan.capability.twoWay.maximumExactEditDistance >= 0,
                plan.capability.twoWay.maximumAlignmentWork >= 0,
                plan.capability.threeWay.maximumInputBytes >= 0,
                plan.capability.threeWay.maximumExactEditDistance >= 0,
                plan.capability.threeWay.maximumAlignmentWork >= 0,
                plan.capability.threeWay.maximumRegions >= 0,
                plan.capability.threeWay.maximumOutputBytes >= 0
            else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            let loadedFiles = plan.panes.compactMap { pane -> ThreePaneHexNewFileIdentity? in
                guard case .file(let identity) = pane.source else { return nil }
                return identity
            }
            for firstIndex in loadedFiles.indices {
                for secondIndex in loadedFiles.indices where secondIndex > firstIndex {
                    if loadedFiles[firstIndex].contentSHA256 == loadedFiles[secondIndex].contentSHA256 {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    if loadedFiles[firstIndex].canonicalPath == loadedFiles[secondIndex].canonicalPath {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                    if normalizedCanonicalURL(loadedFiles[firstIndex].canonicalURL) == normalizedCanonicalURL(loadedFiles[secondIndex].canonicalURL) {
                        throw ThreePaneHexNewPlanningError.receiptMismatch
                    }
                }
            }
            guard plan.receipt.sourceCount == plan.panes.filter({ !$0.isEmpty }).count else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.windowOffset == plan.window.offset else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.windowLength == plan.window.length else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.bytesPerRow == plan.bytesPerRow else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.workUnits == plan.estimatedWorkUnits else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.workUnits >= 1 && plan.receipt.workUnits <= ThreePaneHexNewLimits.hardMaximumWorkUnits else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.workUnits <= plan.limits.maximumWorkUnits else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard plan.executorContract == .required else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            let recomputed = try ThreePaneHexNewCanonicalReceipt.value(
                panes: plan.panes,
                window: plan.window,
                bytesPerRow: plan.bytesPerRow,
                capability: plan.capability,
                findings: plan.findings,
                workUnits: plan.receipt.workUnits,
                limits: plan.limits
            )
            guard recomputed.value == plan.receipt.value else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
            guard recomputed == plan.receipt else {
                throw ThreePaneHexNewPlanningError.receiptMismatch
            }
        } catch is CancellationError {
            throw ThreePaneHexNewPlanningError.cancelled
        } catch let error as ThreePaneHexNewPlanningError {
            throw error
        } catch {
            throw error
        }
    }

    /// File-URL canonicality for `validate(_:)`. Planning never touches the
    /// filesystem and does not accept or reject directory URLs here: a
    /// trailing slash still yields an absolute standardized `file` path, so
    /// directory-vs-file enforcement belongs to the executor, not the plan.
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

    /// Host-normalized URL string. Empty host and `localhost` alias to the
    /// same value so `file:///p` and `file://localhost/p` compare equal.
    /// Path comparison in `validate(_:)` covers the same alias; this keeps
    /// URL-level comparison alias-proof as well.
    fileprivate static func normalizedCanonicalURL(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        var normalized = components
        if let host = normalized.host, host.isEmpty || host.caseInsensitiveCompare("localhost") == .orderedSame {
            normalized.host = ""
        } else if let host = normalized.host {
            normalized.host = host.lowercased()
        }
        normalized.scheme = "file"
        return normalized.string ?? url.absoluteString
    }
}

private enum ThreePaneHexNewDigestHex {
    static func prefix(of digest: [UInt8]) -> String {
        var text = ""
        text.reserveCapacity(8)
        for byte in digest.prefix(4) {
            let part = String(byte, radix: 16, uppercase: false)
            if part.count < 2 {
                text += "0"
            }
            text += part
        }
        if text.isEmpty {
            return "none"
        }
        return text
    }

    static func full(of digest: [UInt8]) -> String {
        var text = ""
        text.reserveCapacity(digest.count * 2)
        for byte in digest {
            let part = String(byte, radix: 16, uppercase: false)
            if part.count < 2 {
                text += "0"
            }
            text += part
        }
        return text
    }
}

private enum ThreePaneHexNewCanonicalReceipt {
    static let domain = "three-pane-hex-new.v1"

    static func value(
        panes: [ThreePaneHexNewPane],
        window: ThreePaneHexNewByteWindow,
        bytesPerRow: Int,
        capability: ThreePaneHexNewCapabilityRequirement,
        findings: [ThreePaneHexNewFinding],
        workUnits: UInt64,
        limits: ThreePaneHexNewLimits
    ) throws -> ThreePaneHexNewReceipt {
        var fields: [(key: String, value: String)] = []
        fields.reserveCapacity(24)
        fields.append((key: "bytesPerRow", value: String(bytesPerRow)))
        fields.append((key: "capability.threeWay.alignmentWork", value: String(capability.threeWay.maximumAlignmentWork)))
        fields.append((key: "capability.threeWay.exactEditDistance", value: String(capability.threeWay.maximumExactEditDistance)))
        fields.append((key: "capability.threeWay.inputBytes", value: String(capability.threeWay.maximumInputBytes)))
        fields.append((key: "capability.threeWay.outputBytes", value: String(capability.threeWay.maximumOutputBytes)))
        fields.append((key: "capability.threeWay.regions", value: String(capability.threeWay.maximumRegions)))
        fields.append((key: "capability.twoWay.alignWork", value: String(capability.twoWay.maximumAlignmentWork)))
        fields.append((key: "capability.twoWay.editDistance", value: String(capability.twoWay.maximumExactEditDistance)))
        fields.append((key: "domain", value: domain))
        let ordered = panes.sorted { $0.side.sortOrder < $1.side.sortOrder }
        for pane in ordered {
            switch pane.source {
            case .empty:
                fields.append((key: "\(pane.side.rawValue).byteSize", value: "0"))
                fields.append((key: "\(pane.side.rawValue).digest", value: "empty"))
                fields.append((key: "\(pane.side.rawValue).path", value: "empty"))
            case .file(let identity):
                fields.append((key: "\(pane.side.rawValue).byteSize", value: String(identity.byteSize)))
                fields.append((key: "\(pane.side.rawValue).digest", value: ThreePaneHexNewDigestHex.full(of: identity.contentSHA256)))
                fields.append((key: "\(pane.side.rawValue).path", value: identity.canonicalPath))
            }
            fields.append((key: "\(pane.side.rawValue).readOnly", value: pane.isReadOnly ? "true" : "false"))
            fields.append((key: "\(pane.side.rawValue).side", value: pane.side.rawValue))
        }
        let findingValue = findings.map(\.rawValue).sorted().joined(separator: ",")
        fields.append((key: "findings", value: findingValue))
        fields.append((key: "length", value: String(window.length)))
        fields.append((key: "offset", value: String(window.offset)))
        fields.append((key: "sourceCount", value: String(ordered.filter({ !$0.isEmpty }).count)))
        fields.append((key: "workUnits", value: String(workUnits)))
        fields.sort { $0.key < $1.key }
        var totalBytes: UInt64 = 0
        for field in fields {
            let keyCount = UInt64(field.key.utf8.count)
            let valueCount = UInt64(field.value.utf8.count)
            let (afterKey, keyOverflow) = totalBytes.addingReportingOverflow(keyCount)
            guard !keyOverflow else {
                throw ThreePaneHexNewPlanningError.stringBudgetExceeded(maximumBytes: limits.maximumStringBytes)
            }
            totalBytes = afterKey
            let (afterValue, valueOverflow) = totalBytes.addingReportingOverflow(valueCount)
            guard !valueOverflow else {
                throw ThreePaneHexNewPlanningError.stringBudgetExceeded(maximumBytes: limits.maximumStringBytes)
            }
            totalBytes = afterValue
            let (afterFraming, framingOverflow) = totalBytes.addingReportingOverflow(16)
            guard !framingOverflow else {
                throw ThreePaneHexNewPlanningError.stringBudgetExceeded(maximumBytes: limits.maximumStringBytes)
            }
            totalBytes = afterFraming
        }
        guard totalBytes <= UInt64(limits.maximumStringBytes) else {
            throw ThreePaneHexNewPlanningError.stringBudgetExceeded(maximumBytes: limits.maximumStringBytes)
        }
        var hasher = SHA256()
        for field in fields {
            appendLengthFramed(key: field.key, value: field.value, hasher: &hasher)
        }
        let digest = Array(hasher.finalize())
        let hex = ThreePaneHexNewDigestHex.full(of: digest)
        let sourceCount = ordered.filter({ !$0.isEmpty }).count
        return ThreePaneHexNewReceipt(
            value: hex,
            sourceCount: sourceCount,
            windowOffset: window.offset,
            windowLength: window.length,
            bytesPerRow: bytesPerRow,
            workUnits: workUnits
        )
    }

    private static func appendLengthFramed(key: String, value: String, hasher: inout SHA256) {
        var keyLength = UInt64(key.utf8.count).bigEndian
        withUnsafeBytes(of: &keyLength) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(key.utf8))
        var valueLength = UInt64(value.utf8.count).bigEndian
        withUnsafeBytes(of: &valueLength) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(value.utf8))
    }
}

private struct ThreePaneHexNewPlanningWork {
    let limits: ThreePaneHexNewLimits
    let cancellationCheck: ThreePaneHexNewPlanner.CancellationCheck
    var completed: UInt64 = 0

    mutating func plan(_ request: ThreePaneHexNewRequest) throws -> ThreePaneHexNewPlan {
        try checkCancellation()
        try limits.validate()
        guard limits.maximumSources == ThreePaneHexNewSide.allCases.count else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.sources)
        }
        guard (ThreePaneHexNewRequest.minimumBytesPerRow...ThreePaneHexNewRequest.maximumBytesPerRow).contains(request.bytesPerRow) else {
            throw ThreePaneHexNewPlanningError.invalidBytesPerRow(actual: request.bytesPerRow)
        }
        guard request.bytesPerRow >= 1 && request.bytesPerRow <= limits.maximumBytesPerRow else {
            throw ThreePaneHexNewPlanningError.invalidBytesPerRow(actual: request.bytesPerRow)
        }
        try validateWindowLength(request.window)
        try validatePathBudgets(request)
        try validateCapability(request.capability)
        guard request.panes.count == ThreePaneHexNewSide.allCases.count else {
            throw ThreePaneHexNewPlanningError.invalidPaneCount(actual: request.panes.count)
        }
        try consume()
        try consume()
        try consume()
        var bySide: [ThreePaneHexNewSide: ThreePaneHexNewPane] = [:]
        bySide.reserveCapacity(request.panes.count)
        for pane in request.panes {
            try consume()
            guard bySide.updateValue(pane, forKey: pane.side) == nil else {
                throw ThreePaneHexNewPlanningError.duplicatePane(pane.side)
            }
            try validate(pane)
        }
        for side in ThreePaneHexNewSide.allCases where bySide[side] == nil {
            throw ThreePaneHexNewPlanningError.missingPane(side)
        }
        try validateWindowFits(request.window, panes: bySide)
        try validateDistinctRevisions(bySide)
        try checkCancellation()
        let ordered = ThreePaneHexNewSide.allCases.map { bySide[$0] ?? ThreePaneHexNewPane(side: $0, source: .empty) }
        let findings = try makeFindings(window: request.window, panes: ordered)
        try consume()
        let receipt = try ThreePaneHexNewCanonicalReceipt.value(
            panes: ordered,
            window: request.window,
            bytesPerRow: request.bytesPerRow,
            capability: request.capability,
            findings: findings,
            workUnits: completed,
            limits: limits
        )
        return ThreePaneHexNewPlan(
            panes: ordered,
            window: request.window,
            bytesPerRow: request.bytesPerRow,
            capability: request.capability,
            findings: findings,
            receipt: receipt,
            limits: limits,
            estimatedWorkUnits: completed
        )
    }

    mutating func validate(_ pane: ThreePaneHexNewPane) throws {
        guard pane.isReadOnly else {
            throw ThreePaneHexNewPlanningError.notReadOnly(pane.side)
        }
        switch pane.source {
        case .empty:
            try consume()
        case .file(let identity):
            // Identity first, metering second: invalid identities fail before
            // burning work units on the per-pane charge below.
            try validate(identity, side: pane.side)
            try consume()
        }
    }

    mutating func validate(_ identity: ThreePaneHexNewFileIdentity, side: ThreePaneHexNewSide) throws {
        guard isCanonicalFileURL(identity.canonicalURL) else {
            throw ThreePaneHexNewPlanningError.invalidCanonicalURL(side)
        }
        guard identity.canonicalPath == identity.canonicalURL.path(percentEncoded: false) else {
            throw ThreePaneHexNewPlanningError.canonicalPathMismatch(side)
        }
        guard identity.canonicalPath.utf8.count <= limits.maximumPathUTF8Bytes else {
            throw ThreePaneHexNewPlanningError.pathTooLarge(side: side, maximumBytes: limits.maximumPathUTF8Bytes)
        }
        guard identity.byteSize >= 1 && identity.byteSize <= limits.maximumByteSize else {
            throw ThreePaneHexNewPlanningError.byteSizeTooLarge(side: side, maximumBytes: limits.maximumByteSize)
        }
        guard identity.contentSHA256.count == 32 else {
            throw ThreePaneHexNewPlanningError.invalidDigest(side)
        }
        try consume()
    }

    func validateWindowLength(_ window: ThreePaneHexNewByteWindow) throws {
        guard window.length >= 1 else {
            throw ThreePaneHexNewPlanningError.emptyByteRange
        }
        guard window.length <= limits.maximumWindowLength else {
            throw ThreePaneHexNewPlanningError.byteRangeTooLarge(maximumBytes: limits.maximumWindowLength)
        }
        let (_, overflow) = window.offset.addingReportingOverflow(window.length)
        guard !overflow else {
            throw ThreePaneHexNewPlanningError.invalidByteRange
        }
    }

    func validatePathBudgets(_ request: ThreePaneHexNewRequest) throws {
        var total = 0
        for pane in request.panes {
            guard case .file(let identity) = pane.source else { continue }
            let pathBytes = identity.canonicalPath.utf8.count
            guard pathBytes <= limits.maximumPathUTF8Bytes else {
                throw ThreePaneHexNewPlanningError.pathTooLarge(side: pane.side, maximumBytes: limits.maximumPathUTF8Bytes)
            }
            let (next, overflow) = total.addingReportingOverflow(pathBytes)
            guard !overflow, next <= limits.maximumTotalPathUTF8Bytes else {
                throw ThreePaneHexNewPlanningError.totalPathTooLarge(maximumBytes: limits.maximumTotalPathUTF8Bytes)
            }
            total = next
        }
    }

    mutating func validateCapability(_ capability: ThreePaneHexNewCapabilityRequirement) throws {
        guard capability.twoWay.maximumExactEditDistance >= 0,
            capability.twoWay.maximumAlignmentWork >= 0
        else {
            throw ThreePaneHexNewPlanningError.unsupportedCapability
        }
        guard capability.threeWay.maximumInputBytes >= 0,
            capability.threeWay.maximumExactEditDistance >= 0,
            capability.threeWay.maximumAlignmentWork >= 0,
            capability.threeWay.maximumRegions >= 0,
            capability.threeWay.maximumOutputBytes >= 0
        else {
            throw ThreePaneHexNewPlanningError.unsupportedCapability
        }
        try consume()
    }

    mutating func validateWindowFits(_ window: ThreePaneHexNewByteWindow, panes: [ThreePaneHexNewSide: ThreePaneHexNewPane]) throws {
        try consume()
        let (end, overflow) = window.offset.addingReportingOverflow(window.length)
        guard !overflow else {
            throw ThreePaneHexNewPlanningError.invalidByteRange
        }
        for side in ThreePaneHexNewSide.allCases {
            try consume()
            guard case .file(let identity) = panes[side]?.source else { continue }
            guard end <= identity.byteSize else {
                throw ThreePaneHexNewPlanningError.rangeOutOfBounds(side)
            }
        }
    }

    mutating func validateDistinctRevisions(_ panes: [ThreePaneHexNewSide: ThreePaneHexNewPane]) throws {
        let loaded = ThreePaneHexNewSide.allCases.compactMap { side -> (ThreePaneHexNewSide, ThreePaneHexNewFileIdentity)? in
            guard case .file(let identity) = panes[side]?.source else { return nil }
            return (side, identity)
        }
        for firstIndex in loaded.indices {
            for secondIndex in loaded.indices where secondIndex > firstIndex {
                try consume()
                try checkCancellation()
                let first = loaded[firstIndex]
                let second = loaded[secondIndex]
                if first.1.contentSHA256 == second.1.contentSHA256 {
                    throw ThreePaneHexNewPlanningError.duplicateSourceRevision(first: first.0, second: second.0)
                }
                // Host-independent: empty host and `localhost` alias the same
                // file, and raw `canonicalURL ==` evades that alias. Compare
                // `canonicalPath` (host-independent) plus a host-normalized
                // URL so `file:///p` and `file://localhost/p` still collide.
                if first.1.canonicalPath == second.1.canonicalPath {
                    throw ThreePaneHexNewPlanningError.duplicateSourceRevision(first: first.0, second: second.0)
                }
                if ThreePaneHexNewPlanner.normalizedCanonicalURL(first.1.canonicalURL) == ThreePaneHexNewPlanner.normalizedCanonicalURL(second.1.canonicalURL) {
                    throw ThreePaneHexNewPlanningError.duplicateSourceRevision(first: first.0, second: second.0)
                }
            }
        }
    }

    mutating func makeFindings(window: ThreePaneHexNewByteWindow, panes: [ThreePaneHexNewPane]) throws -> [ThreePaneHexNewFinding] {
        var findings: [ThreePaneHexNewFinding] = []
        findings.reserveCapacity(panes.count)
        for pane in panes {
            try consume()
            try checkCancellation()
            switch pane.source {
            case .empty:
                findings.append(.windowedView)
            case .file(let identity):
                if window.offset == 0 && window.length == identity.byteSize {
                    findings.append(.fullCoverage)
                } else {
                    findings.append(.windowedView)
                }
            }
            guard findings.count <= limits.maximumFindings else {
                throw ThreePaneHexNewPlanningError.tooManyFindings(maximum: limits.maximumFindings)
            }
        }
        guard findings.count <= limits.maximumFindings else {
            throw ThreePaneHexNewPlanningError.tooManyFindings(maximum: limits.maximumFindings)
        }
        let findingBytes = UInt64(findings.count) &+ 16
        guard findingBytes <= limits.maximumWorkUnits else {
            throw ThreePaneHexNewPlanningError.workLimitExceeded(maximumUnits: limits.maximumWorkUnits)
        }
        return findings
    }

    /// Canonical file-URL check. Directory URLs are accepted here on purpose:
    /// planning never touches the filesystem, so a trailing-slash directory
    /// path still satisfies the absolute standardized `file`-scheme shape and
    /// directory-vs-file enforcement belongs to the executor, not the plan.
    func isCanonicalFileURL(_ url: URL) -> Bool {
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

    mutating func consume(_ amount: UInt64 = 1) throws {
        guard limits.cancellationCheckInterval >= 1 else {
            throw ThreePaneHexNewPlanningError.invalidLimit(.cancellationCheckInterval)
        }
        let (next, overflow) = completed.addingReportingOverflow(amount)
        guard !overflow, next <= limits.maximumWorkUnits else {
            try checkCancellation()
            throw ThreePaneHexNewPlanningError.workLimitExceeded(maximumUnits: limits.maximumWorkUnits)
        }
        let interval = UInt64(limits.cancellationCheckInterval)
        let previousBucket = completed / interval
        completed = next
        if completed / interval != previousBucket {
            try checkCancellation()
        }
    }

    func checkCancellation() throws {
        do {
            try cancellationCheck()
        } catch is CancellationError {
            throw ThreePaneHexNewPlanningError.cancelled
        }
    }
}
