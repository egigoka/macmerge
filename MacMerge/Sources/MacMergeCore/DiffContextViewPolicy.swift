import Foundation

/// Bounded planner binding the View menu's diff-context commands to `DiffContext`.
///
/// Commands cover All plus 0/1/3/5/7/9 context lines, a toggle between All and the last
/// limited mode, and an invert limited to non-All modes. This file owns enable/check
/// derivation, strict versioned persistence, selection remapping, stale validation, row
/// bounds, and cancellation. Menu rendering, editor projection application, and toolbar
/// adoption remain missing: no view is claimed here.
public struct DiffContextViewPolicy: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEncodedBytes = 512
    public static let maximumMutationCount = 9

    fileprivate static let maximumJSONDepth = 2
    fileprivate static let maximumJSONObjectElements = 8
    fileprivate static let maximumJSONStringBytes = 128
    fileprivate static let maximumJSONNumberBytes = 16

    private static let boundedDecodeKey = CodingUserInfoKey(
        rawValue: "org.macmerge.DiffContextViewPolicy.boundedDecode"
    )!
    private static let boundedDecodeToken = UUID()

    public enum Command: String, CaseIterable, Equatable, Hashable, Sendable {
        case showAll
        case showZero
        case showOne
        case showThree
        case showFive
        case showSeven
        case showNine
        case toggle
        case invert

        public var isLevelCommand: Bool {
            switch self {
            case .showAll, .showZero, .showOne, .showThree, .showFive, .showSeven, .showNine:
                true
            case .toggle, .invert:
                false
            }
        }

        /// Exact context line count selected by a level command. Non-level commands
        /// return nil because they transform rather than select a mode.
        public var lineCount: Int? {
            switch self {
            case .showAll:
                nil
            case .showZero:
                0
            case .showOne:
                1
            case .showThree:
                3
            case .showFive:
                5
            case .showSeven:
                7
            case .showNine:
                9
            case .toggle, .invert:
                nil
            }
        }

        public var mode: DiffContextMode? {
            guard isLevelCommand else { return nil }
            return DiffContextMode(lineCount: lineCount)
        }
    }

    /// Runtime comparison presence. Menu enablement needs only existence, never content.
    public struct Context: Equatable, Hashable, Sendable {
        public let hasComparison: Bool

        public init(hasComparison: Bool) {
            self.hasComparison = hasComparison
        }
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case noComparison
        case requiresLimitedContext
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

    public struct Mutation: Equatable, Sendable {
        public let before: DiffContextViewPolicy
        public let after: DiffContextViewPolicy
        public let appliedCommands: [Command]
        public let changedCommands: [Command]

        fileprivate init(
            before: DiffContextViewPolicy,
            after: DiffContextViewPolicy,
            appliedCommands: [Command],
            changedCommands: [Command]
        ) {
            self.before = before
            self.after = after
            self.appliedCommands = appliedCommands
            self.changedCommands = changedCommands
        }

        public var didChange: Bool { before != after }
    }

    public static let `default` = DiffContextViewPolicy()

    public let schemaVersion: Int
    public private(set) var context: DiffContext

    public var mode: DiffContextMode { context.mode }
    public var lineCount: Int? { context.lineCount }
    public var isAll: Bool { context.isAll }
    public var isInverted: Bool { context.isInverted }
    public var lastLimitedLineCount: Int { context.lastLimitedLineCount }

    public init() {
        schemaVersion = Self.currentSchemaVersion
        context = DiffContext()
    }

    public init(context: DiffContext) throws {
        try Self.validate(context: context)
        schemaVersion = Self.currentSchemaVersion
        self.context = context
    }

    public mutating func reset() {
        self = Self.default
    }

    /// Level commands check the active mode. Toggle is a momentary action and never
    /// checks; invert checks the inversion flag gated on limited mode so All never
    /// shows checked while disabled (projection returns identity for All and ignores
    /// the stale flag; gated display, flag retained).
    public func isChecked(_ command: Command) -> Bool {
        switch command {
        case .showAll:
            context.isAll
        case .showZero, .showOne, .showThree, .showFive, .showSeven, .showNine:
            context.mode == command.mode
        case .toggle:
            false
        case .invert:
            !context.isAll && context.isInverted
        }
    }

    /// Invert requires a limited mode; every command requires a live comparison.
    /// Availability reads the candidate policy so batched changes validate in order.
    public func availability(of command: Command, in context: Context) -> Availability {
        guard context.hasComparison else { return .disabled(.noComparison) }
        if command == .invert, isAll {
            return .disabled(.requiresLimitedContext)
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
            [command],
            in: context,
            cancellationCheck: cancellationCheck
        )
    }

    /// Validates and stages every command before committing the complete candidate.
    /// Any disabled command, duplicate, limit failure, or cancellation leaves
    /// `self` unchanged.
    @discardableResult
    public mutating func apply(
        _ commands: [Command],
        in context: Context,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> Mutation {
        try Self.performCancellationCheck(cancellationCheck)
        guard commands.count <= Self.maximumMutationCount else {
            throw DiffContextViewPolicyError.tooManyChanges(
                maximumCount: Self.maximumMutationCount
            )
        }

        var seen: Set<Command> = []
        var candidate = self
        var changedCommands: [Command] = []
        changedCommands.reserveCapacity(commands.count)

        for command in commands {
            try Self.performCancellationCheck(cancellationCheck)
            guard seen.insert(command).inserted else {
                throw DiffContextViewPolicyError.duplicateCommand(command)
            }
            if case .disabled(let reason) = candidate.availability(
                of: command,
                in: context
            ) {
                throw DiffContextViewPolicyError.commandDisabled(command, reason: reason)
            }

            let previous = candidate.context
            switch command {
            case .showAll, .showZero, .showOne, .showThree, .showFive, .showSeven,
                .showNine:
                candidate.context.setMode(command.mode!)
            case .toggle:
                candidate.context.toggle()
            case .invert:
                candidate.context.invert()
            }
            if candidate.context != previous { changedCommands.append(command) }
        }

        try candidate.validate()
        try Self.performCancellationCheck(cancellationCheck)
        let mutation = Mutation(
            before: self,
            after: candidate,
            appliedCommands: commands,
            changedCommands: changedCommands
        )
        self = candidate
        return mutation
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DiffContextViewPolicyError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.validate(context: context)
    }

    private static func validate(context: DiffContext) throws {
        if let lineCount = context.lineCount,
            !DiffContextMode.supportedLineCounts.contains(lineCount)
        {
            throw DiffContextViewPolicyError.unsupportedLineCount(lineCount)
        }
        guard DiffContextMode.supportedLineCounts.contains(context.lastLimitedLineCount) else {
            throw DiffContextViewPolicyError.unsupportedLineCount(
                context.lastLimitedLineCount
            )
        }
    }

    /// Compact deterministic schema-1 JSON.
    public func encodedData(
        limits: DiffContextViewLimits = .default,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> Data {
        try Self.performCancellationCheck(cancellationCheck)
        try limits.validate()
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try Self.performCancellationCheck(cancellationCheck)
        let maximumBytes = Swift.min(limits.maximumEncodedBytes, Self.maximumEncodedBytes)
        guard data.count <= maximumBytes else {
            throw DiffContextViewPolicyError.persistenceDataTooLarge(
                maximumBytes: maximumBytes
            )
        }
        return data
    }

    /// Strict bounded decoding rejects oversized input, duplicate keys, unknown fields,
    /// malformed JSON, nested JSON, unsupported line counts, and every schema other
    /// than the current one.
    public static func decode(
        from data: Data,
        limits: DiffContextViewLimits = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> DiffContextViewPolicy {
        try performCancellationCheck(cancellationCheck)
        try limits.validate()
        let maximumBytes = Swift.min(limits.maximumEncodedBytes, maximumEncodedBytes)
        guard data.count <= maximumBytes else {
            throw DiffContextViewPolicyError.persistenceDataTooLarge(
                maximumBytes: maximumBytes
            )
        }
        let snapshot = immutableSnapshot(of: data)
        guard snapshot.count <= maximumBytes else {
            throw DiffContextViewPolicyError.persistenceDataTooLarge(
                maximumBytes: maximumBytes
            )
        }

        var scanner = DiffContextViewPolicyJSONScanner(
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
        } catch let error as DiffContextViewPolicyError {
            throw error
        } catch is CancellationError {
            throw DiffContextViewPolicyError.cancelled
        } catch {
            throw DiffContextViewPolicyError.malformedPersistence
        }
    }

    /// Explicit fallback for callers that choose reset semantics for corrupt data.
    public static func restored(
        from data: Data?,
        limits: DiffContextViewLimits = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> DiffContextViewPolicy {
        try performCancellationCheck(cancellationCheck)
        guard let data else { return .default }
        do {
            return try decode(from: data, limits: limits, cancellationCheck: cancellationCheck)
        } catch DiffContextViewPolicyError.cancelled {
            throw DiffContextViewPolicyError.cancelled
        } catch {
            try performCancellationCheck(cancellationCheck)
            return .default
        }
    }

    /// Projects rows under the current context and captures the snapshot that later
    /// selection and stale checks must present.
    public func projectedView(
        rows: [DiffRow],
        generation: UInt64,
        limits: DiffContextViewLimits = .default,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> DiffContextProjectedView {
        try Self.performCancellationCheck(cancellationCheck)
        try limits.validate()
        guard rows.count <= limits.maximumRows else {
            throw DiffContextViewPolicyError.tooManyRows(maximumRows: limits.maximumRows)
        }
        try Self.performCancellationCheck(cancellationCheck)
        let projection = context.project(rows)
        try Self.performCancellationCheck(cancellationCheck)
        return DiffContextProjectedView(
            projection: projection,
            snapshot: DiffContextViewSnapshot(
                generation: generation,
                sourceRowCount: rows.count,
                context: context
            )
        )
    }

    /// Rejects a forged or advanced snapshot before touching row identity.
    public func validate(
        _ view: DiffContextProjectedView,
        expectedGeneration: UInt64,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws {
        try Self.performCancellationCheck(cancellationCheck)
        guard view.snapshot.generation == expectedGeneration else {
            throw DiffContextViewPolicyError.staleGeneration(
                expected: expectedGeneration,
                actual: view.snapshot.generation
            )
        }
        guard view.snapshot.sourceRowCount == view.projection.sourceRowCount,
            view.snapshot.context == view.projection.context
        else {
            throw DiffContextViewPolicyError.staleSnapshotContents
        }
        try Self.performCancellationCheck(cancellationCheck)
    }

    /// Remaps a source selection through a stale-checked projection. Row identity
    /// anchors the result: when both an index and an ID are supplied and they agree
    /// the index wins, otherwise the ID lookup wins. Unknown or out-of-range
    /// selections return nil without trapping.
    public func remappedSelection(
        forSourceIndex sourceIndex: Int,
        selectedRowID: DiffRow.ID? = nil,
        in view: DiffContextProjectedView,
        expectedGeneration: UInt64,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> DiffContextSelectionMapping? {
        try validate(
            view,
            expectedGeneration: expectedGeneration,
            cancellationCheck: cancellationCheck
        )
        let anchor = Self.anchor(
            sourceIndex: sourceIndex,
            selectedRowID: selectedRowID,
            in: view.projection
        )
        try Self.performCancellationCheck(cancellationCheck)
        guard let anchor else { return nil }
        return view.projection.selection(forSourceIndex: anchor)
    }

    /// Row-ID-only remap with the same stale and bounds contracts.
    public func remappedSelection(
        forRowID id: DiffRow.ID,
        in view: DiffContextProjectedView,
        expectedGeneration: UInt64,
        cancellationCheck: @Sendable () throws -> Void = Self.checkCancellation
    ) throws -> DiffContextSelectionMapping? {
        try validate(
            view,
            expectedGeneration: expectedGeneration,
            cancellationCheck: cancellationCheck
        )
        try Self.performCancellationCheck(cancellationCheck)
        return view.projection.selection(forRowID: id)
    }

    private static func anchor(
        sourceIndex: Int,
        selectedRowID: DiffRow.ID?,
        in projection: DiffContextProjection
    ) -> Int? {
        let sourceRowCount = projection.sourceRowCount
        if let selectedRowID {
            if sourceIndex >= 0, sourceIndex < sourceRowCount,
                projection.sourceIndex(forRowID: selectedRowID) == sourceIndex
            {
                return sourceIndex
            }
            return projection.sourceIndex(forRowID: selectedRowID)
        }
        guard sourceIndex >= 0, sourceIndex < sourceRowCount else { return nil }
        return sourceIndex
    }

    public static func checkCancellation() throws {
        do {
            try Task<Never, Never>.checkCancellation()
        } catch {
            throw DiffContextViewPolicyError.cancelled
        }
    }

    private static func performCancellationCheck(
        _ cancellationCheck: @Sendable () throws -> Void
    ) throws {
        do {
            try cancellationCheck()
        } catch {
            throw DiffContextViewPolicyError.cancelled
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
        "lineCount",
        "isInverted",
        "lastLimitedLineCount"
    ]

    public init(from decoder: Decoder) throws {
        guard
            decoder.userInfo[Self.boundedDecodeKey] as? UUID
                == Self.boundedDecodeToken
        else {
            throw DiffContextViewPolicyError.boundedDecodingRequired
        }

        let container = try decoder.container(keyedBy: DiffContextViewPolicyCodingKey.self)
        if let unknownField = container.allKeys.map(\.stringValue)
            .filter({ !Self.persistenceFields.contains($0) })
            .sorted()
            .first
        {
            throw DiffContextViewPolicyError.unknownField(unknownField)
        }

        let schemaVersion = try container.decode(
            Int.self,
            forKey: DiffContextViewPolicyCodingKey("schemaVersion")
        )
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DiffContextViewPolicyError.unsupportedSchemaVersion(schemaVersion)
        }
        let lineCount = try container.decodeIfPresent(
            Int.self,
            forKey: DiffContextViewPolicyCodingKey("lineCount")
        )
        if let lineCount, !DiffContextMode.supportedLineCounts.contains(lineCount) {
            throw DiffContextViewPolicyError.unsupportedLineCount(lineCount)
        }
        let isInverted = try container.decode(
            Bool.self,
            forKey: DiffContextViewPolicyCodingKey("isInverted")
        )
        let lastLimitedLineCount = try container.decode(
            Int.self,
            forKey: DiffContextViewPolicyCodingKey("lastLimitedLineCount")
        )
        guard DiffContextMode.supportedLineCounts.contains(lastLimitedLineCount) else {
            throw DiffContextViewPolicyError.unsupportedLineCount(lastLimitedLineCount)
        }

        self.init()
        context = DiffContext(
            lineCount: lineCount,
            isInverted: isInverted,
            lastLimitedLineCount: lastLimitedLineCount
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: DiffContextViewPolicyCodingKey.self)
        try container.encode(
            schemaVersion,
            forKey: DiffContextViewPolicyCodingKey("schemaVersion")
        )
        try container.encodeIfPresent(
            context.lineCount,
            forKey: DiffContextViewPolicyCodingKey("lineCount")
        )
        try container.encode(
            context.isInverted,
            forKey: DiffContextViewPolicyCodingKey("isInverted")
        )
        try container.encode(
            context.lastLimitedLineCount,
            forKey: DiffContextViewPolicyCodingKey("lastLimitedLineCount")
        )
    }
}

public struct DiffContextViewLimits: Equatable, Sendable {
    public static let hardMaximumRows = 1_048_576
    public static let hardMaximumEncodedBytes = 64 * 1_024
    public static let `default` = DiffContextViewLimits()

    public let maximumRows: Int
    public let maximumEncodedBytes: Int

    public init(
        maximumRows: Int = DiffContextViewLimits.hardMaximumRows,
        maximumEncodedBytes: Int = DiffContextViewPolicy.maximumEncodedBytes
    ) {
        precondition(
            maximumRows >= 0 && maximumRows <= DiffContextViewLimits.hardMaximumRows
        )
        precondition(
            maximumEncodedBytes > 0
                && maximumEncodedBytes <= DiffContextViewLimits.hardMaximumEncodedBytes
        )
        self.maximumRows = maximumRows
        self.maximumEncodedBytes = maximumEncodedBytes
    }

    public func validate() throws {
        guard maximumRows >= 0, maximumRows <= Self.hardMaximumRows,
            maximumEncodedBytes > 0,
            maximumEncodedBytes <= Self.hardMaximumEncodedBytes
        else {
            throw DiffContextViewPolicyError.invalidLimits
        }
    }
}

/// Immutable capture of one projection boundary. Owners must advance `generation`
/// whenever rows or view state change; reusing a generation for different content
/// is a stale-validation failure, not a silent remap.
public struct DiffContextViewSnapshot: Equatable, Sendable {
    public let generation: UInt64
    public let sourceRowCount: Int
    public let context: DiffContext

    public init(generation: UInt64, sourceRowCount: Int, context: DiffContext) {
        precondition(sourceRowCount >= 0, "Diff context view source row count must not be negative")
        self.generation = generation
        self.sourceRowCount = sourceRowCount
        self.context = context
    }
}

/// One validated projection plus the snapshot that guards its later use.
public struct DiffContextProjectedView: Equatable, Sendable {
    public let projection: DiffContextProjection
    public let snapshot: DiffContextViewSnapshot

    public init(projection: DiffContextProjection, snapshot: DiffContextViewSnapshot) {
        self.projection = projection
        self.snapshot = snapshot
    }
}

public enum DiffContextViewPolicyError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case tooManyRows(maximumRows: Int)
    case tooManyChanges(maximumCount: Int)
    case duplicateCommand(DiffContextViewPolicy.Command)
    case commandDisabled(
        DiffContextViewPolicy.Command,
        reason: DiffContextViewPolicy.DisabledReason
    )
    case staleGeneration(expected: UInt64, actual: UInt64)
    case staleSnapshotContents
    case unsupportedLineCount(Int)
    case persistenceDataTooLarge(maximumBytes: Int)
    case malformedPersistence
    case invalidJSON
    case duplicateJSONKey(String)
    case unknownField(String)
    case unsupportedSchemaVersion(Int)
    case boundedDecodingRequired
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Diff context view limits are invalid."
        case .tooManyRows(let maximumRows):
            "Diff context view exceeds the \(maximumRows)-row limit."
        case .tooManyChanges(let maximumCount):
            "A diff context View transaction cannot exceed \(maximumCount) changes."
        case .duplicateCommand(let command):
            "Diff context View transaction repeats command \(command.rawValue)."
        case .commandDisabled(let command, let reason):
            "Diff context View command \(command.rawValue) is disabled: \(String(describing: reason))."
        case .staleGeneration(let expected, let actual):
            "Diff context view expected generation \(expected), not \(actual)."
        case .staleSnapshotContents:
            "Diff context view snapshot contents changed without advancing generation."
        case .unsupportedLineCount(let lineCount):
            "Unsupported diff context line count: \(lineCount)."
        case .persistenceDataTooLarge(let maximumBytes):
            "Diff context view policy exceeds the \(maximumBytes)-byte persistence limit."
        case .malformedPersistence:
            "Diff context view policy has malformed persistence values."
        case .invalidJSON:
            "Diff context view policy is not valid strict JSON."
        case .duplicateJSONKey(let key):
            "Diff context view policy repeats JSON key \(key)."
        case .unknownField(let field):
            "Unknown diff context view policy field: \(field)."
        case .unsupportedSchemaVersion(let version):
            "Unsupported diff context view policy schema version: \(version)."
        case .boundedDecodingRequired:
            "Diff context view policy must be decoded with DiffContextViewPolicy.decode(from:)."
        case .cancelled:
            "Diff context view policy operation was cancelled."
        }
    }
}

private struct DiffContextViewPolicyCodingKey: CodingKey, Hashable {
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

private struct DiffContextViewPolicyJSONScanner {
    private let bytes: [UInt8]
    private let cancellationCheck: @Sendable () throws -> Void
    private var index = 0
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
        guard consume(0x7B) else { throw DiffContextViewPolicyError.invalidJSON }
        try skipWhitespace()
        guard !consume(0x7D) else { throw DiffContextViewPolicyError.invalidJSON }

        var elementCount = 0
        var keys: Set<String> = []
        while true {
            try checkpoint()
            guard elementCount < DiffContextViewPolicy.maximumJSONObjectElements else {
                throw DiffContextViewPolicyError.invalidJSON
            }
            elementCount += 1
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw DiffContextViewPolicyError.duplicateJSONKey(key)
            }
            try skipWhitespace()
            guard consume(0x3A) else { throw DiffContextViewPolicyError.invalidJSON }
            try skipWhitespace()
            try parseValue()
            try skipWhitespace()
            if consume(0x7D) { break }
            guard consume(0x2C) else { throw DiffContextViewPolicyError.invalidJSON }
            try skipWhitespace()
        }
        try skipWhitespace()
        guard index == bytes.count else { throw DiffContextViewPolicyError.invalidJSON }
        try checkpoint(force: true)
    }

    private mutating func parseValue() throws {
        try checkpoint()
        guard let byte = currentByte else { throw DiffContextViewPolicyError.invalidJSON }
        switch byte {
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
            throw DiffContextViewPolicyError.invalidJSON
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        guard consume(0x22) else { throw DiffContextViewPolicyError.invalidJSON }
        var escaped = false
        while let byte = currentByte {
            try checkpoint()
            guard index - start < DiffContextViewPolicy.maximumJSONStringBytes else {
                throw DiffContextViewPolicyError.invalidJSON
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
                    throw DiffContextViewPolicyError.invalidJSON
                }
            } else if byte < 0x20 {
                throw DiffContextViewPolicyError.invalidJSON
            }
        }
        throw DiffContextViewPolicyError.invalidJSON
    }

    private mutating func parseNumber() throws {
        let start = index
        if currentByte == 0x2D { index += 1 }
        guard let first = currentByte, (0x30...0x39).contains(first) else {
            throw DiffContextViewPolicyError.invalidJSON
        }
        while let byte = currentByte, (0x30...0x39).contains(byte) {
            try checkpoint()
            guard index - start < DiffContextViewPolicy.maximumJSONNumberBytes else {
                throw DiffContextViewPolicyError.invalidJSON
            }
            index += 1
        }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard literalBytes.count <= bytes.count - index else {
            throw DiffContextViewPolicyError.invalidJSON
        }
        for byte in literalBytes {
            try checkpoint()
            guard bytes[index] == byte else { throw DiffContextViewPolicyError.invalidJSON }
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

    private mutating func checkpoint(force: Bool = false) throws {
        guard force || index >= nextCancellationIndex else { return }
        do {
            try cancellationCheck()
        } catch {
            throw DiffContextViewPolicyError.cancelled
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
