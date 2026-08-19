import Foundation

public enum FolderEntryKind: String, Codable, Equatable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

public struct FolderContentDigest: Codable, Equatable, Sendable {
    public let algorithm: String
    public let bytes: Data

    public init(algorithm: String, bytes: Data) {
        precondition(Self.isValidAlgorithm(algorithm), "Digest algorithm must be nonempty")
        self.algorithm = algorithm
        self.bytes = bytes
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case bytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let algorithm = try container.decode(String.self, forKey: .algorithm)
        guard Self.isValidAlgorithm(algorithm) else {
            throw DecodingError.dataCorruptedError(
                forKey: .algorithm,
                in: container,
                debugDescription: "Digest algorithm must be nonempty"
            )
        }
        self.algorithm = algorithm
        bytes = try container.decode(Data.self, forKey: .bytes)
    }

    private static func isValidAlgorithm(_ algorithm: String) -> Bool {
        !algorithm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct FolderEntry: Codable, Equatable, Sendable {
    public let relativePath: String
    public let kind: FolderEntryKind
    public let size: UInt64?
    public let modificationDate: Date?
    public let contentDigest: FolderContentDigest?

    public init(
        relativePath: String,
        kind: FolderEntryKind,
        size: UInt64? = nil,
        modificationDate: Date? = nil,
        contentDigest: FolderContentDigest? = nil
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.modificationDate = modificationDate
        self.contentDigest = contentDigest
    }

}

public struct FolderSnapshot: Codable, Equatable, Sendable {
    public let entries: [FolderEntry]

    public init(entries: [FolderEntry]) {
        self.entries = entries
    }

}

public enum FolderComparisonMethod: String, Codable, Equatable, Sendable {
    /// Compares presence, kind, size, and modification date without requesting content.
    case metadataOnly

    /// Compares content when a comparable digest pair is embedded or can be provided.
    case contentIfAvailable

    /// Requires a comparable digest pair for every pair of regular files, even when sizes differ.
    case contentRequired
}

public enum FolderPathCaseSensitivity: String, Codable, Equatable, Sendable {
    case sensitive
    case insensitive
}

public struct FolderComparisonOptions: Codable, Equatable, Sendable {
    public let method: FolderComparisonMethod
    public let pathCaseSensitivity: FolderPathCaseSensitivity
    public let modificationDateTolerance: TimeInterval

    public init(
        method: FolderComparisonMethod = .metadataOnly,
        pathCaseSensitivity: FolderPathCaseSensitivity = .sensitive,
        modificationDateTolerance: TimeInterval = 0
    ) {
        precondition(
            Self.isValidModificationDateTolerance(modificationDateTolerance),
            "Modification date tolerance must be finite and nonnegative"
        )
        self.method = method
        self.pathCaseSensitivity = pathCaseSensitivity
        self.modificationDateTolerance = modificationDateTolerance
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case pathCaseSensitivity
        case modificationDateTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(FolderComparisonMethod.self, forKey: .method)
        pathCaseSensitivity = try container.decode(
            FolderPathCaseSensitivity.self,
            forKey: .pathCaseSensitivity
        )
        let tolerance = try container.decode(TimeInterval.self, forKey: .modificationDateTolerance)
        guard Self.isValidModificationDateTolerance(tolerance) else {
            throw DecodingError.dataCorruptedError(
                forKey: .modificationDateTolerance,
                in: container,
                debugDescription: "Modification date tolerance must be finite and nonnegative"
            )
        }
        modificationDateTolerance = tolerance
    }

    private static func isValidModificationDateTolerance(_ tolerance: TimeInterval) -> Bool {
        tolerance.isFinite && tolerance >= 0
    }
}

public enum FolderComparisonSide: String, Codable, Equatable, Sendable {
    case left
    case right
}

public enum FolderMetadataField: String, Codable, Equatable, Sendable {
    case size
    case modificationDate
}

public enum FolderRelativePathError: Error, Codable, Equatable, Sendable {
    case empty
    case absolute
    case parentTraversal
    case containsNull
}

public enum FolderComparisonFailure: Equatable, Sendable {
    case invalidRelativePath(side: FolderComparisonSide, error: FolderRelativePathError)
    case duplicateNormalizedPath(leftEntries: [FolderEntry], rightEntries: [FolderEntry])
    case contentDigestUnavailable(sides: [FolderComparisonSide])
    case incompatibleContentDigests(leftAlgorithm: String, rightAlgorithm: String)
    case contentDigestProviderFailed(
        side: FolderComparisonSide,
        errorDomain: String,
        errorCode: Int,
        message: String
    )
}

public enum FolderComparisonStatus: Equatable, Sendable {
    case identical
    case leftOnly
    case rightOnly
    case metadataDifferent([FolderMetadataField])
    case contentDifferent
    case typeMismatch
    case comparisonFailure(FolderComparisonFailure)
}

public struct FolderComparisonEntry: Equatable, Sendable {
    /// Nil only when an input path could not be normalized.
    public let normalizedRelativePath: String?
    public let left: FolderEntry?
    public let right: FolderEntry?
    public let status: FolderComparisonStatus

    public init(
        normalizedRelativePath: String?,
        left: FolderEntry?,
        right: FolderEntry?,
        status: FolderComparisonStatus
    ) {
        self.normalizedRelativePath = normalizedRelativePath
        self.left = left
        self.right = right
        self.status = status
    }
}

public struct FolderContentDigestProvider: Sendable {
    private let operation: @Sendable (FolderComparisonSide, FolderEntry) async throws -> FolderContentDigest?

    public init(
        _ operation:
            @escaping @Sendable (
                FolderComparisonSide,
                FolderEntry
            ) async throws -> FolderContentDigest?
    ) {
        self.operation = operation
    }

    /// Providers may stream or chunk file I/O; the comparator invokes one request at a time.
    public func digest(
        for entry: FolderEntry,
        side: FolderComparisonSide
    ) async throws -> FolderContentDigest? {
        try await operation(side, entry)
    }
}

public enum FolderComparator {
    enum SortCheckpoint: Equatable, Sendable {
        case resultPaths
        case collisionEntries
        case invalidPathResults
    }

    @TaskLocal
    static var sortCheckpointObserver: (@Sendable (SortCheckpoint) async -> Void)?

    /// Returns normalized-path results first, followed by invalid-path failures.
    /// Both groups use stable, locale-independent ordering.
    public static func compare(
        left: FolderSnapshot,
        right: FolderSnapshot,
        options: FolderComparisonOptions = FolderComparisonOptions(),
        contentDigestProvider: FolderContentDigestProvider? = nil
    ) async throws -> [FolderComparisonEntry] {
        try Task.checkCancellation()

        let leftIndex = try index(
            left.entries,
            side: .left,
            caseSensitivity: options.pathCaseSensitivity
        )
        let rightIndex = try index(
            right.entries,
            side: .right,
            caseSensitivity: options.pathCaseSensitivity
        )
        let paths = try await cancellableSorted(
            Array(Set(leftIndex.entries.keys).union(rightIndex.entries.keys)),
            checkpoint: .resultPaths,
            by: { $0 < $1 }
        )
        var results: [FolderComparisonEntry] = []
        results.reserveCapacity(paths.count + leftIndex.failures.count + rightIndex.failures.count)

        for path in paths {
            try Task.checkCancellation()
            let leftEntries = leftIndex.entries[path] ?? []
            let rightEntries = rightIndex.entries[path] ?? []

            if leftEntries.count > 1 || rightEntries.count > 1 {
                let sortedLeftEntries = try await cancellableSorted(
                    leftEntries,
                    checkpoint: .collisionEntries,
                    by: entryPrecedes
                )
                let sortedRightEntries = try await cancellableSorted(
                    rightEntries,
                    checkpoint: .collisionEntries,
                    by: entryPrecedes
                )
                results.append(
                    FolderComparisonEntry(
                        normalizedRelativePath: path,
                        left: leftEntries.count == 1 ? leftEntries[0] : nil,
                        right: rightEntries.count == 1 ? rightEntries[0] : nil,
                        status: .comparisonFailure(
                            .duplicateNormalizedPath(
                                leftEntries: sortedLeftEntries,
                                rightEntries: sortedRightEntries
                            ))
                    ))
                continue
            }

            guard let leftEntry = leftEntries.first else {
                results.append(
                    FolderComparisonEntry(
                        normalizedRelativePath: path,
                        left: nil,
                        right: rightEntries[0],
                        status: .rightOnly
                    ))
                continue
            }
            guard let rightEntry = rightEntries.first else {
                results.append(
                    FolderComparisonEntry(
                        normalizedRelativePath: path,
                        left: leftEntry,
                        right: nil,
                        status: .leftOnly
                    ))
                continue
            }

            let status = try await status(
                left: leftEntry,
                right: rightEntry,
                options: options,
                contentDigestProvider: contentDigestProvider
            )
            results.append(
                FolderComparisonEntry(
                    normalizedRelativePath: path,
                    left: leftEntry,
                    right: rightEntry,
                    status: status
                ))
        }

        let invalidPathResults = try await cancellableSorted(
            leftIndex.failures + rightIndex.failures,
            checkpoint: .invalidPathResults,
            by: invalidPathOrder
        )
        results.append(contentsOf: invalidPathResults)
        try Task.checkCancellation()
        return results
    }

    public static func normalize(
        relativePath: String,
        caseSensitivity: FolderPathCaseSensitivity = .sensitive
    ) throws -> String {
        guard !relativePath.isEmpty else { throw FolderRelativePathError.empty }
        guard !relativePath.hasPrefix("/") else { throw FolderRelativePathError.absolute }
        guard !relativePath.contains("\0") else { throw FolderRelativePathError.containsNull }

        var components: [String] = []
        for component in relativePath.split(separator: "/", omittingEmptySubsequences: false) {
            if component.isEmpty || component == "." { continue }
            guard component != ".." else { throw FolderRelativePathError.parentTraversal }

            var normalized = String(component).precomposedStringWithCanonicalMapping
            if caseSensitivity == .insensitive {
                normalized =
                    normalized.folding(
                        options: .caseInsensitive,
                        locale: Locale(identifier: "en_US_POSIX")
                    ).precomposedStringWithCanonicalMapping
            }
            components.append(normalized)
        }

        guard !components.isEmpty else { throw FolderRelativePathError.empty }
        return components.joined(separator: "/")
    }

    private struct SnapshotIndex {
        var entries: [String: [FolderEntry]] = [:]
        var failures: [FolderComparisonEntry] = []
    }

    private enum DigestResolution {
        case unavailable
        case value(FolderContentDigest)
        case failure(FolderComparisonFailure)
    }

    private enum DigestPairComparison {
        case unavailable([FolderComparisonSide])
        case equal
        case different
        case failure(FolderComparisonFailure)
    }

    private static func index(
        _ entries: [FolderEntry],
        side: FolderComparisonSide,
        caseSensitivity: FolderPathCaseSensitivity
    ) throws -> SnapshotIndex {
        var result = SnapshotIndex()
        for entry in entries {
            try Task.checkCancellation()
            do {
                let path = try normalize(
                    relativePath: entry.relativePath,
                    caseSensitivity: caseSensitivity
                )
                result.entries[path, default: []].append(entry)
            } catch let error as FolderRelativePathError {
                result.failures.append(
                    FolderComparisonEntry(
                        normalizedRelativePath: nil,
                        left: side == .left ? entry : nil,
                        right: side == .right ? entry : nil,
                        status: .comparisonFailure(.invalidRelativePath(side: side, error: error))
                    ))
            } catch {
                preconditionFailure("Folder path normalization threw an undocumented error")
            }
        }
        return result
    }

    private static func status(
        left: FolderEntry,
        right: FolderEntry,
        options: FolderComparisonOptions,
        contentDigestProvider: FolderContentDigestProvider?
    ) async throws -> FolderComparisonStatus {
        guard left.kind == right.kind else { return .typeMismatch }

        let metadataDifferences = metadataDifferences(left: left, right: right, options: options)
        guard left.kind == .regularFile, options.method != .metadataOnly else {
            return metadataDifferences.isEmpty ? .identical : .metadataDifferent(metadataDifferences)
        }
        let sizesDiffer = left.size != nil && right.size != nil && left.size != right.size
        if options.method == .contentIfAvailable, sizesDiffer {
            return .contentDifferent
        }

        let digestComparison = try await compareDigests(
            left: left,
            right: right,
            provider: contentDigestProvider
        )
        switch digestComparison {
        case .equal:
            if sizesDiffer { return .contentDifferent }
            return metadataDifferences.isEmpty ? .identical : .metadataDifferent(metadataDifferences)
        case .different:
            return .contentDifferent
        case .failure(let failure):
            return .comparisonFailure(failure)
        case .unavailable(let sides):
            if options.method == .contentRequired {
                return .comparisonFailure(.contentDigestUnavailable(sides: sides))
            }
            return metadataDifferences.isEmpty ? .identical : .metadataDifferent(metadataDifferences)
        }
    }

    private static func metadataDifferences(
        left: FolderEntry,
        right: FolderEntry,
        options: FolderComparisonOptions
    ) -> [FolderMetadataField] {
        var differences: [FolderMetadataField] = []
        if left.size != right.size {
            differences.append(.size)
        }
        if datesDiffer(
            left.modificationDate,
            right.modificationDate,
            tolerance: options.modificationDateTolerance
        ) {
            differences.append(.modificationDate)
        }
        return differences
    }

    private static func datesDiffer(_ left: Date?, _ right: Date?, tolerance: TimeInterval) -> Bool {
        switch (left, right) {
        case (nil, nil):
            return false
        case (let left?, let right?):
            let difference = abs(left.timeIntervalSince(right))
            return !difference.isFinite || difference > tolerance
        default:
            return true
        }
    }

    private static func compareDigests(
        left: FolderEntry,
        right: FolderEntry,
        provider: FolderContentDigestProvider?
    ) async throws -> DigestPairComparison {
        if let leftDigest = left.contentDigest,
            let rightDigest = right.contentDigest,
            algorithmsMatch(leftDigest.algorithm, rightDigest.algorithm)
        {
            return leftDigest.bytes == rightDigest.bytes ? .equal : .different
        }

        let leftResolution: DigestResolution
        let rightResolution: DigestResolution
        if let provider {
            leftResolution = try await providedDigest(for: left, side: .left, provider: provider)
            if case .failure(let failure) = leftResolution { return .failure(failure) }
            rightResolution = try await providedDigest(for: right, side: .right, provider: provider)
        } else {
            leftResolution = left.contentDigest.map(DigestResolution.value) ?? .unavailable
            rightResolution = right.contentDigest.map(DigestResolution.value) ?? .unavailable
        }

        if case .failure(let failure) = rightResolution { return .failure(failure) }

        switch (leftResolution, rightResolution) {
        case (.value(let leftDigest), .value(let rightDigest)):
            guard algorithmsMatch(leftDigest.algorithm, rightDigest.algorithm) else {
                return .failure(
                    .incompatibleContentDigests(
                        leftAlgorithm: leftDigest.algorithm,
                        rightAlgorithm: rightDigest.algorithm
                    ))
            }
            return leftDigest.bytes == rightDigest.bytes ? .equal : .different
        default:
            var sides: [FolderComparisonSide] = []
            if case .unavailable = leftResolution { sides.append(.left) }
            if case .unavailable = rightResolution { sides.append(.right) }
            return .unavailable(sides)
        }
    }

    private static func providedDigest(
        for entry: FolderEntry,
        side: FolderComparisonSide,
        provider: FolderContentDigestProvider
    ) async throws -> DigestResolution {
        do {
            try Task.checkCancellation()
            let digest = try await provider.digest(for: entry, side: side)
            try Task.checkCancellation()
            return digest.map(DigestResolution.value) ?? entry.contentDigest.map(DigestResolution.value) ?? .unavailable
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            let providerError = error as NSError
            return .failure(
                .contentDigestProviderFailed(
                    side: side,
                    errorDomain: providerError.domain,
                    errorCode: providerError.code,
                    message: providerError.localizedDescription
                ))
        }
    }

    private static func algorithmsMatch(_ left: String, _ right: String) -> Bool {
        canonicalAlgorithm(left) == canonicalAlgorithm(right)
    }

    private static func canonicalAlgorithm(_ algorithm: String) -> String {
        algorithm
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func invalidPathOrder(
        _ left: FolderComparisonEntry,
        _ right: FolderComparisonEntry
    ) -> Bool {
        let leftSide = left.left == nil ? FolderComparisonSide.right.rawValue : FolderComparisonSide.left.rawValue
        let rightSide = right.left == nil ? FolderComparisonSide.right.rawValue : FolderComparisonSide.left.rawValue
        if leftSide != rightSide { return leftSide < rightSide }

        let leftEntry = left.left ?? left.right!
        let rightEntry = right.left ?? right.right!
        return entryPrecedes(leftEntry, rightEntry)
    }

    private static func entryPrecedes(_ leftEntry: FolderEntry, _ rightEntry: FolderEntry) -> Bool {
        if rawUTF8Precedes(leftEntry.relativePath, rightEntry.relativePath) { return true }
        if rawUTF8Precedes(rightEntry.relativePath, leftEntry.relativePath) { return false }
        if leftEntry.kind.rawValue != rightEntry.kind.rawValue {
            return leftEntry.kind.rawValue < rightEntry.kind.rawValue
        }
        if leftEntry.size != rightEntry.size {
            return optionalSizePrecedes(leftEntry.size, rightEntry.size)
        }
        if optionalDatePrecedes(leftEntry.modificationDate, rightEntry.modificationDate) { return true }
        if optionalDatePrecedes(rightEntry.modificationDate, leftEntry.modificationDate) { return false }
        return digestPrecedes(leftEntry.contentDigest, rightEntry.contentDigest)
    }

    private static func optionalSizePrecedes(_ left: UInt64?, _ right: UInt64?) -> Bool {
        switch (left, right) {
        case (nil, .some):
            return true
        case (let left?, let right?):
            return left < right
        default:
            return false
        }
    }

    private static func optionalDatePrecedes(_ left: Date?, _ right: Date?) -> Bool {
        switch (left, right) {
        case (nil, .some):
            return true
        case (let left?, let right?):
            return dateOrderKey(left) < dateOrderKey(right)
        default:
            return false
        }
    }

    private static func dateOrderKey(_ date: Date) -> UInt64 {
        let bits = date.timeIntervalSinceReferenceDate.bitPattern
        let signMask = UInt64(1) << 63
        return bits & signMask == 0 ? bits | signMask : ~bits
    }

    private static func digestPrecedes(_ left: FolderContentDigest?, _ right: FolderContentDigest?) -> Bool {
        switch (left, right) {
        case (nil, .some):
            return true
        case (let left?, let right?):
            let leftAlgorithm = canonicalAlgorithm(left.algorithm)
            let rightAlgorithm = canonicalAlgorithm(right.algorithm)
            if leftAlgorithm != rightAlgorithm { return leftAlgorithm < rightAlgorithm }
            if rawUTF8Precedes(left.algorithm, right.algorithm) { return true }
            if rawUTF8Precedes(right.algorithm, left.algorithm) { return false }
            return left.bytes.lexicographicallyPrecedes(right.bytes)
        default:
            return false
        }
    }

    private static func rawUTF8Precedes(_ left: String, _ right: String) -> Bool {
        left.utf8.lexicographicallyPrecedes(right.utf8)
    }

    private static func cancellableSorted<Element>(
        _ values: [Element],
        checkpoint: SortCheckpoint,
        by areInIncreasingOrder: (Element, Element) -> Bool
    ) async throws -> [Element] {
        try Task.checkCancellation()
        if let sortCheckpointObserver {
            await sortCheckpointObserver(checkpoint)
        }
        try Task.checkCancellation()
        let sorted = try values.sorted { left, right in
            try Task.checkCancellation()
            return areInIncreasingOrder(left, right)
        }
        try Task.checkCancellation()
        return sorted
    }
}
