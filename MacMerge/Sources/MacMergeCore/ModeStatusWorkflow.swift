import CryptoKit
import Foundation

public enum ModeStatusMode: UInt8, CaseIterable, Hashable, Sendable {
    case folder
    case binary
    case image
    case webpage
}

public enum ModeStatusSide: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case left
    case middle
    case right

    public static func < (left: ModeStatusSide, right: ModeStatusSide) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// Opaque owner identity. It intentionally carries no path, URL, display name, or secret.
public struct ModeStatusSourceIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Exact owner-issued source version. Owners must never reuse one identity and generation for
/// different content or source status.
public struct ModeStatusSourceReference: Hashable, Sendable {
    public let identity: ModeStatusSourceIdentity
    public let generation: UInt64

    public init(identity: ModeStatusSourceIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }
}

public struct ModeStatusInputIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct ModeStatusInputSource: Hashable, Sendable {
    public let side: ModeStatusSide
    public let source: ModeStatusSourceReference

    public init(side: ModeStatusSide, source: ModeStatusSourceReference) {
        self.side = side
        self.source = source
    }
}

/// Exact comparison inputs, including caller-owned configuration generation. `sources` must be in
/// canonical side order: left/right or left/middle/right.
public struct ModeStatusInputReference: Hashable, Sendable {
    public let identity: ModeStatusInputIdentity
    public let generation: UInt64
    public let mode: ModeStatusMode
    public let sources: [ModeStatusInputSource]

    public init(
        identity: ModeStatusInputIdentity,
        generation: UInt64,
        mode: ModeStatusMode,
        sources: [ModeStatusInputSource]
    ) {
        self.identity = identity
        self.generation = generation
        self.mode = mode
        self.sources = sources
    }

    public subscript(side: ModeStatusSide) -> ModeStatusSourceReference? {
        sources.first { $0.side == side }?.source
    }
}

public struct ModeStatusComparisonIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Exact result version and exact inputs used to produce it.
public struct ModeStatusComparisonReference: Hashable, Sendable {
    public let identity: ModeStatusComparisonIdentity
    public let generation: UInt64
    public let inputs: ModeStatusInputReference

    public init(
        identity: ModeStatusComparisonIdentity,
        generation: UInt64,
        inputs: ModeStatusInputReference
    ) {
        self.identity = identity
        self.generation = generation
        self.inputs = inputs
    }
}

public enum ModeStatusExternalChangeState: UInt8, CaseIterable, Hashable, Sendable {
    case notApplicable
    case notChecked
    case unchanged
    case changed
    case missing
    case inaccessible
}

public struct ModeStatusFolderSourceMetrics: Hashable, Sendable {
    public let entryCount: UInt64

    public init(entryCount: UInt64) {
        self.entryCount = entryCount
    }
}

public struct ModeStatusBinarySourceMetrics: Hashable, Sendable {
    public let byteCount: UInt64

    public init(byteCount: UInt64) {
        self.byteCount = byteCount
    }
}

public struct ModeStatusImageSourceMetrics: Hashable, Sendable {
    public let selectedPageIndex: Int
    public let pageCount: Int
    public let width: Int
    public let height: Int
    public let bitsPerPixel: Int
    public let isVector: Bool

    public init(
        selectedPageIndex: Int,
        pageCount: Int,
        width: Int,
        height: Int,
        bitsPerPixel: Int,
        isVector: Bool = false
    ) {
        self.selectedPageIndex = selectedPageIndex
        self.pageCount = pageCount
        self.width = width
        self.height = height
        self.bitsPerPixel = bitsPerPixel
        self.isVector = isVector
    }
}

public struct ModeStatusWebPageSourceMetrics: Hashable, Sendable {
    public let sourceUTF8ByteCount: UInt64
    public let normalizedUTF8ByteCount: UInt64
    public let tokenCount: UInt64
    public let attributeCount: UInt64
    public let comparisonLineCount: UInt64

    public init(
        sourceUTF8ByteCount: UInt64,
        normalizedUTF8ByteCount: UInt64,
        tokenCount: UInt64,
        attributeCount: UInt64,
        comparisonLineCount: UInt64
    ) {
        self.sourceUTF8ByteCount = sourceUTF8ByteCount
        self.normalizedUTF8ByteCount = normalizedUTF8ByteCount
        self.tokenCount = tokenCount
        self.attributeCount = attributeCount
        self.comparisonLineCount = comparisonLineCount
    }
}

public enum ModeStatusSourceMetrics: Hashable, Sendable {
    case folder(ModeStatusFolderSourceMetrics)
    case binary(ModeStatusBinarySourceMetrics)
    case image(ModeStatusImageSourceMetrics)
    case webpage(ModeStatusWebPageSourceMetrics)

    public var mode: ModeStatusMode {
        switch self {
        case .folder: .folder
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        }
    }
}

/// Current per-source status. Persisted state is caller-observed; this workflow performs no I/O.
public struct ModeStatusSourceState: Hashable, Sendable {
    public let side: ModeStatusSide
    public let source: ModeStatusSourceReference
    public let metrics: ModeStatusSourceMetrics
    public let isReadOnly: Bool
    public let isDirty: Bool
    public let isPersisted: Bool
    public let externalChange: ModeStatusExternalChangeState

    public init(
        side: ModeStatusSide,
        source: ModeStatusSourceReference,
        metrics: ModeStatusSourceMetrics,
        isReadOnly: Bool,
        isDirty: Bool,
        isPersisted: Bool,
        externalChange: ModeStatusExternalChangeState
    ) {
        self.side = side
        self.source = source
        self.metrics = metrics
        self.isReadOnly = isReadOnly
        self.isDirty = isDirty
        self.isPersisted = isPersisted
        self.externalChange = externalChange
    }
}

public struct ModeStatusItemIdentity: Hashable, Sendable {
    public let comparisonIdentity: ModeStatusComparisonIdentity
    public let comparisonGeneration: UInt64
    public let rawValue: UUID

    public init(
        comparisonIdentity: ModeStatusComparisonIdentity,
        comparisonGeneration: UInt64,
        rawValue: UUID = UUID()
    ) {
        self.comparisonIdentity = comparisonIdentity
        self.comparisonGeneration = comparisonGeneration
        self.rawValue = rawValue
    }
}

public enum ModeStatusBinarySurface: UInt8, CaseIterable, Hashable, Sendable {
    case bytes
    case characters
}

public struct ModeStatusPixelPoint: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Exact current selection and cursor state. Nil fields represent an absent selection or cursor,
/// never an inferred default.
public enum ModeStatusInteraction: Hashable, Sendable {
    case none
    case folder(
        comparison: ModeStatusComparisonReference,
        selectedItems: [ModeStatusItemIdentity],
        cursor: ModeStatusItemIdentity?
    )
    case binary(
        comparison: ModeStatusComparisonReference,
        side: ModeStatusSide,
        cursorByteOffset: UInt64?,
        selection: Range<UInt64>?,
        surface: ModeStatusBinarySurface
    )
    case image(
        comparison: ModeStatusComparisonReference,
        side: ModeStatusSide,
        pageIndex: Int,
        cursor: ModeStatusPixelPoint?,
        selectedDifferenceIndex: Int?
    )
    case webpage(
        comparison: ModeStatusComparisonReference,
        side: ModeStatusSide,
        cursorNormalizedUTF8Offset: UInt64?,
        selectionNormalizedUTF8Range: Range<UInt64>?,
        selectedDifferenceIndex: Int?
    )
}

public struct ModeStatusFolderComparisonMetrics: Hashable, Sendable {
    public let totalItems: UInt64
    public let visibleItems: UInt64
    public let pendingItems: UInt64
    public let identicalItems: UInt64
    public let differentItems: UInt64
    public let leftOnlyItems: UInt64
    public let rightOnlyItems: UInt64
    public let typeMismatchItems: UInt64
    public let skippedItems: UInt64
    public let errorItems: UInt64
    public let isComplete: Bool

    public init(
        totalItems: UInt64,
        visibleItems: UInt64,
        pendingItems: UInt64,
        identicalItems: UInt64,
        differentItems: UInt64,
        leftOnlyItems: UInt64,
        rightOnlyItems: UInt64,
        typeMismatchItems: UInt64,
        skippedItems: UInt64,
        errorItems: UInt64,
        isComplete: Bool
    ) {
        self.totalItems = totalItems
        self.visibleItems = visibleItems
        self.pendingItems = pendingItems
        self.identicalItems = identicalItems
        self.differentItems = differentItems
        self.leftOnlyItems = leftOnlyItems
        self.rightOnlyItems = rightOnlyItems
        self.typeMismatchItems = typeMismatchItems
        self.skippedItems = skippedItems
        self.errorItems = errorItems
        self.isComplete = isComplete
    }
}

public enum ModeStatusBinaryAlignment: UInt8, CaseIterable, Hashable, Sendable {
    case exact
    case boundedFallback
}

public struct ModeStatusBinaryComparisonMetrics: Hashable, Sendable {
    public let alignedByteCount: UInt64
    public let differenceRegionCount: UInt64
    public let differingByteCount: UInt64
    public let conflictCount: UInt64
    public let alignment: ModeStatusBinaryAlignment

    public init(
        alignedByteCount: UInt64,
        differenceRegionCount: UInt64,
        differingByteCount: UInt64,
        conflictCount: UInt64 = 0,
        alignment: ModeStatusBinaryAlignment
    ) {
        self.alignedByteCount = alignedByteCount
        self.differenceRegionCount = differenceRegionCount
        self.differingByteCount = differingByteCount
        self.conflictCount = conflictCount
        self.alignment = alignment
    }
}

public struct ModeStatusImageComparisonMetrics: Hashable, Sendable {
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let differenceRegionCount: UInt64
    public let differingPixelCount: UInt64
    public let conflictCount: UInt64
    public let conflictingPixelCount: UInt64

    public init(
        canvasWidth: Int,
        canvasHeight: Int,
        differenceRegionCount: UInt64,
        differingPixelCount: UInt64,
        conflictCount: UInt64 = 0,
        conflictingPixelCount: UInt64 = 0
    ) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.differenceRegionCount = differenceRegionCount
        self.differingPixelCount = differingPixelCount
        self.conflictCount = conflictCount
        self.conflictingPixelCount = conflictingPixelCount
    }
}

public enum ModeStatusWebPageForm: UInt8, CaseIterable, Hashable, Sendable {
    case source
    case renderedText
}

public struct ModeStatusWebPageComparisonMetrics: Hashable, Sendable {
    public let form: ModeStatusWebPageForm
    public let comparisonUnitCount: UInt64
    public let differenceCount: UInt64
    public let conflictCount: UInt64

    public init(
        form: ModeStatusWebPageForm,
        comparisonUnitCount: UInt64,
        differenceCount: UInt64,
        conflictCount: UInt64 = 0
    ) {
        self.form = form
        self.comparisonUnitCount = comparisonUnitCount
        self.differenceCount = differenceCount
        self.conflictCount = conflictCount
    }
}

public enum ModeStatusComparisonMetrics: Hashable, Sendable {
    case folder(ModeStatusFolderComparisonMetrics)
    case binary(ModeStatusBinaryComparisonMetrics)
    case image(ModeStatusImageComparisonMetrics)
    case webpage(ModeStatusWebPageComparisonMetrics)

    public var mode: ModeStatusMode {
        switch self {
        case .folder: .folder
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        }
    }
}

/// Exact per-source metrics used to bound one comparison result. These metrics remain attached to
/// retained results after current sources advance to newer generations.
public struct ModeStatusComparisonSourceMetrics: Hashable, Sendable {
    public let side: ModeStatusSide
    public let source: ModeStatusSourceReference
    public let metrics: ModeStatusSourceMetrics

    public init(
        side: ModeStatusSide,
        source: ModeStatusSourceReference,
        metrics: ModeStatusSourceMetrics
    ) {
        self.side = side
        self.source = source
        self.metrics = metrics
    }
}

public struct ModeStatusComparisonSnapshot: Hashable, Sendable {
    public let reference: ModeStatusComparisonReference
    public let sourceMetrics: [ModeStatusComparisonSourceMetrics]
    public let metrics: ModeStatusComparisonMetrics

    public init(
        reference: ModeStatusComparisonReference,
        sourceMetrics: [ModeStatusComparisonSourceMetrics],
        metrics: ModeStatusComparisonMetrics
    ) {
        self.reference = reference
        self.sourceMetrics = sourceMetrics
        self.metrics = metrics
    }
}

public struct ModeStatusOperationIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct ModeStatusOperationReference: Hashable, Sendable {
    public let identity: ModeStatusOperationIdentity
    public let generation: UInt64

    public init(identity: ModeStatusOperationIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }
}

public enum ModeStatusOperationKind: UInt8, CaseIterable, Hashable, Sendable {
    case initialLoad
    case refresh
}

public enum ModeStatusProgressStage: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case preparing
    case loadingInputs
    case comparing
    case projecting
    case publishing

    public static func < (left: ModeStatusProgressStage, right: ModeStatusProgressStage) -> Bool {
        left.rawValue < right.rawValue
    }
}

public struct ModeStatusProgress: Hashable, Sendable {
    public let stage: ModeStatusProgressStage
    public let completedUnits: UInt64
    public let totalUnits: UInt64?

    public init(
        stage: ModeStatusProgressStage,
        completedUnits: UInt64,
        totalUnits: UInt64? = nil
    ) {
        self.stage = stage
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
    }

    public var fractionCompleted: Double? {
        guard let totalUnits, totalUnits > 0 else { return nil }
        guard completedUnits < totalUnits else { return 1 }
        return min(Double(completedUnits) / Double(totalUnits), Double(1).nextDown)
    }
}

/// Active or terminal operation record. A refresh must retain the exact prior comparison.
public struct ModeStatusOperation: Hashable, Sendable {
    public let reference: ModeStatusOperationReference
    public let kind: ModeStatusOperationKind
    public let inputs: ModeStatusInputReference
    public let retainedComparison: ModeStatusComparisonReference?
    public let declaredWorkUnits: UInt64
    public let progress: ModeStatusProgress

    public init(
        reference: ModeStatusOperationReference,
        kind: ModeStatusOperationKind,
        inputs: ModeStatusInputReference,
        retainedComparison: ModeStatusComparisonReference? = nil,
        declaredWorkUnits: UInt64,
        progress: ModeStatusProgress
    ) {
        self.reference = reference
        self.kind = kind
        self.inputs = inputs
        self.retainedComparison = retainedComparison
        self.declaredWorkUnits = declaredWorkUnits
        self.progress = progress
    }
}

public enum ModeStatusStaleReason: Hashable, Sendable {
    case sourceChanged(ModeStatusSide)
    case optionsChanged
    case externalChange(ModeStatusSide)
    case modeChanged
}

public enum ModeStatusFailureKind: UInt8, CaseIterable, Hashable, Sendable {
    case invalidInput
    case inputUnavailable
    case readFailed
    case comparisonFailed
    case unsupported
    case resourceLimit
    case internalFailure
}

/// Structured failure state only. Presentation layers own localized prose and may map private
/// executor diagnostics separately without placing them in status snapshots.
public struct ModeStatusFailure: Hashable, Sendable {
    public let kind: ModeStatusFailureKind
    public let stage: ModeStatusProgressStage
    public let side: ModeStatusSide?
    public let isRetryable: Bool

    public init(
        kind: ModeStatusFailureKind,
        stage: ModeStatusProgressStage,
        side: ModeStatusSide? = nil,
        isRetryable: Bool = false
    ) {
        self.kind = kind
        self.stage = stage
        self.side = side
        self.isRetryable = isRetryable
    }
}

public enum ModeStatusCancellationReason: UInt8, CaseIterable, Hashable, Sendable {
    case userRequested
    case superseded
    case ownerClosing
    case resourceLimit
}

public struct ModeStatusCancellation: Hashable, Sendable {
    public let reason: ModeStatusCancellationReason
    public let stage: ModeStatusProgressStage

    public init(reason: ModeStatusCancellationReason, stage: ModeStatusProgressStage) {
        self.reason = reason
        self.stage = stage
    }
}

public enum ModeStatusLifecycle: Hashable, Sendable {
    case loading(ModeStatusOperation)
    case refreshing(ModeStatusOperation)
    case current(ModeStatusComparisonReference)
    case stale(ModeStatusComparisonReference, reason: ModeStatusStaleReason)
    case failed(ModeStatusOperation, failure: ModeStatusFailure)
    case cancelled(ModeStatusOperation, cancellation: ModeStatusCancellation)
}

public enum ModeStatusPhase: UInt8, CaseIterable, Hashable, Sendable {
    case loading
    case refreshing
    case current
    case stale
    case failed
    case cancelled
}

public struct ModeStatusSnapshotIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct ModeStatusSnapshotReference: Hashable, Sendable {
    public let identity: ModeStatusSnapshotIdentity
    public let generation: UInt64

    public init(identity: ModeStatusSnapshotIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }
}

/// Complete immutable owner state captured at one status boundary.
public struct ModeStatusSnapshot: Hashable, Sendable {
    public let identity: ModeStatusSnapshotIdentity
    public let generation: UInt64
    public let mode: ModeStatusMode
    public let inputs: ModeStatusInputReference
    public let sources: [ModeStatusSourceState]
    public let lifecycle: ModeStatusLifecycle
    public let comparison: ModeStatusComparisonSnapshot?
    public let interaction: ModeStatusInteraction

    public init(
        identity: ModeStatusSnapshotIdentity,
        generation: UInt64,
        mode: ModeStatusMode,
        inputs: ModeStatusInputReference,
        sources: [ModeStatusSourceState],
        lifecycle: ModeStatusLifecycle,
        comparison: ModeStatusComparisonSnapshot?,
        interaction: ModeStatusInteraction = .none
    ) {
        self.identity = identity
        self.generation = generation
        self.mode = mode
        self.inputs = inputs
        self.sources = sources
        self.lifecycle = lifecycle
        self.comparison = comparison
        self.interaction = interaction
    }

    public var reference: ModeStatusSnapshotReference {
        ModeStatusSnapshotReference(identity: identity, generation: generation)
    }
}

public enum ModeStatusLimit: UInt8, CaseIterable, Hashable, Sendable {
    case selectedItems
    case metricValue
    case pixelCount
    case declaredWorkUnits
    case canonicalBytes
    case workUnits
    case cancellationCheckInterval
}

public struct ModeStatusLimits: Hashable, Sendable {
    public static let hardMaximumSelectedItems = 1_000_000
    public static let hardMaximumMetricValue: UInt64 = 1_000_000_000_000
    public static let hardMaximumPixelCount: UInt64 = 1 << 40
    public static let hardMaximumDeclaredWorkUnits: UInt64 = 1 << 50
    public static let hardMaximumCanonicalBytes = 64 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 32
    public static let hardMaximumCancellationCheckInterval: UInt64 = 65_536
    public static let `default` = ModeStatusLimits()

    public let maximumSelectedItems: Int
    public let maximumMetricValue: UInt64
    public let maximumPixelCount: UInt64
    public let maximumDeclaredWorkUnits: UInt64
    public let maximumCanonicalBytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: UInt64

    public init(
        maximumSelectedItems: Int = 100_000,
        maximumMetricValue: UInt64 = 1_000_000_000,
        maximumPixelCount: UInt64 = 256 * 1_024 * 1_024,
        maximumDeclaredWorkUnits: UInt64 = 1 << 40,
        maximumCanonicalBytes: Int = 8 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 64 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 4_096
    ) {
        self.maximumSelectedItems = maximumSelectedItems
        self.maximumMetricValue = maximumMetricValue
        self.maximumPixelCount = maximumPixelCount
        self.maximumDeclaredWorkUnits = maximumDeclaredWorkUnits
        self.maximumCanonicalBytes = maximumCanonicalBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ModeStatusMetricsIssue: UInt8, CaseIterable, Hashable, Sendable {
    case modeMismatch
    case valueOutOfBounds
    case aggregateMismatch
    case visibleCountExceedsTotal
    case incompleteFolderHasNoPendingItems
    case invalidImagePage
    case invalidImageDimensions
    case invalidImagePixelCount
    case differencesExceedComparisonExtent
    case conflictsExceedDifferences
}

public enum ModeStatusInteractionIssue: UInt8, CaseIterable, Hashable, Sendable {
    case modeMismatch
    case comparisonReferenceMismatch
    case unknownSide
    case duplicateSelectedItem
    case tooManySelectedItems
    case unsupportedFolderSelection
    case invalidCursor
    case invalidSelection
    case itemUsesDifferentComparison
    case invalidPage
    case invalidDifferenceIndex
}

public enum ModeStatusLifecycleIssue: UInt8, CaseIterable, Hashable, Sendable {
    case inputMismatch
    case comparisonMissing
    case unexpectedComparison
    case comparisonReferenceMismatch
    case comparisonSourceMismatch
    case currentResultUsesDifferentInputs
    case staleResultUsesCurrentInputs
    case invalidStaleReason
    case invalidOperation
    case invalidProgress
    case terminalStagePrecedesProgress
    case invalidFailureSide
}

public enum ModeStatusWorkflowError: Error, LocalizedError, Hashable, Sendable {
    case cancelled
    case invalidLimit(ModeStatusLimit)
    case invalidSourceLayout
    case duplicateSourceSide(ModeStatusSide)
    case sourceOrderIsNotCanonical
    case sourceReferenceMismatch(ModeStatusSide)
    case sourceModeMismatch(ModeStatusSide)
    case invalidExternalChangeState(ModeStatusSide)
    case invalidMetrics(ModeStatusMetricsIssue)
    case invalidInteraction(ModeStatusInteractionIssue)
    case invalidLifecycle(ModeStatusLifecycleIssue)
    case metricLimitExceeded(ModeStatusLimit)
    case declaredWorkLimitExceeded
    case canonicalRepresentationTooLarge
    case workLimitExceeded
    case staleSnapshotIdentity
    case staleSnapshotGeneration(expected: UInt64, actual: UInt64)
    case snapshotContentsChanged

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Mode status projection was cancelled."
        case .invalidLimit:
            "Mode status limits are invalid."
        case .invalidSourceLayout, .duplicateSourceSide, .sourceOrderIsNotCanonical:
            "Mode status source layout is invalid."
        case .sourceReferenceMismatch:
            "Mode status source identity or generation is inconsistent."
        case .sourceModeMismatch:
            "Mode status source metrics do not match comparison mode."
        case .invalidExternalChangeState:
            "Mode status external-change state is inconsistent."
        case .invalidMetrics:
            "Mode status comparison metrics are inconsistent."
        case .invalidInteraction:
            "Mode status selection or cursor state is inconsistent."
        case .invalidLifecycle:
            "Mode status lifecycle state is inconsistent."
        case .metricLimitExceeded:
            "Mode status metrics exceed configured limits."
        case .declaredWorkLimitExceeded:
            "Mode status operation exceeds configured work limits."
        case .canonicalRepresentationTooLarge:
            "Mode status canonical representation exceeds configured limits."
        case .workLimitExceeded:
            "Mode status projection exceeds configured work limits."
        case .staleSnapshotIdentity:
            "Mode status projection belongs to another snapshot."
        case .staleSnapshotGeneration:
            "Mode status projection generation is stale."
        case .snapshotContentsChanged:
            "Mode status snapshot changed without advancing generation."
        }
    }
}

public struct ModeStatusProjectionReceipt: Hashable, Sendable {
    public static let canonicalDomainIdentifier = "com.macmerge.mode-status-projection"
    public static let currentCanonicalSchemaVersion: UInt64 = 1

    public let canonicalDomain: String
    public let canonicalSchemaVersion: UInt64
    public let snapshot: ModeStatusSnapshotReference
    public let comparison: ModeStatusComparisonReference?
    public let canonicalSHA256: [UInt8]
    public let canonicalByteCount: Int
    public let workUnitsConsumed: UInt64

    fileprivate init(
        snapshot: ModeStatusSnapshotReference,
        comparison: ModeStatusComparisonReference?,
        canonicalSHA256: [UInt8],
        canonicalByteCount: Int,
        workUnitsConsumed: UInt64
    ) {
        canonicalDomain = Self.canonicalDomainIdentifier
        canonicalSchemaVersion = Self.currentCanonicalSchemaVersion
        self.snapshot = snapshot
        self.comparison = comparison
        self.canonicalSHA256 = canonicalSHA256
        self.canonicalByteCount = canonicalByteCount
        self.workUnitsConsumed = workUnitsConsumed
    }
}

/// Deterministic, UI-independent status projection. `metrics` may describe a retained stale result;
/// `isResultCurrent` distinguishes it from metrics for current inputs.
public struct ModeStatusProjection: Hashable, Sendable {
    public let snapshot: ModeStatusSnapshotReference
    public let mode: ModeStatusMode
    public let phase: ModeStatusPhase
    public let inputs: ModeStatusInputReference
    public let sources: [ModeStatusSourceState]
    public let operation: ModeStatusOperation?
    public let comparison: ModeStatusComparisonReference?
    public let staleReason: ModeStatusStaleReason?
    public let failure: ModeStatusFailure?
    public let cancellation: ModeStatusCancellation?
    public let metrics: ModeStatusComparisonMetrics?
    public let interaction: ModeStatusInteraction
    public let isResultCurrent: Bool
    public let limits: ModeStatusLimits
    public let receipt: ModeStatusProjectionReceipt

    fileprivate let canonicalProjection: Data

    public func isCurrent(snapshot: ModeStatusSnapshot) throws(ModeStatusWorkflowError) -> Bool {
        do {
            try validateCurrent(snapshot: snapshot)
            return true
        } catch .staleSnapshotIdentity, .staleSnapshotGeneration, .snapshotContentsChanged {
            return false
        }
    }

    public func validateCurrent(
        snapshot currentSnapshot: ModeStatusSnapshot
    ) throws(ModeStatusWorkflowError) {
        try ModeStatusWorkflow.validateCurrent(self, snapshot: currentSnapshot)
    }
}

/// Pure status validator and projector. It performs no loading, comparison, rendering, localization,
/// filesystem access, network access, or owner-state mutation.
public enum ModeStatusWorkflow: Sendable {
    public static func project(
        _ snapshot: ModeStatusSnapshot,
        limits: ModeStatusLimits = .default
    ) throws(ModeStatusWorkflowError) -> ModeStatusProjection {
        try validate(limits)
        var budget = ModeStatusWorkBudget(limits: limits)
        return try project(snapshot, limits: limits, budget: &budget)
    }

    private static func project(
        _ snapshot: ModeStatusSnapshot,
        limits: ModeStatusLimits,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) -> ModeStatusProjection {
        try budget.checkCancellation()
        try validate(snapshot, limits: limits, budget: &budget)

        let state = lifecycleProjection(snapshot.lifecycle)
        var writer = ModeStatusCanonicalWriter(limits: limits, budget: budget)
        try writer.appendCanonicalHeader()
        try writer.append(limits)
        try writer.append(snapshot)
        try writer.finish()
        let canonical = writer.data
        budget = writer.budget
        let digest = try sha256(canonical, budget: &budget)
        let workUnitsConsumed = budget.consumed
        let receipt = ModeStatusProjectionReceipt(
            snapshot: snapshot.reference,
            comparison: state.comparison,
            canonicalSHA256: digest,
            canonicalByteCount: canonical.count,
            workUnitsConsumed: workUnitsConsumed
        )

        return ModeStatusProjection(
            snapshot: snapshot.reference,
            mode: snapshot.mode,
            phase: state.phase,
            inputs: snapshot.inputs,
            sources: snapshot.sources,
            operation: state.operation,
            comparison: state.comparison,
            staleReason: state.staleReason,
            failure: state.failure,
            cancellation: state.cancellation,
            metrics: snapshot.comparison?.metrics,
            interaction: snapshot.interaction,
            isResultCurrent: state.comparison?.inputs == snapshot.inputs,
            limits: limits,
            receipt: receipt,
            canonicalProjection: canonical
        )
    }

    public static func validateCurrent(
        _ projection: ModeStatusProjection,
        snapshot currentSnapshot: ModeStatusSnapshot
    ) throws(ModeStatusWorkflowError) {
        try checkCancellation()
        guard projection.snapshot.identity == currentSnapshot.identity else {
            throw .staleSnapshotIdentity
        }
        guard projection.snapshot.generation == currentSnapshot.generation else {
            throw .staleSnapshotGeneration(
                expected: projection.snapshot.generation,
                actual: currentSnapshot.generation
            )
        }

        var budget = ModeStatusWorkBudget(limits: projection.limits)
        let currentProjection = try project(
            currentSnapshot,
            limits: projection.limits,
            budget: &budget
        )
        guard
            try bytesAreEqual(
                projection.canonicalProjection,
                currentProjection.canonicalProjection,
                budget: &budget
            )
        else {
            throw .snapshotContentsChanged
        }
    }

    private struct LifecycleProjection {
        let phase: ModeStatusPhase
        let operation: ModeStatusOperation?
        let comparison: ModeStatusComparisonReference?
        let staleReason: ModeStatusStaleReason?
        let failure: ModeStatusFailure?
        let cancellation: ModeStatusCancellation?
    }

    private static func lifecycleProjection(
        _ lifecycle: ModeStatusLifecycle
    ) -> LifecycleProjection {
        switch lifecycle {
        case .loading(let operation):
            LifecycleProjection(
                phase: .loading,
                operation: operation,
                comparison: operation.retainedComparison,
                staleReason: nil,
                failure: nil,
                cancellation: nil
            )
        case .refreshing(let operation):
            LifecycleProjection(
                phase: .refreshing,
                operation: operation,
                comparison: operation.retainedComparison,
                staleReason: nil,
                failure: nil,
                cancellation: nil
            )
        case .current(let comparison):
            LifecycleProjection(
                phase: .current,
                operation: nil,
                comparison: comparison,
                staleReason: nil,
                failure: nil,
                cancellation: nil
            )
        case .stale(let comparison, let reason):
            LifecycleProjection(
                phase: .stale,
                operation: nil,
                comparison: comparison,
                staleReason: reason,
                failure: nil,
                cancellation: nil
            )
        case .failed(let operation, let failure):
            LifecycleProjection(
                phase: .failed,
                operation: operation,
                comparison: operation.retainedComparison,
                staleReason: nil,
                failure: failure,
                cancellation: nil
            )
        case .cancelled(let operation, let cancellation):
            LifecycleProjection(
                phase: .cancelled,
                operation: operation,
                comparison: operation.retainedComparison,
                staleReason: nil,
                failure: nil,
                cancellation: cancellation
            )
        }
    }

    private static func validate(
        _ limits: ModeStatusLimits
    ) throws(ModeStatusWorkflowError) {
        guard limits.maximumSelectedItems >= 0,
            limits.maximumSelectedItems <= ModeStatusLimits.hardMaximumSelectedItems
        else { throw .invalidLimit(.selectedItems) }
        guard limits.maximumMetricValue <= ModeStatusLimits.hardMaximumMetricValue else {
            throw .invalidLimit(.metricValue)
        }
        guard limits.maximumPixelCount > 0,
            limits.maximumPixelCount <= ModeStatusLimits.hardMaximumPixelCount
        else { throw .invalidLimit(.pixelCount) }
        guard limits.maximumDeclaredWorkUnits <= ModeStatusLimits.hardMaximumDeclaredWorkUnits else {
            throw .invalidLimit(.declaredWorkUnits)
        }
        guard limits.maximumCanonicalBytes > 0,
            limits.maximumCanonicalBytes <= ModeStatusLimits.hardMaximumCanonicalBytes
        else { throw .invalidLimit(.canonicalBytes) }
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= ModeStatusLimits.hardMaximumWorkUnits
        else { throw .invalidLimit(.workUnits) }
        guard limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval
                <= ModeStatusLimits.hardMaximumCancellationCheckInterval
        else { throw .invalidLimit(.cancellationCheckInterval) }
    }

    private static func validate(
        _ snapshot: ModeStatusSnapshot,
        limits: ModeStatusLimits,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) {
        guard snapshot.mode == snapshot.inputs.mode else {
            throw .invalidLifecycle(.inputMismatch)
        }
        try validate(snapshot.inputs, limits: limits, budget: &budget)
        guard snapshot.sources.count == snapshot.inputs.sources.count else {
            throw .invalidSourceLayout
        }

        for index in snapshot.sources.indices {
            try budget.consume(1)
            let state = snapshot.sources[index]
            let input = snapshot.inputs.sources[index]
            guard state.side == input.side else { throw .sourceOrderIsNotCanonical }
            guard state.source == input.source else {
                throw .sourceReferenceMismatch(state.side)
            }
            guard state.metrics.mode == snapshot.mode else {
                throw .sourceModeMismatch(state.side)
            }
            if state.isPersisted {
                guard state.externalChange != .notApplicable else {
                    throw .invalidExternalChangeState(state.side)
                }
            } else {
                guard state.externalChange == .notApplicable else {
                    throw .invalidExternalChangeState(state.side)
                }
            }
            try validate(state.metrics, limits: limits)
        }

        try validateLifecycle(snapshot, limits: limits, budget: &budget)
        try validateInteraction(snapshot.interaction, snapshot: snapshot, limits: limits, budget: &budget)
        try budget.checkCancellation()
    }

    private static func validate(
        _ input: ModeStatusInputReference,
        limits: ModeStatusLimits,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) {
        guard input.sources.count == 2 || input.sources.count == 3 else {
            throw .invalidSourceLayout
        }
        guard input.mode != .folder || input.sources.count == 2 else {
            throw .invalidSourceLayout
        }
        let expectedSides: [ModeStatusSide] =
            input.sources.count == 2 ? [.left, .right] : [.left, .middle, .right]
        var seen: Set<ModeStatusSide> = []
        for (index, source) in input.sources.enumerated() {
            try budget.consume(1)
            guard seen.insert(source.side).inserted else {
                throw .duplicateSourceSide(source.side)
            }
            guard source.side == expectedSides[index] else {
                throw .sourceOrderIsNotCanonical
            }
        }
        _ = limits
    }

    private static func validate(
        _ metrics: ModeStatusSourceMetrics,
        limits: ModeStatusLimits
    ) throws(ModeStatusWorkflowError) {
        switch metrics {
        case .folder(let metrics):
            try validateMetric(metrics.entryCount, limits: limits)
        case .binary(let metrics):
            try validateMetric(metrics.byteCount, limits: limits)
        case .image(let metrics):
            guard metrics.pageCount > 0,
                metrics.selectedPageIndex >= 0,
                metrics.selectedPageIndex < metrics.pageCount
            else { throw .invalidMetrics(.invalidImagePage) }
            guard metrics.width > 0, metrics.height > 0, metrics.bitsPerPixel > 0 else {
                throw .invalidMetrics(.invalidImageDimensions)
            }
            _ = try pixelCount(
                width: metrics.width,
                height: metrics.height,
                limits: limits
            )
            try validateMetric(UInt64(metrics.pageCount), limits: limits)
            try validateMetric(UInt64(metrics.width), limits: limits)
            try validateMetric(UInt64(metrics.height), limits: limits)
            try validateMetric(UInt64(metrics.bitsPerPixel), limits: limits)
        case .webpage(let metrics):
            try validateMetric(metrics.sourceUTF8ByteCount, limits: limits)
            try validateMetric(metrics.normalizedUTF8ByteCount, limits: limits)
            try validateMetric(metrics.tokenCount, limits: limits)
            try validateMetric(metrics.attributeCount, limits: limits)
            try validateMetric(metrics.comparisonLineCount, limits: limits)
        }
    }

    private static func validate(
        _ metrics: ModeStatusComparisonMetrics,
        sources: [ModeStatusComparisonSourceMetrics],
        limits: ModeStatusLimits
    ) throws(ModeStatusWorkflowError) {
        switch metrics {
        case .folder(let metrics):
            guard sources.count == 2,
                case .folder(let leftSource) = sources[0].metrics,
                case .folder(let rightSource) = sources[1].metrics
            else { throw .invalidMetrics(.modeMismatch) }
            let counts = [
                metrics.pendingItems,
                metrics.identicalItems,
                metrics.differentItems,
                metrics.leftOnlyItems,
                metrics.rightOnlyItems,
                metrics.typeMismatchItems,
                metrics.skippedItems,
                metrics.errorItems
            ]
            for count in counts { try validateMetric(count, limits: limits) }
            try validateMetric(metrics.totalItems, limits: limits)
            try validateMetric(metrics.visibleItems, limits: limits)
            guard metrics.visibleItems <= metrics.totalItems else {
                throw .invalidMetrics(.visibleCountExceedsTotal)
            }
            guard try sum(counts) == metrics.totalItems else {
                throw .invalidMetrics(.aggregateMismatch)
            }
            let sourceEntryCount = try sum([leftSource.entryCount, rightSource.entryCount])
            let pairedItems = try sum([
                metrics.identicalItems,
                metrics.differentItems,
                metrics.typeMismatchItems
            ])
            let knownLeftItems = try sum([metrics.leftOnlyItems, pairedItems])
            let knownRightItems = try sum([metrics.rightOnlyItems, pairedItems])
            guard metrics.totalItems <= sourceEntryCount,
                knownLeftItems <= leftSource.entryCount,
                knownRightItems <= rightSource.entryCount
            else { throw .invalidMetrics(.differencesExceedComparisonExtent) }
            guard metrics.isComplete || metrics.pendingItems > 0 else {
                throw .invalidMetrics(.incompleteFolderHasNoPendingItems)
            }
            guard !metrics.isComplete || metrics.pendingItems == 0 else {
                throw .invalidMetrics(.aggregateMismatch)
            }
        case .binary(let metrics):
            var sourceByteCounts: [UInt64] = []
            sourceByteCounts.reserveCapacity(sources.count)
            for source in sources {
                guard case .binary(let sourceMetrics) = source.metrics else {
                    throw .invalidMetrics(.modeMismatch)
                }
                sourceByteCounts.append(sourceMetrics.byteCount)
            }
            try validateMetric(metrics.alignedByteCount, limits: limits)
            try validateMetric(metrics.differenceRegionCount, limits: limits)
            try validateMetric(metrics.differingByteCount, limits: limits)
            try validateMetric(metrics.conflictCount, limits: limits)
            let sourceByteCount = try sum(sourceByteCounts)
            guard metrics.alignedByteCount <= sourceByteCount,
                metrics.differingByteCount <= metrics.alignedByteCount
            else {
                throw .invalidMetrics(.differencesExceedComparisonExtent)
            }
            guard (metrics.differenceRegionCount == 0) == (metrics.differingByteCount == 0),
                metrics.differenceRegionCount <= metrics.differingByteCount
            else { throw .invalidMetrics(.aggregateMismatch) }
            guard metrics.conflictCount <= metrics.differenceRegionCount else {
                throw .invalidMetrics(.conflictsExceedDifferences)
            }
            guard sources.count != 2 || metrics.conflictCount == 0 else {
                throw .invalidMetrics(.conflictsExceedDifferences)
            }
        case .image(let metrics):
            var sourceDimensions: [(width: Int, height: Int)] = []
            sourceDimensions.reserveCapacity(sources.count)
            for source in sources {
                guard case .image(let sourceMetrics) = source.metrics else {
                    throw .invalidMetrics(.modeMismatch)
                }
                sourceDimensions.append((sourceMetrics.width, sourceMetrics.height))
            }
            let canvasPixels = try pixelCount(
                width: metrics.canvasWidth,
                height: metrics.canvasHeight,
                limits: limits
            )
            try validateMetric(metrics.differenceRegionCount, limits: limits)
            try validateMetric(metrics.differingPixelCount, limits: limits)
            try validateMetric(metrics.conflictCount, limits: limits)
            try validateMetric(metrics.conflictingPixelCount, limits: limits)
            guard let maximumWidth = sourceDimensions.map(\.width).max(),
                let maximumHeight = sourceDimensions.map(\.height).max(),
                metrics.canvasWidth <= maximumWidth,
                metrics.canvasHeight <= maximumHeight,
                metrics.differingPixelCount <= canvasPixels,
                metrics.conflictingPixelCount <= metrics.differingPixelCount,
                metrics.differenceRegionCount <= metrics.differingPixelCount
            else { throw .invalidMetrics(.differencesExceedComparisonExtent) }
            guard (metrics.differenceRegionCount == 0) == (metrics.differingPixelCount == 0),
                (metrics.conflictCount == 0) == (metrics.conflictingPixelCount == 0)
            else { throw .invalidMetrics(.aggregateMismatch) }
            guard metrics.conflictCount <= metrics.differenceRegionCount,
                metrics.conflictCount <= metrics.conflictingPixelCount
            else {
                throw .invalidMetrics(.conflictsExceedDifferences)
            }
            guard
                sources.count != 2
                    || metrics.conflictCount == 0 && metrics.conflictingPixelCount == 0
            else { throw .invalidMetrics(.conflictsExceedDifferences) }
        case .webpage(let metrics):
            var sourceLineCounts: [UInt64] = []
            sourceLineCounts.reserveCapacity(sources.count)
            for source in sources {
                guard case .webpage(let sourceMetrics) = source.metrics else {
                    throw .invalidMetrics(.modeMismatch)
                }
                sourceLineCounts.append(sourceMetrics.comparisonLineCount)
            }
            try validateMetric(metrics.comparisonUnitCount, limits: limits)
            try validateMetric(metrics.differenceCount, limits: limits)
            try validateMetric(metrics.conflictCount, limits: limits)
            let sourceLineCount = try sum(sourceLineCounts)
            guard metrics.comparisonUnitCount <= sourceLineCount,
                metrics.differenceCount <= metrics.comparisonUnitCount
            else {
                throw .invalidMetrics(.differencesExceedComparisonExtent)
            }
            guard metrics.conflictCount <= metrics.differenceCount else {
                throw .invalidMetrics(.conflictsExceedDifferences)
            }
            guard sources.count != 2 || metrics.conflictCount == 0 else {
                throw .invalidMetrics(.conflictsExceedDifferences)
            }
        }
    }

    private static func validate(
        _ sources: [ModeStatusComparisonSourceMetrics],
        reference: ModeStatusComparisonReference,
        snapshot: ModeStatusSnapshot,
        limits: ModeStatusLimits,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) {
        guard sources.count == reference.inputs.sources.count else {
            throw .invalidLifecycle(.comparisonSourceMismatch)
        }
        for index in sources.indices {
            try budget.consume(1)
            let source = sources[index]
            let input = reference.inputs.sources[index]
            guard source.side == input.side, source.source == input.source else {
                throw .invalidLifecycle(.comparisonSourceMismatch)
            }
            guard source.metrics.mode == reference.inputs.mode else {
                throw .invalidMetrics(.modeMismatch)
            }
            try validate(source.metrics, limits: limits)

            if let currentSource = snapshot.sources.first(where: {
                $0.side == source.side && $0.source == source.source
            }), currentSource.metrics.mode == source.metrics.mode,
                currentSource.metrics != source.metrics
            {
                throw .invalidLifecycle(.comparisonSourceMismatch)
            }
        }
    }

    private static func validateLifecycle(
        _ snapshot: ModeStatusSnapshot,
        limits: ModeStatusLimits,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) {
        let state = lifecycleProjection(snapshot.lifecycle)
        if let operation = state.operation {
            try validate(operation, snapshot: snapshot, limits: limits, budget: &budget)
        }

        if let reference = state.comparison {
            guard let comparison = snapshot.comparison else {
                throw .invalidLifecycle(.comparisonMissing)
            }
            guard comparison.reference == reference else {
                throw .invalidLifecycle(.comparisonReferenceMismatch)
            }
            guard comparison.metrics.mode == reference.inputs.mode else {
                throw .invalidMetrics(.modeMismatch)
            }
            try validate(reference.inputs, limits: limits, budget: &budget)
            try validate(
                comparison.sourceMetrics,
                reference: reference,
                snapshot: snapshot,
                limits: limits,
                budget: &budget
            )
            try validate(
                comparison.metrics,
                sources: comparison.sourceMetrics,
                limits: limits
            )
        } else if snapshot.comparison != nil {
            throw .invalidLifecycle(.unexpectedComparison)
        }

        switch snapshot.lifecycle {
        case .loading(let operation):
            guard operation.kind == .initialLoad else {
                throw .invalidLifecycle(.invalidOperation)
            }
        case .refreshing(let operation):
            guard operation.kind == .refresh else {
                throw .invalidLifecycle(.invalidOperation)
            }
        case .current(let comparison):
            guard comparison.inputs == snapshot.inputs else {
                throw .invalidLifecycle(.currentResultUsesDifferentInputs)
            }
        case .stale(let comparison, let reason):
            guard comparison.inputs != snapshot.inputs else {
                throw .invalidLifecycle(.staleResultUsesCurrentInputs)
            }
            try validate(reason, old: comparison.inputs, current: snapshot.inputs)
            if case .externalChange(let side) = reason {
                guard let state = sourceState(side, snapshot: snapshot),
                    state.externalChange == .changed
                        || state.externalChange == .missing
                        || state.externalChange == .inaccessible
                else { throw .invalidLifecycle(.invalidStaleReason) }
            }
        case .failed(let operation, let failure):
            guard failure.stage >= operation.progress.stage else {
                throw .invalidLifecycle(.terminalStagePrecedesProgress)
            }
            if let side = failure.side, snapshot.inputs[side] == nil {
                throw .invalidLifecycle(.invalidFailureSide)
            }
        case .cancelled(let operation, let cancellation):
            guard cancellation.stage >= operation.progress.stage else {
                throw .invalidLifecycle(.terminalStagePrecedesProgress)
            }
        }
    }

    private static func validate(
        _ operation: ModeStatusOperation,
        snapshot: ModeStatusSnapshot,
        limits: ModeStatusLimits,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) {
        guard operation.inputs == snapshot.inputs else {
            throw .invalidLifecycle(.inputMismatch)
        }
        try validate(operation.inputs, limits: limits, budget: &budget)
        guard operation.declaredWorkUnits <= limits.maximumDeclaredWorkUnits else {
            throw .declaredWorkLimitExceeded
        }
        if let total = operation.progress.totalUnits {
            guard total > 0,
                operation.progress.completedUnits <= total,
                total <= operation.declaredWorkUnits
            else { throw .invalidLifecycle(.invalidProgress) }
        } else {
            guard operation.progress.completedUnits <= operation.declaredWorkUnits else {
                throw .invalidLifecycle(.invalidProgress)
            }
        }
        switch operation.kind {
        case .initialLoad:
            guard operation.retainedComparison == nil else {
                throw .invalidLifecycle(.invalidOperation)
            }
        case .refresh:
            guard operation.retainedComparison != nil else {
                throw .invalidLifecycle(.invalidOperation)
            }
        }
    }

    private static func validate(
        _ reason: ModeStatusStaleReason,
        old: ModeStatusInputReference,
        current: ModeStatusInputReference
    ) throws(ModeStatusWorkflowError) {
        switch reason {
        case .sourceChanged(let side), .externalChange(let side):
            guard old.mode == current.mode,
                let oldSource = old[side],
                let currentSource = current[side],
                oldSource != currentSource
            else { throw .invalidLifecycle(.invalidStaleReason) }
        case .optionsChanged:
            guard old.mode == current.mode,
                old.sources == current.sources,
                old.identity != current.identity || old.generation != current.generation
            else { throw .invalidLifecycle(.invalidStaleReason) }
        case .modeChanged:
            guard old.mode != current.mode else {
                throw .invalidLifecycle(.invalidStaleReason)
            }
        }
    }

    private static func validateInteraction(
        _ interaction: ModeStatusInteraction,
        snapshot: ModeStatusSnapshot,
        limits: ModeStatusLimits,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) {
        switch interaction {
        case .none:
            return
        case .folder(let comparison, let selectedItems, let cursor):
            guard snapshot.mode == .folder else {
                throw .invalidInteraction(.modeMismatch)
            }
            _ = try validateInteractionComparison(comparison, snapshot: snapshot)
            guard selectedItems.count <= limits.maximumSelectedItems else {
                throw .invalidInteraction(.tooManySelectedItems)
            }
            var seen: Set<ModeStatusItemIdentity> = []
            seen.reserveCapacity(selectedItems.count)
            for item in selectedItems {
                try budget.consume(1)
                guard seen.insert(item).inserted else {
                    throw .invalidInteraction(.duplicateSelectedItem)
                }
                guard itemMatches(item, comparison: comparison) else {
                    throw .invalidInteraction(.itemUsesDifferentComparison)
                }
            }
            if let cursor {
                try budget.consume(1)
                guard itemMatches(cursor, comparison: comparison) else {
                    throw .invalidInteraction(.itemUsesDifferentComparison)
                }
            }
            if !selectedItems.isEmpty || cursor != nil {
                throw .invalidInteraction(.unsupportedFolderSelection)
            }
        case .binary(let comparison, let side, let cursor, let selection, _):
            guard snapshot.mode == .binary else {
                throw .invalidInteraction(.modeMismatch)
            }
            let comparisonSnapshot = try validateInteractionComparison(
                comparison,
                snapshot: snapshot
            )
            guard let source = comparisonSourceMetrics(side, comparison: comparisonSnapshot),
                case .binary(let sourceMetrics) = source.metrics
            else { throw .invalidInteraction(.unknownSide) }
            if let cursor, cursor > sourceMetrics.byteCount {
                throw .invalidInteraction(.invalidCursor)
            }
            if let selection,
                selection.lowerBound >= selection.upperBound
                    || selection.upperBound > sourceMetrics.byteCount
            {
                throw .invalidInteraction(.invalidSelection)
            }
        case .image(
            let comparison,
            let side,
            let pageIndex,
            let cursor,
            let selectedDifferenceIndex
        ):
            guard snapshot.mode == .image else {
                throw .invalidInteraction(.modeMismatch)
            }
            let comparisonSnapshot = try validateInteractionComparison(
                comparison,
                snapshot: snapshot
            )
            guard let source = comparisonSourceMetrics(side, comparison: comparisonSnapshot),
                case .image(let sourceMetrics) = source.metrics
            else { throw .invalidInteraction(.unknownSide) }
            guard pageIndex == sourceMetrics.selectedPageIndex else {
                throw .invalidInteraction(.invalidPage)
            }
            if let cursor,
                cursor.x < 0 || cursor.y < 0
                    || cursor.x >= sourceMetrics.width || cursor.y >= sourceMetrics.height
            {
                throw .invalidInteraction(.invalidCursor)
            }
            if let selectedDifferenceIndex {
                let differenceCount = differenceCount(comparisonSnapshot.metrics)
                guard selectedDifferenceIndex >= 0,
                    UInt64(selectedDifferenceIndex) < differenceCount
                else { throw .invalidInteraction(.invalidDifferenceIndex) }
            }
        case .webpage(
            let comparison,
            let side,
            let cursor,
            let selection,
            let selectedDifferenceIndex
        ):
            guard snapshot.mode == .webpage else {
                throw .invalidInteraction(.modeMismatch)
            }
            let comparisonSnapshot = try validateInteractionComparison(
                comparison,
                snapshot: snapshot
            )
            guard let source = comparisonSourceMetrics(side, comparison: comparisonSnapshot),
                case .webpage(let sourceMetrics) = source.metrics
            else { throw .invalidInteraction(.unknownSide) }
            if let cursor, cursor > sourceMetrics.normalizedUTF8ByteCount {
                throw .invalidInteraction(.invalidCursor)
            }
            if let selection,
                selection.lowerBound >= selection.upperBound
                    || selection.upperBound > sourceMetrics.normalizedUTF8ByteCount
            {
                throw .invalidInteraction(.invalidSelection)
            }
            if let selectedDifferenceIndex {
                let differenceCount = differenceCount(comparisonSnapshot.metrics)
                guard selectedDifferenceIndex >= 0,
                    UInt64(selectedDifferenceIndex) < differenceCount
                else { throw .invalidInteraction(.invalidDifferenceIndex) }
            }
        }
    }

    private static func validateInteractionComparison(
        _ reference: ModeStatusComparisonReference,
        snapshot: ModeStatusSnapshot
    ) throws(ModeStatusWorkflowError) -> ModeStatusComparisonSnapshot {
        guard let comparison = snapshot.comparison, comparison.reference == reference else {
            throw .invalidInteraction(.comparisonReferenceMismatch)
        }
        guard comparison.reference.inputs.mode == snapshot.mode else {
            throw .invalidInteraction(.modeMismatch)
        }
        return comparison
    }

    private static func comparisonSourceMetrics(
        _ side: ModeStatusSide,
        comparison: ModeStatusComparisonSnapshot
    ) -> ModeStatusComparisonSourceMetrics? {
        comparison.sourceMetrics.first { $0.side == side }
    }

    private static func sourceState(
        _ side: ModeStatusSide,
        snapshot: ModeStatusSnapshot
    ) -> ModeStatusSourceState? {
        snapshot.sources.first { $0.side == side }
    }

    private static func itemMatches(
        _ item: ModeStatusItemIdentity,
        comparison: ModeStatusComparisonReference?
    ) -> Bool {
        guard let comparison else { return false }
        return item.comparisonIdentity == comparison.identity
            && item.comparisonGeneration == comparison.generation
    }

    private static func differenceCount(_ metrics: ModeStatusComparisonMetrics) -> UInt64 {
        switch metrics {
        case .binary(let metrics): metrics.differenceRegionCount
        case .image(let metrics): metrics.differenceRegionCount
        case .webpage(let metrics): metrics.differenceCount
        case .folder: 0
        }
    }

    private static func validateMetric(
        _ value: UInt64,
        limits: ModeStatusLimits
    ) throws(ModeStatusWorkflowError) {
        guard value <= limits.maximumMetricValue else {
            throw .metricLimitExceeded(.metricValue)
        }
    }

    private static func sum(_ values: [UInt64]) throws(ModeStatusWorkflowError) -> UInt64 {
        var result: UInt64 = 0
        for value in values {
            let (next, overflow) = result.addingReportingOverflow(value)
            guard !overflow else { throw .invalidMetrics(.aggregateMismatch) }
            result = next
        }
        return result
    }

    private static func pixelCount(
        width: Int,
        height: Int,
        limits: ModeStatusLimits
    ) throws(ModeStatusWorkflowError) -> UInt64 {
        guard width > 0, height > 0,
            let width = UInt64(exactly: width),
            let height = UInt64(exactly: height)
        else { throw .invalidMetrics(.invalidImageDimensions) }
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, count <= limits.maximumPixelCount else {
            throw .invalidMetrics(.invalidImagePixelCount)
        }
        return count
    }

    private static func bytesAreEqual(
        _ left: Data,
        _ right: Data,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) -> Bool {
        guard left.count == right.count else { return false }
        var leftIterator = left.makeIterator()
        var rightIterator = right.makeIterator()
        while let leftByte = leftIterator.next() {
            try budget.consume(1)
            guard leftByte == rightIterator.next() else { return false }
        }
        try budget.checkCancellation()
        return rightIterator.next() == nil
    }

    private static func sha256(
        _ data: Data,
        budget: inout ModeStatusWorkBudget
    ) throws(ModeStatusWorkflowError) -> [UInt8] {
        var hasher = SHA256()
        var lowerBound = data.startIndex
        while lowerBound < data.endIndex {
            let count = min(4_096, data.distance(from: lowerBound, to: data.endIndex))
            let upperBound = data.index(lowerBound, offsetBy: count)
            try budget.consume(UInt64(count))
            hasher.update(data: data[lowerBound..<upperBound])
            lowerBound = upperBound
        }
        try budget.checkCancellation()
        return Array(hasher.finalize())
    }

    fileprivate static func checkCancellation() throws(ModeStatusWorkflowError) {
        if Task.isCancelled { throw .cancelled }
    }
}

private struct ModeStatusWorkBudget {
    let limits: ModeStatusLimits
    private(set) var consumed: UInt64 = 0
    private var unchecked: UInt64 = 0

    init(limits: ModeStatusLimits) {
        self.limits = limits
    }

    mutating func consume(_ units: UInt64) throws(ModeStatusWorkflowError) {
        let (next, overflow) = consumed.addingReportingOverflow(units)
        guard !overflow, next <= limits.maximumWorkUnits else {
            try checkCancellation()
            throw .workLimitExceeded
        }
        consumed = next

        let (nextUnchecked, uncheckedOverflow) = unchecked.addingReportingOverflow(units)
        if uncheckedOverflow || nextUnchecked >= limits.cancellationCheckInterval {
            try checkCancellation()
            if uncheckedOverflow {
                unchecked = 0
            } else {
                unchecked = nextUnchecked % limits.cancellationCheckInterval
            }
        } else {
            unchecked = nextUnchecked
        }
    }

    func checkCancellation() throws(ModeStatusWorkflowError) {
        try ModeStatusWorkflow.checkCancellation()
    }
}

private struct ModeStatusCanonicalWriter {
    private(set) var data = Data()
    private(set) var budget: ModeStatusWorkBudget
    private let limits: ModeStatusLimits

    init(limits: ModeStatusLimits, budget: ModeStatusWorkBudget) {
        self.limits = limits
        self.budget = budget
        data.reserveCapacity(min(limits.maximumCanonicalBytes, 4_096))
    }

    mutating func finish() throws(ModeStatusWorkflowError) {
        try budget.checkCancellation()
    }

    mutating func appendCanonicalHeader() throws(ModeStatusWorkflowError) {
        let domain = Array(ModeStatusProjectionReceipt.canonicalDomainIdentifier.utf8)
        try appendCount(domain.count)
        try appendRaw(domain)
        try append(ModeStatusProjectionReceipt.currentCanonicalSchemaVersion)
    }

    mutating func append(_ limits: ModeStatusLimits) throws(ModeStatusWorkflowError) {
        try append(UInt64(limits.maximumSelectedItems))
        try append(limits.maximumMetricValue)
        try append(limits.maximumPixelCount)
        try append(limits.maximumDeclaredWorkUnits)
        try append(UInt64(limits.maximumCanonicalBytes))
        try append(limits.maximumWorkUnits)
        try append(limits.cancellationCheckInterval)
    }

    mutating func append(_ snapshot: ModeStatusSnapshot) throws(ModeStatusWorkflowError) {
        try append(snapshot.identity.rawValue)
        try append(snapshot.generation)
        try append(snapshot.mode.rawValue)
        try append(snapshot.inputs)
        try appendCount(snapshot.sources.count)
        for source in snapshot.sources { try append(source) }
        try append(snapshot.lifecycle)
        try appendOptional(snapshot.comparison) { writer, comparison in
            try writer.append(comparison)
        }
        try append(snapshot.interaction)
    }

    mutating func append(_ input: ModeStatusInputReference) throws(ModeStatusWorkflowError) {
        try append(input.identity.rawValue)
        try append(input.generation)
        try append(input.mode.rawValue)
        try appendCount(input.sources.count)
        for source in input.sources {
            try append(source.side.rawValue)
            try append(source.source)
        }
    }

    mutating func append(
        _ reference: ModeStatusSourceReference
    ) throws(ModeStatusWorkflowError) {
        try append(reference.identity.rawValue)
        try append(reference.generation)
    }

    mutating func append(
        _ reference: ModeStatusComparisonReference
    ) throws(ModeStatusWorkflowError) {
        try append(reference.identity.rawValue)
        try append(reference.generation)
        try append(reference.inputs)
    }

    mutating func append(_ source: ModeStatusSourceState) throws(ModeStatusWorkflowError) {
        try append(source.side.rawValue)
        try append(source.source)
        try append(source.metrics)
        try append(source.isReadOnly)
        try append(source.isDirty)
        try append(source.isPersisted)
        try append(source.externalChange.rawValue)
    }

    mutating func append(_ metrics: ModeStatusSourceMetrics) throws(ModeStatusWorkflowError) {
        switch metrics {
        case .folder(let metrics):
            try append(UInt8(0))
            try append(metrics.entryCount)
        case .binary(let metrics):
            try append(UInt8(1))
            try append(metrics.byteCount)
        case .image(let metrics):
            try append(UInt8(2))
            try appendInt(metrics.selectedPageIndex)
            try appendInt(metrics.pageCount)
            try appendInt(metrics.width)
            try appendInt(metrics.height)
            try appendInt(metrics.bitsPerPixel)
            try append(metrics.isVector)
        case .webpage(let metrics):
            try append(UInt8(3))
            try append(metrics.sourceUTF8ByteCount)
            try append(metrics.normalizedUTF8ByteCount)
            try append(metrics.tokenCount)
            try append(metrics.attributeCount)
            try append(metrics.comparisonLineCount)
        }
    }

    mutating func append(
        _ comparison: ModeStatusComparisonSnapshot
    ) throws(ModeStatusWorkflowError) {
        try append(comparison.reference)
        try appendCount(comparison.sourceMetrics.count)
        for source in comparison.sourceMetrics { try append(source) }
        try append(comparison.metrics)
    }

    mutating func append(
        _ source: ModeStatusComparisonSourceMetrics
    ) throws(ModeStatusWorkflowError) {
        try append(source.side.rawValue)
        try append(source.source)
        try append(source.metrics)
    }

    mutating func append(
        _ metrics: ModeStatusComparisonMetrics
    ) throws(ModeStatusWorkflowError) {
        switch metrics {
        case .folder(let metrics):
            try append(UInt8(0))
            try append(metrics.totalItems)
            try append(metrics.visibleItems)
            try append(metrics.pendingItems)
            try append(metrics.identicalItems)
            try append(metrics.differentItems)
            try append(metrics.leftOnlyItems)
            try append(metrics.rightOnlyItems)
            try append(metrics.typeMismatchItems)
            try append(metrics.skippedItems)
            try append(metrics.errorItems)
            try append(metrics.isComplete)
        case .binary(let metrics):
            try append(UInt8(1))
            try append(metrics.alignedByteCount)
            try append(metrics.differenceRegionCount)
            try append(metrics.differingByteCount)
            try append(metrics.conflictCount)
            try append(metrics.alignment.rawValue)
        case .image(let metrics):
            try append(UInt8(2))
            try appendInt(metrics.canvasWidth)
            try appendInt(metrics.canvasHeight)
            try append(metrics.differenceRegionCount)
            try append(metrics.differingPixelCount)
            try append(metrics.conflictCount)
            try append(metrics.conflictingPixelCount)
        case .webpage(let metrics):
            try append(UInt8(3))
            try append(metrics.form.rawValue)
            try append(metrics.comparisonUnitCount)
            try append(metrics.differenceCount)
            try append(metrics.conflictCount)
        }
    }

    mutating func append(_ lifecycle: ModeStatusLifecycle) throws(ModeStatusWorkflowError) {
        switch lifecycle {
        case .loading(let operation):
            try append(UInt8(0))
            try append(operation)
        case .refreshing(let operation):
            try append(UInt8(1))
            try append(operation)
        case .current(let comparison):
            try append(UInt8(2))
            try append(comparison)
        case .stale(let comparison, let reason):
            try append(UInt8(3))
            try append(comparison)
            try append(reason)
        case .failed(let operation, let failure):
            try append(UInt8(4))
            try append(operation)
            try append(failure)
        case .cancelled(let operation, let cancellation):
            try append(UInt8(5))
            try append(operation)
            try append(cancellation)
        }
    }

    mutating func append(_ operation: ModeStatusOperation) throws(ModeStatusWorkflowError) {
        try append(operation.reference.identity.rawValue)
        try append(operation.reference.generation)
        try append(operation.kind.rawValue)
        try append(operation.inputs)
        try appendOptional(operation.retainedComparison) { writer, comparison in
            try writer.append(comparison)
        }
        try append(operation.declaredWorkUnits)
        try append(operation.progress.stage.rawValue)
        try append(operation.progress.completedUnits)
        try appendOptional(operation.progress.totalUnits) { writer, total in
            try writer.append(total)
        }
    }

    mutating func append(_ reason: ModeStatusStaleReason) throws(ModeStatusWorkflowError) {
        switch reason {
        case .sourceChanged(let side):
            try append(UInt8(0))
            try append(side.rawValue)
        case .optionsChanged:
            try append(UInt8(1))
        case .externalChange(let side):
            try append(UInt8(2))
            try append(side.rawValue)
        case .modeChanged:
            try append(UInt8(3))
        }
    }

    mutating func append(_ failure: ModeStatusFailure) throws(ModeStatusWorkflowError) {
        try append(failure.kind.rawValue)
        try append(failure.stage.rawValue)
        try appendOptional(failure.side) { writer, side in
            try writer.append(side.rawValue)
        }
        try append(failure.isRetryable)
    }

    mutating func append(
        _ cancellation: ModeStatusCancellation
    ) throws(ModeStatusWorkflowError) {
        try append(cancellation.reason.rawValue)
        try append(cancellation.stage.rawValue)
    }

    mutating func append(_ interaction: ModeStatusInteraction) throws(ModeStatusWorkflowError) {
        switch interaction {
        case .none:
            try append(UInt8(0))
        case .folder(let comparison, let selectedItems, let cursor):
            try append(UInt8(1))
            try append(comparison)
            try appendCount(selectedItems.count)
            for item in selectedItems { try append(item) }
            try appendOptional(cursor) { writer, item in
                try writer.append(item)
            }
        case .binary(let comparison, let side, let cursor, let selection, let surface):
            try append(UInt8(2))
            try append(comparison)
            try append(side.rawValue)
            try appendOptional(cursor) { writer, offset in try writer.append(offset) }
            try appendOptional(selection) { writer, range in
                try writer.append(range.lowerBound)
                try writer.append(range.upperBound)
            }
            try append(surface.rawValue)
        case .image(
            let comparison,
            let side,
            let pageIndex,
            let cursor,
            let selectedDifferenceIndex
        ):
            try append(UInt8(3))
            try append(comparison)
            try append(side.rawValue)
            try appendInt(pageIndex)
            try appendOptional(cursor) { writer, point in
                try writer.appendInt(point.x)
                try writer.appendInt(point.y)
            }
            try appendOptional(selectedDifferenceIndex) { writer, index in
                try writer.appendInt(index)
            }
        case .webpage(
            let comparison,
            let side,
            let cursor,
            let selection,
            let selectedDifferenceIndex
        ):
            try append(UInt8(4))
            try append(comparison)
            try append(side.rawValue)
            try appendOptional(cursor) { writer, offset in try writer.append(offset) }
            try appendOptional(selection) { writer, range in
                try writer.append(range.lowerBound)
                try writer.append(range.upperBound)
            }
            try appendOptional(selectedDifferenceIndex) { writer, index in
                try writer.appendInt(index)
            }
        }
    }

    private mutating func appendOptional<Value>(
        _ value: Value?,
        appendValue: (inout ModeStatusCanonicalWriter, Value) throws -> Void
    ) throws(ModeStatusWorkflowError) {
        guard let value else {
            try append(false)
            return
        }
        try append(true)
        do {
            try appendValue(&self, value)
        } catch let error as ModeStatusWorkflowError {
            throw error
        } catch {
            preconditionFailure("Canonical status append threw an undocumented error")
        }
    }

    private mutating func appendCount(_ count: Int) throws(ModeStatusWorkflowError) {
        guard let count = UInt64(exactly: count) else {
            throw .canonicalRepresentationTooLarge
        }
        try append(count)
    }

    private mutating func append(
        _ item: ModeStatusItemIdentity
    ) throws(ModeStatusWorkflowError) {
        try append(item.comparisonIdentity.rawValue)
        try append(item.comparisonGeneration)
        try append(item.rawValue)
    }

    private mutating func appendInt(_ value: Int) throws(ModeStatusWorkflowError) {
        guard let value = UInt64(exactly: value) else {
            throw .canonicalRepresentationTooLarge
        }
        try append(value)
    }

    private mutating func append(_ value: Bool) throws(ModeStatusWorkflowError) {
        try append(value ? UInt8(1) : UInt8(0))
    }

    private mutating func append(_ value: UInt8) throws(ModeStatusWorkflowError) {
        try appendRaw([value])
    }

    private mutating func append(_ value: UInt64) throws(ModeStatusWorkflowError) {
        var encoded = value.bigEndian
        let bytes = withUnsafeBytes(of: &encoded) { Array($0) }
        try appendRaw(bytes)
    }

    private mutating func append(_ value: UUID) throws(ModeStatusWorkflowError) {
        var encoded = value.uuid
        let bytes = withUnsafeBytes(of: &encoded) { Array($0) }
        try appendRaw(bytes)
    }

    private mutating func appendRaw(_ bytes: [UInt8]) throws(ModeStatusWorkflowError) {
        try budget.consume(UInt64(bytes.count))
        guard bytes.count <= limits.maximumCanonicalBytes - data.count else {
            throw .canonicalRepresentationTooLarge
        }
        data.append(contentsOf: bytes)
    }
}
