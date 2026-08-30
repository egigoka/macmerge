import Foundation
import MacMergeCore
import XCTest

final class ToolbarOverflowPlanTests: XCTestCase {
    private typealias Command = ToolbarOverflowPlan.Command
    private typealias Customization = ToolbarOverflowPlan.Customization
    private typealias Item = ToolbarOverflowPlan.Item
    private typealias Limits = ToolbarOverflowPlan.Limits
    private typealias Size = ToolbarOverflowPlan.Size
    private typealias Widths = ToolbarOverflowPlan.Widths

    func testAllSizesExposeExactDimensionsWidthsAndConfigurationAdapters() throws {
        let expectations: [(Size, Double, Double, ToolbarConfiguration.Size?)] = [
            (.none, 0, 0, nil),
            (.small, 16, 24, .small),
            (.medium, 24, 32, .medium),
            (.big, 32, 40, .big),
            (.huge, 40, 48, .huge)
        ]

        XCTAssertEqual(Size.allCases, expectations.map(\.0))
        for (size, imageDimension, commandWidth, configurationSize) in expectations {
            XCTAssertEqual(size.imageDimension, imageDimension)
            XCTAssertEqual(size.defaultCommandWidth, commandWidth)
            XCTAssertEqual(size.toolbarConfigurationSize, configurationSize)

            let customization = try Customization(
                size: size,
                items: [.command(.save)]
            )
            let plan = try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: 1_000
            )
            if size == .none {
                XCTAssertFalse(plan.isToolbarVisible)
                XCTAssertEqual(plan.visibleItems, [])
                XCTAssertEqual(plan.overflowItems, [.command(.save)])
                XCTAssertFalse(plan.showsOverflowControl)
                XCTAssertEqual(plan.occupiedWidth, 0)
            } else {
                XCTAssertTrue(plan.isToolbarVisible)
                XCTAssertEqual(plan.visibleItems, [.command(.save)])
                XCTAssertEqual(plan.overflowItems, [])
                XCTAssertFalse(plan.showsOverflowControl)
                XCTAssertEqual(plan.occupiedWidth, commandWidth)
            }
        }

        for size in ToolbarConfiguration.Size.allCases {
            XCTAssertEqual(Size(size).toolbarConfigurationSize, size)
        }
    }

    func testWinMergeDefaultsPreserveExactGroupsSeparatorsAndCommandOrder() {
        let expectedGroups: [[Command]] = [
            [.newComparison, .openComparison, .save],
            [.undo, .redo],
            [.selectLineDifference],
            [.nextDifference, .previousDifference],
            [.nextConflict, .previousConflict],
            [.firstDifference, .currentDifference, .lastDifference],
            [.copyToRight, .copyToLeft],
            [.copyToRightAndAdvance, .copyToLeftAndAdvance],
            [.copyAllToRight, .copyAllToLeft],
            [.autoMerge],
            [.firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile],
            [.options],
            [.refresh]
        ]

        XCTAssertEqual(
            ToolbarOverflowPlan.winMergeDefaultItems,
            ToolbarConfiguration.winMergeDefaultItems
        )
        XCTAssertEqual(ToolbarOverflowPlan.winMergeDefaultItems.count, 39)
        XCTAssertEqual(ToolbarOverflowPlan.winMergeDefaultCommands, Command.allCases)
        XCTAssertEqual(
            ToolbarOverflowPlan.winMergeDefaultGroups.map(\.commands),
            expectedGroups
        )
        XCTAssertTrue(
            ToolbarOverflowPlan.winMergeDefaultGroups.allSatisfy(\.hasTrailingSeparator)
        )
        XCTAssertEqual(
            ToolbarOverflowPlan.winMergeDefaultGroups.flatMap(\.items),
            ToolbarOverflowPlan.winMergeDefaultItems
        )
    }

    func testCommandGroupPublicItemCapsCover64And63PlusSeparatorBoundaries() throws {
        let sixtyFourCommands = Array(repeating: Command.save, count: 64)
        let sixtyThreeCommands = Array(repeating: Command.save, count: 63)

        let commandOnly = try ToolbarOverflowPlan.CommandGroup(
            commands: sixtyFourCommands,
            hasTrailingSeparator: false
        )
        XCTAssertEqual(commandOnly.items.count, 64)
        XCTAssertEqual(commandOnly.items.last, .command(.save))

        let withSeparator = try ToolbarOverflowPlan.CommandGroup(
            commands: sixtyThreeCommands,
            hasTrailingSeparator: true
        )
        XCTAssertEqual(withSeparator.items.count, 64)
        XCTAssertEqual(withSeparator.items.last, .separator)

        assertPlanError(.tooManyItems(maximumCount: 64)) {
            try ToolbarOverflowPlan.CommandGroup(
                commands: sixtyFourCommands,
                hasTrailingSeparator: true
            )
        }
        assertPlanError(.tooManyItems(maximumCount: 64)) {
            try ToolbarOverflowPlan.CommandGroup(
                commands: Array(repeating: .save, count: 65),
                hasTrailingSeparator: false
            )
        }
    }

    func testGroupConstructionAndValidationPreserveOrderAndRejectInvalidShapes() throws {
        let first = try ToolbarOverflowPlan.CommandGroup(
            commands: [.openComparison, .newComparison],
            hasTrailingSeparator: true
        )
        let second = try ToolbarOverflowPlan.CommandGroup(
            commands: [.undo, .save],
            hasTrailingSeparator: false
        )
        let customization = try Customization(size: .big, groups: [first, second])

        XCTAssertEqual(
            customization.items,
            [
                .command(.openComparison), .command(.newComparison), .separator,
                .command(.undo), .command(.save)
            ]
        )
        XCTAssertEqual(customization.commandGroups, [first, second])
        XCTAssertEqual(
            customization.commands,
            [.openComparison, .newComparison, .undo, .save]
        )

        let empty = try ToolbarOverflowPlan.CommandGroup(
            commands: [],
            hasTrailingSeparator: true
        )
        assertPlanError(.emptyGroup(index: 0)) {
            try Customization(groups: [empty])
        }
        let missingSeparator = try ToolbarOverflowPlan.CommandGroup(
            commands: [.save],
            hasTrailingSeparator: false
        )
        assertPlanError(.missingGroupSeparator(index: 0)) {
            try Customization(groups: [missingSeparator, second])
        }
        assertPlanError(.duplicateCommand(.save)) {
            try Customization(
                groups: [
                    try ToolbarOverflowPlan.CommandGroup(
                        commands: [.save],
                        hasTrailingSeparator: true
                    ),
                    try ToolbarOverflowPlan.CommandGroup(
                        commands: [.save],
                        hasTrailingSeparator: false
                    )
                ]
            )
        }
        assertPlanError(.misplacedSeparator) {
            try Customization(items: [.separator, .command(.save)])
        }
        assertPlanError(.misplacedSeparator) {
            try Customization(items: [.command(.save), .separator, .separator])
        }
    }

    func testWidthsUseOverridesDefaultsAndToolbarLayoutMetricsLosslessly() throws {
        let metrics = try ToolbarConfiguration.LayoutMetrics(
            commandWidths: [.save: 19, .undo: 23],
            separatorWidth: 3,
            overflowButtonWidth: 7
        )
        let widths = try Widths(metrics)

        XCTAssertEqual(widths.commandWidths, [.save: 19, .undo: 23])
        XCTAssertEqual(widths.separatorWidth, 3)
        XCTAssertEqual(widths.overflowControlWidth, 7)
        XCTAssertEqual(widths.width(of: .command(.save), size: .huge), 19)
        XCTAssertEqual(widths.width(of: .command(.openComparison), size: .medium), 32)
        XCTAssertEqual(widths.width(of: .separator, size: .none), 3)
        XCTAssertEqual(try widths.toolbarLayoutMetrics(), metrics)

        let allWidths = Dictionary(uniqueKeysWithValues: Command.allCases.map { ($0, 1.0) })
        XCTAssertNoThrow(try Widths(commandWidths: allWidths))
    }

    func testWidthsRejectEveryNonfiniteNonpositiveAndOverMaximumShape() {
        for width in [0, -1, .infinity, -.infinity, .nan, Widths.maximumItemWidth + 1] {
            assertPlanError(.invalidCommandWidth(.save)) {
                try Widths(commandWidths: [.save: width])
            }
        }
        for width in [-1, .infinity, -.infinity, .nan, Widths.maximumItemWidth + 1] {
            assertPlanError(.invalidSeparatorWidth) {
                try Widths(separatorWidth: width)
            }
        }
        XCTAssertNoThrow(try Widths(separatorWidth: 0))
        for width in [0, -1, .infinity, -.infinity, .nan, Widths.maximumItemWidth + 1] {
            assertPlanError(.invalidOverflowControlWidth) {
                try Widths(overflowControlWidth: width)
            }
        }
    }

    func testWidthsAndLimitsAcceptExactBounds() {
        XCTAssertNoThrow(
            try Widths(
                commandWidths: [.save: Widths.maximumItemWidth],
                separatorWidth: Widths.maximumItemWidth,
                overflowControlWidth: Widths.maximumItemWidth
            )
        )
        XCTAssertNoThrow(
            try Limits(
                maximumItemCount: 0,
                maximumGroupCount: 0,
                maximumPriorityCount: 0,
                maximumPinnedCount: 0,
                maximumOverflowItemCount: 0,
                maximumWork: 1,
                cancellationCheckInterval: 1
            ).validate()
        )
        XCTAssertNoThrow(
            try Limits(
                maximumItemCount: Limits.hardMaximumItemCount,
                maximumGroupCount: Limits.hardMaximumGroupCount,
                maximumPriorityCount: Limits.hardMaximumPriorityCount,
                maximumPinnedCount: Limits.hardMaximumPinnedCount,
                maximumOverflowItemCount: Limits.hardMaximumOverflowItemCount,
                maximumWork: Limits.hardMaximumWork,
                cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval
            ).validate()
        )
    }

    func testFullFitEmptyAndZeroWidthPartitionsHaveExactWidths() throws {
        let customization = try compactCustomization()
        let widths = try compactWidths()

        let full = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 42,
            widths: widths
        )
        XCTAssertEqual(full.visibleItems, compactItems)
        XCTAssertEqual(full.overflowItems, [])
        XCTAssertFalse(full.showsOverflowControl)
        XCTAssertEqual(full.occupiedWidth, 42)
        XCTAssertTrue(full.allConfiguredCommandsAreRepresented)

        let empty = try ToolbarOverflowPlan.make(
            customization: Customization(items: []),
            availableWidth: 0,
            widths: widths
        )
        XCTAssertEqual(empty.configuredItems, [])
        XCTAssertEqual(empty.visibleItems, [])
        XCTAssertEqual(empty.overflowItems, [])
        XCTAssertFalse(empty.showsOverflowControl)
        XCTAssertEqual(empty.occupiedWidth, 0)

        let overflowOnly = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 5,
            widths: widths
        )
        XCTAssertEqual(overflowOnly.visibleItems, [])
        XCTAssertEqual(overflowOnly.overflowItems, compactItems)
        XCTAssertTrue(overflowOnly.showsOverflowControl)
        XCTAssertEqual(overflowOnly.occupiedWidth, 5)
        XCTAssertTrue(overflowOnly.allConfiguredCommandsAreRepresented)
    }

    func testExactWidthBoundariesProduceLiteralPartitions() throws {
        let customization = try compactCustomization()
        let widths = try compactWidths()

        let onePixelBelowFull = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 41,
            widths: widths
        )
        XCTAssertEqual(
            onePixelBelowFull.visibleItems,
            [
                .command(.newComparison), .command(.openComparison), .separator,
                .command(.save)
            ]
        )
        XCTAssertEqual(onePixelBelowFull.overflowItems, [.command(.undo)])
        XCTAssertEqual(onePixelBelowFull.occupiedWidth, 37)
        XCTAssertTrue(onePixelBelowFull.showsOverflowControl)

        let exactThreeCommandFit = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 37,
            widths: widths
        )
        XCTAssertEqual(exactThreeCommandFit.visibleItems, onePixelBelowFull.visibleItems)
        XCTAssertEqual(exactThreeCommandFit.overflowItems, [.command(.undo)])
        XCTAssertEqual(exactThreeCommandFit.occupiedWidth, 37)

        let onePixelBelowThreeCommands = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 36,
            widths: widths
        )
        XCTAssertEqual(
            onePixelBelowThreeCommands.visibleItems,
            [.command(.newComparison), .command(.openComparison)]
        )
        XCTAssertEqual(
            onePixelBelowThreeCommands.overflowItems,
            [.command(.save), .command(.undo)]
        )
        XCTAssertEqual(onePixelBelowThreeCommands.occupiedWidth, 25)

        let exactSingleCommandFit = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 15,
            widths: widths
        )
        XCTAssertEqual(exactSingleCommandFit.visibleItems, [.command(.newComparison)])
        XCTAssertEqual(
            exactSingleCommandFit.overflowItems,
            [
                .command(.openComparison), .separator, .command(.save), .command(.undo)
            ]
        )
        XCTAssertEqual(exactSingleCommandFit.occupiedWidth, 15)

        let exactOverflowControlFit = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 5,
            widths: widths
        )
        XCTAssertEqual(exactOverflowControlFit.visibleItems, [])
        XCTAssertEqual(exactOverflowControlFit.overflowItems, compactItems)
        XCTAssertEqual(exactOverflowControlFit.occupiedWidth, 5)

        let exactPinnedFit = try ToolbarOverflowPlan.make(
            customization: compactCustomization(pinnedCommands: [.save]),
            availableWidth: 15,
            widths: widths
        )
        XCTAssertEqual(exactPinnedFit.visibleItems, [.command(.save)])
        XCTAssertEqual(
            exactPinnedFit.overflowItems,
            [
                .command(.newComparison), .command(.openComparison), .separator,
                .command(.undo)
            ]
        )
        XCTAssertEqual(exactPinnedFit.occupiedWidth, 15)
        assertPlanError(.pinnedCommandsDoNotFit) {
            try ToolbarOverflowPlan.make(
                customization: compactCustomization(pinnedCommands: [.save]),
                availableWidth: 14,
                widths: widths
            )
        }
    }

    func testPrioritySelectionUsesHigherPriorityThenConfiguredOrder() throws {
        let widths = try compactWidths()
        let defaultPlan = try ToolbarOverflowPlan.make(
            customization: compactCustomization(),
            availableWidth: 25,
            widths: widths
        )
        XCTAssertEqual(
            defaultPlan.visibleItems,
            [.command(.newComparison), .command(.openComparison)]
        )
        XCTAssertEqual(
            defaultPlan.overflowItems,
            [.command(.save), .command(.undo)]
        )
        XCTAssertEqual(defaultPlan.occupiedWidth, 25)

        let prioritized = try compactCustomization(priorities: [.save: 100])
        let prioritizedPlan = try ToolbarOverflowPlan.make(
            customization: prioritized,
            availableWidth: 27,
            widths: widths
        )
        XCTAssertEqual(
            prioritizedPlan.visibleItems,
            [.command(.newComparison), .separator, .command(.save)]
        )
        XCTAssertEqual(
            prioritizedPlan.overflowItems,
            [.command(.openComparison), .separator, .command(.undo)]
        )
        XCTAssertEqual(prioritizedPlan.visibleCommands, [.newComparison, .save])
        XCTAssertEqual(prioritizedPlan.overflowCommands, [.openComparison, .undo])
        XCTAssertEqual(prioritizedPlan.occupiedWidth, 27)
        XCTAssertTrue(prioritizedPlan.showsOverflowControl)
        XCTAssertTrue(prioritizedPlan.allConfiguredCommandsAreRepresented)
    }

    func testPinsWinBeforePrioritiesWithoutChangingRenderedOrder() throws {
        let customization = try compactCustomization(
            priorities: [.save: 100],
            pinnedCommands: [.undo]
        )
        let plan = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 27,
            widths: compactWidths()
        )

        XCTAssertEqual(plan.visibleItems, [.command(.save), .command(.undo)])
        XCTAssertEqual(
            plan.overflowItems,
            [.command(.newComparison), .command(.openComparison)]
        )
        XCTAssertEqual(plan.visibleCommands, [.save, .undo])
        XCTAssertEqual(plan.overflowCommands, [.newComparison, .openComparison])
        XCTAssertEqual(plan.occupiedWidth, 25)
        XCTAssertTrue(plan.allConfiguredCommandsAreRepresented)
    }

    func testSeparatorNormalizationIsIndependentForVisibleAndOverflowPartitions() throws {
        let customization = try Customization(
            items: [
                .command(.newComparison), .separator,
                .command(.openComparison), .separator
            ],
            priorities: [.newComparison: 1]
        )
        let widths = try Widths(
            commandWidths: [.newComparison: 10, .openComparison: 10],
            separatorWidth: 2,
            overflowControlWidth: 5
        )
        let plan = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 15,
            widths: widths
        )

        XCTAssertEqual(plan.visibleItems, [.command(.newComparison)])
        XCTAssertEqual(plan.overflowItems, [.command(.openComparison), .separator])
        XCTAssertEqual(plan.visibleGroups.count, 1)
        XCTAssertFalse(plan.visibleGroups[0].hasTrailingSeparator)
        XCTAssertEqual(plan.overflowGroups.count, 1)
        XCTAssertTrue(plan.overflowGroups[0].hasTrailingSeparator)
        XCTAssertTrue(plan.allConfiguredCommandsAreRepresented)
    }

    func testPartitionIsDeterministicAcrossRunsAndDictionaryConstructionOrder() throws {
        let forwardPairs: [(Command, Int)] = [
            (.save, 3), (.undo, 3), (.openComparison, -1), (.newComparison, -1)
        ]
        let reversePairs = forwardPairs.reversed()
        let forward = Dictionary(uniqueKeysWithValues: forwardPairs)
        let reverse = Dictionary(uniqueKeysWithValues: reversePairs)
        let firstCustomization = try compactCustomization(
            priorities: forward,
            pinnedCommands: [.undo]
        )
        let secondCustomization = try compactCustomization(
            priorities: reverse,
            pinnedCommands: [.undo]
        )
        let widths = try compactWidths()

        for index in 0..<32 {
            let customization =
                index.isMultiple(of: 2)
                ? firstCustomization
                : secondCustomization
            let plan = try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: 27,
                widths: widths
            )
            XCTAssertEqual(plan.size, .small)
            XCTAssertEqual(plan.availableWidth, 27)
            XCTAssertEqual(plan.configuredItems, compactItems)
            XCTAssertEqual(plan.visibleItems, [.command(.save), .command(.undo)])
            XCTAssertEqual(
                plan.overflowItems,
                [.command(.newComparison), .command(.openComparison)]
            )
            XCTAssertTrue(plan.showsOverflowControl)
            XCTAssertEqual(plan.occupiedWidth, 25)
            XCTAssertEqual(plan.workPerformed, 64)
            XCTAssertTrue(plan.allConfiguredCommandsAreRepresented)
        }
    }

    func testCustomizationMutationsAreAtomicAndResetAllState() throws {
        let first = try ToolbarOverflowPlan.CommandGroup(
            commands: [.save, .openComparison],
            hasTrailingSeparator: true
        )
        let second = try ToolbarOverflowPlan.CommandGroup(
            commands: [.undo],
            hasTrailingSeparator: false
        )
        var customization = try Customization(items: [.command(.save), .command(.openComparison)])

        customization.setSize(.huge)
        try customization.setPriority(7, for: .save)
        try customization.setPinned(true, for: .openComparison)
        try customization.setGroups([first, second])
        XCTAssertEqual(customization.size, .huge)
        XCTAssertEqual(customization.priority(of: .save), 7)
        XCTAssertEqual(customization.priority(of: .undo), 0)
        XCTAssertEqual(customization.pinnedCommands, [.openComparison])
        XCTAssertTrue(customization.isCustomized)

        let beforeInvalidItems = customization
        assertPlanError(.pinnedCommandMissing(.openComparison)) {
            try customization.setItems([.command(.save), .command(.undo)])
        }
        XCTAssertEqual(customization, beforeInvalidItems)

        assertPlanError(.priorityForMissingCommand(.newComparison)) {
            try customization.setPriority(1, for: .newComparison)
        }
        XCTAssertEqual(customization, beforeInvalidItems)
        assertPlanError(.pinnedCommandMissing(.newComparison)) {
            try customization.setPinned(true, for: .newComparison)
        }
        XCTAssertEqual(customization, beforeInvalidItems)

        try customization.setPriority(nil, for: .save)
        try customization.setPinned(false, for: .openComparison)
        XCTAssertTrue(customization.priorities.isEmpty)
        XCTAssertTrue(customization.pinnedCommands.isEmpty)
        customization.reset()
        XCTAssertEqual(customization, .winMergeDefault)
        XCTAssertFalse(customization.isCustomized)

        customization.setSize(.big)
        customization.resetToWinMergeDefaults()
        XCTAssertEqual(customization, .winMergeDefault)
    }

    func testCustomizationRejectsInvalidPrioritiesPinsCountsAndReferences() {
        assertPlanError(.priorityForMissingCommand(.undo)) {
            try Customization(items: [.command(.save)], priorities: [.undo: 1])
        }
        assertPlanError(.pinnedCommandMissing(.undo)) {
            try Customization(items: [.command(.save)], pinnedCommands: [.undo])
        }
        for priority in [-1_000_001, 1_000_001] {
            assertPlanError(.invalidPriority(command: .save, value: priority)) {
                try Customization(items: [.command(.save)], priorities: [.save: priority])
            }
        }
        XCTAssertNoThrow(
            try Customization(
                items: [.command(.save), .command(.undo)],
                priorities: [.save: -1_000_000, .undo: 1_000_000]
            )
        )

        assertPlanError(.tooManyPriorities(maximumCount: 1)) {
            try Customization(
                items: [.command(.save), .command(.undo)],
                priorities: [.save: 1, .undo: 2],
                limits: Limits(maximumPriorityCount: 1)
            )
        }
        assertPlanError(.tooManyPinnedCommands(maximumCount: 1)) {
            try Customization(
                items: [.command(.save), .command(.undo)],
                pinnedCommands: [.save, .undo],
                limits: Limits(maximumPinnedCount: 1)
            )
        }
    }

    func testCustomizationValidationAcceptsExactCountsAndRejectsOneLess() throws {
        let priorities: [Command: Int] = [.save: 1, .undo: 2]
        let pins: Set<Command> = [.save, .undo]

        XCTAssertNoThrow(
            try Customization(
                items: compactItems,
                priorities: priorities,
                pinnedCommands: pins,
                limits: Limits(
                    maximumItemCount: 5,
                    maximumGroupCount: 2,
                    maximumPriorityCount: 2,
                    maximumPinnedCount: 2
                )
            )
        )
        assertPlanError(.tooManyItems(maximumCount: 4)) {
            try Customization(
                items: compactItems,
                priorities: priorities,
                pinnedCommands: pins,
                limits: Limits(maximumItemCount: 4)
            )
        }
        assertPlanError(.tooManyGroups(maximumCount: 1)) {
            try Customization(
                items: compactItems,
                priorities: priorities,
                pinnedCommands: pins,
                limits: Limits(maximumGroupCount: 1)
            )
        }
        assertPlanError(.tooManyPriorities(maximumCount: 1)) {
            try Customization(
                items: compactItems,
                priorities: priorities,
                pinnedCommands: pins,
                limits: Limits(maximumPriorityCount: 1)
            )
        }
        assertPlanError(.tooManyPinnedCommands(maximumCount: 1)) {
            try Customization(
                items: compactItems,
                priorities: priorities,
                pinnedCommands: pins,
                limits: Limits(maximumPinnedCount: 1)
            )
        }
    }

    func testToolbarConfigurationAdaptersRoundTripVisibleSizesAndHiddenSmall() throws {
        let items: [Item] = [
            .command(.openComparison), .separator, .command(.save)
        ]
        for size in ToolbarConfiguration.Size.allCases {
            let configuration = try ToolbarConfiguration(
                visibility: .visible,
                size: size,
                items: items
            )
            let customization = try Customization(
                toolbarConfiguration: configuration,
                priorities: [.save: 4],
                pinnedCommands: [.openComparison]
            )
            XCTAssertEqual(customization.size, Size(size))
            XCTAssertEqual(customization.items, items)
            XCTAssertEqual(customization.priorities, [.save: 4])
            XCTAssertEqual(customization.pinnedCommands, [.openComparison])
            XCTAssertEqual(try customization.toolbarConfiguration(), configuration)
            XCTAssertEqual(
                try ToolbarConfiguration(overflowCustomization: customization),
                configuration
            )
        }

        let hidden = try ToolbarConfiguration(
            visibility: .hidden,
            size: .small,
            items: items
        )
        let hiddenCustomization = try Customization(toolbarConfiguration: hidden)
        XCTAssertEqual(hiddenCustomization.size, .none)
        XCTAssertEqual(hiddenCustomization.items, items)
        XCTAssertEqual(try hiddenCustomization.toolbarConfiguration(), hidden)
        XCTAssertEqual(
            try ToolbarConfiguration(overflowCustomization: hiddenCustomization),
            hidden
        )
    }

    func testToolbarConfigurationAdapterRejectsLossyHiddenMediumBigAndHuge() throws {
        for size in [
            ToolbarConfiguration.Size.medium,
            ToolbarConfiguration.Size.big,
            ToolbarConfiguration.Size.huge
        ] {
            let configuration = try ToolbarConfiguration(
                visibility: .hidden,
                size: size,
                items: [.command(.save)]
            )
            assertPlanError(.hiddenToolbarSizeNotRepresentable(size)) {
                try Customization(toolbarConfiguration: configuration)
            }
        }
    }

    func testPublicLimitsExposeHardCapsAndValidateEveryField() {
        let limits = Limits.default
        XCTAssertEqual(Limits.hardMaximumItemCount, 64)
        XCTAssertEqual(Limits.hardMaximumGroupCount, 32)
        XCTAssertEqual(Limits.hardMaximumPriorityCount, 64)
        XCTAssertEqual(Limits.hardMaximumPinnedCount, 64)
        XCTAssertEqual(Limits.hardMaximumOverflowItemCount, 64)
        XCTAssertEqual(Limits.hardMaximumWork, 1_000_000)
        XCTAssertEqual(Limits.hardMaximumCancellationCheckInterval, 4_096)
        XCTAssertEqual(limits.maximumItemCount, 64)
        XCTAssertEqual(limits.maximumGroupCount, 32)
        XCTAssertEqual(limits.maximumPriorityCount, 64)
        XCTAssertEqual(limits.maximumPinnedCount, 64)
        XCTAssertEqual(limits.maximumOverflowItemCount, 64)
        XCTAssertEqual(limits.maximumWork, 32_768)
        XCTAssertEqual(limits.cancellationCheckInterval, 16)
        XCTAssertNoThrow(try limits.validate())

        assertInvalidLimit("maximumItemCount", -1, Limits(maximumItemCount: -1))
        assertInvalidLimit("maximumItemCount", 65, Limits(maximumItemCount: 65))
        assertInvalidLimit("maximumGroupCount", -1, Limits(maximumGroupCount: -1))
        assertInvalidLimit("maximumGroupCount", 33, Limits(maximumGroupCount: 33))
        assertInvalidLimit(
            "maximumPriorityCount",
            -1,
            Limits(maximumPriorityCount: -1)
        )
        assertInvalidLimit(
            "maximumPriorityCount",
            65,
            Limits(maximumPriorityCount: 65)
        )
        assertInvalidLimit("maximumPinnedCount", -1, Limits(maximumPinnedCount: -1))
        assertInvalidLimit("maximumPinnedCount", 65, Limits(maximumPinnedCount: 65))
        assertInvalidLimit(
            "maximumOverflowItemCount",
            -1,
            Limits(maximumOverflowItemCount: -1)
        )
        assertInvalidLimit(
            "maximumOverflowItemCount",
            65,
            Limits(maximumOverflowItemCount: 65)
        )
        assertInvalidLimit("maximumWork", 0, Limits(maximumWork: 0))
        assertInvalidLimit("maximumWork", 1_000_001, Limits(maximumWork: 1_000_001))
        assertInvalidLimit(
            "cancellationCheckInterval",
            0,
            Limits(cancellationCheckInterval: 0)
        )
        assertInvalidLimit(
            "cancellationCheckInterval",
            4_097,
            Limits(cancellationCheckInterval: 4_097)
        )
    }

    func testPublicHardCapsRejectOversizedPersistenceArraysBeforeElementDecoding() {
        let sixtyFourItems = Array(repeating: "save", count: 64)
        assertPlanError(.duplicateCommand(.save)) {
            try Customization.decode(from: customizationData(items: sixtyFourItems))
        }
        assertPlanError(.tooManyItems(maximumCount: 64)) {
            try Customization.decode(
                from: customizationData(items: Array(repeating: "save", count: 65))
            )
        }

        let priority = #"{"command":"save","value":0}"#
        assertPlanError(.tooManyPriorities(maximumCount: 64)) {
            try Customization.decode(
                from: customizationData(
                    items: ["save"],
                    prioritiesJSON: "[" + Array(repeating: priority, count: 65).joined(separator: ",")
                        + "]"
                )
            )
        }
        assertPlanError(.tooManyPinnedCommands(maximumCount: 64)) {
            try Customization.decode(
                from: customizationData(
                    items: ["save"],
                    pinnedJSON: "[" + Array(repeating: #""save""#, count: 65).joined(separator: ",")
                        + "]"
                )
            )
        }
    }

    func testPlanningRejectsInvalidAvailableWidthsBeforeWork() throws {
        let customization = try Customization(items: [.command(.save)])
        for width in [
            -1,
            .infinity,
            -.infinity,
            .nan,
            Widths.maximumAvailableWidth + 1
        ] {
            assertPlanError(.invalidAvailableWidth) {
                try ToolbarOverflowPlan.make(
                    customization: customization,
                    availableWidth: width
                )
            }
        }
        XCTAssertNoThrow(
            try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: Widths.maximumAvailableWidth
            )
        )
    }

    func testOverflowControlPinsAndOverflowLimitFailuresAreSpecific() throws {
        let widths = try compactWidths()
        assertPlanError(.overflowControlDoesNotFit) {
            try ToolbarOverflowPlan.make(
                customization: compactCustomization(),
                availableWidth: 4,
                widths: widths
            )
        }
        assertPlanError(.pinnedCommandsDoNotFit) {
            try ToolbarOverflowPlan.make(
                customization: compactCustomization(pinnedCommands: [.save]),
                availableWidth: 14,
                widths: widths
            )
        }
        assertPlanError(.pinnedCommandsDoNotFit) {
            try ToolbarOverflowPlan.make(
                customization: compactCustomization(
                    pinnedCommands: [.newComparison, .openComparison, .save, .undo]
                ),
                availableWidth: 41,
                widths: widths
            )
        }
        assertPlanError(.overflowLimitExceeded(maximumCount: 1)) {
            try ToolbarOverflowPlan.make(
                customization: compactCustomization(),
                availableWidth: 25,
                widths: widths,
                limits: Limits(maximumOverflowItemCount: 1)
            )
        }
        XCTAssertNoThrow(
            try ToolbarOverflowPlan.make(
                customization: compactCustomization(),
                availableWidth: 25,
                widths: widths,
                limits: Limits(maximumOverflowItemCount: 2)
            )
        )
        assertPlanError(.overflowLimitExceeded(maximumCount: 4)) {
            try ToolbarOverflowPlan.make(
                customization: Customization(size: .none, items: compactItems),
                availableWidth: 0,
                widths: widths,
                limits: Limits(maximumOverflowItemCount: 4)
            )
        }
        XCTAssertNoThrow(
            try ToolbarOverflowPlan.make(
                customization: Customization(size: .none, items: compactItems),
                availableWidth: 0,
                widths: widths,
                limits: Limits(maximumOverflowItemCount: 5)
            )
        )
    }

    func testAllPinnedCommandsThatDoNotFitReportPinnedFailure() throws {
        let customization = try Customization(
            items: [.command(.save), .command(.undo)],
            pinnedCommands: [.save, .undo]
        )
        let widths = try Widths(
            commandWidths: [.save: 10, .undo: 10],
            overflowControlWidth: 5
        )

        assertPlanError(.pinnedCommandsDoNotFit) {
            try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: 4,
                widths: widths
            )
        }
    }

    func testMixedPinnedCommandsStillRequireOverflowControlToFit() throws {
        let customization = try Customization(
            items: [.command(.save), .command(.undo)],
            pinnedCommands: [.save]
        )
        let widths = try Widths(
            commandWidths: [.save: 10, .undo: 10],
            overflowControlWidth: 5
        )

        assertPlanError(.overflowControlDoesNotFit) {
            try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: 4,
                widths: widths
            )
        }
    }

    func testAllPinnedAndMixedCommandsFitAtExactRequiredWidths() throws {
        let widths = try Widths(
            commandWidths: [.save: 10, .undo: 10],
            overflowControlWidth: 5
        )
        let allPinned = try ToolbarOverflowPlan.make(
            customization: Customization(
                items: [.command(.save), .command(.undo)],
                pinnedCommands: [.save, .undo]
            ),
            availableWidth: 20,
            widths: widths
        )

        XCTAssertEqual(allPinned.visibleItems, [.command(.save), .command(.undo)])
        XCTAssertEqual(allPinned.overflowItems, [])
        XCTAssertFalse(allPinned.showsOverflowControl)
        XCTAssertEqual(allPinned.occupiedWidth, 20)

        let mixed = try ToolbarOverflowPlan.make(
            customization: Customization(
                items: [.command(.save), .command(.undo)],
                pinnedCommands: [.save]
            ),
            availableWidth: 15,
            widths: widths
        )

        XCTAssertEqual(mixed.visibleItems, [.command(.save)])
        XCTAssertEqual(mixed.overflowItems, [.command(.undo)])
        XCTAssertTrue(mixed.showsOverflowControl)
        XCTAssertEqual(mixed.occupiedWidth, 15)
    }

    func testCanonicalPersistenceBytesAreStableSortedAndRoundTrip() throws {
        let first = try Customization(
            size: .huge,
            items: [.command(.save), .separator, .command(.openComparison)],
            priorities: [.save: 7, .openComparison: -2],
            pinnedCommands: [.save, .openComparison]
        )
        let secondPriorities = Dictionary(
            uniqueKeysWithValues: [
                (Command.openComparison, -2),
                (.save, 7)
            ]
        )
        let second = try Customization(
            size: .huge,
            items: [.command(.save), .separator, .command(.openComparison)],
            priorities: secondPriorities,
            pinnedCommands: Set([.openComparison, .save])
        )
        let expected = data(
            #"{"items":["save","separator","openComparison"],"pinnedCommands":["openComparison","save"],"priorities":[{"command":"openComparison","value":-2},{"command":"save","value":7}],"schemaVersion":1,"size":"huge"}"#
        )

        let firstData = try first.encodedData()
        XCTAssertEqual(firstData, expected)
        XCTAssertEqual(try second.encodedData(), expected)
        XCTAssertEqual(try Customization.decode(from: expected), first)
        XCTAssertEqual(try Customization.decode(from: expected).encodedData(), expected)
        XCTAssertEqual(first.schemaVersion, Customization.currentSchemaVersion)
        XCTAssertEqual(Customization.currentSchemaVersion, 1)
        XCTAssertEqual(Customization.maximumEncodedBytes, 16 * 1_024)
    }

    func testPersistenceRejectsUnsupportedSchemaAndUnknownFieldsAtEveryObjectLevel() {
        assertPlanError(.unsupportedSchemaVersion(2)) {
            try Customization.decode(
                from: data(
                    #"{"schemaVersion":2,"size":"small","items":["save"],"priorities":[],"pinnedCommands":[]}"#
                )
            )
        }
        assertPlanError(.unknownField("alpha")) {
            try Customization.decode(
                from: data(
                    #"{"schemaVersion":1,"size":"small","items":["save"],"priorities":[],"pinnedCommands":[],"zeta":0,"alpha":0}"#
                )
            )
        }
        assertPlanError(.unknownField("extra")) {
            try Customization.decode(
                from: data(
                    #"{"schemaVersion":1,"size":"small","items":["save"],"priorities":[{"command":"save","value":1,"extra":0}],"pinnedCommands":[]}"#
                )
            )
        }
        assertPlanError(.unsupportedSchemaVersion(2)) {
            try Customization.decode(
                from: data(
                    #"{"schemaVersion":2,"size":"small","items":["save"],"priorities":[{"command":"save","value":1,"futureEntryField":0}],"pinnedCommands":[],"futureTopLevelField":0}"#
                )
            )
        }
    }

    func testDirectJSONDecoderCannotBypassBoundedCustomizationDecode() throws {
        let validJSON =
            #"{"schemaVersion":1,"size":"small","items":["save"],"priorities":[],"pinnedCommands":[]}"#
        let oversizedValidJSON =
            validJSON
            + String(
                repeating: " ",
                count: Customization.maximumEncodedBytes + 1 - validJSON.utf8.count
            )
        let decoded = try decodeDirectlyWithJSONDecoder(
            Customization.self,
            from: data(oversizedValidJSON)
        )

        XCTAssertNil(decoded)
        assertPlanError(
            .encodedDataTooLarge(maximumBytes: Customization.maximumEncodedBytes)
        ) {
            try Customization.decode(from: data(oversizedValidJSON))
        }
    }

    func testPersistenceRejectsDuplicateKeysIncludingEscapedAliases() {
        assertPlanError(.duplicateJSONKey("schemaVersion")) {
            try Customization.decode(
                from: data(
                    #"{"schemaVersion":1,"schemaVersion":1,"size":"small","items":["save"],"priorities":[],"pinnedCommands":[]}"#
                )
            )
        }
        assertPlanError(.duplicateJSONKey("schemaVersion")) {
            try Customization.decode(
                from: data(
                    #"{"schemaVersion":1,"schema\u0056ersion":1,"size":"small","items":["save"],"priorities":[],"pinnedCommands":[]}"#
                )
            )
        }
        assertPlanError(.duplicateJSONKey("command")) {
            try Customization.decode(
                from: data(
                    #"{"schemaVersion":1,"size":"small","items":["save"],"priorities":[{"command":"save","command":"save","value":1}],"pinnedCommands":[]}"#
                )
            )
        }
    }

    func testPersistenceRejectsUnknownAndDuplicateCommandsWithPlanErrors() {
        assertPlanError(.unknownCommand("futureCommand")) {
            try Customization.decode(
                from: customizationData(items: ["futureCommand"])
            )
        }
        assertPlanError(.unknownCommand("futurePriority")) {
            try Customization.decode(
                from: customizationData(
                    items: ["save"],
                    prioritiesJSON: #"[{"command":"futurePriority","value":1}]"#
                )
            )
        }
        assertPlanError(.unknownCommand("futurePinned")) {
            try Customization.decode(
                from: customizationData(
                    items: ["save"],
                    pinnedJSON: #"["futurePinned"]"#
                )
            )
        }
        assertPlanError(.duplicatePriority(.save)) {
            try Customization.decode(
                from: customizationData(
                    items: ["save"],
                    prioritiesJSON: #"[{"command":"save","value":1},{"command":"save","value":2}]"#
                )
            )
        }
        assertPlanError(.duplicatePinnedCommand(.save)) {
            try Customization.decode(
                from: customizationData(
                    items: ["save"],
                    pinnedJSON: #"["save","save"]"#
                )
            )
        }
    }

    func testStrictPersistenceRejectsMalformedJSONInvalidUTF8AndOversizedData() {
        for malformed in [
            Data(),
            data("{"),
            data("[] trailing"),
            data(#"{"schemaVersion":1,}"#),
            Data([0x22, 0xC0, 0x80, 0x22])
        ] {
            assertPlanError(.invalidJSON) {
                try Customization.decode(from: malformed)
            }
        }

        assertPlanError(.invalidJSON) {
            try Customization.decode(
                from: Data(repeating: 0x20, count: Customization.maximumEncodedBytes)
            )
        }
        assertPlanError(
            .encodedDataTooLarge(maximumBytes: Customization.maximumEncodedBytes)
        ) {
            try Customization.decode(
                from: Data(repeating: 0x20, count: Customization.maximumEncodedBytes + 1)
            )
        }
    }

    func testStrictPersistenceStructuralLimitsAcceptExactBounds() {
        assertStructuralPreflightAccepts(
            String(repeating: "[", count: 8) + "0" + String(repeating: "]", count: 8)
        )
        assertStructuralPreflightAccepts(
            "[" + Array(repeating: "0", count: 80).joined(separator: ",") + "]"
        )
        assertStructuralPreflightAccepts(exactValueLimitJSON)
        assertStructuralPreflightAccepts("\"" + String(repeating: "s", count: 128) + "\"")
        assertStructuralPreflightAccepts(
            "{\"" + String(repeating: "k", count: 64) + "\":0}"
        )
        assertStructuralPreflightAccepts(String(repeating: "9", count: 32))
        assertStructuralPreflightAccepts(exactAggregateStringLimitJSON)
    }

    func testStrictPersistenceStructuralLimitsRejectFirstExcess() {
        assertPlanError(.jsonNestingTooDeep(maximumDepth: 8)) {
            try Customization.decode(from: data(String(repeating: "[", count: 9) + "0" + String(repeating: "]", count: 9)))
        }
        assertPlanError(.jsonContainerTooLarge(maximumElements: 80)) {
            try Customization.decode(
                from: data("[" + Array(repeating: "0", count: 81).joined(separator: ",") + "]")
            )
        }

        assertPlanError(.tooManyJSONValues(maximumValues: 512)) {
            try Customization.decode(from: data(firstExcessValueJSON))
        }
        assertPlanError(.jsonStringTooLarge(maximumBytes: 128)) {
            try Customization.decode(
                from: data("\"" + String(repeating: "a", count: 129) + "\"")
            )
        }
        assertPlanError(.jsonStringTooLarge(maximumBytes: 64)) {
            try Customization.decode(
                from: data("{\"" + String(repeating: "k", count: 65) + "\":0}")
            )
        }
        assertPlanError(.jsonNumberTooLarge(maximumBytes: 32)) {
            try Customization.decode(from: data(String(repeating: "9", count: 33)))
        }

        XCTAssertLessThan(
            firstExcessAggregateStringJSON.utf8.count,
            Customization.maximumEncodedBytes
        )
        assertPlanError(.jsonStringTooLarge(maximumBytes: 12 * 1_024)) {
            try Customization.decode(from: data(firstExcessAggregateStringJSON))
        }
    }

    func testExactWorkLimitSucceedsAndOneLessFails() throws {
        let customization = try compactCustomization(priorities: [.undo: 2, .save: 1])
        let widths = try compactWidths()
        let baseline = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 27,
            widths: widths
        )
        XCTAssertEqual(baseline.workPerformed, 72)

        let exactLimits = Limits(
            maximumWork: 72,
            cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval
        )
        let exact = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 27,
            widths: widths,
            limits: exactLimits
        )
        XCTAssertEqual(exact, baseline)

        assertPlanError(.workLimitExceeded(maximumWork: 71)) {
            try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: 27,
                widths: widths,
                limits: Limits(
                    maximumWork: 71,
                    cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval
                )
            )
        }
    }

    func testCancellationRunsAtEntryAndConfiguredWorkIntervals() throws {
        let customization = try compactCustomization(priorities: [.save: 1])
        let widths = try compactWidths()
        let baseline = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 27,
            widths: widths
        )
        let interval = 3
        let probe = CancellationProbe()
        let plan = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 27,
            widths: widths,
            limits: Limits(cancellationCheckInterval: interval),
            cancellationCheck: { try probe.check() }
        )

        XCTAssertEqual(plan, baseline)
        XCTAssertEqual(plan.workPerformed, 73)
        XCTAssertEqual(probe.count, 25)
    }

    func testCancellationChecksExactFinalWorkBoundary() throws {
        let customization = try compactCustomization(priorities: [.save: 1])
        let widths = try compactWidths()
        let finalBoundaryProbe = CancellationProbe()
        let finalBoundaryPlan = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 27,
            widths: widths,
            limits: Limits(cancellationCheckInterval: 73),
            cancellationCheck: { try finalBoundaryProbe.check() }
        )
        XCTAssertEqual(finalBoundaryPlan.workPerformed, 73)
        XCTAssertEqual(finalBoundaryProbe.count, 2)

        let beyondWorkProbe = CancellationProbe()
        let beyondWorkPlan = try ToolbarOverflowPlan.make(
            customization: customization,
            availableWidth: 27,
            widths: widths,
            limits: Limits(cancellationCheckInterval: 74),
            cancellationCheck: { try beyondWorkProbe.check() }
        )
        XCTAssertEqual(beyondWorkPlan.workPerformed, 73)
        XCTAssertEqual(beyondWorkProbe.count, 1)

        let finalBoundaryCancellation = CancellationProbe(throwOnCheck: 2)
        assertProbeCancellation(expectedChecks: 2, probe: finalBoundaryCancellation) {
            try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: 27,
                widths: widths,
                limits: Limits(cancellationCheckInterval: 73),
                cancellationCheck: { try finalBoundaryCancellation.check() }
            )
        }
    }

    func testCancellationPropagatesAtEntryAndDuringWork() throws {
        let customization = try compactCustomization()
        let widths = try compactWidths()
        let entryProbe = CancellationProbe(throwOnCheck: 1)
        assertProbeCancellation(expectedChecks: 1, probe: entryProbe) {
            try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: 27,
                widths: widths,
                cancellationCheck: { try entryProbe.check() }
            )
        }

        let workProbe = CancellationProbe(throwOnCheck: 2)
        assertProbeCancellation(expectedChecks: 2, probe: workProbe) {
            try ToolbarOverflowPlan.make(
                customization: customization,
                availableWidth: 27,
                widths: widths,
                limits: Limits(cancellationCheckInterval: 1),
                cancellationCheck: { try workProbe.check() }
            )
        }
    }

    private var compactItems: [Item] {
        [
            .command(.newComparison), .command(.openComparison), .separator,
            .command(.save), .command(.undo)
        ]
    }

    private func compactCustomization(
        priorities: [Command: Int] = [:],
        pinnedCommands: Set<Command> = []
    ) throws -> Customization {
        try Customization(
            items: compactItems,
            priorities: priorities,
            pinnedCommands: pinnedCommands
        )
    }

    private func compactWidths() throws -> Widths {
        try Widths(
            commandWidths: [
                .newComparison: 10,
                .openComparison: 10,
                .save: 10,
                .undo: 10
            ],
            separatorWidth: 2,
            overflowControlWidth: 5
        )
    }

    private func customizationData(
        items: [String],
        prioritiesJSON: String = "[]",
        pinnedJSON: String = "[]"
    ) -> Data {
        let itemsJSON = items.map { #""\#($0)""# }.joined(separator: ",")
        return data(
            "{\"schemaVersion\":1,\"size\":\"small\",\"items\":[\(itemsJSON)],"
                + "\"priorities\":\(prioritiesJSON),\"pinnedCommands\":\(pinnedJSON)}"
        )
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    private var exactValueLimitJSON: String {
        let fullArray = "[" + Array(repeating: "0", count: 80).joined(separator: ",") + "]"
        let finalArray = "[" + Array(repeating: "0", count: 24).joined(separator: ",") + "]"
        return "[" + Array(repeating: fullArray, count: 6).joined(separator: ",")
            + "," + finalArray + "]"
    }

    private var firstExcessValueJSON: String {
        let fullArray = "[" + Array(repeating: "0", count: 80).joined(separator: ",") + "]"
        let finalArray = "[" + Array(repeating: "0", count: 25).joined(separator: ",") + "]"
        return "[" + Array(repeating: fullArray, count: 6).joined(separator: ",")
            + "," + finalArray + "]"
    }

    private var exactAggregateStringLimitJSON: String {
        aggregateStringJSON(trailingString: nil)
    }

    private var firstExcessAggregateStringJSON: String {
        aggregateStringJSON(trailingString: "x")
    }

    private func aggregateStringJSON(trailingString: String?) -> String {
        let string = "\"" + String(repeating: "s", count: 128) + "\""
        let half = "[" + Array(repeating: string, count: 48).joined(separator: ",") + "]"
        var arrays = [half, half]
        if let trailingString { arrays.append("[\"\(trailingString)\"]") }
        return "[" + arrays.joined(separator: ",") + "]"
    }

    private func decodeDirectlyWithJSONDecoder<T>(_ type: T.Type, from data: Data) throws -> T? {
        guard let decodableType = type as? any Decodable.Type else { return nil }
        return try JSONDecoder().decode(decodableType, from: data) as? T
    }

    private func assertStructuralPreflightAccepts(
        _ json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try Customization.decode(from: data(json))
            XCTFail("Expected semantic decoding failure", file: file, line: line)
        } catch is DecodingError {
        } catch ToolbarOverflowPlanError.unknownField {
        } catch {
            XCTFail("Structural preflight rejected exact boundary: \(error)", file: file, line: line)
        }
    }

    private func assertInvalidLimit(
        _ name: String,
        _ value: Int,
        _ limits: Limits,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertPlanError(.invalidLimit(name: name, value: value), file: file, line: line) {
            try limits.validate()
        }
    }

    private func assertPlanError<T>(
        _ expected: ToolbarOverflowPlanError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ToolbarOverflowPlanError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertProbeCancellation<T>(
        expectedChecks: Int,
        probe: CancellationProbe,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected cancellation", file: file, line: line)
        } catch let error as CancellationProbe.ProbeError {
            XCTAssertEqual(error, .cancelled, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
        XCTAssertEqual(probe.count, expectedChecks, file: file, line: line)
    }
}

private final class CancellationProbe: @unchecked Sendable {
    enum ProbeError: Error, Equatable {
        case cancelled
    }

    private let lock = NSLock()
    private let throwOnCheck: Int?
    private var checkCount = 0

    init(throwOnCheck: Int? = nil) {
        self.throwOnCheck = throwOnCheck
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return checkCount
    }

    func check() throws {
        lock.lock()
        checkCount += 1
        let shouldThrow = checkCount == throwOnCheck
        lock.unlock()
        if shouldThrow { throw ProbeError.cancelled }
    }
}
