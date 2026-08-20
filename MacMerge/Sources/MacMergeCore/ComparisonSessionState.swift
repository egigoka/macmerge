import Foundation

/// Persistable inputs and layout for one two-sided comparison window.
public struct ComparisonSessionState: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumScratchpadUTF8Bytes = 16 * 1024 * 1024
    public static let maximumFilePathUTF8Bytes = 64 * 1024
    public static let maximumEncodedBytes = maximumScratchpadUTF8Bytes * 2 + 64 * 1024
    public static let maximumPersistedBytes = 64 * 1024 * 1024
    static let maximumJSONNestingDepth = 16
    static let maximumJSONContainerElements = 64
    static let maximumJSONValueCount = 256
    static let maximumJSONKeyUTF8Bytes = 256
    static let maximumJSONStringUTF8Bytes = maximumFilePathUTF8Bytes * 3 + 1024
    static let maximumJSONNumberBytes = 128
    public static let maximumSelectedRow = 2 * 1024 * 1024 - 1
    public static let minimumWindowWidth = 320.0
    public static let minimumWindowHeight = 200.0
    public static let maximumWindowWidth = 16_384.0
    public static let maximumWindowHeight = 16_384.0
    public static let minimumLocationPaneWidth = 72.0
    public static let maximumLocationPaneWidth = 240.0

    public enum Side: String, CaseIterable, Sendable {
        case left
        case right
    }

    public enum SideIdentity: Equatable, Sendable {
        case file(URL)
        case scratchpad(String)

        fileprivate var isFile: Bool {
            if case .file = self { return true }
            return false
        }
    }

    public enum FileEncoding: String, CaseIterable, Codable, Sendable {
        case utf8
        case utf16LittleEndian
        case utf16BigEndian
        case shiftJIS
        case japaneseEUC
        case iso2022JP
        case windows1250
        case windows1251
        case windows1252
        case windows1253
        case windows1254
        case windows1255
    }

    public enum SplitOrientation: String, CaseIterable, Sendable {
        case horizontal
        case vertical
    }

    public struct WindowFrame: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) throws {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            try validate()
        }

        fileprivate func validate() throws {
            guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else {
                throw ComparisonSessionStateError.nonFiniteWindowFrame
            }
            guard (x + width).isFinite, (y + height).isFinite else {
                throw ComparisonSessionStateError.nonFiniteWindowFrame
            }
            guard width > 0, height > 0 else {
                throw ComparisonSessionStateError.nonPositiveWindowSize(
                    width: width,
                    height: height
                )
            }
            guard width >= ComparisonSessionState.minimumWindowWidth,
                width <= ComparisonSessionState.maximumWindowWidth,
                height >= ComparisonSessionState.minimumWindowHeight,
                height <= ComparisonSessionState.maximumWindowHeight
            else {
                throw ComparisonSessionStateError.windowSizeOutOfBounds(
                    width: width,
                    height: height
                )
            }
        }
    }

    public let schemaVersion: Int
    public let left: SideIdentity
    public let right: SideIdentity
    public let leftReadOnly: Bool
    public let rightReadOnly: Bool
    public let leftEncoding: FileEncoding?
    public let rightEncoding: FileEncoding?
    public let selectedRow: Int?
    public let activeSide: Side
    public let windowFrame: WindowFrame
    public let splitOrientation: SplitOrientation
    public let splitFraction: Double
    public let locationPaneVisible: Bool
    public let locationPaneWidth: Double

    public init(
        left: SideIdentity,
        right: SideIdentity,
        leftReadOnly: Bool = false,
        rightReadOnly: Bool = false,
        leftEncoding: FileEncoding? = nil,
        rightEncoding: FileEncoding? = nil,
        selectedRow: Int? = nil,
        activeSide: Side = .left,
        windowFrame: WindowFrame,
        splitOrientation: SplitOrientation = .vertical,
        splitFraction: Double = 0.5,
        locationPaneVisible: Bool = true,
        locationPaneWidth: Double = 92
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.left = left
        self.right = right
        self.leftReadOnly = leftReadOnly
        self.rightReadOnly = rightReadOnly
        self.leftEncoding = leftEncoding
        self.rightEncoding = rightEncoding
        self.selectedRow = selectedRow
        self.activeSide = activeSide
        self.windowFrame = windowFrame
        self.splitOrientation = splitOrientation
        self.splitFraction = splitFraction
        self.locationPaneVisible = locationPaneVisible
        self.locationPaneWidth = locationPaneWidth
        try validate()
    }

    /// Returns compact JSON with recursively sorted object keys.
    public func encodedData() throws -> Data {
        try validate()
        let wireState = WireState(self)
        try Self.preflightEncodedSize(of: wireState)
        let data = try Self.makeJSONEncoder().encode(wireState)
        guard data.count <= Self.maximumEncodedBytes else {
            throw ComparisonSessionStateError.encodedDataTooLarge(
                maximumBytes: Self.maximumEncodedBytes
            )
        }
        return data
    }

    public static func decode(from data: Data) throws -> ComparisonSessionState {
        guard data.count <= maximumPersistedBytes else {
            throw ComparisonSessionStateError.encodedDataTooLarge(
                maximumBytes: maximumPersistedBytes
            )
        }
        if data.count > maximumEncodedBytes {
            do {
                let schemaVersion = try probeSchemaVersion(in: data)
                guard schemaVersion == currentSchemaVersion else {
                    throw ComparisonSessionStateError.unsupportedSchemaVersion(schemaVersion)
                }
            } catch {
                let prefix = Data(data.prefix(maximumEncodedBytes))
                guard (try? probeSchemaVersion(in: prefix)) == currentSchemaVersion else {
                    throw error
                }
            }
            throw ComparisonSessionStateError.encodedDataTooLarge(
                maximumBytes: maximumEncodedBytes
            )
        }
        let schemaVersion = try probeSchemaVersion(in: data)
        guard schemaVersion == currentSchemaVersion else {
            throw ComparisonSessionStateError.unsupportedSchemaVersion(schemaVersion)
        }
        try preflightJSON(data)
        return try JSONDecoder().decode(WireState.self, from: data).decodedState()
    }

    private static func probeSchemaVersion(in data: Data) throws -> Int {
        try data.withUnsafeBytes { rawBuffer in
            var scanner = JSONSchemaVersionScanner(
                bytes: rawBuffer.bindMemory(to: UInt8.self)
            )
            return try scanner.scan()
        }
    }

    private static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func preflightEncodedSize(of wireState: WireState) throws {
        var byteCount = try makeJSONEncoder().encode(wireState.withEmptyIdentityValues()).count
        byteCount += try escapedJSONStringContentByteCount(
            wireState.left.value,
            maximumBytes: maximumEncodedBytes - byteCount
        )
        byteCount += try escapedJSONStringContentByteCount(
            wireState.right.value,
            maximumBytes: maximumEncodedBytes - byteCount
        )
    }

    static func escapedJSONStringContentByteCount(
        _ value: String,
        maximumBytes: Int
    ) throws -> Int {
        var byteCount = 0
        for scalar in value.unicodeScalars {
            let addedCount: Int
            switch scalar.value {
            case 0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x22, 0x5C:
                addedCount = 2
            case 0x00...0x1F:
                addedCount = 6
            case 0x20...0x7F:
                addedCount = 1
            case 0x80...0x7FF:
                addedCount = 2
            case 0x800...0xFFFF:
                addedCount = 3
            default:
                addedCount = 4
            }
            guard maximumBytes >= addedCount,
                byteCount <= maximumBytes - addedCount
            else {
                throw ComparisonSessionStateError.encodedDataTooLarge(
                    maximumBytes: maximumEncodedBytes
                )
            }
            byteCount += addedCount
        }
        return byteCount
    }

    private struct WireState: Codable {
        let schemaVersion: Int
        let left: WireSideIdentity
        let right: WireSideIdentity
        let leftReadOnly: Bool?
        let rightReadOnly: Bool?
        let leftEncoding: FileEncoding?
        let rightEncoding: FileEncoding?
        let selectedRow: Int?
        let activeSide: WireSide
        let windowFrame: WireWindowFrame
        let splitOrientation: WireSplitOrientation
        let splitFraction: Double
        let locationPaneVisible: Bool
        let locationPaneWidth: Double

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case left
            case right
            case leftReadOnly
            case rightReadOnly
            case leftEncoding
            case rightEncoding
            case selectedRow
            case activeSide
            case windowFrame
            case splitOrientation
            case splitFraction
            case locationPaneVisible
            case locationPaneWidth
        }

        init(_ state: ComparisonSessionState) {
            schemaVersion = state.schemaVersion
            left = WireSideIdentity(state.left)
            right = WireSideIdentity(state.right)
            leftReadOnly = state.leftReadOnly ? true : nil
            rightReadOnly = state.rightReadOnly ? true : nil
            leftEncoding = state.leftEncoding
            rightEncoding = state.rightEncoding
            selectedRow = state.selectedRow
            activeSide = WireSide(state.activeSide)
            windowFrame = WireWindowFrame(state.windowFrame)
            splitOrientation = WireSplitOrientation(state.splitOrientation)
            splitFraction = state.splitFraction
            locationPaneVisible = state.locationPaneVisible
            locationPaneWidth = state.locationPaneWidth
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            left = try container.decode(WireSideIdentity.self, forKey: .left)
            right = try container.decode(WireSideIdentity.self, forKey: .right)
            leftReadOnly =
                container.contains(.leftReadOnly)
                ? try container.decode(Bool.self, forKey: .leftReadOnly)
                : nil
            rightReadOnly =
                container.contains(.rightReadOnly)
                ? try container.decode(Bool.self, forKey: .rightReadOnly)
                : nil
            leftEncoding =
                container.contains(.leftEncoding)
                ? try container.decode(FileEncoding.self, forKey: .leftEncoding)
                : nil
            rightEncoding =
                container.contains(.rightEncoding)
                ? try container.decode(FileEncoding.self, forKey: .rightEncoding)
                : nil
            selectedRow = try container.decodeIfPresent(Int.self, forKey: .selectedRow)
            activeSide = try container.decode(WireSide.self, forKey: .activeSide)
            windowFrame = try container.decode(WireWindowFrame.self, forKey: .windowFrame)
            splitOrientation = try container.decode(WireSplitOrientation.self, forKey: .splitOrientation)
            splitFraction = try container.decode(Double.self, forKey: .splitFraction)
            locationPaneVisible = try container.decode(Bool.self, forKey: .locationPaneVisible)
            locationPaneWidth = try container.decode(Double.self, forKey: .locationPaneWidth)
        }

        private init(
            replacing state: WireState,
            left: WireSideIdentity,
            right: WireSideIdentity
        ) {
            schemaVersion = state.schemaVersion
            self.left = left
            self.right = right
            leftReadOnly = state.leftReadOnly
            rightReadOnly = state.rightReadOnly
            leftEncoding = state.leftEncoding
            rightEncoding = state.rightEncoding
            selectedRow = state.selectedRow
            activeSide = state.activeSide
            windowFrame = state.windowFrame
            splitOrientation = state.splitOrientation
            splitFraction = state.splitFraction
            locationPaneVisible = state.locationPaneVisible
            locationPaneWidth = state.locationPaneWidth
        }

        func withEmptyIdentityValues() -> WireState {
            WireState(
                replacing: self,
                left: left.withEmptyValue(),
                right: right.withEmptyValue()
            )
        }

        func decodedState() throws -> ComparisonSessionState {
            guard schemaVersion == ComparisonSessionState.currentSchemaVersion else {
                throw ComparisonSessionStateError.unsupportedSchemaVersion(schemaVersion)
            }
            return try ComparisonSessionState(
                left: left.decodedIdentity(),
                right: right.decodedIdentity(),
                leftReadOnly: leftReadOnly ?? false,
                rightReadOnly: rightReadOnly ?? false,
                leftEncoding: leftEncoding,
                rightEncoding: rightEncoding,
                selectedRow: selectedRow,
                activeSide: activeSide.decodedSide,
                windowFrame: windowFrame.decodedFrame(),
                splitOrientation: splitOrientation.decodedOrientation,
                splitFraction: splitFraction,
                locationPaneVisible: locationPaneVisible,
                locationPaneWidth: locationPaneWidth
            )
        }
    }

    private struct WireSideIdentity: Codable {
        fileprivate let value: String
        private let kind: Kind

        private enum Kind: String, Codable {
            case file
            case scratchpad
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case url
            case text
        }

        init(_ identity: SideIdentity) {
            switch identity {
            case .file(let url):
                kind = .file
                value = url.absoluteString
            case .scratchpad(let text):
                kind = .scratchpad
                value = text
            }
        }

        private init(value: String, kind: Kind) {
            self.value = value
            self.kind = kind
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawKind = try container.decode(String.self, forKey: .kind)
            guard let kind = Kind(rawValue: rawKind) else {
                throw ComparisonSessionStateError.invalidSideIdentity
            }
            self.kind = kind
            switch kind {
            case .file:
                guard container.contains(.url), !container.contains(.text) else {
                    throw ComparisonSessionStateError.invalidSideIdentity
                }
                value = try container.decode(String.self, forKey: .url)
            case .scratchpad:
                guard container.contains(.text), !container.contains(.url) else {
                    throw ComparisonSessionStateError.invalidSideIdentity
                }
                value = try container.decode(String.self, forKey: .text)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind.rawValue, forKey: .kind)
            switch kind {
            case .file:
                try container.encode(value, forKey: .url)
            case .scratchpad:
                try container.encode(value, forKey: .text)
            }
        }

        func withEmptyValue() -> WireSideIdentity {
            WireSideIdentity(value: "", kind: kind)
        }

        func decodedIdentity() throws -> SideIdentity {
            switch kind {
            case .file:
                guard let url = URL(string: value) else {
                    throw ComparisonSessionStateError.invalidSideIdentity
                }
                return .file(url)
            case .scratchpad:
                return .scratchpad(value)
            }
        }
    }

    private enum WireSide: String, Codable {
        case left
        case right

        init(_ side: Side) {
            switch side {
            case .left: self = .left
            case .right: self = .right
            }
        }

        var decodedSide: Side {
            switch self {
            case .left: .left
            case .right: .right
            }
        }
    }

    private enum WireSplitOrientation: String, Codable {
        case horizontal
        case vertical

        init(_ orientation: SplitOrientation) {
            switch orientation {
            case .horizontal: self = .horizontal
            case .vertical: self = .vertical
            }
        }

        var decodedOrientation: SplitOrientation {
            switch self {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }
        }
    }

    private struct WireWindowFrame: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ frame: WindowFrame) {
            x = frame.x
            y = frame.y
            width = frame.width
            height = frame.height
        }

        func decodedFrame() throws -> WindowFrame {
            try WindowFrame(x: x, y: y, width: width, height: height)
        }
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ComparisonSessionStateError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.validate(left, side: .left)
        try Self.validate(right, side: .right)
        guard leftEncoding == nil || left.isFile else {
            throw ComparisonSessionStateError.invalidFileEncodingSide(.left)
        }
        guard rightEncoding == nil || right.isFile else {
            throw ComparisonSessionStateError.invalidFileEncodingSide(.right)
        }
        if let selectedRow,
            selectedRow < 0 || selectedRow > Self.maximumSelectedRow
        {
            throw ComparisonSessionStateError.invalidSelectedRow(selectedRow)
        }
        if case .file(let leftURL) = left,
            case .file(let rightURL) = right,
            Self.filesIdentifySameResource(leftURL, rightURL)
        {
            throw ComparisonSessionStateError.duplicateFileURL(
                Self.canonicalFilePath(leftURL)
            )
        }
        try windowFrame.validate()
        guard splitFraction.isFinite, splitFraction > 0, splitFraction < 1 else {
            throw ComparisonSessionStateError.invalidSplitFraction(splitFraction)
        }
        guard locationPaneWidth.isFinite,
            locationPaneWidth >= Self.minimumLocationPaneWidth,
            locationPaneWidth <= Self.maximumLocationPaneWidth
        else {
            throw ComparisonSessionStateError.invalidLocationPaneWidth(locationPaneWidth)
        }
    }

    private static func validate(_ identity: SideIdentity, side: Side) throws {
        switch identity {
        case .file(let url):
            guard isValidFileURL(url) else {
                throw ComparisonSessionStateError.invalidFileURL(
                    side: side,
                    value: url.absoluteString
                )
            }
        case .scratchpad(let text):
            guard text.utf8.count <= maximumScratchpadUTF8Bytes else {
                throw ComparisonSessionStateError.scratchpadTooLarge(
                    side: side,
                    maximumBytes: maximumScratchpadUTF8Bytes
                )
            }
        }
    }

    private static func isValidFileURL(_ url: URL) -> Bool {
        let decodedPath = url.path(percentEncoded: false)
        guard url.isFileURL,
            url.baseURL == nil,
            url.query == nil,
            url.fragment == nil,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.caseInsensitiveCompare("file") == .orderedSame,
            components.user == nil,
            components.password == nil,
            components.port == nil,
            decodedPath.hasPrefix("/"),
            decodedPath.utf8.count <= maximumFilePathUTF8Bytes,
            !decodedPath.utf8.contains(0)
        else {
            return false
        }

        guard let host = components.host else { return true }
        return host.isEmpty || host.caseInsensitiveCompare("localhost") == .orderedSame
    }

    private static func canonicalFilePath(_ url: URL) -> String {
        canonicalFileURL(url)
            .path(percentEncoded: false)
            .precomposedStringWithCanonicalMapping
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    private static func filesIdentifySameResource(_ lhs: URL, _ rhs: URL) -> Bool {
        let canonicalLHS = canonicalFileURL(lhs)
        let canonicalRHS = canonicalFileURL(rhs)
        return fileIdentitiesMatch(
            lhsIdentifier: fileResourceIdentifier(for: canonicalLHS),
            rhsIdentifier: fileResourceIdentifier(for: canonicalRHS),
            canonicalPathsMatch: canonicalFilePath(canonicalLHS)
                == canonicalFilePath(canonicalRHS)
        )
    }

    static func fileIdentitiesMatch(
        lhsIdentifier: NSObject?,
        rhsIdentifier: NSObject?,
        canonicalPathsMatch: Bool
    ) -> Bool {
        if canonicalPathsMatch { return true }
        if let lhsIdentifier, let rhsIdentifier {
            return lhsIdentifier.isEqual(rhsIdentifier)
        }
        return false
    }

    private static func fileResourceIdentifier(for url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
            .fileResourceIdentifier) as? NSObject
    }

    private static func preflightJSON(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            var scanner = JSONPreflightScanner(
                bytes: rawBuffer.bindMemory(to: UInt8.self)
            )
            try scanner.validate()
        }
    }
}

public enum ComparisonSessionStateError: Error, Equatable, LocalizedError, Sendable {
    case encodedDataTooLarge(maximumBytes: Int)
    case jsonNestingTooDeep(maximumDepth: Int)
    case jsonContainerTooLarge(maximumElements: Int)
    case tooManyJSONValues(maximumValues: Int)
    case jsonStringTooLarge(maximumBytes: Int)
    case jsonNumberTooLarge(maximumBytes: Int)
    case schemaProbeLimitExceeded
    case unsupportedSchemaVersion(Int)
    case invalidSideIdentity
    case invalidFileEncodingSide(ComparisonSessionState.Side)
    case invalidFileURL(side: ComparisonSessionState.Side, value: String)
    case duplicateFileURL(String)
    case scratchpadTooLarge(side: ComparisonSessionState.Side, maximumBytes: Int)
    case invalidSelectedRow(Int)
    case nonFiniteWindowFrame
    case nonPositiveWindowSize(width: Double, height: Double)
    case windowSizeOutOfBounds(width: Double, height: Double)
    case invalidSplitFraction(Double)
    case invalidLocationPaneWidth(Double)

    public static func == (
        lhs: ComparisonSessionStateError,
        rhs: ComparisonSessionStateError
    ) -> Bool {
        switch (lhs, rhs) {
        case (.encodedDataTooLarge(let lhsMaximum), .encodedDataTooLarge(let rhsMaximum)),
            (.jsonNestingTooDeep(let lhsMaximum), .jsonNestingTooDeep(let rhsMaximum)),
            (.jsonContainerTooLarge(let lhsMaximum), .jsonContainerTooLarge(let rhsMaximum)),
            (.tooManyJSONValues(let lhsMaximum), .tooManyJSONValues(let rhsMaximum)),
            (.jsonStringTooLarge(let lhsMaximum), .jsonStringTooLarge(let rhsMaximum)),
            (.jsonNumberTooLarge(let lhsMaximum), .jsonNumberTooLarge(let rhsMaximum)),
            (.unsupportedSchemaVersion(let lhsMaximum), .unsupportedSchemaVersion(let rhsMaximum)):
            lhsMaximum == rhsMaximum
        case (.invalidSideIdentity, .invalidSideIdentity),
            (.schemaProbeLimitExceeded, .schemaProbeLimitExceeded),
            (.nonFiniteWindowFrame, .nonFiniteWindowFrame):
            true
        case (.invalidFileEncodingSide(let lhsSide), .invalidFileEncodingSide(let rhsSide)):
            lhsSide == rhsSide
        case (.invalidFileURL(let lhsSide, let lhsValue), .invalidFileURL(let rhsSide, let rhsValue)):
            lhsSide.rawValue == rhsSide.rawValue && lhsValue == rhsValue
        case (.duplicateFileURL(let lhsValue), .duplicateFileURL(let rhsValue)):
            lhsValue == rhsValue
        case (.scratchpadTooLarge(let lhsSide, let lhsMaximum), .scratchpadTooLarge(let rhsSide, let rhsMaximum)):
            lhsSide.rawValue == rhsSide.rawValue && lhsMaximum == rhsMaximum
        case (.invalidSelectedRow(let lhsRow), .invalidSelectedRow(let rhsRow)):
            lhsRow == rhsRow
        case (.nonPositiveWindowSize(let lhsWidth, let lhsHeight), .nonPositiveWindowSize(let rhsWidth, let rhsHeight)),
            (.windowSizeOutOfBounds(let lhsWidth, let lhsHeight), .windowSizeOutOfBounds(let rhsWidth, let rhsHeight)):
            Self.equal(lhsWidth, rhsWidth) && Self.equal(lhsHeight, rhsHeight)
        case (.invalidSplitFraction(let lhsValue), .invalidSplitFraction(let rhsValue)),
            (.invalidLocationPaneWidth(let lhsValue), .invalidLocationPaneWidth(let rhsValue)):
            Self.equal(lhsValue, rhsValue)
        default:
            false
        }
    }

    private static func equal(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs == rhs || (lhs.isNaN && rhs.isNaN)
    }

    public var errorDescription: String? {
        switch self {
        case .encodedDataTooLarge(let maximumBytes):
            "Comparison session data exceeds the \(maximumBytes)-byte limit."
        case .jsonNestingTooDeep(let maximumDepth):
            "Comparison session JSON exceeds the \(maximumDepth)-level nesting limit."
        case .jsonContainerTooLarge(let maximumElements):
            "A comparison session JSON container exceeds the \(maximumElements)-element limit."
        case .tooManyJSONValues(let maximumValues):
            "Comparison session JSON exceeds the \(maximumValues)-value limit."
        case .jsonStringTooLarge(let maximumBytes):
            "A comparison session JSON string exceeds the \(maximumBytes)-byte limit."
        case .jsonNumberTooLarge(let maximumBytes):
            "A comparison session JSON number exceeds the \(maximumBytes)-byte limit."
        case .schemaProbeLimitExceeded:
            "Comparison session schema could not be identified within safe parsing limits."
        case .unsupportedSchemaVersion(let version):
            "Unsupported comparison session schema version: \(version)."
        case .invalidSideIdentity:
            "A comparison session side must identify exactly one file or scratchpad."
        case .invalidFileEncodingSide(let side):
            "A saved file encoding is only valid for the \(side.rawValue) file side."
        case .invalidFileURL(let side, let value):
            "Invalid \(side.rawValue) comparison session file URL: \(value)."
        case .duplicateFileURL(let value):
            "Both comparison session panes identify the same file: \(value)."
        case .scratchpadTooLarge(let side, let maximumBytes):
            "The \(side.rawValue) scratchpad exceeds the \(maximumBytes)-byte limit."
        case .invalidSelectedRow(let row):
            "Selected comparison row restoration hint must be between zero and \(ComparisonSessionState.maximumSelectedRow): \(row)."
        case .nonFiniteWindowFrame:
            "Comparison window frame values must be finite."
        case .nonPositiveWindowSize(let width, let height):
            "Comparison window dimensions must be positive: \(width) x \(height)."
        case .windowSizeOutOfBounds(let width, let height):
            "Comparison window dimensions must be between \(ComparisonSessionState.minimumWindowWidth) x \(ComparisonSessionState.minimumWindowHeight) and \(ComparisonSessionState.maximumWindowWidth) x \(ComparisonSessionState.maximumWindowHeight): \(width) x \(height)."
        case .invalidSplitFraction(let fraction):
            "Comparison split fraction must be finite and strictly between zero and one: \(fraction)."
        case .invalidLocationPaneWidth(let width):
            "Location pane width must be finite and between \(ComparisonSessionState.minimumLocationPaneWidth) and \(ComparisonSessionState.maximumLocationPaneWidth): \(width)."
        }
    }
}

private struct JSONSchemaVersionScanner {
    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func scan() throws -> Int {
        skipWhitespace()
        guard consume(0x7B) else { throw malformedJSON() }
        skipWhitespace()
        guard !consume(0x7D) else { throw malformedJSON() }
        var schemaVersion: Int?
        while true {
            guard currentByte == 0x22 else { throw malformedJSON() }
            let isSchemaVersion = try parseString(matching: "schemaVersion")
            skipWhitespace()
            guard consume(0x3A) else { throw malformedJSON() }
            skipWhitespace()
            if isSchemaVersion {
                guard schemaVersion == nil else { throw malformedJSON() }
                schemaVersion = try parseInteger()
            } else {
                try skipValue(depth: 1)
            }
            skipWhitespace()
            if consume(0x7D) { break }
            guard consume(0x2C) else { throw malformedJSON() }
            skipWhitespace()
        }
        skipWhitespace()
        guard index == bytes.count, let schemaVersion else { throw malformedJSON() }
        return schemaVersion
    }

    private mutating func skipValue(depth: Int) throws {
        guard depth <= ComparisonSessionState.maximumJSONNestingDepth * 4 else {
            throw ComparisonSessionStateError.schemaProbeLimitExceeded
        }
        guard let byte = currentByte else { throw malformedJSON() }
        switch byte {
        case 0x7B:
            index += 1
            skipWhitespace()
            if consume(0x7D) { return }
            while true {
                guard currentByte == 0x22 else { throw malformedJSON() }
                _ = try parseString()
                skipWhitespace()
                guard consume(0x3A) else { throw malformedJSON() }
                skipWhitespace()
                try skipValue(depth: depth + 1)
                skipWhitespace()
                if consume(0x7D) { return }
                guard consume(0x2C) else { throw malformedJSON() }
                skipWhitespace()
            }
        case 0x5B:
            index += 1
            skipWhitespace()
            if consume(0x5D) { return }
            while true {
                try skipValue(depth: depth + 1)
                skipWhitespace()
                if consume(0x5D) { return }
                guard consume(0x2C) else { throw malformedJSON() }
                skipWhitespace()
            }
        case 0x22:
            _ = try parseString()
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try skipNumber()
        default:
            throw malformedJSON()
        }
    }

    private mutating func parseString(
        matching expected: StaticString? = nil
    ) throws -> Bool {
        guard consume(0x22) else { throw malformedJSON() }
        let expectedBytes = expected.map { $0.withUTF8Buffer { Array($0) } } ?? []
        var expectedIndex = 0
        var matches = expected != nil
        while let byte = currentByte {
            switch byte {
            case 0x22:
                index += 1
                return matches && expectedIndex == expectedBytes.count
            case 0x00...0x1F:
                throw malformedJSON()
            case 0x5C:
                index += 1
                let scalar = try parseEscapedScalar()
                if matches {
                    guard scalar <= 0x7F,
                        expectedIndex < expectedBytes.count,
                        expectedBytes[expectedIndex] == UInt8(scalar)
                    else {
                        matches = false
                        continue
                    }
                    expectedIndex += 1
                }
            default:
                let scalarLength = try consumeRawUTF8Scalar()
                if matches {
                    guard scalarLength == 1,
                        expectedIndex < expectedBytes.count,
                        expectedBytes[expectedIndex] == byte
                    else {
                        matches = false
                        continue
                    }
                    expectedIndex += 1
                }
            }
        }
        throw malformedJSON()
    }

    private mutating func parseEscapedScalar() throws -> UInt32 {
        guard let escaped = currentByte else { throw malformedJSON() }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            return UInt32(escaped)
        case 0x62:
            return 0x08
        case 0x66:
            return 0x0C
        case 0x6E:
            return 0x0A
        case 0x72:
            return 0x0D
        case 0x74:
            return 0x09
        case 0x75:
            return try parseUnicodeScalar()
        default:
            throw malformedJSON()
        }
    }

    private mutating func consumeRawUTF8Scalar() throws -> Int {
        guard let first = currentByte else { throw malformedJSON() }
        let length: Int
        let secondRange: ClosedRange<UInt8>
        switch first {
        case 0x00...0x7F:
            index += 1
            return 1
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
            throw malformedJSON()
        }
        guard index <= bytes.count - length,
            secondRange.contains(bytes[index + 1])
        else { throw malformedJSON() }
        for offset in 2..<length where !(0x80...0xBF).contains(bytes[index + offset]) {
            throw malformedJSON()
        }
        index += length
        return length
    }

    private mutating func parseUnicodeScalar() throws -> UInt32 {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            guard consume(0x5C), consume(0x75) else { throw malformedJSON() }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else { throw malformedJSON() }
            return 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
        }
        guard !(0xDC00...0xDFFF).contains(first) else { throw malformedJSON() }
        return UInt32(first)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw malformedJSON()
            }
            value = value * 16 + UInt16(digit)
            index += 1
        }
        return value
    }

    private mutating func parseInteger() throws -> Int {
        let start = index
        if consume(0x2D) {}
        guard let first = currentByte else { throw malformedJSON() }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw malformedJSON()
            }
        } else {
            guard (0x31...0x39).contains(first) else { throw malformedJSON() }
            while currentByte.map({ (0x30...0x39).contains($0) }) == true {
                guard index - start < ComparisonSessionState.maximumJSONNumberBytes else {
                    throw ComparisonSessionStateError.jsonNumberTooLarge(
                        maximumBytes: ComparisonSessionState.maximumJSONNumberBytes
                    )
                }
                index += 1
            }
        }
        guard index - start <= ComparisonSessionState.maximumJSONNumberBytes,
            let value = Int(String(decoding: bytes[start..<index], as: UTF8.self))
        else {
            throw malformedJSON()
        }
        return value
    }

    private mutating func skipNumber() throws {
        _ = consume(0x2D)
        guard let first = currentByte else { throw malformedJSON() }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw malformedJSON()
            }
        } else {
            guard (0x31...0x39).contains(first) else { throw malformedJSON() }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformedJSON()
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x65) || consume(0x45) {
            _ = consume(0x2B) || consume(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformedJSON()
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else { throw malformedJSON() }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw malformedJSON() }
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

    private func malformedJSON() -> DecodingError {
        .dataCorrupted(
            .init(
                codingPath: [],
                debugDescription: "Comparison session data is not valid JSON."
            )
        )
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

private struct JSONPreflightScanner {
    private enum ValueContext {
        case root
        case side(ComparisonSessionState.Side)
        case scratchpad(ComparisonSessionState.Side)
        case other

        func child(for key: String) -> ValueContext {
            switch (self, key) {
            case (.root, "left"):
                .side(.left)
            case (.root, "right"):
                .side(.right)
            case (.side(let side), "text"):
                .scratchpad(side)
            default:
                .other
            }
        }
    }

    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0
    private var valueCount = 0
    private var totalStringByteCount = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue(depth: 0, context: .root)
        skipWhitespace()
        guard index == bytes.count else { throw malformedJSON() }
    }

    private mutating func parseValue(depth: Int, context: ValueContext) throws {
        guard valueCount < ComparisonSessionState.maximumJSONValueCount else {
            throw ComparisonSessionStateError.tooManyJSONValues(
                maximumValues: ComparisonSessionState.maximumJSONValueCount
            )
        }
        valueCount += 1
        guard let byte = currentByte else { throw malformedJSON() }

        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1, context: context)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString(
                maximumBytes: stringLimit(for: context),
                context: context,
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
            throw malformedJSON()
        }
    }

    private mutating func parseObject(depth: Int, context: ValueContext) throws {
        try validateDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }

        var elementCount = 0
        var keys: Set<String> = []
        while true {
            try incrementContainerCount(&elementCount)
            guard currentByte == 0x22 else { throw malformedJSON() }
            let key = try parseString(
                maximumBytes: ComparisonSessionState.maximumJSONKeyUTF8Bytes,
                context: .other,
                capture: true
            )
            guard keys.insert(key).inserted else { throw malformedJSON() }
            skipWhitespace()
            guard consume(0x3A) else { throw malformedJSON() }
            skipWhitespace()
            try parseValue(depth: depth, context: context.child(for: key))
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw malformedJSON() }
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
            try parseValue(depth: depth, context: .other)
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw malformedJSON() }
            skipWhitespace()
        }
    }

    private mutating func parseString(
        maximumBytes: Int,
        context: ValueContext,
        capture: Bool
    ) throws -> String {
        guard consume(0x22) else { throw malformedJSON() }
        var decodedBytes: [UInt8] = []
        if capture {
            decodedBytes.reserveCapacity(min(maximumBytes, 32))
        }
        var byteCount = 0

        while let byte = currentByte {
            index += 1
            switch byte {
            case 0x22:
                return capture ? try decodedString(decodedBytes) : ""
            case 0x00...0x1F:
                throw malformedJSON()
            case 0x5C:
                try parseEscape(
                    byteCount: &byteCount,
                    decodedBytes: &decodedBytes,
                    maximumBytes: maximumBytes,
                    context: context,
                    capture: capture
                )
            default:
                try accountStringBytes(
                    1,
                    byteCount: &byteCount,
                    maximumBytes: maximumBytes,
                    context: context
                )
                if capture { decodedBytes.append(byte) }
            }
        }
        throw malformedJSON()
    }

    private mutating func parseEscape(
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        context: ValueContext,
        capture: Bool
    ) throws {
        guard let escaped = currentByte else { throw malformedJSON() }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            try appendEscapedByte(
                escaped,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                context: context,
                capture: capture
            )
        case 0x62:
            try appendEscapedByte(0x08, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, context: context, capture: capture)
        case 0x66:
            try appendEscapedByte(0x0C, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, context: context, capture: capture)
        case 0x6E:
            try appendEscapedByte(0x0A, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, context: context, capture: capture)
        case 0x72:
            try appendEscapedByte(0x0D, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, context: context, capture: capture)
        case 0x74:
            try appendEscapedByte(0x09, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, context: context, capture: capture)
        case 0x75:
            let scalar = try parseUnicodeScalar()
            try appendEscapedScalar(
                scalar,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                context: context,
                capture: capture
            )
        default:
            throw malformedJSON()
        }
    }

    private mutating func parseUnicodeScalar() throws -> UInt32 {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            guard consume(0x5C), consume(0x75) else { throw malformedJSON() }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else { throw malformedJSON() }
            return 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
        }
        guard !(0xDC00...0xDFFF).contains(first) else { throw malformedJSON() }
        return UInt32(first)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw malformedJSON()
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
        context: ValueContext,
        capture: Bool
    ) throws {
        try accountStringBytes(
            1,
            byteCount: &byteCount,
            maximumBytes: maximumBytes,
            context: context
        )
        if capture { decodedBytes.append(byte) }
    }

    private mutating func appendEscapedScalar(
        _ scalar: UInt32,
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        context: ValueContext,
        capture: Bool
    ) throws {
        let addedCount = Self.utf8ByteCount(for: scalar)
        try accountStringBytes(
            addedCount,
            byteCount: &byteCount,
            maximumBytes: maximumBytes,
            context: context
        )
        guard capture else { return }
        switch addedCount {
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
        maximumBytes: Int,
        context: ValueContext
    ) throws {
        guard byteCount <= maximumBytes - addedCount else {
            if case .scratchpad(let side) = context {
                throw ComparisonSessionStateError.scratchpadTooLarge(
                    side: side,
                    maximumBytes: ComparisonSessionState.maximumScratchpadUTF8Bytes
                )
            }
            throw ComparisonSessionStateError.jsonStringTooLarge(
                maximumBytes: maximumBytes
            )
        }
        guard totalStringByteCount <= ComparisonSessionState.maximumEncodedBytes - addedCount else {
            throw ComparisonSessionStateError.jsonStringTooLarge(
                maximumBytes: ComparisonSessionState.maximumEncodedBytes
            )
        }
        byteCount += addedCount
        totalStringByteCount += addedCount
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else { throw malformedJSON() }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw malformedJSON() }
            index += 1
        }
    }

    private mutating func parseNumber() throws {
        let start = index
        while let byte = currentByte,
            byte == 0x2B || byte == 0x2D || byte == 0x2E || (0x30...0x39).contains(byte) || byte == 0x45 || byte == 0x65
        {
            guard index - start < ComparisonSessionState.maximumJSONNumberBytes else {
                throw ComparisonSessionStateError.jsonNumberTooLarge(
                    maximumBytes: ComparisonSessionState.maximumJSONNumberBytes
                )
            }
            index += 1
        }
    }

    private mutating func validateDepth(_ depth: Int) throws {
        guard depth <= ComparisonSessionState.maximumJSONNestingDepth else {
            throw ComparisonSessionStateError.jsonNestingTooDeep(
                maximumDepth: ComparisonSessionState.maximumJSONNestingDepth
            )
        }
    }

    private mutating func incrementContainerCount(_ count: inout Int) throws {
        guard count < ComparisonSessionState.maximumJSONContainerElements else {
            throw ComparisonSessionStateError.jsonContainerTooLarge(
                maximumElements: ComparisonSessionState.maximumJSONContainerElements
            )
        }
        count += 1
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

    private func stringLimit(for context: ValueContext) -> Int {
        if case .scratchpad = context {
            return ComparisonSessionState.maximumScratchpadUTF8Bytes
        }
        return ComparisonSessionState.maximumJSONStringUTF8Bytes
    }

    private func decodedString(_ bytes: [UInt8]) throws -> String {
        guard let value = String(bytes: bytes, encoding: .utf8) else {
            throw malformedJSON()
        }
        return value
    }

    private func malformedJSON() -> DecodingError {
        .dataCorrupted(
            .init(
                codingPath: [],
                debugDescription: "Comparison session data is not valid JSON."
            ))
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            byte - 0x30
        case 0x41...0x46:
            byte - 0x41 + 10
        case 0x61...0x66:
            byte - 0x61 + 10
        default:
            nil
        }
    }

    private static func utf8ByteCount(for scalar: UInt32) -> Int {
        switch scalar {
        case 0...0x7F:
            1
        case 0x80...0x7FF:
            2
        case 0x800...0xFFFF:
            3
        default:
            4
        }
    }
}
