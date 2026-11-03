import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ConflictPaneCommandsTests: XCTestCase {
    func testPaneRoleChoiceAndCapabilityMapping() {
        XCTAssertEqual(ConflictPaneCommands.Pane.allCases, [.base, .theirs, .mine])
        XCTAssertEqual(ConflictPaneCommands.Pane.base.rawValue, "base")
        XCTAssertEqual(ConflictPaneCommands.Pane.base.role, .base)
        XCTAssertEqual(ConflictPaneCommands.Pane.theirs.role, .theirs)
        XCTAssertEqual(ConflictPaneCommands.Pane.mine.role, .mine)
        XCTAssertEqual(ConflictPaneCommands.Pane.base.choice, .base)
        XCTAssertEqual(ConflictPaneCommands.Pane.theirs.choice, .theirs)
        XCTAssertEqual(ConflictPaneCommands.Pane.mine.choice, .mine)
        XCTAssertEqual(ConflictPaneCommands.Pane.base.requiredCapability, .chooseBase)
        XCTAssertEqual(ConflictPaneCommands.Pane.theirs.requiredCapability, .chooseTheirs)
        XCTAssertEqual(ConflictPaneCommands.Pane.mine.requiredCapability, .chooseMine)
    }

    func testNavigationAvailabilityCoversAllFiveCommands() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let first = try XCTUnwrap(plan.navigation.first)
        let last = try XCTUnwrap(plan.navigation.last)
        let selection = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: first.id
        )

        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .firstConflict, in: plan, selection: selection),
            .enabled
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .currentConflict, in: plan, selection: selection),
            .enabled
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .previousConflict, in: plan, selection: selection),
            .disabled(.noTargetConflict)
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .nextConflict, in: plan, selection: selection),
            .enabled
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .lastConflict, in: plan, selection: selection),
            .enabled
        )

        let selectedLast = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: last.id
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .nextConflict, in: plan, selection: selectedLast),
            .disabled(.noTargetConflict)
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .previousConflict, in: plan, selection: selectedLast),
            .enabled
        )

        let states = try ConflictPaneCommands.states(in: plan, selection: selection)
        XCTAssertEqual(states.first, .enabled)
        XCTAssertEqual(states.current, .enabled)
        XCTAssertEqual(states.previous, .disabled(.noTargetConflict))
        XCTAssertEqual(states.next, .enabled)
        XCTAssertEqual(states.last, .enabled)
    }

    func testNavigationResolveReturnsBoundReceipts() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let first = try XCTUnwrap(plan.navigation.first)
        let last = try XCTUnwrap(plan.navigation.last)
        let selection = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: first.id
        )

        let resolvedFirst = try ConflictPaneCommands.resolve(
            .firstConflict,
            in: plan,
            selection: selection,
            validating: snapshot
        )
        guard case .navigation(let firstPlan) = resolvedFirst else {
            return XCTFail("Expected navigation plan")
        }
        XCTAssertEqual(firstPlan.target, first)
        XCTAssertTrue(firstPlan.canNavigate)
        XCTAssertEqual(firstPlan.snapshotCAS, plan.snapshotCAS)
        XCTAssertEqual(resolvedFirst.executorContract, .required)
        XCTAssertFalse(resolvedFirst.authorizesMutation)
        XCTAssertEqual(
            try ConflictPaneCommands.resolve(
                .firstConflict,
                in: plan,
                selection: selection,
                validating: snapshot
            ),
            resolvedFirst
        )

        let resolvedCurrent = try ConflictPaneCommands.resolve(
            .currentConflict,
            in: plan,
            selection: selection,
            validating: snapshot
        )
        guard case .navigation(let currentPlan) = resolvedCurrent else {
            return XCTFail("Expected navigation plan")
        }
        XCTAssertEqual(currentPlan.target, first)

        let resolvedNext = try ConflictPaneCommands.resolve(
            .nextConflict,
            in: plan,
            selection: selection,
            validating: snapshot
        )
        guard case .navigation(let nextPlan) = resolvedNext else {
            return XCTFail("Expected navigation plan")
        }
        XCTAssertEqual(nextPlan.target, last)

        let resolvedLast = try ConflictPaneCommands.resolve(
            .lastConflict,
            in: plan,
            selection: selection,
            validating: snapshot
        )
        guard case .navigation(let lastPlan) = resolvedLast else {
            return XCTFail("Expected navigation plan")
        }
        XCTAssertEqual(lastPlan.target, last)

        let resolvedPrevious = try ConflictPaneCommands.resolve(
            .previousConflict,
            in: plan,
            selection: selection,
            validating: snapshot
        )
        guard case .navigation(let previousPlan) = resolvedPrevious else {
            return XCTFail("Expected navigation plan")
        }
        XCTAssertNil(previousPlan.target)
        XCTAssertFalse(previousPlan.canNavigate)
    }

    func testChooseAndApplyResolvePerPane() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let selection = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: target.id
        )

        for pane in ConflictPaneCommands.Pane.allCases {
            XCTAssertEqual(
                ConflictPaneCommands.availability(
                    of: .choose(pane, target.id),
                    in: plan,
                    selection: selection
                ),
                .enabled
            )
            XCTAssertEqual(
                ConflictPaneCommands.availability(
                    of: .apply(pane, target.id),
                    in: plan,
                    selection: selection
                ),
                .enabled
            )

            let resolvedChoose = try ConflictPaneCommands.resolve(
                .choose(pane, target.id),
                in: plan,
                selection: selection,
                validating: snapshot
            )
            guard case .resolution(let choosePlan) = resolvedChoose else {
                return XCTFail("Expected resolution plan for \(pane)")
            }
            XCTAssertEqual(choosePlan.choice, pane.choice)
            XCTAssertEqual(choosePlan.action, .choose)
            XCTAssertFalse(resolvedChoose.authorizesMutation)
            XCTAssertEqual(resolvedChoose.snapshotCAS, plan.snapshotCAS)
            XCTAssertEqual(resolvedChoose.executorContract, .required)
            XCTAssertEqual(
                choosePlan.selectedSourceRevision,
                try XCTUnwrap(plan.roleReference(for: pane.role)?.sourceRevision)
            )

            let resolvedApply = try ConflictPaneCommands.resolve(
                .apply(pane, target.id),
                in: plan,
                selection: selection,
                validating: snapshot
            )
            guard case .resolution(let applyPlan) = resolvedApply else {
                return XCTFail("Expected resolution plan for \(pane)")
            }
            XCTAssertEqual(applyPlan.choice, pane.choice)
            XCTAssertEqual(applyPlan.action, .apply)
            XCTAssertTrue(resolvedApply.authorizesMutation)

            let states = try ConflictPaneCommands.states(in: plan, selection: selection)
            XCTAssertEqual(states.availability(for: pane, action: .choose), .enabled)
            XCTAssertEqual(states.availability(for: pane, action: .apply), .enabled)
        }
    }

    func testTwoWayBaseIsUnavailableForChooseAndApply() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        XCTAssertEqual(plan.mapping.topology, .twoWay)
        let target = try XCTUnwrap(plan.navigation.first)
        let selection = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: target.id
        )

        let states = try ConflictPaneCommands.states(in: plan, selection: selection)
        XCTAssertEqual(states.chooseBase, .disabled(.baseUnavailableInTwoWay))
        XCTAssertEqual(states.applyBase, .disabled(.baseUnavailableInTwoWay))
        XCTAssertFalse(states.chooseBase.isEnabled)
        XCTAssertFalse(states.applyBase.isEnabled)
        XCTAssertEqual(states.chooseTheirs, .enabled)
        XCTAssertEqual(states.chooseMine, .enabled)
        XCTAssertEqual(states.applyTheirs, .enabled)
        XCTAssertEqual(states.applyMine, .enabled)

        XCTAssertEqual(
            ConflictPaneCommands.availability(
                of: .choose(.base, target.id),
                in: plan,
                selection: selection
            ),
            .disabled(.baseUnavailableInTwoWay)
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(
                of: .apply(.base, target.id),
                in: plan,
                selection: selection
            ),
            .disabled(.baseUnavailableInTwoWay)
        )
    }

    func testReadOnlyGatesApplyButNotChooseOrNavigation() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source, isReadOnly: true)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let selection = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: target.id
        )
        let states = try ConflictPaneCommands.states(in: plan, selection: selection)

        XCTAssertEqual(states.first, .enabled)
        XCTAssertEqual(states.chooseBase, .enabled)
        XCTAssertEqual(states.chooseTheirs, .enabled)
        XCTAssertEqual(states.chooseMine, .enabled)
        XCTAssertEqual(states.applyBase, .disabled(.readOnlyDocument))
        XCTAssertEqual(states.applyTheirs, .disabled(.readOnlyDocument))
        XCTAssertEqual(states.applyMine, .disabled(.readOnlyDocument))
        XCTAssertFalse(states.applyMine.isEnabled)

        XCTAssertEqual(
            ConflictPaneCommands.availability(
                of: .apply(.mine, target.id),
                in: plan,
                selection: selection
            ),
            .disabled(.readOnlyDocument)
        )
    }

    func testStaleSelectionDisablesCommandsWithoutThrowing() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let staleSelection = ConflictComparisonSelectionState(
            snapshot: .init(identity: snapshot.identity, generation: snapshot.generation + 1),
            selectedConflictID: target.id
        )

        for command in [
            ConflictPaneCommands.Command.firstConflict,
            .currentConflict,
            .previousConflict,
            .nextConflict,
            .lastConflict,
            .clearSelection,
            .select(target.id),
            .choose(.mine, target.id),
            .apply(.mine, target.id)
        ] as [ConflictPaneCommands.Command] {
            let availability = ConflictPaneCommands.availability(
                of: command,
                in: plan,
                selection: staleSelection
            )
            XCTAssertEqual(availability, .disabled(.staleSelection))
            XCTAssertFalse(availability.isEnabled)
            XCTAssertEqual(availability.disabledReason, .staleSelection)
        }

        let staleStates = try ConflictPaneCommands.states(in: plan, selection: staleSelection)
        XCTAssertEqual(staleStates.first, .disabled(.staleSelection))
        XCTAssertEqual(staleStates.chooseMine, .disabled(.staleSelection))
        XCTAssertEqual(staleStates.applyMine, .disabled(.staleSelection))

        let emptySelection = ConflictComparisonSelectionState(snapshot: plan.snapshotCAS.reference)
        XCTAssertEqual(
            ConflictPaneCommands.availability(
                of: .choose(.mine, target.id),
                in: plan,
                selection: emptySelection
            ),
            .enabled
        )
        let emptyStates = try ConflictPaneCommands.states(in: plan, selection: emptySelection)
        XCTAssertEqual(emptyStates.chooseBase, .disabled(.noTargetConflict))
        XCTAssertEqual(emptyStates.applyMine, .disabled(.noTargetConflict))
    }

    func testForgedTargetAvailabilityIsNotEnabled() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let forged = try ConflictNavigationTarget(
            generation: target.generation,
            index: target.index,
            sourceLineRange: target.sourceLineRange,
            markerWidth: target.id.markerWidth + 1,
            topology: target.id.topology,
            currentLabel: target.id.currentLabel,
            baseLabel: target.id.baseLabel,
            incomingLabel: target.id.incomingLabel,
            paneContributions: target.paneContributions
        )
        let selection = ConflictComparisonSelectionState(snapshot: plan.snapshotCAS.reference)

        let selectAvailability = ConflictPaneCommands.availability(
            of: .select(forged.id),
            in: plan,
            selection: selection
        )
        XCTAssertEqual(selectAvailability, .disabled(.noTargetConflict))
        XCTAssertFalse(selectAvailability.isEnabled)

        for pane in ConflictPaneCommands.Pane.allCases {
            XCTAssertFalse(
                ConflictPaneCommands.availability(
                    of: .choose(pane, forged.id),
                    in: plan,
                    selection: selection
                ).isEnabled
            )
            XCTAssertEqual(
                ConflictPaneCommands.availability(
                    of: .apply(pane, forged.id),
                    in: plan,
                    selection: selection
                ),
                .disabled(.noTargetConflict)
            )
        }

        XCTAssertThrowsError(
            try ConflictPaneCommands.resolve(
                .select(forged.id),
                in: plan,
                selection: selection,
                validating: snapshot
            )
        ) { error in
            XCTAssertEqual(
                error as? ConflictComparisonWorkflowError,
                .staleConflictIdentity(forged.id)
            )
        }
    }

    func testMissingCapabilitiesDisableWithExactReasons() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let selection = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: target.id
        )

        let noNavigateSnapshot = rebuilding(
            snapshot,
            capabilities: ConflictComparisonCapability.all.subtracting(.navigate)
        )
        let noNavigatePlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: noNavigateSnapshot))
        XCTAssertEqual(
            ConflictPaneCommands.availability(
                of: .firstConflict,
                in: noNavigatePlan,
                selection: .init(snapshot: noNavigatePlan.snapshotCAS.reference)
            ),
            .disabled(.missingNavigateCapability)
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(
                of: .clearSelection,
                in: noNavigatePlan,
                selection: .init(snapshot: noNavigatePlan.snapshotCAS.reference)
            ),
            .disabled(.missingNavigateCapability)
        )

        let noChooseMine = rebuilding(
            snapshot,
            capabilities: ConflictComparisonCapability.all.subtracting(.chooseMine)
        )
        let noChooseMinePlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: noChooseMine))
        XCTAssertEqual(
            ConflictPaneCommands.availability(
                of: .choose(.mine, target.id),
                in: noChooseMinePlan,
                selection: selection
            ),
            .disabled(.missingChooseCapability(.mine))
        )

        let noApply = rebuilding(
            snapshot,
            capabilities: ConflictComparisonCapability.all.subtracting(.applyResolution)
        )
        let noApplyPlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: noApply))
        XCTAssertEqual(
            ConflictPaneCommands.availability(
                of: .apply(.mine, target.id),
                in: noApplyPlan,
                selection: selection
            ),
            .disabled(.missingApplyCapability)
        )
    }

    func testResolveValidatesCurrentSnapshotBeforePlanning() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let selection = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: target.id
        )
        let changed = rebuilding(snapshot, generation: snapshot.generation + 1)

        XCTAssertThrowsError(
            try ConflictPaneCommands.resolve(
                .firstConflict,
                in: plan,
                selection: selection,
                validating: changed
            )
        ) { error in
            XCTAssertEqual(
                error as? ConflictComparisonWorkflowError,
                .staleGeneration(expected: snapshot.generation, actual: snapshot.generation + 1)
            )
        }
        XCTAssertThrowsError(
            try ConflictPaneCommands.resolve(
                .choose(.mine, target.id),
                in: plan,
                selection: selection,
                validating: changed
            )
        )
    }

    func testClearSelectionAndSelectAvailability() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let selection = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: target.id
        )

        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .clearSelection, in: plan, selection: selection),
            .enabled
        )
        XCTAssertEqual(
            ConflictPaneCommands.availability(of: .select(target.id), in: plan, selection: selection),
            .enabled
        )

        let cleared = try ConflictPaneCommands.resolve(
            .clearSelection,
            in: plan,
            selection: selection,
            validating: snapshot
        )
        guard case .navigation(let clearedPlan) = cleared else {
            return XCTFail("Expected navigation plan")
        }
        XCTAssertNil(clearedPlan.target)
        XCTAssertFalse(clearedPlan.canNavigate)
        XCTAssertFalse(cleared.authorizesMutation)

        let selected = try ConflictPaneCommands.resolve(
            .select(target.id),
            in: plan,
            selection: selection,
            validating: snapshot
        )
        guard case .navigation(let selectedPlan) = selected else {
            return XCTFail("Expected navigation plan")
        }
        XCTAssertEqual(selectedPlan.target, target)
        XCTAssertEqual(selected.snapshotCAS, plan.snapshotCAS)
        XCTAssertEqual(selected.executorContract, .required)
    }

    private static let namespaceUUID = uuid("00000000-0000-0000-0000-000000000001")
    private static let snapshotUUID = uuid("00000000-0000-0000-0000-000000000002")

    private static let twoWaySource =
        [
            "before",
            "<<<<<<< mine-one",
            "mine one",
            "=======",
            "theirs one",
            ">>>>>>> theirs-one",
            "between",
            "<<<<<<< mine-two",
            "mine two",
            "=======",
            "theirs two",
            ">>>>>>> theirs-two",
            "after"
        ].joined(separator: "\n") + "\n"

    private static let diff3Source =
        [
            "before",
            "<<<<<<< mine-one",
            "mine one",
            "||||||| base-one",
            "base one",
            "=======",
            "theirs one",
            ">>>>>>> theirs-one",
            "between",
            "<<<<<<< mine-two",
            "mine two",
            "||||||| base-two",
            "base two",
            "=======",
            "theirs two",
            ">>>>>>> theirs-two",
            "after"
        ].joined(separator: "\n") + "\n"

    private func makeSnapshot(
        source: String = ConflictPaneCommandsTests.twoWaySource,
        isReadOnly: Bool = false,
        capabilities: ConflictComparisonCapability = .all
    ) throws -> ConflictComparisonParsedDocumentSnapshot {
        let parseResult = try ConflictFileParser.parse(source)
        let documentRevision = revision(
            text: source,
            identity: .init(namespace: Self.namespaceUUID, value: "document"),
            revision: 7
        )
        var roles: [ConflictComparisonRoleSnapshot] = []
        if let base = parseResult.baseText {
            roles.append(roleSnapshot(.base, text: base))
        }
        roles.append(roleSnapshot(.theirs, text: parseResult.incomingText))
        roles.append(roleSnapshot(.mine, text: parseResult.currentText))
        return ConflictComparisonParsedDocumentSnapshot(
            identity: .init(rawValue: Self.snapshotUUID),
            generation: 42,
            documentSourceRevision: documentRevision,
            parseResultSourceRevision: documentRevision,
            parseResult: parseResult,
            roleSnapshots: roles,
            isReadOnly: isReadOnly,
            capabilities: capabilities
        )
    }

    private func rebuilding(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot,
        generation: UInt64? = nil,
        isReadOnly: Bool? = nil,
        capabilities: ConflictComparisonCapability? = nil
    ) -> ConflictComparisonParsedDocumentSnapshot {
        ConflictComparisonParsedDocumentSnapshot(
            identity: snapshot.identity,
            generation: generation ?? snapshot.generation,
            documentSourceRevision: snapshot.documentSourceRevision,
            parseResultSourceRevision: snapshot.parseResultSourceRevision,
            parseResult: snapshot.parseResult,
            roleSnapshots: snapshot.roleSnapshots,
            isReadOnly: isReadOnly ?? snapshot.isReadOnly,
            capabilities: capabilities ?? snapshot.capabilities
        )
    }

    private func roleSnapshot(
        _ role: ConflictComparisonRole,
        text: String
    ) -> ConflictComparisonRoleSnapshot {
        let number: UInt64 =
            switch role {
            case .base: 10
            case .theirs: 11
            case .mine: 12
            }
        return ConflictComparisonRoleSnapshot(
            role: role,
            sourceRevision: revision(
                text: text,
                identity: .init(namespace: Self.namespaceUUID, value: "role.\(role.rawValue)"),
                revision: number
            ),
            text: text
        )
    }

    private func revision(
        text: String,
        identity: ConflictComparisonSourceIdentity,
        revision: UInt64
    ) -> ConflictComparisonSourceRevision {
        ConflictComparisonSourceRevision(
            identity: identity,
            revision: revision,
            utf8ByteCount: text.utf8.count,
            contentSHA256: Array(SHA256.hash(data: Data(text.utf8)))
        )
    }

    private static func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
