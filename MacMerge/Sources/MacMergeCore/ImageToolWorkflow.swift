import CryptoKit
import Foundation

extension ImageComparisonOptions: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(channelTolerance)
        hasher.combine(maximumCanvasPixels)
        hasher.combine(maximumRegions)
        hasher.combine(maximumQueuedPixels)
    }
}

public enum ImageToolPane: Int, CaseIterable, Comparable, Hashable, Sendable {
    case left
    case middle
    case right

    public static func < (left: ImageToolPane, right: ImageToolPane) -> Bool {
        left.rawValue < right.rawValue
    }
}

public struct ImageToolImageIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Exact caller-owned image revision. Owners must advance `revision` whenever encoded content or
/// decoded page membership changes and `generation` whenever materialized image state changes.
public struct ImageToolImageRevision: Hashable, Sendable {
    public let identity: ImageToolImageIdentity
    public let revision: UInt64
    public let generation: UInt64
    public let contentSHA256: [UInt8]

    public init(
        identity: ImageToolImageIdentity,
        revision: UInt64,
        generation: UInt64,
        contentSHA256: [UInt8]
    ) {
        self.identity = identity
        self.revision = revision
        self.generation = generation
        self.contentSHA256 = contentSHA256
    }
}

/// Metadata supplied by an image owner. This workflow never decodes or inspects image bytes.
public struct ImageToolPageDescriptor: Hashable, Sendable {
    public let index: Int
    public let width: Int
    public let height: Int
    public let bitsPerPixel: Int
    public let isVector: Bool
    public let label: String?

    public init(
        index: Int,
        width: Int,
        height: Int,
        bitsPerPixel: Int,
        isVector: Bool = false,
        label: String? = nil
    ) {
        self.index = index
        self.width = width
        self.height = height
        self.bitsPerPixel = bitsPerPixel
        self.isVector = isVector
        self.label = label
    }
}

public struct ImageToolTransform: Hashable, Sendable {
    public static let identity = ImageToolTransform()

    /// Clockwise quarter turns, represented by values from zero through three.
    /// Executor applies rotation, then the requested horizontal and vertical flips.
    public let clockwiseQuarterTurns: Int
    public let flipsHorizontally: Bool
    public let flipsVertically: Bool

    public init(
        clockwiseQuarterTurns: Int = 0,
        flipsHorizontally: Bool = false,
        flipsVertically: Bool = false
    ) {
        self.clockwiseQuarterTurns = clockwiseQuarterTurns
        self.flipsHorizontally = flipsHorizontally
        self.flipsVertically = flipsVertically
    }
}

public struct ImageToolPaneSnapshot: Hashable, Sendable {
    public let pane: ImageToolPane
    public let image: ImageToolImageRevision
    public let pages: [ImageToolPageDescriptor]
    public let selectedPageIndex: Int
    public let transform: ImageToolTransform
    public let displayName: String?
    public let isReadOnly: Bool
    public let isModified: Bool

    public init(
        pane: ImageToolPane,
        image: ImageToolImageRevision,
        pages: [ImageToolPageDescriptor],
        selectedPageIndex: Int = 0,
        transform: ImageToolTransform = .identity,
        displayName: String? = nil,
        isReadOnly: Bool = true,
        isModified: Bool = false
    ) {
        self.pane = pane
        self.image = image
        self.pages = pages
        self.selectedPageIndex = selectedPageIndex
        self.transform = transform
        self.displayName = displayName
        self.isReadOnly = isReadOnly
        self.isModified = isModified
    }

    public var selectedPage: ImageToolPageDescriptor? {
        pages.first { $0.index == selectedPageIndex }
    }
}

public enum ImageToolPageSelectionMode: String, CaseIterable, Hashable, Sendable {
    case synchronized
    case independent
}

public struct ImageToolPanePageSelection: Hashable, Sendable {
    public let pane: ImageToolPane
    public let pageIndex: Int

    public init(pane: ImageToolPane, pageIndex: Int) {
        self.pane = pane
        self.pageIndex = pageIndex
    }
}

/// Complete desired page selection. Planner canonicalizes entries into pane order.
public struct ImageToolPageSelection: Hashable, Sendable {
    public let mode: ImageToolPageSelectionMode
    public let selections: [ImageToolPanePageSelection]

    public init(
        mode: ImageToolPageSelectionMode,
        selections: [ImageToolPanePageSelection]
    ) {
        self.mode = mode
        self.selections = selections
    }
}

public enum ImageToolInsertionDetection: String, CaseIterable, Hashable, Sendable {
    case none
    case vertical
    case horizontal
}

/// Difference controls supplement `ImageComparisonOptions`; they do not reimplement pixel matching.
public struct ImageToolDifferenceOptions: Hashable, Sendable {
    public static let `default` = ImageToolDifferenceOptions()

    public let pixelComparison: ImageComparisonOptions
    public let showsDifferences: Bool
    public let differenceBlockSize: Int
    public let colorDistanceThreshold: Double
    public let insertionDetection: ImageToolInsertionDetection

    public init(
        pixelComparison: ImageComparisonOptions = .default,
        showsDifferences: Bool = true,
        differenceBlockSize: Int = 8,
        colorDistanceThreshold: Double = 0,
        insertionDetection: ImageToolInsertionDetection = .none
    ) {
        self.pixelComparison = pixelComparison
        self.showsDifferences = showsDifferences
        self.differenceBlockSize = differenceBlockSize
        self.colorDistanceThreshold = colorDistanceThreshold
        self.insertionDetection = insertionDetection
    }
}

private struct ImageToolComparisonOptionProjection: Hashable {
    let pixelComparison: ImageComparisonOptions
    let differenceBlockSize: Int
    let colorDistanceThreshold: Double
    let insertionDetection: ImageToolInsertionDetection
}

public enum ImageToolZoomMode: String, CaseIterable, Hashable, Sendable {
    case fixed
    case fit
}

public struct ImageToolZoom: Hashable, Sendable {
    public static let normal = ImageToolZoom(mode: .fixed, scale: 1)

    public let mode: ImageToolZoomMode
    /// Used by fixed zoom. Fit mode retains this as a deterministic fallback scale.
    public let scale: Double

    public init(mode: ImageToolZoomMode = .fixed, scale: Double = 1) {
        self.mode = mode
        self.scale = scale
    }
}

public enum ImageToolOverlayMode: String, CaseIterable, Hashable, Sendable {
    case none
    case xor
    case alphaBlend
    case alphaBlendAnimation
}

public struct ImageToolOverlay: Hashable, Sendable {
    public static let none = ImageToolOverlay(mode: .none, alpha: 0.3)

    public let mode: ImageToolOverlayMode
    public let alpha: Double

    public init(mode: ImageToolOverlayMode = .none, alpha: Double = 0.3) {
        self.mode = mode
        self.alpha = alpha
    }
}

public enum ImageToolWipeMode: String, CaseIterable, Hashable, Sendable {
    case none
    case vertical
    case horizontal
}

public struct ImageToolWipe: Hashable, Sendable {
    public static let none = ImageToolWipe(mode: .none, position: 0.5)

    public let mode: ImageToolWipeMode
    /// Normalized reveal position from zero through one.
    public let position: Double

    public init(mode: ImageToolWipeMode = .none, position: Double = 0.5) {
        self.mode = mode
        self.position = position
    }
}

public struct ImageToolAnimation: Hashable, Sendable {
    public static let `default` = ImageToolAnimation()

    public let blinksDifferences: Bool
    public let blinkIntervalMilliseconds: Int
    public let overlayIntervalMilliseconds: Int

    public init(
        blinksDifferences: Bool = false,
        blinkIntervalMilliseconds: Int = 800,
        overlayIntervalMilliseconds: Int = 1_000
    ) {
        self.blinksDifferences = blinksDifferences
        self.blinkIntervalMilliseconds = blinkIntervalMilliseconds
        self.overlayIntervalMilliseconds = overlayIntervalMilliseconds
    }
}

public struct ImageToolControlState: Hashable, Sendable {
    public static let `default` = ImageToolControlState()

    public let pageSelectionMode: ImageToolPageSelectionMode
    public let differences: ImageToolDifferenceOptions
    public let zoom: ImageToolZoom
    public let overlay: ImageToolOverlay
    public let wipe: ImageToolWipe
    public let animation: ImageToolAnimation

    public init(
        pageSelectionMode: ImageToolPageSelectionMode = .synchronized,
        differences: ImageToolDifferenceOptions = .default,
        zoom: ImageToolZoom = .normal,
        overlay: ImageToolOverlay = .none,
        wipe: ImageToolWipe = .none,
        animation: ImageToolAnimation = .default
    ) {
        self.pageSelectionMode = pageSelectionMode
        self.differences = differences
        self.zoom = zoom
        self.overlay = overlay
        self.wipe = wipe
        self.animation = animation
    }
}

/// Exact, bounded reference to externally computed difference data.
public struct ImageToolDifferenceResultReference: Hashable, Sendable {
    public let identity: UUID
    public let generation: UInt64
    public let inputSHA256: [UInt8]
    public let resultSHA256: [UInt8]
    public let differenceCount: Int
    public let conflictCount: Int
    public let differingPixelCount: Int
    public let selectedDifferenceIndex: Int?

    public init(
        identity: UUID,
        generation: UInt64,
        inputSHA256: [UInt8],
        resultSHA256: [UInt8],
        differenceCount: Int,
        conflictCount: Int = 0,
        differingPixelCount: Int,
        selectedDifferenceIndex: Int? = nil
    ) {
        self.identity = identity
        self.generation = generation
        self.inputSHA256 = inputSHA256
        self.resultSHA256 = resultSHA256
        self.differenceCount = differenceCount
        self.conflictCount = conflictCount
        self.differingPixelCount = differingPixelCount
        self.selectedDifferenceIndex = selectedDifferenceIndex
    }
}

/// Owner snapshot. `revision` identifies the exact image set; `generation` changes for every control,
/// selection, transform, status-result, or edit-state mutation and is never reused.
public struct ImageToolWorkflowSnapshot: Hashable, Sendable {
    public let identity: UUID
    public let revision: UInt64
    public let generation: UInt64
    public let panes: [ImageToolPaneSnapshot]
    public let controls: ImageToolControlState
    public let differenceResult: ImageToolDifferenceResultReference?

    public init(
        identity: UUID = UUID(),
        revision: UInt64,
        generation: UInt64,
        panes: [ImageToolPaneSnapshot],
        controls: ImageToolControlState = .default,
        differenceResult: ImageToolDifferenceResultReference? = nil
    ) {
        self.identity = identity
        self.revision = revision
        self.generation = generation
        self.panes = panes
        self.controls = controls
        self.differenceResult = differenceResult
    }

    public subscript(pane: ImageToolPane) -> ImageToolPaneSnapshot? {
        panes.first { $0.pane == pane }
    }
}

public struct ImageToolSnapshotReference: Hashable, Sendable {
    public let identity: UUID
    public let revision: UInt64
    public let generation: UInt64

    public init(identity: UUID, revision: UInt64, generation: UInt64) {
        self.identity = identity
        self.revision = revision
        self.generation = generation
    }

    public init(_ snapshot: ImageToolWorkflowSnapshot) {
        identity = snapshot.identity
        revision = snapshot.revision
        generation = snapshot.generation
    }
}

public struct ImageToolSnapshotFingerprint: Hashable, Sendable {
    public let reference: ImageToolSnapshotReference
    public let stateSHA256: [UInt8]

    fileprivate init(reference: ImageToolSnapshotReference, stateSHA256: [UInt8]) {
        self.reference = reference
        self.stateSHA256 = stateSHA256
    }
}

public enum ImageToolCapability: String, CaseIterable, Hashable, Sendable {
    case normalizedPixelComparison
    case differenceVisibility
    case differenceBlockSize
    case colorDistanceThreshold
    case verticalInsertionDetection
    case horizontalInsertionDetection
    case synchronizedPageSelection
    case independentPageSelection
    case quarterTurnRotation
    case horizontalFlip
    case verticalFlip
    case fixedZoom
    case fitZoom
    case xorOverlay
    case alphaOverlay
    case animatedOverlay
    case verticalWipe
    case horizontalWipe
    case differenceBlink
    case ocrText
    case ocrLineObservations
    case ocrWordObservations
    case ocrLanguageHints
    case pixelStatus
}

public struct ImageToolCapabilities: Hashable, Sendable {
    public static let all = ImageToolCapabilities(Set(ImageToolCapability.allCases))
    public static let existingComparisonCore = ImageToolCapabilities([
        .normalizedPixelComparison,
        .differenceVisibility,
        .fixedZoom
    ])

    public let values: Set<ImageToolCapability>

    public init(_ values: Set<ImageToolCapability>) {
        self.values = values
    }

    public init(_ values: [ImageToolCapability]) {
        self.values = Set(values)
    }

    public func contains(_ capability: ImageToolCapability) -> Bool {
        values.contains(capability)
    }

    public func contains(_ capabilities: ImageToolCapabilities) -> Bool {
        values.isSuperset(of: capabilities.values)
    }
}

public enum ImageToolOCRResultKind: String, CaseIterable, Hashable, Sendable {
    case textOnly
    case lines
    case words
}

public enum ImageToolOCRCompletionIntent: String, CaseIterable, Hashable, Sendable {
    case returnResults
    /// Coordinator may open a text comparison after successful extraction. OCR executor never opens UI.
    case compareExtractedText
}

public struct ImageToolOCRTarget: Hashable, Sendable {
    public let pane: ImageToolPane
    public let pageIndex: Int

    public init(pane: ImageToolPane, pageIndex: Int) {
        self.pane = pane
        self.pageIndex = pageIndex
    }
}

public struct ImageToolOCRRequestIntent: Hashable, Sendable {
    public let targets: [ImageToolOCRTarget]
    public let resultKind: ImageToolOCRResultKind
    public let languageHints: [String]
    public let completion: ImageToolOCRCompletionIntent

    public init(
        targets: [ImageToolOCRTarget],
        resultKind: ImageToolOCRResultKind = .textOnly,
        languageHints: [String] = [],
        completion: ImageToolOCRCompletionIntent = .returnResults
    ) {
        self.targets = targets
        self.resultKind = resultKind
        self.languageHints = languageHints
        self.completion = completion
    }
}

public struct ImageToolPaneTransform: Hashable, Sendable {
    public let pane: ImageToolPane
    public let transform: ImageToolTransform

    public init(pane: ImageToolPane, transform: ImageToolTransform) {
        self.pane = pane
        self.transform = transform
    }
}

public enum ImageToolWorkflowIntent: Hashable, Sendable {
    case selectPages(ImageToolPageSelection)
    case setDifferenceOptions(ImageToolDifferenceOptions)
    case setTransforms([ImageToolPaneTransform])
    case setZoom(ImageToolZoom)
    case setOverlay(ImageToolOverlay)
    case setWipe(ImageToolWipe)
    case setAnimation(ImageToolAnimation)
    case requestOCR(ImageToolOCRRequestIntent)
}

public enum ImageToolWorkflowLimit: String, CaseIterable, Hashable, Sendable {
    case panes
    case pagesPerPane
    case totalPages
    case items
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case planBytes
    case workUnits
    case ocrResultUTF8Bytes
    case ocrResultItems
    case cancellationCheckInterval
}

public struct ImageToolWorkflowLimits: Hashable, Sendable {
    public static let hardMaximumPaneCount = 3
    public static let hardMaximumPagesPerPane = 1_000_000
    public static let hardMaximumTotalPages = 3_000_000
    public static let hardMaximumItemCount = 4_000_000
    public static let hardMaximumStringUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumPlanBytes = 64 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let hardMaximumOCRResultUTF8Bytes = 256 * 1_024 * 1_024
    public static let hardMaximumOCRResultItems = 4_000_000
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = ImageToolWorkflowLimits()

    public let maximumPaneCount: Int
    public let maximumPagesPerPane: Int
    public let maximumTotalPages: Int
    public let maximumItemCount: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumPlanBytes: Int
    public let maximumWorkUnits: UInt64
    public let maximumOCRResultUTF8Bytes: Int
    public let maximumOCRResultItems: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumPaneCount: Int = 3,
        maximumPagesPerPane: Int = 65_536,
        maximumTotalPages: Int = 196_608,
        maximumItemCount: Int = 262_144,
        maximumStringUTF8Bytes: Int = 16 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumPlanBytes: Int = 16 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
        maximumOCRResultUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumOCRResultItems: Int = 1_000_000,
        cancellationCheckInterval: Int = 4_096
    ) {
        self.maximumPaneCount = maximumPaneCount
        self.maximumPagesPerPane = maximumPagesPerPane
        self.maximumTotalPages = maximumTotalPages
        self.maximumItemCount = maximumItemCount
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumPlanBytes = maximumPlanBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumOCRResultUTF8Bytes = maximumOCRResultUTF8Bytes
        self.maximumOCRResultItems = maximumOCRResultItems
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct ImageToolWorkflowRequest: Hashable, Sendable {
    public let snapshot: ImageToolWorkflowSnapshot
    public let intent: ImageToolWorkflowIntent
    public let availableCapabilities: ImageToolCapabilities
    public let limits: ImageToolWorkflowLimits

    public init(
        snapshot: ImageToolWorkflowSnapshot,
        intent: ImageToolWorkflowIntent,
        availableCapabilities: ImageToolCapabilities,
        limits: ImageToolWorkflowLimits = .default
    ) {
        self.snapshot = snapshot
        self.intent = intent
        self.availableCapabilities = availableCapabilities
        self.limits = limits
    }
}

public enum ImageToolSnapshotIssue: String, CaseIterable, Hashable, Sendable {
    case invalidPaneCount
    case duplicatePane
    case invalidPaneSet
    case invalidImageDigest
    case emptyPageSet
    case tooManyPages
    case noncontiguousPageIndices
    case invalidPageDimensions
    case invalidBitsPerPixel
    case selectedPageMissing
    case invalidTransform
    case invalidDifferenceResult
    case invalidControlState
}

public enum ImageToolWorkflowError: Error, LocalizedError, Hashable, Sendable {
    case cancelled
    case invalidLimit(ImageToolWorkflowLimit)
    case invalidSnapshot(pane: ImageToolPane?, issue: ImageToolSnapshotIssue)
    case staleIdentity(expected: UUID, actual: UUID)
    case staleRevision(expected: UInt64, actual: UInt64)
    case staleGeneration(expected: UInt64, actual: UInt64)
    case snapshotContentsChanged
    case duplicatePaneSelection(ImageToolPane)
    case missingPaneSelection(ImageToolPane)
    case unknownPane(ImageToolPane)
    case pageNotFound(pane: ImageToolPane, pageIndex: Int)
    case synchronizedPagesDiffer
    case duplicateTransform(ImageToolPane)
    case invalidTransform(ImageToolPane)
    case invalidDifferenceBlockSize(Int)
    case invalidColorDistanceThreshold(Double)
    case invalidPixelComparisonOptions
    case invalidZoom(Double)
    case invalidOverlayAlpha(Double)
    case invalidWipePosition(Double)
    case invalidAnimationInterval(Int)
    case comparisonCanvasTooLarge(maximumPixels: Int)
    case missingCapability(ImageToolCapability)
    case emptyOCRTargets
    case duplicateOCRTarget(ImageToolOCRTarget)
    case invalidString
    case invalidLanguageHint(String)
    case stringTooLarge(maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case tooManyItems(maximum: Int)
    case workLimitExceeded(maximumUnits: UInt64)
    case planTooLarge(maximumBytes: Int)
    case noChange
    case generationOverflow
    case arithmeticOverflow
    case invalidStatusSample
    case invalidStatusDistance(ImageToolPane)
    case invalidExecutionResult
    case invalidOCRResult
    case ocrResultTooLarge(maximumUTF8Bytes: Int)
    case tooManyOCRResultItems(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Image tool planning was cancelled."
        case .invalidLimit(let limit):
            "Invalid image tool workflow limit: \(limit.rawValue)."
        case .invalidSnapshot(_, let issue):
            "Invalid image tool snapshot: \(issue.rawValue)."
        case .staleIdentity:
            "Image tool plan belongs to another snapshot."
        case .staleRevision:
            "Image tool image revision changed after planning."
        case .staleGeneration:
            "Image tool snapshot generation changed after planning."
        case .snapshotContentsChanged:
            "Image tool snapshot changed without advancing its revision or generation."
        case .duplicatePaneSelection(let pane):
            "Image page selection repeats the \(pane) pane."
        case .missingPaneSelection(let pane):
            "Image page selection omits the \(pane) pane."
        case .unknownPane(let pane):
            "Image tool snapshot has no \(pane) pane."
        case .pageNotFound(let pane, let page):
            "Image pane \(pane) has no page at index \(page)."
        case .synchronizedPagesDiffer:
            "Synchronized image page selections must use one page index."
        case .duplicateTransform(let pane):
            "Image transform repeats the \(pane) pane."
        case .invalidTransform(let pane):
            "Image transform for pane \(pane) is not canonical."
        case .invalidDifferenceBlockSize(let value):
            "Invalid image difference block size: \(value)."
        case .invalidColorDistanceThreshold(let value):
            "Invalid image color-distance threshold: \(value)."
        case .invalidPixelComparisonOptions:
            "Image pixel-comparison limits are invalid."
        case .invalidZoom(let value):
            "Invalid image zoom scale: \(value)."
        case .invalidOverlayAlpha(let value):
            "Invalid image overlay alpha: \(value)."
        case .invalidWipePosition(let value):
            "Invalid image wipe position: \(value)."
        case .invalidAnimationInterval(let value):
            "Invalid image animation interval: \(value)."
        case .comparisonCanvasTooLarge(let maximum):
            "Image comparison canvas exceeds the \(maximum)-pixel engine limit."
        case .missingCapability(let capability):
            "Image executor does not support \(capability.rawValue)."
        case .emptyOCRTargets:
            "Image OCR requires at least one target."
        case .duplicateOCRTarget(let target):
            "Image OCR repeats pane \(target.pane), page \(target.pageIndex)."
        case .invalidString:
            "Image tool strings may not contain NUL."
        case .invalidLanguageHint(let hint):
            "Invalid image OCR language hint: \(hint)."
        case .stringTooLarge(let maximum):
            "Image tool string exceeds \(maximum) UTF-8 bytes."
        case .totalStringsTooLarge(let maximum):
            "Image tool strings exceed \(maximum) combined UTF-8 bytes."
        case .tooManyItems(let maximum):
            "Image tool workflow exceeds the \(maximum)-item limit."
        case .workLimitExceeded(let maximum):
            "Image tool workflow exceeds the \(maximum)-unit work limit."
        case .planTooLarge(let maximum):
            "Image tool plan exceeds \(maximum) bytes."
        case .noChange:
            "Image tool intent does not change current state."
        case .generationOverflow:
            "Image tool generation cannot advance."
        case .arithmeticOverflow:
            "Image tool size calculation overflowed."
        case .invalidStatusSample:
            "Image status sample is outside the selected page."
        case .invalidStatusDistance(let pane):
            "Image status has an invalid distance for pane \(pane)."
        case .invalidExecutionResult:
            "Image executor returned a result that does not match the plan."
        case .invalidOCRResult:
            "Image OCR executor returned a result that does not match the plan."
        case .ocrResultTooLarge(let maximum):
            "Image OCR result exceeds \(maximum) UTF-8 bytes."
        case .tooManyOCRResultItems(let maximum):
            "Image OCR result exceeds the \(maximum)-item limit."
        }
    }
}

public enum ImageToolPlanningReceiptKind: String, CaseIterable, Hashable, Sendable {
    case pageSelection
    case differenceOptions
    case transforms
    case zoom
    case overlay
    case wipe
    case animation
    case ocr
}

/// Deterministic planning receipt. No random value or wall-clock time is generated by planning.
public struct ImageToolPlanningReceipt: Hashable, Sendable {
    public let kind: ImageToolPlanningReceiptKind
    public let source: ImageToolSnapshotReference
    public let projected: ImageToolSnapshotReference?
    public let planSHA256: [UInt8]
    public let canonicalPlanByteCount: Int
    public let estimatedWorkUnits: UInt64

    fileprivate init(
        kind: ImageToolPlanningReceiptKind,
        source: ImageToolSnapshotReference,
        projected: ImageToolSnapshotReference?,
        planSHA256: [UInt8],
        canonicalPlanByteCount: Int,
        estimatedWorkUnits: UInt64
    ) {
        self.kind = kind
        self.source = source
        self.projected = projected
        self.planSHA256 = planSHA256
        self.canonicalPlanByteCount = canonicalPlanByteCount
        self.estimatedWorkUnits = estimatedWorkUnits
    }
}

public enum ImageToolSnapshotExecutorContract: String, Hashable, Sendable {
    case exactFingerprintLeaseOrAtomicOwnerCompareAndSwap
}

public enum ImageToolComparisonExecutorContract: String, Hashable, Sendable {
    case invalidateThenScheduleImageDifferenceEngineUnderProjectedGeneration
}

public enum ImageToolPageExecutorContract: String, Hashable, Sendable {
    case resolveOnlyWithinPinnedImageRevisionAndDeclaredPageSet
}

public enum ImageToolCapabilityExecutorContract: String, Hashable, Sendable {
    case revalidateEveryRequiredCapabilityBeforeWork
}

public enum ImageToolOCRExecutorContract: String, Hashable, Sendable {
    case extractBoundedTextWithoutUIAndReturnExactTargetOrderedResults
}

public enum ImageToolCancellationExecutorContract: String, Hashable, Sendable {
    case checkBeforeWorkAtBoundedIntervalsAndBeforeAtomicStatePublication
}

public enum ImageToolPlannerIsolationContract: String, Hashable, Sendable {
    case noImageBytesDecodingOCRRenderingUIOrIO
}

/// Mandatory boundary for a platform executor. Planner supplies state and intent only.
public struct ImageToolExecutorContract: Hashable, Sendable {
    public static let required = ImageToolExecutorContract()

    public let snapshot =
        ImageToolSnapshotExecutorContract.exactFingerprintLeaseOrAtomicOwnerCompareAndSwap
    public let comparison =
        ImageToolComparisonExecutorContract.invalidateThenScheduleImageDifferenceEngineUnderProjectedGeneration
    public let pages =
        ImageToolPageExecutorContract.resolveOnlyWithinPinnedImageRevisionAndDeclaredPageSet
    public let capabilities =
        ImageToolCapabilityExecutorContract.revalidateEveryRequiredCapabilityBeforeWork
    public let ocr =
        ImageToolOCRExecutorContract.extractBoundedTextWithoutUIAndReturnExactTargetOrderedResults
    public let cancellation =
        ImageToolCancellationExecutorContract.checkBeforeWorkAtBoundedIntervalsAndBeforeAtomicStatePublication
    public let plannerIsolation =
        ImageToolPlannerIsolationContract.noImageBytesDecodingOCRRenderingUIOrIO

    public init() {}
}

/// Immutable plan. State intents include exact projected owner state; OCR plans retain no result.
/// Compare-affecting state transitions clear prior results. Executor publishes that transition, then
/// schedules `ImageDifferenceEngine` work bound to projected generation; later result publication must
/// perform its own exact owner-generation compare-and-swap.
public struct ImageToolWorkflowPlan: Hashable, Sendable {
    public let expectedSnapshot: ImageToolSnapshotFingerprint
    public let intent: ImageToolWorkflowIntent
    public let requiredCapabilities: ImageToolCapabilities
    public let projectedSnapshot: ImageToolWorkflowSnapshot?
    public let invalidatesDifferenceResult: Bool
    public let receipt: ImageToolPlanningReceipt
    public let limits: ImageToolWorkflowLimits
    public let executorContract: ImageToolExecutorContract

    fileprivate init(
        expectedSnapshot: ImageToolSnapshotFingerprint,
        intent: ImageToolWorkflowIntent,
        requiredCapabilities: ImageToolCapabilities,
        projectedSnapshot: ImageToolWorkflowSnapshot?,
        invalidatesDifferenceResult: Bool,
        receipt: ImageToolPlanningReceipt,
        limits: ImageToolWorkflowLimits
    ) {
        self.expectedSnapshot = expectedSnapshot
        self.intent = intent
        self.requiredCapabilities = requiredCapabilities
        self.projectedSnapshot = projectedSnapshot
        self.invalidatesDifferenceResult = invalidatesDifferenceResult
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func validateForExecution(
        currentSnapshot: ImageToolWorkflowSnapshot,
        capabilities: ImageToolCapabilities
    ) throws {
        try ImageToolWorkflowPlanner.validateForExecution(
            currentSnapshot,
            capabilities: capabilities,
            plan: self
        )
    }
}

public struct ImageToolPixelPoint: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct ImageToolRGBA8: Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// Pixel data is an executor-provided observation, never read by the projection itself.
public struct ImageToolStatusSample: Hashable, Sendable {
    public let point: ImageToolPixelPoint
    public let color: ImageToolRGBA8

    public init(point: ImageToolPixelPoint, color: ImageToolRGBA8) {
        self.point = point
        self.color = color
    }
}

public struct ImageToolStatusDistance: Hashable, Sendable {
    public let otherPane: ImageToolPane
    public let colorDistance: Double

    public init(otherPane: ImageToolPane, colorDistance: Double) {
        self.otherPane = otherPane
        self.colorDistance = colorDistance
    }
}

public struct ImageToolStatusRequest: Hashable, Sendable {
    /// Exact owner state against which executor captured the pixel observations below.
    public let observedSnapshot: ImageToolSnapshotFingerprint
    public let pane: ImageToolPane
    public let observedImage: ImageToolImageRevision
    public let observedPageIndex: Int
    public let sample: ImageToolStatusSample?
    public let distances: [ImageToolStatusDistance]

    public init(
        observedSnapshot: ImageToolSnapshotFingerprint,
        pane: ImageToolPane,
        observedImage: ImageToolImageRevision,
        observedPageIndex: Int,
        sample: ImageToolStatusSample? = nil,
        distances: [ImageToolStatusDistance] = []
    ) {
        self.observedSnapshot = observedSnapshot
        self.pane = pane
        self.observedImage = observedImage
        self.observedPageIndex = observedPageIndex
        self.sample = sample
        self.distances = distances
    }
}

public struct ImageToolStatusProjection: Hashable, Sendable {
    public let snapshot: ImageToolSnapshotReference
    public let pane: ImageToolPane
    public let image: ImageToolImageRevision
    public let pageIndex: Int
    public let pageNumber: Int
    public let pageCount: Int
    public let width: Int
    public let height: Int
    public let bitsPerPixel: Int
    public let isVector: Bool
    public let transform: ImageToolTransform
    public let zoom: ImageToolZoom
    public let isReadOnly: Bool
    public let isModified: Bool
    public let sample: ImageToolStatusSample?
    public let distances: [ImageToolStatusDistance]
    public let differenceCount: Int?
    public let conflictCount: Int?
    public let selectedDifferenceIndex: Int?
    public let differingPixelCount: Int?
    public let differenceResultIsCurrent: Bool

    fileprivate init(
        snapshot: ImageToolWorkflowSnapshot,
        pane: ImageToolPaneSnapshot,
        page: ImageToolPageDescriptor,
        sample: ImageToolStatusSample?,
        distances: [ImageToolStatusDistance],
        differenceResultIsCurrent: Bool
    ) {
        self.snapshot = ImageToolSnapshotReference(snapshot)
        self.pane = pane.pane
        image = pane.image
        pageIndex = page.index
        pageNumber = page.index + 1
        pageCount = pane.pages.count
        width = page.width
        height = page.height
        bitsPerPixel = page.bitsPerPixel
        isVector = page.isVector
        transform = pane.transform
        zoom = snapshot.controls.zoom
        isReadOnly = pane.isReadOnly
        isModified = pane.isModified
        self.sample = sample
        self.distances = distances
        differenceCount = snapshot.differenceResult?.differenceCount
        conflictCount = snapshot.differenceResult?.conflictCount
        selectedDifferenceIndex = snapshot.differenceResult?.selectedDifferenceIndex
        differingPixelCount = snapshot.differenceResult?.differingPixelCount
        self.differenceResultIsCurrent = differenceResultIsCurrent
    }
}

public struct ImageToolOCRResultDraft: Hashable, Sendable {
    public let target: ImageToolOCRTarget
    public let text: String
    /// Number of line or word observations represented by `text`; text-only results use zero.
    public let itemCount: Int

    public init(target: ImageToolOCRTarget, text: String, itemCount: Int = 0) {
        self.target = target
        self.text = text
        self.itemCount = itemCount
    }
}

public struct ImageToolOCRResult: Hashable, Sendable {
    public let target: ImageToolOCRTarget
    public let text: String
    public let itemCount: Int
    public let utf8ByteCount: Int
    public let contentSHA256: [UInt8]

    fileprivate init(
        draft: ImageToolOCRResultDraft,
        utf8ByteCount: Int,
        contentSHA256: [UInt8]
    ) {
        target = draft.target
        text = draft.text
        itemCount = draft.itemCount
        self.utf8ByteCount = utf8ByteCount
        self.contentSHA256 = contentSHA256
    }
}

public enum ImageToolExecutionEffect: Hashable, Sendable {
    case stateTransition(ImageToolSnapshotReference)
    case ocr(
        results: [ImageToolOCRResult],
        completion: ImageToolOCRCompletionIntent
    )
}

/// Exact result tied to one deterministic planning receipt. No execution timestamp is retained.
public struct ImageToolExecutionReceipt: Hashable, Sendable {
    public let planning: ImageToolPlanningReceipt
    public let effect: ImageToolExecutionEffect

    fileprivate init(planning: ImageToolPlanningReceipt, effect: ImageToolExecutionEffect) {
        self.planning = planning
        self.effect = effect
    }
}

public enum ImageToolExecutionFailureCode: String, CaseIterable, Hashable, Sendable {
    case staleSnapshot
    case missingCapability
    case invalidPlan
    case invalidExecutorResult
    case comparisonFailed
    case ocrFailed
    case resourceLimit
    case internalFailure
}

public enum ImageToolExecutionOutcome: Hashable, Sendable {
    case completed(ImageToolExecutionReceipt)
    case failed(ImageToolExecutionFailureCode)
    case cancelled
}

/// Side-effect implementation supplied by app/platform code. It must validate the exact snapshot and
/// capabilities before work. State publication is one owner compare-and-swap; OCR publishes no state.
public protocol ImageToolPlanExecutor: Sendable {
    func execute(
        _ plan: ImageToolWorkflowPlan,
        validating currentSnapshot: ImageToolWorkflowSnapshot,
        capabilities: ImageToolCapabilities
    ) async -> ImageToolExecutionOutcome
}

public enum ImageToolExecutionReceiptFactory: Sendable {
    public static func stateTransition(
        plan: ImageToolWorkflowPlan,
        currentSnapshot: ImageToolWorkflowSnapshot,
        capabilities: ImageToolCapabilities,
        publishedSnapshot: ImageToolWorkflowSnapshot
    ) throws -> ImageToolExecutionReceipt {
        try plan.validateForExecution(
            currentSnapshot: currentSnapshot,
            capabilities: capabilities
        )
        guard let projected = plan.projectedSnapshot,
            plan.receipt.projected == ImageToolSnapshotReference(publishedSnapshot)
        else {
            throw ImageToolWorkflowError.invalidExecutionResult
        }
        guard
            try ImageToolWorkflowPlanner.snapshotsMatch(
                publishedSnapshot,
                projected,
                limits: plan.limits
            )
        else {
            throw ImageToolWorkflowError.invalidExecutionResult
        }
        return ImageToolExecutionReceipt(
            planning: plan.receipt,
            effect: .stateTransition(ImageToolSnapshotReference(publishedSnapshot))
        )
    }

    public static func ocr(
        plan: ImageToolWorkflowPlan,
        currentSnapshot: ImageToolWorkflowSnapshot,
        capabilities: ImageToolCapabilities,
        results drafts: [ImageToolOCRResultDraft]
    ) throws -> ImageToolExecutionReceipt {
        do {
            try plan.validateForExecution(
                currentSnapshot: currentSnapshot,
                capabilities: capabilities
            )
            guard case .requestOCR(let request) = plan.intent,
                plan.projectedSnapshot == nil,
                drafts.count == request.targets.count
            else {
                throw ImageToolWorkflowError.invalidOCRResult
            }

            var totalBytes = 0
            var totalItems = 0
            var results: [ImageToolOCRResult] = []
            results.reserveCapacity(drafts.count)
            var budget = ImageToolWorkBudget(maximum: plan.limits.maximumWorkUnits)
            for (index, draft) in drafts.enumerated() {
                try budget.consume(1)
                guard draft.target == request.targets[index], draft.itemCount >= 0 else {
                    throw ImageToolWorkflowError.invalidOCRResult
                }
                let hasValidItemCount =
                    switch request.resultKind {
                    case .textOnly: draft.itemCount == 0
                    case .lines, .words: draft.itemCount >= 0
                    }
                guard hasValidItemCount else {
                    throw ImageToolWorkflowError.invalidOCRResult
                }
                let measurement = try ImageToolWorkflowPlanner.measureOCRText(
                    draft.text,
                    maximumBytes: plan.limits.maximumOCRResultUTF8Bytes,
                    cancellationCheckInterval: plan.limits.cancellationCheckInterval,
                    budget: &budget
                )
                totalBytes = try ImageToolWorkflowPlanner.boundedAdd(
                    totalBytes,
                    measurement.byteCount,
                    maximum: plan.limits.maximumOCRResultUTF8Bytes,
                    error: .ocrResultTooLarge(
                        maximumUTF8Bytes: plan.limits.maximumOCRResultUTF8Bytes
                    )
                )
                totalItems = try ImageToolWorkflowPlanner.boundedAdd(
                    totalItems,
                    draft.itemCount,
                    maximum: plan.limits.maximumOCRResultItems,
                    error: .tooManyOCRResultItems(maximum: plan.limits.maximumOCRResultItems)
                )
                results.append(
                    ImageToolOCRResult(
                        draft: draft,
                        utf8ByteCount: measurement.byteCount,
                        contentSHA256: measurement.sha256
                    )
                )
            }
            return ImageToolExecutionReceipt(
                planning: plan.receipt,
                effect: .ocr(results: results, completion: request.completion)
            )
        } catch is CancellationError {
            throw ImageToolWorkflowError.cancelled
        }
    }
}

/// Pure, UI-independent planner and status projector.
public enum ImageToolWorkflowPlanner: Sendable {
    public static func plan(
        _ request: ImageToolWorkflowRequest,
        expecting expectedSnapshot: ImageToolSnapshotReference? = nil
    ) throws -> ImageToolWorkflowPlan {
        do {
            return try makePlan(request, expecting: expectedSnapshot)
        } catch is CancellationError {
            throw ImageToolWorkflowError.cancelled
        }
    }

    public static func projectStatus(
        snapshot: ImageToolWorkflowSnapshot,
        request: ImageToolStatusRequest,
        capabilities: ImageToolCapabilities,
        limits: ImageToolWorkflowLimits = .default
    ) throws -> ImageToolStatusProjection {
        do {
            try checkCancellation()
            try validate(limits)
            var budget = ImageToolWorkBudget(maximum: limits.maximumWorkUnits)
            let validated = try validateSnapshot(snapshot, limits: limits, budget: &budget)
            guard capabilities.contains(.pixelStatus) else {
                throw ImageToolWorkflowError.missingCapability(.pixelStatus)
            }
            let actualFingerprint = try fingerprint(
                validated,
                limits: limits,
                budget: &budget
            )
            try require(
                actualFingerprint,
                equals: request.observedSnapshot
            )
            guard let pane = validated.panes.first(where: { $0.pane == request.pane }),
                let page = pane.selectedPage
            else {
                throw ImageToolWorkflowError.unknownPane(request.pane)
            }
            guard request.observedImage == pane.image,
                request.observedPageIndex == page.index
            else {
                throw ImageToolWorkflowError.snapshotContentsChanged
            }
            if let sample = request.sample {
                guard sample.point.x >= 0, sample.point.y >= 0,
                    sample.point.x < page.width, sample.point.y < page.height
                else {
                    throw ImageToolWorkflowError.invalidStatusSample
                }
            }
            guard request.distances.count < validated.panes.count else {
                throw ImageToolWorkflowError.tooManyItems(maximum: validated.panes.count - 1)
            }
            var seenPanes: Set<ImageToolPane> = []
            for distance in request.distances {
                try checkCancellation()
                guard distance.otherPane != request.pane,
                    validated[distance.otherPane] != nil,
                    seenPanes.insert(distance.otherPane).inserted,
                    distance.colorDistance.isFinite,
                    distance.colorDistance >= 0
                else {
                    throw ImageToolWorkflowError.invalidStatusDistance(distance.otherPane)
                }
                try budget.consume(1)
            }
            let distances = validated.panes.compactMap { pane in
                request.distances.first { $0.otherPane == pane.pane }
            }
            let inputDigest = try differenceInputSHA256(
                validatedSnapshot: validated,
                limits: limits,
                budget: &budget
            )
            return ImageToolStatusProjection(
                snapshot: validated,
                pane: pane,
                page: page,
                sample: request.sample,
                distances: distances,
                differenceResultIsCurrent: validated.differenceResult?.inputSHA256 == inputDigest
            )
        } catch is CancellationError {
            throw ImageToolWorkflowError.cancelled
        }
    }

    /// Digest of execution-relevant selected pages, image revisions, transforms, and diff options.
    public static func differenceInputSHA256(
        for snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits = .default
    ) throws -> [UInt8] {
        do {
            try validate(limits)
            var budget = ImageToolWorkBudget(maximum: limits.maximumWorkUnits)
            let validated = try validateSnapshot(snapshot, limits: limits, budget: &budget)
            return try differenceInputSHA256(
                validatedSnapshot: validated,
                limits: limits,
                budget: &budget
            )
        } catch is CancellationError {
            throw ImageToolWorkflowError.cancelled
        }
    }

    /// Exact owner-state token for executor observations and stale validation.
    public static func snapshotFingerprint(
        for snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits = .default
    ) throws -> ImageToolSnapshotFingerprint {
        do {
            try validate(limits)
            var budget = ImageToolWorkBudget(maximum: limits.maximumWorkUnits)
            let validated = try validateSnapshot(snapshot, limits: limits, budget: &budget)
            return try fingerprint(validated, limits: limits, budget: &budget)
        } catch is CancellationError {
            throw ImageToolWorkflowError.cancelled
        }
    }

    fileprivate static func validateForExecution(
        _ snapshot: ImageToolWorkflowSnapshot,
        capabilities: ImageToolCapabilities,
        plan: ImageToolWorkflowPlan
    ) throws {
        do {
            try checkCancellation()
            try validate(plan.limits)
            guard capabilities.contains(plan.requiredCapabilities) else {
                let missing = plan.requiredCapabilities.values
                    .subtracting(capabilities.values)
                    .sorted { $0.rawValue < $1.rawValue }[0]
                throw ImageToolWorkflowError.missingCapability(missing)
            }
            let actual = ImageToolSnapshotReference(snapshot)
            let expected = plan.expectedSnapshot.reference
            guard actual.identity == expected.identity else {
                throw ImageToolWorkflowError.staleIdentity(
                    expected: expected.identity,
                    actual: actual.identity
                )
            }
            guard actual.revision == expected.revision else {
                throw ImageToolWorkflowError.staleRevision(
                    expected: expected.revision,
                    actual: actual.revision
                )
            }
            guard actual.generation == expected.generation else {
                throw ImageToolWorkflowError.staleGeneration(
                    expected: expected.generation,
                    actual: actual.generation
                )
            }
            var budget = ImageToolWorkBudget(maximum: plan.limits.maximumWorkUnits)
            let validated = try validateSnapshot(snapshot, limits: plan.limits, budget: &budget)
            let fingerprint = try fingerprint(validated, limits: plan.limits, budget: &budget)
            guard fingerprint.stateSHA256 == plan.expectedSnapshot.stateSHA256 else {
                throw ImageToolWorkflowError.snapshotContentsChanged
            }
        } catch is CancellationError {
            throw ImageToolWorkflowError.cancelled
        }
    }

    fileprivate static func snapshotsMatch(
        _ left: ImageToolWorkflowSnapshot,
        _ right: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits
    ) throws -> Bool {
        do {
            try validate(limits)
            var budget = ImageToolWorkBudget(maximum: limits.maximumWorkUnits)
            let left = try validateSnapshot(left, limits: limits, budget: &budget)
            let right = try validateSnapshot(right, limits: limits, budget: &budget)
            guard left.identity == right.identity,
                left.revision == right.revision,
                left.generation == right.generation,
                left.panes.count == right.panes.count,
                left.controls == right.controls,
                left.differenceResult == right.differenceResult
            else {
                return false
            }
            for (leftPane, rightPane) in zip(left.panes, right.panes) {
                try budget.consume(1)
                guard leftPane.pane == rightPane.pane,
                    leftPane.image == rightPane.image,
                    leftPane.pages.count == rightPane.pages.count,
                    leftPane.selectedPageIndex == rightPane.selectedPageIndex,
                    leftPane.transform == rightPane.transform,
                    leftPane.isReadOnly == rightPane.isReadOnly,
                    leftPane.isModified == rightPane.isModified,
                    try stringsMatch(
                        leftPane.displayName,
                        rightPane.displayName,
                        cancellationCheckInterval: limits.cancellationCheckInterval,
                        budget: &budget
                    )
                else {
                    return false
                }
                for (leftPage, rightPage) in zip(leftPane.pages, rightPane.pages) {
                    try budget.consume(1)
                    guard leftPage.index == rightPage.index,
                        leftPage.width == rightPage.width,
                        leftPage.height == rightPage.height,
                        leftPage.bitsPerPixel == rightPage.bitsPerPixel,
                        leftPage.isVector == rightPage.isVector,
                        try stringsMatch(
                            leftPage.label,
                            rightPage.label,
                            cancellationCheckInterval: limits.cancellationCheckInterval,
                            budget: &budget
                        )
                    else {
                        return false
                    }
                }
            }
            return true
        } catch is CancellationError {
            throw ImageToolWorkflowError.cancelled
        }
    }

    private static func stringsMatch(
        _ left: String?,
        _ right: String?,
        cancellationCheckInterval: Int,
        budget: inout ImageToolWorkBudget
    ) throws -> Bool {
        guard let left, let right else { return left == nil && right == nil }
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        var comparisons = 0
        while true {
            let leftByte = leftIterator.next()
            let rightByte = rightIterator.next()
            comparisons += 1
            if comparisons == cancellationCheckInterval {
                try budget.consume(UInt64(comparisons))
                comparisons = 0
            }
            guard leftByte == rightByte else {
                if comparisons > 0 { try budget.consume(UInt64(comparisons)) }
                return false
            }
            if leftByte == nil {
                if comparisons > 0 { try budget.consume(UInt64(comparisons)) }
                return true
            }
        }
    }

    fileprivate static func checkCancellation() throws {
        try Task.checkCancellation()
    }

    fileprivate static func boundedAdd(
        _ left: Int,
        _ right: Int,
        maximum: Int,
        error: ImageToolWorkflowError
    ) throws -> Int {
        let result = left.addingReportingOverflow(right)
        guard !result.overflow, result.partialValue <= maximum else { throw error }
        return result.partialValue
    }

    fileprivate static func measureOCRText(
        _ text: String,
        maximumBytes: Int,
        cancellationCheckInterval: Int,
        budget: inout ImageToolWorkBudget
    ) throws -> (byteCount: Int, sha256: [UInt8]) {
        var hasher = SHA256()
        var chunk = Data()
        chunk.reserveCapacity(cancellationCheckInterval)
        var byteCount = 0
        for byte in text.utf8 {
            byteCount += 1
            guard byte != 0 else { throw ImageToolWorkflowError.invalidOCRResult }
            guard byteCount <= maximumBytes else {
                throw ImageToolWorkflowError.ocrResultTooLarge(
                    maximumUTF8Bytes: maximumBytes
                )
            }
            chunk.append(byte)
            if chunk.count == cancellationCheckInterval {
                try budget.consume(UInt64(chunk.count))
                hasher.update(data: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty { try budget.consume(UInt64(chunk.count)) }
        try checkCancellation()
        if !chunk.isEmpty { hasher.update(data: chunk) }
        return (byteCount, Array(hasher.finalize()))
    }

    private static func require(
        _ actual: ImageToolSnapshotFingerprint,
        equals expected: ImageToolSnapshotFingerprint
    ) throws {
        guard actual.reference.identity == expected.reference.identity else {
            throw ImageToolWorkflowError.staleIdentity(
                expected: expected.reference.identity,
                actual: actual.reference.identity
            )
        }
        guard actual.reference.revision == expected.reference.revision else {
            throw ImageToolWorkflowError.staleRevision(
                expected: expected.reference.revision,
                actual: actual.reference.revision
            )
        }
        guard actual.reference.generation == expected.reference.generation else {
            throw ImageToolWorkflowError.staleGeneration(
                expected: expected.reference.generation,
                actual: actual.reference.generation
            )
        }
        guard actual.stateSHA256 == expected.stateSHA256 else {
            throw ImageToolWorkflowError.snapshotContentsChanged
        }
    }

    private static func makePlan(
        _ request: ImageToolWorkflowRequest,
        expecting expectedSnapshot: ImageToolSnapshotReference?
    ) throws -> ImageToolWorkflowPlan {
        try checkCancellation()
        try validate(request.limits)
        var budget = ImageToolWorkBudget(maximum: request.limits.maximumWorkUnits)
        let snapshot = try validateSnapshot(
            request.snapshot,
            limits: request.limits,
            budget: &budget
        )
        if let expectedSnapshot {
            let actual = ImageToolSnapshotReference(snapshot)
            guard expectedSnapshot.identity == actual.identity else {
                throw ImageToolWorkflowError.staleIdentity(
                    expected: expectedSnapshot.identity,
                    actual: actual.identity
                )
            }
            guard expectedSnapshot.revision == actual.revision else {
                throw ImageToolWorkflowError.staleRevision(
                    expected: expectedSnapshot.revision,
                    actual: actual.revision
                )
            }
            guard expectedSnapshot.generation == actual.generation else {
                throw ImageToolWorkflowError.staleGeneration(
                    expected: expectedSnapshot.generation,
                    actual: actual.generation
                )
            }
        }

        let sourceFingerprint = try fingerprint(
            snapshot,
            limits: request.limits,
            budget: &budget
        )
        let prepared = try prepare(
            request.intent,
            snapshot: snapshot,
            limits: request.limits,
            budget: &budget
        )
        guard request.availableCapabilities.contains(prepared.requiredCapabilities) else {
            let missing = prepared.requiredCapabilities.values
                .subtracting(request.availableCapabilities.values)
                .sorted { $0.rawValue < $1.rawValue }[0]
            throw ImageToolWorkflowError.missingCapability(missing)
        }

        let payload = try canonicalPlanData(
            source: sourceFingerprint,
            intent: prepared.intent,
            requiredCapabilities: prepared.requiredCapabilities,
            projectedSnapshot: prepared.projectedSnapshot,
            invalidatesDifferenceResult: prepared.invalidatesDifferenceResult,
            limits: request.limits,
            maximumWorkUnits: budget.remaining
        )
        try budget.consume(UInt64(payload.count))
        try checkCancellation()
        let digest = try sha256(
            payload,
            cancellationCheckInterval: request.limits.cancellationCheckInterval
        )
        let receipt = ImageToolPlanningReceipt(
            kind: prepared.kind,
            source: sourceFingerprint.reference,
            projected: prepared.projectedSnapshot.map(ImageToolSnapshotReference.init),
            planSHA256: digest,
            canonicalPlanByteCount: payload.count,
            estimatedWorkUnits: budget.consumed
        )
        return ImageToolWorkflowPlan(
            expectedSnapshot: sourceFingerprint,
            intent: prepared.intent,
            requiredCapabilities: prepared.requiredCapabilities,
            projectedSnapshot: prepared.projectedSnapshot,
            invalidatesDifferenceResult: prepared.invalidatesDifferenceResult,
            receipt: receipt,
            limits: request.limits
        )
    }

    private struct PreparedIntent {
        let kind: ImageToolPlanningReceiptKind
        let intent: ImageToolWorkflowIntent
        let requiredCapabilities: ImageToolCapabilities
        let projectedSnapshot: ImageToolWorkflowSnapshot?
        let invalidatesDifferenceResult: Bool
    }

    private static func prepare(
        _ intent: ImageToolWorkflowIntent,
        snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> PreparedIntent {
        switch intent {
        case .selectPages(let selection):
            let canonical = try validate(
                selection,
                snapshot: snapshot,
                limits: limits,
                budget: &budget
            )
            let panes = snapshot.panes.map { pane in
                let page = canonical.selections.first { $0.pane == pane.pane }!.pageIndex
                return ImageToolPaneSnapshot(
                    pane: pane.pane,
                    image: pane.image,
                    pages: pane.pages,
                    selectedPageIndex: page,
                    transform: pane.transform,
                    displayName: pane.displayName,
                    isReadOnly: pane.isReadOnly,
                    isModified: pane.isModified
                )
            }
            let controls = ImageToolControlState(
                pageSelectionMode: canonical.mode,
                differences: snapshot.controls.differences,
                zoom: snapshot.controls.zoom,
                overlay: snapshot.controls.overlay,
                wipe: snapshot.controls.wipe,
                animation: snapshot.controls.animation
            )
            let comparisonChanged = zip(panes, snapshot.panes).contains { pair in
                pair.0.selectedPageIndex != pair.1.selectedPageIndex
            }
            let selectionModeChanged = canonical.mode != snapshot.controls.pageSelectionMode
            guard comparisonChanged || selectionModeChanged else {
                throw ImageToolWorkflowError.noChange
            }
            var required = requiredCapabilities(
                for: controls,
                panes: panes,
                includesComparison: comparisonChanged
            )
            required.insert(
                canonical.mode == .synchronized
                    ? .synchronizedPageSelection
                    : .independentPageSelection
            )
            let projected = try projectedSnapshot(
                from: snapshot,
                panes: panes,
                controls: controls,
                invalidatesDifferenceResult: comparisonChanged
            )
            if comparisonChanged { try consumeSelectedPixelWork(projected, budget: &budget) }
            return PreparedIntent(
                kind: .pageSelection,
                intent: .selectPages(canonical),
                requiredCapabilities: ImageToolCapabilities(required),
                projectedSnapshot: projected,
                invalidatesDifferenceResult: comparisonChanged
            )

        case .setDifferenceOptions(let options):
            try validate(options)
            let controls = ImageToolControlState(
                pageSelectionMode: snapshot.controls.pageSelectionMode,
                differences: options,
                zoom: snapshot.controls.zoom,
                overlay: snapshot.controls.overlay,
                wipe: snapshot.controls.wipe,
                animation: snapshot.controls.animation
            )
            guard options != snapshot.controls.differences else {
                throw ImageToolWorkflowError.noChange
            }
            let comparisonChanged =
                comparisonOptions(options)
                != comparisonOptions(snapshot.controls.differences)
            var required = requiredCapabilities(
                for: controls,
                panes: snapshot.panes,
                includesComparison: comparisonChanged
            )
            if options.showsDifferences != snapshot.controls.differences.showsDifferences {
                required.insert(.differenceVisibility)
            }
            let projected = try projectedSnapshot(
                from: snapshot,
                controls: controls,
                invalidatesDifferenceResult: comparisonChanged
            )
            if comparisonChanged { try consumeSelectedPixelWork(projected, budget: &budget) }
            return PreparedIntent(
                kind: .differenceOptions,
                intent: .setDifferenceOptions(options),
                requiredCapabilities: ImageToolCapabilities(required),
                projectedSnapshot: projected,
                invalidatesDifferenceResult: comparisonChanged
            )

        case .setTransforms(let transforms):
            guard !transforms.isEmpty else { throw ImageToolWorkflowError.noChange }
            guard transforms.count <= limits.maximumItemCount else {
                throw ImageToolWorkflowError.tooManyItems(maximum: limits.maximumItemCount)
            }
            var seen: Set<ImageToolPane> = []
            var canonical: [ImageToolPaneTransform] = []
            canonical.reserveCapacity(transforms.count)
            var required: Set<ImageToolCapability> = []
            for item in transforms {
                try checkCancellation()
                guard snapshot[item.pane] != nil else {
                    throw ImageToolWorkflowError.unknownPane(item.pane)
                }
                guard seen.insert(item.pane).inserted else {
                    throw ImageToolWorkflowError.duplicateTransform(item.pane)
                }
                try validateIntentTransform(item.transform, pane: item.pane)
                if item.transform.clockwiseQuarterTurns != 0 {
                    required.insert(.quarterTurnRotation)
                }
                if item.transform.flipsHorizontally { required.insert(.horizontalFlip) }
                if item.transform.flipsVertically { required.insert(.verticalFlip) }
                canonical.append(item)
                try budget.consume(1)
            }
            canonical = snapshot.panes.compactMap { pane in
                canonical.first { $0.pane == pane.pane }
            }
            let panes = snapshot.panes.map { pane in
                let transform =
                    canonical.first { $0.pane == pane.pane }?.transform
                    ?? pane.transform
                return ImageToolPaneSnapshot(
                    pane: pane.pane,
                    image: pane.image,
                    pages: pane.pages,
                    selectedPageIndex: pane.selectedPageIndex,
                    transform: transform,
                    displayName: pane.displayName,
                    isReadOnly: pane.isReadOnly,
                    isModified: pane.isModified
                )
            }
            let transformsChanged = canonical.contains { item in
                snapshot[item.pane]?.transform != item.transform
            }
            guard transformsChanged else { throw ImageToolWorkflowError.noChange }
            required.formUnion(
                requiredCapabilities(
                    for: snapshot.controls,
                    panes: panes,
                    includesComparison: true
                )
            )
            let projected = try projectedSnapshot(
                from: snapshot,
                panes: panes,
                invalidatesDifferenceResult: true
            )
            try consumeSelectedPixelWork(projected, budget: &budget)
            return PreparedIntent(
                kind: .transforms,
                intent: .setTransforms(canonical),
                requiredCapabilities: ImageToolCapabilities(required),
                projectedSnapshot: projected,
                invalidatesDifferenceResult: true
            )

        case .setZoom(let zoom):
            try validate(zoom)
            let controls = ImageToolControlState(
                pageSelectionMode: snapshot.controls.pageSelectionMode,
                differences: snapshot.controls.differences,
                zoom: zoom,
                overlay: snapshot.controls.overlay,
                wipe: snapshot.controls.wipe,
                animation: snapshot.controls.animation
            )
            guard controls != snapshot.controls else { throw ImageToolWorkflowError.noChange }
            let projected = try projectedSnapshot(from: snapshot, controls: controls)
            return PreparedIntent(
                kind: .zoom,
                intent: .setZoom(zoom),
                requiredCapabilities: ImageToolCapabilities(
                    requiredCapabilities(
                        for: controls,
                        panes: snapshot.panes,
                        includesComparison: false
                    )
                ),
                projectedSnapshot: projected,
                invalidatesDifferenceResult: false
            )

        case .setOverlay(let overlay):
            try validate(overlay)
            let controls = ImageToolControlState(
                pageSelectionMode: snapshot.controls.pageSelectionMode,
                differences: snapshot.controls.differences,
                zoom: snapshot.controls.zoom,
                overlay: overlay,
                wipe: snapshot.controls.wipe,
                animation: snapshot.controls.animation
            )
            guard controls != snapshot.controls else { throw ImageToolWorkflowError.noChange }
            let required = requiredCapabilities(
                for: controls,
                panes: snapshot.panes,
                includesComparison: false
            )
            let projected = try projectedSnapshot(from: snapshot, controls: controls)
            return PreparedIntent(
                kind: .overlay,
                intent: .setOverlay(overlay),
                requiredCapabilities: ImageToolCapabilities(required),
                projectedSnapshot: projected,
                invalidatesDifferenceResult: false
            )

        case .setWipe(let wipe):
            try validate(wipe)
            let controls = ImageToolControlState(
                pageSelectionMode: snapshot.controls.pageSelectionMode,
                differences: snapshot.controls.differences,
                zoom: snapshot.controls.zoom,
                overlay: snapshot.controls.overlay,
                wipe: wipe,
                animation: snapshot.controls.animation
            )
            guard controls != snapshot.controls else { throw ImageToolWorkflowError.noChange }
            let required = requiredCapabilities(
                for: controls,
                panes: snapshot.panes,
                includesComparison: false
            )
            let projected = try projectedSnapshot(from: snapshot, controls: controls)
            return PreparedIntent(
                kind: .wipe,
                intent: .setWipe(wipe),
                requiredCapabilities: ImageToolCapabilities(required),
                projectedSnapshot: projected,
                invalidatesDifferenceResult: false
            )

        case .setAnimation(let animation):
            try validate(animation)
            let controls = ImageToolControlState(
                pageSelectionMode: snapshot.controls.pageSelectionMode,
                differences: snapshot.controls.differences,
                zoom: snapshot.controls.zoom,
                overlay: snapshot.controls.overlay,
                wipe: snapshot.controls.wipe,
                animation: animation
            )
            guard controls != snapshot.controls else { throw ImageToolWorkflowError.noChange }
            let required = requiredCapabilities(
                for: controls,
                panes: snapshot.panes,
                includesComparison: false
            )
            let projected = try projectedSnapshot(from: snapshot, controls: controls)
            return PreparedIntent(
                kind: .animation,
                intent: .setAnimation(animation),
                requiredCapabilities: ImageToolCapabilities(required),
                projectedSnapshot: projected,
                invalidatesDifferenceResult: false
            )

        case .requestOCR(let request):
            let canonical = try validate(
                request,
                snapshot: snapshot,
                limits: limits,
                budget: &budget
            )
            var required: Set<ImageToolCapability> = [.ocrText]
            switch canonical.resultKind {
            case .textOnly: break
            case .lines: required.insert(.ocrLineObservations)
            case .words: required.insert(.ocrWordObservations)
            }
            if !canonical.languageHints.isEmpty { required.insert(.ocrLanguageHints) }
            try consumeOCRPixelWork(canonical, snapshot: snapshot, budget: &budget)
            return PreparedIntent(
                kind: .ocr,
                intent: .requestOCR(canonical),
                requiredCapabilities: ImageToolCapabilities(required),
                projectedSnapshot: nil,
                invalidatesDifferenceResult: false
            )
        }
    }

    private static func projectedSnapshot(
        from snapshot: ImageToolWorkflowSnapshot,
        panes: [ImageToolPaneSnapshot]? = nil,
        controls: ImageToolControlState? = nil,
        invalidatesDifferenceResult: Bool = false
    ) throws -> ImageToolWorkflowSnapshot {
        let next = snapshot.generation.addingReportingOverflow(1)
        guard !next.overflow else { throw ImageToolWorkflowError.generationOverflow }
        return ImageToolWorkflowSnapshot(
            identity: snapshot.identity,
            revision: snapshot.revision,
            generation: next.partialValue,
            panes: panes ?? snapshot.panes,
            controls: controls ?? snapshot.controls,
            differenceResult: invalidatesDifferenceResult ? nil : snapshot.differenceResult
        )
    }

    private static func comparisonOptions(
        _ options: ImageToolDifferenceOptions
    ) -> ImageToolComparisonOptionProjection {
        ImageToolComparisonOptionProjection(
            pixelComparison: options.pixelComparison,
            differenceBlockSize: options.differenceBlockSize,
            colorDistanceThreshold: options.colorDistanceThreshold,
            insertionDetection: options.insertionDetection
        )
    }

    private static func requiredCapabilities(
        for controls: ImageToolControlState,
        panes: [ImageToolPaneSnapshot] = [],
        includesComparison: Bool
    ) -> Set<ImageToolCapability> {
        var result: Set<ImageToolCapability> = []
        result.insert(controls.zoom.mode == .fixed ? .fixedZoom : .fitZoom)
        switch controls.overlay.mode {
        case .none: break
        case .xor: result.insert(.xorOverlay)
        case .alphaBlend: result.insert(.alphaOverlay)
        case .alphaBlendAnimation:
            result.formUnion([.alphaOverlay, .animatedOverlay])
        }
        switch controls.wipe.mode {
        case .none: break
        case .vertical: result.insert(.verticalWipe)
        case .horizontal: result.insert(.horizontalWipe)
        }
        if controls.animation.blinksDifferences { result.insert(.differenceBlink) }
        if includesComparison {
            result.formUnion([
                .normalizedPixelComparison,
                .differenceBlockSize,
                .colorDistanceThreshold
            ])
            switch controls.differences.insertionDetection {
            case .none: break
            case .vertical: result.insert(.verticalInsertionDetection)
            case .horizontal: result.insert(.horizontalInsertionDetection)
            }
            for pane in panes {
                if pane.transform.clockwiseQuarterTurns != 0 {
                    result.insert(.quarterTurnRotation)
                }
                if pane.transform.flipsHorizontally { result.insert(.horizontalFlip) }
                if pane.transform.flipsVertically { result.insert(.verticalFlip) }
            }
        }
        result.insert(
            controls.pageSelectionMode == .synchronized
                ? .synchronizedPageSelection
                : .independentPageSelection
        )
        for pane in panes {
            if pane.transform.clockwiseQuarterTurns != 0 {
                result.insert(.quarterTurnRotation)
            }
            if pane.transform.flipsHorizontally { result.insert(.horizontalFlip) }
            if pane.transform.flipsVertically { result.insert(.verticalFlip) }
        }
        if controls.differences.showsDifferences { result.insert(.differenceVisibility) }
        return result
    }

    private static func validate(_ limits: ImageToolWorkflowLimits) throws {
        let values: [(Bool, ImageToolWorkflowLimit)] = [
            ((2...ImageToolWorkflowLimits.hardMaximumPaneCount).contains(limits.maximumPaneCount), .panes),
            ((1...ImageToolWorkflowLimits.hardMaximumPagesPerPane).contains(limits.maximumPagesPerPane), .pagesPerPane),
            ((2...ImageToolWorkflowLimits.hardMaximumTotalPages).contains(limits.maximumTotalPages), .totalPages),
            ((1...ImageToolWorkflowLimits.hardMaximumItemCount).contains(limits.maximumItemCount), .items),
            ((1...ImageToolWorkflowLimits.hardMaximumStringUTF8Bytes).contains(limits.maximumStringUTF8Bytes), .stringUTF8Bytes),
            ((1...ImageToolWorkflowLimits.hardMaximumTotalStringUTF8Bytes).contains(limits.maximumTotalStringUTF8Bytes), .totalStringUTF8Bytes),
            ((1...ImageToolWorkflowLimits.hardMaximumPlanBytes).contains(limits.maximumPlanBytes), .planBytes),
            ((1...ImageToolWorkflowLimits.hardMaximumWorkUnits).contains(limits.maximumWorkUnits), .workUnits),
            ((1...ImageToolWorkflowLimits.hardMaximumOCRResultUTF8Bytes).contains(limits.maximumOCRResultUTF8Bytes), .ocrResultUTF8Bytes),
            ((1...ImageToolWorkflowLimits.hardMaximumOCRResultItems).contains(limits.maximumOCRResultItems), .ocrResultItems),
            ((1...ImageToolWorkflowLimits.hardMaximumCancellationCheckInterval).contains(limits.cancellationCheckInterval), .cancellationCheckInterval)
        ]
        for (isValid, limit) in values where !isValid {
            throw ImageToolWorkflowError.invalidLimit(limit)
        }
        guard limits.maximumPaneCount <= limits.maximumItemCount,
            limits.maximumPagesPerPane <= limits.maximumTotalPages,
            limits.maximumTotalPages <= limits.maximumItemCount,
            limits.maximumStringUTF8Bytes <= limits.maximumTotalStringUTF8Bytes
        else {
            throw ImageToolWorkflowError.invalidLimit(.items)
        }
    }

    private static func validateSnapshot(
        _ snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> ImageToolWorkflowSnapshot {
        guard snapshot.panes.count == 2 || snapshot.panes.count == 3,
            snapshot.panes.count <= limits.maximumPaneCount
        else {
            throw ImageToolWorkflowError.invalidSnapshot(pane: nil, issue: .invalidPaneCount)
        }
        var panes: [ImageToolPaneSnapshot] = []
        panes.reserveCapacity(snapshot.panes.count)
        var seen: Set<ImageToolPane> = []
        var totalPages = 0
        var totalStrings = 0
        for pane in snapshot.panes.sorted(by: { $0.pane < $1.pane }) {
            try checkCancellation()
            guard seen.insert(pane.pane).inserted else {
                throw ImageToolWorkflowError.invalidSnapshot(
                    pane: pane.pane,
                    issue: .duplicatePane
                )
            }
            guard pane.image.contentSHA256.count == SHA256.Digest.byteCount else {
                throw ImageToolWorkflowError.invalidSnapshot(
                    pane: pane.pane,
                    issue: .invalidImageDigest
                )
            }
            guard !pane.pages.isEmpty else {
                throw ImageToolWorkflowError.invalidSnapshot(
                    pane: pane.pane,
                    issue: .emptyPageSet
                )
            }
            guard pane.pages.count <= limits.maximumPagesPerPane else {
                throw ImageToolWorkflowError.invalidSnapshot(
                    pane: pane.pane,
                    issue: .tooManyPages
                )
            }
            totalPages = try boundedAdd(
                totalPages,
                pane.pages.count,
                maximum: limits.maximumTotalPages,
                error: .invalidSnapshot(pane: pane.pane, issue: .tooManyPages)
            )
            var pages: [ImageToolPageDescriptor] = []
            for (index, page) in pane.pages.enumerated() {
                if index.isMultiple(of: limits.cancellationCheckInterval) {
                    try checkCancellation()
                }
                guard page.index == index else {
                    throw ImageToolWorkflowError.invalidSnapshot(
                        pane: pane.pane,
                        issue: .noncontiguousPageIndices
                    )
                }
                guard page.width > 0, page.height > 0 else {
                    throw ImageToolWorkflowError.invalidSnapshot(
                        pane: pane.pane,
                        issue: .invalidPageDimensions
                    )
                }
                guard page.bitsPerPixel > 0, page.bitsPerPixel <= 1_024 else {
                    throw ImageToolWorkflowError.invalidSnapshot(
                        pane: pane.pane,
                        issue: .invalidBitsPerPixel
                    )
                }
                var label: String?
                if let pageLabel = page.label {
                    (label, totalStrings) = try validateString(
                        pageLabel,
                        total: totalStrings,
                        limits: limits,
                        budget: &budget
                    )
                }
                pages.append(
                    ImageToolPageDescriptor(
                        index: page.index,
                        width: page.width,
                        height: page.height,
                        bitsPerPixel: page.bitsPerPixel,
                        isVector: page.isVector,
                        label: label
                    )
                )
                try budget.consume(1)
            }
            guard pane.pages.indices.contains(pane.selectedPageIndex) else {
                throw ImageToolWorkflowError.invalidSnapshot(
                    pane: pane.pane,
                    issue: .selectedPageMissing
                )
            }
            try validate(pane.transform, pane: pane.pane)
            var displayName: String?
            if let paneDisplayName = pane.displayName {
                (displayName, totalStrings) = try validateString(
                    paneDisplayName,
                    total: totalStrings,
                    limits: limits,
                    budget: &budget
                )
            }
            panes.append(
                ImageToolPaneSnapshot(
                    pane: pane.pane,
                    image: pane.image,
                    pages: pages,
                    selectedPageIndex: pane.selectedPageIndex,
                    transform: pane.transform,
                    displayName: displayName,
                    isReadOnly: pane.isReadOnly,
                    isModified: pane.isModified
                )
            )
        }
        let expectedPanes: [ImageToolPane] =
            panes.count == 2 ? [.left, .right] : [.left, .middle, .right]
        guard panes.map(\.pane) == expectedPanes else {
            throw ImageToolWorkflowError.invalidSnapshot(pane: nil, issue: .invalidPaneSet)
        }
        try validate(snapshot.controls)
        if snapshot.controls.pageSelectionMode == .synchronized {
            let pages = Set(panes.map(\.selectedPageIndex))
            guard pages.count == 1 else {
                throw ImageToolWorkflowError.invalidSnapshot(
                    pane: nil,
                    issue: .invalidControlState
                )
            }
        }
        if let result = snapshot.differenceResult {
            guard result.inputSHA256.count == SHA256.Digest.byteCount,
                result.resultSHA256.count == SHA256.Digest.byteCount,
                result.differenceCount >= 0,
                result.conflictCount >= 0,
                result.conflictCount <= result.differenceCount,
                result.differingPixelCount >= 0,
                result.selectedDifferenceIndex.map({
                    $0 >= 0 && $0 < result.differenceCount
                }) ?? true
            else {
                throw ImageToolWorkflowError.invalidSnapshot(
                    pane: nil,
                    issue: .invalidDifferenceResult
                )
            }
        }
        return ImageToolWorkflowSnapshot(
            identity: snapshot.identity,
            revision: snapshot.revision,
            generation: snapshot.generation,
            panes: panes,
            controls: snapshot.controls,
            differenceResult: snapshot.differenceResult
        )
    }

    private static func validate(_ controls: ImageToolControlState) throws {
        try validate(controls.differences)
        try validate(controls.zoom)
        try validate(controls.overlay)
        try validate(controls.wipe)
        try validate(controls.animation)
    }

    private static func validate(_ options: ImageToolDifferenceOptions) throws {
        guard (1...64).contains(options.differenceBlockSize) else {
            throw ImageToolWorkflowError.invalidDifferenceBlockSize(
                options.differenceBlockSize
            )
        }
        guard options.colorDistanceThreshold.isFinite,
            (0...442).contains(options.colorDistanceThreshold)
        else {
            throw ImageToolWorkflowError.invalidColorDistanceThreshold(
                options.colorDistanceThreshold
            )
        }
        guard options.pixelComparison.maximumCanvasPixels > 0,
            options.pixelComparison.maximumRegions > 0,
            options.pixelComparison.maximumQueuedPixels > 0
        else {
            throw ImageToolWorkflowError.invalidPixelComparisonOptions
        }
    }

    private static func validate(_ zoom: ImageToolZoom) throws {
        guard zoom.scale.isFinite, (0.01...8).contains(zoom.scale) else {
            throw ImageToolWorkflowError.invalidZoom(zoom.scale)
        }
    }

    private static func validate(_ overlay: ImageToolOverlay) throws {
        guard overlay.alpha.isFinite, (0...1).contains(overlay.alpha) else {
            throw ImageToolWorkflowError.invalidOverlayAlpha(overlay.alpha)
        }
    }

    private static func validate(_ wipe: ImageToolWipe) throws {
        guard wipe.position.isFinite, (0...1).contains(wipe.position) else {
            throw ImageToolWorkflowError.invalidWipePosition(wipe.position)
        }
    }

    private static func validate(_ animation: ImageToolAnimation) throws {
        for value in [animation.blinkIntervalMilliseconds, animation.overlayIntervalMilliseconds] {
            guard (200...8_000).contains(value) else {
                throw ImageToolWorkflowError.invalidAnimationInterval(value)
            }
        }
    }

    private static func validate(
        _ transform: ImageToolTransform,
        pane: ImageToolPane
    ) throws {
        guard (0...3).contains(transform.clockwiseQuarterTurns) else {
            throw ImageToolWorkflowError.invalidSnapshot(pane: pane, issue: .invalidTransform)
        }
    }

    private static func validateIntentTransform(
        _ transform: ImageToolTransform,
        pane: ImageToolPane
    ) throws {
        guard (0...3).contains(transform.clockwiseQuarterTurns) else {
            throw ImageToolWorkflowError.invalidTransform(pane)
        }
    }

    private static func validate(
        _ selection: ImageToolPageSelection,
        snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> ImageToolPageSelection {
        guard selection.selections.count <= limits.maximumItemCount else {
            throw ImageToolWorkflowError.tooManyItems(maximum: limits.maximumItemCount)
        }
        var seen: Set<ImageToolPane> = []
        for item in selection.selections {
            try checkCancellation()
            guard snapshot[item.pane] != nil else {
                throw ImageToolWorkflowError.unknownPane(item.pane)
            }
            guard seen.insert(item.pane).inserted else {
                throw ImageToolWorkflowError.duplicatePaneSelection(item.pane)
            }
            try budget.consume(1)
        }
        guard selection.selections.count == snapshot.panes.count else {
            if let pane = snapshot.panes.first(where: { !seen.contains($0.pane) }) {
                throw ImageToolWorkflowError.missingPaneSelection(pane.pane)
            }
            throw ImageToolWorkflowError.tooManyItems(maximum: snapshot.panes.count)
        }
        var selections: [ImageToolPanePageSelection] = []
        selections.reserveCapacity(selection.selections.count)
        for pane in snapshot.panes {
            try checkCancellation()
            guard let item = selection.selections.first(where: { $0.pane == pane.pane }) else {
                throw ImageToolWorkflowError.missingPaneSelection(pane.pane)
            }
            guard pane.pages.indices.contains(item.pageIndex) else {
                throw ImageToolWorkflowError.pageNotFound(
                    pane: item.pane,
                    pageIndex: item.pageIndex
                )
            }
            selections.append(item)
        }
        if selection.mode == .synchronized,
            Set(selections.map(\.pageIndex)).count != 1
        {
            throw ImageToolWorkflowError.synchronizedPagesDiffer
        }
        return ImageToolPageSelection(mode: selection.mode, selections: selections)
    }

    private static func validate(
        _ request: ImageToolOCRRequestIntent,
        snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> ImageToolOCRRequestIntent {
        guard !request.targets.isEmpty else { throw ImageToolWorkflowError.emptyOCRTargets }
        guard request.targets.count <= limits.maximumItemCount else {
            throw ImageToolWorkflowError.tooManyItems(maximum: limits.maximumItemCount)
        }
        var seenTargets: Set<ImageToolOCRTarget> = []
        for target in request.targets {
            try checkCancellation()
            guard seenTargets.insert(target).inserted else {
                throw ImageToolWorkflowError.duplicateOCRTarget(target)
            }
            guard let pane = snapshot[target.pane] else {
                throw ImageToolWorkflowError.unknownPane(target.pane)
            }
            guard pane.pages.indices.contains(target.pageIndex) else {
                throw ImageToolWorkflowError.pageNotFound(
                    pane: target.pane,
                    pageIndex: target.pageIndex
                )
            }
            try budget.consume(1)
        }
        let targets = try cancellationAwareSorted(
            request.targets,
            by: {
                ($0.pane.rawValue, $0.pageIndex) < ($1.pane.rawValue, $1.pageIndex)
            },
            cancellationCheckInterval: limits.cancellationCheckInterval,
            budget: &budget
        )
        var totalStrings = try snapshotStringUTF8ByteCount(
            snapshot,
            limits: limits,
            budget: &budget
        )
        var hints: [String] = []
        var seenHints: Set<String> = []
        for hint in request.languageHints {
            try checkCancellation()
            let normalized = try normalizeLanguageHint(
                hint,
                limits: limits,
                budget: &budget
            )
            if seenHints.insert(normalized).inserted {
                guard hints.count < limits.maximumItemCount - request.targets.count else {
                    throw ImageToolWorkflowError.tooManyItems(maximum: limits.maximumItemCount)
                }
                totalStrings = try boundedAdd(
                    totalStrings,
                    normalized.utf8.count,
                    maximum: limits.maximumTotalStringUTF8Bytes,
                    error: .totalStringsTooLarge(
                        maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
                    )
                )
                hints.append(normalized)
            }
        }
        hints = try cancellationAwareSortedStrings(
            hints,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            budget: &budget
        )
        return ImageToolOCRRequestIntent(
            targets: targets,
            resultKind: request.resultKind,
            languageHints: hints,
            completion: request.completion
        )
    }

    private static func normalizeLanguageHint(
        _ value: String,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(limits.maximumStringUTF8Bytes, 256))
        for byte in value.utf8 {
            if bytes.count.isMultiple(of: limits.cancellationCheckInterval) {
                try checkCancellation()
            }
            guard byte != 0 else { throw ImageToolWorkflowError.invalidString }
            guard bytes.count < limits.maximumStringUTF8Bytes else {
                throw ImageToolWorkflowError.stringTooLarge(
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            bytes.append(byte)
            if bytes.count.isMultiple(of: limits.cancellationCheckInterval) {
                try budget.consume(UInt64(limits.cancellationCheckInterval))
            }
        }
        let unchargedBytes = bytes.count % limits.cancellationCheckInterval
        if unchargedBytes > 0 { try budget.consume(UInt64(unchargedBytes)) }
        guard let normalized = canonicalLanguageTag(bytes) else {
            throw ImageToolWorkflowError.invalidLanguageHint(value)
        }
        try budget.consume(UInt64(normalized.utf8.count))
        return normalized
    }

    private static func canonicalLanguageTag(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty,
            bytes.first != 45,
            bytes.last != 45,
            bytes.allSatisfy({ isASCIIAlphanumeric($0) || $0 == 45 })
        else {
            return nil
        }
        let lowercased = bytes.map(asciiLowercased)
        let lowercasedTag = String(decoding: lowercased, as: UTF8.self)
        let grandfathered: Set<String> = [
            "art-lojban", "cel-gaulish", "en-gb-oed", "i-ami", "i-bnn", "i-default",
            "i-enochian", "i-hak", "i-klingon", "i-lux", "i-mingo", "i-navajo",
            "i-pwn", "i-tao", "i-tay", "i-tsu", "no-bok", "no-nyn", "sgn-be-fr",
            "sgn-be-nl", "sgn-ch-de", "zh-guoyu", "zh-hakka", "zh-min", "zh-min-nan",
            "zh-xiang"
        ]
        if grandfathered.contains(lowercasedTag) { return lowercasedTag }

        let subtags = lowercased.split(separator: 45, omittingEmptySubsequences: false)
        guard !subtags.contains(where: \.isEmpty) else { return nil }
        if subtags[0].count == 1, subtags[0].first == 120 {
            guard subtags.count > 1,
                subtags.dropFirst().allSatisfy({ isAlphanumericSubtag($0, lengths: 1...8) })
            else {
                return nil
            }
            return lowercasedTag
        }

        var index = 0
        let language = subtags[index]
        guard isAlphaSubtag(language, lengths: 2...8) else {
            return nil
        }
        index += 1
        var canonical: [[UInt8]] = [Array(language)]
        if (2...3).contains(language.count) {
            var extlangCount = 0
            while index < subtags.count,
                extlangCount < 3,
                isAlphaSubtag(subtags[index], lengths: 3...3)
            {
                canonical.append(Array(subtags[index]))
                index += 1
                extlangCount += 1
            }
        }
        if index < subtags.count, isAlphaSubtag(subtags[index], lengths: 4...4) {
            var script = Array(subtags[index])
            script[0] = asciiUppercased(script[0])
            canonical.append(script)
            index += 1
        }
        if index < subtags.count,
            isAlphaSubtag(subtags[index], lengths: 2...2)
                || isDigitSubtag(subtags[index], lengths: 3...3)
        {
            canonical.append(Array(subtags[index]).map(asciiUppercased))
            index += 1
        }

        var variants: Set<String> = []
        while index < subtags.count, isVariantSubtag(subtags[index]) {
            let variant = String(decoding: subtags[index], as: UTF8.self)
            guard variants.insert(variant).inserted else { return nil }
            canonical.append(Array(subtags[index]))
            index += 1
        }
        var extensionSingletons: Set<UInt8> = []
        var extensions: [(singleton: UInt8, subtags: [[UInt8]])] = []
        while index < subtags.count,
            subtags[index].count == 1,
            subtags[index].first != 120,
            isASCIIAlphanumeric(subtags[index].first!)
        {
            let singleton = subtags[index].first!
            guard extensionSingletons.insert(singleton).inserted else { return nil }
            index += 1
            var extensionSubtags: [[UInt8]] = []
            while index < subtags.count,
                isAlphanumericSubtag(subtags[index], lengths: 2...8)
            {
                extensionSubtags.append(Array(subtags[index]))
                index += 1
            }
            guard !extensionSubtags.isEmpty else { return nil }
            extensions.append((singleton, extensionSubtags))
        }
        for item in extensions.sorted(by: { $0.singleton < $1.singleton }) {
            canonical.append([item.singleton])
            canonical.append(contentsOf: item.subtags)
        }
        if index < subtags.count, subtags[index].count == 1, subtags[index].first == 120 {
            canonical.append([120])
            index += 1
            let firstPrivateSubtag = index
            while index < subtags.count,
                isAlphanumericSubtag(subtags[index], lengths: 1...8)
            {
                canonical.append(Array(subtags[index]))
                index += 1
            }
            guard index > firstPrivateSubtag else { return nil }
        }
        guard index == subtags.count else { return nil }
        return canonical.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "-")
    }

    private static func isVariantSubtag(_ bytes: ArraySlice<UInt8>) -> Bool {
        isAlphanumericSubtag(bytes, lengths: 5...8)
            || (bytes.count == 4 && isASCIIDigit(bytes.first!)
                && bytes.dropFirst().allSatisfy(isASCIIAlphanumeric))
    }

    private static func isAlphaSubtag(
        _ bytes: ArraySlice<UInt8>,
        lengths: ClosedRange<Int>
    ) -> Bool {
        lengths.contains(bytes.count) && bytes.allSatisfy(isASCIIAlpha)
    }

    private static func isDigitSubtag(
        _ bytes: ArraySlice<UInt8>,
        lengths: ClosedRange<Int>
    ) -> Bool {
        lengths.contains(bytes.count) && bytes.allSatisfy(isASCIIDigit)
    }

    private static func isAlphanumericSubtag(
        _ bytes: ArraySlice<UInt8>,
        lengths: ClosedRange<Int>
    ) -> Bool {
        lengths.contains(bytes.count) && bytes.allSatisfy(isASCIIAlphanumeric)
    }

    private static func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (97...122).contains(byte)
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        isASCIIAlpha(asciiLowercased(byte)) || isASCIIDigit(byte)
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (65...90).contains(byte) ? byte + 32 : byte
    }

    private static func asciiUppercased(_ byte: UInt8) -> UInt8 {
        (97...122).contains(byte) ? byte - 32 : byte
    }

    private static func cancellationAwareSorted<Element>(
        _ values: [Element],
        by areInIncreasingOrder: (Element, Element) -> Bool,
        cancellationCheckInterval: Int,
        budget: inout ImageToolWorkBudget
    ) throws -> [Element] {
        guard values.count > 1 else { return values }
        var source = values
        var destination = values
        var width = 1
        while width < source.count {
            try checkCancellation()
            try budget.consume(UInt64(source.count))
            var lower = 0
            while lower < source.count {
                let middle = min(lower + width, source.count)
                let upper = min(middle + width, source.count)
                var left = lower
                var right = middle
                var output = lower
                while left < middle || right < upper {
                    if output.isMultiple(of: cancellationCheckInterval) {
                        try checkCancellation()
                    }
                    if right >= upper
                        || (left < middle && !areInIncreasingOrder(source[right], source[left]))
                    {
                        destination[output] = source[left]
                        left += 1
                    } else {
                        destination[output] = source[right]
                        right += 1
                    }
                    output += 1
                }
                lower = upper
            }
            swap(&source, &destination)
            let doubled = width.multipliedReportingOverflow(by: 2)
            width = doubled.overflow ? source.count : doubled.partialValue
        }
        return source
    }

    private static func cancellationAwareSortedStrings(
        _ values: [String],
        cancellationCheckInterval: Int,
        budget: inout ImageToolWorkBudget
    ) throws -> [String] {
        guard values.count > 1 else { return values }
        var source = values
        var destination = values
        var width = 1
        while width < source.count {
            try checkCancellation()
            var lower = 0
            while lower < source.count {
                let middle = min(lower + width, source.count)
                let upper = min(middle + width, source.count)
                var left = lower
                var right = middle
                var output = lower
                while left < middle || right < upper {
                    let takeLeft: Bool
                    if right >= upper {
                        takeLeft = true
                    } else if left >= middle {
                        takeLeft = false
                    } else {
                        takeLeft = try utf8LexicographicallyPrecedes(
                            source[left],
                            source[right],
                            cancellationCheckInterval: cancellationCheckInterval,
                            budget: &budget
                        )
                    }
                    if takeLeft {
                        destination[output] = source[left]
                        left += 1
                    } else {
                        destination[output] = source[right]
                        right += 1
                    }
                    output += 1
                    try budget.consume(1)
                }
                lower = upper
            }
            swap(&source, &destination)
            let doubled = width.multipliedReportingOverflow(by: 2)
            width = doubled.overflow ? source.count : doubled.partialValue
        }
        return source
    }

    private static func utf8LexicographicallyPrecedes(
        _ left: String,
        _ right: String,
        cancellationCheckInterval: Int,
        budget: inout ImageToolWorkBudget
    ) throws -> Bool {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        var comparisons = 0
        while true {
            let leftByte = leftIterator.next()
            let rightByte = rightIterator.next()
            comparisons += 1
            if comparisons == cancellationCheckInterval {
                try budget.consume(UInt64(comparisons))
                comparisons = 0
            }
            if leftByte != rightByte {
                if comparisons > 0 { try budget.consume(UInt64(comparisons)) }
                guard let leftByte else { return true }
                guard let rightByte else { return false }
                return leftByte < rightByte
            }
            if leftByte == nil {
                if comparisons > 0 { try budget.consume(UInt64(comparisons)) }
                return false
            }
        }
    }

    private static func validateString(
        _ value: String,
        total: Int,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> (value: String, total: Int) {
        let maximumInputBytes = limits.maximumStringUTF8Bytes * 3
        var inputByteCount = 0
        for byte in value.utf8 {
            if inputByteCount.isMultiple(of: limits.cancellationCheckInterval) {
                try checkCancellation()
            }
            guard byte != 0 else { throw ImageToolWorkflowError.invalidString }
            inputByteCount += 1
            guard inputByteCount <= maximumInputBytes else {
                throw ImageToolWorkflowError.stringTooLarge(
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            if inputByteCount.isMultiple(of: limits.cancellationCheckInterval) {
                try budget.consume(UInt64(limits.cancellationCheckInterval))
            }
        }
        let unchargedInputBytes = inputByteCount % limits.cancellationCheckInterval
        if unchargedInputBytes > 0 { try budget.consume(UInt64(unchargedInputBytes)) }
        let value = value.precomposedStringWithCanonicalMapping
        try checkCancellation()
        var byteCount = 0
        for byte in value.utf8 {
            if byteCount.isMultiple(of: limits.cancellationCheckInterval) {
                try checkCancellation()
            }
            guard byte != 0 else { throw ImageToolWorkflowError.invalidString }
            byteCount += 1
            guard byteCount <= limits.maximumStringUTF8Bytes else {
                throw ImageToolWorkflowError.stringTooLarge(
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            if byteCount.isMultiple(of: limits.cancellationCheckInterval) {
                try budget.consume(UInt64(limits.cancellationCheckInterval))
            }
        }
        let newTotal = try boundedAdd(
            total,
            byteCount,
            maximum: limits.maximumTotalStringUTF8Bytes,
            error: .totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        )
        let unchargedBytes = byteCount % limits.cancellationCheckInterval
        if unchargedBytes > 0 { try budget.consume(UInt64(unchargedBytes)) }
        return (value, newTotal)
    }

    private static func snapshotStringUTF8ByteCount(
        _ snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> Int {
        var total = 0
        for pane in snapshot.panes {
            try budget.consume(1)
            if let displayName = pane.displayName {
                (_, total) = try validateString(
                    displayName,
                    total: total,
                    limits: limits,
                    budget: &budget
                )
            }
            for (index, page) in pane.pages.enumerated() {
                if index.isMultiple(of: limits.cancellationCheckInterval) {
                    try checkCancellation()
                }
                try budget.consume(1)
                if let label = page.label {
                    (_, total) = try validateString(
                        label,
                        total: total,
                        limits: limits,
                        budget: &budget
                    )
                }
            }
        }
        return total
    }

    private static func consumeSelectedPixelWork(
        _ snapshot: ImageToolWorkflowSnapshot,
        budget: inout ImageToolWorkBudget
    ) throws {
        var maximumWidth: UInt64 = 0
        var maximumHeight: UInt64 = 0
        for pane in snapshot.panes {
            guard let page = pane.selectedPage else {
                throw ImageToolWorkflowError.invalidSnapshot(
                    pane: pane.pane,
                    issue: .selectedPageMissing
                )
            }
            guard let sourceWidth = UInt64(exactly: page.width),
                let sourceHeight = UInt64(exactly: page.height)
            else {
                throw ImageToolWorkflowError.arithmeticOverflow
            }
            let swapsDimensions = pane.transform.clockwiseQuarterTurns.isMultiple(of: 2) == false
            maximumWidth = max(maximumWidth, swapsDimensions ? sourceHeight : sourceWidth)
            maximumHeight = max(maximumHeight, swapsDimensions ? sourceWidth : sourceHeight)
        }
        let canvas = maximumWidth.multipliedReportingOverflow(by: maximumHeight)
        guard !canvas.overflow else { throw ImageToolWorkflowError.arithmeticOverflow }
        guard
            let maximumCanvasPixels = UInt64(
                exactly: snapshot.controls.differences.pixelComparison.maximumCanvasPixels
            ), canvas.partialValue <= maximumCanvasPixels
        else {
            throw ImageToolWorkflowError.comparisonCanvasTooLarge(
                maximumPixels: snapshot.controls.differences.pixelComparison.maximumCanvasPixels
            )
        }
        try budget.consume(canvas.partialValue)
    }

    private static func consumeOCRPixelWork(
        _ request: ImageToolOCRRequestIntent,
        snapshot: ImageToolWorkflowSnapshot,
        budget: inout ImageToolWorkBudget
    ) throws {
        for target in request.targets {
            guard let page = snapshot[target.pane]?.pages[target.pageIndex] else {
                throw ImageToolWorkflowError.pageNotFound(
                    pane: target.pane,
                    pageIndex: target.pageIndex
                )
            }
            try budget.consume(try pixelCount(page))
        }
    }

    private static func pixelCount(_ page: ImageToolPageDescriptor) throws -> UInt64 {
        guard let width = UInt64(exactly: page.width),
            let height = UInt64(exactly: page.height)
        else {
            throw ImageToolWorkflowError.arithmeticOverflow
        }
        let result = width.multipliedReportingOverflow(by: height)
        guard !result.overflow else { throw ImageToolWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    private static func fingerprint(
        _ snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> ImageToolSnapshotFingerprint {
        var writer = ImageToolCanonicalWriter(
            maximumBytes: limits.maximumPlanBytes,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            maximumWorkUnits: budget.remaining,
            workLimitMaximum: budget.maximum
        )
        writer.add("MacMerge.ImageToolSnapshot.v1")
        writer.add(snapshot)
        let data = try writer.finalize()
        try budget.consume(UInt64(data.count))
        try checkCancellation()
        return ImageToolSnapshotFingerprint(
            reference: ImageToolSnapshotReference(snapshot),
            stateSHA256: try sha256(
                data,
                cancellationCheckInterval: limits.cancellationCheckInterval
            )
        )
    }

    private static func differenceInputSHA256(
        validatedSnapshot snapshot: ImageToolWorkflowSnapshot,
        limits: ImageToolWorkflowLimits,
        budget: inout ImageToolWorkBudget
    ) throws -> [UInt8] {
        var writer = ImageToolCanonicalWriter(
            maximumBytes: limits.maximumPlanBytes,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            maximumWorkUnits: budget.remaining,
            workLimitMaximum: budget.maximum
        )
        writer.add("MacMerge.ImageToolDifferenceInput.v1")
        writer.add(UInt64(snapshot.panes.count))
        for pane in snapshot.panes {
            writer.add(pane.pane)
            writer.add(pane.image)
            writer.add(pane.selectedPageIndex)
            writer.add(pane.transform)
        }
        writer.add(comparisonOptions(snapshot.controls.differences))
        let data = try writer.finalize()
        try budget.consume(UInt64(data.count))
        try checkCancellation()
        return try sha256(
            data,
            cancellationCheckInterval: limits.cancellationCheckInterval
        )
    }

    private static func canonicalPlanData(
        source: ImageToolSnapshotFingerprint,
        intent: ImageToolWorkflowIntent,
        requiredCapabilities: ImageToolCapabilities,
        projectedSnapshot: ImageToolWorkflowSnapshot?,
        invalidatesDifferenceResult: Bool,
        limits: ImageToolWorkflowLimits,
        maximumWorkUnits: UInt64
    ) throws -> Data {
        var writer = ImageToolCanonicalWriter(
            maximumBytes: limits.maximumPlanBytes,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            maximumWorkUnits: maximumWorkUnits,
            workLimitMaximum: limits.maximumWorkUnits
        )
        writer.add("MacMerge.ImageToolPlan.v1")
        writer.add(source.reference)
        writer.add(source.stateSHA256)
        writer.add(intent)
        writer.add(requiredCapabilities)
        writer.add(projectedSnapshot)
        writer.add(invalidatesDifferenceResult)
        writer.add(limits)
        return try writer.finalize()
    }

    private static func sha256(
        _ data: Data,
        cancellationCheckInterval: Int
    ) throws -> [UInt8] {
        var hasher = SHA256()
        var offset = 0
        while offset < data.count {
            try checkCancellation()
            let upperBound = min(offset + cancellationCheckInterval, data.count)
            hasher.update(data: data[offset..<upperBound])
            offset = upperBound
        }
        try checkCancellation()
        return Array(hasher.finalize())
    }
}

private struct ImageToolWorkBudget {
    let maximum: UInt64
    private(set) var consumed: UInt64 = 0
    var remaining: UInt64 { maximum - consumed }

    mutating func consume(_ units: UInt64) throws {
        try Task.checkCancellation()
        let result = consumed.addingReportingOverflow(units)
        guard !result.overflow, result.partialValue <= maximum else {
            throw ImageToolWorkflowError.workLimitExceeded(maximumUnits: maximum)
        }
        consumed = result.partialValue
    }
}

private struct ImageToolCanonicalWriter {
    private var data = Data()
    private let maximumBytes: Int
    private let cancellationCheckInterval: Int
    private let maximumWorkUnits: UInt64
    private let workLimitMaximum: UInt64
    private var workUnits: UInt64 = 0
    private var exceededLimit = false
    private var exceededWork = false
    private var cancelled = false
    private var shouldStop: Bool { exceededLimit || exceededWork || cancelled }

    init(
        maximumBytes: Int,
        cancellationCheckInterval: Int,
        maximumWorkUnits: UInt64,
        workLimitMaximum: UInt64
    ) {
        self.maximumBytes = maximumBytes
        self.cancellationCheckInterval = cancellationCheckInterval
        self.maximumWorkUnits = maximumWorkUnits
        self.workLimitMaximum = workLimitMaximum
        data.reserveCapacity(min(maximumBytes, 64 * 1_024))
    }

    mutating func finalize() throws -> Data {
        if cancelled { throw CancellationError() }
        guard !exceededWork else {
            throw ImageToolWorkflowError.workLimitExceeded(maximumUnits: workLimitMaximum)
        }
        guard !exceededLimit else {
            throw ImageToolWorkflowError.planTooLarge(maximumBytes: maximumBytes)
        }
        return data
    }

    private mutating func append(_ byte: UInt8) {
        guard !shouldStop else { return }
        if data.count.isMultiple(of: cancellationCheckInterval), Task.isCancelled {
            cancelled = true
            return
        }
        guard workUnits < maximumWorkUnits else {
            exceededWork = true
            return
        }
        guard data.count < maximumBytes else {
            exceededLimit = true
            return
        }
        data.append(byte)
        workUnits += 1
    }

    private mutating func append<Bytes>(contentsOf bytes: Bytes)
    where
        Bytes: Collection,
        Bytes.Element == UInt8
    {
        for byte in bytes {
            append(byte)
            if shouldStop { return }
        }
    }

    mutating func add(_ value: Bool) {
        append(value ? 1 : 0)
    }

    mutating func add(_ value: UInt8) {
        append(value)
    }

    mutating func add(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func add(_ value: Int) {
        add(UInt64(bitPattern: Int64(value)))
    }

    mutating func add(_ value: Double) {
        add((value == 0 ? 0 : value).bitPattern)
    }

    mutating func add(_ value: String) {
        let bytes = value.utf8
        add(UInt64(bytes.count))
        append(contentsOf: bytes)
    }

    mutating func add(_ value: UUID) {
        var uuid = value.uuid
        withUnsafeBytes(of: &uuid) { append(contentsOf: $0) }
    }

    mutating func add(_ value: [UInt8]) {
        add(UInt64(value.count))
        append(contentsOf: value)
    }

    mutating func add(_ value: ImageToolPane) { add(value.rawValue) }

    mutating func add(_ value: ImageToolImageRevision) {
        add(value.identity.rawValue)
        add(value.revision)
        add(value.generation)
        add(value.contentSHA256)
    }

    mutating func add(_ value: ImageToolPageDescriptor) {
        add(value.index)
        add(value.width)
        add(value.height)
        add(value.bitsPerPixel)
        add(value.isVector)
        add(value.label)
    }

    mutating func add(_ value: ImageToolTransform) {
        add(value.clockwiseQuarterTurns)
        add(value.flipsHorizontally)
        add(value.flipsVertically)
    }

    mutating func add(_ value: ImageToolPaneSnapshot) {
        add(value.pane)
        add(value.image)
        add(UInt64(value.pages.count))
        for page in value.pages {
            if shouldStop { break }
            add(page)
        }
        add(value.selectedPageIndex)
        add(value.transform)
        add(value.displayName)
        add(value.isReadOnly)
        add(value.isModified)
    }

    mutating func add(_ value: ImageComparisonOptions) {
        add(value.channelTolerance)
        add(value.maximumCanvasPixels)
        add(value.maximumRegions)
        add(value.maximumQueuedPixels)
    }

    mutating func add(_ value: ImageToolDifferenceOptions) {
        add(value.pixelComparison)
        add(value.showsDifferences)
        add(value.differenceBlockSize)
        add(value.colorDistanceThreshold)
        add(value.insertionDetection.rawValue)
    }

    mutating func add(_ value: ImageToolComparisonOptionProjection) {
        add(value.pixelComparison)
        add(value.differenceBlockSize)
        add(value.colorDistanceThreshold)
        add(value.insertionDetection.rawValue)
    }

    mutating func add(_ value: ImageToolZoom) {
        add(value.mode.rawValue)
        add(value.scale)
    }

    mutating func add(_ value: ImageToolOverlay) {
        add(value.mode.rawValue)
        add(value.alpha)
    }

    mutating func add(_ value: ImageToolWipe) {
        add(value.mode.rawValue)
        add(value.position)
    }

    mutating func add(_ value: ImageToolAnimation) {
        add(value.blinksDifferences)
        add(value.blinkIntervalMilliseconds)
        add(value.overlayIntervalMilliseconds)
    }

    mutating func add(_ value: ImageToolControlState) {
        add(value.pageSelectionMode.rawValue)
        add(value.differences)
        add(value.zoom)
        add(value.overlay)
        add(value.wipe)
        add(value.animation)
    }

    mutating func add(_ value: ImageToolDifferenceResultReference) {
        add(value.identity)
        add(value.generation)
        add(value.inputSHA256)
        add(value.resultSHA256)
        add(value.differenceCount)
        add(value.conflictCount)
        add(value.differingPixelCount)
        add(value.selectedDifferenceIndex)
    }

    mutating func add(_ value: ImageToolWorkflowSnapshot) {
        add(value.identity)
        add(value.revision)
        add(value.generation)
        add(UInt64(value.panes.count))
        for pane in value.panes {
            if shouldStop { break }
            add(pane)
        }
        add(value.controls)
        add(value.differenceResult)
    }

    mutating func add(_ value: ImageToolSnapshotReference) {
        add(value.identity)
        add(value.revision)
        add(value.generation)
    }

    mutating func add(_ value: ImageToolCapabilities) {
        let values = value.values.sorted { $0.rawValue < $1.rawValue }
        add(UInt64(values.count))
        for capability in values {
            if shouldStop { break }
            add(capability.rawValue)
        }
    }

    mutating func add(_ value: ImageToolPageSelection) {
        add(value.mode.rawValue)
        add(UInt64(value.selections.count))
        for selection in value.selections {
            if shouldStop { break }
            add(selection.pane)
            add(selection.pageIndex)
        }
    }

    mutating func add(_ value: ImageToolOCRRequestIntent) {
        add(UInt64(value.targets.count))
        for target in value.targets {
            if shouldStop { break }
            add(target.pane)
            add(target.pageIndex)
        }
        add(value.resultKind.rawValue)
        add(UInt64(value.languageHints.count))
        for hint in value.languageHints {
            if shouldStop { break }
            add(hint)
        }
        add(value.completion.rawValue)
    }

    mutating func add(_ value: ImageToolWorkflowIntent) {
        switch value {
        case .selectPages(let selection):
            add(UInt8(0))
            add(selection)
        case .setDifferenceOptions(let options):
            add(UInt8(1))
            add(options)
        case .setTransforms(let transforms):
            add(UInt8(2))
            add(UInt64(transforms.count))
            for item in transforms {
                if shouldStop { break }
                add(item.pane)
                add(item.transform)
            }
        case .setZoom(let zoom):
            add(UInt8(3))
            add(zoom)
        case .setOverlay(let overlay):
            add(UInt8(4))
            add(overlay)
        case .setWipe(let wipe):
            add(UInt8(5))
            add(wipe)
        case .setAnimation(let animation):
            add(UInt8(6))
            add(animation)
        case .requestOCR(let request):
            add(UInt8(7))
            add(request)
        }
    }

    mutating func add(_ value: ImageToolWorkflowLimits) {
        add(value.maximumPaneCount)
        add(value.maximumPagesPerPane)
        add(value.maximumTotalPages)
        add(value.maximumItemCount)
        add(value.maximumStringUTF8Bytes)
        add(value.maximumTotalStringUTF8Bytes)
        add(value.maximumPlanBytes)
        add(value.maximumWorkUnits)
        add(value.maximumOCRResultUTF8Bytes)
        add(value.maximumOCRResultItems)
        add(value.cancellationCheckInterval)
    }

    mutating func add(_ value: String?) {
        guard let value else {
            add(false)
            return
        }
        add(true)
        add(value)
    }

    mutating func add(_ value: Int?) {
        guard let value else {
            add(false)
            return
        }
        add(true)
        add(value)
    }

    mutating func add(_ value: ImageToolDifferenceResultReference?) {
        guard let value else {
            add(false)
            return
        }
        add(true)
        add(value)
    }

    mutating func add(_ value: ImageToolWorkflowSnapshot?) {
        guard let value else {
            add(false)
            return
        }
        add(true)
        add(value)
    }
}
