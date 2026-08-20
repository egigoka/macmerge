import Foundation

public enum FilenameFilterDecision: String, Equatable, Hashable, Sendable {
    case include
    case exclude
}

public enum FilenameFilterPattern: Equatable, Hashable, Sendable {
    /// Matches the entire relative path. `*`, `?`, and character classes do not cross `/`;
    /// `**` does. A `**/` sequence also matches zero directory components.
    case glob(String)
    /// Searches the relative path using the safe regular-expression subset documented by
    /// `FilenameFilterDiagnosticReason.unsupportedRegularExpression`.
    case regularExpression(String)

    public var source: String {
        switch self {
        case .glob(let source), .regularExpression(let source):
            source
        }
    }
}

public enum FilenameFilterRuleApplicability: String, Equatable, Hashable, Sendable {
    case files
    case directories
    case filesAndDirectories
}

public enum FilenameFilterEntryKind: String, Equatable, Hashable, Sendable {
    case file
    case directory
}

public enum FilenameFilterCasePolicy: String, Equatable, Hashable, Sendable {
    case sensitive
    /// Uses locale-independent Unicode case folding after canonical composition.
    case insensitive
}

public enum FilenameFilterMatchSemantics: String, Equatable, Hashable, Sendable {
    /// Evaluation stops at the first applicable matching rule.
    case firstMatchWins
    /// Every applicable rule is evaluated and the final matching rule decides.
    case lastMatchWins
}

public struct FilenameFilterRule: Equatable, Hashable, Sendable {
    public let decision: FilenameFilterDecision
    public let pattern: FilenameFilterPattern
    public let applicability: FilenameFilterRuleApplicability

    public init(
        _ decision: FilenameFilterDecision,
        pattern: FilenameFilterPattern,
        applicability: FilenameFilterRuleApplicability = .filesAndDirectories
    ) {
        self.decision = decision
        self.pattern = pattern
        self.applicability = applicability
    }
}

public struct FilenameFilterLimits: Equatable, Hashable, Sendable {
    public static let `default` = FilenameFilterLimits()

    public let maximumRuleCount: Int
    public let maximumPatternUTF8Bytes: Int
    public let maximumTotalPatternUTF8Bytes: Int
    public let maximumRelativePathUTF8Bytes: Int
    public let maximumCompiledStateCount: Int
    public let maximumMatchWork: Int
    public let maximumRegularExpressionNestingDepth: Int
    public let maximumRegularExpressionRepetition: Int

    public init(
        maximumRuleCount: Int = 1_024,
        maximumPatternUTF8Bytes: Int = 4_096,
        maximumTotalPatternUTF8Bytes: Int = 1_048_576,
        maximumRelativePathUTF8Bytes: Int = 16_384,
        maximumCompiledStateCount: Int = 65_536,
        maximumMatchWork: Int = 1_000_000,
        maximumRegularExpressionNestingDepth: Int = 64,
        maximumRegularExpressionRepetition: Int = 1_024
    ) {
        precondition(maximumRuleCount >= 0)
        precondition(maximumPatternUTF8Bytes >= 0)
        precondition(maximumTotalPatternUTF8Bytes >= 0)
        precondition(maximumRelativePathUTF8Bytes >= 0)
        precondition(maximumCompiledStateCount >= 0)
        precondition(maximumMatchWork >= 0)
        precondition(maximumRegularExpressionNestingDepth >= 0)
        precondition(maximumRegularExpressionRepetition >= 0)
        self.maximumRuleCount = maximumRuleCount
        self.maximumPatternUTF8Bytes = maximumPatternUTF8Bytes
        self.maximumTotalPatternUTF8Bytes = maximumTotalPatternUTF8Bytes
        self.maximumRelativePathUTF8Bytes = maximumRelativePathUTF8Bytes
        self.maximumCompiledStateCount = maximumCompiledStateCount
        self.maximumMatchWork = maximumMatchWork
        self.maximumRegularExpressionNestingDepth = maximumRegularExpressionNestingDepth
        self.maximumRegularExpressionRepetition = maximumRegularExpressionRepetition
    }
}

public enum FilenameFilterDiagnosticReason: Equatable, Hashable, Sendable {
    case ruleCountExceeded(maximum: Int)
    case emptyPattern
    case patternContainsNull
    case patternTooLarge(maximumUTF8Bytes: Int)
    case totalPatternSizeExceeded(maximumUTF8Bytes: Int)
    case invalidGlob(unicodeScalarOffset: Int, message: String)
    /// Supported syntax is literals, `.`, classes, grouping, `|`, `*`, `+`, `?`,
    /// `{m}`, `{m,}`, `{m,n}`, `^`, `$`, `\A`, `\z`, and `\d`, `\w`, `\s`
    /// (plus their uppercase inverses). Captures are accepted but not reported.
    /// Backreferences, lookaround, inline options, boundaries, and Unicode-property
    /// escapes are intentionally unsupported. Matching uses a Thompson NFA and never
    /// recursive backtracking.
    case unsupportedRegularExpression(unicodeScalarOffset: Int, message: String)
    case invalidRegularExpression(unicodeScalarOffset: Int, message: String)
    case compiledStateCountExceeded(maximum: Int)
}

public struct FilenameFilterDiagnostic: Error, LocalizedError, Equatable, Hashable, Sendable {
    /// Nil only for a rule-count diagnostic covering all rules after the configured limit.
    public let ruleIndex: Int?
    public let reason: FilenameFilterDiagnosticReason

    public init(ruleIndex: Int?, reason: FilenameFilterDiagnosticReason) {
        self.ruleIndex = ruleIndex
        self.reason = reason
    }

    public var errorDescription: String? {
        let prefix = ruleIndex.map { "Filename filter rule \($0)" } ?? "Filename filter"
        switch reason {
        case .ruleCountExceeded(let maximum):
            return "\(prefix) has more than \(maximum) rules; remaining rules were ignored."
        case .emptyPattern:
            return "\(prefix) has an empty pattern."
        case .patternContainsNull:
            return "\(prefix) contains a null character."
        case .patternTooLarge(let maximum):
            return "\(prefix) exceeds the \(maximum)-byte pattern limit."
        case .totalPatternSizeExceeded(let maximum):
            return "\(prefix) exceeds the \(maximum)-byte total pattern limit."
        case .invalidGlob(let offset, let message):
            return "\(prefix) has an invalid glob at scalar offset \(offset): \(message)"
        case .unsupportedRegularExpression(let offset, let message):
            return "\(prefix) uses unsupported regex syntax at scalar offset \(offset): \(message)"
        case .invalidRegularExpression(let offset, let message):
            return "\(prefix) has an invalid regex at scalar offset \(offset): \(message)"
        case .compiledStateCountExceeded(let maximum):
            return "\(prefix) exceeds the \(maximum)-state compiled-pattern limit."
        }
    }
}

public enum FilenameFilterRelativePathError: String, Error, Equatable, Hashable, Sendable {
    case empty
    case absolute
    case containsNull
    case emptyComponent
    case currentDirectoryComponent
    case parentTraversal
    case notCanonicallyComposed
}

public enum FilenameFilterError: Error, LocalizedError, Equatable, Sendable {
    case invalidRelativePath(FilenameFilterRelativePathError)
    case relativePathTooLarge(maximumUTF8Bytes: Int)
    case matchWorkExceeded(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let reason):
            return "Filename filter requires a canonical relative path: \(reason.rawValue)."
        case .relativePathTooLarge(let maximum):
            return "Filename filter path exceeds the \(maximum)-byte limit."
        case .matchWorkExceeded(let maximum):
            return "Filename filter exceeded its \(maximum)-step match-work limit."
        }
    }
}

public struct FilenameFilterEvaluation: Equatable, Hashable, Sendable {
    public let decision: FilenameFilterDecision
    /// Original array index of the deciding rule, or nil when the default decided.
    public let matchedRuleIndex: Int?
    public let work: Int

    public init(decision: FilenameFilterDecision, matchedRuleIndex: Int?, work: Int) {
        self.decision = decision
        self.matchedRuleIndex = matchedRuleIndex
        self.work = work
    }

    public var isIncluded: Bool { decision == .include }
}

/// Immutable filename filtering with deterministic rule order and no filesystem access.
/// Invalid rules are skipped and reported in input order through `diagnostics`.
public struct FilenameFilter: Sendable {
    public let rules: [FilenameFilterRule]
    public let defaultDecision: FilenameFilterDecision
    public let matchSemantics: FilenameFilterMatchSemantics
    public let casePolicy: FilenameFilterCasePolicy
    public let limits: FilenameFilterLimits
    public let diagnostics: [FilenameFilterDiagnostic]

    private let compiledRules: [FilenameFilterCompiledRule]

    public init(
        rules: [FilenameFilterRule],
        defaultDecision: FilenameFilterDecision = .include,
        matchSemantics: FilenameFilterMatchSemantics = .lastMatchWins,
        casePolicy: FilenameFilterCasePolicy = .sensitive,
        limits: FilenameFilterLimits = .default
    ) throws {
        var compiledRules: [FilenameFilterCompiledRule] = []
        var diagnostics: [FilenameFilterDiagnostic] = []
        let admittedRuleCount = min(rules.count, limits.maximumRuleCount)
        compiledRules.reserveCapacity(admittedRuleCount)
        diagnostics.reserveCapacity(min(rules.count, 64))

        if rules.count > limits.maximumRuleCount {
            diagnostics.append(
                FilenameFilterDiagnostic(
                    ruleIndex: nil,
                    reason: .ruleCountExceeded(maximum: limits.maximumRuleCount)
                )
            )
        }

        var totalPatternBytes = 0
        var totalCompiledStates = 0
        for index in 0..<admittedRuleCount {
            try Task.checkCancellation()
            let rule = rules[index]
            let source = rule.pattern.source
            guard !source.isEmpty else {
                diagnostics.append(FilenameFilterDiagnostic(ruleIndex: index, reason: .emptyPattern))
                continue
            }
            guard !source.contains("\0") else {
                diagnostics.append(
                    FilenameFilterDiagnostic(ruleIndex: index, reason: .patternContainsNull)
                )
                continue
            }

            let patternBytes = source.utf8.count
            guard patternBytes <= limits.maximumPatternUTF8Bytes else {
                diagnostics.append(
                    FilenameFilterDiagnostic(
                        ruleIndex: index,
                        reason: .patternTooLarge(maximumUTF8Bytes: limits.maximumPatternUTF8Bytes)
                    )
                )
                continue
            }
            let (nextTotalPatternBytes, patternSizeOverflow) =
                totalPatternBytes.addingReportingOverflow(patternBytes)
            guard !patternSizeOverflow,
                nextTotalPatternBytes <= limits.maximumTotalPatternUTF8Bytes
            else {
                diagnostics.append(
                    FilenameFilterDiagnostic(
                        ruleIndex: index,
                        reason: .totalPatternSizeExceeded(
                            maximumUTF8Bytes: limits.maximumTotalPatternUTF8Bytes
                        )
                    )
                )
                continue
            }
            totalPatternBytes = nextTotalPatternBytes

            do {
                let normalizedSource = source.precomposedStringWithCanonicalMapping
                let node: FilenameFilterRegexNode
                let anchored: Bool
                switch rule.pattern {
                case .glob:
                    var parser = FilenameFilterGlobParser(
                        source: normalizedSource,
                        casePolicy: casePolicy
                    )
                    node = try parser.parse()
                    anchored = true
                case .regularExpression:
                    var parser = FilenameFilterRegexParser(
                        source: normalizedSource,
                        casePolicy: casePolicy,
                        maximumNestingDepth: limits.maximumRegularExpressionNestingDepth,
                        maximumRepetition: limits.maximumRegularExpressionRepetition
                    )
                    node = try parser.parse()
                    anchored = false
                }

                let remainingStateCount = limits.maximumCompiledStateCount - totalCompiledStates
                var compiler = FilenameFilterRegexCompiler(maximumStateCount: remainingStateCount)
                let machine = try compiler.compile(node, anchored: anchored)
                totalCompiledStates += machine.instructions.count
                compiledRules.append(
                    FilenameFilterCompiledRule(
                        originalIndex: index,
                        decision: rule.decision,
                        applicability: rule.applicability,
                        machine: machine
                    )
                )
            } catch let error as FilenameFilterPatternParseError {
                let reason: FilenameFilterDiagnosticReason
                switch (rule.pattern, error.kind) {
                case (.glob, _):
                    reason = .invalidGlob(
                        unicodeScalarOffset: error.offset,
                        message: error.message
                    )
                case (.regularExpression, .unsupported):
                    reason = .unsupportedRegularExpression(
                        unicodeScalarOffset: error.offset,
                        message: error.message
                    )
                case (.regularExpression, .invalid):
                    reason = .invalidRegularExpression(
                        unicodeScalarOffset: error.offset,
                        message: error.message
                    )
                }
                diagnostics.append(FilenameFilterDiagnostic(ruleIndex: index, reason: reason))
            } catch is FilenameFilterStateLimitError {
                diagnostics.append(
                    FilenameFilterDiagnostic(
                        ruleIndex: index,
                        reason: .compiledStateCountExceeded(
                            maximum: limits.maximumCompiledStateCount
                        )
                    )
                )
            }
        }
        try Task.checkCancellation()

        self.rules = rules
        self.defaultDecision = defaultDecision
        self.matchSemantics = matchSemantics
        self.casePolicy = casePolicy
        self.limits = limits
        self.diagnostics = diagnostics
        self.compiledRules = compiledRules
    }

    public func evaluate(
        relativePath: String,
        kind: FilenameFilterEntryKind
    ) throws -> FilenameFilterEvaluation {
        try Task.checkCancellation()
        try Self.validateCanonicalRelativePath(relativePath)
        guard relativePath.utf8.count <= limits.maximumRelativePathUTF8Bytes else {
            throw FilenameFilterError.relativePathTooLarge(
                maximumUTF8Bytes: limits.maximumRelativePathUTF8Bytes
            )
        }

        let matchingPath = filenameFilterFold(relativePath, using: casePolicy)
        let scalars = matchingPath.unicodeScalars.map(\.value)
        var budget = FilenameFilterMatchBudget(maximum: limits.maximumMatchWork)
        var decision = defaultDecision
        var matchedRuleIndex: Int?

        for rule in compiledRules where rule.applies(to: kind) {
            try Task.checkCancellation()
            try budget.charge()
            guard try rule.machine.matches(scalars, budget: &budget) else { continue }
            decision = rule.decision
            matchedRuleIndex = rule.originalIndex
            if matchSemantics == .firstMatchWins { break }
        }
        try Task.checkCancellation()
        return FilenameFilterEvaluation(
            decision: decision,
            matchedRuleIndex: matchedRuleIndex,
            work: budget.work
        )
    }

    public func includes(relativePath: String, kind: FilenameFilterEntryKind) throws -> Bool {
        try evaluate(relativePath: relativePath, kind: kind).isIncluded
    }

    public static func validateCanonicalRelativePath(_ relativePath: String) throws {
        guard !relativePath.isEmpty else {
            throw FilenameFilterError.invalidRelativePath(.empty)
        }
        guard !relativePath.hasPrefix("/") else {
            throw FilenameFilterError.invalidRelativePath(.absolute)
        }
        guard !relativePath.contains("\0") else {
            throw FilenameFilterError.invalidRelativePath(.containsNull)
        }
        guard relativePath == relativePath.precomposedStringWithCanonicalMapping else {
            throw FilenameFilterError.invalidRelativePath(.notCanonicallyComposed)
        }
        for component in relativePath.split(separator: "/", omittingEmptySubsequences: false) {
            guard !component.isEmpty else {
                throw FilenameFilterError.invalidRelativePath(.emptyComponent)
            }
            guard component != "." else {
                throw FilenameFilterError.invalidRelativePath(.currentDirectoryComponent)
            }
            guard component != ".." else {
                throw FilenameFilterError.invalidRelativePath(.parentTraversal)
            }
        }
    }
}

private struct FilenameFilterCompiledRule: Sendable {
    let originalIndex: Int
    let decision: FilenameFilterDecision
    let applicability: FilenameFilterRuleApplicability
    let machine: FilenameFilterRegexMachine

    func applies(to kind: FilenameFilterEntryKind) -> Bool {
        switch (applicability, kind) {
        case (.filesAndDirectories, _), (.files, .file), (.directories, .directory):
            return true
        default:
            return false
        }
    }
}

private enum FilenameFilterPatternParseErrorKind: Sendable {
    case invalid
    case unsupported
}

private struct FilenameFilterPatternParseError: Error, Sendable {
    let kind: FilenameFilterPatternParseErrorKind
    let offset: Int
    let message: String
}

private struct FilenameFilterStateLimitError: Error {}

private indirect enum FilenameFilterRegexNode: Sendable {
    case empty
    case consume(FilenameFilterScalarPredicate)
    case concatenation([FilenameFilterRegexNode])
    case alternation([FilenameFilterRegexNode])
    case repetition(FilenameFilterRegexNode, minimum: Int, maximum: Int?)
    case assertStart
    case assertEnd
}

private enum FilenameFilterBuiltinScalarClass: Sendable {
    case digit
    case word
    case whitespace

    func contains(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        switch self {
        case .digit:
            return scalar.properties.numericType == .decimal
        case .word:
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                .otherLetter, .nonspacingMark, .spacingMark, .decimalNumber,
                .letterNumber, .otherNumber, .connectorPunctuation:
                return true
            default:
                return value == 0x5F
            }
        case .whitespace:
            return scalar.properties.isWhitespace
        }
    }
}

private struct FilenameFilterScalarRange: Sendable {
    let lower: UInt32
    let upper: UInt32
}

private struct FilenameFilterScalarSet: Sendable {
    let ranges: [FilenameFilterScalarRange]
    let builtins: [FilenameFilterBuiltinScalarClass]
    let inverted: Bool

    func contains(_ value: UInt32) -> Bool {
        let found =
            ranges.contains { $0.lower <= value && value <= $0.upper }
            || builtins.contains { $0.contains(value) }
        return inverted ? !found : found
    }
}

private enum FilenameFilterScalarPredicate: Sendable {
    case literal(UInt32)
    case any(excludesSeparator: Bool, excludesLineTerminators: Bool)
    case scalarSet(FilenameFilterScalarSet, excludesSeparator: Bool)

    func matches(_ value: UInt32) -> Bool {
        switch self {
        case .literal(let expected):
            return value == expected
        case .any(let excludesSeparator, let excludesLineTerminators):
            if excludesSeparator && value == 0x2F { return false }
            if excludesLineTerminators && filenameFilterIsLineTerminator(value) { return false }
            return true
        case .scalarSet(let set, let excludesSeparator):
            return (!excludesSeparator || value != 0x2F) && set.contains(value)
        }
    }
}

private struct FilenameFilterGlobParser {
    private let scalars: [UInt32]
    private let casePolicy: FilenameFilterCasePolicy
    private var index = 0

    init(source: String, casePolicy: FilenameFilterCasePolicy) {
        scalars = source.unicodeScalars.map(\.value)
        self.casePolicy = casePolicy
    }

    mutating func parse() throws -> FilenameFilterRegexNode {
        var nodes: [FilenameFilterRegexNode] = [.assertStart]
        while index < scalars.count {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let value = scalars[index]
            index += 1
            switch value {
            case 0x2A:
                if peek() == 0x2A {
                    index += 1
                    if peek() == 0x2F {
                        index += 1
                        let component = FilenameFilterRegexNode.concatenation([
                            .repetition(
                                .consume(
                                    .any(
                                        excludesSeparator: true,
                                        excludesLineTerminators: false
                                    )
                                ),
                                minimum: 1,
                                maximum: nil
                            ),
                            .consume(.literal(0x2F))
                        ])
                        nodes.append(.repetition(component, minimum: 0, maximum: nil))
                    } else {
                        nodes.append(
                            .repetition(
                                .consume(
                                    .any(
                                        excludesSeparator: false,
                                        excludesLineTerminators: false
                                    )
                                ),
                                minimum: 0,
                                maximum: nil
                            )
                        )
                    }
                } else {
                    nodes.append(
                        .repetition(
                            .consume(
                                .any(excludesSeparator: true, excludesLineTerminators: false)
                            ),
                            minimum: 0,
                            maximum: nil
                        )
                    )
                }
            case 0x3F:
                nodes.append(
                    .consume(.any(excludesSeparator: true, excludesLineTerminators: false))
                )
            case 0x5B:
                nodes.append(.consume(try parseCharacterClass()))
            case 0x5C:
                guard let escaped = consume() else {
                    throw invalid(at: index - 1, "Trailing escape.")
                }
                nodes.append(contentsOf: literalNodes(for: escaped))
            default:
                nodes.append(contentsOf: literalNodes(for: value))
            }
        }
        nodes.append(.assertEnd)
        return .concatenation(nodes)
    }

    private mutating func parseCharacterClass() throws -> FilenameFilterScalarPredicate {
        let classOffset = index - 1
        var inverted = false
        if peek() == 0x21 || peek() == 0x5E {
            inverted = true
            index += 1
        }
        var atoms: [FilenameFilterClassAtom] = []
        while let value = consume() {
            if value == 0x5D {
                guard !atoms.isEmpty else {
                    throw invalid(at: classOffset, "Empty character class.")
                }
                return try predicate(from: atoms, inverted: inverted, classOffset: classOffset)
            }
            if value == 0x5C {
                guard let escaped = consume() else {
                    throw invalid(at: index - 1, "Trailing escape in character class.")
                }
                atoms.append(.literal(escaped, escaped: true))
            } else {
                atoms.append(.literal(value, escaped: false))
            }
        }
        throw invalid(at: classOffset, "Unterminated character class.")
    }

    private func predicate(
        from atoms: [FilenameFilterClassAtom],
        inverted: Bool,
        classOffset: Int
    ) throws -> FilenameFilterScalarPredicate {
        let set = try filenameFilterScalarSet(
            atoms: atoms,
            inverted: inverted,
            casePolicy: casePolicy,
            offset: classOffset
        )
        return .scalarSet(set, excludesSeparator: true)
    }

    private func literalNodes(for value: UInt32) -> [FilenameFilterRegexNode] {
        filenameFilterFoldedScalars(value, using: casePolicy).map {
            .consume(.literal($0))
        }
    }

    private func peek() -> UInt32? {
        index < scalars.count ? scalars[index] : nil
    }

    private mutating func consume() -> UInt32? {
        guard index < scalars.count else { return nil }
        defer { index += 1 }
        return scalars[index]
    }

    private func invalid(at offset: Int, _ message: String) -> FilenameFilterPatternParseError {
        FilenameFilterPatternParseError(kind: .invalid, offset: offset, message: message)
    }
}

private enum FilenameFilterClassAtom: Sendable {
    case literal(UInt32, escaped: Bool)
    case builtin(FilenameFilterBuiltinScalarClass, inverted: Bool)
}

private struct FilenameFilterRegexParser {
    private let scalars: [UInt32]
    private let casePolicy: FilenameFilterCasePolicy
    private let maximumNestingDepth: Int
    private let maximumRepetition: Int
    private var index = 0

    init(
        source: String,
        casePolicy: FilenameFilterCasePolicy,
        maximumNestingDepth: Int,
        maximumRepetition: Int
    ) {
        scalars = source.unicodeScalars.map(\.value)
        self.casePolicy = casePolicy
        self.maximumNestingDepth = maximumNestingDepth
        self.maximumRepetition = maximumRepetition
    }

    mutating func parse() throws -> FilenameFilterRegexNode {
        let node = try parseAlternation(depth: 0)
        guard index == scalars.count else {
            throw invalid(at: index, "Unexpected closing parenthesis.")
        }
        return node
    }

    private mutating func parseAlternation(depth: Int) throws -> FilenameFilterRegexNode {
        var alternatives: [FilenameFilterRegexNode] = [try parseConcatenation(depth: depth)]
        while peek() == 0x7C {
            index += 1
            alternatives.append(try parseConcatenation(depth: depth))
        }
        return alternatives.count == 1 ? alternatives[0] : .alternation(alternatives)
    }

    private mutating func parseConcatenation(depth: Int) throws -> FilenameFilterRegexNode {
        var nodes: [FilenameFilterRegexNode] = []
        while let value = peek(), value != 0x29, value != 0x7C {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            nodes.append(try parseRepetition(depth: depth))
        }
        if nodes.isEmpty { return .empty }
        return nodes.count == 1 ? nodes[0] : .concatenation(nodes)
    }

    private mutating func parseRepetition(depth: Int) throws -> FilenameFilterRegexNode {
        let atomOffset = index
        let (atom, quantifiable) = try parseAtom(depth: depth)
        guard let value = peek(), value == 0x2A || value == 0x2B || value == 0x3F || value == 0x7B
        else {
            return atom
        }
        guard quantifiable else {
            throw invalid(at: atomOffset, "Assertions cannot be repeated.")
        }

        let bounds: (minimum: Int, maximum: Int?)
        switch value {
        case 0x2A:
            index += 1
            bounds = (0, nil)
        case 0x2B:
            index += 1
            bounds = (1, nil)
        case 0x3F:
            index += 1
            bounds = (0, 1)
        default:
            bounds = try parseBraceQuantifier()
        }
        if let next = peek(), next == 0x2A || next == 0x2B || next == 0x3F || next == 0x7B {
            throw unsupported(at: index, "Lazy, possessive, and stacked quantifiers are unsupported.")
        }
        return .repetition(atom, minimum: bounds.minimum, maximum: bounds.maximum)
    }

    private mutating func parseAtom(
        depth: Int
    ) throws -> (FilenameFilterRegexNode, quantifiable: Bool) {
        let offset = index
        guard let value = consume() else {
            throw invalid(at: index, "Expected an expression atom.")
        }
        switch value {
        case 0x28:
            guard depth < maximumNestingDepth else {
                throw invalid(at: offset, "Regular-expression nesting limit was exceeded.")
            }
            if peek() == 0x3F {
                index += 1
                guard consume() == 0x3A else {
                    throw unsupported(
                        at: offset,
                        "Only ordinary and noncapturing groups are supported."
                    )
                }
            }
            let group = try parseAlternation(depth: depth + 1)
            guard consume() == 0x29 else {
                throw invalid(at: offset, "Unterminated group.")
            }
            return (group, true)
        case 0x2E:
            return (
                .consume(.any(excludesSeparator: false, excludesLineTerminators: true)),
                true
            )
        case 0x5B:
            return (.consume(try parseCharacterClass()), true)
        case 0x5E:
            return (.assertStart, false)
        case 0x24:
            return (.assertEnd, false)
        case 0x5C:
            return try parseEscape(at: offset)
        case 0x2A, 0x2B, 0x3F, 0x7B:
            throw invalid(at: offset, "Quantifier has no preceding atom.")
        case 0x5D:
            throw invalid(at: offset, "Unexpected closing bracket.")
        default:
            return (literalNode(for: value), true)
        }
    }

    private mutating func parseEscape(
        at offset: Int
    ) throws -> (FilenameFilterRegexNode, quantifiable: Bool) {
        guard let escaped = consume() else {
            throw invalid(at: offset, "Trailing escape.")
        }
        switch escaped {
        case 0x41:
            return (.assertStart, false)
        case 0x7A:
            return (.assertEnd, false)
        case 0x64:
            return (builtinNode(.digit, inverted: false), true)
        case 0x44:
            return (builtinNode(.digit, inverted: true), true)
        case 0x77:
            return (builtinNode(.word, inverted: false), true)
        case 0x57:
            return (builtinNode(.word, inverted: true), true)
        case 0x73:
            return (builtinNode(.whitespace, inverted: false), true)
        case 0x53:
            return (builtinNode(.whitespace, inverted: true), true)
        case 0x6E:
            return (literalNode(for: 0x0A), true)
        case 0x72:
            return (literalNode(for: 0x0D), true)
        case 0x74:
            return (literalNode(for: 0x09), true)
        case 0x5C, 0x2E, 0x2A, 0x2B, 0x3F, 0x5B, 0x5D, 0x28, 0x29,
            0x7B, 0x7D, 0x7C, 0x5E, 0x24, 0x2D, 0x2F:
            return (literalNode(for: escaped), true)
        default:
            throw unsupported(
                at: offset,
                "Escape is not part of the bounded regular-expression subset."
            )
        }
    }

    private mutating func parseCharacterClass() throws -> FilenameFilterScalarPredicate {
        let classOffset = index - 1
        var inverted = false
        if peek() == 0x5E {
            inverted = true
            index += 1
        }
        var atoms: [FilenameFilterClassAtom] = []
        while let value = consume() {
            if value == 0x5D {
                guard !atoms.isEmpty else {
                    throw invalid(at: classOffset, "Empty character class.")
                }
                let set = try filenameFilterScalarSet(
                    atoms: atoms,
                    inverted: inverted,
                    casePolicy: casePolicy,
                    offset: classOffset
                )
                return .scalarSet(set, excludesSeparator: false)
            }
            if value == 0x5C {
                guard let escaped = consume() else {
                    throw invalid(at: index - 1, "Trailing escape in character class.")
                }
                switch escaped {
                case 0x64:
                    atoms.append(.builtin(.digit, inverted: false))
                case 0x44:
                    atoms.append(.builtin(.digit, inverted: true))
                case 0x77:
                    atoms.append(.builtin(.word, inverted: false))
                case 0x57:
                    atoms.append(.builtin(.word, inverted: true))
                case 0x73:
                    atoms.append(.builtin(.whitespace, inverted: false))
                case 0x53:
                    atoms.append(.builtin(.whitespace, inverted: true))
                case 0x6E:
                    atoms.append(.literal(0x0A, escaped: true))
                case 0x72:
                    atoms.append(.literal(0x0D, escaped: true))
                case 0x74:
                    atoms.append(.literal(0x09, escaped: true))
                case 0x5C, 0x5D, 0x5B, 0x5E, 0x2D:
                    atoms.append(.literal(escaped, escaped: true))
                default:
                    throw unsupported(
                        at: index - 2,
                        "Character-class escape is unsupported."
                    )
                }
            } else {
                atoms.append(.literal(value, escaped: false))
            }
        }
        throw invalid(at: classOffset, "Unterminated character class.")
    }

    private mutating func parseBraceQuantifier() throws -> (minimum: Int, maximum: Int?) {
        let offset = index
        index += 1
        guard let minimum = parseDecimalInteger() else {
            throw invalid(at: offset, "Expected a repetition count after `{`.")
        }
        let maximum: Int?
        if peek() == 0x7D {
            index += 1
            maximum = minimum
        } else {
            guard consume() == 0x2C else {
                throw invalid(at: offset, "Expected `,` or `}` in repetition.")
            }
            if peek() == 0x7D {
                index += 1
                maximum = nil
            } else {
                guard let parsedMaximum = parseDecimalInteger(), consume() == 0x7D else {
                    throw invalid(at: offset, "Invalid bounded repetition.")
                }
                maximum = parsedMaximum
            }
        }
        guard minimum <= maximumRepetition,
            maximum.map({ $0 <= maximumRepetition }) ?? true
        else {
            throw invalid(at: offset, "Repetition limit was exceeded.")
        }
        guard maximum.map({ minimum <= $0 }) ?? true else {
            throw invalid(at: offset, "Repetition maximum is smaller than its minimum.")
        }
        return (minimum, maximum)
    }

    private mutating func parseDecimalInteger() -> Int? {
        var result = 0
        var foundDigit = false
        while let value = peek(), (0x30...0x39).contains(value) {
            foundDigit = true
            let digit = Int(value - 0x30)
            let (multiplied, multiplyOverflow) = result.multipliedReportingOverflow(by: 10)
            let (next, addOverflow) = multiplied.addingReportingOverflow(digit)
            if multiplyOverflow || addOverflow {
                result = Int.max
            } else {
                result = next
            }
            index += 1
        }
        return foundDigit ? result : nil
    }

    private func literalNode(for value: UInt32) -> FilenameFilterRegexNode {
        let nodes = filenameFilterFoldedScalars(value, using: casePolicy).map {
            FilenameFilterRegexNode.consume(.literal($0))
        }
        return nodes.count == 1 ? nodes[0] : .concatenation(nodes)
    }

    private func builtinNode(
        _ builtin: FilenameFilterBuiltinScalarClass,
        inverted: Bool
    ) -> FilenameFilterRegexNode {
        .consume(
            .scalarSet(
                FilenameFilterScalarSet(ranges: [], builtins: [builtin], inverted: inverted),
                excludesSeparator: false
            )
        )
    }

    private func peek() -> UInt32? {
        index < scalars.count ? scalars[index] : nil
    }

    private mutating func consume() -> UInt32? {
        guard index < scalars.count else { return nil }
        defer { index += 1 }
        return scalars[index]
    }

    private func invalid(at offset: Int, _ message: String) -> FilenameFilterPatternParseError {
        FilenameFilterPatternParseError(kind: .invalid, offset: offset, message: message)
    }

    private func unsupported(at offset: Int, _ message: String) -> FilenameFilterPatternParseError {
        FilenameFilterPatternParseError(kind: .unsupported, offset: offset, message: message)
    }
}

private enum FilenameFilterInstructionOperation: Sendable {
    case consume(FilenameFilterScalarPredicate)
    case epsilon
    case split
    case assertStart
    case assertEnd
    case accept
}

private struct FilenameFilterInstruction: Sendable {
    let operation: FilenameFilterInstructionOperation
    var first: Int
    var second: Int
}

private struct FilenameFilterPatch: Sendable {
    let instruction: Int
    let branch: Int
}

private struct FilenameFilterFragment: Sendable {
    let start: Int
    let outputs: [FilenameFilterPatch]
}

private struct FilenameFilterRegexCompiler {
    private let maximumStateCount: Int
    private var instructions: [FilenameFilterInstruction] = []

    init(maximumStateCount: Int) {
        self.maximumStateCount = maximumStateCount
    }

    mutating func compile(
        _ node: FilenameFilterRegexNode,
        anchored: Bool
    ) throws -> FilenameFilterRegexMachine {
        let fragment = try compile(node)
        let accept = try emit(.accept)
        patch(fragment.outputs, to: accept)
        return FilenameFilterRegexMachine(
            instructions: instructions,
            start: fragment.start,
            anchored: anchored
        )
    }

    private mutating func compile(
        _ node: FilenameFilterRegexNode
    ) throws -> FilenameFilterFragment {
        switch node {
        case .empty:
            let instruction = try emit(.epsilon)
            return FilenameFilterFragment(
                start: instruction,
                outputs: [FilenameFilterPatch(instruction: instruction, branch: 0)]
            )
        case .consume(let predicate):
            let instruction = try emit(.consume(predicate))
            return FilenameFilterFragment(
                start: instruction,
                outputs: [FilenameFilterPatch(instruction: instruction, branch: 0)]
            )
        case .assertStart:
            let instruction = try emit(.assertStart)
            return FilenameFilterFragment(
                start: instruction,
                outputs: [FilenameFilterPatch(instruction: instruction, branch: 0)]
            )
        case .assertEnd:
            let instruction = try emit(.assertEnd)
            return FilenameFilterFragment(
                start: instruction,
                outputs: [FilenameFilterPatch(instruction: instruction, branch: 0)]
            )
        case .concatenation(let nodes):
            var result: FilenameFilterFragment?
            for child in nodes {
                let next = try compile(child)
                if let previous = result {
                    patch(previous.outputs, to: next.start)
                    result = FilenameFilterFragment(start: previous.start, outputs: next.outputs)
                } else {
                    result = next
                }
            }
            return try result ?? compile(.empty)
        case .alternation(let nodes):
            guard var result = try nodes.first.map({ try compile($0) }) else {
                return try compile(.empty)
            }
            for child in nodes.dropFirst() {
                let alternative = try compile(child)
                let split = try emit(
                    .split,
                    first: result.start,
                    second: alternative.start
                )
                result = FilenameFilterFragment(
                    start: split,
                    outputs: result.outputs + alternative.outputs
                )
            }
            return result
        case .repetition(let child, let minimum, let maximum):
            var result: FilenameFilterFragment?
            for _ in 0..<minimum {
                result = try append(compile(child), to: result)
            }
            if let maximum {
                for _ in minimum..<maximum {
                    let optional = try optionalFragment(for: child)
                    result = append(optional, to: result)
                }
            } else {
                let repeating = try starFragment(for: child)
                result = append(repeating, to: result)
            }
            return try result ?? compile(.empty)
        }
    }

    private mutating func optionalFragment(
        for node: FilenameFilterRegexNode
    ) throws -> FilenameFilterFragment {
        let child = try compile(node)
        let split = try emit(.split, first: child.start)
        return FilenameFilterFragment(
            start: split,
            outputs: child.outputs + [FilenameFilterPatch(instruction: split, branch: 1)]
        )
    }

    private mutating func starFragment(
        for node: FilenameFilterRegexNode
    ) throws -> FilenameFilterFragment {
        let child = try compile(node)
        let split = try emit(.split, first: child.start)
        patch(child.outputs, to: split)
        return FilenameFilterFragment(
            start: split,
            outputs: [FilenameFilterPatch(instruction: split, branch: 1)]
        )
    }

    private mutating func append(
        _ fragment: FilenameFilterFragment,
        to result: FilenameFilterFragment?
    ) -> FilenameFilterFragment {
        guard let result else { return fragment }
        patch(result.outputs, to: fragment.start)
        return FilenameFilterFragment(start: result.start, outputs: fragment.outputs)
    }

    private mutating func emit(
        _ operation: FilenameFilterInstructionOperation,
        first: Int = -1,
        second: Int = -1
    ) throws -> Int {
        guard instructions.count < maximumStateCount else {
            throw FilenameFilterStateLimitError()
        }
        if instructions.count.isMultiple(of: 256) { try Task.checkCancellation() }
        instructions.append(
            FilenameFilterInstruction(operation: operation, first: first, second: second)
        )
        return instructions.count - 1
    }

    private mutating func patch(_ patches: [FilenameFilterPatch], to destination: Int) {
        for patch in patches {
            if patch.branch == 0 {
                instructions[patch.instruction].first = destination
            } else {
                instructions[patch.instruction].second = destination
            }
        }
    }
}

private struct FilenameFilterRegexMachine: Sendable {
    let instructions: [FilenameFilterInstruction]
    let start: Int
    let anchored: Bool

    func matches(_ path: [UInt32], budget: inout FilenameFilterMatchBudget) throws -> Bool {
        var pending: [Int] = []
        var marks = [Int](repeating: 0, count: instructions.count)
        var generation = 0

        for position in 0...path.count {
            try Task.checkCancellation()
            var seeds = pending
            if position == 0 || !anchored { seeds.append(start) }
            let closure = try epsilonClosure(
                from: seeds,
                position: position,
                pathCount: path.count,
                marks: &marks,
                generation: &generation,
                budget: &budget
            )
            if closure.accepted { return true }
            guard position < path.count else { return false }

            pending.removeAll(keepingCapacity: true)
            for state in closure.consumingStates {
                try budget.charge()
                guard case .consume(let predicate) = instructions[state].operation,
                    predicate.matches(path[position])
                else {
                    continue
                }
                pending.append(instructions[state].first)
            }
            if anchored && pending.isEmpty { return false }
        }
        return false
    }

    private func epsilonClosure(
        from seeds: [Int],
        position: Int,
        pathCount: Int,
        marks: inout [Int],
        generation: inout Int,
        budget: inout FilenameFilterMatchBudget
    ) throws -> (consumingStates: [Int], accepted: Bool) {
        generation += 1
        var stack = seeds
        var consumingStates: [Int] = []
        var accepted = false
        while let state = stack.popLast() {
            guard state >= 0, marks[state] != generation else { continue }
            marks[state] = generation
            try budget.charge()
            let instruction = instructions[state]
            switch instruction.operation {
            case .consume:
                consumingStates.append(state)
            case .epsilon:
                stack.append(instruction.first)
            case .split:
                stack.append(instruction.second)
                stack.append(instruction.first)
            case .assertStart:
                if position == 0 { stack.append(instruction.first) }
            case .assertEnd:
                if position == pathCount { stack.append(instruction.first) }
            case .accept:
                accepted = true
            }
        }
        return (consumingStates, accepted)
    }
}

private struct FilenameFilterMatchBudget {
    let maximum: Int
    private(set) var work = 0

    mutating func charge(_ amount: Int = 1) throws {
        let (next, overflow) = work.addingReportingOverflow(amount)
        guard !overflow, next <= maximum else {
            throw FilenameFilterError.matchWorkExceeded(maximum: maximum)
        }
        work = next
        if work.isMultiple(of: 256) { try Task.checkCancellation() }
    }
}

private func filenameFilterScalarSet(
    atoms: [FilenameFilterClassAtom],
    inverted: Bool,
    casePolicy: FilenameFilterCasePolicy,
    offset: Int
) throws -> FilenameFilterScalarSet {
    var ranges: [FilenameFilterScalarRange] = []
    var builtins: [FilenameFilterBuiltinScalarClass] = []
    var index = 0
    while index < atoms.count {
        if index + 2 < atoms.count,
            case .literal(let lower, _) = atoms[index],
            case .literal(0x2D, escaped: false) = atoms[index + 1],
            case .literal(let upper, _) = atoms[index + 2]
        {
            let foldedLower = filenameFilterFoldedScalars(lower, using: casePolicy)
            let foldedUpper = filenameFilterFoldedScalars(upper, using: casePolicy)
            guard foldedLower.count == 1, foldedUpper.count == 1 else {
                throw FilenameFilterPatternParseError(
                    kind: .unsupported,
                    offset: offset,
                    message: "Case-folding expansion is unsupported in character-class ranges."
                )
            }
            guard foldedLower[0] <= foldedUpper[0] else {
                throw FilenameFilterPatternParseError(
                    kind: .invalid,
                    offset: offset,
                    message: "Character-class range is descending."
                )
            }
            ranges.append(FilenameFilterScalarRange(lower: foldedLower[0], upper: foldedUpper[0]))
            index += 3
            continue
        }

        switch atoms[index] {
        case .literal(let value, _):
            let folded = filenameFilterFoldedScalars(value, using: casePolicy)
            guard folded.count == 1 else {
                throw FilenameFilterPatternParseError(
                    kind: .unsupported,
                    offset: offset,
                    message: "Case-folding expansion is unsupported in character classes."
                )
            }
            ranges.append(FilenameFilterScalarRange(lower: folded[0], upper: folded[0]))
        case .builtin(let builtin, let atomInverted):
            if atomInverted {
                guard atoms.count == 1, !inverted else {
                    throw FilenameFilterPatternParseError(
                        kind: .unsupported,
                        offset: offset,
                        message: "An inverted shorthand must be the only item in its character class."
                    )
                }
                return FilenameFilterScalarSet(ranges: [], builtins: [builtin], inverted: true)
            }
            builtins.append(builtin)
        }
        index += 1
    }
    return FilenameFilterScalarSet(ranges: ranges, builtins: builtins, inverted: inverted)
}

private func filenameFilterFold(
    _ value: String,
    using casePolicy: FilenameFilterCasePolicy
) -> String {
    guard casePolicy == .insensitive else { return value }
    return value.folding(
        options: .caseInsensitive,
        locale: Locale(identifier: "en_US_POSIX")
    ).precomposedStringWithCanonicalMapping
}

private func filenameFilterFoldedScalars(
    _ value: UInt32,
    using casePolicy: FilenameFilterCasePolicy
) -> [UInt32] {
    guard casePolicy == .insensitive, let scalar = Unicode.Scalar(value) else { return [value] }
    return filenameFilterFold(String(scalar), using: casePolicy).unicodeScalars.map(\.value)
}

private func filenameFilterIsLineTerminator(_ value: UInt32) -> Bool {
    value == 0x0A || value == 0x0D || value == 0x85 || value == 0x2028 || value == 0x2029
}
