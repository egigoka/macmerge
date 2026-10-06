import Foundation
import MacMergeCore
import XCTest

final class MenuValidationContractTests: XCTestCase {
    func testValidNestedManifestAndScenariosProduceEmptyReport() throws {
        let input = validInput()

        let report = try MenuValidationAudit.audit(
            contract: input.contract,
            evidence: input.evidence
        )

        XCTAssertEqual(report.formatVersion, MenuValidationAudit.reportFormatVersion)
        XCTAssertEqual(report.contractID, contractID("main-menu"))
        XCTAssertEqual(
            MenuValidationReport.scopeStatement,
            "Deterministic checks of caller-supplied menu contracts and observations only; not runtime UI verification."
        )
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertNil(report.highestSeverity)
        XCTAssertFalse(report.containsErrors)
    }

    func testReportsTitleOrderShortcutStateTargetAndResultDifferences() throws {
        let input = mismatchedInput()

        let report = try MenuValidationAudit.audit(
            contract: input.contract,
            evidence: input.evidence
        )
        let codes = Set(report.findings.map(\.code))

        XCTAssertTrue(
            Set([
                MenuValidationFindingCode.titleMismatch,
                .orderMismatch,
                .shortcutMismatch,
                .targetActionMismatch,
                .checkedStateMismatch,
                .enabledStateMismatch,
                .invocationTargetMismatch,
                .resultMismatch
            ]).isSubset(of: codes)
        )
        XCTAssertEqual(
            finding(in: report, code: .titleMismatch)?.evidence,
            .title(expected: "Open", observed: "Open File")
        )
        XCTAssertEqual(
            finding(in: report, code: .orderMismatch)?.evidence,
            .order(
                expected: [
                    elementID("open-item"), elementID("recent-menu"),
                    elementID("file-separator"), elementID("close-item")
                ],
                observed: [
                    elementID("recent-menu"), elementID("open-item"),
                    elementID("file-separator"), elementID("close-item")
                ]
            )
        )
        XCTAssertEqual(
            finding(in: report, code: .shortcutMismatch)?.evidence,
            .shortcuts(
                expected: [shortcut("o")],
                observed: [shortcut("p")]
            )
        )
        XCTAssertEqual(
            finding(in: report, code: .checkedStateMismatch)?.evidence,
            .checkedState(expected: .notCheckable, observed: .on)
        )
        XCTAssertEqual(
            finding(in: report, code: .enabledStateMismatch)?.evidence,
            .enabledState(expected: true, observed: false)
        )
        XCTAssertEqual(
            finding(in: report, code: .targetActionMismatch)?.evidence,
            .targetAction(expected: openTarget, observed: alternateOpenTarget)
        )
        XCTAssertEqual(
            finding(in: report, code: .invocationTargetMismatch)?.evidence,
            .targetAction(expected: openTarget, observed: alternateOpenTarget)
        )
        XCTAssertEqual(
            finding(in: report, code: .resultMismatch)?.evidence,
            .result(
                expected: .completed(resultID("opened")),
                observed: .failed(resultID("open-failed"))
            )
        )
    }

    func testNestedHierarchyChangeReportsParentAndLocalOrder() throws {
        let scenario = readyScenario()
        let contract = MenuValidationContract(
            id: contractID("nested-menu"),
            tree: menuTree(),
            scenarios: [scenario]
        )
        let evidence = MenuValidationEvidence(
            scenarios: [observedScenario(scenario, tree: menuTree(moveClearToRoot: true))]
        )

        let report = try MenuValidationAudit.audit(contract: contract, evidence: evidence)
        let hierarchy = report.findings.first { finding in
            guard finding.code == .hierarchyMismatch else { return false }
            guard case .element(_, _, let id) = finding.subject else { return false }
            return id == elementID("clear-recent-item")
        }

        XCTAssertEqual(
            hierarchy?.evidence,
            .parent(expected: elementID("recent-menu"), observed: elementID("file-menu"))
        )
        XCTAssertGreaterThanOrEqual(
            report.findings.filter { $0.code == .orderMismatch }.count,
            2
        )
    }

    func testDuplicateElementAndCommandOccurrencesAreEachAudited() throws {
        let invalidShortcut = MenuShortcutDescriptor(
            platform: .macOS,
            key: "O",
            modifiers: [.command]
        )
        let first = MenuValidationElement(
            id: elementID("duplicate-item"),
            kind: .command,
            title: nil,
            commandID: commandID("duplicate-command"),
            targetAction: openTarget
        )
        let second = MenuValidationElement(
            id: elementID("duplicate-item"),
            kind: .command,
            title: "Second",
            commandID: commandID("duplicate-command"),
            shortcuts: [invalidShortcut],
            targetAction: openTarget
        )
        let tree = MenuValidationTree(
            roots: [
                MenuValidationElement(
                    id: elementID("root-menu"),
                    kind: .menu,
                    title: "Root",
                    children: [first, second]
                )
            ]
        )
        let contract = MenuValidationContract(
            id: contractID("duplicate-elements"),
            tree: tree,
            scenarios: []
        )

        let report = try MenuValidationAudit.audit(
            contract: contract,
            evidence: MenuValidationEvidence(scenarios: [])
        )

        XCTAssertEqual(
            finding(in: report, code: .duplicateElementID)?.evidence,
            .occurrences(2)
        )
        XCTAssertEqual(
            finding(in: report, code: .duplicateCommandID)?.evidence,
            .occurrences(2)
        )
        XCTAssertNotNil(finding(in: report, code: .invalidTitle))
        XCTAssertNotNil(finding(in: report, code: .invalidShortcut))
    }

    func testEveryDuplicateExpectedAndObservedScenarioIsAudited() throws {
        let input = duplicateScenarioInput()

        let report = try MenuValidationAudit.audit(
            contract: input.contract,
            evidence: input.evidence
        )
        let duplicateScopes = Set(
            report.findings.compactMap { finding -> MenuValidationEvidenceScope? in
                guard finding.code == .duplicateScenarioID,
                    case .scenario(let scope, _) = finding.subject
                else {
                    return nil
                }
                return scope
            }
        )
        let auditedUnknownCommands = Set(
            report.findings.compactMap { finding -> String? in
                guard finding.code == .stateTargetsUnknownCommand,
                    case .command(let scope, _, let id) = finding.subject
                else {
                    return nil
                }
                return "\(scope.rawValue):\(id.rawValue)"
            }
        )

        XCTAssertEqual(duplicateScopes, [.contract, .observed])
        XCTAssertEqual(
            auditedUnknownCommands,
            [
                "contract:unknown-a", "contract:unknown-b",
                "observed:unknown-a", "observed:unknown-b"
            ]
        )
    }

    func testShortcutFindingIDsRemainUniquePerElement() throws {
        let invalid = MenuShortcutDescriptor(
            platform: .macOS,
            key: "O",
            modifiers: [.command]
        )
        let commands = [
            MenuValidationElement(
                id: elementID("first-item"),
                kind: .command,
                title: "First",
                commandID: commandID("first"),
                shortcuts: [invalid, invalid],
                targetAction: openTarget
            ),
            MenuValidationElement(
                id: elementID("second-item"),
                kind: .command,
                title: "Second",
                commandID: commandID("second"),
                shortcuts: [invalid, invalid],
                targetAction: closeTarget
            )
        ]
        let contract = MenuValidationContract(
            id: contractID("shortcut-identity"),
            tree: MenuValidationTree(
                roots: [
                    MenuValidationElement(
                        id: elementID("shortcut-menu"),
                        kind: .menu,
                        title: "Shortcuts",
                        children: commands
                    )
                ]
            ),
            scenarios: []
        )

        let report = try MenuValidationAudit.audit(
            contract: contract,
            evidence: MenuValidationEvidence(scenarios: [])
        )

        for code in [MenuValidationFindingCode.invalidShortcut, .duplicateShortcut] {
            let findings = report.findings.filter { $0.code == code }
            let elementIDs = Set(
                findings.compactMap { finding -> MenuElementID? in
                    guard case .shortcut(_, _, let elementID, _) = finding.subject else {
                        return nil
                    }
                    return elementID
                }
            )
            XCTAssertEqual(findings.count, 2, "code=\(code)")
            XCTAssertEqual(Set(findings.map(\.id)).count, 2, "code=\(code)")
            XCTAssertEqual(elementIDs, [elementID("first-item"), elementID("second-item")])
        }
    }

    func testMalformedUnknownInvocationStillAuditsTargetAndResult() throws {
        let unknown = commandID("unknown-command")
        let malformedTarget = MenuTargetAction(
            targetID: targetID(""),
            actionID: actionID(" ")
        )
        let scenario = MenuValidationScenario(
            id: scenarioID("unknown-invocation"),
            states: [],
            invocations: [
                MenuInvocationExpectation(
                    commandID: unknown,
                    source: .menuItem,
                    targetAction: malformedTarget,
                    result: .failed(resultID(""))
                )
            ]
        )
        let contract = MenuValidationContract(
            id: contractID("malformed-invocation"),
            tree: menuTree(),
            scenarios: [scenario]
        )

        let report = try MenuValidationAudit.audit(
            contract: contract,
            evidence: MenuValidationEvidence(scenarios: [])
        )

        XCTAssertEqual(
            report.findings.filter { $0.code == .invalidTargetAction }.count,
            2
        )
        XCTAssertEqual(report.findings.filter { $0.code == .invalidResult }.count, 1)
        XCTAssertEqual(
            report.findings.filter { $0.code == .invocationTargetsUnknownCommand }.count,
            1
        )
    }

    func testNotInvokedIsValidOnlyForDisabledKnownCommandWithState() throws {
        let disabled = try invocationReport(
            isEnabled: false,
            targetAction: nil,
            result: .notInvoked
        )
        XCTAssertTrue(disabled.findings.isEmpty)

        let enabled = try invocationReport(
            isEnabled: true,
            targetAction: nil,
            result: .notInvoked
        )
        XCTAssertEqual(
            enabled.findings.filter { $0.code == .invalidInvocation }.count,
            2
        )

        let missingState = try invocationReport(
            isEnabled: nil,
            targetAction: nil,
            result: .notInvoked
        )
        XCTAssertEqual(
            missingState.findings.filter { $0.code == .invalidInvocation }.count,
            2
        )

        let unknownCommand = try invocationReport(
            commandID: commandID("unknown-command"),
            isEnabled: false,
            targetAction: nil,
            result: .notInvoked
        )
        XCTAssertEqual(
            unknownCommand.findings.filter { $0.code == .invalidInvocation }.count,
            2
        )
        XCTAssertEqual(
            unknownCommand.findings.filter { $0.code == .invocationTargetsUnknownCommand }.count,
            2
        )

        let dispatchedWhileDisabled = try invocationReport(
            isEnabled: false,
            targetAction: openTarget,
            result: .completed(resultID("opened"))
        )
        XCTAssertEqual(
            dispatchedWhileDisabled.findings.filter { $0.code == .invocationStateConflict }.count,
            2
        )
    }

    func testFindingIDsRepresentEverySemanticFindingAcrossIndependentScenarioPermutations() throws {
        let forward = duplicateScenarioInput()

        let first = try MenuValidationAudit.audit(
            contract: forward.contract,
            evidence: forward.evidence
        )
        let repeated = try MenuValidationAudit.audit(
            contract: forward.contract,
            evidence: forward.evidence
        )
        let duplicateID = scenarioID("duplicate")
        let unknownA = MenuCommandDynamicState(
            commandID: commandID("unknown-a"),
            isEnabled: true
        )
        let unknownB = MenuCommandDynamicState(
            commandID: commandID("unknown-b"),
            isEnabled: false
        )
        let expectedSemantics: Set<MenuValidationFindingSemantic> = [
            MenuValidationFindingSemantic(
                code: .duplicateScenarioID,
                subject: .scenario(scope: .contract, id: duplicateID),
                evidence: .occurrences(2)
            ),
            MenuValidationFindingSemantic(
                code: .duplicateScenarioID,
                subject: .scenario(scope: .observed, id: duplicateID),
                evidence: .occurrences(2)
            ),
            MenuValidationFindingSemantic(
                code: .stateTargetsUnknownCommand,
                subject: .command(
                    scope: .contract,
                    scenarioID: duplicateID,
                    id: unknownA.commandID
                ),
                evidence: .state(expected: unknownA, observed: nil)
            ),
            MenuValidationFindingSemantic(
                code: .stateTargetsUnknownCommand,
                subject: .command(
                    scope: .contract,
                    scenarioID: duplicateID,
                    id: unknownB.commandID
                ),
                evidence: .state(expected: unknownB, observed: nil)
            ),
            MenuValidationFindingSemantic(
                code: .stateTargetsUnknownCommand,
                subject: .command(
                    scope: .observed,
                    scenarioID: duplicateID,
                    id: unknownA.commandID
                ),
                evidence: .state(expected: nil, observed: unknownA)
            ),
            MenuValidationFindingSemantic(
                code: .stateTargetsUnknownCommand,
                subject: .command(
                    scope: .observed,
                    scenarioID: duplicateID,
                    id: unknownB.commandID
                ),
                evidence: .state(expected: nil, observed: unknownB)
            )
        ]
        let semanticIDs = Dictionary(
            grouping: first.findings,
            by: MenuValidationFindingSemantic.init
        ).mapValues { Set($0.map(\.id)) }

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(Set(first.findings.map(MenuValidationFindingSemantic.init)), expectedSemantics)
        XCTAssertEqual(first.findings.count, expectedSemantics.count)
        XCTAssertTrue(semanticIDs.values.allSatisfy { $0.count == 1 })
        XCTAssertEqual(Set(first.findings.map(\.id)).count, expectedSemantics.count)

        for reverseExpected in [false, true] {
            for reverseObserved in [false, true] {
                let input = duplicateScenarioInput(
                    reverseExpected: reverseExpected,
                    reverseObserved: reverseObserved
                )
                let report = try MenuValidationAudit.audit(
                    contract: input.contract,
                    evidence: input.evidence
                )
                XCTAssertEqual(report, first)
                XCTAssertEqual(
                    Dictionary(
                        grouping: report.findings,
                        by: MenuValidationFindingSemantic.init
                    ).mapValues { Set($0.map(\.id)) },
                    semanticIDs
                )
            }
        }
    }

    func testRejectsEveryInvalidLimit() {
        let cases: [(MenuValidationLimits, MenuValidationError)] = [
            (
                MenuValidationLimits(maximumElements: -1),
                .invalidLimit(
                    name: "maximumElements",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumElements
                )
            ),
            (
                MenuValidationLimits(maximumTotalElements: -1),
                .invalidLimit(
                    name: "maximumTotalElements",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumTotalElements
                )
            ),
            (
                MenuValidationLimits(maximumDepth: 0),
                .invalidLimit(
                    name: "maximumDepth",
                    value: 0,
                    minimum: 1,
                    maximum: MenuValidationLimits.hardMaximumDepth
                )
            ),
            (
                MenuValidationLimits(maximumScenarios: -1),
                .invalidLimit(
                    name: "maximumScenarios",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumScenarios
                )
            ),
            (
                MenuValidationLimits(maximumStatesPerScenario: -1),
                .invalidLimit(
                    name: "maximumStatesPerScenario",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumStatesPerScenario
                )
            ),
            (
                MenuValidationLimits(maximumInvocationsPerScenario: -1),
                .invalidLimit(
                    name: "maximumInvocationsPerScenario",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumInvocationsPerScenario
                )
            ),
            (
                MenuValidationLimits(maximumShortcutsPerElement: -1),
                .invalidLimit(
                    name: "maximumShortcutsPerElement",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumShortcutsPerElement
                )
            ),
            (
                MenuValidationLimits(maximumStringUTF8Bytes: -1),
                .invalidLimit(
                    name: "maximumStringUTF8Bytes",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumStringUTF8Bytes
                )
            ),
            (
                MenuValidationLimits(maximumTotalStringUTF8Bytes: -1),
                .invalidLimit(
                    name: "maximumTotalStringUTF8Bytes",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumTotalStringUTF8Bytes
                )
            ),
            (
                MenuValidationLimits(maximumWorkUnits: 0),
                .invalidLimit(
                    name: "maximumWorkUnits",
                    value: 0,
                    minimum: 1,
                    maximum: MenuValidationLimits.hardMaximumWorkUnits
                )
            ),
            (
                MenuValidationLimits(maximumFindings: -1),
                .invalidLimit(
                    name: "maximumFindings",
                    value: -1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumFindings
                )
            ),
            (
                MenuValidationLimits(cancellationCheckInterval: 0),
                .invalidLimit(
                    name: "cancellationCheckInterval",
                    value: 0,
                    minimum: 1,
                    maximum: MenuValidationLimits.hardMaximumCancellationCheckInterval
                )
            ),
            (
                MenuValidationLimits(
                    maximumElements: MenuValidationLimits.hardMaximumElements + 1
                ),
                .invalidLimit(
                    name: "maximumElements",
                    value: MenuValidationLimits.hardMaximumElements + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumElements
                )
            ),
            (
                MenuValidationLimits(
                    maximumTotalElements: MenuValidationLimits.hardMaximumTotalElements + 1
                ),
                .invalidLimit(
                    name: "maximumTotalElements",
                    value: MenuValidationLimits.hardMaximumTotalElements + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumTotalElements
                )
            ),
            (
                MenuValidationLimits(
                    maximumDepth: MenuValidationLimits.hardMaximumDepth + 1
                ),
                .invalidLimit(
                    name: "maximumDepth",
                    value: MenuValidationLimits.hardMaximumDepth + 1,
                    minimum: 1,
                    maximum: MenuValidationLimits.hardMaximumDepth
                )
            ),
            (
                MenuValidationLimits(
                    maximumScenarios: MenuValidationLimits.hardMaximumScenarios + 1
                ),
                .invalidLimit(
                    name: "maximumScenarios",
                    value: MenuValidationLimits.hardMaximumScenarios + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumScenarios
                )
            ),
            (
                MenuValidationLimits(
                    maximumStatesPerScenario:
                        MenuValidationLimits.hardMaximumStatesPerScenario + 1
                ),
                .invalidLimit(
                    name: "maximumStatesPerScenario",
                    value: MenuValidationLimits.hardMaximumStatesPerScenario + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumStatesPerScenario
                )
            ),
            (
                MenuValidationLimits(
                    maximumInvocationsPerScenario:
                        MenuValidationLimits.hardMaximumInvocationsPerScenario + 1
                ),
                .invalidLimit(
                    name: "maximumInvocationsPerScenario",
                    value: MenuValidationLimits.hardMaximumInvocationsPerScenario + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumInvocationsPerScenario
                )
            ),
            (
                MenuValidationLimits(
                    maximumShortcutsPerElement:
                        MenuValidationLimits.hardMaximumShortcutsPerElement + 1
                ),
                .invalidLimit(
                    name: "maximumShortcutsPerElement",
                    value: MenuValidationLimits.hardMaximumShortcutsPerElement + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumShortcutsPerElement
                )
            ),
            (
                MenuValidationLimits(
                    maximumStringUTF8Bytes:
                        MenuValidationLimits.hardMaximumStringUTF8Bytes + 1
                ),
                .invalidLimit(
                    name: "maximumStringUTF8Bytes",
                    value: MenuValidationLimits.hardMaximumStringUTF8Bytes + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumStringUTF8Bytes
                )
            ),
            (
                MenuValidationLimits(
                    maximumTotalStringUTF8Bytes:
                        MenuValidationLimits.hardMaximumTotalStringUTF8Bytes + 1
                ),
                .invalidLimit(
                    name: "maximumTotalStringUTF8Bytes",
                    value: MenuValidationLimits.hardMaximumTotalStringUTF8Bytes + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumTotalStringUTF8Bytes
                )
            ),
            (
                MenuValidationLimits(
                    maximumWorkUnits: MenuValidationLimits.hardMaximumWorkUnits + 1
                ),
                .invalidLimit(
                    name: "maximumWorkUnits",
                    value: MenuValidationLimits.hardMaximumWorkUnits + 1,
                    minimum: 1,
                    maximum: MenuValidationLimits.hardMaximumWorkUnits
                )
            ),
            (
                MenuValidationLimits(
                    maximumFindings: MenuValidationLimits.hardMaximumFindings + 1
                ),
                .invalidLimit(
                    name: "maximumFindings",
                    value: MenuValidationLimits.hardMaximumFindings + 1,
                    minimum: 0,
                    maximum: MenuValidationLimits.hardMaximumFindings
                )
            ),
            (
                MenuValidationLimits(
                    cancellationCheckInterval:
                        MenuValidationLimits.hardMaximumCancellationCheckInterval + 1
                ),
                .invalidLimit(
                    name: "cancellationCheckInterval",
                    value: MenuValidationLimits.hardMaximumCancellationCheckInterval + 1,
                    minimum: 1,
                    maximum: MenuValidationLimits.hardMaximumCancellationCheckInterval
                )
            )
        ]

        for (limits, expected) in cases {
            assertAuditError(expected) {
                _ = try MenuValidationAudit.audit(
                    contract: self.emptyContract(),
                    evidence: MenuValidationEvidence(scenarios: []),
                    limits: limits
                )
            }
        }
    }

    func testEnforcesEveryCountLimit() {
        assertAuditError(.countLimitExceeded(kind: .elements, maximum: 0)) {
            _ = try MenuValidationAudit.audit(
                contract: MenuValidationContract(
                    id: self.contractID("elements"),
                    tree: self.menuTree(),
                    scenarios: []
                ),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumElements: 0)
            )
        }
        assertAuditError(.countLimitExceeded(kind: .totalElements, maximum: 1)) {
            _ = try MenuValidationAudit.audit(
                contract: MenuValidationContract(
                    id: self.contractID("total-elements"),
                    tree: self.menuTree(),
                    scenarios: []
                ),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumTotalElements: 1)
            )
        }
        assertAuditError(.countLimitExceeded(kind: .depth, maximum: 1)) {
            _ = try MenuValidationAudit.audit(
                contract: MenuValidationContract(
                    id: self.contractID("depth"),
                    tree: self.menuTree(),
                    scenarios: []
                ),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumDepth: 1)
            )
        }
        assertAuditError(.countLimitExceeded(kind: .scenarios, maximum: 0)) {
            _ = try MenuValidationAudit.audit(
                contract: MenuValidationContract(
                    id: self.contractID("scenarios"),
                    tree: MenuValidationTree(roots: []),
                    scenarios: [
                        MenuValidationScenario(id: self.scenarioID("scenario"), states: [])
                    ]
                ),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumScenarios: 0)
            )
        }
        assertAuditError(.countLimitExceeded(kind: .states, maximum: 0)) {
            _ = try MenuValidationAudit.audit(
                contract: MenuValidationContract(
                    id: self.contractID("states"),
                    tree: MenuValidationTree(roots: []),
                    scenarios: [
                        MenuValidationScenario(
                            id: self.scenarioID("scenario"),
                            states: [
                                MenuCommandDynamicState(
                                    commandID: self.commandID("command"),
                                    isEnabled: true
                                )
                            ]
                        )
                    ]
                ),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumStatesPerScenario: 0)
            )
        }
        assertAuditError(.countLimitExceeded(kind: .invocations, maximum: 0)) {
            _ = try MenuValidationAudit.audit(
                contract: MenuValidationContract(
                    id: self.contractID("invocations"),
                    tree: MenuValidationTree(roots: []),
                    scenarios: [
                        MenuValidationScenario(
                            id: self.scenarioID("scenario"),
                            states: [],
                            invocations: [
                                MenuInvocationExpectation(
                                    commandID: self.commandID("command"),
                                    source: .menuItem,
                                    targetAction: self.openTarget,
                                    result: .completed(self.resultID("result"))
                                )
                            ]
                        )
                    ]
                ),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumInvocationsPerScenario: 0)
            )
        }
        assertAuditError(.countLimitExceeded(kind: .shortcuts, maximum: 0)) {
            _ = try MenuValidationAudit.audit(
                contract: MenuValidationContract(
                    id: self.contractID("shortcuts"),
                    tree: self.menuTree(),
                    scenarios: []
                ),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumShortcutsPerElement: 0)
            )
        }
    }

    func testEnforcesStringFindingAndWorkLimits() {
        assertAuditError(.stringTooLarge(field: "contract.id", maximumUTF8Bytes: 1)) {
            _ = try MenuValidationAudit.audit(
                contract: self.emptyContract(),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumStringUTF8Bytes: 1)
            )
        }
        assertAuditError(.totalStringsTooLarge(maximumUTF8Bytes: 1)) {
            _ = try MenuValidationAudit.audit(
                contract: self.emptyContract(id: "ab"),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumTotalStringUTF8Bytes: 1)
            )
        }
        assertAuditError(.findingLimitExceeded(maximum: 0)) {
            _ = try MenuValidationAudit.audit(
                contract: self.emptyContract(id: ""),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumFindings: 0)
            )
        }
        assertAuditError(.workLimitExceeded(maximum: 1)) {
            _ = try MenuValidationAudit.audit(
                contract: self.emptyContract(),
                evidence: MenuValidationEvidence(scenarios: []),
                limits: MenuValidationLimits(maximumWorkUnits: 1)
            )
        }
    }

    func testWorkBudgetCanBeExhaustedInsideMultiKeyFindingSort() throws {
        func contract(targetID: String) -> MenuValidationContract {
            MenuValidationContract(
                id: contractID("sort-budget"),
                tree: MenuValidationTree(
                    roots: [
                        MenuValidationElement(
                            id: elementID("root"),
                            kind: .menu,
                            title: "Root",
                            children: [
                                MenuValidationElement(
                                    id: elementID("command"),
                                    kind: .command,
                                    title: "Command",
                                    commandID: commandID("command"),
                                    targetAction: MenuTargetAction(
                                        targetID: self.targetID(targetID),
                                        actionID: actionID("\t")
                                    )
                                )
                            ]
                        )
                    ]
                ),
                scenarios: []
            )
        }

        let controlContract = contract(targetID: "a")
        let contract = contract(targetID: " ")
        let evidence = MenuValidationEvidence(scenarios: [])
        let report = try MenuValidationAudit.audit(contract: contract, evidence: evidence)

        XCTAssertEqual(report.findings.map(\.code), [.invalidTargetAction, .invalidTargetAction])

        var controlMinimum = 1
        var upperBound = MenuValidationLimits.default.maximumWorkUnits
        while controlMinimum < upperBound {
            let candidate = controlMinimum + (upperBound - controlMinimum) / 2
            do {
                _ = try MenuValidationAudit.audit(
                    contract: controlContract,
                    evidence: evidence,
                    limits: MenuValidationLimits(maximumWorkUnits: candidate)
                )
                upperBound = candidate
            } catch {
                XCTAssertEqual(
                    error as? MenuValidationError,
                    .workLimitExceeded(maximum: candidate)
                )
                controlMinimum = candidate + 1
            }
        }

        let targetFinding = try XCTUnwrap(
            report.findings.first {
                $0.evidence == .identifier(field: "targetAction.targetID", value: " ")
            }
        )
        // One finding skips stable sorting, so its exact budget isolates all non-sort work.
        let sortStart = controlMinimum + targetFinding.id.rawValue.utf8.count + 1
        let codeComparisonWork = MenuValidationFindingCode.invalidTargetAction.rawValue.utf8.count + 1
        let sortedIDs = report.findings.map(\.id.rawValue)
        let idComparisonWork = utf8ComparisonWork(sortedIDs[0], sortedIDs[1])
        let maximumInsideIDComparison =
            sortStart + 1 + codeComparisonWork + idComparisonWork - 1

        assertAuditError(.workLimitExceeded(maximum: maximumInsideIDComparison)) {
            _ = try MenuValidationAudit.audit(
                contract: contract,
                evidence: evidence,
                limits: MenuValidationLimits(maximumWorkUnits: maximumInsideIDComparison)
            )
        }
        let exactMaximum = maximumInsideIDComparison + 3
        assertAuditError(.workLimitExceeded(maximum: exactMaximum - 1)) {
            _ = try MenuValidationAudit.audit(
                contract: contract,
                evidence: evidence,
                limits: MenuValidationLimits(maximumWorkUnits: exactMaximum - 1)
            )
        }
        XCTAssertEqual(
            try MenuValidationAudit.audit(
                contract: contract,
                evidence: evidence,
                limits: MenuValidationLimits(maximumWorkUnits: exactMaximum)
            ),
            report
        )
    }

    func testCancellationBeforeAndDuringAudit() {
        let input = validInput()
        assertAuditError(.cancelled) {
            _ = try MenuValidationAudit.audit(
                contract: input.contract,
                evidence: input.evidence,
                cancellationCheck: { true }
            )
        }

        let probe = CancellationProbe(cancelOnCheck: 2)
        assertAuditError(.cancelled) {
            _ = try MenuValidationAudit.audit(
                contract: input.contract,
                evidence: input.evidence,
                limits: MenuValidationLimits(cancellationCheckInterval: 1),
                cancellationCheck: { probe.shouldCancel() }
            )
        }
        XCTAssertGreaterThanOrEqual(probe.checkCount, 2)
    }

    private var openTarget: MenuTargetAction {
        MenuTargetAction(targetID: targetID("application"), actionID: actionID("open"))
    }

    private var alternateOpenTarget: MenuTargetAction {
        MenuTargetAction(targetID: targetID("document"), actionID: actionID("open-copy"))
    }

    private var clearTarget: MenuTargetAction {
        MenuTargetAction(targetID: targetID("history"), actionID: actionID("clear"))
    }

    private var closeTarget: MenuTargetAction {
        MenuTargetAction(targetID: targetID("window"), actionID: actionID("close"))
    }

    private func validInput() -> (
        contract: MenuValidationContract,
        evidence: MenuValidationEvidence
    ) {
        let tree = menuTree()
        let scenarios = [readyScenario(), disabledScenario()]
        return (
            MenuValidationContract(
                id: contractID("main-menu"),
                tree: tree,
                scenarios: scenarios
            ),
            MenuValidationEvidence(
                scenarios: scenarios.map { observedScenario($0, tree: tree) }
            )
        )
    }

    private func mismatchedInput() -> (
        contract: MenuValidationContract,
        evidence: MenuValidationEvidence
    ) {
        let valid = validInput()
        let changedTree = menuTree(
            openTitle: "Open File",
            openShortcut: shortcut("p"),
            openTarget: alternateOpenTarget,
            reorderFileChildren: true
        )
        let ready = readyScenario()
        let changedStates = ready.states.map { state in
            guard state.commandID == commandID("open") else { return state }
            return MenuCommandDynamicState(
                commandID: state.commandID,
                isEnabled: false,
                checkedState: .on
            )
        }
        let changedInvocations = ready.invocations.map { invocation in
            guard invocation.commandID == commandID("open") else {
                return MenuInvocationEvidence(
                    commandID: invocation.commandID,
                    source: invocation.source,
                    targetAction: invocation.targetAction,
                    result: invocation.result
                )
            }
            return MenuInvocationEvidence(
                commandID: invocation.commandID,
                source: invocation.source,
                targetAction: alternateOpenTarget,
                result: .failed(resultID("open-failed"))
            )
        }
        let changedReady = MenuValidationObservedScenario(
            id: ready.id,
            tree: changedTree,
            states: changedStates,
            invocations: changedInvocations
        )
        let disabled = disabledScenario()
        return (
            valid.contract,
            MenuValidationEvidence(
                scenarios: [changedReady, observedScenario(disabled, tree: menuTree())]
            )
        )
    }

    private func duplicateScenarioInput(
        reverseExpected: Bool = false,
        reverseObserved: Bool = false
    ) -> (
        contract: MenuValidationContract,
        evidence: MenuValidationEvidence
    ) {
        var expected = [
            MenuValidationScenario(
                id: scenarioID("duplicate"),
                states: [
                    MenuCommandDynamicState(
                        commandID: commandID("unknown-a"),
                        isEnabled: true
                    )
                ]
            ),
            MenuValidationScenario(
                id: scenarioID("duplicate"),
                states: [
                    MenuCommandDynamicState(
                        commandID: commandID("unknown-b"),
                        isEnabled: false
                    )
                ]
            )
        ]
        var observed = [
            MenuValidationObservedScenario(
                id: scenarioID("duplicate"),
                tree: MenuValidationTree(roots: []),
                states: [
                    MenuCommandDynamicState(
                        commandID: commandID("unknown-a"),
                        isEnabled: true
                    )
                ]
            ),
            MenuValidationObservedScenario(
                id: scenarioID("duplicate"),
                tree: MenuValidationTree(roots: []),
                states: [
                    MenuCommandDynamicState(
                        commandID: commandID("unknown-b"),
                        isEnabled: false
                    )
                ]
            )
        ]
        if reverseExpected { expected.reverse() }
        if reverseObserved { observed.reverse() }
        return (
            MenuValidationContract(
                id: contractID("duplicate-scenarios"),
                tree: MenuValidationTree(roots: []),
                scenarios: expected
            ),
            MenuValidationEvidence(scenarios: observed)
        )
    }

    private func invocationReport(
        commandID: MenuCommandID? = nil,
        isEnabled: Bool?,
        targetAction: MenuTargetAction?,
        result: MenuCommandResult
    ) throws -> MenuValidationReport {
        let invocationCommandID = commandID ?? self.commandID("open")
        let tree = MenuValidationTree(
            roots: [
                MenuValidationElement(
                    id: elementID("file-menu"),
                    kind: .menu,
                    title: "File",
                    children: [
                        MenuValidationElement(
                            id: elementID("open-item"),
                            kind: .command,
                            title: "Open",
                            commandID: self.commandID("open"),
                            targetAction: openTarget
                        )
                    ]
                )
            ]
        )
        let scenario = MenuValidationScenario(
            id: scenarioID("invocation"),
            states: isEnabled.map {
                [MenuCommandDynamicState(commandID: invocationCommandID, isEnabled: $0)]
            } ?? [],
            invocations: [
                MenuInvocationExpectation(
                    commandID: invocationCommandID,
                    source: .menuItem,
                    targetAction: targetAction,
                    result: result
                )
            ]
        )
        let contract = MenuValidationContract(
            id: contractID("invocation-state"),
            tree: tree,
            scenarios: [scenario]
        )
        return try MenuValidationAudit.audit(
            contract: contract,
            evidence: MenuValidationEvidence(
                scenarios: [observedScenario(scenario, tree: tree)]
            )
        )
    }

    private func menuTree(
        openTitle: String = "Open",
        openShortcut: MenuShortcutDescriptor? = nil,
        openTarget: MenuTargetAction? = nil,
        reorderFileChildren: Bool = false,
        moveClearToRoot: Bool = false
    ) -> MenuValidationTree {
        let open = MenuValidationElement(
            id: elementID("open-item"),
            kind: .command,
            title: openTitle,
            commandID: commandID("open"),
            shortcuts: [openShortcut ?? shortcut("o")],
            targetAction: openTarget ?? self.openTarget
        )
        let clear = MenuValidationElement(
            id: elementID("clear-recent-item"),
            kind: .command,
            title: "Clear Menu",
            commandID: commandID("clear-recent"),
            shortcuts: [shortcut("r", modifiers: [.command, .shift])],
            targetAction: clearTarget
        )
        let recentSeparator = MenuValidationElement(
            id: elementID("recent-separator"),
            kind: .separator
        )
        let recent = MenuValidationElement(
            id: elementID("recent-menu"),
            kind: .menu,
            title: "Open Recent",
            children: moveClearToRoot ? [recentSeparator] : [clear, recentSeparator]
        )
        let fileSeparator = MenuValidationElement(
            id: elementID("file-separator"),
            kind: .separator
        )
        let close = MenuValidationElement(
            id: elementID("close-item"),
            kind: .command,
            title: "Close",
            commandID: commandID("close"),
            shortcuts: [shortcut("w")],
            targetAction: closeTarget
        )
        var children =
            moveClearToRoot
            ? [open, recent, clear, fileSeparator, close]
            : [open, recent, fileSeparator, close]
        if reorderFileChildren {
            children.swapAt(0, 1)
        }
        return MenuValidationTree(
            roots: [
                MenuValidationElement(
                    id: elementID("file-menu"),
                    kind: .menu,
                    title: "File",
                    children: children
                )
            ]
        )
    }

    private func readyScenario() -> MenuValidationScenario {
        MenuValidationScenario(
            id: scenarioID("ready"),
            states: [
                MenuCommandDynamicState(commandID: commandID("open"), isEnabled: true),
                MenuCommandDynamicState(
                    commandID: commandID("clear-recent"),
                    isEnabled: true,
                    checkedState: .on
                ),
                MenuCommandDynamicState(commandID: commandID("close"), isEnabled: true)
            ],
            invocations: [
                MenuInvocationExpectation(
                    commandID: commandID("open"),
                    source: .menuItem,
                    targetAction: openTarget,
                    result: .completed(resultID("opened"))
                ),
                MenuInvocationExpectation(
                    commandID: commandID("close"),
                    source: .keyboardShortcut,
                    targetAction: closeTarget,
                    result: .completed(resultID("closed"))
                )
            ]
        )
    }

    private func disabledScenario() -> MenuValidationScenario {
        MenuValidationScenario(
            id: scenarioID("disabled"),
            states: [
                MenuCommandDynamicState(commandID: commandID("open"), isEnabled: false),
                MenuCommandDynamicState(
                    commandID: commandID("clear-recent"),
                    isEnabled: true,
                    checkedState: .on
                ),
                MenuCommandDynamicState(commandID: commandID("close"), isEnabled: false)
            ],
            invocations: [
                MenuInvocationExpectation(
                    commandID: commandID("open"),
                    source: .keyboardShortcut,
                    targetAction: nil,
                    result: .notInvoked
                ),
                MenuInvocationExpectation(
                    commandID: commandID("close"),
                    source: .accessibilityAction,
                    targetAction: nil,
                    result: .notInvoked
                )
            ]
        )
    }

    private func observedScenario(
        _ scenario: MenuValidationScenario,
        tree: MenuValidationTree
    ) -> MenuValidationObservedScenario {
        MenuValidationObservedScenario(
            id: scenario.id,
            tree: tree,
            states: scenario.states,
            invocations: scenario.invocations.map {
                MenuInvocationEvidence(
                    commandID: $0.commandID,
                    source: $0.source,
                    targetAction: $0.targetAction,
                    result: $0.result
                )
            }
        )
    }

    private func emptyContract(id: String = "manifest") -> MenuValidationContract {
        MenuValidationContract(
            id: contractID(id),
            tree: MenuValidationTree(roots: []),
            scenarios: []
        )
    }

    private func shortcut(
        _ key: String,
        modifiers: Set<MenuShortcutModifier> = [.command]
    ) -> MenuShortcutDescriptor {
        MenuShortcutDescriptor(platform: .macOS, key: key, modifiers: modifiers)
    }

    private func finding(
        in report: MenuValidationReport,
        code: MenuValidationFindingCode
    ) -> MenuValidationFinding? {
        report.findings.first { $0.code == code }
    }

    private func utf8ComparisonWork(_ left: String, _ right: String) -> Int {
        let sharedCount = zip(left.utf8, right.utf8).prefix { $0 == $1 }.count
        return sharedCount + 1
    }

    private func assertAuditError(
        _ expected: MenuValidationError,
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? MenuValidationError, expected, file: file, line: line)
        }
    }

    private func contractID(_ value: String) -> MenuValidationContractID {
        MenuValidationContractID(rawValue: value)
    }

    private func elementID(_ value: String) -> MenuElementID {
        MenuElementID(rawValue: value)
    }

    private func commandID(_ value: String) -> MenuCommandID {
        MenuCommandID(rawValue: value)
    }

    private func scenarioID(_ value: String) -> MenuValidationScenarioID {
        MenuValidationScenarioID(rawValue: value)
    }

    private func targetID(_ value: String) -> MenuValidationTargetID {
        MenuValidationTargetID(rawValue: value)
    }

    private func actionID(_ value: String) -> MenuValidationActionID {
        MenuValidationActionID(rawValue: value)
    }

    private func resultID(_ value: String) -> MenuValidationResultID {
        MenuValidationResultID(rawValue: value)
    }
}

private struct MenuValidationFindingSemantic: Hashable {
    let code: MenuValidationFindingCode
    let subject: MenuValidationSubject
    let evidence: MenuValidationFindingEvidence

    init(
        code: MenuValidationFindingCode,
        subject: MenuValidationSubject,
        evidence: MenuValidationFindingEvidence
    ) {
        self.code = code
        self.subject = subject
        self.evidence = evidence
    }

    init(_ finding: MenuValidationFinding) {
        self.init(
            code: finding.code,
            subject: finding.subject,
            evidence: finding.evidence
        )
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelOnCheck: Int
    private var checks = 0

    init(cancelOnCheck: Int) {
        self.cancelOnCheck = cancelOnCheck
    }

    var checkCount: Int {
        lock.withLock { checks }
    }

    func shouldCancel() -> Bool {
        lock.withLock {
            checks += 1
            return checks >= cancelOnCheck
        }
    }
}
