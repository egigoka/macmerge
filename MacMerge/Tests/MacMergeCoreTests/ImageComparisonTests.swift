import Foundation
import XCTest

@testable import MacMergeCore

final class ImageComparisonTests: XCTestCase {
    func testComparisonProducesStableTopToBottomRegions() throws {
        let left = try image(width: 5, height: 4)
        let right = try image(
            width: 5,
            height: 4,
            changedPixels: [(0, 0), (1, 0), (4, 3)]
        )

        let first = try ImageDifferenceEngine.compare(left: left, right: right)
        let second = try ImageDifferenceEngine.compare(left: left, right: right)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.differingPixelCount, 3)
        XCTAssertEqual(
            first.regions,
            [
                ImageDifferenceRegion(
                    id: 0,
                    bounds: ImagePixelRect(x: 0, y: 0, width: 2, height: 1),
                    pixelCount: 2
                ),
                ImageDifferenceRegion(
                    id: 1,
                    bounds: ImagePixelRect(x: 4, y: 3, width: 1, height: 1),
                    pixelCount: 1
                )
            ]
        )
    }

    func testDiagonalPixelsBelongToOneEightConnectedRegion() throws {
        let left = try image(width: 2, height: 2)
        let right = try image(width: 2, height: 2, changedPixels: [(0, 0), (1, 1)])

        let result = try ImageDifferenceEngine.compare(left: left, right: right)

        XCTAssertEqual(result.regions.count, 1)
        XCTAssertEqual(result.regions[0].bounds, ImagePixelRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertEqual(result.regions[0].pixelCount, 2)
    }

    func testChannelToleranceIsInclusive() throws {
        let left = try image(width: 1, height: 1)
        let withinTolerance = try image(width: 1, height: 1, red: 10)
        let outsideTolerance = try image(width: 1, height: 1, red: 11)
        let options = ImageComparisonOptions(channelTolerance: 10)

        XCTAssertTrue(
            try ImageDifferenceEngine.compare(
                left: left,
                right: withinTolerance,
                options: options
            ).isIdentical
        )
        XCTAssertFalse(
            try ImageDifferenceEngine.compare(
                left: left,
                right: outsideTolerance,
                options: options
            ).isIdentical
        )
    }

    func testDifferentDimensionsCompareMissingPixelsButNotEmptyCanvasCorners() throws {
        let left = try image(width: 2, height: 1)
        let right = try image(width: 1, height: 2)

        let result = try ImageDifferenceEngine.compare(left: left, right: right)

        XCTAssertEqual(result.differingPixelCount, 2)
        XCTAssertEqual(result.regions.count, 1)
        XCTAssertEqual(result.regions[0].bounds, ImagePixelRect(x: 0, y: 0, width: 2, height: 2))
    }

    func testComparisonFailsClosedAtCanvasRegionAndQueueFrontierBounds() throws {
        let horizontal = try image(width: 2, height: 1)
        let vertical = try image(width: 1, height: 2)
        XCTAssertThrowsError(
            try ImageDifferenceEngine.compare(
                left: horizontal,
                right: vertical,
                options: ImageComparisonOptions(maximumCanvasPixels: 3)
            )
        ) { error in
            XCTAssertEqual(
                error as? ImageComparisonError,
                .comparisonCanvasTooLarge(maximumPixels: 3)
            )
        }

        let unchanged = try image(width: 3, height: 1)
        let separated = try image(width: 3, height: 1, changedPixels: [(0, 0), (2, 0)])
        XCTAssertThrowsError(
            try ImageDifferenceEngine.compare(
                left: unchanged,
                right: separated,
                options: ImageComparisonOptions(maximumRegions: 1)
            )
        ) { error in
            XCTAssertEqual(
                error as? ImageComparisonError,
                .tooManyDifferenceRegions(maximumRegions: 1)
            )
        }

        let center = try image(width: 3, height: 3)
        let branching = try image(
            width: 3,
            height: 3,
            changedPixels: [(1, 0), (0, 1), (1, 1), (2, 1)]
        )
        XCTAssertThrowsError(
            try ImageDifferenceEngine.compare(
                left: center,
                right: branching,
                options: ImageComparisonOptions(maximumQueuedPixels: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? ImageComparisonError,
                .comparisonTooComplex(maximumQueuedPixels: 2)
            )
        }
    }

    func testComparisonAcceptsExactCanvasRegionAndQueueFrontierBounds() throws {
        let horizontal = try image(width: 2, height: 1)
        let vertical = try image(width: 1, height: 2)
        XCTAssertEqual(
            try ImageDifferenceEngine.compare(
                left: horizontal,
                right: vertical,
                options: ImageComparisonOptions(maximumCanvasPixels: 4)
            ).differingPixelCount,
            2
        )

        let unchanged = try image(width: 3, height: 1)
        let separated = try image(width: 3, height: 1, changedPixels: [(0, 0), (2, 0)])
        XCTAssertEqual(
            try ImageDifferenceEngine.compare(
                left: unchanged,
                right: separated,
                options: ImageComparisonOptions(maximumRegions: 2)
            ).regions.count,
            2
        )

        let center = try image(width: 3, height: 3)
        let branching = try image(
            width: 3,
            height: 3,
            changedPixels: [(1, 0), (0, 1), (1, 1), (2, 1)]
        )
        XCTAssertEqual(
            try ImageDifferenceEngine.compare(
                left: center,
                right: branching,
                options: ImageComparisonOptions(maximumQueuedPixels: 3)
            ).differingPixelCount,
            4
        )
    }

    func testComparisonChecksCancellationInsideWideRows() throws {
        let left = try image(width: 8_193, height: 1)
        let right = try image(width: 8_193, height: 1)
        var cancellationChecks = 0

        XCTAssertThrowsError(
            try ImageDifferenceEngine.compare(
                left: left,
                right: right,
                options: .default
            ) {
                cancellationChecks += 1
                if cancellationChecks == 4 {
                    throw ImageComparisonError.cancelled
                }
            }
        ) { error in
            XCTAssertEqual(error as? ImageComparisonError, .cancelled)
        }
        XCTAssertEqual(cancellationChecks, 4)
    }

    func testNormalizedImageRejectsMalformedPixelStorage() {
        XCTAssertThrowsError(
            try NormalizedImage(width: 2, height: 2, rgba8Premultiplied: Data(count: 15))
        ) { error in
            XCTAssertEqual(error as? ImageComparisonError, .invalidPixelBuffer)
        }
        XCTAssertThrowsError(
            try NormalizedImage(width: Int.max, height: 2, rgba8Premultiplied: Data())
        ) { error in
            XCTAssertEqual(error as? ImageComparisonError, .invalidPixelBuffer)
        }
    }

    private func image(
        width: Int,
        height: Int,
        changedPixels: [(Int, Int)] = [],
        red: UInt8 = 255
    ) throws -> NormalizedImage {
        var bytes = Data(repeating: 0, count: width * height * 4)
        for (x, y) in changedPixels {
            let offset = (y * width + x) * 4
            bytes[offset] = red
            bytes[offset + 3] = 255
        }
        if changedPixels.isEmpty, red != 255 {
            bytes[0] = red
        }
        return try NormalizedImage(width: width, height: height, rgba8Premultiplied: bytes)
    }
}
