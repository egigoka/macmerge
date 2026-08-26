import Foundation
import XCTest

@testable import MacMergeCore

final class PaneLayoutTests: XCTestCase {
    func testTwoAndThreePaneIdentitiesAndAdaptersAreComplete() throws {
        XCTAssertEqual(PaneIdentity.allCases.map(\.rawValue), ["left", "middle", "right"])
        XCTAssertEqual(PaneLayout.PaneCount.allCases.map(\.rawValue), [2, 3])
        XCTAssertEqual(PaneLayout.PaneCount.two.identities, [.left, .right])
        XCTAssertEqual(PaneLayout.PaneCount.three.identities, [.left, .middle, .right])

        let defaultTwoPane = try PaneLayout(paneCount: .two)
        XCTAssertEqual(defaultTwoPane.activePane, .left)
        XCTAssertEqual(defaultTwoPane.visualOrder, [.left, .right])
        XCTAssertEqual(defaultTwoPane.orientation, .vertical)
        assertDoublesEqual(defaultTwoPane.paneFractions, [0.5, 0.5])

        let defaultThreePane = try PaneLayout(paneCount: .three)
        XCTAssertEqual(defaultThreePane.activePane, .left)
        XCTAssertEqual(defaultThreePane.visualOrder, [.left, .middle, .right])
        XCTAssertEqual(defaultThreePane.orientation, .vertical)
        assertDoublesEqual(
            defaultThreePane.paneFractions,
            Array(repeating: 1.0 / 3.0, count: 3)
        )

        XCTAssertEqual(PaneIdentity(ComparisonSideIdentity.left), .left)
        XCTAssertEqual(PaneIdentity(ComparisonSideIdentity.middle), .middle)
        XCTAssertEqual(PaneIdentity(ComparisonSideIdentity.right), .right)
        XCTAssertEqual(PaneIdentity.left.comparisonSideIdentity, .left)
        XCTAssertEqual(PaneIdentity.middle.comparisonSideIdentity, .middle)
        XCTAssertEqual(PaneIdentity.right.comparisonSideIdentity, .right)
        XCTAssertEqual(PaneIdentity(ComparisonSessionState.Side.left), .left)
        XCTAssertEqual(PaneIdentity(ComparisonSessionState.Side.right), .right)
        XCTAssertEqual(PaneIdentity.left.comparisonSessionSide, .left)
        XCTAssertNil(PaneIdentity.middle.comparisonSessionSide)
        XCTAssertEqual(PaneIdentity.right.comparisonSessionSide, .right)
        XCTAssertEqual(PaneIdentity(MergeCommandPolicy.Side.left), .left)
        XCTAssertEqual(PaneIdentity(MergeCommandPolicy.Side.middle), .middle)
        XCTAssertEqual(PaneIdentity(MergeCommandPolicy.Side.right), .right)
        XCTAssertEqual(PaneIdentity.left.mergeCommandSide, .left)
        XCTAssertEqual(PaneIdentity.middle.mergeCommandSide, .middle)
        XCTAssertEqual(PaneIdentity.right.mergeCommandSide, .right)

        let count: PaneLayoutCount = .three
        let orientation: PaneSplitOrientation = .horizontal
        XCTAssertEqual(count, .three)
        XCTAssertEqual(orientation, .horizontal)
        requireSendable(PaneIdentity.left)
        requireSendable(try PaneLayout(paneCount: .two))
        requireSendable(PaneLayoutError.invalidVisualIndex(2))
    }

    func testEveryVisualPermutationPreservesLogicalIdentityAndActivePane() throws {
        for paneCount in PaneLayout.PaneCount.allCases {
            for order in orders(for: paneCount) {
                for activePane in order {
                    let layout = try PaneLayout(visualOrder: order, activePane: activePane)

                    XCTAssertEqual(layout.paneCount, paneCount)
                    XCTAssertEqual(layout.logicalOrder, paneCount.identities)
                    XCTAssertEqual(layout.visualOrder, order)
                    XCTAssertEqual(layout.activePane, activePane)
                    XCTAssertEqual(layout.activeVisualIndex, order.firstIndex(of: activePane))
                    for (index, identity) in order.enumerated() {
                        XCTAssertEqual(try layout.identity(atVisualIndex: index), identity)
                        XCTAssertEqual(try layout.visualIndex(of: identity), index)
                    }
                }
            }
        }
    }

    func testActivePaneMutationRejectsAbsentIdentityAtomically() throws {
        var layout = try PaneLayout(paneCount: .two)
        try layout.setActivePane(.right)
        XCTAssertEqual(layout.activePane, .right)
        XCTAssertEqual(layout.activeVisualIndex, 1)

        let unchanged = layout
        assertLayoutError(.identityNotPresent(.middle), try layout.setActivePane(.middle))
        XCTAssertEqual(layout, unchanged)
        assertLayoutError(.invalidVisualIndex(-1), try layout.identity(atVisualIndex: -1))
        assertLayoutError(.invalidVisualIndex(2), try layout.identity(atVisualIndex: 2))
        assertLayoutError(.identityNotPresent(.middle), try layout.visualIndex(of: .middle))
    }

    func testAllIdentitySwapsKeepActiveOwnerAndRespectSizePreservation() throws {
        for paneCount in PaneLayout.PaneCount.allCases {
            for order in orders(for: paneCount) {
                for firstIndex in order.indices {
                    for secondIndex in order.indices where firstIndex < secondIndex {
                        for activePane in order {
                            let original = try PaneLayout(
                                visualOrder: order,
                                activePane: activePane,
                                splitFractions: paneCount == .two ? [0.25] : [0.2, 0.55]
                            )
                            var expectedOrder = order
                            expectedOrder.swapAt(firstIndex, secondIndex)

                            var byIndex = original
                            try byIndex.swapVisualPanes(at: firstIndex, and: secondIndex)
                            XCTAssertEqual(byIndex.visualOrder, expectedOrder)
                            XCTAssertEqual(byIndex.activePane, activePane)
                            XCTAssertEqual(
                                byIndex.activeVisualIndex,
                                expectedOrder.firstIndex(of: activePane)
                            )
                            XCTAssertEqual(byIndex.splitFractions, original.splitFractions)

                            let byIdentity = try original.swappingPanes(
                                order[firstIndex],
                                order[secondIndex]
                            )
                            XCTAssertEqual(byIdentity, byIndex)

                            var expectedOwnerFractions = original.paneFractions
                            expectedOwnerFractions.swapAt(firstIndex, secondIndex)
                            var byIndexPreservingSizes = original
                            try byIndexPreservingSizes.swapVisualPanes(
                                at: firstIndex,
                                and: secondIndex,
                                preservingPaneSizes: true
                            )
                            XCTAssertEqual(byIndexPreservingSizes.visualOrder, expectedOrder)
                            XCTAssertEqual(byIndexPreservingSizes.activePane, activePane)
                            XCTAssertEqual(
                                byIndexPreservingSizes.activeVisualIndex,
                                expectedOrder.firstIndex(of: activePane)
                            )
                            assertDoublesEqual(
                                byIndexPreservingSizes.paneFractions,
                                expectedOwnerFractions
                            )

                            let byIdentityPreservingSizes = try original.swappingPanes(
                                order[firstIndex],
                                order[secondIndex],
                                preservingPaneSizes: true
                            )
                            XCTAssertEqual(byIdentityPreservingSizes, byIndexPreservingSizes)
                            XCTAssertEqual(original.visualOrder, order)
                        }
                    }
                }
            }
        }
    }

    func testStandardAndSizePreservingSwapsCoverTwoAndThreePanes() throws {
        var twoPane = try PaneLayout(
            paneCount: .two,
            activePane: .left,
            splitFractions: [0.25]
        )
        try twoPane.swapPanes(preservingPaneSizes: true)
        XCTAssertEqual(twoPane.visualOrder, [.right, .left])
        XCTAssertEqual(twoPane.activePane, .left)
        XCTAssertEqual(twoPane.activeVisualIndex, 1)
        assertDoublesEqual(twoPane.paneFractions, [0.75, 0.25])

        let threePane = try PaneLayout(
            paneCount: .three,
            activePane: .middle,
            splitFractions: [0.2, 0.5]
        )
        let fixedSlots = try threePane.swappingPanes()
        XCTAssertEqual(fixedSlots.visualOrder, [.right, .middle, .left])
        assertDoublesEqual(fixedSlots.paneFractions, [0.2, 0.3, 0.5])

        let ownerSizes = try threePane.swappingPanes(preservingPaneSizes: true)
        XCTAssertEqual(ownerSizes.visualOrder, [.right, .middle, .left])
        XCTAssertEqual(ownerSizes.activePane, .middle)
        XCTAssertEqual(ownerSizes.activeVisualIndex, 1)
        assertDoublesEqual(ownerSizes.paneFractions, [0.5, 0.3, 0.2])
        XCTAssertEqual(threePane.visualOrder, [.left, .middle, .right])

        for paneCount in PaneLayout.PaneCount.allCases {
            for order in orders(for: paneCount) {
                for activePane in order {
                    let original = try PaneLayout(
                        visualOrder: order,
                        activePane: activePane,
                        splitFractions: paneCount == .two ? [0.25] : [0.2, 0.55]
                    )
                    var expectedOrder = order
                    expectedOrder.swapAt(expectedOrder.startIndex, expectedOrder.endIndex - 1)

                    var swapped = original
                    try swapped.swapPanes()
                    XCTAssertEqual(swapped.visualOrder, expectedOrder)
                    XCTAssertEqual(swapped.activePane, activePane)
                    XCTAssertEqual(
                        swapped.activeVisualIndex,
                        expectedOrder.firstIndex(of: activePane)
                    )
                    XCTAssertEqual(swapped.splitFractions, original.splitFractions)

                    try swapped.swapPanes()
                    XCTAssertEqual(swapped, original)
                }
            }
        }
    }

    func testTinyUnrepresentableSizePreservingSwapIsAtomic() throws {
        var layout = try PaneLayout(
            paneCount: .three,
            visualOrder: [.left, .middle, .right],
            splitFractions: [1e-20, 0.5],
            minimumPaneFraction: 1e-20
        )
        let unchanged = layout

        assertLayoutError(
            .unrepresentablePaneFraction(index: 2, fraction: 1e-20),
            try layout.swapVisualPanes(at: 0, and: 2, preservingPaneSizes: true)
        )
        XCTAssertEqual(layout, unchanged)
    }

    func testOwnerValuesRemapAcrossEveryPermutationWithoutChangingOwnership() throws {
        let owners = Dictionary(
            uniqueKeysWithValues: PaneIdentity.allCases.map { ($0, Owner($0.rawValue)) }
        )
        let ownedValues = PaneIdentity.allCases.reversed().map {
            PaneOwnedValue(identity: $0, value: owners[$0]!)
        }

        for sourceOrder in orders(for: .three) {
            let source = try PaneLayout(visualOrder: sourceOrder)
            let sourceValues = sourceOrder.map { owners[$0]!.name }
            XCTAssertEqual(
                try source.valuesByIdentity(fromVisualValues: sourceValues),
                Dictionary(uniqueKeysWithValues: PaneIdentity.allCases.map { ($0, $0.rawValue) })
            )

            for destinationOrder in orders(for: .three) {
                let destination = try PaneLayout(visualOrder: destinationOrder)
                XCTAssertEqual(
                    try destination.remapVisualValues(sourceValues, from: source),
                    destinationOrder.map(\.rawValue)
                )

                let remappedOwners = try destination.remapOwnedValues(ownedValues)
                XCTAssertEqual(remappedOwners.map(\.identity), destinationOrder)
                for (index, identity) in destinationOrder.enumerated() {
                    XCTAssertTrue(remappedOwners[index].value === owners[identity])
                }
            }
        }
    }

    func testOwnerRemappingRejectsMissingExtraDuplicateAndIncompatibleValues() throws {
        let twoPane = try PaneLayout(paneCount: .two)
        let threePane = try PaneLayout(paneCount: .three)

        assertLayoutError(
            .invalidOwnershipIdentities([.left]),
            try twoPane.valuesInVisualOrder([.left: "left"])
        )
        assertLayoutError(
            .invalidOwnershipIdentities([.left, .middle, .right]),
            try twoPane.valuesInVisualOrder([.left: "left", .middle: "middle", .right: "right"])
        )
        assertLayoutError(
            .invalidVisualValueCount(expected: 2, actual: 1),
            try twoPane.valuesByIdentity(fromVisualValues: ["left"])
        )
        assertLayoutError(
            .invalidVisualValueCount(expected: 2, actual: 3),
            try twoPane.remapVisualValues(["left", "right", "extra"], from: twoPane)
        )
        assertLayoutError(
            .duplicateOwnedIdentity(.left),
            try twoPane.ownedValuesInVisualOrder([
                PaneOwnedValue(identity: .left, value: "first"),
                PaneOwnedValue(identity: .left, value: "second")
            ])
        )
        assertLayoutError(
            .invalidOwnershipIdentities([.left, .middle]),
            try twoPane.remapOwnedValues([
                PaneOwnedValue(identity: .left, value: "left"),
                PaneOwnedValue(identity: .middle, value: "unexpected")
            ])
        )
        assertLayoutError(
            .incompatiblePaneCounts(source: 2, destination: 3),
            try threePane.remapVisualValues(["left", "right"], from: twoPane)
        )
    }

    func testOrientationMutationAndValueOperationsPreserveOtherLayoutState() throws {
        XCTAssertEqual(PaneLayout.Orientation.allCases, [.vertical, .horizontal])
        XCTAssertEqual(PaneLayout.Orientation.vertical.toggled, .horizontal)
        XCTAssertEqual(PaneLayout.Orientation.horizontal.toggled, .vertical)

        var layout = try PaneLayout(
            paneCount: .three,
            activePane: .right,
            visualOrder: [.middle, .right, .left],
            orientation: .vertical,
            splitFractions: [0.25, 0.75]
        )
        let original = layout
        let horizontal = layout.settingOrientation(.horizontal)
        XCTAssertEqual(horizontal.orientation, .horizontal)
        XCTAssertEqual(layout, original)
        XCTAssertEqual(horizontal.visualOrder, layout.visualOrder)
        XCTAssertEqual(horizontal.splitFractions, layout.splitFractions)
        XCTAssertEqual(horizontal.activePane, layout.activePane)

        layout.toggleOrientation()
        XCTAssertEqual(layout, horizontal)
        let vertical = layout.togglingOrientation()
        XCTAssertEqual(vertical, original)
        XCTAssertEqual(layout, horizontal)
        layout.setOrientation(.vertical)
        XCTAssertEqual(layout, original)
    }

    func testNormalizedSplitFractionsAreScaleIndependentAndRoundTripPaneSizes() throws {
        assertDoublesEqual(
            try PaneLayout.normalizedSplitFractions(forPaneSizes: [3, 1], paneCount: .two),
            [0.75]
        )
        assertDoublesEqual(
            try PaneLayout.normalizedSplitFractions(forPaneSizes: [2, 3, 5], paneCount: .three),
            [0.2, 0.5]
        )
        assertDoublesEqual(
            try PaneLayout.normalizedSplitFractions(
                forPaneSizes: [
                    Double.greatestFiniteMagnitude,
                    Double.greatestFiniteMagnitude,
                    Double.greatestFiniteMagnitude
                ],
                paneCount: .three
            ),
            [1.0 / 3.0, 2.0 / 3.0]
        )
        assertDoublesEqual(
            try PaneLayout.normalizedSplitFractions(
                forPaneSizes: Array(repeating: Double.leastNonzeroMagnitude, count: 3),
                paneCount: .three
            ),
            [1.0 / 3.0, 2.0 / 3.0]
        )

        var layout = try PaneLayout(paneCount: .three)
        try layout.setPaneSizes([160, 410, 70], minimumPaneSize: 70)
        assertDoublesEqual(layout.splitFractions, [0.25, 0.890625])
        assertDoublesEqual(layout.paneFractions, [0.25, 0.640625, 0.109375])
        assertDoublesEqual(try layout.paneSizes(forTotalSize: 640), [160, 410, 70])

        let scaled = try PaneLayout.normalizedSplitFractions(
            forPaneSizes: [16, 41, 7],
            paneCount: .three
        )
        assertDoublesEqual(scaled, layout.splitFractions)
    }

    func testLegacyMigrationPreservesEveryRepresentableOpenIntervalBoundary() throws {
        let fractions = [
            Double.leastNonzeroMagnitude,
            Double.leastNormalMagnitude,
            1e-20,
            0.05,
            0.1,
            0.5,
            0.9,
            1.0.nextDown
        ]

        for fraction in fractions {
            let layout = try PaneLayout(
                migratingLegacySplitFraction: fraction,
                activePane: .right,
                orientation: .horizontal
            )
            XCTAssertEqual(layout.paneCount, .two)
            XCTAssertEqual(layout.activePane, .right)
            XCTAssertEqual(layout.orientation, .horizontal)
            XCTAssertEqual(layout.splitFractions, [fraction])
            XCTAssertEqual(
                layout.minimumPaneFraction,
                min(PaneLayout.defaultMinimumPaneFraction, min(fraction, 1.0 - fraction))
            )
            try layout.validate()

            let encoded = try layout.encodedData()
            XCTAssertEqual(try PaneLayout.decode(from: encoded), layout)
            if fraction <= 1e-20 {
                XCTAssertTrue(String(decoding: encoded, as: UTF8.self).lowercased().contains("e-"))
            }
        }

        for fraction in [-Double.infinity, -1, 0, 1, 1.0.nextUp, Double.infinity] {
            assertLayoutError(
                .invalidSplitFraction(index: 0, value: fraction),
                try PaneLayout(migratingLegacySplitFraction: fraction)
            )
        }
        XCTAssertThrowsError(try PaneLayout(migratingLegacySplitFraction: .nan)) { error in
            guard case .invalidSplitFraction(let index, let value) = error as? PaneLayoutError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(index, 0)
            XCTAssertTrue(value.isNaN)
        }
    }

    func testInvalidConstructionSplitAndSizeStatesFailClosedAndAtomically() throws {
        assertLayoutError(.invalidPaneCount(1), try PaneLayout(visualOrder: [.left]))
        assertLayoutError(
            .invalidVisualOrder([.left, .left]),
            try PaneLayout(paneCount: .two, visualOrder: [.left, .left])
        )
        assertLayoutError(
            .invalidVisualOrder([.left, .middle]),
            try PaneLayout(paneCount: .two, visualOrder: [.left, .middle])
        )
        assertLayoutError(
            .identityNotPresent(.middle),
            try PaneLayout(paneCount: .two, activePane: .middle)
        )
        assertLayoutError(
            .nonFiniteMinimumPaneFraction,
            try PaneLayout(paneCount: .two, minimumPaneFraction: .nan)
        )
        assertLayoutError(
            .invalidMinimumPaneFraction(0, maximum: 0.5),
            try PaneLayout(paneCount: .two, minimumPaneFraction: 0)
        )
        assertLayoutError(
            .invalidMinimumPaneFraction(0.34, maximum: 1.0 / 3.0),
            try PaneLayout(paneCount: .three, minimumPaneFraction: 0.34)
        )
        let maximumTwoPaneMinimum = try PaneLayout(
            paneCount: .two,
            minimumPaneFraction: 0.5
        )
        XCTAssertEqual(maximumTwoPaneMinimum.minimumPaneFraction, 0.5)
        assertDoublesEqual(maximumTwoPaneMinimum.paneFractions, [0.5, 0.5])
        try maximumTwoPaneMinimum.validate()

        let maximumThreePaneMinimum = try PaneLayout(
            paneCount: .three,
            minimumPaneFraction: 1.0 / 3.0
        )
        XCTAssertEqual(maximumThreePaneMinimum.minimumPaneFraction, 1.0 / 3.0)
        assertDoublesEqual(
            maximumThreePaneMinimum.paneFractions,
            Array(repeating: 1.0 / 3.0, count: 3)
        )
        try maximumThreePaneMinimum.validate()
        assertLayoutError(
            .invalidSplitFractionCount(expected: 2, actual: 1),
            try PaneLayout(paneCount: .three, splitFractions: [0.5])
        )
        assertLayoutError(
            .nonFiniteSplitFraction(index: 0),
            try PaneLayout(paneCount: .two, splitFractions: [.infinity])
        )
        assertLayoutError(
            .invalidSplitFraction(index: 1, value: 0.4),
            try PaneLayout(paneCount: .three, splitFractions: [0.5, 0.4])
        )
        assertLayoutError(
            .paneFractionBelowMinimum(index: 0, fraction: 0.05, minimum: 0.1),
            try PaneLayout(paneCount: .two, splitFractions: [0.05])
        )
        assertLayoutError(
            .paneFractionBelowMinimum(index: 1, fraction: 0.050000000000000044, minimum: 0.1),
            try PaneLayout(paneCount: .two, splitFractions: [0.95])
        )

        var layout = try PaneLayout(
            paneCount: .three,
            activePane: .right,
            visualOrder: [.middle, .right, .left],
            orientation: .horizontal
        )
        try layout.setSplitFractions([0.2, 0.7])
        let expectedAfterSet = try PaneLayout(
            paneCount: .three,
            activePane: .right,
            visualOrder: [.middle, .right, .left],
            orientation: .horizontal,
            splitFractions: [0.2, 0.7]
        )
        XCTAssertEqual(layout, expectedAfterSet)

        let unchanged = layout
        assertLayoutError(
            .invalidSplitFractionCount(expected: 2, actual: 1),
            try layout.setSplitFractions([0.5])
        )
        XCTAssertEqual(layout, unchanged)
        assertLayoutError(
            .invalidPaneSizeCount(expected: 3, actual: 2),
            try layout.setPaneSizes([1, 1])
        )
        assertLayoutError(.nonFinitePaneSize(index: 1), try layout.setPaneSizes([1, .nan, 1]))
        assertLayoutError(.nonPositivePaneSize(index: 1, size: 0), try layout.setPaneSizes([1, 0, 1]))
        assertLayoutError(
            .paneSizeBelowMinimum(index: 2, size: 70, minimum: 71),
            try layout.setPaneSizes([160, 410, 70], minimumPaneSize: 71)
        )
        assertLayoutError(.nonFiniteMinimumPaneSize, try layout.setPaneSizes([1, 1, 1], minimumPaneSize: .nan))
        assertLayoutError(.negativeMinimumPaneSize(-1), try layout.setPaneSizes([1, 1, 1], minimumPaneSize: -1))
        XCTAssertEqual(layout, unchanged)
    }

    func testInvalidLookupSwapAndTotalSizeOperationsLeaveLayoutUnchanged() throws {
        var layout = try PaneLayout(paneCount: .two, splitFractions: [0.25])
        let unchanged = layout

        assertLayoutError(.identicalSwapIdentities(.left), try layout.swapPanes(.left, .left))
        assertLayoutError(.identityNotPresent(.middle), try layout.swapPanes(.left, .middle))
        assertLayoutError(.invalidVisualIndex(-1), try layout.swapVisualPanes(at: -1, and: 1))
        assertLayoutError(.invalidVisualIndex(2), try layout.swapVisualPanes(at: 0, and: 2))
        assertLayoutError(.identicalVisualIndices(0), try layout.swapVisualPanes(at: 0, and: 0))
        XCTAssertEqual(layout, unchanged)

        assertLayoutError(.nonFiniteTotalSize, try layout.paneSizes(forTotalSize: .infinity))
        assertLayoutError(.nonPositiveTotalSize(0), try layout.paneSizes(forTotalSize: 0))
        assertLayoutError(.nonFiniteMinimumPaneSize, try layout.paneSizes(forTotalSize: 100, minimumPaneSize: .nan))
        assertLayoutError(.negativeMinimumPaneSize(-1), try layout.paneSizes(forTotalSize: 100, minimumPaneSize: -1))
        assertLayoutError(
            .minimumPaneSizeExceedsAvailableSize(minimumPaneSize: 51, totalSize: 100),
            try layout.paneSizes(forTotalSize: 100, minimumPaneSize: 51)
        )
        assertLayoutError(
            .paneSizeBelowMinimum(index: 0, size: 25, minimum: 40),
            try layout.paneSizes(forTotalSize: 100, minimumPaneSize: 40)
        )

        for paneCount in PaneLayout.PaneCount.allCases {
            let equalLayout = try PaneLayout(paneCount: paneCount)
            let minimumPaneSize = 30.0
            let totalSize = minimumPaneSize * Double(paneCount.rawValue)
            assertDoublesEqual(
                try equalLayout.paneSizes(
                    forTotalSize: totalSize,
                    minimumPaneSize: minimumPaneSize
                ),
                Array(repeating: minimumPaneSize, count: paneCount.rawValue)
            )
        }
    }

    func testPersistenceIsCompactDeterministicSortedAndRoundTrips() throws {
        let layout = try PaneLayout(
            paneCount: .three,
            activePane: .middle,
            visualOrder: [.right, .middle, .left],
            orientation: .horizontal,
            splitFractions: [0.25, 0.75]
        )
        let first = try layout.encodedData()
        let second = try layout.encodedData()
        let expectedJSON =
            #"{"activePane":"middle","minimumPaneFraction":0.1,"orientation":"horizontal","#
            + #""paneCount":3,"schemaVersion":1,"splitFractions":[0.25,0.75],"#
            + #""visualOrder":["right","middle","left"]}"#

        XCTAssertEqual(first, second)
        XCTAssertEqual(String(decoding: first, as: UTF8.self), expectedJSON)
        XCTAssertFalse(first.contains(0x0A))
        XCTAssertLessThanOrEqual(first.count, PaneLayout.maximumEncodedBytes)
        XCTAssertEqual(try PaneLayout.decode(from: first), layout)

        let owned = PaneOwnedValue(identity: PaneIdentity.middle, value: "document")
        XCTAssertEqual(
            try JSONDecoder().decode(
                PaneOwnedValue<String>.self,
                from: JSONEncoder().encode(owned)
            ),
            owned
        )
    }

    func testBoundedDecodeAcceptsExactLimitAndRejectsOversizeAndDirectCodableBypass() throws {
        let layout = try PaneLayout(paneCount: .two, activePane: .right)
        let directData = try JSONEncoder().encode(layout)
        XCTAssertEqual(try PaneLayout.decode(from: directData), layout)

        assertLayoutError(
            .boundedDecodingRequired,
            try JSONDecoder().decode(PaneLayout.self, from: directData)
        )

        var padded = try layout.encodedData()
        padded.append(
            Data(
                repeating: 0x20,
                count: PaneLayout.maximumEncodedBytes - padded.count
            )
        )
        XCTAssertEqual(padded.count, PaneLayout.maximumEncodedBytes)
        XCTAssertEqual(try PaneLayout.decode(from: padded), layout)

        padded.append(0x20)
        assertLayoutError(
            .persistenceDataTooLarge(maximumBytes: PaneLayout.maximumEncodedBytes),
            try PaneLayout.decode(from: padded)
        )
    }

    func testDuplicateDecodedJSONKeysAreRejectedAtEveryObjectDepth() throws {
        let layout = try PaneLayout(paneCount: .two)
        let base = String(decoding: try layout.encodedData(), as: UTF8.self)
        let withoutClosingBrace = String(base.dropLast())
        let duplicateRoot = withoutClosingBrace + #", "schema\u0056ersion":1}"#
        let duplicateNested = withoutClosingBrace + #", "padding":{"x":1,"\u0078":2}}"#
        let duplicateInsideArray =
            withoutClosingBrace + #", "padding":[{"x":1,"\u0078":2}]}"#
        let deepPrefix = String(repeating: "[", count: 14)
        let deepSuffix = String(repeating: "]", count: 14)
        let duplicateAtMaximumDepth =
            withoutClosingBrace
            + #", "padding":\#(deepPrefix){"x":1,"\u0078":2}\#(deepSuffix)}"#

        assertLayoutError(
            .duplicateJSONKey("schemaVersion"),
            try PaneLayout.decode(from: Data(duplicateRoot.utf8))
        )
        assertLayoutError(
            .duplicateJSONKey("x"),
            try PaneLayout.decode(from: Data(duplicateNested.utf8))
        )
        assertLayoutError(
            .duplicateJSONKey("x"),
            try PaneLayout.decode(from: Data(duplicateInsideArray.utf8))
        )
        assertLayoutError(
            .duplicateJSONKey("x"),
            try PaneLayout.decode(from: Data(duplicateAtMaximumDepth.utf8))
        )
    }

    func testDecodeRejectsInvalidJSONNestingSchemaAndLayoutStates() throws {
        let valid = try PaneLayout(paneCount: .two).encodedData()
        assertLayoutError(.invalidJSON, try PaneLayout.decode(from: Data()))
        assertLayoutError(.invalidJSON, try PaneLayout.decode(from: valid + Data(" trailing".utf8)))
        assertLayoutError(
            .invalidJSON,
            try PaneLayout.decode(
                from: Data(layoutJSON(addingRootMember: #""padding":01"#).utf8)
            )
        )

        let depth16Value =
            String(repeating: "[", count: 15) + "0" + String(repeating: "]", count: 15)
        XCTAssertEqual(
            try PaneLayout.decode(
                from: Data(layoutJSON(addingRootMember: #""padding":\#(depth16Value)"#).utf8)
            ),
            try PaneLayout(paneCount: .two)
        )

        let depth17Value =
            String(repeating: "[", count: 16) + "0" + String(repeating: "]", count: 16)
        assertLayoutError(
            .jsonNestingTooDeep(maximumDepth: 16),
            try PaneLayout.decode(
                from: Data(layoutJSON(addingRootMember: #""padding":\#(depth17Value)"#).utf8)
            )
        )
        assertLayoutError(
            .unsupportedSchemaVersion(2),
            try PaneLayout.decode(from: Data(layoutJSON(schemaVersion: 2).utf8))
        )
        assertLayoutError(
            .invalidPaneCount(4),
            try PaneLayout.decode(from: Data(layoutJSON(paneCount: 4).utf8))
        )
        assertLayoutError(
            .invalidVisualOrder([.left, .left]),
            try PaneLayout.decode(from: Data(layoutJSON(visualOrder: #"["left","left"]"#).utf8))
        )
        assertLayoutError(
            .identityNotPresent(.middle),
            try PaneLayout.decode(from: Data(layoutJSON(activePane: "middle").utf8))
        )
        assertLayoutError(
            .invalidSplitFractionCount(expected: 1, actual: 0),
            try PaneLayout.decode(from: Data(layoutJSON(splitFractions: "[]").utf8))
        )
        assertLayoutError(
            .invalidMinimumPaneFraction(0, maximum: 0.5),
            try PaneLayout.decode(from: Data(layoutJSON(minimumPaneFraction: "0").utf8))
        )

        XCTAssertThrowsError(
            try PaneLayout.decode(from: Data(layoutJSON(activePane: "unknown").utf8))
        ) { XCTAssertTrue($0 is DecodingError) }
        XCTAssertThrowsError(
            try PaneLayout.decode(from: Data(layoutJSON(orientation: "diagonal").utf8))
        ) { XCTAssertTrue($0 is DecodingError) }
        assertLayoutError(
            .invalidPaneCount(4),
            try JSONDecoder().decode(PaneLayout.PaneCount.self, from: Data("4".utf8))
        )
    }

    private func orders(for paneCount: PaneLayout.PaneCount) -> [[PaneIdentity]] {
        switch paneCount {
        case .two:
            [
                [.left, .right],
                [.right, .left]
            ]
        case .three:
            [
                [.left, .middle, .right],
                [.left, .right, .middle],
                [.middle, .left, .right],
                [.middle, .right, .left],
                [.right, .left, .middle],
                [.right, .middle, .left]
            ]
        }
    }

    private func layoutJSON(
        schemaVersion: Int = 1,
        paneCount: Int = 2,
        activePane: String = "left",
        visualOrder: String = #"["left","right"]"#,
        orientation: String = "vertical",
        splitFractions: String = "[0.5]",
        minimumPaneFraction: String = "0.1",
        addingRootMember member: String? = nil
    ) -> String {
        let suffix = member.map { ",\($0)" } ?? ""
        return #"{"schemaVersion":\#(schemaVersion),"paneCount":\#(paneCount),"#
            + #""activePane":"\#(activePane)","visualOrder":\#(visualOrder),"#
            + #""orientation":"\#(orientation)","splitFractions":\#(splitFractions),"#
            + #""minimumPaneFraction":\#(minimumPaneFraction)\#(suffix)}"#
    }

    private func assertDoublesEqual(
        _ actual: [Double],
        _ expected: [Double],
        accuracy: Double = 1e-12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualValue, expectedValue) in zip(actual, expected) {
            XCTAssertEqual(actualValue, expectedValue, accuracy: accuracy, file: file, line: line)
        }
    }

    private func assertLayoutError<T>(
        _ expected: PaneLayoutError,
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? PaneLayoutError, expected, file: file, line: line)
        }
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

private final class Owner: @unchecked Sendable {
    let name: String

    init(_ name: String) {
        self.name = name
    }
}
