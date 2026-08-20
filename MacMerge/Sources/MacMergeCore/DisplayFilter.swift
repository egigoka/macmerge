import Foundation

public enum DisplayFilterExpression: Codable, Equatable, Hashable, Sendable {
    case literal(String)
    case regularExpression(String)

    public var text: String {
        switch self {
        case .literal(let text), .regularExpression(let text):
            text
        }
    }

    public var isRegularExpression: Bool {
        if case .regularExpression = self { return true }
        return false
    }

    private enum Kind: String, Codable {
        case literal
        case regularExpression
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let text = try container.decode(String.self, forKey: .text)
        guard text.utf16.count <= DisplayFilter.maximumExpressionUTF16Length else {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription:
                    "Display filter expressions cannot exceed \(DisplayFilter.maximumExpressionUTF16Length) UTF-16 units."
            )
        }
        self = switch kind {
        case .literal: .literal(text)
        case .regularExpression: .regularExpression(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard text.utf16.count <= DisplayFilter.maximumExpressionUTF16Length else {
            throw EncodingError.invalidValue(
                self,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription:
                        "Display filter expressions cannot exceed \(DisplayFilter.maximumExpressionUTF16Length) UTF-16 units."
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .literal(let text):
            try container.encode(Kind.literal, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .regularExpression(let text):
            try container.encode(Kind.regularExpression, forKey: .kind)
            try container.encode(text, forKey: .text)
        }
    }
}

public enum DisplayFilterRowPredicate: String, Codable, CaseIterable, Equatable, Sendable {
    case any
    case significant
    case unchanged
    case moved
}

public enum DisplayFilterPreset: String, Codable, CaseIterable, Equatable, Sendable {
    case allRows
    case significantRows
    case unchangedRows
    case movedRows

    public var filter: DisplayFilter {
        switch self {
        case .allRows:
            DisplayFilter()
        case .significantRows:
            DisplayFilter(predicate: .significant)
        case .unchangedRows:
            DisplayFilter(predicate: .unchanged)
        case .movedRows:
            DisplayFilter(predicate: .moved)
        }
    }
}

public struct DisplayFilterLimits: Equatable, Sendable {
    public static let `default` = DisplayFilterLimits()

    public let maximumRows: Int
    public let maximumExpressionUTF16Length: Int
    public let maximumLineUTF16Length: Int
    public let maximumTotalTextUTF16Length: Int
    public let maximumTextEvaluations: Int
    public let maximumRegularExpressionProgressSteps: Int

    public init(
        maximumRows: Int = 1_048_576,
        maximumExpressionUTF16Length: Int = DisplayFilter.maximumExpressionUTF16Length,
        maximumLineUTF16Length: Int = 1_048_576,
        maximumTotalTextUTF16Length: Int = 64 * 1_048_576,
        maximumTextEvaluations: Int = 2_097_152,
        maximumRegularExpressionProgressSteps: Int = 1_000_000
    ) {
        precondition(maximumRows >= 0)
        precondition(
            maximumExpressionUTF16Length >= 0
                && maximumExpressionUTF16Length <= DisplayFilter.maximumExpressionUTF16Length
        )
        precondition(maximumLineUTF16Length >= 0)
        precondition(maximumTotalTextUTF16Length >= 0)
        precondition(maximumTextEvaluations >= 0)
        precondition(maximumRegularExpressionProgressSteps > 0)
        self.maximumRows = maximumRows
        self.maximumExpressionUTF16Length = maximumExpressionUTF16Length
        self.maximumLineUTF16Length = maximumLineUTF16Length
        self.maximumTotalTextUTF16Length = maximumTotalTextUTF16Length
        self.maximumTextEvaluations = maximumTextEvaluations
        self.maximumRegularExpressionProgressSteps = maximumRegularExpressionProgressSteps
    }
}

public enum DisplayFilterError: Error, LocalizedError, Equatable, Sendable {
    case encodedDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case expressionTooLarge(maximumUTF16Length: Int)
    case invalidRegularExpression(String)
    case tooManyRows(maximumRows: Int)
    case lineTooLong(maximumUTF16Length: Int)
    case inputTooLarge(maximumUTF16Length: Int)
    case tooManyTextEvaluations(maximumEvaluations: Int)
    case regularExpressionEvaluationFailed
    case regularExpressionEvaluationLimitExceeded(maximumProgressSteps: Int)
    case movedLineMetadataUnavailable
    case invalidHistoryCapacity(Int)
    case tooManyHistoryEntries(maximumEntries: Int)
    case duplicateHistoryEntry

    public var errorDescription: String? {
        switch self {
        case .encodedDataTooLarge(let maximumBytes):
            "Display filter history data exceeds the \(maximumBytes)-byte limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported display filter history schema version: \(version)."
        case .expressionTooLarge(let maximumUTF16Length):
            "Display filter expression exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .invalidRegularExpression(let expression):
            "Invalid display filter regular expression: \(expression)"
        case .tooManyRows(let maximumRows):
            "Display filtering exceeds the \(maximumRows)-row limit."
        case .lineTooLong(let maximumUTF16Length):
            "A display-filter line exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .inputTooLarge(let maximumUTF16Length):
            "Display-filter text exceeds the \(maximumUTF16Length)-UTF-16-unit limit."
        case .tooManyTextEvaluations(let maximumEvaluations):
            "Display filtering exceeds the \(maximumEvaluations)-text-evaluation limit."
        case .regularExpressionEvaluationFailed:
            "Display filter regular expression evaluation failed."
        case .regularExpressionEvaluationLimitExceeded(let maximumProgressSteps):
            "Display filter regular expression exceeds the \(maximumProgressSteps)-step evaluation limit."
        case .movedLineMetadataUnavailable:
            "Moved-row filtering requires available moved-line analysis metadata."
        case .invalidHistoryCapacity(let capacity):
            "Display filter history capacity is invalid: \(capacity)."
        case .tooManyHistoryEntries(let maximumEntries):
            "Display filter history cannot exceed \(maximumEntries) entries."
        case .duplicateHistoryEntry:
            "Display filter history contains a duplicate entry."
        }
    }
}

public struct DisplayFilterResult: Equatable, Sendable {
    public let rows: [DiffRow]
    /// Original row index for each entry in `rows`.
    public let sourceRowIndices: [Int]
    /// Selection in filtered `rows`, after identity preservation or nearest-row fallback.
    public let selectedRowIndex: Int?

    public var selectedSourceRowIndex: Int? {
        selectedRowIndex.map { sourceRowIndices[$0] }
    }

    public var selectedRowID: DiffRow.ID? {
        selectedRowIndex.map { rows[$0].id }
    }

    public init(
        rows: [DiffRow],
        sourceRowIndices: [Int],
        selectedRowIndex: Int?
    ) {
        precondition(rows.count == sourceRowIndices.count)
        precondition(selectedRowIndex.map(rows.indices.contains) ?? true)
        precondition(
            zip(sourceRowIndices, sourceRowIndices.dropFirst()).allSatisfy(<)
                && (sourceRowIndices.first.map { $0 >= 0 } ?? true)
        )
        self.rows = rows
        self.sourceRowIndices = sourceRowIndices
        self.selectedRowIndex = selectedRowIndex
    }

    public func visibleRowIndex(forSourceRowIndex sourceRowIndex: Int) -> Int? {
        var lower = sourceRowIndices.startIndex
        var upper = sourceRowIndices.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if sourceRowIndices[middle] < sourceRowIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < sourceRowIndices.endIndex, sourceRowIndices[lower] == sourceRowIndex else {
            return nil
        }
        return lower
    }
}

public struct DisplayFilter: Codable, Equatable, Hashable, Sendable {
    public static let maximumExpressionUTF16Length = 4_096

    public var expression: DisplayFilterExpression
    public var caseSensitive: Bool
    /// Inverts the complete predicate-and-expression result.
    public var invert: Bool
    public var predicate: DisplayFilterRowPredicate

    public init(
        expression: DisplayFilterExpression = .literal(""),
        caseSensitive: Bool = false,
        invert: Bool = false,
        predicate: DisplayFilterRowPredicate = .any
    ) {
        self.expression = expression
        self.caseSensitive = caseSensitive
        self.invert = invert
        self.predicate = predicate
    }

    public init(
        literal: String,
        caseSensitive: Bool = false,
        invert: Bool = false,
        predicate: DisplayFilterRowPredicate = .any
    ) {
        self.init(
            expression: .literal(literal),
            caseSensitive: caseSensitive,
            invert: invert,
            predicate: predicate
        )
    }

    public init(
        regularExpression: String,
        caseSensitive: Bool = false,
        invert: Bool = false,
        predicate: DisplayFilterRowPredicate = .any
    ) {
        self.init(
            expression: .regularExpression(regularExpression),
            caseSensitive: caseSensitive,
            invert: invert,
            predicate: predicate
        )
    }

    public func validate(limits: DisplayFilterLimits = .default) throws {
        _ = try compiledMatcher(limits: limits)
    }

    public func apply(
        to result: LineDiffResult,
        selectedRowIndex: Int? = nil,
        selectedRowID: DiffRow.ID? = nil,
        limits: DisplayFilterLimits = .default
    ) throws -> DisplayFilterResult {
        let movedLines = result.movedLineAnalysisStatus == .available ? result.movedLines : nil
        return try apply(
            to: result.rows,
            movedLines: movedLines,
            selectedRowIndex: selectedRowIndex,
            selectedRowID: selectedRowID,
            limits: limits
        )
    }

    public func apply(
        to rows: [DiffRow],
        movedLines: MovedLines? = nil,
        selectedRowIndex: Int? = nil,
        selectedRowID: DiffRow.ID? = nil,
        limits: DisplayFilterLimits = .default
    ) throws -> DisplayFilterResult {
        let matcher = try compiledMatcher(limits: limits)
        guard rows.count <= limits.maximumRows else {
            throw DisplayFilterError.tooManyRows(maximumRows: limits.maximumRows)
        }
        guard predicate != .moved || movedLines != nil else {
            throw DisplayFilterError.movedLineMetadataUnavailable
        }
        try Task.checkCancellation()

        var budget = WorkBudget(limits: limits)
        var filteredRows: [DiffRow] = []
        var sourceIndices: [Int] = []
        filteredRows.reserveCapacity(rows.count)
        sourceIndices.reserveCapacity(rows.count)

        for (index, row) in rows.enumerated() {
            if index & 0xFF == 0 { try Task.checkCancellation() }
            let predicateMatches = matchesPredicate(row, movedLines: movedLines)
            let textMatches = try predicateMatches
                ? matchesText(row, matcher: matcher, budget: &budget)
                : false
            if invert != (predicateMatches && textMatches) {
                filteredRows.append(row)
                sourceIndices.append(index)
            }
        }
        try Task.checkCancellation()

        let selection = Self.remappedSelection(
            sourceRows: rows,
            visibleSourceIndices: sourceIndices,
            selectedSourceIndex: selectedRowIndex,
            selectedRowID: selectedRowID
        )
        return DisplayFilterResult(
            rows: filteredRows,
            sourceRowIndices: sourceIndices,
            selectedRowIndex: selection
        )
    }

    private enum CodingKeys: String, CodingKey {
        case expression
        case caseSensitive
        case invert
        case predicate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expression = try container.decode(DisplayFilterExpression.self, forKey: .expression)
        caseSensitive = try container.decode(Bool.self, forKey: .caseSensitive)
        invert = try container.decode(Bool.self, forKey: .invert)
        predicate = try container.decode(DisplayFilterRowPredicate.self, forKey: .predicate)
        do {
            try validate()
        } catch let error as DisplayFilterError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.localizedDescription)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        do {
            try validate()
        } catch let error as DisplayFilterError {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: encoder.codingPath, debugDescription: error.localizedDescription)
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expression, forKey: .expression)
        try container.encode(caseSensitive, forKey: .caseSensitive)
        try container.encode(invert, forKey: .invert)
        try container.encode(predicate, forKey: .predicate)
    }

    private func compiledMatcher(limits: DisplayFilterLimits) throws -> CompiledMatcher? {
        let text = expression.text
        guard text.utf16.count <= limits.maximumExpressionUTF16Length else {
            throw DisplayFilterError.expressionTooLarge(
                maximumUTF16Length: limits.maximumExpressionUTF16Length
            )
        }
        guard !text.isEmpty else { return nil }
        switch expression {
        case .literal:
            return .literal(text, caseSensitive: caseSensitive)
        case .regularExpression:
            do {
                return .regularExpression(
                    try NSRegularExpression(
                        pattern: text,
                        options: caseSensitive ? [] : [.caseInsensitive]
                    )
                )
            } catch {
                throw DisplayFilterError.invalidRegularExpression(text)
            }
        }
    }

    private func matchesPredicate(_ row: DiffRow, movedLines: MovedLines?) -> Bool {
        switch predicate {
        case .any:
            return true
        case .significant:
            return row.kind != .unchanged
        case .unchanged:
            return row.kind == .unchanged
        case .moved:
            guard let movedLines else { return false }
            let id = row.id
            return id.leftNumber.flatMap(movedLines.rightLine(forLeftLine:)) != nil
                || id.rightNumber.flatMap(movedLines.leftLine(forRightLine:)) != nil
        }
    }

    private func matchesText(
        _ row: DiffRow,
        matcher: CompiledMatcher?,
        budget: inout WorkBudget
    ) throws -> Bool {
        guard let matcher else { return true }
        if let left = row.left?.text, try matcher.matches(left, budget: &budget) {
            return true
        }
        guard let right = row.right?.text else { return false }
        return try matcher.matches(right, budget: &budget)
    }

    private static func remappedSelection(
        sourceRows: [DiffRow],
        visibleSourceIndices: [Int],
        selectedSourceIndex: Int?,
        selectedRowID: DiffRow.ID?
    ) -> Int? {
        guard !visibleSourceIndices.isEmpty else { return nil }

        let anchor: Int?
        if let selectedRowID {
            if let selectedSourceIndex,
               sourceRows.indices.contains(selectedSourceIndex),
               sourceRows[selectedSourceIndex].id == selectedRowID {
                anchor = selectedSourceIndex
            } else {
                anchor = sourceRows.firstIndex { $0.id == selectedRowID }
            }
        } else if let selectedSourceIndex, sourceRows.indices.contains(selectedSourceIndex) {
            anchor = selectedSourceIndex
        } else {
            anchor = nil
        }
        guard let anchor else { return nil }

        var lower = visibleSourceIndices.startIndex
        var upper = visibleSourceIndices.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if visibleSourceIndices[middle] < anchor {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower < visibleSourceIndices.endIndex { return lower }
        return visibleSourceIndices.index(before: visibleSourceIndices.endIndex)
    }
}

private enum CompiledMatcher {
    case literal(String, caseSensitive: Bool)
    case regularExpression(NSRegularExpression)

    func matches(_ text: String, budget: inout WorkBudget) throws -> Bool {
        try budget.chargeText(text)
        switch self {
        case .literal(let pattern, let caseSensitive):
            let source = text as NSString
            let range = source.range(
                of: pattern,
                options: caseSensitive ? [] : [.caseInsensitive],
                range: NSRange(location: 0, length: source.length)
            )
            return range.location != NSNotFound
        case .regularExpression(let expression):
            return try matchesRegularExpression(expression, in: text, budget: &budget)
        }
    }

    private func matchesRegularExpression(
        _ expression: NSRegularExpression,
        in text: String,
        budget: inout WorkBudget
    ) throws -> Bool {
        let remainingSteps = budget.remainingRegularExpressionProgressSteps
        guard remainingSteps > 0 else {
            throw DisplayFilterError.regularExpressionEvaluationLimitExceeded(
                maximumProgressSteps: budget.limits.maximumRegularExpressionProgressSteps
            )
        }

        var matched = false
        var failed = false
        var cancelled = false
        var exceededLimit = false
        var progressSteps = 0
        expression.enumerateMatches(
            in: text,
            options: [.reportProgress, .reportCompletion],
            range: NSRange(location: 0, length: text.utf16.count)
        ) { result, flags, stop in
            if Task.isCancelled {
                cancelled = true
                stop.pointee = true
                return
            }
            if flags.contains(.internalError) {
                failed = true
                stop.pointee = true
                return
            }
            if flags.contains(.progress) || result != nil {
                guard progressSteps < remainingSteps else {
                    exceededLimit = true
                    stop.pointee = true
                    return
                }
                progressSteps += 1
            }
            if result != nil {
                matched = true
                stop.pointee = true
            }
        }
        budget.regularExpressionProgressSteps += progressSteps
        if cancelled { throw CancellationError() }
        if failed { throw DisplayFilterError.regularExpressionEvaluationFailed }
        if exceededLimit {
            throw DisplayFilterError.regularExpressionEvaluationLimitExceeded(
                maximumProgressSteps: budget.limits.maximumRegularExpressionProgressSteps
            )
        }
        return matched
    }
}

private struct WorkBudget {
    let limits: DisplayFilterLimits
    var totalTextUTF16Length = 0
    var textEvaluations = 0
    var regularExpressionProgressSteps = 0

    var remainingRegularExpressionProgressSteps: Int {
        limits.maximumRegularExpressionProgressSteps - regularExpressionProgressSteps
    }

    mutating func chargeText(_ text: String) throws {
        guard textEvaluations < limits.maximumTextEvaluations else {
            throw DisplayFilterError.tooManyTextEvaluations(
                maximumEvaluations: limits.maximumTextEvaluations
            )
        }
        textEvaluations += 1

        let length = text.utf16.count
        guard length <= limits.maximumLineUTF16Length else {
            throw DisplayFilterError.lineTooLong(
                maximumUTF16Length: limits.maximumLineUTF16Length
            )
        }
        let (nextLength, overflow) = totalTextUTF16Length.addingReportingOverflow(length)
        guard !overflow, nextLength <= limits.maximumTotalTextUTF16Length else {
            throw DisplayFilterError.inputTooLarge(
                maximumUTF16Length: limits.maximumTotalTextUTF16Length
            )
        }
        totalTextUTF16Length = nextLength
    }
}

/// Bounded MRU history. `entries[0]` is the most recently applied filter.
public struct DisplayFilterHistory: Codable, Equatable, Sendable, RandomAccessCollection {
    public static let currentSchemaVersion = 1
    public static let defaultCapacity = 20
    public static let maximumCapacity = 100
    public static let maximumEncodedBytes = 2 * 1_048_576

    public typealias Index = Int

    public let capacity: Int
    public private(set) var entries: [DisplayFilter]

    public var startIndex: Int { entries.startIndex }
    public var endIndex: Int { entries.endIndex }

    public subscript(position: Int) -> DisplayFilter {
        entries[position]
    }

    public init(capacity: Int = defaultCapacity) {
        precondition(capacity > 0 && capacity <= Self.maximumCapacity)
        self.capacity = capacity
        entries = []
    }

    public init(_ entries: [DisplayFilter], capacity: Int = defaultCapacity) throws {
        guard capacity > 0 && capacity <= Self.maximumCapacity else {
            throw DisplayFilterError.invalidHistoryCapacity(capacity)
        }
        guard entries.count <= capacity else {
            throw DisplayFilterError.tooManyHistoryEntries(maximumEntries: capacity)
        }
        var seen: Set<DisplayFilter> = []
        for entry in entries {
            try entry.validate()
            guard seen.insert(entry).inserted else {
                throw DisplayFilterError.duplicateHistoryEntry
            }
        }
        self.capacity = capacity
        self.entries = entries
    }

    @discardableResult
    public mutating func record(_ filter: DisplayFilter) throws -> Bool {
        try filter.validate()
        guard entries.first != filter else { return false }
        entries.removeAll { $0 == filter }
        entries.insert(filter, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        return true
    }

    @discardableResult
    public mutating func remove(_ filter: DisplayFilter) -> Bool {
        guard let index = entries.firstIndex(of: filter) else { return false }
        entries.remove(at: index)
        return true
    }

    public mutating func removeAll(keepingCapacity: Bool = false) {
        entries.removeAll(keepingCapacity: keepingCapacity)
    }

    public func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw DisplayFilterError.encodedDataTooLarge(
                maximumBytes: Self.maximumEncodedBytes
            )
        }
        return data
    }

    public static func decode(from data: Data) throws -> DisplayFilterHistory {
        guard data.count <= Self.maximumEncodedBytes else {
            throw DisplayFilterError.encodedDataTooLarge(maximumBytes: Self.maximumEncodedBytes)
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case capacity
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DisplayFilterError.unsupportedSchemaVersion(schemaVersion)
        }
        let capacity = try container.decode(Int.self, forKey: .capacity)
        guard capacity > 0 && capacity <= Self.maximumCapacity else {
            throw DecodingError.dataCorruptedError(
                forKey: .capacity,
                in: container,
                debugDescription:
                    "Display filter history capacity must be between 1 and \(Self.maximumCapacity)."
            )
        }

        var entriesContainer = try container.nestedUnkeyedContainer(forKey: .entries)
        if let count = entriesContainer.count, count > capacity {
            throw DecodingError.dataCorruptedError(
                forKey: .entries,
                in: container,
                debugDescription: "Display filter history cannot exceed its capacity of \(capacity)."
            )
        }

        var decoded: [DisplayFilter] = []
        decoded.reserveCapacity(Swift.min(entriesContainer.count ?? capacity, capacity))
        var seen: Set<DisplayFilter> = []
        while !entriesContainer.isAtEnd {
            guard decoded.count < capacity else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: entriesContainer.codingPath,
                        debugDescription:
                            "Display filter history cannot exceed its capacity of \(capacity)."
                    )
                )
            }
            let filter = try entriesContainer.decode(DisplayFilter.self)
            guard seen.insert(filter).inserted else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: entriesContainer.codingPath,
                        debugDescription: "Display filter history contains a duplicate entry."
                    )
                )
            }
            decoded.append(filter)
        }
        self.capacity = capacity
        entries = decoded
    }

    public func encode(to encoder: Encoder) throws {
        guard capacity > 0 && capacity <= Self.maximumCapacity else {
            throw EncodingError.invalidValue(
                capacity,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "Display filter history capacity is invalid."
                )
            )
        }
        guard entries.count <= capacity, Set(entries).count == entries.count else {
            throw EncodingError.invalidValue(
                entries,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "Display filter history entries are invalid."
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(entries, forKey: .entries)
    }
}

/// Apply state commits only after filtering, validation, and cancellation checks succeed.
public struct DisplayFilterModel: Equatable, Sendable {
    public private(set) var appliedFilter: DisplayFilter
    public private(set) var history: DisplayFilterHistory

    public init(historyCapacity: Int = DisplayFilterHistory.defaultCapacity) {
        appliedFilter = DisplayFilterPreset.allRows.filter
        history = DisplayFilterHistory(capacity: historyCapacity)
    }

    public init(
        appliedFilter: DisplayFilter,
        history: DisplayFilterHistory = DisplayFilterHistory()
    ) throws {
        try appliedFilter.validate()
        self.appliedFilter = appliedFilter
        self.history = history
    }

    @discardableResult
    public mutating func apply(
        _ filter: DisplayFilter,
        to result: LineDiffResult,
        selectedRowIndex: Int? = nil,
        selectedRowID: DiffRow.ID? = nil,
        limits: DisplayFilterLimits = .default
    ) throws -> DisplayFilterResult {
        let filtered = try filter.apply(
            to: result,
            selectedRowIndex: selectedRowIndex,
            selectedRowID: selectedRowID,
            limits: limits
        )
        try commit(filter)
        return filtered
    }

    @discardableResult
    public mutating func apply(
        _ filter: DisplayFilter,
        to rows: [DiffRow],
        movedLines: MovedLines? = nil,
        selectedRowIndex: Int? = nil,
        selectedRowID: DiffRow.ID? = nil,
        limits: DisplayFilterLimits = .default
    ) throws -> DisplayFilterResult {
        let filtered = try filter.apply(
            to: rows,
            movedLines: movedLines,
            selectedRowIndex: selectedRowIndex,
            selectedRowID: selectedRowID,
            limits: limits
        )
        try commit(filter)
        return filtered
    }

    private mutating func commit(_ filter: DisplayFilter) throws {
        try Task.checkCancellation()
        var updatedHistory = history
        try updatedHistory.record(filter)
        appliedFilter = filter
        history = updatedHistory
    }
}
