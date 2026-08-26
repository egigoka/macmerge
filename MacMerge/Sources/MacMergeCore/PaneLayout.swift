import Foundation

/// Logical identity of a comparison document, independent of its current screen position.
public enum PaneIdentity: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case left
    case middle
    case right

    public init(_ identity: ComparisonSideIdentity) {
        switch identity {
        case .left: self = .left
        case .middle: self = .middle
        case .right: self = .right
        }
    }

    public init(_ side: ComparisonSessionState.Side) {
        switch side {
        case .left: self = .left
        case .right: self = .right
        }
    }

    public init(_ side: MergeCommandPolicy.Side) {
        switch side {
        case .left: self = .left
        case .middle: self = .middle
        case .right: self = .right
        }
    }

    public var comparisonSideIdentity: ComparisonSideIdentity {
        switch self {
        case .left: .left
        case .middle: .middle
        case .right: .right
        }
    }

    public var comparisonSessionSide: ComparisonSessionState.Side? {
        switch self {
        case .left: .left
        case .middle: nil
        case .right: .right
        }
    }

    public var mergeCommandSide: MergeCommandPolicy.Side {
        switch self {
        case .left: .left
        case .middle: .middle
        case .right: .right
        }
    }
}

/// Keeps a document owner and all owner-specific state bound to one logical pane identity.
///
/// Reorder these values with `PaneLayout.ownedValuesInVisualOrder(_:)` rather than rebuilding
/// payloads. This preserves document identity and state such as dirty and read-only flags.
public struct PaneOwnedValue<Value: Sendable>: Sendable {
    public let identity: PaneIdentity
    public var value: Value

    public init(identity: PaneIdentity, value: Value) {
        self.identity = identity
        self.value = value
    }
}

extension PaneOwnedValue: Codable where Value: Codable {}
extension PaneOwnedValue: Equatable where Value: Equatable {}
extension PaneOwnedValue: Hashable where Value: Hashable {}

/// UI-independent two- or three-pane comparison layout.
///
/// Pane identities remain logical document owners. `visualOrder` is the only mapping from
/// those owners to screen positions, so swapping panes never transfers or recreates documents.
/// Split fractions are normalized divider positions along the layout's primary axis. A vertical
/// layout presents panes left-to-right; a horizontal layout presents them top-to-bottom.
public struct PaneLayout: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEncodedBytes = 64 * 1024
    public static let defaultMinimumPaneFraction = 0.1

    private static let boundedDecodeKey = CodingUserInfoKey(
        rawValue: "org.macmerge.PaneLayout.boundedDecode"
    )!
    private static let boundedDecodeToken = UUID()

    public typealias Identity = PaneIdentity

    public enum PaneCount: Int, Codable, CaseIterable, Equatable, Sendable {
        case two = 2
        case three = 3

        public var identities: [Identity] {
            switch self {
            case .two:
                [.left, .right]
            case .three:
                [.left, .middle, .right]
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(Int.self)
            guard let paneCount = Self(rawValue: value) else {
                throw PaneLayoutError.invalidPaneCount(value)
            }
            self = paneCount
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public enum Orientation: String, Codable, CaseIterable, Equatable, Sendable {
        case vertical
        case horizontal

        public var toggled: Orientation {
            switch self {
            case .vertical: .horizontal
            case .horizontal: .vertical
            }
        }
    }

    public let schemaVersion: Int
    public let paneCount: PaneCount
    public private(set) var activePane: Identity
    public private(set) var visualOrder: [Identity]
    public private(set) var orientation: Orientation
    public private(set) var splitFractions: [Double]
    public let minimumPaneFraction: Double

    public var logicalOrder: [Identity] { paneCount.identities }
    public var activeVisualIndex: Int { visualOrder.firstIndex(of: activePane)! }

    /// Normalized size of every visual pane. Values are finite, positive, and sum to one.
    public var paneFractions: [Double] {
        var lowerBound = 0.0
        var result: [Double] = []
        result.reserveCapacity(paneCount.rawValue)
        for upperBound in splitFractions + [1.0] {
            result.append(upperBound - lowerBound)
            lowerBound = upperBound
        }
        return result
    }

    public init(
        paneCount: PaneCount,
        activePane: Identity = .left,
        visualOrder: [Identity]? = nil,
        orientation: Orientation = .vertical,
        splitFractions: [Double]? = nil,
        minimumPaneFraction: Double = Self.defaultMinimumPaneFraction
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.paneCount = paneCount
        self.activePane = activePane
        self.visualOrder = visualOrder ?? paneCount.identities
        self.orientation = orientation
        self.splitFractions = splitFractions ?? Self.defaultSplitFractions(for: paneCount)
        self.minimumPaneFraction = minimumPaneFraction
        try validate()
    }

    public init(
        visualOrder: [Identity],
        activePane: Identity = .left,
        orientation: Orientation = .vertical,
        splitFractions: [Double]? = nil,
        minimumPaneFraction: Double = Self.defaultMinimumPaneFraction
    ) throws {
        guard let paneCount = PaneCount(rawValue: visualOrder.count) else {
            throw PaneLayoutError.invalidPaneCount(visualOrder.count)
        }
        try self.init(
            paneCount: paneCount,
            activePane: activePane,
            visualOrder: visualOrder,
            orientation: orientation,
            splitFractions: splitFractions,
            minimumPaneFraction: minimumPaneFraction
        )
    }

    /// Migrates a legacy two-pane split while preserving every finite value strictly between zero
    /// and one, including values below the current default minimum pane fraction.
    public init(
        migratingLegacySplitFraction splitFraction: Double,
        activePane: Identity = .left,
        orientation: Orientation = .vertical
    ) throws {
        guard splitFraction.isFinite, splitFraction > 0, splitFraction < 1 else {
            throw PaneLayoutError.invalidSplitFraction(index: 0, value: splitFraction)
        }
        let preservingMinimum = min(
            Self.defaultMinimumPaneFraction,
            splitFraction,
            1.0 - splitFraction
        )
        try self.init(
            paneCount: .two,
            activePane: activePane,
            orientation: orientation,
            splitFractions: [splitFraction],
            minimumPaneFraction: preservingMinimum
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case paneCount
        case activePane
        case visualOrder
        case orientation
        case splitFractions
        case minimumPaneFraction
    }

    public init(from decoder: Decoder) throws {
        guard
            decoder.userInfo[Self.boundedDecodeKey] as? UUID
                == Self.boundedDecodeToken
        else {
            throw PaneLayoutError.boundedDecodingRequired
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PaneLayoutError.unsupportedSchemaVersion(schemaVersion)
        }

        let paneCount = try container.decode(PaneCount.self, forKey: .paneCount)
        try self.init(
            paneCount: paneCount,
            activePane: try container.decode(Identity.self, forKey: .activePane),
            visualOrder: try container.decode([Identity].self, forKey: .visualOrder),
            orientation: try container.decode(Orientation.self, forKey: .orientation),
            splitFractions: try container.decode([Double].self, forKey: .splitFractions),
            minimumPaneFraction: try container.decode(Double.self, forKey: .minimumPaneFraction)
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(paneCount, forKey: .paneCount)
        try container.encode(activePane, forKey: .activePane)
        try container.encode(visualOrder, forKey: .visualOrder)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(splitFractions, forKey: .splitFractions)
        try container.encode(minimumPaneFraction, forKey: .minimumPaneFraction)
    }

    /// Returns compact, deterministic JSON with recursively sorted object keys.
    public func encodedData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw PaneLayoutError.persistenceDataTooLarge(maximumBytes: Self.maximumEncodedBytes)
        }
        return data
    }

    public static func decode(from data: Data) throws -> PaneLayout {
        guard data.count <= maximumEncodedBytes else {
            throw PaneLayoutError.persistenceDataTooLarge(maximumBytes: maximumEncodedBytes)
        }
        try data.withUnsafeBytes { rawBuffer in
            var scanner = PaneLayoutJSONScanner(
                bytes: rawBuffer.bindMemory(to: UInt8.self)
            )
            try scanner.validate()
        }
        let decoder = JSONDecoder()
        decoder.userInfo[boundedDecodeKey] = boundedDecodeToken
        return try decoder.decode(Self.self, from: data)
    }

    public func identity(atVisualIndex index: Int) throws -> Identity {
        guard visualOrder.indices.contains(index) else {
            throw PaneLayoutError.invalidVisualIndex(index)
        }
        return visualOrder[index]
    }

    public func visualIndex(of identity: Identity) throws -> Int {
        guard let index = visualOrder.firstIndex(of: identity) else {
            throw PaneLayoutError.identityNotPresent(identity)
        }
        return index
    }

    public mutating func setActivePane(_ identity: Identity) throws {
        guard visualOrder.contains(identity) else {
            throw PaneLayoutError.identityNotPresent(identity)
        }
        activePane = identity
    }

    public mutating func setOrientation(_ orientation: Orientation) {
        self.orientation = orientation
    }

    public mutating func toggleOrientation() {
        orientation = orientation.toggled
    }

    public func settingOrientation(_ orientation: Orientation) -> PaneLayout {
        var result = self
        result.setOrientation(orientation)
        return result
    }

    public func togglingOrientation() -> PaneLayout {
        var result = self
        result.toggleOrientation()
        return result
    }

    /// Swaps logical document owners at two visual positions. Active identity follows its owner.
    ///
    /// By default, visual slot sizes stay fixed. Set `preservingPaneSizes` when each owner should
    /// carry its current size to the destination slot as well.
    public mutating func swapPanes(
        _ first: Identity,
        _ second: Identity,
        preservingPaneSizes: Bool = false
    ) throws {
        guard first != second else { throw PaneLayoutError.identicalSwapIdentities(first) }
        let firstIndex = try visualIndex(of: first)
        let secondIndex = try visualIndex(of: second)
        try swapVisualPanes(
            at: firstIndex,
            and: secondIndex,
            preservingPaneSizes: preservingPaneSizes
        )
    }

    public func swappingPanes(
        _ first: Identity,
        _ second: Identity,
        preservingPaneSizes: Bool = false
    ) throws -> PaneLayout {
        var result = self
        try result.swapPanes(first, second, preservingPaneSizes: preservingPaneSizes)
        return result
    }

    /// Performs the standard pane swap: left/right for two panes, outer panes for three panes.
    public mutating func swapPanes(preservingPaneSizes: Bool = false) throws {
        try swapVisualPanesUnchecked(
            at: visualOrder.startIndex,
            and: visualOrder.index(before: visualOrder.endIndex),
            preservingPaneSizes: preservingPaneSizes
        )
    }

    public func swappingPanes(preservingPaneSizes: Bool = false) throws -> PaneLayout {
        var result = self
        try result.swapPanes(preservingPaneSizes: preservingPaneSizes)
        return result
    }

    public mutating func swapVisualPanes(
        at firstIndex: Int,
        and secondIndex: Int,
        preservingPaneSizes: Bool = false
    ) throws {
        guard visualOrder.indices.contains(firstIndex) else {
            throw PaneLayoutError.invalidVisualIndex(firstIndex)
        }
        guard visualOrder.indices.contains(secondIndex) else {
            throw PaneLayoutError.invalidVisualIndex(secondIndex)
        }
        guard firstIndex != secondIndex else {
            throw PaneLayoutError.identicalVisualIndices(firstIndex)
        }
        try swapVisualPanesUnchecked(
            at: firstIndex,
            and: secondIndex,
            preservingPaneSizes: preservingPaneSizes
        )
    }

    public mutating func setSplitFractions(_ fractions: [Double]) throws {
        try Self.validateSplitFractions(
            fractions,
            paneCount: paneCount,
            minimumPaneFraction: minimumPaneFraction
        )
        splitFractions = fractions
    }

    /// Normalizes finite positive pane sizes into cumulative split fractions.
    public mutating func setPaneSizes(
        _ paneSizes: [Double],
        minimumPaneSize: Double = 0
    ) throws {
        splitFractions = try Self.normalizedSplitFractions(
            forPaneSizes: paneSizes,
            paneCount: paneCount,
            minimumPaneSize: minimumPaneSize,
            minimumPaneFraction: minimumPaneFraction
        )
    }

    /// Converts normalized pane fractions to sizes along a finite positive layout extent.
    public func paneSizes(
        forTotalSize totalSize: Double,
        minimumPaneSize: Double = 0
    ) throws -> [Double] {
        guard totalSize.isFinite else { throw PaneLayoutError.nonFiniteTotalSize }
        guard totalSize > 0 else { throw PaneLayoutError.nonPositiveTotalSize(totalSize) }
        try Self.validateMinimumPaneSize(minimumPaneSize)
        guard minimumPaneSize <= totalSize / Double(paneCount.rawValue) else {
            throw PaneLayoutError.minimumPaneSizeExceedsAvailableSize(
                minimumPaneSize: minimumPaneSize,
                totalSize: totalSize
            )
        }

        let sizes = paneFractions.map { $0 * totalSize }
        for (index, size) in sizes.enumerated() {
            guard size > 0 else {
                throw PaneLayoutError.nonPositivePaneSize(index: index, size: size)
            }
            guard size >= minimumPaneSize else {
                throw PaneLayoutError.paneSizeBelowMinimum(
                    index: index,
                    size: size,
                    minimum: minimumPaneSize
                )
            }
        }
        return sizes
    }

    public static func normalizedSplitFractions(
        forPaneSizes paneSizes: [Double],
        paneCount: PaneCount,
        minimumPaneSize: Double = 0,
        minimumPaneFraction: Double = Self.defaultMinimumPaneFraction
    ) throws -> [Double] {
        guard paneSizes.count == paneCount.rawValue else {
            throw PaneLayoutError.invalidPaneSizeCount(
                expected: paneCount.rawValue,
                actual: paneSizes.count
            )
        }
        try validateMinimumPaneSize(minimumPaneSize)
        try validateMinimumPaneFraction(minimumPaneFraction, paneCount: paneCount)

        for (index, size) in paneSizes.enumerated() {
            guard size.isFinite else { throw PaneLayoutError.nonFinitePaneSize(index: index) }
            guard size > 0 else {
                throw PaneLayoutError.nonPositivePaneSize(index: index, size: size)
            }
            guard size >= minimumPaneSize else {
                throw PaneLayoutError.paneSizeBelowMinimum(
                    index: index,
                    size: size,
                    minimum: minimumPaneSize
                )
            }
        }

        let scale = paneSizes.max()!
        let scaledSizes = paneSizes.map { $0 / scale }
        let scaledTotal = scaledSizes.reduce(0, +)
        for (index, size) in scaledSizes.enumerated() {
            let minimumScaledSize = minimumPaneFraction * scaledTotal
            let roundingTolerance = max(size.ulp, minimumScaledSize.ulp) * 4
            guard size >= minimumScaledSize - roundingTolerance else {
                throw PaneLayoutError.paneFractionBelowMinimum(
                    index: index,
                    fraction: size / scaledTotal,
                    minimum: minimumPaneFraction
                )
            }
        }
        return try constrainedSplitFractions(
            from: scaledSizes.map { $0 / scaledTotal },
            paneCount: paneCount,
            minimumPaneFraction: minimumPaneFraction
        )
    }

    /// Strictly maps identity-keyed owner values to current visual order.
    ///
    /// Extra values are rejected as well as missing values so a two/three-pane transition cannot
    /// silently discard a middle document or any owner-specific dirty/read-only state.
    public func valuesInVisualOrder<Value>(
        _ valuesByIdentity: [Identity: Value]
    ) throws -> [Value] {
        try validateOwnershipIdentities(Array(valuesByIdentity.keys))
        return visualOrder.map { valuesByIdentity[$0]! }
    }

    /// Strictly binds visual values to their logical identities in this layout.
    public func valuesByIdentity<Value>(
        fromVisualValues values: [Value]
    ) throws -> [Identity: Value] {
        guard values.count == visualOrder.count else {
            throw PaneLayoutError.invalidVisualValueCount(
                expected: visualOrder.count,
                actual: values.count
            )
        }
        return Dictionary(uniqueKeysWithValues: zip(visualOrder, values))
    }

    /// Remaps complete owner values from another visual order without reconstructing payloads.
    public func remapVisualValues<Value>(
        _ values: [Value],
        from sourceLayout: PaneLayout
    ) throws -> [Value] {
        guard paneCount == sourceLayout.paneCount else {
            throw PaneLayoutError.incompatiblePaneCounts(
                source: sourceLayout.paneCount.rawValue,
                destination: paneCount.rawValue
            )
        }
        return try valuesInVisualOrder(
            sourceLayout.valuesByIdentity(fromVisualValues: values)
        )
    }

    /// Orders identity-bound owners for display while keeping each payload attached to its owner.
    public func ownedValuesInVisualOrder<Value: Sendable>(
        _ values: [PaneOwnedValue<Value>]
    ) throws -> [PaneOwnedValue<Value>] {
        var valuesByIdentity: [Identity: PaneOwnedValue<Value>] = [:]
        valuesByIdentity.reserveCapacity(values.count)
        for value in values {
            guard valuesByIdentity.updateValue(value, forKey: value.identity) == nil else {
                throw PaneLayoutError.duplicateOwnedIdentity(value.identity)
            }
        }
        return try valuesInVisualOrder(valuesByIdentity)
    }

    public func remapOwnedValues<Value: Sendable>(
        _ values: [PaneOwnedValue<Value>]
    ) throws -> [PaneOwnedValue<Value>] {
        try ownedValuesInVisualOrder(values)
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PaneLayoutError.unsupportedSchemaVersion(schemaVersion)
        }
        guard visualOrder.count == paneCount.rawValue,
            Set(visualOrder) == Set(paneCount.identities)
        else {
            throw PaneLayoutError.invalidVisualOrder(visualOrder)
        }
        guard visualOrder.contains(activePane) else {
            throw PaneLayoutError.identityNotPresent(activePane)
        }
        try Self.validateMinimumPaneFraction(minimumPaneFraction, paneCount: paneCount)
        try Self.validateSplitFractions(
            splitFractions,
            paneCount: paneCount,
            minimumPaneFraction: minimumPaneFraction
        )
    }

    private static func defaultSplitFractions(for paneCount: PaneCount) -> [Double] {
        switch paneCount {
        case .two:
            [0.5]
        case .three:
            [1.0 / 3.0, 2.0 / 3.0]
        }
    }

    private mutating func swapVisualPanesUnchecked(
        at firstIndex: Int,
        and secondIndex: Int,
        preservingPaneSizes: Bool
    ) throws {
        var replacementFractions = splitFractions
        if preservingPaneSizes {
            var sizes = paneFractions
            sizes.swapAt(firstIndex, secondIndex)
            replacementFractions = try Self.constrainedSplitFractions(
                from: sizes,
                paneCount: paneCount,
                minimumPaneFraction: minimumPaneFraction
            )
        }
        visualOrder.swapAt(firstIndex, secondIndex)
        splitFractions = replacementFractions
    }

    private static func constrainedSplitFractions(
        from paneFractions: [Double],
        paneCount: PaneCount,
        minimumPaneFraction: Double
    ) throws -> [Double] {
        var desired: [Double] = []
        desired.reserveCapacity(paneCount.rawValue - 1)
        var cumulativeFraction = 0.0
        for fraction in paneFractions.dropLast() {
            cumulativeFraction += fraction
            desired.append(cumulativeFraction)
        }

        var upperBounds = Array(repeating: 0.0, count: desired.count)
        var nextBoundary = 1.0
        for index in upperBounds.indices.reversed() {
            var upperBound = nextBoundary - minimumPaneFraction
            while nextBoundary - upperBound < minimumPaneFraction {
                upperBound = upperBound.nextDown
            }
            upperBounds[index] = upperBound
            nextBoundary = upperBound
        }

        var result: [Double] = []
        result.reserveCapacity(desired.count)
        var previous = 0.0
        for index in desired.indices {
            var lowerBound = previous + minimumPaneFraction
            while lowerBound - previous < minimumPaneFraction {
                lowerBound = lowerBound.nextUp
            }
            guard lowerBound <= upperBounds[index] else {
                throw PaneLayoutError.invalidMinimumPaneFraction(
                    minimumPaneFraction,
                    maximum: 1.0 / Double(paneCount.rawValue)
                )
            }
            let fraction = max(lowerBound, min(desired[index], upperBounds[index]))
            result.append(fraction)
            previous = fraction
        }

        try validateSplitFractions(
            result,
            paneCount: paneCount,
            minimumPaneFraction: minimumPaneFraction
        )
        let representedFractions = Self.paneFractions(fromSplitFractions: result)
        for index in paneFractions.indices {
            let expected = paneFractions[index]
            let represented = representedFractions[index]
            let tolerance = max(expected.ulp, represented.ulp) * 32
            guard abs(expected - represented) <= tolerance else {
                throw PaneLayoutError.unrepresentablePaneFraction(
                    index: index,
                    fraction: expected
                )
            }
        }
        return result
    }

    private static func paneFractions(fromSplitFractions splitFractions: [Double]) -> [Double] {
        var previous = 0.0
        var result: [Double] = []
        result.reserveCapacity(splitFractions.count + 1)
        for fraction in splitFractions {
            result.append(fraction - previous)
            previous = fraction
        }
        result.append(1.0 - previous)
        return result
    }

    private func validateOwnershipIdentities(_ identities: [Identity]) throws {
        guard identities.count == paneCount.rawValue,
            Set(identities) == Set(paneCount.identities)
        else {
            let supplied = Identity.allCases.filter(Set(identities).contains)
            throw PaneLayoutError.invalidOwnershipIdentities(supplied)
        }
    }

    private static func validateMinimumPaneSize(_ minimumPaneSize: Double) throws {
        guard minimumPaneSize.isFinite else {
            throw PaneLayoutError.nonFiniteMinimumPaneSize
        }
        guard minimumPaneSize >= 0 else {
            throw PaneLayoutError.negativeMinimumPaneSize(minimumPaneSize)
        }
    }

    private static func validateMinimumPaneFraction(
        _ minimumPaneFraction: Double,
        paneCount: PaneCount
    ) throws {
        guard minimumPaneFraction.isFinite else {
            throw PaneLayoutError.nonFiniteMinimumPaneFraction
        }
        let maximum = 1.0 / Double(paneCount.rawValue)
        guard minimumPaneFraction > 0,
            minimumPaneFraction <= maximum
        else {
            throw PaneLayoutError.invalidMinimumPaneFraction(
                minimumPaneFraction,
                maximum: maximum
            )
        }
    }

    private static func validateSplitFractions(
        _ splitFractions: [Double],
        paneCount: PaneCount,
        minimumPaneFraction: Double
    ) throws {
        let expectedCount = paneCount.rawValue - 1
        guard splitFractions.count == expectedCount else {
            throw PaneLayoutError.invalidSplitFractionCount(
                expected: expectedCount,
                actual: splitFractions.count
            )
        }

        var previous = 0.0
        for (index, fraction) in splitFractions.enumerated() {
            guard fraction.isFinite else {
                throw PaneLayoutError.nonFiniteSplitFraction(index: index)
            }
            guard fraction > previous, fraction < 1 else {
                throw PaneLayoutError.invalidSplitFraction(index: index, value: fraction)
            }
            let paneFraction = fraction - previous
            guard paneFraction >= minimumPaneFraction else {
                throw PaneLayoutError.paneFractionBelowMinimum(
                    index: index,
                    fraction: paneFraction,
                    minimum: minimumPaneFraction
                )
            }
            previous = fraction
        }

        let finalPaneFraction = 1.0 - previous
        guard finalPaneFraction >= minimumPaneFraction else {
            throw PaneLayoutError.paneFractionBelowMinimum(
                index: paneCount.rawValue - 1,
                fraction: finalPaneFraction,
                minimum: minimumPaneFraction
            )
        }
    }

}

public typealias PaneSplitOrientation = PaneLayout.Orientation
public typealias PaneLayoutCount = PaneLayout.PaneCount

public enum PaneLayoutError: Error, Equatable, LocalizedError, Sendable {
    case persistenceDataTooLarge(maximumBytes: Int)
    case boundedDecodingRequired
    case invalidJSON
    case duplicateJSONKey(String)
    case jsonNestingTooDeep(maximumDepth: Int)
    case unsupportedSchemaVersion(Int)
    case invalidPaneCount(Int)
    case invalidVisualOrder([PaneIdentity])
    case identityNotPresent(PaneIdentity)
    case invalidVisualIndex(Int)
    case identicalSwapIdentities(PaneIdentity)
    case identicalVisualIndices(Int)
    case invalidSplitFractionCount(expected: Int, actual: Int)
    case nonFiniteSplitFraction(index: Int)
    case invalidSplitFraction(index: Int, value: Double)
    case nonFiniteMinimumPaneFraction
    case invalidMinimumPaneFraction(Double, maximum: Double)
    case paneFractionBelowMinimum(index: Int, fraction: Double, minimum: Double)
    case unrepresentablePaneFraction(index: Int, fraction: Double)
    case invalidPaneSizeCount(expected: Int, actual: Int)
    case nonFinitePaneSize(index: Int)
    case nonPositivePaneSize(index: Int, size: Double)
    case nonFiniteTotalSize
    case nonPositiveTotalSize(Double)
    case nonFiniteMinimumPaneSize
    case negativeMinimumPaneSize(Double)
    case minimumPaneSizeExceedsAvailableSize(minimumPaneSize: Double, totalSize: Double)
    case paneSizeBelowMinimum(index: Int, size: Double, minimum: Double)
    case invalidVisualValueCount(expected: Int, actual: Int)
    case invalidOwnershipIdentities([PaneIdentity])
    case duplicateOwnedIdentity(PaneIdentity)
    case incompatiblePaneCounts(source: Int, destination: Int)

    public var errorDescription: String? {
        switch self {
        case .persistenceDataTooLarge(let maximumBytes):
            "Pane layout persistence data exceeds the \(maximumBytes)-byte limit."
        case .boundedDecodingRequired:
            "Pane layouts must be decoded with PaneLayout.decode(from:) to enforce persistence bounds."
        case .invalidJSON:
            "Pane layout persistence data is not valid JSON."
        case .duplicateJSONKey(let key):
            "Pane layout JSON key appears more than once in one object: \(key)."
        case .jsonNestingTooDeep(let maximumDepth):
            "Pane layout JSON exceeds the \(maximumDepth)-level nesting limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported pane layout schema version: \(version)."
        case .invalidPaneCount(let count):
            "A pane layout must contain two or three panes, not \(count)."
        case .invalidVisualOrder(let order):
            "Invalid pane visual order: \(order.map(\.rawValue).joined(separator: ", "))."
        case .identityNotPresent(let identity):
            "Pane identity is not present in this layout: \(identity.rawValue)."
        case .invalidVisualIndex(let index):
            "Pane visual index is outside this layout: \(index)."
        case .identicalSwapIdentities(let identity):
            "Cannot swap pane identity \(identity.rawValue) with itself."
        case .identicalVisualIndices(let index):
            "Cannot swap pane visual index \(index) with itself."
        case .invalidSplitFractionCount(let expected, let actual):
            "Pane layout requires \(expected) split fractions, not \(actual)."
        case .nonFiniteSplitFraction(let index):
            "Pane split fraction at index \(index) must be finite."
        case .invalidSplitFraction(let index, let value):
            "Pane split fraction at index \(index) must be strictly ordered between zero and one: \(value)."
        case .nonFiniteMinimumPaneFraction:
            "Minimum pane fraction must be finite."
        case .invalidMinimumPaneFraction(let fraction, let maximum):
            "Minimum pane fraction must be greater than zero and at most \(maximum): \(fraction)."
        case .paneFractionBelowMinimum(let index, let fraction, let minimum):
            "Pane fraction at index \(index) is below the \(minimum) minimum: \(fraction)."
        case .unrepresentablePaneFraction(let index, let fraction):
            "Pane fraction at index \(index) cannot be represented by normalized split fractions: \(fraction)."
        case .invalidPaneSizeCount(let expected, let actual):
            "Pane layout requires \(expected) pane sizes, not \(actual)."
        case .nonFinitePaneSize(let index):
            "Pane size at index \(index) must be finite."
        case .nonPositivePaneSize(let index, let size):
            "Pane size at index \(index) must be positive: \(size)."
        case .nonFiniteTotalSize:
            "Pane layout total size must be finite."
        case .nonPositiveTotalSize(let size):
            "Pane layout total size must be positive: \(size)."
        case .nonFiniteMinimumPaneSize:
            "Minimum pane size must be finite."
        case .negativeMinimumPaneSize(let size):
            "Minimum pane size must not be negative: \(size)."
        case .minimumPaneSizeExceedsAvailableSize(let minimumPaneSize, let totalSize):
            "Minimum pane size \(minimumPaneSize) cannot fit in available size \(totalSize)."
        case .paneSizeBelowMinimum(let index, let size, let minimum):
            "Pane size at index \(index) is below the \(minimum) minimum: \(size)."
        case .invalidVisualValueCount(let expected, let actual):
            "Pane remapping requires \(expected) visual values, not \(actual)."
        case .invalidOwnershipIdentities(let identities):
            "Pane owner identities do not exactly match the layout: \(identities.map(\.rawValue).joined(separator: ", "))."
        case .duplicateOwnedIdentity(let identity):
            "Pane owner identity appears more than once: \(identity.rawValue)."
        case .incompatiblePaneCounts(let source, let destination):
            "Cannot remap \(source)-pane owner values into a \(destination)-pane layout."
        }
    }
}

private struct PaneLayoutJSONScanner {
    private static let maximumNestingDepth = 16

    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw PaneLayoutError.invalidJSON }
    }

    private mutating func parseValue(depth: Int) throws {
        guard let byte = currentByte else { throw PaneLayoutError.invalidJSON }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString(capturing: false)
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw PaneLayoutError.invalidJSON
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }

        var keys: Set<String> = []
        while true {
            let key = try parseString(capturing: true)
            guard keys.insert(key).inserted else {
                throw PaneLayoutError.duplicateJSONKey(key)
            }
            skipWhitespace()
            guard consume(0x3A) else { throw PaneLayoutError.invalidJSON }
            skipWhitespace()
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw PaneLayoutError.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x5D) { return }

        while true {
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw PaneLayoutError.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseString(capturing: Bool) throws -> String {
        let start = index
        guard consume(0x22) else { throw PaneLayoutError.invalidJSON }
        while let byte = currentByte {
            index += 1
            switch byte {
            case 0x22:
                guard capturing else { return "" }
                do {
                    return try JSONDecoder().decode(
                        String.self,
                        from: Data(bytes[start..<index])
                    )
                } catch {
                    throw PaneLayoutError.invalidJSON
                }
            case 0x00...0x1F:
                throw PaneLayoutError.invalidJSON
            case 0x5C:
                try parseEscape()
            default:
                break
            }
        }
        throw PaneLayoutError.invalidJSON
    }

    private mutating func parseEscape() throws {
        guard let escaped = currentByte else { throw PaneLayoutError.invalidJSON }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74:
            return
        case 0x75:
            for _ in 0..<4 {
                guard let byte = currentByte, Self.hexValue(byte) != nil else {
                    throw PaneLayoutError.invalidJSON
                }
                index += 1
            }
        default:
            throw PaneLayoutError.invalidJSON
        }
    }

    private mutating func parseNumber() throws {
        _ = consume(0x2D)
        guard let first = currentByte else { throw PaneLayoutError.invalidJSON }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw PaneLayoutError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw PaneLayoutError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw PaneLayoutError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x65) || consume(0x45) {
            _ = consume(0x2B) || consume(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw PaneLayoutError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else {
            throw PaneLayoutError.invalidJSON
        }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw PaneLayoutError.invalidJSON }
            index += 1
        }
    }

    private func validateDepth(_ depth: Int) throws {
        guard depth <= Self.maximumNestingDepth else {
            throw PaneLayoutError.jsonNestingTooDeep(
                maximumDepth: Self.maximumNestingDepth
            )
        }
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }
}
