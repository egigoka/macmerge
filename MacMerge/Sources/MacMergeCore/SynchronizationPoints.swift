import CXDiff
import Foundation

public enum SynchronizationPointsError: Error, Equatable, LocalizedError, Sendable {
    case negativeLeftSourceLine(Int)
    case negativeRightSourceLine(Int)
    case invalidLeftLineCount(Int)
    case invalidRightLineCount(Int)
    case leftSourceLineOutOfBounds(line: Int, lineCount: Int)
    case rightSourceLineOutOfBounds(line: Int, lineCount: Int)
    case leftSourceLinesNotStrictlyIncreasing(previous: Int, next: Int)
    case rightSourceLinesNotStrictlyIncreasing(previous: Int, next: Int)
    case tooManyAnchors(maximum: Int)
    case invalidEditRange(side: SynchronizationPointSide, lowerBound: Int, upperBound: Int)
    case invalidInsertedLineCount(Int)
    case sourceLineOverflow(side: SynchronizationPointSide)
    case persistenceDataTooLarge(maximumBytes: Int)
    case unsupportedPersistenceSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .negativeLeftSourceLine(let line):
            "Left source line must not be negative: \(line)."
        case .negativeRightSourceLine(let line):
            "Right source line must not be negative: \(line)."
        case .invalidLeftLineCount(let count):
            "Left line count must be between 0 and \(SynchronizationPoints.maximumLineCount): \(count)."
        case .invalidRightLineCount(let count):
            "Right line count must be between 0 and \(SynchronizationPoints.maximumLineCount): \(count)."
        case .leftSourceLineOutOfBounds(let line, let lineCount):
            "Left source line \(line) is outside the document's \(lineCount) lines."
        case .rightSourceLineOutOfBounds(let line, let lineCount):
            "Right source line \(line) is outside the document's \(lineCount) lines."
        case .leftSourceLinesNotStrictlyIncreasing(let previous, let next):
            "Left source lines must be strictly increasing: \(previous), \(next)."
        case .rightSourceLinesNotStrictlyIncreasing(let previous, let next):
            "Right source lines must be strictly increasing: \(previous), \(next)."
        case .tooManyAnchors(let maximum):
            "Synchronization points exceed the \(maximum)-anchor limit."
        case .invalidEditRange(let side, let lowerBound, let upperBound):
            "The \(side.description) source-line edit range \(lowerBound)..<\(upperBound) is invalid."
        case .invalidInsertedLineCount(let count):
            "Inserted source-line count must be between 0 and \(SynchronizationPoints.maximumLineCount): \(count)."
        case .sourceLineOverflow(let side):
            "The \(side.description) source-line edit exceeds the supported line-number range."
        case .persistenceDataTooLarge(let maximumBytes):
            "Synchronization-point persistence data exceeds the \(maximumBytes)-byte limit."
        case .unsupportedPersistenceSchemaVersion(let version):
            "Unsupported synchronization-point persistence schema version: \(version)."
        }
    }
}

public enum SynchronizationPointSide: Equatable, Sendable {
    case left
    case right

    fileprivate var description: String {
        switch self {
        case .left: "left"
        case .right: "right"
        }
    }
}

/// A zero-based source-line pair that fixes one point in a two-file mapping.
public struct SynchronizationPoint: Codable, Equatable, Hashable, Sendable {
    public let leftSourceLine: Int
    public let rightSourceLine: Int

    public init(leftSourceLine: Int, rightSourceLine: Int) throws {
        try Self.validateLeftSourceLine(leftSourceLine)
        try Self.validateRightSourceLine(rightSourceLine)
        self.leftSourceLine = leftSourceLine
        self.rightSourceLine = rightSourceLine
    }

    public init(
        leftSourceLine: Int,
        rightSourceLine: Int,
        leftLineCount: Int,
        rightLineCount: Int
    ) throws {
        try self.init(leftSourceLine: leftSourceLine, rightSourceLine: rightSourceLine)
        try Self.validateLineCounts(left: leftLineCount, right: rightLineCount)
        try Self.validateBounds(
            leftSourceLine: leftSourceLine,
            rightSourceLine: rightSourceLine,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
    }

    private enum CodingKeys: String, CodingKey {
        case leftSourceLine
        case rightSourceLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let leftSourceLine = try container.decode(Int.self, forKey: .leftSourceLine)
        let rightSourceLine = try container.decode(Int.self, forKey: .rightSourceLine)
        do {
            try self.init(
                leftSourceLine: leftSourceLine,
                rightSourceLine: rightSourceLine
            )
        } catch let error as SynchronizationPointsError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: error.localizedDescription
                )
            )
        }
    }

    fileprivate static func validateLineCounts(left: Int, right: Int) throws {
        guard (0...SynchronizationPoints.maximumLineCount).contains(left) else {
            throw SynchronizationPointsError.invalidLeftLineCount(left)
        }
        guard (0...SynchronizationPoints.maximumLineCount).contains(right) else {
            throw SynchronizationPointsError.invalidRightLineCount(right)
        }
    }

    fileprivate static func validateLeftSourceLine(_ line: Int) throws {
        guard line >= 0 else {
            throw SynchronizationPointsError.negativeLeftSourceLine(line)
        }
        guard line < SynchronizationPoints.maximumLineCount else {
            throw SynchronizationPointsError.leftSourceLineOutOfBounds(
                line: line,
                lineCount: SynchronizationPoints.maximumLineCount
            )
        }
    }

    fileprivate static func validateRightSourceLine(_ line: Int) throws {
        guard line >= 0 else {
            throw SynchronizationPointsError.negativeRightSourceLine(line)
        }
        guard line < SynchronizationPoints.maximumLineCount else {
            throw SynchronizationPointsError.rightSourceLineOutOfBounds(
                line: line,
                lineCount: SynchronizationPoints.maximumLineCount
            )
        }
    }

    fileprivate static func validateBounds(
        leftSourceLine: Int,
        rightSourceLine: Int,
        leftLineCount: Int,
        rightLineCount: Int
    ) throws {
        guard leftSourceLine < leftLineCount else {
            throw SynchronizationPointsError.leftSourceLineOutOfBounds(
                line: leftSourceLine,
                lineCount: leftLineCount
            )
        }
        guard rightSourceLine < rightLineCount else {
            throw SynchronizationPointsError.rightSourceLineOutOfBounds(
                line: rightSourceLine,
                lineCount: rightLineCount
            )
        }
    }
}

/// Ordered synchronization anchors with deterministic bidirectional line mapping.
public struct SynchronizationPoints: Codable, Equatable, Sendable {
    /// Matches the comparison engine's practical per-file line limit.
    public static let maximumLineCount = Int(MMX_MAX_LINE_COUNT)
    static let maximumAnchorCount = 65_536

    /// Bounded, versioned data for restoring synchronization points with their source bounds.
    public struct PersistencePayload: Equatable, Sendable {
        public static let currentSchemaVersion = 1
        public static let maximumEncodedBytes = 4 * 1024 * 1024

        public let schemaVersion: Int
        public let leftLineCount: Int
        public let rightLineCount: Int
        public let synchronizationPoints: SynchronizationPoints

        public var anchors: [SynchronizationPoint] { synchronizationPoints.anchors }

        public init(
            synchronizationPoints: SynchronizationPoints,
            leftLineCount: Int,
            rightLineCount: Int
        ) throws {
            try synchronizationPoints.validate(
                leftLineCount: leftLineCount,
                rightLineCount: rightLineCount
            )
            schemaVersion = Self.currentSchemaVersion
            self.leftLineCount = leftLineCount
            self.rightLineCount = rightLineCount
            self.synchronizationPoints = synchronizationPoints
        }

        /// Returns compact JSON with recursively sorted object keys.
        public func encodedData() throws -> Data {
            try synchronizationPoints.validate(
                leftLineCount: leftLineCount,
                rightLineCount: rightLineCount
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(WirePayload(self))
            guard data.count <= Self.maximumEncodedBytes else {
                throw SynchronizationPointsError.persistenceDataTooLarge(
                    maximumBytes: Self.maximumEncodedBytes
                )
            }
            return data
        }

        public static func decode(from data: Data) throws -> PersistencePayload {
            guard data.count <= maximumEncodedBytes else {
                throw SynchronizationPointsError.persistenceDataTooLarge(
                    maximumBytes: maximumEncodedBytes
                )
            }
            return try JSONDecoder().decode(WirePayload.self, from: data).decodedPayload()
        }

        private struct WirePayload: Codable {
            let schemaVersion: Int
            let leftLineCount: Int
            let rightLineCount: Int
            let synchronizationPoints: SynchronizationPoints

            private enum CodingKeys: String, CodingKey {
                case schemaVersion
                case leftLineCount
                case rightLineCount
                case synchronizationPoints
            }

            init(_ payload: PersistencePayload) {
                schemaVersion = payload.schemaVersion
                leftLineCount = payload.leftLineCount
                rightLineCount = payload.rightLineCount
                synchronizationPoints = payload.synchronizationPoints
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
                guard schemaVersion == PersistencePayload.currentSchemaVersion else {
                    throw SynchronizationPointsError.unsupportedPersistenceSchemaVersion(
                        schemaVersion
                    )
                }
                leftLineCount = try container.decode(Int.self, forKey: .leftLineCount)
                rightLineCount = try container.decode(Int.self, forKey: .rightLineCount)
                synchronizationPoints = try container.decode(
                    SynchronizationPoints.self,
                    forKey: .synchronizationPoints
                )
            }

            func decodedPayload() throws -> PersistencePayload {
                guard schemaVersion == PersistencePayload.currentSchemaVersion else {
                    throw SynchronizationPointsError.unsupportedPersistenceSchemaVersion(
                        schemaVersion
                    )
                }
                return try PersistencePayload(
                    synchronizationPoints: synchronizationPoints,
                    leftLineCount: leftLineCount,
                    rightLineCount: rightLineCount
                )
            }
        }
    }

    public private(set) var anchors: [SynchronizationPoint]

    public var count: Int { anchors.count }
    public var isEmpty: Bool { anchors.isEmpty }

    public init() {
        anchors = []
    }

    public init(anchors: [SynchronizationPoint]) throws {
        self.anchors = try Self.buildAnchors(from: anchors, expectedCount: anchors.count)
    }

    public init<Anchors: Sequence>(anchors: Anchors) throws
    where Anchors.Element == SynchronizationPoint {
        self.anchors = try Self.buildAnchors(from: anchors, expectedCount: nil)
    }

    public init(
        anchors: [SynchronizationPoint],
        leftLineCount: Int,
        rightLineCount: Int
    ) throws {
        try SynchronizationPoint.validateLineCounts(left: leftLineCount, right: rightLineCount)
        let anchors = try Self.buildAnchors(from: anchors, expectedCount: anchors.count)
        try Self.validateBounds(
            of: anchors,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
        self.anchors = anchors
    }

    public func validate(leftLineCount: Int, rightLineCount: Int) throws {
        try SynchronizationPoint.validateLineCounts(left: leftLineCount, right: rightLineCount)
        try Self.validateBounds(
            of: anchors,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
    }

    /// Adds an anchor in left-source order. An existing identical anchor is unchanged.
    @discardableResult
    public mutating func add(_ anchor: SynchronizationPoint) throws -> Bool {
        let index = insertionIndex(forLeftSourceLine: anchor.leftSourceLine)
        if index < anchors.count, anchors[index] == anchor {
            return false
        }
        guard anchors.count < Self.maximumAnchorCount else {
            throw SynchronizationPointsError.tooManyAnchors(maximum: Self.maximumAnchorCount)
        }
        try Self.validateInsertion(anchor, at: index, in: anchors)
        anchors.insert(anchor, at: index)
        return true
    }

    @discardableResult
    public mutating func add(
        _ anchor: SynchronizationPoint,
        leftLineCount: Int,
        rightLineCount: Int
    ) throws -> Bool {
        try SynchronizationPoint.validateLineCounts(left: leftLineCount, right: rightLineCount)
        try Self.validateBounds(
            of: anchors,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
        try SynchronizationPoint.validateBounds(
            leftSourceLine: anchor.leftSourceLine,
            rightSourceLine: anchor.rightSourceLine,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
        return try add(anchor)
    }

    @discardableResult
    public mutating func add(leftSourceLine: Int, rightSourceLine: Int) throws -> Bool {
        try add(
            SynchronizationPoint(
                leftSourceLine: leftSourceLine,
                rightSourceLine: rightSourceLine
            )
        )
    }

    @discardableResult
    public mutating func add(
        leftSourceLine: Int,
        rightSourceLine: Int,
        leftLineCount: Int,
        rightLineCount: Int
    ) throws -> Bool {
        try add(
            SynchronizationPoint(
                leftSourceLine: leftSourceLine,
                rightSourceLine: rightSourceLine
            ),
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
    }

    @discardableResult
    public mutating func remove(_ anchor: SynchronizationPoint) -> Bool {
        guard let index = anchors.firstIndex(of: anchor) else { return false }
        anchors.remove(at: index)
        return true
    }

    @discardableResult
    public mutating func remove(leftSourceLine: Int, rightSourceLine: Int) throws -> Bool {
        try remove(
            SynchronizationPoint(
                leftSourceLine: leftSourceLine,
                rightSourceLine: rightSourceLine
            )
        )
    }

    /// Removes all anchors and returns whether the collection changed.
    @discardableResult
    public mutating func clear() -> Bool {
        guard !anchors.isEmpty else { return false }
        anchors.removeAll(keepingCapacity: true)
        return true
    }

    /// Invalidates every anchor after either source is replaced or reloaded.
    @discardableResult
    public mutating func invalidate() -> Bool {
        clear()
    }

    /// Reloading either source invalidates every cross-file anchor.
    @discardableResult
    public mutating func invalidateAfterReloadingLeftSource() -> Bool {
        clear()
    }

    /// Reloading either source invalidates every cross-file anchor.
    @discardableResult
    public mutating func invalidateAfterReloadingRightSource() -> Bool {
        clear()
    }

    /// Applies a checked left-side replacement and returns the resulting left line count.
    @discardableResult
    public mutating func remapLeftSource(
        replacing sourceLines: Range<Int>,
        withLineCount insertedLineCount: Int,
        currentLineCount: Int
    ) throws -> Int {
        try remap(
            afterEditing: .left,
            replacing: sourceLines,
            withLineCount: insertedLineCount,
            currentLineCount: currentLineCount
        )
    }

    /// Applies a checked right-side replacement and returns the resulting right line count.
    @discardableResult
    public mutating func remapRightSource(
        replacing sourceLines: Range<Int>,
        withLineCount insertedLineCount: Int,
        currentLineCount: Int
    ) throws -> Int {
        try remap(
            afterEditing: .right,
            replacing: sourceLines,
            withLineCount: insertedLineCount,
            currentLineCount: currentLineCount
        )
    }

    /// Atomically remaps one side after a replacement bounded by its current line count.
    @discardableResult
    public mutating func remap(
        afterEditing side: SynchronizationPointSide,
        replacing sourceLines: Range<Int>,
        withLineCount insertedLineCount: Int,
        currentLineCount: Int
    ) throws -> Int {
        try Self.validate(lineCount: currentLineCount, for: side)
        guard sourceLines.lowerBound >= 0,
            sourceLines.upperBound >= sourceLines.lowerBound,
            sourceLines.upperBound <= currentLineCount
        else {
            throw SynchronizationPointsError.invalidEditRange(
                side: side,
                lowerBound: sourceLines.lowerBound,
                upperBound: sourceLines.upperBound
            )
        }
        guard (0...Self.maximumLineCount).contains(insertedLineCount) else {
            throw SynchronizationPointsError.invalidInsertedLineCount(insertedLineCount)
        }
        try Self.validateBounds(of: anchors, on: side, lineCount: currentLineCount)

        let retainedLineCount = currentLineCount - sourceLines.count
        let (resultingLineCount, overflow) = retainedLineCount.addingReportingOverflow(
            insertedLineCount
        )
        guard !overflow, resultingLineCount <= Self.maximumLineCount else {
            throw SynchronizationPointsError.sourceLineOverflow(side: side)
        }
        try remap(
            afterEditing: side,
            replacing: sourceLines,
            withLineCount: insertedLineCount
        )
        return resultingLineCount
    }

    /// Atomically remaps anchors after a half-open source-line range is replaced.
    /// Anchors in the replaced range are removed; following anchors shift by the line-count delta.
    public mutating func remap(
        afterEditing side: SynchronizationPointSide,
        replacing sourceLines: Range<Int>,
        withLineCount insertedLineCount: Int
    ) throws {
        guard sourceLines.lowerBound >= 0,
            sourceLines.upperBound >= sourceLines.lowerBound,
            sourceLines.upperBound <= Self.maximumLineCount
        else {
            throw SynchronizationPointsError.invalidEditRange(
                side: side,
                lowerBound: sourceLines.lowerBound,
                upperBound: sourceLines.upperBound
            )
        }
        guard (0...Self.maximumLineCount).contains(insertedLineCount) else {
            throw SynchronizationPointsError.invalidInsertedLineCount(insertedLineCount)
        }
        let (insertedUpperBound, endpointOverflow) = sourceLines.lowerBound
            .addingReportingOverflow(insertedLineCount)
        guard !endpointOverflow, insertedUpperBound <= Self.maximumLineCount else {
            throw SynchronizationPointsError.sourceLineOverflow(side: side)
        }
        guard !sourceLines.isEmpty || insertedLineCount > 0 else { return }

        let removedLineCount = sourceLines.upperBound - sourceLines.lowerBound
        var remapped: [SynchronizationPoint] = []
        remapped.reserveCapacity(anchors.count)
        for anchor in anchors {
            let sourceLine =
                switch side {
                case .left: anchor.leftSourceLine
                case .right: anchor.rightSourceLine
                }
            if sourceLines.contains(sourceLine) {
                continue
            }

            let newSourceLine: Int
            if sourceLine >= sourceLines.upperBound {
                let lineAfterDeletion = sourceLine - removedLineCount
                let (shiftedLine, overflow) = lineAfterDeletion.addingReportingOverflow(
                    insertedLineCount
                )
                guard !overflow, shiftedLine < Self.maximumLineCount else {
                    throw SynchronizationPointsError.sourceLineOverflow(side: side)
                }
                newSourceLine = shiftedLine
            } else {
                newSourceLine = sourceLine
            }

            switch side {
            case .left:
                remapped.append(
                    try SynchronizationPoint(
                        leftSourceLine: newSourceLine,
                        rightSourceLine: anchor.rightSourceLine
                    )
                )
            case .right:
                remapped.append(
                    try SynchronizationPoint(
                        leftSourceLine: anchor.leftSourceLine,
                        rightSourceLine: newSourceLine
                    )
                )
            }
        }
        anchors = remapped
    }

    /// Maps a zero-based left source line, clamping outside the first and last anchors.
    public func mapLeftToRight(_ leftSourceLine: Int) throws -> Int? {
        try SynchronizationPoint.validateLeftSourceLine(leftSourceLine)
        return mappedLine(
            leftSourceLine,
            sourceLine: \.leftSourceLine,
            destinationLine: \.rightSourceLine
        )
    }

    public func mapLeftToRight(
        _ leftSourceLine: Int,
        leftLineCount: Int,
        rightLineCount: Int
    ) throws -> Int? {
        try SynchronizationPoint.validateLineCounts(left: leftLineCount, right: rightLineCount)
        guard leftSourceLine >= 0 else {
            throw SynchronizationPointsError.negativeLeftSourceLine(leftSourceLine)
        }
        guard leftSourceLine < leftLineCount else {
            throw SynchronizationPointsError.leftSourceLineOutOfBounds(
                line: leftSourceLine,
                lineCount: leftLineCount
            )
        }
        try Self.validateBounds(
            of: anchors,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
        return mappedLine(
            leftSourceLine,
            sourceLine: \.leftSourceLine,
            destinationLine: \.rightSourceLine
        )
    }

    /// Maps a zero-based right source line, clamping outside the first and last anchors.
    public func mapRightToLeft(_ rightSourceLine: Int) throws -> Int? {
        try SynchronizationPoint.validateRightSourceLine(rightSourceLine)
        return mappedLine(
            rightSourceLine,
            sourceLine: \.rightSourceLine,
            destinationLine: \.leftSourceLine
        )
    }

    public func mapRightToLeft(
        _ rightSourceLine: Int,
        leftLineCount: Int,
        rightLineCount: Int
    ) throws -> Int? {
        try SynchronizationPoint.validateLineCounts(left: leftLineCount, right: rightLineCount)
        guard rightSourceLine >= 0 else {
            throw SynchronizationPointsError.negativeRightSourceLine(rightSourceLine)
        }
        guard rightSourceLine < rightLineCount else {
            throw SynchronizationPointsError.rightSourceLineOutOfBounds(
                line: rightSourceLine,
                lineCount: rightLineCount
            )
        }
        try Self.validateBounds(
            of: anchors,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
        return mappedLine(
            rightSourceLine,
            sourceLine: \.rightSourceLine,
            destinationLine: \.leftSourceLine
        )
    }

    private enum CodingKeys: String, CodingKey {
        case anchors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decoded = try container.nestedUnkeyedContainer(forKey: .anchors)
        let expectedCount = decoded.count
        if let expectedCount, expectedCount > Self.maximumAnchorCount {
            throw DecodingError.dataCorruptedError(
                forKey: .anchors,
                in: container,
                debugDescription: SynchronizationPointsError.tooManyAnchors(
                    maximum: Self.maximumAnchorCount
                ).localizedDescription
            )
        }
        var builder = AnchorBuilder(expectedCount: expectedCount)
        while !decoded.isAtEnd {
            guard builder.canAppend else {
                throw DecodingError.dataCorruptedError(
                    forKey: .anchors,
                    in: container,
                    debugDescription: SynchronizationPointsError.tooManyAnchors(
                        maximum: Self.maximumAnchorCount
                    ).localizedDescription
                )
            }
            let anchor = try decoded.decode(SynchronizationPoint.self)
            do {
                try builder.append(anchor)
            } catch let error as SynchronizationPointsError {
                throw DecodingError.dataCorruptedError(
                    forKey: .anchors,
                    in: container,
                    debugDescription: error.localizedDescription
                )
            }
        }
        anchors = builder.anchors
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(anchors, forKey: .anchors)
    }

    private func insertionIndex(forLeftSourceLine line: Int) -> Int {
        var lowerBound = 0
        var upperBound = anchors.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if anchors[middle].leftSourceLine < line {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func mappedLine(
        _ line: Int,
        sourceLine: KeyPath<SynchronizationPoint, Int>,
        destinationLine: KeyPath<SynchronizationPoint, Int>
    ) -> Int? {
        guard let first = anchors.first, let last = anchors.last else { return nil }
        if line <= first[keyPath: sourceLine] {
            return first[keyPath: destinationLine]
        }
        if line >= last[keyPath: sourceLine] {
            return last[keyPath: destinationLine]
        }

        var lowerBound = 0
        var upperBound = anchors.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if anchors[middle][keyPath: sourceLine] <= line {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let lower = anchors[lowerBound - 1]
        let upper = anchors[lowerBound]
        let lowerSource = lower[keyPath: sourceLine]
        let lowerDestination = lower[keyPath: destinationLine]
        if line == lowerSource {
            return lowerDestination
        }

        let sourceOffset = UInt(line - lowerSource)
        let sourceSpan = UInt(upper[keyPath: sourceLine] - lowerSource)
        let destinationSpan = UInt(upper[keyPath: destinationLine] - lowerDestination)
        let product = sourceOffset.multipliedFullWidth(by: destinationSpan)
        let mappedOffset = sourceSpan.dividingFullWidth(product).quotient
        return lowerDestination + Int(mappedOffset)
    }

    private struct AnchorBuilder {
        private(set) var anchors: [SynchronizationPoint]

        init(expectedCount: Int?) {
            anchors = []
            if let expectedCount {
                anchors.reserveCapacity(expectedCount)
            }
        }

        var canAppend: Bool { anchors.count < maximumAnchorCount }

        mutating func append(_ next: SynchronizationPoint) throws {
            guard canAppend else {
                throw SynchronizationPointsError.tooManyAnchors(maximum: maximumAnchorCount)
            }
            if let previous = anchors.last {
                guard previous.leftSourceLine < next.leftSourceLine else {
                    throw SynchronizationPointsError.leftSourceLinesNotStrictlyIncreasing(
                        previous: previous.leftSourceLine,
                        next: next.leftSourceLine
                    )
                }
                guard previous.rightSourceLine < next.rightSourceLine else {
                    throw SynchronizationPointsError.rightSourceLinesNotStrictlyIncreasing(
                        previous: previous.rightSourceLine,
                        next: next.rightSourceLine
                    )
                }
            }
            anchors.append(next)
        }
    }

    private static func buildAnchors<Anchors: Sequence>(
        from source: Anchors,
        expectedCount: Int?
    ) throws -> [SynchronizationPoint] where Anchors.Element == SynchronizationPoint {
        let capacity = expectedCount ?? source.underestimatedCount
        if capacity > maximumAnchorCount {
            throw SynchronizationPointsError.tooManyAnchors(maximum: maximumAnchorCount)
        }
        var builder = AnchorBuilder(expectedCount: capacity)
        for anchor in source {
            try builder.append(anchor)
        }
        return builder.anchors
    }

    private static func validateBounds(
        of anchors: [SynchronizationPoint],
        leftLineCount: Int,
        rightLineCount: Int
    ) throws {
        guard let last = anchors.last else { return }
        try SynchronizationPoint.validateBounds(
            leftSourceLine: last.leftSourceLine,
            rightSourceLine: last.rightSourceLine,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
    }

    private static func validateBounds(
        of anchors: [SynchronizationPoint],
        on side: SynchronizationPointSide,
        lineCount: Int
    ) throws {
        guard let last = anchors.last else { return }
        switch side {
        case .left:
            guard last.leftSourceLine < lineCount else {
                throw SynchronizationPointsError.leftSourceLineOutOfBounds(
                    line: last.leftSourceLine,
                    lineCount: lineCount
                )
            }
        case .right:
            guard last.rightSourceLine < lineCount else {
                throw SynchronizationPointsError.rightSourceLineOutOfBounds(
                    line: last.rightSourceLine,
                    lineCount: lineCount
                )
            }
        }
    }

    private static func validate(
        lineCount: Int,
        for side: SynchronizationPointSide
    ) throws {
        switch side {
        case .left:
            guard (0...maximumLineCount).contains(lineCount) else {
                throw SynchronizationPointsError.invalidLeftLineCount(lineCount)
            }
        case .right:
            guard (0...maximumLineCount).contains(lineCount) else {
                throw SynchronizationPointsError.invalidRightLineCount(lineCount)
            }
        }
    }

    private static func validateInsertion(
        _ anchor: SynchronizationPoint,
        at index: Int,
        in anchors: [SynchronizationPoint]
    ) throws {
        if index > 0 {
            let previous = anchors[index - 1]
            guard previous.leftSourceLine < anchor.leftSourceLine else {
                throw SynchronizationPointsError.leftSourceLinesNotStrictlyIncreasing(
                    previous: previous.leftSourceLine,
                    next: anchor.leftSourceLine
                )
            }
            guard previous.rightSourceLine < anchor.rightSourceLine else {
                throw SynchronizationPointsError.rightSourceLinesNotStrictlyIncreasing(
                    previous: previous.rightSourceLine,
                    next: anchor.rightSourceLine
                )
            }
        }
        if index < anchors.count {
            let next = anchors[index]
            guard anchor.leftSourceLine < next.leftSourceLine else {
                throw SynchronizationPointsError.leftSourceLinesNotStrictlyIncreasing(
                    previous: anchor.leftSourceLine,
                    next: next.leftSourceLine
                )
            }
            guard anchor.rightSourceLine < next.rightSourceLine else {
                throw SynchronizationPointsError.rightSourceLinesNotStrictlyIncreasing(
                    previous: anchor.rightSourceLine,
                    next: next.rightSourceLine
                )
            }
        }
    }
}
