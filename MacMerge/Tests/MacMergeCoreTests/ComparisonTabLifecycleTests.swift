import Foundation
import MacMergeCore
import XCTest

final class ComparisonTabLifecycleTests: XCTestCase {
    typealias Lifecycle = ComparisonTabLifecycle
    typealias LifecycleError = ComparisonTabLifecycleError

    func testPublicInventoriesValueSemanticsAndContracts() throws {
        XCTAssertEqual(
            Lifecycle.Limit.allCases,
            [
                .windows, .tabsPerWindow, .totalTabs, .restorationItems, .titleUTF8Bytes,
                .restorationCodeUTF8Bytes, .restorationMessageUTF8Bytes,
                .aggregateStringUTF8Bytes, .tabWidthRange, .workUnits,
                .cancellationCheckInterval
            ]
        )
        XCTAssertEqual(Lifecycle.CloseScope.allCases, [.current, .others, .left, .right])
        XCTAssertEqual(
            Lifecycle.CloseVetoReason.allCases,
            [.activeOperation, .ownerRejected, .policyRestricted]
        )
        XCTAssertEqual(
            Lifecycle.RestorationSkipReason.allCases,
            [.userDeclined, .unsupportedContent, .unavailableSource, .policyRestricted]
        )

        XCTAssertFalse(Lifecycle.CloseVeto.none.isVetoed)
        XCTAssertNil(Lifecycle.CloseVeto.none.reason)
        XCTAssertTrue(Lifecycle.CloseVeto.vetoed(.ownerRejected).isVetoed)
        XCTAssertEqual(Lifecycle.CloseVeto.vetoed(.ownerRejected).reason, .ownerRejected)
        XCTAssertNil(Lifecycle.TabWidthPreference.automatic.fixedWidth)
        XCTAssertEqual(Lifecycle.TabWidthPreference.fixed(144).fixedWidth, 144)

        let materializationIDs = [materializationID(2), materializationID(1)].sorted()
        let ownerIDs = [ownerID(2), ownerID(1)].sorted()
        XCTAssertEqual(materializationIDs, [materializationID(1), materializationID(2)])
        XCTAssertEqual(ownerIDs, [ownerID(1), ownerID(2)])
        XCTAssertEqual(
            try JSONDecoder().decode(
                Lifecycle.MaterializationID.self,
                from: JSONEncoder().encode(materializationID(9))
            ),
            materializationID(9)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                Lifecycle.RestorationOwnerID.self,
                from: JSONEncoder().encode(ownerID(10))
            ),
            ownerID(10)
        )

        let contract = Lifecycle.ExecutorContract.required
        XCTAssertEqual(contract.stateCAS, .compareExactSnapshotThenReplaceOnce)
        XCTAssertEqual(contract.closing, .authorizeAllTargetsBeforeAtomicStateReplacement)
        XCTAssertEqual(
            contract.materialization,
            .materializeNativeWindowWithoutOwningComparisonContent
        )
        XCTAssertEqual(
            contract.cancellation,
            .cancellationBeforeMutationLeavesOwnerStateUnchanged
        )
        XCTAssertEqual(
            Lifecycle.MaterializationContract.required.materialization,
            .materializeValidatedSessionStateWithoutPersistenceOrUIAssumptions
        )
        XCTAssertEqual(
            Lifecycle.MaterializationContract.required.publication,
            .atomicallyCompareOwnerAndEpochThenPublishCanonicalReceiptOrderOnceAfterAllOutcomes
        )
        requireSendable(contract)
        requireSendable(LifecycleError.cancelled)
    }

    func testStatePreservesWindowTabSelectionMetadataAndCommandProjection() throws {
        let decomposedTitle = "Cafe\u{301}"
        let first = try tab(
            1,
            title: decomposedTitle,
            materializationRevision: 8,
            dirty: true,
            veto: .vetoed(.activeOperation),
            restorable: false,
            eligibility: .ineligible(.unsupportedContent)
        )
        let second = try tab(2, title: "Second")
        let window = try self.window(
            10,
            generation: 4,
            tabs: [first, second],
            selected: 1,
            restorable: false,
            eligibility: .ineligible(.transientWindow)
        )
        let state = try self.state(
            generation: 7,
            windows: [window],
            selectedWindow: 10,
            width: .fixed(120)
        )

        XCTAssertEqual(state.revision, revision(lineage: 1, generation: 7))
        XCTAssertEqual(state.windows, [window])
        XCTAssertEqual(state.selectedWindow, window)
        XCTAssertEqual(state.selectedTab, first)
        XCTAssertEqual(state.totalTabCount, 2)
        XCTAssertEqual(state.tabWidthPreference, .fixed(120))
        XCTAssertEqual(first.title, "Café")
        XCTAssertEqual(first.materialization, materialization(1, revision: 8))
        XCTAssertTrue(first.requiresCloseConfirmation)
        XCTAssertTrue(first.isCloseVetoed)
        XCTAssertEqual(first.closeVeto.reason, .activeOperation)

        let snapshot = try state.commandStateSnapshot()
        XCTAssertEqual(snapshot.lineage, lineage(1))
        XCTAssertEqual(snapshot.generation, 7)
        XCTAssertEqual(snapshot.keyWindowID, windowID(10))
        XCTAssertEqual(snapshot.totalTabCount, 2)
        XCTAssertEqual(snapshot.dirtyTabIDs, [tabID(1)])
        XCTAssertEqual(snapshot.closeVetoedTabIDs, [tabID(1)])
        XCTAssertEqual(snapshot.nonRestorableWindowIDs, [windowID(10)])
        XCTAssertEqual(snapshot.nonRestorableTabIDs, [tabID(1)])
        XCTAssertEqual(snapshot.windows[0].tabbingEligibility, .ineligible(.transientWindow))
        XCTAssertEqual(snapshot.windows[0].tabs[0].tabbingEligibility, .ineligible(.unsupportedContent))
    }

    func testWindowStateReservationAndStateShapeGuardsAreIsolated() throws {
        let one = try tab(1)
        let two = try tab(2)

        assertError(.windowRevisionIdentityMismatch(expected: windowID(1), actual: windowID(2))) {
            _ = try Lifecycle.WindowState(
                id: windowID(1),
                revision: windowRevision(2, generation: 0),
                tabs: [one],
                selectedTabID: tabID(1)
            )
        }
        assertError(.emptyWindow(windowID(1))) {
            _ = try Lifecycle.WindowState(
                id: windowID(1),
                revision: windowRevision(1, generation: 0),
                tabs: [],
                selectedTabID: tabID(1)
            )
        }
        assertError(.duplicateTabID(tabID(1))) {
            _ = try Lifecycle.WindowState(
                id: windowID(1),
                revision: windowRevision(1, generation: 0),
                tabs: [one, one],
                selectedTabID: tabID(1)
            )
        }
        assertError(.selectedTabNotFound(windowID: windowID(1), tabID: tabID(9))) {
            _ = try Lifecycle.WindowState(
                id: windowID(1),
                revision: windowRevision(1, generation: 0),
                tabs: [one],
                selectedTabID: tabID(9)
            )
        }
        assertError(.windowRevisionIdentityMismatch(expected: windowID(1), actual: windowID(2))) {
            _ = try Lifecycle.WindowReservation(
                id: windowID(1),
                initialRevision: windowRevision(2, generation: 0)
            )
        }
        assertError(.invalidInitialWindowRevision(windowID(1))) {
            _ = try Lifecycle.WindowReservation(
                id: windowID(1),
                initialRevision: windowRevision(1, generation: 1)
            )
        }

        let firstWindow = try window(1, tabs: [one], selected: 1)
        let secondWindow = try window(2, tabs: [two], selected: 2)
        assertError(.selectedWindowNotFound(windowID(9))) {
            _ = try self.state(windows: [], selectedWindow: 9)
        }
        assertError(.missingSelectedWindow) {
            _ = try self.state(windows: [firstWindow], selectedWindow: nil)
        }
        assertError(.selectedWindowNotFound(windowID(9))) {
            _ = try self.state(windows: [firstWindow], selectedWindow: 9)
        }
        assertError(.duplicateWindowID(windowID(1))) {
            _ = try self.state(windows: [firstWindow, firstWindow], selectedWindow: 1)
        }
        let duplicateTabWindow = try window(2, tabs: [one], selected: 1)
        assertError(.duplicateTabID(tabID(1))) {
            _ = try self.state(
                windows: [firstWindow, duplicateTabWindow],
                selectedWindow: 1
            )
        }
        assertError(.tooManyWindows(maximum: 1)) {
            _ = try self.state(
                windows: [firstWindow, secondWindow],
                selectedWindow: 1,
                limits: Lifecycle.Limits(maximumWindowCount: 1)
            )
        }
        let twoTabWindow = try window(1, tabs: [one, two], selected: 1)
        assertError(.tooManyTabs(windowID: windowID(1), maximum: 1)) {
            _ = try self.state(
                windows: [twoTabWindow],
                selectedWindow: 1,
                limits: Lifecycle.Limits(maximumTabsPerWindow: 1)
            )
        }
        assertError(.tooManyTotalTabs(maximum: 1)) {
            _ = try self.state(
                windows: [firstWindow, secondWindow],
                selectedWindow: 1,
                limits: Lifecycle.Limits(maximumTabsPerWindow: 1, maximumTotalTabCount: 1)
            )
        }
    }

    func testWindowAndRestorationWindowHardTabCapsAcceptExactAndRejectExcess() throws {
        let exactTabs = try (1...Lifecycle.Limits.hardMaximumTabsPerWindow).map {
            try tab(UInt64($0))
        }
        let exactWindow = try Lifecycle.WindowState(
            id: windowID(1),
            revision: windowRevision(1, generation: 0),
            tabs: exactTabs,
            selectedTabID: tabID(1)
        )
        XCTAssertEqual(exactWindow.tabs.count, Lifecycle.Limits.hardMaximumTabsPerWindow)
        assertError(
            .tooManyTabs(
                windowID: windowID(1),
                maximum: Lifecycle.Limits.hardMaximumTabsPerWindow
            )
        ) {
            _ = try Lifecycle.WindowState(
                id: self.windowID(1),
                revision: self.windowRevision(1, generation: 0),
                tabs: exactTabs + [
                    try self.tab(UInt64(Lifecycle.Limits.hardMaximumTabsPerWindow + 1))
                ],
                selectedTabID: self.tabID(1)
            )
        }

        let session = try sessionState()
        let exactRestorationTabs = try (1...Lifecycle.Limits.hardMaximumTabsPerWindow).map {
            try restorationTab(UInt64($0), session: session)
        }
        let exactRestorationWindow = try Lifecycle.RestorationWindow(
            id: windowID(1),
            revision: windowRevision(1, generation: 0),
            tabs: exactRestorationTabs,
            selectedTabID: tabID(1)
        )
        XCTAssertEqual(
            exactRestorationWindow.tabs.count,
            Lifecycle.Limits.hardMaximumTabsPerWindow
        )
        assertError(
            .tooManyTabs(
                windowID: windowID(1),
                maximum: Lifecycle.Limits.hardMaximumTabsPerWindow
            )
        ) {
            _ = try Lifecycle.RestorationWindow(
                id: self.windowID(1),
                revision: self.windowRevision(1, generation: 0),
                tabs: exactRestorationTabs + [
                    try self.restorationTab(
                        UInt64(Lifecycle.Limits.hardMaximumTabsPerWindow + 1),
                        session: session
                    )
                ],
                selectedTabID: self.tabID(1)
            )
        }
    }

    func testSelectionAdvancesOnlyRequiredRevisionsAndRejectsNoOpsAndMissingIDs() throws {
        let firstWindow = try window(
            1,
            generation: 10,
            tabs: [try tab(1), try tab(2)],
            selected: 1
        )
        let secondWindow = try window(
            2,
            generation: 20,
            tabs: [try tab(3), try tab(4)],
            selected: 3
        )
        let original = try state(
            generation: 30,
            windows: [firstWindow, secondWindow],
            selectedWindow: 1
        )

        let windowOnly = try Lifecycle.plan(
            .select(windowID: windowID(2), tabID: tabID(3)),
            in: original
        )
        let windowOnlyIntent = try selectionIntent(windowOnly)
        XCTAssertEqual(windowOnlyIntent.windowID, windowID(2))
        XCTAssertEqual(windowOnlyIntent.tabID, tabID(3))
        XCTAssertEqual(windowOnly.successor.revision.generation, 31)
        XCTAssertEqual(windowOnly.successor.selectedWindowID, windowID(2))
        XCTAssertEqual(windowOnly.successor.windows.map(\.revision), [firstWindow.revision, secondWindow.revision])

        let tabAndWindow = try Lifecycle.plan(
            .select(windowID: windowID(2), tabID: tabID(4)),
            in: original
        )
        XCTAssertEqual(tabAndWindow.successor.revision.generation, 31)
        XCTAssertEqual(tabAndWindow.successor.windows[0].revision, firstWindow.revision)
        XCTAssertEqual(tabAndWindow.successor.windows[1].revision.generation, 21)
        XCTAssertEqual(tabAndWindow.successor.windows[1].selectedTabID, tabID(4))

        assertError(.noStateChange) {
            _ = try Lifecycle.plan(
                .select(windowID: windowID(1), tabID: tabID(1)),
                in: original
            )
        }
        assertError(.windowNotFound(windowID(9))) {
            _ = try Lifecycle.plan(
                .select(windowID: windowID(9), tabID: tabID(1)),
                in: original
            )
        }
        assertError(.tabNotFound(tabID(9))) {
            _ = try Lifecycle.plan(
                .select(windowID: windowID(1), tabID: tabID(9)),
                in: original
            )
        }
    }

    func testTabWidthPreferenceUsesInclusiveFiniteBoundsAndExactNoOp() throws {
        let limits = Lifecycle.Limits(minimumTabWidth: 72, maximumTabWidth: 320)
        let original = try state(
            windows: [try window(1, tabs: [try tab(1)], selected: 1)],
            selectedWindow: 1,
            limits: limits
        )

        for width in [72.0, 320.0] {
            let plan = try Lifecycle.plan(.setTabWidthPreference(.fixed(width)), in: original)
            XCTAssertEqual(plan.effect, .tabWidthPreference(.fixed(width)))
            XCTAssertEqual(plan.successor.tabWidthPreference, .fixed(width))
            XCTAssertEqual(plan.successor.revision.generation, 1)
            XCTAssertEqual(plan.successor.windows, original.windows)
        }
        for width in [71.999, 320.001, .infinity, -.infinity, .nan] {
            assertError(.invalidTabWidth, "width \(width)") {
                _ = try Lifecycle.plan(.setTabWidthPreference(.fixed(width)), in: original)
            }
            assertError(.invalidTabWidth, "state width \(width)") {
                _ = try self.state(
                    windows: original.windows,
                    selectedWindow: 1,
                    width: .fixed(width),
                    limits: limits
                )
            }
        }
        assertError(.noStateChange) {
            _ = try Lifecycle.plan(.setTabWidthPreference(.automatic), in: original)
        }
        let fixed = try state(
            windows: original.windows,
            selectedWindow: 1,
            width: .fixed(100),
            limits: limits
        )
        assertError(.noStateChange) {
            _ = try Lifecycle.plan(.setTabWidthPreference(.fixed(100)), in: fixed)
        }
        let automatic = try Lifecycle.plan(.setTabWidthPreference(.automatic), in: fixed)
        XCTAssertEqual(automatic.successor.tabWidthPreference, .automatic)
        XCTAssertEqual(automatic.successor.revision.generation, fixed.revision.generation + 1)
    }

    func testCloseScopesUseReverseVisualTargetsAndRetainDeterministicSelection() throws {
        let tabs = [
            try tab(1),
            try tab(2, dirty: true),
            try tab(3, dirty: true, veto: .vetoed(.ownerRejected)),
            try tab(4, restorable: false),
            try tab(5, veto: .vetoed(.policyRestricted))
        ]
        let original = try state(
            windows: [try window(1, generation: 4, tabs: tabs, selected: 3)],
            selectedWindow: 1
        )
        let cases: [(Lifecycle.CloseScope, [UInt64], [UInt64], UInt64)] = [
            (.current, [3], [1, 2, 4, 5], 4),
            (.others, [5, 4, 2, 1], [3], 3),
            (.left, [2, 1], [3, 4, 5], 3),
            (.right, [5, 4], [1, 2, 3], 3)
        ]

        for (scope, targetIDs, remainingIDs, selection) in cases {
            let plan = try Lifecycle.plan(.close(scope), in: original)
            let intent = try closeIntent(plan)
            XCTAssertEqual(intent.scope, scope)
            XCTAssertEqual(intent.targets.map(\.tabID), targetIDs.map(tabID))
            XCTAssertEqual(plan.successor.windows[0].tabs.map(\.id), remainingIDs.map(tabID))
            XCTAssertEqual(plan.successor.windows[0].selectedTabID, tabID(selection))
            XCTAssertEqual(plan.successor.windows[0].revision.generation, 5)
            XCTAssertEqual(plan.successor.revision.generation, 1)
            XCTAssertEqual(plan.successor.totalTabCount, remainingIDs.count)
        }

        let current = try closeIntent(Lifecycle.plan(.close(.current), in: original)).targets[0]
        XCTAssertEqual(current.windowID, windowID(1))
        XCTAssertEqual(current.tabID, tabID(3))
        XCTAssertEqual(current.materialization, materialization(3))
        XCTAssertTrue(current.requiresConfirmation)
        XCTAssertTrue(current.isCloseVetoed)
        XCTAssertEqual(current.closeVeto.reason, .ownerRejected)
        XCTAssertTrue(current.isRestorable)

        let others = try closeIntent(Lifecycle.plan(.close(.others), in: original)).targets
        XCTAssertEqual(others.filter(\.requiresConfirmation).map(\.tabID), [tabID(2)])
        XCTAssertEqual(others.filter(\.isCloseVetoed).map(\.tabID), [tabID(5)])
        XCTAssertEqual(others.filter { !$0.isRestorable }.map(\.tabID), [tabID(4)])
        XCTAssertEqual(
            Lifecycle.ExecutorContract.required.closing,
            .authorizeAllTargetsBeforeAtomicStateReplacement
        )
    }

    func testCloseScopeGuardsAndClosingLastTabSelectsNextWindowOrEmptiesState() throws {
        let first = try window(1, tabs: [try tab(1)], selected: 1)
        let second = try window(2, generation: 8, tabs: [try tab(2)], selected: 2)
        let twoWindows = try state(windows: [first, second], selectedWindow: 1)

        let closeFirst = try Lifecycle.plan(.close(.current), in: twoWindows)
        XCTAssertEqual(closeFirst.successor.windows, [second])
        XCTAssertEqual(closeFirst.successor.selectedWindowID, windowID(2))
        XCTAssertEqual(closeFirst.successor.windows[0].revision.generation, 8)
        XCTAssertEqual(closeFirst.successor.totalTabCount, 1)

        let last = try state(windows: [first], selectedWindow: 1)
        let closeLast = try Lifecycle.plan(.close(.current), in: last)
        XCTAssertEqual(closeLast.successor.windows, [])
        XCTAssertNil(closeLast.successor.selectedWindowID)
        XCTAssertEqual(closeLast.successor.totalTabCount, 0)

        for scope in [Lifecycle.CloseScope.others, .left, .right] {
            assertError(.noCloseTargets(scope)) {
                _ = try Lifecycle.plan(.close(scope), in: last)
            }
        }
        assertError(.noSelectedWindow) {
            _ = try Lifecycle.plan(.close(.current), in: self.state())
        }
    }

    func testDetachCreatesAdjacentSelectedWindowAndCopiesSourceWindowPolicy() throws {
        let source = try window(
            1,
            generation: 5,
            tabs: [try tab(1), try tab(2, restorable: true), try tab(3)],
            selected: 2,
            restorable: false,
            eligibility: .ineligible(.transientWindow)
        )
        let trailing = try window(2, tabs: [try tab(4)], selected: 4)
        let original = try state(windows: [source, trailing], selectedWindow: 1)
        let request = Lifecycle.DetachRequest(
            sourceWindowID: windowID(1),
            tabID: tabID(2),
            destination: try reservation(9)
        )

        assertError(.windowTabbingIneligible(windowID(1), .transientWindow)) {
            _ = try Lifecycle.plan(.detach(request), in: original)
        }

        let eligibleSource = try window(
            1,
            generation: 5,
            tabs: [try tab(1), try tab(2, restorable: true), try tab(3)],
            selected: 2,
            restorable: false
        )
        let eligibleState = try state(windows: [eligibleSource, trailing], selectedWindow: 1)
        let plan = try Lifecycle.plan(.detach(request), in: eligibleState)
        let intent = try detachIntent(plan)
        XCTAssertEqual(intent.sourceWindowID, windowID(1))
        XCTAssertEqual(intent.destinationWindowID, windowID(9))
        XCTAssertEqual(intent.tabID, tabID(2))
        XCTAssertEqual(intent.replacementSourceTabID, tabID(3))
        XCTAssertEqual(plan.successor.windows.map(\.id), [windowID(1), windowID(9), windowID(2)])
        XCTAssertEqual(plan.successor.windows[0].tabs.map(\.id), [tabID(1), tabID(3)])
        XCTAssertEqual(plan.successor.windows[0].selectedTabID, tabID(3))
        XCTAssertEqual(plan.successor.windows[0].revision.generation, 6)
        XCTAssertEqual(plan.successor.windows[1].tabs.map(\.id), [tabID(2)])
        XCTAssertEqual(plan.successor.windows[1].selectedTabID, tabID(2))
        XCTAssertEqual(plan.successor.windows[1].revision, windowRevision(9, generation: 0))
        XCTAssertFalse(plan.successor.windows[1].isRestorable)
        XCTAssertEqual(plan.successor.windows[1].tabbingEligibility, .eligible)
        XCTAssertTrue(plan.successor.windows[1].tabs[0].isRestorable)
        XCTAssertEqual(plan.successor.selectedWindowID, windowID(9))
        XCTAssertEqual(plan.successor.totalTabCount, eligibleState.totalTabCount)

        let nonrestorableTabState = try state(
            windows: [
                try window(
                    1,
                    tabs: [try tab(1), try tab(2, restorable: false)],
                    selected: 2,
                    restorable: true
                )
            ],
            selectedWindow: 1
        )
        let nonrestorableTabPlan = try Lifecycle.plan(
            .detach(
                Lifecycle.DetachRequest(
                    sourceWindowID: windowID(1),
                    tabID: tabID(2),
                    destination: try reservation(9)
                )
            ),
            in: nonrestorableTabState
        )
        XCTAssertTrue(nonrestorableTabPlan.successor.windows[1].isRestorable)
        XCTAssertFalse(nonrestorableTabPlan.successor.windows[1].tabs[0].isRestorable)
    }

    func testDetachGuardsWindowLimitsIdentityOnlyTabAndTabEligibility() throws {
        let single = try state(
            windows: [try window(1, tabs: [try tab(1)], selected: 1)],
            selectedWindow: 1
        )
        assertError(.onlyTabCannotDetach(tabID(1))) {
            _ = try Lifecycle.plan(
                .detach(
                    Lifecycle.DetachRequest(
                        sourceWindowID: windowID(1),
                        tabID: tabID(1),
                        destination: try self.reservation(2)
                    )
                ),
                in: single
            )
        }

        let ineligible = try state(
            windows: [
                try window(
                    1,
                    tabs: [
                        try tab(1, eligibility: .ineligible(.policyRestricted)),
                        try tab(2)
                    ],
                    selected: 1
                )
            ],
            selectedWindow: 1
        )
        let request = Lifecycle.DetachRequest(
            sourceWindowID: windowID(1),
            tabID: tabID(1),
            destination: try reservation(2)
        )
        assertError(.tabTabbingIneligible(tabID(1), .policyRestricted)) {
            _ = try Lifecycle.plan(.detach(request), in: ineligible)
        }

        let eligible = try state(
            windows: [try window(1, tabs: [try tab(1), try tab(2)], selected: 1)],
            selectedWindow: 1
        )
        let duplicateDestination = Lifecycle.DetachRequest(
            sourceWindowID: windowID(1),
            tabID: tabID(1),
            destination: try reservation(1)
        )
        assertError(.duplicateWindowID(windowID(1))) {
            _ = try Lifecycle.plan(.detach(duplicateDestination), in: eligible)
        }

        let limited = try state(
            windows: eligible.windows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWindowCount: 1)
        )
        assertError(.tooManyWindows(maximum: 1)) {
            _ = try Lifecycle.plan(.detach(request), in: limited)
        }
    }

    func testMoveWithinWindowUsesPostRemovalIndexAndOptionalSelection() throws {
        let original = try state(
            windows: [
                try window(
                    1,
                    generation: 6,
                    tabs: [try tab(1), try tab(2), try tab(3)],
                    selected: 1
                )
            ],
            selectedWindow: 1
        )
        let request = Lifecycle.MoveRequest(
            sourceWindowID: windowID(1),
            destinationWindowID: windowID(1),
            tabID: tabID(3),
            insertionIndex: 0,
            selectsMovedTab: false
        )
        let plan = try Lifecycle.plan(.move(request), in: original)
        let intent = try moveIntent(plan)
        XCTAssertEqual(intent.destinationInsertionIndex, 0)
        XCTAssertEqual(intent.resultingSourceTabOrder, [tabID(3), tabID(1), tabID(2)])
        XCTAssertEqual(intent.resultingDestinationTabOrder, [tabID(3), tabID(1), tabID(2)])
        XCTAssertEqual(intent.resultingSourceSelection, tabID(1))
        XCTAssertEqual(intent.resultingDestinationSelection, tabID(1))
        XCTAssertEqual(plan.successor.windows[0].tabs.map(\.id), [tabID(3), tabID(1), tabID(2)])
        XCTAssertEqual(plan.successor.windows[0].selectedTabID, tabID(1))
        XCTAssertEqual(plan.successor.windows[0].revision.generation, 7)

        let selecting = try Lifecycle.plan(
            .move(
                Lifecycle.MoveRequest(
                    sourceWindowID: windowID(1),
                    destinationWindowID: windowID(1),
                    tabID: tabID(3),
                    insertionIndex: 0
                )
            ),
            in: original
        )
        XCTAssertEqual(selecting.successor.selectedWindowID, windowID(1))
        XCTAssertEqual(selecting.successor.windows[0].selectedTabID, tabID(3))

        assertError(.noStateChange) {
            _ = try Lifecycle.plan(
                .move(
                    Lifecycle.MoveRequest(
                        sourceWindowID: windowID(1),
                        destinationWindowID: windowID(1),
                        tabID: tabID(1),
                        insertionIndex: 0,
                        selectsMovedTab: false
                    )
                ),
                in: original
            )
        }
    }

    func testMoveAcrossWindowsClosesEmptySourceAndRetainsDestinationWindowPolicy() throws {
        let source = try window(
            1,
            generation: 3,
            tabs: [try tab(1, restorable: false)],
            selected: 1,
            restorable: false
        )
        let destination = try window(
            2,
            generation: 8,
            tabs: [try tab(2), try tab(3)],
            selected: 2,
            restorable: true,
            eligibility: .eligible
        )
        let original = try state(windows: [source, destination], selectedWindow: 1)
        let request = Lifecycle.MoveRequest(
            sourceWindowID: windowID(1),
            destinationWindowID: windowID(2),
            tabID: tabID(1),
            insertionIndex: 1,
            selectsMovedTab: false
        )
        let plan = try Lifecycle.plan(.move(request), in: original)
        let intent = try moveIntent(plan)
        XCTAssertEqual(intent.resultingSourceTabOrder, [])
        XCTAssertNil(intent.resultingSourceSelection)
        XCTAssertEqual(intent.resultingDestinationTabOrder, [tabID(2), tabID(1), tabID(3)])
        XCTAssertEqual(intent.resultingDestinationSelection, tabID(2))
        XCTAssertEqual(plan.successor.windows.map(\.id), [windowID(2)])
        XCTAssertEqual(plan.successor.windows[0].revision.generation, 9)
        XCTAssertTrue(plan.successor.windows[0].isRestorable)
        XCTAssertFalse(plan.successor.windows[0].tabs[1].isRestorable)
        XCTAssertEqual(plan.successor.selectedWindowID, windowID(2))
        XCTAssertEqual(plan.successor.totalTabCount, original.totalTabCount)

        let retainedSource = try state(
            windows: [
                try window(1, generation: 3, tabs: [try tab(1), try tab(4)], selected: 1),
                destination
            ],
            selectedWindow: 1
        )
        let retainedPlan = try Lifecycle.plan(.move(request), in: retainedSource)
        XCTAssertEqual(retainedPlan.successor.windows[0].tabs.map(\.id), [tabID(4)])
        XCTAssertEqual(retainedPlan.successor.windows[0].selectedTabID, tabID(4))
        XCTAssertEqual(retainedPlan.successor.windows[0].revision.generation, 4)
        XCTAssertEqual(retainedPlan.successor.windows[1].revision.generation, 9)
    }

    func testMoveGuardsSourceDestinationEligibilityCapacityAndInsertionBounds() throws {
        let source = try window(
            1,
            tabs: [
                try tab(1, eligibility: .ineligible(.unsupportedContent)),
                try tab(2)
            ],
            selected: 1
        )
        let destination = try window(
            2,
            tabs: [try tab(3)],
            selected: 3,
            eligibility: .ineligible(.modalWorkflow)
        )
        let original = try state(windows: [source, destination], selectedWindow: 1)
        let request = Lifecycle.MoveRequest(
            sourceWindowID: windowID(1),
            destinationWindowID: windowID(2),
            tabID: tabID(1),
            insertionIndex: 0
        )
        assertError(.tabTabbingIneligible(tabID(1), .unsupportedContent)) {
            _ = try Lifecycle.plan(.move(request), in: original)
        }

        let eligibleSource = try window(1, tabs: [try tab(1), try tab(2)], selected: 1)
        let destinationBlocked = try state(
            windows: [eligibleSource, destination],
            selectedWindow: 1
        )
        assertError(.windowTabbingIneligible(windowID(2), .modalWorkflow)) {
            _ = try Lifecycle.plan(.move(request), in: destinationBlocked)
        }

        let eligibleDestination = try window(2, tabs: [try tab(3)], selected: 3)
        let eligible = try state(
            windows: [eligibleSource, eligibleDestination],
            selectedWindow: 1
        )
        for index in [-1, 2] {
            assertError(.invalidInsertionIndex(index, windowID: windowID(2))) {
                _ = try Lifecycle.plan(
                    .move(
                        Lifecycle.MoveRequest(
                            sourceWindowID: windowID(1),
                            destinationWindowID: windowID(2),
                            tabID: tabID(1),
                            insertionIndex: index
                        )
                    ),
                    in: eligible
                )
            }
        }
        let append = try Lifecycle.plan(
            .move(
                Lifecycle.MoveRequest(
                    sourceWindowID: windowID(1),
                    destinationWindowID: windowID(2),
                    tabID: tabID(1),
                    insertionIndex: 1
                )
            ),
            in: eligible
        )
        XCTAssertEqual(
            append.successor.windows[1].tabs.map(\.id),
            [tabID(3), tabID(1)]
        )
        let sameWindowAppend = try Lifecycle.plan(
            .move(
                Lifecycle.MoveRequest(
                    sourceWindowID: windowID(1),
                    destinationWindowID: windowID(1),
                    tabID: tabID(1),
                    insertionIndex: 1
                )
            ),
            in: eligible
        )
        XCTAssertEqual(
            sameWindowAppend.successor.windows[0].tabs.map(\.id),
            [tabID(2), tabID(1)]
        )

        let capacityLimitedSource = try window(1, tabs: [try tab(1)], selected: 1)
        let capacityLimited = try state(
            windows: [capacityLimitedSource, eligibleDestination],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumTabsPerWindow: 1, maximumTotalTabCount: 3)
        )
        assertError(.tooManyTabs(windowID: windowID(2), maximum: 1)) {
            _ = try Lifecycle.plan(.move(request), in: capacityLimited)
        }
        assertError(.windowNotFound(windowID(9))) {
            _ = try Lifecycle.plan(
                .move(
                    Lifecycle.MoveRequest(
                        sourceWindowID: windowID(9),
                        destinationWindowID: windowID(2),
                        tabID: tabID(1),
                        insertionIndex: 0
                    )
                ),
                in: eligible
            )
        }
        assertError(.tabNotFound(tabID(9))) {
            _ = try Lifecycle.plan(
                .move(
                    Lifecycle.MoveRequest(
                        sourceWindowID: windowID(1),
                        destinationWindowID: windowID(2),
                        tabID: tabID(9),
                        insertionIndex: 0
                    )
                ),
                in: eligible
            )
        }
    }

    func testStateCASBindsExactSnapshotBeyondPublicRevisionNumbers() throws {
        let first = try tab(1, title: "One")
        let second = try tab(2, title: "Two")
        let baseWindow = try window(
            1,
            generation: 5,
            tabs: [first, second],
            selected: 1
        )
        let base = try state(
            generation: 7,
            windows: [baseWindow],
            selectedWindow: 1
        )
        let identical = try state(
            generation: 7,
            windows: [baseWindow],
            selectedWindow: 1
        )
        XCTAssertEqual(base.cas.sessionRevision, base.revision)
        XCTAssertEqual(base.cas.windowRevisions, [baseWindow.revision])
        XCTAssertTrue(try base.cas.matches(identical))
        XCTAssertNoThrow(try base.cas.validate(identical))

        let variants = try [
            state(
                lineage: 2,
                generation: 7,
                windows: [baseWindow],
                selectedWindow: 1
            ),
            state(
                generation: 8,
                windows: [baseWindow],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [try window(1, generation: 6, tabs: [first, second], selected: 1)],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [try window(1, generation: 5, tabs: [first, second], selected: 2)],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [try window(1, generation: 5, tabs: [second, first], selected: 1)],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [first, second],
                        selected: 1,
                        restorable: false
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [
                            try Lifecycle.TabState(
                                id: tabID(1),
                                title: "One",
                                materialization: materialization(99),
                                isDirty: false,
                                closeVeto: .none,
                                isRestorable: true,
                                tabbingEligibility: .eligible
                            ),
                            second
                        ],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [first, second],
                        selected: 1,
                        eligibility: .ineligible(.policyRestricted)
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [try tab(1, title: "Changed"), second],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [try tab(1, materializationRevision: 1), second],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [try tab(1, dirty: true), second],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [try tab(1, veto: .vetoed(.ownerRejected)), second],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [try tab(1, restorable: false), second],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [
                    try window(
                        1,
                        generation: 5,
                        tabs: [
                            try tab(1, eligibility: .ineligible(.unsupportedContent)),
                            second
                        ],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            ),
            state(
                generation: 7,
                windows: [baseWindow],
                selectedWindow: 1,
                width: .fixed(100)
            ),
            state(
                generation: 7,
                windows: [baseWindow],
                selectedWindow: 1,
                limits: Lifecycle.Limits(maximumWorkUnits: 4_000_000)
            )
        ]
        for (index, variant) in variants.enumerated() {
            XCTAssertFalse(try base.cas.matches(variant), "variant \(index)")
            assertError(.staleState(expected: base.cas, actual: variant.cas), "variant \(index)") {
                try base.cas.validate(variant)
            }
        }

        let plan = try Lifecycle.plan(.setTabWidthPreference(.fixed(100)), in: base)
        XCTAssertNoThrow(try plan.validateCurrentState(base))
        assertError(.staleState(expected: base.cas, actual: variants[0].cas)) {
            try plan.validateCurrentState(variants[0])
        }
    }

    func testStateCASAndSelectionComparisonHaveExactWorkBoundaries() throws {
        let exactState = try state(
            windows: [try window(1, tabs: [try tab(1, title: "A")], selected: 1)],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 4, cancellationCheckInterval: 4)
        )
        XCTAssertTrue(try exactState.cas.matches(exactState))
        XCTAssertNoThrow(try exactState.cas.validate(exactState))

        let selectionState = try state(
            windows: [
                try window(1, tabs: [try tab(1), try tab(2)], selected: 1),
                try window(2, tabs: [try tab(3)], selected: 3)
            ],
            selectedWindow: 2
        )
        let selection = try Lifecycle.plan(
            .select(windowID: windowID(1), tabID: tabID(2)),
            in: selectionState
        )
        XCTAssertEqual(selection.workPerformed, 3)
    }

    func testPlansAndPlanningReceiptsAreDeterministicAndFullyBound() throws {
        let original = try state(
            generation: 9,
            windows: [try window(1, tabs: [try tab(1), try tab(2)], selected: 1)],
            selectedWindow: 1
        )
        let command = Lifecycle.Command.select(windowID: windowID(1), tabID: tabID(2))
        let first = try Lifecycle.plan(command, in: original)
        let second = try Lifecycle.plan(command, in: original)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.command, command)
        XCTAssertEqual(first.expectedStateCAS, original.cas)
        XCTAssertEqual(first.successor.revision.generation, 10)
        XCTAssertEqual(first.receipt.expectedStateCAS, original.cas)
        XCTAssertEqual(first.receipt.successorStateCAS, first.successor.cas)
        XCTAssertEqual(first.receipt.effect, first.effect)
        XCTAssertEqual(first.executorContract, .required)
        XCTAssertGreaterThan(first.workPerformed, 0)
        XCTAssertEqual(Set([first, second]).count, 1)
        XCTAssertEqual(Set([first.receipt, second.receipt]).count, 1)
    }

    func testSessionAndWindowRevisionExhaustionFailBeforeSuccessorPublication() throws {
        let sessionExhausted = try state(
            generation: .max,
            windows: [try window(1, tabs: [try tab(1)], selected: 1)],
            selectedWindow: 1
        )
        assertError(.sessionRevisionExhausted(lineage(1))) {
            _ = try Lifecycle.plan(
                .setTabWidthPreference(.fixed(100)),
                in: sessionExhausted
            )
        }
        let structuralSessionExhausted = try state(
            generation: .max,
            windows: [try window(1, tabs: [try tab(1), try tab(2)], selected: 1)],
            selectedWindow: 1
        )
        assertError(.sessionRevisionExhausted(lineage(1))) {
            _ = try Lifecycle.plan(
                .select(windowID: self.windowID(1), tabID: self.tabID(2)),
                in: structuralSessionExhausted
            )
        }

        let windowExhausted = try state(
            windows: [
                try window(
                    1,
                    generation: .max,
                    tabs: [try tab(1), try tab(2)],
                    selected: 1
                )
            ],
            selectedWindow: 1
        )
        assertError(.windowRevisionExhausted(windowID(1))) {
            _ = try Lifecycle.plan(
                .select(windowID: windowID(1), tabID: tabID(2)),
                in: windowExhausted
            )
        }

        let destinationExhausted = try state(
            windows: [
                try window(1, tabs: [try tab(1), try tab(2)], selected: 1),
                try window(2, generation: .max, tabs: [try tab(3)], selected: 3)
            ],
            selectedWindow: 1
        )
        assertError(.windowRevisionExhausted(windowID(2))) {
            _ = try Lifecycle.plan(
                .move(
                    Lifecycle.MoveRequest(
                        sourceWindowID: self.windowID(1),
                        destinationWindowID: self.windowID(2),
                        tabID: self.tabID(1),
                        insertionIndex: 0
                    )
                ),
                in: destinationExhausted
            )
        }
        let sourceExhausted = try state(
            windows: [
                try window(
                    1,
                    generation: .max,
                    tabs: [try tab(1), try tab(2)],
                    selected: 1
                ),
                try window(2, tabs: [try tab(3)], selected: 3)
            ],
            selectedWindow: 1
        )
        assertError(.windowRevisionExhausted(windowID(1))) {
            _ = try Lifecycle.plan(
                .move(
                    Lifecycle.MoveRequest(
                        sourceWindowID: self.windowID(1),
                        destinationWindowID: self.windowID(2),
                        tabID: self.tabID(1),
                        insertionIndex: 0
                    )
                ),
                in: sourceExhausted
            )
        }
        assertError(.windowRevisionExhausted(windowID(1))) {
            _ = try Lifecycle.plan(.close(.others), in: windowExhausted)
        }
        assertError(.windowRevisionExhausted(windowID(1))) {
            _ = try Lifecycle.plan(
                .detach(
                    Lifecycle.DetachRequest(
                        sourceWindowID: windowID(1),
                        tabID: tabID(1),
                        destination: try self.reservation(2)
                    )
                ),
                in: windowExhausted
            )
        }
    }

    func testRestorationPublicationCASBindsExactOwnerAndEpochAndRejectsExhaustion() throws {
        let cas = try publicationCAS(owner: 7, epoch: 11)
        XCTAssertEqual(cas.ownerID, ownerID(7))
        XCTAssertEqual(cas.expectedEpoch, 11)
        XCTAssertEqual(cas.successorEpoch, 12)
        XCTAssertTrue(cas.matches(ownerID: ownerID(7), epoch: 11))
        XCTAssertFalse(cas.matches(ownerID: ownerID(8), epoch: 11))
        XCTAssertFalse(cas.matches(ownerID: ownerID(7), epoch: 12))
        XCTAssertNoThrow(try cas.validate(ownerID: ownerID(7), epoch: 11))

        assertError(
            .staleRestorationPublication(
                expectedOwnerID: ownerID(7),
                expectedEpoch: 11,
                actualOwnerID: ownerID(8),
                actualEpoch: 11
            )
        ) {
            try cas.validate(ownerID: self.ownerID(8), epoch: 11)
        }
        assertError(
            .staleRestorationPublication(
                expectedOwnerID: ownerID(7),
                expectedEpoch: 11,
                actualOwnerID: ownerID(7),
                actualEpoch: 12
            )
        ) {
            try cas.validate(ownerID: self.ownerID(7), epoch: 12)
        }
        assertError(.restorationPublicationEpochExhausted(ownerID(7))) {
            _ = try Lifecycle.RestorationPublicationCAS(
                ownerID: self.ownerID(7),
                expectedEpoch: .max
            )
        }
    }

    func testRestorationPlanPreservesCanonicalOrderAndExactMaterializationBinding() throws {
        let sessionOne = try sessionState(left: "left-1", right: "right-1")
        let sessionTwo = try sessionState(
            left: "left-2",
            right: "right-2",
            selectedRow: 2,
            activeSide: .right,
            splitOrientation: .horizontal
        )
        let sessionThree = try sessionState(left: "left-3", right: "right-3")
        let request = Lifecycle.RestorationRequest(
            publicationCAS: try publicationCAS(owner: 44, epoch: 9),
            sessionRevision: revision(lineage: 12, generation: 13),
            windows: [
                try restorationWindow(
                    4,
                    generation: 5,
                    tabs: [
                        try restorationTab(
                            8,
                            title: "Eight",
                            session: sessionOne,
                            dirty: true,
                            veto: .vetoed(.ownerRejected),
                            restorable: false,
                            eligibility: .ineligible(.unsupportedContent)
                        ),
                        try restorationTab(9, title: "Nine", session: sessionTwo)
                    ],
                    selected: 9,
                    restorable: false,
                    eligibility: .ineligible(.transientWindow)
                ),
                try restorationWindow(
                    5,
                    generation: 6,
                    tabs: [try restorationTab(10, title: "Ten", session: sessionThree)],
                    selected: 10
                )
            ],
            selectedWindowID: windowID(5),
            tabWidthPreference: .fixed(100)
        )
        let plan = try Lifecycle.planRestoration(request)

        XCTAssertEqual(plan.request, request)
        XCTAssertEqual(plan.publicationCAS, request.publicationCAS)
        XCTAssertEqual(plan.materializations.map(\.ordinal), [0, 1, 2])
        XCTAssertEqual(plan.materializations.map(\.windowID), [windowID(4), windowID(4), windowID(5)])
        XCTAssertEqual(plan.materializations.map(\.tabID), [tabID(8), tabID(9), tabID(10)])
        XCTAssertEqual(
            plan.materializations.map(\.expectedWindowRevision),
            [windowRevision(4, generation: 5), windowRevision(4, generation: 5), windowRevision(5, generation: 6)]
        )
        XCTAssertTrue(
            plan.materializations.allSatisfy {
                $0.expectedPublicationCAS == request.publicationCAS
                    && $0.expectedSessionRevision == request.sessionRevision
                    && $0.contract == .required
            }
        )
        XCTAssertEqual(plan.materializations.map(\.sessionState), [sessionOne, sessionTwo, sessionThree])
        XCTAssertEqual(plan.retainedStringUTF8Bytes, 5 + 4 + 3)
        XCTAssertGreaterThan(plan.workPerformed, 0)
        XCTAssertEqual(plan.materializationContract, .required)
    }

    func testRestorationShapeSelectionAndItemCountGuardsAreIsolated() throws {
        let firstTab = try restorationTab(1)
        let secondTab = try restorationTab(2)
        let firstWindow = try restorationWindow(1, tabs: [firstTab], selected: 1)
        let secondWindow = try restorationWindow(2, tabs: [secondTab], selected: 2)

        assertError(.windowRevisionIdentityMismatch(expected: windowID(1), actual: windowID(2))) {
            _ = try Lifecycle.RestorationWindow(
                id: self.windowID(1),
                revision: self.windowRevision(2, generation: 0),
                tabs: [firstTab],
                selectedTabID: self.tabID(1)
            )
        }
        assertError(.emptyWindow(windowID(1))) {
            _ = try Lifecycle.RestorationWindow(
                id: self.windowID(1),
                revision: self.windowRevision(1, generation: 0),
                tabs: [],
                selectedTabID: self.tabID(1)
            )
        }
        assertError(.duplicateTabID(tabID(1))) {
            _ = try Lifecycle.RestorationWindow(
                id: self.windowID(1),
                revision: self.windowRevision(1, generation: 0),
                tabs: [firstTab, firstTab],
                selectedTabID: self.tabID(1)
            )
        }
        assertError(.selectedTabNotFound(windowID: windowID(1), tabID: tabID(9))) {
            _ = try Lifecycle.RestorationWindow(
                id: self.windowID(1),
                revision: self.windowRevision(1, generation: 0),
                tabs: [firstTab],
                selectedTabID: self.tabID(9)
            )
        }

        assertRestorationPlanningError(
            .missingSelectedWindow,
            windows: [firstWindow],
            selectedWindow: nil
        )
        assertRestorationPlanningError(
            .selectedWindowNotFound(windowID(9)),
            windows: [firstWindow],
            selectedWindow: 9
        )
        assertRestorationPlanningError(
            .selectedWindowNotFound(windowID(9)),
            windows: [],
            selectedWindow: 9
        )
        assertRestorationPlanningError(
            .duplicateWindowID(windowID(1)),
            windows: [firstWindow, firstWindow],
            selectedWindow: 1
        )
        let duplicateTabWindow = try restorationWindow(2, tabs: [firstTab], selected: 1)
        assertRestorationPlanningError(
            .duplicateTabID(tabID(1)),
            windows: [firstWindow, duplicateTabWindow],
            selectedWindow: 1
        )
        assertRestorationPlanningError(
            .tooManyWindows(maximum: 1),
            windows: [firstWindow, secondWindow],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWindowCount: 1)
        )
        let twoTabWindow = try restorationWindow(
            1,
            tabs: [firstTab, secondTab],
            selected: 1
        )
        assertRestorationPlanningError(
            .tooManyTabs(windowID: windowID(1), maximum: 1),
            windows: [twoTabWindow],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumTabsPerWindow: 1)
        )
        assertRestorationPlanningError(
            .tooManyTotalTabs(maximum: 1),
            windows: [firstWindow, secondWindow],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumTabsPerWindow: 1, maximumTotalTabCount: 1)
        )
        assertRestorationPlanningError(
            .tooManyRestorationItems(maximum: 1),
            windows: [twoTabWindow],
            selectedWindow: 1,
            limits: Lifecycle.Limits(
                maximumTabsPerWindow: 2,
                maximumTotalTabCount: 2,
                maximumRestorationItemCount: 1
            )
        )

        let empty = try Lifecycle.planRestoration(restorationRequest(windows: [], selectedWindow: nil))
        XCTAssertEqual(empty.materializations, [])
        XCTAssertEqual(empty.retainedStringUTF8Bytes, 0)
    }

    func testRestorationReceiptCanonicalizesExecutorOrderAndPreservesAllOutcomes() throws {
        let plan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    generation: 7,
                    tabs: [
                        try restorationTab(
                            1,
                            title: "One",
                            dirty: true,
                            veto: .vetoed(.activeOperation),
                            restorable: false,
                            eligibility: .ineligible(.unsupportedContent)
                        ),
                        try restorationTab(2, title: "Two"),
                        try restorationTab(3, title: "Three")
                    ],
                    selected: 2,
                    restorable: false,
                    eligibility: .ineligible(.transientWindow)
                ),
                try restorationWindow(
                    2,
                    generation: 9,
                    tabs: [try restorationTab(4, title: "Four")],
                    selected: 4
                )
            ],
            selectedWindow: 1,
            generation: 20,
            width: .fixed(96)
        )
        let failure = try Lifecycle.RestorationFailure(
            code: "READ_1",
            message: "Read failed",
            isRetryable: true
        )
        let unordered = [
            itemReceipt(plan, ordinal: 3, outcome: .restored(materialization(40, revision: 4))),
            itemReceipt(plan, ordinal: 1, outcome: .skipped(.userDeclined)),
            itemReceipt(plan, ordinal: 0, outcome: .restored(materialization(10, revision: 1))),
            itemReceipt(plan, ordinal: 2, outcome: .failed(failure))
        ]
        let receipt = try plan.receipt(unordered)

        XCTAssertEqual(receipt.plan, plan)
        XCTAssertEqual(receipt.publicationCAS, plan.publicationCAS)
        XCTAssertEqual(receipt.itemReceipts.map(\.tabID), [tabID(1), tabID(2), tabID(3), tabID(4)])
        XCTAssertEqual(receipt.restoredTabIDs, [tabID(1), tabID(4)])
        XCTAssertEqual(receipt.skippedTabIDs, [tabID(2)])
        XCTAssertEqual(receipt.failedTabIDs, [tabID(3)])
        guard case .restored(let firstMaterialization) = receipt.itemReceipts[0].outcome else {
            return XCTFail("Expected restored first item")
        }
        XCTAssertEqual(firstMaterialization, materialization(10, revision: 1))
        guard case .skipped(let skipReason) = receipt.itemReceipts[1].outcome else {
            return XCTFail("Expected skipped second item")
        }
        XCTAssertEqual(skipReason, .userDeclined)
        guard case .failed(let recordedFailure) = receipt.itemReceipts[2].outcome else {
            return XCTFail("Expected failed third item")
        }
        XCTAssertEqual(recordedFailure.code, "READ_1")
        XCTAssertEqual(recordedFailure.message, "Read failed")
        XCTAssertTrue(recordedFailure.isRetryable)
        guard case .restored(let fourthMaterialization) = receipt.itemReceipts[3].outcome else {
            return XCTFail("Expected restored fourth item")
        }
        XCTAssertEqual(fourthMaterialization, materialization(40, revision: 4))
        XCTAssertEqual(receipt.windowOutcomes.map(\.windowID), [windowID(1), windowID(2)])
        XCTAssertEqual(receipt.windowOutcomes[0].restoredTabIDs, [tabID(1)])
        XCTAssertEqual(receipt.windowOutcomes[0].skippedTabIDs, [tabID(2)])
        XCTAssertEqual(receipt.windowOutcomes[0].failedTabIDs, [tabID(3)])
        XCTAssertFalse(receipt.windowOutcomes[0].wasOmitted)
        XCTAssertEqual(receipt.windowOutcomes[1].restoredTabIDs, [tabID(4)])
        XCTAssertEqual(receipt.windowOutcomes[1].skippedTabIDs, [])
        XCTAssertEqual(receipt.windowOutcomes[1].failedTabIDs, [])
        XCTAssertFalse(receipt.windowOutcomes[1].wasOmitted)
        XCTAssertEqual(receipt.restoredState.revision, revision(lineage: 1, generation: 21))
        XCTAssertEqual(receipt.restoredState.windows.map(\.id), [windowID(1), windowID(2)])
        XCTAssertEqual(receipt.restoredState.windows[0].tabs.map(\.id), [tabID(1)])
        XCTAssertEqual(receipt.restoredState.windows[0].selectedTabID, tabID(1))
        XCTAssertEqual(receipt.restoredState.windows[0].revision.generation, 8)
        XCTAssertFalse(receipt.restoredState.windows[0].isRestorable)
        XCTAssertEqual(
            receipt.restoredState.windows[0].tabbingEligibility,
            .ineligible(.transientWindow)
        )
        XCTAssertTrue(receipt.restoredState.windows[0].tabs[0].isDirty)
        XCTAssertEqual(receipt.restoredState.windows[0].tabs[0].closeVeto.reason, .activeOperation)
        XCTAssertFalse(receipt.restoredState.windows[0].tabs[0].isRestorable)
        XCTAssertEqual(
            receipt.restoredState.windows[0].tabs[0].tabbingEligibility,
            .ineligible(.unsupportedContent)
        )
        XCTAssertEqual(receipt.restoredState.windows[1].revision.generation, 9)
        XCTAssertEqual(receipt.restoredState.selectedWindowID, windowID(1))
        XCTAssertEqual(receipt.restoredState.tabWidthPreference, .fixed(96))
        XCTAssertEqual(receipt.restoredState.totalTabCount, 2)
        XCTAssertGreaterThan(receipt.workPerformed, 0)
    }

    func testRestorationOmitsEmptyWindowsAndFallsBackSelectionsByRequestedInsertionPoint() throws {
        let plan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    tabs: [try restorationTab(1), try restorationTab(2)],
                    selected: 1
                ),
                try restorationWindow(
                    2,
                    tabs: [try restorationTab(3), try restorationTab(4), try restorationTab(5)],
                    selected: 4
                ),
                try restorationWindow(
                    3,
                    tabs: [try restorationTab(6)],
                    selected: 6
                )
            ],
            selectedWindow: 2,
            generation: 30
        )
        let outcomes: [Lifecycle.RestorationItemOutcome] = [
            .skipped(.userDeclined),
            .failed(try Lifecycle.RestorationFailure(code: "E1", message: "First failed")),
            .restored(materialization(3)),
            .skipped(.policyRestricted),
            .restored(materialization(5)),
            .restored(materialization(6))
        ]
        let receipt = try plan.receipt(
            zip(plan.materializations, outcomes).map {
                Lifecycle.RestorationItemReceipt(request: $0, outcome: $1)
            }
        )

        XCTAssertEqual(receipt.restoredState.windows.map(\.id), [windowID(2), windowID(3)])
        XCTAssertEqual(receipt.restoredState.selectedWindowID, windowID(2))
        XCTAssertEqual(receipt.restoredState.windows[0].tabs.map(\.id), [tabID(3), tabID(5)])
        XCTAssertEqual(receipt.restoredState.windows[0].selectedTabID, tabID(5))
        XCTAssertEqual(receipt.restoredState.windows[0].revision.generation, 1)
        XCTAssertEqual(receipt.windowOutcomes[0].wasOmitted, true)
        XCTAssertEqual(receipt.windowOutcomes[0].restoredTabIDs, [])
        XCTAssertEqual(receipt.windowOutcomes[0].skippedTabIDs, [tabID(1)])
        XCTAssertEqual(receipt.windowOutcomes[0].failedTabIDs, [tabID(2)])

        let omittedSelectionPlan = try restorationPlan(
            windows: plan.request.windows,
            selectedWindow: 1,
            generation: 30
        )
        let omittedReceipt = try omittedSelectionPlan.receipt(
            zip(omittedSelectionPlan.materializations, outcomes).map {
                Lifecycle.RestorationItemReceipt(request: $0, outcome: $1)
            }
        )
        XCTAssertEqual(omittedReceipt.restoredState.selectedWindowID, windowID(2))

        let middleSelectionPlan = try restorationPlan(
            windows: plan.request.windows,
            selectedWindow: 2,
            generation: 30
        )
        let middleSelectionOutcomes: [Lifecycle.RestorationItemOutcome] = [
            .restored(materialization(1)),
            .restored(materialization(2)),
            .skipped(.userDeclined),
            .skipped(.policyRestricted),
            .failed(try Lifecycle.RestorationFailure(code: "E2", message: "Unavailable")),
            .restored(materialization(6))
        ]
        let middleSelectionReceipt = try middleSelectionPlan.receipt(
            zip(middleSelectionPlan.materializations, middleSelectionOutcomes).map {
                Lifecycle.RestorationItemReceipt(request: $0, outcome: $1)
            }
        )
        XCTAssertEqual(
            middleSelectionReceipt.restoredState.windows.map(\.id),
            [windowID(1), windowID(3)]
        )
        XCTAssertEqual(middleSelectionReceipt.restoredState.selectedWindowID, windowID(3))

        let finalSelectionsPlan = try restorationPlan(
            windows: plan.request.windows,
            selectedWindow: 3,
            generation: 30
        )
        let finalSelectionOutcomes: [Lifecycle.RestorationItemOutcome] = [
            .restored(materialization(1)),
            .restored(materialization(2)),
            .restored(materialization(3)),
            .restored(materialization(4)),
            .skipped(.policyRestricted),
            .skipped(.unavailableSource)
        ]
        let finalSelectionsReceipt = try finalSelectionsPlan.receipt(
            zip(finalSelectionsPlan.materializations, finalSelectionOutcomes).map {
                Lifecycle.RestorationItemReceipt(request: $0, outcome: $1)
            }
        )
        XCTAssertEqual(finalSelectionsReceipt.restoredState.selectedWindowID, windowID(2))
        XCTAssertEqual(
            finalSelectionsReceipt.restoredState.windows[1].selectedTabID,
            tabID(4)
        )

        let multipleSuccessorOutcomes: [Lifecycle.RestorationItemOutcome] = [
            .restored(materialization(1)),
            .restored(materialization(2)),
            .restored(materialization(3)),
            .skipped(.policyRestricted),
            .restored(materialization(5)),
            .restored(materialization(6))
        ]
        let multipleSuccessorReceipt = try plan.receipt(
            zip(plan.materializations, multipleSuccessorOutcomes).map {
                Lifecycle.RestorationItemReceipt(request: $0, outcome: $1)
            }
        )
        XCTAssertEqual(
            multipleSuccessorReceipt.restoredState.windows[1].tabs.map(\.id),
            [tabID(3), tabID(5)]
        )
        XCTAssertEqual(
            multipleSuccessorReceipt.restoredState.windows[1].selectedTabID,
            tabID(5)
        )

        let multipleSuccessorsPlan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    tabs: [
                        try restorationTab(1),
                        try restorationTab(2),
                        try restorationTab(3),
                        try restorationTab(4)
                    ],
                    selected: 2
                )
            ],
            selectedWindow: 1
        )
        let multipleSuccessorsReceipt = try multipleSuccessorsPlan.receipt(
            [
                itemReceipt(
                    multipleSuccessorsPlan,
                    ordinal: 0,
                    outcome: .restored(materialization(1))
                ),
                itemReceipt(
                    multipleSuccessorsPlan,
                    ordinal: 1,
                    outcome: .skipped(.userDeclined)
                ),
                itemReceipt(
                    multipleSuccessorsPlan,
                    ordinal: 2,
                    outcome: .restored(materialization(3))
                ),
                itemReceipt(
                    multipleSuccessorsPlan,
                    ordinal: 3,
                    outcome: .restored(materialization(4))
                )
            ]
        )
        XCTAssertEqual(
            multipleSuccessorsReceipt.restoredState.windows[0].tabs.map(\.id),
            [tabID(1), tabID(3), tabID(4)]
        )
        XCTAssertEqual(
            multipleSuccessorsReceipt.restoredState.windows[0].selectedTabID,
            tabID(3)
        )

        let emptyReceipt = try plan.receipt(
            plan.materializations.map {
                Lifecycle.RestorationItemReceipt(
                    request: $0,
                    outcome: .skipped(.unavailableSource)
                )
            }
        )
        XCTAssertEqual(emptyReceipt.restoredState.windows, [])
        XCTAssertNil(emptyReceipt.restoredState.selectedWindowID)
        XCTAssertEqual(emptyReceipt.restoredState.totalTabCount, 0)
        XCTAssertTrue(emptyReceipt.windowOutcomes.allSatisfy(\.wasOmitted))
    }

    func testCompleteRestorationPreservesRevisionsAndReceiptIsDeterministic() throws {
        let plan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    generation: .max,
                    tabs: [try restorationTab(1), try restorationTab(2)],
                    selected: 2
                )
            ],
            selectedWindow: 1,
            generation: .max
        )
        let unordered = [
            itemReceipt(plan, ordinal: 1, outcome: .restored(materialization(2, revision: 20))),
            itemReceipt(plan, ordinal: 0, outcome: .restored(materialization(1, revision: 10)))
        ]
        let first = try plan.receipt(unordered)
        let second = try plan.receipt(unordered.reversed())

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.itemReceipts.map(\.tabID), [tabID(1), tabID(2)])
        XCTAssertEqual(first.restoredState.revision.generation, .max)
        XCTAssertEqual(first.restoredState.windows[0].revision.generation, .max)
        XCTAssertEqual(first.restoredState.windows[0].selectedTabID, tabID(2))
        XCTAssertEqual(first.restoredState.windows[0].tabs.map(\.materialization), [materialization(1, revision: 10), materialization(2, revision: 20)])
    }

    func testPartialRestorationExhaustionIsExactForSessionAndWindowRevisions() throws {
        let sessionPlan = try restorationPlan(
            windows: [try restorationWindow(1, tabs: [try restorationTab(1)], selected: 1)],
            selectedWindow: 1,
            generation: .max
        )
        assertError(.sessionRevisionExhausted(lineage(1))) {
            _ = try sessionPlan.receipt([
                self.itemReceipt(sessionPlan, ordinal: 0, outcome: .skipped(.userDeclined))
            ])
        }

        let windowPlan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    generation: .max,
                    tabs: [try restorationTab(1), try restorationTab(2)],
                    selected: 1
                )
            ],
            selectedWindow: 1
        )
        assertError(.windowRevisionExhausted(windowID(1))) {
            _ = try windowPlan.receipt([
                self.itemReceipt(windowPlan, ordinal: 0, outcome: .restored(self.materialization(1))),
                self.itemReceipt(windowPlan, ordinal: 1, outcome: .skipped(.userDeclined))
            ])
        }
    }

    func testRestorationReceiptRejectsCountDuplicateAndUnknownRequests() throws {
        let plan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    tabs: [try restorationTab(1), try restorationTab(2)],
                    selected: 1
                )
            ],
            selectedWindow: 1
        )
        let first = itemReceipt(plan, ordinal: 0, outcome: .restored(materialization(1)))
        let second = itemReceipt(plan, ordinal: 1, outcome: .restored(materialization(2)))

        assertError(.restorationReceiptCountMismatch(expected: 2, actual: 1)) {
            _ = try plan.receipt([first])
        }
        assertError(.restorationReceiptCountMismatch(expected: 2, actual: 3)) {
            _ = try plan.receipt([first, second, second])
        }
        assertError(.duplicateRestorationReceipt(tabID(1))) {
            _ = try plan.receipt([first, first])
        }

        let otherPlan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    tabs: [try restorationTab(1), try restorationTab(9)],
                    selected: 1
                )
            ],
            selectedWindow: 1
        )
        let unknown = itemReceipt(otherPlan, ordinal: 1, outcome: .restored(materialization(9)))
        assertError(.unknownRestorationReceipt(tabID(9))) {
            _ = try plan.receipt([first, unknown])
        }
    }

    func testRestorationReceiptBindsEveryMaterializationIdentityFieldExactly() throws {
        let baseWindow = try restorationWindow(
            1,
            generation: 4,
            tabs: [try restorationTab(1, session: try sessionState(left: "A", right: "B"))],
            selected: 1
        )
        let base = try restorationPlan(
            windows: [baseWindow],
            selectedWindow: 1,
            lineage: 2,
            generation: 3,
            owner: 5,
            epoch: 6
        )
        let outcome = Lifecycle.RestorationItemOutcome.restored(materialization(1))

        let variantPlans = try [
            restorationPlan(
                windows: [baseWindow],
                selectedWindow: 1,
                lineage: 2,
                generation: 3,
                owner: 99,
                epoch: 6
            ),
            restorationPlan(
                windows: [baseWindow],
                selectedWindow: 1,
                lineage: 2,
                generation: 3,
                owner: 5,
                epoch: 7
            ),
            restorationPlan(
                windows: [baseWindow],
                selectedWindow: 1,
                lineage: 22,
                generation: 3,
                owner: 5,
                epoch: 6
            ),
            restorationPlan(
                windows: [baseWindow],
                selectedWindow: 1,
                lineage: 2,
                generation: 4,
                owner: 5,
                epoch: 6
            ),
            restorationPlan(
                windows: [
                    try restorationWindow(
                        1,
                        generation: 5,
                        tabs: [try restorationTab(1, session: try sessionState(left: "A", right: "B"))],
                        selected: 1
                    )
                ],
                selectedWindow: 1,
                lineage: 2,
                generation: 3,
                owner: 5,
                epoch: 6
            ),
            restorationPlan(
                windows: [
                    try restorationWindow(
                        9,
                        generation: 4,
                        tabs: [try restorationTab(1, session: try sessionState(left: "A", right: "B"))],
                        selected: 1
                    )
                ],
                selectedWindow: 9,
                lineage: 2,
                generation: 3,
                owner: 5,
                epoch: 6
            ),
            restorationPlan(
                windows: [
                    try restorationWindow(
                        1,
                        generation: 4,
                        tabs: [try restorationTab(1, session: try sessionState(left: "A", right: "C"))],
                        selected: 1
                    )
                ],
                selectedWindow: 1,
                lineage: 2,
                generation: 3,
                owner: 5,
                epoch: 6
            )
        ]
        for (index, variant) in variantPlans.enumerated() {
            let receipt = Lifecycle.RestorationItemReceipt(
                request: variant.materializations[0],
                outcome: outcome
            )
            assertError(.unknownRestorationReceipt(tabID(1)), "variant \(index)") {
                _ = try base.receipt([receipt])
            }
        }

        let shiftedOrdinal = try restorationPlan(
            windows: [
                try restorationWindow(9, tabs: [try restorationTab(9)], selected: 9),
                baseWindow
            ],
            selectedWindow: 1,
            lineage: 2,
            generation: 3,
            owner: 5,
            epoch: 6
        )
        let wrongOrdinal = Lifecycle.RestorationItemReceipt(
            request: shiftedOrdinal.materializations[1],
            outcome: outcome
        )
        assertError(.unknownRestorationReceipt(tabID(1))) {
            _ = try base.receipt([wrongOrdinal])
        }
    }

    func testRestorationSessionComparisonMetersUTF8AndEveryWireField() throws {
        let baseSession = try sessionState(
            left: "é-left",
            right: "é-right",
            leftReadOnly: true,
            rightReadOnly: true,
            selectedRow: 7,
            activeSide: .right,
            x: -0.0,
            y: 20,
            width: 800,
            height: 600,
            splitOrientation: .horizontal,
            splitFraction: 0.25,
            locationPaneVisible: false,
            locationPaneWidth: 120
        )
        let base = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    tabs: [try restorationTab(1, session: baseSession)],
                    selected: 1
                )
            ],
            selectedWindow: 1
        )
        let outcome = Lifecycle.RestorationItemOutcome.restored(materialization(1))
        let exact = try base.receipt([
            Lifecycle.RestorationItemReceipt(request: base.materializations[0], outcome: outcome)
        ])
        XCTAssertEqual(exact.restoredTabIDs, [tabID(1)])

        let variants = try [
            sessionState(
                left: "e-left",
                right: "é-right",
                leftReadOnly: true,
                rightReadOnly: true,
                selectedRow: 7,
                activeSide: .right,
                x: -0.0,
                y: 20,
                width: 800,
                height: 600,
                splitOrientation: .horizontal,
                splitFraction: 0.25,
                locationPaneVisible: false,
                locationPaneWidth: 120
            ),
            sessionState(
                left: "é-lef",
                right: "é-right",
                leftReadOnly: true,
                rightReadOnly: true,
                selectedRow: 7,
                activeSide: .right,
                x: -0.0,
                y: 20,
                width: 800,
                height: 600,
                splitOrientation: .horizontal,
                splitFraction: 0.25,
                locationPaneVisible: false,
                locationPaneWidth: 120
            ),
            ComparisonSessionState(
                left: .file(URL(fileURLWithPath: "/tmp/left")),
                right: .scratchpad("é-right"),
                leftReadOnly: true,
                rightReadOnly: true,
                selectedRow: 7,
                activeSide: .right,
                windowFrame: ComparisonSessionState.WindowFrame(
                    x: -0.0,
                    y: 20,
                    width: 800,
                    height: 600
                ),
                splitOrientation: .horizontal,
                splitFraction: 0.25,
                locationPaneVisible: false,
                locationPaneWidth: 120
            ),
            sessionState(
                left: "é-left", right: "changed", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: false, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: false, selectedRow: 7, activeSide: .right, x: -0.0,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 8, activeSide: .right, x: -0.0,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .left, x: -0.0,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: 0.0,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0, y: 21,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0, width: 801,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0, height: 601,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0,
                splitOrientation: .vertical, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0,
                splitOrientation: .horizontal, splitFraction: 0.5, locationPaneVisible: false, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: true, locationPaneWidth: 120),
            sessionState(
                left: "é-left", right: "é-right", leftReadOnly: true, rightReadOnly: true, selectedRow: 7, activeSide: .right, x: -0.0,
                splitOrientation: .horizontal, splitFraction: 0.25, locationPaneVisible: false, locationPaneWidth: 121)
        ]
        for (index, session) in variants.enumerated() {
            let variant = try restorationPlan(
                windows: [
                    try restorationWindow(
                        1,
                        tabs: [try restorationTab(1, session: session)],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            )
            let receipt = Lifecycle.RestorationItemReceipt(
                request: variant.materializations[0],
                outcome: outcome
            )
            assertError(.unknownRestorationReceipt(tabID(1)), "session field \(index)") {
                _ = try base.receipt([receipt])
            }
        }

        let fileBase = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    tabs: [
                        try restorationTab(
                            1,
                            session: try fileSessionState(
                                leftPath: "/tmp/left-é.txt",
                                rightPath: "/tmp/right.txt",
                                leftEncoding: .windows1250,
                                rightEncoding: .windows1251
                            )
                        )
                    ],
                    selected: 1
                )
            ],
            selectedWindow: 1
        )
        for (index, session) in try [
            fileSessionState(leftPath: "/tmp/left-e.txt", rightPath: "/tmp/right.txt", leftEncoding: .windows1250, rightEncoding: .windows1251),
            fileSessionState(leftPath: "/tmp/left-é.txt", rightPath: "/tmp/other.txt", leftEncoding: .windows1250, rightEncoding: .windows1251),
            fileSessionState(leftPath: "/tmp/left-é.txt", rightPath: "/tmp/right.txt", leftEncoding: .windows1252, rightEncoding: .windows1251),
            fileSessionState(leftPath: "/tmp/left-é.txt", rightPath: "/tmp/right.txt", leftEncoding: .windows1250, rightEncoding: .windows1252)
        ].enumerated() {
            let variant = try restorationPlan(
                windows: [
                    try restorationWindow(
                        1,
                        tabs: [try restorationTab(1, session: session)],
                        selected: 1
                    )
                ],
                selectedWindow: 1
            )
            assertError(.unknownRestorationReceipt(tabID(1)), "file session field \(index)") {
                _ = try fileBase.receipt([
                    Lifecycle.RestorationItemReceipt(
                        request: variant.materializations[0],
                        outcome: outcome
                    )
                ])
            }
        }
    }

    func testRestorationSessionUTF8ComparisonHasExactWorkBoundary() throws {
        let session = try sessionState(left: "éé", right: "😀")
        let exactPlan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    tabs: [try restorationTab(1, session: session)],
                    selected: 1
                )
            ],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 19, cancellationCheckInterval: 19)
        )
        let receipt = Lifecycle.RestorationItemReceipt(
            request: exactPlan.materializations[0],
            outcome: .restored(materialization(1))
        )
        let exact = try exactPlan.receipt([receipt])
        XCTAssertEqual(exact.workPerformed, 19)

        let shortPlan = try restorationPlan(
            windows: exactPlan.request.windows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 18, cancellationCheckInterval: 18)
        )
        assertError(.workLimitExceeded(maximum: 18)) {
            _ = try shortPlan.receipt([
                Lifecycle.RestorationItemReceipt(
                    request: shortPlan.materializations[0],
                    outcome: .restored(self.materialization(1))
                )
            ])
        }
    }

    func testTitleAndFailureTextPermitHTLFCRAndRejectOtherC0DELAndC1Controls() throws {
        let allowedWhitespace = "Title\tline\nreturn\r"
        XCTAssertEqual(try tab(1, title: allowedWhitespace).title, allowedWhitespace)
        XCTAssertEqual(
            try Lifecycle.RestorationFailure(code: "OK", message: allowedWhitespace).message,
            allowedWhitespace
        )

        let controls =
            Array(0...0x1F).filter { ![0x09, 0x0A, 0x0D].contains($0) }
            + Array(0x7F...0x9F)
        for value in controls {
            let scalar = String(try XCTUnwrap(UnicodeScalar(value)))
            assertError(.invalidTitle, "title U+\(String(value, radix: 16))") {
                _ = try self.tab(1, title: "A\(scalar)B")
            }
            assertError(
                .invalidRestorationFailureMessage,
                "message U+\(String(value, radix: 16))"
            ) {
                _ = try Lifecycle.RestorationFailure(code: "OK", message: "A\(scalar)B")
            }
        }
        for invalid in ["", " ", "\t\n\r"] {
            assertError(.invalidTitle, "blank title") {
                _ = try self.tab(1, title: invalid)
            }
            assertError(.invalidRestorationFailureMessage, "blank message") {
                _ = try Lifecycle.RestorationFailure(code: "OK", message: invalid)
            }
        }
    }

    func testFailureCodeGrammarAndStandaloneStringHardBoundariesAreExact() throws {
        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"
        for scalar in allowed {
            XCTAssertEqual(
                try Lifecycle.RestorationFailure(code: String(scalar), message: "message").code,
                String(scalar)
            )
        }
        for invalid in ["", "bad code", "BAD/CODE", "é", "\n"] {
            assertError(.invalidRestorationFailureCode, "code \(invalid.debugDescription)") {
                _ = try Lifecycle.RestorationFailure(code: invalid, message: "message")
            }
        }

        let exactTitle = String(repeating: "é", count: Lifecycle.Limits.hardMaximumTitleUTF8Bytes / 2)
        XCTAssertEqual(try tab(1, title: exactTitle).title.utf8.count, Lifecycle.Limits.hardMaximumTitleUTF8Bytes)
        assertError(
            .titleTooLarge(maximumUTF8Bytes: Lifecycle.Limits.hardMaximumTitleUTF8Bytes)
        ) {
            _ = try self.tab(1, title: exactTitle + "x")
        }
        let exactCode = String(repeating: "A", count: Lifecycle.Limits.hardMaximumRestorationCodeUTF8Bytes)
        XCTAssertEqual(
            try Lifecycle.RestorationFailure(code: exactCode, message: "message").code.utf8.count,
            Lifecycle.Limits.hardMaximumRestorationCodeUTF8Bytes
        )
        assertError(
            .restorationFailureCodeTooLarge(
                maximumUTF8Bytes: Lifecycle.Limits.hardMaximumRestorationCodeUTF8Bytes
            )
        ) {
            _ = try Lifecycle.RestorationFailure(code: exactCode + "A", message: "message")
        }
        let exactMessage = String(
            repeating: "é",
            count: Lifecycle.Limits.hardMaximumRestorationMessageUTF8Bytes / 2
        )
        XCTAssertEqual(
            try Lifecycle.RestorationFailure(code: "OK", message: exactMessage).message.utf8.count,
            Lifecycle.Limits.hardMaximumRestorationMessageUTF8Bytes
        )
        assertError(
            .restorationFailureMessageTooLarge(
                maximumUTF8Bytes: Lifecycle.Limits.hardMaximumRestorationMessageUTF8Bytes
            )
        ) {
            _ = try Lifecycle.RestorationFailure(code: "OK", message: exactMessage + "x")
        }
    }

    func testConfiguredUTF8AndAggregateStringLimitsUseExactBoundaries() throws {
        let title = "éé"
        let exactLimits = Lifecycle.Limits(
            maximumTitleUTF8Bytes: 4,
            maximumRestorationCodeUTF8Bytes: 2,
            maximumRestorationMessageUTF8Bytes: 4,
            maximumAggregateStringUTF8Bytes: 10
        )
        let exactState = try state(
            windows: [try window(1, tabs: [try tab(1, title: title), try tab(2, title: title)], selected: 1)],
            selectedWindow: 1,
            limits: exactLimits
        )
        XCTAssertEqual(exactState.totalTabCount, 2)

        assertError(.titleTooLarge(maximumUTF8Bytes: 3)) {
            _ = try self.state(
                windows: [try self.window(1, tabs: [try self.tab(1, title: title)], selected: 1)],
                selectedWindow: 1,
                limits: Lifecycle.Limits(
                    maximumTitleUTF8Bytes: 3,
                    maximumRestorationCodeUTF8Bytes: 2,
                    maximumRestorationMessageUTF8Bytes: 4,
                    maximumAggregateStringUTF8Bytes: 4
                )
            )
        }
        assertError(.aggregateStringsTooLarge(maximumUTF8Bytes: 7)) {
            _ = try self.state(
                windows: [try self.window(1, tabs: [try self.tab(1, title: title), try self.tab(2, title: title)], selected: 1)],
                selectedWindow: 1,
                limits: Lifecycle.Limits(
                    maximumTitleUTF8Bytes: 4,
                    maximumRestorationCodeUTF8Bytes: 2,
                    maximumRestorationMessageUTF8Bytes: 4,
                    maximumAggregateStringUTF8Bytes: 7
                )
            )
        }

        let plan = try restorationPlan(
            windows: [
                try restorationWindow(
                    1,
                    tabs: [try restorationTab(1, title: title)],
                    selected: 1
                )
            ],
            selectedWindow: 1,
            limits: exactLimits
        )
        XCTAssertEqual(plan.retainedStringUTF8Bytes, 4)
        let failure = try Lifecycle.RestorationFailure(code: "AB", message: "éé")
        let exactReceipt = try plan.receipt([
            itemReceipt(plan, ordinal: 0, outcome: .failed(failure))
        ])
        XCTAssertEqual(exactReceipt.failedTabIDs, [tabID(1)])

        let codeLimitedPlan = try restorationPlan(
            windows: plan.request.windows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(
                maximumTitleUTF8Bytes: 4,
                maximumRestorationCodeUTF8Bytes: 1,
                maximumRestorationMessageUTF8Bytes: 4,
                maximumAggregateStringUTF8Bytes: 10
            )
        )
        assertError(.restorationFailureCodeTooLarge(maximumUTF8Bytes: 1)) {
            _ = try codeLimitedPlan.receipt([
                self.itemReceipt(codeLimitedPlan, ordinal: 0, outcome: .failed(failure))
            ])
        }
        let messageLimitedPlan = try restorationPlan(
            windows: plan.request.windows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(
                maximumTitleUTF8Bytes: 4,
                maximumRestorationCodeUTF8Bytes: 2,
                maximumRestorationMessageUTF8Bytes: 3,
                maximumAggregateStringUTF8Bytes: 10
            )
        )
        assertError(.restorationFailureMessageTooLarge(maximumUTF8Bytes: 3)) {
            _ = try messageLimitedPlan.receipt([
                self.itemReceipt(messageLimitedPlan, ordinal: 0, outcome: .failed(failure))
            ])
        }
        let aggregateLimitedPlan = try restorationPlan(
            windows: plan.request.windows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(
                maximumTitleUTF8Bytes: 4,
                maximumRestorationCodeUTF8Bytes: 2,
                maximumRestorationMessageUTF8Bytes: 4,
                maximumAggregateStringUTF8Bytes: 9
            )
        )
        assertError(.aggregateStringsTooLarge(maximumUTF8Bytes: 9)) {
            _ = try aggregateLimitedPlan.receipt([
                self.itemReceipt(aggregateLimitedPlan, ordinal: 0, outcome: .failed(failure))
            ])
        }
    }

    func testEveryLimitAcceptsHardBoundaryAndRejectsZeroOrInvalidRange() throws {
        let hard = Lifecycle.Limits(
            maximumWindowCount: Lifecycle.Limits.hardMaximumWindowCount,
            maximumTabsPerWindow: Lifecycle.Limits.hardMaximumTabsPerWindow,
            maximumTotalTabCount: Lifecycle.Limits.hardMaximumTotalTabCount,
            maximumRestorationItemCount: Lifecycle.Limits.hardMaximumRestorationItemCount,
            maximumTitleUTF8Bytes: Lifecycle.Limits.hardMaximumTitleUTF8Bytes,
            maximumRestorationCodeUTF8Bytes: Lifecycle.Limits.hardMaximumRestorationCodeUTF8Bytes,
            maximumRestorationMessageUTF8Bytes: Lifecycle.Limits.hardMaximumRestorationMessageUTF8Bytes,
            maximumAggregateStringUTF8Bytes: Lifecycle.Limits.hardMaximumAggregateStringUTF8Bytes,
            minimumTabWidth: Lifecycle.Limits.hardMinimumTabWidth,
            maximumTabWidth: Lifecycle.Limits.hardMaximumTabWidth,
            maximumWorkUnits: Lifecycle.Limits.hardMaximumWorkUnits,
            cancellationCheckInterval: Lifecycle.Limits.hardMaximumCancellationCheckInterval
        )
        XCTAssertNoThrow(try hard.validate())

        let cases: [(Lifecycle.Limits, Lifecycle.Limit)] = [
            (Lifecycle.Limits(maximumWindowCount: 0), .windows),
            (Lifecycle.Limits(maximumTabsPerWindow: 0), .tabsPerWindow),
            (Lifecycle.Limits(maximumTabsPerWindow: 2, maximumTotalTabCount: 1), .tabsPerWindow),
            (Lifecycle.Limits(maximumTotalTabCount: 0), .totalTabs),
            (Lifecycle.Limits(maximumRestorationItemCount: 0), .restorationItems),
            (Lifecycle.Limits(maximumTitleUTF8Bytes: 0), .titleUTF8Bytes),
            (Lifecycle.Limits(maximumRestorationCodeUTF8Bytes: 0), .restorationCodeUTF8Bytes),
            (Lifecycle.Limits(maximumRestorationMessageUTF8Bytes: 0), .restorationMessageUTF8Bytes),
            (Lifecycle.Limits(maximumAggregateStringUTF8Bytes: 0), .aggregateStringUTF8Bytes),
            (Lifecycle.Limits(maximumTitleUTF8Bytes: 2, maximumAggregateStringUTF8Bytes: 1), .aggregateStringUTF8Bytes),
            (Lifecycle.Limits(minimumTabWidth: 23, maximumTabWidth: 320), .tabWidthRange),
            (Lifecycle.Limits(minimumTabWidth: 72, maximumTabWidth: 4_097), .tabWidthRange),
            (Lifecycle.Limits(minimumTabWidth: 321, maximumTabWidth: 320), .tabWidthRange),
            (Lifecycle.Limits(minimumTabWidth: .nan, maximumTabWidth: 320), .tabWidthRange),
            (Lifecycle.Limits(minimumTabWidth: 72, maximumTabWidth: .infinity), .tabWidthRange),
            (Lifecycle.Limits(maximumWorkUnits: 0), .workUnits),
            (Lifecycle.Limits(cancellationCheckInterval: 0), .cancellationCheckInterval)
        ]
        for (limits, expected) in cases {
            assertError(.invalidLimit(expected), "limit \(expected)") {
                try limits.validate()
            }
        }
    }

    func testStateAndRestorationWorkLimitsHaveExactBoundaries() throws {
        let tabs = [try tab(1, title: "é"), try tab(2, title: "x")]
        let window = try self.window(1, tabs: tabs, selected: 1)
        let exactStateLimits = Lifecycle.Limits(maximumWorkUnits: 8, cancellationCheckInterval: 8)
        let exactState = try state(
            windows: [window],
            selectedWindow: 1,
            limits: exactStateLimits
        )
        XCTAssertEqual(exactState.totalTabCount, 2)
        assertError(.workLimitExceeded(maximum: 7)) {
            _ = try self.state(
                windows: [window],
                selectedWindow: 1,
                limits: Lifecycle.Limits(maximumWorkUnits: 7, cancellationCheckInterval: 7)
            )
        }

        let restorationWindows = [
            try restorationWindow(
                1,
                tabs: [try restorationTab(1, title: "é"), try restorationTab(2, title: "x")],
                selected: 1
            )
        ]
        let exactRestoration = try restorationPlan(
            windows: restorationWindows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 8, cancellationCheckInterval: 8)
        )
        XCTAssertEqual(exactRestoration.workPerformed, 8)
        assertRestorationPlanningError(
            .workLimitExceeded(maximum: 7),
            windows: restorationWindows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 7, cancellationCheckInterval: 7)
        )

        let planningState = try state(
            limits: Lifecycle.Limits(maximumWorkUnits: 1, cancellationCheckInterval: 1)
        )
        let exactPlan = try Lifecycle.plan(
            .setTabWidthPreference(.fixed(100)),
            in: planningState
        )
        XCTAssertEqual(exactPlan.workPerformed, 1)
        let zeroWorkState = try state(
            limits: Lifecycle.Limits(maximumWorkUnits: 1, cancellationCheckInterval: 1)
        )
        XCTAssertEqual(
            try Lifecycle.plan(.setTabWidthPreference(.fixed(100)), in: zeroWorkState).workPerformed,
            1
        )
    }

    func testCancellationCheckErrorMappingPreservesDomainErrors() throws {
        let state = try self.state(
            windows: [try window(1, tabs: [try tab(1), try tab(2)], selected: 1)],
            selectedWindow: 1,
            limits: Lifecycle.Limits(cancellationCheckInterval: 1)
        )
        assertError(.cancelled) {
            _ = try Lifecycle.plan(
                .select(windowID: self.windowID(1), tabID: self.tabID(2)),
                in: state,
                cancellationCheck: { throw CancellationError() }
            )
        }
        assertError(.cancellationCheckFailed) {
            _ = try Lifecycle.plan(
                .select(windowID: self.windowID(1), tabID: self.tabID(2)),
                in: state,
                cancellationCheck: { throw ProbeError.stopped }
            )
        }
        assertError(.noStateChange) {
            _ = try Lifecycle.plan(
                .select(windowID: self.windowID(1), tabID: self.tabID(2)),
                in: state,
                cancellationCheck: { throw LifecycleError.noStateChange }
            )
        }

        let restoration = try restorationPlan(
            windows: [try restorationWindow(1, tabs: [try restorationTab(1)], selected: 1)],
            selectedWindow: 1,
            limits: Lifecycle.Limits(cancellationCheckInterval: 1)
        )
        assertError(.cancelled) {
            _ = try restoration.receipt(
                [self.itemReceipt(restoration, ordinal: 0, outcome: .restored(self.materialization(1)))],
                cancellationCheck: { throw CancellationError() }
            )
        }
        assertError(.cancellationCheckFailed) {
            _ = try restoration.receipt(
                [self.itemReceipt(restoration, ordinal: 0, outcome: .restored(self.materialization(1)))],
                cancellationCheck: { throw ProbeError.stopped }
            )
        }
        assertError(.invalidTitle) {
            _ = try restoration.receipt(
                [self.itemReceipt(restoration, ordinal: 0, outcome: .restored(self.materialization(1)))],
                cancellationCheck: { throw LifecycleError.invalidTitle }
            )
        }
    }

    func testCancellationChecksEntryIntervalsAndFinalBoundary() throws {
        let state = try self.state(
            windows: [try window(1, tabs: [try tab(1), try tab(2)], selected: 1)],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 100, cancellationCheckInterval: 1)
        )
        let successfulProbe = CancellationProbe()
        let plan = try Lifecycle.plan(
            .select(windowID: windowID(1), tabID: tabID(2)),
            in: state,
            cancellationCheck: { try successfulProbe.check() }
        )
        XCTAssertEqual(successfulProbe.count, plan.workPerformed + 2)

        let entryProbe = CancellationProbe(throwOnCheck: 1)
        assertError(.cancelled) {
            _ = try Lifecycle.plan(
                .select(windowID: self.windowID(1), tabID: self.tabID(2)),
                in: state,
                cancellationCheck: { try entryProbe.check() }
            )
        }
        XCTAssertEqual(entryProbe.count, 1)

        let intervalProbe = CancellationProbe(throwOnCheck: 2)
        assertError(.cancelled) {
            _ = try Lifecycle.plan(
                .select(windowID: self.windowID(1), tabID: self.tabID(2)),
                in: state,
                cancellationCheck: { try intervalProbe.check() }
            )
        }
        XCTAssertEqual(intervalProbe.count, 2)

        let finalProbe = CancellationProbe(throwOnCheck: successfulProbe.count)
        assertError(.cancelled) {
            _ = try Lifecycle.plan(
                .select(windowID: self.windowID(1), tabID: self.tabID(2)),
                in: state,
                cancellationCheck: { try finalProbe.check() }
            )
        }
        XCTAssertEqual(finalProbe.count, successfulProbe.count)
    }

    func testRestorationPlanningCancellationMapsCustomDomainIntervalAndFinalChecks() throws {
        let intervalRequest = try restorationRequest(
            windows: [try restorationWindow(1, tabs: [try restorationTab(1)], selected: 1)],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 100, cancellationCheckInterval: 1)
        )
        assertError(.invalidTitle) {
            _ = try Lifecycle.planRestoration(
                intervalRequest,
                cancellationCheck: { throw LifecycleError.invalidTitle }
            )
        }

        let intervalProbe = CancellationProbe(throwOnCheck: 2)
        assertError(.cancelled) {
            _ = try Lifecycle.planRestoration(
                intervalRequest,
                cancellationCheck: { try intervalProbe.check() }
            )
        }
        XCTAssertEqual(intervalProbe.count, 2)

        let finalRequest = try restorationRequest(
            windows: intervalRequest.windows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 100, cancellationCheckInterval: 100)
        )
        let finalProbe = CancellationProbe()
        assertError(.cancellationCheckFailed) {
            _ = try Lifecycle.planRestoration(
                finalRequest,
                cancellationCheck: {
                    try finalProbe.check()
                    if finalProbe.count == 2 { throw ProbeError.stopped }
                }
            )
        }
        XCTAssertEqual(finalProbe.count, 2)
    }

    func testDefaultCancellationPreservesTypedErrorBeforeAndAfterSessionEncoding() async throws {
        let selectedWindowID = windowID(1)
        let selectedTabID = tabID(2)
        let restoredMaterialization = materialization(1)
        let planningState = try state(
            windows: [try window(1, tabs: [try tab(1), try tab(2)], selected: 1)],
            selectedWindow: 1
        )
        let planningError = await Task { () -> LifecycleError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Lifecycle.plan(
                    .select(windowID: selectedWindowID, tabID: selectedTabID),
                    in: planningState
                )
                return nil
            } catch {
                return error as? LifecycleError
            }
        }.value
        XCTAssertEqual(planningError, .cancelled)

        let restorationRequest = try restorationRequest(
            windows: [try restorationWindow(1, tabs: [try restorationTab(1)], selected: 1)],
            selectedWindow: 1
        )
        let restorationError = await Task { () -> LifecycleError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Lifecycle.planRestoration(restorationRequest)
                return nil
            } catch {
                return error as? LifecycleError
            }
        }.value
        XCTAssertEqual(restorationError, .cancelled)

        let plan = try Lifecycle.planRestoration(restorationRequest)
        let receiptError = await Task { () -> LifecycleError? in
            _ = try? plan.materializations[0].sessionState.encodedData()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try plan.receipt([
                    Lifecycle.RestorationItemReceipt(
                        request: plan.materializations[0],
                        outcome: .restored(restoredMaterialization)
                    )
                ])
                return nil
            } catch {
                return error as? LifecycleError
            }
        }.value
        XCTAssertEqual(receiptError, .cancelled)
    }

    func testRestorationReceiptCancellationAfterEncodingCheckpointIsPreserved() throws {
        let plan = try restorationPlan(
            windows: [try restorationWindow(1, tabs: [try restorationTab(1)], selected: 1)],
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 1_000, cancellationCheckInterval: 1_000)
        )
        let successfulProbe = CancellationProbe()
        let item = itemReceipt(plan, ordinal: 0, outcome: .restored(materialization(1)))
        let receipt = try plan.receipt(
            [item],
            cancellationCheck: { try successfulProbe.check() }
        )
        XCTAssertEqual(successfulProbe.count, 2)
        XCTAssertGreaterThan(receipt.workPerformed, 0)

        let afterEncodingProbe = CancellationProbe(throwOnCheck: 2)
        assertError(.cancelled) {
            _ = try plan.receipt(
                [item],
                cancellationCheck: {
                    _ = try plan.materializations[0].sessionState.encodedData()
                    try afterEncodingProbe.check()
                }
            )
        }
        XCTAssertEqual(afterEncodingProbe.count, 2)

        let intervalPlan = try restorationPlan(
            windows: plan.request.windows,
            selectedWindow: 1,
            limits: Lifecycle.Limits(maximumWorkUnits: 1_000, cancellationCheckInterval: 1)
        )
        let intervalItem = itemReceipt(
            intervalPlan,
            ordinal: 0,
            outcome: .restored(materialization(1))
        )
        let intervalProbe = CancellationProbe(throwOnCheck: 2)
        assertError(.cancelled) {
            _ = try intervalPlan.receipt(
                [intervalItem],
                cancellationCheck: { try intervalProbe.check() }
            )
        }
        XCTAssertEqual(intervalProbe.count, 2)
    }

    private func tab(
        _ rawID: UInt64,
        title: String? = nil,
        materializationRevision: UInt64 = 0,
        dirty: Bool = false,
        veto: Lifecycle.CloseVeto = .none,
        restorable: Bool = true,
        eligibility: Lifecycle.TabbingEligibility = .eligible
    ) throws -> Lifecycle.TabState {
        try Lifecycle.TabState(
            id: tabID(rawID),
            title: title ?? "Tab \(rawID)",
            materialization: materialization(rawID, revision: materializationRevision),
            isDirty: dirty,
            closeVeto: veto,
            isRestorable: restorable,
            tabbingEligibility: eligibility
        )
    }

    private func window(
        _ rawID: UInt64,
        generation: UInt64 = 0,
        tabs: [Lifecycle.TabState],
        selected rawSelected: UInt64,
        restorable: Bool = true,
        eligibility: Lifecycle.TabbingEligibility = .eligible
    ) throws -> Lifecycle.WindowState {
        try Lifecycle.WindowState(
            id: windowID(rawID),
            revision: windowRevision(rawID, generation: generation),
            tabs: tabs,
            selectedTabID: tabID(rawSelected),
            isRestorable: restorable,
            tabbingEligibility: eligibility
        )
    }

    private func state(
        lineage rawLineage: UInt64 = 1,
        generation: UInt64 = 0,
        windows: [Lifecycle.WindowState] = [],
        selectedWindow rawSelectedWindow: UInt64? = nil,
        width: Lifecycle.TabWidthPreference = .automatic,
        limits: Lifecycle.Limits = .default
    ) throws -> Lifecycle.State {
        try Lifecycle.State(
            revision: revision(lineage: rawLineage, generation: generation),
            windows: windows,
            selectedWindowID: rawSelectedWindow.map(windowID),
            tabWidthPreference: width,
            limits: limits
        )
    }

    private func restorationTab(
        _ rawID: UInt64,
        title: String? = nil,
        session: ComparisonSessionState? = nil,
        dirty: Bool = false,
        veto: Lifecycle.CloseVeto = .none,
        restorable: Bool = true,
        eligibility: Lifecycle.TabbingEligibility = .eligible
    ) throws -> Lifecycle.RestorationTab {
        try Lifecycle.RestorationTab(
            id: tabID(rawID),
            title: title ?? "Tab \(rawID)",
            sessionState: session ?? sessionState(left: "left-\(rawID)", right: "right-\(rawID)"),
            isDirty: dirty,
            closeVeto: veto,
            isRestorable: restorable,
            tabbingEligibility: eligibility
        )
    }

    private func restorationWindow(
        _ rawID: UInt64,
        generation: UInt64 = 0,
        tabs: [Lifecycle.RestorationTab],
        selected rawSelected: UInt64,
        restorable: Bool = true,
        eligibility: Lifecycle.TabbingEligibility = .eligible
    ) throws -> Lifecycle.RestorationWindow {
        try Lifecycle.RestorationWindow(
            id: windowID(rawID),
            revision: windowRevision(rawID, generation: generation),
            tabs: tabs,
            selectedTabID: tabID(rawSelected),
            isRestorable: restorable,
            tabbingEligibility: eligibility
        )
    }

    private func restorationRequest(
        windows: [Lifecycle.RestorationWindow],
        selectedWindow rawSelectedWindow: UInt64?,
        lineage rawLineage: UInt64 = 1,
        generation: UInt64 = 0,
        owner rawOwner: UInt64 = 1,
        epoch: UInt64 = 0,
        width: Lifecycle.TabWidthPreference = .automatic,
        limits: Lifecycle.Limits = .default
    ) throws -> Lifecycle.RestorationRequest {
        Lifecycle.RestorationRequest(
            publicationCAS: try publicationCAS(owner: rawOwner, epoch: epoch),
            sessionRevision: revision(lineage: rawLineage, generation: generation),
            windows: windows,
            selectedWindowID: rawSelectedWindow.map(windowID),
            tabWidthPreference: width,
            limits: limits
        )
    }

    private func restorationPlan(
        windows: [Lifecycle.RestorationWindow],
        selectedWindow: UInt64?,
        lineage: UInt64 = 1,
        generation: UInt64 = 0,
        owner: UInt64 = 1,
        epoch: UInt64 = 0,
        width: Lifecycle.TabWidthPreference = .automatic,
        limits: Lifecycle.Limits = .default
    ) throws -> Lifecycle.RestorationPlan {
        try Lifecycle.planRestoration(
            restorationRequest(
                windows: windows,
                selectedWindow: selectedWindow,
                lineage: lineage,
                generation: generation,
                owner: owner,
                epoch: epoch,
                width: width,
                limits: limits
            )
        )
    }

    private func sessionState(
        left: String = "left",
        right: String = "right",
        leftReadOnly: Bool = false,
        rightReadOnly: Bool = false,
        selectedRow: Int? = nil,
        activeSide: ComparisonSessionState.Side = .left,
        x: Double = 10,
        y: Double = 20,
        width: Double = 800,
        height: Double = 600,
        splitOrientation: ComparisonSessionState.SplitOrientation = .vertical,
        splitFraction: Double = 0.5,
        locationPaneVisible: Bool = true,
        locationPaneWidth: Double = 92
    ) throws -> ComparisonSessionState {
        try ComparisonSessionState(
            left: .scratchpad(left),
            right: .scratchpad(right),
            leftReadOnly: leftReadOnly,
            rightReadOnly: rightReadOnly,
            selectedRow: selectedRow,
            activeSide: activeSide,
            windowFrame: ComparisonSessionState.WindowFrame(
                x: x,
                y: y,
                width: width,
                height: height
            ),
            splitOrientation: splitOrientation,
            splitFraction: splitFraction,
            locationPaneVisible: locationPaneVisible,
            locationPaneWidth: locationPaneWidth
        )
    }

    private func fileSessionState(
        leftPath: String,
        rightPath: String,
        leftEncoding: ComparisonSessionState.FileEncoding,
        rightEncoding: ComparisonSessionState.FileEncoding
    ) throws -> ComparisonSessionState {
        try ComparisonSessionState(
            left: .file(URL(fileURLWithPath: leftPath)),
            right: .file(URL(fileURLWithPath: rightPath)),
            leftEncoding: leftEncoding,
            rightEncoding: rightEncoding,
            windowFrame: ComparisonSessionState.WindowFrame(x: 10, y: 20, width: 800, height: 600)
        )
    }

    private func itemReceipt(
        _ plan: Lifecycle.RestorationPlan,
        ordinal: Int,
        outcome: Lifecycle.RestorationItemOutcome
    ) -> Lifecycle.RestorationItemReceipt {
        Lifecycle.RestorationItemReceipt(request: plan.materializations[ordinal], outcome: outcome)
    }

    private func selectionIntent(_ plan: Lifecycle.Plan) throws -> Lifecycle.SelectionIntent {
        guard case .selection(let intent) = plan.effect else {
            throw UnexpectedEffectError()
        }
        return intent
    }

    private func closeIntent(_ plan: Lifecycle.Plan) throws -> Lifecycle.CloseIntent {
        guard case .close(let intent) = plan.effect else {
            throw UnexpectedEffectError()
        }
        return intent
    }

    private func detachIntent(_ plan: Lifecycle.Plan) throws -> Lifecycle.DetachIntent {
        guard case .detach(let intent) = plan.effect else {
            throw UnexpectedEffectError()
        }
        return intent
    }

    private func moveIntent(_ plan: Lifecycle.Plan) throws -> Lifecycle.MoveIntent {
        guard case .move(let intent) = plan.effect else {
            throw UnexpectedEffectError()
        }
        return intent
    }

    private func reservation(_ rawID: UInt64) throws -> Lifecycle.WindowReservation {
        try Lifecycle.WindowReservation(
            id: windowID(rawID),
            initialRevision: windowRevision(rawID, generation: 0)
        )
    }

    private func publicationCAS(owner: UInt64, epoch: UInt64) throws -> Lifecycle.RestorationPublicationCAS {
        try Lifecycle.RestorationPublicationCAS(ownerID: ownerID(owner), expectedEpoch: epoch)
    }

    private func revision(lineage rawLineage: UInt64, generation: UInt64) -> Lifecycle.SessionRevision {
        Lifecycle.SessionRevision(lineage: lineage(rawLineage), generation: generation)
    }

    private func windowRevision(_ rawID: UInt64, generation: UInt64) -> Lifecycle.WindowRevision {
        Lifecycle.WindowRevision(windowID: windowID(rawID), generation: generation)
    }

    private func materialization(_ rawID: UInt64, revision: UInt64 = 0) -> Lifecycle.MaterializationReference {
        Lifecycle.MaterializationReference(identity: materializationID(rawID), revision: revision)
    }

    private func windowID(_ rawValue: UInt64) -> Lifecycle.WindowID {
        Lifecycle.WindowID(rawValue: rawValue)
    }

    private func tabID(_ rawValue: UInt64) -> Lifecycle.TabID {
        Lifecycle.TabID(rawValue: rawValue)
    }

    private func lineage(_ rawValue: UInt64) -> Lifecycle.SessionLineage {
        Lifecycle.SessionLineage(rawValue: rawValue)
    }

    private func materializationID(_ rawValue: UInt64) -> Lifecycle.MaterializationID {
        Lifecycle.MaterializationID(rawValue: rawValue)
    }

    private func ownerID(_ rawValue: UInt64) -> Lifecycle.RestorationOwnerID {
        Lifecycle.RestorationOwnerID(rawValue: rawValue)
    }

    private func assertRestorationPlanningError(
        _ expected: LifecycleError,
        windows: [Lifecycle.RestorationWindow],
        selectedWindow: UInt64?,
        limits: Lifecycle.Limits = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertError(expected, file: file, line: line) {
            _ = try Lifecycle.planRestoration(
                self.restorationRequest(
                    windows: windows,
                    selectedWindow: selectedWindow,
                    limits: limits
                )
            )
        }
    }

    private func assertError<T>(
        _ expected: LifecycleError,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), message(), file: file, line: line) {
            XCTAssertEqual($0 as? LifecycleError, expected, message(), file: file, line: line)
        }
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

private enum ProbeError: Error {
    case stopped
}

private struct UnexpectedEffectError: Error {}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let throwOnCheck: Int?
    private var storedCount = 0

    init(throwOnCheck: Int? = nil) {
        self.throwOnCheck = throwOnCheck
    }

    var count: Int {
        lock.withLock { storedCount }
    }

    func check() throws {
        let shouldThrow = lock.withLock {
            storedCount += 1
            return storedCount == throwOnCheck
        }
        if shouldThrow {
            throw CancellationError()
        }
    }
}
