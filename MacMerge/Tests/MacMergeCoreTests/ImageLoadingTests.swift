import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import MacMergeCore

final class ImageLoadingTests: XCTestCase {
    func testPNGLoadsIntoCanonicalRGBAStorage() throws {
        let encoded = try encodedImage(
            typeIdentifier: UTType.png.identifier,
            frames: [Data([255, 0, 0, 255, 0, 255, 0, 255])],
            width: 2,
            height: 1
        )

        let image = try BoundedImageLoader.normalize(data: encoded)

        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 1)
        XCTAssertEqual(image.rgba8Premultiplied.count, 8)
        XCTAssertEqual(Array(image.rgba8Premultiplied), [255, 0, 0, 255, 0, 255, 0, 255])
    }

    func testLosslessFormatsNormalizeToIdenticalPixels() throws {
        let pixels = Data([10, 20, 30, 255, 40, 50, 60, 255])
        let png = try encodedImage(
            typeIdentifier: UTType.png.identifier,
            frames: [pixels],
            width: 1,
            height: 2
        )
        let tiff = try encodedImage(
            typeIdentifier: UTType.tiff.identifier,
            frames: [pixels],
            width: 1,
            height: 2
        )

        let normalizedPNG = try BoundedImageLoader.normalize(data: png)
        XCTAssertEqual(normalizedPNG.width, 1)
        XCTAssertEqual(normalizedPNG.height, 2)
        XCTAssertEqual(normalizedPNG.rgba8Premultiplied, pixels)
        XCTAssertEqual(normalizedPNG, try BoundedImageLoader.normalize(data: tiff))
    }

    func testWideGamutSemitransparentPixelsBecomePremultipliedSRGB() throws {
        let encoded = try encodedImage(
            typeIdentifier: UTType.png.identifier,
            frames: [Data([64, 96, 32, 128])],
            width: 1,
            height: 1,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)
        )

        let image = try BoundedImageLoader.normalize(data: encoded)

        XCTAssertEqual(Array(image.rgba8Premultiplied), [54, 97, 14, 128])
    }

    func testAsymmetricOrientationMetadataTransformsDimensionsAndRows() throws {
        let encoded = try encodedImage(
            typeIdentifier: UTType.tiff.identifier,
            frames: [
                Data([
                    255, 0, 0, 255,
                    0, 255, 0, 255,
                    0, 0, 255, 255,
                    255, 255, 0, 255,
                    255, 0, 255, 255,
                    0, 255, 255, 255
                ])
            ],
            width: 2,
            height: 3,
            imageProperties: [
                kCGImagePropertyOrientation: 6
            ]
        )

        let image = try BoundedImageLoader.normalize(data: encoded)

        XCTAssertEqual(image.width, 3)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(
            Array(image.rgba8Premultiplied),
            [
                255, 0, 255, 255,
                0, 0, 255, 255,
                255, 0, 0, 255,
                0, 255, 255, 255,
                255, 255, 0, 255,
                0, 255, 0, 255
            ]
        )
    }

    func testEncodedAndDecodedBoundsFailClosed() throws {
        let encoded = try encodedImage(
            typeIdentifier: UTType.png.identifier,
            frames: [Data(repeating: 255, count: 2 * 2 * 4)],
            width: 2,
            height: 2
        )
        let encodedLimit = ImageComparisonLimits(
            maximumEncodedBytes: encoded.count - 1,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 400
        )
        XCTAssertThrowsError(try BoundedImageLoader.normalize(data: encoded, limits: encodedLimit)) {
            XCTAssertEqual(
                $0 as? ImageComparisonError,
                .encodedFileTooLarge(maximumBytes: encoded.count - 1)
            )
        }

        let exactLimits = ImageComparisonLimits(
            maximumEncodedBytes: encoded.count,
            maximumDimension: 2,
            maximumPixelCount: 4,
            maximumDecodedBytes: 48
        )
        XCTAssertEqual(
            try BoundedImageLoader.normalize(data: encoded, limits: exactLimits).rgba8Premultiplied.count,
            16
        )

        let dimensionLimit = ImageComparisonLimits(
            maximumEncodedBytes: encoded.count,
            maximumDimension: 1,
            maximumPixelCount: 100,
            maximumDecodedBytes: 400
        )
        XCTAssertThrowsError(try BoundedImageLoader.normalize(data: encoded, limits: dimensionLimit)) {
            XCTAssertEqual(
                $0 as? ImageComparisonError,
                .imageDimensionsExceeded(width: 2, height: 2, maximumDimension: 1)
            )
        }

        let pixelLimit = ImageComparisonLimits(
            maximumEncodedBytes: encoded.count,
            maximumDimension: 10,
            maximumPixelCount: 3,
            maximumDecodedBytes: 400
        )
        XCTAssertThrowsError(try BoundedImageLoader.normalize(data: encoded, limits: pixelLimit)) {
            XCTAssertEqual(
                $0 as? ImageComparisonError,
                .imagePixelCountExceeded(maximumPixels: 3)
            )
        }

        let decodedLimit = ImageComparisonLimits(
            maximumEncodedBytes: encoded.count,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 15
        )
        XCTAssertThrowsError(try BoundedImageLoader.normalize(data: encoded, limits: decodedLimit)) {
            XCTAssertEqual(
                $0 as? ImageComparisonError,
                .decodedImageTooLarge(maximumBytes: 15)
            )
        }

        let aggregateDecodedLimit = ImageComparisonLimits(
            maximumEncodedBytes: encoded.count,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 47
        )
        XCTAssertThrowsError(
            try BoundedImageLoader.normalize(data: encoded, limits: aggregateDecodedLimit)
        ) {
            XCTAssertEqual(
                $0 as? ImageComparisonError,
                .decodedImageTooLarge(maximumBytes: 47)
            )
        }
    }

    func testFileReadAppliesEncodedBound() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0, count: 9).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let limits = ImageComparisonLimits(
            maximumEncodedBytes: 8,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 400
        )

        XCTAssertThrowsError(try BoundedImageLoader.load(from: url, limits: limits)) {
            XCTAssertEqual(
                $0 as? ImageComparisonError,
                .encodedFileTooLarge(maximumBytes: 8)
            )
        }
    }

    func testBoundedReaderRejectsStreamGrowthBeyondAdvertisedSize() throws {
        let maximumEncodedBytes = 64 * 1024 + 2
        let limits = ImageComparisonLimits(
            maximumEncodedBytes: maximumEncodedBytes,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 400
        )
        let stream = Data(repeating: 0xA5, count: maximumEncodedBytes + 1)
        var offset = 0
        var requestedReadSizes: [Int] = []

        XCTAssertThrowsError(
            try BoundedImageLoader.readBoundedData(expectedSize: 4, limits: limits) { count in
                requestedReadSizes.append(count)
                guard offset < stream.count else { return nil }
                let end = min(offset + count, stream.count)
                defer { offset = end }
                return stream[offset..<end]
            }
        ) { error in
            XCTAssertEqual(
                error as? ImageComparisonError,
                .encodedFileTooLarge(maximumBytes: maximumEncodedBytes)
            )
        }
        XCTAssertEqual(offset, stream.count)
        XCTAssertEqual(requestedReadSizes, [64 * 1024, 3])
    }

    func testBoundedReaderRejectsProviderChunkLargerThanRequested() throws {
        let maximumEncodedBytes = 64 * 1024 + 2
        let limits = ImageComparisonLimits(
            maximumEncodedBytes: maximumEncodedBytes,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 400
        )
        var readCount = 0

        XCTAssertThrowsError(
            try BoundedImageLoader.readBoundedData(expectedSize: 0, limits: limits) { requested in
                readCount += 1
                XCTAssertEqual(requested, 64 * 1024)
                return Data(repeating: 0xA5, count: requested + 1)
            }
        ) { error in
            XCTAssertEqual(
                error as? ImageComparisonError,
                .encodedFileTooLarge(maximumBytes: maximumEncodedBytes)
            )
        }
        XCTAssertEqual(readCount, 1)
    }

    func testBoundedReaderRejectsChunkThatOverrunsRemainingCapacity() throws {
        let limits = ImageComparisonLimits(
            maximumEncodedBytes: 8,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 400
        )
        var readCount = 0

        XCTAssertThrowsError(
            try BoundedImageLoader.readBoundedData(expectedSize: 0, limits: limits) { requested in
                readCount += 1
                XCTAssertEqual(requested, 9)
                return Data(repeating: 0xA5, count: requested)
            }
        ) { error in
            XCTAssertEqual(
                error as? ImageComparisonError,
                .encodedFileTooLarge(maximumBytes: 8)
            )
        }
        XCTAssertEqual(readCount, 1)
    }

    func testPreCancelledNormalizationStopsBeforeImageIOWork() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try BoundedImageLoader.normalize(data: Data("not an image".utf8))
        }

        do {
            _ = try await task.value
            XCTFail("Expected preflight cancellation")
        } catch {
            XCTAssertEqual(error as? ImageComparisonError, .cancelled)
        }
    }

    func testPreCancelledFileLoadStopsBeforeMetadataWork() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try BoundedImageLoader.load(from: missingURL)
        }

        do {
            _ = try await task.value
            XCTFail("Expected preflight cancellation")
        } catch {
            XCTAssertEqual(error as? ImageComparisonError, .cancelled)
        }
    }

    func testPreCancelledBoundedReaderDoesNotCallProvider() async {
        let task = Task { () -> (ImageComparisonError?, Int) in
            withUnsafeCurrentTask { $0?.cancel() }
            var providerReadCount = 0

            do {
                _ = try BoundedImageLoader.readBoundedData(
                    expectedSize: 0,
                    limits: .default
                ) { _ in
                    providerReadCount += 1
                    return nil
                }
                return (nil, providerReadCount)
            } catch {
                return (error as? ImageComparisonError, providerReadCount)
            }
        }

        let (error, providerReadCount) = await task.value
        XCTAssertEqual(error, .cancelled)
        XCTAssertEqual(providerReadCount, 0)
    }

    func testUnsupportedFormatAndMultipleFramesFailClosed() throws {
        let gif = try encodedImage(
            typeIdentifier: UTType.gif.identifier,
            frames: [Data([0, 0, 0, 255])],
            width: 1,
            height: 1
        )
        let pngOnly = ImageComparisonLimits(
            maximumEncodedBytes: gif.count,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 400,
            supportedTypeIdentifiers: [UTType.png.identifier]
        )
        XCTAssertThrowsError(try BoundedImageLoader.normalize(data: gif, limits: pngOnly)) {
            XCTAssertEqual(
                $0 as? ImageComparisonError,
                .unsupportedFormat(typeIdentifier: UTType.gif.identifier)
            )
        }

        let animatedGIF = try encodedImage(
            typeIdentifier: UTType.gif.identifier,
            frames: [Data([0, 0, 0, 255]), Data([255, 255, 255, 255])],
            width: 1,
            height: 1
        )
        XCTAssertThrowsError(try BoundedImageLoader.normalize(data: animatedGIF)) {
            XCTAssertEqual($0 as? ImageComparisonError, .unsupportedFrameCount(2))
        }

        let animatedPNGOnly = ImageComparisonLimits(
            maximumEncodedBytes: animatedGIF.count,
            maximumDimension: 10,
            maximumPixelCount: 100,
            maximumDecodedBytes: 400,
            supportedTypeIdentifiers: [UTType.png.identifier]
        )
        XCTAssertThrowsError(
            try BoundedImageLoader.normalize(data: animatedGIF, limits: animatedPNGOnly)
        ) {
            XCTAssertEqual(
                $0 as? ImageComparisonError,
                .unsupportedFormat(typeIdentifier: UTType.gif.identifier)
            )
        }

        let manyFrameGIF = try encodedImage(
            typeIdentifier: UTType.gif.identifier,
            frames: Array(repeating: Data([0, 0, 0, 255]), count: 128),
            width: 1,
            height: 1
        )
        XCTAssertThrowsError(try BoundedImageLoader.normalize(data: manyFrameGIF)) {
            XCTAssertEqual($0 as? ImageComparisonError, .unsupportedFrameCount(2))
        }

        XCTAssertThrowsError(try BoundedImageLoader.normalize(data: Data("not an image".utf8))) {
            XCTAssertEqual($0 as? ImageComparisonError, .invalidImage)
        }
    }

    private func encodedImage(
        typeIdentifier: String,
        frames: [Data],
        width: Int,
        height: Int,
        colorSpace: CGColorSpace? = nil,
        imageProperties: [CFString: Any]? = nil
    ) throws -> Data {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                typeIdentifier as CFString,
                frames.count,
                nil
            )
        else {
            throw EncodingError.destination
        }

        for frame in frames {
            guard let provider = CGDataProvider(data: frame as CFData),
                let colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                let image = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    ),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                )
            else {
                throw EncodingError.image
            }
            CGImageDestinationAddImage(destination, image, imageProperties as CFDictionary?)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.finalize
        }
        return output as Data
    }

    private enum EncodingError: Error {
        case destination
        case image
        case finalize
    }
}
