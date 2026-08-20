import Foundation

public enum ThreeWayImageComparisonResolution: UInt8, CaseIterable, Equatable, Sendable {
    case unchanged
    case left
    case right
    case identical
    case conflict

    public var isConflict: Bool { self == .conflict }
}

public enum ThreeWayImageComparisonConflictChoice: UInt8, CaseIterable, Equatable, Sendable {
    case base
    case left
    case right
}

public struct ThreeWayImageComparisonRegion: Identifiable, Equatable, Sendable {
    public let difference: ImageDifferenceRegion
    public let resolution: ThreeWayImageComparisonResolution

    public var id: Int { difference.id }
    public var bounds: ImagePixelRect { difference.bounds }
    public var pixelCount: Int { difference.pixelCount }
    public var isConflict: Bool { resolution.isConflict }

    public init(
        difference: ImageDifferenceRegion,
        resolution: ThreeWayImageComparisonResolution
    ) {
        self.difference = difference
        self.resolution = resolution
    }

    public init(
        id: Int,
        bounds: ImagePixelRect,
        pixelCount: Int,
        resolution: ThreeWayImageComparisonResolution
    ) {
        self.init(
            difference: ImageDifferenceRegion(
                id: id,
                bounds: bounds,
                pixelCount: pixelCount
            ),
            resolution: resolution
        )
    }
}

public struct ThreeWayImageComparisonResult: Equatable, Sendable {
    public let base: NormalizedImage
    public let left: NormalizedImage
    public let right: NormalizedImage
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let changedPixelCount: Int
    public let conflictingPixelCount: Int
    public let regions: [ThreeWayImageComparisonRegion]
    public let conflicts: [ThreeWayImageComparisonRegion]
    public let mergedImage: NormalizedImage?

    private let pixelResolutions: Data
    private let regionSeedIndices: [Int]
    private let maximumQueuedPixels: Int

    public var baseWidth: Int { base.width }
    public var baseHeight: Int { base.height }
    public var leftWidth: Int { left.width }
    public var leftHeight: Int { left.height }
    public var rightWidth: Int { right.width }
    public var rightHeight: Int { right.height }
    public var isIdentical: Bool { changedPixelCount == 0 }
    public var hasConflicts: Bool { !conflicts.isEmpty }

    fileprivate init(
        base: NormalizedImage,
        left: NormalizedImage,
        right: NormalizedImage,
        canvasWidth: Int,
        canvasHeight: Int,
        changedPixelCount: Int,
        conflictingPixelCount: Int,
        regions: [ThreeWayImageComparisonRegion],
        conflicts: [ThreeWayImageComparisonRegion],
        pixelResolutions: Data,
        regionSeedIndices: [Int],
        maximumQueuedPixels: Int,
        mergedImage: NormalizedImage?
    ) {
        self.base = base
        self.left = left
        self.right = right
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.changedPixelCount = changedPixelCount
        self.conflictingPixelCount = conflictingPixelCount
        self.regions = regions
        self.conflicts = conflicts
        self.pixelResolutions = pixelResolutions
        self.regionSeedIndices = regionSeedIndices
        self.maximumQueuedPixels = maximumQueuedPixels
        self.mergedImage = mergedImage
    }

    public func resolution(
        atX x: Int,
        y: Int
    ) -> ThreeWayImageComparisonResolution? {
        guard x >= 0, y >= 0, x < canvasWidth, y < canvasHeight else { return nil }
        return ThreeWayImageComparisonResolution(
            rawValue: pixelResolutions[y * canvasWidth + x]
        )
    }

    public func image(
        resolvingConflictsWith choices: [Int: ThreeWayImageComparisonConflictChoice]
    ) throws -> NormalizedImage? {
        try resolvedImage(
            choices: choices,
            cancellationCheck: ThreeWayImageComparison.checkCancellation
        )
    }

    fileprivate func resolvedImage(
        choices: [Int: ThreeWayImageComparisonConflictChoice],
        cancellationCheck: () throws -> Void
    ) throws -> NormalizedImage? {
        for (index, conflict) in conflicts.enumerated() {
            if index.isMultiple(of: 4_096) { try cancellationCheck() }
            guard choices[conflict.id] != nil else { return nil }
        }

        try cancellationCheck()
        let canvasPixelCount = pixelResolutions.count
        var conflictChoices = Data(count: canvasPixelCount)
        var queue = ThreeWayImagePixelQueue(
            capacity: min(maximumQueuedPixels, canvasPixelCount)
        )

        try pixelResolutions.withUnsafeBytes { resolutionBytes in
            try conflictChoices.withUnsafeMutableBytes { choiceBytes in
                guard
                    let resolutionBase = resolutionBytes.baseAddress?.assumingMemoryBound(
                        to: UInt8.self
                    ),
                    let choiceBase = choiceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else {
                    throw ImageComparisonError.invalidPixelBuffer
                }

                for (regionIndex, region) in regions.enumerated() where region.isConflict {
                    try cancellationCheck()
                    guard let choice = choices[region.id] else { return }
                    let storedChoice = choice.rawValue + 1
                    let seed = regionSeedIndices[regionIndex]
                    queue.removeAll()
                    try queue.append(seed)
                    choiceBase[seed] = storedChoice
                    var visitedPixelCount = 0

                    while let current = queue.popFirst() {
                        if visitedPixelCount.isMultiple(of: 4_096) {
                            try cancellationCheck()
                        }
                        visitedPixelCount += 1
                        let currentX = current % canvasWidth
                        let currentY = current / canvasWidth

                        for deltaY in -1...1 {
                            let neighborY = currentY + deltaY
                            guard neighborY >= 0, neighborY < canvasHeight else { continue }
                            for deltaX in -1...1 where deltaX != 0 || deltaY != 0 {
                                let neighborX = currentX + deltaX
                                guard neighborX >= 0, neighborX < canvasWidth else { continue }
                                let neighbor = neighborY * canvasWidth + neighborX
                                guard
                                    choiceBase[neighbor] == 0,
                                    resolutionBase[neighbor]
                                        == ThreeWayImageComparisonResolution.conflict.rawValue
                                else {
                                    continue
                                }
                                choiceBase[neighbor] = storedChoice
                                try queue.append(neighbor)
                            }
                        }
                    }
                }
            }
        }

        try cancellationCheck()
        return try makeImage(
            conflictChoices: conflictChoices,
            cancellationCheck: cancellationCheck
        )
    }

    private func makeImage(
        conflictChoices: Data,
        cancellationCheck: () throws -> Void
    ) throws -> NormalizedImage? {
        try base.rgba8Premultiplied.withUnsafeBytes { baseBytes in
            try left.rgba8Premultiplied.withUnsafeBytes { leftBytes in
                try right.rgba8Premultiplied.withUnsafeBytes { rightBytes in
                    try pixelResolutions.withUnsafeBytes { resolutionBytes in
                        try conflictChoices.withUnsafeBytes { choiceBytes in
                            guard
                                let baseAddress = baseBytes.baseAddress?.assumingMemoryBound(
                                    to: UInt8.self
                                ),
                                let leftAddress = leftBytes.baseAddress?.assumingMemoryBound(
                                    to: UInt8.self
                                ),
                                let rightAddress = rightBytes.baseAddress?.assumingMemoryBound(
                                    to: UInt8.self
                                ),
                                let resolutionBase = resolutionBytes.baseAddress?
                                    .assumingMemoryBound(to: UInt8.self),
                                let choiceBase = choiceBytes.baseAddress?.assumingMemoryBound(
                                    to: UInt8.self
                                )
                            else {
                                throw ImageComparisonError.invalidPixelBuffer
                            }

                            func selectedSource(at index: Int) -> Source {
                                let resolution = ThreeWayImageComparisonResolution(
                                    rawValue: resolutionBase[index]
                                ) ?? .conflict
                                switch resolution {
                                case .unchanged:
                                    return .base
                                case .left, .identical:
                                    return .left
                                case .right:
                                    return .right
                                case .conflict:
                                    switch choiceBase[index] {
                                    case ThreeWayImageComparisonConflictChoice.base.rawValue + 1:
                                        return .base
                                    case ThreeWayImageComparisonConflictChoice.left.rawValue + 1:
                                        return .left
                                    default:
                                        return .right
                                    }
                                }
                            }

                            func contains(_ source: Source, x: Int, y: Int) -> Bool {
                                switch source {
                                case .base: x < base.width && y < base.height
                                case .left: x < left.width && y < left.height
                                case .right: x < right.width && y < right.height
                                }
                            }

                            var maximumX = -1
                            var maximumY = -1
                            for y in 0..<canvasHeight {
                                try cancellationCheck()
                                for x in 0..<canvasWidth {
                                    if x & 0xFFF == 0 { try cancellationCheck() }
                                    let index = y * canvasWidth + x
                                    if contains(selectedSource(at: index), x: x, y: y) {
                                        maximumX = max(maximumX, x)
                                        maximumY = max(maximumY, y)
                                    }
                                }
                            }

                            guard maximumX >= 0, maximumY >= 0 else { return nil }
                            let width = maximumX + 1
                            let height = maximumY + 1
                            let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(
                                by: height
                            )
                            let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(
                                by: 4
                            )
                            guard !pixelOverflow, !byteOverflow,
                                pixelCount <= pixelResolutions.count
                            else {
                                throw ImageComparisonError.invalidPixelBuffer
                            }

                            for y in 0..<height {
                                try cancellationCheck()
                                for x in 0..<width {
                                    if x & 0xFFF == 0 { try cancellationCheck() }
                                    let index = y * canvasWidth + x
                                    guard contains(selectedSource(at: index), x: x, y: y) else {
                                        return nil
                                    }
                                }
                            }

                            var output = Data(count: byteCount)
                            try output.withUnsafeMutableBytes { outputBytes in
                                guard let outputBase = outputBytes.baseAddress?.assumingMemoryBound(
                                    to: UInt8.self
                                ) else {
                                    throw ImageComparisonError.invalidPixelBuffer
                                }

                                for y in 0..<height {
                                    try cancellationCheck()
                                    for x in 0..<width {
                                        if x & 0xFFF == 0 { try cancellationCheck() }
                                        let canvasIndex = y * canvasWidth + x
                                        let source = selectedSource(at: canvasIndex)
                                        let sourceWidth: Int
                                        let sourceAddress: UnsafePointer<UInt8>
                                        switch source {
                                        case .base:
                                            sourceWidth = base.width
                                            sourceAddress = baseAddress
                                        case .left:
                                            sourceWidth = left.width
                                            sourceAddress = leftAddress
                                        case .right:
                                            sourceWidth = right.width
                                            sourceAddress = rightAddress
                                        }
                                        let sourceOffset = (y * sourceWidth + x) * 4
                                        let outputOffset = (y * width + x) * 4
                                        outputBase[outputOffset] = sourceAddress[sourceOffset]
                                        outputBase[outputOffset + 1] = sourceAddress[sourceOffset + 1]
                                        outputBase[outputOffset + 2] = sourceAddress[sourceOffset + 2]
                                        outputBase[outputOffset + 3] = sourceAddress[sourceOffset + 3]
                                    }
                                }
                            }
                            return try NormalizedImage(
                                width: width,
                                height: height,
                                rgba8Premultiplied: output
                            )
                        }
                    }
                }
            }
        }
    }

    private enum Source {
        case base
        case left
        case right
    }
}

public enum ThreeWayImageComparison: Sendable {
    public static func compare(
        base: NormalizedImage,
        left: NormalizedImage,
        right: NormalizedImage,
        options: ImageComparisonOptions = .default
    ) throws -> ThreeWayImageComparisonResult {
        try compare(
            base: base,
            left: left,
            right: right,
            options: options,
            cancellationCheck: checkCancellation
        )
    }

    static func compare(
        base: NormalizedImage,
        left: NormalizedImage,
        right: NormalizedImage,
        options: ImageComparisonOptions,
        cancellationCheck: () throws -> Void
    ) throws -> ThreeWayImageComparisonResult {
        guard options.maximumCanvasPixels > 0,
            options.maximumRegions > 0,
            options.maximumQueuedPixels > 0
        else {
            throw ImageComparisonError.invalidLimits
        }
        try cancellationCheck()

        let canvasWidth = max(base.width, left.width, right.width)
        let canvasHeight = max(base.height, left.height, right.height)
        let (canvasPixelCount, canvasOverflow) = canvasWidth.multipliedReportingOverflow(
            by: canvasHeight
        )
        guard !canvasOverflow, canvasPixelCount <= options.maximumCanvasPixels else {
            throw ImageComparisonError.comparisonCanvasTooLarge(
                maximumPixels: options.maximumCanvasPixels
            )
        }

        var pixelResolutions = Data(count: canvasPixelCount)
        var visited = Data(count: canvasPixelCount)
        var changedPixelCount = 0
        var conflictingPixelCount = 0

        try base.rgba8Premultiplied.withUnsafeBytes { baseBytes in
            try left.rgba8Premultiplied.withUnsafeBytes { leftBytes in
                try right.rgba8Premultiplied.withUnsafeBytes { rightBytes in
                    try pixelResolutions.withUnsafeMutableBytes { resolutionBytes in
                        guard
                            let baseAddress = baseBytes.baseAddress?.assumingMemoryBound(
                                to: UInt8.self
                            ),
                            let leftAddress = leftBytes.baseAddress?.assumingMemoryBound(
                                to: UInt8.self
                            ),
                            let rightAddress = rightBytes.baseAddress?.assumingMemoryBound(
                                to: UInt8.self
                            ),
                            let resolutionBase = resolutionBytes.baseAddress?
                                .assumingMemoryBound(to: UInt8.self)
                        else {
                            throw ImageComparisonError.invalidPixelBuffer
                        }

                        func pixelsAreEqual(
                            _ firstAddress: UnsafePointer<UInt8>,
                            width firstWidth: Int,
                            height firstHeight: Int,
                            _ secondAddress: UnsafePointer<UInt8>,
                            width secondWidth: Int,
                            height secondHeight: Int,
                            x: Int,
                            y: Int
                        ) -> Bool {
                            let inFirst = x < firstWidth && y < firstHeight
                            let inSecond = x < secondWidth && y < secondHeight
                            guard inFirst == inSecond else { return false }
                            guard inFirst else { return true }
                            let firstOffset = (y * firstWidth + x) * 4
                            let secondOffset = (y * secondWidth + x) * 4
                            let tolerance = Int(options.channelTolerance)
                            for channel in 0..<4 {
                                if abs(
                                    Int(firstAddress[firstOffset + channel])
                                        - Int(secondAddress[secondOffset + channel])
                                ) > tolerance {
                                    return false
                                }
                            }
                            return true
                        }

                        for y in 0..<canvasHeight {
                            try cancellationCheck()
                            for x in 0..<canvasWidth {
                                if x & 0xFFF == 0 { try cancellationCheck() }
                                let leftIsBase = pixelsAreEqual(
                                    leftAddress,
                                    width: left.width,
                                    height: left.height,
                                    baseAddress,
                                    width: base.width,
                                    height: base.height,
                                    x: x,
                                    y: y
                                )
                                let rightIsBase = pixelsAreEqual(
                                    rightAddress,
                                    width: right.width,
                                    height: right.height,
                                    baseAddress,
                                    width: base.width,
                                    height: base.height,
                                    x: x,
                                    y: y
                                )
                                let leftIsRight = pixelsAreEqual(
                                    leftAddress,
                                    width: left.width,
                                    height: left.height,
                                    rightAddress,
                                    width: right.width,
                                    height: right.height,
                                    x: x,
                                    y: y
                                )
                                let resolution: ThreeWayImageComparisonResolution
                                if leftIsBase, rightIsBase {
                                    resolution = .unchanged
                                } else if leftIsBase {
                                    resolution = .right
                                } else if rightIsBase {
                                    resolution = .left
                                } else if leftIsRight {
                                    resolution = .identical
                                } else {
                                    resolution = .conflict
                                }
                                let index = y * canvasWidth + x
                                resolutionBase[index] = resolution.rawValue
                                if resolution != .unchanged { changedPixelCount += 1 }
                                if resolution == .conflict { conflictingPixelCount += 1 }
                            }
                        }
                    }
                }
            }
        }

        var regions: [ThreeWayImageComparisonRegion] = []
        regions.reserveCapacity(min(options.maximumRegions, 1_024))
        var conflicts: [ThreeWayImageComparisonRegion] = []
        conflicts.reserveCapacity(min(options.maximumRegions, 1_024))
        var regionSeedIndices: [Int] = []
        regionSeedIndices.reserveCapacity(min(options.maximumRegions, 1_024))
        var queue = ThreeWayImagePixelQueue(
            capacity: min(options.maximumQueuedPixels, canvasPixelCount)
        )

        try pixelResolutions.withUnsafeBytes { resolutionBytes in
            try visited.withUnsafeMutableBytes { visitedBytes in
                guard
                    let resolutionBase = resolutionBytes.baseAddress?.assumingMemoryBound(
                        to: UInt8.self
                    ),
                    let visitedBase = visitedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else {
                    throw ImageComparisonError.invalidPixelBuffer
                }

                for y in 0..<canvasHeight {
                    try cancellationCheck()
                    for x in 0..<canvasWidth {
                        if x & 0xFFF == 0 { try cancellationCheck() }
                        let index = y * canvasWidth + x
                        let rawResolution = resolutionBase[index]
                        guard
                            rawResolution
                                != ThreeWayImageComparisonResolution.unchanged.rawValue,
                            visitedBase[index] == 0
                        else {
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
                            if regionPixelCount.isMultiple(of: 4_096) {
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
                                    let neighbor = neighborY * canvasWidth + neighborX
                                    guard
                                        visitedBase[neighbor] == 0,
                                        resolutionBase[neighbor] == rawResolution
                                    else {
                                        continue
                                    }
                                    visitedBase[neighbor] = 1
                                    try queue.append(neighbor)
                                }
                            }
                        }

                        guard
                            let resolution = ThreeWayImageComparisonResolution(
                                rawValue: rawResolution
                            )
                        else {
                            throw ImageComparisonError.invalidPixelBuffer
                        }
                        let region = ThreeWayImageComparisonRegion(
                            id: regions.count,
                            bounds: ImagePixelRect(
                                x: minimumX,
                                y: minimumY,
                                width: maximumX - minimumX + 1,
                                height: maximumY - minimumY + 1
                            ),
                            pixelCount: regionPixelCount,
                            resolution: resolution
                        )
                        regionSeedIndices.append(index)
                        regions.append(region)
                        if region.isConflict { conflicts.append(region) }
                    }
                }
            }
        }

        var result = ThreeWayImageComparisonResult(
            base: base,
            left: left,
            right: right,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            changedPixelCount: changedPixelCount,
            conflictingPixelCount: conflictingPixelCount,
            regions: regions,
            conflicts: conflicts,
            pixelResolutions: pixelResolutions,
            regionSeedIndices: regionSeedIndices,
            maximumQueuedPixels: options.maximumQueuedPixels,
            mergedImage: nil
        )
        if result.conflicts.isEmpty {
            let mergedImage = try result.resolvedImage(
                choices: [:],
                cancellationCheck: cancellationCheck
            )
            result = ThreeWayImageComparisonResult(
                base: base,
                left: left,
                right: right,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
                changedPixelCount: changedPixelCount,
                conflictingPixelCount: conflictingPixelCount,
                regions: regions,
                conflicts: conflicts,
                pixelResolutions: pixelResolutions,
                regionSeedIndices: regionSeedIndices,
                maximumQueuedPixels: options.maximumQueuedPixels,
                mergedImage: mergedImage
            )
        }
        return result
    }

    fileprivate static func checkCancellation() throws {
        if Task.isCancelled { throw ImageComparisonError.cancelled }
    }
}

private struct ThreeWayImagePixelQueue {
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
