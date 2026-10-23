import CryptoKit
import Foundation

/// Bounded UI-independent two-pane binary/hex new comparison core.
///
/// Groundwork for `ID_FILE_NEW_HEX`. Planning only: never reads files,
/// creates documents, opens pickers, touches the filesystem, performs
/// hex-view rendering, or mutates bytes. A document host must materialize
/// the bound sources and provide all UI. Comparison semantics defer to
/// `BinaryComparison` / `BinaryComparisonOptions` and
/// `ThreeWayBinaryComparison` / `ThreeWayBinaryComparisonOptions`.
/// This file redeclares none of those cores.
public enum TwoPaneHexNewSide: String, CaseIterable, Hashable, Sendable {
    case left
    case right

    fileprivate var sortOrder: Int {
        switch self {
        case .left: 0
        case .right: 1
        }
    }
}

public enum TwoPaneHexNewLimit: String, CaseIterable, Hashable, Sendable {
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

public struct TwoPaneHexNewLimits: Equatable, Sendable {
    public static let hardMaximumSources = 2
    public static let hardMaximumPathUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 512 * 1_024
    public static let hardMaximumByteSize: UInt64 = 64 * 1_024 * 1_024
    public static let hardMaximumWindowLength: UInt64 = 64 * 1_024 * 1_024
    public static let hardMaximumBytesPerRow = 64
    public static let hardMaximumStringBytes = 16 * 1_024
    public static let hardMaximumFindings = 16
    public static let hardMaximumWorkUnits: UInt64 = 1_000_000
    public static let hardMaximumCancellationCheckInterval = 4_096

    public static let `default`: TwoPaneHexNewLimits = {
        try! TwoPaneHexNewLimits()
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
        maximumSources: Int = 2,
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
            throw TwoPaneHexNewPlanningError.invalidLimit(.sources)
        }
        guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.pathUTF8Bytes)
        }
        guard maximumTotalPathUTF8Bytes >= maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes <= Self.hardMaximumTotalPathUTF8Bytes,
            maximumTotalPathUTF8Bytes >= 1
        else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.totalPathUTF8Bytes)
        }
        guard maximumByteSize >= 1 && maximumByteSize <= Self.hardMaximumByteSize else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.byteSize)
        }
        guard maximumWindowLength >= 1 && maximumWindowLength <= Self.hardMaximumWindowLength else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.windowLength)
        }
        guard (1...Self.hardMaximumBytesPerRow).contains(maximumBytesPerRow) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.bytesPerRow)
        }
        guard (1...Self.hardMaximumStringBytes).contains(maximumStringBytes) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.stringBytes)
        }
        guard (1...Self.hardMaximumFindings).contains(maximumFindings) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.findings)
        }
        guard maximumWorkUnits >= 1 && maximumWorkUnits <= Self.hardMaximumWorkUnits else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.workUnits)
        }
        guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.cancellationCheckInterval)
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
            throw TwoPaneHexNewPlanningError.invalidLimit(.sources)
        }
        guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.pathUTF8Bytes)
        }
        guard maximumTotalPathUTF8Bytes >= maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes <= Self.hardMaximumTotalPathUTF8Bytes,
            maximumTotalPathUTF8Bytes >= 1
        else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.totalPathUTF8Bytes)
        }
        guard maximumByteSize >= 1 && maximumByteSize <= Self.hardMaximumByteSize else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.byteSize)
        }
        guard maximumWindowLength >= 1 && maximumWindowLength <= Self.hardMaximumWindowLength else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.windowLength)
        }
        guard (1...Self.hardMaximumBytesPerRow).contains(maximumBytesPerRow) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.bytesPerRow)
        }
        guard (1...Self.hardMaximumStringBytes).contains(maximumStringBytes) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.stringBytes)
        }
        guard (1...Self.hardMaximumFindings).contains(maximumFindings) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.findings)
        }
        guard maximumWorkUnits >= 1 && maximumWorkUnits <= Self.hardMaximumWorkUnits else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.workUnits)
        }
        guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.cancellationCheckInterval)
        }
    }
}

/// Caller-captured identity for one canonical file plus its exact revision.
///
/// Planning never resolves this URL. Executors must pin the object by its
/// SHA-256 digest rather than treating the URL as authority.
public struct TwoPaneHexNewFileIdentity: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
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
        "TwoPaneHexNewFileIdentity(bytes: \(byteSize), pathBytes: \(canonicalPath.utf8.count), digest: \(TwoPaneHexNewDigestHex.prefix(of: contentSHA256)))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "byteSize": byteSize,
                "pathByteCount": canonicalPath.utf8.count,
                "digestByteCount": contentSHA256.count,
                "digestPrefix": TwoPaneHexNewDigestHex.prefix(of: contentSHA256)
            ],
            displayStyle: .struct
        )
    }
}

public enum TwoPaneHexNewPaneSource: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case empty
    case file(TwoPaneHexNewFileIdentity)

    public var isEmpty: Bool {
        if case .empty = self { true } else { false }
    }

    public var description: String {
        switch self {
        case .empty:
            "TwoPaneHexNewPaneSource(empty)"
        case .file(let identity):
            "TwoPaneHexNewPaneSource(file bytes: \(identity.byteSize), digest: \(TwoPaneHexNewDigestHex.prefix(of: identity.contentSHA256)))"
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

public struct TwoPaneHexNewPane: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let side: TwoPaneHexNewSide
    public let source: TwoPaneHexNewPaneSource
    public let isReadOnly: Bool

    public init(side: TwoPaneHexNewSide, source: TwoPaneHexNewPaneSource, isReadOnly: Bool = true) {
        self.side = side
        self.source = source
        self.isReadOnly = isReadOnly
    }

    public var isEmpty: Bool { source.isEmpty }

    public var description: String {
        "TwoPaneHexNewPane(\(side.rawValue), empty: \(isEmpty), readOnly: \(isReadOnly))"
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

public struct TwoPaneHexNewByteWindow: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let offset: UInt64
    public let length: UInt64

    public init(offset: UInt64, length: UInt64) {
        self.offset = offset
        self.length = length
    }

    public var description: String {
        "TwoPaneHexNewByteWindow(offset: \(offset), length: \(length))"
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
public struct TwoPaneHexNewCapabilityRequirement: Equatable, Sendable {
    public let twoWay: BinaryComparisonOptions
    public let threeWay: ThreeWayBinaryComparisonOptions

    public init(twoWay: BinaryComparisonOptions = BinaryComparisonOptions(), threeWay: ThreeWayBinaryComparisonOptions = .default) {
        self.twoWay = twoWay
        self.threeWay = threeWay
    }
}

public struct TwoPaneHexNewRequest: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let minimumBytesPerRow = 1
    public static let maximumBytesPerRow = 64
    public static let defaultBytesPerRow = 16

    public let panes: [TwoPaneHexNewPane]
    public let window: TwoPaneHexNewByteWindow
    public let bytesPerRow: Int
    public let capability: TwoPaneHexNewCapabilityRequirement
    public let limits: TwoPaneHexNewLimits

    public init(
        panes: [TwoPaneHexNewPane],
        window: TwoPaneHexNewByteWindow,
        bytesPerRow: Int = 16,
        capability: TwoPaneHexNewCapabilityRequirement = TwoPaneHexNewCapabilityRequirement(),
        limits: TwoPaneHexNewLimits = .default
    ) {
        self.panes = panes
        self.window = window
        self.bytesPerRow = bytesPerRow
        self.capability = capability
        self.limits = limits
    }

    public init(
        left: TwoPaneHexNewPaneSource,
        right: TwoPaneHexNewPaneSource,
        window: TwoPaneHexNewByteWindow,
        bytesPerRow: Int = 16,
        capability: TwoPaneHexNewCapabilityRequirement = TwoPaneHexNewCapabilityRequirement(),
        limits: TwoPaneHexNewLimits = .default,
        isReadOnly: Bool = true
    ) {
        self.init(
            panes: [
                TwoPaneHexNewPane(side: .left, source: left, isReadOnly: isReadOnly),
                TwoPaneHexNewPane(side: .right, source: right, isReadOnly: isReadOnly)
            ],
            window: window,
            bytesPerRow: bytesPerRow,
            capability: capability,
            limits: limits
        )
    }

    public var description: String {
        "TwoPaneHexNewRequest(panes: \(panes.count), offset: \(window.offset), length: \(window.length), bytesPerRow: \(bytesPerRow))"
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

public enum TwoPaneHexNewSourceRevisionContract: String, Hashable, Sendable {
    case exactDigestPinnedThroughExecution
}

public enum TwoPaneHexNewRangeContract: String, Hashable, Sendable {
    case windowedReadOnlyNoMutation
}

public enum TwoPaneHexNewIOContract: String, Hashable, Sendable {
    case planOnlyNoFileSystemAccess
}

public enum TwoPaneHexNewCancellationContract: String, Hashable, Sendable {
    case cancellableDuringPlanningOnly
}

public struct TwoPaneHexNewExecutorContract: Equatable, Sendable {
    public static let required = TwoPaneHexNewExecutorContract()

    public let sourceRevision = TwoPaneHexNewSourceRevisionContract.exactDigestPinnedThroughExecution
    public let range = TwoPaneHexNewRangeContract.windowedReadOnlyNoMutation
    public let fileSystem = TwoPaneHexNewIOContract.planOnlyNoFileSystemAccess
    public let cancellation = TwoPaneHexNewCancellationContract.cancellableDuringPlanningOnly
    public let readOnly = true

    public init() {}
}

public enum TwoPaneHexNewFinding: String, CaseIterable, Hashable, Sendable {
    case fullCoverage
    case windowedView
}

public struct TwoPaneHexNewReceipt: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
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
        "TwoPaneHexNewReceipt(\(value), sources: \(sourceCount), offset: \(windowOffset), length: \(windowLength), bytesPerRow: \(bytesPerRow), work: \(workUnits))"
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

public struct TwoPaneHexNewPlan: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let panes: [TwoPaneHexNewPane]
    public let window: TwoPaneHexNewByteWindow
    public let bytesPerRow: Int
    public let capability: TwoPaneHexNewCapabilityRequirement
    public let findings: [TwoPaneHexNewFinding]
    public let receipt: TwoPaneHexNewReceipt
    public let executorContract: TwoPaneHexNewExecutorContract
    public let limits: TwoPaneHexNewLimits
    public let estimatedWorkUnits: UInt64

    fileprivate init(
        panes: [TwoPaneHexNewPane],
        window: TwoPaneHexNewByteWindow,
        bytesPerRow: Int,
        capability: TwoPaneHexNewCapabilityRequirement,
        findings: [TwoPaneHexNewFinding],
        receipt: TwoPaneHexNewReceipt,
        limits: TwoPaneHexNewLimits,
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

    public func requireReceipt(_ receipt: TwoPaneHexNewReceipt) throws {
        guard receipt == self.receipt else {
            throw TwoPaneHexNewPlanningError.receiptMismatch
        }
    }

    public var description: String {
        "TwoPaneHexNewPlan(panes: \(panes.count), findings: \(findings.count), length: \(window.length), bytesPerRow: \(bytesPerRow), receipt: \(receipt.value))"
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

public enum TwoPaneHexNewPlanningError: Error, LocalizedError, Equatable, Sendable, CustomDebugStringConvertible, CustomReflectable {
    case cancelled
    case invalidLimit(TwoPaneHexNewLimit)
    case invalidPaneCount(actual: Int)
    case duplicatePane(TwoPaneHexNewSide)
    case missingPane(TwoPaneHexNewSide)
    case invalidCanonicalURL(TwoPaneHexNewSide)
    case canonicalPathMismatch(TwoPaneHexNewSide)
    case pathTooLarge(side: TwoPaneHexNewSide, maximumBytes: Int)
    case totalPathTooLarge(maximumBytes: Int)
    case byteSizeTooLarge(side: TwoPaneHexNewSide, maximumBytes: UInt64)
    case invalidDigest(TwoPaneHexNewSide)
    case invalidBytesPerRow(actual: Int)
    case emptyByteRange
    case byteRangeTooLarge(maximumBytes: UInt64)
    case invalidByteRange
    case rangeOutOfBounds(TwoPaneHexNewSide)
    case duplicateSourceRevision(first: TwoPaneHexNewSide, second: TwoPaneHexNewSide)
    case notReadOnly(TwoPaneHexNewSide)
    case unsupportedCapability
    case stringBudgetExceeded(maximumBytes: Int)
    case tooManyFindings(maximum: Int)
    case receiptMismatch
    case workLimitExceeded(maximumUnits: UInt64)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Two-pane hex new planning was cancelled."
        case .invalidLimit(let limit):
            "Invalid two-pane hex new limit: \(limit.rawValue)."
        case .invalidPaneCount(let actual):
            "Two-pane hex new requires exactly two panes, not \(actual)."
        case .duplicatePane(let side):
            "Two-pane hex new repeats the \(side.rawValue) pane."
        case .missingPane(let side):
            "Two-pane hex new is missing the \(side.rawValue) pane."
        case .invalidCanonicalURL(let side):
            "Two-pane hex new \(side.rawValue) source is not a canonical local file URL."
        case .canonicalPathMismatch(let side):
            "Two-pane hex new \(side.rawValue) canonical path does not match its URL."
        case .pathTooLarge(let side, let maximumBytes):
            "Two-pane hex new \(side.rawValue) path exceeds the \(maximumBytes)-byte limit."
        case .totalPathTooLarge(let maximumBytes):
            "Two-pane hex new paths exceed the \(maximumBytes)-byte total limit."
        case .byteSizeTooLarge(let side, let maximumBytes):
            "Two-pane hex new \(side.rawValue) file exceeds the \(maximumBytes)-byte limit."
        case .invalidDigest(let side):
            "Two-pane hex new \(side.rawValue) digest is not a 32-byte SHA-256 value."
        case .invalidBytesPerRow(let actual):
            "Two-pane hex new bytes-per-row \(actual) is outside 1 through 64."
        case .emptyByteRange:
            "Two-pane hex new byte window must not be empty."
        case .byteRangeTooLarge(let maximumBytes):
            "Two-pane hex new byte window exceeds the \(maximumBytes)-byte limit."
        case .invalidByteRange:
            "Two-pane hex new byte window offset plus length overflows."
        case .rangeOutOfBounds(let side):
            "Two-pane hex new byte window extends past the \(side.rawValue) file end."
        case .duplicateSourceRevision(let first, let second):
            "Two-pane hex new \(first.rawValue) and \(second.rawValue) panes bind the same revision."
        case .notReadOnly(let side):
            "Two-pane hex new \(side.rawValue) pane must stay read-only."
        case .unsupportedCapability:
            "Two-pane hex new capability is not supported."
        case .stringBudgetExceeded(let maximumBytes):
            "Two-pane hex new canonical encoding exceeds the \(maximumBytes)-byte string budget."
        case .tooManyFindings(let maximum):
            "Two-pane hex new exceeds the \(maximum)-finding limit."
        case .receiptMismatch:
            "Two-pane hex new receipt does not match the plan."
        case .workLimitExceeded(let maximumUnits):
            "Two-pane hex new planning exceeds the \(maximumUnits)-unit work limit."
        }
    }

    public var debugDescription: String { errorDescription ?? "Two-pane hex new planning failed." }

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

public enum TwoPaneHexNewPlanner: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let commandID = "ID_FILE_NEW_HEX"

    public static func plan(
        _ request: TwoPaneHexNewRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> TwoPaneHexNewPlan {
        do {
            try request.limits.validate()
            var work = TwoPaneHexNewPlanningWork(limits: request.limits, cancellationCheck: cancellationCheck)
            return try work.plan(request)
        } catch is CancellationError {
            throw TwoPaneHexNewPlanningError.cancelled
        } catch let error as TwoPaneHexNewPlanningError {
            throw error
        } catch {
            throw error
        }
    }

    /// Structural recheck of a materialized plan. Takes no `cancellationCheck`
    /// because it performs no metering, no suspension points, and no
    /// filesystem access: every guard is a constant-time comparison over
    /// already-materialized values. The `CancellationError` catch below only
    /// maps stray task cancellation raised around this call to `.cancelled`
    /// for consistency with `plan`; it never invokes a per-step callback.
    ///
    /// Limits are execution bounds, not hashed content. The receipt binds
    /// panes, window, bytesPerRow, capability, findings, and workUnits;
    /// `limits` ride alongside on the plan and are enforced here via
    /// `limits.validate()` plus explicit `<= limits.*` guards. Receipt
    /// equality alone does not prove equal limits: compare `plan.limits`
    /// explicitly when the bound matters.
    public static func validate(_ plan: TwoPaneHexNewPlan) throws {
        do {
            try plan.limits.validate()
            guard plan.limits.maximumSources == TwoPaneHexNewSide.allCases.count else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.capability.twoWay.maximumExactEditDistance >= 0,
                plan.capability.twoWay.maximumAlignmentWork >= 0
            else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.capability.threeWay.maximumInputBytes >= 0,
                plan.capability.threeWay.maximumExactEditDistance >= 0,
                plan.capability.threeWay.maximumAlignmentWork >= 0,
                plan.capability.threeWay.maximumRegions >= 0,
                plan.capability.threeWay.maximumOutputBytes >= 0
            else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.panes.count == TwoPaneHexNewSide.allCases.count else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.panes.map(\.side) == TwoPaneHexNewSide.allCases else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            for pane in plan.panes {
                guard pane.isReadOnly else {
                    throw TwoPaneHexNewPlanningError.receiptMismatch
                }
            }
            guard plan.window.length >= 1 else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.window.length <= TwoPaneHexNewLimits.hardMaximumWindowLength else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.window.length <= plan.limits.maximumWindowLength else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            let (windowEnd, windowOverflow) = plan.window.offset.addingReportingOverflow(plan.window.length)
            guard !windowOverflow else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard (TwoPaneHexNewRequest.minimumBytesPerRow...TwoPaneHexNewRequest.maximumBytesPerRow).contains(plan.bytesPerRow) else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.bytesPerRow >= 1 && plan.bytesPerRow <= plan.limits.maximumBytesPerRow else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.findings.count <= plan.limits.maximumFindings else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            var totalPathBytes = 0
            for pane in plan.panes {
                switch pane.source {
                case .empty:
                    continue
                case .file(let identity):
                    guard isCanonicalFileURL(identity.canonicalURL) else {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                    guard identity.canonicalPath == identity.canonicalURL.path(percentEncoded: false) else {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                    guard identity.canonicalPath.utf8.count <= plan.limits.maximumPathUTF8Bytes else {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                    let (nextTotal, totalOverflow) = totalPathBytes.addingReportingOverflow(identity.canonicalPath.utf8.count)
                    guard !totalOverflow, nextTotal <= plan.limits.maximumTotalPathUTF8Bytes else {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                    totalPathBytes = nextTotal
                    guard identity.byteSize >= 1 && identity.byteSize <= TwoPaneHexNewLimits.hardMaximumByteSize else {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                    guard identity.byteSize >= 1 && identity.byteSize <= plan.limits.maximumByteSize else {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                    guard identity.contentSHA256.count == 32 else {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                    guard windowEnd <= identity.byteSize else {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                }
            }
            let loaded = plan.panes.compactMap { pane -> (TwoPaneHexNewSide, TwoPaneHexNewFileIdentity)? in
                guard case .file(let identity) = pane.source else { return nil }
                return (pane.side, identity)
            }
            for firstIndex in loaded.indices {
                for secondIndex in loaded.indices where secondIndex > firstIndex {
                    let first = loaded[firstIndex]
                    let second = loaded[secondIndex]
                    if first.1.contentSHA256 == second.1.contentSHA256 {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                    if first.1.canonicalURL == second.1.canonicalURL {
                        throw TwoPaneHexNewPlanningError.receiptMismatch
                    }
                }
            }
            guard plan.receipt.sourceCount == plan.panes.filter({ !$0.isEmpty }).count else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.windowOffset == plan.window.offset else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.windowLength == plan.window.length else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.bytesPerRow == plan.bytesPerRow else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.workUnits == plan.estimatedWorkUnits else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.workUnits >= 1 && plan.receipt.workUnits <= TwoPaneHexNewLimits.hardMaximumWorkUnits else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.receipt.workUnits >= 1 && plan.receipt.workUnits <= plan.limits.maximumWorkUnits else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard plan.executorContract == .required else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            let recomputed = try TwoPaneHexNewCanonicalReceipt.value(
                panes: plan.panes,
                window: plan.window,
                bytesPerRow: plan.bytesPerRow,
                capability: plan.capability,
                findings: plan.findings,
                workUnits: plan.receipt.workUnits,
                limits: plan.limits
            )
            guard recomputed.value == plan.receipt.value else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
            guard recomputed == plan.receipt else {
                throw TwoPaneHexNewPlanningError.receiptMismatch
            }
        } catch is CancellationError {
            throw TwoPaneHexNewPlanningError.cancelled
        } catch let error as TwoPaneHexNewPlanningError {
            throw error
        } catch {
            throw error
        }
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
        guard let host = components.host else { return true }
        return host.isEmpty || host.caseInsensitiveCompare("localhost") == .orderedSame
    }
}

private enum TwoPaneHexNewDigestHex {
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

private enum TwoPaneHexNewCanonicalReceipt {
    static let domain = "two-pane-hex-new.v1"

    static func value(
        panes: [TwoPaneHexNewPane],
        window: TwoPaneHexNewByteWindow,
        bytesPerRow: Int,
        capability: TwoPaneHexNewCapabilityRequirement,
        findings: [TwoPaneHexNewFinding],
        workUnits: UInt64,
        limits: TwoPaneHexNewLimits
    ) throws -> TwoPaneHexNewReceipt {
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
                fields.append((key: "\(pane.side.rawValue).digest", value: TwoPaneHexNewDigestHex.full(of: identity.contentSHA256)))
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
                throw TwoPaneHexNewPlanningError.stringBudgetExceeded(maximumBytes: limits.maximumStringBytes)
            }
            totalBytes = afterKey
            let (afterValue, valueOverflow) = totalBytes.addingReportingOverflow(valueCount)
            guard !valueOverflow else {
                throw TwoPaneHexNewPlanningError.stringBudgetExceeded(maximumBytes: limits.maximumStringBytes)
            }
            totalBytes = afterValue
            let (afterFraming, framingOverflow) = totalBytes.addingReportingOverflow(16)
            guard !framingOverflow else {
                throw TwoPaneHexNewPlanningError.stringBudgetExceeded(maximumBytes: limits.maximumStringBytes)
            }
            totalBytes = afterFraming
        }
        guard totalBytes <= UInt64(limits.maximumStringBytes) else {
            throw TwoPaneHexNewPlanningError.stringBudgetExceeded(maximumBytes: limits.maximumStringBytes)
        }
        var hasher = SHA256()
        for field in fields {
            appendLengthFramed(key: field.key, value: field.value, hasher: &hasher)
        }
        let digest = Array(hasher.finalize())
        let hex = TwoPaneHexNewDigestHex.full(of: digest)
        let sourceCount = ordered.filter({ !$0.isEmpty }).count
        return TwoPaneHexNewReceipt(
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

private struct TwoPaneHexNewPlanningWork {
    let limits: TwoPaneHexNewLimits
    let cancellationCheck: TwoPaneHexNewPlanner.CancellationCheck
    var completed: UInt64 = 0

    mutating func plan(_ request: TwoPaneHexNewRequest) throws -> TwoPaneHexNewPlan {
        try checkCancellation()
        try limits.validate()
        guard limits.maximumSources == TwoPaneHexNewSide.allCases.count else {
            throw TwoPaneHexNewPlanningError.invalidLimit(.sources)
        }
        guard (TwoPaneHexNewRequest.minimumBytesPerRow...TwoPaneHexNewRequest.maximumBytesPerRow).contains(request.bytesPerRow) else {
            throw TwoPaneHexNewPlanningError.invalidBytesPerRow(actual: request.bytesPerRow)
        }
        guard request.bytesPerRow >= 1 && request.bytesPerRow <= limits.maximumBytesPerRow else {
            throw TwoPaneHexNewPlanningError.invalidBytesPerRow(actual: request.bytesPerRow)
        }
        try validateWindowLength(request.window)
        try validatePathBudgets(request)
        try validateCapability(request.capability)
        guard request.panes.count == TwoPaneHexNewSide.allCases.count else {
            throw TwoPaneHexNewPlanningError.invalidPaneCount(actual: request.panes.count)
        }
        try consume()
        try consume()
        try consume()
        var bySide: [TwoPaneHexNewSide: TwoPaneHexNewPane] = [:]
        bySide.reserveCapacity(request.panes.count)
        for pane in request.panes {
            guard bySide[pane.side] == nil else {
                throw TwoPaneHexNewPlanningError.duplicatePane(pane.side)
            }
            try consume()
            bySide[pane.side] = pane
            try validate(pane)
        }
        for side in TwoPaneHexNewSide.allCases where bySide[side] == nil {
            throw TwoPaneHexNewPlanningError.missingPane(side)
        }
        try validateWindowFits(request.window, panes: bySide)
        try validateDistinctRevisions(bySide)
        try checkCancellation()
        let ordered = TwoPaneHexNewSide.allCases.map { bySide[$0] ?? TwoPaneHexNewPane(side: $0, source: .empty) }
        let findings = try makeFindings(window: request.window, panes: ordered)
        try consume()
        let receipt = try TwoPaneHexNewCanonicalReceipt.value(
            panes: ordered,
            window: request.window,
            bytesPerRow: request.bytesPerRow,
            capability: request.capability,
            findings: findings,
            workUnits: completed,
            limits: limits
        )
        return TwoPaneHexNewPlan(
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

    mutating func validate(_ pane: TwoPaneHexNewPane) throws {
        guard pane.isReadOnly else {
            throw TwoPaneHexNewPlanningError.notReadOnly(pane.side)
        }
        switch pane.source {
        case .empty:
            try consume()
        case .file(let identity):
            try consume()
            try validate(identity, side: pane.side)
        }
    }

    mutating func validate(_ identity: TwoPaneHexNewFileIdentity, side: TwoPaneHexNewSide) throws {
        guard isCanonicalFileURL(identity.canonicalURL) else {
            throw TwoPaneHexNewPlanningError.invalidCanonicalURL(side)
        }
        guard identity.canonicalPath == identity.canonicalURL.path(percentEncoded: false) else {
            throw TwoPaneHexNewPlanningError.canonicalPathMismatch(side)
        }
        guard identity.canonicalPath.utf8.count <= limits.maximumPathUTF8Bytes else {
            throw TwoPaneHexNewPlanningError.pathTooLarge(side: side, maximumBytes: limits.maximumPathUTF8Bytes)
        }
        guard identity.byteSize >= 1 && identity.byteSize <= limits.maximumByteSize else {
            throw TwoPaneHexNewPlanningError.byteSizeTooLarge(side: side, maximumBytes: limits.maximumByteSize)
        }
        guard identity.contentSHA256.count == 32 else {
            throw TwoPaneHexNewPlanningError.invalidDigest(side)
        }
        try consume()
    }

    func validateWindowLength(_ window: TwoPaneHexNewByteWindow) throws {
        guard window.length >= 1 else {
            throw TwoPaneHexNewPlanningError.emptyByteRange
        }
        guard window.length <= limits.maximumWindowLength else {
            throw TwoPaneHexNewPlanningError.byteRangeTooLarge(maximumBytes: limits.maximumWindowLength)
        }
        let (_, overflow) = window.offset.addingReportingOverflow(window.length)
        guard !overflow else {
            throw TwoPaneHexNewPlanningError.invalidByteRange
        }
    }

    func validatePathBudgets(_ request: TwoPaneHexNewRequest) throws {
        var total = 0
        for pane in request.panes {
            guard case .file(let identity) = pane.source else { continue }
            let pathBytes = identity.canonicalPath.utf8.count
            guard pathBytes <= limits.maximumPathUTF8Bytes else {
                throw TwoPaneHexNewPlanningError.pathTooLarge(side: pane.side, maximumBytes: limits.maximumPathUTF8Bytes)
            }
            let (next, overflow) = total.addingReportingOverflow(pathBytes)
            guard !overflow, next <= limits.maximumTotalPathUTF8Bytes else {
                throw TwoPaneHexNewPlanningError.totalPathTooLarge(maximumBytes: limits.maximumTotalPathUTF8Bytes)
            }
            total = next
        }
    }

    mutating func validateCapability(_ capability: TwoPaneHexNewCapabilityRequirement) throws {
        guard capability.twoWay.maximumExactEditDistance >= 0,
            capability.twoWay.maximumAlignmentWork >= 0
        else {
            throw TwoPaneHexNewPlanningError.unsupportedCapability
        }
        guard capability.threeWay.maximumInputBytes >= 0,
            capability.threeWay.maximumExactEditDistance >= 0,
            capability.threeWay.maximumAlignmentWork >= 0,
            capability.threeWay.maximumRegions >= 0,
            capability.threeWay.maximumOutputBytes >= 0
        else {
            throw TwoPaneHexNewPlanningError.unsupportedCapability
        }
        try consume()
    }

    mutating func validateWindowFits(_ window: TwoPaneHexNewByteWindow, panes: [TwoPaneHexNewSide: TwoPaneHexNewPane]) throws {
        let (end, overflow) = window.offset.addingReportingOverflow(window.length)
        guard !overflow else {
            throw TwoPaneHexNewPlanningError.invalidByteRange
        }
        try consume()
        for side in TwoPaneHexNewSide.allCases {
            try consume()
            guard case .file(let identity) = panes[side]?.source else { continue }
            guard end <= identity.byteSize else {
                throw TwoPaneHexNewPlanningError.rangeOutOfBounds(side)
            }
        }
    }

    mutating func validateDistinctRevisions(_ panes: [TwoPaneHexNewSide: TwoPaneHexNewPane]) throws {
        let loaded = TwoPaneHexNewSide.allCases.compactMap { side -> (TwoPaneHexNewSide, TwoPaneHexNewFileIdentity)? in
            guard case .file(let identity) = panes[side]?.source else { return nil }
            return (side, identity)
        }
        for firstIndex in loaded.indices {
            for secondIndex in loaded.indices where secondIndex > firstIndex {
                let first = loaded[firstIndex]
                let second = loaded[secondIndex]
                if first.1.contentSHA256 == second.1.contentSHA256 {
                    throw TwoPaneHexNewPlanningError.duplicateSourceRevision(first: first.0, second: second.0)
                }
                if first.1.canonicalURL == second.1.canonicalURL {
                    throw TwoPaneHexNewPlanningError.duplicateSourceRevision(first: first.0, second: second.0)
                }
                try consume()
                try checkCancellation()
            }
        }
    }

    mutating func makeFindings(window: TwoPaneHexNewByteWindow, panes: [TwoPaneHexNewPane]) throws -> [TwoPaneHexNewFinding] {
        var findings: [TwoPaneHexNewFinding] = []
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
                throw TwoPaneHexNewPlanningError.tooManyFindings(maximum: limits.maximumFindings)
            }
        }
        guard findings.count <= limits.maximumFindings else {
            throw TwoPaneHexNewPlanningError.tooManyFindings(maximum: limits.maximumFindings)
        }
        let (findingBytes, findingOverflow) = UInt64(findings.count).addingReportingOverflow(16)
        guard !findingOverflow, findingBytes <= limits.maximumWorkUnits else {
            throw TwoPaneHexNewPlanningError.workLimitExceeded(maximumUnits: limits.maximumWorkUnits)
        }
        return findings
    }

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
            throw TwoPaneHexNewPlanningError.invalidLimit(.cancellationCheckInterval)
        }
        let (next, overflow) = completed.addingReportingOverflow(amount)
        guard !overflow, next <= limits.maximumWorkUnits else {
            throw TwoPaneHexNewPlanningError.workLimitExceeded(maximumUnits: limits.maximumWorkUnits)
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
            throw TwoPaneHexNewPlanningError.cancelled
        }
    }
}
