import MacMergeCore
import XCTest

final class ThreeWayDifferenceNavigationTests: XCTestCase {
    typealias Difference = ThreeWayDifferenceNavigationDifference
    typealias DifferenceType = ThreeWayDifferenceType
    typealias NavigationError = ThreeWayDifferenceNavigationError
    typealias NavigationIndex = ThreeWayDifferenceNavigationIndex

    func testAllSixDifferenceTypesExposeExpectedPaneSemantics() {
        let pairExpectations: [(ThreeWayDifferencePanePair, ThreeWayDifferencePane, ThreeWayDifferencePane)] = [
            (.leftAndMiddle, .left, .middle),
            (.leftAndRight, .left, .right),
            (.middleAndRight, .middle, .right)
        ]
        XCTAssertEqual(ThreeWayDifferencePane.allCases, [.left, .middle, .right])
        XCTAssertEqual(ThreeWayDifferencePanePair.allCases.count, 3)
        for (pair, first, second) in pairExpectations {
            XCTAssertEqual(pair.firstPane, first)
            XCTAssertEqual(pair.secondPane, second)
            for pane in ThreeWayDifferencePane.allCases {
                XCTAssertEqual(pair.contains(pane), pane == first || pane == second)
            }
        }

        let oneSidedExpectations: [(ThreeWayOneSidedDifferenceType, ThreeWayDifferencePane)] = [
            (.leftOnly, .left),
            (.middleOnly, .middle),
            (.rightOnly, .right)
        ]
        XCTAssertEqual(ThreeWayOneSidedDifferenceType.allCases.count, 3)
        for (type, pane) in oneSidedExpectations {
            XCTAssertEqual(type.pane, pane)
        }
        XCTAssertEqual(Set(allTypes).count, 6)
    }

    func testOrderingUsesRowsThenTypeAndIsDeterministicAcrossInputOrder() throws {
        let input = [
            difference(15, .oneSided(.rightOnly), 10..<12),
            difference(13, .oneSided(.leftOnly), 10..<12),
            difference(2, .panePair(.leftAndRight), 0..<3),
            difference(12, .panePair(.middleAndRight), 10..<12),
            difference(90, .oneSided(.rightOnly), 20..<21),
            difference(10, .panePair(.leftAndMiddle), 10..<12),
            difference(1, .panePair(.leftAndMiddle), 0..<4),
            difference(14, .oneSided(.middleOnly), 10..<12),
            difference(11, .panePair(.leftAndRight), 10..<12)
        ]
        let permutations = [
            input,
            Array(input.reversed()),
            Array(input[3...] + input[..<3])
        ]
        let indices = try permutations.map {
            try NavigationIndex(generation: 41, differences: $0)
        }
        let expectedSourceIDs: [UInt64] = [2, 1, 10, 11, 12, 13, 14, 15, 90]
        let expectedTypes: [DifferenceType] = [
            .panePair(.leftAndRight),
            .panePair(.leftAndMiddle),
            .panePair(.leftAndMiddle),
            .panePair(.leftAndRight),
            .panePair(.middleAndRight),
            .oneSided(.leftOnly),
            .oneSided(.middleOnly),
            .oneSided(.rightOnly),
            .oneSided(.rightOnly)
        ]

        for index in indices {
            XCTAssertEqual(index.generation, 41)
            XCTAssertEqual(index.count, input.count)
            XCTAssertEqual(index.targets.map(\.index), Array(input.indices))
            XCTAssertEqual(index.targets.map(\.sourceID.rawValue), expectedSourceIDs)
            XCTAssertEqual(index.targets.map(\.type), expectedTypes)
            XCTAssertEqual(index.differences, index.targets)
            XCTAssertEqual(index.first, index.targets.first)
            XCTAssertEqual(index.last, index.targets.last)
            for target in index.targets {
                XCTAssertEqual(index.target(withID: target.id), target)
                XCTAssertEqual(target.generation, 41)
                XCTAssertEqual(target.firstRow, target.rowRange.lowerBound)
                XCTAssertEqual(target.lastRow, target.rowRange.upperBound - 1)
                XCTAssertTrue(target.contains(row: target.firstRow))
                XCTAssertTrue(target.contains(row: target.lastRow))
                XCTAssertFalse(target.contains(row: target.rowRange.upperBound))
            }
        }
        XCTAssertTrue(indices.dropFirst().allSatisfy { $0 == indices[0] })

        let context = ThreeWayDifferenceNavigationContext(generation: 41, cursorRow: 11)
        let expectedResolutions = try ThreeWayDifferenceNavigationCommand.allCases.map {
            try indices[0].resolve($0, in: context)
        }
        for index in indices.dropFirst() {
            let resolutions = try ThreeWayDifferenceNavigationCommand.allCases.map {
                try index.resolve($0, in: context)
            }
            XCTAssertEqual(resolutions, expectedResolutions)
        }
    }

    func testEveryDifferenceTypeHasAnExactFilterAndCombinedFiltersPreserveOrder() throws {
        let differences = allTypes.enumerated().map { offset, type in
            difference(UInt64(offset + 1), type, (offset * 2)..<(offset * 2 + 1))
        }
        let index = try NavigationIndex(generation: 2, differences: differences)

        XCTAssertEqual(try index.targets(matching: .all), index.targets)
        for type in allTypes {
            let filter = filter(for: type)
            XCTAssertEqual(filter.types, [type])
            XCTAssertEqual(try index.targets(matching: filter).map(\.type), [type])
        }

        let combinedTypes: Set<DifferenceType> = [
            .panePair(.leftAndRight), .oneSided(.leftOnly), .oneSided(.rightOnly)
        ]
        let combined = try ThreeWayDifferenceNavigationFilter(types: combinedTypes)
        XCTAssertEqual(
            try index.targets(matching: combined).map(\.type),
            index.targets.map(\.type).filter(combinedTypes.contains)
        )
        assertNavigationError(.emptyFilter) {
            _ = try ThreeWayDifferenceNavigationFilter(types: [])
        }
    }

    func testFilteredFirstPreviousNextLastAndStatesUseOnlyMatchingTargets() throws {
        let includedType = DifferenceType.oneSided(.rightOnly)
        let index = try NavigationIndex(
            generation: 3,
            differences: [
                difference(1, .panePair(.leftAndMiddle), 0..<1),
                difference(2, includedType, 10..<11),
                difference(3, .panePair(.leftAndMiddle), 20..<21),
                difference(4, includedType, 30..<31),
                difference(5, .panePair(.leftAndMiddle), 40..<41)
            ]
        )
        let filter = ThreeWayDifferenceNavigationFilter.oneSided(.rightOnly)
        let context = ThreeWayDifferenceNavigationContext(
            generation: 3,
            selectedTarget: index.targets[2],
            currentTarget: index.targets[1]
        )

        XCTAssertEqual(try index.first(in: context, matching: filter), index.targets[1])
        XCTAssertEqual(try index.previous(in: context, matching: filter), index.targets[1])
        XCTAssertEqual(try index.next(in: context, matching: filter), index.targets[3])
        XCTAssertEqual(try index.last(in: context, matching: filter), index.targets[3])

        let stateContext = ThreeWayDifferenceNavigationContext(
            generation: 3,
            selectedTarget: index.targets[1]
        )
        let states = try index.commandStates(in: stateContext, matching: filter)
        XCTAssertEqual(
            states,
            ThreeWayDifferenceNavigationCommandStates(
                first: true,
                current: true,
                previous: false,
                next: true,
                last: true
            )
        )
    }

    func testAllFiveCommandsResolveExactTargetsAndPublishMatchingStates() throws {
        let index = try navigationWithFourTargets(generation: 7)
        let first = index.targets[0]
        let selected = index.targets[1]
        let next = index.targets[2]
        let last = index.targets[3]
        let context = ThreeWayDifferenceNavigationContext(
            generation: 7,
            selectedTarget: selected,
            currentTarget: first,
            cursorRow: last.firstRow
        )
        let expectations: [(ThreeWayDifferenceNavigationCommand, ThreeWayDifferenceNavigationTarget)] = [
            (.first, first),
            (.current, selected),
            (.previous, first),
            (.next, next),
            (.last, last)
        ]

        XCTAssertEqual(
            ThreeWayDifferenceNavigationCommand.allCases,
            [.first, .current, .previous, .next, .last]
        )
        for (command, expected) in expectations {
            let resolution = try index.resolve(command, in: context)
            XCTAssertEqual(resolution.command, command)
            XCTAssertEqual(resolution.expectedGeneration, 7)
            XCTAssertEqual(resolution.target, expected)
            XCTAssertTrue(resolution.canExecute)
            XCTAssertTrue(resolution.isEnabled)
        }
        XCTAssertEqual(try index.first(in: context), first)
        XCTAssertEqual(try index.current(in: context), selected)
        XCTAssertEqual(try index.previous(in: context), first)
        XCTAssertEqual(try index.next(in: context), next)
        XCTAssertEqual(try index.last(in: context), last)

        let states = try index.commandStates(in: context)
        XCTAssertEqual(
            states,
            ThreeWayDifferenceNavigationCommandStates(
                first: true,
                current: true,
                previous: true,
                next: true,
                last: true
            )
        )
        for command in ThreeWayDifferenceNavigationCommand.allCases {
            XCTAssertEqual(states[command], true, "Command: \(command)")
        }
    }

    func testMixedCommandStatePropertiesAndSubscriptsAgree() throws {
        let index = try navigationWithFourTargets(generation: 7)
        let context = ThreeWayDifferenceNavigationContext(
            generation: 7,
            selectedTarget: index.targets[0]
        )

        let states = try index.commandStates(in: context)
        XCTAssertTrue(states.first)
        XCTAssertTrue(states.current)
        XCTAssertFalse(states.previous)
        XCTAssertTrue(states.next)
        XCTAssertTrue(states.last)
        XCTAssertEqual(states[.first], states.first)
        XCTAssertEqual(states[.current], states.current)
        XCTAssertEqual(states[.previous], states.previous)
        XCTAssertEqual(states[.next], states.next)
        XCTAssertEqual(states[.last], states.last)
    }

    func testCurrentFallsBackFromSelectionToCurrentTargetThenCursor() throws {
        let types: [DifferenceType] = [
            .panePair(.leftAndMiddle),
            .panePair(.leftAndRight),
            .panePair(.middleAndRight),
            .oneSided(.leftOnly)
        ]
        let index = try NavigationIndex(
            generation: 8,
            differences: types.enumerated().map { offset, type in
                difference(UInt64(offset), type, (offset * 10)..<(offset * 10 + 3))
            }
        )
        let selected = index.targets[0]
        let current = index.targets[1]
        let cursorTarget = index.targets[2]

        XCTAssertEqual(
            try index.current(
                in: ThreeWayDifferenceNavigationContext(
                    generation: 8,
                    selectedTarget: selected,
                    currentTarget: current,
                    cursorRow: cursorTarget.firstRow
                )
            ),
            selected
        )
        XCTAssertEqual(
            try index.current(
                in: ThreeWayDifferenceNavigationContext(
                    generation: 8,
                    selectedTarget: nil,
                    currentTarget: current,
                    cursorRow: cursorTarget.firstRow
                )
            ),
            current
        )
        XCTAssertEqual(
            try index.current(
                in: ThreeWayDifferenceNavigationContext(
                    generation: 8,
                    cursorRow: cursorTarget.firstRow + 1
                )
            ),
            cursorTarget
        )
        XCTAssertEqual(
            try index.current(
                in: ThreeWayDifferenceNavigationContext(
                    generation: 8,
                    selectedTarget: selected,
                    currentTarget: current,
                    cursorRow: cursorTarget.firstRow
                ),
                matching: .panePair(.leftAndRight)
            ),
            current
        )
        XCTAssertEqual(
            try index.current(
                in: ThreeWayDifferenceNavigationContext(
                    generation: 8,
                    selectedTarget: selected,
                    currentTarget: current,
                    cursorRow: cursorTarget.firstRow
                ),
                matching: .panePair(.middleAndRight)
            ),
            cursorTarget
        )
        XCTAssertNil(
            try index.current(
                in: ThreeWayDifferenceNavigationContext(generation: 8, cursorRow: 15)
            )
        )
        XCTAssertNil(
            try index.current(in: ThreeWayDifferenceNavigationContext(generation: 8))
        )
    }

    func testVisibleAndOffscreenSelectionChooseDifferentAdjacentOrigins() throws {
        let index = try navigationWithFourTargets(generation: 9)
        let selected = index.targets[2]
        let current = index.targets[1]
        let visible = ThreeWayDifferenceNavigationContext(
            generation: 9,
            selectedTarget: selected,
            selectionVisibility: .visible,
            currentTarget: current,
            cursorRow: 25
        )
        let offscreen = ThreeWayDifferenceNavigationContext(
            generation: 9,
            selectedTarget: selected,
            selectionVisibility: .offscreen,
            currentTarget: current,
            cursorRow: 25
        )

        XCTAssertEqual(try index.previous(in: visible), index.targets[1])
        XCTAssertEqual(try index.next(in: visible), index.targets[3])
        XCTAssertEqual(try index.previous(in: offscreen), index.targets[0])
        XCTAssertEqual(try index.next(in: offscreen), index.targets[2])
        XCTAssertEqual(try index.current(in: offscreen), selected)

        let cursorFallback = ThreeWayDifferenceNavigationContext(
            generation: 9,
            selectedTarget: selected,
            selectionVisibility: .offscreen,
            cursorRow: 25
        )
        XCTAssertEqual(try index.previous(in: cursorFallback), index.targets[1])
        XCTAssertEqual(try index.next(in: cursorFallback), index.targets[2])

        let endFallback = ThreeWayDifferenceNavigationContext(
            generation: 9,
            selectedTarget: selected,
            selectionVisibility: .offscreen
        )
        XCTAssertEqual(try index.previous(in: endFallback), index.last)
        XCTAssertEqual(try index.next(in: endFallback), index.first)
    }

    func testPreviousAndNextDoNotWrapAndHonorCursorBoundaries() throws {
        let index = try NavigationIndex(
            generation: 10,
            differences: [
                difference(1, .panePair(.leftAndMiddle), 0..<1),
                difference(2, .panePair(.leftAndMiddle), 5..<8),
                difference(3, .panePair(.leftAndMiddle), 10..<11)
            ]
        )
        let first = index.targets[0]
        let middle = index.targets[1]
        let last = index.targets[2]

        XCTAssertNil(
            try index.previous(
                in: ThreeWayDifferenceNavigationContext(
                    generation: 10,
                    selectedTarget: first,
                    cursorRow: .max
                )
            )
        )
        XCTAssertNil(
            try index.next(
                in: ThreeWayDifferenceNavigationContext(
                    generation: 10,
                    selectedTarget: last,
                    cursorRow: .min
                )
            )
        )
        XCTAssertEqual(
            try index.next(
                in: ThreeWayDifferenceNavigationContext(generation: 10, cursorRow: .min)
            ),
            first
        )
        XCTAssertNil(
            try index.previous(
                in: ThreeWayDifferenceNavigationContext(generation: 10, cursorRow: .min)
            )
        )
        XCTAssertNil(
            try index.next(
                in: ThreeWayDifferenceNavigationContext(generation: 10, cursorRow: .max)
            )
        )
        XCTAssertEqual(
            try index.previous(
                in: ThreeWayDifferenceNavigationContext(generation: 10, cursorRow: .max)
            ),
            last
        )
        XCTAssertEqual(
            try index.next(
                in: ThreeWayDifferenceNavigationContext(generation: 10, cursorRow: 5)
            ),
            middle
        )
        XCTAssertEqual(
            try index.previous(
                in: ThreeWayDifferenceNavigationContext(generation: 10, cursorRow: 5)
            ),
            first
        )
        XCTAssertEqual(
            try index.previous(
                in: ThreeWayDifferenceNavigationContext(generation: 10, cursorRow: 7)
            ),
            middle
        )
        XCTAssertEqual(
            try index.next(
                in: ThreeWayDifferenceNavigationContext(generation: 10, cursorRow: 7)
            ),
            last
        )
    }

    func testEmptyIndexDisablesEveryCommandWithoutConsumingWork() throws {
        let limits = ThreeWayDifferenceNavigationLimits(
            maximumRows: 0,
            maximumDifferences: 0,
            maximumWork: 0,
            cancellationCheckInterval: 1
        )
        let index = try NavigationIndex(generation: .max, differences: [], limits: limits)
        let context = ThreeWayDifferenceNavigationContext(generation: .max)

        XCTAssertTrue(index.isEmpty)
        XCTAssertEqual(index.count, 0)
        XCTAssertNil(index.first)
        XCTAssertNil(index.last)
        XCTAssertEqual(try index.targets(matching: .all), [])
        for command in ThreeWayDifferenceNavigationCommand.allCases {
            let resolution = try index.resolve(command, in: context)
            XCTAssertEqual(resolution.command, command)
            XCTAssertEqual(resolution.expectedGeneration, .max)
            XCTAssertNil(resolution.target)
            XCTAssertFalse(resolution.canExecute)
            XCTAssertFalse(resolution.isEnabled)
        }
        XCTAssertEqual(
            try index.commandStates(in: context),
            ThreeWayDifferenceNavigationCommandStates(
                first: false,
                current: false,
                previous: false,
                next: false,
                last: false
            )
        )
    }

    func testDuplicateIDsInvalidRangesAndSameTypeOverlapAreRejected() throws {
        assertNavigationError(.duplicateDifferenceID(.init(rawValue: 42))) {
            _ = try NavigationIndex(
                generation: 1,
                differences: [
                    difference(42, .panePair(.leftAndMiddle), 1..<2),
                    difference(42, .oneSided(.rightOnly), 4..<5)
                ]
            )
        }

        let limits = ThreeWayDifferenceNavigationLimits(maximumRows: 10)
        let descendingRange: Range<Int> = unsafeBitCast(
            (lowerBound: 7, upperBound: 4),
            to: Range<Int>.self
        )
        let malformed = [
            difference(1, .oneSided(.leftOnly), (-1)..<1),
            difference(2, .oneSided(.middleOnly), 2..<2),
            difference(3, .oneSided(.rightOnly), 9..<11),
            difference(4, .panePair(.leftAndRight), descendingRange)
        ]
        for difference in malformed {
            assertNavigationError(
                .invalidRowRange(
                    id: difference.id,
                    range: difference.rowRange,
                    maximumRows: 10
                )
            ) {
                _ = try NavigationIndex(
                    generation: 1,
                    differences: [difference],
                    limits: limits
                )
            }
        }

        let overlapping = [
            difference(2, .panePair(.leftAndMiddle), 3..<6),
            difference(1, .panePair(.leftAndMiddle), 1..<4)
        ]
        assertNavigationError(
            .overlappingDifferences(
                type: .panePair(.leftAndMiddle),
                first: .init(rawValue: 1),
                second: .init(rawValue: 2)
            )
        ) {
            _ = try NavigationIndex(generation: 1, differences: overlapping)
        }

        XCTAssertNoThrow(
            try NavigationIndex(
                generation: 1,
                differences: [
                    difference(1, .oneSided(.leftOnly), 1..<4),
                    difference(2, .oneSided(.leftOnly), 4..<6)
                ]
            )
        )
        XCTAssertNoThrow(
            try NavigationIndex(
                generation: 1,
                differences: [
                    difference(1, .oneSided(.leftOnly), 1..<4),
                    difference(2, .oneSided(.rightOnly), 2..<3)
                ]
            )
        )
    }

    func testLimitsRejectEveryOutOfRangeFieldAndHonorExactCaps() throws {
        let defaults = ThreeWayDifferenceNavigationLimits.default
        XCTAssertEqual(
            defaults.maximumRows,
            ThreeWayDifferenceNavigationLimits.maximumSupportedRows
        )
        XCTAssertEqual(
            defaults.maximumDifferences,
            ThreeWayDifferenceNavigationLimits.maximumSupportedDifferences
        )
        XCTAssertEqual(
            defaults.maximumWork,
            ThreeWayDifferenceNavigationLimits.maximumSupportedWork
        )
        XCTAssertEqual(defaults.cancellationCheckInterval, 1_024)

        let invalidLimits = [
            ThreeWayDifferenceNavigationLimits(maximumRows: -1),
            ThreeWayDifferenceNavigationLimits(
                maximumRows: ThreeWayDifferenceNavigationLimits.maximumSupportedRows + 1
            ),
            ThreeWayDifferenceNavigationLimits(maximumDifferences: -1),
            ThreeWayDifferenceNavigationLimits(
                maximumDifferences:
                    ThreeWayDifferenceNavigationLimits.maximumSupportedDifferences + 1
            ),
            ThreeWayDifferenceNavigationLimits(maximumWork: -1),
            ThreeWayDifferenceNavigationLimits(
                maximumWork: ThreeWayDifferenceNavigationLimits.maximumSupportedWork + 1
            ),
            ThreeWayDifferenceNavigationLimits(cancellationCheckInterval: 0),
            ThreeWayDifferenceNavigationLimits(
                cancellationCheckInterval:
                    ThreeWayDifferenceNavigationLimits.maximumCancellationCheckInterval + 1
            )
        ]
        for limits in invalidLimits {
            assertNavigationError(.invalidLimits) {
                _ = try NavigationIndex(generation: 1, differences: [], limits: limits)
            }
        }

        let exactLimits = ThreeWayDifferenceNavigationLimits(
            maximumRows: 2,
            maximumDifferences: 1,
            maximumWork: 2,
            cancellationCheckInterval: 1
        )
        let exact = try NavigationIndex(
            generation: 1,
            differences: [difference(1, .oneSided(.rightOnly), 1..<2)],
            limits: exactLimits
        )
        XCTAssertEqual(exact.count, 1)

        let maximumCancellationInterval = ThreeWayDifferenceNavigationLimits(
            maximumRows: 1,
            maximumDifferences: 1,
            maximumWork: 2,
            cancellationCheckInterval:
                ThreeWayDifferenceNavigationLimits.maximumCancellationCheckInterval
        )
        XCTAssertEqual(
            try NavigationIndex(
                generation: 1,
                differences: [difference(2, .oneSided(.leftOnly), 0..<1)],
                limits: maximumCancellationInterval
            ).count,
            1
        )
        assertNavigationError(.tooManyDifferences(maximum: 1)) {
            _ = try NavigationIndex(
                generation: 1,
                differences: [
                    difference(1, .oneSided(.leftOnly), 0..<1),
                    difference(2, .oneSided(.rightOnly), 1..<2)
                ],
                limits: exactLimits
            )
        }
    }

    func testWorkBudgetAppliesToConstructionAndWholeCommandStateResolution() throws {
        let oneDifference = [difference(1, .panePair(.leftAndMiddle), 0..<1)]
        assertNavigationError(.workLimitExceeded(maximumWork: 1)) {
            _ = try NavigationIndex(
                generation: 4,
                differences: oneDifference,
                limits: ThreeWayDifferenceNavigationLimits(
                    maximumRows: 1,
                    maximumDifferences: 1,
                    maximumWork: 1,
                    cancellationCheckInterval: 1
                )
            )
        }

        let limits = ThreeWayDifferenceNavigationLimits(
            maximumRows: 1,
            maximumDifferences: 1,
            maximumWork: 2,
            cancellationCheckInterval: 1
        )
        let index = try NavigationIndex(
            generation: 4,
            differences: oneDifference,
            limits: limits
        )
        let context = ThreeWayDifferenceNavigationContext(generation: 4)
        XCTAssertEqual(try index.targets(matching: .all), index.targets)
        for command in ThreeWayDifferenceNavigationCommand.allCases {
            XCTAssertNoThrow(try index.resolve(command, in: context), "Command: \(command)")
        }
        assertNavigationError(.workLimitExceeded(maximumWork: 2)) {
            _ = try index.commandStates(in: context)
        }
    }

    func testConstructionSortingUsesExactWorkBudgetForMultipleTargets() throws {
        let differences = [
            difference(40, .oneSided(.rightOnly), 3..<4),
            difference(30, .oneSided(.middleOnly), 2..<3),
            difference(20, .oneSided(.leftOnly), 1..<2),
            difference(10, .panePair(.leftAndMiddle), 0..<1)
        ]
        let exactWork = 24
        let exactLimits = ThreeWayDifferenceNavigationLimits(
            maximumRows: 4,
            maximumDifferences: differences.count,
            maximumWork: exactWork,
            cancellationCheckInterval: 1
        )

        let index = try NavigationIndex(
            generation: 5,
            differences: differences,
            limits: exactLimits
        )
        XCTAssertEqual(index.targets.map(\.sourceID.rawValue), [10, 20, 30, 40])

        let insufficientWork = exactWork - 1
        assertNavigationError(.workLimitExceeded(maximumWork: insufficientWork)) {
            _ = try NavigationIndex(
                generation: 5,
                differences: differences,
                limits: ThreeWayDifferenceNavigationLimits(
                    maximumRows: 4,
                    maximumDifferences: differences.count,
                    maximumWork: insufficientWork,
                    cancellationCheckInterval: 1
                )
            )
        }
    }

    func testCommandStateQueryUsesExactWorkBudgetIncludingBothIdentities() throws {
        let differences = [
            difference(1, .panePair(.leftAndMiddle), 0..<1),
            difference(2, .oneSided(.rightOnly), 1..<2)
        ]
        let exactWork = 23
        let exactIndex = try NavigationIndex(
            generation: 6,
            differences: differences,
            limits: ThreeWayDifferenceNavigationLimits(
                maximumRows: 2,
                maximumDifferences: differences.count,
                maximumWork: exactWork,
                cancellationCheckInterval: 1
            )
        )
        let context = ThreeWayDifferenceNavigationContext(
            generation: 6,
            selectedTarget: exactIndex.targets[0],
            currentTarget: exactIndex.targets[1]
        )
        XCTAssertEqual(context.selectedDifferenceID, exactIndex.targets[0].id)
        XCTAssertEqual(context.currentDifferenceID, exactIndex.targets[1].id)
        XCTAssertEqual(
            try exactIndex.commandStates(in: context),
            ThreeWayDifferenceNavigationCommandStates(
                first: true,
                current: true,
                previous: false,
                next: true,
                last: true
            )
        )

        let insufficientWork = exactWork - 1
        let insufficientIndex = try NavigationIndex(
            generation: 6,
            differences: differences,
            limits: ThreeWayDifferenceNavigationLimits(
                maximumRows: 2,
                maximumDifferences: differences.count,
                maximumWork: insufficientWork,
                cancellationCheckInterval: 1
            )
        )
        assertNavigationError(.workLimitExceeded(maximumWork: insufficientWork)) {
            _ = try insufficientIndex.commandStates(in: context)
        }
    }

    func testContextAndTargetGenerationMismatchesAreRejected() throws {
        let index = try navigationWithFourTargets(generation: 12)
        for command in ThreeWayDifferenceNavigationCommand.allCases {
            assertNavigationError(.staleGeneration(expected: 12, actual: 11)) {
                _ = try index.resolve(
                    command,
                    in: ThreeWayDifferenceNavigationContext(generation: 11)
                )
            }
        }
        assertNavigationError(.staleGeneration(expected: 12, actual: 11)) {
            _ = try index.commandStates(
                in: ThreeWayDifferenceNavigationContext(generation: 11)
            )
        }

        let oldIndex = try navigationWithFourTargets(generation: 11)
        let oldTarget = oldIndex.targets[1]
        XCTAssertNil(index.target(withID: oldTarget.id))
        let selectedContext = ThreeWayDifferenceNavigationContext(
            generation: 12,
            selectedTarget: oldTarget
        )
        let currentContext = ThreeWayDifferenceNavigationContext(
            generation: 12,
            selectedTarget: nil,
            currentTarget: oldTarget
        )
        for context in [selectedContext, currentContext] {
            for command in ThreeWayDifferenceNavigationCommand.allCases {
                assertNavigationError(.staleGeneration(expected: 12, actual: 11)) {
                    _ = try index.resolve(command, in: context)
                }
            }
            assertNavigationError(.staleGeneration(expected: 12, actual: 11)) {
                _ = try index.commandStates(in: context)
            }
        }
    }

    func testChangedOrMissingIdentityIsRejectedForSelectionAndCurrentRoles() throws {
        let original = try NavigationIndex(
            generation: 13,
            differences: [difference(7, .panePair(.leftAndMiddle), 2..<4)]
        )
        let originalTarget = try XCTUnwrap(original.first)
        let changedFixtures = [
            [difference(7, .panePair(.leftAndRight), 2..<4)],
            [difference(7, .panePair(.leftAndMiddle), 3..<5)],
            [difference(8, .panePair(.leftAndMiddle), 2..<4)]
        ]

        for differences in changedFixtures {
            let rebuilt = try NavigationIndex(generation: 13, differences: differences)
            XCTAssertNil(rebuilt.target(withID: originalTarget.id))
            let selectedContext = ThreeWayDifferenceNavigationContext(
                generation: 13,
                selectedTarget: originalTarget,
                cursorRow: 100
            )
            let currentContext = ThreeWayDifferenceNavigationContext(
                generation: 13,
                selectedTarget: nil,
                currentTarget: originalTarget,
                cursorRow: 100
            )
            for command in ThreeWayDifferenceNavigationCommand.allCases {
                assertNavigationError(.staleIdentity(role: .selected, id: originalTarget.id)) {
                    _ = try rebuilt.resolve(command, in: selectedContext)
                }
                assertNavigationError(.staleIdentity(role: .current, id: originalTarget.id)) {
                    _ = try rebuilt.resolve(command, in: currentContext)
                }
            }
            assertNavigationError(.staleIdentity(role: .selected, id: originalTarget.id)) {
                _ = try rebuilt.commandStates(in: selectedContext)
            }
            assertNavigationError(.staleIdentity(role: .current, id: originalTarget.id)) {
                _ = try rebuilt.commandStates(in: currentContext)
            }
        }
    }

    func testMissingSourceAboveLookupEndIsRejectedForSelectionAndCurrentRoles() throws {
        let source = try NavigationIndex(
            generation: 15,
            differences: [difference(99, .panePair(.leftAndMiddle), 4..<5)]
        )
        let missingTarget = try XCTUnwrap(source.first)
        let rebuilt = try NavigationIndex(
            generation: 15,
            differences: [
                difference(1, .panePair(.leftAndMiddle), 0..<1),
                difference(2, .oneSided(.rightOnly), 2..<3)
            ]
        )
        XCTAssertNil(rebuilt.target(withID: missingTarget.id))

        let selectedContext = ThreeWayDifferenceNavigationContext(
            generation: 15,
            selectedTarget: missingTarget
        )
        for command in ThreeWayDifferenceNavigationCommand.allCases {
            assertNavigationError(.staleIdentity(role: .selected, id: missingTarget.id)) {
                _ = try rebuilt.resolve(command, in: selectedContext)
            }
        }
        assertNavigationError(.staleIdentity(role: .selected, id: missingTarget.id)) {
            _ = try rebuilt.commandStates(in: selectedContext)
        }

        let currentContext = ThreeWayDifferenceNavigationContext(
            generation: 15,
            selectedTarget: nil,
            currentTarget: missingTarget
        )
        for command in ThreeWayDifferenceNavigationCommand.allCases {
            assertNavigationError(.staleIdentity(role: .current, id: missingTarget.id)) {
                _ = try rebuilt.resolve(command, in: currentContext)
            }
        }
        assertNavigationError(.staleIdentity(role: .current, id: missingTarget.id)) {
            _ = try rebuilt.commandStates(in: currentContext)
        }
    }

    func testPreexistingCancellationStopsConstructionAndEveryFallibleQuery() async throws {
        let differences = [difference(1, .oneSided(.leftOnly), 0..<1)]
        let limits = ThreeWayDifferenceNavigationLimits(
            maximumRows: 1,
            maximumDifferences: 1,
            maximumWork: 10,
            cancellationCheckInterval: 1
        )
        let index = try NavigationIndex(
            generation: 14,
            differences: differences,
            limits: limits
        )
        let context = ThreeWayDifferenceNavigationContext(generation: 14)

        let errors = await Task { () -> [NavigationError?] in
            withUnsafeCurrentTask { $0?.cancel() }
            var errors: [NavigationError?] = []
            do {
                _ = try NavigationIndex(
                    generation: 14,
                    differences: differences,
                    limits: limits
                )
                errors.append(nil)
            } catch {
                errors.append(error as? NavigationError)
            }
            do {
                _ = try index.targets(matching: .all)
                errors.append(nil)
            } catch {
                errors.append(error as? NavigationError)
            }
            do {
                _ = try index.resolve(.first, in: context)
                errors.append(nil)
            } catch {
                errors.append(error as? NavigationError)
            }
            do {
                _ = try index.commandStates(in: context)
                errors.append(nil)
            } catch {
                errors.append(error as? NavigationError)
            }
            return errors
        }.value

        XCTAssertEqual(errors, [.cancelled, .cancelled, .cancelled, .cancelled])
    }

    func testCancellationObservedOnlyByFinishStillCancelsQuery() async throws {
        let limits = ThreeWayDifferenceNavigationLimits(
            maximumRows: 1,
            maximumDifferences: 1,
            maximumWork: 2,
            cancellationCheckInterval:
                ThreeWayDifferenceNavigationLimits.maximumCancellationCheckInterval
        )
        let index = try NavigationIndex(
            generation: 16,
            differences: [difference(1, .oneSided(.leftOnly), 0..<1)],
            limits: limits
        )

        let outcome = await Task.detached { [index] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try index.targets(matching: .all)
                return NavigationCancellationOutcome.succeeded
            } catch let error as NavigationError where error == .cancelled {
                return NavigationCancellationOutcome.cancelled
            } catch {
                return NavigationCancellationOutcome.failed(String(describing: error))
            }
        }.value

        assertCancelled(outcome, message: "Finish-only cancellation was not observed")
    }

    func testMidOperationCancellationStopsConstruction() async {
        let count = 262_144
        let differences = (0..<count).reversed().map { row in
            Difference(
                id: UInt64(row),
                type: .panePair(.leftAndMiddle),
                rowRange: row..<(row + 1)
            )
        }
        let limits = ThreeWayDifferenceNavigationLimits(
            maximumRows: count,
            maximumDifferences: count,
            maximumWork: ThreeWayDifferenceNavigationLimits.maximumSupportedWork,
            cancellationCheckInterval: 1_024
        )
        let gate = NavigationCancellationGate()
        let task = Task.detached { [differences, limits] in
            await gate.markStarted()
            do {
                _ = try NavigationIndex(
                    generation: 17,
                    differences: differences,
                    limits: limits
                )
                return NavigationCancellationOutcome.succeeded
            } catch let error as NavigationError where error == .cancelled {
                return NavigationCancellationOutcome.cancelled
            } catch {
                return NavigationCancellationOutcome.failed(String(describing: error))
            }
        }

        guard await gate.waitUntilStarted(timeout: .seconds(5)) else {
            task.cancel()
            XCTFail("Construction did not start")
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
        task.cancel()
        assertCancelled(
            await task.value,
            message: "Mid-operation construction cancellation was not observed"
        )
    }

    private var allTypes: [DifferenceType] {
        [
            .panePair(.leftAndMiddle),
            .panePair(.leftAndRight),
            .panePair(.middleAndRight),
            .oneSided(.leftOnly),
            .oneSided(.middleOnly),
            .oneSided(.rightOnly)
        ]
    }

    private func difference(
        _ id: UInt64,
        _ type: DifferenceType,
        _ rowRange: Range<Int>
    ) -> Difference {
        Difference(id: id, type: type, rowRange: rowRange)
    }

    private func filter(for type: DifferenceType) -> ThreeWayDifferenceNavigationFilter {
        switch type {
        case .panePair(let pair):
            .panePair(pair)
        case .oneSided(let oneSided):
            .oneSided(oneSided)
        }
    }

    private func navigationWithFourTargets(generation: UInt64) throws -> NavigationIndex {
        try NavigationIndex(
            generation: generation,
            differences: [
                difference(1, .panePair(.leftAndMiddle), 10..<12),
                difference(2, .panePair(.leftAndMiddle), 20..<22),
                difference(3, .panePair(.leftAndMiddle), 30..<32),
                difference(4, .panePair(.leftAndMiddle), 40..<42)
            ]
        )
    }

    private func assertNavigationError(
        _ expected: NavigationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? NavigationError, expected, file: file, line: line)
        }
    }

    private func assertCancelled(
        _ outcome: NavigationCancellationOutcome,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch outcome {
        case .cancelled:
            break
        case .succeeded:
            XCTFail(message, file: file, line: line)
        case .failed(let description):
            XCTFail("Unexpected cancellation error: \(description)", file: file, line: line)
        }
    }
}

private enum NavigationCancellationOutcome: Sendable {
    case succeeded
    case cancelled
    case failed(String)
}

private actor NavigationCancellationGate {
    private var started = false

    func markStarted() {
        started = true
    }

    func waitUntilStarted(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !started, clock.now < deadline {
            await Task.yield()
        }
        return started
    }
}
