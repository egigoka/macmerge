import CoreGraphics
import Foundation
import ImageIO

public struct ImageComparisonLimits: Equatable, Sendable {
    public static let supportedStaticTypeIdentifiers: Set<String> = [
        "com.compuserve.gif",
        "com.microsoft.bmp",
        "public.heic",
        "public.heif",
        "public.jpeg",
        "public.png",
        "public.tiff"
    ]

    public static let `default` = ImageComparisonLimits(
        maximumEncodedBytes: 64 * 1024 * 1024,
        maximumDimension: 16_384,
        maximumPixelCount: 16 * 1024 * 1024,
        maximumDecodedBytes: 128 * 1024 * 1024
    )

    public let maximumEncodedBytes: Int
    public let maximumDimension: Int
    public let maximumPixelCount: Int
    /// Caps estimated visible decoder raster plus normalized destination bytes.
    /// ImageIO does not expose or bound its internal transient allocations.
    public let maximumDecodedBytes: Int
    public let supportedTypeIdentifiers: Set<String>

    public init(
        maximumEncodedBytes: Int,
        maximumDimension: Int,
        maximumPixelCount: Int,
        maximumDecodedBytes: Int,
        supportedTypeIdentifiers: Set<String> = supportedStaticTypeIdentifiers
    ) {
        self.maximumEncodedBytes = maximumEncodedBytes
        self.maximumDimension = maximumDimension
        self.maximumPixelCount = maximumPixelCount
        self.maximumDecodedBytes = maximumDecodedBytes
        self.supportedTypeIdentifiers = supportedTypeIdentifiers
    }
}

public enum ImageComparisonError: Error, Equatable, Sendable {
    case invalidLimits
    case unsupportedFile
    case encodedFileTooLarge(maximumBytes: Int)
    case invalidImage
    case unsupportedFormat(typeIdentifier: String?)
    case unsupportedFrameCount(Int)
    case imageDimensionsExceeded(width: Int, height: Int, maximumDimension: Int)
    case imagePixelCountExceeded(maximumPixels: Int)
    case decodedImageTooLarge(maximumBytes: Int)
    case normalizationFailed
    case invalidPixelBuffer
    case comparisonCanvasTooLarge(maximumPixels: Int)
    case tooManyDifferenceRegions(maximumRegions: Int)
    case comparisonTooComplex(maximumQueuedPixels: Int)
    case cancelled
}

public struct NormalizedImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba8Premultiplied: Data

    public init(width: Int, height: Int, rgba8Premultiplied: Data) throws {
        guard width > 0, height > 0,
            let byteCount = Self.byteCount(width: width, height: height),
            rgba8Premultiplied.count == byteCount
        else {
            throw ImageComparisonError.invalidPixelBuffer
        }

        self.width = width
        self.height = height
        self.rgba8Premultiplied = rgba8Premultiplied
    }

    fileprivate static func byteCount(width: Int, height: Int) -> Int? {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        return pixelOverflow || byteOverflow ? nil : bytes
    }
}

public enum BoundedImageLoader {
    public static func load(
        from url: URL,
        limits: ImageComparisonLimits = .default
    ) throws -> NormalizedImage {
        try validate(limits)
        try checkCancellation()

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize >= 0 else {
            throw ImageComparisonError.unsupportedFile
        }
        guard fileSize <= limits.maximumEncodedBytes else {
            throw ImageComparisonError.encodedFileTooLarge(maximumBytes: limits.maximumEncodedBytes)
        }

        let data = try readBoundedFile(from: url, expectedSize: fileSize, limits: limits)
        try checkCancellation()
        return try normalize(data: data, limits: limits)
    }

    public static func normalize(
        data: Data,
        limits: ImageComparisonLimits = .default
    ) throws -> NormalizedImage {
        try validate(limits)
        try checkCancellation()
        guard data.count <= limits.maximumEncodedBytes else {
            throw ImageComparisonError.encodedFileTooLarge(maximumBytes: limits.maximumEncodedBytes)
        }

        let sourceOptions =
            [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ImageComparisonError.invalidImage
        }

        guard let typeIdentifier = CGImageSourceGetType(source) as String? else {
            throw ImageComparisonError.invalidImage
        }
        guard limits.supportedTypeIdentifiers.contains(typeIdentifier) else {
            throw ImageComparisonError.unsupportedFormat(typeIdentifier: typeIdentifier)
        }

        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions)
                as? [CFString: Any],
            let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else {
            throw ImageComparisonError.invalidImage
        }
        try rejectAdditionalFrames(in: source, options: sourceOptions)
        try validateDimensions(width: sourceWidth, height: sourceHeight, limits: limits)
        try checkCancellation()

        let estimatedNativeRasterBytes = try estimatedDecodedRasterByteCount(
            source: source,
            limits: limits
        )
        guard
            let sourceDestinationBytes = NormalizedImage.byteCount(
                width: sourceWidth,
                height: sourceHeight
            )
        else {
            throw ImageComparisonError.decodedImageTooLarge(
                maximumBytes: limits.maximumDecodedBytes
            )
        }
        try validateDecodedWorkingSetEstimate(
            decoderRasterBytes: estimatedNativeRasterBytes,
            destinationBytes: sourceDestinationBytes,
            maximumBytes: limits.maximumDecodedBytes
        )
        CGImageSourceRemoveCacheAtIndex(source, 0)
        try checkCancellation()

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: max(sourceWidth, sourceHeight)
        ]
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions as CFDictionary
            )
        else {
            throw ImageComparisonError.invalidImage
        }
        defer { CGImageSourceRemoveCacheAtIndex(source, 0) }
        try validateDimensions(width: image.width, height: image.height, limits: limits)
        try checkCancellation()

        guard let byteCount = NormalizedImage.byteCount(width: image.width, height: image.height) else {
            throw ImageComparisonError.decodedImageTooLarge(
                maximumBytes: limits.maximumDecodedBytes
            )
        }
        guard let estimatedTransformedRasterBytes = decodedByteCount(image) else {
            throw ImageComparisonError.decodedImageTooLarge(
                maximumBytes: limits.maximumDecodedBytes
            )
        }
        try validateDecodedWorkingSetEstimate(
            decoderRasterBytes: max(
                estimatedNativeRasterBytes,
                estimatedTransformedRasterBytes
            ),
            destinationBytes: byteCount,
            maximumBytes: limits.maximumDecodedBytes
        )
        var pixels = Data(count: byteCount)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }

            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }
        guard rendered else {
            throw ImageComparisonError.normalizationFailed
        }

        return try NormalizedImage(
            width: image.width,
            height: image.height,
            rgba8Premultiplied: pixels
        )
    }

    private static func validate(_ limits: ImageComparisonLimits) throws {
        guard limits.maximumEncodedBytes > 0,
            limits.maximumDimension > 0,
            limits.maximumPixelCount > 0,
            limits.maximumDecodedBytes > 0,
            !limits.supportedTypeIdentifiers.isEmpty
        else {
            throw ImageComparisonError.invalidLimits
        }
    }

    private static func validateDimensions(
        width: Int,
        height: Int,
        limits: ImageComparisonLimits
    ) throws {
        guard width > 0, height > 0 else {
            throw ImageComparisonError.invalidImage
        }
        guard width <= limits.maximumDimension, height <= limits.maximumDimension else {
            throw ImageComparisonError.imageDimensionsExceeded(
                width: width,
                height: height,
                maximumDimension: limits.maximumDimension
            )
        }

        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow, pixelCount <= limits.maximumPixelCount else {
            throw ImageComparisonError.imagePixelCountExceeded(
                maximumPixels: limits.maximumPixelCount
            )
        }
        guard let byteCount = NormalizedImage.byteCount(width: width, height: height),
            byteCount <= limits.maximumDecodedBytes
        else {
            throw ImageComparisonError.decodedImageTooLarge(
                maximumBytes: limits.maximumDecodedBytes
            )
        }
    }

    private static func rejectAdditionalFrames(
        in source: CGImageSource,
        options: CFDictionary
    ) throws {
        try checkCancellation()
        // A fixed second-index probe avoids CGImageSourceGetCount scanning every frame.
        if CGImageSourceCopyPropertiesAtIndex(source, 1, options) != nil {
            throw ImageComparisonError.unsupportedFrameCount(2)
        }
    }

    private static func decodedByteCount(_ image: CGImage) -> Int? {
        let (byteCount, overflow) = image.bytesPerRow.multipliedReportingOverflow(
            by: image.height
        )
        return overflow ? nil : byteCount
    }

    private static func estimatedDecodedRasterByteCount(
        source: CGImageSource,
        limits: ImageComparisonLimits
    ) throws -> Int {
        // ImageIO exposes no decoder peak-memory metric. Caching options request a lazy image;
        // bytesPerRow * height is the strongest native-raster estimate available before drawing.
        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard
            let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                imageOptions as CFDictionary
            )
        else {
            throw ImageComparisonError.invalidImage
        }
        try validateDimensions(width: image.width, height: image.height, limits: limits)
        guard let byteCount = decodedByteCount(image) else {
            throw ImageComparisonError.decodedImageTooLarge(
                maximumBytes: limits.maximumDecodedBytes
            )
        }
        return byteCount
    }

    private static func validateDecodedWorkingSetEstimate(
        decoderRasterBytes: Int,
        destinationBytes: Int,
        maximumBytes: Int
    ) throws {
        let (aggregateByteCount, overflow) = decoderRasterBytes.addingReportingOverflow(
            destinationBytes
        )
        guard !overflow, aggregateByteCount <= maximumBytes else {
            throw ImageComparisonError.decodedImageTooLarge(maximumBytes: maximumBytes)
        }
    }

    private static func readBoundedFile(
        from url: URL,
        expectedSize: Int,
        limits: ImageComparisonLimits
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        return try readBoundedData(expectedSize: expectedSize, limits: limits) { readSize in
            try handle.read(upToCount: readSize)
        }
    }

    static func readBoundedData(
        expectedSize: Int,
        limits: ImageComparisonLimits,
        readChunk: (Int) throws -> Data?
    ) throws -> Data {
        try validate(limits)
        try checkCancellation()
        guard expectedSize >= 0, expectedSize <= limits.maximumEncodedBytes else {
            throw ImageComparisonError.encodedFileTooLarge(
                maximumBytes: limits.maximumEncodedBytes
            )
        }
        var data = Data()
        data.reserveCapacity(min(expectedSize, 64 * 1024))
        while true {
            try checkCancellation()
            let remaining = limits.maximumEncodedBytes - data.count
            guard remaining >= 0 else {
                throw ImageComparisonError.encodedFileTooLarge(
                    maximumBytes: limits.maximumEncodedBytes
                )
            }
            let readSize = remaining < 64 * 1024 ? remaining + 1 : 64 * 1024
            let chunk = try readChunk(readSize) ?? Data()
            guard !chunk.isEmpty else { break }
            guard chunk.count <= readSize, chunk.count <= remaining else {
                throw ImageComparisonError.encodedFileTooLarge(
                    maximumBytes: limits.maximumEncodedBytes
                )
            }
            data.append(chunk)
        }
        return data
    }

    fileprivate static func checkCancellation() throws {
        if Task.isCancelled {
            throw ImageComparisonError.cancelled
        }
    }
}

public struct ImagePixelRect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ImageDifferenceRegion: Equatable, Identifiable, Sendable {
    public let id: Int
    public let bounds: ImagePixelRect
    public let pixelCount: Int

    public init(id: Int, bounds: ImagePixelRect, pixelCount: Int) {
        self.id = id
        self.bounds = bounds
        self.pixelCount = pixelCount
    }
}

public struct ImageComparisonResult: Equatable, Sendable {
    public let leftWidth: Int
    public let leftHeight: Int
    public let rightWidth: Int
    public let rightHeight: Int
    public let differingPixelCount: Int
    public let regions: [ImageDifferenceRegion]

    public var isIdentical: Bool { differingPixelCount == 0 }

    public init(
        leftWidth: Int,
        leftHeight: Int,
        rightWidth: Int,
        rightHeight: Int,
        differingPixelCount: Int,
        regions: [ImageDifferenceRegion]
    ) {
        self.leftWidth = leftWidth
        self.leftHeight = leftHeight
        self.rightWidth = rightWidth
        self.rightHeight = rightHeight
        self.differingPixelCount = differingPixelCount
        self.regions = regions
    }
}

public struct ImageComparisonOptions: Equatable, Sendable {
    public static let `default` = ImageComparisonOptions()

    public let channelTolerance: UInt8
    public let maximumCanvasPixels: Int
    public let maximumRegions: Int
    public let maximumQueuedPixels: Int

    public init(
        channelTolerance: UInt8 = 0,
        maximumCanvasPixels: Int = 16 * 1024 * 1024,
        maximumRegions: Int = 250_000,
        maximumQueuedPixels: Int = 262_144
    ) {
        self.channelTolerance = channelTolerance
        self.maximumCanvasPixels = maximumCanvasPixels
        self.maximumRegions = maximumRegions
        self.maximumQueuedPixels = maximumQueuedPixels
    }
}

public enum ImageDifferenceEngine {
    public static func compare(
        left: NormalizedImage,
        right: NormalizedImage,
        options: ImageComparisonOptions = .default
    ) throws -> ImageComparisonResult {
        try compare(
            left: left,
            right: right,
            options: options,
            cancellationCheck: BoundedImageLoader.checkCancellation
        )
    }

    static func compare(
        left: NormalizedImage,
        right: NormalizedImage,
        options: ImageComparisonOptions,
        cancellationCheck: () throws -> Void
    ) throws -> ImageComparisonResult {
        guard options.maximumCanvasPixels > 0,
            options.maximumRegions > 0,
            options.maximumQueuedPixels > 0
        else {
            throw ImageComparisonError.invalidLimits
        }
        try cancellationCheck()

        let canvasWidth = max(left.width, right.width)
        let canvasHeight = max(left.height, right.height)
        let (canvasPixels, canvasOverflow) = canvasWidth.multipliedReportingOverflow(
            by: canvasHeight
        )
        guard !canvasOverflow, canvasPixels <= options.maximumCanvasPixels else {
            throw ImageComparisonError.comparisonCanvasTooLarge(
                maximumPixels: options.maximumCanvasPixels
            )
        }

        var visited = Data(count: canvasPixels)
        var regions: [ImageDifferenceRegion] = []
        regions.reserveCapacity(min(options.maximumRegions, 1_024))
        var differingPixelCount = 0
        var queue = BoundedPixelQueue(
            capacity: min(options.maximumQueuedPixels, canvasPixels)
        )

        try left.rgba8Premultiplied.withUnsafeBytes { leftBytes in
            try right.rgba8Premultiplied.withUnsafeBytes { rightBytes in
                try visited.withUnsafeMutableBytes { visitedBytes in
                    guard let leftBase = leftBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        let rightBase = rightBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        let visitedBase = visitedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    else {
                        throw ImageComparisonError.invalidPixelBuffer
                    }

                    func isDifferent(x: Int, y: Int) -> Bool {
                        let inLeft = x < left.width && y < left.height
                        let inRight = x < right.width && y < right.height
                        if inLeft != inRight { return true }
                        guard inLeft else { return false }

                        let leftOffset = (y * left.width + x) * 4
                        let rightOffset = (y * right.width + x) * 4
                        let tolerance = Int(options.channelTolerance)
                        for channel in 0..<4 {
                            if abs(
                                Int(leftBase[leftOffset + channel])
                                    - Int(rightBase[rightOffset + channel])) > tolerance
                            {
                                return true
                            }
                        }
                        return false
                    }

                    for y in 0..<canvasHeight {
                        try cancellationCheck()
                        for x in 0..<canvasWidth {
                            if x & 0xFFF == 0 {
                                try cancellationCheck()
                            }
                            let index = y * canvasWidth + x
                            guard visitedBase[index] == 0, isDifferent(x: x, y: y) else {
                                continue
                            }
                            guard regions.count < options.maximumRegions else {
                                throw ImageComparisonError.tooManyDifferenceRegions(
                                    maximumRegions: options.maximumRegions
                                )
                            }

                            queue.removeAll()
                            try queue.append(index)
                            visitedBase[index] = 1
                            var minimumX = x
                            var maximumX = x
                            var minimumY = y
                            var maximumY = y
                            var regionPixelCount = 0

                            while let current = queue.popFirst() {
                                if regionPixelCount & 0xFFF == 0 {
                                    try cancellationCheck()
                                }
                                let currentX = current % canvasWidth
                                let currentY = current / canvasWidth
                                minimumX = min(minimumX, currentX)
                                maximumX = max(maximumX, currentX)
                                minimumY = min(minimumY, currentY)
                                maximumY = max(maximumY, currentY)
                                regionPixelCount += 1

                                for deltaY in -1...1 {
                                    let neighborY = currentY + deltaY
                                    guard neighborY >= 0, neighborY < canvasHeight else { continue }
                                    for deltaX in -1...1 where deltaX != 0 || deltaY != 0 {
                                        let neighborX = currentX + deltaX
                                        guard neighborX >= 0, neighborX < canvasWidth else { continue }
                                        let neighborIndex = neighborY * canvasWidth + neighborX
                                        guard visitedBase[neighborIndex] == 0,
                                            isDifferent(x: neighborX, y: neighborY)
                                        else {
                                            continue
                                        }
                                        try queue.append(neighborIndex)
                                        visitedBase[neighborIndex] = 1
                                    }
                                }
                            }

                            differingPixelCount += regionPixelCount
                            regions.append(
                                ImageDifferenceRegion(
                                    id: regions.count,
                                    bounds: ImagePixelRect(
                                        x: minimumX,
                                        y: minimumY,
                                        width: maximumX - minimumX + 1,
                                        height: maximumY - minimumY + 1
                                    ),
                                    pixelCount: regionPixelCount
                                )
                            )
                        }
                    }
                }
            }
        }

        return ImageComparisonResult(
            leftWidth: left.width,
            leftHeight: left.height,
            rightWidth: right.width,
            rightHeight: right.height,
            differingPixelCount: differingPixelCount,
            regions: regions
        )
    }
}

private struct BoundedPixelQueue {
    private var storage: [Int]
    private var head = 0
    private var tail = 0
    private(set) var count = 0

    init(capacity: Int) {
        storage = Array(repeating: 0, count: capacity)
    }

    mutating func append(_ value: Int) throws {
        guard count < storage.count else {
            throw ImageComparisonError.comparisonTooComplex(
                maximumQueuedPixels: storage.count
            )
        }
        storage[tail] = value
        tail = (tail + 1) % storage.count
        count += 1
    }

    mutating func popFirst() -> Int? {
        guard count > 0 else { return nil }
        let value = storage[head]
        head = (head + 1) % storage.count
        count -= 1
        return value
    }

    mutating func removeAll() {
        head = 0
        tail = 0
        count = 0
    }
}
