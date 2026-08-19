import Foundation

public enum ImageComparisonSide: Equatable, Sendable {
    case left
    case right
}

public enum ImageComparisonDisplayMode: Equatable, Sendable {
    case sideBySide
    case overlay
    case blink
}

public struct ImageLayerPresentation: Equatable, Sendable {
    public let leftOpacity: Double
    public let rightOpacity: Double

    public init(leftOpacity: Double, rightOpacity: Double) {
        self.leftOpacity = leftOpacity
        self.rightOpacity = rightOpacity
    }
}

public struct ImageComparisonPresentationState: Equatable, Sendable {
    public private(set) var displayMode: ImageComparisonDisplayMode
    public private(set) var overlayOpacity: Double
    public private(set) var blinkVisibleSide: ImageComparisonSide
    public private(set) var regions: [ImageDifferenceRegion]
    public private(set) var selectedDifferenceIndex: Int?

    public init(
        comparison: ImageComparisonResult,
        displayMode: ImageComparisonDisplayMode = .sideBySide,
        overlayOpacity: Double = 0.5
    ) {
        self.displayMode = displayMode
        self.overlayOpacity = Self.normalizedOpacity(overlayOpacity)
        blinkVisibleSide = .left
        regions = comparison.regions
        selectedDifferenceIndex = nil
    }

    public var selectedRegion: ImageDifferenceRegion? {
        guard let selectedDifferenceIndex, regions.indices.contains(selectedDifferenceIndex) else {
            return nil
        }
        return regions[selectedDifferenceIndex]
    }

    public var selectedDifferenceNumber: Int? {
        selectedDifferenceIndex.map { $0 + 1 }
    }

    public var canNavigateDifferences: Bool { !regions.isEmpty }

    public var canSelectNextDifference: Bool {
        guard !regions.isEmpty else { return false }
        guard let selectedDifferenceIndex else { return true }
        return selectedDifferenceIndex < regions.count - 1
    }

    public var canSelectPreviousDifference: Bool {
        guard !regions.isEmpty else { return false }
        guard let selectedDifferenceIndex else { return true }
        return selectedDifferenceIndex > 0
    }

    public var layerPresentation: ImageLayerPresentation {
        switch displayMode {
        case .sideBySide:
            ImageLayerPresentation(leftOpacity: 1, rightOpacity: 1)
        case .overlay:
            ImageLayerPresentation(leftOpacity: 1, rightOpacity: overlayOpacity)
        case .blink:
            switch blinkVisibleSide {
            case .left:
                ImageLayerPresentation(leftOpacity: 1, rightOpacity: 0)
            case .right:
                ImageLayerPresentation(leftOpacity: 0, rightOpacity: 1)
            }
        }
    }

    public mutating func replaceComparison(_ comparison: ImageComparisonResult) {
        regions = comparison.regions
        selectedDifferenceIndex = nil
        blinkVisibleSide = .left
    }

    public mutating func setDisplayMode(_ mode: ImageComparisonDisplayMode) {
        guard mode != displayMode else { return }
        if mode == .blink {
            blinkVisibleSide = .left
        }
        displayMode = mode
    }

    @discardableResult
    public mutating func setOverlayOpacity(_ opacity: Double) -> Bool {
        guard opacity.isFinite else { return false }
        overlayOpacity = Self.normalizedOpacity(opacity)
        return true
    }

    @discardableResult
    public mutating func advanceBlinkFrame() -> Bool {
        guard displayMode == .blink else { return false }
        blinkVisibleSide = blinkVisibleSide == .left ? .right : .left
        return true
    }

    @discardableResult
    public mutating func selectDifference(at index: Int) -> Bool {
        guard regions.indices.contains(index) else { return false }
        selectedDifferenceIndex = index
        return true
    }

    @discardableResult
    public mutating func selectFirstDifference() -> Bool {
        selectDifference(at: regions.startIndex)
    }

    @discardableResult
    public mutating func selectLastDifference() -> Bool {
        guard let lastIndex = regions.indices.last else { return false }
        return selectDifference(at: lastIndex)
    }

    @discardableResult
    public mutating func selectNextDifference() -> Bool {
        guard let selectedDifferenceIndex else { return selectFirstDifference() }
        return selectDifference(at: selectedDifferenceIndex + 1)
    }

    @discardableResult
    public mutating func selectPreviousDifference() -> Bool {
        guard let selectedDifferenceIndex else { return selectLastDifference() }
        return selectDifference(at: selectedDifferenceIndex - 1)
    }

    public mutating func clearSelection() {
        selectedDifferenceIndex = nil
    }

    private static func normalizedOpacity(_ opacity: Double) -> Double {
        opacity.isFinite ? min(max(opacity, 0), 1) : 0.5
    }
}
