import Foundation

public enum ThreeWayFolderComparisonSide: String, CaseIterable, Equatable, Hashable, Sendable {
    case left
    case middle
    case right
}

public enum ThreeWayFolderComparisonResolution: String, CaseIterable, Equatable, Hashable, Sendable {
    case unchanged
    case left
    case right
    case identical
    case conflict

    public var isChange: Bool { self != .unchanged }
    public var isConflict: Bool { self == .conflict }

    /// Source selected by an automatic merge. `nil` means manual conflict resolution is required.
    public var automaticSource: ThreeWayFolderComparisonSide? {
        switch self {
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
}

public enum ThreeWayFolderPresence: UInt8, CaseIterable, Equatable, Hashable, Sendable {
    case leftOnly = 1
    case middleOnly = 2
    case leftAndMiddle = 3
    case rightOnly = 4
    case leftAndRight = 5
    case middleAndRight = 6
    case all = 7

    public func contains(_ side: ThreeWayFolderComparisonSide) -> Bool {
        let mask: UInt8 =
            switch side {
            case .left: 1
            case .middle: 2
            case .right: 4
            }
        return rawValue & mask != 0
    }
}

public enum ThreeWayFolderTypeState: Equatable, Sendable {
    case uniform(FolderEntryKind)
    case mixed
}

/// Presence of values in one ordered pair. "First" and "second" refer to the pair property name.
public enum ThreeWayFolderPairPresenceState: String, CaseIterable, Equatable, Hashable, Sendable {
    case neither
    case firstOnly
    case secondOnly
    case both
}

public enum ThreeWayFolderPairTypeState: String, CaseIterable, Equatable, Hashable, Sendable {
    case notComparable
    case same
    case different
}

public enum ThreeWayFolderPairContentState: String, CaseIterable, Equatable, Hashable, Sendable {
    /// The pair does not contain two regular files of the same type.
    case notApplicable
    /// Metadata-only comparison was requested.
    case notCompared
    /// Content comparison was requested, but one or both digests were unavailable.
    case unavailable
    case equal
    case different
}

public struct ThreeWayFolderPairComparison: Equatable, Sendable {
    public let presenceState: ThreeWayFolderPairPresenceState
    public let typeState: ThreeWayFolderPairTypeState
    public let metadataDifferences: [FolderMetadataField]
    public let contentState: ThreeWayFolderPairContentState
    public let isEquivalent: Bool

    fileprivate init(
        presenceState: ThreeWayFolderPairPresenceState,
        typeState: ThreeWayFolderPairTypeState,
        metadataDifferences: [FolderMetadataField],
        contentState: ThreeWayFolderPairContentState,
        isEquivalent: Bool
    ) {
        self.presenceState = presenceState
        self.typeState = typeState
        self.metadataDifferences = metadataDifferences
        self.contentState = contentState
        self.isEquivalent = isEquivalent
    }
}

public struct ThreeWayFolderPairComparisons: Equatable, Sendable {
    /// First is left; second is middle.
    public let leftAndMiddle: ThreeWayFolderPairComparison
    /// First is right; second is middle.
    public let rightAndMiddle: ThreeWayFolderPairComparison
    /// First is left; second is right.
    public let leftAndRight: ThreeWayFolderPairComparison

    fileprivate init(
        leftAndMiddle: ThreeWayFolderPairComparison,
        rightAndMiddle: ThreeWayFolderPairComparison,
        leftAndRight: ThreeWayFolderPairComparison
    ) {
        self.leftAndMiddle = leftAndMiddle
        self.rightAndMiddle = rightAndMiddle
        self.leftAndRight = leftAndRight
    }
}

public struct ThreeWayFolderEquality: Equatable, Sendable {
    public let leftEqualsMiddle: Bool
    public let rightEqualsMiddle: Bool
    public let leftEqualsRight: Bool

    fileprivate init(comparisons: ThreeWayFolderPairComparisons) {
        leftEqualsMiddle = comparisons.leftAndMiddle.isEquivalent
        rightEqualsMiddle = comparisons.rightAndMiddle.isEquivalent
        leftEqualsRight = comparisons.leftAndRight.isEquivalent
    }
}

public enum ThreeWayFolderConflictKind: String, CaseIterable, Equatable, Hashable, Sendable {
    /// Left and right independently added different values at a path absent from middle.
    case divergentInsertion
    case deletionVersusChange
    case typeMismatch
    case contentDifference
    case metadataDifference
}

public struct ThreeWayFolderComparisonEntry: Identifiable, Equatable, Sendable {
    public struct ID: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue.precomposedStringWithCanonicalMapping
        }
    }

    public let id: ID
    public let left: FolderEntry?
    public let middle: FolderEntry?
    public let right: FolderEntry?
    public let presence: ThreeWayFolderPresence
    public let typeState: ThreeWayFolderTypeState
    public let comparisons: ThreeWayFolderPairComparisons
    public let equality: ThreeWayFolderEquality
    public let resolution: ThreeWayFolderComparisonResolution
    public let conflictKind: ThreeWayFolderConflictKind?

    public var normalizedRelativePath: String { id.rawValue }
    public var isChange: Bool { resolution.isChange }
    public var isConflict: Bool { resolution.isConflict }

    fileprivate init(
        normalizedRelativePath: String,
        left: FolderEntry?,
        middle: FolderEntry?,
        right: FolderEntry?,
        comparisons: ThreeWayFolderPairComparisons,
        resolution: ThreeWayFolderComparisonResolution,
        conflictKind: ThreeWayFolderConflictKind?
    ) {
        id = ID(rawValue: normalizedRelativePath)
        self.left = left
        self.middle = middle
        self.right = right
        presence = Self.presence(left: left, middle: middle, right: right)
        typeState = Self.typeState(left: left, middle: middle, right: right)
        self.comparisons = comparisons
        equality = ThreeWayFolderEquality(comparisons: comparisons)
        self.resolution = resolution
        self.conflictKind = conflictKind
    }

    private static func presence(
        left: FolderEntry?,
        middle: FolderEntry?,
        right: FolderEntry?
    ) -> ThreeWayFolderPresence {
        let rawValue = (left == nil ? 0 : 1) | (middle == nil ? 0 : 2) | (right == nil ? 0 : 4)
        guard let presence = ThreeWayFolderPresence(rawValue: UInt8(rawValue)) else {
            preconditionFailure("A three-way folder result requires at least one entry")
        }
        return presence
    }

    private static func typeState(
        left: FolderEntry?,
        middle: FolderEntry?,
        right: FolderEntry?
    ) -> ThreeWayFolderTypeState {
        let kinds = [left?.kind, middle?.kind, right?.kind].compactMap { $0 }
        guard let first = kinds.first else {
            preconditionFailure("A three-way folder result requires at least one entry")
        }
        return kinds.dropFirst().allSatisfy { $0 == first } ? .uniform(first) : .mixed
    }
}

public struct ThreeWayFolderComparisonSummary: Equatable, Sendable {
    public let leftInputEntryCount: Int
    public let middleInputEntryCount: Int
    public let rightInputEntryCount: Int
    public let entryCount: Int
    public let unchangedEntryCount: Int
    public let leftChangeEntryCount: Int
    public let rightChangeEntryCount: Int
    public let identicalChangeEntryCount: Int
    public let conflictEntryCount: Int
    public let presenceDifferenceEntryCount: Int
    public let typeMismatchEntryCount: Int
    public let metadataDifferenceEntryCount: Int
    public let contentDifferenceEntryCount: Int
    public let unavailableContentEntryCount: Int

    public var changedEntryCount: Int {
        leftChangeEntryCount
            + rightChangeEntryCount
            + identicalChangeEntryCount
            + conflictEntryCount
    }

    public var hasChanges: Bool { changedEntryCount > 0 }
    public var hasConflicts: Bool { conflictEntryCount > 0 }

    fileprivate init(
        leftInputEntryCount: Int,
        middleInputEntryCount: Int,
        rightInputEntryCount: Int,
        counts: ThreeWayFolderMutableCounts
    ) {
        self.leftInputEntryCount = leftInputEntryCount
        self.middleInputEntryCount = middleInputEntryCount
        self.rightInputEntryCount = rightInputEntryCount
        entryCount = counts.entries
        unchangedEntryCount = counts.unchanged
        leftChangeEntryCount = counts.left
        rightChangeEntryCount = counts.right
        identicalChangeEntryCount = counts.identical
        conflictEntryCount = counts.conflicts
        presenceDifferenceEntryCount = counts.presenceDifferences
        typeMismatchEntryCount = counts.typeMismatches
        metadataDifferenceEntryCount = counts.metadataDifferences
        contentDifferenceEntryCount = counts.contentDifferences
        unavailableContentEntryCount = counts.unavailableContent
    }
}

public struct ThreeWayFolderComparisonResult: Equatable, Sendable {
    /// Entries sorted by normalized relative-path UTF-8 bytes.
    public let entries: [ThreeWayFolderComparisonEntry]
    public let summary: ThreeWayFolderComparisonSummary
    /// Stable IDs in the same order as `entries`, suitable for next/previous change navigation.
    public let changedEntryIDs: [ThreeWayFolderComparisonEntry.ID]
    /// Stable IDs in the same order as `entries`, suitable for conflict navigation.
    public let conflictEntryIDs: [ThreeWayFolderComparisonEntry.ID]

    public var hasChanges: Bool { summary.hasChanges }
    public var hasConflicts: Bool { summary.hasConflicts }

    fileprivate init(
        entries: [ThreeWayFolderComparisonEntry],
        summary: ThreeWayFolderComparisonSummary,
        changedEntryIDs: [ThreeWayFolderComparisonEntry.ID],
        conflictEntryIDs: [ThreeWayFolderComparisonEntry.ID]
    ) {
        self.entries = entries
        self.summary = summary
        self.changedEntryIDs = changedEntryIDs
        self.conflictEntryIDs = conflictEntryIDs
    }

    public func entry(withID id: ThreeWayFolderComparisonEntry.ID) -> ThreeWayFolderComparisonEntry? {
        var lower = entries.startIndex
        var upper = entries.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if Self.rawUTF8Precedes(entries[middle].id.rawValue, id.rawValue) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let index = lower
        guard entries.indices.contains(index), entries[index].id == id else { return nil }
        return entries[index]
    }

    public func nextChangedEntryID(
        after id: ThreeWayFolderComparisonEntry.ID? = nil
    ) -> ThreeWayFolderComparisonEntry.ID? {
        Self.nextID(after: id, in: changedEntryIDs)
    }

    public func previousChangedEntryID(
        before id: ThreeWayFolderComparisonEntry.ID? = nil
    ) -> ThreeWayFolderComparisonEntry.ID? {
        Self.previousID(before: id, in: changedEntryIDs)
    }

    public func nextConflictEntryID(
        after id: ThreeWayFolderComparisonEntry.ID? = nil
    ) -> ThreeWayFolderComparisonEntry.ID? {
        Self.nextID(after: id, in: conflictEntryIDs)
    }

    public func previousConflictEntryID(
        before id: ThreeWayFolderComparisonEntry.ID? = nil
    ) -> ThreeWayFolderComparisonEntry.ID? {
        Self.previousID(before: id, in: conflictEntryIDs)
    }

    private static func nextID(
        after id: ThreeWayFolderComparisonEntry.ID?,
        in ids: [ThreeWayFolderComparisonEntry.ID]
    ) -> ThreeWayFolderComparisonEntry.ID? {
        guard let id else { return ids.first }
        let index = upperBound(of: id, in: ids)
        return ids.indices.contains(index) ? ids[index] : nil
    }

    private static func previousID(
        before id: ThreeWayFolderComparisonEntry.ID?,
        in ids: [ThreeWayFolderComparisonEntry.ID]
    ) -> ThreeWayFolderComparisonEntry.ID? {
        guard let id else { return ids.last }
        let lowerBound = lowerBound(of: id, in: ids)
        guard lowerBound != ids.startIndex else { return nil }
        return ids[lowerBound - 1]
    }

    private static func lowerBound(
        of id: ThreeWayFolderComparisonEntry.ID,
        in ids: [ThreeWayFolderComparisonEntry.ID]
    ) -> Int {
        var lower = ids.startIndex
        var upper = ids.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if rawUTF8Precedes(ids[middle].rawValue, id.rawValue) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func upperBound(
        of id: ThreeWayFolderComparisonEntry.ID,
        in ids: [ThreeWayFolderComparisonEntry.ID]
    ) -> Int {
        var lower = ids.startIndex
        var upper = ids.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if rawUTF8Precedes(id.rawValue, ids[middle].rawValue) {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return lower
    }

    private static func rawUTF8Precedes(_ left: String, _ right: String) -> Bool {
        left.utf8.lexicographicallyPrecedes(right.utf8)
    }
}

public struct ThreeWayFolderContentDigestProvider: Sendable {
    private let operation:
        @Sendable (
            ThreeWayFolderComparisonSide,
            FolderEntry
        ) async throws -> FolderContentDigest?

    public init(
        _ operation:
            @escaping @Sendable (
                ThreeWayFolderComparisonSide,
                FolderEntry
            ) async throws -> FolderContentDigest?
    ) {
        self.operation = operation
    }

    /// The comparator requests at most one digest per side and normalized path, serially.
    public func digest(
        for entry: FolderEntry,
        side: ThreeWayFolderComparisonSide
    ) async throws -> FolderContentDigest? {
        try await operation(side, entry)
    }
}

public struct ThreeWayFolderComparisonOptions: Equatable, Sendable {
    public static let `default` = ThreeWayFolderComparisonOptions()

    public let comparison: FolderComparisonOptions
    public let maximumEntriesPerSnapshot: Int
    public let maximumResultEntries: Int
    public let maximumRelativePathUTF8Bytes: Int
    public let maximumDigestBytes: Int
    public let maximumDigestAlgorithmUTF8Bytes: Int
    public let maximumWorkUnits: Int

    public init(
        comparison: FolderComparisonOptions = FolderComparisonOptions(),
        maximumEntriesPerSnapshot: Int = 1_000_000,
        maximumResultEntries: Int = 3_000_000,
        maximumRelativePathUTF8Bytes: Int = 16_384,
        maximumDigestBytes: Int = 1_048_576,
        maximumDigestAlgorithmUTF8Bytes: Int = 1_024,
        maximumWorkUnits: Int = 256 * 1_024 * 1_024
    ) {
        self.comparison = comparison
        self.maximumEntriesPerSnapshot = maximumEntriesPerSnapshot
        self.maximumResultEntries = maximumResultEntries
        self.maximumRelativePathUTF8Bytes = maximumRelativePathUTF8Bytes
        self.maximumDigestBytes = maximumDigestBytes
        self.maximumDigestAlgorithmUTF8Bytes = maximumDigestAlgorithmUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
    }
}

public enum ThreeWayFolderComparisonError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case tooManyInputEntries(side: ThreeWayFolderComparisonSide, maximumEntries: Int)
    case tooManyResultEntries(maximumEntries: Int)
    case relativePathTooLong(
        side: ThreeWayFolderComparisonSide,
        relativePath: String,
        maximumUTF8Bytes: Int
    )
    case invalidRelativePath(
        side: ThreeWayFolderComparisonSide,
        relativePath: String,
        error: FolderRelativePathError
    )
    case duplicateNormalizedPath(
        side: ThreeWayFolderComparisonSide,
        normalizedRelativePath: String,
        entryCount: Int
    )
    case digestTooLarge(
        side: ThreeWayFolderComparisonSide,
        relativePath: String,
        maximumBytes: Int
    )
    case digestAlgorithmTooLong(
        side: ThreeWayFolderComparisonSide,
        relativePath: String,
        maximumUTF8Bytes: Int
    )
    case contentDigestUnavailable(
        relativePath: String,
        sides: [ThreeWayFolderComparisonSide]
    )
    case incompatibleContentDigests(
        relativePath: String,
        firstSide: ThreeWayFolderComparisonSide,
        firstAlgorithm: String,
        secondSide: ThreeWayFolderComparisonSide,
        secondAlgorithm: String
    )
    case contentDigestProviderFailed(
        side: ThreeWayFolderComparisonSide,
        relativePath: String,
        errorDomain: String,
        errorCode: Int,
        message: String
    )
    case workLimitExceeded(maximumWorkUnits: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            return "Three-way folder comparison limits must not be negative."
        case .tooManyInputEntries(let side, let maximumEntries):
            return "Three-way folder comparison \(side.rawValue) input exceeds the \(maximumEntries)-entry limit."
        case .tooManyResultEntries(let maximumEntries):
            return "Three-way folder comparison exceeds the \(maximumEntries)-entry result limit."
        case .relativePathTooLong(let side, let relativePath, let maximumBytes):
            return "Three-way folder comparison \(side.rawValue) path \(relativePath) exceeds the \(maximumBytes)-byte UTF-8 limit."
        case .invalidRelativePath(let side, let relativePath, let error):
            return "Three-way folder comparison \(side.rawValue) path \(relativePath) is invalid: \(Self.pathErrorDescription(error))."
        case .duplicateNormalizedPath(let side, let path, let count):
            return "Three-way folder comparison \(side.rawValue) input has \(count) entries normalized to \(path)."
        case .digestTooLarge(let side, let path, let maximumBytes):
            return "Three-way folder comparison \(side.rawValue) digest for \(path) exceeds the \(maximumBytes)-byte limit."
        case .digestAlgorithmTooLong(let side, let path, let maximumBytes):
            return "Three-way folder comparison \(side.rawValue) digest algorithm for \(path) exceeds the \(maximumBytes)-byte UTF-8 limit."
        case .contentDigestUnavailable(let path, let sides):
            let names = sides.map(\.rawValue).joined(separator: ", ")
            return "Three-way folder comparison requires content digests for \(path): \(names)."
        case .incompatibleContentDigests(
            let path,
            let firstSide,
            let firstAlgorithm,
            let secondSide,
            let secondAlgorithm
        ):
            return "Three-way folder comparison has incompatible digests for \(path): "
                + "\(firstSide.rawValue) uses \(firstAlgorithm), "
                + "\(secondSide.rawValue) uses \(secondAlgorithm)."
        case .contentDigestProviderFailed(let side, let path, _, _, let message):
            return "Three-way folder comparison could not obtain the \(side.rawValue) digest for \(path): \(message)"
        case .workLimitExceeded(let maximumWorkUnits):
            return "Three-way folder comparison exceeds the \(maximumWorkUnits)-unit work limit."
        }
    }

    private static func pathErrorDescription(_ error: FolderRelativePathError) -> String {
        switch error {
        case .empty: "path is empty"
        case .absolute: "path is absolute"
        case .parentTraversal: "path contains parent traversal"
        case .containsNull: "path contains a null byte"
        }
    }
}

/// Compares immutable snapshots only. This API performs no filesystem access or path resolution.
/// The middle snapshot is the common baseline used to classify left and right changes.
public enum ThreeWayFolderComparison: Sendable {
    public static func compare(
        left: FolderSnapshot,
        middle: FolderSnapshot,
        right: FolderSnapshot,
        options: ThreeWayFolderComparisonOptions = .default,
        contentDigestProvider: ThreeWayFolderContentDigestProvider? = nil
    ) async throws -> ThreeWayFolderComparisonResult {
        try validate(options)
        try Task.checkCancellation()
        try validateEntryCount(left.entries.count, side: .left, options: options)
        try validateEntryCount(middle.entries.count, side: .middle, options: options)
        try validateEntryCount(right.entries.count, side: .right, options: options)

        var work = ThreeWayFolderWorkBudget(maximum: options.maximumWorkUnits)
        let leftIndex = try index(left.entries, side: .left, options: options, work: &work)
        let middleIndex = try index(middle.entries, side: .middle, options: options, work: &work)
        let rightIndex = try index(right.entries, side: .right, options: options, work: &work)
        let orderedPaths = try orderedPathUnion(
            leftIndex.orderedPaths,
            middleIndex.orderedPaths,
            rightIndex.orderedPaths,
            maximumResultEntries: options.maximumResultEntries,
            work: &work
        )

        var entries: [ThreeWayFolderComparisonEntry] = []
        entries.reserveCapacity(orderedPaths.count)
        var changedEntryIDs: [ThreeWayFolderComparisonEntry.ID] = []
        var conflictEntryIDs: [ThreeWayFolderComparisonEntry.ID] = []
        var counts = ThreeWayFolderMutableCounts()

        for path in orderedPaths {
            try work.consume(1)
            for _ in 0..<3 {
                try work.consume(path.utf8.count)
                try work.consume(1)
            }
            let leftEntry = leftIndex.entries[path]
            let middleEntry = middleIndex.entries[path]
            let rightEntry = rightIndex.entries[path]
            let entriesBySide: [ThreeWayFolderComparisonSide: FolderEntry] = [
                .left: leftEntry,
                .middle: middleEntry,
                .right: rightEntry
            ].compactMapValues { $0 }

            var digestSides: [ThreeWayFolderComparisonSide] = []
            if options.comparison.method != .metadataOnly {
                for pair in comparisonPairs(
                    left: leftEntry,
                    middle: middleEntry,
                    right: rightEntry
                ) {
                    guard pair.first.entry?.kind == .regularFile,
                        pair.second.entry?.kind == .regularFile
                    else {
                        continue
                    }
                    if options.comparison.method == .contentIfAvailable,
                        sizesDiffer(pair.first.entry, pair.second.entry)
                    {
                        continue
                    }
                    if !digestSides.contains(pair.first.side) {
                        digestSides.append(pair.first.side)
                    }
                    if !digestSides.contains(pair.second.side) {
                        digestSides.append(pair.second.side)
                    }
                }
            }

            var digests: [ThreeWayFolderComparisonSide: [ThreeWayFolderPreparedDigest]] = [:]
            for side in ThreeWayFolderComparisonSide.allCases where digestSides.contains(side) {
                guard let entry = entriesBySide[side] else { continue }
                if let digest = entry.contentDigest {
                    digests[side] = [
                        try prepare(
                            digest,
                            side: side,
                            relativePath: path,
                            options: options,
                            work: &work
                        )
                    ]
                } else {
                    digests[side] = []
                }
            }

            if let contentDigestProvider {
                var providerSides: [ThreeWayFolderComparisonSide] = []
                for pair in comparisonPairs(
                    left: leftEntry,
                    middle: middleEntry,
                    right: rightEntry
                ) {
                    guard digestSides.contains(pair.first.side),
                        digestSides.contains(pair.second.side)
                    else {
                        continue
                    }
                    if options.comparison.method == .contentIfAvailable,
                        sizesDiffer(pair.first.entry, pair.second.entry)
                    {
                        continue
                    }
                    if compatibleDigestPair(
                        first: digests[pair.first.side] ?? [],
                        second: digests[pair.second.side] ?? []
                    ) != nil {
                        continue
                    }
                    if !providerSides.contains(pair.first.side) {
                        providerSides.append(pair.first.side)
                    }
                    if !providerSides.contains(pair.second.side) {
                        providerSides.append(pair.second.side)
                    }
                }

                for side in ThreeWayFolderComparisonSide.allCases where providerSides.contains(side) {
                    guard let entry = entriesBySide[side] else { continue }
                    try work.consume(1)
                    try Task.checkCancellation()
                    let provided: FolderContentDigest?
                    do {
                        provided = try await contentDigestProvider.digest(for: entry, side: side)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        let providerError = error as NSError
                        throw ThreeWayFolderComparisonError.contentDigestProviderFailed(
                            side: side,
                            relativePath: path,
                            errorDomain: providerError.domain,
                            errorCode: providerError.code,
                            message: providerError.localizedDescription
                        )
                    }
                    try Task.checkCancellation()
                    if let provided {
                        digests[side, default: []].append(
                            try prepare(
                                provided,
                                side: side,
                                relativePath: path,
                                options: options,
                                work: &work
                            )
                        )
                    }
                }
            }

            let leftAndMiddle = try pairComparison(
                first: (leftEntry, .left),
                second: (middleEntry, .middle),
                relativePath: path,
                options: options,
                digests: digests,
                work: &work
            )
            let rightAndMiddle = try pairComparison(
                first: (rightEntry, .right),
                second: (middleEntry, .middle),
                relativePath: path,
                options: options,
                digests: digests,
                work: &work
            )
            let leftAndRight = try pairComparison(
                first: (leftEntry, .left),
                second: (rightEntry, .right),
                relativePath: path,
                options: options,
                digests: digests,
                work: &work
            )
            let comparisons = ThreeWayFolderPairComparisons(
                leftAndMiddle: leftAndMiddle,
                rightAndMiddle: rightAndMiddle,
                leftAndRight: leftAndRight
            )
            let resolution = resolution(for: comparisons)
            let conflictKind =
                resolution == .conflict
                ? conflictKind(
                    left: leftEntry,
                    middle: middleEntry,
                    right: rightEntry,
                    comparisons: comparisons
                )
                : nil
            let entry = ThreeWayFolderComparisonEntry(
                normalizedRelativePath: path,
                left: leftEntry,
                middle: middleEntry,
                right: rightEntry,
                comparisons: comparisons,
                resolution: resolution,
                conflictKind: conflictKind
            )
            entries.append(entry)
            counts.add(entry)
            if entry.isChange { changedEntryIDs.append(entry.id) }
            if entry.isConflict { conflictEntryIDs.append(entry.id) }
        }
        try Task.checkCancellation()

        return ThreeWayFolderComparisonResult(
            entries: entries,
            summary: ThreeWayFolderComparisonSummary(
                leftInputEntryCount: left.entries.count,
                middleInputEntryCount: middle.entries.count,
                rightInputEntryCount: right.entries.count,
                counts: counts
            ),
            changedEntryIDs: changedEntryIDs,
            conflictEntryIDs: conflictEntryIDs
        )
    }

    private typealias SidedEntry = (entry: FolderEntry?, side: ThreeWayFolderComparisonSide)

    private static func validate(_ options: ThreeWayFolderComparisonOptions) throws {
        guard options.maximumEntriesPerSnapshot >= 0,
            options.maximumResultEntries >= 0,
            options.maximumRelativePathUTF8Bytes >= 0,
            options.maximumDigestBytes >= 0,
            options.maximumDigestAlgorithmUTF8Bytes >= 0,
            options.maximumWorkUnits >= 0
        else {
            throw ThreeWayFolderComparisonError.invalidLimits
        }
    }

    private static func validateEntryCount(
        _ count: Int,
        side: ThreeWayFolderComparisonSide,
        options: ThreeWayFolderComparisonOptions
    ) throws {
        guard count <= options.maximumEntriesPerSnapshot else {
            throw ThreeWayFolderComparisonError.tooManyInputEntries(
                side: side,
                maximumEntries: options.maximumEntriesPerSnapshot
            )
        }
    }

    private static func index(
        _ entries: [FolderEntry],
        side: ThreeWayFolderComparisonSide,
        options: ThreeWayFolderComparisonOptions,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> ThreeWayFolderSnapshotIndex {
        var inputEntries: [ThreeWayFolderInputEntry] = []
        inputEntries.reserveCapacity(entries.count)
        for entry in entries {
            try work.consume(1)
            inputEntries.append(
                ThreeWayFolderInputEntry(
                    entry: entry,
                    relativePathUTF8Count: try utf8Count(entry.relativePath, work: &work)
                )
            )
        }

        var preparedEntries: [ThreeWayFolderPreparedEntry] = []
        preparedEntries.reserveCapacity(entries.count)
        for input in try sortedInputEntries(inputEntries, work: &work) {
            let entry = input.entry
            guard input.relativePathUTF8Count <= options.maximumRelativePathUTF8Bytes else {
                throw ThreeWayFolderComparisonError.relativePathTooLong(
                    side: side,
                    relativePath: entry.relativePath,
                    maximumUTF8Bytes: options.maximumRelativePathUTF8Bytes
                )
            }

            let normalizedPath: String
            do {
                normalizedPath = try FolderComparator.normalize(
                    relativePath: entry.relativePath,
                    caseSensitivity: options.comparison.pathCaseSensitivity
                )
            } catch let error as FolderRelativePathError {
                throw ThreeWayFolderComparisonError.invalidRelativePath(
                    side: side,
                    relativePath: entry.relativePath,
                    error: error
                )
            } catch {
                preconditionFailure("Folder path normalization threw an undocumented error")
            }
            let normalizedByteCount = try utf8Count(normalizedPath, work: &work)
            guard normalizedByteCount <= options.maximumRelativePathUTF8Bytes else {
                throw ThreeWayFolderComparisonError.relativePathTooLong(
                    side: side,
                    relativePath: entry.relativePath,
                    maximumUTF8Bytes: options.maximumRelativePathUTF8Bytes
                )
            }
            preparedEntries.append(
                ThreeWayFolderPreparedEntry(
                    normalizedPath: normalizedPath,
                    normalizedPathUTF8Count: normalizedByteCount,
                    entry: entry
                )
            )
        }

        let sortedEntries = try sortedPreparedEntries(preparedEntries, work: &work)
        var indexedEntries: [String: FolderEntry] = [:]
        indexedEntries.reserveCapacity(sortedEntries.count)
        var orderedPaths: [String] = []
        orderedPaths.reserveCapacity(sortedEntries.count)
        var index = sortedEntries.startIndex
        while index < sortedEntries.endIndex {
            let prepared = sortedEntries[index]
            var nextIndex = index + 1
            while nextIndex < sortedEntries.endIndex,
                try rawUTF8AreEqual(
                    prepared.normalizedPath,
                    sortedEntries[nextIndex].normalizedPath,
                    work: &work
                )
            {
                nextIndex += 1
            }
            guard nextIndex == index + 1 else {
                throw ThreeWayFolderComparisonError.duplicateNormalizedPath(
                    side: side,
                    normalizedRelativePath: prepared.normalizedPath,
                    entryCount: nextIndex - index
                )
            }
            try work.consume(prepared.normalizedPathUTF8Count)
            try work.consume(1)
            indexedEntries[prepared.normalizedPath] = prepared.entry
            orderedPaths.append(prepared.normalizedPath)
            index = nextIndex
        }
        return ThreeWayFolderSnapshotIndex(
            entries: indexedEntries,
            orderedPaths: orderedPaths
        )
    }

    private static func sortedInputEntries(
        _ entries: [ThreeWayFolderInputEntry],
        work: inout ThreeWayFolderWorkBudget
    ) throws -> [ThreeWayFolderInputEntry] {
        try deterministicallySorted(
            entries,
            utf8Count: \ThreeWayFolderInputEntry.relativePathUTF8Count,
            path: { $0.entry.relativePath },
            work: &work
        )
    }

    private static func sortedPreparedEntries(
        _ entries: [ThreeWayFolderPreparedEntry],
        work: inout ThreeWayFolderWorkBudget
    ) throws -> [ThreeWayFolderPreparedEntry] {
        try deterministicallySorted(
            entries,
            utf8Count: \ThreeWayFolderPreparedEntry.normalizedPathUTF8Count,
            path: \ThreeWayFolderPreparedEntry.normalizedPath,
            work: &work
        )
    }

    private static func deterministicallySorted<Element>(
        _ elements: [Element],
        utf8Count: KeyPath<Element, Int>,
        path: (Element) -> String,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> [Element] {
        guard elements.count > 1 else { return elements }

        // Fixed merge passes make work-limit outcomes independent of input and hash order.
        var source = elements
        var destination = elements
        var width = 1
        while width < source.count {
            for element in source {
                try work.consume(element[keyPath: utf8Count])
                try work.consume(1)
            }

            var lowerBound = 0
            while lowerBound < source.count {
                let middle = min(lowerBound + width, source.count)
                let upperBound = min(middle + width, source.count)
                var leftIndex = lowerBound
                var rightIndex = middle
                var destinationIndex = lowerBound
                while leftIndex < middle, rightIndex < upperBound {
                    if rawUTF8Precedes(
                        path(source[rightIndex]),
                        path(source[leftIndex])
                    ) {
                        destination[destinationIndex] = source[rightIndex]
                        rightIndex += 1
                    } else {
                        destination[destinationIndex] = source[leftIndex]
                        leftIndex += 1
                    }
                    destinationIndex += 1
                    if destinationIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
                }
                while leftIndex < middle {
                    destination[destinationIndex] = source[leftIndex]
                    leftIndex += 1
                    destinationIndex += 1
                    if destinationIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
                }
                while rightIndex < upperBound {
                    destination[destinationIndex] = source[rightIndex]
                    rightIndex += 1
                    destinationIndex += 1
                    if destinationIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
                }
                lowerBound = upperBound
            }
            swap(&source, &destination)
            let halfCountRoundedUp = source.count / 2 + source.count % 2
            width = width >= halfCountRoundedUp ? source.count : width * 2
        }
        return source
    }

    private static func orderedPathUnion(
        _ left: [String],
        _ middle: [String],
        _ right: [String],
        maximumResultEntries: Int,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> [String] {
        let pathLists = [left, middle, right]
        var pathIndices = [0, 0, 0]
        var paths: [String] = []
        paths.reserveCapacity(
            min(maximumResultEntries, max(left.count, middle.count, right.count))
        )

        while true {
            var candidate: String?
            for listIndex in pathLists.indices {
                let pathIndex = pathIndices[listIndex]
                guard pathIndex < pathLists[listIndex].count else { continue }
                let path = pathLists[listIndex][pathIndex]
                if let currentCandidate = candidate {
                    if try rawUTF8Precedes(path, currentCandidate, work: &work) {
                        candidate = path
                    }
                } else {
                    candidate = path
                }
            }
            guard let candidate else { return paths }

            for listIndex in pathLists.indices {
                let pathIndex = pathIndices[listIndex]
                guard pathIndex < pathLists[listIndex].count else { continue }
                if try rawUTF8AreEqual(
                    pathLists[listIndex][pathIndex],
                    candidate,
                    work: &work
                ) {
                    try work.consume(1)
                    pathIndices[listIndex] += 1
                }
            }
            paths.append(candidate)
            guard paths.count <= maximumResultEntries else {
                throw ThreeWayFolderComparisonError.tooManyResultEntries(
                    maximumEntries: maximumResultEntries
                )
            }
            if paths.count.isMultiple(of: 4_096) { try Task.checkCancellation() }
        }
    }

    private static func comparisonPairs(
        left: FolderEntry?,
        middle: FolderEntry?,
        right: FolderEntry?
    ) -> [(first: SidedEntry, second: SidedEntry)] {
        [
            ((left, .left), (middle, .middle)),
            ((right, .right), (middle, .middle)),
            ((left, .left), (right, .right))
        ]
    }

    private static func pairComparison(
        first: SidedEntry,
        second: SidedEntry,
        relativePath: String,
        options: ThreeWayFolderComparisonOptions,
        digests: [ThreeWayFolderComparisonSide: [ThreeWayFolderPreparedDigest]],
        work: inout ThreeWayFolderWorkBudget
    ) throws -> ThreeWayFolderPairComparison {
        try work.consume(1)
        switch (first.entry, second.entry) {
        case (nil, nil):
            return ThreeWayFolderPairComparison(
                presenceState: .neither,
                typeState: .notComparable,
                metadataDifferences: [],
                contentState: .notApplicable,
                isEquivalent: true
            )
        case (.some, nil):
            return ThreeWayFolderPairComparison(
                presenceState: .firstOnly,
                typeState: .notComparable,
                metadataDifferences: [],
                contentState: .notApplicable,
                isEquivalent: false
            )
        case (nil, .some):
            return ThreeWayFolderPairComparison(
                presenceState: .secondOnly,
                typeState: .notComparable,
                metadataDifferences: [],
                contentState: .notApplicable,
                isEquivalent: false
            )
        case (let firstEntry?, let secondEntry?):
            guard firstEntry.kind == secondEntry.kind else {
                return ThreeWayFolderPairComparison(
                    presenceState: .both,
                    typeState: .different,
                    metadataDifferences: [],
                    contentState: .notApplicable,
                    isEquivalent: false
                )
            }

            let metadataDifferences = metadataDifferences(
                firstEntry,
                secondEntry,
                tolerance: options.comparison.modificationDateTolerance
            )
            guard firstEntry.kind == .regularFile else {
                return ThreeWayFolderPairComparison(
                    presenceState: .both,
                    typeState: .same,
                    metadataDifferences: metadataDifferences,
                    contentState: .notApplicable,
                    isEquivalent: metadataDifferences.isEmpty
                )
            }
            guard options.comparison.method != .metadataOnly else {
                return ThreeWayFolderPairComparison(
                    presenceState: .both,
                    typeState: .same,
                    metadataDifferences: metadataDifferences,
                    contentState: .notCompared,
                    isEquivalent: metadataDifferences.isEmpty
                )
            }
            if options.comparison.method == .contentIfAvailable,
                sizesDiffer(firstEntry, secondEntry)
            {
                return ThreeWayFolderPairComparison(
                    presenceState: .both,
                    typeState: .same,
                    metadataDifferences: metadataDifferences,
                    contentState: .different,
                    isEquivalent: false
                )
            }

            let firstDigests = digests[first.side] ?? []
            let secondDigests = digests[second.side] ?? []
            if let (firstValue, secondValue) = compatibleDigestPair(
                first: firstDigests,
                second: secondDigests
            ) {
                let equal = try digestBytesAreEqual(
                    firstValue.digest.bytes,
                    secondValue.digest.bytes,
                    work: &work
                )
                let contentState: ThreeWayFolderPairContentState =
                    equal && !sizesDiffer(firstEntry, secondEntry) ? .equal : .different
                return ThreeWayFolderPairComparison(
                    presenceState: .both,
                    typeState: .same,
                    metadataDifferences: metadataDifferences,
                    contentState: contentState,
                    isEquivalent: contentState == .equal && metadataDifferences.isEmpty
                )
            }
            if let firstDigest = firstDigests.first,
                let secondDigest = secondDigests.first
            {
                throw ThreeWayFolderComparisonError.incompatibleContentDigests(
                    relativePath: relativePath,
                    firstSide: first.side,
                    firstAlgorithm: firstDigest.digest.algorithm,
                    secondSide: second.side,
                    secondAlgorithm: secondDigest.digest.algorithm
                )
            }
            if options.comparison.method == .contentRequired {
                var unavailableSides: [ThreeWayFolderComparisonSide] = []
                if firstDigests.isEmpty { unavailableSides.append(first.side) }
                if secondDigests.isEmpty { unavailableSides.append(second.side) }
                throw ThreeWayFolderComparisonError.contentDigestUnavailable(
                    relativePath: relativePath,
                    sides: unavailableSides
                )
            }
            return ThreeWayFolderPairComparison(
                presenceState: .both,
                typeState: .same,
                metadataDifferences: metadataDifferences,
                contentState: .unavailable,
                isEquivalent: metadataDifferences.isEmpty
            )
        }
    }

    private static func compatibleDigestPair(
        first: [ThreeWayFolderPreparedDigest],
        second: [ThreeWayFolderPreparedDigest]
    ) -> (ThreeWayFolderPreparedDigest, ThreeWayFolderPreparedDigest)? {
        for firstDigest in first {
            if let secondDigest = second.first(where: {
                $0.canonicalAlgorithm == firstDigest.canonicalAlgorithm
            }) {
                return (firstDigest, secondDigest)
            }
        }
        return nil
    }

    private static func prepare(
        _ digest: FolderContentDigest,
        side: ThreeWayFolderComparisonSide,
        relativePath: String,
        options: ThreeWayFolderComparisonOptions,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> ThreeWayFolderPreparedDigest {
        guard digest.bytes.count <= options.maximumDigestBytes else {
            throw ThreeWayFolderComparisonError.digestTooLarge(
                side: side,
                relativePath: relativePath,
                maximumBytes: options.maximumDigestBytes
            )
        }
        let algorithmByteCount = try boundedUTF8Count(
            digest.algorithm,
            maximum: options.maximumDigestAlgorithmUTF8Bytes,
            work: &work
        )
        guard algorithmByteCount != nil else {
            throw ThreeWayFolderComparisonError.digestAlgorithmTooLong(
                side: side,
                relativePath: relativePath,
                maximumUTF8Bytes: options.maximumDigestAlgorithmUTF8Bytes
            )
        }
        try work.consume(digest.bytes.count)
        let canonicalAlgorithm = digest.algorithm
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        return ThreeWayFolderPreparedDigest(
            digest: digest,
            canonicalAlgorithm: canonicalAlgorithm
        )
    }

    private static func metadataDifferences(
        _ first: FolderEntry,
        _ second: FolderEntry,
        tolerance: TimeInterval
    ) -> [FolderMetadataField] {
        var differences: [FolderMetadataField] = []
        if first.size != second.size { differences.append(.size) }
        if datesDiffer(first.modificationDate, second.modificationDate, tolerance: tolerance) {
            differences.append(.modificationDate)
        }
        return differences
    }

    private static func datesDiffer(
        _ first: Date?,
        _ second: Date?,
        tolerance: TimeInterval
    ) -> Bool {
        switch (first, second) {
        case (nil, nil):
            false
        case (let first?, let second?):
            !abs(first.timeIntervalSince(second)).isFinite
                || abs(first.timeIntervalSince(second)) > tolerance
        default:
            true
        }
    }

    private static func sizesDiffer(_ first: FolderEntry?, _ second: FolderEntry?) -> Bool {
        guard let firstSize = first?.size, let secondSize = second?.size else { return false }
        return firstSize != secondSize
    }

    private static func digestBytesAreEqual(
        _ first: Data,
        _ second: Data,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> Bool {
        guard first.count == second.count else {
            try work.consume(1)
            return false
        }
        try work.consume(first.count)
        return try first.withUnsafeBytes { (firstBytes: UnsafeRawBufferPointer) in
            try second.withUnsafeBytes { (secondBytes: UnsafeRawBufferPointer) in
                for index in 0..<first.count {
                    if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
                    if firstBytes[index] != secondBytes[index] { return false }
                }
                return true
            }
        }
    }

    private static func resolution(
        for comparisons: ThreeWayFolderPairComparisons
    ) -> ThreeWayFolderComparisonResolution {
        if comparisons.leftAndMiddle.isEquivalent {
            guard comparisons.rightAndMiddle.isEquivalent else { return .right }
            if comparisons.leftAndMiddle.contentState == .unavailable,
                comparisons.rightAndMiddle.contentState == .unavailable,
                comparisons.leftAndRight.contentState == .different
            {
                return .conflict
            }
            return .unchanged
        }
        if comparisons.rightAndMiddle.isEquivalent { return .left }
        if comparisons.leftAndRight.isEquivalent { return .identical }
        return .conflict
    }

    private static func conflictKind(
        left: FolderEntry?,
        middle: FolderEntry?,
        right: FolderEntry?,
        comparisons: ThreeWayFolderPairComparisons
    ) -> ThreeWayFolderConflictKind {
        if middle == nil { return .divergentInsertion }
        if left == nil || right == nil { return .deletionVersusChange }
        if comparisons.leftAndRight.typeState == .different { return .typeMismatch }
        if comparisons.leftAndRight.contentState == .different { return .contentDifference }
        return .metadataDifference
    }

    private static func utf8Count(
        _ value: String,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> Int {
        var count = 0
        var pendingWork = 0
        for _ in value.utf8 {
            count += 1
            pendingWork += 1
            if pendingWork == 4_096 {
                try work.consume(pendingWork)
                pendingWork = 0
            }
        }
        try work.consume(pendingWork)
        return count
    }

    private static func boundedUTF8Count(
        _ value: String,
        maximum: Int,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> Int? {
        var count = 0
        var pendingWork = 0
        for _ in value.utf8 {
            count += 1
            pendingWork += 1
            if pendingWork == 4_096 {
                try work.consume(pendingWork)
                pendingWork = 0
            }
            if count > maximum {
                try work.consume(pendingWork)
                return nil
            }
        }
        try work.consume(pendingWork)
        return count
    }

    private static func rawUTF8Precedes(
        _ first: String,
        _ second: String,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> Bool {
        try work.consume(min(first.utf8.count, second.utf8.count))
        try work.consume(1)
        return rawUTF8Precedes(first, second)
    }

    private static func rawUTF8AreEqual(
        _ first: String,
        _ second: String,
        work: inout ThreeWayFolderWorkBudget
    ) throws -> Bool {
        try work.consume(min(first.utf8.count, second.utf8.count))
        try work.consume(1)
        return first == second
    }

    private static func rawUTF8Precedes(_ first: String, _ second: String) -> Bool {
        first.utf8.lexicographicallyPrecedes(second.utf8)
    }
}

private struct ThreeWayFolderSnapshotIndex {
    let entries: [String: FolderEntry]
    let orderedPaths: [String]
}

private struct ThreeWayFolderInputEntry {
    let entry: FolderEntry
    let relativePathUTF8Count: Int
}

private struct ThreeWayFolderPreparedEntry {
    let normalizedPath: String
    let normalizedPathUTF8Count: Int
    let entry: FolderEntry
}

private struct ThreeWayFolderPreparedDigest {
    let digest: FolderContentDigest
    let canonicalAlgorithm: String
}

private struct ThreeWayFolderWorkBudget {
    let maximum: Int
    private var consumed = 0
    private var workUntilCancellationCheck = 4_096

    init(maximum: Int) {
        self.maximum = maximum
    }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximum - consumed else {
            throw ThreeWayFolderComparisonError.workLimitExceeded(maximumWorkUnits: maximum)
        }
        consumed += amount
        workUntilCancellationCheck -= min(workUntilCancellationCheck, amount)
        if workUntilCancellationCheck == 0 {
            try Task.checkCancellation()
            workUntilCancellationCheck = 4_096
        }
    }
}

private struct ThreeWayFolderMutableCounts {
    var entries = 0
    var unchanged = 0
    var left = 0
    var right = 0
    var identical = 0
    var conflicts = 0
    var presenceDifferences = 0
    var typeMismatches = 0
    var metadataDifferences = 0
    var contentDifferences = 0
    var unavailableContent = 0

    mutating func add(_ entry: ThreeWayFolderComparisonEntry) {
        entries += 1
        switch entry.resolution {
        case .unchanged: unchanged += 1
        case .left: left += 1
        case .right: right += 1
        case .identical: identical += 1
        case .conflict: conflicts += 1
        }
        if entry.presence != .all { presenceDifferences += 1 }
        if entry.typeState == .mixed { typeMismatches += 1 }
        let pairComparisons = [
            entry.comparisons.leftAndMiddle,
            entry.comparisons.rightAndMiddle,
            entry.comparisons.leftAndRight
        ]
        if pairComparisons.contains(where: { !$0.metadataDifferences.isEmpty }) {
            metadataDifferences += 1
        }
        if pairComparisons.contains(where: { $0.contentState == .different }) {
            contentDifferences += 1
        }
        if pairComparisons.contains(where: { $0.contentState == .unavailable }) {
            unavailableContent += 1
        }
    }
}
