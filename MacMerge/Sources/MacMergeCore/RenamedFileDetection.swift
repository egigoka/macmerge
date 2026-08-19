import Foundation

public struct RenamedFileCandidate: Equatable, Sendable {
    /// Stable path relative to its comparison root, using "/" as the separator.
    public let relativePath: String
    public let size: UInt64
    /// Caller-supplied digest of exactly `size` bytes of file content.
    ///
    /// Detection trusts this provenance and does not open files or recompute digests. Callers
    /// must derive both sides with the named algorithm over complete, immutable file contents.
    public let contentDigest: FolderContentDigest?

    public init(
        relativePath: String,
        size: UInt64,
        contentDigest: FolderContentDigest? = nil
    ) {
        self.relativePath = relativePath
        self.size = size
        self.contentDigest = contentDigest
    }
}

public struct RenamedFileMatch: Equatable, Sendable {
    public let left: RenamedFileCandidate
    public let right: RenamedFileCandidate
    /// Levenshtein distance between normalized Unicode path characters.
    public let pathSimilarityCost: Int

    init(
        left: RenamedFileCandidate,
        right: RenamedFileCandidate,
        pathSimilarityCost: Int
    ) {
        precondition(pathSimilarityCost >= 0)
        self.left = left
        self.right = right
        self.pathSimilarityCost = pathSimilarityCost
    }
}

public struct RenamedFileDetectionResult: Equatable, Sendable {
    public let matches: [RenamedFileMatch]
    public let unmatchedLeft: [RenamedFileCandidate]
    public let unmatchedRight: [RenamedFileCandidate]

    public init(
        matches: [RenamedFileMatch],
        unmatchedLeft: [RenamedFileCandidate],
        unmatchedRight: [RenamedFileCandidate]
    ) {
        self.matches = matches
        self.unmatchedLeft = unmatchedLeft
        self.unmatchedRight = unmatchedRight
    }
}

public struct RenamedFileDetectionOptions: Equatable, Sendable {
    public static let `default` = RenamedFileDetectionOptions()

    public let pathCaseSensitivity: FolderPathCaseSensitivity
    /// Maximum total duplicate-content matrix cells across all digest buckets.
    public let maximumCostMatrixCells: Int
    /// Maximum total normalized `Character` comparisons across all digest buckets.
    public let maximumPathCharacterComparisons: Int
    /// Maximum total reserved Hungarian-assignment operations across all digest buckets.
    public let maximumAssignmentOperations: Int
    /// Inclusive Unicode-scalar limit applied before and after path normalization.
    public let maximumNormalizedPathScalars: Int
    /// Inclusive UTF-8 byte limit applied before and after path normalization.
    public let maximumNormalizedPathUTF8Bytes: Int

    public init(
        pathCaseSensitivity: FolderPathCaseSensitivity = .sensitive,
        maximumCostMatrixCells: Int = 65_536,
        maximumPathCharacterComparisons: Int = 16_777_216,
        maximumAssignmentOperations: Int = 16_777_216,
        maximumNormalizedPathScalars: Int = 16_384,
        maximumNormalizedPathUTF8Bytes: Int = 16_384
    ) {
        self.pathCaseSensitivity = pathCaseSensitivity
        self.maximumCostMatrixCells = maximumCostMatrixCells
        self.maximumPathCharacterComparisons = maximumPathCharacterComparisons
        self.maximumAssignmentOperations = maximumAssignmentOperations
        self.maximumNormalizedPathScalars = maximumNormalizedPathScalars
        self.maximumNormalizedPathUTF8Bytes = maximumNormalizedPathUTF8Bytes
    }
}

public enum RenamedFileDetectionError: Error, Equatable, Sendable {
    case invalidLimits
    case invalidRelativePath(
        side: FolderComparisonSide,
        path: String,
        error: FolderRelativePathError
    )
    case duplicateNormalizedPath(side: FolderComparisonSide, normalizedPath: String)
    case workLimitExceeded
}

public enum RenamedFileDetection {
    enum Checkpoint: Equatable, Sendable {
        case candidatePreparation
        case candidateBucketing
        case digestKeyUnion
        case costMatrix
        case assignment
        case oneSidedProjection
        case resultOrdering
    }

    enum AssignmentCheckpoint: Sendable {
        case performedFirstOperation
        case completed
    }

    @TaskLocal
    static var checkpointObserver: (@Sendable (Checkpoint) -> Void)?

    @TaskLocal
    static var assignmentObserver: (@Sendable (AssignmentCheckpoint) -> Void)?

    /// Pairs candidates with equal sizes and equal SHA-256, SHA-384, SHA-512, or 256-bit
    /// BLAKE3 digests. Algorithm labels over 64 UTF-8 bytes are untrusted. Remaining labels
    /// are trimmed with Foundation's `whitespacesAndNewlines` set and lowercased using the
    /// `en_US_POSIX` locale. `sha256` and `sha-256` canonicalize to `sha256` and require exactly 32 bytes;
    /// `sha384` and `sha-384` canonicalize to `sha384` and require exactly 48 bytes;
    /// `sha512` and `sha-512` canonicalize to `sha512` and require exactly 64 bytes; and
    /// `blake3` canonicalizes to `blake3` and requires exactly 32 bytes.
    ///
    /// Digests and sizes are trusted caller metadata. Detection does not verify their
    /// provenance against file contents. Duplicate-content groups minimize normalized path
    /// character edit distance; raw UTF-8 ordering provides deterministic input-order-independent
    /// tie-breaking.
    public static func detect(
        unmatchedLeft: [RenamedFileCandidate],
        unmatchedRight: [RenamedFileCandidate],
        options: RenamedFileDetectionOptions = .default
    ) throws -> RenamedFileDetectionResult {
        guard options.maximumCostMatrixCells >= 0,
            options.maximumPathCharacterComparisons >= 0,
            options.maximumAssignmentOperations >= 0,
            options.maximumNormalizedPathScalars >= 0,
            options.maximumNormalizedPathUTF8Bytes >= 0
        else {
            throw RenamedFileDetectionError.invalidLimits
        }
        try Task.checkCancellation()

        try checkpoint(.candidatePreparation)
        let sortedLeft = try preparedCandidates(
            unmatchedLeft,
            side: .left,
            options: options
        )
        let sortedRight = try preparedCandidates(
            unmatchedRight,
            side: .right,
            options: options
        )
        var leftBuckets: [DigestKey: [PreparedCandidate]] = [:]
        var rightBuckets: [DigestKey: [PreparedCandidate]] = [:]
        var remainingLeft: [RenamedFileCandidate] = []
        var remainingRight: [RenamedFileCandidate] = []
        var workBudget = WorkBudget(options: options)

        try checkpoint(.candidateBucketing)
        for (index, prepared) in sortedLeft.enumerated() {
            try checkCancellation(at: index)
            guard let key = try digestKey(for: prepared.candidate) else {
                remainingLeft.append(prepared.candidate)
                continue
            }
            leftBuckets[key, default: []].append(prepared)
        }
        for (index, prepared) in sortedRight.enumerated() {
            try checkCancellation(at: index)
            guard let key = try digestKey(for: prepared.candidate) else {
                remainingRight.append(prepared.candidate)
                continue
            }
            rightBuckets[key, default: []].append(prepared)
        }

        try checkpoint(.digestKeyUnion)
        var keySet: Set<DigestKey> = []
        keySet.reserveCapacity(leftBuckets.count + rightBuckets.count)
        for (index, key) in leftBuckets.keys.enumerated() {
            try checkCancellation(at: index)
            keySet.insert(key)
        }
        for (index, key) in rightBuckets.keys.enumerated() {
            try checkCancellation(at: index)
            keySet.insert(key)
        }
        var unsortedKeys: [DigestKey] = []
        unsortedKeys.reserveCapacity(keySet.count)
        for (index, key) in keySet.enumerated() {
            try checkCancellation(at: index)
            unsortedKeys.append(key)
        }
        let keys = try cancellableSorted(unsortedKeys, by: digestKeyPrecedes)
        var matches: [RenamedFileMatch] = []
        for (index, key) in keys.enumerated() {
            try checkCancellation(at: index)
            let left = leftBuckets[key] ?? []
            let right = rightBuckets[key] ?? []
            guard !left.isEmpty, !right.isEmpty else {
                try appendCandidates(left, to: &remainingLeft)
                try appendCandidates(right, to: &remainingRight)
                continue
            }

            let bucketResult = try matchDuplicateContent(
                left: left,
                right: right,
                workBudget: &workBudget
            )
            matches.append(contentsOf: bucketResult.matches)
            remainingLeft.append(contentsOf: bucketResult.unmatchedLeft)
            remainingRight.append(contentsOf: bucketResult.unmatchedRight)
        }

        try checkpoint(.resultOrdering)
        matches = try cancellableSorted(matches, by: matchPrecedes)
        remainingLeft = try cancellableSorted(remainingLeft, by: candidatePrecedes)
        remainingRight = try cancellableSorted(remainingRight, by: candidatePrecedes)
        try Task.checkCancellation()
        return RenamedFileDetectionResult(
            matches: matches,
            unmatchedLeft: remainingLeft,
            unmatchedRight: remainingRight
        )
    }

    private struct DigestKey: Hashable {
        let size: UInt64
        let algorithm: String
        let bytes: Data
    }

    private struct PreparedCandidate {
        let candidate: RenamedFileCandidate
        let normalizedPath: String
    }

    private struct WorkBudget {
        var remainingCostMatrixCells: Int
        var remainingPathCharacterComparisons: Int
        var remainingAssignmentOperations: Int
        var assignmentOperationCount = 0

        init(options: RenamedFileDetectionOptions) {
            remainingCostMatrixCells = options.maximumCostMatrixCells
            remainingPathCharacterComparisons = options.maximumPathCharacterComparisons
            remainingAssignmentOperations = options.maximumAssignmentOperations
        }

        mutating func reserve(
            costMatrixCells: Int,
            pathCharacterComparisons: Int,
            assignmentOperations: Int
        ) throws {
            guard costMatrixCells <= remainingCostMatrixCells,
                pathCharacterComparisons <= remainingPathCharacterComparisons,
                assignmentOperations <= remainingAssignmentOperations
            else {
                throw RenamedFileDetectionError.workLimitExceeded
            }
            remainingCostMatrixCells -= costMatrixCells
            remainingPathCharacterComparisons -= pathCharacterComparisons
            remainingAssignmentOperations -= assignmentOperations
        }

        mutating func didPerformAssignmentOperation() throws {
            assignmentOperationCount += 1
            if assignmentOperationCount == 1 {
                RenamedFileDetection.assignmentObserver?(.performedFirstOperation)
                try Task.checkCancellation()
            }
            if assignmentOperationCount.isMultiple(of: 1_024) {
                try Task.checkCancellation()
            }
        }
    }

    private struct BucketResult {
        var matches: [RenamedFileMatch]
        var unmatchedLeft: [RenamedFileCandidate]
        var unmatchedRight: [RenamedFileCandidate]
    }

    private static func digestKey(for candidate: RenamedFileCandidate) throws -> DigestKey? {
        guard let digest = candidate.contentDigest else { return nil }
        var algorithmByteCount = 0
        for _ in digest.algorithm.utf8 {
            guard algorithmByteCount < 64 else { return nil }
            algorithmByteCount += 1
            try checkCancellation(at: algorithmByteCount)
        }
        guard
            let algorithm = trustedAlgorithm(
                canonicalAlgorithm(digest.algorithm),
                byteCount: digest.bytes.count
            )
        else { return nil }
        return DigestKey(
            size: candidate.size,
            algorithm: algorithm,
            bytes: digest.bytes
        )
    }

    private static func trustedAlgorithm(_ algorithm: String, byteCount: Int) -> String? {
        switch algorithm {
        case "sha256" where byteCount == 32,
            "sha-256" where byteCount == 32:
            return "sha256"
        case "sha384" where byteCount == 48,
            "sha-384" where byteCount == 48:
            return "sha384"
        case "sha512" where byteCount == 64,
            "sha-512" where byteCount == 64:
            return "sha512"
        case "blake3" where byteCount == 32:
            return "blake3"
        default:
            return nil
        }
    }

    private static func canonicalAlgorithm(_ algorithm: String) -> String {
        algorithm
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func matchDuplicateContent(
        left: [PreparedCandidate],
        right: [PreparedCandidate],
        workBudget: inout WorkBudget
    ) throws -> BucketResult {
        let rowsAreLeft: Bool
        if left.count != right.count {
            rowsAreLeft = left.count < right.count
        } else {
            rowsAreLeft = !candidateSequencePrecedes(right, left)
        }

        if rowsAreLeft {
            let costs = try pathCostMatrix(
                rows: left,
                columns: right,
                workBudget: &workBudget
            )
            let assignment = try minimumCostAssignment(costs, workBudget: &workBudget)
            let matchedRight = try cancellableSet(assignment)
            var matches: [RenamedFileMatch] = []
            matches.reserveCapacity(assignment.count)
            for (leftIndex, rightIndex) in assignment.enumerated() {
                try checkCancellation(at: leftIndex)
                matches.append(RenamedFileMatch(
                    left: left[leftIndex].candidate,
                    right: right[rightIndex].candidate,
                    pathSimilarityCost: costs[leftIndex][rightIndex]
                ))
            }
            return BucketResult(
                matches: matches,
                unmatchedLeft: [],
                unmatchedRight: try unmatchedCandidates(right, excluding: matchedRight)
            )
        }

        let costs = try pathCostMatrix(
            rows: right,
            columns: left,
            workBudget: &workBudget
        )
        let assignment = try minimumCostAssignment(costs, workBudget: &workBudget)
        let matchedLeft = try cancellableSet(assignment)
        var matches: [RenamedFileMatch] = []
        matches.reserveCapacity(assignment.count)
        for (rightIndex, leftIndex) in assignment.enumerated() {
            try checkCancellation(at: rightIndex)
            matches.append(RenamedFileMatch(
                left: left[leftIndex].candidate,
                right: right[rightIndex].candidate,
                pathSimilarityCost: costs[rightIndex][leftIndex]
            ))
        }
        return BucketResult(
            matches: matches,
            unmatchedLeft: try unmatchedCandidates(left, excluding: matchedLeft),
            unmatchedRight: []
        )
    }

    private static func pathCostMatrix(
        rows: [PreparedCandidate],
        columns: [PreparedCandidate],
        workBudget: inout WorkBudget
    ) throws -> [[Int]] {
        try checkpoint(.costMatrix)
        guard let cellCount = checkedProduct(rows.count, columns.count),
            let rowCharacterCount = try pathCharacterCount(in: rows),
            let columnCharacterCount = try pathCharacterCount(in: columns),
            let comparisonCount = checkedProduct(rowCharacterCount, columnCharacterCount),
            let rowSquare = checkedProduct(rows.count, rows.count),
            let assignmentOperationCount = checkedProduct(rowSquare, columns.count)
        else {
            throw RenamedFileDetectionError.workLimitExceeded
        }
        try workBudget.reserve(
            costMatrixCells: cellCount,
            pathCharacterComparisons: comparisonCount,
            assignmentOperations: assignmentOperationCount
        )

        let rowCharacters = try pathCharacters(in: rows)
        let columnCharacters = try pathCharacters(in: columns)

        var costs: [[Int]] = []
        costs.reserveCapacity(rows.count)
        for (rowIndex, row) in rowCharacters.enumerated() {
            try checkCancellation(at: rowIndex)
            var rowCosts: [Int] = []
            rowCosts.reserveCapacity(columns.count)
            for (columnIndex, column) in columnCharacters.enumerated() {
                try checkCancellation(at: columnIndex)
                rowCosts.append(
                    try pathEditDistance(row, column)
                )
            }
            costs.append(rowCosts)
        }
        return costs
    }

    /// Hungarian assignment for a rectangular matrix with no more rows than columns.
    /// Ascending row and column traversal is the deterministic tie-break for equal costs.
    private static func minimumCostAssignment(
        _ costs: [[Int]],
        workBudget: inout WorkBudget
    ) throws -> [Int] {
        try checkpoint(.assignment)
        let rowCount = costs.count
        guard rowCount > 0 else { return [] }
        let columnCount = costs[0].count
        precondition(rowCount <= columnCount)
        precondition(costs.allSatisfy { $0.count == columnCount })

        var rowPotential = [Int](repeating: 0, count: rowCount + 1)
        var columnPotential = [Int](repeating: 0, count: columnCount + 1)
        var matchedRow = [Int](repeating: 0, count: columnCount + 1)
        var predecessor = [Int](repeating: 0, count: columnCount + 1)

        for row in 1...rowCount {
            try Task.checkCancellation()
            matchedRow[0] = row
            var currentColumn = 0
            var minimumReducedCost = [Int](repeating: .max, count: columnCount + 1)
            var used = [Bool](repeating: false, count: columnCount + 1)

            repeat {
                used[currentColumn] = true
                let currentRow = matchedRow[currentColumn]
                var delta = Int.max
                var nextColumn = 0

                for column in 1...columnCount where !used[column] {
                    let reducedCost =
                        costs[currentRow - 1][column - 1]
                        - rowPotential[currentRow]
                        - columnPotential[column]
                    if reducedCost < minimumReducedCost[column] {
                        minimumReducedCost[column] = reducedCost
                        predecessor[column] = currentColumn
                    }
                    if minimumReducedCost[column] < delta {
                        delta = minimumReducedCost[column]
                        nextColumn = column
                    }
                    try workBudget.didPerformAssignmentOperation()
                }

                precondition(delta != Int.max)
                for column in 0...columnCount {
                    if used[column] {
                        rowPotential[matchedRow[column]] += delta
                        columnPotential[column] -= delta
                    } else if column > 0 {
                        minimumReducedCost[column] -= delta
                    }
                }
                currentColumn = nextColumn
            } while matchedRow[currentColumn] != 0

            repeat {
                let previousColumn = predecessor[currentColumn]
                matchedRow[currentColumn] = matchedRow[previousColumn]
                currentColumn = previousColumn
            } while currentColumn != 0
        }

        var assignment = [Int](repeating: -1, count: rowCount)
        for column in 1...columnCount where matchedRow[column] != 0 {
            assignment[matchedRow[column] - 1] = column - 1
        }
        precondition(assignment.allSatisfy { $0 >= 0 })
        assignmentObserver?(.completed)
        return assignment
    }

    private static func pathEditDistance(
        _ leftCharacters: [Character],
        _ rightCharacters: [Character]
    ) throws -> Int {
        let left: [Character]
        let right: [Character]
        if leftCharacters.count <= rightCharacters.count {
            left = rightCharacters
            right = leftCharacters
        } else {
            left = leftCharacters
            right = rightCharacters
        }
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        var comparisonCount = 0
        for (leftIndex, leftCharacter) in left.enumerated() {
            try checkCancellation(at: leftIndex)
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                comparisonCount += 1
                try checkCancellation(at: comparisonCount)
                let substitution =
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                current[rightIndex + 1] = min(substitution, insertion, deletion)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }

    private static func preparedCandidates(
        _ candidates: [RenamedFileCandidate],
        side: FolderComparisonSide,
        options: RenamedFileDetectionOptions
    ) throws -> [PreparedCandidate] {
        var normalizedPaths: Set<String> = []
        var prepared: [PreparedCandidate] = []
        prepared.reserveCapacity(candidates.count)
        for (index, candidate) in candidates.enumerated() {
            try checkCancellation(at: index)
            guard try pathFitsLimits(candidate.relativePath, options: options) else {
                throw RenamedFileDetectionError.workLimitExceeded
            }
            let normalizedPath: String
            do {
                normalizedPath = try FolderComparator.normalize(
                    relativePath: candidate.relativePath,
                    caseSensitivity: options.pathCaseSensitivity
                )
            } catch let error as FolderRelativePathError {
                throw RenamedFileDetectionError.invalidRelativePath(
                    side: side,
                    path: candidate.relativePath,
                    error: error
                )
            }
            guard try pathFitsLimits(normalizedPath, options: options) else {
                throw RenamedFileDetectionError.workLimitExceeded
            }
            guard normalizedPaths.insert(normalizedPath).inserted else {
                throw RenamedFileDetectionError.duplicateNormalizedPath(
                    side: side,
                    normalizedPath: normalizedPath
                )
            }
            prepared.append(
                PreparedCandidate(
                    candidate: candidate,
                    normalizedPath: normalizedPath
                )
            )
        }
        return try cancellableSorted(prepared) {
            candidatePrecedes($0.candidate, $1.candidate)
        }
    }

    private static func checkedProduct(_ left: Int, _ right: Int) -> Int? {
        let result = left.multipliedReportingOverflow(by: right)
        return result.overflow ? nil : result.partialValue
    }

    private static func pathCharacterCount(
        in candidates: [PreparedCandidate]
    ) throws -> Int? {
        var result = 0
        for (index, candidate) in candidates.enumerated() {
            try checkCancellation(at: index)
            let addition = result.addingReportingOverflow(candidate.normalizedPath.count)
            guard !addition.overflow else { return nil }
            result = addition.partialValue
        }
        return result
    }

    private static func pathCharacters(
        in candidates: [PreparedCandidate]
    ) throws -> [[Character]] {
        var result: [[Character]] = []
        result.reserveCapacity(candidates.count)
        for (index, candidate) in candidates.enumerated() {
            try checkCancellation(at: index)
            result.append(Array(candidate.normalizedPath))
        }
        return result
    }

    private static func pathFitsLimits(
        _ path: String,
        options: RenamedFileDetectionOptions
    ) throws -> Bool {
        var scalarCount = 0
        for _ in path.unicodeScalars {
            guard scalarCount < options.maximumNormalizedPathScalars else { return false }
            scalarCount += 1
            try checkCancellation(at: scalarCount)
        }
        var byteCount = 0
        for _ in path.utf8 {
            guard byteCount < options.maximumNormalizedPathUTF8Bytes else { return false }
            byteCount += 1
            try checkCancellation(at: byteCount)
        }
        return true
    }

    private static func appendCandidates(
        _ prepared: [PreparedCandidate],
        to result: inout [RenamedFileCandidate]
    ) throws {
        try checkpoint(.oneSidedProjection)
        result.reserveCapacity(result.count + prepared.count)
        for (index, candidate) in prepared.enumerated() {
            try checkCancellation(at: index)
            result.append(candidate.candidate)
        }
    }

    private static func cancellableSet(_ values: [Int]) throws -> Set<Int> {
        try checkpoint(.oneSidedProjection)
        var result: Set<Int> = []
        result.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            try checkCancellation(at: index)
            result.insert(value)
        }
        return result
    }

    private static func unmatchedCandidates(
        _ candidates: [PreparedCandidate],
        excluding matched: Set<Int>
    ) throws -> [RenamedFileCandidate] {
        try checkpoint(.oneSidedProjection)
        var result: [RenamedFileCandidate] = []
        result.reserveCapacity(candidates.count - matched.count)
        for (index, candidate) in candidates.enumerated() {
            try checkCancellation(at: index)
            if !matched.contains(index) { result.append(candidate.candidate) }
        }
        return result
    }

    private static func checkpoint(_ checkpoint: Checkpoint) throws {
        checkpointObserver?(checkpoint)
        try Task.checkCancellation()
    }

    private static func checkCancellation(at index: Int) throws {
        if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
    }

    private static func cancellableSorted<Element>(
        _ values: [Element],
        by areInIncreasingOrder: (Element, Element) -> Bool
    ) throws -> [Element] {
        guard values.count > 1 else {
            try Task.checkCancellation()
            return values
        }

        var source = values
        var destination = values
        var width = 1
        while width < source.count {
            try Task.checkCancellation()
            var lowerBound = 0
            while lowerBound < source.count {
                try checkCancellation(at: lowerBound)
                let middle = min(lowerBound + width, source.count)
                let upperBound = min(middle + width, source.count)
                var left = lowerBound
                var right = middle
                var output = lowerBound
                while left < middle || right < upperBound {
                    try checkCancellation(at: output - lowerBound)
                    if right == upperBound
                        || (left < middle
                            && !areInIncreasingOrder(source[right], source[left]))
                    {
                        destination[output] = source[left]
                        left += 1
                    } else {
                        destination[output] = source[right]
                        right += 1
                    }
                    output += 1
                }
                lowerBound = upperBound
            }
            swap(&source, &destination)
            if width > source.count / 2 { break }
            width *= 2
        }
        try Task.checkCancellation()
        return source
    }

    private static func candidatePrecedes(
        _ left: RenamedFileCandidate,
        _ right: RenamedFileCandidate
    ) -> Bool {
        if rawUTF8Precedes(left.relativePath, right.relativePath) { return true }
        if rawUTF8Precedes(right.relativePath, left.relativePath) { return false }
        if left.size != right.size { return left.size < right.size }
        return digestPrecedes(left.contentDigest, right.contentDigest)
    }

    private static func candidateSequencePrecedes(
        _ left: [PreparedCandidate],
        _ right: [PreparedCandidate]
    ) -> Bool {
        for (leftCandidate, rightCandidate) in zip(left, right) {
            if candidatePrecedes(leftCandidate.candidate, rightCandidate.candidate) { return true }
            if candidatePrecedes(rightCandidate.candidate, leftCandidate.candidate) { return false }
        }
        return left.count < right.count
    }

    private static func digestPrecedes(
        _ left: FolderContentDigest?,
        _ right: FolderContentDigest?
    ) -> Bool {
        switch (left, right) {
        case (nil, .some):
            return true
        case (let left?, let right?):
            let leftCanonicalAlgorithm = canonicalAlgorithm(left.algorithm)
            let rightCanonicalAlgorithm = canonicalAlgorithm(right.algorithm)
            if leftCanonicalAlgorithm != rightCanonicalAlgorithm {
                return rawUTF8Precedes(leftCanonicalAlgorithm, rightCanonicalAlgorithm)
            }
            if rawUTF8Precedes(left.algorithm, right.algorithm) { return true }
            if rawUTF8Precedes(right.algorithm, left.algorithm) { return false }
            return left.bytes.lexicographicallyPrecedes(right.bytes)
        default:
            return false
        }
    }

    private static func digestKeyPrecedes(_ left: DigestKey, _ right: DigestKey) -> Bool {
        if left.size != right.size { return left.size < right.size }
        if left.algorithm != right.algorithm {
            return rawUTF8Precedes(left.algorithm, right.algorithm)
        }
        return left.bytes.lexicographicallyPrecedes(right.bytes)
    }

    private static func matchPrecedes(_ left: RenamedFileMatch, _ right: RenamedFileMatch) -> Bool {
        if candidatePrecedes(left.left, right.left) { return true }
        if candidatePrecedes(right.left, left.left) { return false }
        return candidatePrecedes(left.right, right.right)
    }

    private static func rawUTF8Precedes(_ left: String, _ right: String) -> Bool {
        left.utf8.lexicographicallyPrecedes(right.utf8)
    }
}
