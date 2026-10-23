import CryptoKit
import Foundation

/// Bounded, UI-independent new three-pane image comparison core (`ID_FILE_NEW3_IMAGE`).
///
/// Planning performs no I/O, decoding, rendering, document creation, or picker work.
/// Callers supply observed file identities alongside caller-computed SHA-256 digests;
/// the planner validates bounds, binds exact revisions, and emits a deterministic
/// receipt plus an executor contract. A document host performs all loading and
/// comparison off-plan.
public enum ThreePaneImageNewPane: String, CaseIterable, Hashable, Sendable {
    case left
    case middle
    case right

    public static let requestOrder: [ThreePaneImageNewPane] = [.left, .middle, .right]

    var sortOrder: Int {
        switch self {
        case .left: 0
        case .middle: 1
        case .right: 2
        }
    }
}

/// Initial presentation mode for a new three-pane image comparison.
public enum ThreePaneImageNewDisplayMode: String, CaseIterable, Hashable, Sendable {
    case overlay
    case blink

    public static let `default`: ThreePaneImageNewDisplayMode = .overlay
}

/// Observed file identity for one pane. Pass `url.standardizedFileURL.path` as `canonicalPath`.
public struct ThreePaneImageNewSource: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let canonicalPath: String
    public let byteSize: Int
    public let formatHint: String
    public let width: Int
    public let height: Int

    public init(
        canonicalPath: String,
        byteSize: Int,
        formatHint: String,
        width: Int,
        height: Int
    ) {
        self.canonicalPath = canonicalPath
        self.byteSize = byteSize
        self.formatHint = formatHint
        self.width = width
        self.height = height
    }

    public var pathUTF8Bytes: Int { canonicalPath.utf8.count }

    public var description: String {
        "ThreePaneImageNewSource(bytes: \(byteSize), format: \(formatHint.utf8.count) bytes, extent: \(width)x\(height))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "pathUTF8Bytes": pathUTF8Bytes,
                "byteSize": byteSize,
                "formatUTF8Bytes": formatHint.utf8.count,
                "width": width,
                "height": height
            ],
            displayStyle: .struct
        )
    }
}

/// One pane source bound to its exact SHA-256 revision digest.
public struct ThreePaneImageNewRevision: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let digestByteCount = 32

    public let source: ThreePaneImageNewSource
    public let sha256: Data

    public init(source: ThreePaneImageNewSource, sha256: Data) {
        self.source = source
        self.sha256 = sha256
    }

    public var digestHex: String { threePaneImageNewHex(sha256) }

    public var isValidDigest: Bool {
        sha256.count == Self.digestByteCount && !sha256.allSatisfy({ $0 == 0 })
    }

    public var description: String {
        "ThreePaneImageNewRevision(digest: \(digestHex), bytes: \(source.byteSize), extent: \(source.width)x\(source.height))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "digestHex": digestHex,
                "byteSize": source.byteSize,
                "formatUTF8Bytes": source.formatHint.utf8.count,
                "width": source.width,
                "height": source.height
            ],
            displayStyle: .struct
        )
    }
}

/// Capability requirement naming the existing image cores an executor must use.
public struct ThreePaneImageNewCapability: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = ThreePaneImageNewCapability(
        loaderName: "BoundedImageLoader",
        limitsName: "ImageComparisonLimits",
        optionsName: "ImageComparisonOptions",
        comparisonName: "ThreeWayImageComparison",
        supportedTypeIdentifiers: ImageComparisonLimits.supportedStaticTypeIdentifiers,
        supportedPaneCounts: [3]
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
        "ThreePaneImageNewCapability(loader: \(loaderName), comparison: \(comparisonName), panes: \(supportedPaneCounts.count))"
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
                "supportedPaneCounts": supportedPaneCounts
            ],
            displayStyle: .struct
        )
    }
}

/// Plan-only new request. All three panes are always required.
public struct ThreePaneImageNewRequest: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let left: ThreePaneImageNewRevision
    public let middle: ThreePaneImageNewRevision
    public let right: ThreePaneImageNewRevision
    public let displayMode: ThreePaneImageNewDisplayMode
    public let comparisonOptions: ImageComparisonOptions
    public let comparisonLimits: ImageComparisonLimits
    public let capability: ThreePaneImageNewCapability

    public init(
        left: ThreePaneImageNewRevision,
        middle: ThreePaneImageNewRevision,
        right: ThreePaneImageNewRevision,
        displayMode: ThreePaneImageNewDisplayMode = .default,
        comparisonOptions: ImageComparisonOptions = .default,
        comparisonLimits: ImageComparisonLimits = .default,
        capability: ThreePaneImageNewCapability = .default
    ) {
        self.left = left
        self.middle = middle
        self.right = right
        self.displayMode = displayMode
        self.comparisonOptions = comparisonOptions
        self.comparisonLimits = comparisonLimits
        self.capability = capability
    }

    public var paneCount: Int { 3 }

    var orderedRevisions: [(pane: ThreePaneImageNewPane, revision: ThreePaneImageNewRevision)] {
        [
            (pane: .left, revision: left),
            (pane: .middle, revision: middle),
            (pane: .right, revision: right)
        ]
    }

    public var description: String {
        let digests = orderedRevisions.map({ $0.revision.digestHex })
        return "ThreePaneImageNewRequest(panes: 3, mode: \(displayMode.rawValue), digests: \(digests))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "paneCount": 3,
                "displayMode": displayMode.rawValue,
                "digestHexes": orderedRevisions.map({ $0.revision.digestHex }),
                "loaderName": capability.loaderName,
                "comparisonName": capability.comparisonName
            ],
            displayStyle: .struct
        )
    }
}

/// Bounded limit selector for `ThreePaneImageNewLimits`.
public enum ThreePaneImageNewLimit: String, CaseIterable, Hashable, Sendable {
    case sources
    case pathBytes
    case byteSize
    case dimension
    case pixelCount
    case workUnits
    case cancellationCheckInterval
}

/// Bounds for three-pane image new planning. All maxima are enforced before any receipt is issued.
public struct ThreePaneImageNewLimits: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let hardMaximumSources = 3
    public static let hardMaximumPathUTF8Bytes = 32 * 1024
    public static let hardMaximumByteSize = 256 * 1024 * 1024
    public static let hardMaximumDimension = 16_384
    public static let hardMaximumPixelCount = 64 * 1024 * 1024
    public static let hardMaximumPlanningWorkUnits = 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 4_096
    public static let `default` = ThreePaneImageNewLimits()

    public let maximumSources: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumByteSize: Int
    public let maximumDimension: Int
    public let maximumPixelCount: Int
    public let maximumPlanningWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumSources: Int = ThreePaneImageNewLimits.hardMaximumSources,
        maximumPathUTF8Bytes: Int = 4_096,
        maximumByteSize: Int = 64 * 1024 * 1024,
        maximumDimension: Int = ThreePaneImageNewLimits.hardMaximumDimension,
        maximumPixelCount: Int = 16 * 1024 * 1024,
        maximumPlanningWorkUnits: Int = 16_384,
        cancellationCheckInterval: Int = 64
    ) {
        self.maximumSources = maximumSources
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumByteSize = maximumByteSize
        self.maximumDimension = maximumDimension
        self.maximumPixelCount = maximumPixelCount
        self.maximumPlanningWorkUnits = maximumPlanningWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }

    public func validate() throws {
        guard (2...Self.hardMaximumSources).contains(maximumSources) else {
            throw ThreePaneImageNewError.invalidLimit(.sources, value: maximumSources)
        }
        guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
            throw ThreePaneImageNewError.invalidLimit(.pathBytes, value: maximumPathUTF8Bytes)
        }
        guard (1...Self.hardMaximumByteSize).contains(maximumByteSize) else {
            throw ThreePaneImageNewError.invalidLimit(.byteSize, value: maximumByteSize)
        }
        guard (1...Self.hardMaximumDimension).contains(maximumDimension) else {
            throw ThreePaneImageNewError.invalidLimit(.dimension, value: maximumDimension)
        }
        guard (1...Self.hardMaximumPixelCount).contains(maximumPixelCount) else {
            throw ThreePaneImageNewError.invalidLimit(.pixelCount, value: maximumPixelCount)
        }
        guard (1...Self.hardMaximumPlanningWorkUnits).contains(maximumPlanningWorkUnits) else {
            throw ThreePaneImageNewError.invalidLimit(.workUnits, value: maximumPlanningWorkUnits)
        }
        guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
            throw ThreePaneImageNewError.invalidLimit(.cancellationCheckInterval, value: cancellationCheckInterval)
        }
    }

    public var description: String {
        "ThreePaneImageNewLimits(sources: \(maximumSources), pathBytes: \(maximumPathUTF8Bytes),"
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
                "maximumPlanningWorkUnits": maximumPlanningWorkUnits,
                "cancellationCheckInterval": cancellationCheckInterval
            ],
            displayStyle: .struct
        )
    }
}

/// Typed rejection for every three-pane image new planning failure. Summaries carry digests and
/// counts only, never pixel bytes or full paths.
public enum ThreePaneImageNewError: Error, Equatable, LocalizedError, Sendable,
    CustomDebugStringConvertible, CustomReflectable
{
    case cancelled
    case invalidLimit(ThreePaneImageNewLimit, value: Int)
    case paneCountExceeded(requested: Int, maximum: Int)
    case unsupportedPaneCount(panes: Int)
    case invalidOptions
    case invalidComparisonLimits
    case unsupportedCapability(name: String)
    case emptyPath
    case pathTooLarge(maximumUTF8Bytes: Int)
    case byteSizeExceeded(maximumBytes: Int)
    case unsupportedFormat(hint: String)
    case dimensionsExceeded(width: Int, height: Int, maximum: Int)
    case pixelCountExceeded(maximumPixels: Int)
    case invalidDigest
    case duplicateRevision
    case planningWorkExceeded(maximumWorkUnits: Int)

    public var errorDescription: String? { redactedSummary }

    public var debugDescription: String { redactedSummary }

    public var customMirror: Mirror {
        Mirror(self, children: ["summary": redactedSummary], displayStyle: .enum)
    }

    private var redactedSummary: String {
        switch self {
        case .cancelled:
            "Three-pane image new planning was cancelled."
        case .invalidLimit(let limit, let value):
            "Invalid three-pane image new limit \(limit.rawValue): \(value)."
        case .paneCountExceeded(let requested, let maximum):
            "A \(requested)-pane request exceeds the \(maximum)-pane limit."
        case .unsupportedPaneCount(let panes):
            "Three-pane image capability does not support \(panes) panes."
        case .invalidOptions:
            "Three-pane image new comparison options are invalid."
        case .invalidComparisonLimits:
            "Three-pane image new comparison limits are invalid."
        case .unsupportedCapability(let name):
            "Three-pane image new capability names an unsupported core (\(name.count) UTF-8 bytes)."
        case .emptyPath:
            "Three-pane image new source path is empty."
        case .pathTooLarge(let maximum):
            "Three-pane image new source path exceeds \(maximum) UTF-8 bytes."
        case .byteSizeExceeded(let maximum):
            "Three-pane image new source exceeds \(maximum) bytes."
        case .unsupportedFormat(let hint):
            "Three-pane image new format (\(hint.utf8.count) UTF-8 bytes) is not in the allowlist."
        case .dimensionsExceeded(let width, let height, let maximum):
            "Three-pane image new extent \(width)x\(height) exceeds maximum dimension \(maximum)."
        case .pixelCountExceeded(let maximum):
            "Three-pane image new pixel count exceeds \(maximum) pixels."
        case .invalidDigest:
            "Three-pane image new revision digest is not a non-zero SHA-256 value."
        case .duplicateRevision:
            "Three-pane image new panes bind the same source revision."
        case .planningWorkExceeded(let maximum):
            "Three-pane image new planning exceeds the \(maximum)-unit work limit."
        }
    }
}

/// Deterministic receipt binding the exact revisions a plan was issued for.
public struct ThreePaneImageNewReceipt: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public var description: String { "ThreePaneImageNewReceipt(\(value))" }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["value": value], displayStyle: .struct)
    }
}

/// Plan-only executor contract. Data only; the executor performs all I/O and comparison off-plan.
public struct ThreePaneImageNewExecutorContract: Equatable, Hashable, Sendable,
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
        "ThreePaneImageNewExecutorContract(panes: \(expectedPaneCount), loader: \(loaderName), comparison: \(comparisonName), steps: \(steps.count))"
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
                "stepCount": steps.count
            ],
            displayStyle: .struct
        )
    }
}

/// One validated pane with its exact bound revision.
public struct ThreePaneImageNewPlannedPane: Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let pane: ThreePaneImageNewPane
    public let revision: ThreePaneImageNewRevision

    public init(pane: ThreePaneImageNewPane, revision: ThreePaneImageNewRevision) {
        self.pane = pane
        self.revision = revision
    }

    public var description: String {
        "ThreePaneImageNewPlannedPane(pane: \(pane.rawValue), digest: \(revision.digestHex))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "pane": pane.rawValue,
                "digestHex": revision.digestHex,
                "byteSize": revision.source.byteSize
            ],
            displayStyle: .struct
        )
    }
}

/// Validated three-pane image new plan with deterministic receipt and executor contract.
public struct ThreePaneImageNewPlan: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let panes: [ThreePaneImageNewPlannedPane]
    public let displayMode: ThreePaneImageNewDisplayMode
    public let comparisonOptions: ImageComparisonOptions
    public let comparisonLimits: ImageComparisonLimits
    public let capability: ThreePaneImageNewCapability
    public let receipt: ThreePaneImageNewReceipt
    public let executorContract: ThreePaneImageNewExecutorContract
    public let workPerformed: Int

    public var paneCount: Int { panes.count }

    public var description: String {
        "ThreePaneImageNewPlan(panes: \(paneCount), mode: \(displayMode.rawValue), receipt: \(receipt.value), work: \(workPerformed))"
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
                "workPerformed": workPerformed
            ],
            displayStyle: .struct
        )
    }

    private init(
        panes: [ThreePaneImageNewPlannedPane],
        displayMode: ThreePaneImageNewDisplayMode,
        comparisonOptions: ImageComparisonOptions,
        comparisonLimits: ImageComparisonLimits,
        capability: ThreePaneImageNewCapability,
        receipt: ThreePaneImageNewReceipt,
        executorContract: ThreePaneImageNewExecutorContract,
        workPerformed: Int
    ) {
        self.panes = panes
        self.displayMode = displayMode
        self.comparisonOptions = comparisonOptions
        self.comparisonLimits = comparisonLimits
        self.capability = capability
        self.receipt = receipt
        self.executorContract = executorContract
        self.workPerformed = workPerformed
    }

    fileprivate static func issued(
        panes: [ThreePaneImageNewPlannedPane],
        displayMode: ThreePaneImageNewDisplayMode,
        comparisonOptions: ImageComparisonOptions,
        comparisonLimits: ImageComparisonLimits,
        capability: ThreePaneImageNewCapability,
        receipt: ThreePaneImageNewReceipt,
        executorContract: ThreePaneImageNewExecutorContract,
        workPerformed: Int
    ) -> ThreePaneImageNewPlan {
        ThreePaneImageNewPlan(
            panes: panes,
            displayMode: displayMode,
            comparisonOptions: comparisonOptions,
            comparisonLimits: comparisonLimits,
            capability: capability,
            receipt: receipt,
            executorContract: executorContract,
            workPerformed: workPerformed
        )
    }
}

/// Plan-only planner. Validates three bound revisions, options, mode, limits, and capability,
/// then binds exact revisions and emits the plan. Never performs I/O, decoding, or rendering.
public enum ThreePaneImageNewPlanner: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let commandID = "ID_FILE_NEW3_IMAGE"

    public static func plan(
        _ request: ThreePaneImageNewRequest,
        limits: ThreePaneImageNewLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ThreePaneImageNewPlan {
        try limits.validate()
        var work = ThreePaneImageNewPlanningWork(
            maximum: limits.maximumPlanningWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try work.checkCancellation()

        let paneCount = request.paneCount
        guard paneCount <= limits.maximumSources else {
            throw ThreePaneImageNewError.paneCountExceeded(requested: paneCount, maximum: limits.maximumSources)
        }
        guard request.capability.supports(paneCount: paneCount) else {
            throw ThreePaneImageNewError.unsupportedPaneCount(panes: paneCount)
        }
        try work.consume()

        try validateCapability(request.capability)
        try validateOptions(request.comparisonOptions)
        try validateComparisonLimits(request.comparisonLimits)

        var planned: [ThreePaneImageNewPlannedPane] = []
        planned.reserveCapacity(paneCount)
        for entry in request.orderedRevisions {
            try validateRevision(
                entry.revision,
                request: request,
                limits: limits,
                work: &work
            )
            planned.append(ThreePaneImageNewPlannedPane(pane: entry.pane, revision: entry.revision))
        }
        planned.sort { $0.pane.sortOrder < $1.pane.sortOrder }

        let digests = planned.map({ $0.revision.sha256 })
        guard Set(digests).count == digests.count else {
            throw ThreePaneImageNewError.duplicateRevision
        }
        try work.consume()

        try validateCanvas(planned: planned, request: request, limits: limits, work: &work)

        try work.checkCancellation()
        let receipt = ThreePaneImageNewReceipt(value: try receiptValue(request: request, limits: limits, work: &work))
        let steps = [
            "load 3 bound revisions via \(request.capability.loaderName)",
            "compare via \(request.capability.comparisonName)",
            "present initial mode \(request.displayMode.rawValue)"
        ]
        let contract = ThreePaneImageNewExecutorContract(
            receiptValue: receipt.value,
            expectedPaneCount: paneCount,
            loaderName: request.capability.loaderName,
            comparisonName: request.capability.comparisonName,
            steps: steps
        )
        return ThreePaneImageNewPlan.issued(
            panes: planned,
            displayMode: request.displayMode,
            comparisonOptions: request.comparisonOptions,
            comparisonLimits: request.comparisonLimits,
            capability: request.capability,
            receipt: receipt,
            executorContract: contract,
            workPerformed: work.completed
        )
    }

    public static func make(
        _ request: ThreePaneImageNewRequest,
        limits: ThreePaneImageNewLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ThreePaneImageNewPlan {
        try plan(request, limits: limits, cancellationCheck: cancellationCheck)
    }

    private static func validateCapability(_ capability: ThreePaneImageNewCapability) throws {
        guard !capability.loaderName.isEmpty,
            !capability.limitsName.isEmpty,
            !capability.optionsName.isEmpty,
            !capability.comparisonName.isEmpty,
            !capability.supportedTypeIdentifiers.isEmpty
        else {
            throw ThreePaneImageNewError.unsupportedCapability(name: capability.comparisonName)
        }
    }

    private static func validateOptions(_ options: ImageComparisonOptions) throws {
        guard options.maximumCanvasPixels > 0,
            options.maximumRegions > 0,
            options.maximumQueuedPixels > 0
        else {
            throw ThreePaneImageNewError.invalidOptions
        }
    }

    private static func validateComparisonLimits(_ comparisonLimits: ImageComparisonLimits) throws {
        guard comparisonLimits.maximumEncodedBytes > 0,
            comparisonLimits.maximumDimension > 0,
            comparisonLimits.maximumPixelCount > 0,
            comparisonLimits.maximumDecodedBytes > 0,
            !comparisonLimits.supportedTypeIdentifiers.isEmpty
        else {
            throw ThreePaneImageNewError.invalidComparisonLimits
        }
    }

    private static func validateRevision(
        _ revision: ThreePaneImageNewRevision,
        request: ThreePaneImageNewRequest,
        limits: ThreePaneImageNewLimits,
        work: inout ThreePaneImageNewPlanningWork
    ) throws {
        let source = revision.source
        let path = source.canonicalPath
        guard !path.isEmpty, !path.contains("\0"), path.contains(where: { !$0.isWhitespace }) else {
            throw ThreePaneImageNewError.emptyPath
        }
        let pathBytes = path.utf8.count
        guard pathBytes <= limits.maximumPathUTF8Bytes else {
            throw ThreePaneImageNewError.pathTooLarge(maximumUTF8Bytes: limits.maximumPathUTF8Bytes)
        }
        guard (1...limits.maximumByteSize).contains(source.byteSize) else {
            throw ThreePaneImageNewError.byteSizeExceeded(maximumBytes: limits.maximumByteSize)
        }
        guard (1...request.comparisonLimits.maximumEncodedBytes).contains(source.byteSize) else {
            throw ThreePaneImageNewError.byteSizeExceeded(maximumBytes: request.comparisonLimits.maximumEncodedBytes)
        }
        guard request.capability.supportedTypeIdentifiers.contains(source.formatHint) else {
            throw ThreePaneImageNewError.unsupportedFormat(hint: source.formatHint)
        }
        guard request.comparisonLimits.supportedTypeIdentifiers.contains(source.formatHint) else {
            throw ThreePaneImageNewError.unsupportedFormat(hint: source.formatHint)
        }
        guard revision.isValidDigest else {
            throw ThreePaneImageNewError.invalidDigest
        }
        try work.consume(pathBytes)
        try work.consume()
        try work.consume()
        try work.consume()
        guard (1...limits.maximumDimension).contains(source.width) else {
            throw ThreePaneImageNewError.dimensionsExceeded(
                width: source.width,
                height: source.height,
                maximum: limits.maximumDimension
            )
        }
        guard (1...limits.maximumDimension).contains(source.height) else {
            throw ThreePaneImageNewError.dimensionsExceeded(
                width: source.width,
                height: source.height,
                maximum: limits.maximumDimension
            )
        }
        guard (1...request.comparisonLimits.maximumDimension).contains(source.width) else {
            throw ThreePaneImageNewError.dimensionsExceeded(
                width: source.width,
                height: source.height,
                maximum: request.comparisonLimits.maximumDimension
            )
        }
        guard (1...request.comparisonLimits.maximumDimension).contains(source.height) else {
            throw ThreePaneImageNewError.dimensionsExceeded(
                width: source.width,
                height: source.height,
                maximum: request.comparisonLimits.maximumDimension
            )
        }
        try work.consume()
        let (pixels, overflow) = source.width.multipliedReportingOverflow(by: source.height)
        guard !overflow, (1...limits.maximumPixelCount).contains(pixels) else {
            throw ThreePaneImageNewError.pixelCountExceeded(maximumPixels: limits.maximumPixelCount)
        }
        guard (1...request.comparisonLimits.maximumPixelCount).contains(pixels) else {
            throw ThreePaneImageNewError.pixelCountExceeded(maximumPixels: request.comparisonLimits.maximumPixelCount)
        }
        try work.consume(revision.sha256.count)
        try work.consume()
    }

    private static func validateCanvas(
        planned: [ThreePaneImageNewPlannedPane],
        request: ThreePaneImageNewRequest,
        limits: ThreePaneImageNewLimits,
        work: inout ThreePaneImageNewPlanningWork
    ) throws {
        let widths = planned.map({ $0.revision.source.width })
        let heights = planned.map({ $0.revision.source.height })
        // Planned always binds exactly three revisions, so maxima are always present.
        let canvasWidth = widths.max() ?? 1
        let canvasHeight = heights.max() ?? 1
        try work.consume()
        let (canvasPixels, overflow) = canvasWidth.multipliedReportingOverflow(by: canvasHeight)
        guard !overflow, canvasPixels >= 1 else {
            throw ThreePaneImageNewError.pixelCountExceeded(maximumPixels: limits.maximumPixelCount)
        }
        guard canvasPixels <= limits.maximumPixelCount else {
            throw ThreePaneImageNewError.pixelCountExceeded(maximumPixels: limits.maximumPixelCount)
        }
        guard canvasPixels <= request.comparisonLimits.maximumPixelCount else {
            throw ThreePaneImageNewError.pixelCountExceeded(maximumPixels: request.comparisonLimits.maximumPixelCount)
        }
        guard canvasPixels <= request.comparisonOptions.maximumCanvasPixels else {
            throw ThreePaneImageNewError.pixelCountExceeded(maximumPixels: request.comparisonOptions.maximumCanvasPixels)
        }
        try work.consume()
    }

    private static let maxReceiptNameCharacters = 256

    private static func cappedReceiptName(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "\n", with: "_").replacingOccurrences(of: "\r", with: "_")
        let byteCount = sanitized.utf8.count
        let capped =
            sanitized.count <= maxReceiptNameCharacters
            ? sanitized : String(sanitized.prefix(maxReceiptNameCharacters))
        let fullHash = threePaneImageNewHex(Data(SHA256.hash(data: Data(sanitized.utf8))))
        return "\(byteCount):\(capped):\(fullHash)"
    }

    private static func receiptValue(
        request: ThreePaneImageNewRequest,
        limits: ThreePaneImageNewLimits,
        work: inout ThreePaneImageNewPlanningWork
    ) throws -> String {
        var canonical = "three-pane-image-new/1\n"
        canonical += "command:\(commandID)\n"
        canonical += "panes:3\n"
        canonical += "mode:\(request.displayMode.rawValue)\n"
        canonical += "loader:\(cappedReceiptName(request.capability.loaderName))\n"
        canonical += "limits-core:\(cappedReceiptName(request.capability.limitsName))\n"
        canonical += "options-core:\(cappedReceiptName(request.capability.optionsName))\n"
        canonical += "comparison:\(cappedReceiptName(request.capability.comparisonName))\n"
        canonical += "limits:\(limits.maximumSources)/\(limits.maximumPathUTF8Bytes)/\(limits.maximumByteSize)/"
        canonical += "\(limits.maximumDimension)/\(limits.maximumPixelCount)/\(limits.maximumPlanningWorkUnits)/"
        canonical += "\(limits.cancellationCheckInterval)\n"
        canonical += "comparison-limits:\(request.comparisonLimits.maximumEncodedBytes)/"
        canonical += "\(request.comparisonLimits.maximumDimension)/\(request.comparisonLimits.maximumPixelCount)/"
        canonical += "\(request.comparisonLimits.maximumDecodedBytes)\n"
        canonical += "options:\(Int(request.comparisonOptions.channelTolerance))/"
        canonical += "\(request.comparisonOptions.maximumCanvasPixels)/\(request.comparisonOptions.maximumRegions)/"
        canonical += "\(request.comparisonOptions.maximumQueuedPixels)\n"
        let capabilityAllowlist = request.capability.supportedTypeIdentifiers.sorted().joined(separator: ",")
        canonical += "capability-allowlist:\(capabilityAllowlist)\n"
        let comparisonAllowlist = request.comparisonLimits.supportedTypeIdentifiers.sorted().joined(separator: ",")
        canonical += "comparison-allowlist:\(comparisonAllowlist)\n"
        for entry in request.orderedRevisions {
            let source = entry.revision.source
            canonical += "pane:\(entry.pane.rawValue)\n"
            canonical += "digest:\(entry.revision.digestHex)\n"
            canonical += "bytes:\(source.byteSize)\n"
            canonical += "extent:\(source.width)x\(source.height)\n"
            canonical += "format:\(cappedReceiptName(source.formatHint))\n"
        }
        try work.consume(canonical.utf8.count)
        try work.checkCancellation()
        return threePaneImageNewHex(Data(SHA256.hash(data: Data(canonical.utf8))))
    }
}

private func threePaneImageNewHex(_ data: Data) -> String {
    var result = ""
    result.reserveCapacity(data.count * 2)
    let digits = Array("0123456789abcdef")
    for byte in data {
        result.append(digits[Int(byte >> 4)])
        result.append(digits[Int(byte & 0x0F)])
    }
    return result
}

struct ThreePaneImageNewPlanningWork {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: ThreePaneImageNewPlanner.CancellationCheck
    private(set) var completed = 0

    init(
        maximum: Int,
        cancellationCheckInterval: Int,
        cancellationCheck: @escaping ThreePaneImageNewPlanner.CancellationCheck
    ) {
        precondition(cancellationCheckInterval >= 1)
        self.maximum = maximum
        self.cancellationCheckInterval = cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            try checkCancellation()
            throw ThreePaneImageNewError.planningWorkExceeded(maximumWorkUnits: maximum)
        }
        guard amount <= maximum, completed <= maximum - amount else {
            try checkCancellation()
            throw ThreePaneImageNewError.planningWorkExceeded(maximumWorkUnits: maximum)
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
            throw ThreePaneImageNewError.cancelled
        }
    }
}
