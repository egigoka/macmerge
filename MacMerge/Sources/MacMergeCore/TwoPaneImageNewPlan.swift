import CryptoKit
import Foundation

/// Bounded, UI-independent open core for two-pane image comparison (`ID_FILE_NEW_IMAGE`).
///
/// Planning performs no I/O, pixel decoding, rendering, OCR, comparison materialization,
/// publication, window creation, or AppKit work. Callers supply observed file identities
/// alongside caller-computed SHA-256 digests; the planner validates bounds, binds exact
/// revisions, and emits a deterministic receipt plus an executor contract. A document host
/// performs all loading and comparison off-plan.
public enum TwoPaneImageNewPane: String, CaseIterable, Hashable, Sendable {
    case left
    case right

    public static let requestOrder: [TwoPaneImageNewPane] = [.left, .right]

    var sortOrder: Int {
        switch self {
        case .left: 0
        case .right: 1
        }
    }
}

/// Initial presentation mode for a bound two-pane image comparison.
public enum TwoPaneImageNewDisplayMode: String, CaseIterable, Hashable, Sendable {
    case sideBySide
    case overlay
    case blink

    public static let `default`: TwoPaneImageNewDisplayMode = .sideBySide
}

/// Observed file identity for one pane. Pass `url.standardizedFileURL.path` as `canonicalPath`.
public struct TwoPaneImageNewSource: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let canonicalPath: String
    public let byteSize: Int
    public let typeIdentifier: String
    public let width: Int
    public let height: Int
    public let pixelFormat: String

    public init(
        canonicalPath: String,
        byteSize: Int,
        typeIdentifier: String,
        width: Int,
        height: Int,
        pixelFormat: String
    ) {
        self.canonicalPath = canonicalPath
        self.byteSize = byteSize
        self.typeIdentifier = typeIdentifier
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
    }

    public var pathUTF8Bytes: Int { canonicalPath.utf8.count }

    public var pixelFormatUTF8Bytes: Int { pixelFormat.utf8.count }

    public var description: String {
        "TwoPaneImageNewSource(bytes: \(byteSize), extent: \(width)x\(height), pathBytes: \(pathUTF8Bytes))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "pathUTF8Bytes": pathUTF8Bytes,
                "byteSize": byteSize,
                "width": width,
                "height": height,
                "pixelFormatUTF8Bytes": pixelFormatUTF8Bytes,
                "typeIdentifierBytes": typeIdentifier.utf8.count,
            ],
            displayStyle: .struct
        )
    }
}

/// One pane source bound to its exact SHA-256 revision digest.
public struct TwoPaneImageNewRevision: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let digestByteCount = 32

    public let source: TwoPaneImageNewSource
    public let sha256: Data

    public init(source: TwoPaneImageNewSource, sha256: Data) {
        self.source = source
        self.sha256 = sha256
    }

    public var digestHex: String { twoPaneImageNewHex(sha256) }

    public var isValidDigest: Bool {
        sha256.count == Self.digestByteCount && !sha256.allSatisfy({ $0 == 0 })
    }

    public var description: String {
        "TwoPaneImageNewRevision(digest: \(digestHex), bytes: \(source.byteSize), extent: \(source.width)x\(source.height))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "digestHex": digestHex,
                "byteSize": source.byteSize,
                "width": source.width,
                "height": source.height,
                "pixelFormatUTF8Bytes": source.pixelFormatUTF8Bytes,
            ],
            displayStyle: .struct
        )
    }
}

/// Capability requirement naming the existing image cores an executor must use.
public struct TwoPaneImageNewCapability: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = TwoPaneImageNewCapability(
        loaderName: "BoundedImageLoader",
        limitsName: "ImageComparisonLimits",
        optionsName: "ImageComparisonOptions",
        comparisonName: "ImageDifferenceEngine",
        supportedTypeIdentifiers: ImageComparisonLimits.supportedStaticTypeIdentifiers,
        supportedPaneCounts: [2]
    )

    public let loaderName: String
    public let limitsName: String
    public let optionsName: String
    public let comparisonName: String
    public let supportedTypeIdentifiers: Set<String>
    public let supportedPaneCounts: [Int]

    public init(
        loaderName: String,
        limitsName: String,
        optionsName: String,
        comparisonName: String,
        supportedTypeIdentifiers: Set<String>,
        supportedPaneCounts: [Int]
    ) {
        self.loaderName = loaderName
        self.limitsName = limitsName
        self.optionsName = optionsName
        self.comparisonName = comparisonName
        self.supportedTypeIdentifiers = supportedTypeIdentifiers
        self.supportedPaneCounts = supportedPaneCounts
    }

    public func supports(paneCount: Int) -> Bool {
        supportedPaneCounts.contains(paneCount)
    }

    public var description: String {
        "TwoPaneImageNewCapability(loader: \(loaderName), comparison: \(comparisonName), panes: \(supportedPaneCounts.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "loaderName": loaderName,
                "limitsName": limitsName,
                "optionsName": optionsName,
                "comparisonName": comparisonName,
                "supportedTypeCount": supportedTypeIdentifiers.count,
                "supportedPaneCounts": supportedPaneCounts,
            ],
            displayStyle: .struct
        )
    }
}

/// Plan-only open request. Both sides are always required.
public struct TwoPaneImageNewRequest: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let left: TwoPaneImageNewRevision
    public let right: TwoPaneImageNewRevision
    public let displayMode: TwoPaneImageNewDisplayMode
    public let comparisonOptions: ImageComparisonOptions
    public let capability: TwoPaneImageNewCapability

    public init(
        left: TwoPaneImageNewRevision,
        right: TwoPaneImageNewRevision,
        displayMode: TwoPaneImageNewDisplayMode = .default,
        comparisonOptions: ImageComparisonOptions = .default,
        capability: TwoPaneImageNewCapability = .default
    ) {
        self.left = left
        self.right = right
        self.displayMode = displayMode
        self.comparisonOptions = comparisonOptions
        self.capability = capability
    }

    public var paneCount: Int { 2 }

    var orderedRevisions: [(pane: TwoPaneImageNewPane, revision: TwoPaneImageNewRevision)] {
        [
            (pane: .left, revision: left),
            (pane: .right, revision: right),
        ]
    }

    public var description: String {
        let digests = orderedRevisions.map({ $0.revision.digestHex })
        return "TwoPaneImageNewRequest(panes: 2, mode: \(displayMode.rawValue), digests: \(digests))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "paneCount": paneCount,
                "displayMode": displayMode.rawValue,
                "digestHexes": orderedRevisions.map({ $0.revision.digestHex }),
                "loaderName": capability.loaderName,
                "comparisonName": capability.comparisonName,
            ],
            displayStyle: .struct
        )
    }
}

/// Bounded limit selector for `TwoPaneImageNewLimits`.
public enum TwoPaneImageNewLimit: String, CaseIterable, Hashable, Sendable {
    case sources
    case pathBytes
    case byteSize
    case dimension
    case pixelCount
    case pixelFormatBytes
    case workUnits
    case cancellationCheckInterval
}

/// Bounds for two-pane image-new planning. All maxima are enforced before any receipt is issued.
public struct TwoPaneImageNewLimits: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let hardMaximumSources = 2
    public static let hardMaximumPathUTF8Bytes = 32 * 1024
    public static let hardMaximumByteSize = 256 * 1024 * 1024
    public static let hardMaximumDimension = 16_384
    public static let hardMaximumPixelCount = 64 * 1024 * 1024
    public static let hardMaximumPixelFormatUTF8Bytes = 64
    public static let hardMaximumPlanningWorkUnits = 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 4_096
    public static let `default` = TwoPaneImageNewLimits()

    public let maximumSources: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumByteSize: Int
    public let maximumDimension: Int
    public let maximumPixelCount: Int
    public let maximumPixelFormatUTF8Bytes: Int
    public let maximumPlanningWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumSources: Int = TwoPaneImageNewLimits.hardMaximumSources,
        maximumPathUTF8Bytes: Int = 4_096,
        maximumByteSize: Int = 64 * 1024 * 1024,
        maximumDimension: Int = TwoPaneImageNewLimits.hardMaximumDimension,
        maximumPixelCount: Int = 16 * 1024 * 1024,
        maximumPixelFormatUTF8Bytes: Int = 64,
        maximumPlanningWorkUnits: Int = 4_096,
        cancellationCheckInterval: Int = 64
    ) {
        self.maximumSources = maximumSources
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumByteSize = maximumByteSize
        self.maximumDimension = maximumDimension
        self.maximumPixelCount = maximumPixelCount
        self.maximumPixelFormatUTF8Bytes = maximumPixelFormatUTF8Bytes
        self.maximumPlanningWorkUnits = maximumPlanningWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }

    public func validate() throws {
        guard (1...Self.hardMaximumSources).contains(maximumSources) else {
            throw TwoPaneImageNewError.invalidLimit(.sources, value: maximumSources)
        }
        guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
            throw TwoPaneImageNewError.invalidLimit(.pathBytes, value: maximumPathUTF8Bytes)
        }
        guard (1...Self.hardMaximumByteSize).contains(maximumByteSize) else {
            throw TwoPaneImageNewError.invalidLimit(.byteSize, value: maximumByteSize)
        }
        guard (1...Self.hardMaximumDimension).contains(maximumDimension) else {
            throw TwoPaneImageNewError.invalidLimit(.dimension, value: maximumDimension)
        }
        guard (1...Self.hardMaximumPixelCount).contains(maximumPixelCount) else {
            throw TwoPaneImageNewError.invalidLimit(.pixelCount, value: maximumPixelCount)
        }
        guard (1...Self.hardMaximumPixelFormatUTF8Bytes).contains(maximumPixelFormatUTF8Bytes) else {
            throw TwoPaneImageNewError.invalidLimit(.pixelFormatBytes, value: maximumPixelFormatUTF8Bytes)
        }
        guard (1...Self.hardMaximumPlanningWorkUnits).contains(maximumPlanningWorkUnits) else {
            throw TwoPaneImageNewError.invalidLimit(.workUnits, value: maximumPlanningWorkUnits)
        }
        guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
            throw TwoPaneImageNewError.invalidLimit(.cancellationCheckInterval, value: cancellationCheckInterval)
        }
    }

    public var description: String {
        "TwoPaneImageNewLimits(sources: \(maximumSources), pathBytes: \(maximumPathUTF8Bytes),"
            + " bytes: \(maximumByteSize), pixels: \(maximumPixelCount), work: \(maximumPlanningWorkUnits))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "maximumSources": maximumSources,
                "maximumPathUTF8Bytes": maximumPathUTF8Bytes,
                "maximumByteSize": maximumByteSize,
                "maximumDimension": maximumDimension,
                "maximumPixelCount": maximumPixelCount,
                "maximumPixelFormatUTF8Bytes": maximumPixelFormatUTF8Bytes,
                "maximumPlanningWorkUnits": maximumPlanningWorkUnits,
                "cancellationCheckInterval": cancellationCheckInterval,
            ],
            displayStyle: .struct
        )
    }
}

/// Typed rejection for every two-pane image-new planning failure. Summaries carry digests and
/// counts only, never pixel bytes or full paths.
public enum TwoPaneImageNewError: Error, Equatable, LocalizedError, Sendable,
    CustomDebugStringConvertible, CustomReflectable
{
    case cancelled
    case invalidLimit(TwoPaneImageNewLimit, value: Int)
    case paneCountExceeded(requested: Int, maximum: Int)
    case unsupportedPaneCount(panes: Int)
    case emptyPath
    case pathTooLarge(maximumUTF8Bytes: Int)
    case byteSizeExceeded(maximumBytes: Int)
    case unsupportedFormat(hintBytes: Int)
    case dimensionsExceeded(width: Int, height: Int, maximum: Int)
    case pixelCountExceeded(maximumPixels: Int)
    case emptyPixelFormat
    case pixelFormatTooLarge(maximumUTF8Bytes: Int)
    case invalidDigest
    case invalidComparisonOptions
    case duplicateRevision
    case planningWorkExceeded(maximumWorkUnits: Int)
    case receiptMismatch

    public var errorDescription: String? { redactedSummary }

    public var debugDescription: String { redactedSummary }

    public var customMirror: Mirror {
        Mirror(self, children: ["summary": redactedSummary], displayStyle: .enum)
    }

    private var redactedSummary: String {
        switch self {
        case .cancelled:
            "Two-pane image-new planning was cancelled."
        case .invalidLimit(let limit, let value):
            "Invalid two-pane image-new limit \(limit.rawValue): \(value)."
        case .paneCountExceeded(let requested, let maximum):
            "A \(requested)-pane request exceeds the \(maximum)-pane limit."
        case .unsupportedPaneCount(let panes):
            "Two-pane image-new capability does not support \(panes) panes."
        case .emptyPath:
            "Two-pane image-new source path is empty."
        case .pathTooLarge(let maximum):
            "Two-pane image-new source path exceeds \(maximum) UTF-8 bytes."
        case .byteSizeExceeded(let maximum):
            "Two-pane image-new source exceeds \(maximum) bytes."
        case .unsupportedFormat(let hintBytes):
            "Two-pane image-new format (\(hintBytes) UTF-8 bytes) is not in the allowlist."
        case .dimensionsExceeded(let width, let height, let maximum):
            "Two-pane image-new extent \(width)x\(height) exceeds maximum dimension \(maximum)."
        case .pixelCountExceeded(let maximum):
            "Two-pane image-new pixel count exceeds \(maximum) pixels."
        case .emptyPixelFormat:
            "Two-pane image-new pixel format is empty."
        case .pixelFormatTooLarge(let maximum):
            "Two-pane image-new pixel format exceeds \(maximum) UTF-8 bytes."
        case .invalidDigest:
            "Two-pane image-new revision digest is not a non-zero SHA-256 value."
        case .invalidComparisonOptions:
            "Two-pane image-new comparison options are invalid."
        case .duplicateRevision:
            "Two-pane image-new panes bind the same source revision."
        case .planningWorkExceeded(let maximum):
            "Two-pane image-new planning exceeds the \(maximum)-unit work limit."
        case .receiptMismatch:
            "Two-pane image-new receipt does not match the plan."
        }
    }
}

/// Deterministic receipt binding the exact revisions a plan was issued for.
public struct TwoPaneImageNewReceipt: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public var description: String { "TwoPaneImageNewReceipt(\(value))" }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["value": value], displayStyle: .struct)
    }
}

/// Plan-only executor contract. Data only; the executor performs all I/O and comparison off-plan.
public struct TwoPaneImageNewExecutorContract: Equatable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let receiptValue: String
    public let expectedPaneCount: Int
    public let loaderName: String
    public let comparisonName: String
    public let steps: [String]

    public init(
        receiptValue: String,
        expectedPaneCount: Int,
        loaderName: String,
        comparisonName: String,
        steps: [String]
    ) {
        self.receiptValue = receiptValue
        self.expectedPaneCount = expectedPaneCount
        self.loaderName = loaderName
        self.comparisonName = comparisonName
        self.steps = steps
    }

    public var description: String {
        "TwoPaneImageNewExecutorContract(panes: \(expectedPaneCount), loader: \(loaderName), comparison: \(comparisonName), steps: \(steps.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "receiptValue": receiptValue,
                "expectedPaneCount": expectedPaneCount,
                "loaderName": loaderName,
                "comparisonName": comparisonName,
                "stepCount": steps.count,
            ],
            displayStyle: .struct
        )
    }
}

/// One validated pane with its exact bound revision.
public struct TwoPaneImageNewPlannedPane: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let pane: TwoPaneImageNewPane
    public let revision: TwoPaneImageNewRevision

    public init(pane: TwoPaneImageNewPane, revision: TwoPaneImageNewRevision) {
        self.pane = pane
        self.revision = revision
    }

    public var description: String {
        "TwoPaneImageNewPlannedPane(pane: \(pane.rawValue), digest: \(revision.digestHex))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "pane": pane.rawValue,
                "digestHex": revision.digestHex,
                "byteSize": revision.source.byteSize,
            ],
            displayStyle: .struct
        )
    }
}

/// Validated two-pane image-new plan with deterministic receipt and executor contract.
public struct TwoPaneImageNewPlan: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let panes: [TwoPaneImageNewPlannedPane]
    public let displayMode: TwoPaneImageNewDisplayMode
    public let comparisonOptions: ImageComparisonOptions
    public let capability: TwoPaneImageNewCapability
    public let limits: TwoPaneImageNewLimits
    public let receipt: TwoPaneImageNewReceipt
    public let executorContract: TwoPaneImageNewExecutorContract
    public let workPerformed: Int

    public var paneCount: Int { panes.count }

    public var description: String {
        "TwoPaneImageNewPlan(panes: \(paneCount), mode: \(displayMode.rawValue), receipt: \(receipt.value), work: \(workPerformed))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "paneCount": paneCount,
                "displayMode": displayMode.rawValue,
                "receiptValue": receipt.value,
                "expectedPaneCount": executorContract.expectedPaneCount,
                "workPerformed": workPerformed,
            ],
            displayStyle: .struct
        )
    }

    public func requireReceipt(_ receipt: TwoPaneImageNewReceipt) throws {
        guard receipt == self.receipt else {
            throw TwoPaneImageNewError.receiptMismatch
        }
    }

    public init(
        panes: [TwoPaneImageNewPlannedPane],
        displayMode: TwoPaneImageNewDisplayMode,
        comparisonOptions: ImageComparisonOptions,
        capability: TwoPaneImageNewCapability,
        limits: TwoPaneImageNewLimits,
        receipt: TwoPaneImageNewReceipt,
        executorContract: TwoPaneImageNewExecutorContract,
        workPerformed: Int
    ) {
        self.panes = panes
        self.displayMode = displayMode
        self.comparisonOptions = comparisonOptions
        self.capability = capability
        self.limits = limits
        self.receipt = receipt
        self.executorContract = executorContract
        self.workPerformed = workPerformed
    }

    fileprivate static func issued(
        panes: [TwoPaneImageNewPlannedPane],
        displayMode: TwoPaneImageNewDisplayMode,
        comparisonOptions: ImageComparisonOptions,
        capability: TwoPaneImageNewCapability,
        limits: TwoPaneImageNewLimits,
        receipt: TwoPaneImageNewReceipt,
        executorContract: TwoPaneImageNewExecutorContract,
        workPerformed: Int
    ) -> TwoPaneImageNewPlan {
        TwoPaneImageNewPlan(
            panes: panes,
            displayMode: displayMode,
            comparisonOptions: comparisonOptions,
            capability: capability,
            limits: limits,
            receipt: receipt,
            executorContract: executorContract,
            workPerformed: workPerformed
        )
    }
}

/// Plan-only planner. Validates bounds and distinct revisions, then binds exact revisions
/// and emits the plan. Never performs I/O, decoding, rendering, or OCR.
public enum TwoPaneImageNewPlanner: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let commandID = "ID_FILE_NEW_IMAGE"

    public static func plan(
        _ request: TwoPaneImageNewRequest,
        limits: TwoPaneImageNewLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> TwoPaneImageNewPlan {
        do {
            try limits.validate()
            var work = TwoPaneImageNewPlanningWork(
                maximum: limits.maximumPlanningWorkUnits,
                cancellationCheckInterval: limits.cancellationCheckInterval,
                cancellationCheck: cancellationCheck
            )
            try work.checkCancellation()

            let paneCount = request.paneCount
            guard limits.maximumSources == TwoPaneImageNewLimits.hardMaximumSources else {
                throw TwoPaneImageNewError.invalidLimit(.sources, value: limits.maximumSources)
            }
            guard paneCount <= limits.maximumSources else {
                throw TwoPaneImageNewError.paneCountExceeded(requested: paneCount, maximum: limits.maximumSources)
            }
            guard request.capability.supports(paneCount: paneCount) else {
                throw TwoPaneImageNewError.unsupportedPaneCount(panes: paneCount)
            }
            guard !request.capability.loaderName.isEmpty,
                !request.capability.limitsName.isEmpty,
                !request.capability.optionsName.isEmpty,
                !request.capability.comparisonName.isEmpty,
                !request.capability.supportedTypeIdentifiers.isEmpty
            else {
                // Receipt must bind the full capability; empty names cannot be bound safely.
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard request.comparisonOptions.maximumCanvasPixels >= 1,
                request.comparisonOptions.maximumRegions >= 1,
                request.comparisonOptions.maximumQueuedPixels >= 1
            else {
                throw TwoPaneImageNewError.invalidComparisonOptions
            }
            try work.consume()

            var planned: [TwoPaneImageNewPlannedPane] = []
            planned.reserveCapacity(paneCount)
            for entry in request.orderedRevisions {
                try validateRevision(entry.revision, limits: limits, capability: request.capability, work: &work)
                planned.append(TwoPaneImageNewPlannedPane(pane: entry.pane, revision: entry.revision))
            }
            planned.sort { $0.pane.sortOrder < $1.pane.sortOrder }

            let digests = planned.map({ $0.revision.sha256 })
            guard Set(digests).count == digests.count else {
                throw TwoPaneImageNewError.duplicateRevision
            }
            try work.consume()

            try work.checkCancellation()
            let receipt = TwoPaneImageNewReceipt(value: try receiptValue(request: request, limits: limits, work: &work))
            let steps = [
                "load \(paneCount) bound revisions via \(request.capability.loaderName)",
                "compare via \(request.capability.comparisonName)",
                "present initial mode \(request.displayMode.rawValue)",
            ]
            let contract = TwoPaneImageNewExecutorContract(
                receiptValue: receipt.value,
                expectedPaneCount: paneCount,
                loaderName: request.capability.loaderName,
                comparisonName: request.capability.comparisonName,
                steps: steps
            )
            return TwoPaneImageNewPlan.issued(
                panes: planned,
                displayMode: request.displayMode,
                comparisonOptions: request.comparisonOptions,
                capability: request.capability,
                limits: limits,
                receipt: receipt,
                executorContract: contract,
                workPerformed: work.completed
            )
        } catch is CancellationError {
            throw TwoPaneImageNewError.cancelled
        } catch let error as TwoPaneImageNewError {
            throw error
        } catch {
            throw error
        }
    }

    public static func make(
        _ request: TwoPaneImageNewRequest,
        limits: TwoPaneImageNewLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> TwoPaneImageNewPlan {
        try plan(request, limits: limits, cancellationCheck: cancellationCheck)
    }

    /// Recomputes the canonical receipt from the plan's bound values and rejects mismatches.
    /// Re-enforces every plan-time bound (per-revision shape, digest, allowlist, options>=1,
    /// capability supports, duplicate) so a hand-crafted plan cannot bypass checks via recompute
    /// alone. Work is deterministic for identical inputs, so workPerformed must equal recomputed
    /// work exactly; no tolerance.
    public static func validate(
        _ plan: TwoPaneImageNewPlan,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws {
        do {
            try plan.limits.validate()
            guard plan.limits.maximumSources == TwoPaneImageNewLimits.hardMaximumSources else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard plan.panes.count == 2 else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard plan.panes[0].pane == .left, plan.panes[1].pane == .right else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard plan.executorContract.receiptValue == plan.receipt.value else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard plan.executorContract.expectedPaneCount == 2,
                plan.executorContract.loaderName == plan.capability.loaderName,
                plan.executorContract.comparisonName == plan.capability.comparisonName
            else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard plan.capability.supports(paneCount: 2) else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard !plan.capability.loaderName.isEmpty,
                !plan.capability.limitsName.isEmpty,
                !plan.capability.optionsName.isEmpty,
                !plan.capability.comparisonName.isEmpty,
                !plan.capability.supportedTypeIdentifiers.isEmpty
            else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard plan.receipt.value.count == 64,
                plan.receipt.value.allSatisfy({ $0.isHexDigit })
            else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard plan.workPerformed >= 1,
                plan.workPerformed <= plan.limits.maximumPlanningWorkUnits
            else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            guard plan.comparisonOptions.maximumCanvasPixels >= 1,
                plan.comparisonOptions.maximumRegions >= 1,
                plan.comparisonOptions.maximumQueuedPixels >= 1
            else {
                throw TwoPaneImageNewError.receiptMismatch
            }
            var work = TwoPaneImageNewPlanningWork(
                maximum: plan.limits.maximumPlanningWorkUnits,
                cancellationCheckInterval: plan.limits.cancellationCheckInterval,
                cancellationCheck: cancellationCheck
            )
            do {
                try work.checkCancellation()
                guard 2 <= plan.limits.maximumSources else {
                    throw TwoPaneImageNewError.receiptMismatch
                }
                // Mirrors plan(): one unit for the header guards.
                try work.consume()
                for pane in plan.panes {
                    try validateRevision(
                        pane.revision,
                        limits: plan.limits,
                        capability: plan.capability,
                        work: &work
                    )
                }
                let digests = plan.panes.map({ $0.revision.sha256 })
                guard Set(digests).count == digests.count else {
                    throw TwoPaneImageNewError.receiptMismatch
                }
                // Mirrors plan(): one unit for the duplicate guard.
                try work.consume()
                try work.checkCancellation()
                let request = TwoPaneImageNewRequest(
                    left: plan.panes[0].revision,
                    right: plan.panes[1].revision,
                    displayMode: plan.displayMode,
                    comparisonOptions: plan.comparisonOptions,
                    capability: plan.capability
                )
                let recomputed = try receiptValue(request: request, limits: plan.limits, work: &work)
                guard recomputed == plan.receipt.value else {
                    throw TwoPaneImageNewError.receiptMismatch
                }
                guard work.completed == plan.workPerformed else {
                    throw TwoPaneImageNewError.receiptMismatch
                }
            } catch let error as TwoPaneImageNewError {
                if error == .cancelled {
                    throw error
                }
                throw TwoPaneImageNewError.receiptMismatch
            }
            try plan.requireReceipt(plan.receipt)
        } catch is CancellationError {
            throw TwoPaneImageNewError.cancelled
        } catch let error as TwoPaneImageNewError {
            throw error
        } catch {
            throw error
        }
    }

    private static func validateRevision(
        _ revision: TwoPaneImageNewRevision,
        limits: TwoPaneImageNewLimits,
        capability: TwoPaneImageNewCapability,
        work: inout TwoPaneImageNewPlanningWork
    ) throws {
        let source = revision.source
        let path = source.canonicalPath
        guard !path.isEmpty, !path.contains("\0"), path.contains(where: { !$0.isWhitespace }) else {
            throw TwoPaneImageNewError.emptyPath
        }
        let pathBytes = path.utf8.count
        guard pathBytes <= limits.maximumPathUTF8Bytes else {
            throw TwoPaneImageNewError.pathTooLarge(maximumUTF8Bytes: limits.maximumPathUTF8Bytes)
        }
        try work.consume(pathBytes)
        try work.consume()
        guard (1...limits.maximumByteSize).contains(source.byteSize) else {
            throw TwoPaneImageNewError.byteSizeExceeded(maximumBytes: limits.maximumByteSize)
        }
        try work.consume()
        guard capability.supportedTypeIdentifiers.contains(source.typeIdentifier) else {
            throw TwoPaneImageNewError.unsupportedFormat(hintBytes: source.typeIdentifier.utf8.count)
        }
        try work.consume()
        guard (1...limits.maximumDimension).contains(source.width) else {
            throw TwoPaneImageNewError.dimensionsExceeded(
                width: source.width,
                height: source.height,
                maximum: limits.maximumDimension
            )
        }
        guard (1...limits.maximumDimension).contains(source.height) else {
            throw TwoPaneImageNewError.dimensionsExceeded(
                width: source.width,
                height: source.height,
                maximum: limits.maximumDimension
            )
        }
        try work.consume()
        let (pixels, overflow) = source.width.multipliedReportingOverflow(by: source.height)
        guard !overflow, (1...limits.maximumPixelCount).contains(pixels) else {
            throw TwoPaneImageNewError.pixelCountExceeded(maximumPixels: limits.maximumPixelCount)
        }
        try work.consume(revision.sha256.count)
        guard revision.isValidDigest else {
            throw TwoPaneImageNewError.invalidDigest
        }
        try work.consume()
        let pixelFormat = source.pixelFormat
        guard !pixelFormat.isEmpty, !pixelFormat.contains("\0"),
            !pixelFormat.contains("\n"), !pixelFormat.contains("\r")
        else {
            throw TwoPaneImageNewError.emptyPixelFormat
        }
        let pixelFormatBytes = pixelFormat.utf8.count
        guard pixelFormatBytes <= limits.maximumPixelFormatUTF8Bytes else {
            throw TwoPaneImageNewError.pixelFormatTooLarge(maximumUTF8Bytes: limits.maximumPixelFormatUTF8Bytes)
        }
        try work.consume(pixelFormatBytes)
        try work.consume()
    }

    private static let maxReceiptNameCharacters = 256

    /// Collision-free receipt encoding for short names. Length-prefix frames the value and hex
    /// avoids newline-folding collisions. Rejects overlong or control-character names instead of
    /// truncating/folding (truncation lets distinct names share one receipt).
    private static func receiptName(_ value: String) throws -> String {
        let byteCount = value.utf8.count
        guard byteCount <= maxReceiptNameCharacters else {
            throw TwoPaneImageNewError.receiptMismatch
        }
        guard !value.contains("\0"), !value.contains("\n"), !value.contains("\r") else {
            throw TwoPaneImageNewError.receiptMismatch
        }
        return "\(byteCount):\(twoPaneImageNewHex(Data(value.utf8)))"
    }

    private static func receiptPathHash(_ canonicalPath: String) -> String {
        twoPaneImageNewHex(Data(SHA256.hash(data: Data(canonicalPath.utf8))))
    }

    /// Canonical receipt. Binds loader/limits/options/comparison names, supported pane counts,
    /// limits, allowlist, options, and per-pane digest/geometry/format. canonicalPath itself is
    /// intentionally omitted (redaction: receipts may be logged); only its SHA-256 hash is bound
    /// so path substitution is detected without leaking path bytes.
    static func receiptValue(
        request: TwoPaneImageNewRequest,
        limits: TwoPaneImageNewLimits,
        work: inout TwoPaneImageNewPlanningWork
    ) throws -> String {
        var canonical = "two-pane-image-new.v1\n"
        canonical += "panes:\(request.paneCount)\n"
        canonical += "mode:\(request.displayMode.rawValue)\n"
        canonical += "loader:\(try receiptName(request.capability.loaderName))\n"
        canonical += "limits-core:\(try receiptName(request.capability.limitsName))\n"
        canonical += "options-core:\(try receiptName(request.capability.optionsName))\n"
        canonical += "comparison:\(try receiptName(request.capability.comparisonName))\n"
        let paneCounts = request.capability.supportedPaneCounts.sorted().map({ String($0) }).joined(
            separator: ","
        )
        canonical += "paneCounts:\(paneCounts)\n"
        canonical += "limits:\(limits.maximumSources)/\(limits.maximumPathUTF8Bytes)/\(limits.maximumByteSize)/"
        canonical += "\(limits.maximumDimension)/\(limits.maximumPixelCount)/\(limits.maximumPixelFormatUTF8Bytes)/"
        canonical += "\(limits.maximumPlanningWorkUnits)/\(limits.cancellationCheckInterval)\n"
        let allowlist = request.capability.supportedTypeIdentifiers.sorted().joined(separator: ",")
        canonical += "allowlist:\(allowlist)\n"
        canonical += "options:\(request.comparisonOptions.channelTolerance)/"
        canonical += "\(request.comparisonOptions.maximumCanvasPixels)/\(request.comparisonOptions.maximumRegions)/"
        canonical += "\(request.comparisonOptions.maximumQueuedPixels)\n"
        for entry in request.orderedRevisions {
            let source = entry.revision.source
            canonical += "pane:\(entry.pane.rawValue)\n"
            canonical += "digest:\(entry.revision.digestHex)\n"
            canonical += "bytes:\(source.byteSize)\n"
            canonical += "extent:\(source.width)x\(source.height)\n"
            canonical += "format:\(try receiptName(source.typeIdentifier))\n"
            canonical += "pixelFormat:\(try receiptName(source.pixelFormat))\n"
            canonical += "pathHash:\(receiptPathHash(source.canonicalPath))\n"
        }
        try work.consume(canonical.utf8.count)
        try work.checkCancellation()
        return twoPaneImageNewHex(Data(SHA256.hash(data: Data(canonical.utf8))))
    }
}

func twoPaneImageNewHex(_ data: Data) -> String {
    var result = ""
    result.reserveCapacity(data.count * 2)
    let digits = Array("0123456789abcdef")
    for byte in data {
        result.append(digits[Int(byte >> 4)])
        result.append(digits[Int(byte & 0x0F)])
    }
    return result
}

struct TwoPaneImageNewPlanningWork {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: TwoPaneImageNewPlanner.CancellationCheck
    private(set) var completed = 0

    init(
        maximum: Int,
        cancellationCheckInterval: Int,
        cancellationCheck: @escaping TwoPaneImageNewPlanner.CancellationCheck
    ) {
        self.maximum = maximum
        self.cancellationCheckInterval = cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            try checkCancellation()
            throw TwoPaneImageNewError.planningWorkExceeded(maximumWorkUnits: maximum)
        }
        guard amount <= maximum, completed <= maximum - amount else {
            try checkCancellation()
            throw TwoPaneImageNewError.planningWorkExceeded(maximumWorkUnits: maximum)
        }
        let previousBucket = completed / cancellationCheckInterval
        completed += amount
        if completed / cancellationCheckInterval != previousBucket {
            try checkCancellation()
        }
    }

    func checkCancellation() throws {
        do {
            try cancellationCheck()
        } catch is CancellationError {
            throw TwoPaneImageNewError.cancelled
        }
    }
}
