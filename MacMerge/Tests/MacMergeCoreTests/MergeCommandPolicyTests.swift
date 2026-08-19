import MacMergeCore
import XCTest

final class MergeCommandPolicyTests: XCTestCase {
    typealias Policy = MergeCommandPolicy

    func testTwoWayEnabledMatrixAndCommandLookupAreConsistent() {
        let state = makeState()
        let commands = Policy.evaluate(state)

        XCTAssertEqual(commands.leftToRight, .enabled)
        XCTAssertEqual(commands.rightToLeft, .enabled)
        XCTAssertEqual(commands.leftToRightAndAdvance, commands.leftToRight)
        XCTAssertEqual(commands.rightToLeftAndAdvance, commands.rightToLeft)
        XCTAssertEqual(commands.copyAllToRight, .enabled)
        XCTAssertEqual(commands.copyAllToLeft, .enabled)
        XCTAssertEqual(commands.saveLeft, .disabled(.noUnsavedChanges(.left)))
        XCTAssertEqual(commands.saveMiddle, .disabled(.sideNotLoaded(.middle)))
        XCTAssertEqual(commands.saveRight, .disabled(.noUnsavedChanges(.right)))
        XCTAssertEqual(commands.autoMerge, .disabled(.autoMergeUnavailable))
        XCTAssertFalse(state.isThreeWay)
        XCTAssertNil(state.middle)
        XCTAssertNil(state.autoMergeDestination)

        let storedStates: [(Policy.Command, Policy.Availability)] = [
            (.leftToRight, commands.leftToRight),
            (.rightToLeft, commands.rightToLeft),
            (.leftToRightAndAdvance, commands.leftToRightAndAdvance),
            (.rightToLeftAndAdvance, commands.rightToLeftAndAdvance),
            (.copyAllToRight, commands.copyAllToRight),
            (.copyAllToLeft, commands.copyAllToLeft),
            (.saveLeft, commands.saveLeft),
            (.saveMiddle, commands.saveMiddle),
            (.saveRight, commands.saveRight),
            (.autoMerge, commands.autoMerge)
        ]
        XCTAssertEqual(storedStates.map(\.0), Policy.Command.allCases)
        for (command, storedState) in storedStates {
            XCTAssertEqual(commands[command], storedState)
            XCTAssertEqual(storedState.isEnabled, storedState == .enabled)
            XCTAssertEqual(storedState.disabledReason, disabledReason(storedState))
        }
    }

    func testCommandLookupMapsEveryCaseToItsStoredProperty() {
        let states = Policy.CommandStates(
            leftToRight: .disabled(.sideNotLoaded(.left)),
            rightToLeft: .disabled(.sideNotLoaded(.right)),
            leftToRightAndAdvance: .disabled(.destinationNotEditable(.right)),
            rightToLeftAndAdvance: .disabled(.destinationNotEditable(.left)),
            copyAllToRight: .disabled(.noSelection),
            copyAllToLeft: .disabled(.noSignificantDifferences),
            saveLeft: .disabled(.noUnsavedChanges(.left)),
            saveMiddle: .disabled(.noUnsavedChanges(.middle)),
            saveRight: .disabled(.noUnsavedChanges(.right)),
            autoMerge: .disabled(.autoMergeUnavailable)
        )
        let expected: [Policy.Command: Policy.Availability] = [
            .leftToRight: states.leftToRight,
            .rightToLeft: states.rightToLeft,
            .leftToRightAndAdvance: states.leftToRightAndAdvance,
            .rightToLeftAndAdvance: states.rightToLeftAndAdvance,
            .copyAllToRight: states.copyAllToRight,
            .copyAllToLeft: states.copyAllToLeft,
            .saveLeft: states.saveLeft,
            .saveMiddle: states.saveMiddle,
            .saveRight: states.saveRight,
            .autoMerge: states.autoMerge
        ]

        for command in Policy.Command.allCases {
            XCTAssertEqual(states[command], expected[command])
        }
    }

    func testLifecycleAndEqualityMatrixCoversEveryWiredCommand() {
        let cases:
            [(
                name: String,
                lifecycle: Policy.ComparisonLifecycle,
                hasSignificantDifferences: Bool,
                expected: Policy.Availability,
                expectedAutoMerge: Policy.Availability
            )] = [
                (
                    "loading",
                    .loading,
                    true,
                    .disabled(.comparisonLoading),
                    .disabled(.comparisonLoading)
                ),
                (
                    "stale",
                    .stale,
                    true,
                    .disabled(.comparisonStale),
                    .disabled(.comparisonStale)
                ),
                (
                    "failed",
                    .failed,
                    true,
                    .disabled(.comparisonFailed),
                    .disabled(.comparisonFailed)
                ),
                (
                    "current equal",
                    .currentSuccess,
                    false,
                    .disabled(.noSignificantDifferences),
                    .enabled
                ),
                ("current different", .currentSuccess, true, .enabled, .enabled)
            ]

        for testCase in cases {
            let commands = evaluate(
                comparisonLifecycle: testCase.lifecycle,
                hasSignificantDifferences: testCase.hasSignificantDifferences
            )
            assertWiredCommands(
                commands,
                equal: testCase.expected,
                state: testCase.name
            )
            XCTAssertEqual(
                evaluate(
                    layout: threeWay(isAutoMergeEligible: true),
                    comparisonLifecycle: testCase.lifecycle,
                    hasSignificantDifferences: testCase.hasSignificantDifferences
                ).autoMerge,
                testCase.expectedAutoMerge,
                testCase.name
            )
        }
    }

    func testNoncurrentLifecyclePrecedesUnloadedAndReadOnlyMergeInputs() {
        let lifecycleCases: [(Policy.ComparisonLifecycle, Policy.Availability)] = [
            (.loading, .disabled(.comparisonLoading)),
            (.stale, .disabled(.comparisonStale)),
            (.failed, .disabled(.comparisonFailed))
        ]
        let sideCases: [(String, Policy.SideState, Policy.SideState, Policy.SideState)] = [
            ("unloaded", unloaded(), unloaded(), unloaded()),
            (
                "read-only",
                clean(editable: false),
                clean(editable: false),
                clean(editable: false)
            )
        ]

        for (lifecycle, expected) in lifecycleCases {
            for (inputState, left, middle, right) in sideCases {
                let commands = evaluate(
                    left: left,
                    right: right,
                    layout: threeWay(middle: middle, isAutoMergeEligible: true),
                    comparisonLifecycle: lifecycle,
                    hasSelection: false,
                    hasSignificantDifferences: false
                )
                let state = "\(lifecycle), \(inputState)"

                assertWiredCommands(commands, equal: expected, state: state)
                XCTAssertEqual(commands.autoMerge, expected, state)
            }
        }
    }

    func testAutoMergeLoadingPrecedesIneligibilityAndPaneState() {
        let commands = evaluate(
            left: unloaded(),
            right: unloaded(),
            layout: threeWay(middle: unloaded(), isAutoMergeEligible: false),
            comparisonLifecycle: .loading
        )

        XCTAssertEqual(commands.autoMerge, .disabled(.comparisonLoading))
    }

    func testAllCommandStateMatrixMatchesExecutionLifecycleGates() {
        let loading: Policy.Availability = .disabled(.comparisonLoading)
        let stale: Policy.Availability = .disabled(.comparisonStale)
        let failed: Policy.Availability = .disabled(.comparisonFailed)
        let cases:
            [(
                name: String,
                state: Policy.State,
                expected: [Policy.Command: Policy.Availability]
            )] = [
                (
                    "clean two-way",
                    makeState(),
                    commandMatrix(
                        leftToRight: .enabled,
                        rightToLeft: .enabled,
                        saveLeft: .disabled(.noUnsavedChanges(.left)),
                        saveMiddle: .disabled(.sideNotLoaded(.middle)),
                        saveRight: .disabled(.noUnsavedChanges(.right)),
                        autoMerge: .disabled(.autoMergeUnavailable)
                    )
                ),
                (
                    "dirty two-way",
                    makeState(left: dirty(), right: dirty()),
                    commandMatrix(
                        leftToRight: .enabled,
                        rightToLeft: .enabled,
                        saveLeft: .enabled,
                        saveMiddle: .disabled(.sideNotLoaded(.middle)),
                        saveRight: .enabled,
                        autoMerge: .disabled(.autoMergeUnavailable)
                    )
                ),
                (
                    "loading dirty two-way",
                    makeState(
                        left: dirty(),
                        right: dirty(),
                        comparisonLifecycle: .loading
                    ),
                    commandMatrix(
                        leftToRight: loading,
                        rightToLeft: loading,
                        saveLeft: loading,
                        saveMiddle: loading,
                        saveRight: loading,
                        autoMerge: loading
                    )
                ),
                (
                    "failed clean two-way",
                    makeState(comparisonLifecycle: .failed),
                    commandMatrix(
                        leftToRight: failed,
                        rightToLeft: failed,
                        saveLeft: .disabled(.noUnsavedChanges(.left)),
                        saveMiddle: .disabled(.sideNotLoaded(.middle)),
                        saveRight: .disabled(.noUnsavedChanges(.right)),
                        autoMerge: failed
                    )
                ),
                (
                    "clean three-way",
                    makeState(layout: threeWay(isAutoMergeEligible: true)),
                    commandMatrix(
                        leftToRight: .enabled,
                        rightToLeft: .enabled,
                        saveLeft: .disabled(.noUnsavedChanges(.left)),
                        saveMiddle: .disabled(.noUnsavedChanges(.middle)),
                        saveRight: .disabled(.noUnsavedChanges(.right)),
                        autoMerge: .enabled
                    )
                ),
                (
                    "dirty three-way",
                    makeState(
                        left: dirty(),
                        right: dirty(),
                        layout: threeWay(middle: dirty(), isAutoMergeEligible: true)
                    ),
                    commandMatrix(
                        leftToRight: .enabled,
                        rightToLeft: .enabled,
                        saveLeft: .enabled,
                        saveMiddle: .enabled,
                        saveRight: .enabled,
                        autoMerge: .disabled(.unsavedChanges(.left))
                    )
                ),
                (
                    "loading dirty three-way",
                    makeState(
                        left: dirty(),
                        right: dirty(),
                        layout: threeWay(middle: dirty(), isAutoMergeEligible: true),
                        comparisonLifecycle: .loading
                    ),
                    commandMatrix(
                        leftToRight: loading,
                        rightToLeft: loading,
                        saveLeft: loading,
                        saveMiddle: loading,
                        saveRight: loading,
                        autoMerge: loading
                    )
                ),
                (
                    "stale dirty three-way",
                    makeState(
                        left: dirty(),
                        right: dirty(),
                        layout: threeWay(middle: dirty(), isAutoMergeEligible: true),
                        comparisonLifecycle: .stale
                    ),
                    commandMatrix(
                        leftToRight: stale,
                        rightToLeft: stale,
                        saveLeft: .enabled,
                        saveMiddle: .enabled,
                        saveRight: .enabled,
                        autoMerge: stale
                    )
                ),
                (
                    "failed dirty three-way",
                    makeState(
                        left: dirty(),
                        right: dirty(),
                        layout: threeWay(middle: dirty(), isAutoMergeEligible: true),
                        comparisonLifecycle: .failed
                    ),
                    commandMatrix(
                        leftToRight: failed,
                        rightToLeft: failed,
                        saveLeft: .enabled,
                        saveMiddle: .enabled,
                        saveRight: .enabled,
                        autoMerge: failed
                    )
                ),
                (
                    "dirty read-only three-way",
                    makeState(
                        left: dirty(editable: false),
                        right: dirty(editable: false),
                        layout: threeWay(
                            middle: dirty(editable: false),
                            isAutoMergeEligible: true
                        )
                    ),
                    commandMatrix(
                        leftToRight: .disabled(.destinationNotEditable(.right)),
                        rightToLeft: .disabled(.destinationNotEditable(.left)),
                        saveLeft: .disabled(.sideNotEditable(.left)),
                        saveMiddle: .disabled(.sideNotEditable(.middle)),
                        saveRight: .disabled(.sideNotEditable(.right)),
                        autoMerge: .disabled(.destinationNotEditable(.middle))
                    )
                )
            ]

        for testCase in cases {
            assertAllCommands(
                Policy.evaluate(testCase.state),
                expected: testCase.expected,
                state: testCase.name
            )
        }
    }

    func testReadOnlyPaneMatrixIsDirectionalAndCopyAllSymmetric() {
        let destinationReadOnly: Policy.Availability = .disabled(
            .destinationNotEditable(.left)
        )
        let leftReadOnly = evaluate(left: clean(editable: false))
        assertWiredCommands(
            leftReadOnly,
            expected: [
                .leftToRight: .enabled,
                .rightToLeft: destinationReadOnly,
                .leftToRightAndAdvance: .enabled,
                .rightToLeftAndAdvance: destinationReadOnly,
                .copyAllToRight: .enabled,
                .copyAllToLeft: destinationReadOnly
            ],
            state: "left read-only"
        )

        let rightDestinationReadOnly: Policy.Availability = .disabled(
            .destinationNotEditable(.right)
        )
        let rightReadOnly = evaluate(right: clean(editable: false))
        assertWiredCommands(
            rightReadOnly,
            expected: [
                .leftToRight: rightDestinationReadOnly,
                .rightToLeft: .enabled,
                .leftToRightAndAdvance: rightDestinationReadOnly,
                .rightToLeftAndAdvance: .enabled,
                .copyAllToRight: rightDestinationReadOnly,
                .copyAllToLeft: .enabled
            ],
            state: "right read-only"
        )
    }

    func testAllSixWiredCommandsExposeExecutionAndEnablementPolicyOutputs() {
        let noSelection = evaluate(hasSelection: false)
        let expected: [Policy.Command: Policy.Availability] = [
            .leftToRight: .disabled(.noSelection),
            .rightToLeft: .disabled(.noSelection),
            .leftToRightAndAdvance: .disabled(.noSelection),
            .rightToLeftAndAdvance: .disabled(.noSelection),
            .copyAllToRight: .enabled,
            .copyAllToLeft: .enabled
        ]

        assertWiredCommands(noSelection, expected: expected, state: "no selection")
    }

    func testDirectionalCommandsUseDocumentedValidationOrder() {
        let allInvalid = evaluate(
            left: unloaded(),
            right: unloaded(),
            hasSelection: false,
            hasSignificantDifferences: false
        )
        XCTAssertEqual(allInvalid.leftToRight, .disabled(.sideNotLoaded(.left)))
        XCTAssertEqual(allInvalid.leftToRightAndAdvance, allInvalid.leftToRight)
        XCTAssertEqual(allInvalid.rightToLeft, .disabled(.sideNotLoaded(.left)))
        XCTAssertEqual(allInvalid.rightToLeftAndAdvance, allInvalid.rightToLeft)

        XCTAssertEqual(
            evaluate(left: unloaded()).leftToRight,
            .disabled(.sideNotLoaded(.left))
        )
        XCTAssertEqual(
            evaluate(right: unloaded()).leftToRight,
            .disabled(.sideNotLoaded(.right))
        )
        XCTAssertEqual(
            evaluate(right: clean(editable: false)).leftToRight,
            .disabled(.destinationNotEditable(.right))
        )
        XCTAssertEqual(
            evaluate(hasSignificantDifferences: false).leftToRight,
            .disabled(.noSignificantDifferences)
        )
        XCTAssertEqual(
            evaluate(hasSelection: false, hasSignificantDifferences: false).leftToRight,
            .disabled(.noSignificantDifferences)
        )
        XCTAssertEqual(
            evaluate(hasSelection: false).leftToRight,
            .disabled(.noSelection)
        )
        XCTAssertEqual(
            evaluate(left: clean(editable: false)).leftToRight,
            .enabled,
            "Read-only source remains mergeable into an editable destination"
        )
        XCTAssertEqual(
            evaluate(left: clean(editable: false)).rightToLeft,
            .disabled(.destinationNotEditable(.left))
        )

        let disabled = evaluate(right: clean(editable: false))
        XCTAssertEqual(disabled.leftToRightAndAdvance, disabled.leftToRight)
        XCTAssertEqual(disabled.rightToLeftAndAdvance, disabled.rightToLeft)
    }

    func testCopyAllDoesNotRequireSelectionButRequiresDifferencesAndEditableDestination() {
        let noSelection = evaluate(hasSelection: false)
        XCTAssertEqual(noSelection.copyAllToLeft, .enabled)
        XCTAssertEqual(noSelection.copyAllToRight, .enabled)

        let noDifferences = evaluate(hasSelection: false, hasSignificantDifferences: false)
        XCTAssertEqual(noDifferences.copyAllToLeft, .disabled(.noSignificantDifferences))
        XCTAssertEqual(noDifferences.copyAllToRight, .disabled(.noSignificantDifferences))

        let readOnly = evaluate(left: clean(editable: false), right: clean(editable: false))
        XCTAssertEqual(readOnly.copyAllToLeft, .disabled(.destinationNotEditable(.left)))
        XCTAssertEqual(readOnly.copyAllToRight, .disabled(.destinationNotEditable(.right)))
    }

    func testSaveAvailabilityCoversEveryPaneAndReadOnlyState() {
        let layout = Policy.State.Layout.threeWay(
            middle: dirty(),
            autoMergeDestination: .middle
        )
        let commands = evaluate(left: dirty(), right: dirty(), layout: layout)

        XCTAssertEqual(commands.saveLeft, .enabled)
        XCTAssertEqual(commands.saveMiddle, .enabled)
        XCTAssertEqual(commands.saveRight, .enabled)

        let readOnlyLayout = Policy.State.Layout.threeWay(
            middle: dirty(editable: false),
            autoMergeDestination: .middle
        )
        let readOnly = evaluate(
            left: dirty(editable: false),
            right: dirty(editable: false),
            layout: readOnlyLayout
        )
        XCTAssertEqual(readOnly.saveLeft, .disabled(.sideNotEditable(.left)))
        XCTAssertEqual(readOnly.saveMiddle, .disabled(.sideNotEditable(.middle)))
        XCTAssertEqual(readOnly.saveRight, .disabled(.sideNotEditable(.right)))

        let unloadedLayout = Policy.State.Layout.threeWay(
            middle: unloaded(),
            autoMergeDestination: .middle
        )
        XCTAssertEqual(
            evaluate(left: unloaded(), right: unloaded(), layout: unloadedLayout).saveMiddle,
            .disabled(.sideNotLoaded(.middle))
        )
    }

    func testExplicitThreeWayStateExposesMiddlePaneAndDestination() {
        let middle = clean(editable: false)
        let state = makeState(
            layout: .threeWay(middle: middle, autoMergeDestination: .right)
        )

        XCTAssertTrue(state.isThreeWay)
        XCTAssertEqual(state.middle, middle)
        XCTAssertEqual(state[.middle], middle)
        XCTAssertEqual(state.autoMergeDestination, .right)
        XCTAssertFalse(state.isAutoMergeEligible)
        XCTAssertEqual(
            Policy.evaluate(state).autoMerge,
            .disabled(.autoMergeUnavailable)
        )
        XCTAssertEqual(Policy.Side.allCases, [.left, .middle, .right])
    }

    func testExplicitThreeWayAutoMergeEligibilityIsIndependentOfPairwiseDifferences() {
        for isEligible in [false, true] {
            for hasSignificantDifferences in [false, true] {
                let commands = evaluate(
                    layout: threeWay(isAutoMergeEligible: isEligible),
                    hasSelection: false,
                    hasSignificantDifferences: hasSignificantDifferences
                )
                let expected: Policy.Availability =
                    isEligible
                    ? .enabled
                    : .disabled(.autoMergeUnavailable)
                XCTAssertEqual(
                    commands.autoMerge,
                    expected,
                    "Eligible: \(isEligible), pairwise differences: \(hasSignificantDifferences)"
                )
            }
        }
    }

    func testAutoMergeRequiresAllPanesLoadedInStableOrder() {
        XCTAssertEqual(
            evaluate(
                left: unloaded(),
                right: unloaded(),
                layout: threeWay(middle: unloaded(), isAutoMergeEligible: true)
            ).autoMerge,
            .disabled(.sideNotLoaded(.left))
        )
        XCTAssertEqual(
            evaluate(
                left: unloaded(),
                layout: threeWay(isAutoMergeEligible: true)
            ).autoMerge,
            .disabled(.sideNotLoaded(.left))
        )
        XCTAssertEqual(
            evaluate(
                layout: threeWay(middle: unloaded(), isAutoMergeEligible: true)
            ).autoMerge,
            .disabled(.sideNotLoaded(.middle))
        )
        XCTAssertEqual(
            evaluate(
                right: unloaded(),
                layout: threeWay(isAutoMergeEligible: true)
            ).autoMerge,
            .disabled(.sideNotLoaded(.right))
        )
    }

    func testAutoMergeRequiresOnlyDestinationEditability() {
        let readOnlySources = evaluate(
            left: clean(editable: false),
            right: clean(editable: false),
            layout: threeWay(isAutoMergeEligible: true)
        )
        XCTAssertEqual(readOnlySources.autoMerge, .enabled)

        let readOnlyDestination = evaluate(
            layout: threeWay(
                middle: dirty(editable: false),
                isAutoMergeEligible: true
            )
        )
        XCTAssertEqual(
            readOnlyDestination.autoMerge,
            .disabled(.destinationNotEditable(.middle))
        )

        let leftDestination = evaluate(
            left: clean(editable: false),
            layout: threeWay(destination: .left, isAutoMergeEligible: true)
        )
        XCTAssertEqual(leftDestination.autoMerge, .disabled(.destinationNotEditable(.left)))
    }

    func testAutoMergeRejectsUnsavedChangesOnEveryPaneInStableOrder() {
        XCTAssertEqual(
            evaluate(
                left: dirty(),
                right: dirty(),
                layout: threeWay(middle: dirty(), isAutoMergeEligible: true)
            ).autoMerge,
            .disabled(.unsavedChanges(.left))
        )
        XCTAssertEqual(
            evaluate(
                right: dirty(),
                layout: threeWay(middle: dirty(), isAutoMergeEligible: true)
            ).autoMerge,
            .disabled(.unsavedChanges(.middle))
        )
        XCTAssertEqual(
            evaluate(
                right: dirty(),
                layout: threeWay(isAutoMergeEligible: true)
            ).autoMerge,
            .disabled(.unsavedChanges(.right))
        )
    }

    func testThreeWayAutoMergeCanTargetAnyEditablePane() {
        for destination in Policy.Side.allCases {
            let commands = evaluate(
                layout: threeWay(
                    destination: destination,
                    isAutoMergeEligible: true
                ))
            XCTAssertEqual(commands.autoMerge, .enabled, "Destination: \(destination)")
        }
    }

    private func evaluate(
        left: Policy.SideState = Policy.SideState(
            isLoaded: true,
            isEditable: true,
            isDirty: false
        ),
        right: Policy.SideState = Policy.SideState(
            isLoaded: true,
            isEditable: true,
            isDirty: false
        ),
        layout: Policy.State.Layout = .twoWay,
        comparisonLifecycle: Policy.ComparisonLifecycle = .currentSuccess,
        hasSelection: Bool = true,
        hasSignificantDifferences: Bool = true
    ) -> Policy.CommandStates {
        Policy.evaluate(
            makeState(
                left: left,
                right: right,
                layout: layout,
                comparisonLifecycle: comparisonLifecycle,
                hasSelection: hasSelection,
                hasSignificantDifferences: hasSignificantDifferences
            ))
    }

    private func makeState(
        left: Policy.SideState = Policy.SideState(
            isLoaded: true,
            isEditable: true,
            isDirty: false
        ),
        right: Policy.SideState = Policy.SideState(
            isLoaded: true,
            isEditable: true,
            isDirty: false
        ),
        layout: Policy.State.Layout = .twoWay,
        comparisonLifecycle: Policy.ComparisonLifecycle = .currentSuccess,
        hasSelection: Bool = true,
        hasSignificantDifferences: Bool = true
    ) -> Policy.State {
        Policy.State(
            left: left,
            right: right,
            layout: layout,
            comparisonLifecycle: comparisonLifecycle,
            hasSelection: hasSelection,
            hasSignificantDifferences: hasSignificantDifferences
        )
    }

    private func threeWay(
        middle: Policy.SideState = Policy.SideState(
            isLoaded: true,
            isEditable: true,
            isDirty: false
        ),
        destination: Policy.Side = .middle,
        isAutoMergeEligible: Bool
    ) -> Policy.State.Layout {
        .threeWay(
            middle: middle,
            autoMergeDestination: destination,
            isAutoMergeEligible: isAutoMergeEligible
        )
    }

    private var wiredCommands: [Policy.Command] {
        [
            .leftToRight,
            .rightToLeft,
            .leftToRightAndAdvance,
            .rightToLeftAndAdvance,
            .copyAllToRight,
            .copyAllToLeft
        ]
    }

    private func commandMatrix(
        leftToRight: Policy.Availability,
        rightToLeft: Policy.Availability,
        saveLeft: Policy.Availability,
        saveMiddle: Policy.Availability,
        saveRight: Policy.Availability,
        autoMerge: Policy.Availability
    ) -> [Policy.Command: Policy.Availability] {
        [
            .leftToRight: leftToRight,
            .rightToLeft: rightToLeft,
            .leftToRightAndAdvance: leftToRight,
            .rightToLeftAndAdvance: rightToLeft,
            .copyAllToRight: leftToRight,
            .copyAllToLeft: rightToLeft,
            .saveLeft: saveLeft,
            .saveMiddle: saveMiddle,
            .saveRight: saveRight,
            .autoMerge: autoMerge
        ]
    }

    private func assertAllCommands(
        _ commands: Policy.CommandStates,
        expected: [Policy.Command: Policy.Availability],
        state: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expected.count, Policy.Command.allCases.count, state, file: file, line: line)
        for command in Policy.Command.allCases {
            guard let expectedAvailability = expected[command] else {
                XCTFail("Missing \(command) expectation for \(state)", file: file, line: line)
                continue
            }
            XCTAssertEqual(
                commands[command],
                expectedAvailability,
                "Execution/enablement mismatch for \(command), \(state)",
                file: file,
                line: line
            )
        }
    }

    private func assertWiredCommands(
        _ commands: Policy.CommandStates,
        equal expected: Policy.Availability,
        state: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertWiredCommands(
            commands,
            expected: Dictionary(uniqueKeysWithValues: wiredCommands.map { ($0, expected) }),
            state: state,
            file: file,
            line: line
        )
    }

    private func assertWiredCommands(
        _ commands: Policy.CommandStates,
        expected: [Policy.Command: Policy.Availability],
        state: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expected.count, wiredCommands.count, state, file: file, line: line)
        for command in wiredCommands {
            guard let expectedAvailability = expected[command] else {
                XCTFail("Missing \(command) expectation for \(state)", file: file, line: line)
                continue
            }
            let availability = commands[command]
            XCTAssertEqual(availability, expectedAvailability, state, file: file, line: line)
            XCTAssertEqual(
                availability.isEnabled,
                expectedAvailability == .enabled,
                "Execution/enablement mismatch for \(command), \(state)",
                file: file,
                line: line
            )
        }
    }

    private func clean(editable: Bool = true) -> Policy.SideState {
        Policy.SideState(isLoaded: true, isEditable: editable, isDirty: false)
    }

    private func dirty(editable: Bool = true) -> Policy.SideState {
        Policy.SideState(isLoaded: true, isEditable: editable, isDirty: true)
    }

    private func unloaded() -> Policy.SideState {
        Policy.SideState(isLoaded: false, isEditable: false, isDirty: false)
    }

    private func disabledReason(_ availability: Policy.Availability) -> Policy.DisabledReason? {
        guard case .disabled(let reason) = availability else { return nil }
        return reason
    }
}
