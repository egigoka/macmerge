import Foundation

/// Bounded, UI-independent state and command policy for comparison-editor View commands.
///
/// Font, zoom, and syntax highlighting remain owned by `EditorDisplayPreferences`. This policy
/// mirrors only its relevant display flags and adds pane locking plus command availability.
/// Use `decode(from:)` for persistence; direct `Decoder` use is rejected to preserve input bounds.
public struct EditorViewPolicy: Codable, Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEncodedBytes = 2 * 1_024
    public static let maximumPaneCount = 3
    public static let maximumMutationCount = 8

    fileprivate static let maximumJSONNestingDepth = 4
    fileprivate static let maximumJSONContainerElements = 16
    fileprivate static let maximumJSONValueCount = 32
    fileprivate static let maximumJSONStringBytes = 256
    fileprivate static let maximumJSONNumberBytes = 16

    private static let boundedDecodeKey = CodingUserInfoKey(
        rawValue: "org.macmerge.EditorViewPolicy.boundedDecode"
    )!
    private static let boundedDecodeToken = UUID()

    public enum Command: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
        case lockPanes
        case viewWhitespace
        case viewEndOfLineMarkers
        case viewLineDifferences
        case viewLineNumbers
        case viewMargins
        case viewTopMargins
        case wrapLines

        public static var whitespace: Command { .viewWhitespace }
        public static var endOfLineMarkers: Command { .viewEndOfLineMarkers }
        public static var lineDifferences: Command { .viewLineDifferences }
        public static var lineNumbers: Command { .viewLineNumbers }
        public static var margins: Command { .viewMargins }
        public static var topMargins: Command { .viewTopMargins }
    }

    /// Runtime editor shape and capabilities. Zero panes represents no active editor.
    public struct Context: Equatable, Hashable, Sendable {
        public let paneCount: Int
        public let supportedCommands: Set<Command>

        public init(
            paneCount: Int,
            supportedCommands: Set<Command> = Set(Command.allCases)
        ) throws {
            guard (0...EditorViewPolicy.maximumPaneCount).contains(paneCount) else {
                throw EditorViewPolicyError.invalidPaneCount(paneCount)
            }
            self.paneCount = paneCount
            self.supportedCommands = supportedCommands
        }

        public var hasActiveEditor: Bool { paneCount > 0 }
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case noActiveEditor
        case unsupportedByEditor(Command)
        case requiresMultiplePanes(actualPaneCount: Int)
    }

    public enum Availability: Equatable, Hashable, Sendable {
        case enabled
        case disabled(DisabledReason)

        public var isEnabled: Bool { self == .enabled }

        public var disabledReason: DisabledReason? {
            guard case .disabled(let reason) = self else { return nil }
            return reason
        }
    }

    public struct CommandState: Equatable, Hashable, Sendable {
        public let command: Command
        public let isChecked: Bool
        public let availability: Availability

        public init(command: Command, isChecked: Bool, availability: Availability) {
            self.command = command
            self.isChecked = isChecked
            self.availability = availability
        }

        public var isEnabled: Bool { availability.isEnabled }
        public var disabledReason: DisabledReason? { availability.disabledReason }
    }

    public enum RequestedState: Equatable, Hashable, Sendable {
        case toggle
        case checked(Bool)
    }

    public struct Change: Equatable, Hashable, Sendable {
        public let command: Command
        public let requestedState: RequestedState

        public init(command: Command, requestedState: RequestedState = .toggle) {
            self.command = command
            self.requestedState = requestedState
        }

        public static func toggle(_ command: Command) -> Change {
            Change(command: command, requestedState: .toggle)
        }

        public static func set(_ command: Command, checked: Bool) -> Change {
            Change(command: command, requestedState: .checked(checked))
        }
    }

    public struct Mutation: Equatable, Hashable, Sendable {
        public let before: EditorViewPolicy
        public let after: EditorViewPolicy
        public let appliedChanges: [Change]
        public let changedCommands: [Command]

        fileprivate init(
            before: EditorViewPolicy,
            after: EditorViewPolicy,
            appliedChanges: [Change],
            changedCommands: [Command]
        ) {
            self.before = before
            self.after = after
            self.appliedChanges = appliedChanges
            self.changedCommands = changedCommands
        }

        public var didChange: Bool { before != after }
    }

    public static let `default` = EditorViewPolicy()

    public let schemaVersion: Int
    public private(set) var locksPanes: Bool
    public private(set) var showsWhitespace: Bool
    public private(set) var showsEndOfLineMarkers: Bool
    public private(set) var showsLineDifferences: Bool
    public private(set) var showsLineNumbers: Bool
    public private(set) var showsMargins: Bool
    public private(set) var showsTopMargins: Bool
    public private(set) var wrapsLines: Bool

    public init(
        locksPanes: Bool = false,
        showsWhitespace: Bool = false,
        showsEndOfLineMarkers: Bool = false,
        showsLineDifferences: Bool = true,
        showsLineNumbers: Bool = false,
        showsMargins: Bool = false,
        showsTopMargins: Bool = false,
        wrapsLines: Bool = false
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.locksPanes = locksPanes
        self.showsWhitespace = showsWhitespace
        self.showsEndOfLineMarkers = showsEndOfLineMarkers
        self.showsLineDifferences = showsLineDifferences
        self.showsLineNumbers = showsLineNumbers
        self.showsMargins = showsMargins
        self.showsTopMargins = showsTopMargins
        self.wrapsLines = wrapsLines
    }

    /// Imports the shared display flags without taking ownership of font, zoom, or syntax state.
    public init(
        locksPanes: Bool = false,
        displayPreferences: EditorDisplayPreferences
    ) {
        self.init(
            locksPanes: locksPanes,
            showsWhitespace: displayPreferences.showsWhitespace,
            showsEndOfLineMarkers: displayPreferences.showsEndOfLineMarkers,
            showsLineDifferences: displayPreferences.showsLineDifferences,
            showsLineNumbers: displayPreferences.showsLineNumbers,
            showsMargins: displayPreferences.showsMargins,
            showsTopMargins: displayPreferences.showsTopMargin,
            wrapsLines: displayPreferences.wrapsLines
        )
    }

    /// Applies only shared display flags. Existing font, zoom, and syntax preferences are preserved.
    public func applying(to displayPreferences: EditorDisplayPreferences) -> EditorDisplayPreferences {
        var result = displayPreferences
        result.showsWhitespace = showsWhitespace
        result.showsEndOfLineMarkers = showsEndOfLineMarkers
        result.showsLineDifferences = showsLineDifferences
        result.showsLineNumbers = showsLineNumbers
        result.showsMargins = showsMargins
        result.showsTopMargin = showsTopMargins
        result.wrapsLines = wrapsLines
        return result
    }

    /// Dependency order is active editor, editor capability, then command-specific pane shape.
    public func availability(of command: Command, in context: Context) -> Availability {
        guard context.hasActiveEditor else { return .disabled(.noActiveEditor) }
        guard context.supportedCommands.contains(command) else {
            return .disabled(.unsupportedByEditor(command))
        }
        if command == .lockPanes, context.paneCount < 2 {
            return .disabled(.requiresMultiplePanes(actualPaneCount: context.paneCount))
        }
        return .enabled
    }

    public func commandState(for command: Command, in context: Context) -> CommandState {
        CommandState(
            command: command,
            isChecked: isChecked(command),
            availability: availability(of: command, in: context)
        )
    }

    /// Returns states in stable `Command.allCases` order.
    public func commandStates(
        in context: Context,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> [CommandState] {
        try Self.performCancellationCheck(cancellationCheck)
        var states: [CommandState] = []
        states.reserveCapacity(Command.allCases.count)
        for command in Command.allCases {
            try Self.performCancellationCheck(cancellationCheck)
            states.append(commandState(for: command, in: context))
        }
        try Self.performCancellationCheck(cancellationCheck)
        return states
    }

    /// Applies one command through the same atomic path used by batches.
    @discardableResult
    public mutating func apply(
        _ command: Command,
        in context: Context,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> Mutation {
        try apply(
            [.toggle(command)],
            in: context,
            cancellationCheck: cancellationCheck
        )
    }

    /// Validates and stages every change before committing the complete candidate snapshot.
    /// Any disabled command, duplicate, limit failure, or cancellation leaves `self` unchanged.
    @discardableResult
    public mutating func apply(
        _ changes: [Change],
        in context: Context,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> Mutation {
        try Self.performCancellationCheck(cancellationCheck)
        guard changes.count <= Self.maximumMutationCount else {
            throw EditorViewPolicyError.tooManyChanges(maximumCount: Self.maximumMutationCount)
        }

        var seen: Set<Command> = []
        var candidate = self
        var changedCommands: [Command] = []
        changedCommands.reserveCapacity(changes.count)

        for change in changes {
            try Self.performCancellationCheck(cancellationCheck)
            guard seen.insert(change.command).inserted else {
                throw EditorViewPolicyError.duplicateCommand(change.command)
            }
            if case .disabled(let reason) = availability(
                of: change.command,
                in: context
            ) {
                throw EditorViewPolicyError.commandDisabled(change.command, reason: reason)
            }

            let oldValue = candidate.isChecked(change.command)
            let newValue: Bool
            switch change.requestedState {
            case .toggle:
                newValue = !oldValue
            case .checked(let checked):
                newValue = checked
            }
            candidate.setChecked(newValue, for: change.command)
            if oldValue != newValue { changedCommands.append(change.command) }
        }

        try candidate.validate()
        try Self.performCancellationCheck(cancellationCheck)
        let mutation = Mutation(
            before: self,
            after: candidate,
            appliedChanges: changes,
            changedCommands: changedCommands
        )
        self = candidate
        return mutation
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw EditorViewPolicyError.unsupportedSchemaVersion(schemaVersion)
        }
    }

    /// Compact deterministic schema-1 JSON.
    public func encodedData(
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> Data {
        try Self.performCancellationCheck(cancellationCheck)
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try Self.performCancellationCheck(cancellationCheck)
        guard data.count <= Self.maximumEncodedBytes else {
            throw EditorViewPolicyError.persistenceDataTooLarge(
                maximumBytes: Self.maximumEncodedBytes
            )
        }
        return data
    }

    /// Strict bounded decoding rejects oversized input, duplicate keys, unknown fields, malformed
    /// JSON, excessive JSON structure, and every schema other than the current one.
    public static func decode(
        from data: Data,
        cancellationCheck: @escaping @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> EditorViewPolicy {
        try performCancellationCheck(cancellationCheck)
        guard data.count <= maximumEncodedBytes else {
            throw EditorViewPolicyError.persistenceDataTooLarge(maximumBytes: maximumEncodedBytes)
        }
        let snapshot = immutableSnapshot(of: data)
        guard snapshot.count <= maximumEncodedBytes else {
            throw EditorViewPolicyError.persistenceDataTooLarge(maximumBytes: maximumEncodedBytes)
        }

        var scanner = EditorViewPolicyJSONScanner(
            data: snapshot,
            cancellationCheck: cancellationCheck
        )
        try scanner.validate()
        try performCancellationCheck(cancellationCheck)

        let decoder = JSONDecoder()
        decoder.userInfo[boundedDecodeKey] = boundedDecodeToken
        do {
            let policy = try decoder.decode(Self.self, from: snapshot)
            try performCancellationCheck(cancellationCheck)
            return policy
        } catch let error as EditorViewPolicyError {
            throw error
        } catch is CancellationError {
            throw EditorViewPolicyError.cancelled
        } catch {
            throw EditorViewPolicyError.malformedPersistence
        }
    }

    /// Explicit fallback for callers that choose reset semantics for corrupt or unsupported data.
    public static func restored(
        from data: Data?,
        cancellationCheck: @escaping @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> EditorViewPolicy {
        try performCancellationCheck(cancellationCheck)
        guard let data else { return .default }
        do {
            return try decode(from: data, cancellationCheck: cancellationCheck)
        } catch EditorViewPolicyError.cancelled {
            throw EditorViewPolicyError.cancelled
        } catch {
            try performCancellationCheck(cancellationCheck)
            return .default
        }
    }

    public static func checkCancellation() throws {
        do {
            try Task<Never, Never>.checkCancellation()
        } catch {
            throw EditorViewPolicyError.cancelled
        }
    }

    public func isChecked(_ command: Command) -> Bool {
        switch command {
        case .lockPanes: locksPanes
        case .viewWhitespace: showsWhitespace
        case .viewEndOfLineMarkers: showsEndOfLineMarkers
        case .viewLineDifferences: showsLineDifferences
        case .viewLineNumbers: showsLineNumbers
        case .viewMargins: showsMargins
        case .viewTopMargins: showsTopMargins
        case .wrapLines: wrapsLines
        }
    }

    private mutating func setChecked(_ checked: Bool, for command: Command) {
        switch command {
        case .lockPanes: locksPanes = checked
        case .viewWhitespace: showsWhitespace = checked
        case .viewEndOfLineMarkers: showsEndOfLineMarkers = checked
        case .viewLineDifferences: showsLineDifferences = checked
        case .viewLineNumbers: showsLineNumbers = checked
        case .viewMargins: showsMargins = checked
        case .viewTopMargins: showsTopMargins = checked
        case .wrapLines: wrapsLines = checked
        }
    }

    private static func performCancellationCheck(
        _ cancellationCheck: @Sendable () throws -> Void
    ) throws {
        do {
            try cancellationCheck()
        } catch {
            throw EditorViewPolicyError.cancelled
        }
    }

    private static func immutableSnapshot(of data: Data) -> Data {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return Data() }
            return Data(bytes: baseAddress, count: bytes.count)
        }
    }

    private static let persistenceFields: Set<String> = [
        "schemaVersion",
        "locksPanes",
        "showsWhitespace",
        "showsEndOfLineMarkers",
        "showsLineDifferences",
        "showsLineNumbers",
        "showsMargins",
        "showsTopMargins",
        "wrapsLines"
    ]

    public init(from decoder: Decoder) throws {
        guard
            decoder.userInfo[Self.boundedDecodeKey] as? UUID
                == Self.boundedDecodeToken
        else {
            throw EditorViewPolicyError.boundedDecodingRequired
        }

        let container = try decoder.container(keyedBy: EditorViewPolicyCodingKey.self)
        if let unknownField = container.allKeys.map(\.stringValue)
            .filter({ !Self.persistenceFields.contains($0) })
            .sorted()
            .first
        {
            throw EditorViewPolicyError.unknownField(unknownField)
        }

        let schemaVersion = try container.decode(
            Int.self,
            forKey: EditorViewPolicyCodingKey("schemaVersion")
        )
        guard schemaVersion == Self.currentSchemaVersion else {
            throw EditorViewPolicyError.unsupportedSchemaVersion(schemaVersion)
        }
        self.init(
            locksPanes: try container.decode(
                Bool.self,
                forKey: EditorViewPolicyCodingKey("locksPanes")
            ),
            showsWhitespace: try container.decode(
                Bool.self,
                forKey: EditorViewPolicyCodingKey("showsWhitespace")
            ),
            showsEndOfLineMarkers: try container.decode(
                Bool.self,
                forKey: EditorViewPolicyCodingKey("showsEndOfLineMarkers")
            ),
            showsLineDifferences: try container.decode(
                Bool.self,
                forKey: EditorViewPolicyCodingKey("showsLineDifferences")
            ),
            showsLineNumbers: try container.decode(
                Bool.self,
                forKey: EditorViewPolicyCodingKey("showsLineNumbers")
            ),
            showsMargins: try container.decode(
                Bool.self,
                forKey: EditorViewPolicyCodingKey("showsMargins")
            ),
            showsTopMargins: try container.decode(
                Bool.self,
                forKey: EditorViewPolicyCodingKey("showsTopMargins")
            ),
            wrapsLines: try container.decode(
                Bool.self,
                forKey: EditorViewPolicyCodingKey("wrapsLines")
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: EditorViewPolicyCodingKey.self)
        try container.encode(
            schemaVersion,
            forKey: EditorViewPolicyCodingKey("schemaVersion")
        )
        try container.encode(locksPanes, forKey: EditorViewPolicyCodingKey("locksPanes"))
        try container.encode(
            showsWhitespace,
            forKey: EditorViewPolicyCodingKey("showsWhitespace")
        )
        try container.encode(
            showsEndOfLineMarkers,
            forKey: EditorViewPolicyCodingKey("showsEndOfLineMarkers")
        )
        try container.encode(
            showsLineDifferences,
            forKey: EditorViewPolicyCodingKey("showsLineDifferences")
        )
        try container.encode(
            showsLineNumbers,
            forKey: EditorViewPolicyCodingKey("showsLineNumbers")
        )
        try container.encode(
            showsMargins,
            forKey: EditorViewPolicyCodingKey("showsMargins")
        )
        try container.encode(
            showsTopMargins,
            forKey: EditorViewPolicyCodingKey("showsTopMargins")
        )
        try container.encode(wrapsLines, forKey: EditorViewPolicyCodingKey("wrapsLines"))
    }
}

public enum EditorViewPolicyError: Error, Equatable, LocalizedError, Sendable {
    case invalidPaneCount(Int)
    case tooManyChanges(maximumCount: Int)
    case duplicateCommand(EditorViewPolicy.Command)
    case commandDisabled(EditorViewPolicy.Command, reason: EditorViewPolicy.DisabledReason)
    case persistenceDataTooLarge(maximumBytes: Int)
    case malformedPersistence
    case invalidJSON
    case jsonNestingTooDeep(maximumDepth: Int)
    case jsonContainerTooLarge(maximumElements: Int)
    case tooManyJSONValues(maximumValues: Int)
    case jsonStringTooLarge(maximumBytes: Int)
    case jsonNumberTooLarge(maximumBytes: Int)
    case duplicateJSONKey(String)
    case unknownField(String)
    case unsupportedSchemaVersion(Int)
    case boundedDecodingRequired
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidPaneCount(let count):
            "Editor pane count must be between zero and \(EditorViewPolicy.maximumPaneCount): \(count)."
        case .tooManyChanges(let maximumCount):
            "An editor View transaction cannot exceed \(maximumCount) changes."
        case .duplicateCommand(let command):
            "Editor View transaction repeats command \(command.rawValue)."
        case .commandDisabled(let command, let reason):
            "Editor View command \(command.rawValue) is disabled: \(String(describing: reason))."
        case .persistenceDataTooLarge(let maximumBytes):
            "Editor View policy exceeds the \(maximumBytes)-byte persistence limit."
        case .malformedPersistence:
            "Editor View policy has malformed persistence values."
        case .invalidJSON:
            "Editor View policy is not valid strict JSON."
        case .jsonNestingTooDeep(let maximumDepth):
            "Editor View policy exceeds the \(maximumDepth)-level JSON nesting limit."
        case .jsonContainerTooLarge(let maximumElements):
            "An Editor View policy JSON container exceeds \(maximumElements) elements."
        case .tooManyJSONValues(let maximumValues):
            "Editor View policy exceeds \(maximumValues) JSON values."
        case .jsonStringTooLarge(let maximumBytes):
            "An Editor View policy JSON string exceeds \(maximumBytes) encoded bytes."
        case .jsonNumberTooLarge(let maximumBytes):
            "An Editor View policy JSON number exceeds \(maximumBytes) bytes."
        case .duplicateJSONKey(let key):
            "Editor View policy repeats JSON key \(key)."
        case .unknownField(let field):
            "Unknown Editor View policy field: \(field)."
        case .unsupportedSchemaVersion(let version):
            "Unsupported Editor View policy schema version: \(version)."
        case .boundedDecodingRequired:
            "Editor View policy must be decoded with EditorViewPolicy.decode(from:)."
        case .cancelled:
            "Editor View policy operation was cancelled."
        }
    }
}

private struct EditorViewPolicyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

private struct EditorViewPolicyJSONScanner {
    private let bytes: [UInt8]
    private let cancellationCheck: @Sendable () throws -> Void
    private var index = 0
    private var valueCount = 0
    private var nextCancellationIndex = 0

    init(
        data: Data,
        cancellationCheck: @escaping @Sendable () throws -> Void
    ) {
        bytes = Array(data)
        self.cancellationCheck = cancellationCheck
    }

    mutating func validate() throws {
        try checkpoint(force: true)
        try skipWhitespace()
        try parseValue(depth: 0)
        try skipWhitespace()
        guard index == bytes.count else { throw EditorViewPolicyError.invalidJSON }
        try checkpoint(force: true)
    }

    private mutating func parseValue(depth: Int) throws {
        try checkpoint()
        guard valueCount < EditorViewPolicy.maximumJSONValueCount else {
            throw EditorViewPolicyError.tooManyJSONValues(
                maximumValues: EditorViewPolicy.maximumJSONValueCount
            )
        }
        valueCount += 1
        guard let byte = currentByte else { throw EditorViewPolicyError.invalidJSON }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString()
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw EditorViewPolicyError.invalidJSON
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        try skipWhitespace()
        if consume(0x7D) { return }

        var elementCount = 0
        var keys: Set<String> = []
        while true {
            try checkpoint()
            try incrementContainerCount(&elementCount)
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw EditorViewPolicyError.duplicateJSONKey(key)
            }
            try skipWhitespace()
            guard consume(0x3A) else { throw EditorViewPolicyError.invalidJSON }
            try skipWhitespace()
            try parseValue(depth: depth)
            try skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw EditorViewPolicyError.invalidJSON }
            try skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        try skipWhitespace()
        if consume(0x5D) { return }

        var elementCount = 0
        while true {
            try checkpoint()
            try incrementContainerCount(&elementCount)
            try parseValue(depth: depth)
            try skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw EditorViewPolicyError.invalidJSON }
            try skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        guard consume(0x22) else { throw EditorViewPolicyError.invalidJSON }
        var escaped = false
        while let byte = currentByte {
            try checkpoint()
            guard index - start < EditorViewPolicy.maximumJSONStringBytes else {
                throw EditorViewPolicyError.jsonStringTooLarge(
                    maximumBytes: EditorViewPolicy.maximumJSONStringBytes
                )
            }
            index += 1
            if escaped {
                escaped = false
                continue
            }
            if byte == 0x5C {
                escaped = true
            } else if byte == 0x22 {
                let encoded = Data(bytes[start..<index])
                do {
                    return try JSONDecoder().decode(String.self, from: encoded)
                } catch {
                    throw EditorViewPolicyError.invalidJSON
                }
            } else if byte < 0x20 {
                throw EditorViewPolicyError.invalidJSON
            }
        }
        throw EditorViewPolicyError.invalidJSON
    }

    private mutating func parseNumber() throws {
        let start = index
        while let byte = currentByte,
            byte == 0x2B || byte == 0x2D || byte == 0x2E
                || (0x30...0x39).contains(byte) || byte == 0x45 || byte == 0x65
        {
            try checkpoint()
            guard index - start < EditorViewPolicy.maximumJSONNumberBytes else {
                throw EditorViewPolicyError.jsonNumberTooLarge(
                    maximumBytes: EditorViewPolicy.maximumJSONNumberBytes
                )
            }
            index += 1
        }
        guard index > start else { throw EditorViewPolicyError.invalidJSON }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard literalBytes.count <= bytes.count - index else {
            throw EditorViewPolicyError.invalidJSON
        }
        for byte in literalBytes {
            try checkpoint()
            guard bytes[index] == byte else { throw EditorViewPolicyError.invalidJSON }
            index += 1
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            try checkpoint()
            index += 1
        }
    }

    private func validateDepth(_ depth: Int) throws {
        guard depth <= EditorViewPolicy.maximumJSONNestingDepth else {
            throw EditorViewPolicyError.jsonNestingTooDeep(
                maximumDepth: EditorViewPolicy.maximumJSONNestingDepth
            )
        }
    }

    private func incrementContainerCount(_ count: inout Int) throws {
        guard count < EditorViewPolicy.maximumJSONContainerElements else {
            throw EditorViewPolicyError.jsonContainerTooLarge(
                maximumElements: EditorViewPolicy.maximumJSONContainerElements
            )
        }
        count += 1
    }

    private mutating func checkpoint(force: Bool = false) throws {
        guard force || index >= nextCancellationIndex else { return }
        do {
            try cancellationCheck()
        } catch {
            throw EditorViewPolicyError.cancelled
        }
        nextCancellationIndex = index + 64
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }
}
