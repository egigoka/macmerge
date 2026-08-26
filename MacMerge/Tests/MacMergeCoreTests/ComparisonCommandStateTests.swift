import MacMergeCore
import XCTest

final class ComparisonCommandStateTests: XCTestCase {
    typealias State = ComparisonCommandState
    typealias Command = State.Identifier
    typealias Pane = State.PaneState
    typealias Preconditions = State.ExecutionPrecondition

    func testLifecycleMatrixIncludesStaleAndPreservesWorkspaceExceptions() {
        let cases:
            [(
                name: String,
                lifecycle: State.ComparisonLifecycle,
                workspace: State.Availability,
                currentComparison: State.Availability
            )] = [
                (
                    "loading",
                    .loading,
                    .disabled(.comparisonLoading),
                    .disabled(.comparisonLoading)
                ),
                (
                    "refreshing",
                    .refreshing,
                    .disabled(.comparisonRefreshing),
                    .disabled(.comparisonRefreshing)
                ),
                ("stale", .stale, .enabled, .disabled(.comparisonStale)),
                ("failed", .failed, .enabled, .disabled(.comparisonFailed)),
                ("canceled", .canceled, .enabled, .disabled(.comparisonCanceled)),
                ("current", .currentSuccess, .enabled, .enabled)
            ]

        for testCase in cases {
            let context = makeContext(
                left: pane(isDirty: true),
                lifecycle: testCase.lifecycle,
                hasSelection: true,
                hasSignificantDifferences: true
            )

            assertResolution(
                .openComparison,
                in: context,
                availability: testCase.workspace,
                preconditions: [.sessionUnlocked, .comparisonNotLoading],
                state: testCase.name
            )
            assertResolution(
                .saveLeft,
                in: context,
                availability: testCase.workspace,
                preconditions: [
                    .sessionUnlocked,
                    .comparisonNotLoading,
                    .paneExists(.left),
                    .paneLoaded(.left),
                    .paneEditable(.left),
                    .paneDirty(.left),
                    .paneUnchangedExternally(.left)
                ],
                state: testCase.name
            )
            assertResolution(
                .copyToRight,
                in: context,
                availability: testCase.currentComparison,
                title: .copy(to: .right),
                copyRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .left,
                    destinationPosition: .right
                ),
                preconditions: [
                    .sessionUnlocked,
                    .currentComparison,
                    .paneLoaded(.left),
                    .paneLoaded(.right),
                    .paneEditable(.right),
                    .hasSignificantDifferences,
                    .hasSelection
                ],
                state: testCase.name
            )
        }
    }

    func testAllPerSideSaveAndSaveAsContractsAreLiteral() {
        let context = makeContext(
            left: pane(isDirty: true, isUntitled: true),
            right: pane(isDirty: true, isUntitled: true),
            layout: threePane(middle: pane(isDirty: true, isUntitled: true))
        )

        assertResolution(
            .saveLeft,
            in: context,
            availability: .enabled,
            title: .saveAs(.left),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.left),
                .paneLoaded(.left),
                .paneEditable(.left),
                .paneDirty(.left),
                .paneUnchangedExternally(.left)
            ]
        )
        assertResolution(
            .saveMiddle,
            in: context,
            availability: .enabled,
            title: .saveAs(.middle),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.middle),
                .paneLoaded(.middle),
                .paneEditable(.middle),
                .paneDirty(.middle),
                .paneUnchangedExternally(.middle)
            ]
        )
        assertResolution(
            .saveRight,
            in: context,
            availability: .enabled,
            title: .saveAs(.right),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.right),
                .paneLoaded(.right),
                .paneEditable(.right),
                .paneDirty(.right),
                .paneUnchangedExternally(.right)
            ]
        )
        assertResolution(
            .saveLeftAs,
            in: context,
            availability: .enabled,
            title: .saveAs(.left),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.left),
                .paneLoaded(.left)
            ]
        )
        assertResolution(
            .saveMiddleAs,
            in: context,
            availability: .enabled,
            title: .saveAs(.middle),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.middle),
                .paneLoaded(.middle)
            ]
        )
        assertResolution(
            .saveRightAs,
            in: context,
            availability: .enabled,
            title: .saveAs(.right),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.right),
                .paneLoaded(.right)
            ]
        )
    }

    func testPerSideSaveFailuresAndSaveAsExceptionsApplyToEverySide() {
        let cases:
            [(
                side: State.Side,
                save: Command,
                saveAs: Command,
                clean: State.Context,
                readOnlyDirty: State.Context,
                externallyChanged: State.Context,
                unloaded: State.Context,
                savePreconditions: [Preconditions],
                saveAsPreconditions: [Preconditions]
            )] = [
                (
                    .left,
                    .saveLeft,
                    .saveLeftAs,
                    makeContext(),
                    makeContext(left: pane(isEditable: false, isDirty: true)),
                    makeContext(left: pane(isDirty: true, hasExternalChange: true)),
                    makeContext(left: unloadedPane()),
                    [
                        .sessionUnlocked,
                        .comparisonNotLoading,
                        .paneExists(.left),
                        .paneLoaded(.left),
                        .paneEditable(.left),
                        .paneDirty(.left),
                        .paneUnchangedExternally(.left)
                    ],
                    [
                        .sessionUnlocked,
                        .comparisonNotLoading,
                        .paneExists(.left),
                        .paneLoaded(.left)
                    ]
                ),
                (
                    .middle,
                    .saveMiddle,
                    .saveMiddleAs,
                    makeContext(layout: threePane()),
                    makeContext(
                        layout: threePane(middle: pane(isEditable: false, isDirty: true))
                    ),
                    makeContext(
                        layout: threePane(
                            middle: pane(isDirty: true, hasExternalChange: true)
                        )
                    ),
                    makeContext(layout: threePane(middle: unloadedPane())),
                    [
                        .sessionUnlocked,
                        .comparisonNotLoading,
                        .paneExists(.middle),
                        .paneLoaded(.middle),
                        .paneEditable(.middle),
                        .paneDirty(.middle),
                        .paneUnchangedExternally(.middle)
                    ],
                    [
                        .sessionUnlocked,
                        .comparisonNotLoading,
                        .paneExists(.middle),
                        .paneLoaded(.middle)
                    ]
                ),
                (
                    .right,
                    .saveRight,
                    .saveRightAs,
                    makeContext(),
                    makeContext(right: pane(isEditable: false, isDirty: true)),
                    makeContext(right: pane(isDirty: true, hasExternalChange: true)),
                    makeContext(right: unloadedPane()),
                    [
                        .sessionUnlocked,
                        .comparisonNotLoading,
                        .paneExists(.right),
                        .paneLoaded(.right),
                        .paneEditable(.right),
                        .paneDirty(.right),
                        .paneUnchangedExternally(.right)
                    ],
                    [
                        .sessionUnlocked,
                        .comparisonNotLoading,
                        .paneExists(.right),
                        .paneLoaded(.right)
                    ]
                )
            ]

        for testCase in cases {
            assertResolution(
                testCase.save,
                in: testCase.clean,
                availability: .disabled(.noUnsavedChangesOnSide(testCase.side)),
                preconditions: testCase.savePreconditions,
                state: "clean \(testCase.side)"
            )
            assertResolution(
                testCase.save,
                in: testCase.readOnlyDirty,
                availability: .disabled(.sideReadOnly(testCase.side)),
                preconditions: testCase.savePreconditions,
                state: "read-only \(testCase.side)"
            )
            assertResolution(
                testCase.save,
                in: testCase.externallyChanged,
                availability: .disabled(.externalChange(testCase.side)),
                preconditions: testCase.savePreconditions,
                state: "external change \(testCase.side)"
            )
            assertResolution(
                testCase.save,
                in: testCase.unloaded,
                availability: .disabled(.sideNotLoaded(testCase.side)),
                preconditions: testCase.savePreconditions,
                state: "unloaded \(testCase.side)"
            )
            assertResolution(
                testCase.saveAs,
                in: testCase.clean,
                availability: .enabled,
                title: .saveAs(testCase.side),
                preconditions: testCase.saveAsPreconditions,
                state: "clean Save As \(testCase.side)"
            )
            assertResolution(
                testCase.saveAs,
                in: testCase.readOnlyDirty,
                availability: .enabled,
                title: .saveAs(testCase.side),
                preconditions: testCase.saveAsPreconditions,
                state: "read-only Save As \(testCase.side)"
            )
            assertResolution(
                testCase.saveAs,
                in: testCase.externallyChanged,
                availability: .enabled,
                title: .saveAs(testCase.side),
                preconditions: testCase.saveAsPreconditions,
                state: "external-change Save As \(testCase.side)"
            )
            assertResolution(
                testCase.saveAs,
                in: testCase.unloaded,
                availability: .disabled(.sideNotLoaded(testCase.side)),
                title: .saveAs(testCase.side),
                preconditions: testCase.saveAsPreconditions,
                state: "unloaded Save As \(testCase.side)"
            )
        }

        let twoPane = makeContext()
        assertResolution(
            .saveMiddle,
            in: twoPane,
            availability: .disabled(.requiresThreePane),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.middle),
                .paneLoaded(.middle),
                .paneEditable(.middle),
                .paneDirty(.middle),
                .paneUnchangedExternally(.middle)
            ]
        )
        assertResolution(
            .saveMiddleAs,
            in: twoPane,
            availability: .disabled(.requiresThreePane),
            title: .saveAs(.middle),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.middle),
                .paneLoaded(.middle)
            ]
        )
    }

    func testEmptyAndOneSideLoadedSaveStatesAreExplicit() {
        let savePreconditions: [Preconditions] = [
            .sessionUnlocked,
            .comparisonNotLoading,
            .anyPaneLoaded,
            .anyDirtyPane,
            .dirtyPanesEditable,
            .dirtyPanesUnchangedExternally
        ]

        assertResolution(
            .save,
            in: makeContext(left: unloadedPane(), right: unloadedPane()),
            availability: .disabled(.noComparison),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(left: pane(), right: unloadedPane()),
            availability: .disabled(.noUnsavedChanges),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(left: pane(isDirty: true, isUntitled: true), right: unloadedPane()),
            availability: .enabled,
            title: .saveAs(.left),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(left: unloadedPane(), right: pane(isDirty: true, isUntitled: true)),
            availability: .enabled,
            title: .saveAs(.right),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(
                left: pane(isEditable: false, isDirty: true),
                right: pane(isDirty: true, hasExternalChange: true)
            ),
            availability: .disabled(.sideReadOnly(.left)),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(
                left: pane(isDirty: true, hasExternalChange: true),
                right: pane(isDirty: true, hasExternalChange: true)
            ),
            availability: .disabled(.externalChange(.left)),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(
                left: pane(isDirty: true, isUntitled: true),
                right: pane(isDirty: true)
            ),
            availability: .enabled,
            preconditions: savePreconditions
        )
    }

    func testGlobalSaveCoversMiddlePaneStatesInThreePaneLayout() {
        let savePreconditions: [Preconditions] = [
            .sessionUnlocked,
            .comparisonNotLoading,
            .anyPaneLoaded,
            .anyDirtyPane,
            .dirtyPanesEditable,
            .dirtyPanesUnchangedExternally
        ]

        assertResolution(
            .save,
            in: makeContext(
                layout: threePane(middle: pane(isDirty: true, isUntitled: true))
            ),
            availability: .enabled,
            title: .saveAs(.middle),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(
                layout: threePane(middle: pane(isEditable: false, isDirty: true))
            ),
            availability: .disabled(.sideReadOnly(.middle)),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(
                layout: threePane(
                    middle: pane(isDirty: true, hasExternalChange: true)
                )
            ),
            availability: .disabled(.externalChange(.middle)),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(
                layout: threePane(
                    middle: pane(isLoaded: false, isDirty: true)
                )
            ),
            availability: .disabled(.sideNotLoaded(.middle)),
            preconditions: savePreconditions
        )
        assertResolution(
            .save,
            in: makeContext(
                left: pane(isDirty: true),
                layout: threePane(middle: pane(isDirty: true, isUntitled: true))
            ),
            availability: .enabled,
            preconditions: savePreconditions
        )
    }

    func testOpenMiddleRequiresAndThenUsesThreePaneLayout() {
        let preconditions: [Preconditions] = [
            .sessionUnlocked,
            .comparisonNotLoading,
            .paneExists(.middle)
        ]

        assertResolution(
            .openMiddle,
            in: makeContext(),
            availability: .disabled(.requiresThreePane),
            preconditions: preconditions
        )
        assertResolution(
            .openMiddle,
            in: makeContext(layout: threePane(middle: unloadedPane())),
            availability: .enabled,
            preconditions: preconditions
        )
        assertResolution(
            .openMiddle,
            in: makeContext(layout: threePane(), lifecycle: .loading),
            availability: .disabled(.comparisonLoading),
            preconditions: preconditions
        )
    }

    func testLockedCommandMatrixHasOnlyMergeModeAndOptionsExceptions() {
        let locked = makeContext(
            left: pane(isDirty: true),
            right: pane(isDirty: true),
            layout: threePane(middle: pane(isDirty: true)),
            hasSelection: true,
            hasSignificantDifferences: true,
            canUndo: true,
            canRedo: true,
            differenceNavigation: State.DifferenceNavigation(
                canSelectLineDifference: true,
                canSelectPreviousLineDifference: true,
                canSelectNextDifference: true,
                canSelectPreviousDifference: true,
                canSelectFirstDifference: true,
                canSelectCurrentDifference: true,
                canSelectLastDifference: true
            ),
            conflictNavigation: State.ConflictNavigationState(
                isSupported: true,
                hasConflicts: true,
                canSelectFirstConflict: true,
                canSelectNextConflict: true,
                canSelectPreviousConflict: true,
                canSelectCurrentConflict: true,
                canSelectLastConflict: true
            ),
            comparedFileNavigation: State.ComparedFileNavigation(
                isSupported: true,
                canSelectFirst: true,
                canSelectPrevious: true,
                canSelectNext: true,
                canSelectLast: true
            ),
            canChangePane: true,
            canChangePaneBack: true,
            isSessionLocked: true
        )
        let commandOrder: [Command] = [
            .newComparison,
            .openComparison,
            .openLeft,
            .openMiddle,
            .openRight,
            .save,
            .saveLeft,
            .saveMiddle,
            .saveRight,
            .saveLeftAs,
            .saveMiddleAs,
            .saveRightAs,
            .undo,
            .redo,
            .selectLineDifference,
            .selectPreviousLineDifference,
            .nextDifference,
            .previousDifference,
            .nextConflict,
            .previousConflict,
            .firstConflict,
            .currentConflict,
            .lastConflict,
            .firstDifference,
            .currentDifference,
            .lastDifference,
            .copyToRight,
            .copyToLeft,
            .copyToRightAndAdvance,
            .copyToLeftAndAdvance,
            .copyAllToRight,
            .copyAllToLeft,
            .autoMerge,
            .firstComparedFile,
            .previousComparedFile,
            .nextComparedFile,
            .lastComparedFile,
            .leftReadOnly,
            .middleReadOnly,
            .rightReadOnly,
            .mergeMode,
            .reloadFromDisk,
            .changePane,
            .changePaneBack,
            .options,
            .refresh
        ]
        let lockedCommands: [Command] = [
            .newComparison,
            .openComparison,
            .openLeft,
            .openMiddle,
            .openRight,
            .save,
            .saveLeft,
            .saveMiddle,
            .saveRight,
            .saveLeftAs,
            .saveMiddleAs,
            .saveRightAs,
            .undo,
            .redo,
            .selectLineDifference,
            .selectPreviousLineDifference,
            .nextDifference,
            .previousDifference,
            .nextConflict,
            .previousConflict,
            .firstConflict,
            .currentConflict,
            .lastConflict,
            .firstDifference,
            .currentDifference,
            .lastDifference,
            .copyToRight,
            .copyToLeft,
            .copyToRightAndAdvance,
            .copyToLeftAndAdvance,
            .copyAllToRight,
            .copyAllToLeft,
            .autoMerge,
            .firstComparedFile,
            .previousComparedFile,
            .nextComparedFile,
            .lastComparedFile,
            .leftReadOnly,
            .middleReadOnly,
            .rightReadOnly,
            .reloadFromDisk,
            .changePane,
            .changePaneBack,
            .refresh
        ]

        XCTAssertEqual(Command.allCases, commandOrder)
        for command in lockedCommands {
            XCTAssertEqual(
                State.resolve(command, in: locked).availability,
                .disabled(.sessionLocked),
                "Command: \(command)"
            )
        }
        XCTAssertEqual(State.resolve(.mergeMode, in: locked).availability, .enabled)
        XCTAssertEqual(State.resolve(.options, in: locked).availability, .enabled)
    }

    func testAllTwoAndThreePaneVisualOrdersProduceLiteralCopyRoutes() throws {
        let cases: [CopyLayoutCase] = [
            CopyLayoutCase(
                order: [.left, .right],
                active: .left,
                leftRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .right,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .left,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.left, .right],
                active: .right,
                leftRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .right,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .left,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.right, .left],
                active: .right,
                leftRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .right,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .left,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.right, .left],
                active: .left,
                leftRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .right,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .left,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.left, .middle, .right],
                active: .left,
                leftRoute: route(
                    source: .middle,
                    destination: .left,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .left,
                    destination: .middle,
                    sourcePosition: .left,
                    destinationPosition: .middle
                )
            ),
            CopyLayoutCase(
                order: [.left, .middle, .right],
                active: .middle,
                leftRoute: route(
                    source: .middle,
                    destination: .left,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .middle,
                    destination: .right,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.left, .middle, .right],
                active: .right,
                leftRoute: route(
                    source: .right,
                    destination: .middle,
                    sourcePosition: .right,
                    destinationPosition: .middle
                ),
                rightRoute: route(
                    source: .middle,
                    destination: .right,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.left, .right, .middle],
                active: .left,
                leftRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .left,
                    destinationPosition: .middle
                )
            ),
            CopyLayoutCase(
                order: [.left, .right, .middle],
                active: .right,
                leftRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .right,
                    destination: .middle,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.left, .right, .middle],
                active: .middle,
                leftRoute: route(
                    source: .middle,
                    destination: .right,
                    sourcePosition: .right,
                    destinationPosition: .middle
                ),
                rightRoute: route(
                    source: .right,
                    destination: .middle,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.middle, .left, .right],
                active: .middle,
                leftRoute: route(
                    source: .left,
                    destination: .middle,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .middle,
                    destination: .left,
                    sourcePosition: .left,
                    destinationPosition: .middle
                )
            ),
            CopyLayoutCase(
                order: [.middle, .left, .right],
                active: .left,
                leftRoute: route(
                    source: .left,
                    destination: .middle,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.middle, .left, .right],
                active: .right,
                leftRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .right,
                    destinationPosition: .middle
                ),
                rightRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.middle, .right, .left],
                active: .middle,
                leftRoute: route(
                    source: .right,
                    destination: .middle,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .middle,
                    destination: .right,
                    sourcePosition: .left,
                    destinationPosition: .middle
                )
            ),
            CopyLayoutCase(
                order: [.middle, .right, .left],
                active: .right,
                leftRoute: route(
                    source: .right,
                    destination: .middle,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.middle, .right, .left],
                active: .left,
                leftRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .right,
                    destinationPosition: .middle
                ),
                rightRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.right, .left, .middle],
                active: .right,
                leftRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .right,
                    destination: .left,
                    sourcePosition: .left,
                    destinationPosition: .middle
                )
            ),
            CopyLayoutCase(
                order: [.right, .left, .middle],
                active: .left,
                leftRoute: route(
                    source: .left,
                    destination: .right,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .left,
                    destination: .middle,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.right, .left, .middle],
                active: .middle,
                leftRoute: route(
                    source: .middle,
                    destination: .left,
                    sourcePosition: .right,
                    destinationPosition: .middle
                ),
                rightRoute: route(
                    source: .left,
                    destination: .middle,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.right, .middle, .left],
                active: .right,
                leftRoute: route(
                    source: .middle,
                    destination: .right,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .right,
                    destination: .middle,
                    sourcePosition: .left,
                    destinationPosition: .middle
                )
            ),
            CopyLayoutCase(
                order: [.right, .middle, .left],
                active: .middle,
                leftRoute: route(
                    source: .middle,
                    destination: .right,
                    sourcePosition: .middle,
                    destinationPosition: .left
                ),
                rightRoute: route(
                    source: .middle,
                    destination: .left,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            ),
            CopyLayoutCase(
                order: [.right, .middle, .left],
                active: .left,
                leftRoute: route(
                    source: .left,
                    destination: .middle,
                    sourcePosition: .right,
                    destinationPosition: .middle
                ),
                rightRoute: route(
                    source: .middle,
                    destination: .left,
                    sourcePosition: .middle,
                    destinationPosition: .right
                )
            )
        ]

        for testCase in cases {
            let isThreePane = testCase.order.count == 3
            let context = makeContext(
                layout: isThreePane ? threePane() : .twoPane,
                layoutContext: try State.LayoutContext(
                    visualOrder: testCase.order,
                    activePane: testCase.active
                ),
                hasSelection: true,
                hasSignificantDifferences: true
            )

            assertCopyRoutes(
                in: context,
                leftRoute: testCase.leftRoute,
                rightRoute: testCase.rightRoute,
                state: "Order: \(testCase.order), active: \(testCase.active)"
            )
        }
    }

    func testInvalidAndMismatchedLayoutContextsFailOrNormalizeLiterally() throws {
        XCTAssertThrowsError(
            try State.LayoutContext(visualOrder: [.left], activePane: .left)
        ) { error in
            XCTAssertEqual(
                error as? State.LayoutContextError,
                .invalidVisualOrder([.left])
            )
        }
        XCTAssertThrowsError(
            try State.LayoutContext(visualOrder: [.left, .left], activePane: .left)
        ) { error in
            XCTAssertEqual(
                error as? State.LayoutContextError,
                .invalidVisualOrder([.left, .left])
            )
        }
        XCTAssertThrowsError(
            try State.LayoutContext(visualOrder: [.left, .right], activePane: .middle)
        ) { error in
            XCTAssertEqual(
                error as? State.LayoutContextError,
                .activePaneNotPresent(.middle)
            )
        }

        let threePaneContext = try State.LayoutContext(
            visualOrder: [.right, .middle, .left],
            activePane: .middle
        )
        let normalizedTwoPane = makeContext(
            layoutContext: threePaneContext,
            hasSelection: true,
            hasSignificantDifferences: true
        )
        XCTAssertEqual(normalizedTwoPane.layoutContext.visualOrder, [.left, .right])
        XCTAssertEqual(normalizedTwoPane.layoutContext.activePane, .left)
        assertResolution(
            .copyToRight,
            in: normalizedTwoPane,
            availability: .enabled,
            title: .copy(to: .right),
            copyRoute: route(
                source: .left,
                destination: .right,
                sourcePosition: .left,
                destinationPosition: .right
            ),
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .paneLoaded(.left),
                .paneLoaded(.right),
                .paneEditable(.right),
                .hasSignificantDifferences,
                .hasSelection
            ]
        )

        let twoPaneContext = try State.LayoutContext(
            visualOrder: [.right, .left],
            activePane: .right
        )
        let normalizedThreePane = makeContext(
            layout: threePane(),
            layoutContext: twoPaneContext,
            hasSelection: true,
            hasSignificantDifferences: true
        )
        XCTAssertEqual(
            normalizedThreePane.layoutContext.visualOrder,
            [.left, .middle, .right]
        )
        XCTAssertEqual(normalizedThreePane.layoutContext.activePane, .left)
        assertResolution(
            .copyToRight,
            in: normalizedThreePane,
            availability: .enabled,
            title: .copy(to: .middle),
            copyRoute: route(
                source: .left,
                destination: .middle,
                sourcePosition: .left,
                destinationPosition: .middle
            ),
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .paneLoaded(.left),
                .paneLoaded(.middle),
                .paneEditable(.middle),
                .hasSignificantDifferences,
                .hasSelection
            ]
        )
    }

    func testCopyFailurePrecedenceAndSelectionExceptionAreLocked() throws {
        let layoutContext = try State.LayoutContext(
            visualOrder: [.right, .middle, .left],
            activePane: .middle
        )
        let expectedRoute = route(
            source: .middle,
            destination: .left,
            sourcePosition: .middle,
            destinationPosition: .right
        )
        let directionalPreconditions: [Preconditions] = [
            .sessionUnlocked,
            .currentComparison,
            .paneLoaded(.middle),
            .paneLoaded(.left),
            .paneEditable(.left),
            .hasSignificantDifferences,
            .hasSelection
        ]
        let copyAllPreconditions: [Preconditions] = [
            .sessionUnlocked,
            .currentComparison,
            .paneLoaded(.middle),
            .paneLoaded(.left),
            .paneEditable(.left),
            .hasSignificantDifferences
        ]

        assertResolution(
            .copyToRight,
            in: makeContext(
                left: unloadedPane(),
                layout: threePane(middle: unloadedPane()),
                layoutContext: layoutContext
            ),
            availability: .disabled(.sideNotLoaded(.middle)),
            title: .copy(to: .right),
            copyRoute: expectedRoute,
            preconditions: directionalPreconditions
        )
        assertResolution(
            .copyToRight,
            in: makeContext(
                left: unloadedPane(),
                layout: threePane(),
                layoutContext: layoutContext
            ),
            availability: .disabled(.sideNotLoaded(.left)),
            title: .copy(to: .right),
            copyRoute: expectedRoute,
            preconditions: directionalPreconditions
        )
        assertResolution(
            .copyToRight,
            in: makeContext(
                left: pane(isEditable: false),
                layout: threePane(),
                layoutContext: layoutContext
            ),
            availability: .disabled(.destinationReadOnly(.left)),
            title: .copy(to: .right),
            copyRoute: expectedRoute,
            preconditions: directionalPreconditions
        )
        assertResolution(
            .copyToRight,
            in: makeContext(
                layout: threePane(),
                layoutContext: layoutContext,
                hasSelection: true
            ),
            availability: .disabled(.noSignificantDifferences),
            title: .copy(to: .right),
            copyRoute: expectedRoute,
            preconditions: directionalPreconditions
        )
        assertResolution(
            .copyToRight,
            in: makeContext(
                layout: threePane(),
                layoutContext: layoutContext,
                hasSignificantDifferences: true
            ),
            availability: .disabled(.noSelection),
            title: .copy(to: .right),
            copyRoute: expectedRoute,
            preconditions: directionalPreconditions
        )
        assertResolution(
            .copyAllToRight,
            in: makeContext(
                layout: threePane(),
                layoutContext: layoutContext,
                hasSignificantDifferences: true
            ),
            availability: .enabled,
            title: .copyAll(to: .right),
            copyRoute: expectedRoute,
            preconditions: copyAllPreconditions
        )
    }

    func testEveryDifferenceTargetResolvesIndependently() {
        let navigation = State.DifferenceNavigation(
            canSelectLineDifference: true,
            canSelectPreviousLineDifference: false,
            canSelectNextDifference: true,
            canSelectPreviousDifference: false,
            canSelectFirstDifference: true,
            canSelectCurrentDifference: false,
            canSelectLastDifference: true
        )
        let context = makeContext(
            hasSignificantDifferences: true,
            differenceNavigation: navigation
        )
        let cases:
            [(
                command: Command,
                availability: State.Availability,
                target: State.DifferenceTarget
            )] = [
                (.selectLineDifference, .enabled, .line),
                (
                    .selectPreviousLineDifference,
                    .disabled(.noPreviousLineDifference),
                    .previousLine
                ),
                (.nextDifference, .enabled, .next),
                (.previousDifference, .disabled(.noPreviousDifference), .previous),
                (.firstDifference, .enabled, .first),
                (.currentDifference, .disabled(.noCurrentDifference), .current),
                (.lastDifference, .enabled, .last)
            ]

        for testCase in cases {
            assertResolution(
                testCase.command,
                in: context,
                availability: testCase.availability,
                preconditions: [
                    .sessionUnlocked,
                    .currentComparison,
                    .allPanesLoaded,
                    .hasSignificantDifferences,
                    .differenceTarget(testCase.target)
                ]
            )
        }
    }

    func testEveryConflictTargetAndFailureLayerResolvesLiterally() {
        let navigation = State.ConflictNavigationState(
            isSupported: true,
            hasConflicts: true,
            canSelectFirstConflict: true,
            canSelectNextConflict: false,
            canSelectPreviousConflict: true,
            canSelectCurrentConflict: false,
            canSelectLastConflict: true
        )
        let context = makeContext(conflictNavigation: navigation)
        let cases:
            [(
                command: Command,
                availability: State.Availability,
                target: State.ConflictTarget
            )] = [
                (.firstConflict, .enabled, .first),
                (.previousConflict, .enabled, .previous),
                (.currentConflict, .disabled(.noCurrentConflict), .current),
                (.nextConflict, .disabled(.noNextConflict), .next),
                (.lastConflict, .enabled, .last)
            ]

        for testCase in cases {
            assertResolution(
                testCase.command,
                in: context,
                availability: testCase.availability,
                preconditions: [
                    .sessionUnlocked,
                    .currentComparison,
                    .allPanesLoaded,
                    .conflictNavigationSupported,
                    .hasConflicts,
                    .conflictTarget(testCase.target)
                ]
            )
        }

        assertResolution(
            .firstConflict,
            in: makeContext(),
            availability: .disabled(.unsupportedCommand(.firstConflict)),
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .allPanesLoaded,
                .conflictNavigationSupported,
                .hasConflicts,
                .conflictTarget(.first)
            ]
        )
        assertResolution(
            .lastConflict,
            in: makeContext(
                conflictNavigation: State.ConflictNavigationState(
                    isSupported: true,
                    hasConflicts: false,
                    canSelectLastConflict: true
                )
            ),
            availability: .disabled(.noConflicts),
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .allPanesLoaded,
                .conflictNavigationSupported,
                .hasConflicts,
                .conflictTarget(.last)
            ]
        )
        assertResolution(
            .firstConflict,
            in: makeContext(
                lifecycle: .stale,
                conflictNavigation: State.ConflictNavigationState(
                    isSupported: false,
                    hasConflicts: false
                )
            ),
            availability: .disabled(.comparisonStale),
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .allPanesLoaded,
                .conflictNavigationSupported,
                .hasConflicts,
                .conflictTarget(.first)
            ]
        )
    }

    func testAutomaticMergeMatrixUsesDirectLiteralExpectations() {
        let middlePreconditions: [Preconditions] = [
            .sessionUnlocked,
            .currentComparison,
            .threePane,
            .automaticMergeSupported,
            .automaticMergeEligible,
            .allPanesLoaded,
            .paneEditable(.middle),
            .allPanesClean
        ]
        let lifecycleCases:
            [(
                name: String,
                lifecycle: State.ComparisonLifecycle,
                availability: State.Availability
            )] = [
                ("loading", .loading, .disabled(.comparisonLoading)),
                ("refreshing", .refreshing, .disabled(.comparisonRefreshing)),
                ("stale", .stale, .disabled(.comparisonStale)),
                ("failed", .failed, .disabled(.comparisonFailed)),
                ("canceled", .canceled, .disabled(.comparisonCanceled))
            ]

        for testCase in lifecycleCases {
            assertResolution(
                .autoMerge,
                in: makeContext(
                    layout: automaticMergeLayout(),
                    lifecycle: testCase.lifecycle
                ),
                availability: testCase.availability,
                preconditions: middlePreconditions,
                state: testCase.name
            )
        }

        assertResolution(
            .autoMerge,
            in: makeContext(),
            availability: .disabled(.requiresThreePane),
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .threePane,
                .automaticMergeSupported,
                .automaticMergeEligible,
                .allPanesLoaded,
                .allPanesClean
            ]
        )
        assertResolution(
            .autoMerge,
            in: makeContext(layout: threePane()),
            availability: .disabled(.unsupportedCommand(.autoMerge)),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(layout: automaticMergeLayout(isEligible: false)),
            availability: .disabled(.automaticMergeUnavailable),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(
                left: unloadedPane(),
                layout: automaticMergeLayout()
            ),
            availability: .disabled(.sideNotLoaded(.left)),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(
                layout: automaticMergeLayout(middle: unloadedPane())
            ),
            availability: .disabled(.sideNotLoaded(.middle)),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(
                right: unloadedPane(),
                layout: automaticMergeLayout()
            ),
            availability: .disabled(.sideNotLoaded(.right)),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(
                layout: automaticMergeLayout(middle: pane(isEditable: false))
            ),
            availability: .disabled(.destinationReadOnly(.middle)),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(
                left: pane(isDirty: true),
                layout: automaticMergeLayout()
            ),
            availability: .disabled(.unsavedChanges(.left)),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(
                layout: automaticMergeLayout(middle: pane(isDirty: true))
            ),
            availability: .disabled(.unsavedChanges(.middle)),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(
                right: pane(isDirty: true),
                layout: automaticMergeLayout()
            ),
            availability: .disabled(.unsavedChanges(.right)),
            preconditions: middlePreconditions
        )
        assertResolution(
            .autoMerge,
            in: makeContext(layout: automaticMergeLayout()),
            availability: .enabled,
            preconditions: middlePreconditions
        )

        let leftDestination = automaticMergeLayout(destination: .left)
        assertResolution(
            .autoMerge,
            in: makeContext(left: pane(isEditable: false), layout: leftDestination),
            availability: .disabled(.destinationReadOnly(.left)),
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .threePane,
                .automaticMergeSupported,
                .automaticMergeEligible,
                .allPanesLoaded,
                .paneEditable(.left),
                .allPanesClean
            ]
        )
        let rightDestination = automaticMergeLayout(destination: .right)
        assertResolution(
            .autoMerge,
            in: makeContext(right: pane(isEditable: false), layout: rightDestination),
            availability: .disabled(.destinationReadOnly(.right)),
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .threePane,
                .automaticMergeSupported,
                .automaticMergeEligible,
                .allPanesLoaded,
                .paneEditable(.right),
                .allPanesClean
            ]
        )
    }

    func testUndoAndRedoRemainAsymmetric() {
        let undoOnly = makeContext(canUndo: true, canRedo: false)
        assertResolution(
            .undo,
            in: undoOnly,
            availability: .enabled,
            preconditions: [.sessionUnlocked, .comparisonNotLoading, .undoAvailable]
        )
        assertResolution(
            .redo,
            in: undoOnly,
            availability: .disabled(.noRedo),
            preconditions: [.sessionUnlocked, .comparisonNotLoading, .redoAvailable]
        )

        let redoOnly = makeContext(canUndo: false, canRedo: true)
        assertResolution(
            .undo,
            in: redoOnly,
            availability: .disabled(.noUndo),
            preconditions: [.sessionUnlocked, .comparisonNotLoading, .undoAvailable]
        )
        assertResolution(
            .redo,
            in: redoOnly,
            availability: .enabled,
            preconditions: [.sessionUnlocked, .comparisonNotLoading, .redoAvailable]
        )
    }

    func testComparedFileTargetsAreOneHot() {
        let cases:
            [(
                enabledCommand: Command,
                navigation: State.ComparedFileNavigation,
                expected: [(Command, State.Availability, State.ComparedFileTarget)]
            )] = [
                (
                    .firstComparedFile,
                    State.ComparedFileNavigation(isSupported: true, canSelectFirst: true),
                    [
                        (.firstComparedFile, .enabled, .first),
                        (.previousComparedFile, .disabled(.noPreviousComparedFile), .previous),
                        (.nextComparedFile, .disabled(.noNextComparedFile), .next),
                        (.lastComparedFile, .disabled(.noLastComparedFile), .last)
                    ]
                ),
                (
                    .previousComparedFile,
                    State.ComparedFileNavigation(isSupported: true, canSelectPrevious: true),
                    [
                        (.firstComparedFile, .disabled(.noFirstComparedFile), .first),
                        (.previousComparedFile, .enabled, .previous),
                        (.nextComparedFile, .disabled(.noNextComparedFile), .next),
                        (.lastComparedFile, .disabled(.noLastComparedFile), .last)
                    ]
                ),
                (
                    .nextComparedFile,
                    State.ComparedFileNavigation(isSupported: true, canSelectNext: true),
                    [
                        (.firstComparedFile, .disabled(.noFirstComparedFile), .first),
                        (.previousComparedFile, .disabled(.noPreviousComparedFile), .previous),
                        (.nextComparedFile, .enabled, .next),
                        (.lastComparedFile, .disabled(.noLastComparedFile), .last)
                    ]
                ),
                (
                    .lastComparedFile,
                    State.ComparedFileNavigation(isSupported: true, canSelectLast: true),
                    [
                        (.firstComparedFile, .disabled(.noFirstComparedFile), .first),
                        (.previousComparedFile, .disabled(.noPreviousComparedFile), .previous),
                        (.nextComparedFile, .disabled(.noNextComparedFile), .next),
                        (.lastComparedFile, .enabled, .last)
                    ]
                )
            ]

        for testCase in cases {
            let context = makeContext(comparedFileNavigation: testCase.navigation)
            for expected in testCase.expected {
                assertResolution(
                    expected.0,
                    in: context,
                    availability: expected.1,
                    preconditions: [
                        .sessionUnlocked,
                        .comparisonNotLoading,
                        .comparedFileNavigationSupported,
                        .comparedFileTarget(expected.2)
                    ],
                    state: "Enabled: \(testCase.enabledCommand)"
                )
            }
        }

        assertResolution(
            .nextComparedFile,
            in: makeContext(),
            availability: .disabled(.unsupportedCommand(.nextComparedFile)),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .comparedFileNavigationSupported,
                .comparedFileTarget(.next)
            ]
        )
    }

    func testToolbarOrderAndBidirectionalMappingsAreLiteral() {
        let toolbarOrder: [ToolbarConfiguration.Command] = [
            .newComparison,
            .openComparison,
            .save,
            .undo,
            .redo,
            .selectLineDifference,
            .nextDifference,
            .previousDifference,
            .nextConflict,
            .previousConflict,
            .firstDifference,
            .currentDifference,
            .lastDifference,
            .copyToRight,
            .copyToLeft,
            .copyToRightAndAdvance,
            .copyToLeftAndAdvance,
            .copyAllToRight,
            .copyAllToLeft,
            .autoMerge,
            .firstComparedFile,
            .previousComparedFile,
            .nextComparedFile,
            .lastComparedFile,
            .options,
            .refresh
        ]
        let identifierOrder: [Command] = [
            .newComparison,
            .openComparison,
            .save,
            .undo,
            .redo,
            .selectLineDifference,
            .nextDifference,
            .previousDifference,
            .nextConflict,
            .previousConflict,
            .firstDifference,
            .currentDifference,
            .lastDifference,
            .copyToRight,
            .copyToLeft,
            .copyToRightAndAdvance,
            .copyToLeftAndAdvance,
            .copyAllToRight,
            .copyAllToLeft,
            .autoMerge,
            .firstComparedFile,
            .previousComparedFile,
            .nextComparedFile,
            .lastComparedFile,
            .options,
            .refresh
        ]
        let menuOnlyCommands: [Command] = [
            .openLeft,
            .openMiddle,
            .openRight,
            .saveLeft,
            .saveMiddle,
            .saveRight,
            .saveLeftAs,
            .saveMiddleAs,
            .saveRightAs,
            .selectPreviousLineDifference,
            .firstConflict,
            .currentConflict,
            .lastConflict,
            .leftReadOnly,
            .middleReadOnly,
            .rightReadOnly,
            .mergeMode,
            .reloadFromDisk,
            .changePane,
            .changePaneBack
        ]

        XCTAssertEqual(ToolbarConfiguration.Command.allCases, toolbarOrder)
        XCTAssertEqual(toolbarOrder.map(Command.init), identifierOrder)
        XCTAssertEqual(identifierOrder.map(\.toolbarCommand), toolbarOrder.map(Optional.some))
        XCTAssertEqual(menuOnlyCommands.map(\.toolbarCommand), Array(repeating: nil, count: 20))
        XCTAssertEqual(
            State.resolveToolbar(in: makeContext()).map(\.command),
            identifierOrder
        )
    }

    func testReloadAndChangePaneStatesAreLiteral() {
        let reloadPreconditions: [Preconditions] = [
            .sessionUnlocked,
            .comparisonNotLoading,
            .anyReloadablePane
        ]
        assertResolution(
            .reloadFromDisk,
            in: makeContext(left: unloadedPane(), right: unloadedPane()),
            availability: .disabled(.noReloadablePane),
            preconditions: reloadPreconditions
        )
        assertResolution(
            .reloadFromDisk,
            in: makeContext(
                left: pane(isUntitled: true),
                right: pane(isUntitled: true)
            ),
            availability: .disabled(.noReloadablePane),
            preconditions: reloadPreconditions
        )
        assertResolution(
            .reloadFromDisk,
            in: makeContext(left: pane(), right: unloadedPane()),
            availability: .enabled,
            preconditions: reloadPreconditions
        )
        assertResolution(
            .reloadFromDisk,
            in: makeContext(left: pane(isDirty: true), right: unloadedPane()),
            availability: .enabled,
            title: .reloadWithUnsavedChanges,
            preconditions: reloadPreconditions
        )
        assertResolution(
            .reloadFromDisk,
            in: makeContext(
                left: pane(isDirty: true, isUntitled: true),
                right: unloadedPane()
            ),
            availability: .disabled(.noReloadablePane),
            preconditions: reloadPreconditions
        )

        let changePanePreconditions: [Preconditions] = [
            .sessionUnlocked,
            .comparisonNotLoading,
            .allPanesLoaded,
            .changePaneAvailable
        ]
        let changePaneBackPreconditions: [Preconditions] = [
            .sessionUnlocked,
            .comparisonNotLoading,
            .allPanesLoaded,
            .changePaneBackAvailable
        ]
        assertResolution(
            .changePane,
            in: makeContext(canChangePane: false, canChangePaneBack: true),
            availability: .disabled(.paneChangeUnavailable),
            preconditions: changePanePreconditions
        )
        assertResolution(
            .changePaneBack,
            in: makeContext(canChangePane: false, canChangePaneBack: true),
            availability: .enabled,
            preconditions: changePaneBackPreconditions
        )
        assertResolution(
            .changePane,
            in: makeContext(canChangePane: true, canChangePaneBack: false),
            availability: .enabled,
            preconditions: changePanePreconditions
        )
        assertResolution(
            .changePaneBack,
            in: makeContext(canChangePane: true, canChangePaneBack: false),
            availability: .disabled(.paneChangeBackUnavailable),
            preconditions: changePaneBackPreconditions
        )
        assertResolution(
            .changePane,
            in: makeContext(
                right: unloadedPane(),
                canChangePane: true,
                canChangePaneBack: true
            ),
            availability: .disabled(.sideNotLoaded(.right)),
            preconditions: changePanePreconditions
        )
        assertResolution(
            .changePaneBack,
            in: makeContext(
                left: unloadedPane(),
                right: unloadedPane(),
                canChangePane: true,
                canChangePaneBack: true
            ),
            availability: .disabled(.noComparison),
            preconditions: changePaneBackPreconditions
        )
    }

    func testRefreshRequiresCurrentLoadedPanes() {
        let preconditions: [Preconditions] = [
            .sessionUnlocked,
            .comparisonNotLoading,
            .allPanesLoaded
        ]

        assertResolution(
            .refresh,
            in: makeContext(),
            availability: .enabled,
            preconditions: preconditions
        )
        assertResolution(
            .refresh,
            in: makeContext(left: unloadedPane(), right: unloadedPane()),
            availability: .disabled(.noComparison),
            preconditions: preconditions
        )
        assertResolution(
            .refresh,
            in: makeContext(right: unloadedPane()),
            availability: .disabled(.sideNotLoaded(.right)),
            preconditions: preconditions
        )
        assertResolution(
            .refresh,
            in: makeContext(lifecycle: .loading),
            availability: .disabled(.comparisonLoading),
            preconditions: preconditions
        )
        assertResolution(
            .refresh,
            in: makeContext(lifecycle: .refreshing),
            availability: .disabled(.comparisonRefreshing),
            preconditions: preconditions
        )
        assertResolution(
            .refresh,
            in: makeContext(lifecycle: .stale),
            availability: .enabled,
            preconditions: preconditions
        )
    }

    func testMergeModeAndReadOnlyCheckedStatesCoverOffAndOn() {
        let off = makeContext(
            layout: threePane(middle: pane()),
            isMergeMode: false
        )
        assertResolution(
            .leftReadOnly,
            in: off,
            availability: .enabled,
            checkedState: .off,
            title: .makeReadOnly(.left),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.left),
                .paneLoaded(.left)
            ]
        )
        assertResolution(
            .middleReadOnly,
            in: off,
            availability: .enabled,
            checkedState: .off,
            title: .makeReadOnly(.middle),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.middle),
                .paneLoaded(.middle)
            ]
        )
        assertResolution(
            .rightReadOnly,
            in: off,
            availability: .enabled,
            checkedState: .off,
            title: .makeReadOnly(.right),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.right),
                .paneLoaded(.right)
            ]
        )
        assertResolution(
            .mergeMode,
            in: off,
            availability: .enabled,
            checkedState: .off,
            preconditions: []
        )

        let on = makeContext(
            left: pane(isEditable: false),
            right: pane(isEditable: false),
            layout: threePane(middle: pane(isEditable: false)),
            isMergeMode: true
        )
        assertResolution(
            .leftReadOnly,
            in: on,
            availability: .enabled,
            checkedState: .on,
            title: .makeEditable(.left),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.left),
                .paneLoaded(.left)
            ]
        )
        assertResolution(
            .middleReadOnly,
            in: on,
            availability: .enabled,
            checkedState: .on,
            title: .makeEditable(.middle),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.middle),
                .paneLoaded(.middle)
            ]
        )
        assertResolution(
            .rightReadOnly,
            in: on,
            availability: .enabled,
            checkedState: .on,
            title: .makeEditable(.right),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.right),
                .paneLoaded(.right)
            ]
        )
        assertResolution(
            .mergeMode,
            in: on,
            availability: .enabled,
            checkedState: .on,
            preconditions: []
        )

        assertResolution(
            .middleReadOnly,
            in: makeContext(),
            availability: .disabled(.requiresThreePane),
            checkedState: .off,
            title: .makeReadOnly(.middle),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.middle),
                .paneLoaded(.middle)
            ]
        )
        assertResolution(
            .rightReadOnly,
            in: makeContext(right: unloadedPane()),
            availability: .disabled(.sideNotLoaded(.right)),
            checkedState: .off,
            title: .makeReadOnly(.right),
            preconditions: [
                .sessionUnlocked,
                .comparisonNotLoading,
                .paneExists(.right),
                .paneLoaded(.right)
            ]
        )
    }

    private struct CopyLayoutCase {
        let order: [State.Side]
        let active: State.Side
        let leftRoute: State.CopyRoute
        let rightRoute: State.CopyRoute
    }

    private func assertCopyRoutes(
        in context: State.Context,
        leftRoute: State.CopyRoute,
        rightRoute: State.CopyRoute,
        state: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertResolution(
            .copyToLeft,
            in: context,
            availability: .enabled,
            title: .copy(to: leftRoute.destinationPosition),
            copyRoute: leftRoute,
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .paneLoaded(leftRoute.source),
                .paneLoaded(leftRoute.destination),
                .paneEditable(leftRoute.destination),
                .hasSignificantDifferences,
                .hasSelection
            ],
            state: state,
            file: file,
            line: line
        )
        assertResolution(
            .copyToLeftAndAdvance,
            in: context,
            availability: .enabled,
            title: .copy(to: leftRoute.destinationPosition),
            copyRoute: leftRoute,
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .paneLoaded(leftRoute.source),
                .paneLoaded(leftRoute.destination),
                .paneEditable(leftRoute.destination),
                .hasSignificantDifferences,
                .hasSelection
            ],
            state: state,
            file: file,
            line: line
        )
        assertResolution(
            .copyAllToLeft,
            in: context,
            availability: .enabled,
            title: .copyAll(to: leftRoute.destinationPosition),
            copyRoute: leftRoute,
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .paneLoaded(leftRoute.source),
                .paneLoaded(leftRoute.destination),
                .paneEditable(leftRoute.destination),
                .hasSignificantDifferences
            ],
            state: state,
            file: file,
            line: line
        )
        assertResolution(
            .copyToRight,
            in: context,
            availability: .enabled,
            title: .copy(to: rightRoute.destinationPosition),
            copyRoute: rightRoute,
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .paneLoaded(rightRoute.source),
                .paneLoaded(rightRoute.destination),
                .paneEditable(rightRoute.destination),
                .hasSignificantDifferences,
                .hasSelection
            ],
            state: state,
            file: file,
            line: line
        )
        assertResolution(
            .copyToRightAndAdvance,
            in: context,
            availability: .enabled,
            title: .copy(to: rightRoute.destinationPosition),
            copyRoute: rightRoute,
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .paneLoaded(rightRoute.source),
                .paneLoaded(rightRoute.destination),
                .paneEditable(rightRoute.destination),
                .hasSignificantDifferences,
                .hasSelection
            ],
            state: state,
            file: file,
            line: line
        )
        assertResolution(
            .copyAllToRight,
            in: context,
            availability: .enabled,
            title: .copyAll(to: rightRoute.destinationPosition),
            copyRoute: rightRoute,
            preconditions: [
                .sessionUnlocked,
                .currentComparison,
                .paneLoaded(rightRoute.source),
                .paneLoaded(rightRoute.destination),
                .paneEditable(rightRoute.destination),
                .hasSignificantDifferences
            ],
            state: state,
            file: file,
            line: line
        )
    }

    private func assertResolution(
        _ command: Command,
        in context: State.Context,
        availability: State.Availability,
        checkedState: State.CheckedState = .notApplicable,
        title: State.TitleVariant = .standard,
        copyRoute: State.CopyRoute? = nil,
        preconditions: [Preconditions],
        state: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = State.Resolution(
            command: command,
            availability: availability,
            checkedState: checkedState,
            titleVariant: title,
            copyRoute: copyRoute,
            executionPreconditions: preconditions
        )

        XCTAssertEqual(
            State.resolve(command, in: context),
            expected,
            state,
            file: file,
            line: line
        )
    }

    private func makeContext(
        left: Pane = Pane(isLoaded: true, isEditable: true),
        right: Pane = Pane(isLoaded: true, isEditable: true),
        layout: State.Layout = .twoPane,
        layoutContext: State.LayoutContext? = nil,
        lifecycle: State.ComparisonLifecycle = .currentSuccess,
        hasSelection: Bool = false,
        hasSignificantDifferences: Bool = false,
        canUndo: Bool = false,
        canRedo: Bool = false,
        differenceNavigation: State.DifferenceNavigation = .unavailable,
        conflictNavigation: State.ConflictNavigationState = .unsupported,
        comparedFileNavigation: State.ComparedFileNavigation = .unsupported,
        canChangePane: Bool = false,
        canChangePaneBack: Bool = false,
        isMergeMode: Bool = false,
        isSessionLocked: Bool = false
    ) -> State.Context {
        State.Context(
            left: left,
            right: right,
            layout: layout,
            layoutContext: layoutContext,
            lifecycle: lifecycle,
            hasSelection: hasSelection,
            hasSignificantDifferences: hasSignificantDifferences,
            canUndo: canUndo,
            canRedo: canRedo,
            differenceNavigation: differenceNavigation,
            conflictNavigation: conflictNavigation,
            comparedFileNavigation: comparedFileNavigation,
            canChangePane: canChangePane,
            canChangePaneBack: canChangePaneBack,
            isMergeMode: isMergeMode,
            isSessionLocked: isSessionLocked
        )
    }

    private func pane(
        isLoaded: Bool = true,
        isEditable: Bool = true,
        isDirty: Bool = false,
        isUntitled: Bool = false,
        hasExternalChange: Bool = false
    ) -> Pane {
        Pane(
            isLoaded: isLoaded,
            isEditable: isEditable,
            isDirty: isDirty,
            isUntitled: isUntitled,
            hasExternalChange: hasExternalChange
        )
    }

    private func unloadedPane() -> Pane {
        Pane()
    }

    private func threePane(middle: Pane? = nil) -> State.Layout {
        .threePane(
            middle: middle ?? pane(),
            automaticMergeDestination: .middle
        )
    }

    private func automaticMergeLayout(
        middle: Pane? = nil,
        destination: State.Side = .middle,
        isEligible: Bool = true
    ) -> State.Layout {
        .threePane(
            middle: middle ?? pane(),
            automaticMergeDestination: destination,
            supportsAutomaticMerge: true,
            isAutomaticMergeEligible: isEligible
        )
    }

    private func route(
        source: State.Side,
        destination: State.Side,
        sourcePosition: State.VisualPosition,
        destinationPosition: State.VisualPosition
    ) -> State.CopyRoute {
        State.CopyRoute(
            source: source,
            destination: destination,
            sourcePosition: sourcePosition,
            destinationPosition: destinationPosition
        )
    }
}
