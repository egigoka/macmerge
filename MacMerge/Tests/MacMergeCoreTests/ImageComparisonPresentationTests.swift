import MacMergeCore
import XCTest

final class ImageComparisonPresentationTests: XCTestCase {
    func testDifferenceNavigationUsesStableRegionOrderWithoutWrapping() {
        var state = ImageComparisonPresentationState(comparison: comparison(regionCount: 3))

        XCTAssertTrue(state.canSelectNextDifference)
        XCTAssertTrue(state.selectNextDifference())
        XCTAssertEqual(state.selectedDifferenceIndex, 0)
        XCTAssertEqual(state.selectedDifferenceNumber, 1)
        XCTAssertTrue(state.selectNextDifference())
        XCTAssertTrue(state.selectLastDifference())
        XCTAssertEqual(state.selectedDifferenceIndex, 2)
        XCTAssertFalse(state.canSelectNextDifference)
        XCTAssertFalse(state.selectNextDifference())
        XCTAssertEqual(state.selectedDifferenceIndex, 2)
        XCTAssertTrue(state.selectPreviousDifference())
        XCTAssertEqual(state.selectedRegion?.id, 1)
        XCTAssertTrue(state.selectFirstDifference())
        XCTAssertFalse(state.canSelectPreviousDifference)
        XCTAssertFalse(state.selectPreviousDifference())
    }

    func testInvalidSelectionDoesNotDiscardCurrentSelection() {
        var state = ImageComparisonPresentationState(comparison: comparison(regionCount: 2))
        XCTAssertTrue(state.selectDifference(at: 1))

        XCTAssertFalse(state.selectDifference(at: -1))
        XCTAssertFalse(state.selectDifference(at: 2))
        XCTAssertEqual(state.selectedDifferenceIndex, 1)

        state.clearSelection()
        XCTAssertNil(state.selectedRegion)
        XCTAssertTrue(state.selectPreviousDifference())
        XCTAssertEqual(state.selectedDifferenceIndex, 1)
    }

    func testReplacingComparisonResetsTransientNavigationAndBlinkState() {
        var state = ImageComparisonPresentationState(
            comparison: comparison(regionCount: 2),
            displayMode: .blink
        )
        XCTAssertTrue(state.selectLastDifference())
        XCTAssertTrue(state.advanceBlinkFrame())

        state.replaceComparison(comparison(regionCount: 1))

        XCTAssertNil(state.selectedDifferenceIndex)
        XCTAssertEqual(state.blinkVisibleSide, .left)
        XCTAssertEqual(state.regions.count, 1)
        XCTAssertEqual(state.displayMode, .blink)
    }

    func testOverlayAndBlinkLayerPresentationIsDeterministic() {
        var state = ImageComparisonPresentationState(
            comparison: comparison(regionCount: 0),
            overlayOpacity: 0.25
        )
        XCTAssertEqual(
            state.layerPresentation,
            ImageLayerPresentation(leftOpacity: 1, rightOpacity: 1)
        )
        XCTAssertFalse(state.advanceBlinkFrame())

        state.setDisplayMode(.overlay)
        XCTAssertEqual(
            state.layerPresentation,
            ImageLayerPresentation(leftOpacity: 1, rightOpacity: 0.25)
        )
        XCTAssertTrue(state.setOverlayOpacity(0.75))
        XCTAssertEqual(state.layerPresentation.rightOpacity, 0.75)

        state.setDisplayMode(.blink)
        XCTAssertEqual(
            state.layerPresentation,
            ImageLayerPresentation(leftOpacity: 1, rightOpacity: 0)
        )
        XCTAssertTrue(state.advanceBlinkFrame())
        XCTAssertEqual(
            state.layerPresentation,
            ImageLayerPresentation(leftOpacity: 0, rightOpacity: 1)
        )
        state.setDisplayMode(.overlay)
        state.setDisplayMode(.blink)
        XCTAssertEqual(state.blinkVisibleSide, .left)
    }

    func testSettingBlinkModeIsIdempotent() {
        var state = ImageComparisonPresentationState(
            comparison: comparison(regionCount: 0),
            displayMode: .blink
        )
        XCTAssertTrue(state.advanceBlinkFrame())
        XCTAssertEqual(state.blinkVisibleSide, .right)

        state.setDisplayMode(.blink)

        XCTAssertEqual(state.blinkVisibleSide, .right)
        XCTAssertEqual(
            state.layerPresentation,
            ImageLayerPresentation(leftOpacity: 0, rightOpacity: 1)
        )
    }

    func testInitialOverlayOpacityIsNormalized() {
        let cases: [(input: Double, expected: Double)] = [
            (-0.25, 0),
            (1.25, 1),
            (.nan, 0.5),
            (.infinity, 0.5),
            (-.infinity, 0.5),
        ]

        for testCase in cases {
            let state = ImageComparisonPresentationState(
                comparison: comparison(regionCount: 0),
                overlayOpacity: testCase.input
            )

            XCTAssertEqual(state.overlayOpacity, testCase.expected)
        }
    }

    func testUpdatingOverlayOpacityRejectsNonfiniteValuesWithoutChangingValue() {
        let nonfiniteOpacities: [Double] = [.nan, .infinity, -.infinity]

        for opacity in nonfiniteOpacities {
            var state = ImageComparisonPresentationState(
                comparison: comparison(regionCount: 0),
                overlayOpacity: 0.25
            )

            XCTAssertFalse(state.setOverlayOpacity(opacity))
            XCTAssertEqual(state.overlayOpacity, 0.25)
        }
    }

    func testUpdatingOverlayOpacityClampsFiniteOutOfRangeValues() {
        let cases: [(input: Double, expected: Double)] = [
            (-0.25, 0),
            (1.25, 1),
        ]

        for testCase in cases {
            var state = ImageComparisonPresentationState(comparison: comparison(regionCount: 0))

            XCTAssertTrue(state.setOverlayOpacity(testCase.input))
            XCTAssertEqual(state.overlayOpacity, testCase.expected)
        }
    }

    private func comparison(regionCount: Int) -> ImageComparisonResult {
        ImageComparisonResult(
            leftWidth: 1,
            leftHeight: 1,
            rightWidth: 1,
            rightHeight: 1,
            differingPixelCount: regionCount,
            regions: (0..<regionCount).map { index in
                ImageDifferenceRegion(
                    id: index,
                    bounds: ImagePixelRect(x: index, y: index, width: 1, height: 1),
                    pixelCount: 1
                )
            }
        )
    }
}
