import MacMergeCore
import XCTest

final class ComparisonWindowCommandStateTests: XCTestCase {
    typealias State = ComparisonWindowCommandState
    typealias Command = State.Identifier

    func testIdentifierOrderAliasesAndRichSnapshotDerivedState() throws {
        XCTAssertEqual(
            Command.allCases,
            [
                .closeAll,
                .closeOthers,
                .closeLeft,
                .closeRight,
                .nextTab,
                .previousTab,
                .nextWindow,
                .previousWindow,
                .moveToNewWindow,
                .mergeAllWindows,
                .split,
                .tile
            ]
        )
        XCTAssertEqual(Command.closeAllWindows, .closeAll)
        XCTAssertEqual(Command.closeOtherTabs, .closeOthers)
        XCTAssertEqual(Command.closeTabsToLeft, .closeLeft)
        XCTAssertEqual(Command.closeTabsToRight, .closeRight)
        XCTAssertEqual(Command.selectNextTab, .nextTab)
        XCTAssertEqual(Command.selectPreviousTab, .previousTab)
        XCTAssertEqual(Command.selectNextWindow, .nextWindow)
        XCTAssertEqual(Command.selectPreviousWindow, .previousWindow)
        XCTAssertEqual(Command.moveSelectedTabToNewWindow, .moveToNewWindow)
        XCTAssertEqual(Command.splitWindow, .split)
        XCTAssertEqual(Command.tileWindows, .tile)

        let snapshot = try richSnapshot()

        XCTAssertEqual(snapshot.lineage, lineage(41))
        XCTAssertEqual(snapshot.generation, 7)
        XCTAssertEqual(snapshot.keyWindowID, windowID(1))
        XCTAssertEqual(snapshot.keyWindow?.id, windowID(1))
        XCTAssertEqual(snapshot.totalTabCount, 6)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(snapshot.dirtyTabIDs, [tabID(2), tabID(5)])
        XCTAssertEqual(snapshot.closeVetoedTabIDs, [tabID(2), tabID(4)])
        XCTAssertEqual(snapshot.nonRestorableWindowIDs, [windowID(2)])
        XCTAssertEqual(snapshot.nonRestorableTabIDs, [tabID(3)])
        XCTAssertEqual(snapshot.window(withID: windowID(2))?.selectedTabID, tabID(4))
        XCTAssertEqual(snapshot.tab(withID: tabID(5))?.id, tabID(5))
        XCTAssertNil(snapshot.window(withID: windowID(99)))
        XCTAssertNil(snapshot.tab(withID: tabID(99)))
        XCTAssertTrue(try XCTUnwrap(snapshot.window(withID: windowID(1))).isDirty)
        XCTAssertTrue(try XCTUnwrap(snapshot.window(withID: windowID(1))).isCloseVetoed)
        XCTAssertTrue(try XCTUnwrap(snapshot.window(withID: windowID(1))).isEligibleForTabbing)
    }

    func testFingerprintIncludesLineageGenerationLimitsAndEveryWindowAndTabField() throws {
        let baseTabs = [
            tab(1, selected: true),
            tab(2)
        ]
        let base = try snapshot(
            lineage: 10,
            generation: 20,
            windows: [window(1, tabs: baseTabs)]
        )
        let identical = try snapshot(
            lineage: 10,
            generation: 20,
            windows: [window(1, tabs: baseTabs)]
        )
        XCTAssertEqual(base.fingerprint, identical.fingerprint)
        XCTAssertEqual(base.fingerprint.lineage, lineage(10))
        XCTAssertEqual(base.fingerprint.generation, 20)

        let variants = try [
            snapshot(lineage: 11, generation: 20, windows: [window(1, tabs: baseTabs)]),
            snapshot(lineage: 10, generation: 21, windows: [window(1, tabs: baseTabs)]),
            snapshot(lineage: 10, generation: 20, windows: [window(2, tabs: baseTabs)]),
            snapshot(lineage: 10, generation: 20, windows: [window(1, tabs: baseTabs, key: true)]),
            snapshot(lineage: 10, generation: 20, windows: [window(1, tabs: baseTabs, minimized: true)]),
            snapshot(lineage: 10, generation: 20, windows: [window(1, tabs: baseTabs, fullScreen: true)]),
            snapshot(lineage: 10, generation: 20, windows: [window(1, tabs: baseTabs, restorable: false)]),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [
                    window(
                        1,
                        tabs: baseTabs,
                        eligibility: .ineligible(.transientWindow)
                    )
                ]
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: [tab(3, selected: true), tab(2)])]
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: [tab(1), tab(2, selected: true)])]
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: [tab(1, selected: true, dirty: true), tab(2)])]
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: [tab(1, selected: true, vetoed: true), tab(2)])]
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: [tab(1, selected: true, restorable: false), tab(2)])]
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [
                    window(
                        1,
                        tabs: [
                            tab(
                                1,
                                selected: true,
                                eligibility: .ineligible(.unsupportedContent)
                            ),
                            tab(2)
                        ]
                    )
                ]
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: [tab(2), tab(1, selected: true)])]
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: baseTabs)],
                limits: State.Limits(maximumWindowCount: 255)
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: baseTabs)],
                limits: State.Limits(maximumTabsPerWindow: 255)
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: baseTabs)],
                limits: State.Limits(maximumTotalTabCount: 4_095)
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: baseTabs)],
                limits: State.Limits(maximumWorkUnits: 32_767)
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: baseTabs)],
                limits: State.Limits(maximumAggregateWorkUnits: 1_000)
            ),
            snapshot(
                lineage: 10,
                generation: 20,
                windows: [window(1, tabs: baseTabs)],
                limits: State.Limits(cancellationCheckInterval: 63)
            )
        ]

        for (index, variant) in variants.enumerated() {
            XCTAssertNotEqual(base.fingerprint, variant.fingerprint, "Variant \(index)")
        }

        let ordered = try snapshot(
            lineage: 10,
            generation: 20,
            windows: [
                window(1, tabs: [tab(1, selected: true)]),
                window(2, tabs: [tab(2, selected: true)])
            ]
        )
        let reordered = try snapshot(
            lineage: 10,
            generation: 20,
            windows: [
                window(2, tabs: [tab(2, selected: true)]),
                window(1, tabs: [tab(1, selected: true)])
            ]
        )
        XCTAssertNotEqual(ordered.fingerprint, reordered.fingerprint)
    }

    func testSnapshotRejectsEveryInvalidLimit() {
        let validWindow = window(1, tabs: [tab(1, selected: true)])
        let cases: [(State.Limits, State.StateError)] = [
            (
                State.Limits(maximumWindowCount: 0, maximumAggregateWorkUnits: 1),
                .invalidLimit(.windows, value: 0)
            ),
            (
                State.Limits(maximumTabsPerWindow: 0, maximumAggregateWorkUnits: 1),
                .invalidLimit(.tabsPerWindow, value: 0)
            ),
            (
                State.Limits(maximumTotalTabCount: 0, maximumAggregateWorkUnits: 1),
                .invalidLimit(.totalTabs, value: 0)
            ),
            (
                State.Limits(maximumWorkUnits: 0, maximumAggregateWorkUnits: 1),
                .invalidLimit(.work, value: 0)
            ),
            (
                State.Limits(maximumAggregateWorkUnits: 0),
                .invalidLimit(.aggregateWork, value: 0)
            ),
            (
                State.Limits(maximumAggregateWorkUnits: 1, cancellationCheckInterval: 0),
                .invalidLimit(.cancellationCheckInterval, value: 0)
            ),
            (
                State.Limits(maximumWindowCount: -1, maximumAggregateWorkUnits: 1),
                .invalidLimit(.windows, value: -1)
            ),
            (
                State.Limits(maximumTabsPerWindow: -2, maximumAggregateWorkUnits: 1),
                .invalidLimit(.tabsPerWindow, value: -2)
            ),
            (
                State.Limits(maximumTotalTabCount: -3, maximumAggregateWorkUnits: 1),
                .invalidLimit(.totalTabs, value: -3)
            ),
            (
                State.Limits(maximumWorkUnits: -4, maximumAggregateWorkUnits: 1),
                .invalidLimit(.work, value: -4)
            ),
            (
                State.Limits(maximumAggregateWorkUnits: -5),
                .invalidLimit(.aggregateWork, value: -5)
            ),
            (
                State.Limits(maximumAggregateWorkUnits: 1, cancellationCheckInterval: -6),
                .invalidLimit(.cancellationCheckInterval, value: -6)
            )
        ]

        for (limits, expected) in cases {
            assertStateError(expected) {
                _ = try State.Snapshot(
                    lineage: self.lineage(1),
                    generation: 1,
                    windows: [validWindow],
                    limits: limits
                )
            }
        }
    }

    func testSnapshotConstructionWorkBudgetAcceptsExactBoundaryAndRejectsNextUnit() throws {
        let windows = [window(1, tabs: [tab(1, selected: true)])]
        let exact = try snapshot(
            windows: windows,
            limits: State.Limits(maximumWorkUnits: 2)
        )
        XCTAssertEqual(exact.windows, windows)
        XCTAssertEqual(exact.totalTabCount, 1)

        assertStateError(.workLimitExceeded(maximum: 1)) {
            _ = try self.snapshot(
                windows: windows,
                limits: State.Limits(maximumWorkUnits: 1)
            )
        }
    }

    func testSnapshotRejectsEveryInvalidWindowAndTabShape() {
        assertStateError(.tooManyWindows(maximum: 1)) {
            _ = try self.snapshot(
                windows: [
                    self.window(1, tabs: [self.tab(1, selected: true)]),
                    self.window(2, tabs: [self.tab(2, selected: true)])
                ],
                limits: State.Limits(maximumWindowCount: 1)
            )
        }
        assertStateError(.emptyWindow(windowID(1))) {
            _ = try self.snapshot(windows: [self.window(1, tabs: [])])
        }
        assertStateError(.tooManyTabs(windowID: windowID(1), maximum: 1)) {
            _ = try self.snapshot(
                windows: [
                    self.window(1, tabs: [self.tab(1, selected: true), self.tab(2)])
                ],
                limits: State.Limits(maximumTabsPerWindow: 1)
            )
        }
        assertStateError(.tooManyTotalTabs(maximum: 1)) {
            _ = try self.snapshot(
                windows: [
                    self.window(1, tabs: [self.tab(1, selected: true), self.tab(2)])
                ],
                limits: State.Limits(maximumTabsPerWindow: 2, maximumTotalTabCount: 1)
            )
        }
        assertStateError(.duplicateWindowID(windowID(1))) {
            _ = try self.snapshot(
                windows: [
                    self.window(1, tabs: [self.tab(1, selected: true)]),
                    self.window(1, tabs: [self.tab(2, selected: true)])
                ]
            )
        }
        assertStateError(.duplicateTabID(tabID(1))) {
            _ = try self.snapshot(
                windows: [
                    self.window(1, tabs: [self.tab(1, selected: true)]),
                    self.window(2, tabs: [self.tab(1, selected: true)])
                ]
            )
        }
        assertStateError(.invalidSelectedTabCount(windowID: windowID(1), count: 0)) {
            _ = try self.snapshot(windows: [self.window(1, tabs: [self.tab(1)])])
        }
        assertStateError(.invalidSelectedTabCount(windowID: windowID(1), count: 2)) {
            _ = try self.snapshot(
                windows: [
                    self.window(
                        1,
                        tabs: [self.tab(1, selected: true), self.tab(2, selected: true)]
                    )
                ]
            )
        }
        assertStateError(.multipleKeyWindows(first: windowID(1), second: windowID(2))) {
            _ = try self.snapshot(
                windows: [
                    self.window(1, tabs: [self.tab(1, selected: true)], key: true),
                    self.window(2, tabs: [self.tab(2, selected: true)], key: true)
                ]
            )
        }
        assertStateError(.keyWindowMinimized(windowID(1))) {
            _ = try self.snapshot(
                windows: [
                    self.window(
                        1,
                        tabs: [self.tab(1, selected: true)],
                        key: true,
                        minimized: true
                    )
                ]
            )
        }
        assertStateError(.contradictoryPresentationState(windowID(1))) {
            _ = try self.snapshot(
                windows: [
                    self.window(
                        1,
                        tabs: [self.tab(1, selected: true)],
                        minimized: true,
                        fullScreen: true
                    )
                ]
            )
        }
    }

    func testEveryCommandResolvesInStableOrderWithExactRichTargets() throws {
        let snapshot = try richSnapshot()
        let resolutions = try State.resolveAll(in: snapshot)
        XCTAssertEqual(resolutions.map(\.command), Command.allCases)
        XCTAssertEqual(resolutions.map(\.expectedGeneration), Array(repeating: 7, count: 12))
        XCTAssertTrue(resolutions.allSatisfy { $0.expectedSnapshotFingerprint == snapshot.fingerprint })

        let byCommand = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.command, $0) })
        let closeAll = try closePlan(XCTUnwrap(byCommand[.closeAll]))
        XCTAssertEqual(
            closeAll.targets,
            [
                closeTarget(window: 3, tab: 6),
                closeTarget(window: 2, tab: 5, dirty: true, windowRestorable: false),
                closeTarget(window: 2, tab: 4, vetoed: true, windowRestorable: false),
                closeTarget(window: 1, tab: 3, tabRestorable: false),
                closeTarget(window: 1, tab: 2, dirty: true, vetoed: true),
                closeTarget(window: 1, tab: 1)
            ]
        )
        XCTAssertEqual(closeAll.dirtyTargets.map(\.tabID), [tabID(5), tabID(2)])
        XCTAssertEqual(closeAll.vetoedTargets.map(\.tabID), [tabID(4), tabID(2)])
        XCTAssertEqual(closeAll.nonRestorableTargets.map(\.tabID), [tabID(5), tabID(4), tabID(3)])
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.closeAll]).enabledReason,
            .closeTargets(targetCount: 6, dirtyTargetCount: 2, nonRestorableTargetCount: 3)
        )

        XCTAssertEqual(
            try XCTUnwrap(byCommand[.closeOthers]).enabledReason,
            .closeTargets(targetCount: 2, dirtyTargetCount: 0, nonRestorableTargetCount: 1)
        )
        XCTAssertEqual(
            try closePlan(XCTUnwrap(byCommand[.closeOthers])).targets,
            [
                closeTarget(window: 1, tab: 3, tabRestorable: false),
                closeTarget(window: 1, tab: 1)
            ]
        )
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.closeLeft]).enabledReason,
            .closeTargets(targetCount: 1, dirtyTargetCount: 0, nonRestorableTargetCount: 0)
        )
        XCTAssertEqual(
            try closePlan(XCTUnwrap(byCommand[.closeLeft])).targets,
            [closeTarget(window: 1, tab: 1)]
        )
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.closeRight]).enabledReason,
            .closeTargets(targetCount: 1, dirtyTargetCount: 0, nonRestorableTargetCount: 1)
        )
        XCTAssertEqual(
            try closePlan(XCTUnwrap(byCommand[.closeRight])).targets,
            [closeTarget(window: 1, tab: 3, tabRestorable: false)]
        )

        XCTAssertEqual(
            try tabNavigationPlan(XCTUnwrap(byCommand[.nextTab])),
            State.TabNavigationPlan(
                windowID: windowID(1),
                sourceTabID: tabID(2),
                targetTabID: tabID(3)
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.nextTab]).enabledReason,
            .tabNavigation(target: tabID(3))
        )
        XCTAssertEqual(
            try tabNavigationPlan(XCTUnwrap(byCommand[.previousTab])),
            State.TabNavigationPlan(
                windowID: windowID(1),
                sourceTabID: tabID(2),
                targetTabID: tabID(1)
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.previousTab]).enabledReason,
            .tabNavigation(target: tabID(1))
        )
        XCTAssertEqual(
            try windowNavigationPlan(XCTUnwrap(byCommand[.nextWindow])),
            State.WindowNavigationPlan(
                sourceWindowID: windowID(1),
                targetWindowID: windowID(2),
                targetTabID: tabID(4),
                restoresMinimizedWindow: true
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.nextWindow]).enabledReason,
            .windowNavigation(target: windowID(2))
        )
        XCTAssertEqual(
            try windowNavigationPlan(XCTUnwrap(byCommand[.previousWindow])),
            State.WindowNavigationPlan(
                sourceWindowID: windowID(1),
                targetWindowID: windowID(3),
                targetTabID: tabID(6),
                restoresMinimizedWindow: false
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.previousWindow]).enabledReason,
            .windowNavigation(target: windowID(3))
        )

        let move = try movePlan(XCTUnwrap(byCommand[.moveToNewWindow]))
        XCTAssertEqual(move.sourceWindowID, windowID(1))
        XCTAssertEqual(move.destinationWindowIDAllocation, .owningRegistry)
        XCTAssertEqual(move.tabID, tabID(2))
        XCTAssertEqual(move.replacementSourceTabID, tabID(3))
        XCTAssertTrue(move.isDirty)
        XCTAssertTrue(move.isRestorable)
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.moveToNewWindow]).enabledReason,
            .moveToNewWindow(tabID: tabID(2))
        )

        let merge = try mergePlan(XCTUnwrap(byCommand[.mergeAllWindows]))
        XCTAssertEqual(merge.destinationWindowID, windowID(1))
        XCTAssertEqual(merge.destinationSelectedTabID, tabID(2))
        XCTAssertEqual(
            merge.sources,
            [
                State.WindowTabMove(sourceWindowID: windowID(2), tabIDs: [tabID(4), tabID(5)]),
                State.WindowTabMove(sourceWindowID: windowID(3), tabIDs: [tabID(6)])
            ]
        )
        XCTAssertEqual(merge.restoreMinimizedWindowIDs, [windowID(2)])
        XCTAssertEqual(merge.resultingTabOrder, (1...6).map(tabID))
        XCTAssertEqual(merge.nonRestorableTabIDs, [tabID(3), tabID(4), tabID(5)])
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.mergeAllWindows]).enabledReason,
            .mergeAllWindows(destination: windowID(1), movedTabCount: 3)
        )

        let split = try XCTUnwrap(byCommand[.split])
        XCTAssertEqual(split.targetPlan, .none)
        XCTAssertEqual(split.availability, .disabled(.unsupportedCommand(.split)))
        XCTAssertEqual(split.platformOutcome, .unsupported(.comparisonWindowSplit))
        XCTAssertFalse(split.canExecute)

        let tile = try arrangementPlan(XCTUnwrap(byCommand[.tile]))
        XCTAssertEqual(tile.windowIDs, [windowID(1), windowID(2), windowID(3)])
        XCTAssertEqual(tile.restoreMinimizedWindowIDs, [windowID(2)])
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.tile]).enabledReason,
            .macOSAdaptation(.nativeDocumentWindowsAndTabs)
        )
        XCTAssertEqual(
            try XCTUnwrap(byCommand[.tile]).platformOutcome,
            .macOSAdaptation(.nativeDocumentWindowsAndTabs)
        )

        for command in Command.allCases where command != .split {
            let resolution = try XCTUnwrap(byCommand[command])
            XCTAssertTrue(resolution.isEnabled, "Command \(command)")
            XCTAssertTrue(resolution.canExecute, "Command \(command)")
            XCTAssertNil(resolution.disabledReason, "Command \(command)")
            XCTAssertTrue(try State.canExecute(command, in: snapshot), "Command \(command)")
            XCTAssertEqual(
                resolution.platformOutcome,
                command == .tile ? .macOSAdaptation(.nativeDocumentWindowsAndTabs) : .native,
                "Command \(command)"
            )
        }
        XCTAssertFalse(try State.canExecute(.split, in: snapshot))
    }

    func testEveryCommandHasExplicitEmptySnapshotAvailabilityAndTarget() throws {
        let snapshot = try self.snapshot(windows: [])
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertNil(snapshot.keyWindow)
        let resolutions = try State.resolveAll(in: snapshot)

        for resolution in resolutions {
            switch resolution.command {
            case .closeAll, .closeOthers, .closeLeft, .closeRight:
                XCTAssertEqual(try closePlan(resolution).targets, [])
                XCTAssertEqual(resolution.availability, .disabled(.noWindows))
                XCTAssertEqual(resolution.platformOutcome, .native)
            case .nextTab, .previousTab, .nextWindow, .previousWindow, .moveToNewWindow,
                .mergeAllWindows:
                XCTAssertEqual(resolution.targetPlan, .none)
                XCTAssertEqual(resolution.availability, .disabled(.noWindows))
                XCTAssertEqual(resolution.platformOutcome, .native)
            case .split:
                XCTAssertEqual(resolution.targetPlan, .none)
                XCTAssertEqual(resolution.availability, .disabled(.unsupportedCommand(.split)))
                XCTAssertEqual(resolution.platformOutcome, .unsupported(.comparisonWindowSplit))
            case .tile:
                XCTAssertEqual(
                    try arrangementPlan(resolution),
                    State.NativeWindowArrangementPlan(windowIDs: [], restoreMinimizedWindowIDs: [])
                )
                XCTAssertEqual(resolution.availability, .disabled(.noWindows))
                XCTAssertEqual(
                    resolution.platformOutcome,
                    .macOSAdaptation(.nativeDocumentWindowsAndTabs)
                )
            }
        }
    }

    func testNoKeyAndSingleWindowDisabledReasonsAndTargetsAreLiteral() throws {
        let noKey = try snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true)]),
                window(2, tabs: [tab(2, selected: true)])
            ]
        )
        let noKeyCloseAll = try State.resolve(.closeAll, in: noKey)
        XCTAssertEqual(
            try closePlan(noKeyCloseAll).targets,
            [closeTarget(window: 2, tab: 2), closeTarget(window: 1, tab: 1)]
        )
        XCTAssertEqual(
            noKeyCloseAll.enabledReason,
            .closeTargets(targetCount: 2, dirtyTargetCount: 0, nonRestorableTargetCount: 0)
        )
        XCTAssertEqual(noKeyCloseAll.platformOutcome, .native)

        let noKeyTile = try State.resolve(.tile, in: noKey)
        XCTAssertEqual(
            try arrangementPlan(noKeyTile),
            State.NativeWindowArrangementPlan(
                windowIDs: [windowID(1), windowID(2)],
                restoreMinimizedWindowIDs: []
            )
        )
        XCTAssertEqual(
            noKeyTile.enabledReason,
            .macOSAdaptation(.nativeDocumentWindowsAndTabs)
        )
        XCTAssertEqual(
            noKeyTile.platformOutcome,
            .macOSAdaptation(.nativeDocumentWindowsAndTabs)
        )

        for command in [Command.closeOthers, .closeLeft, .closeRight] {
            let resolution = try State.resolve(command, in: noKey)
            XCTAssertEqual(
                resolution.availability,
                .disabled(.noKeyWindow),
                "Command \(command)"
            )
            XCTAssertEqual(
                try closePlan(resolution),
                State.ClosePlan(targets: []),
                "Command \(command)"
            )
            XCTAssertEqual(resolution.platformOutcome, .native, "Command \(command)")
        }
        for command in [
            Command.nextTab,
            .previousTab,
            .nextWindow,
            .previousWindow,
            .moveToNewWindow,
            .mergeAllWindows
        ] {
            let resolution = try State.resolve(command, in: noKey)
            XCTAssertEqual(
                resolution.availability,
                .disabled(.noKeyWindow),
                "Command \(command)"
            )
            XCTAssertEqual(resolution.targetPlan, .none, "Command \(command)")
            XCTAssertEqual(resolution.platformOutcome, .native, "Command \(command)")
        }

        let single = try snapshot(
            windows: [window(1, tabs: [tab(1, selected: true)], key: true)]
        )
        let expected: [(Command, State.DisabledReason, State.TargetPlan, State.PlatformOutcome)] = [
            (.closeOthers, .noOtherTabs, .close(State.ClosePlan(targets: [])), .native),
            (.closeLeft, .noTabsToLeft, .close(State.ClosePlan(targets: [])), .native),
            (.closeRight, .noTabsToRight, .close(State.ClosePlan(targets: [])), .native),
            (.nextTab, .noOtherTabs, .none, .native),
            (.previousTab, .noOtherTabs, .none, .native),
            (.nextWindow, .noOtherWindows, .none, .native),
            (.previousWindow, .noOtherWindows, .none, .native),
            (.moveToNewWindow, .noOtherTabs, .none, .native),
            (.mergeAllWindows, .noOtherWindows, .none, .native),
            (
                .split,
                .unsupportedCommand(.split),
                .none,
                .unsupported(.comparisonWindowSplit)
            ),
            (
                .tile,
                .noOtherWindows,
                .nativeWindowArrangement(
                    State.NativeWindowArrangementPlan(
                        windowIDs: [windowID(1)],
                        restoreMinimizedWindowIDs: []
                    )
                ),
                .macOSAdaptation(.nativeDocumentWindowsAndTabs)
            )
        ]
        for (command, reason, target, outcome) in expected {
            let resolution = try State.resolve(command, in: single)
            XCTAssertEqual(
                resolution.availability,
                .disabled(reason),
                "Command \(command)"
            )
            XCTAssertEqual(resolution.targetPlan, target, "Command \(command)")
            XCTAssertEqual(resolution.platformOutcome, outcome, "Command \(command)")
        }
        let singleCloseAll = try State.resolve(.closeAll, in: single)
        XCTAssertEqual(
            try closePlan(singleCloseAll),
            State.ClosePlan(targets: [closeTarget(window: 1, tab: 1)])
        )
        XCTAssertEqual(
            singleCloseAll.enabledReason,
            .closeTargets(targetCount: 1, dirtyTargetCount: 0, nonRestorableTargetCount: 0)
        )
        XCTAssertEqual(singleCloseAll.platformOutcome, .native)
    }

    func testCommandSpecificDisabledReasonsCoverLimitsAndTabbingEligibility() throws {
        let windowLimited = try snapshot(
            windows: [
                window(
                    1,
                    tabs: [tab(1, selected: true), tab(2)],
                    key: true
                )
            ],
            limits: State.Limits(maximumWindowCount: 1)
        )
        XCTAssertEqual(
            try State.resolve(.moveToNewWindow, in: windowLimited).availability,
            .disabled(.windowLimitReached(maximum: 1))
        )

        let ineligibleWindow = try snapshot(
            windows: [
                window(
                    1,
                    tabs: [tab(1, selected: true), tab(2)],
                    key: true,
                    eligibility: .ineligible(.modalWorkflow)
                ),
                window(2, tabs: [tab(3, selected: true)])
            ]
        )
        XCTAssertEqual(
            try State.resolve(.moveToNewWindow, in: ineligibleWindow).availability,
            .disabled(.windowTabbingIneligible(windowID(1), .modalWorkflow))
        )
        XCTAssertEqual(
            try State.resolve(.mergeAllWindows, in: ineligibleWindow).availability,
            .disabled(.windowTabbingIneligible(windowID(1), .modalWorkflow))
        )

        let ineligibleSourceWindow = try snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true)], key: true),
                window(
                    2,
                    tabs: [tab(2, selected: true)],
                    eligibility: .ineligible(.transientWindow)
                )
            ]
        )
        XCTAssertEqual(
            try State.resolve(.mergeAllWindows, in: ineligibleSourceWindow).availability,
            .disabled(.windowTabbingIneligible(windowID(2), .transientWindow))
        )

        let ineligibleSelectedTab = try snapshot(
            windows: [
                window(
                    1,
                    tabs: [
                        tab(
                            1,
                            selected: true,
                            eligibility: .ineligible(.policyRestricted)
                        ),
                        tab(2)
                    ],
                    key: true
                ),
                window(2, tabs: [tab(3, selected: true)])
            ]
        )
        XCTAssertEqual(
            try State.resolve(.moveToNewWindow, in: ineligibleSelectedTab).availability,
            .disabled(.tabTabbingIneligible(tabID(1), .policyRestricted))
        )
        XCTAssertEqual(
            try State.resolve(.mergeAllWindows, in: ineligibleSelectedTab).availability,
            .disabled(.tabTabbingIneligible(tabID(1), .policyRestricted))
        )

        let ineligibleSiblingTab = try snapshot(
            windows: [
                window(
                    1,
                    tabs: [
                        tab(1, selected: true),
                        tab(2, eligibility: .ineligible(.policyRestricted))
                    ],
                    key: true
                ),
                window(2, tabs: [tab(3, selected: true)])
            ]
        )
        XCTAssertEqual(
            try movePlan(State.resolve(.moveToNewWindow, in: ineligibleSiblingTab)).tabID,
            tabID(1)
        )
        XCTAssertEqual(
            try State.resolve(.mergeAllWindows, in: ineligibleSiblingTab).availability,
            .disabled(.tabTabbingIneligible(tabID(2), .policyRestricted))
        )

        let ineligibleSourceTab = try snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true)], key: true),
                window(
                    2,
                    tabs: [
                        tab(
                            2,
                            selected: true,
                            eligibility: .ineligible(.unsupportedContent)
                        )
                    ]
                )
            ]
        )
        XCTAssertEqual(
            try State.resolve(.mergeAllWindows, in: ineligibleSourceTab).availability,
            .disabled(.tabTabbingIneligible(tabID(2), .unsupportedContent))
        )

        let tabLimited = try snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true)], key: true),
                window(2, tabs: [tab(2, selected: true), tab(3)])
            ],
            limits: State.Limits(maximumTabsPerWindow: 2)
        )
        XCTAssertEqual(
            try State.resolve(.mergeAllWindows, in: tabLimited).availability,
            .disabled(.tabLimitReached(windowID: windowID(1), maximum: 2))
        )
    }

    func testClosePlansPreserveReverseOrderAndFullAdvisoryMetadata() throws {
        let orderingSnapshot = try snapshot(
            windows: [
                window(
                    1,
                    tabs: [tab(1), tab(2), tab(3, selected: true), tab(4), tab(5)],
                    key: true
                )
            ]
        )

        let cases: [(Command, [UInt64])] = [
            (.closeAll, [5, 4, 3, 2, 1]),
            (.closeOthers, [5, 4, 2, 1]),
            (.closeLeft, [2, 1]),
            (.closeRight, [5, 4])
        ]
        for (command, expectedIDs) in cases {
            let resolution = try State.resolve(command, in: orderingSnapshot)
            let plan = try closePlan(resolution)
            XCTAssertEqual(plan.targets.map(\.tabID), expectedIDs.map(tabID), "Command \(command)")
            XCTAssertEqual(plan.targets.count, expectedIDs.count, "Command \(command)")
            XCTAssertTrue(resolution.canExecute, "Command \(command)")
        }

        let snapshot = try richSnapshot()
        let closeAll = try closePlan(State.resolve(.closeAll, in: snapshot))
        XCTAssertEqual(closeAll.targets.filter(\.requiresConfirmation).map(\.tabID), [tabID(5), tabID(2)])
        XCTAssertEqual(closeAll.targets.filter(\.isCloseVetoed).map(\.tabID), [tabID(4), tabID(2)])
        XCTAssertEqual(closeAll.targets.filter { !$0.isFullyRestorable }.map(\.tabID), [tabID(5), tabID(4), tabID(3)])
        XCTAssertEqual(
            closeAll.targets.map(\.tabID),
            [tabID(6), tabID(5), tabID(4), tabID(3), tabID(2), tabID(1)]
        )
    }

    func testMoveToNewWindowDelegatesIdentityAllocationToOwningRegistry() throws {
        let sourceID = State.WindowID(rawValue: .max)
        let snapshot = try State.Snapshot(
            lineage: lineage(8),
            generation: 9,
            windows: [
                State.WindowState(
                    id: sourceID,
                    tabs: [tab(1), tab(2, selected: true)],
                    isKey: true
                )
            ]
        )

        let plan = try movePlan(State.resolve(.moveToNewWindow, in: snapshot))
        XCTAssertEqual(plan.sourceWindowID, sourceID)
        XCTAssertEqual(plan.destinationWindowIDAllocation, .owningRegistry)
        XCTAssertEqual(plan.tabID, tabID(2))
        XCTAssertEqual(plan.replacementSourceTabID, tabID(1))
    }

    func testMoveToNewWindowMetadataCombinesWindowAndSelectedTabRestorability() throws {
        let cases: [(Bool, Bool, Bool, Bool)] = [
            (true, true, false, true),
            (false, true, true, false),
            (true, false, false, false)
        ]

        for (windowRestorable, tabRestorable, dirty, expectedRestorable) in cases {
            let snapshot = try self.snapshot(
                windows: [
                    window(
                        1,
                        tabs: [
                            tab(
                                1,
                                selected: true,
                                dirty: dirty,
                                restorable: tabRestorable
                            ),
                            tab(2)
                        ],
                        key: true,
                        restorable: windowRestorable
                    )
                ]
            )
            let resolution = try State.resolve(.moveToNewWindow, in: snapshot)
            let plan = try movePlan(resolution)
            XCTAssertEqual(plan.isDirty, dirty)
            XCTAssertEqual(plan.isRestorable, expectedRestorable)
            XCTAssertEqual(plan.sourceWindowID, windowID(1))
            XCTAssertEqual(plan.tabID, tabID(1))
            XCTAssertEqual(plan.replacementSourceTabID, tabID(2))
            XCTAssertEqual(resolution.enabledReason, .moveToNewWindow(tabID: tabID(1)))
            XCTAssertEqual(resolution.platformOutcome, .native)
        }
    }

    func testTabAndWindowNavigationWrapAtBothCycleBoundaries() throws {
        let lastTabAndWindow = try snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true)]),
                window(2, tabs: [tab(2), tab(3, selected: true)], key: true)
            ]
        )
        XCTAssertEqual(
            try tabNavigationPlan(State.resolve(.nextTab, in: lastTabAndWindow)),
            State.TabNavigationPlan(
                windowID: windowID(2),
                sourceTabID: tabID(3),
                targetTabID: tabID(2)
            )
        )
        XCTAssertEqual(
            try windowNavigationPlan(State.resolve(.nextWindow, in: lastTabAndWindow)),
            State.WindowNavigationPlan(
                sourceWindowID: windowID(2),
                targetWindowID: windowID(1),
                targetTabID: tabID(1),
                restoresMinimizedWindow: false
            )
        )

        let firstTab = try snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                window(2, tabs: [tab(3, selected: true)])
            ]
        )
        XCTAssertEqual(
            try tabNavigationPlan(State.resolve(.previousTab, in: firstTab)),
            State.TabNavigationPlan(
                windowID: windowID(1),
                sourceTabID: tabID(1),
                targetTabID: tabID(2)
            )
        )
    }

    func testMinimizedWindowsAreExplicitlyRestoredForNavigationMergeAndTile() throws {
        let snapshot = try self.snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true)], minimized: true),
                window(2, tabs: [tab(2, selected: true)], key: true),
                window(3, tabs: [tab(3, selected: true)], minimized: true)
            ]
        )

        XCTAssertEqual(
            try windowNavigationPlan(State.resolve(.nextWindow, in: snapshot)),
            State.WindowNavigationPlan(
                sourceWindowID: windowID(2),
                targetWindowID: windowID(3),
                targetTabID: tabID(3),
                restoresMinimizedWindow: true
            )
        )
        XCTAssertEqual(
            try windowNavigationPlan(State.resolve(.previousWindow, in: snapshot)),
            State.WindowNavigationPlan(
                sourceWindowID: windowID(2),
                targetWindowID: windowID(1),
                targetTabID: tabID(1),
                restoresMinimizedWindow: true
            )
        )

        let merge = try mergePlan(State.resolve(.mergeAllWindows, in: snapshot))
        XCTAssertEqual(merge.destinationWindowID, windowID(2))
        XCTAssertEqual(merge.destinationSelectedTabID, tabID(2))
        XCTAssertEqual(
            merge.sources,
            [
                State.WindowTabMove(sourceWindowID: windowID(1), tabIDs: [tabID(1)]),
                State.WindowTabMove(sourceWindowID: windowID(3), tabIDs: [tabID(3)])
            ]
        )
        XCTAssertEqual(merge.restoreMinimizedWindowIDs, [windowID(1), windowID(3)])
        XCTAssertEqual(merge.resultingTabOrder, [tabID(2), tabID(1), tabID(3)])
        XCTAssertEqual(merge.nonRestorableTabIDs, [])
        XCTAssertEqual(
            try arrangementPlan(State.resolve(.tile, in: snapshot)).restoreMinimizedWindowIDs,
            [windowID(1), windowID(3)]
        )
    }

    func testFullScreenWindowsAreNeverSilentlyRestoredForMoveMergeOrTile() throws {
        let fullScreenSource = try snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true)], key: true),
                window(2, tabs: [tab(2, selected: true)], fullScreen: true)
            ]
        )
        let navigation = try windowNavigationPlan(
            State.resolve(.nextWindow, in: fullScreenSource)
        )
        XCTAssertEqual(navigation.targetWindowID, windowID(2))
        XCTAssertFalse(navigation.restoresMinimizedWindow)
        XCTAssertEqual(
            try State.resolve(.mergeAllWindows, in: fullScreenSource).availability,
            .disabled(.fullScreenWindow(windowID(2)))
        )
        XCTAssertEqual(
            try State.resolve(.tile, in: fullScreenSource).availability,
            .disabled(.fullScreenWindow(windowID(2)))
        )
        XCTAssertEqual(try State.resolve(.tile, in: fullScreenSource).targetPlan, .none)

        let fullScreenKey = try snapshot(
            windows: [
                window(
                    1,
                    tabs: [tab(1, selected: true), tab(2)],
                    key: true,
                    fullScreen: true
                ),
                window(2, tabs: [tab(3, selected: true)])
            ]
        )
        XCTAssertEqual(
            try State.resolve(.moveToNewWindow, in: fullScreenKey).availability,
            .disabled(.fullScreenWindow(windowID(1)))
        )
        XCTAssertEqual(
            try State.resolve(.mergeAllWindows, in: fullScreenKey).availability,
            .disabled(.fullScreenWindow(windowID(1)))
        )
    }

    func testPerCommandWorkBudgetAcceptsExactBoundaryAndRejectsNextUnit() throws {
        let windows = [
            window(
                1,
                tabs: [tab(1), tab(2, selected: true), tab(3)],
                key: true
            )
        ]
        let exact = try snapshot(
            windows: windows,
            limits: State.Limits(maximumWorkUnits: 7, maximumAggregateWorkUnits: 1_000)
        )
        let closeAll = try State.resolve(.closeAll, in: exact)
        XCTAssertEqual(closeAll.plannedWorkUnits, 7)
        XCTAssertEqual(try closePlan(closeAll).targets.count, 3)

        let oneShort = try snapshot(
            windows: windows,
            limits: State.Limits(maximumWorkUnits: 6, maximumAggregateWorkUnits: 1_000)
        )
        assertStateError(.workLimitExceeded(maximum: 6)) {
            _ = try State.resolve(.closeAll, in: oneShort)
        }
        assertStateError(.workLimitExceeded(maximum: 6)) {
            _ = try State.resolveAll(in: oneShort)
        }

        let laterCommandTooLarge = try snapshot(
            windows: windows,
            limits: State.Limits(maximumWorkUnits: 7, maximumAggregateWorkUnits: 1_000)
        )
        XCTAssertEqual(
            try State.resolve(.closeAll, in: laterCommandTooLarge).plannedWorkUnits,
            7
        )
        assertStateError(.workLimitExceeded(maximum: 7)) {
            _ = try State.resolveAll(in: laterCommandTooLarge)
        }

        let resetBetweenCommands = try snapshot(
            windows: windows,
            limits: State.Limits(maximumWorkUnits: 8, maximumAggregateWorkUnits: 36)
        )
        XCTAssertEqual(
            try State.resolveAll(in: resetBetweenCommands).map(\.plannedWorkUnits),
            [7, 8, 5, 5, 3, 3, 0, 0, 3, 1, 0, 1]
        )
    }

    func testAggregateWorkBudgetAcceptsExactSumAndRejectsNextUnit() throws {
        let windows = [
            window(
                1,
                tabs: [tab(1), tab(2, selected: true), tab(3)],
                key: true
            )
        ]
        let expectedWork = 36
        let expectedPerCommandWork = [7, 8, 5, 5, 3, 3, 0, 0, 3, 1, 0, 1]

        let exact = try snapshot(
            windows: windows,
            limits: State.Limits(
                maximumWorkUnits: 100,
                maximumAggregateWorkUnits: expectedWork
            )
        )
        let exactResolutions = try State.resolveAll(in: exact)
        XCTAssertEqual(exactResolutions.map(\.plannedWorkUnits), expectedPerCommandWork)
        XCTAssertEqual(exactResolutions.reduce(0) { $0 + $1.plannedWorkUnits }, 36)

        let oneShort = try snapshot(
            windows: windows,
            limits: State.Limits(
                maximumWorkUnits: 100,
                maximumAggregateWorkUnits: expectedWork - 1
            )
        )
        assertStateError(.workLimitExceeded(maximum: expectedWork - 1)) {
            _ = try State.resolveAll(in: oneShort)
        }
    }

    func testDefaultBudgetsCover256WindowsAnd4096TabsWith153600AggregateCap() throws {
        let limits = State.Limits.default
        XCTAssertEqual(limits.maximumWindowCount, 256)
        XCTAssertEqual(limits.maximumTabsPerWindow, 256)
        XCTAssertEqual(limits.maximumTotalTabCount, 4_096)
        XCTAssertEqual(limits.maximumWorkUnits, 32_768)
        XCTAssertEqual(limits.maximumAggregateWorkUnits, 153_600)
        XCTAssertEqual(limits.cancellationCheckInterval, 64)
        XCTAssertEqual(
            State.Limits.derivedMaximumAggregateWorkUnits(
                maximumWindowCount: 256,
                maximumTotalTabCount: 4_096,
                maximumWorkUnits: 32_768
            ),
            153_600
        )
        XCTAssertEqual(
            State.Limits.derivedMaximumAggregateWorkUnits(
                maximumWindowCount: .max,
                maximumTotalTabCount: .max,
                maximumWorkUnits: .max
            ),
            .max
        )
        XCTAssertEqual(
            State.Limits.derivedMaximumAggregateWorkUnits(
                maximumWindowCount: 256,
                maximumTotalTabCount: 4_096,
                maximumWorkUnits: 5
            ),
            60
        )

        var windows: [State.WindowState] = []
        windows.reserveCapacity(256)
        for windowIndex in 0..<256 {
            let tabs: [State.TabState] = (0..<16).map { tabIndex in
                tab(
                    UInt64(windowIndex * 16 + tabIndex + 1),
                    selected: tabIndex == 0
                )
            }
            windows.append(
                window(
                    UInt64(windowIndex + 1),
                    tabs: tabs,
                    key: windowIndex == 0
                ))
        }
        let snapshot = try self.snapshot(windows: windows)
        XCTAssertEqual(snapshot.windows.count, 256)
        XCTAssertEqual(snapshot.totalTabCount, 4_096)

        let resolutions = try State.resolveAll(in: snapshot)
        XCTAssertEqual(resolutions.count, 12)
        XCTAssertLessThanOrEqual(
            resolutions.reduce(0) { $0 + $1.plannedWorkUnits },
            limits.maximumAggregateWorkUnits
        )
        let closeAllResolution = try XCTUnwrap(
            resolutions.first { $0.command == Command.closeAll }
        )
        let closeAll = try closePlan(closeAllResolution)
        XCTAssertEqual(closeAll.targets.count, 4_096)
        XCTAssertEqual(closeAll.targets.first?.windowID, windowID(256))
        XCTAssertEqual(closeAll.targets.first?.tabID, tabID(4_096))
        XCTAssertEqual(closeAll.targets.last?.windowID, windowID(1))
        XCTAssertEqual(closeAll.targets.last?.tabID, tabID(1))
    }

    func testPreCancelledSnapshotConstructionWinsBeforeInvalidLimitsAndShape() async {
        let error = await Task { () -> State.StateError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try State.Snapshot(
                    lineage: State.SnapshotLineage(rawValue: 1),
                    generation: 1,
                    windows: [
                        State.WindowState(
                            id: State.WindowID(rawValue: 1),
                            tabs: [],
                            isKey: true,
                            isMinimized: true,
                            isFullScreen: true
                        )
                    ],
                    limits: State.Limits(
                        maximumWindowCount: 0,
                        maximumTabsPerWindow: 0,
                        maximumTotalTabCount: 0,
                        maximumWorkUnits: 0,
                        maximumAggregateWorkUnits: 0,
                        cancellationCheckInterval: 0
                    )
                )
                return nil
            } catch {
                return error as? State.StateError
            }
        }.value

        XCTAssertEqual(error, .cancelled)
    }

    func testEveryPublicPlanningAndValidationAPIGuardsPreCancellation() async throws {
        let snapshot = try self.snapshot(
            windows: [
                window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                window(2, tabs: [tab(3, selected: true)])
            ]
        )
        let resolution = try State.resolve(.nextTab, in: snapshot)
        let operations: [@Sendable () throws -> Void] = [
            { _ = try State.resolve(.closeAll, in: snapshot) },
            { _ = try State.resolveAll(in: snapshot) },
            { _ = try State.canExecute(.closeAll, in: snapshot) },
            { _ = try resolution.plan.isCurrent(snapshot: snapshot) },
            { try resolution.plan.validate(against: snapshot) },
            { try resolution.validate(against: snapshot) },
            { try State.validate(resolution.plan, against: snapshot) },
            { try State.validate(resolution, against: snapshot) }
        ]

        for (index, operation) in operations.enumerated() {
            let error = await Task { () -> State.StateError? in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    try operation()
                    return nil
                } catch {
                    return error as? State.StateError
                }
            }.value
            XCTAssertEqual(error, .cancelled, "Operation \(index)")
        }
    }

    func testEnabledPlanValidationRequiresExactCurrentSnapshotFingerprint() throws {
        let original = try snapshot(
            lineage: 50,
            generation: 60,
            windows: [
                window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                window(2, tabs: [tab(3, selected: true)])
            ]
        )
        let resolution = try State.resolve(.nextTab, in: original)
        XCTAssertTrue(try resolution.plan.isCurrent(snapshot: original))
        XCTAssertNoThrow(try resolution.plan.validate(against: original))
        XCTAssertNoThrow(try resolution.validate(against: original))
        XCTAssertNoThrow(try State.validate(resolution.plan, against: original))
        XCTAssertNoThrow(try State.validate(resolution, against: original))

        let changed = try snapshot(
            lineage: 50,
            generation: 60,
            windows: [
                window(
                    1,
                    tabs: [tab(1, selected: true, dirty: true), tab(2)],
                    key: true
                ),
                window(2, tabs: [tab(3, selected: true)])
            ]
        )
        XCTAssertFalse(try resolution.plan.isCurrent(snapshot: changed))
        let expected = State.StateError.staleSnapshot(
            expected: original.fingerprint,
            actual: changed.fingerprint
        )
        assertStateError(expected) {
            try resolution.plan.validate(against: changed)
        }
        assertStateError(expected) {
            try resolution.validate(against: changed)
        }
        assertStateError(expected) {
            try State.validate(resolution.plan, against: changed)
        }
        assertStateError(expected) {
            try State.validate(resolution, against: changed)
        }

        let reusedGeneration = try snapshot(
            lineage: 51,
            generation: 60,
            windows: original.windows
        )
        XCTAssertFalse(try resolution.plan.isCurrent(snapshot: reusedGeneration))
        let nextGeneration = try snapshot(
            lineage: 50,
            generation: 61,
            windows: original.windows
        )
        XCTAssertFalse(try resolution.plan.isCurrent(snapshot: nextGeneration))

        let fieldAndLimitVariants = try [
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true), tab(2)]),
                    window(2, tabs: [tab(3, selected: true)], key: true)
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                    window(4, tabs: [tab(3, selected: true)])
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                    window(2, tabs: [tab(3, selected: true)], minimized: true)
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                    window(2, tabs: [tab(3, selected: true)], fullScreen: true)
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                    window(2, tabs: [tab(3, selected: true)], restorable: false)
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                    window(
                        2,
                        tabs: [tab(3, selected: true)],
                        eligibility: .ineligible(.transientWindow)
                    )
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1), tab(2, selected: true)], key: true),
                    window(2, tabs: [tab(3, selected: true)])
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(
                        1,
                        tabs: [tab(1, selected: true), tab(2), tab(4)],
                        key: true
                    ),
                    window(2, tabs: [tab(3, selected: true)])
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true), tab(2)], key: true),
                    window(2, tabs: [tab(3, selected: true)]),
                    window(3, tabs: [tab(4, selected: true)])
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(4, selected: true), tab(2)], key: true),
                    window(2, tabs: [tab(3, selected: true)])
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true, vetoed: true), tab(2)], key: true),
                    window(2, tabs: [tab(3, selected: true)])
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(1, tabs: [tab(1, selected: true, restorable: false), tab(2)], key: true),
                    window(2, tabs: [tab(3, selected: true)])
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(
                        1,
                        tabs: [
                            tab(
                                1,
                                selected: true,
                                eligibility: .ineligible(.unsupportedContent)
                            ),
                            tab(2)
                        ],
                        key: true
                    ),
                    window(2, tabs: [tab(3, selected: true)])
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: [
                    window(2, tabs: [tab(3, selected: true)]),
                    window(1, tabs: [tab(1, selected: true), tab(2)], key: true)
                ]
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: original.windows,
                limits: State.Limits(maximumWindowCount: 255)
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: original.windows,
                limits: State.Limits(maximumTabsPerWindow: 255)
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: original.windows,
                limits: State.Limits(maximumTotalTabCount: 4_095)
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: original.windows,
                limits: State.Limits(maximumWorkUnits: 32_767)
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: original.windows,
                limits: State.Limits(maximumAggregateWorkUnits: 153_599)
            ),
            snapshot(
                lineage: 50,
                generation: 60,
                windows: original.windows,
                limits: State.Limits(cancellationCheckInterval: 63)
            )
        ]
        for (index, variant) in fieldAndLimitVariants.enumerated() {
            XCTAssertFalse(
                try resolution.plan.isCurrent(snapshot: variant),
                "Variant \(index)"
            )
            assertStateError(
                .staleSnapshot(expected: original.fingerprint, actual: variant.fingerprint)
            ) {
                try resolution.validate(against: variant)
            }
        }
    }

    func testDisabledPlanChecksStalenessBeforeCommandDisabledReason() throws {
        let original = try snapshot(
            lineage: 70,
            generation: 80,
            windows: [window(1, tabs: [tab(1, selected: true)], key: true)]
        )
        let split = try State.resolve(.split, in: original)
        assertStateError(.commandDisabled(.unsupportedCommand(.split))) {
            try split.validate(against: original)
        }

        let stale = try snapshot(
            lineage: 70,
            generation: 81,
            windows: original.windows
        )
        assertStateError(
            .staleSnapshot(expected: original.fingerprint, actual: stale.fingerprint)
        ) {
            try split.validate(against: stale)
        }
    }

    private func richSnapshot() throws -> State.Snapshot {
        try snapshot(
            lineage: 41,
            generation: 7,
            windows: [
                window(
                    1,
                    tabs: [
                        tab(1),
                        tab(2, selected: true, dirty: true, vetoed: true),
                        tab(3, restorable: false)
                    ],
                    key: true
                ),
                window(
                    2,
                    tabs: [
                        tab(4, selected: true, vetoed: true),
                        tab(5, dirty: true)
                    ],
                    minimized: true,
                    restorable: false
                ),
                window(3, tabs: [tab(6, selected: true)])
            ]
        )
    }

    private func snapshot(
        lineage: UInt64 = 1,
        generation: UInt64 = 1,
        windows: [State.WindowState],
        limits: State.Limits = .default
    ) throws -> State.Snapshot {
        try State.Snapshot(
            lineage: self.lineage(lineage),
            generation: generation,
            windows: windows,
            limits: limits
        )
    }

    private func window(
        _ id: UInt64,
        tabs: [State.TabState],
        key: Bool = false,
        minimized: Bool = false,
        fullScreen: Bool = false,
        restorable: Bool = true,
        eligibility: State.TabbingEligibility = .eligible
    ) -> State.WindowState {
        State.WindowState(
            id: windowID(id),
            tabs: tabs,
            isKey: key,
            isMinimized: minimized,
            isFullScreen: fullScreen,
            isRestorable: restorable,
            tabbingEligibility: eligibility
        )
    }

    private func tab(
        _ id: UInt64,
        selected: Bool = false,
        dirty: Bool = false,
        vetoed: Bool = false,
        restorable: Bool = true,
        eligibility: State.TabbingEligibility = .eligible
    ) -> State.TabState {
        State.TabState(
            id: tabID(id),
            isSelected: selected,
            isDirty: dirty,
            isCloseVetoed: vetoed,
            isRestorable: restorable,
            tabbingEligibility: eligibility
        )
    }

    private func closeTarget(
        window: UInt64,
        tab: UInt64,
        dirty: Bool = false,
        vetoed: Bool = false,
        windowRestorable: Bool = true,
        tabRestorable: Bool = true
    ) -> State.CloseTarget {
        State.CloseTarget(
            windowID: windowID(window),
            tabID: tabID(tab),
            isDirty: dirty,
            isCloseVetoed: vetoed,
            isWindowRestorable: windowRestorable,
            isTabRestorable: tabRestorable
        )
    }

    private func lineage(_ value: UInt64) -> State.SnapshotLineage {
        State.SnapshotLineage(rawValue: value)
    }

    private func windowID(_ value: UInt64) -> State.WindowID {
        State.WindowID(rawValue: value)
    }

    private func tabID(_ value: UInt64) -> State.TabID {
        State.TabID(rawValue: value)
    }

    private func closePlan(_ resolution: State.Resolution) throws -> State.ClosePlan {
        guard case .close(let plan) = resolution.targetPlan else {
            XCTFail("Expected close plan for \(resolution.command)")
            throw UnexpectedTargetPlan()
        }
        return plan
    }

    private func tabNavigationPlan(
        _ resolution: State.Resolution
    ) throws -> State.TabNavigationPlan {
        guard case .navigateTab(let plan) = resolution.targetPlan else {
            XCTFail("Expected tab navigation plan for \(resolution.command)")
            throw UnexpectedTargetPlan()
        }
        return plan
    }

    private func windowNavigationPlan(
        _ resolution: State.Resolution
    ) throws -> State.WindowNavigationPlan {
        guard case .navigateWindow(let plan) = resolution.targetPlan else {
            XCTFail("Expected window navigation plan for \(resolution.command)")
            throw UnexpectedTargetPlan()
        }
        return plan
    }

    private func movePlan(_ resolution: State.Resolution) throws -> State.MoveToNewWindowPlan {
        guard case .moveToNewWindow(let plan) = resolution.targetPlan else {
            XCTFail("Expected move plan for \(resolution.command)")
            throw UnexpectedTargetPlan()
        }
        return plan
    }

    private func mergePlan(_ resolution: State.Resolution) throws -> State.MergeAllWindowsPlan {
        guard case .mergeAllWindows(let plan) = resolution.targetPlan else {
            XCTFail("Expected merge plan for \(resolution.command)")
            throw UnexpectedTargetPlan()
        }
        return plan
    }

    private func arrangementPlan(
        _ resolution: State.Resolution
    ) throws -> State.NativeWindowArrangementPlan {
        guard case .nativeWindowArrangement(let plan) = resolution.targetPlan else {
            XCTFail("Expected native arrangement plan for \(resolution.command)")
            throw UnexpectedTargetPlan()
        }
        return plan
    }

    private func assertStateError(
        _ expected: State.StateError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? State.StateError, expected, file: file, line: line)
        }
    }

    private struct UnexpectedTargetPlan: Error {}
}
