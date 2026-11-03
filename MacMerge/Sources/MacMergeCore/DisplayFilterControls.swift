import Foundation

/// UI-independent controls planner for the display-filter bar.
///
/// The planner validates preset select/apply/close intents without performing UI,
/// pasteboard, or storage I/O. One controls value binds two independent
/// `DisplayFilterPresets` stores, one per ``Variant``: `.text` drives row filtering and
/// accepts every `DisplayFilterRowPredicate`, while `.folder` drives name filtering and
/// only accepts `.any`. Folder-only acceptance is enforced at every entry point that can
/// introduce a filter (add, update, restore, decode), so select/apply paths hold the
/// invariant by construction.
///
/// Every mutating intent checks the optional `expectedVersion` compare-and-swap first,
/// validates the candidate before running the caller-supplied `apply` effect, bumps
/// `version` exactly once per committed change, and leaves state untouched when
/// validation fails or nothing changes. Applying a new filter reuses
/// `DisplayFilterPresets` atomic apply/rollback semantics: if `apply` throws after
/// mutating external state, the previous filter is re-applied on a detached task before
/// the original error propagates. Errors thrown by the `apply` effect itself, including
/// `DisplayFilterPresetsRollbackError` and `CancellationError`, propagate unwrapped.
public struct DisplayFilterControls: Equatable, Sendable {
    public enum Variant: String, CaseIterable, Codable, Sendable {
        case text
        case folder
    }

    public enum Command: String, CaseIterable, Sendable {
        case selectPreset
        case applyExpression
        case applyFilter
        case close
        case bindVariant
    }

    public struct Limits: Equatable, Sendable {
        public static let `default` = Limits()

        public static let hardMaximumDraftUTF8Bytes = 1 * 1_024 * 1_024
        public static let hardMaximumInputBytes = 16 * 1_024 * 1_024
        public static let hardMaximumOutputBytes = 16 * 1_024 * 1_024
        public static let hardMaximumWork = 16 * 1_024 * 1_024

        public let presets: DisplayFilterPresetLimits
        public let maximumDraftUTF8Bytes: Int
        public let maximumInputBytes: Int
        public let maximumOutputBytes: Int
        public let maximumWork: Int

        public init(
            presets: DisplayFilterPresetLimits = .default,
            maximumDraftUTF8Bytes: Int = 64 * 1_024,
            maximumInputBytes: Int = 8 * 1_024 * 1_024,
            maximumOutputBytes: Int = 8 * 1_024 * 1_024,
            maximumWork: Int = 1 * 1_024 * 1_024
        ) {
            precondition(
                maximumDraftUTF8Bytes > 0
                    && maximumDraftUTF8Bytes <= Self.hardMaximumDraftUTF8Bytes
            )
            precondition(
                maximumInputBytes > 0 && maximumInputBytes <= Self.hardMaximumInputBytes
            )
            precondition(
                maximumOutputBytes > 0 && maximumOutputBytes <= Self.hardMaximumOutputBytes
            )
            precondition(maximumWork >= 0 && maximumWork <= Self.hardMaximumWork)
            self.presets = presets
            self.maximumDraftUTF8Bytes = maximumDraftUTF8Bytes
            self.maximumInputBytes = maximumInputBytes
            self.maximumOutputBytes = maximumOutputBytes
            self.maximumWork = maximumWork
        }
    }

    /// Exact in-memory restoration point. Adopt with `restore(_:expectedVersion:)`.
    public struct Snapshot: Equatable, Sendable {
        public let variant: Variant
        public let version: UInt64
        public let textPresets: DisplayFilterPresets
        public let folderPresets: DisplayFilterPresets

        public init(
            variant: Variant,
            version: UInt64,
            textPresets: DisplayFilterPresets,
            folderPresets: DisplayFilterPresets
        ) {
            self.variant = variant
            self.version = version
            self.textPresets = textPresets
            self.folderPresets = folderPresets
        }
    }

    /// Stable order for direct bar controls: preset picker, expression apply, close.
    public static let primaryCommands: [Command] = [.selectPreset, .applyExpression, .close]

    public let limits: Limits
    public private(set) var variant: Variant
    public private(set) var version: UInt64
    public private(set) var textPresets: DisplayFilterPresets
    public private(set) var folderPresets: DisplayFilterPresets

    public init(limits: Limits = .default, variant: Variant = .text) {
        self.limits = limits
        self.variant = variant
        version = 0
        textPresets = DisplayFilterPresets(limits: limits.presets)
        folderPresets = DisplayFilterPresets(limits: limits.presets)
    }

    private init(
        limits: Limits,
        variant: Variant,
        version: UInt64,
        textPresets: DisplayFilterPresets,
        folderPresets: DisplayFilterPresets
    ) {
        self.limits = limits
        self.variant = variant
        self.version = version
        self.textPresets = textPresets
        self.folderPresets = folderPresets
    }

    public var activePresets: DisplayFilterPresets {
        variant == .text ? textPresets : folderPresets
    }

    public var activeFilter: DisplayFilter { activePresets.activeFilter }

    public var selectedPresetName: String? { activePresets.selectedPresetName }

    public var presetNames: [String] { activePresets.map(\.name) }

    public var canClose: Bool {
        activePresets.activeFilter != DisplayFilterPreset.allRows.filter
    }

    public func availability(of command: Command) -> Bool {
        switch command {
        case .selectPreset:
            !activePresets.isEmpty
        case .applyExpression, .applyFilter, .bindVariant:
            true
        case .close:
            canClose
        }
    }

    /// Validates expression-bar draft text for the bound variant without applying it.
    public func validatedDraft(
        expressionText: String,
        asRegularExpression: Bool = false,
        caseSensitive: Bool = false,
        invert: Bool = false,
        predicate: DisplayFilterRowPredicate = .any
    ) throws -> DisplayFilter {
        do {
            try Task.checkCancellation()
            let expression: DisplayFilterExpression =
                asRegularExpression
                ? .regularExpression(expressionText) : .literal(expressionText)
            let filter = DisplayFilter(
                expression: expression,
                caseSensitive: caseSensitive,
                invert: invert,
                predicate: predicate
            )
            try Self.validatedFilter(filter, variant: variant, limits: limits)
            return filter
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch is CancellationError {
            throw DisplayFilterControlsError.cancelled
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    @discardableResult
    public mutating func addPreset(
        named name: String,
        filter: DisplayFilter,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        do {
            try Task.checkCancellation()
            try checkStale(expectedVersion: expectedVersion)
            guard version < UInt64.max else {
                throw DisplayFilterControlsError.versionExhausted
            }
            try Self.validatedFilter(filter, variant: variant, limits: limits)
            var candidate = activePresets
            do {
                guard try candidate.add(name: name, filter: filter) else {
                    return false
                }
            } catch let error as DisplayFilterPresetsError {
                throw DisplayFilterControlsError.presets(error)
            }
            setActivePresets(candidate)
            version += 1
            return true
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch is CancellationError {
            throw DisplayFilterControlsError.cancelled
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    @discardableResult
    public mutating func updatePreset(
        named name: String,
        newName: String? = nil,
        filter: DisplayFilter,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        do {
            try Task.checkCancellation()
            try checkStale(expectedVersion: expectedVersion)
            guard version < UInt64.max else {
                throw DisplayFilterControlsError.versionExhausted
            }
            try Self.validatedFilter(filter, variant: variant, limits: limits)
            var candidate = activePresets
            let changed: Bool
            do {
                changed = try candidate.update(named: name, newName: newName, filter: filter)
            } catch let error as DisplayFilterPresetsError {
                throw DisplayFilterControlsError.presets(error)
            }
            guard changed else {
                return false
            }
            setActivePresets(candidate)
            version += 1
            return true
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch is CancellationError {
            throw DisplayFilterControlsError.cancelled
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    @discardableResult
    public mutating func removePreset(
        named name: String,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        do {
            try Task.checkCancellation()
            try checkStale(expectedVersion: expectedVersion)
            guard version < UInt64.max else {
                throw DisplayFilterControlsError.versionExhausted
            }
            var candidate = activePresets
            let changed: Bool
            do {
                changed = try candidate.remove(named: name)
            } catch let error as DisplayFilterPresetsError {
                throw DisplayFilterControlsError.presets(error)
            }
            guard changed else {
                return false
            }
            setActivePresets(candidate)
            version += 1
            return true
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch is CancellationError {
            throw DisplayFilterControlsError.cancelled
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    @discardableResult
    public mutating func selectPreset(
        named name: String,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        expectedVersion: UInt64? = nil
    ) async throws -> Bool {
        do {
            if Task.isCancelled {
                throw DisplayFilterControlsError.cancelled
            }
            try checkStale(expectedVersion: expectedVersion)
            guard version < UInt64.max else {
                throw DisplayFilterControlsError.versionExhausted
            }
            var candidate = activePresets
            let changed: Bool
            do {
                changed = try await candidate.select(named: name, applying: apply)
            } catch let error as DisplayFilterPresetsError {
                throw DisplayFilterControlsError.presets(error)
            }
            guard changed else {
                return false
            }
            setActivePresets(candidate)
            version += 1
            return true
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    @discardableResult
    public mutating func applyFilter(
        _ filter: DisplayFilter,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        expectedVersion: UInt64? = nil
    ) async throws -> Bool {
        do {
            if Task.isCancelled {
                throw DisplayFilterControlsError.cancelled
            }
            try checkStale(expectedVersion: expectedVersion)
            guard version < UInt64.max else {
                throw DisplayFilterControlsError.versionExhausted
            }
            try Self.validatedFilter(filter, variant: variant, limits: limits)
            var candidate = activePresets
            let changed: Bool
            do {
                changed = try await candidate.setActiveFilter(filter, applying: apply)
            } catch let error as DisplayFilterPresetsError {
                throw DisplayFilterControlsError.presets(error)
            }
            guard changed else {
                return false
            }
            setActivePresets(candidate)
            version += 1
            return true
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    @discardableResult
    public mutating func applyExpressionText(
        _ text: String,
        asRegularExpression: Bool = false,
        caseSensitive: Bool = false,
        invert: Bool = false,
        predicate: DisplayFilterRowPredicate = .any,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        expectedVersion: UInt64? = nil
    ) async throws -> Bool {
        let filter = try validatedDraft(
            expressionText: text,
            asRegularExpression: asRegularExpression,
            caseSensitive: caseSensitive,
            invert: invert,
            predicate: predicate
        )
        return try await applyFilter(filter, applying: apply, expectedVersion: expectedVersion)
    }

    /// Clears the active filter to all-rows while keeping presets and history.
    @discardableResult
    public mutating func close(
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        expectedVersion: UInt64? = nil
    ) async throws -> Bool {
        do {
            if Task.isCancelled {
                throw DisplayFilterControlsError.cancelled
            }
            try checkStale(expectedVersion: expectedVersion)
            guard version < UInt64.max else {
                throw DisplayFilterControlsError.versionExhausted
            }
            let cleared = DisplayFilterPreset.allRows.filter
            var candidate = activePresets
            let changed: Bool
            do {
                changed = try await candidate.setActiveFilter(cleared, applying: apply)
            } catch let error as DisplayFilterPresetsError {
                throw DisplayFilterControlsError.presets(error)
            }
            guard changed else {
                return false
            }
            setActivePresets(candidate)
            version += 1
            return true
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    @discardableResult
    public mutating func bind(
        variant newVariant: Variant,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        do {
            try Task.checkCancellation()
            try checkStale(expectedVersion: expectedVersion)
            guard newVariant != variant else {
                return false
            }
            guard version < UInt64.max else {
                throw DisplayFilterControlsError.versionExhausted
            }
            variant = newVariant
            version += 1
            return true
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch is CancellationError {
            throw DisplayFilterControlsError.cancelled
        }
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            variant: variant,
            version: version,
            textPresets: textPresets,
            folderPresets: folderPresets
        )
    }

    public mutating func restore(_ snapshot: Snapshot, expectedVersion: UInt64? = nil) throws {
        do {
            try Task.checkCancellation()
            try checkStale(expectedVersion: expectedVersion)
            let restoredText = try revalidated(snapshot.textPresets, for: .text)
            let restoredFolder = try revalidated(snapshot.folderPresets, for: .folder)
            textPresets = restoredText
            folderPresets = restoredFolder
            variant = snapshot.variant
            version = snapshot.version
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch is CancellationError {
            throw DisplayFilterControlsError.cancelled
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    /// Returns compact deterministic JSON. Runtime limits are policy, not persisted.
    public func encodedData() throws -> Data {
        do {
            try Task.checkCancellation()
            let textData = try textPresets.encodedData()
            let folderData = try folderPresets.encodedData()
            try Task.checkCancellation()
            let state = PersistedState(
                schemaVersion: PersistedState.currentSchemaVersion,
                stateVersion: version,
                variant: variant,
                textPresets: textData,
                folderPresets: folderData
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data: Data
            do {
                data = try encoder.encode(state)
            } catch {
                throw DisplayFilterControlsError.invalidPersistence
            }
            guard data.count <= limits.maximumOutputBytes else {
                throw DisplayFilterControlsError.outputTooLarge(
                    maximumBytes: limits.maximumOutputBytes
                )
            }
            try Task.checkCancellation()
            return data
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch is CancellationError {
            throw DisplayFilterControlsError.cancelled
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        }
    }

    /// Decodes only after bounded input-size validation and exact field matching.
    public static func decode(from data: Data, limits: Limits = .default) throws
        -> DisplayFilterControls
    {
        do {
            try Task.checkCancellation()
            guard data.count <= limits.maximumInputBytes else {
                throw DisplayFilterControlsError.inputTooLarge(
                    maximumBytes: limits.maximumInputBytes
                )
            }
            let state: PersistedState
            do {
                state = try JSONDecoder().decode(PersistedState.self, from: data)
            } catch let error as DisplayFilterControlsError {
                throw error
            } catch is CancellationError {
                throw DisplayFilterControlsError.cancelled
            } catch {
                throw DisplayFilterControlsError.invalidPersistence
            }
            guard state.schemaVersion == PersistedState.currentSchemaVersion else {
                throw DisplayFilterControlsError.unsupportedSchemaVersion(state.schemaVersion)
            }
            let textPresets: DisplayFilterPresets
            let folderPresets: DisplayFilterPresets
            do {
                textPresets = try DisplayFilterPresets.decode(
                    from: state.textPresets,
                    limits: limits.presets
                )
                folderPresets = try DisplayFilterPresets.decode(
                    from: state.folderPresets,
                    limits: limits.presets
                )
            } catch let error as DisplayFilterPresetsError {
                throw DisplayFilterControlsError.presets(error)
            } catch is CancellationError {
                throw DisplayFilterControlsError.cancelled
            } catch {
                throw DisplayFilterControlsError.invalidPersistence
            }
            try Task.checkCancellation()
            try validatedFilter(
                folderPresets.activeFilter,
                variant: .folder,
                limits: limits
            )
            for preset in folderPresets {
                try validatedFilter(preset.filter, variant: .folder, limits: limits)
            }
            for entry in folderPresets.recentHistory {
                try validatedFilter(entry, variant: .folder, limits: limits)
            }
            return DisplayFilterControls(
                limits: limits,
                variant: state.variant,
                version: state.stateVersion,
                textPresets: textPresets,
                folderPresets: folderPresets
            )
        } catch let error as DisplayFilterControlsError {
            throw error
        } catch is CancellationError {
            throw DisplayFilterControlsError.cancelled
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }

    private func checkStale(expectedVersion: UInt64?) throws {
        if let expectedVersion, expectedVersion != version {
            throw DisplayFilterControlsError.staleVersion(
                expected: expectedVersion,
                actual: version
            )
        }
    }

    private mutating func setActivePresets(_ presets: DisplayFilterPresets) {
        switch variant {
        case .text:
            textPresets = presets
        case .folder:
            folderPresets = presets
        }
    }

    private func revalidated(_ presets: DisplayFilterPresets, for variant: Variant) throws
        -> DisplayFilterPresets
    {
        let rebuilt: DisplayFilterPresets
        do {
            rebuilt = try DisplayFilterPresets(
                presets: presets.presets,
                activeFilter: presets.activeFilter,
                recentHistory: presets.recentHistory,
                selectedPresetName: presets.selectedPresetName,
                version: presets.version,
                limits: limits.presets
            )
        } catch let error as DisplayFilterPresetsError {
            throw DisplayFilterControlsError.presets(error)
        }
        if variant == .folder {
            try Self.validatedFilter(rebuilt.activeFilter, variant: variant, limits: limits)
            for preset in rebuilt {
                try Self.validatedFilter(preset.filter, variant: variant, limits: limits)
            }
            for entry in rebuilt.recentHistory {
                try Self.validatedFilter(entry, variant: variant, limits: limits)
            }
        }
        return rebuilt
    }

    private static func validatedFilter(
        _ filter: DisplayFilter,
        variant: Variant,
        limits: Limits
    ) throws {
        if variant == .folder, filter.predicate != .any {
            throw DisplayFilterControlsError.unsupportedFolderPredicate(filter.predicate)
        }
        var budget = WorkBudget(maximum: limits.maximumWork)
        _ = try budget.consumeUTF8Bytes(
            in: filter.expression.text,
            maximum: limits.maximumDraftUTF8Bytes
        )
        do {
            try filter.validate()
        } catch let error as DisplayFilterError {
            throw DisplayFilterControlsError.invalidFilter(error)
        }
    }
}

public enum DisplayFilterControlsError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case staleVersion(expected: UInt64, actual: UInt64)
    case versionExhausted
    case draftTooLarge(maximumBytes: Int)
    case unsupportedFolderPredicate(DisplayFilterRowPredicate)
    case invalidFilter(DisplayFilterError)
    case presets(DisplayFilterPresetsError)
    case inputTooLarge(maximumBytes: Int)
    case outputTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumWork: Int)
    case invalidPersistence
    case unknownField(String)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Display filter controls were cancelled."
        case .staleVersion(let expected, let actual):
            "Display filter controls changed from expected version \(expected) to \(actual)."
        case .versionExhausted:
            "Display filter controls version space is exhausted."
        case .draftTooLarge(let maximumBytes):
            "Display filter draft exceeds the \(maximumBytes)-byte UTF-8 limit."
        case .unsupportedFolderPredicate(let predicate):
            "Display filter folder variant does not support the \(predicate.rawValue) predicate."
        case .invalidFilter(let error):
            error.localizedDescription
        case .presets(let error):
            error.localizedDescription
        case .inputTooLarge(let maximumBytes):
            "Display filter controls input exceeds the \(maximumBytes)-byte limit."
        case .outputTooLarge(let maximumBytes):
            "Display filter controls output exceeds the \(maximumBytes)-byte limit."
        case .workLimitExceeded(let maximumWork):
            "Display filter controls work exceeds the \(maximumWork)-unit limit."
        case .invalidPersistence:
            "Display filter controls persistence data is invalid."
        case .unknownField(let field):
            "Unknown display filter controls persistence field: \(field)."
        case .unsupportedSchemaVersion(let version):
            "Unsupported display filter controls schema version: \(version)."
        }
    }
}

private struct WorkBudget {
    let maximum: Int
    private(set) var remaining: Int

    init(maximum: Int) {
        self.maximum = maximum
        remaining = maximum
    }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= remaining else {
            throw DisplayFilterControlsError.workLimitExceeded(maximumWork: maximum)
        }
        remaining -= amount
        try Task.checkCancellation()
    }

    mutating func consumeUTF8Bytes(in value: String, maximum: Int) throws -> Int {
        var count = 0
        var pending = 0
        for _ in value.utf8 {
            guard count < maximum else {
                try consume(pending + 1)
                throw DisplayFilterControlsError.draftTooLarge(maximumBytes: maximum)
            }
            count += 1
            pending += 1
            if pending == 4_096 || pending > remaining {
                try consume(pending)
                pending = 0
            }
        }
        if pending > 0 {
            try consume(pending)
        } else {
            try Task.checkCancellation()
        }
        return count
    }
}

private struct PersistedState: Codable {
    static let currentSchemaVersion = 1
    static let fields: Set<String> = [
        "schemaVersion", "stateVersion", "variant", "textPresets", "folderPresets"
    ]

    let schemaVersion: Int
    let stateVersion: UInt64
    let variant: DisplayFilterControls.Variant
    let textPresets: Data
    let folderPresets: Data

    init(
        schemaVersion: Int,
        stateVersion: UInt64,
        variant: DisplayFilterControls.Variant,
        textPresets: Data,
        folderPresets: Data
    ) {
        self.schemaVersion = schemaVersion
        self.stateVersion = stateVersion
        self.variant = variant
        self.textPresets = textPresets
        self.folderPresets = folderPresets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PersistedFieldKey.self)
        let actual = Set(container.allKeys.map(\.stringValue))
        if let unknown = actual.subtracting(Self.fields).sorted().first {
            throw DisplayFilterControlsError.unknownField(unknown)
        }
        guard actual == Self.fields else {
            throw DisplayFilterControlsError.invalidPersistence
        }
        schemaVersion = try container.decode(Int.self, forKey: PersistedFieldKey("schemaVersion"))
        stateVersion = try container.decode(
            UInt64.self,
            forKey: PersistedFieldKey("stateVersion")
        )
        variant = try container.decode(
            DisplayFilterControls.Variant.self,
            forKey: PersistedFieldKey("variant")
        )
        textPresets = try container.decode(Data.self, forKey: PersistedFieldKey("textPresets"))
        folderPresets = try container.decode(
            Data.self,
            forKey: PersistedFieldKey("folderPresets")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PersistedFieldKey.self)
        try container.encode(schemaVersion, forKey: PersistedFieldKey("schemaVersion"))
        try container.encode(stateVersion, forKey: PersistedFieldKey("stateVersion"))
        try container.encode(variant, forKey: PersistedFieldKey("variant"))
        try container.encode(textPresets, forKey: PersistedFieldKey("textPresets"))
        try container.encode(folderPresets, forKey: PersistedFieldKey("folderPresets"))
    }
}

private struct PersistedFieldKey: CodingKey, Hashable {
    let stringValue: String
    var intValue: Int? { nil }

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
