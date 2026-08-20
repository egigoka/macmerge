import Foundation

public enum TextSearchPattern: Equatable, Sendable {
    case literal(String)
    case regularExpression(String)

    public var text: String {
        switch self {
        case .literal(let text), .regularExpression(let text):
            text
        }
    }
}

public struct TextSearchQuery: Equatable, Sendable {
    public let pattern: TextSearchPattern
    public let caseSensitive: Bool
    public let wholeWord: Bool

    public init(
        pattern: TextSearchPattern,
        caseSensitive: Bool = true,
        wholeWord: Bool = false
    ) {
        self.pattern = pattern
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
    }

    public init(
        literal: String,
        caseSensitive: Bool = true,
        wholeWord: Bool = false
    ) {
        self.init(
            pattern: .literal(literal),
            caseSensitive: caseSensitive,
            wholeWord: wholeWord
        )
    }

    public init(
        regularExpression: String,
        caseSensitive: Bool = true,
        wholeWord: Bool = false
    ) {
        self.init(
            pattern: .regularExpression(regularExpression),
            caseSensitive: caseSensitive,
            wholeWord: wholeWord
        )
    }
}

public enum TextSearchDirection: Equatable, Sendable {
    case forward
    case backward
}

/// Complete find or find-and-replace state suitable for restoring UI options.
/// A `nil` replacement represents find-only state; an empty replacement is a replace operation.
public struct TextSearchPreset: Equatable, Sendable {
    public let query: TextSearchQuery
    public let replacement: String?
    public let direction: TextSearchDirection
    public let wrap: Bool

    public init(
        query: TextSearchQuery,
        replacement: String? = nil,
        direction: TextSearchDirection = .forward,
        wrap: Bool = true
    ) {
        self.query = query
        self.replacement = replacement
        self.direction = direction
        self.wrap = wrap
    }
}

public enum TextSearchHistoryError: Error, Equatable, LocalizedError, Sendable {
    case encodedDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case invalidCapacity(Int)
    case invalidUTF8ByteLimit(Int)
    case tooManyPresets(maximumPresets: Int)
    case patternTooLarge(maximumUTF8Bytes: Int)
    case replacementTooLarge(maximumUTF8Bytes: Int)
    case historyTooLarge(maximumUTF8Bytes: Int)
    case duplicatePreset

    public var errorDescription: String? {
        switch self {
        case .encodedDataTooLarge(let maximumBytes):
            "Text search history data exceeds the \(maximumBytes)-byte limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported text search history schema version: \(version)."
        case .invalidCapacity(let capacity):
            "Text search history capacity is invalid: \(capacity)."
        case .invalidUTF8ByteLimit(let limit):
            "Text search history UTF-8 byte limit is invalid: \(limit)."
        case .tooManyPresets(let maximumPresets):
            "Text search history exceeds the \(maximumPresets)-preset limit."
        case .patternTooLarge(let maximumUTF8Bytes):
            "Search pattern exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .replacementTooLarge(let maximumUTF8Bytes):
            "Replacement text exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .historyTooLarge(let maximumUTF8Bytes):
            "Text search history exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .duplicatePreset:
            "Text search history contains a duplicate preset."
        }
    }
}

/// Bounded most-recently-used find/replace state. `presets[0]` is most recent.
public struct TextSearchHistory: Equatable, Sendable, RandomAccessCollection {
    public static let currentSchemaVersion = 1
    public static let defaultCapacity = 20
    public static let maximumCapacity = 1_000
    public static let maximumPatternUTF8Bytes = 64 * 1024
    public static let maximumReplacementUTF8Bytes = 1024 * 1024
    public static let defaultUTF8ByteLimit = 2 * 1024 * 1024
    public static let maximumUTF8ByteLimit = 16 * 1024 * 1024
    public static let maximumEncodedBytes = maximumUTF8ByteLimit * 6 + 256 * 1024

    public typealias Index = Int

    public let capacity: Int
    public let utf8ByteLimit: Int
    public private(set) var presets: [TextSearchPreset]
    public private(set) var retainedUTF8ByteCount: Int

    public var startIndex: Int { presets.startIndex }
    public var endIndex: Int { presets.endIndex }

    public subscript(position: Int) -> TextSearchPreset {
        presets[position]
    }

    public init(
        capacity: Int = defaultCapacity,
        utf8ByteLimit: Int = defaultUTF8ByteLimit
    ) {
        Self.preconditionValid(capacity: capacity, utf8ByteLimit: utf8ByteLimit)
        self.capacity = capacity
        self.utf8ByteLimit = utf8ByteLimit
        presets = []
        retainedUTF8ByteCount = 0
    }

    public init(
        _ presets: [TextSearchPreset],
        capacity: Int = defaultCapacity,
        utf8ByteLimit: Int = defaultUTF8ByteLimit
    ) throws {
        Self.preconditionValid(capacity: capacity, utf8ByteLimit: utf8ByteLimit)
        self.capacity = capacity
        self.utf8ByteLimit = utf8ByteLimit
        self.presets = []
        retainedUTF8ByteCount = 0

        for preset in presets where !self.presets.contains(preset) {
            let byteCount = try Self.validatedUTF8ByteCount(of: preset)
            guard byteCount <= utf8ByteLimit else {
                throw TextSearchHistoryError.historyTooLarge(maximumUTF8Bytes: utf8ByteLimit)
            }
            guard self.presets.count < capacity,
                retainedUTF8ByteCount <= utf8ByteLimit - byteCount
            else {
                break
            }
            self.presets.append(preset)
            retainedUTF8ByteCount += byteCount
        }
    }

    /// Adds or promotes a preset, evicting least-recent entries to satisfy both limits.
    @discardableResult
    public mutating func record(_ preset: TextSearchPreset) throws -> Bool {
        let byteCount = try Self.validatedUTF8ByteCount(of: preset)
        guard byteCount <= utf8ByteLimit else {
            throw TextSearchHistoryError.historyTooLarge(maximumUTF8Bytes: utf8ByteLimit)
        }
        guard presets.first != preset else { return false }

        if let existingIndex = presets.firstIndex(of: preset) {
            removePreset(at: existingIndex)
        }
        while presets.count >= capacity || retainedUTF8ByteCount > utf8ByteLimit - byteCount {
            removePreset(at: presets.index(before: presets.endIndex))
        }
        presets.insert(preset, at: 0)
        retainedUTF8ByteCount += byteCount
        return true
    }

    @discardableResult
    public mutating func remove(_ preset: TextSearchPreset) -> Bool {
        guard let index = presets.firstIndex(of: preset) else { return false }
        removePreset(at: index)
        return true
    }

    public mutating func removeAll(keepingCapacity: Bool = false) {
        presets.removeAll(keepingCapacity: keepingCapacity)
        retainedUTF8ByteCount = 0
    }

    /// Returns compact JSON with recursively sorted object keys.
    public func encodedData() throws -> Data {
        try validatePersistedState()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(WireHistory(self))
        guard data.count <= Self.maximumEncodedBytes else {
            throw TextSearchHistoryError.encodedDataTooLarge(
                maximumBytes: Self.maximumEncodedBytes
            )
        }
        return data
    }

    public static func decode(from data: Data) throws -> TextSearchHistory {
        guard data.count <= maximumEncodedBytes else {
            throw TextSearchHistoryError.encodedDataTooLarge(maximumBytes: maximumEncodedBytes)
        }
        return try JSONDecoder().decode(WireHistory.self, from: data).decodedHistory()
    }

    private init(
        validatedPresets: [TextSearchPreset],
        capacity: Int,
        utf8ByteLimit: Int,
        retainedUTF8ByteCount: Int
    ) {
        self.capacity = capacity
        self.utf8ByteLimit = utf8ByteLimit
        presets = validatedPresets
        self.retainedUTF8ByteCount = retainedUTF8ByteCount
    }

    private static func preconditionValid(capacity: Int, utf8ByteLimit: Int) {
        precondition(
            capacity > 0 && capacity <= maximumCapacity,
            "Text search history capacity must be between 1 and \(maximumCapacity)"
        )
        precondition(
            utf8ByteLimit > 0 && utf8ByteLimit <= maximumUTF8ByteLimit,
            "Text search history UTF-8 byte limit must be between 1 and \(maximumUTF8ByteLimit)"
        )
    }

    private static func validatedUTF8ByteCount(of preset: TextSearchPreset) throws -> Int {
        let patternByteCount = preset.query.pattern.text.utf8.count
        guard patternByteCount <= maximumPatternUTF8Bytes else {
            throw TextSearchHistoryError.patternTooLarge(
                maximumUTF8Bytes: maximumPatternUTF8Bytes
            )
        }
        let replacementByteCount = preset.replacement?.utf8.count ?? 0
        guard replacementByteCount <= maximumReplacementUTF8Bytes else {
            throw TextSearchHistoryError.replacementTooLarge(
                maximumUTF8Bytes: maximumReplacementUTF8Bytes
            )
        }
        let (byteCount, overflow) = patternByteCount.addingReportingOverflow(replacementByteCount)
        guard !overflow else {
            throw TextSearchHistoryError.historyTooLarge(
                maximumUTF8Bytes: maximumUTF8ByteLimit
            )
        }
        return byteCount
    }

    private func validatePersistedState() throws {
        guard capacity > 0, capacity <= Self.maximumCapacity else {
            throw TextSearchHistoryError.invalidCapacity(capacity)
        }
        guard utf8ByteLimit > 0, utf8ByteLimit <= Self.maximumUTF8ByteLimit else {
            throw TextSearchHistoryError.invalidUTF8ByteLimit(utf8ByteLimit)
        }
        guard presets.count <= capacity, presets.count <= Self.maximumCapacity else {
            throw TextSearchHistoryError.tooManyPresets(maximumPresets: capacity)
        }

        var validatedByteCount = 0
        for (index, preset) in presets.enumerated() {
            guard !presets[..<index].contains(preset) else {
                throw TextSearchHistoryError.duplicatePreset
            }
            let byteCount = try Self.validatedUTF8ByteCount(of: preset)
            guard validatedByteCount <= utf8ByteLimit - byteCount else {
                throw TextSearchHistoryError.historyTooLarge(maximumUTF8Bytes: utf8ByteLimit)
            }
            validatedByteCount += byteCount
        }
        guard validatedByteCount == retainedUTF8ByteCount else {
            throw TextSearchHistoryError.historyTooLarge(maximumUTF8Bytes: utf8ByteLimit)
        }
    }

    private mutating func removePreset(at index: Int) {
        let preset = presets.remove(at: index)
        let byteCount = preset.query.pattern.text.utf8.count + (preset.replacement?.utf8.count ?? 0)
        retainedUTF8ByteCount -= byteCount
    }

    private struct WireHistory: Codable {
        let schemaVersion: Int
        let capacity: Int
        let utf8ByteLimit: Int
        let presets: [WirePreset]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case capacity
            case utf8ByteLimit
            case presets
        }

        init(_ history: TextSearchHistory) {
            schemaVersion = TextSearchHistory.currentSchemaVersion
            capacity = history.capacity
            utf8ByteLimit = history.utf8ByteLimit
            presets = history.presets.map(WirePreset.init)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == TextSearchHistory.currentSchemaVersion else {
                throw TextSearchHistoryError.unsupportedSchemaVersion(schemaVersion)
            }

            capacity = try container.decode(Int.self, forKey: .capacity)
            guard capacity > 0, capacity <= TextSearchHistory.maximumCapacity else {
                throw TextSearchHistoryError.invalidCapacity(capacity)
            }
            utf8ByteLimit = try container.decode(Int.self, forKey: .utf8ByteLimit)
            guard utf8ByteLimit > 0,
                utf8ByteLimit <= TextSearchHistory.maximumUTF8ByteLimit
            else {
                throw TextSearchHistoryError.invalidUTF8ByteLimit(utf8ByteLimit)
            }

            var presetsContainer = try container.nestedUnkeyedContainer(forKey: .presets)
            if let count = presetsContainer.count, count > capacity {
                throw TextSearchHistoryError.tooManyPresets(maximumPresets: capacity)
            }
            var wirePresets: [WirePreset] = []
            wirePresets.reserveCapacity(Swift.min(presetsContainer.count ?? capacity, capacity))
            var decodedPresets: [TextSearchPreset] = []
            var retainedByteCount = 0

            while !presetsContainer.isAtEnd {
                guard wirePresets.count < capacity else {
                    throw TextSearchHistoryError.tooManyPresets(maximumPresets: capacity)
                }
                let wirePreset = try presetsContainer.decode(WirePreset.self)
                let preset = wirePreset.decodedPreset
                guard !decodedPresets.contains(preset) else {
                    throw TextSearchHistoryError.duplicatePreset
                }
                let byteCount = try TextSearchHistory.validatedUTF8ByteCount(of: preset)
                guard byteCount <= utf8ByteLimit,
                    retainedByteCount <= utf8ByteLimit - byteCount
                else {
                    throw TextSearchHistoryError.historyTooLarge(
                        maximumUTF8Bytes: utf8ByteLimit
                    )
                }
                retainedByteCount += byteCount
                decodedPresets.append(preset)
                wirePresets.append(wirePreset)
            }
            presets = wirePresets
        }

        func decodedHistory() throws -> TextSearchHistory {
            let decodedPresets = presets.map(\.decodedPreset)
            let retainedByteCount = try decodedPresets.reduce(into: 0) { result, preset in
                result += try TextSearchHistory.validatedUTF8ByteCount(of: preset)
            }
            return TextSearchHistory(
                validatedPresets: decodedPresets,
                capacity: capacity,
                utf8ByteLimit: utf8ByteLimit,
                retainedUTF8ByteCount: retainedByteCount
            )
        }
    }

    private struct WirePreset: Codable {
        let pattern: String
        let patternKind: PatternKind
        let caseSensitive: Bool
        let wholeWord: Bool
        let replacement: String?
        let direction: Direction
        let wrap: Bool

        init(_ preset: TextSearchPreset) {
            switch preset.query.pattern {
            case .literal(let pattern):
                self.pattern = pattern
                patternKind = .literal
            case .regularExpression(let pattern):
                self.pattern = pattern
                patternKind = .regularExpression
            }
            caseSensitive = preset.query.caseSensitive
            wholeWord = preset.query.wholeWord
            replacement = preset.replacement
            direction = Direction(preset.direction)
            wrap = preset.wrap
        }

        var decodedPreset: TextSearchPreset {
            let decodedPattern: TextSearchPattern =
                switch patternKind {
                case .literal: .literal(pattern)
                case .regularExpression: .regularExpression(pattern)
                }
            return TextSearchPreset(
                query: TextSearchQuery(
                    pattern: decodedPattern,
                    caseSensitive: caseSensitive,
                    wholeWord: wholeWord
                ),
                replacement: replacement,
                direction: direction.decodedDirection,
                wrap: wrap
            )
        }
    }

    private enum PatternKind: String, Codable {
        case literal
        case regularExpression
    }

    private enum Direction: String, Codable {
        case forward
        case backward

        init(_ direction: TextSearchDirection) {
            switch direction {
            case .forward: self = .forward
            case .backward: self = .backward
            }
        }

        var decodedDirection: TextSearchDirection {
            switch self {
            case .forward: .forward
            case .backward: .backward
            }
        }
    }
}

public struct TextSearchLimits: Equatable, Sendable {
    public static let `default` = TextSearchLimits()

    public let maximumInputUTF16Length: Int
    public let maximumPatternUTF16Length: Int
    public let maximumOutputUTF16Length: Int
    public let maximumMatches: Int
    public let maximumMarkers: Int
    public let maximumCombinedPatternUTF16Length: Int
    public let maximumReplacementTemplateUTF16Length: Int
    public let maximumStoredCaptureRanges: Int
    public let maximumRegularExpressionProgressSteps: Int

    public init(
        maximumInputUTF16Length: Int = 64 * 1024 * 1024,
        maximumPatternUTF16Length: Int = 64 * 1024,
        maximumOutputUTF16Length: Int = 64 * 1024 * 1024,
        maximumMatches: Int = 100_000,
        maximumMarkers: Int = 256,
        maximumCombinedPatternUTF16Length: Int = 4 * 1024 * 1024,
        maximumReplacementTemplateUTF16Length: Int = 1024 * 1024,
        maximumStoredCaptureRanges: Int = 1_000_000,
        maximumRegularExpressionProgressSteps: Int = 1_000_000
    ) {
        precondition(maximumInputUTF16Length >= 0)
        precondition(maximumPatternUTF16Length >= 0)
        precondition(maximumOutputUTF16Length >= 0)
        precondition(maximumMatches > 0)
        precondition(maximumMarkers >= 0)
        precondition(maximumCombinedPatternUTF16Length >= 0)
        precondition(maximumReplacementTemplateUTF16Length >= 0)
        precondition(maximumStoredCaptureRanges > 0)
        precondition(maximumRegularExpressionProgressSteps > 0)
        self.maximumInputUTF16Length = maximumInputUTF16Length
        self.maximumPatternUTF16Length = maximumPatternUTF16Length
        self.maximumOutputUTF16Length = maximumOutputUTF16Length
        self.maximumMatches = maximumMatches
        self.maximumMarkers = maximumMarkers
        self.maximumCombinedPatternUTF16Length = maximumCombinedPatternUTF16Length
        self.maximumReplacementTemplateUTF16Length = maximumReplacementTemplateUTF16Length
        self.maximumStoredCaptureRanges = maximumStoredCaptureRanges
        self.maximumRegularExpressionProgressSteps = maximumRegularExpressionProgressSteps
    }
}

public struct TextSearchMatch: Equatable, Sendable {
    public let range: NSRange

    public init(range: NSRange) {
        self.range = range
    }
}

public struct TextSearchResult: Equatable, Sendable {
    public let match: TextSearchMatch?
    public let didWrap: Bool

    public init(match: TextSearchMatch?, didWrap: Bool) {
        self.match = match
        self.didWrap = didWrap
    }
}

public struct TextReplacementResult: Equatable, Sendable {
    public let text: String
    public let replacementCount: Int

    public init(text: String, replacementCount: Int) {
        self.text = text
        self.replacementCount = replacementCount
    }
}

public struct TextMarker: Equatable, Sendable {
    public let id: String
    public let query: TextSearchQuery

    public init(id: String, query: TextSearchQuery) {
        self.id = id
        self.query = query
    }
}

public struct TextMarkerRange: Equatable, Sendable {
    public let markerID: String
    public let range: NSRange

    public init(markerID: String, range: NSRange) {
        self.markerID = markerID
        self.range = range
    }
}

public enum TextSearchError: Error, LocalizedError, Equatable, Sendable {
    case invalidPattern(String)
    case inputTooLarge(maximumUTF16Length: Int)
    case patternTooLarge(maximumUTF16Length: Int)
    case outputTooLarge(maximumUTF16Length: Int)
    case tooManyMatches(maximumMatches: Int)
    case tooManyMarkers(maximumMarkers: Int)
    case combinedPatternsTooLarge(maximumUTF16Length: Int)
    case replacementTemplateTooLarge(maximumUTF16Length: Int)
    case tooManyCaptureRanges(maximumRanges: Int)
    case invalidUTF16Range(NSRange)
    case rangeSplitsGrapheme(NSRange)
    case evaluationFailed
    case evaluationLimitExceeded(maximumProgressSteps: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidPattern(let pattern):
            "Invalid regular expression: \(pattern)"
        case .inputTooLarge(let maximumUTF16Length):
            "Search input exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .patternTooLarge(let maximumUTF16Length):
            "Search pattern exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .outputTooLarge(let maximumUTF16Length):
            "Replacement output exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .tooManyMatches(let maximumMatches):
            "Search exceeds the \(maximumMatches)-match limit."
        case .tooManyMarkers(let maximumMarkers):
            "Marker search exceeds the \(maximumMarkers)-marker limit."
        case .combinedPatternsTooLarge(let maximumUTF16Length):
            "Marker patterns exceed the combined \(maximumUTF16Length)-UTF-16-unit limit."
        case .replacementTemplateTooLarge(let maximumUTF16Length):
            "Replacement template exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .tooManyCaptureRanges(let maximumRanges):
            "Search exceeds the \(maximumRanges)-capture-range limit."
        case .invalidUTF16Range(let range):
            "Invalid UTF-16 range: \(NSStringFromRange(range))."
        case .rangeSplitsGrapheme(let range):
            "UTF-16 range splits an extended grapheme cluster: \(NSStringFromRange(range))."
        case .evaluationFailed:
            "Regular expression evaluation failed."
        case .evaluationLimitExceeded(let maximumProgressSteps):
            "Regular expression exceeds the \(maximumProgressSteps)-step evaluation limit."
        }
    }
}

public enum TextSearch {
    private enum RegexReplacementComponent {
        case literal(String, utf16Length: Int)
        case capture(Int)
    }

    private struct RegexReplacementTemplate {
        let components: [RegexReplacementComponent]
    }

    private struct RegexPatternAnalysis {
        let hasOpenQuote: Bool
        let containsMatchContinuationAnchor: Bool
        let patternWithoutMatchContinuationAnchors: String
    }

    public static func find(
        in text: String,
        matching query: TextSearchQuery,
        direction: TextSearchDirection = .forward,
        fromUTF16Offset offset: Int,
        wrap: Bool = true,
        limits: TextSearchLimits = .default
    ) throws -> TextSearchResult {
        let textLength = try validate(text: text, query: query, limits: limits)
        try validate(range: NSRange(location: offset, length: 0), in: text, textLength: textLength)
        let matches = try matchingResults(in: text, query: query, limits: limits)
        return find(in: matches, direction: direction, offset: offset, wrap: wrap, excluding: nil)
    }

    // Excluding a zero-length current match guarantees repeat search makes progress.
    public static func find(
        in text: String,
        matching query: TextSearchQuery,
        direction: TextSearchDirection = .forward,
        after match: TextSearchMatch,
        wrap: Bool = true,
        limits: TextSearchLimits = .default
    ) throws -> TextSearchResult {
        let textLength = try validate(text: text, query: query, limits: limits)
        try validate(range: match.range, in: text, textLength: textLength)
        let matches = try matchingResults(in: text, query: query, limits: limits)
        let offset = direction == .forward ? upperBound(of: match.range) : match.range.location
        let excludedRange = match.range.length == 0 ? match.range : nil
        return find(
            in: matches,
            direction: direction,
            offset: offset,
            wrap: wrap,
            excluding: excludedRange
        )
    }

    public static func markerRanges(
        in text: String,
        matching query: TextSearchQuery,
        limits: TextSearchLimits = .default
    ) throws -> [NSRange] {
        _ = try validate(text: text, query: query, limits: limits)
        return try matchingResults(in: text, query: query, limits: limits).map(\.range)
    }

    public static func markerRanges(
        in text: String,
        markers: [TextMarker],
        limits: TextSearchLimits = .default
    ) throws -> [TextMarkerRange] {
        let textLength = text.utf16.count
        guard textLength <= limits.maximumInputUTF16Length else {
            throw TextSearchError.inputTooLarge(maximumUTF16Length: limits.maximumInputUTF16Length)
        }
        guard markers.count <= limits.maximumMarkers else {
            throw TextSearchError.tooManyMarkers(maximumMarkers: limits.maximumMarkers)
        }

        var combinedPatternLength = 0
        var compiledPatterns: [NSRegularExpression?] = []
        compiledPatterns.reserveCapacity(markers.count)
        for marker in markers {
            try validate(pattern: marker.query.pattern, limits: limits)
            combinedPatternLength = try addingLength(
                combinedPatternLength,
                marker.query.pattern.text.utf16.count,
                limit: limits.maximumCombinedPatternUTF16Length,
                error: .combinedPatternsTooLarge(
                    maximumUTF16Length: limits.maximumCombinedPatternUTF16Length
                )
            )
        }
        for marker in markers {
            if case .regularExpression = marker.query.pattern {
                compiledPatterns.append(try compile(marker.query, limits: limits))
            } else {
                compiledPatterns.append(nil)
            }
        }

        var ranges: [(markerIndex: Int, value: TextMarkerRange)] = []
        var remainingCaptureRanges = limits.maximumStoredCaptureRanges
        for (markerIndex, marker) in markers.enumerated() {
            let remaining = limits.maximumMatches - ranges.count
            let matches: [NSTextCheckingResult]
            do {
                if let compiled = compiledPatterns[markerIndex] {
                    matches = try matchingResults(
                        in: text,
                        query: marker.query,
                        compiled: compiled,
                        maximumMatches: remaining,
                        maximumCaptureRanges: remainingCaptureRanges,
                        limits: limits
                    )
                } else {
                    matches = try matchingResults(
                        in: text,
                        query: marker.query,
                        limits: limits,
                        maximumMatches: remaining,
                        maximumCaptureRanges: remainingCaptureRanges
                    )
                }
            } catch TextSearchError.tooManyMatches {
                throw TextSearchError.tooManyMatches(maximumMatches: limits.maximumMatches)
            } catch TextSearchError.tooManyCaptureRanges {
                throw TextSearchError.tooManyCaptureRanges(
                    maximumRanges: limits.maximumStoredCaptureRanges
                )
            }
            for match in matches {
                remainingCaptureRanges -= matchedRangeCount(in: match)
            }
            ranges.append(
                contentsOf: matches.map {
                    (markerIndex, TextMarkerRange(markerID: marker.id, range: $0.range))
                })
        }
        ranges.sort {
            if $0.value.range.location != $1.value.range.location {
                return $0.value.range.location < $1.value.range.location
            }
            if $0.markerIndex != $1.markerIndex {
                return $0.markerIndex < $1.markerIndex
            }
            return $0.value.range.length < $1.value.range.length
        }
        return ranges.map(\.value)
    }

    public static func replaceCurrent(
        in text: String,
        match: TextSearchMatch,
        matching query: TextSearchQuery,
        with replacement: String,
        limits: TextSearchLimits = .default
    ) throws -> TextReplacementResult {
        let textLength = try validate(text: text, query: query, limits: limits)
        try validate(replacementTemplate: replacement, limits: limits)
        try validate(range: match.range, in: text, textLength: textLength)
        let compiled = try compile(query, limits: limits)
        guard let compiled else {
            try validateUnchangedOutput(textLength, limits: limits)
            return TextReplacementResult(text: text, replacementCount: 0)
        }
        let parsedTemplate: RegexReplacementTemplate
        if case .regularExpression = query.pattern {
            parsedTemplate = parseReplacementTemplate(
                replacement,
                numberOfRanges: compiled.numberOfCaptureGroups + 1
            )
        } else {
            parsedTemplate = RegexReplacementTemplate(components: [])
        }

        let matches = try matchingResults(
            in: text,
            query: query,
            compiled: compiled,
            maximumMatches: limits.maximumMatches,
            limits: limits
        )
        guard let result = matches.first(where: { $0.range == match.range }) else {
            try validateUnchangedOutput(textLength, limits: limits)
            return TextReplacementResult(text: text, replacementCount: 0)
        }
        if case .regularExpression = query.pattern {
            try validateReplacementWork(
                parsedTemplate,
                matchCount: 1,
                passes: 2,
                limits: limits
            )
        }
        let replacement = try replacementString(
            for: result,
            in: text,
            query: query,
            template: replacement,
            parsedTemplate: parsedTemplate,
            maximumUTF16Length: limits.maximumOutputUTF16Length
        )
        let outputLength = try replacedLength(
            textLength,
            removing: result.range.length,
            adding: replacement.utf16.count,
            limit: limits.maximumOutputUTF16Length
        )
        guard outputLength <= limits.maximumOutputUTF16Length else {
            throw TextSearchError.outputTooLarge(maximumUTF16Length: limits.maximumOutputUTF16Length)
        }

        let output = NSMutableString(string: text)
        output.replaceCharacters(in: result.range, with: replacement)
        return TextReplacementResult(text: output as String, replacementCount: 1)
    }

    public static func replaceAll(
        in text: String,
        matching query: TextSearchQuery,
        with replacement: String,
        limits: TextSearchLimits = .default
    ) throws -> TextReplacementResult {
        let textLength = try validate(text: text, query: query, limits: limits)
        try validate(replacementTemplate: replacement, limits: limits)
        let compiled = try compile(query, limits: limits)
        guard let compiled else {
            try validateUnchangedOutput(textLength, limits: limits)
            return TextReplacementResult(text: text, replacementCount: 0)
        }
        let parsedTemplate: RegexReplacementTemplate
        if case .regularExpression = query.pattern {
            parsedTemplate = parseReplacementTemplate(
                replacement,
                numberOfRanges: compiled.numberOfCaptureGroups + 1
            )
        } else {
            parsedTemplate = RegexReplacementTemplate(components: [])
        }
        let matches = try matchingResults(
            in: text,
            query: query,
            compiled: compiled,
            maximumMatches: limits.maximumMatches,
            limits: limits
        )
        guard !matches.isEmpty else {
            try validateUnchangedOutput(textLength, limits: limits)
            return TextReplacementResult(text: text, replacementCount: 0)
        }

        if case .regularExpression = query.pattern {
            try validateReplacementWork(
                parsedTemplate,
                matchCount: matches.count,
                passes: 3,
                limits: limits
            )
        }
        var outputLength = textLength
        for match in matches {
            let replacementLength = try replacementLength(
                for: match,
                query: query,
                template: replacement,
                parsedTemplate: parsedTemplate,
                maximumUTF16Length: limits.maximumOutputUTF16Length
            )
            outputLength = try replacedLength(
                outputLength,
                removing: match.range.length,
                adding: replacementLength,
                limit: limits.maximumOutputUTF16Length
            )
        }
        guard outputLength <= limits.maximumOutputUTF16Length else {
            throw TextSearchError.outputTooLarge(maximumUTF16Length: limits.maximumOutputUTF16Length)
        }

        let source = text as NSString
        let output = NSMutableString(capacity: outputLength)
        var cursor = 0
        for match in matches {
            output.append(
                source.substring(
                    with: NSRange(
                        location: cursor,
                        length: match.range.location - cursor
                    )))
            output.append(
                try replacementString(
                    for: match,
                    in: text,
                    query: query,
                    template: replacement,
                    parsedTemplate: parsedTemplate,
                    maximumUTF16Length: limits.maximumOutputUTF16Length
                ))
            cursor = upperBound(of: match.range)
        }
        output.append(source.substring(with: NSRange(location: cursor, length: textLength - cursor)))
        return TextReplacementResult(text: output as String, replacementCount: matches.count)
    }

    private static func validate(
        text: String,
        query: TextSearchQuery,
        limits: TextSearchLimits
    ) throws -> Int {
        let textLength = text.utf16.count
        guard textLength <= limits.maximumInputUTF16Length else {
            throw TextSearchError.inputTooLarge(maximumUTF16Length: limits.maximumInputUTF16Length)
        }
        try validate(pattern: query.pattern, limits: limits)
        return textLength
    }

    private static func validate(pattern: TextSearchPattern, limits: TextSearchLimits) throws {
        guard pattern.text.utf16.count <= limits.maximumPatternUTF16Length else {
            throw TextSearchError.patternTooLarge(maximumUTF16Length: limits.maximumPatternUTF16Length)
        }
    }

    private static func validate(
        replacementTemplate: String,
        limits: TextSearchLimits
    ) throws {
        guard replacementTemplate.utf16.count <= limits.maximumReplacementTemplateUTF16Length else {
            throw TextSearchError.replacementTemplateTooLarge(
                maximumUTF16Length: limits.maximumReplacementTemplateUTF16Length
            )
        }
    }

    private static func validate(range: NSRange, in text: String, textLength: Int) throws {
        let (end, overflow) = range.location.addingReportingOverflow(range.length)
        guard range.location >= 0, range.length >= 0, !overflow, end <= textLength else {
            throw TextSearchError.invalidUTF16Range(range)
        }
        let source = text as NSString
        guard isGraphemeBoundary(range.location, in: source),
            isGraphemeBoundary(end, in: source)
        else {
            throw TextSearchError.rangeSplitsGrapheme(range)
        }
    }

    private static func isGraphemeBoundary(_ offset: Int, in text: NSString) -> Bool {
        guard offset >= 0, offset <= text.length else { return false }
        guard offset < text.length else { return true }
        return text.rangeOfComposedCharacterSequence(at: offset).location == offset
    }

    private static func compile(
        _ query: TextSearchQuery,
        limits: TextSearchLimits
    ) throws -> NSRegularExpression? {
        try validate(pattern: query.pattern, limits: limits)
        let pattern: String
        switch query.pattern {
        case .literal(let value):
            guard !value.isEmpty else { return nil }
            pattern = NSRegularExpression.escapedPattern(
                for: value.precomposedStringWithCanonicalMapping
            )
        case .regularExpression(let value):
            pattern = value.isEmpty ? "(?:)" : value
        }
        do {
            let expression = try NSRegularExpression(
                pattern: pattern,
                options: query.caseSensitive ? [] : [.caseInsensitive]
            )
            guard query.wholeWord, !query.pattern.text.isEmpty else { return expression }
            let word = "[\\p{L}\\p{N}\\p{Pc}]"
            let wrapped = "(?<!\(word))(?:\(closingOpenQuote(in: pattern)))(?!\(word))"
            do {
                return try NSRegularExpression(
                    pattern: wrapped,
                    options: query.caseSensitive ? [] : [.caseInsensitive]
                )
            } catch {
                // A trailing extended-mode comment can consume the wrapper suffix.
                return try NSRegularExpression(
                    pattern: "(?<!\(word))(?:\(closingOpenQuote(in: pattern + "\n")))(?!\(word))",
                    options: query.caseSensitive ? [] : [.caseInsensitive]
                )
            }
        } catch {
            throw TextSearchError.invalidPattern(query.pattern.text)
        }
    }

    private static func matchingResults(
        in text: String,
        query: TextSearchQuery,
        limits: TextSearchLimits,
        maximumMatches: Int? = nil,
        maximumCaptureRanges: Int? = nil
    ) throws -> [NSTextCheckingResult] {
        if case .literal = query.pattern {
            return try literalMatchingResults(
                in: text,
                query: query,
                maximumMatches: maximumMatches ?? limits.maximumMatches,
                maximumCaptureRanges: maximumCaptureRanges ?? limits.maximumStoredCaptureRanges
            )
        }
        guard let compiled = try compile(query, limits: limits) else { return [] }
        return try matchingResults(
            in: text,
            query: query,
            compiled: compiled,
            maximumMatches: maximumMatches ?? limits.maximumMatches,
            maximumCaptureRanges: maximumCaptureRanges ?? limits.maximumStoredCaptureRanges,
            limits: limits
        )
    }

    private static func matchingResults(
        in text: String,
        query: TextSearchQuery,
        compiled: NSRegularExpression,
        maximumMatches: Int,
        maximumCaptureRanges: Int? = nil,
        limits: TextSearchLimits
    ) throws -> [NSTextCheckingResult] {
        if case .literal = query.pattern {
            return try literalMatchingResults(
                in: text,
                query: query,
                maximumMatches: maximumMatches,
                maximumCaptureRanges: maximumCaptureRanges ?? limits.maximumStoredCaptureRanges
            )
        }
        let source = text as NSString
        let textLength = source.length
        let matchingOptions: NSRegularExpression.MatchingOptions = [
            .reportProgress,
            .reportCompletion,
            .withTransparentBounds,
            .withoutAnchoringBounds
        ]
        var results: [NSTextCheckingResult] = []
        results.reserveCapacity(min(maximumMatches, 1024))
        var exceededLimit = false
        var evaluationFailed = false
        var progressSteps = 0
        var exceededProgressLimit = false
        var captureRanges = 0
        var exceededCaptureLimit = false
        var cursorFloor = 0
        let patternAnalysis = regexPatternAnalysis(compiled.pattern)
        let containsMatchContinuationAnchor = patternAnalysis.containsMatchContinuationAnchor
        let recoveryExpression: NSRegularExpression
        if containsMatchContinuationAnchor {
            guard let expression = try? NSRegularExpression(
                pattern: patternAnalysis.patternWithoutMatchContinuationAnchors,
                options: compiled.options
            ) else {
                throw TextSearchError.evaluationFailed
            }
            recoveryExpression = expression
        } else {
            recoveryExpression = compiled
        }
        var continuationCursor: Int?

        func chargeProgress(_ stop: UnsafeMutablePointer<ObjCBool>? = nil) -> Bool {
            chargeProgress(by: 1, stop)
        }

        func chargeProgress(
            by amount: Int,
            _ stop: UnsafeMutablePointer<ObjCBool>? = nil
        ) -> Bool {
            let (nextProgressSteps, overflow) = progressSteps.addingReportingOverflow(amount)
            guard !overflow,
                nextProgressSteps <= limits.maximumRegularExpressionProgressSteps
            else {
                exceededProgressLimit = true
                stop?.pointee = true
                return false
            }
            progressSteps = nextProgressSteps
            return true
        }

        func record(_ result: NSTextCheckingResult) {
            guard results.count < maximumMatches else {
                exceededLimit = true
                return
            }
            let (nextCaptureRanges, overflow) = captureRanges.addingReportingOverflow(
                matchedRangeCount(in: result)
            )
            guard !overflow,
                nextCaptureRanges
                    <= (maximumCaptureRanges ?? limits.maximumStoredCaptureRanges)
            else {
                exceededCaptureLimit = true
                return
            }
            captureRanges = nextCaptureRanges
            results.append(result)
            if result.range.length > 0 {
                cursorFloor = upperBound(of: result.range)
            } else if let next = nextGraphemeBoundary(after: result.range.location, in: source) {
                cursorFloor = next
            } else {
                cursorFloor = textLength + 1
            }
        }

        func firstResult(
            using expression: NSRegularExpression,
            options: NSRegularExpression.MatchingOptions,
            range: NSRange
        ) -> NSTextCheckingResult? {
            var found: NSTextCheckingResult?
            expression.enumerateMatches(in: text, options: options, range: range) { result, flags, stop in
                if flags.contains(.internalError) {
                    evaluationFailed = true
                    stop.pointee = true
                    return
                }
                if flags.contains(.progress), !chargeProgress(stop) {
                    return
                }
                guard let result else { return }
                guard chargeProgress(stop) else { return }
                found = result
                stop.pointee = true
            }
            return found
        }

        func boundaryAdjusted(
            _ initial: NSTextCheckingResult,
            using expression: NSRegularExpression
        ) -> NSTextCheckingResult? {
            guard isGraphemeBoundary(initial.range.location, in: source) else { return nil }
            var candidate = initial
            var excludedSuffixScalarCounts: [Int] = []
            while !isGraphemeBoundary(upperBound(of: candidate.range), in: source) {
                let suffixUTF16Length = textLength - upperBound(of: candidate.range)
                guard chargeProgress(by: suffixUTF16Length) else { return nil }
                let suffix = source.substring(from: upperBound(of: candidate.range))
                excludedSuffixScalarCounts.append(suffix.unicodeScalars.count)
                let excludedEnds = excludedSuffixScalarCounts
                    .map { "[\\s\\S]{\($0)}" }
                    .joined(separator: "|")
                let boundarySuffix = "(?!(?:\(excludedEnds))\\z)"
                let retryPattern =
                    "(?:\(closingOpenQuote(in: expression.pattern)))\(boundarySuffix)"
                guard chargeProgress(by: retryPattern.utf16.count) else {
                    return nil
                }
                let retry: NSRegularExpression
                if let compiledRetry = try? NSRegularExpression(
                    pattern: retryPattern,
                    options: expression.options
                ) {
                    retry = compiledRetry
                } else {
                    let fallbackPattern =
                        "(?:\(closingOpenQuote(in: expression.pattern + "\n")))\(boundarySuffix)"
                    guard chargeProgress(by: fallbackPattern.utf16.count) else {
                        return nil
                    }
                    guard let compiledRetry = try? NSRegularExpression(
                        pattern: fallbackPattern,
                        options: expression.options
                    ) else {
                        evaluationFailed = true
                        return nil
                    }
                    retry = compiledRetry
                }
                guard let next = firstResult(
                    using: retry,
                    options: matchingOptions.union(.anchored),
                    range: NSRange(
                        location: initial.range.location,
                        length: textLength - initial.range.location
                    )
                ), next.range.location == initial.range.location
                else {
                    return nil
                }
                candidate = next
            }
            return candidate
        }

        func isAccepted(_ result: NSTextCheckingResult) -> Bool {
            isGraphemeBoundary(result.range.location, in: source)
                && isGraphemeBoundary(upperBound(of: result.range), in: source)
                && (!query.wholeWord || query.pattern.text.isEmpty
                    || hasWholeWordBoundaries(result.range, in: source))
        }

        func recoverMatches(hiddenBefore hiddenEnd: Int, startingAt recoveryStart: Int) {
            var recoveryCursor = max(recoveryStart, cursorFloor)
            while recoveryCursor < hiddenEnd, recoveryCursor <= textLength,
                !evaluationFailed, !exceededProgressLimit, !exceededLimit,
                !exceededCaptureLimit
            {
                guard let raw = firstResult(
                    using: recoveryExpression,
                    options: matchingOptions,
                    range: NSRange(location: recoveryCursor, length: textLength - recoveryCursor)
                ), raw.range.location < hiddenEnd
                else {
                    return
                }
                if let adjusted = boundaryAdjusted(raw, using: recoveryExpression),
                    isAccepted(adjusted)
                {
                    record(adjusted)
                    recoveryCursor = cursorFloor
                } else if let next = nextGraphemeBoundary(after: raw.range.location, in: source) {
                    recoveryCursor = max(next, cursorFloor)
                } else {
                    return
                }
            }
        }

        continuationCursor = 0
        while let enumerationStart = continuationCursor, enumerationStart <= textLength,
            !evaluationFailed, !exceededProgressLimit, !exceededLimit,
            !exceededCaptureLimit
        {
            continuationCursor = nil
            compiled.enumerateMatches(
                in: text,
                options: matchingOptions,
                range: NSRange(
                    location: enumerationStart,
                    length: textLength - enumerationStart
                )
            ) { raw, flags, stop in
                if flags.contains(.internalError) {
                    evaluationFailed = true
                    stop.pointee = true
                    return
                }
                if flags.contains(.progress), !chargeProgress(stop) {
                    return
                }
                guard let raw else { return }
                guard chargeProgress(stop) else { return }
                guard raw.range.location >= cursorFloor else {
                    if upperBound(of: raw.range) > cursorFloor {
                        recoverMatches(
                            hiddenBefore: upperBound(of: raw.range),
                            startingAt: cursorFloor
                        )
                    }
                    return
                }

                if let adjusted = boundaryAdjusted(raw, using: compiled), isAccepted(adjusted) {
                    record(adjusted)
                    if containsMatchContinuationAnchor, adjusted.range != raw.range {
                        continuationCursor = cursorFloor
                        stop.pointee = true
                    }
                } else {
                    if let next = nextGraphemeBoundary(after: raw.range.location, in: source) {
                        recoverMatches(
                            hiddenBefore: upperBound(of: raw.range),
                            startingAt: next
                        )
                    }
                }
                if evaluationFailed || exceededProgressLimit || exceededLimit || exceededCaptureLimit {
                    stop.pointee = true
                }
            }
        }
        guard !evaluationFailed else { throw TextSearchError.evaluationFailed }
        guard !exceededProgressLimit else {
            throw TextSearchError.evaluationLimitExceeded(
                maximumProgressSteps: limits.maximumRegularExpressionProgressSteps
            )
        }
        guard !exceededCaptureLimit else {
            throw TextSearchError.tooManyCaptureRanges(
                maximumRanges: limits.maximumStoredCaptureRanges
            )
        }
        guard !exceededLimit else {
            throw TextSearchError.tooManyMatches(maximumMatches: maximumMatches)
        }
        return results
    }

    private static func matchedRangeCount(in result: NSTextCheckingResult) -> Int {
        (0..<result.numberOfRanges).reduce(into: 0) { count, index in
            if result.range(at: index).location != NSNotFound {
                count += 1
            }
        }
    }

    private static func literalMatchingResults(
        in text: String,
        query: TextSearchQuery,
        maximumMatches: Int,
        maximumCaptureRanges: Int
    ) throws -> [NSTextCheckingResult] {
        guard case .literal(let pattern) = query.pattern, !pattern.isEmpty else { return [] }
        let source = text as NSString
        let textLength = source.length
        let options: NSString.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive]
        let expression = try NSRegularExpression(
            pattern: NSRegularExpression.escapedPattern(for: pattern)
        )
        var results: [NSTextCheckingResult] = []
        results.reserveCapacity(min(maximumMatches, 1024))
        var cursor = 0

        while cursor < textLength {
            let range = source.range(
                of: pattern,
                options: options,
                range: NSRange(location: cursor, length: textLength - cursor)
            )
            guard range.location != NSNotFound else { break }
            let end = upperBound(of: range)
            guard end > cursor else { break }
            guard isGraphemeBoundary(range.location, in: source),
                isGraphemeBoundary(end, in: source),
                !query.wholeWord || hasWholeWordBoundaries(range, in: source)
            else {
                guard let next = nextGraphemeBoundary(after: range.location, in: source) else {
                    break
                }
                cursor = next
                continue
            }
            cursor = end
            guard results.count < maximumMatches else {
                throw TextSearchError.tooManyMatches(maximumMatches: maximumMatches)
            }
            guard results.count < maximumCaptureRanges else {
                throw TextSearchError.tooManyCaptureRanges(maximumRanges: maximumCaptureRanges)
            }
            var storedRange = range
            results.append(
                withUnsafeMutablePointer(to: &storedRange) {
                    NSTextCheckingResult.regularExpressionCheckingResult(
                        ranges: $0,
                        count: 1,
                        regularExpression: expression
                    )
                })
        }
        return results
    }

    private static func hasWholeWordBoundaries(_ range: NSRange, in text: NSString) -> Bool {
        let end = upperBound(of: range)
        let previous =
            range.location > 0
            ? text.substring(with: text.rangeOfComposedCharacterSequence(at: range.location - 1))
            : nil
        let next =
            end < text.length
            ? text.substring(with: text.rangeOfComposedCharacterSequence(at: end))
            : nil
        return previous.map(isWordCharacter) != true && next.map(isWordCharacter) != true
    }

    private static func isWordCharacter(_ character: String) -> Bool {
        var hasMark = false
        for scalar in character.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                .otherLetter, .decimalNumber, .letterNumber, .otherNumber,
                .connectorPunctuation:
                return true
            case .nonspacingMark, .spacingMark, .enclosingMark:
                if !scalar.properties.isVariationSelector {
                    hasMark = true
                }
            default:
                break
            }
        }
        return hasMark
    }

    private static func nextGraphemeBoundary(after offset: Int, in text: NSString) -> Int? {
        guard offset >= 0, offset < text.length else { return nil }
        let boundary = upperBound(of: text.rangeOfComposedCharacterSequence(at: offset))
        return boundary > offset ? boundary : nil
    }

    private static func find(
        in matches: [NSTextCheckingResult],
        direction: TextSearchDirection,
        offset: Int,
        wrap: Bool,
        excluding excludedRange: NSRange?
    ) -> TextSearchResult {
        let candidates = matches.filter { excludedRange == nil || $0.range != excludedRange }
        let primary: NSTextCheckingResult?
        switch direction {
        case .forward:
            primary = candidates.first { $0.range.location >= offset }
        case .backward:
            primary = candidates.last { upperBound(of: $0.range) <= offset }
        }
        if let primary {
            return TextSearchResult(match: TextSearchMatch(range: primary.range), didWrap: false)
        }
        guard wrap else { return TextSearchResult(match: nil, didWrap: false) }
        let wrapped = direction == .forward ? candidates.first : candidates.last
        return TextSearchResult(
            match: wrapped.map { TextSearchMatch(range: $0.range) },
            didWrap: wrapped != nil
        )
    }

    private static func replacementString(
        for result: NSTextCheckingResult,
        in text: String,
        query: TextSearchQuery,
        template: String,
        parsedTemplate: RegexReplacementTemplate,
        maximumUTF16Length: Int
    ) throws -> String {
        switch query.pattern {
        case .literal:
            guard template.utf16.count <= maximumUTF16Length else {
                throw TextSearchError.outputTooLarge(maximumUTF16Length: maximumUTF16Length)
            }
            return template
        case .regularExpression:
            let expectedLength = try replacementLength(
                for: result,
                query: query,
                template: template,
                parsedTemplate: parsedTemplate,
                maximumUTF16Length: maximumUTF16Length
            )
            let source = text as NSString
            let replacement = NSMutableString(capacity: expectedLength)
            for component in parsedTemplate.components {
                switch component {
                case .literal(let literal, _):
                    replacement.append(literal)
                case .capture(let capture):
                    guard capture < result.numberOfRanges else { continue }
                    let range = result.range(at: capture)
                    if range.location != NSNotFound {
                        replacement.append(source.substring(with: range))
                    }
                }
            }
            return replacement as String
        }
    }

    private static func replacementLength(
        for result: NSTextCheckingResult,
        query: TextSearchQuery,
        template: String,
        parsedTemplate: RegexReplacementTemplate,
        maximumUTF16Length: Int
    ) throws -> Int {
        guard case .regularExpression = query.pattern else {
            let length = template.utf16.count
            guard length <= maximumUTF16Length else {
                throw TextSearchError.outputTooLarge(maximumUTF16Length: maximumUTF16Length)
            }
            return length
        }
        var length = 0
        for component in parsedTemplate.components {
            switch component {
            case .literal(_, let literalLength):
                length = try addingLength(
                    length,
                    literalLength,
                    limit: maximumUTF16Length,
                    error: .outputTooLarge(maximumUTF16Length: maximumUTF16Length)
                )
            case .capture(let capture):
                guard capture < result.numberOfRanges else { continue }
                let range = result.range(at: capture)
                if range.location != NSNotFound {
                    length = try addingLength(
                        length,
                        range.length,
                        limit: maximumUTF16Length,
                        error: .outputTooLarge(maximumUTF16Length: maximumUTF16Length)
                    )
                }
            }
        }
        return length
    }

    private static func parseReplacementTemplate(
        _ template: String,
        numberOfRanges: Int
    ) -> RegexReplacementTemplate {
        let units = Array(template.utf16)
        let maximumCaptureDigits = String(max(0, numberOfRanges - 1)).count
        var components: [RegexReplacementComponent] = []
        var literalUnits: [UInt16] = []
        var index = 0

        func flushLiteral() {
            guard !literalUnits.isEmpty else { return }
            components.append(
                .literal(
                    String(decoding: literalUnits, as: UTF16.self),
                    utf16Length: literalUnits.count
                ))
            literalUnits.removeAll(keepingCapacity: true)
        }

        while index < units.count {
            if units[index] == 0x5C {
                guard index + 1 < units.count else { break }
                let escapedLength =
                    units[index + 1].isLeadSurrogate && index + 2 < units.count
                        && units[index + 2].isTrailSurrogate
                    ? 2 : 1
                literalUnits.append(contentsOf: units[(index + 1)..<(index + 1 + escapedLength)])
                index += 1 + escapedLength
                continue
            }
            if units[index] == 0x24, index + 1 < units.count,
                units[index + 1] >= 0x30, units[index + 1] <= 0x39
            {
                flushLiteral()
                var capture = 0
                var consumed = 0
                index += 1
                while index < units.count, consumed < maximumCaptureDigits,
                    units[index] >= 0x30, units[index] <= 0x39
                {
                    capture = capture * 10 + Int(units[index] - 0x30)
                    index += 1
                    consumed += 1
                }
                components.append(.capture(capture))
                continue
            }
            literalUnits.append(units[index])
            index += 1
        }
        flushLiteral()
        return RegexReplacementTemplate(components: components)
    }

    private static func validateReplacementWork(
        _ template: RegexReplacementTemplate,
        matchCount: Int,
        passes: Int,
        limits: TextSearchLimits
    ) throws {
        let (perPass, firstOverflow) = template.components.count.multipliedReportingOverflow(
            by: matchCount
        )
        let (work, secondOverflow) = perPass.multipliedReportingOverflow(by: passes)
        guard !firstOverflow, !secondOverflow,
            work <= limits.maximumRegularExpressionProgressSteps
        else {
            throw TextSearchError.evaluationLimitExceeded(
                maximumProgressSteps: limits.maximumRegularExpressionProgressSteps
            )
        }
    }

    private static func closingOpenQuote(in pattern: String) -> String {
        regexPatternAnalysis(pattern).hasOpenQuote ? pattern + "\\E" : pattern
    }

    private static func containsMatchContinuationAnchor(_ pattern: String) -> Bool {
        regexPatternAnalysis(pattern).containsMatchContinuationAnchor
    }

    private static func regexPatternAnalysis(_ pattern: String) -> RegexPatternAnalysis {
        let units = Array(pattern.utf16)
        var unitsWithoutMatchContinuationAnchors: [UInt16] = []
        unitsWithoutMatchContinuationAnchors.reserveCapacity(units.count)
        var quoted = false
        var characterClassDepth = 0
        var characterClassCanClose = false
        var characterClassCanNegate = false
        var extendedMode = false
        var groupExtendedModes: [Bool] = []
        var containsMatchContinuationAnchor = false
        var index = 0
        while index < units.count {
            if quoted {
                if index + 1 < units.count, units[index] == 0x5C,
                    units[index + 1] == 0x45
                {
                    unitsWithoutMatchContinuationAnchors.append(contentsOf: units[index...(index + 1)])
                    quoted = false
                    index += 2
                } else {
                    unitsWithoutMatchContinuationAnchors.append(units[index])
                    index += 1
                }
                continue
            }
            if characterClassDepth > 0 {
                if units[index] == 0x5C, index + 1 < units.count {
                    unitsWithoutMatchContinuationAnchors.append(contentsOf: units[index...(index + 1)])
                    if units[index + 1] == 0x51 {
                        quoted = true
                    }
                    characterClassCanClose = true
                    index += 2
                } else if units[index] == 0x5B {
                    unitsWithoutMatchContinuationAnchors.append(units[index])
                    characterClassDepth += 1
                    characterClassCanClose = false
                    characterClassCanNegate = true
                    index += 1
                } else if units[index] == 0x5E, characterClassCanNegate {
                    unitsWithoutMatchContinuationAnchors.append(units[index])
                    characterClassCanNegate = false
                    index += 1
                } else if units[index] == 0x5D, characterClassCanClose {
                    unitsWithoutMatchContinuationAnchors.append(units[index])
                    characterClassDepth -= 1
                    characterClassCanClose = true
                    index += 1
                } else {
                    unitsWithoutMatchContinuationAnchors.append(units[index])
                    characterClassCanClose = true
                    characterClassCanNegate = false
                    index += 1
                }
                continue
            }
            if extendedMode, units[index] == 0x23 {
                while index < units.count, !isRegexLineTerminator(units[index]) {
                    unitsWithoutMatchContinuationAnchors.append(units[index])
                    index += 1
                }
                continue
            }
            if units[index] == 0x5B {
                unitsWithoutMatchContinuationAnchors.append(units[index])
                characterClassDepth = 1
                characterClassCanClose = false
                characterClassCanNegate = true
                index += 1
                continue
            }
            if units[index] == 0x28, index + 2 < units.count,
                units[index + 1] == 0x3F, units[index + 2] == 0x23
            {
                let commentStart = index
                index += 3
                while index < units.count, units[index] != 0x29 {
                    index += 1
                }
                if index < units.count {
                    index += 1
                }
                unitsWithoutMatchContinuationAnchors.append(contentsOf: units[commentStart..<index])
                continue
            }
            if units[index] == 0x28 {
                if let options = regexInlineOptions(in: units, at: index, current: extendedMode) {
                    unitsWithoutMatchContinuationAnchors.append(contentsOf: units[index..<options.end])
                    if options.isScoped {
                        groupExtendedModes.append(extendedMode)
                    }
                    extendedMode = options.extendedMode
                    index = options.end
                } else {
                    unitsWithoutMatchContinuationAnchors.append(units[index])
                    groupExtendedModes.append(extendedMode)
                    index += 1
                }
                continue
            }
            if units[index] == 0x29, let enclosingExtendedMode = groupExtendedModes.popLast() {
                unitsWithoutMatchContinuationAnchors.append(units[index])
                extendedMode = enclosingExtendedMode
                index += 1
                continue
            }
            guard units[index] == 0x5C, index + 1 < units.count else {
                unitsWithoutMatchContinuationAnchors.append(units[index])
                index += 1
                continue
            }
            if units[index + 1] == 0x51 {
                unitsWithoutMatchContinuationAnchors.append(contentsOf: units[index...(index + 1)])
                quoted = true
                index += 2
            } else if units[index + 1] == 0x47 {
                containsMatchContinuationAnchor = true
                unitsWithoutMatchContinuationAnchors.append(contentsOf: [0x28, 0x3F, 0x21, 0x29])
                index += 2
            } else {
                unitsWithoutMatchContinuationAnchors.append(contentsOf: units[index...(index + 1)])
                index += 2
            }
        }
        return RegexPatternAnalysis(
            hasOpenQuote: quoted,
            containsMatchContinuationAnchor: containsMatchContinuationAnchor,
            patternWithoutMatchContinuationAnchors: String(
                decoding: unitsWithoutMatchContinuationAnchors,
                as: UTF16.self
            )
        )
    }

    private static func isRegexLineTerminator(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x85 || unit == 0x2028
    }

    private static func regexInlineOptions(
        in units: [UInt16],
        at opening: Int,
        current: Bool
    ) -> (extendedMode: Bool, isScoped: Bool, end: Int)? {
        guard opening + 2 < units.count, units[opening + 1] == 0x3F else { return nil }
        var extendedMode = current
        var enabling = true
        var sawOption = false
        var index = opening + 2
        while index < units.count {
            switch units[index] {
            case 0x2D:
                enabling = false
                index += 1
            case 0x69, 0x64, 0x6D, 0x73, 0x75, 0x77:
                sawOption = true
                index += 1
            case 0x78:
                sawOption = true
                extendedMode = enabling
                index += 1
            case 0x29 where sawOption:
                return (extendedMode, false, index + 1)
            case 0x3A where sawOption:
                return (extendedMode, true, index + 1)
            default:
                return nil
            }
        }
        return nil
    }

    private static func replacedLength(
        _ current: Int,
        removing removed: Int,
        adding added: Int,
        limit: Int
    ) throws -> Int {
        let reduced = current - removed
        let (result, overflow) = reduced.addingReportingOverflow(added)
        guard !overflow else {
            throw TextSearchError.outputTooLarge(maximumUTF16Length: limit)
        }
        return result
    }

    private static func validateUnchangedOutput(
        _ textLength: Int,
        limits: TextSearchLimits
    ) throws {
        guard textLength <= limits.maximumOutputUTF16Length else {
            throw TextSearchError.outputTooLarge(maximumUTF16Length: limits.maximumOutputUTF16Length)
        }
    }

    private static func addingLength(
        _ current: Int,
        _ added: Int,
        limit: Int,
        error: TextSearchError
    ) throws -> Int {
        let (result, overflow) = current.addingReportingOverflow(added)
        guard !overflow, result <= limit else { throw error }
        return result
    }

    private static func upperBound(of range: NSRange) -> Int {
        range.location + range.length
    }
}

extension UInt16 {
    fileprivate var isLeadSurrogate: Bool { (0xD800...0xDBFF).contains(self) }
    fileprivate var isTrailSurrogate: Bool { (0xDC00...0xDFFF).contains(self) }
}
