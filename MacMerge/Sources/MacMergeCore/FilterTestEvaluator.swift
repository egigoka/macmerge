import CXDiff
import Foundation

public enum FilterTestKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case filename
    case display
    case line
    case substitution
}

public struct FilterTestLimits: Equatable, Hashable, Sendable {
    public static let `default` = FilterTestLimits()

    public let maximumCaseCount: Int
    public let maximumCollectionCount: Int
    public let maximumConditionDepth: Int
    public let maximumPatternUTF8Bytes: Int
    public let maximumReplacementUTF8Bytes: Int
    public let maximumTotalPatternUTF8Bytes: Int
    public let maximumInputUTF8Bytes: Int
    public let maximumTotalInputUTF8Bytes: Int
    public let maximumOutputUTF8Bytes: Int
    public let maximumWork: Int
    public let maximumResults: Int

    public init(
        maximumCaseCount: Int = 1_024,
        maximumCollectionCount: Int = 1_024,
        maximumConditionDepth: Int = 64,
        maximumPatternUTF8Bytes: Int = 64 * 1_024,
        maximumReplacementUTF8Bytes: Int = 1_024 * 1_024,
        maximumTotalPatternUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumInputUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumTotalInputUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumOutputUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumWork: Int = 256 * 1_024 * 1_024,
        maximumResults: Int = 100_000
    ) {
        precondition(maximumCaseCount >= 0)
        precondition(maximumCollectionCount >= 0)
        precondition(maximumConditionDepth >= 0)
        precondition(maximumPatternUTF8Bytes >= 0)
        precondition(maximumReplacementUTF8Bytes >= 0)
        precondition(maximumTotalPatternUTF8Bytes >= 0)
        precondition(maximumInputUTF8Bytes >= 0)
        precondition(maximumTotalInputUTF8Bytes >= 0)
        precondition(maximumOutputUTF8Bytes >= 0)
        precondition(maximumWork >= 0)
        precondition(maximumResults >= 0)
        self.maximumCaseCount = maximumCaseCount
        self.maximumCollectionCount = maximumCollectionCount
        self.maximumConditionDepth = maximumConditionDepth
        self.maximumPatternUTF8Bytes = maximumPatternUTF8Bytes
        self.maximumReplacementUTF8Bytes = maximumReplacementUTF8Bytes
        self.maximumTotalPatternUTF8Bytes = maximumTotalPatternUTF8Bytes
        self.maximumInputUTF8Bytes = maximumInputUTF8Bytes
        self.maximumTotalInputUTF8Bytes = maximumTotalInputUTF8Bytes
        self.maximumOutputUTF8Bytes = maximumOutputUTF8Bytes
        self.maximumWork = maximumWork
        self.maximumResults = maximumResults
    }
}

public enum FilterTestError: Error, Equatable, LocalizedError, Sendable {
    case caseLimitExceeded(maximum: Int)
    case collectionLimitExceeded(maximum: Int)
    case conditionDepthExceeded(maximum: Int)
    case patternTooLarge(kind: FilterTestKind, ruleIndex: Int?, maximumUTF8Bytes: Int)
    case replacementTooLarge(ruleIndex: Int, maximumUTF8Bytes: Int)
    case totalPatternSizeExceeded(maximumUTF8Bytes: Int)
    case inputTooLarge(kind: FilterTestKind, maximumUTF8Bytes: Int)
    case totalInputSizeExceeded(maximumUTF8Bytes: Int)
    case outputTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximumWork: Int)
    case resultLimitExceeded(maximumResults: Int)

    public var errorDescription: String? {
        switch self {
        case .caseLimitExceeded(let maximum):
            "Filter testing exceeds the \(maximum)-case limit."
        case .collectionLimitExceeded(let maximum):
            "A filter-test collection exceeds the \(maximum)-element limit."
        case .conditionDepthExceeded(let maximum):
            "Filter-test conditions exceed the \(maximum)-level depth limit."
        case .patternTooLarge(let kind, let ruleIndex, let maximum):
            "The \(kind.rawValue) filter pattern\(Self.ruleSuffix(ruleIndex)) exceeds the \(maximum)-byte UTF-8 limit."
        case .replacementTooLarge(let ruleIndex, let maximum):
            "Substitution replacement at rule \(ruleIndex) exceeds the \(maximum)-byte UTF-8 limit."
        case .totalPatternSizeExceeded(let maximum):
            "Filter-test patterns exceed the \(maximum)-byte total UTF-8 limit."
        case .inputTooLarge(let kind, let maximum):
            "The \(kind.rawValue) filter input exceeds the \(maximum)-byte UTF-8 limit."
        case .totalInputSizeExceeded(let maximum):
            "Filter-test inputs exceed the \(maximum)-byte total UTF-8 limit."
        case .outputTooLarge(let maximum):
            "Filter-test output exceeds the \(maximum)-byte limit."
        case .workLimitExceeded(let maximum):
            "Filter testing exceeds the \(maximum)-unit work limit."
        case .resultLimitExceeded(let maximum):
            "Filter testing exceeds the \(maximum)-result limit."
        }
    }

    private static func ruleSuffix(_ index: Int?) -> String {
        index.map { " at rule \($0)" } ?? ""
    }
}

public struct FilenameFilterTestCase:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let enabled: Bool
    public let rules: [FilenameFilterRule]
    public let defaultDecision: FilenameFilterDecision
    public let matchSemantics: FilenameFilterMatchSemantics
    public let casePolicy: FilenameFilterCasePolicy
    public let relativePath: String
    public let entryKind: FilenameFilterEntryKind
    public let filenameLimits: FilenameFilterLimits

    public init(
        enabled: Bool = true,
        rules: [FilenameFilterRule],
        defaultDecision: FilenameFilterDecision = .include,
        matchSemantics: FilenameFilterMatchSemantics = .lastMatchWins,
        casePolicy: FilenameFilterCasePolicy = .sensitive,
        relativePath: String,
        entryKind: FilenameFilterEntryKind = .file,
        limits: FilenameFilterLimits = .default
    ) {
        self.enabled = enabled
        self.rules = rules
        self.defaultDecision = defaultDecision
        self.matchSemantics = matchSemantics
        self.casePolicy = casePolicy
        self.relativePath = relativePath
        self.entryKind = entryKind
        filenameLimits = limits
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.enabled == rhs.enabled
            && filterTestFilenameRulesEqual(lhs.rules, rhs.rules)
            && lhs.defaultDecision == rhs.defaultDecision
            && lhs.matchSemantics == rhs.matchSemantics
            && lhs.casePolicy == rhs.casePolicy
            && filterTestStringsAreIdentical(lhs.relativePath, rhs.relativePath)
            && lhs.entryKind == rhs.entryKind
            && lhs.filenameLimits == rhs.filenameLimits
    }

    public var description: String { "FilenameFilterTestCase(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "enabled": enabled,
                "ruleCount": rules.count,
                "entryKind": entryKind.rawValue,
                "input": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct DisplayFilterTestInput:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let row: DiffRow
    public let movedLines: MovedLines?

    public init(row: DiffRow, movedLines: MovedLines? = nil) {
        self.row = row
        self.movedLines = movedLines
    }

    public init(
        leftText: String?,
        rightText: String?,
        kind: DiffKind,
        leftLineNumber: Int = 1,
        rightLineNumber: Int = 1,
        movedLines: MovedLines? = nil
    ) {
        row = DiffRow(
            left: leftText.map { DiffLine(number: leftLineNumber, text: $0) },
            right: rightText.map { DiffLine(number: rightLineNumber, text: $0) },
            kind: kind
        )
        self.movedLines = movedLines
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        filterTestDiffLinesEqual(lhs.row.left, rhs.row.left)
            && filterTestDiffLinesEqual(lhs.row.right, rhs.row.right)
            && lhs.row.kind == rhs.row.kind
            && lhs.row.hasEqualSourceRecords == rhs.row.hasEqualSourceRecords
            && lhs.movedLines == rhs.movedLines
    }

    public var description: String { "DisplayFilterTestInput(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": String(describing: row.kind),
                "hasLeft": row.left != nil,
                "hasRight": row.right != nil,
                "hasMovedMetadata": movedLines != nil,
                "input": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct DisplayFilterTestCase:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let enabled: Bool
    public let filter: DisplayFilter
    public let input: DisplayFilterTestInput
    public let displayLimits: DisplayFilterLimits

    public init(
        enabled: Bool = true,
        filter: DisplayFilter,
        input: DisplayFilterTestInput,
        limits: DisplayFilterLimits = .default
    ) {
        self.enabled = enabled
        self.filter = filter
        self.input = input
        displayLimits = limits
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.enabled == rhs.enabled
            && filterTestDisplayFiltersEqual(lhs.filter, rhs.filter)
            && lhs.input == rhs.input
            && lhs.displayLimits == rhs.displayLimits
    }

    public var description: String { "DisplayFilterTestCase(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "enabled": enabled,
                "predicate": filter.predicate.rawValue,
                "input": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct LineFilterTestCase:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let enabled: Bool
    public let rules: [LineFilterRule]
    public let input: String

    public init(enabled: Bool = true, rules: [LineFilterRule], input: String) {
        self.enabled = enabled
        self.rules = rules
        self.input = input
    }

    public init(enabled: Bool = true, rule: LineFilterRule, input: String) {
        self.init(enabled: enabled, rules: [rule], input: input)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.enabled == rhs.enabled
            && filterTestLineRulesEqual(lhs.rules, rhs.rules)
            && filterTestStringsAreIdentical(lhs.input, rhs.input)
    }

    public var description: String { "LineFilterTestCase(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "enabled": enabled,
                "ruleCount": rules.count,
                "input": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct SubstitutionFilterTestCase:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let enabled: Bool
    public let rules: [SubstitutionRule]
    public let input: String

    public init(enabled: Bool = true, rules: [SubstitutionRule], input: String) {
        self.enabled = enabled
        self.rules = rules
        self.input = input
    }

    public init(enabled: Bool = true, rule: SubstitutionRule, input: String) {
        self.init(enabled: enabled, rules: [rule], input: input)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.enabled == rhs.enabled
            && filterTestSubstitutionRulesEqual(lhs.rules, rhs.rules)
            && filterTestStringsAreIdentical(lhs.input, rhs.input)
    }

    public var description: String { "SubstitutionFilterTestCase(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "enabled": enabled,
                "ruleCount": rules.count,
                "input": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum FilterTestCase:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case filename(FilenameFilterTestCase)
    case display(DisplayFilterTestCase)
    case line(LineFilterTestCase)
    case substitution(SubstitutionFilterTestCase)

    public var kind: FilterTestKind {
        switch self {
        case .filename: .filename
        case .display: .display
        case .line: .line
        case .substitution: .substitution
        }
    }

    public var description: String { "FilterTestCase.\(kind.rawValue)(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["kind": kind.rawValue, "value": "<redacted>"], displayStyle: .enum)
    }
}

public enum FilterTestComposition: String, CaseIterable, Equatable, Hashable, Sendable {
    case all
    case any
}

public indirect enum FilterTestCondition:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case test(FilterTestCase)
    case all([FilterTestCondition])
    case any([FilterTestCondition])
    case not(FilterTestCondition)

    public var description: String {
        switch self {
        case .test(let test): "FilterTestCondition.test(\(test.kind.rawValue):<redacted>)"
        case .all(let conditions): "FilterTestCondition.all(count:\(conditions.count))"
        case .any(let conditions): "FilterTestCondition.any(count:\(conditions.count))"
        case .not: "FilterTestCondition.not(<redacted>)"
        }
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        switch self {
        case .test(let test):
            Mirror(self, children: ["kind": test.kind.rawValue, "value": "<redacted>"], displayStyle: .enum)
        case .all(let conditions):
            Mirror(self, children: ["operation": "all", "count": conditions.count], displayStyle: .enum)
        case .any(let conditions):
            Mirror(self, children: ["operation": "any", "count": conditions.count], displayStyle: .enum)
        case .not:
            Mirror(self, children: ["operation": "not", "value": "<redacted>"], displayStyle: .enum)
        }
    }
}

public enum FilterTestResultState: String, Equatable, Hashable, Sendable {
    case evaluated
    case noOp
    case invalid
    case failed
}

public enum FilterTestOutcome: String, Equatable, Hashable, Sendable {
    case matched
    case notMatched
    case noOp
    case invalid
    case failed
}

public enum FilterTestRangeField: String, Equatable, Hashable, Sendable {
    case input
    case leftInput
    case rightInput
    case output
}

public struct FilterTestMatchRange: Equatable, Hashable, Sendable {
    public let field: FilterTestRangeField
    public let utf16Range: NSRange

    public init(field: FilterTestRangeField, utf16Range: NSRange) {
        self.field = field
        self.utf16Range = utf16Range
    }
}

public struct FilterTestOutput:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let bytes: [UInt8]

    public var string: String? { String(bytes: bytes, encoding: .utf8) }
    public var isValidUTF8: Bool { string != nil }
    public var utf8ByteCount: Int { bytes.count }

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public init(_ string: String) {
        bytes = Array(string.utf8)
    }

    public var description: String { "FilterTestOutput(<redacted>, bytes:\(bytes.count))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["byteCount": bytes.count, "isValidUTF8": isValidUTF8, "value": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public enum FilterTestResultValue:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case filename(decision: FilenameFilterDecision)
    case display(isVisible: Bool)
    case line(isFiltered: Bool)
    case substitution(output: FilterTestOutput, didMatch: Bool)

    public var description: String {
        switch self {
        case .filename(let decision): "filename(decision:\(decision.rawValue))"
        case .display(let visible): "display(isVisible:\(visible))"
        case .line(let filtered): "line(isFiltered:\(filtered))"
        case .substitution(let output, let matched):
            "substitution(didMatch:\(matched), outputBytes:\(output.utf8ByteCount), value:<redacted>)"
        }
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        switch self {
        case .filename(let decision):
            Mirror(self, children: ["decision": decision.rawValue], displayStyle: .enum)
        case .display(let visible):
            Mirror(self, children: ["isVisible": visible], displayStyle: .enum)
        case .line(let filtered):
            Mirror(self, children: ["isFiltered": filtered], displayStyle: .enum)
        case .substitution(let output, let matched):
            Mirror(
                self,
                children: [
                    "didMatch": matched,
                    "outputByteCount": output.utf8ByteCount,
                    "output": "<redacted>"
                ],
                displayStyle: .enum
            )
        }
    }
}

public enum FilterTestDiagnosticCode: String, CaseIterable, Equatable, Hashable, Sendable {
    case disabled
    case noRules
    case emptyPatternIgnored
    case collectionLimitExceeded
    case invalidPattern
    case unsupportedPattern
    case patternContainsNull
    case patternLimitExceeded
    case totalPatternLimitExceeded
    case compiledPatternLimitExceeded
    case invalidInput
    case inputLimitExceeded
    case evaluationLimitExceeded
    case engineFailure
    case outputLimitExceeded
    case outputIsNotValidUTF8
    case changedLineStructure
}

public struct FilterTestDiagnostic:
    Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible
{
    public let kind: FilterTestKind
    public let code: FilterTestDiagnosticCode
    public let ruleIndex: Int?
    public let unicodeScalarOffset: Int?
    public let limit: Int?
    public let engineCode: Int32?

    public init(
        kind: FilterTestKind,
        code: FilterTestDiagnosticCode,
        ruleIndex: Int? = nil,
        unicodeScalarOffset: Int? = nil,
        limit: Int? = nil,
        engineCode: Int32? = nil
    ) {
        self.kind = kind
        self.code = code
        self.ruleIndex = ruleIndex
        self.unicodeScalarOffset = unicodeScalarOffset
        self.limit = limit
        self.engineCode = engineCode
    }

    public var description: String {
        var value = "filter-test/\(kind.rawValue)/\(code.rawValue)"
        if let ruleIndex { value += "/rule=\(ruleIndex)" }
        if let unicodeScalarOffset { value += "/offset=\(unicodeScalarOffset)" }
        if let limit { value += "/limit=\(limit)" }
        if let engineCode { value += "/engine=\(engineCode)" }
        return value
    }

    public var debugDescription: String { description }
}

public struct FilterTestCaseResult:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let kind: FilterTestKind
    public let state: FilterTestResultState
    public let value: FilterTestResultValue?
    public let matchedRuleIndices: [Int]
    public let matchRanges: [FilterTestMatchRange]
    public let diagnostics: [FilterTestDiagnostic]

    public var outcome: FilterTestOutcome {
        switch state {
        case .noOp: return .noOp
        case .invalid: return .invalid
        case .failed: return .failed
        case .evaluated:
            return filterTestTruth(from: value) == true ? .matched : .notMatched
        }
    }

    public var didMatch: Bool? {
        guard state == .evaluated else { return nil }
        return filterTestTruth(from: value)
    }

    fileprivate init(
        kind: FilterTestKind,
        state: FilterTestResultState,
        value: FilterTestResultValue?,
        matchedRuleIndices: [Int] = [],
        matchRanges: [FilterTestMatchRange] = [],
        diagnostics: [FilterTestDiagnostic] = []
    ) {
        self.kind = kind
        self.state = state
        self.value = value
        self.matchedRuleIndices = matchedRuleIndices
        self.matchRanges = matchRanges
        self.diagnostics = diagnostics
    }

    public var description: String {
        "FilterTestCaseResult(kind:\(kind.rawValue), state:\(state.rawValue), outcome:\(outcome.rawValue), value:<redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": kind.rawValue,
                "state": state.rawValue,
                "outcome": outcome.rawValue,
                "matchedRuleCount": matchedRuleIndices.count,
                "rangeCount": matchRanges.count,
                "diagnosticCount": diagnostics.count,
                "value": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct FilterTestEvaluation:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let outcome: FilterTestOutcome
    public let results: [FilterTestCaseResult]
    public let work: Int

    public var diagnostics: [FilterTestDiagnostic] { results.flatMap(\.diagnostics) }

    public init(outcome: FilterTestOutcome, results: [FilterTestCaseResult], work: Int) {
        self.outcome = outcome
        self.results = results
        self.work = work
    }

    public var description: String {
        "FilterTestEvaluation(outcome:\(outcome.rawValue), results:\(results.count), work:\(work), values:<redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "outcome": outcome.rawValue,
                "resultCount": results.count,
                "diagnosticCount": diagnostics.count,
                "work": work,
                "results": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Bounded, UI-independent evaluation of persisted filter definitions against caller input.
/// Regex work is delegated to `FilenameFilter`, `DisplayFilter`, or CXDiff's bounded PCRE2 paths.
public enum FilterTestEvaluator: Sendable {
    public static func evaluate(
        _ test: FilterTestCase,
        limits: FilterTestLimits = .default
    ) throws -> FilterTestCaseResult {
        let evaluation = try evaluate(.test(test), limits: limits)
        guard let result = evaluation.results.first else {
            preconditionFailure("A single filter test must produce one result")
        }
        return result
    }

    public static func evaluate(
        _ tests: [FilterTestCase],
        composition: FilterTestComposition = .all,
        limits: FilterTestLimits = .default
    ) throws -> FilterTestEvaluation {
        try Task.checkCancellation()
        guard tests.count <= limits.maximumCollectionCount else {
            throw FilterTestError.collectionLimitExceeded(maximum: limits.maximumCollectionCount)
        }
        guard tests.count <= limits.maximumCaseCount else {
            throw FilterTestError.caseLimitExceeded(maximum: limits.maximumCaseCount)
        }
        guard tests.count <= limits.maximumResults else {
            throw FilterTestError.resultLimitExceeded(maximumResults: limits.maximumResults)
        }
        let conditions = tests.map(FilterTestCondition.test)
        return try evaluate(
            composition == .all ? .all(conditions) : .any(conditions),
            limits: limits
        )
    }

    public static func evaluate(
        _ condition: FilterTestCondition,
        limits: FilterTestLimits = .default
    ) throws -> FilterTestEvaluation {
        try Task.checkCancellation()
        var context = FilterTestContext(limits: limits)
        try context.preflight(condition, depth: 1)
        let outcome = try context.evaluate(condition)
        try Task.checkCancellation()
        return FilterTestEvaluation(outcome: outcome, results: context.results, work: context.work.completed)
    }
}

private struct FilterTestContext {
    let limits: FilterTestLimits
    var work: FilterTestWorkBudget
    var results: [FilterTestCaseResult] = []
    private var caseCount = 0
    private var totalPatternBytes = 0
    private var totalInputBytes = 0
    private var retainedResultCount = 0

    init(limits: FilterTestLimits) {
        self.limits = limits
        work = FilterTestWorkBudget(maximum: limits.maximumWork)
        results.reserveCapacity(min(limits.maximumCaseCount, 64))
    }

    mutating func preflight(_ condition: FilterTestCondition, depth: Int) throws {
        try Task.checkCancellation()
        guard depth <= limits.maximumConditionDepth else {
            throw FilterTestError.conditionDepthExceeded(maximum: limits.maximumConditionDepth)
        }
        try work.consume()
        switch condition {
        case .test(let test):
            guard caseCount < limits.maximumCaseCount else {
                throw FilterTestError.caseLimitExceeded(maximum: limits.maximumCaseCount)
            }
            caseCount += 1
            guard caseCount <= limits.maximumResults else {
                throw FilterTestError.resultLimitExceeded(maximumResults: limits.maximumResults)
            }
            try preflight(test)
        case .all(let conditions), .any(let conditions):
            try validateCollection(conditions.count)
            for condition in conditions {
                try preflight(condition, depth: depth + 1)
            }
        case .not(let condition):
            try preflight(condition, depth: depth + 1)
        }
    }

    mutating func evaluate(_ condition: FilterTestCondition) throws -> FilterTestOutcome {
        try Task.checkCancellation()
        try work.consume()
        switch condition {
        case .test(let test):
            let result = try evaluate(test)
            try retain(result)
            results.append(result)
            return result.outcome
        case .all(let conditions):
            var outcomes: [FilterTestOutcome] = []
            outcomes.reserveCapacity(conditions.count)
            for condition in conditions { outcomes.append(try evaluate(condition)) }
            return filterTestCompose(outcomes, using: .all)
        case .any(let conditions):
            var outcomes: [FilterTestOutcome] = []
            outcomes.reserveCapacity(conditions.count)
            for condition in conditions { outcomes.append(try evaluate(condition)) }
            return filterTestCompose(outcomes, using: .any)
        case .not(let condition):
            switch try evaluate(condition) {
            case .matched: return .notMatched
            case .notMatched: return .matched
            case .noOp: return .noOp
            case .invalid: return .invalid
            case .failed: return .failed
            }
        }
    }

    private mutating func preflight(_ test: FilterTestCase) throws {
        switch test {
        case .filename(let test):
            try validateCollection(test.rules.count)
            for (index, rule) in test.rules.enumerated() {
                try addPattern(rule.pattern.source, kind: .filename, ruleIndex: index)
            }
            try addInput(test.relativePath, kind: .filename)
        case .display(let test):
            try addPattern(test.filter.expression.text, kind: .display, ruleIndex: nil)
            if let text = test.input.row.left?.text { try addInput(text, kind: .display) }
            if let text = test.input.row.right?.text { try addInput(text, kind: .display) }
        case .line(let test):
            try validateCollection(test.rules.count)
            for (index, rule) in test.rules.enumerated() {
                try addPattern(rule.pattern, kind: .line, ruleIndex: index)
            }
            try addInput(test.input, kind: .line)
        case .substitution(let test):
            try validateCollection(test.rules.count)
            for (index, rule) in test.rules.enumerated() {
                try addPattern(rule.pattern, kind: .substitution, ruleIndex: index)
                let replacementBytes = rule.replacement.utf8.count
                guard replacementBytes <= limits.maximumReplacementUTF8Bytes else {
                    throw FilterTestError.replacementTooLarge(
                        ruleIndex: index,
                        maximumUTF8Bytes: limits.maximumReplacementUTF8Bytes
                    )
                }
                try addTotalPatternBytes(replacementBytes)
                try work.consume(replacementBytes)
            }
            try addInput(test.input, kind: .substitution)
        }
    }

    private mutating func evaluate(_ test: FilterTestCase) throws -> FilterTestCaseResult {
        switch test {
        case .filename(let test): try evaluateFilename(test)
        case .display(let test): try evaluateDisplay(test)
        case .line(let test): try evaluateLine(test)
        case .substitution(let test): try evaluateSubstitution(test)
        }
    }

    private mutating func evaluateFilename(
        _ test: FilenameFilterTestCase
    ) throws -> FilterTestCaseResult {
        let kind = FilterTestKind.filename
        guard test.enabled else {
            return noOpResult(kind: kind, value: .filename(decision: .include), code: .disabled)
        }
        if test.rules.isEmpty, test.defaultDecision == .include {
            do {
                try FilenameFilter.validateCanonicalRelativePath(test.relativePath)
                guard
                    test.relativePath.utf8.count
                        <= test.filenameLimits.maximumRelativePathUTF8Bytes
                else {
                    throw FilenameFilterError.relativePathTooLarge(
                        maximumUTF8Bytes: test.filenameLimits.maximumRelativePathUTF8Bytes
                    )
                }
            } catch let error as FilenameFilterError {
                return FilterTestCaseResult(
                    kind: kind,
                    state: filterTestFilenameErrorState(error),
                    value: nil,
                    diagnostics: [filterTestFilenameEvaluationDiagnostic(error)]
                )
            }
            return noOpResult(kind: kind, value: .filename(decision: .include), code: .noRules)
        }

        try work.consume(test.relativePath.utf8.count + test.rules.count)
        let matchWork = min(test.filenameLimits.maximumMatchWork, work.remaining)
        do {
            let filter = try FilenameFilter(
                rules: test.rules,
                defaultDecision: test.defaultDecision,
                matchSemantics: test.matchSemantics,
                casePolicy: test.casePolicy,
                limits: filterTestFilenameLimits(test.filenameLimits, workLimit: matchWork)
            )
            var diagnostics = filter.diagnostics.map(filterTestFilenameDiagnostic)
            let evaluation: FilenameFilterEvaluation
            do {
                evaluation = try filter.evaluate(relativePath: test.relativePath, kind: test.entryKind)
                try work.consume(evaluation.work)
            } catch let error as FilenameFilterError {
                if case .matchWorkExceeded(let maximum) = error {
                    try work.consume(maximum)
                }
                let diagnostic = filterTestFilenameEvaluationDiagnostic(error)
                diagnostics.append(diagnostic)
                return FilterTestCaseResult(
                    kind: kind,
                    state: filterTestFilenameErrorState(error),
                    value: nil,
                    diagnostics: diagnostics
                )
            }
            return FilterTestCaseResult(
                kind: kind,
                state: .evaluated,
                value: .filename(decision: evaluation.decision),
                matchedRuleIndices: evaluation.matchedRuleIndex.map { [$0] } ?? [],
                diagnostics: diagnostics
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FilterTestError {
            throw error
        } catch {
            return FilterTestCaseResult(
                kind: kind,
                state: .failed,
                value: nil,
                diagnostics: [FilterTestDiagnostic(kind: kind, code: .engineFailure)]
            )
        }
    }

    private mutating func evaluateDisplay(
        _ test: DisplayFilterTestCase
    ) throws -> FilterTestCaseResult {
        let kind = FilterTestKind.display
        guard test.enabled else {
            return noOpResult(kind: kind, value: .display(isVisible: true), code: .disabled)
        }
        guard test.displayLimits.maximumRows >= 1 else {
            return filterTestDisplayFailure(.tooManyRows(maximumRows: 0))
        }
        if test.filter.expression.text.isEmpty,
            test.filter.predicate == .any,
            !test.filter.invert
        {
            return noOpResult(kind: kind, value: .display(isVisible: true), code: .noRules)
        }

        let leftText = test.input.row.left?.text
        let rightText = test.input.row.right?.text
        try work.consume((leftText?.utf8.count ?? 0) + (rightText?.utf8.count ?? 0) + 1)
        do {
            let displayLimits: DisplayFilterLimits
            if test.filter.expression.isRegularExpression,
                !test.filter.expression.text.isEmpty
            {
                let progressWork = min(
                    test.displayLimits.maximumRegularExpressionProgressSteps,
                    work.remaining
                )
                guard progressWork > 0 else {
                    throw FilterTestError.workLimitExceeded(maximumWork: limits.maximumWork)
                }
                try work.consume(progressWork)
                displayLimits = filterTestDisplayLimits(
                    test.displayLimits,
                    maximumRegularExpressionProgressSteps: progressWork
                )
            } else {
                displayLimits = test.displayLimits
            }
            let filtered = try test.filter.apply(
                to: [test.input.row],
                movedLines: test.input.movedLines,
                limits: displayLimits
            )
            let visible = filtered.sourceRowIndices == [0]
            let ranges = filterTestDisplayRanges(
                filter: test.filter,
                left: leftText,
                right: rightText,
                visible: visible
            )
            return FilterTestCaseResult(
                kind: kind,
                state: .evaluated,
                value: .display(isVisible: visible),
                matchRanges: ranges
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FilterTestError {
            throw error
        } catch let error as DisplayFilterError {
            return filterTestDisplayFailure(error)
        } catch {
            return FilterTestCaseResult(
                kind: kind,
                state: .failed,
                value: nil,
                diagnostics: [FilterTestDiagnostic(kind: kind, code: .engineFailure)]
            )
        }
    }

    private mutating func evaluateLine(_ test: LineFilterTestCase) throws -> FilterTestCaseResult {
        let kind = FilterTestKind.line
        guard test.enabled else {
            return noOpResult(kind: kind, value: .line(isFiltered: false), code: .disabled)
        }
        guard !test.rules.isEmpty else {
            return noOpResult(kind: kind, value: .line(isFiltered: false), code: .noRules)
        }

        let inputBytes = Array(test.input.utf8)
        try work.consume(inputBytes.count)
        guard !(try filterTestContainsLineTerminator(inputBytes)) else {
            return FilterTestCaseResult(
                kind: kind,
                state: .invalid,
                value: nil,
                diagnostics: [FilterTestDiagnostic(kind: kind, code: .invalidInput)]
            )
        }
        var activeRuleIndex: Int?
        do {
            var matchers: [(index: Int, value: FilterTestNativeLineMatcher)] = []
            matchers.reserveCapacity(test.rules.count)
            for (index, rule) in test.rules.enumerated() {
                activeRuleIndex = index
                try Task.checkCancellation()
                try work.consume(rule.pattern.utf8.count)
                matchers.append(
                    (
                        index,
                        try FilterTestNativeLineMatcher(
                            pattern: Array(rule.pattern.utf8),
                            caseSensitive: rule.caseSensitive
                        )
                    )
                )
            }
            for matcher in matchers {
                activeRuleIndex = matcher.index
                try work.consume(inputBytes.count + filterTestNativeRegexWork)
                if try matcher.value.matches(inputBytes) {
                    return FilterTestCaseResult(
                        kind: kind,
                        state: .evaluated,
                        value: .line(isFiltered: true),
                        matchedRuleIndices: [matcher.index],
                        matchRanges: [filterTestWholeRange(.input, text: test.input)]
                    )
                }
            }
            return FilterTestCaseResult(
                kind: kind,
                state: .evaluated,
                value: .line(isFiltered: false)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FilterTestError {
            throw error
        } catch let error as FilterTestNativeRegexError {
            return filterTestNativeFailure(kind: kind, ruleIndex: activeRuleIndex, error: error)
        } catch {
            return FilterTestCaseResult(
                kind: kind,
                state: .failed,
                value: nil,
                diagnostics: [FilterTestDiagnostic(kind: kind, code: .engineFailure)]
            )
        }
    }

    private mutating func evaluateSubstitution(
        _ test: SubstitutionFilterTestCase
    ) throws -> FilterTestCaseResult {
        let kind = FilterTestKind.substitution
        let inputBytes = Array(test.input.utf8)
        guard inputBytes.count <= limits.maximumOutputUTF8Bytes else {
            throw FilterTestError.outputTooLarge(maximumUTF8Bytes: limits.maximumOutputUTF8Bytes)
        }
        guard test.enabled else {
            return noOpResult(
                kind: kind,
                value: .substitution(output: FilterTestOutput(bytes: inputBytes), didMatch: false),
                code: .disabled
            )
        }

        let effectiveRules = test.rules.enumerated().filter { !$0.element.pattern.isEmpty }
        guard !effectiveRules.isEmpty else {
            let diagnostics = test.rules.indices.map {
                FilterTestDiagnostic(kind: kind, code: .emptyPatternIgnored, ruleIndex: $0)
            }
            return FilterTestCaseResult(
                kind: kind,
                state: .noOp,
                value: .substitution(output: FilterTestOutput(bytes: inputBytes), didMatch: false),
                diagnostics: diagnostics.isEmpty
                    ? [FilterTestDiagnostic(kind: kind, code: .noRules)]
                    : diagnostics
            )
        }

        try work.consume(inputBytes.count)
        let inputRecordCount = try filterTestByteRecordCount(inputBytes)
        var activeRuleIndex: Int?
        do {
            var prepared: [(index: Int, pattern: [UInt8], replacement: [UInt8], caseSensitive: Bool)] = []
            prepared.reserveCapacity(effectiveRules.count)
            for (index, rule) in effectiveRules {
                activeRuleIndex = index
                try Task.checkCancellation()
                let pattern = Array(rule.pattern.utf8)
                let replacement = try filterTestReplacementBytes(rule.replacement)
                try work.consume(pattern.count + replacement.count)
                try work.consumeNativeRegex(subjectUTF8Bytes: 0, passes: 1)
                _ = try filterTestSubstitute(
                    source: [],
                    pattern: pattern,
                    replacement: [],
                    caseSensitive: rule.caseSensitive,
                    maximumBytes: limits.maximumOutputUTF8Bytes
                )
                prepared.append((index, pattern, replacement, rule.caseSensitive))
            }

            var current = inputBytes
            var matchedRuleIndices: [Int] = []
            for rule in prepared {
                activeRuleIndex = rule.index
                try Task.checkCancellation()
                try work.consume(
                    current.count
                        + rule.pattern.count
                        + rule.replacement.count
                        + 1
                )
                try work.consumeNativeRegex(subjectUTF8Bytes: current.count, passes: 1)
                let substitution = try filterTestSubstitute(
                    source: current,
                    pattern: rule.pattern,
                    replacement: rule.replacement,
                    caseSensitive: rule.caseSensitive,
                    maximumBytes: limits.maximumOutputUTF8Bytes
                )
                current = substitution.output
                if substitution.didMatch { matchedRuleIndices.append(rule.index) }
            }
            try work.consume(current.count)
            var outputRecordCount = try filterTestByteRecordCount(current)
            if try filterTestNeedsTrailingEmptyRecord(
                input: inputBytes,
                output: current,
                inputRecordCount: inputRecordCount,
                outputRecordCount: outputRecordCount
            ) {
                outputRecordCount += 1
            }
            guard outputRecordCount == inputRecordCount else {
                return FilterTestCaseResult(
                    kind: kind,
                    state: .failed,
                    value: nil,
                    diagnostics: [FilterTestDiagnostic(kind: kind, code: .changedLineStructure)]
                )
            }
            guard current.count <= limits.maximumOutputUTF8Bytes else {
                throw FilterTestError.outputTooLarge(
                    maximumUTF8Bytes: limits.maximumOutputUTF8Bytes
                )
            }

            let output = FilterTestOutput(bytes: current)
            var diagnostics: [FilterTestDiagnostic] = []
            for index in test.rules.indices where test.rules[index].pattern.isEmpty {
                diagnostics.append(
                    FilterTestDiagnostic(kind: kind, code: .emptyPatternIgnored, ruleIndex: index)
                )
            }
            if !output.isValidUTF8 {
                diagnostics.append(FilterTestDiagnostic(kind: kind, code: .outputIsNotValidUTF8))
            }
            let didMatch = !matchedRuleIndices.isEmpty
            var ranges: [FilterTestMatchRange] = []
            if didMatch {
                ranges.append(filterTestWholeRange(.input, text: test.input))
                if let outputText = output.string {
                    ranges.append(filterTestWholeRange(.output, text: outputText))
                }
            }
            return FilterTestCaseResult(
                kind: kind,
                state: .evaluated,
                value: .substitution(output: output, didMatch: didMatch),
                matchedRuleIndices: matchedRuleIndices,
                matchRanges: ranges,
                diagnostics: diagnostics
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FilterTestError {
            throw error
        } catch let error as FilterTestNativeRegexError {
            return filterTestNativeFailure(kind: kind, ruleIndex: activeRuleIndex, error: error)
        } catch {
            return FilterTestCaseResult(
                kind: kind,
                state: .failed,
                value: nil,
                diagnostics: [FilterTestDiagnostic(kind: kind, code: .engineFailure)]
            )
        }
    }

    private mutating func addPattern(
        _ pattern: String,
        kind: FilterTestKind,
        ruleIndex: Int?
    ) throws {
        let byteCount = pattern.utf8.count
        let maximumPatternUTF8Bytes =
            switch kind {
            case .line, .substitution:
                min(limits.maximumPatternUTF8Bytes, filterTestMaximumNativePatternUTF8Bytes)
            case .filename, .display:
                limits.maximumPatternUTF8Bytes
            }
        guard byteCount <= maximumPatternUTF8Bytes else {
            throw FilterTestError.patternTooLarge(
                kind: kind,
                ruleIndex: ruleIndex,
                maximumUTF8Bytes: maximumPatternUTF8Bytes
            )
        }
        try addTotalPatternBytes(byteCount)
        try work.consume(byteCount)
    }

    private mutating func addTotalPatternBytes(_ byteCount: Int) throws {
        let (next, overflow) = totalPatternBytes.addingReportingOverflow(byteCount)
        guard !overflow, next <= limits.maximumTotalPatternUTF8Bytes else {
            throw FilterTestError.totalPatternSizeExceeded(
                maximumUTF8Bytes: limits.maximumTotalPatternUTF8Bytes
            )
        }
        totalPatternBytes = next
    }

    private mutating func addInput(_ input: String, kind: FilterTestKind) throws {
        let byteCount = input.utf8.count
        guard byteCount <= limits.maximumInputUTF8Bytes else {
            throw FilterTestError.inputTooLarge(
                kind: kind,
                maximumUTF8Bytes: limits.maximumInputUTF8Bytes
            )
        }
        let (next, overflow) = totalInputBytes.addingReportingOverflow(byteCount)
        guard !overflow, next <= limits.maximumTotalInputUTF8Bytes else {
            throw FilterTestError.totalInputSizeExceeded(
                maximumUTF8Bytes: limits.maximumTotalInputUTF8Bytes
            )
        }
        totalInputBytes = next
        try work.consume(byteCount)
    }

    private func validateCollection(_ count: Int) throws {
        guard count <= limits.maximumCollectionCount else {
            throw FilterTestError.collectionLimitExceeded(maximum: limits.maximumCollectionCount)
        }
    }

    private mutating func retain(_ result: FilterTestCaseResult) throws {
        let additions =
            1
            + result.matchedRuleIndices.count
            + result.matchRanges.count
            + result.diagnostics.count
        let (next, overflow) = retainedResultCount.addingReportingOverflow(additions)
        guard !overflow, next <= limits.maximumResults else {
            throw FilterTestError.resultLimitExceeded(maximumResults: limits.maximumResults)
        }
        retainedResultCount = next
        try work.consume(additions)
    }

    private func noOpResult(
        kind: FilterTestKind,
        value: FilterTestResultValue,
        code: FilterTestDiagnosticCode
    ) -> FilterTestCaseResult {
        FilterTestCaseResult(
            kind: kind,
            state: .noOp,
            value: value,
            diagnostics: [FilterTestDiagnostic(kind: kind, code: code)]
        )
    }
}

private struct FilterTestWorkBudget {
    let maximum: Int
    private(set) var completed = 0

    var remaining: Int { maximum - completed }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            throw FilterTestError.workLimitExceeded(maximumWork: maximum)
        }
        let (next, overflow) = completed.addingReportingOverflow(amount)
        guard !overflow, next <= maximum else {
            throw FilterTestError.workLimitExceeded(maximumWork: maximum)
        }
        completed = next
        try Task.checkCancellation()
    }

    mutating func consumeNativeRegex(subjectUTF8Bytes: Int, passes: Int) throws {
        guard subjectUTF8Bytes >= 0, passes >= 0 else {
            throw FilterTestError.workLimitExceeded(maximumWork: maximum)
        }
        let (matchCount, countOverflow) =
            subjectUTF8Bytes == 0
            ? (0, false)
            : subjectUTF8Bytes.addingReportingOverflow(1)
        let (scaled, scaleOverflow) = matchCount.multipliedReportingOverflow(
            by: filterTestNativeRegexWork
        )
        let (total, passOverflow) = scaled.multipliedReportingOverflow(by: passes)
        guard !countOverflow, !scaleOverflow, !passOverflow else {
            throw FilterTestError.workLimitExceeded(maximumWork: maximum)
        }
        try consume(total)
    }
}

private enum FilterTestNativeRegexError: Error {
    case invalidPattern
    case evaluationLimit
    case allocationFailure
    case outputLimit
    case engineFailure(Int32)
}

// CXDiff configures this match-step cap but exposes no progress or cancellation callback.
// Reserve every possible native match before entry and keep compilation bounded by pattern size.
private let filterTestNativeRegexWork = 1_000_000
private let filterTestMaximumNativePatternUTF8Bytes = 4_096
private final class FilterTestNativeLineMatcher {
    private let handle: UnsafeMutableRawPointer

    init(pattern: [UInt8], caseSensitive: Bool) throws {
        try Task.checkCancellation()
        var nativeFilter: UnsafeMutableRawPointer?
        let status = pattern.withUnsafeBytes { buffer in
            mmx_line_filter_create(
                buffer.baseAddress,
                buffer.count,
                caseSensitive ? 1 : 0,
                &nativeFilter
            )
        }
        guard status == 0, let nativeFilter else {
            throw filterTestNativeError(status)
        }
        if Task.isCancelled {
            mmx_line_filter_free(nativeFilter)
            throw CancellationError()
        }
        handle = nativeFilter
    }

    deinit {
        mmx_line_filter_free(handle)
    }

    func matches(_ input: [UInt8]) throws -> Bool {
        try Task.checkCancellation()
        var matched: Int32 = 0
        let status = input.withUnsafeBytes { buffer in
            mmx_line_filter_matches(handle, buffer.baseAddress, buffer.count, &matched)
        }
        guard status == 0 else { throw filterTestNativeError(status) }
        try Task.checkCancellation()
        return matched != 0
    }
}

private func filterTestSubstitute(
    source: [UInt8],
    pattern: [UInt8],
    replacement: [UInt8],
    caseSensitive: Bool,
    maximumBytes: Int
) throws -> (output: [UInt8], didMatch: Bool) {
    try Task.checkCancellation()
    var result = mmx_bytes_result(bytes: nil, size: -1)
    let status = source.withUnsafeBytes { sourceBuffer in
        pattern.withUnsafeBytes { patternBuffer in
            replacement.withUnsafeBytes { replacementBuffer in
                mmx_regex_substitute(
                    sourceBuffer.baseAddress,
                    sourceBuffer.count,
                    patternBuffer.baseAddress,
                    patternBuffer.count,
                    replacementBuffer.baseAddress,
                    replacementBuffer.count,
                    caseSensitive ? 1 : 0,
                    maximumBytes,
                    &result
                )
            }
        }
    }
    defer { mmx_bytes_result_free(&result) }
    try Task.checkCancellation()
    guard status == 0 else { throw filterTestNativeError(status) }
    let didMatch = result.size < 0
    let outputSize = result.size & Int.max
    guard outputSize == 0 || result.bytes != nil else {
        throw FilterTestNativeRegexError.allocationFailure
    }
    let output = Array(UnsafeBufferPointer(start: result.bytes, count: outputSize))
    try Task.checkCancellation()
    return (output, didMatch)
}

private func filterTestNativeError(_ status: Int32) -> FilterTestNativeRegexError {
    switch status {
    case 1: .invalidPattern
    case 2: .evaluationLimit
    case 3: .allocationFailure
    case 4: .outputLimit
    default: .engineFailure(status)
    }
}

private func filterTestNativeFailure(
    kind: FilterTestKind,
    ruleIndex: Int?,
    error: FilterTestNativeRegexError
) -> FilterTestCaseResult {
    let diagnostic: FilterTestDiagnostic
    let state: FilterTestResultState
    switch error {
    case .invalidPattern:
        state = .invalid
        diagnostic = FilterTestDiagnostic(kind: kind, code: .invalidPattern, ruleIndex: ruleIndex)
    case .evaluationLimit:
        state = .failed
        diagnostic = FilterTestDiagnostic(
            kind: kind,
            code: .evaluationLimitExceeded,
            ruleIndex: ruleIndex
        )
    case .allocationFailure:
        state = .failed
        diagnostic = FilterTestDiagnostic(
            kind: kind,
            code: .engineFailure,
            ruleIndex: ruleIndex,
            engineCode: 3
        )
    case .outputLimit:
        state = .failed
        diagnostic = FilterTestDiagnostic(
            kind: kind,
            code: .outputLimitExceeded,
            ruleIndex: ruleIndex
        )
    case .engineFailure(let code):
        state = .failed
        diagnostic = FilterTestDiagnostic(
            kind: kind,
            code: .engineFailure,
            ruleIndex: ruleIndex,
            engineCode: code
        )
    }
    return FilterTestCaseResult(kind: kind, state: state, value: nil, diagnostics: [diagnostic])
}

private func filterTestDisplayFailure(_ error: DisplayFilterError) -> FilterTestCaseResult {
    let kind = FilterTestKind.display
    let state: FilterTestResultState
    let code: FilterTestDiagnosticCode
    let limit: Int?
    switch error {
    case .invalidRegularExpression:
        state = .invalid
        code = .invalidPattern
        limit = nil
    case .expressionTooLarge(let maximum):
        state = .invalid
        code = .patternLimitExceeded
        limit = maximum
    case .movedLineMetadataUnavailable:
        state = .invalid
        code = .invalidInput
        limit = nil
    case .tooManyRows(let maximum):
        state = .failed
        code = .collectionLimitExceeded
        limit = maximum
    case .lineTooLong(let maximum), .inputTooLarge(let maximum):
        state = .failed
        code = .inputLimitExceeded
        limit = maximum
    case .tooManyTextEvaluations(let maximum):
        state = .failed
        code = .evaluationLimitExceeded
        limit = maximum
    case .regularExpressionEvaluationLimitExceeded(let maximum):
        state = .failed
        code = .evaluationLimitExceeded
        limit = maximum
    case .regularExpressionEvaluationFailed:
        state = .failed
        code = .engineFailure
        limit = nil
    case .encodedDataTooLarge(let maximum):
        state = .failed
        code = .inputLimitExceeded
        limit = maximum
    case .unsupportedSchemaVersion, .invalidHistoryCapacity, .tooManyHistoryEntries,
        .duplicateHistoryEntry:
        state = .failed
        code = .engineFailure
        limit = nil
    }
    return FilterTestCaseResult(
        kind: kind,
        state: state,
        value: nil,
        diagnostics: [FilterTestDiagnostic(kind: kind, code: code, limit: limit)]
    )
}

private func filterTestFilenameDiagnostic(
    _ diagnostic: FilenameFilterDiagnostic
) -> FilterTestDiagnostic {
    let code: FilterTestDiagnosticCode
    let offset: Int?
    let limit: Int?
    switch diagnostic.reason {
    case .ruleCountExceeded(let maximum):
        code = .collectionLimitExceeded
        offset = nil
        limit = maximum
    case .emptyPattern:
        code = .invalidPattern
        offset = nil
        limit = nil
    case .patternContainsNull:
        code = .patternContainsNull
        offset = nil
        limit = nil
    case .patternTooLarge(let maximum):
        code = .patternLimitExceeded
        offset = nil
        limit = maximum
    case .totalPatternSizeExceeded(let maximum):
        code = .totalPatternLimitExceeded
        offset = nil
        limit = maximum
    case .invalidGlob(let scalarOffset, _), .invalidRegularExpression(let scalarOffset, _):
        code = .invalidPattern
        offset = scalarOffset
        limit = nil
    case .unsupportedRegularExpression(let scalarOffset, _):
        code = .unsupportedPattern
        offset = scalarOffset
        limit = nil
    case .compiledStateCountExceeded(let maximum):
        code = .compiledPatternLimitExceeded
        offset = nil
        limit = maximum
    }
    return FilterTestDiagnostic(
        kind: .filename,
        code: code,
        ruleIndex: diagnostic.ruleIndex,
        unicodeScalarOffset: offset,
        limit: limit
    )
}

private func filterTestFilenameEvaluationDiagnostic(
    _ error: FilenameFilterError
) -> FilterTestDiagnostic {
    switch error {
    case .invalidRelativePath:
        FilterTestDiagnostic(kind: .filename, code: .invalidInput)
    case .relativePathTooLarge(let maximum):
        FilterTestDiagnostic(kind: .filename, code: .inputLimitExceeded, limit: maximum)
    case .matchWorkExceeded(let maximum):
        FilterTestDiagnostic(kind: .filename, code: .evaluationLimitExceeded, limit: maximum)
    }
}

private func filterTestFilenameErrorState(_ error: FilenameFilterError) -> FilterTestResultState {
    switch error {
    case .invalidRelativePath, .relativePathTooLarge: .invalid
    case .matchWorkExceeded: .failed
    }
}

private func filterTestFilenameLimits(
    _ limits: FilenameFilterLimits,
    workLimit: Int
) -> FilenameFilterLimits {
    FilenameFilterLimits(
        maximumRuleCount: limits.maximumRuleCount,
        maximumPatternUTF8Bytes: limits.maximumPatternUTF8Bytes,
        maximumTotalPatternUTF8Bytes: limits.maximumTotalPatternUTF8Bytes,
        maximumRelativePathUTF8Bytes: limits.maximumRelativePathUTF8Bytes,
        maximumCompiledStateCount: limits.maximumCompiledStateCount,
        maximumMatchWork: min(limits.maximumMatchWork, workLimit),
        maximumRegularExpressionNestingDepth: limits.maximumRegularExpressionNestingDepth,
        maximumRegularExpressionRepetition: limits.maximumRegularExpressionRepetition
    )
}

private func filterTestDisplayLimits(
    _ limits: DisplayFilterLimits,
    maximumRegularExpressionProgressSteps: Int
) -> DisplayFilterLimits {
    DisplayFilterLimits(
        maximumRows: limits.maximumRows,
        maximumExpressionUTF16Length: limits.maximumExpressionUTF16Length,
        maximumLineUTF16Length: limits.maximumLineUTF16Length,
        maximumTotalTextUTF16Length: limits.maximumTotalTextUTF16Length,
        maximumTextEvaluations: limits.maximumTextEvaluations,
        maximumRegularExpressionProgressSteps: maximumRegularExpressionProgressSteps
    )
}

private func filterTestDisplayRanges(
    filter: DisplayFilter,
    left: String?,
    right: String?,
    visible: Bool
) -> [FilterTestMatchRange] {
    guard visible,
        !filter.invert,
        filter.predicate == .any,
        case .literal(let pattern) = filter.expression,
        !pattern.isEmpty
    else { return [] }

    var ranges: [FilterTestMatchRange] = []
    if let left,
        let range = filterTestLiteralRange(
            pattern,
            in: left,
            caseSensitive: filter.caseSensitive
        )
    {
        ranges.append(FilterTestMatchRange(field: .leftInput, utf16Range: range))
        return ranges
    } else if let right,
        let range = filterTestLiteralRange(
            pattern,
            in: right,
            caseSensitive: filter.caseSensitive
        )
    {
        ranges.append(FilterTestMatchRange(field: .rightInput, utf16Range: range))
    }
    return ranges
}

private func filterTestLiteralRange(
    _ pattern: String,
    in text: String,
    caseSensitive: Bool
) -> NSRange? {
    let source = text as NSString
    let range = source.range(
        of: pattern,
        options: caseSensitive ? [] : [.caseInsensitive],
        range: NSRange(location: 0, length: source.length)
    )
    guard range.location != NSNotFound else { return nil }
    let end = range.location + range.length
    let startRange = source.rangeOfComposedCharacterSequence(at: range.location)
    let lowerBound = startRange.location
    let upperBound: Int
    if end == 0 {
        upperBound = 0
    } else if end == source.length {
        upperBound = source.length
    } else {
        let endRange = source.rangeOfComposedCharacterSequence(at: end - 1)
        upperBound = endRange.location + endRange.length
    }
    return NSRange(location: lowerBound, length: upperBound - lowerBound)
}

private func filterTestWholeRange(
    _ field: FilterTestRangeField,
    text: String
) -> FilterTestMatchRange {
    FilterTestMatchRange(
        field: field,
        utf16Range: NSRange(location: 0, length: text.utf16.count)
    )
}

private func filterTestContainsLineTerminator(_ bytes: [UInt8]) throws -> Bool {
    for (index, byte) in bytes.enumerated() {
        if index.isMultiple(of: 64 * 1_024) { try Task.checkCancellation() }
        if byte == 10 || byte == 13 { return true }
    }
    try Task.checkCancellation()
    return false
}

private func filterTestByteRecordCount(_ bytes: [UInt8]) throws -> Int {
    var recordCount = 0
    var recordStart = 0
    var index = 0
    while index < bytes.count {
        if index.isMultiple(of: 64 * 1_024) { try Task.checkCancellation() }
        if bytes[index] == 13 {
            recordCount += 1
            index += index + 1 < bytes.count && bytes[index + 1] == 10 ? 2 : 1
            recordStart = index
        } else if bytes[index] == 10 {
            recordCount += 1
            index += 1
            recordStart = index
        } else {
            index += 1
        }
    }
    if recordStart < bytes.count { recordCount += 1 }
    try Task.checkCancellation()
    return recordCount
}

private func filterTestNeedsTrailingEmptyRecord(
    input: [UInt8],
    output: [UInt8],
    inputRecordCount: Int,
    outputRecordCount: Int
) throws -> Bool {
    try Task.checkCancellation()
    return input.last != 10
        && input.last != 13
        && (output.isEmpty || output.last == 10 || output.last == 13)
        && outputRecordCount == inputRecordCount - 1
}

private func filterTestCompose(
    _ outcomes: [FilterTestOutcome],
    using composition: FilterTestComposition
) -> FilterTestOutcome {
    if outcomes.contains(.failed) { return .failed }
    if outcomes.contains(.invalid) { return .invalid }
    let evaluated = outcomes.filter { $0 != .noOp }
    guard !evaluated.isEmpty else { return .noOp }
    switch composition {
    case .all:
        return evaluated.allSatisfy { $0 == .matched } ? .matched : .notMatched
    case .any:
        return evaluated.contains(.matched) ? .matched : .notMatched
    }
}

private func filterTestTruth(from value: FilterTestResultValue?) -> Bool? {
    switch value {
    case .filename(let decision): decision == .include
    case .display(let visible): visible
    case .line(let filtered): filtered
    case .substitution(_, let didMatch): didMatch
    case nil: nil
    }
}

private func filterTestStringsAreIdentical(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.elementsEqual(rhs.utf8)
}

private func filterTestFilenameRulesEqual(
    _ lhs: [FilenameFilterRule],
    _ rhs: [FilenameFilterRule]
) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { left, right in
        guard left.decision == right.decision,
            left.applicability == right.applicability
        else { return false }
        switch (left.pattern, right.pattern) {
        case (.glob(let left), .glob(let right)),
            (.regularExpression(let left), .regularExpression(let right)):
            return filterTestStringsAreIdentical(left, right)
        default:
            return false
        }
    }
}

private func filterTestDisplayFiltersEqual(_ lhs: DisplayFilter, _ rhs: DisplayFilter) -> Bool {
    guard lhs.caseSensitive == rhs.caseSensitive,
        lhs.invert == rhs.invert,
        lhs.predicate == rhs.predicate
    else { return false }
    switch (lhs.expression, rhs.expression) {
    case (.literal(let left), .literal(let right)),
        (.regularExpression(let left), .regularExpression(let right)):
        return filterTestStringsAreIdentical(left, right)
    default:
        return false
    }
}

private func filterTestLineRulesEqual(_ lhs: [LineFilterRule], _ rhs: [LineFilterRule]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy {
        $0.caseSensitive == $1.caseSensitive
            && filterTestStringsAreIdentical($0.pattern, $1.pattern)
    }
}

private func filterTestSubstitutionRulesEqual(
    _ lhs: [SubstitutionRule],
    _ rhs: [SubstitutionRule]
) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy {
        $0.caseSensitive == $1.caseSensitive
            && filterTestStringsAreIdentical($0.pattern, $1.pattern)
            && filterTestStringsAreIdentical($0.replacement, $1.replacement)
    }
}

private func filterTestDiffLinesEqual(_ lhs: DiffLine?, _ rhs: DiffLine?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case (.some(let left), .some(let right)):
        left.number == right.number && filterTestStringsAreIdentical(left.text, right.text)
    default: false
    }
}

private func filterTestReplacementBytes(_ replacement: String) throws -> [UInt8] {
    enum Part {
        case literal(String)
        case capture(Int)
        case rawByte(UInt8)
    }

    var parts: [Part] = []
    var literal = ""
    var index = replacement.startIndex
    var visited = 0

    func asciiDigit(_ character: Character) -> Int? {
        guard character.unicodeScalars.count == 1,
            let value = character.unicodeScalars.first?.value,
            (0x30...0x39).contains(value)
        else { return nil }
        return Int(value - 0x30)
    }

    func hexByte(_ text: String) -> UInt8? {
        let prefix = text.prefix { $0.isHexDigit }
        guard !prefix.isEmpty else { return nil }
        return UInt8(prefix, radix: 16)
    }

    func bytes(_ part: Part) -> [UInt8] {
        switch part {
        case .literal(let value): Array(value.utf8)
        case .capture(let group): Array("$\(group)".utf8)
        case .rawByte(let byte): [byte]
        }
    }

    func flushLiteral() {
        if !literal.isEmpty {
            parts.append(.literal(literal))
            literal = ""
        }
    }

    while index < replacement.endIndex {
        visited += 1
        if visited.isMultiple(of: 256) { try Task.checkCancellation() }
        let character = replacement[index]
        let next = replacement.index(after: index)
        if character == "\\", next < replacement.endIndex {
            let escaped = replacement[next]
            if let digit = asciiDigit(escaped) {
                flushLiteral()
                parts.append(.capture(digit))
                index = next
            } else if escaped == "x" {
                let firstHexIndex = replacement.index(after: next)
                if firstHexIndex < replacement.endIndex {
                    let secondHexIndex = replacement.index(after: firstHexIndex)
                    if secondHexIndex < replacement.endIndex {
                        let hex = String(replacement[firstHexIndex...secondHexIndex])
                        if let value = hexByte(hex), value > 0x7F {
                            flushLiteral()
                            parts.append(.rawByte(value))
                            index = secondHexIndex
                        } else if let value = hexByte(hex), let scalar = UnicodeScalar(Int(value)) {
                            literal.unicodeScalars.append(scalar)
                            index = secondHexIndex
                        } else {
                            literal += "\\x"
                            index = next
                        }
                    } else {
                        literal += "\\x"
                        index = next
                    }
                } else {
                    literal += "\\x"
                    index = next
                }
            } else {
                switch escaped {
                case "a": literal.append("\u{0007}")
                case "b": literal.append("\u{0008}")
                case "f": literal.append("\u{000C}")
                case "n": literal.append("\n")
                case "r": literal.append("\r")
                case "t": literal.append("\t")
                case "v": literal.append("\u{000B}")
                default: literal.append(escaped)
                }
                index = next
            }
        } else if character == "\\" {
            index = next
            continue
        } else if character == "$", next < replacement.endIndex,
            let digit = asciiDigit(replacement[next])
        {
            flushLiteral()
            parts.append(.capture(digit))
            index = next
        } else {
            literal.append(character)
        }
        index = replacement.index(after: index)
    }
    flushLiteral()
    try Task.checkCancellation()
    return parts.flatMap(bytes)
}
