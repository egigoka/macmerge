import Foundation

/// Persistable, UI-independent configuration for the comparison toolbar.
public struct ToolbarConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumItemCount = 64
    public static let maximumEncodedBytes = 16 * 1024

    fileprivate static let maximumJSONNestingDepth = 8
    fileprivate static let maximumJSONContainerElements = maximumItemCount
    fileprivate static let maximumJSONValueCount = 128
    fileprivate static let maximumJSONKeyUTF8Bytes = 64
    fileprivate static let maximumJSONStringUTF8Bytes = 256
    fileprivate static let maximumTotalJSONStringUTF8Bytes = 8 * 1024
    fileprivate static let maximumJSONNumberBytes = 32

    public enum Visibility: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case hidden
        case visible
    }

    /// WinMerge's four supported visible toolbar sizes. Hidden state is modeled separately.
    public enum Size: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case small
        case medium
        case big
        case huge

        public var imageDimension: Double {
            switch self {
            case .small: 16
            case .medium: 24
            case .big: 32
            case .huge: 40
            }
        }

        public var defaultCommandWidth: Double { imageDimension + 8 }
    }

    /// Stable command identities. Raw values form the persistence contract.
    public enum Command: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case newComparison
        case openComparison
        case save
        case undo
        case redo
        case selectLineDifference
        case nextDifference
        case previousDifference
        case nextConflict
        case previousConflict
        case firstDifference
        case currentDifference
        case lastDifference
        case copyToRight
        case copyToLeft
        case copyToRightAndAdvance
        case copyToLeftAndAdvance
        case copyAllToRight
        case copyAllToLeft
        case autoMerge
        case firstComparedFile
        case previousComparedFile
        case nextComparedFile
        case lastComparedFile
        case options
        case refresh

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let command = Self(rawValue: rawValue) else {
                throw ToolbarConfigurationError.unknownCommand(rawValue)
            }
            self = command
        }
    }

    public enum Item: Codable, Equatable, Hashable, Sendable {
        case command(Command)
        case separator

        private static let separatorWireValue = "separator"

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if rawValue == Self.separatorWireValue {
                self = .separator
            } else if let command = Command(rawValue: rawValue) {
                self = .command(command)
            } else {
                throw ToolbarConfigurationError.unknownCommand(rawValue)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .command(let command):
                try container.encode(command.rawValue)
            case .separator:
                try container.encode(Self.separatorWireValue)
            }
        }

        public var command: Command? {
            guard case .command(let command) = self else { return nil }
            return command
        }
    }

    /// Exact `IDR_MAINFRAME` order and separators from WinMerge's `Merge2.rc`.
    public static let winMergeDefaultItems: [Item] = [
        .command(.newComparison),
        .command(.openComparison),
        .command(.save),
        .separator,
        .command(.undo),
        .command(.redo),
        .separator,
        .command(.selectLineDifference),
        .separator,
        .command(.nextDifference),
        .command(.previousDifference),
        .separator,
        .command(.nextConflict),
        .command(.previousConflict),
        .separator,
        .command(.firstDifference),
        .command(.currentDifference),
        .command(.lastDifference),
        .separator,
        .command(.copyToRight),
        .command(.copyToLeft),
        .separator,
        .command(.copyToRightAndAdvance),
        .command(.copyToLeftAndAdvance),
        .separator,
        .command(.copyAllToRight),
        .command(.copyAllToLeft),
        .separator,
        .command(.autoMerge),
        .separator,
        .command(.firstComparedFile),
        .command(.previousComparedFile),
        .command(.nextComparedFile),
        .command(.lastComparedFile),
        .separator,
        .command(.options),
        .separator,
        .command(.refresh),
        .separator
    ]

    public static let defaultItems = winMergeDefaultItems
    public static let winMergeDefault = ToolbarConfiguration()
    public static let defaultConfiguration = winMergeDefault

    public let schemaVersion: Int
    public var visibility: Visibility
    public var size: Size
    public private(set) var items: [Item]

    public var isVisible: Bool {
        get { visibility == .visible }
        set { visibility = newValue ? .visible : .hidden }
    }

    public var commands: [Command] { items.compactMap(\.command) }
    public var isCustomized: Bool { self != Self.winMergeDefault }

    public init() {
        schemaVersion = Self.currentSchemaVersion
        visibility = .visible
        size = .small
        items = Self.winMergeDefaultItems
    }

    public init(
        visibility: Visibility = .visible,
        size: Size = .small,
        items: [Item]
    ) throws {
        try Self.validate(items)
        schemaVersion = Self.currentSchemaVersion
        self.visibility = visibility
        self.size = size
        self.items = items
    }

    public mutating func setItems(_ items: [Item]) throws {
        try Self.validate(items)
        self.items = items
    }

    public mutating func replaceItems(with items: [Item]) throws {
        try setItems(items)
    }

    public mutating func insert(_ item: Item, at index: Int) throws {
        guard (0...items.count).contains(index) else {
            throw ToolbarConfigurationError.invalidItemIndex(index)
        }
        var candidate = items
        candidate.insert(item, at: index)
        try setItems(candidate)
    }

    @discardableResult
    public mutating func removeItem(at index: Int) throws -> Item {
        guard items.indices.contains(index) else {
            throw ToolbarConfigurationError.invalidItemIndex(index)
        }
        return items.remove(at: index)
    }

    /// Moves an item to an insertion boundary in the original array; `items.count` means the end.
    public mutating func moveItem(from sourceIndex: Int, to destinationIndex: Int) throws {
        guard items.indices.contains(sourceIndex) else {
            throw ToolbarConfigurationError.invalidItemIndex(sourceIndex)
        }
        guard (0...items.count).contains(destinationIndex) else {
            throw ToolbarConfigurationError.invalidItemIndex(destinationIndex)
        }
        guard sourceIndex != destinationIndex, sourceIndex + 1 != destinationIndex else { return }

        var candidate = items
        let item = candidate.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex
            ? destinationIndex - 1
            : destinationIndex
        candidate.insert(item, at: adjustedDestination)
        try setItems(candidate)
    }

    @discardableResult
    public mutating func remove(_ command: Command) -> Bool {
        guard let index = items.firstIndex(of: .command(command)) else { return false }
        items.remove(at: index)
        return true
    }

    public mutating func resetToWinMergeDefaults() {
        self = Self.winMergeDefault
    }

    public mutating func reset() {
        resetToWinMergeDefaults()
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ToolbarConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.validate(items)
    }

    /// Compact JSON with stable object-key ordering for `UserDefaults` or scene persistence.
    public func encodedData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw ToolbarConfigurationError.encodedDataTooLarge(
                maximumBytes: Self.maximumEncodedBytes
            )
        }
        return data
    }

    /// Decodes untrusted persistence only after bounded structural JSON validation.
    public static func decode(from data: Data) throws -> ToolbarConfiguration {
        guard data.count <= maximumEncodedBytes else {
            throw ToolbarConfigurationError.encodedDataTooLarge(
                maximumBytes: maximumEncodedBytes
            )
        }
        try preflightJSON(data)
        let configuration = try JSONDecoder().decode(Self.self, from: data)
        try configuration.validate()
        return configuration
    }

    public struct LayoutMetrics: Equatable, Sendable {
        public static let defaultSeparatorWidth = 8.0
        public static let defaultOverflowButtonWidth = 28.0
        public static let maximumItemWidth = 1_000_000.0

        public let commandWidths: [Command: Double]
        public let separatorWidth: Double
        public let overflowButtonWidth: Double

        public init(
            commandWidths: [Command: Double] = [:],
            separatorWidth: Double = defaultSeparatorWidth,
            overflowButtonWidth: Double = defaultOverflowButtonWidth
        ) throws {
            for (command, width) in commandWidths {
                guard width.isFinite, width > 0, width <= Self.maximumItemWidth else {
                    throw ToolbarConfigurationError.invalidCommandWidth(command)
                }
            }
            guard separatorWidth.isFinite,
                separatorWidth >= 0,
                separatorWidth <= Self.maximumItemWidth
            else {
                throw ToolbarConfigurationError.invalidSeparatorWidth
            }
            guard overflowButtonWidth.isFinite,
                overflowButtonWidth > 0,
                overflowButtonWidth <= Self.maximumItemWidth
            else {
                throw ToolbarConfigurationError.invalidOverflowButtonWidth
            }
            self.commandWidths = commandWidths
            self.separatorWidth = separatorWidth
            self.overflowButtonWidth = overflowButtonWidth
        }

        fileprivate func width(of item: Item, size: Size) -> Double {
            switch item {
            case .command(let command):
                commandWidths[command] ?? size.defaultCommandWidth
            case .separator:
                separatorWidth
            }
        }
    }

    public struct Layout: Equatable, Sendable {
        public let isToolbarVisible: Bool
        public let visibleItems: [Item]
        public let overflowItems: [Item]
        public let showsOverflowButton: Bool
        public let occupiedWidth: Double

        /// Exact identity-preserving partition of configured items.
        public var representedItems: [Item] { visibleItems + overflowItems }
        public var visibleCommands: [Command] { visibleItems.compactMap(\.command) }
        public var overflowCommands: [Command] { overflowItems.compactMap(\.command) }
    }

    /// Selects a leading visible run and places every remaining item in overflow.
    /// No command is discarded; `representedItems` always equals `items`.
    public func layout(
        availableWidth: Double,
        metrics: LayoutMetrics? = nil
    ) throws -> Layout {
        guard availableWidth.isFinite, availableWidth >= 0 else {
            throw ToolbarConfigurationError.invalidAvailableWidth
        }
        let metrics = try metrics ?? LayoutMetrics()

        guard isVisible else {
            return Layout(
                isToolbarVisible: false,
                visibleItems: [],
                overflowItems: items,
                showsOverflowButton: false,
                occupiedWidth: 0
            )
        }
        guard !items.isEmpty else {
            return Layout(
                isToolbarVisible: true,
                visibleItems: [],
                overflowItems: [],
                showsOverflowButton: false,
                occupiedWidth: 0
            )
        }

        let totalWidth = items.reduce(into: 0.0) {
            $0 += metrics.width(of: $1, size: size)
        }
        if totalWidth <= availableWidth {
            return Layout(
                isToolbarVisible: true,
                visibleItems: items,
                overflowItems: [],
                showsOverflowButton: false,
                occupiedWidth: totalWidth
            )
        }

        let visibleCapacity = max(0, availableWidth - metrics.overflowButtonWidth)
        var splitIndex = 0
        var visibleWidth = 0.0
        while splitIndex < items.count {
            let itemWidth = metrics.width(of: items[splitIndex], size: size)
            guard visibleWidth + itemWidth <= visibleCapacity else { break }
            visibleWidth += itemWidth
            splitIndex += 1
        }

        // Avoid leaving a decorative separator at the visible trailing edge.
        while splitIndex > 0, items[splitIndex - 1] == .separator {
            splitIndex -= 1
            visibleWidth -= metrics.separatorWidth
        }

        return Layout(
            isToolbarVisible: true,
            visibleItems: Array(items[..<splitIndex]),
            overflowItems: Array(items[splitIndex...]),
            showsOverflowButton: true,
            occupiedWidth: visibleWidth + metrics.overflowButtonWidth
        )
    }

    private static func validate(_ items: [Item]) throws {
        guard items.count <= maximumItemCount else {
            throw ToolbarConfigurationError.tooManyItems(maximumCount: maximumItemCount)
        }
        var seen: Set<Command> = []
        for case .command(let command) in items {
            guard seen.insert(command).inserted else {
                throw ToolbarConfigurationError.duplicateCommand(command)
            }
        }
    }

    private enum CodingField: String, CaseIterable {
        case schemaVersion
        case visibility
        case size
        case items

        var key: ToolbarCodingKey { ToolbarCodingKey(stringValue: rawValue) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ToolbarCodingKey.self)
        let allowedFields = Set(CodingField.allCases.map(\.rawValue))
        if let unknownField = container.allKeys.map(\.stringValue)
            .filter({ !allowedFields.contains($0) })
            .sorted()
            .first
        {
            throw ToolbarConfigurationError.unknownField(unknownField)
        }

        let schemaVersion = try container.decode(
            Int.self,
            forKey: CodingField.schemaVersion.key
        )
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ToolbarConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        let visibility = try container.decode(
            Visibility.self,
            forKey: CodingField.visibility.key
        )
        let size = try container.decode(Size.self, forKey: CodingField.size.key)
        var itemContainer = try container.nestedUnkeyedContainer(
            forKey: CodingField.items.key
        )
        if let count = itemContainer.count, count > Self.maximumItemCount {
            throw ToolbarConfigurationError.tooManyItems(
                maximumCount: Self.maximumItemCount
            )
        }

        var items: [Item] = []
        items.reserveCapacity(min(itemContainer.count ?? 0, Self.maximumItemCount))
        while !itemContainer.isAtEnd {
            guard items.count < Self.maximumItemCount else {
                throw ToolbarConfigurationError.tooManyItems(
                    maximumCount: Self.maximumItemCount
                )
            }
            items.append(try itemContainer.decode(Item.self))
        }
        try Self.validate(items)

        self.schemaVersion = schemaVersion
        self.visibility = visibility
        self.size = size
        self.items = items
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: ToolbarCodingKey.self)
        try container.encode(schemaVersion, forKey: CodingField.schemaVersion.key)
        try container.encode(visibility, forKey: CodingField.visibility.key)
        try container.encode(size, forKey: CodingField.size.key)
        try container.encode(items, forKey: CodingField.items.key)
    }

    private static func preflightJSON(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            var scanner = ToolbarJSONScanner(
                bytes: rawBuffer.bindMemory(to: UInt8.self)
            )
            try scanner.validate()
        }
    }
}

public enum ToolbarConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case encodedDataTooLarge(maximumBytes: Int)
    case invalidJSON
    case jsonNestingTooDeep(maximumDepth: Int)
    case jsonContainerTooLarge(maximumElements: Int)
    case tooManyJSONValues(maximumValues: Int)
    case jsonStringTooLarge(maximumBytes: Int)
    case jsonNumberTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case unknownField(String)
    case unknownCommand(String)
    case duplicateCommand(ToolbarConfiguration.Command)
    case tooManyItems(maximumCount: Int)
    case invalidItemIndex(Int)
    case invalidAvailableWidth
    case invalidCommandWidth(ToolbarConfiguration.Command)
    case invalidSeparatorWidth
    case invalidOverflowButtonWidth

    public var errorDescription: String? {
        switch self {
        case .encodedDataTooLarge(let maximumBytes):
            "Toolbar configuration exceeds the \(maximumBytes)-byte limit."
        case .invalidJSON:
            "Toolbar configuration is not valid JSON."
        case .jsonNestingTooDeep(let maximumDepth):
            "Toolbar configuration JSON exceeds the \(maximumDepth)-level nesting limit."
        case .jsonContainerTooLarge(let maximumElements):
            "A toolbar configuration JSON container exceeds the \(maximumElements)-element limit."
        case .tooManyJSONValues(let maximumValues):
            "Toolbar configuration JSON exceeds the \(maximumValues)-value limit."
        case .jsonStringTooLarge(let maximumBytes):
            "A toolbar configuration JSON string exceeds the \(maximumBytes)-byte limit."
        case .jsonNumberTooLarge(let maximumBytes):
            "A toolbar configuration JSON number exceeds the \(maximumBytes)-byte limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported toolbar configuration schema version: \(version)."
        case .unknownField(let field):
            "Unknown toolbar configuration field: \(field)."
        case .unknownCommand(let command):
            "Unknown toolbar command: \(command)."
        case .duplicateCommand(let command):
            "Toolbar command appears more than once: \(command.rawValue)."
        case .tooManyItems(let maximumCount):
            "Toolbar configuration cannot exceed \(maximumCount) items."
        case .invalidItemIndex(let index):
            "Invalid toolbar item index: \(index)."
        case .invalidAvailableWidth:
            "Available toolbar width must be finite and nonnegative."
        case .invalidCommandWidth(let command):
            "Width for toolbar command \(command.rawValue) is invalid."
        case .invalidSeparatorWidth:
            "Toolbar separator width must be finite, nonnegative, and bounded."
        case .invalidOverflowButtonWidth:
            "Toolbar overflow button width must be finite, positive, and bounded."
        }
    }
}

private struct ToolbarCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct ToolbarJSONScanner {
    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0
    private var valueCount = 0
    private var totalStringByteCount = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw ToolbarConfigurationError.invalidJSON }
    }

    private mutating func parseValue(depth: Int) throws {
        guard valueCount < ToolbarConfiguration.maximumJSONValueCount else {
            throw ToolbarConfigurationError.tooManyJSONValues(
                maximumValues: ToolbarConfiguration.maximumJSONValueCount
            )
        }
        valueCount += 1
        guard let byte = currentByte else { throw ToolbarConfigurationError.invalidJSON }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString(
                maximumBytes: ToolbarConfiguration.maximumJSONStringUTF8Bytes,
                capture: false
            )
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw ToolbarConfigurationError.invalidJSON
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }

        var elementCount = 0
        var keys: Set<String> = []
        while true {
            try incrementContainerCount(&elementCount)
            guard currentByte == 0x22 else { throw ToolbarConfigurationError.invalidJSON }
            let key = try parseString(
                maximumBytes: ToolbarConfiguration.maximumJSONKeyUTF8Bytes,
                capture: true
            )
            guard keys.insert(key).inserted else {
                throw ToolbarConfigurationError.invalidJSON
            }
            skipWhitespace()
            guard consume(0x3A) else { throw ToolbarConfigurationError.invalidJSON }
            skipWhitespace()
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw ToolbarConfigurationError.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x5D) { return }

        var elementCount = 0
        while true {
            try incrementContainerCount(&elementCount)
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw ToolbarConfigurationError.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseString(maximumBytes: Int, capture: Bool) throws -> String {
        guard consume(0x22) else { throw ToolbarConfigurationError.invalidJSON }
        var decodedBytes: [UInt8] = []
        if capture { decodedBytes.reserveCapacity(min(maximumBytes, 32)) }
        var byteCount = 0

        while let byte = currentByte {
            switch byte {
            case 0x22:
                index += 1
                return capture ? String(decoding: decodedBytes, as: UTF8.self) : ""
            case 0x00...0x1F:
                throw ToolbarConfigurationError.invalidJSON
            case 0x5C:
                index += 1
                try parseEscape(
                    byteCount: &byteCount,
                    decodedBytes: &decodedBytes,
                    maximumBytes: maximumBytes,
                    capture: capture
                )
            case 0x00...0x7F:
                try accountStringBytes(1, byteCount: &byteCount, maximumBytes: maximumBytes)
                index += 1
                if capture { decodedBytes.append(byte) }
            default:
                let length = try rawUTF8ScalarLength()
                try accountStringBytes(
                    length,
                    byteCount: &byteCount,
                    maximumBytes: maximumBytes
                )
                if capture { decodedBytes.append(contentsOf: bytes[index..<(index + length)]) }
                index += length
            }
        }
        throw ToolbarConfigurationError.invalidJSON
    }

    private mutating func parseEscape(
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        capture: Bool
    ) throws {
        guard let escaped = currentByte else { throw ToolbarConfigurationError.invalidJSON }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            try appendEscapedByte(
                escaped,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        case 0x62:
            try appendEscapedByte(0x08, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x66:
            try appendEscapedByte(0x0C, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x6E:
            try appendEscapedByte(0x0A, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x72:
            try appendEscapedByte(0x0D, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x74:
            try appendEscapedByte(0x09, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x75:
            let scalar = try parseUnicodeScalar()
            try appendEscapedScalar(
                scalar,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        default:
            throw ToolbarConfigurationError.invalidJSON
        }
    }

    private mutating func parseUnicodeScalar() throws -> UInt32 {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            guard consume(0x5C), consume(0x75) else {
                throw ToolbarConfigurationError.invalidJSON
            }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw ToolbarConfigurationError.invalidJSON
            }
            return 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
        }
        guard !(0xDC00...0xDFFF).contains(first) else {
            throw ToolbarConfigurationError.invalidJSON
        }
        return UInt32(first)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw ToolbarConfigurationError.invalidJSON
            }
            value = value * 16 + UInt16(digit)
            index += 1
        }
        return value
    }

    private mutating func appendEscapedByte(
        _ byte: UInt8,
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        capture: Bool
    ) throws {
        try accountStringBytes(1, byteCount: &byteCount, maximumBytes: maximumBytes)
        if capture { decodedBytes.append(byte) }
    }

    private mutating func appendEscapedScalar(
        _ scalar: UInt32,
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        capture: Bool
    ) throws {
        let length: Int
        switch scalar {
        case 0...0x7F: length = 1
        case 0x80...0x7FF: length = 2
        case 0x800...0xFFFF: length = 3
        default: length = 4
        }
        try accountStringBytes(length, byteCount: &byteCount, maximumBytes: maximumBytes)
        guard capture else { return }
        switch length {
        case 1:
            decodedBytes.append(UInt8(scalar))
        case 2:
            decodedBytes.append(0xC0 | UInt8(scalar >> 6))
            decodedBytes.append(0x80 | UInt8(scalar & 0x3F))
        case 3:
            decodedBytes.append(0xE0 | UInt8(scalar >> 12))
            decodedBytes.append(0x80 | UInt8((scalar >> 6) & 0x3F))
            decodedBytes.append(0x80 | UInt8(scalar & 0x3F))
        default:
            decodedBytes.append(0xF0 | UInt8(scalar >> 18))
            decodedBytes.append(0x80 | UInt8((scalar >> 12) & 0x3F))
            decodedBytes.append(0x80 | UInt8((scalar >> 6) & 0x3F))
            decodedBytes.append(0x80 | UInt8(scalar & 0x3F))
        }
    }

    private mutating func accountStringBytes(
        _ addedCount: Int,
        byteCount: inout Int,
        maximumBytes: Int
    ) throws {
        guard byteCount <= maximumBytes - addedCount,
            totalStringByteCount <= ToolbarConfiguration.maximumTotalJSONStringUTF8Bytes - addedCount
        else {
            throw ToolbarConfigurationError.jsonStringTooLarge(
                maximumBytes: maximumBytes
            )
        }
        byteCount += addedCount
        totalStringByteCount += addedCount
    }

    private func rawUTF8ScalarLength() throws -> Int {
        guard let first = currentByte else { throw ToolbarConfigurationError.invalidJSON }
        let length: Int
        let secondRange: ClosedRange<UInt8>
        switch first {
        case 0xC2...0xDF:
            length = 2
            secondRange = 0x80...0xBF
        case 0xE0:
            length = 3
            secondRange = 0xA0...0xBF
        case 0xE1...0xEC, 0xEE...0xEF:
            length = 3
            secondRange = 0x80...0xBF
        case 0xED:
            length = 3
            secondRange = 0x80...0x9F
        case 0xF0:
            length = 4
            secondRange = 0x90...0xBF
        case 0xF1...0xF3:
            length = 4
            secondRange = 0x80...0xBF
        case 0xF4:
            length = 4
            secondRange = 0x80...0x8F
        default:
            throw ToolbarConfigurationError.invalidJSON
        }
        guard index <= bytes.count - length,
            secondRange.contains(bytes[index + 1])
        else {
            throw ToolbarConfigurationError.invalidJSON
        }
        for offset in 2..<length where !(0x80...0xBF).contains(bytes[index + offset]) {
            throw ToolbarConfigurationError.invalidJSON
        }
        return length
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = consume(0x2D)
        guard let first = currentByte else { throw ToolbarConfigurationError.invalidJSON }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw ToolbarConfigurationError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw ToolbarConfigurationError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw ToolbarConfigurationError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x65) || consume(0x45) {
            _ = consume(0x2B) || consume(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw ToolbarConfigurationError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        guard index - start <= ToolbarConfiguration.maximumJSONNumberBytes else {
            throw ToolbarConfigurationError.jsonNumberTooLarge(
                maximumBytes: ToolbarConfiguration.maximumJSONNumberBytes
            )
        }
    }

    private mutating func validateDepth(_ depth: Int) throws {
        guard depth <= ToolbarConfiguration.maximumJSONNestingDepth else {
            throw ToolbarConfigurationError.jsonNestingTooDeep(
                maximumDepth: ToolbarConfiguration.maximumJSONNestingDepth
            )
        }
    }

    private mutating func incrementContainerCount(_ count: inout Int) throws {
        guard count < ToolbarConfiguration.maximumJSONContainerElements else {
            throw ToolbarConfigurationError.jsonContainerTooLarge(
                maximumElements: ToolbarConfiguration.maximumJSONContainerElements
            )
        }
        count += 1
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else {
            throw ToolbarConfigurationError.invalidJSON
        }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw ToolbarConfigurationError.invalidJSON }
            index += 1
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
