import Foundation

/// Strongly typed, caller-owned identifier normalized to Unicode NFC.
public struct MenuValidationIdentifier<Domain>: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        menuValidationCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

public enum MenuValidationIdentifierDomain {
    public enum Contract: Sendable {}
    public enum Element: Sendable {}
    public enum Command: Sendable {}
    public enum Scenario: Sendable {}
    public enum Target: Sendable {}
    public enum Action: Sendable {}
    public enum Result: Sendable {}
}

public typealias MenuValidationContractID =
    MenuValidationIdentifier<MenuValidationIdentifierDomain.Contract>
public typealias MenuElementID = MenuValidationIdentifier<MenuValidationIdentifierDomain.Element>
public typealias MenuCommandID = MenuValidationIdentifier<MenuValidationIdentifierDomain.Command>
public typealias MenuValidationScenarioID =
    MenuValidationIdentifier<MenuValidationIdentifierDomain.Scenario>
public typealias MenuValidationTargetID =
    MenuValidationIdentifier<MenuValidationIdentifierDomain.Target>
public typealias MenuValidationActionID =
    MenuValidationIdentifier<MenuValidationIdentifierDomain.Action>
public typealias MenuValidationResultID =
    MenuValidationIdentifier<MenuValidationIdentifierDomain.Result>

public enum MenuShortcutPlatform: String, CaseIterable, Comparable, Hashable, Sendable {
    case macOS
    case windows
    case linux

    public static func < (left: Self, right: Self) -> Bool {
        left.rank < right.rank
    }

    fileprivate var rank: Int {
        switch self {
        case .macOS: 0
        case .windows: 1
        case .linux: 2
        }
    }
}

public enum MenuShortcutModifier: String, CaseIterable, Comparable, Hashable, Sendable {
    case command
    case control
    case option
    case shift
    case function
    case alt
    case superKey

    public static func < (left: Self, right: Self) -> Bool {
        left.rank < right.rank
    }

    fileprivate var rank: Int {
        switch self {
        case .command: 0
        case .control: 1
        case .option: 2
        case .shift: 3
        case .function: 4
        case .alt: 5
        case .superKey: 6
        }
    }
}

/// Physical-key spelling. Audits require lowercase ASCII characters or a canonical named key.
public struct MenuShortcutKey: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        menuValidationCompareUTF8(left.rawValue, right.rawValue) < 0
    }

    public var canonical: Self {
        guard rawValue.utf8.count == 1, let byte = rawValue.utf8.first,
            (0x41...0x5A).contains(byte)
        else {
            return self
        }
        return Self(rawValue: String(UnicodeScalar(byte + 0x20)))
    }
}

/// Platform-qualified shortcut. Chords conflict only within the same platform.
public struct MenuShortcutDescriptor: Comparable, Hashable, Sendable {
    public let platform: MenuShortcutPlatform
    public let key: MenuShortcutKey
    public let modifiers: Set<MenuShortcutModifier>

    public init(
        platform: MenuShortcutPlatform,
        key: MenuShortcutKey,
        modifiers: Set<MenuShortcutModifier> = []
    ) {
        self.platform = platform
        self.key = key
        self.modifiers = modifiers
    }

    public init(
        platform: MenuShortcutPlatform,
        key: String,
        modifiers: Set<MenuShortcutModifier> = []
    ) {
        self.init(
            platform: platform,
            key: MenuShortcutKey(rawValue: key),
            modifiers: modifiers
        )
    }

    public var canonicalized: Self {
        Self(platform: platform, key: key.canonical, modifiers: modifiers)
    }

    public var canonicalChord: String {
        let names = modifiers.sorted().map(\.rawValue)
        return platform.rawValue + ":" + names.joined(separator: "+") + ":"
            + menuValidationFrame(key.canonical.rawValue)
    }

    public static func < (left: Self, right: Self) -> Bool {
        menuValidationCompareUTF8(left.sortKey, right.sortKey) < 0
    }

    fileprivate var sortKey: String {
        canonicalChord + ":" + menuValidationFrame(key.rawValue)
    }
}

/// UI-framework-neutral equivalent of a target/action routing pair.
public struct MenuTargetAction: Hashable, Sendable {
    public let targetID: MenuValidationTargetID
    public let actionID: MenuValidationActionID

    public init(targetID: MenuValidationTargetID, actionID: MenuValidationActionID) {
        self.targetID = targetID
        self.actionID = actionID
    }
}

public enum MenuValidationElementKind: String, CaseIterable, Hashable, Sendable {
    case menu
    case command
    case separator
}

/// Static menu node. Child-array position is the exact expected or observed order.
public struct MenuValidationElement: Identifiable, Hashable, Sendable {
    public let id: MenuElementID
    public let kind: MenuValidationElementKind
    public let title: String?
    public let commandID: MenuCommandID?
    public let shortcuts: [MenuShortcutDescriptor]
    public let targetAction: MenuTargetAction?
    public let children: [MenuValidationElement]

    public init(
        id: MenuElementID,
        kind: MenuValidationElementKind,
        title: String? = nil,
        commandID: MenuCommandID? = nil,
        shortcuts: [MenuShortcutDescriptor] = [],
        targetAction: MenuTargetAction? = nil,
        children: [MenuValidationElement] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.commandID = commandID
        self.shortcuts = shortcuts
        self.targetAction = targetAction
        self.children = children
    }
}

public struct MenuValidationTree: Hashable, Sendable {
    public let roots: [MenuValidationElement]

    public init(roots: [MenuValidationElement]) {
        self.roots = roots
    }
}

public enum MenuCheckedState: String, CaseIterable, Hashable, Sendable {
    case notCheckable
    case off
    case on
    case mixed
}

/// Dynamic state for one canonical command in one scenario.
public struct MenuCommandDynamicState: Hashable, Sendable {
    public let commandID: MenuCommandID
    public let isEnabled: Bool
    public let checkedState: MenuCheckedState

    public init(
        commandID: MenuCommandID,
        isEnabled: Bool,
        checkedState: MenuCheckedState = .notCheckable
    ) {
        self.commandID = commandID
        self.isEnabled = isEnabled
        self.checkedState = checkedState
    }
}

public enum MenuInvocationSource: String, CaseIterable, Comparable, Hashable, Sendable {
    case menuItem
    case keyboardShortcut
    case accessibilityAction

    public static func < (left: Self, right: Self) -> Bool {
        left.rank < right.rank
    }

    fileprivate var rank: Int {
        switch self {
        case .menuItem: 0
        case .keyboardShortcut: 1
        case .accessibilityAction: 2
        }
    }
}

/// Caller-defined exact result token. `notInvoked` proves disabled activation did not dispatch.
public enum MenuCommandResult: Hashable, Sendable {
    case completed(MenuValidationResultID)
    case rejected(MenuValidationResultID)
    case failed(MenuValidationResultID)
    case notInvoked
}

public struct MenuInvocationExpectation: Hashable, Sendable {
    public let commandID: MenuCommandID
    public let source: MenuInvocationSource
    public let targetAction: MenuTargetAction?
    public let result: MenuCommandResult

    public init(
        commandID: MenuCommandID,
        source: MenuInvocationSource,
        targetAction: MenuTargetAction?,
        result: MenuCommandResult
    ) {
        self.commandID = commandID
        self.source = source
        self.targetAction = targetAction
        self.result = result
    }
}

/// Exact caller-supplied observation. Presence is evidence, not proof of platform behavior.
public struct MenuInvocationEvidence: Hashable, Sendable {
    public let commandID: MenuCommandID
    public let source: MenuInvocationSource
    public let targetAction: MenuTargetAction?
    public let result: MenuCommandResult

    public init(
        commandID: MenuCommandID,
        source: MenuInvocationSource,
        targetAction: MenuTargetAction?,
        result: MenuCommandResult
    ) {
        self.commandID = commandID
        self.source = source
        self.targetAction = targetAction
        self.result = result
    }
}

public struct MenuValidationScenario: Identifiable, Hashable, Sendable {
    public let id: MenuValidationScenarioID
    public let states: [MenuCommandDynamicState]
    public let invocations: [MenuInvocationExpectation]

    public init(
        id: MenuValidationScenarioID,
        states: [MenuCommandDynamicState],
        invocations: [MenuInvocationExpectation] = []
    ) {
        self.id = id
        self.states = states
        self.invocations = invocations
    }
}

public struct MenuValidationObservedScenario: Identifiable, Hashable, Sendable {
    public let id: MenuValidationScenarioID
    public let tree: MenuValidationTree
    public let states: [MenuCommandDynamicState]
    public let invocations: [MenuInvocationEvidence]

    public init(
        id: MenuValidationScenarioID,
        tree: MenuValidationTree,
        states: [MenuCommandDynamicState],
        invocations: [MenuInvocationEvidence] = []
    ) {
        self.id = id
        self.tree = tree
        self.states = states
        self.invocations = invocations
    }
}

/// Immutable expected menu and scenario contract. It contains no AppKit or runtime objects.
public struct MenuValidationContract: Identifiable, Hashable, Sendable {
    public let id: MenuValidationContractID
    public let tree: MenuValidationTree
    public let scenarios: [MenuValidationScenario]

    public init(
        id: MenuValidationContractID,
        tree: MenuValidationTree,
        scenarios: [MenuValidationScenario]
    ) {
        self.id = id
        self.tree = tree
        self.scenarios = scenarios
    }
}

public struct MenuValidationEvidence: Hashable, Sendable {
    public let scenarios: [MenuValidationObservedScenario]

    public init(scenarios: [MenuValidationObservedScenario]) {
        self.scenarios = scenarios
    }
}

public struct MenuValidationLimits: Hashable, Sendable {
    public static let hardMaximumElements = 100_000
    public static let hardMaximumTotalElements = 1_000_000
    public static let hardMaximumDepth = 128
    public static let hardMaximumScenarios = 1_024
    public static let hardMaximumStatesPerScenario = 100_000
    public static let hardMaximumInvocationsPerScenario = 100_000
    public static let hardMaximumShortcutsPerElement = 32
    public static let hardMaximumStringUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumWorkUnits = 1_000_000_000
    public static let hardMaximumFindings = 1_000_000
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = MenuValidationLimits()

    public let maximumElements: Int
    public let maximumTotalElements: Int
    public let maximumDepth: Int
    public let maximumScenarios: Int
    public let maximumStatesPerScenario: Int
    public let maximumInvocationsPerScenario: Int
    public let maximumShortcutsPerElement: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumWorkUnits: Int
    public let maximumFindings: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumElements: Int = 10_000,
        maximumTotalElements: Int = 100_000,
        maximumDepth: Int = 64,
        maximumScenarios: Int = 64,
        maximumStatesPerScenario: Int = 10_000,
        maximumInvocationsPerScenario: Int = 20_000,
        maximumShortcutsPerElement: Int = 8,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumWorkUnits: Int = 64 * 1_024 * 1_024,
        maximumFindings: Int = 100_000,
        cancellationCheckInterval: Int = 256
    ) {
        self.maximumElements = maximumElements
        self.maximumTotalElements = maximumTotalElements
        self.maximumDepth = maximumDepth
        self.maximumScenarios = maximumScenarios
        self.maximumStatesPerScenario = maximumStatesPerScenario
        self.maximumInvocationsPerScenario = maximumInvocationsPerScenario
        self.maximumShortcutsPerElement = maximumShortcutsPerElement
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumFindings = maximumFindings
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum MenuValidationCountKind: String, Hashable, Sendable {
    case elements
    case totalElements
    case depth
    case scenarios
    case states
    case invocations
    case shortcuts
}

public enum MenuValidationError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(name: String, value: Int, minimum: Int, maximum: Int)
    case countLimitExceeded(kind: MenuValidationCountKind, maximum: Int)
    case stringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximum: Int)
    case findingLimitExceeded(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Menu validation was cancelled."
        case .invalidLimit(let name, let value, let minimum, let maximum):
            "Menu-validation limit \(name) is invalid (\(value)); expected \(minimum)...\(maximum)."
        case .countLimitExceeded(let kind, let maximum):
            "Menu-validation input exceeds the \(maximum)-\(kind.rawValue) limit."
        case .stringTooLarge(let field, let maximumUTF8Bytes):
            "Menu-validation field \(field) exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .totalStringsTooLarge(let maximumUTF8Bytes):
            "Menu-validation strings exceed the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .workLimitExceeded(let maximum):
            "Menu validation exceeds the \(maximum)-unit work limit."
        case .findingLimitExceeded(let maximum):
            "Menu validation exceeds the \(maximum)-finding limit."
        }
    }
}

public enum MenuValidationSeverity: String, CaseIterable, Comparable, Hashable, Sendable {
    case advisory
    case warning
    case error

    public static func < (left: Self, right: Self) -> Bool {
        left.rank < right.rank
    }

    fileprivate var rank: Int {
        switch self {
        case .advisory: 0
        case .warning: 1
        case .error: 2
        }
    }
}

public enum MenuValidationFindingCode: String, CaseIterable, Hashable, Sendable {
    case invalidIdentifier
    case invalidTitle
    case invalidElementShape
    case invalidRootElement
    case invalidShortcut
    case invalidTargetAction
    case invalidResult
    case invalidInvocation
    case duplicateElementID
    case duplicateCommandID
    case duplicateScenarioID
    case duplicateState
    case duplicateInvocation
    case duplicateShortcut
    case shortcutConflict
    case stateTargetsUnknownCommand
    case invocationTargetsUnknownCommand
    case invocationTargetConflict
    case invocationStateConflict
    case missingScenario
    case unexpectedScenario
    case missingElement
    case unexpectedElement
    case elementKindMismatch
    case titleMismatch
    case commandIDMismatch
    case hierarchyMismatch
    case orderMismatch
    case shortcutMismatch
    case targetActionMismatch
    case missingState
    case unexpectedState
    case checkedStateMismatch
    case enabledStateMismatch
    case missingInvocation
    case unexpectedInvocation
    case invocationTargetMismatch
    case resultMismatch
}

public enum MenuValidationEvidenceScope: String, Hashable, Sendable {
    case contract
    case observed
}

public enum MenuValidationSubject: Hashable, Sendable {
    case contract(MenuValidationContractID)
    case scenario(scope: MenuValidationEvidenceScope, id: MenuValidationScenarioID)
    case element(
        scope: MenuValidationEvidenceScope,
        scenarioID: MenuValidationScenarioID?,
        id: MenuElementID
    )
    case command(
        scope: MenuValidationEvidenceScope,
        scenarioID: MenuValidationScenarioID?,
        id: MenuCommandID
    )
    case invocation(
        scope: MenuValidationEvidenceScope,
        scenarioID: MenuValidationScenarioID,
        commandID: MenuCommandID,
        source: MenuInvocationSource
    )
    case rootOrder(
        scope: MenuValidationEvidenceScope,
        scenarioID: MenuValidationScenarioID?
    )
    case shortcut(
        scope: MenuValidationEvidenceScope,
        scenarioID: MenuValidationScenarioID?,
        elementID: MenuElementID,
        descriptor: MenuShortcutDescriptor
    )
}

/// Shallow exact node evidence; child identifiers preserve immediate order without recursion.
public struct MenuValidationElementSummary: Hashable, Sendable {
    public let id: MenuElementID
    public let kind: MenuValidationElementKind
    public let title: String?
    public let commandID: MenuCommandID?
    public let shortcuts: [MenuShortcutDescriptor]
    public let targetAction: MenuTargetAction?
    public let childIDs: [MenuElementID]

    public init(_ element: MenuValidationElement) {
        id = element.id
        kind = element.kind
        title = element.title
        commandID = element.commandID
        shortcuts = element.shortcuts.sorted()
        targetAction = element.targetAction
        childIDs = element.children.map(\.id)
    }

    fileprivate init(
        _ element: MenuValidationElement,
        sortedShortcuts: [MenuShortcutDescriptor]
    ) {
        id = element.id
        kind = element.kind
        title = element.title
        commandID = element.commandID
        shortcuts = sortedShortcuts
        targetAction = element.targetAction
        childIDs = element.children.map(\.id)
    }
}

public enum MenuValidationFindingEvidence: Hashable, Sendable {
    case none
    case identifier(field: String, value: String)
    case occurrences(Int)
    case shape(fields: [String])
    case element(expected: MenuValidationElementSummary?, observed: MenuValidationElementSummary?)
    case elementKind(expected: MenuValidationElementKind, observed: MenuValidationElementKind)
    case title(expected: String?, observed: String?)
    case commandID(expected: MenuCommandID?, observed: MenuCommandID?)
    case parent(expected: MenuElementID?, observed: MenuElementID?)
    case order(expected: [MenuElementID], observed: [MenuElementID])
    case shortcuts(expected: [MenuShortcutDescriptor], observed: [MenuShortcutDescriptor])
    case shortcutConflict(descriptor: MenuShortcutDescriptor, commands: [MenuCommandID])
    case state(expected: MenuCommandDynamicState?, observed: MenuCommandDynamicState?)
    case checkedState(expected: MenuCheckedState, observed: MenuCheckedState)
    case enabledState(expected: Bool, observed: Bool)
    case targetAction(expected: MenuTargetAction?, observed: MenuTargetAction?)
    case invocation(expected: MenuInvocationExpectation?, observed: MenuInvocationEvidence?)
    case result(expected: MenuCommandResult, observed: MenuCommandResult)
}

public struct MenuValidationFinding: Identifiable, Hashable, Sendable {
    public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            menuValidationCompareUTF8(left.rawValue, right.rawValue) < 0
        }

        fileprivate init(
            code: MenuValidationFindingCode,
            subject: MenuValidationSubject,
            evidence: MenuValidationFindingEvidence
        ) {
            var value = menuValidationFrame(code.rawValue)
            for component in subject.menuValidationIdentityComponents
                + evidence.menuValidationIdentityComponents
            {
                value.append(menuValidationFrame(component))
            }
            rawValue = value
        }
    }

    public let id: ID
    public let severity: MenuValidationSeverity
    public let code: MenuValidationFindingCode
    public let subject: MenuValidationSubject
    public let evidence: MenuValidationFindingEvidence
    public let message: String

    fileprivate init(
        severity: MenuValidationSeverity,
        code: MenuValidationFindingCode,
        subject: MenuValidationSubject,
        evidence: MenuValidationFindingEvidence
    ) {
        id = ID(code: code, subject: subject, evidence: evidence)
        self.severity = severity
        self.code = code
        self.subject = subject
        self.evidence = evidence
        message = menuValidationMessage(for: code)
    }
}

public struct MenuValidationReport: Hashable, Sendable {
    public static let scopeStatement =
        "Deterministic checks of caller-supplied menu contracts and observations only; not runtime UI verification."

    public let formatVersion: Int
    public let contractID: MenuValidationContractID
    public let findings: [MenuValidationFinding]

    public var highestSeverity: MenuValidationSeverity? { findings.first?.severity }
    public var containsErrors: Bool { findings.contains { $0.severity == .error } }

    fileprivate init(
        formatVersion: Int,
        contractID: MenuValidationContractID,
        findings: [MenuValidationFinding]
    ) {
        self.formatVersion = formatVersion
        self.contractID = contractID
        self.findings = findings
    }
}

/// Pure, deterministic menu-contract audit. No AppKit, accessibility, or dispatch calls occur.
public enum MenuValidationAudit: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool
    public static let reportFormatVersion = 1

    public static func audit(
        contract: MenuValidationContract,
        evidence: MenuValidationEvidence,
        limits: MenuValidationLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> MenuValidationReport {
        try MenuValidationPreflight.validate(limits)
        var budget = MenuValidationWorkBudget(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try budget.checkCancellation()
        try MenuValidationPreflight.inspect(
            contract: contract,
            evidence: evidence,
            limits: limits,
            budget: &budget
        )
        var context = MenuValidationAuditContext(limits: limits, budget: budget)
        try context.run(contract: contract, evidence: evidence)
        return MenuValidationReport(
            formatVersion: reportFormatVersion,
            contractID: contract.id,
            findings: try context.sortedFindings()
        )
    }
}

private struct MenuValidationFlatElement {
    let element: MenuValidationElement
    let parentID: MenuElementID?
}

private struct MenuValidationAnalyzedTree {
    let roots: [MenuValidationElement]
    let elements: [MenuValidationFlatElement]
    let elementByID: [MenuElementID: MenuValidationFlatElement]
    let commandByID: [MenuCommandID: MenuValidationFlatElement]
    let commandIDs: Set<MenuCommandID>
}

private struct MenuValidationInvocationKey: Hashable {
    let commandID: MenuCommandID
    let source: MenuInvocationSource
}

private struct MenuValidationAuditContext {
    let limits: MenuValidationLimits
    var budget: MenuValidationWorkBudget
    private var findings: [MenuValidationFinding] = []
    private var findingIDs: Set<MenuValidationFinding.ID> = []

    init(limits: MenuValidationLimits, budget: MenuValidationWorkBudget) {
        self.limits = limits
        self.budget = budget
    }

    mutating func run(
        contract: MenuValidationContract,
        evidence: MenuValidationEvidence
    ) throws {
        if !menuValidationIsValidIdentifier(contract.id.rawValue) {
            try add(
                .error,
                .invalidIdentifier,
                subject: .contract(contract.id),
                evidence: .identifier(field: "contract.id", value: contract.id.rawValue)
            )
        }

        let expectedTree = try analyzeTree(
            contract.tree,
            scope: .contract,
            scenarioID: nil
        )
        let (expectedScenarios, _) = try scenarioMap(
            contract.scenarios,
            scope: .contract
        )
        let (observedScenarios, observedScenarioIndices) = try observedScenarioMap(
            evidence.scenarios
        )

        for id in try sortedIdentifiers(Array(expectedScenarios.keys))
        where observedScenarios[id] == nil {
            try add(
                .error,
                .missingScenario,
                subject: .scenario(scope: .observed, id: id),
                evidence: .none
            )
        }
        for id in try sortedIdentifiers(Array(observedScenarios.keys))
        where expectedScenarios[id] == nil {
            try add(
                .error,
                .unexpectedScenario,
                subject: .scenario(scope: .observed, id: id),
                evidence: .none
            )
        }

        for (index, observed) in evidence.scenarios.enumerated()
        where observedScenarioIndices[observed.id] != index {
            let observedTree = try analyzeTree(
                observed.tree,
                scope: .observed,
                scenarioID: observed.id
            )
            try inspectObservedScenario(observed, tree: observedTree)
        }

        for id in try sortedIdentifiers(Array(observedScenarios.keys)) {
            guard let observed = observedScenarios[id] else { continue }
            let observedTree = try analyzeTree(
                observed.tree,
                scope: .observed,
                scenarioID: id
            )
            guard let expected = expectedScenarios[id] else {
                try inspectObservedScenario(observed, tree: observedTree)
                continue
            }
            try compareTrees(expectedTree, observedTree, scenarioID: id)
            try compareScenario(
                expected,
                observed,
                expectedTree: expectedTree,
                observedTree: observedTree
            )
        }

        for expected in contract.scenarios {
            try inspectExpectedScenario(expected, tree: expectedTree)
        }
    }

    mutating func sortedFindings() throws -> [MenuValidationFinding] {
        try menuValidationStableSorted(findings, budget: &budget) { left, right, budget in
            try budget.consume(1)
            if left.severity != right.severity {
                return left.severity.rank > right.severity.rank
            }
            let codeOrder = try menuValidationCompareUTF8(
                left.code.rawValue,
                right.code.rawValue,
                budget: &budget
            )
            if codeOrder != 0 {
                return codeOrder < 0
            }
            return try menuValidationCompareUTF8(
                left.id.rawValue,
                right.id.rawValue,
                budget: &budget
            ) < 0
        }
    }

    private mutating func scenarioMap(
        _ scenarios: [MenuValidationScenario],
        scope: MenuValidationEvidenceScope
    ) throws -> (
        scenarios: [MenuValidationScenarioID: MenuValidationScenario],
        indices: [MenuValidationScenarioID: Int]
    ) {
        var counts: [MenuValidationScenarioID: Int] = [:]
        var result: [MenuValidationScenarioID: MenuValidationScenario] = [:]
        var resultKeys: [MenuValidationScenarioID: String] = [:]
        var resultIndices: [MenuValidationScenarioID: Int] = [:]
        for (index, scenario) in scenarios.enumerated() {
            try budget.consume(1)
            counts[scenario.id, default: 0] += 1
            if !menuValidationIsValidIdentifier(scenario.id.rawValue) {
                try add(
                    .error,
                    .invalidIdentifier,
                    subject: .scenario(scope: scope, id: scenario.id),
                    evidence: .identifier(field: "scenario.id", value: scenario.id.rawValue)
                )
            }
            let key = try comparisonKey(for: scenario)
            if let currentKey = resultKeys[scenario.id] {
                if try menuValidationCompareUTF8(key, currentKey, budget: &budget) < 0 {
                    result[scenario.id] = scenario
                    resultKeys[scenario.id] = key
                    resultIndices[scenario.id] = index
                }
            } else {
                result[scenario.id] = scenario
                resultKeys[scenario.id] = key
                resultIndices[scenario.id] = index
            }
        }
        for id in try sortedIdentifiers(Array(counts.keys)) where counts[id, default: 0] > 1 {
            try add(
                .error,
                .duplicateScenarioID,
                subject: .scenario(scope: scope, id: id),
                evidence: .occurrences(counts[id, default: 0])
            )
        }
        return (result, resultIndices)
    }

    private mutating func observedScenarioMap(
        _ scenarios: [MenuValidationObservedScenario]
    ) throws -> (
        scenarios: [MenuValidationScenarioID: MenuValidationObservedScenario],
        indices: [MenuValidationScenarioID: Int]
    ) {
        var counts: [MenuValidationScenarioID: Int] = [:]
        var result: [MenuValidationScenarioID: MenuValidationObservedScenario] = [:]
        var resultKeys: [MenuValidationScenarioID: String] = [:]
        var resultIndices: [MenuValidationScenarioID: Int] = [:]
        for (index, scenario) in scenarios.enumerated() {
            try budget.consume(1)
            counts[scenario.id, default: 0] += 1
            if !menuValidationIsValidIdentifier(scenario.id.rawValue) {
                try add(
                    .error,
                    .invalidIdentifier,
                    subject: .scenario(scope: .observed, id: scenario.id),
                    evidence: .identifier(field: "scenario.id", value: scenario.id.rawValue)
                )
            }
            let key = try comparisonKey(for: scenario)
            if let currentKey = resultKeys[scenario.id] {
                if try menuValidationCompareUTF8(key, currentKey, budget: &budget) < 0 {
                    result[scenario.id] = scenario
                    resultKeys[scenario.id] = key
                    resultIndices[scenario.id] = index
                }
            } else {
                result[scenario.id] = scenario
                resultKeys[scenario.id] = key
                resultIndices[scenario.id] = index
            }
        }
        for id in try sortedIdentifiers(Array(counts.keys)) where counts[id, default: 0] > 1 {
            try add(
                .error,
                .duplicateScenarioID,
                subject: .scenario(scope: .observed, id: id),
                evidence: .occurrences(counts[id, default: 0])
            )
        }
        return (result, resultIndices)
    }

    private mutating func analyzeTree(
        _ tree: MenuValidationTree,
        scope: MenuValidationEvidenceScope,
        scenarioID: MenuValidationScenarioID?
    ) throws -> MenuValidationAnalyzedTree {
        var stack: [(MenuValidationElement, MenuElementID?, Bool)] = []
        stack.reserveCapacity(tree.roots.count)
        for root in tree.roots.reversed() { stack.append((root, nil, true)) }
        var elements: [MenuValidationFlatElement] = []
        var elementCounts: [MenuElementID: Int] = [:]
        var commandCounts: [MenuCommandID: Int] = [:]
        var elementByID: [MenuElementID: MenuValidationFlatElement] = [:]
        var commandByID: [MenuCommandID: MenuValidationFlatElement] = [:]
        var commandIDs: Set<MenuCommandID> = []
        var shortcutsByChord: [String: (MenuShortcutDescriptor, Set<MenuCommandID>, Set<MenuElementID>)] = [:]

        while let (element, parentID, isRoot) = stack.popLast() {
            try budget.consume(1)
            let flat = MenuValidationFlatElement(element: element, parentID: parentID)
            elements.append(flat)
            elementCounts[element.id, default: 0] += 1
            if elementByID[element.id] == nil { elementByID[element.id] = flat }
            if let commandID = element.commandID {
                commandCounts[commandID, default: 0] += 1
                if commandByID[commandID] == nil { commandByID[commandID] = flat }
                commandIDs.insert(commandID)
            }

            let subject = MenuValidationSubject.element(
                scope: scope,
                scenarioID: scenarioID,
                id: element.id
            )
            if !menuValidationIsValidIdentifier(element.id.rawValue) {
                try add(
                    .error,
                    .invalidIdentifier,
                    subject: subject,
                    evidence: .identifier(field: "element.id", value: element.id.rawValue)
                )
            }
            if isRoot, element.kind != .menu {
                try add(
                    .error,
                    .invalidRootElement,
                    subject: subject,
                    evidence: .shape(fields: ["kind"])
                )
            }
            if element.kind != .separator, menuValidationIsBlank(element.title) {
                try add(
                    .error,
                    .invalidTitle,
                    subject: subject,
                    evidence: .title(expected: nil, observed: element.title)
                )
            }

            var invalidShapeFields: [String] = []
            switch element.kind {
            case .menu:
                if element.commandID != nil { invalidShapeFields.append("commandID") }
                if !element.shortcuts.isEmpty { invalidShapeFields.append("shortcuts") }
                if element.targetAction != nil { invalidShapeFields.append("targetAction") }
            case .command:
                if element.commandID == nil { invalidShapeFields.append("commandID") }
                if element.targetAction == nil { invalidShapeFields.append("targetAction") }
                if !element.children.isEmpty { invalidShapeFields.append("children") }
            case .separator:
                if element.title != nil { invalidShapeFields.append("title") }
                if element.commandID != nil { invalidShapeFields.append("commandID") }
                if !element.shortcuts.isEmpty { invalidShapeFields.append("shortcuts") }
                if element.targetAction != nil { invalidShapeFields.append("targetAction") }
                if !element.children.isEmpty { invalidShapeFields.append("children") }
            }
            if !invalidShapeFields.isEmpty {
                try add(
                    .error,
                    .invalidElementShape,
                    subject: subject,
                    evidence: .shape(fields: invalidShapeFields.sorted())
                )
            }

            if let commandID = element.commandID,
                !menuValidationIsValidIdentifier(commandID.rawValue)
            {
                try add(
                    .error,
                    .invalidIdentifier,
                    subject: subject,
                    evidence: .identifier(field: "element.commandID", value: commandID.rawValue)
                )
            }
            if let targetAction = element.targetAction {
                try inspectTargetAction(targetAction, subject: subject)
            }

            var shortcutCounts: [MenuShortcutDescriptor: Int] = [:]
            for shortcut in element.shortcuts {
                try budget.consume(1)
                shortcutCounts[shortcut, default: 0] += 1
                if !menuValidationIsValid(shortcut) {
                    try add(
                        .error,
                        .invalidShortcut,
                        subject: .shortcut(
                            scope: scope,
                            scenarioID: scenarioID,
                            elementID: element.id,
                            descriptor: shortcut
                        ),
                        evidence: .none
                    )
                }
                if let commandID = element.commandID {
                    let key = shortcut.canonicalChord
                    if shortcutsByChord[key] == nil {
                        shortcutsByChord[key] = (shortcut.canonicalized, [], [])
                    }
                    shortcutsByChord[key]?.1.insert(commandID)
                    shortcutsByChord[key]?.2.insert(element.id)
                }
            }
            for shortcut in try sortedShortcuts(Array(shortcutCounts.keys))
            where shortcutCounts[shortcut, default: 0] > 1 {
                try add(
                    .error,
                    .duplicateShortcut,
                    subject: .shortcut(
                        scope: scope,
                        scenarioID: scenarioID,
                        elementID: element.id,
                        descriptor: shortcut
                    ),
                    evidence: .occurrences(shortcutCounts[shortcut, default: 0])
                )
            }

            for child in element.children.reversed() {
                stack.append((child, element.id, false))
            }
        }

        for id in try sortedIdentifiers(Array(elementCounts.keys))
        where elementCounts[id, default: 0] > 1 {
            try add(
                .error,
                .duplicateElementID,
                subject: .element(scope: scope, scenarioID: scenarioID, id: id),
                evidence: .occurrences(elementCounts[id, default: 0])
            )
        }
        for id in try sortedIdentifiers(Array(commandCounts.keys))
        where commandCounts[id, default: 0] > 1 {
            try add(
                .error,
                .duplicateCommandID,
                subject: .command(scope: scope, scenarioID: scenarioID, id: id),
                evidence: .occurrences(commandCounts[id, default: 0])
            )
        }
        for key in try sortedStrings(Array(shortcutsByChord.keys)) {
            guard let (shortcut, commands, elementIDs) = shortcutsByChord[key],
                commands.count > 1
            else {
                continue
            }
            let sortedCommands = try sortedIdentifiers(Array(commands))
            guard let elementID = try sortedIdentifiers(Array(elementIDs)).first else { continue }
            try add(
                .error,
                .shortcutConflict,
                subject: .shortcut(
                    scope: scope,
                    scenarioID: scenarioID,
                    elementID: elementID,
                    descriptor: shortcut
                ),
                evidence: .shortcutConflict(
                    descriptor: shortcut,
                    commands: sortedCommands
                )
            )
        }

        return MenuValidationAnalyzedTree(
            roots: tree.roots,
            elements: elements,
            elementByID: elementByID,
            commandByID: commandByID,
            commandIDs: commandIDs
        )
    }

    private mutating func inspectTargetAction(
        _ targetAction: MenuTargetAction,
        subject: MenuValidationSubject
    ) throws {
        for (field, value) in [
            ("targetAction.targetID", targetAction.targetID.rawValue),
            ("targetAction.actionID", targetAction.actionID.rawValue)
        ] where !menuValidationIsValidIdentifier(value) {
            try add(
                .error,
                .invalidTargetAction,
                subject: subject,
                evidence: .identifier(field: field, value: value)
            )
        }
    }

    private mutating func compareTrees(
        _ expected: MenuValidationAnalyzedTree,
        _ observed: MenuValidationAnalyzedTree,
        scenarioID: MenuValidationScenarioID
    ) throws {
        let expectedRoots = expected.roots.map(\.id)
        let observedRoots = observed.roots.map(\.id)
        if expectedRoots != observedRoots {
            try add(
                .error,
                .orderMismatch,
                subject: .rootOrder(scope: .observed, scenarioID: scenarioID),
                evidence: .order(expected: expectedRoots, observed: observedRoots)
            )
        }

        for id in try sortedIdentifiers(Array(expected.elementByID.keys)) {
            guard let expectedFlat = expected.elementByID[id] else { continue }
            guard let observedFlat = observed.elementByID[id] else {
                try add(
                    .error,
                    .missingElement,
                    subject: .element(scope: .observed, scenarioID: scenarioID, id: id),
                    evidence: .element(
                        expected: try elementSummary(expectedFlat.element),
                        observed: nil
                    )
                )
                continue
            }
            let subject = MenuValidationSubject.element(
                scope: .observed,
                scenarioID: scenarioID,
                id: id
            )
            let expectedElement = expectedFlat.element
            let observedElement = observedFlat.element
            if expectedElement.kind != observedElement.kind {
                try add(
                    .error,
                    .elementKindMismatch,
                    subject: subject,
                    evidence: .elementKind(
                        expected: expectedElement.kind,
                        observed: observedElement.kind
                    )
                )
            }
            if expectedElement.title != observedElement.title {
                try add(
                    .error,
                    .titleMismatch,
                    subject: subject,
                    evidence: .title(
                        expected: expectedElement.title,
                        observed: observedElement.title
                    )
                )
            }
            if expectedElement.commandID != observedElement.commandID {
                try add(
                    .error,
                    .commandIDMismatch,
                    subject: subject,
                    evidence: .commandID(
                        expected: expectedElement.commandID,
                        observed: observedElement.commandID
                    )
                )
            }
            if expectedFlat.parentID != observedFlat.parentID {
                try add(
                    .error,
                    .hierarchyMismatch,
                    subject: subject,
                    evidence: .parent(
                        expected: expectedFlat.parentID,
                        observed: observedFlat.parentID
                    )
                )
            }
            let expectedOrder = expectedElement.children.map(\.id)
            let observedOrder = observedElement.children.map(\.id)
            if expectedOrder != observedOrder {
                try add(
                    .error,
                    .orderMismatch,
                    subject: subject,
                    evidence: .order(expected: expectedOrder, observed: observedOrder)
                )
            }
            let expectedShortcuts = try sortedShortcuts(expectedElement.shortcuts)
            let observedShortcuts = try sortedShortcuts(observedElement.shortcuts)
            if expectedShortcuts != observedShortcuts {
                try add(
                    .error,
                    .shortcutMismatch,
                    subject: subject,
                    evidence: .shortcuts(
                        expected: expectedShortcuts,
                        observed: observedShortcuts
                    )
                )
            }
            if expectedElement.targetAction != observedElement.targetAction {
                try add(
                    .error,
                    .targetActionMismatch,
                    subject: subject,
                    evidence: .targetAction(
                        expected: expectedElement.targetAction,
                        observed: observedElement.targetAction
                    )
                )
            }
        }

        for id in try sortedIdentifiers(Array(observed.elementByID.keys))
        where expected.elementByID[id] == nil {
            guard let observedFlat = observed.elementByID[id] else { continue }
            try add(
                .error,
                .unexpectedElement,
                subject: .element(scope: .observed, scenarioID: scenarioID, id: id),
                evidence: .element(
                    expected: nil,
                    observed: try elementSummary(observedFlat.element)
                )
            )
        }
    }

    private mutating func compareScenario(
        _ expected: MenuValidationScenario,
        _ observed: MenuValidationObservedScenario,
        expectedTree: MenuValidationAnalyzedTree,
        observedTree: MenuValidationAnalyzedTree
    ) throws {
        let expectedStates = try stateMap(
            expected.states,
            scope: .contract,
            scenarioID: expected.id,
            knownCommands: expectedTree.commandIDs
        )
        let observedStates = try stateMap(
            observed.states,
            scope: .observed,
            scenarioID: observed.id,
            knownCommands: observedTree.commandIDs
        )

        for commandID in try sortedIdentifiers(Array(expectedStates.keys)) {
            guard let expectedState = expectedStates[commandID] else { continue }
            guard let observedState = observedStates[commandID] else {
                try add(
                    .error,
                    .missingState,
                    subject: .command(scope: .observed, scenarioID: observed.id, id: commandID),
                    evidence: .state(expected: expectedState, observed: nil)
                )
                continue
            }
            let subject = MenuValidationSubject.command(
                scope: .observed,
                scenarioID: observed.id,
                id: commandID
            )
            if expectedState.checkedState != observedState.checkedState {
                try add(
                    .error,
                    .checkedStateMismatch,
                    subject: subject,
                    evidence: .checkedState(
                        expected: expectedState.checkedState,
                        observed: observedState.checkedState
                    )
                )
            }
            if expectedState.isEnabled != observedState.isEnabled {
                try add(
                    .error,
                    .enabledStateMismatch,
                    subject: subject,
                    evidence: .enabledState(
                        expected: expectedState.isEnabled,
                        observed: observedState.isEnabled
                    )
                )
            }
        }
        for commandID in try sortedIdentifiers(Array(observedStates.keys))
        where expectedStates[commandID] == nil {
            try add(
                .error,
                .unexpectedState,
                subject: .command(scope: .observed, scenarioID: observed.id, id: commandID),
                evidence: .state(expected: nil, observed: observedStates[commandID])
            )
        }

        let expectedInvocations = try expectationMap(
            expected.invocations,
            scenario: expected,
            tree: expectedTree,
            states: expectedStates
        )
        let observedInvocations = try evidenceMap(
            observed.invocations,
            scenario: observed,
            tree: observedTree,
            states: observedStates
        )
        for key in try sortedInvocationKeys(Array(expectedInvocations.keys)) {
            guard let expectation = expectedInvocations[key] else { continue }
            guard let actual = observedInvocations[key] else {
                try add(
                    .error,
                    .missingInvocation,
                    subject: .invocation(
                        scope: .observed,
                        scenarioID: observed.id,
                        commandID: key.commandID,
                        source: key.source
                    ),
                    evidence: .invocation(expected: expectation, observed: nil)
                )
                continue
            }
            let subject = MenuValidationSubject.invocation(
                scope: .observed,
                scenarioID: observed.id,
                commandID: key.commandID,
                source: key.source
            )
            if expectation.targetAction != actual.targetAction {
                try add(
                    .error,
                    .invocationTargetMismatch,
                    subject: subject,
                    evidence: .targetAction(
                        expected: expectation.targetAction,
                        observed: actual.targetAction
                    )
                )
            }
            if expectation.result != actual.result {
                try add(
                    .error,
                    .resultMismatch,
                    subject: subject,
                    evidence: .result(expected: expectation.result, observed: actual.result)
                )
            }
        }
        for key in try sortedInvocationKeys(Array(observedInvocations.keys))
        where expectedInvocations[key] == nil {
            try add(
                .error,
                .unexpectedInvocation,
                subject: .invocation(
                    scope: .observed,
                    scenarioID: observed.id,
                    commandID: key.commandID,
                    source: key.source
                ),
                evidence: .invocation(expected: nil, observed: observedInvocations[key])
            )
        }
    }

    private mutating func inspectExpectedScenario(
        _ scenario: MenuValidationScenario,
        tree: MenuValidationAnalyzedTree
    ) throws {
        let states = try stateMap(
            scenario.states,
            scope: .contract,
            scenarioID: scenario.id,
            knownCommands: tree.commandIDs
        )
        _ = try expectationMap(
            scenario.invocations,
            scenario: scenario,
            tree: tree,
            states: states
        )
    }

    private mutating func inspectObservedScenario(
        _ scenario: MenuValidationObservedScenario,
        tree: MenuValidationAnalyzedTree
    ) throws {
        let states = try stateMap(
            scenario.states,
            scope: .observed,
            scenarioID: scenario.id,
            knownCommands: tree.commandIDs
        )
        _ = try evidenceMap(
            scenario.invocations,
            scenario: scenario,
            tree: tree,
            states: states
        )
    }

    private mutating func stateMap(
        _ states: [MenuCommandDynamicState],
        scope: MenuValidationEvidenceScope,
        scenarioID: MenuValidationScenarioID,
        knownCommands: Set<MenuCommandID>
    ) throws -> [MenuCommandID: MenuCommandDynamicState] {
        var counts: [MenuCommandID: Int] = [:]
        var result: [MenuCommandID: MenuCommandDynamicState] = [:]
        for state in states {
            try budget.consume(1)
            counts[state.commandID, default: 0] += 1
            if result[state.commandID] == nil { result[state.commandID] = state }
            let subject = MenuValidationSubject.command(
                scope: scope,
                scenarioID: scenarioID,
                id: state.commandID
            )
            if !menuValidationIsValidIdentifier(state.commandID.rawValue) {
                try add(
                    .error,
                    .invalidIdentifier,
                    subject: subject,
                    evidence: .identifier(
                        field: "state.commandID",
                        value: state.commandID.rawValue
                    )
                )
            }
            if !knownCommands.contains(state.commandID) {
                try add(
                    .error,
                    .stateTargetsUnknownCommand,
                    subject: subject,
                    evidence: .state(
                        expected: scope == .contract ? state : nil,
                        observed: scope == .observed ? state : nil
                    )
                )
            }
        }
        for id in try sortedIdentifiers(Array(counts.keys)) where counts[id, default: 0] > 1 {
            try add(
                .error,
                .duplicateState,
                subject: .command(scope: scope, scenarioID: scenarioID, id: id),
                evidence: .occurrences(counts[id, default: 0])
            )
        }
        return result
    }

    private mutating func expectationMap(
        _ invocations: [MenuInvocationExpectation],
        scenario: MenuValidationScenario,
        tree: MenuValidationAnalyzedTree,
        states: [MenuCommandID: MenuCommandDynamicState]
    ) throws -> [MenuValidationInvocationKey: MenuInvocationExpectation] {
        var counts: [MenuValidationInvocationKey: Int] = [:]
        var result: [MenuValidationInvocationKey: MenuInvocationExpectation] = [:]
        for invocation in invocations {
            try budget.consume(1)
            let key = MenuValidationInvocationKey(
                commandID: invocation.commandID,
                source: invocation.source
            )
            counts[key, default: 0] += 1
            if result[key] == nil { result[key] = invocation }
            let subject = MenuValidationSubject.invocation(
                scope: .contract,
                scenarioID: scenario.id,
                commandID: invocation.commandID,
                source: invocation.source
            )
            try inspectInvocation(
                commandID: invocation.commandID,
                targetAction: invocation.targetAction,
                result: invocation.result,
                subject: subject,
                tree: tree,
                state: states[invocation.commandID]
            )
        }
        for key in try sortedInvocationKeys(Array(counts.keys)) where counts[key, default: 0] > 1 {
            try add(
                .error,
                .duplicateInvocation,
                subject: .invocation(
                    scope: .contract,
                    scenarioID: scenario.id,
                    commandID: key.commandID,
                    source: key.source
                ),
                evidence: .occurrences(counts[key, default: 0])
            )
        }
        return result
    }

    private mutating func evidenceMap(
        _ invocations: [MenuInvocationEvidence],
        scenario: MenuValidationObservedScenario,
        tree: MenuValidationAnalyzedTree,
        states: [MenuCommandID: MenuCommandDynamicState]
    ) throws -> [MenuValidationInvocationKey: MenuInvocationEvidence] {
        var counts: [MenuValidationInvocationKey: Int] = [:]
        var result: [MenuValidationInvocationKey: MenuInvocationEvidence] = [:]
        for invocation in invocations {
            try budget.consume(1)
            let key = MenuValidationInvocationKey(
                commandID: invocation.commandID,
                source: invocation.source
            )
            counts[key, default: 0] += 1
            if result[key] == nil { result[key] = invocation }
            let subject = MenuValidationSubject.invocation(
                scope: .observed,
                scenarioID: scenario.id,
                commandID: invocation.commandID,
                source: invocation.source
            )
            try inspectInvocation(
                commandID: invocation.commandID,
                targetAction: invocation.targetAction,
                result: invocation.result,
                subject: subject,
                tree: tree,
                state: states[invocation.commandID]
            )
        }
        for key in try sortedInvocationKeys(Array(counts.keys)) where counts[key, default: 0] > 1 {
            try add(
                .error,
                .duplicateInvocation,
                subject: .invocation(
                    scope: .observed,
                    scenarioID: scenario.id,
                    commandID: key.commandID,
                    source: key.source
                ),
                evidence: .occurrences(counts[key, default: 0])
            )
        }
        return result
    }

    private mutating func inspectInvocation(
        commandID: MenuCommandID,
        targetAction: MenuTargetAction?,
        result: MenuCommandResult,
        subject: MenuValidationSubject,
        tree: MenuValidationAnalyzedTree,
        state: MenuCommandDynamicState?
    ) throws {
        if !menuValidationIsValidIdentifier(commandID.rawValue) {
            try add(
                .error,
                .invalidIdentifier,
                subject: subject,
                evidence: .identifier(
                    field: "invocation.commandID",
                    value: commandID.rawValue
                )
            )
        }
        if let targetAction {
            try inspectTargetAction(targetAction, subject: subject)
        }
        if let resultID = menuValidationResultID(result),
            !menuValidationIsValidIdentifier(resultID.rawValue)
        {
            try add(
                .error,
                .invalidResult,
                subject: subject,
                evidence: .identifier(field: "invocation.result", value: resultID.rawValue)
            )
        }
        let isNotInvoked = result == .notInvoked
        if isNotInvoked, tree.commandByID[commandID] == nil || state?.isEnabled != false {
            try add(
                .error,
                .invalidInvocation,
                subject: subject,
                evidence: .enabledState(
                    expected: false,
                    observed: state?.isEnabled ?? true
                )
            )
        }
        let command = tree.commandByID[commandID]
        if isNotInvoked != (targetAction == nil) {
            try add(
                .error,
                .invalidInvocation,
                subject: subject,
                evidence: .targetAction(
                    expected: isNotInvoked ? nil : command?.element.targetAction,
                    observed: targetAction
                )
            )
        }
        guard let command else {
            try add(
                .error,
                .invocationTargetsUnknownCommand,
                subject: subject,
                evidence: .none
            )
            return
        }
        if targetAction != nil, targetAction != command.element.targetAction {
            try add(
                .error,
                .invocationTargetConflict,
                subject: subject,
                evidence: .targetAction(
                    expected: command.element.targetAction,
                    observed: targetAction
                )
            )
        }
        if state?.isEnabled == false, !isNotInvoked {
            try add(
                .error,
                .invocationStateConflict,
                subject: subject,
                evidence: .enabledState(expected: false, observed: true)
            )
        }
    }

    private mutating func sortedIdentifiers<Domain>(
        _ values: [MenuValidationIdentifier<Domain>]
    ) throws -> [MenuValidationIdentifier<Domain>] {
        try menuValidationStableSorted(values, budget: &budget) { left, right, budget in
            try menuValidationCompareUTF8(
                left.rawValue,
                right.rawValue,
                budget: &budget
            ) < 0
        }
    }

    private mutating func sortedStrings(_ values: [String]) throws -> [String] {
        try menuValidationStableSorted(values, budget: &budget) { left, right, budget in
            try menuValidationCompareUTF8(left, right, budget: &budget) < 0
        }
    }

    private mutating func sortedShortcuts(
        _ values: [MenuShortcutDescriptor]
    ) throws -> [MenuShortcutDescriptor] {
        let keyed = values.map { (shortcut: $0, key: $0.sortKey) }
        return try menuValidationStableSorted(keyed, budget: &budget) { left, right, budget in
            try menuValidationCompareUTF8(left.key, right.key, budget: &budget) < 0
        }.map(\.shortcut)
    }

    private mutating func sortedInvocationKeys(
        _ values: [MenuValidationInvocationKey]
    ) throws -> [MenuValidationInvocationKey] {
        try menuValidationStableSorted(values, budget: &budget) { left, right, budget in
            let commandOrder = try menuValidationCompareUTF8(
                left.commandID.rawValue,
                right.commandID.rawValue,
                budget: &budget
            )
            if commandOrder != 0 { return commandOrder < 0 }
            try budget.consume(1)
            return left.source.rank < right.source.rank
        }
    }

    private mutating func elementSummary(
        _ element: MenuValidationElement
    ) throws -> MenuValidationElementSummary {
        MenuValidationElementSummary(
            element,
            sortedShortcuts: try sortedShortcuts(element.shortcuts)
        )
    }

    private mutating func comparisonKey(
        for scenario: MenuValidationScenario
    ) throws -> String {
        var key = ""
        try appendComparisonComponent("scenario", to: &key)
        try appendComparisonComponent(scenario.id.rawValue, to: &key)
        try appendComparisonComponent(String(scenario.states.count), to: &key)
        for state in scenario.states {
            try appendComparisonState(state, to: &key)
        }
        try appendComparisonComponent(String(scenario.invocations.count), to: &key)
        for invocation in scenario.invocations {
            try appendComparisonInvocation(
                commandID: invocation.commandID,
                source: invocation.source,
                targetAction: invocation.targetAction,
                result: invocation.result,
                to: &key
            )
        }
        return key
    }

    private mutating func comparisonKey(
        for scenario: MenuValidationObservedScenario
    ) throws -> String {
        var key = ""
        try appendComparisonComponent("observedScenario", to: &key)
        try appendComparisonComponent(scenario.id.rawValue, to: &key)
        try appendComparisonTree(scenario.tree, to: &key)
        try appendComparisonComponent(String(scenario.states.count), to: &key)
        for state in scenario.states {
            try appendComparisonState(state, to: &key)
        }
        try appendComparisonComponent(String(scenario.invocations.count), to: &key)
        for invocation in scenario.invocations {
            try appendComparisonInvocation(
                commandID: invocation.commandID,
                source: invocation.source,
                targetAction: invocation.targetAction,
                result: invocation.result,
                to: &key
            )
        }
        return key
    }

    private mutating func appendComparisonTree(
        _ tree: MenuValidationTree,
        to key: inout String
    ) throws {
        try appendComparisonComponent(String(tree.roots.count), to: &key)
        var stack: [MenuValidationElement] = []
        stack.reserveCapacity(tree.roots.count)
        for root in tree.roots.reversed() {
            try budget.consume(1)
            stack.append(root)
        }
        while let element = stack.popLast() {
            try appendComparisonComponent("element", to: &key)
            try appendComparisonComponent(element.id.rawValue, to: &key)
            try appendComparisonComponent(element.kind.rawValue, to: &key)
            try appendComparisonOptional(element.title, to: &key)
            try appendComparisonOptional(element.commandID?.rawValue, to: &key)
            try appendComparisonComponent(String(element.shortcuts.count), to: &key)
            for shortcut in element.shortcuts {
                try appendComparisonComponent(shortcut.platform.rawValue, to: &key)
                try appendComparisonComponent(shortcut.key.rawValue, to: &key)
                let modifiers = shortcut.modifiers.sorted()
                try appendComparisonComponent(String(modifiers.count), to: &key)
                for modifier in modifiers {
                    try appendComparisonComponent(modifier.rawValue, to: &key)
                }
            }
            try appendComparisonTargetAction(element.targetAction, to: &key)
            try appendComparisonComponent(String(element.children.count), to: &key)
            for child in element.children.reversed() {
                try budget.consume(1)
                stack.append(child)
            }
        }
    }

    private mutating func appendComparisonState(
        _ state: MenuCommandDynamicState,
        to key: inout String
    ) throws {
        try appendComparisonComponent("state", to: &key)
        try appendComparisonComponent(state.commandID.rawValue, to: &key)
        try appendComparisonComponent(String(state.isEnabled), to: &key)
        try appendComparisonComponent(state.checkedState.rawValue, to: &key)
    }

    private mutating func appendComparisonInvocation(
        commandID: MenuCommandID,
        source: MenuInvocationSource,
        targetAction: MenuTargetAction?,
        result: MenuCommandResult,
        to key: inout String
    ) throws {
        try appendComparisonComponent("invocation", to: &key)
        try appendComparisonComponent(commandID.rawValue, to: &key)
        try appendComparisonComponent(source.rawValue, to: &key)
        try appendComparisonTargetAction(targetAction, to: &key)
        for component in result.menuValidationIdentityComponents {
            try appendComparisonComponent(component, to: &key)
        }
    }

    private mutating func appendComparisonTargetAction(
        _ targetAction: MenuTargetAction?,
        to key: inout String
    ) throws {
        guard let targetAction else {
            try appendComparisonComponent("none", to: &key)
            return
        }
        try appendComparisonComponent("some", to: &key)
        try appendComparisonComponent(targetAction.targetID.rawValue, to: &key)
        try appendComparisonComponent(targetAction.actionID.rawValue, to: &key)
    }

    private mutating func appendComparisonOptional(
        _ value: String?,
        to key: inout String
    ) throws {
        guard let value else {
            try appendComparisonComponent("none", to: &key)
            return
        }
        try appendComparisonComponent("some", to: &key)
        try appendComparisonComponent(value, to: &key)
    }

    private mutating func appendComparisonComponent(
        _ component: String,
        to key: inout String
    ) throws {
        let framed = menuValidationFrame(component)
        try budget.consume(framed.utf8.count + 1)
        key.append(framed)
    }

    private mutating func add(
        _ severity: MenuValidationSeverity,
        _ code: MenuValidationFindingCode,
        subject: MenuValidationSubject,
        evidence: MenuValidationFindingEvidence
    ) throws {
        let finding = MenuValidationFinding(
            severity: severity,
            code: code,
            subject: subject,
            evidence: evidence
        )
        try budget.consume(finding.id.rawValue.utf8.count + 1)
        guard findingIDs.insert(finding.id).inserted else { return }
        guard findings.count < limits.maximumFindings else {
            throw MenuValidationError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        findings.append(finding)
    }
}

private enum MenuValidationPreflight {
    static func validate(_ limits: MenuValidationLimits) throws {
        try validate(limits.maximumElements, name: "maximumElements", minimum: 0, maximum: MenuValidationLimits.hardMaximumElements)
        try validate(limits.maximumTotalElements, name: "maximumTotalElements", minimum: 0, maximum: MenuValidationLimits.hardMaximumTotalElements)
        try validate(limits.maximumDepth, name: "maximumDepth", minimum: 1, maximum: MenuValidationLimits.hardMaximumDepth)
        try validate(limits.maximumScenarios, name: "maximumScenarios", minimum: 0, maximum: MenuValidationLimits.hardMaximumScenarios)
        try validate(limits.maximumStatesPerScenario, name: "maximumStatesPerScenario", minimum: 0, maximum: MenuValidationLimits.hardMaximumStatesPerScenario)
        try validate(
            limits.maximumInvocationsPerScenario, name: "maximumInvocationsPerScenario", minimum: 0,
            maximum: MenuValidationLimits.hardMaximumInvocationsPerScenario)
        try validate(
            limits.maximumShortcutsPerElement, name: "maximumShortcutsPerElement", minimum: 0, maximum: MenuValidationLimits.hardMaximumShortcutsPerElement)
        try validate(limits.maximumStringUTF8Bytes, name: "maximumStringUTF8Bytes", minimum: 0, maximum: MenuValidationLimits.hardMaximumStringUTF8Bytes)
        try validate(
            limits.maximumTotalStringUTF8Bytes, name: "maximumTotalStringUTF8Bytes", minimum: 0, maximum: MenuValidationLimits.hardMaximumTotalStringUTF8Bytes)
        try validate(limits.maximumWorkUnits, name: "maximumWorkUnits", minimum: 1, maximum: MenuValidationLimits.hardMaximumWorkUnits)
        try validate(limits.maximumFindings, name: "maximumFindings", minimum: 0, maximum: MenuValidationLimits.hardMaximumFindings)
        try validate(
            limits.cancellationCheckInterval, name: "cancellationCheckInterval", minimum: 1, maximum: MenuValidationLimits.hardMaximumCancellationCheckInterval)
    }

    static func inspect(
        contract: MenuValidationContract,
        evidence: MenuValidationEvidence,
        limits: MenuValidationLimits,
        budget: inout MenuValidationWorkBudget
    ) throws {
        guard contract.scenarios.count <= limits.maximumScenarios,
            evidence.scenarios.count <= limits.maximumScenarios
        else {
            throw MenuValidationError.countLimitExceeded(
                kind: .scenarios,
                maximum: limits.maximumScenarios
            )
        }
        var totalStringBytes = 0
        var totalElements = 0
        try consume(
            contract.id.rawValue,
            field: "contract.id",
            limits: limits,
            total: &totalStringBytes,
            budget: &budget
        )
        try inspectTree(
            contract.tree,
            field: "contract.tree",
            limits: limits,
            totalElements: &totalElements,
            totalStringBytes: &totalStringBytes,
            budget: &budget
        )
        for scenario in contract.scenarios {
            try inspectScenarioCounts(
                states: scenario.states.count,
                invocations: scenario.invocations.count,
                limits: limits
            )
            try consume(scenario.id.rawValue, field: "contract.scenario.id", limits: limits, total: &totalStringBytes, budget: &budget)
            for state in scenario.states {
                try consume(state.commandID.rawValue, field: "contract.state.commandID", limits: limits, total: &totalStringBytes, budget: &budget)
            }
            for invocation in scenario.invocations {
                try inspectInvocation(
                    invocation.commandID, invocation.targetAction, invocation.result, field: "contract.invocation", limits: limits, total: &totalStringBytes,
                    budget: &budget)
            }
        }
        for scenario in evidence.scenarios {
            try inspectScenarioCounts(
                states: scenario.states.count,
                invocations: scenario.invocations.count,
                limits: limits
            )
            try consume(scenario.id.rawValue, field: "evidence.scenario.id", limits: limits, total: &totalStringBytes, budget: &budget)
            try inspectTree(
                scenario.tree,
                field: "evidence.tree",
                limits: limits,
                totalElements: &totalElements,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            for state in scenario.states {
                try consume(state.commandID.rawValue, field: "evidence.state.commandID", limits: limits, total: &totalStringBytes, budget: &budget)
            }
            for invocation in scenario.invocations {
                try inspectInvocation(
                    invocation.commandID, invocation.targetAction, invocation.result, field: "evidence.invocation", limits: limits, total: &totalStringBytes,
                    budget: &budget)
            }
        }
    }

    private static func inspectScenarioCounts(
        states: Int,
        invocations: Int,
        limits: MenuValidationLimits
    ) throws {
        guard states <= limits.maximumStatesPerScenario else {
            throw MenuValidationError.countLimitExceeded(
                kind: .states,
                maximum: limits.maximumStatesPerScenario
            )
        }
        guard invocations <= limits.maximumInvocationsPerScenario else {
            throw MenuValidationError.countLimitExceeded(
                kind: .invocations,
                maximum: limits.maximumInvocationsPerScenario
            )
        }
    }

    private static func inspectTree(
        _ tree: MenuValidationTree,
        field: String,
        limits: MenuValidationLimits,
        totalElements: inout Int,
        totalStringBytes: inout Int,
        budget: inout MenuValidationWorkBudget
    ) throws {
        guard tree.roots.count <= limits.maximumElements else {
            throw MenuValidationError.countLimitExceeded(
                kind: .elements,
                maximum: limits.maximumElements
            )
        }
        guard tree.roots.count <= limits.maximumTotalElements - totalElements else {
            throw MenuValidationError.countLimitExceeded(
                kind: .totalElements,
                maximum: limits.maximumTotalElements
            )
        }
        var stack: [(MenuValidationElement, Int)] = []
        stack.reserveCapacity(tree.roots.count)
        for root in tree.roots.reversed() { stack.append((root, 1)) }
        var treeElements = tree.roots.count
        totalElements += tree.roots.count
        while let (element, depth) = stack.popLast() {
            try budget.consume(1)
            guard depth <= limits.maximumDepth else {
                throw MenuValidationError.countLimitExceeded(
                    kind: .depth,
                    maximum: limits.maximumDepth
                )
            }
            guard element.children.count <= limits.maximumElements - treeElements else {
                throw MenuValidationError.countLimitExceeded(
                    kind: .elements,
                    maximum: limits.maximumElements
                )
            }
            guard element.children.count <= limits.maximumTotalElements - totalElements else {
                throw MenuValidationError.countLimitExceeded(
                    kind: .totalElements,
                    maximum: limits.maximumTotalElements
                )
            }
            treeElements += element.children.count
            totalElements += element.children.count
            guard element.shortcuts.count <= limits.maximumShortcutsPerElement else {
                throw MenuValidationError.countLimitExceeded(
                    kind: .shortcuts,
                    maximum: limits.maximumShortcutsPerElement
                )
            }
            try consume(element.id.rawValue, field: field + ".element.id", limits: limits, total: &totalStringBytes, budget: &budget)
            if let title = element.title {
                try consume(title, field: field + ".element.title", limits: limits, total: &totalStringBytes, budget: &budget)
            }
            if let commandID = element.commandID {
                try consume(commandID.rawValue, field: field + ".element.commandID", limits: limits, total: &totalStringBytes, budget: &budget)
            }
            for shortcut in element.shortcuts {
                try consume(shortcut.key.rawValue, field: field + ".shortcut.key", limits: limits, total: &totalStringBytes, budget: &budget)
            }
            if let targetAction = element.targetAction {
                try inspectTargetAction(targetAction, field: field + ".targetAction", limits: limits, total: &totalStringBytes, budget: &budget)
            }
            for child in element.children.reversed() { stack.append((child, depth + 1)) }
        }
    }

    private static func inspectInvocation(
        _ commandID: MenuCommandID,
        _ targetAction: MenuTargetAction?,
        _ result: MenuCommandResult,
        field: String,
        limits: MenuValidationLimits,
        total: inout Int,
        budget: inout MenuValidationWorkBudget
    ) throws {
        try consume(commandID.rawValue, field: field + ".commandID", limits: limits, total: &total, budget: &budget)
        if let targetAction {
            try inspectTargetAction(targetAction, field: field + ".targetAction", limits: limits, total: &total, budget: &budget)
        }
        if let resultID = menuValidationResultID(result) {
            try consume(resultID.rawValue, field: field + ".result", limits: limits, total: &total, budget: &budget)
        }
    }

    private static func inspectTargetAction(
        _ targetAction: MenuTargetAction,
        field: String,
        limits: MenuValidationLimits,
        total: inout Int,
        budget: inout MenuValidationWorkBudget
    ) throws {
        try consume(targetAction.targetID.rawValue, field: field + ".targetID", limits: limits, total: &total, budget: &budget)
        try consume(targetAction.actionID.rawValue, field: field + ".actionID", limits: limits, total: &total, budget: &budget)
    }

    private static func consume(
        _ value: String,
        field: String,
        limits: MenuValidationLimits,
        total: inout Int,
        budget: inout MenuValidationWorkBudget
    ) throws {
        var count = 0
        for _ in value.utf8 {
            if count == limits.maximumStringUTF8Bytes {
                throw MenuValidationError.stringTooLarge(
                    field: field,
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            if total == limits.maximumTotalStringUTF8Bytes - count {
                throw MenuValidationError.totalStringsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
                )
            }
            count += 1
        }
        total += count
        try budget.consume(count + 1)
    }

    private static func validate(
        _ value: Int,
        name: String,
        minimum: Int,
        maximum: Int
    ) throws {
        guard (minimum...maximum).contains(value) else {
            throw MenuValidationError.invalidLimit(
                name: name,
                value: value,
                minimum: minimum,
                maximum: maximum
            )
        }
    }
}

private struct MenuValidationWorkBudget {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: MenuValidationAudit.CancellationCheck
    private(set) var consumed = 0

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximum - consumed else {
            throw MenuValidationError.workLimitExceeded(maximum: maximum)
        }
        let oldCheckpoint = consumed / cancellationCheckInterval
        consumed += amount
        let newCheckpoint = consumed / cancellationCheckInterval
        if newCheckpoint > oldCheckpoint {
            try checkCancellation()
        }
    }

    func checkCancellation() throws {
        if cancellationCheck() { throw MenuValidationError.cancelled }
    }
}

private func menuValidationIsValidIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value == value.precomposedStringWithCanonicalMapping else {
        return false
    }
    for scalar in value.unicodeScalars {
        if scalar.properties.isWhitespace || scalar.value <= 0x1F
            || (0x7F...0x9F).contains(scalar.value)
            || scalar.properties.generalCategory == .format
            || scalar.properties.isNoncharacterCodePoint
        {
            return false
        }
    }
    return true
}

private func menuValidationIsBlank(_ value: String?) -> Bool {
    guard let value else { return true }
    return value.unicodeScalars.allSatisfy {
        $0.properties.isWhitespace || $0.value <= 0x1F
            || (0x7F...0x9F).contains($0.value)
            || $0.properties.generalCategory == .format
            || $0.properties.isNoncharacterCodePoint
    }
}

private func menuValidationIsValid(_ shortcut: MenuShortcutDescriptor) -> Bool {
    guard shortcut.key.rawValue == shortcut.key.canonical.rawValue,
        menuValidationIsValidShortcutKey(shortcut.key.rawValue)
    else {
        return false
    }
    let allowed: Set<MenuShortcutModifier>
    switch shortcut.platform {
    case .macOS:
        allowed = [.command, .control, .option, .shift, .function]
    case .windows, .linux:
        allowed = [.control, .shift, .alt, .superKey]
    }
    guard shortcut.modifiers.isSubset(of: allowed) else { return false }
    return !shortcut.modifiers.isEmpty || !menuValidationIsPrintableShortcutKey(shortcut.key.rawValue)
}

private func menuValidationIsValidShortcutKey(_ value: String) -> Bool {
    if menuValidationIsPrintableShortcutKey(value) { return true }
    switch value {
    case "backspace", "delete", "down", "end", "escape", "home", "left", "pagedown",
        "pageup", "return", "right", "space", "tab", "up":
        return true
    default:
        guard value.count >= 2, value.count <= 3, value.first == "f",
            let number = Int(value.dropFirst())
        else {
            return false
        }
        return (1...24).contains(number) && value == "f\(number)"
    }
}

private func menuValidationIsPrintableShortcutKey(_ value: String) -> Bool {
    guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first else {
        return false
    }
    return scalar.value >= 0x21 && scalar.value <= 0x7E
}

private func menuValidationResultID(_ result: MenuCommandResult) -> MenuValidationResultID? {
    switch result {
    case .completed(let id), .rejected(let id), .failed(let id): id
    case .notInvoked: nil
    }
}

private func menuValidationStableSorted<Value>(
    _ values: [Value],
    budget: inout MenuValidationWorkBudget,
    by areInIncreasingOrder: (Value, Value, inout MenuValidationWorkBudget) throws -> Bool
) throws -> [Value] {
    guard values.count > 1 else { return values }
    var source = values
    var width = 1
    while width < source.count {
        var destination: [Value] = []
        destination.reserveCapacity(source.count)
        var start = 0
        while start < source.count {
            let middle = min(start + width, source.count)
            let end = min(middle + width, source.count)
            var left = start
            var right = middle
            while left < middle, right < end {
                if try areInIncreasingOrder(source[right], source[left], &budget) {
                    try budget.consume(1)
                    destination.append(source[right])
                    right += 1
                } else {
                    try budget.consume(1)
                    destination.append(source[left])
                    left += 1
                }
            }
            while left < middle {
                try budget.consume(1)
                destination.append(source[left])
                left += 1
            }
            while right < end {
                try budget.consume(1)
                destination.append(source[right])
                right += 1
            }
            start = end
        }
        source = destination
        if width > source.count / 2 { break }
        width *= 2
    }
    return source
}

private func menuValidationCompareUTF8(
    _ left: String,
    _ right: String,
    budget: inout MenuValidationWorkBudget
) throws -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        try budget.consume(1)
        switch (leftIterator.next(), rightIterator.next()) {
        case (.none, .none): return 0
        case (.none, .some): return -1
        case (.some, .none): return 1
        case (.some(let leftByte), .some(let rightByte)):
            if leftByte < rightByte { return -1 }
            if leftByte > rightByte { return 1 }
        }
    }
}

private func menuValidationFrame(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
}

private func menuValidationOptional(_ value: String?) -> [String] {
    value.map { ["some", $0] } ?? ["none"]
}

private func menuValidationCompareUTF8(_ left: String, _ right: String) -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        switch (leftIterator.next(), rightIterator.next()) {
        case (.none, .none): return 0
        case (.none, .some): return -1
        case (.some, .none): return 1
        case (.some(let leftByte), .some(let rightByte)):
            if leftByte < rightByte { return -1 }
            if leftByte > rightByte { return 1 }
        }
    }
}

extension MenuValidationSubject {
    fileprivate var menuValidationIdentityComponents: [String] {
        switch self {
        case .contract(let id):
            return ["contract", id.rawValue]
        case .scenario(let scope, let id):
            return ["scenario", scope.rawValue, id.rawValue]
        case .element(let scope, let scenarioID, let id):
            return ["element", scope.rawValue]
                + menuValidationOptional(scenarioID?.rawValue) + [id.rawValue]
        case .command(let scope, let scenarioID, let id):
            return ["command", scope.rawValue]
                + menuValidationOptional(scenarioID?.rawValue) + [id.rawValue]
        case .invocation(let scope, let scenarioID, let commandID, let source):
            return [
                "invocation", scope.rawValue, scenarioID.rawValue, commandID.rawValue,
                source.rawValue
            ]
        case .rootOrder(let scope, let scenarioID):
            return ["rootOrder", scope.rawValue]
                + menuValidationOptional(scenarioID?.rawValue)
        case .shortcut(let scope, let scenarioID, let elementID, let descriptor):
            return ["shortcut", scope.rawValue]
                + menuValidationOptional(scenarioID?.rawValue)
                + [elementID.rawValue] + descriptor.menuValidationIdentityComponents
        }
    }
}

extension MenuValidationFindingEvidence {
    fileprivate var menuValidationIdentityComponents: [String] {
        switch self {
        case .none:
            return ["none"]
        case .identifier(let field, let value):
            return ["identifier", field, value]
        case .occurrences(let count):
            return ["occurrences", String(count)]
        case .shape(let fields):
            return ["shape"] + fields
        case .element(let expected, let observed):
            return ["element"] + expected.menuValidationIdentityComponents
                + observed.menuValidationIdentityComponents
        case .elementKind(let expected, let observed):
            return ["elementKind", expected.rawValue, observed.rawValue]
        case .title(let expected, let observed):
            return ["title"] + menuValidationOptional(expected)
                + menuValidationOptional(observed)
        case .commandID(let expected, let observed):
            return ["commandID"] + menuValidationOptional(expected?.rawValue)
                + menuValidationOptional(observed?.rawValue)
        case .parent(let expected, let observed):
            return ["parent"] + menuValidationOptional(expected?.rawValue)
                + menuValidationOptional(observed?.rawValue)
        case .order(let expected, let observed):
            return ["order", "expected"] + expected.map(\.rawValue)
                + ["observed"] + observed.map(\.rawValue)
        case .shortcuts(let expected, let observed):
            return ["shortcuts", "expected"]
                + expected.flatMap(\.menuValidationIdentityComponents)
                + ["observed"] + observed.flatMap(\.menuValidationIdentityComponents)
        case .shortcutConflict(let descriptor, let commands):
            return ["shortcutConflict"] + descriptor.menuValidationIdentityComponents
                + commands.map(\.rawValue)
        case .state(let expected, let observed):
            return ["state"] + expected.menuValidationIdentityComponents
                + observed.menuValidationIdentityComponents
        case .checkedState(let expected, let observed):
            return ["checkedState", expected.rawValue, observed.rawValue]
        case .enabledState(let expected, let observed):
            return ["enabledState", String(expected), String(observed)]
        case .targetAction(let expected, let observed):
            return ["targetAction"] + expected.menuValidationIdentityComponents
                + observed.menuValidationIdentityComponents
        case .invocation(let expected, let observed):
            return ["invocation"] + expected.menuValidationIdentityComponents
                + observed.menuValidationIdentityComponents
        case .result(let expected, let observed):
            return ["result"] + expected.menuValidationIdentityComponents
                + observed.menuValidationIdentityComponents
        }
    }
}

extension MenuShortcutDescriptor {
    fileprivate var menuValidationIdentityComponents: [String] {
        [platform.rawValue, key.rawValue] + modifiers.sorted().map(\.rawValue)
    }
}

extension MenuValidationElementSummary? {
    fileprivate var menuValidationIdentityComponents: [String] {
        guard let value = self else { return ["none"] }
        var components = ["some", value.id.rawValue, value.kind.rawValue]
        components += menuValidationOptional(value.title)
        components += menuValidationOptional(value.commandID?.rawValue)
        components += value.shortcuts.flatMap(\.menuValidationIdentityComponents)
        components += value.targetAction.menuValidationIdentityComponents
        components += value.childIDs.map(\.rawValue)
        return components
    }
}

extension MenuCommandDynamicState? {
    fileprivate var menuValidationIdentityComponents: [String] {
        guard let value = self else { return ["none"] }
        return [
            "some", value.commandID.rawValue, String(value.isEnabled), value.checkedState.rawValue
        ]
    }
}

extension MenuTargetAction? {
    fileprivate var menuValidationIdentityComponents: [String] {
        guard let value = self else { return ["none"] }
        return ["some", value.targetID.rawValue, value.actionID.rawValue]
    }
}

extension MenuInvocationExpectation? {
    fileprivate var menuValidationIdentityComponents: [String] {
        guard let value = self else { return ["none"] }
        return ["some", value.commandID.rawValue, value.source.rawValue]
            + value.targetAction.menuValidationIdentityComponents
            + value.result.menuValidationIdentityComponents
    }
}

extension MenuInvocationEvidence? {
    fileprivate var menuValidationIdentityComponents: [String] {
        guard let value = self else { return ["none"] }
        return ["some", value.commandID.rawValue, value.source.rawValue]
            + value.targetAction.menuValidationIdentityComponents
            + value.result.menuValidationIdentityComponents
    }
}

extension MenuCommandResult {
    fileprivate var menuValidationIdentityComponents: [String] {
        switch self {
        case .completed(let id): ["completed", id.rawValue]
        case .rejected(let id): ["rejected", id.rawValue]
        case .failed(let id): ["failed", id.rawValue]
        case .notInvoked: ["notInvoked"]
        }
    }
}

private func menuValidationMessage(for code: MenuValidationFindingCode) -> String {
    switch code {
    case .invalidIdentifier: "Identifier is empty, noncanonical, or contains disallowed scalars."
    case .invalidTitle: "Menu or command title must be nonblank."
    case .invalidElementShape: "Menu element fields do not match its declared kind."
    case .invalidRootElement: "Every root menu element must have menu kind."
    case .invalidShortcut: "Shortcut key, modifiers, or platform combination is not canonical."
    case .invalidTargetAction: "Target/action identifiers are invalid."
    case .invalidResult: "Invocation result identifier is invalid."
    case .invalidInvocation: "Invocation dispatch evidence is inconsistent with its result."
    case .duplicateElementID: "Menu element identifier appears more than once."
    case .duplicateCommandID: "Canonical command identifier appears more than once."
    case .duplicateScenarioID: "Menu-validation scenario identifier appears more than once."
    case .duplicateState: "Scenario contains duplicate dynamic state for one command."
    case .duplicateInvocation: "Scenario contains duplicate invocation evidence for one command and source."
    case .duplicateShortcut: "Menu command repeats the same platform shortcut."
    case .shortcutConflict: "Platform shortcut is assigned to multiple canonical commands."
    case .stateTargetsUnknownCommand: "Dynamic state targets a command absent from its menu tree."
    case .invocationTargetsUnknownCommand: "Invocation targets a command absent from its menu tree."
    case .invocationTargetConflict: "Invocation target/action conflicts with its menu command."
    case .invocationStateConflict: "Disabled command dispatched an invocation."
    case .missingScenario: "Expected menu-validation scenario is missing."
    case .unexpectedScenario: "Observed menu-validation scenario was not expected."
    case .missingElement: "Expected menu element is missing."
    case .unexpectedElement: "Observed menu element was not expected."
    case .elementKindMismatch: "Menu element kind differs from contract."
    case .titleMismatch: "Menu title differs from contract."
    case .commandIDMismatch: "Canonical command identifier differs from contract."
    case .hierarchyMismatch: "Menu element parent differs from contract."
    case .orderMismatch: "Menu element order differs from contract."
    case .shortcutMismatch: "Platform shortcut descriptors differ from contract."
    case .targetActionMismatch: "Menu target/action differs from contract."
    case .missingState: "Expected dynamic command state is missing."
    case .unexpectedState: "Observed dynamic command state was not expected."
    case .checkedStateMismatch: "Menu checked state differs from contract."
    case .enabledStateMismatch: "Menu enabled state differs from contract."
    case .missingInvocation: "Expected invocation evidence is missing."
    case .unexpectedInvocation: "Observed invocation evidence was not expected."
    case .invocationTargetMismatch: "Invoked target/action differs from contract."
    case .resultMismatch: "Command result differs from contract."
    }
}
