import MacMergeCore
import XCTest

final class WindowArrangementPlanTests: XCTestCase {
    private typealias Plan = WindowArrangementPlan
    private typealias PlanError = WindowArrangementPlanError

    private func ownerID(_ rawValue: UInt64 = 7) -> Plan.OwnerID {
        Plan.OwnerID(rawValue: rawValue)
    }

    private func lineage(_ rawValue: UInt64 = 11) -> Plan.SessionLineage {
        Plan.SessionLineage(rawValue: rawValue)
    }

    private func windowID(_ rawValue: UInt64) -> Plan.WindowID {
        Plan.WindowID(rawValue: rawValue)
    }

    private func tabID(_ rawValue: UInt64) -> Plan.TabID {
        Plan.TabID(rawValue: rawValue)
    }

    private func materialization(_ rawValue: UInt64) -> Plan.MaterializationReference {
        Plan.MaterializationReference(
            identity: Plan.MaterializationID(rawValue: rawValue),
            revision: rawValue
        )
    }

    private func makeTab(
        _ rawValue: UInt64,
        title: String,
        eligibility: Plan.TabbingEligibility = .eligible
    ) throws -> Plan.TabState {
        try Plan.TabState(
            id: tabID(rawValue),
            title: title,
            materialization: materialization(rawValue),
            tabbingEligibility: eligibility
        )
    }

    private func makeWindow(
        _ rawValue: UInt64,
        generation: UInt64 = 0,
        tabs: [Plan.TabState],
        selectedTabRawValue: UInt64,
        split: Plan.SplitConfiguration? = nil,
        eligibility: Plan.TabbingEligibility = .eligible
    ) throws -> Plan.WindowState {
        try Plan.WindowState(
            id: windowID(rawValue),
            revision: Plan.WindowRevision(windowID: windowID(rawValue), generation: generation),
            tabs: tabs,
            selectedTabID: tabID(selectedTabRawValue),
            tabbingEligibility: eligibility,
            split: split
        )
    }

    private func makeState(
        windows: [Plan.WindowState],
        selectedWindowRawValue: UInt64?,
        arrangement: Plan.Arrangement = .separateWindows,
        tabWidth: Plan.TabWidthPreference = .automatic,
        limits: Plan.Limits = .default,
        generation: UInt64 = 0
    ) throws -> Plan.State {
        try Plan.State(
            revision: Plan.SessionRevision(lineage: lineage(), generation: generation),
            ownerID: ownerID(),
            windows: windows,
            selectedWindowID: selectedWindowRawValue.map { windowID($0) },
            arrangement: arrangement,
            tabWidthPreference: tabWidth,
            limits: limits
        )
    }

    private func twoWindowState(generation: UInt64 = 0) throws -> Plan.State {
        let first = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha"), try makeTab(102, title: "Beta")],
            selectedTabRawValue: 101
        )
        let second = try makeWindow(
            2,
            tabs: [try makeTab(201, title: "Gamma")],
            selectedTabRawValue: 201
        )
        return try makeState(windows: [first, second], selectedWindowRawValue: 1, generation: generation)
    }

    private func threeWindowState() throws -> Plan.State {
        let first = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha")],
            selectedTabRawValue: 101
        )
        let second = try makeWindow(
            2,
            tabs: [try makeTab(201, title: "Gamma"), try makeTab(202, title: "Delta")],
            selectedTabRawValue: 201
        )
        let third = try makeWindow(
            3,
            tabs: [try makeTab(301, title: "Epsilon")],
            selectedTabRawValue: 301
        )
        return try makeState(windows: [first, second, third], selectedWindowRawValue: 1)
    }

    private func singleWindowTwoTabState() throws -> Plan.State {
        let only = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha"), try makeTab(102, title: "Beta")],
            selectedTabRawValue: 101
        )
        return try makeState(windows: [only], selectedWindowRawValue: 1)
    }

    private func restorationTab(_ rawValue: UInt64, title: String) throws -> Plan.RestorationTab {
        try Plan.RestorationTab(
            id: tabID(rawValue),
            title: title,
            materialization: materialization(rawValue)
        )
    }

    private func restorationWindow(
        _ rawValue: UInt64,
        tabs: [Plan.RestorationTab],
        selectedTabRawValue: UInt64
    ) throws -> Plan.RestorationWindow {
        try Plan.RestorationWindow(
            id: windowID(rawValue),
            revision: Plan.WindowRevision(windowID: windowID(rawValue), generation: 0),
            tabs: tabs,
            selectedTabID: tabID(selectedTabRawValue)
        )
    }

    private func restorationRequest() throws -> Plan.RestorationRequest {
        let publicationCAS = try Plan.RestorationPublicationCAS(ownerID: ownerID(), expectedEpoch: 0)
        return Plan.RestorationRequest(
            publicationCAS: publicationCAS,
            sessionRevision: Plan.SessionRevision(lineage: lineage(), generation: 0),
            ownerID: ownerID(),
            windows: [
                try restorationWindow(
                    1,
                    tabs: [
                        try restorationTab(101, title: "Alpha"),
                        try restorationTab(102, title: "Beta")
                    ],
                    selectedTabRawValue: 101
                ),
                try restorationWindow(
                    2,
                    tabs: [try restorationTab(201, title: "Gamma")],
                    selectedTabRawValue: 201
                )
            ],
            selectedWindowID: windowID(1)
        )
    }

    private func assertPlanError(
        _ expected: PlanError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? PlanError, expected, file: file, line: line)
        }
    }

    func testSplitAppliesFractionAndAdvancesRevisions() throws {
        let state = try twoWindowState()
        let configuration = try Plan.SplitConfiguration(orientation: .horizontal, fraction: 0.5)
        let request = Plan.SplitRequest(windowID: windowID(1), configuration: configuration)
        let plan = try Plan.plan(.split(request), in: state)
        let repeatPlan = try Plan.plan(.split(request), in: state)

        XCTAssertEqual(plan, repeatPlan)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(plan.successor.revision.generation, 1)
        XCTAssertEqual(plan.successor.revision.lineage, lineage())
        XCTAssertEqual(plan.successor.ownerID, ownerID())
        let original = try XCTUnwrap(state.windows.first(where: { $0.id == windowID(1) }))
        let updated = try XCTUnwrap(plan.successor.windows.first(where: { $0.id == windowID(1) }))
        XCTAssertEqual(updated.split, configuration)
        XCTAssertEqual(updated.revision.generation, original.revision.generation + 1)
        guard case .split(let intent) = plan.effect else {
            return XCTFail("Expected split effect")
        }
        XCTAssertEqual(intent.windowID, windowID(1))
        XCTAssertEqual(intent.configuration, configuration)
        XCTAssertFalse(plan.redactedDescription.contains("Alpha"))
    }

    func testSplitClearRemovesConfiguration() throws {
        let configuration = try Plan.SplitConfiguration(orientation: .vertical, fraction: 0.5)
        let window = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha")],
            selectedTabRawValue: 101,
            split: configuration
        )
        let other = try makeWindow(
            2,
            tabs: [try makeTab(201, title: "Gamma")],
            selectedTabRawValue: 201
        )
        let state = try makeState(windows: [window, other], selectedWindowRawValue: 1)
        let plan = try Plan.plan(.split(Plan.SplitRequest(windowID: windowID(1))), in: state)

        let updated = try XCTUnwrap(plan.successor.windows.first(where: { $0.id == windowID(1) }))
        XCTAssertNil(updated.split)
        guard case .split(let intent) = plan.effect else {
            return XCTFail("Expected split effect")
        }
        XCTAssertEqual(intent.windowID, windowID(1))
        XCTAssertNil(intent.configuration)
    }

    func testSplitIdenticalConfigurationThrowsNoStateChange() throws {
        let state = try twoWindowState()
        assertPlanError(.noStateChange) {
            _ = try Plan.plan(.split(Plan.SplitRequest(windowID: windowID(1))), in: state)
        }
    }

    func testSplitFractionOutsideConfiguredLimitsThrows() throws {
        assertPlanError(.invalidSplitFraction(0.01)) {
            _ = try Plan.SplitConfiguration(orientation: .horizontal, fraction: 0.01)
        }
        let state = try twoWindowState()
        let loose = try Plan.SplitConfiguration(orientation: .horizontal, fraction: 0.1)
        assertPlanError(.invalidSplitFraction(0.1)) {
            _ = try Plan.plan(
                .split(Plan.SplitRequest(windowID: windowID(1), configuration: loose)),
                in: state
            )
        }
    }

    func testTabGroupsSourcesIntoDestination() throws {
        let state = try threeWindowState()
        let request = Plan.TabRequest(
            sourceWindowIDs: [windowID(2), windowID(3)],
            destinationWindowID: windowID(1)
        )
        let plan = try Plan.plan(.tab(request), in: state)

        guard case .tab(let intent) = plan.effect else {
            return XCTFail("Expected tab effect")
        }
        XCTAssertEqual(intent.destinationWindowID, windowID(1))
        XCTAssertEqual(intent.movedTabIDs, [tabID(201), tabID(202), tabID(301)])
        XCTAssertEqual(intent.resultingTabOrder, [tabID(101), tabID(201), tabID(202), tabID(301)])
        XCTAssertEqual(intent.resultingSelection, tabID(101))
    }

    func testTabResultHoldsSingleGroupInvariant() throws {
        let state = try threeWindowState()
        let request = Plan.TabRequest(
            sourceWindowIDs: [windowID(2), windowID(3)],
            destinationWindowID: windowID(1)
        )
        let plan = try Plan.plan(.tab(request), in: state)

        XCTAssertEqual(plan.successor.windows.count, 1)
        XCTAssertEqual(plan.successor.arrangement, .tabbed(destinationWindowID: windowID(1)))
        XCTAssertEqual(plan.successor.selectedWindowID, windowID(1))
        XCTAssertEqual(plan.successor.totalTabCount, 4)
        let grouped = try XCTUnwrap(plan.successor.windows.first)
        XCTAssertEqual(grouped.id, windowID(1))
        XCTAssertEqual(grouped.tabs.map(\.id), [tabID(101), tabID(201), tabID(202), tabID(301)])
        XCTAssertEqual(grouped.selectedTabID, tabID(101))
        XCTAssertFalse(plan.redactedDescription.contains("Gamma"))
        let summary = plan.successor.redacted()
        XCTAssertEqual(summary.windowCount, 1)
        XCTAssertEqual(summary.totalTabCount, 4)
    }

    func testTabMalformedRequestsThrow() throws {
        let state = try twoWindowState()
        assertPlanError(.emptyTabGroup) {
            _ = try Plan.plan(
                .tab(Plan.TabRequest(sourceWindowIDs: [], destinationWindowID: windowID(1))),
                in: state
            )
        }
        assertPlanError(.tabGroupIncludesDestination(windowID(1))) {
            _ = try Plan.plan(
                .tab(Plan.TabRequest(sourceWindowIDs: [windowID(1)], destinationWindowID: windowID(1))),
                in: state
            )
        }
    }

    func testTabIneligibleDestinationWindowThrows() throws {
        let first = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha")],
            selectedTabRawValue: 101
        )
        let second = try makeWindow(
            2,
            tabs: [try makeTab(201, title: "Gamma")],
            selectedTabRawValue: 201,
            eligibility: .ineligible(.policyRestricted)
        )
        let state = try makeState(windows: [first, second], selectedWindowRawValue: 1)
        assertPlanError(.windowTabbingIneligible(windowID(2), .policyRestricted)) {
            _ = try Plan.plan(
                .tab(Plan.TabRequest(sourceWindowIDs: [windowID(2)], destinationWindowID: windowID(1))),
                in: state
            )
        }
    }

    func testTabIneligibleTabThrows() throws {
        let first = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha")],
            selectedTabRawValue: 101
        )
        let second = try makeWindow(
            2,
            tabs: [try makeTab(201, title: "Gamma", eligibility: .ineligible(.modalWorkflow))],
            selectedTabRawValue: 201
        )
        let state = try makeState(windows: [first, second], selectedWindowRawValue: 1)
        assertPlanError(.tabTabbingIneligible(tabID(201), .modalWorkflow)) {
            _ = try Plan.plan(
                .tab(Plan.TabRequest(sourceWindowIDs: [windowID(2)], destinationWindowID: windowID(1))),
                in: state
            )
        }
    }

    func testTabExceedingPerWindowLimitThrows() throws {
        let limits = Plan.Limits(maximumTabsPerWindow: 2)
        let first = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha")],
            selectedTabRawValue: 101
        )
        let second = try makeWindow(
            2,
            tabs: [try makeTab(201, title: "Gamma"), try makeTab(202, title: "Delta")],
            selectedTabRawValue: 201
        )
        let state = try makeState(
            windows: [first, second],
            selectedWindowRawValue: 1,
            limits: limits
        )
        assertPlanError(.tooManyTabs(windowID: windowID(1), maximum: 2)) {
            _ = try Plan.plan(
                .tab(Plan.TabRequest(sourceWindowIDs: [windowID(2)], destinationWindowID: windowID(1))),
                in: state
            )
        }
    }

    func testTilePlansStableRowMajorOrder() throws {
        let state = try twoWindowState()
        let plan = try Plan.plan(.tile(Plan.TileRequest(columns: 2)), in: state)

        guard case .tile(let intent) = plan.effect else {
            return XCTFail("Expected tile effect")
        }
        XCTAssertEqual(intent.columns, 2)
        XCTAssertEqual(intent.rows, 1)
        XCTAssertEqual(intent.windowIDs, [windowID(1), windowID(2)])
        XCTAssertEqual(plan.successor.arrangement, .tiled(columns: 2))
        XCTAssertEqual(plan.successor.selectedWindowID, state.selectedWindowID)
    }

    func testTileInvalidColumnsThrow() throws {
        let state = try twoWindowState()
        assertPlanError(.invalidTileColumns(0, maximum: 8)) {
            _ = try Plan.plan(.tile(Plan.TileRequest(columns: 0)), in: state)
        }
        assertPlanError(.invalidTileColumns(9, maximum: 8)) {
            _ = try Plan.plan(.tile(Plan.TileRequest(columns: 9)), in: state)
        }
    }

    func testTileIdenticalArrangementThrowsNoStateChange() throws {
        let state = try twoWindowState()
        let plan = try Plan.plan(.tile(Plan.TileRequest(columns: 2)), in: state)
        assertPlanError(.noStateChange) {
            _ = try Plan.plan(.tile(Plan.TileRequest(columns: 2)), in: plan.successor)
        }
    }

    func testCascadePlansStrideAndStableOrder() throws {
        let state = try twoWindowState()
        let plan = try Plan.plan(.cascade(Plan.CascadeRequest(stride: 24)), in: state)

        guard case .cascade(let intent) = plan.effect else {
            return XCTFail("Expected cascade effect")
        }
        XCTAssertEqual(intent.stride, 24)
        XCTAssertEqual(intent.windowIDs, [windowID(1), windowID(2)])
        XCTAssertEqual(plan.successor.arrangement, .cascaded(stride: 24))
    }

    func testCascadeStrideOutsideLimitsThrows() throws {
        let state = try twoWindowState()
        assertPlanError(.invalidCascadeStride(1, minimum: 16, maximum: 64)) {
            _ = try Plan.plan(.cascade(Plan.CascadeRequest(stride: 1)), in: state)
        }
    }

    func testDetachMovesTabIntoReservedWindow() throws {
        let state = try singleWindowTwoTabState()
        let reservation = try Plan.WindowReservation(
            id: windowID(9),
            initialRevision: Plan.WindowRevision(windowID: windowID(9), generation: 0)
        )
        let plan = try Plan.plan(
            .detach(
                Plan.DetachRequest(
                    sourceWindowID: windowID(1),
                    tabID: tabID(101),
                    destination: reservation
                )
            ),
            in: state
        )

        guard case .detach(let intent) = plan.effect else {
            return XCTFail("Expected detach effect")
        }
        XCTAssertEqual(intent.sourceWindowID, windowID(1))
        XCTAssertEqual(intent.destinationWindowID, windowID(9))
        XCTAssertEqual(intent.tabID, tabID(101))
        XCTAssertEqual(intent.replacementSourceTabID, tabID(102))
        XCTAssertEqual(plan.successor.windows.count, 2)
        XCTAssertEqual(plan.successor.selectedWindowID, windowID(9))
        let source = try XCTUnwrap(plan.successor.windows.first(where: { $0.id == windowID(1) }))
        let destination = try XCTUnwrap(plan.successor.windows.first(where: { $0.id == windowID(9) }))
        XCTAssertEqual(source.tabs.map(\.id), [tabID(102)])
        XCTAssertEqual(source.selectedTabID, tabID(102))
        XCTAssertEqual(destination.tabs.map(\.id), [tabID(101)])
        XCTAssertEqual(destination.selectedTabID, tabID(101))
    }

    func testDetachOnlyTabThrows() throws {
        let only = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha")],
            selectedTabRawValue: 101
        )
        let state = try makeState(windows: [only], selectedWindowRawValue: 1)
        let reservation = try Plan.WindowReservation(
            id: windowID(9),
            initialRevision: Plan.WindowRevision(windowID: windowID(9), generation: 0)
        )
        assertPlanError(.onlyTabCannotDetach(tabID(101))) {
            _ = try Plan.plan(
                .detach(
                    Plan.DetachRequest(
                        sourceWindowID: windowID(1),
                        tabID: tabID(101),
                        destination: reservation
                    )
                ),
                in: state
            )
        }
    }

    func testMoveTabAcrossWindowsInsertsAtIndex() throws {
        let state = try twoWindowState()
        let plan = try Plan.plan(
            .move(
                Plan.MoveRequest(
                    sourceWindowID: windowID(1),
                    destinationWindowID: windowID(2),
                    tabID: tabID(101),
                    insertionIndex: 1
                )
            ),
            in: state
        )

        guard case .move(let intent) = plan.effect else {
            return XCTFail("Expected move effect")
        }
        XCTAssertEqual(intent.destinationInsertionIndex, 1)
        XCTAssertEqual(intent.resultingSourceTabOrder, [tabID(102)])
        XCTAssertEqual(intent.resultingDestinationTabOrder, [tabID(201), tabID(101)])
        XCTAssertEqual(intent.resultingDestinationSelection, tabID(101))
        let source = try XCTUnwrap(plan.successor.windows.first(where: { $0.id == windowID(1) }))
        let destination = try XCTUnwrap(plan.successor.windows.first(where: { $0.id == windowID(2) }))
        XCTAssertEqual(source.tabs.map(\.id), [tabID(102)])
        XCTAssertEqual(destination.tabs.map(\.id), [tabID(201), tabID(101)])
        XCTAssertEqual(plan.successor.selectedWindowID, windowID(2))
    }

    func testMoveInvalidInsertionIndexThrows() throws {
        let state = try twoWindowState()
        assertPlanError(.invalidInsertionIndex(99, windowID: windowID(2))) {
            _ = try Plan.plan(
                .move(
                    Plan.MoveRequest(
                        sourceWindowID: windowID(1),
                        destinationWindowID: windowID(2),
                        tabID: tabID(101),
                        insertionIndex: 99
                    )
                ),
                in: state
            )
        }
    }

    func testMoveWithoutOrderOrSelectionChangeThrows() throws {
        let state = try singleWindowTwoTabState()
        assertPlanError(.noStateChange) {
            _ = try Plan.plan(
                .move(
                    Plan.MoveRequest(
                        sourceWindowID: windowID(1),
                        destinationWindowID: windowID(1),
                        tabID: tabID(101),
                        insertionIndex: 0,
                        selectsMovedTab: false
                    )
                ),
                in: state
            )
        }
    }

    func testMergeCollapsesAllWindowsIntoDestination() throws {
        let state = try threeWindowState()
        let plan = try Plan.plan(.merge(Plan.MergeRequest(destinationWindowID: windowID(1))), in: state)

        guard case .merge(let intent) = plan.effect else {
            return XCTFail("Expected merge effect")
        }
        XCTAssertEqual(intent.destinationWindowID, windowID(1))
        XCTAssertEqual(intent.movedTabCount, 3)
        XCTAssertEqual(intent.resultingTabOrder, [tabID(101), tabID(201), tabID(202), tabID(301)])
        XCTAssertEqual(intent.resultingSelection, tabID(101))
        XCTAssertEqual(intent.closedWindowIDs, [windowID(2), windowID(3)])
        XCTAssertEqual(plan.successor.windows.count, 1)
        XCTAssertEqual(plan.successor.arrangement, .separateWindows)
        XCTAssertEqual(plan.successor.selectedWindowID, windowID(1))
        XCTAssertEqual(plan.successor.totalTabCount, 4)
    }

    func testTabbedArrangementWithUnknownDestinationThrows() throws {
        let only = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha")],
            selectedTabRawValue: 101
        )
        assertPlanError(.selectedWindowNotFound(windowID(999))) {
            _ = try makeState(
                windows: [only],
                selectedWindowRawValue: 1,
                arrangement: .tabbed(destinationWindowID: windowID(999))
            )
        }
    }

    func testOwnerSessionCASLineageAdvancesAndRejectsStaleState() throws {
        let state = try twoWindowState(generation: 3)
        let configuration = try Plan.SplitConfiguration(orientation: .horizontal, fraction: 0.5)
        let plan = try Plan.plan(
            .split(Plan.SplitRequest(windowID: windowID(1), configuration: configuration)),
            in: state
        )

        XCTAssertEqual(plan.expectedStateCAS, state.cas)
        XCTAssertEqual(plan.receipt.expectedStateCAS, state.cas)
        XCTAssertEqual(plan.receipt.successorStateCAS, plan.successor.cas)
        XCTAssertEqual(plan.successor.revision.lineage, lineage())
        XCTAssertEqual(plan.successor.revision.generation, 4)
        XCTAssertEqual(plan.successor.ownerID, ownerID())
        XCTAssertNoThrow(try plan.validateCurrentState(state))
        do {
            try plan.validateCurrentState(plan.successor)
            XCTFail("Expected stale state")
        } catch let error as PlanError {
            guard case .staleState = error else {
                return XCTFail("Expected staleState, got \(error)")
            }
        }

        let publicationCAS = try Plan.RestorationPublicationCAS(ownerID: ownerID(), expectedEpoch: 5)
        XCTAssertEqual(publicationCAS.successorEpoch, 6)
        XCTAssertTrue(publicationCAS.matches(ownerID: ownerID(), epoch: 5))
        XCTAssertFalse(publicationCAS.matches(ownerID: ownerID(), epoch: 6))
        XCTAssertNoThrow(try publicationCAS.validate(ownerID: ownerID(), epoch: 5))
        assertPlanError(
            .staleRestorationPublication(
                expectedOwnerID: ownerID(),
                expectedEpoch: 5,
                actualOwnerID: ownerID(),
                actualEpoch: 6
            )
        ) {
            try publicationCAS.validate(ownerID: ownerID(), epoch: 6)
        }
        assertPlanError(.restorationPublicationEpochExhausted(ownerID())) {
            _ = try Plan.RestorationPublicationCAS(ownerID: ownerID(), expectedEpoch: UInt64.max)
        }
    }

    func testWidthAndArrangementValidation() throws {
        let first = try makeWindow(
            1,
            tabs: [try makeTab(101, title: "Alpha")],
            selectedTabRawValue: 101
        )
        assertPlanError(.invalidTabWidth(1000)) {
            _ = try makeState(
                windows: [first],
                selectedWindowRawValue: 1,
                tabWidth: .fixed(1000)
            )
        }
        let validWidth = try makeState(
            windows: [first],
            selectedWindowRawValue: 1,
            tabWidth: .fixed(100)
        )
        XCTAssertEqual(validWidth.tabWidthPreference.fixedWidth, 100)
        assertPlanError(.invalidArrangement("empty session must use separate windows")) {
            _ = try makeState(
                windows: [],
                selectedWindowRawValue: nil,
                arrangement: .tiled(columns: 2)
            )
        }
    }

    func testRestorationIsDeterministicWithOrderedMaterializations() throws {
        let request = try restorationRequest()
        let firstPlan = try Plan.planRestoration(request)
        let secondPlan = try Plan.planRestoration(request)

        XCTAssertEqual(firstPlan, secondPlan)
        XCTAssertEqual(firstPlan.materializations.map(\.ordinal), [0, 1, 2])
        XCTAssertEqual(firstPlan.materializations.map(\.tabID), [tabID(101), tabID(102), tabID(201)])
        XCTAssertEqual(firstPlan.publicationCAS, request.publicationCAS)

        let itemReceipts = firstPlan.materializations.map {
            Plan.RestorationItemReceipt(request: $0, outcome: .restored($0.materialization))
        }
        let firstReceipt = try firstPlan.receipt(itemReceipts)
        let secondReceipt = try secondPlan.receipt(itemReceipts)

        XCTAssertEqual(firstReceipt, secondReceipt)
        XCTAssertEqual(firstReceipt.restoredState.totalTabCount, 3)
        XCTAssertEqual(firstReceipt.restoredState.selectedWindowID, windowID(1))
        XCTAssertEqual(firstReceipt.restoredState.arrangement, .separateWindows)
        XCTAssertEqual(firstReceipt.restoredTabIDs, [tabID(101), tabID(102), tabID(201)])
        XCTAssertTrue(firstReceipt.skippedTabIDs.isEmpty)
        XCTAssertTrue(firstReceipt.failedTabIDs.isEmpty)
        XCTAssertFalse(firstReceipt.redactedDescription.contains("Alpha"))
        let redacted = firstReceipt.redacted()
        XCTAssertEqual(redacted.windowCount, 2)
        XCTAssertEqual(redacted.totalTabCount, 3)
    }

    func testCancellationAbortsPlanning() throws {
        let state = try twoWindowState()
        assertPlanError(.cancelled) {
            _ = try Plan.plan(
                .tile(Plan.TileRequest(columns: 2)),
                in: state,
                cancellationCheck: { throw CancellationError() }
            )
        }
        let request = try restorationRequest()
        assertPlanError(.cancelled) {
            _ = try Plan.planRestoration(request, cancellationCheck: { throw CancellationError() })
        }
    }
}
