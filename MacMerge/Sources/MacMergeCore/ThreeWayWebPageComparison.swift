import Foundation

/// Position of a normalized webpage snapshot in a three-pane comparison.
public enum ThreeWayWebPageComparisonSource: String, CaseIterable, Equatable, Hashable, Sendable {
    case left
    case middle
    case right
}

/// Identifies one coherent set of normalized snapshots.
///
/// Callers should advance `generation` whenever normalization inputs or settings change. Comparing
/// snapshots from different identifiers is a mismatch; comparing different generations is stale.
public struct ThreeWayWebPageComparisonContext: Equatable, Hashable, Sendable {
    public let identifier: String
    public let generation: UInt64

    public init(identifier: String, generation: UInt64) {
        self.identifier = identifier
        self.generation = generation
    }
}

/// Caller-owned metadata retained with a normalized snapshot.
public struct ThreeWayWebPageComparisonMetadataEntry: Equatable, Hashable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Offline input for a three-pane webpage comparison.
///
/// `document` must come from the deterministic normalization performed by `WebPageComparison`.
/// This model never loads a URL, executes script, applies CSS, or otherwise accesses the network.
public struct ThreeWayWebPageComparisonSnapshot: Equatable, Sendable {
    public let source: ThreeWayWebPageComparisonSource
    public let context: ThreeWayWebPageComparisonContext
    public let document: WebPageComparisonDocument
    public let metadata: [ThreeWayWebPageComparisonMetadataEntry]

    public var mode: WebPageComparisonMode { document.mode }
    public var normalizedText: String { document.comparisonText }

    public init(
        source: ThreeWayWebPageComparisonSource,
        context: ThreeWayWebPageComparisonContext,
        document: WebPageComparisonDocument,
        metadata: [ThreeWayWebPageComparisonMetadataEntry] = []
    ) {
        self.source = source
        self.context = context
        self.document = document
        self.metadata = metadata
    }
}

public struct ThreeWayWebPageComparisonLimits: Equatable, Sendable {
    public static let `default` = ThreeWayWebPageComparisonLimits()

    public let maximumSourceInputBytesPerSnapshot: Int
    public let maximumNormalizedInputBytesPerSnapshot: Int
    public let maximumTokenCountPerSnapshot: Int
    public let maximumAttributeCountPerSnapshot: Int
    /// Bounds the sum of all three normalized comparison texts.
    public let maximumTotalNormalizedInputBytes: Int
    public let maximumInputLinesPerSnapshot: Int
    /// Bounds context and caller metadata retained by the result.
    public let maximumMetadataEntriesPerSnapshot: Int
    public let maximumMetadataBytes: Int
    /// Bounds deterministic validation and range-mapping work around the bounded line-diff engine.
    public let maximumWorkUnits: Int
    public let maximumResultRegions: Int
    public let maximumMappedSegments: Int
    public let maximumOutputBytes: Int
    public let maximumOutputLines: Int

    public init(
        maximumSourceInputBytesPerSnapshot: Int = 64 * 1024 * 1024,
        maximumNormalizedInputBytesPerSnapshot: Int = 64 * 1024 * 1024,
        maximumTokenCountPerSnapshot: Int = 1_000_000,
        maximumAttributeCountPerSnapshot: Int = 1_000_000,
        maximumTotalNormalizedInputBytes: Int = 192 * 1024 * 1024,
        maximumInputLinesPerSnapshot: Int = 1024 * 1024,
        maximumMetadataEntriesPerSnapshot: Int = 1024,
        maximumMetadataBytes: Int = 1024 * 1024,
        maximumWorkUnits: Int = 512 * 1024 * 1024,
        maximumResultRegions: Int = 3 * 1024 * 1024 + 1,
        maximumMappedSegments: Int = 6 * 1024 * 1024,
        maximumOutputBytes: Int = 192 * 1024 * 1024,
        maximumOutputLines: Int = 3 * 1024 * 1024
    ) {
        self.maximumSourceInputBytesPerSnapshot = maximumSourceInputBytesPerSnapshot
        self.maximumNormalizedInputBytesPerSnapshot = maximumNormalizedInputBytesPerSnapshot
        self.maximumTokenCountPerSnapshot = maximumTokenCountPerSnapshot
        self.maximumAttributeCountPerSnapshot = maximumAttributeCountPerSnapshot
        self.maximumTotalNormalizedInputBytes = maximumTotalNormalizedInputBytes
        self.maximumInputLinesPerSnapshot = maximumInputLinesPerSnapshot
        self.maximumMetadataEntriesPerSnapshot = maximumMetadataEntriesPerSnapshot
        self.maximumMetadataBytes = maximumMetadataBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumResultRegions = maximumResultRegions
        self.maximumMappedSegments = maximumMappedSegments
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumOutputLines = maximumOutputLines
    }
}

public struct ThreeWayWebPageComparisonOptions: Equatable, Sendable {
    public static let `default` = ThreeWayWebPageComparisonOptions()

    public let diffAlgorithm: DiffAlgorithm
    public let expectedContext: ThreeWayWebPageComparisonContext?
    public let limits: ThreeWayWebPageComparisonLimits

    public init(
        diffAlgorithm: DiffAlgorithm = .default,
        expectedContext: ThreeWayWebPageComparisonContext? = nil,
        limits: ThreeWayWebPageComparisonLimits = .default
    ) {
        self.diffAlgorithm = diffAlgorithm
        self.expectedContext = expectedContext
        self.limits = limits
    }
}

/// Reuses exact three-way text classification for normalized webpage regions.
public typealias ThreeWayWebPageComparisonResolution = ThreeWayTextMergeResolution

public enum ThreeWayWebPageComparisonOutcome: Equatable, Sendable {
    case equal
    case leftOnly
    case rightOnly
    case identical
    case merged
    case conflict

    public var isConflict: Bool { self == .conflict }
}

/// Location of one aligned region in one normalized snapshot.
public struct ThreeWayWebPageComparisonLocation: Equatable, Sendable {
    /// Zero-based half-open line range in `snapshot.document.comparisonText`.
    public let lineRange: Range<Int>
    /// Half-open UTF-8 range in `snapshot.document.comparisonText`.
    public let normalizedUTF8Range: Range<Int>
    /// Whole normalization segments contributing bytes to this region, in source order.
    ///
    /// Segments are deliberately not clipped: rendered text and character references do not always
    /// have a one-to-one byte mapping back to HTML source.
    public let contributingSegments: [WebPageComparisonSegment]

    public var sourceUTF8Ranges: [Range<Int>] {
        contributingSegments.map(\.sourceUTF8Range)
    }

    fileprivate init(
        lineRange: Range<Int>,
        normalizedUTF8Range: Range<Int>,
        contributingSegments: [WebPageComparisonSegment]
    ) {
        self.lineRange = lineRange
        self.normalizedUTF8Range = normalizedUTF8Range
        self.contributingSegments = contributingSegments
    }
}

public struct ThreeWayWebPageComparisonRegion: Identifiable, Equatable, Sendable {
    public let id: Int
    public let left: ThreeWayWebPageComparisonLocation
    public let middle: ThreeWayWebPageComparisonLocation
    public let right: ThreeWayWebPageComparisonLocation
    public let resolution: ThreeWayWebPageComparisonResolution

    public var isDifference: Bool { resolution != .unchanged }
    public var isConflict: Bool { resolution.isConflict }

    public var automaticSource: ThreeWayWebPageComparisonSource? {
        switch resolution {
        case .unchanged:
            .middle
        case .left, .identical:
            .left
        case .right:
            .right
        case .conflict:
            nil
        }
    }

    fileprivate init(
        id: Int,
        left: ThreeWayWebPageComparisonLocation,
        middle: ThreeWayWebPageComparisonLocation,
        right: ThreeWayWebPageComparisonLocation,
        resolution: ThreeWayWebPageComparisonResolution
    ) {
        self.id = id
        self.left = left
        self.middle = middle
        self.right = right
        self.resolution = resolution
    }
}

public struct ThreeWayWebPageComparisonResult: Equatable, Sendable {
    public let context: ThreeWayWebPageComparisonContext
    public let mode: WebPageComparisonMode
    public let left: ThreeWayWebPageComparisonSnapshot
    public let middle: ThreeWayWebPageComparisonSnapshot
    public let right: ThreeWayWebPageComparisonSnapshot
    public let regions: [ThreeWayWebPageComparisonRegion]
    public let differences: [ThreeWayWebPageComparisonRegion]
    public let conflicts: [ThreeWayWebPageComparisonRegion]
    public let outcome: ThreeWayWebPageComparisonOutcome
    /// Deterministic normalized comparison text when safely available.
    ///
    /// Source-mode output composed from both changed sides is nil unless its bytes equal one complete
    /// validated input, because combining independent HTML ranges can produce malformed HTML.
    /// Rendered-text output never reconstructs HTML.
    public let automaticallyMergedComparisonText: String?
    public let leftEqualsMiddle: Bool
    public let rightEqualsMiddle: Bool
    public let leftEqualsRight: Bool

    public var isEqual: Bool { outcome == .equal }
    public var hasDifferences: Bool { !differences.isEmpty }
    public var hasConflicts: Bool { !conflicts.isEmpty }

    fileprivate init(
        context: ThreeWayWebPageComparisonContext,
        mode: WebPageComparisonMode,
        left: ThreeWayWebPageComparisonSnapshot,
        middle: ThreeWayWebPageComparisonSnapshot,
        right: ThreeWayWebPageComparisonSnapshot,
        regions: [ThreeWayWebPageComparisonRegion],
        differences: [ThreeWayWebPageComparisonRegion],
        conflicts: [ThreeWayWebPageComparisonRegion],
        outcome: ThreeWayWebPageComparisonOutcome,
        automaticallyMergedComparisonText: String?,
        leftEqualsMiddle: Bool,
        rightEqualsMiddle: Bool,
        leftEqualsRight: Bool
    ) {
        self.context = context
        self.mode = mode
        self.left = left
        self.middle = middle
        self.right = right
        self.regions = regions
        self.differences = differences
        self.conflicts = conflicts
        self.outcome = outcome
        self.automaticallyMergedComparisonText = automaticallyMergedComparisonText
        self.leftEqualsMiddle = leftEqualsMiddle
        self.rightEqualsMiddle = rightEqualsMiddle
        self.leftEqualsRight = leftEqualsRight
    }
}

public enum ThreeWayWebPageComparisonSnapshotIssue: Equatable, Sendable {
    case emptyContextIdentifier
    case negativeSourceByteCount
    case negativeTokenCount
    case negativeAttributeCount
    case duplicateMetadataKey(String)
    case invalidSegmentSourceRange(index: Int)
    case invalidSegmentOutputRange(index: Int)
    case nonmonotonicSegmentSourceRange(index: Int)
    case noncontiguousSegmentOutput(index: Int)
    case incompleteSegmentOutput
    case invalidSourceModeSegment(index: Int)
    case invalidRenderedModeSegment(index: Int)
    case invalidSourceModeCounts
    case renderedSegmentCountExceedsTokenCount
}

public enum ThreeWayWebPageComparisonError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case mismatchedSource(
        expected: ThreeWayWebPageComparisonSource,
        actual: ThreeWayWebPageComparisonSource
    )
    case mismatchedSnapshotSet(
        source: ThreeWayWebPageComparisonSource,
        expectedIdentifier: String,
        actualIdentifier: String
    )
    case mismatchedSnapshotGeneration(
        source: ThreeWayWebPageComparisonSource,
        middleGeneration: UInt64,
        actualGeneration: UInt64
    )
    case staleSnapshot(
        source: ThreeWayWebPageComparisonSource,
        expectedGeneration: UInt64,
        actualGeneration: UInt64
    )
    case mismatchedMode(
        source: ThreeWayWebPageComparisonSource,
        expected: WebPageComparisonMode,
        actual: WebPageComparisonMode
    )
    case invalidSnapshot(
        source: ThreeWayWebPageComparisonSource,
        issue: ThreeWayWebPageComparisonSnapshotIssue
    )
    case sourceInputTooLarge(source: ThreeWayWebPageComparisonSource, maximumBytes: Int)
    case normalizedInputTooLarge(source: ThreeWayWebPageComparisonSource, maximumBytes: Int)
    case totalNormalizedInputTooLarge(maximumBytes: Int)
    case tooManyTokens(source: ThreeWayWebPageComparisonSource, maximumTokens: Int)
    case tooManyAttributes(source: ThreeWayWebPageComparisonSource, maximumAttributes: Int)
    case tooManyMetadataEntries(source: ThreeWayWebPageComparisonSource, maximumEntries: Int)
    case metadataTooLarge(maximumBytes: Int)
    case tooManyInputLines(source: ThreeWayWebPageComparisonSource, maximumLines: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case tooManyResultRegions(maximumRegions: Int)
    case tooManyMappedSegments(maximumSegments: Int)
    case outputTooLarge(maximumBytes: Int)
    case tooManyOutputLines(maximumLines: Int)
    case lineDiff(LineDiffError)
    case invalidComparisonResult
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Three-way webpage-comparison limits are invalid."
        case .mismatchedSource(let expected, let actual):
            "The \(actual.rawValue) webpage snapshot was supplied in the \(expected.rawValue) position."
        case .mismatchedSnapshotSet(let source, let expected, let actual):
            "The \(source.rawValue) webpage snapshot belongs to set '\(actual)', not '\(expected)'."
        case .mismatchedSnapshotGeneration(let source, let middle, let actual):
            "The \(source.rawValue) webpage snapshot has generation \(actual), not middle generation \(middle)."
        case .staleSnapshot(let source, let expected, let actual):
            "The \(source.rawValue) webpage snapshot has generation \(actual), not \(expected)."
        case .mismatchedMode(let source, let expected, let actual):
            "The \(source.rawValue) webpage snapshot uses \(actual.rawValue) mode, not \(expected.rawValue)."
        case .invalidSnapshot(let source, let issue):
            "The \(source.rawValue) webpage snapshot is invalid: \(Self.description(of: issue))."
        case .sourceInputTooLarge(let source, let maximumBytes):
            "The \(source.rawValue) webpage source exceeds the \(maximumBytes)-byte snapshot limit."
        case .normalizedInputTooLarge(let source, let maximumBytes):
            "The \(source.rawValue) normalized webpage exceeds the \(maximumBytes)-byte input limit."
        case .totalNormalizedInputTooLarge(let maximumBytes):
            "Normalized webpage inputs exceed the \(maximumBytes)-byte total input limit."
        case .tooManyTokens(let source, let maximumTokens):
            "The \(source.rawValue) webpage snapshot exceeds the \(maximumTokens)-token limit."
        case .tooManyAttributes(let source, let maximumAttributes):
            "The \(source.rawValue) webpage snapshot exceeds the \(maximumAttributes)-attribute limit."
        case .tooManyMetadataEntries(let source, let maximumEntries):
            "The \(source.rawValue) webpage snapshot exceeds the \(maximumEntries)-metadata-entry limit."
        case .metadataTooLarge(let maximumBytes):
            "Three-way webpage snapshot metadata exceeds the \(maximumBytes)-byte limit."
        case .tooManyInputLines(let source, let maximumLines):
            "The \(source.rawValue) normalized webpage exceeds the \(maximumLines)-line input limit."
        case .workLimitExceeded(let maximumWorkUnits):
            "Three-way webpage comparison exceeds the \(maximumWorkUnits)-unit work limit."
        case .tooManyResultRegions(let maximumRegions):
            "Three-way webpage comparison exceeds the \(maximumRegions)-region result limit."
        case .tooManyMappedSegments(let maximumSegments):
            "Three-way webpage comparison exceeds the \(maximumSegments)-segment mapping limit."
        case .outputTooLarge(let maximumBytes):
            "Three-way webpage comparison output exceeds the \(maximumBytes)-byte limit."
        case .tooManyOutputLines(let maximumLines):
            "Three-way webpage comparison output exceeds the \(maximumLines)-line limit."
        case .lineDiff(let error):
            error.errorDescription
        case .invalidComparisonResult:
            "Normalized webpage comparison returned an invalid three-way line mapping."
        case .cancelled:
            "Three-way webpage comparison was cancelled."
        }
    }

    private static func description(of issue: ThreeWayWebPageComparisonSnapshotIssue) -> String {
        switch issue {
        case .emptyContextIdentifier:
            "snapshot-set identifier is empty"
        case .negativeSourceByteCount:
            "source byte count is negative"
        case .negativeTokenCount:
            "token count is negative"
        case .negativeAttributeCount:
            "attribute count is negative"
        case .duplicateMetadataKey(let key):
            "metadata key '\(key)' is duplicated"
        case .invalidSegmentSourceRange(let index):
            "segment \(index) has an invalid source range"
        case .invalidSegmentOutputRange(let index):
            "segment \(index) has an invalid normalized-output range"
        case .nonmonotonicSegmentSourceRange(let index):
            "segment \(index) is out of source order"
        case .noncontiguousSegmentOutput(let index):
            "segment \(index) does not continue normalized output"
        case .incompleteSegmentOutput:
            "segments do not cover normalized output"
        case .invalidSourceModeSegment(let index):
            "segment \(index) is incompatible with source mode"
        case .invalidRenderedModeSegment(let index):
            "segment \(index) is incompatible with rendered-text mode"
        case .invalidSourceModeCounts:
            "source-mode text, source byte count, token count, and segments disagree"
        case .renderedSegmentCountExceedsTokenCount:
            "rendered output has more segments than parsed tokens"
        }
    }
}

public enum ThreeWayWebPageComparison: Sendable {
    public static func compare(
        left: ThreeWayWebPageComparisonSnapshot,
        middle: ThreeWayWebPageComparisonSnapshot,
        right: ThreeWayWebPageComparisonSnapshot,
        options: ThreeWayWebPageComparisonOptions = .default
    ) throws -> ThreeWayWebPageComparisonResult {
        try validate(options.limits)
        try checkCancellation()

        let expectedContext = options.expectedContext ?? middle.context
        let contextIsAuthoritative = options.expectedContext != nil
        let expectedMode = middle.mode
        var budget = WorkBudget(
            maximumWorkUnits: options.limits.maximumWorkUnits
        )
        var totalNormalizedBytes = 0
        var totalMetadataBytes = try boundedUTF8Count(
            expectedContext.identifier,
            maximumBytes: options.limits.maximumMetadataBytes,
            error: .metadataTooLarge(maximumBytes: options.limits.maximumMetadataBytes)
        )

        let leftNormalizedByteCount = try validate(
            left,
            expectedSource: .left,
            expectedContext: expectedContext,
            contextIsAuthoritative: contextIsAuthoritative,
            expectedMode: expectedMode,
            limits: options.limits,
            totalNormalizedBytes: &totalNormalizedBytes,
            totalMetadataBytes: &totalMetadataBytes,
            budget: &budget
        )
        let middleNormalizedByteCount = try validate(
            middle,
            expectedSource: .middle,
            expectedContext: expectedContext,
            contextIsAuthoritative: contextIsAuthoritative,
            expectedMode: expectedMode,
            limits: options.limits,
            totalNormalizedBytes: &totalNormalizedBytes,
            totalMetadataBytes: &totalMetadataBytes,
            budget: &budget
        )
        let rightNormalizedByteCount = try validate(
            right,
            expectedSource: .right,
            expectedContext: expectedContext,
            contextIsAuthoritative: contextIsAuthoritative,
            expectedMode: expectedMode,
            limits: options.limits,
            totalNormalizedBytes: &totalNormalizedBytes,
            totalMetadataBytes: &totalMetadataBytes,
            budget: &budget
        )

        let mergeResult = try merge(
            left: left,
            middle: middle,
            right: right,
            options: options
        )
        let leftOffsets = try lineOffsets(
            mergeResult.left,
            expectedUTF8ByteCount: leftNormalizedByteCount,
            budget: &budget
        )
        let middleOffsets = try lineOffsets(
            mergeResult.base,
            expectedUTF8ByteCount: middleNormalizedByteCount,
            budget: &budget
        )
        let rightOffsets = try lineOffsets(
            mergeResult.right,
            expectedUTF8ByteCount: rightNormalizedByteCount,
            budget: &budget
        )

        var leftMapper = SegmentMapper(segments: left.document.segments)
        var middleMapper = SegmentMapper(segments: middle.document.segments)
        var rightMapper = SegmentMapper(segments: right.document.segments)
        var mappedSegmentCount = 0
        var regions: [ThreeWayWebPageComparisonRegion] = []
        regions.reserveCapacity(mergeResult.regions.count)
        var differences: [ThreeWayWebPageComparisonRegion] = []
        var conflicts: [ThreeWayWebPageComparisonRegion] = []

        for (index, mergedRegion) in mergeResult.regions.enumerated() {
            if index.isMultiple(of: 4_096) { try checkCancellation() }
            try budget.consume(1)
            let leftLocation = try location(
                lineRange: mergedRegion.leftRange,
                offsets: leftOffsets,
                mapper: &leftMapper,
                mappedSegmentCount: &mappedSegmentCount,
                limits: options.limits,
                budget: &budget
            )
            let middleLocation = try location(
                lineRange: mergedRegion.baseRange,
                offsets: middleOffsets,
                mapper: &middleMapper,
                mappedSegmentCount: &mappedSegmentCount,
                limits: options.limits,
                budget: &budget
            )
            let rightLocation = try location(
                lineRange: mergedRegion.rightRange,
                offsets: rightOffsets,
                mapper: &rightMapper,
                mappedSegmentCount: &mappedSegmentCount,
                limits: options.limits,
                budget: &budget
            )
            let region = ThreeWayWebPageComparisonRegion(
                id: mergedRegion.id,
                left: leftLocation,
                middle: middleLocation,
                right: rightLocation,
                resolution: mergedRegion.resolution
            )
            regions.append(region)
            if region.isDifference { differences.append(region) }
            if region.isConflict { conflicts.append(region) }
        }

        let equality = try equality(from: regions)
        let outcome = outcome(
            equality: equality,
            hasConflicts: !conflicts.isEmpty
        )
        let automaticallyMergedComparisonText = try automaticallyMergedComparisonText(
            mode: expectedMode,
            outcome: outcome,
            mergedText: mergeResult.mergedText,
            left: left.normalizedText,
            middle: middle.normalizedText,
            right: right.normalizedText
        )
        try checkCancellation()
        return ThreeWayWebPageComparisonResult(
            context: expectedContext,
            mode: expectedMode,
            left: left,
            middle: middle,
            right: right,
            regions: regions,
            differences: differences,
            conflicts: conflicts,
            outcome: outcome,
            automaticallyMergedComparisonText: automaticallyMergedComparisonText,
            leftEqualsMiddle: equality.leftEqualsMiddle,
            rightEqualsMiddle: equality.rightEqualsMiddle,
            leftEqualsRight: equality.leftEqualsRight
        )
    }

    private struct Equality {
        let leftEqualsMiddle: Bool
        let rightEqualsMiddle: Bool
        let leftEqualsRight: Bool
    }

    private struct WorkBudget {
        let maximumWorkUnits: Int
        private var remainingWorkUnits: Int

        init(maximumWorkUnits: Int) {
            self.maximumWorkUnits = maximumWorkUnits
            remainingWorkUnits = maximumWorkUnits
        }

        mutating func consume(_ amount: Int) throws {
            guard amount >= 0, amount <= remainingWorkUnits else {
                throw ThreeWayWebPageComparisonError.workLimitExceeded(
                    maximumWorkUnits: maximumWorkUnits
                )
            }
            remainingWorkUnits -= amount
        }
    }

    private struct SegmentMapper {
        let segments: [WebPageComparisonSegment]
        private var firstCandidate = 0

        init(segments: [WebPageComparisonSegment]) {
            self.segments = segments
        }

        mutating func segments(
            intersecting outputRange: Range<Int>,
            maximumCount: Int,
            configuredMaximum: Int,
            budget: inout WorkBudget
        ) throws -> [WebPageComparisonSegment] {
            guard !outputRange.isEmpty else { return [] }
            while firstCandidate < segments.count,
                segments[firstCandidate].outputUTF8Range.upperBound <= outputRange.lowerBound
            {
                if firstCandidate.isMultiple(of: 4_096) { try checkCancellation() }
                firstCandidate += 1
                try budget.consume(1)
            }

            var result: [WebPageComparisonSegment] = []
            var index = firstCandidate
            while index < segments.count,
                segments[index].outputUTF8Range.lowerBound < outputRange.upperBound
            {
                if index.isMultiple(of: 4_096) { try checkCancellation() }
                try budget.consume(1)
                if segments[index].outputUTF8Range.upperBound > outputRange.lowerBound {
                    guard result.count < maximumCount else {
                        throw ThreeWayWebPageComparisonError.tooManyMappedSegments(
                            maximumSegments: configuredMaximum
                        )
                    }
                    result.append(segments[index])
                }
                index += 1
            }
            return result
        }
    }

    private static func validate(_ limits: ThreeWayWebPageComparisonLimits) throws {
        guard limits.maximumSourceInputBytesPerSnapshot >= 0,
            limits.maximumNormalizedInputBytesPerSnapshot >= 0,
            limits.maximumTokenCountPerSnapshot >= 0,
            limits.maximumAttributeCountPerSnapshot >= 0,
            limits.maximumTotalNormalizedInputBytes >= 0,
            limits.maximumInputLinesPerSnapshot >= 0,
            limits.maximumMetadataEntriesPerSnapshot >= 0,
            limits.maximumMetadataBytes >= 0,
            limits.maximumWorkUnits >= 0,
            limits.maximumResultRegions >= 0,
            limits.maximumMappedSegments >= 0,
            limits.maximumOutputBytes >= 0,
            limits.maximumOutputLines >= 0
        else {
            throw ThreeWayWebPageComparisonError.invalidLimits
        }
    }

    private static func validate(
        _ snapshot: ThreeWayWebPageComparisonSnapshot,
        expectedSource: ThreeWayWebPageComparisonSource,
        expectedContext: ThreeWayWebPageComparisonContext,
        contextIsAuthoritative: Bool,
        expectedMode: WebPageComparisonMode,
        limits: ThreeWayWebPageComparisonLimits,
        totalNormalizedBytes: inout Int,
        totalMetadataBytes: inout Int,
        budget: inout WorkBudget
    ) throws -> Int {
        try checkCancellation()
        guard snapshot.source == expectedSource else {
            throw ThreeWayWebPageComparisonError.mismatchedSource(
                expected: expectedSource,
                actual: snapshot.source
            )
        }
        guard !snapshot.context.identifier.isEmpty else {
            throw invalidSnapshot(snapshot.source, .emptyContextIdentifier)
        }
        let contextByteCount = try boundedUTF8Count(
            snapshot.context.identifier,
            maximumBytes: limits.maximumMetadataBytes - totalMetadataBytes,
            error: .metadataTooLarge(maximumBytes: limits.maximumMetadataBytes)
        )
        try addMetadataBytes(
            contextByteCount,
            total: &totalMetadataBytes,
            maximumBytes: limits.maximumMetadataBytes
        )
        guard snapshot.context.identifier == expectedContext.identifier else {
            throw ThreeWayWebPageComparisonError.mismatchedSnapshotSet(
                source: snapshot.source,
                expectedIdentifier: expectedContext.identifier,
                actualIdentifier: snapshot.context.identifier
            )
        }
        guard snapshot.context.generation == expectedContext.generation else {
            if contextIsAuthoritative {
                throw ThreeWayWebPageComparisonError.staleSnapshot(
                    source: snapshot.source,
                    expectedGeneration: expectedContext.generation,
                    actualGeneration: snapshot.context.generation
                )
            }
            throw ThreeWayWebPageComparisonError.mismatchedSnapshotGeneration(
                source: snapshot.source,
                middleGeneration: expectedContext.generation,
                actualGeneration: snapshot.context.generation
            )
        }
        guard snapshot.mode == expectedMode else {
            throw ThreeWayWebPageComparisonError.mismatchedMode(
                source: snapshot.source,
                expected: expectedMode,
                actual: snapshot.mode
            )
        }

        let document = snapshot.document
        guard document.sourceUTF8ByteCount >= 0 else {
            throw invalidSnapshot(snapshot.source, .negativeSourceByteCount)
        }
        guard document.tokenCount >= 0 else {
            throw invalidSnapshot(snapshot.source, .negativeTokenCount)
        }
        guard document.attributeCount >= 0 else {
            throw invalidSnapshot(snapshot.source, .negativeAttributeCount)
        }
        guard document.sourceUTF8ByteCount <= limits.maximumSourceInputBytesPerSnapshot else {
            throw ThreeWayWebPageComparisonError.sourceInputTooLarge(
                source: snapshot.source,
                maximumBytes: limits.maximumSourceInputBytesPerSnapshot
            )
        }
        try budget.consume(document.sourceUTF8ByteCount)
        let normalizedByteCount = try boundedUTF8Count(
            document.comparisonText,
            maximumBytes: limits.maximumNormalizedInputBytesPerSnapshot,
            error: .normalizedInputTooLarge(
                source: snapshot.source,
                maximumBytes: limits.maximumNormalizedInputBytesPerSnapshot
            ),
            budget: &budget
        )
        guard normalizedByteCount <= limits.maximumTotalNormalizedInputBytes - totalNormalizedBytes else {
            throw ThreeWayWebPageComparisonError.totalNormalizedInputTooLarge(
                maximumBytes: limits.maximumTotalNormalizedInputBytes
            )
        }
        totalNormalizedBytes += normalizedByteCount
        guard document.tokenCount <= limits.maximumTokenCountPerSnapshot else {
            throw ThreeWayWebPageComparisonError.tooManyTokens(
                source: snapshot.source,
                maximumTokens: limits.maximumTokenCountPerSnapshot
            )
        }
        guard document.attributeCount <= limits.maximumAttributeCountPerSnapshot else {
            throw ThreeWayWebPageComparisonError.tooManyAttributes(
                source: snapshot.source,
                maximumAttributes: limits.maximumAttributeCountPerSnapshot
            )
        }
        guard snapshot.metadata.count <= limits.maximumMetadataEntriesPerSnapshot else {
            throw ThreeWayWebPageComparisonError.tooManyMetadataEntries(
                source: snapshot.source,
                maximumEntries: limits.maximumMetadataEntriesPerSnapshot
            )
        }

        var metadataKeys: Set<String> = []
        metadataKeys.reserveCapacity(snapshot.metadata.count)
        for (index, entry) in snapshot.metadata.enumerated() {
            if index.isMultiple(of: 4_096) { try checkCancellation() }
            let keyByteCount = try boundedUTF8Count(
                entry.key,
                maximumBytes: limits.maximumMetadataBytes - totalMetadataBytes,
                error: .metadataTooLarge(maximumBytes: limits.maximumMetadataBytes)
            )
            if !metadataKeys.insert(entry.key).inserted {
                throw invalidSnapshot(snapshot.source, .duplicateMetadataKey(entry.key))
            }
            try addMetadataBytes(
                keyByteCount,
                total: &totalMetadataBytes,
                maximumBytes: limits.maximumMetadataBytes
            )
            let valueByteCount = try boundedUTF8Count(
                entry.value,
                maximumBytes: limits.maximumMetadataBytes - totalMetadataBytes,
                error: .metadataTooLarge(maximumBytes: limits.maximumMetadataBytes)
            )
            try addMetadataBytes(
                valueByteCount,
                total: &totalMetadataBytes,
                maximumBytes: limits.maximumMetadataBytes
            )
        }

        try validateSegments(
            document,
            source: snapshot.source,
            normalizedByteCount: normalizedByteCount,
            budget: &budget
        )
        return normalizedByteCount
    }

    private static func validateSegments(
        _ document: WebPageComparisonDocument,
        source: ThreeWayWebPageComparisonSource,
        normalizedByteCount: Int,
        budget: inout WorkBudget
    ) throws {
        var previousSourceEnd = 0
        var previousOutputEnd = 0
        for (index, segment) in document.segments.enumerated() {
            if index.isMultiple(of: 4_096) { try checkCancellation() }
            try budget.consume(1)
            let sourceRange = segment.sourceUTF8Range
            let outputRange = segment.outputUTF8Range
            guard sourceRange.lowerBound >= 0,
                sourceRange.upperBound > sourceRange.lowerBound,
                sourceRange.upperBound <= document.sourceUTF8ByteCount
            else {
                throw invalidSnapshot(source, .invalidSegmentSourceRange(index: index))
            }
            guard sourceRange.lowerBound >= previousSourceEnd else {
                throw invalidSnapshot(source, .nonmonotonicSegmentSourceRange(index: index))
            }
            guard outputRange.lowerBound >= 0,
                outputRange.upperBound > outputRange.lowerBound,
                outputRange.upperBound <= normalizedByteCount
            else {
                throw invalidSnapshot(source, .invalidSegmentOutputRange(index: index))
            }
            guard outputRange.lowerBound == previousOutputEnd else {
                throw invalidSnapshot(source, .noncontiguousSegmentOutput(index: index))
            }
            if document.mode == .source,
                segment.kind == .renderedBoundary || sourceRange != outputRange
            {
                throw invalidSnapshot(source, .invalidSourceModeSegment(index: index))
            }
            if document.mode == .renderedText,
                segment.kind != .text && segment.kind != .renderedBoundary
            {
                throw invalidSnapshot(source, .invalidRenderedModeSegment(index: index))
            }
            previousSourceEnd = sourceRange.upperBound
            previousOutputEnd = outputRange.upperBound
        }
        guard previousOutputEnd == normalizedByteCount else {
            throw invalidSnapshot(source, .incompleteSegmentOutput)
        }
        if document.mode == .source {
            guard normalizedByteCount == document.sourceUTF8ByteCount,
                previousSourceEnd == document.sourceUTF8ByteCount,
                document.segments.count == document.tokenCount
            else {
                throw invalidSnapshot(source, .invalidSourceModeCounts)
            }
        } else if document.segments.count > document.tokenCount {
            throw invalidSnapshot(source, .renderedSegmentCountExceedsTokenCount)
        }
    }

    private static func merge(
        left: ThreeWayWebPageComparisonSnapshot,
        middle: ThreeWayWebPageComparisonSnapshot,
        right: ThreeWayWebPageComparisonSnapshot,
        options: ThreeWayWebPageComparisonOptions
    ) throws -> ThreeWayTextMergeResult {
        let limits = options.limits
        let mergeOptions = ThreeWayTextMergeOptions(
            diffAlgorithm: options.diffAlgorithm,
            maximumInputBytes: limits.maximumNormalizedInputBytesPerSnapshot,
            maximumInputLines: limits.maximumInputLinesPerSnapshot,
            maximumOutputBytes: limits.maximumOutputBytes,
            maximumOutputLines: limits.maximumOutputLines,
            maximumRegions: limits.maximumResultRegions
        )
        try checkCancellation()
        do {
            let result = try ThreeWayTextMerge.merge(
                base: middle.normalizedText,
                left: left.normalizedText,
                right: right.normalizedText,
                options: mergeOptions
            )
            try checkCancellation()
            return result
        } catch {
            try checkCancellation()
            if error is CancellationError {
                throw ThreeWayWebPageComparisonError.cancelled
            }
            if let error = error as? LineDiffError {
                throw ThreeWayWebPageComparisonError.lineDiff(error)
            }
            guard let error = error as? ThreeWayTextMergeError else { throw error }
            switch error {
            case .inputTooLarge(let source, let maximumBytes):
                throw ThreeWayWebPageComparisonError.normalizedInputTooLarge(
                    source: webSource(source),
                    maximumBytes: maximumBytes
                )
            case .tooManyLines(let source, let maximumLines):
                throw ThreeWayWebPageComparisonError.tooManyInputLines(
                    source: webSource(source),
                    maximumLines: maximumLines
                )
            case .outputTooLarge(let maximumBytes):
                throw ThreeWayWebPageComparisonError.outputTooLarge(maximumBytes: maximumBytes)
            case .tooManyOutputLines(let maximumLines):
                throw ThreeWayWebPageComparisonError.tooManyOutputLines(
                    maximumLines: maximumLines
                )
            case .tooManyRegions(let maximumRegions):
                throw ThreeWayWebPageComparisonError.tooManyResultRegions(
                    maximumRegions: maximumRegions
                )
            case .invalidDiffResult:
                throw ThreeWayWebPageComparisonError.invalidComparisonResult
            }
        }
    }

    private static func lineOffsets(
        _ document: ThreeWayTextMergeDocument,
        expectedUTF8ByteCount: Int,
        budget: inout WorkBudget
    ) throws -> [Int] {
        var offsets: [Int] = [0]
        offsets.reserveCapacity(document.lines.count + 1)
        var offset = 0
        for (index, line) in document.lines.enumerated() {
            if index.isMultiple(of: 4_096) { try checkCancellation() }
            try budget.consume(1)
            let contentEnd = offset.addingReportingOverflow(line.text.utf8.count)
            guard !contentEnd.overflow else {
                throw ThreeWayWebPageComparisonError.invalidComparisonResult
            }
            let lineEnd = contentEnd.partialValue.addingReportingOverflow(
                line.lineEnding?.rawValue.utf8.count ?? 0
            )
            guard !lineEnd.overflow, lineEnd.partialValue <= expectedUTF8ByteCount else {
                throw ThreeWayWebPageComparisonError.invalidComparisonResult
            }
            offset = lineEnd.partialValue
            offsets.append(offset)
        }
        guard offset == expectedUTF8ByteCount else {
            throw ThreeWayWebPageComparisonError.invalidComparisonResult
        }
        return offsets
    }

    private static func location(
        lineRange: Range<Int>,
        offsets: [Int],
        mapper: inout SegmentMapper,
        mappedSegmentCount: inout Int,
        limits: ThreeWayWebPageComparisonLimits,
        budget: inout WorkBudget
    ) throws -> ThreeWayWebPageComparisonLocation {
        guard lineRange.lowerBound >= 0,
            lineRange.upperBound >= lineRange.lowerBound,
            lineRange.upperBound < offsets.count
        else {
            throw ThreeWayWebPageComparisonError.invalidComparisonResult
        }
        let normalizedRange = offsets[lineRange.lowerBound]..<offsets[lineRange.upperBound]
        let segments = try mapper.segments(
            intersecting: normalizedRange,
            maximumCount: limits.maximumMappedSegments - mappedSegmentCount,
            configuredMaximum: limits.maximumMappedSegments,
            budget: &budget
        )
        mappedSegmentCount += segments.count
        return ThreeWayWebPageComparisonLocation(
            lineRange: lineRange,
            normalizedUTF8Range: normalizedRange,
            contributingSegments: segments
        )
    }

    private static func equality(
        from regions: [ThreeWayWebPageComparisonRegion]
    ) throws -> Equality {
        var leftEqualsMiddle = true
        var rightEqualsMiddle = true
        var leftEqualsRight = true
        for (index, region) in regions.enumerated() {
            if index.isMultiple(of: 4_096) { try checkCancellation() }
            switch region.resolution {
            case .unchanged:
                break
            case .left:
                leftEqualsMiddle = false
                leftEqualsRight = false
            case .right:
                rightEqualsMiddle = false
                leftEqualsRight = false
            case .identical:
                leftEqualsMiddle = false
                rightEqualsMiddle = false
            case .conflict:
                leftEqualsMiddle = false
                rightEqualsMiddle = false
                leftEqualsRight = false
            }
        }
        return Equality(
            leftEqualsMiddle: leftEqualsMiddle,
            rightEqualsMiddle: rightEqualsMiddle,
            leftEqualsRight: leftEqualsRight
        )
    }

    private static func outcome(
        equality: Equality,
        hasConflicts: Bool
    ) -> ThreeWayWebPageComparisonOutcome {
        if equality.leftEqualsMiddle, equality.rightEqualsMiddle { return .equal }
        if equality.rightEqualsMiddle { return .leftOnly }
        if equality.leftEqualsMiddle { return .rightOnly }
        if equality.leftEqualsRight { return .identical }
        return hasConflicts ? .conflict : .merged
    }

    private static func automaticallyMergedComparisonText(
        mode: WebPageComparisonMode,
        outcome: ThreeWayWebPageComparisonOutcome,
        mergedText: String?,
        left: String,
        middle: String,
        right: String
    ) throws -> String? {
        guard mode == .source, outcome == .merged, let mergedText else { return mergedText }
        for candidate in [left, middle, right] {
            if try utf8BytesAreEqual(mergedText, candidate) { return candidate }
        }
        try checkCancellation()
        return nil
    }

    private static func utf8BytesAreEqual(_ left: String, _ right: String) throws -> Bool {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        var comparedByteCount = 0
        while true {
            if comparedByteCount.isMultiple(of: 64 * 1024) { try checkCancellation() }
            let leftByte = leftIterator.next()
            let rightByte = rightIterator.next()
            guard leftByte == rightByte else { return false }
            guard leftByte != nil else {
                try checkCancellation()
                return true
            }
            comparedByteCount += 1
        }
    }

    private static func addMetadataBytes(
        _ count: Int,
        total: inout Int,
        maximumBytes: Int
    ) throws {
        guard count <= maximumBytes - total else {
            throw ThreeWayWebPageComparisonError.metadataTooLarge(
                maximumBytes: maximumBytes
            )
        }
        total += count
    }

    private static func boundedUTF8Count(
        _ value: String,
        maximumBytes: Int,
        error: ThreeWayWebPageComparisonError
    ) throws -> Int {
        guard maximumBytes >= 0 else { throw error }
        var count = 0
        for _ in value.utf8 {
            if count.isMultiple(of: 64 * 1024) { try checkCancellation() }
            guard count < maximumBytes else { throw error }
            count += 1
        }
        return count
    }

    private static func boundedUTF8Count(
        _ value: String,
        maximumBytes: Int,
        error: ThreeWayWebPageComparisonError,
        budget: inout WorkBudget
    ) throws -> Int {
        guard maximumBytes >= 0 else { throw error }
        var count = 0
        var unchargedCount = 0
        for _ in value.utf8 {
            if count.isMultiple(of: 64 * 1024) { try checkCancellation() }
            guard count < maximumBytes else {
                try budget.consume(unchargedCount + 1)
                throw error
            }
            count += 1
            unchargedCount += 1
            if unchargedCount == 4_096 {
                try budget.consume(unchargedCount)
                unchargedCount = 0
            }
        }
        try budget.consume(unchargedCount)
        return count
    }

    private static func invalidSnapshot(
        _ source: ThreeWayWebPageComparisonSource,
        _ issue: ThreeWayWebPageComparisonSnapshotIssue
    ) -> ThreeWayWebPageComparisonError {
        .invalidSnapshot(source: source, issue: issue)
    }

    private static func webSource(
        _ source: ThreeWayTextMergeSource
    ) -> ThreeWayWebPageComparisonSource {
        switch source {
        case .base: .middle
        case .left: .left
        case .right: .right
        }
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw ThreeWayWebPageComparisonError.cancelled }
    }
}
