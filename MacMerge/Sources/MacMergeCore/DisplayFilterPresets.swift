import Foundation

public struct DisplayFilterPresetLimits: Equatable, Sendable {
    public static let `default` = DisplayFilterPresetLimits()

    public let maximumPresetCount: Int
    public let maximumHistoryEntries: Int
    public let maximumPresetNameUTF8Bytes: Int
    public let maximumTotalPresetNameUTF8Bytes: Int
    public let maximumExpressionUTF8Bytes: Int
    public let maximumTotalExpressionUTF8Bytes: Int
    public let maximumInputBytes: Int
    public let maximumOutputBytes: Int
    public let maximumWork: Int

    public init(
        maximumPresetCount: Int = DisplayFilterPresets.maximumPresetCount,
        maximumHistoryEntries: Int = DisplayFilterPresetHistory.maximumCapacity,
        maximumPresetNameUTF8Bytes: Int = 256,
        maximumTotalPresetNameUTF8Bytes: Int = 16 * 1024,
        maximumExpressionUTF8Bytes: Int = DisplayFilterPresets.maximumExpressionUTF8Bytes,
        maximumTotalExpressionUTF8Bytes: Int = 1 * 1024 * 1024,
        maximumInputBytes: Int = DisplayFilterPresets.maximumPersistedInputBytes,
        maximumOutputBytes: Int = DisplayFilterPresets.maximumEncodedOutputBytes,
        maximumWork: Int = 8 * 1024 * 1024
    ) {
        precondition(
            maximumPresetCount >= 0
                && maximumPresetCount <= DisplayFilterPresets.maximumPresetCount
        )
        precondition(
            maximumHistoryEntries > 0
                && maximumHistoryEntries <= DisplayFilterPresetHistory.maximumCapacity
        )
        precondition(
            maximumPresetNameUTF8Bytes > 0
                && maximumPresetNameUTF8Bytes <= DisplayFilterPresets.maximumPresetNameUTF8Bytes
        )
        precondition(
            maximumTotalPresetNameUTF8Bytes >= 0
                && maximumTotalPresetNameUTF8Bytes
                    <= DisplayFilterPresets.maximumTotalPresetNameUTF8Bytes
        )
        precondition(
            maximumExpressionUTF8Bytes >= 0
                && maximumExpressionUTF8Bytes <= DisplayFilterPresets.maximumExpressionUTF8Bytes
        )
        precondition(
            maximumTotalExpressionUTF8Bytes >= 0
                && maximumTotalExpressionUTF8Bytes
                    <= DisplayFilterPresets.maximumTotalExpressionUTF8Bytes
        )
        precondition(
            maximumInputBytes > 0
                && maximumInputBytes <= DisplayFilterPresets.maximumPersistedInputBytes
        )
        precondition(
            maximumOutputBytes > 0
                && maximumOutputBytes <= DisplayFilterPresets.maximumEncodedOutputBytes
        )
        precondition(
            maximumWork >= 0
                && maximumWork <= DisplayFilterPresets.maximumWork
        )
        self.maximumPresetCount = maximumPresetCount
        self.maximumHistoryEntries = maximumHistoryEntries
        self.maximumPresetNameUTF8Bytes = maximumPresetNameUTF8Bytes
        self.maximumTotalPresetNameUTF8Bytes = maximumTotalPresetNameUTF8Bytes
        self.maximumExpressionUTF8Bytes = maximumExpressionUTF8Bytes
        self.maximumTotalExpressionUTF8Bytes = maximumTotalExpressionUTF8Bytes
        self.maximumInputBytes = maximumInputBytes
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumWork = maximumWork
    }
}

public struct DisplayFilterPresetHistory: Equatable, Sendable, RandomAccessCollection {
    public static let defaultCapacity = DisplayFilterHistory.defaultCapacity
    public static let maximumCapacity = DisplayFilterHistory.maximumCapacity

    public typealias Index = Int

    public let capacity: Int
    public private(set) var entries: [DisplayFilter]

    public var startIndex: Int { entries.startIndex }
    public var endIndex: Int { entries.endIndex }

    public subscript(position: Int) -> DisplayFilter {
        entries[position]
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.capacity == rhs.capacity, lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            ExactFilterIdentity($0) == ExactFilterIdentity($1)
        }
    }

    public init(capacity: Int = defaultCapacity) {
        precondition(capacity > 0 && capacity <= Self.maximumCapacity)
        self.capacity = capacity
        entries = []
    }

    public init(_ entries: [DisplayFilter], capacity: Int = defaultCapacity) throws {
        guard capacity > 0 && capacity <= Self.maximumCapacity else {
            throw DisplayFilterError.invalidHistoryCapacity(capacity)
        }
        guard entries.count <= capacity else {
            throw DisplayFilterError.tooManyHistoryEntries(maximumEntries: capacity)
        }
        var seen: Set<ExactFilterIdentity> = []
        seen.reserveCapacity(entries.count)
        for entry in entries {
            try entry.validate()
            guard seen.insert(ExactFilterIdentity(entry)).inserted else {
                throw DisplayFilterError.duplicateHistoryEntry
            }
        }
        self.capacity = capacity
        self.entries = entries
    }

    public mutating func removeAll(keepingCapacity: Bool = false) {
        entries.removeAll(keepingCapacity: keepingCapacity)
    }
}

public struct NamedDisplayFilterPreset: Equatable, Hashable, Identifiable, Sendable {
    public let name: String
    public let filter: DisplayFilter

    public var id: String { name }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name.utf8.elementsEqual(rhs.name.utf8)
            && Self.exactlyEqual(lhs.filter, rhs.filter)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name.utf8.count)
        for byte in name.utf8 { hasher.combine(byte) }
        switch filter.expression {
        case .literal(let text):
            hasher.combine(0 as UInt8)
            hasher.combine(text.utf8.count)
            for byte in text.utf8 { hasher.combine(byte) }
        case .regularExpression(let text):
            hasher.combine(1 as UInt8)
            hasher.combine(text.utf8.count)
            for byte in text.utf8 { hasher.combine(byte) }
        }
        hasher.combine(filter.caseSensitive)
        hasher.combine(filter.invert)
        hasher.combine(filter.predicate.rawValue)
    }

    public init(name: String, filter: DisplayFilter) throws {
        var work = DisplayFilterPresetWorkBudget(
            maximum: DisplayFilterPresetLimits.default.maximumWork
        )
        self.name = try DisplayFilterPresets.canonicalizedPresetName(
            name,
            maximumUTF8Bytes: DisplayFilterPresets.maximumPresetNameUTF8Bytes,
            work: &work
        )
        var totalExpressionBytes: Int?
        try DisplayFilterPresets.validate(
            filter,
            limits: .default,
            totalExpressionBytes: &totalExpressionBytes,
            work: &work
        )
        self.filter = filter
    }

    fileprivate init(validatedName name: String, filter: DisplayFilter) {
        self.name = name
        self.filter = filter
    }

    private static func exactlyEqual(_ lhs: DisplayFilter, _ rhs: DisplayFilter) -> Bool {
        let expressionEqual: Bool
        switch (lhs.expression, rhs.expression) {
        case (.literal(let lhs), .literal(let rhs)),
            (.regularExpression(let lhs), .regularExpression(let rhs)):
            expressionEqual = lhs.utf8.elementsEqual(rhs.utf8)
        default:
            expressionEqual = false
        }
        return expressionEqual
            && lhs.caseSensitive == rhs.caseSensitive
            && lhs.invert == rhs.invert
            && lhs.predicate == rhs.predicate
    }
}

public struct DisplayFilterPresetsRollbackError: Error, LocalizedError, Sendable {
    public let applicationError: any Error
    public let rollbackError: any Error

    public var errorDescription: String? {
        "Applying the display filter failed: \(applicationError.localizedDescription) "
            + "Restoring the previous filter also failed: \(rollbackError.localizedDescription)"
    }

    fileprivate init(applicationError: any Error, rollbackError: any Error) {
        self.applicationError = applicationError
        self.rollbackError = rollbackError
    }
}

public enum DisplayFilterPresetsError: Error, Equatable, LocalizedError, Sendable {
    case emptyPresetName
    case invalidPresetName(String)
    case presetNameTooLarge(maximumBytes: Int)
    case totalPresetNamesTooLarge(maximumBytes: Int)
    case expressionTooLarge(maximumBytes: Int)
    case totalExpressionsTooLarge(maximumBytes: Int)
    case tooManyPresets(maximumCount: Int)
    case invalidHistoryCapacity(Int)
    case tooManyHistoryEntries(maximumCount: Int)
    case duplicatePresetName(String)
    case duplicateHistoryEntry
    case nonCanonicalPresetName(String)
    case presetNotFound(String)
    case selectedPresetFilterMismatch(String)
    case invalidFilter(DisplayFilterError)
    case staleVersion(expected: UInt64, actual: UInt64)
    case versionExhausted
    case inputTooLarge(maximumBytes: Int)
    case outputTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumWork: Int)
    case invalidJSON
    case duplicateJSONKey(String)
    case unknownField(String)
    case unknownExpressionKind(String)
    case jsonNestingTooDeep(maximumDepth: Int)
    case jsonContainerTooLarge(maximumElements: Int)
    case tooManyJSONValues(maximumValues: Int)
    case jsonStringTooLarge(maximumBytes: Int)
    case jsonNumberTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyPresetName:
            "Display filter preset names must not be empty."
        case .invalidPresetName(let name):
            "Display filter preset name contains control characters: \(name)."
        case .presetNameTooLarge(let maximumBytes):
            "Display filter preset names cannot exceed \(maximumBytes) UTF-8 bytes."
        case .totalPresetNamesTooLarge(let maximumBytes):
            "Display filter preset names exceed the \(maximumBytes)-byte total UTF-8 limit."
        case .expressionTooLarge(let maximumBytes):
            "A display filter expression exceeds the \(maximumBytes)-byte UTF-8 limit."
        case .totalExpressionsTooLarge(let maximumBytes):
            "Display filter expressions exceed the \(maximumBytes)-byte total UTF-8 limit."
        case .tooManyPresets(let maximumCount):
            "Display filter presets cannot exceed \(maximumCount) entries."
        case .invalidHistoryCapacity(let capacity):
            "Display filter preset history capacity is invalid: \(capacity)."
        case .tooManyHistoryEntries(let maximumCount):
            "Display filter preset history cannot exceed \(maximumCount) entries."
        case .duplicatePresetName(let name):
            "Display filter preset name is duplicated canonically: \(name)."
        case .duplicateHistoryEntry:
            "Display filter preset history contains a duplicate filter."
        case .nonCanonicalPresetName(let name):
            "Persisted display filter preset name is not canonical: \(name)."
        case .presetNotFound(let name):
            "Display filter preset was not found: \(name)."
        case .selectedPresetFilterMismatch(let name):
            "Selected display filter preset does not match the active filter: \(name)."
        case .invalidFilter(let error):
            error.localizedDescription
        case .staleVersion(let expected, let actual):
            "Display filter presets changed from expected version \(expected) to \(actual)."
        case .versionExhausted:
            "Display filter preset version space is exhausted."
        case .inputTooLarge(let maximumBytes):
            "Display filter preset input exceeds the \(maximumBytes)-byte limit."
        case .outputTooLarge(let maximumBytes):
            "Display filter preset output exceeds the \(maximumBytes)-byte limit."
        case .workLimitExceeded(let maximumWork):
            "Display filter preset work exceeds the \(maximumWork)-unit limit."
        case .invalidJSON:
            "Display filter preset persistence data is not valid JSON."
        case .duplicateJSONKey(let key):
            "Display filter preset JSON key appears more than once in one object: \(key)."
        case .unknownField(let field):
            "Unknown display filter preset persistence field: \(field)."
        case .unknownExpressionKind(let kind):
            "Unknown display filter expression kind: \(kind)."
        case .jsonNestingTooDeep(let maximumDepth):
            "Display filter preset JSON exceeds the \(maximumDepth)-level nesting limit."
        case .jsonContainerTooLarge(let maximumElements):
            "A display filter preset JSON container exceeds \(maximumElements) elements."
        case .tooManyJSONValues(let maximumValues):
            "Display filter preset JSON exceeds the \(maximumValues)-value limit."
        case .jsonStringTooLarge(let maximumBytes):
            "A display filter preset JSON string exceeds \(maximumBytes) UTF-8 bytes."
        case .jsonNumberTooLarge(let maximumBytes):
            "A display filter preset JSON number exceeds \(maximumBytes) bytes."
        case .unsupportedSchemaVersion(let version):
            "Unsupported display filter preset schema version: \(version)."
        }
    }
}

/// UI-independent named filters, active filter, and deterministic bounded MRU history.
///
/// Applying callbacks have rollback semantics. If applying a new filter throws after mutating
/// external state, the callback is invoked again with the previous filter before the original
/// error is rethrown. Rollback runs in an uncancelled task. If rollback also fails, both failures
/// are surfaced in `DisplayFilterPresetsRollbackError`.
public struct DisplayFilterPresets: Equatable, Sendable, RandomAccessCollection {
    public static let currentSchemaVersion = 2
    public static let maximumPresetCount = 100
    public static let maximumPresetNameUTF8Bytes = 1_024
    public static let maximumTotalPresetNameUTF8Bytes = maximumPresetCount * maximumPresetNameUTF8Bytes
    public static let maximumExpressionUTF8Bytes = DisplayFilter.maximumExpressionUTF16Length * 3
    public static let maximumTotalExpressionUTF8Bytes = 2 * 1_024 * 1_024
    public static let maximumPersistedInputBytes = 2 * 1_024 * 1_024
    public static let maximumEncodedOutputBytes = 2 * 1_024 * 1_024
    public static let maximumWork = 16 * 1_024 * 1_024

    fileprivate static let maximumJSONNestingDepth = 8
    fileprivate static let maximumJSONContainerElements = 256
    fileprivate static let maximumJSONValueCount =
        14 + 9 * maximumPresetCount + 7 * DisplayFilterPresetHistory.maximumCapacity
    fileprivate static let maximumJSONKeyUTF8Bytes = 64
    fileprivate static let maximumJSONNumberBytes = 32

    public typealias Limits = DisplayFilterPresetLimits
    public typealias Preset = NamedDisplayFilterPreset
    public typealias Index = Int

    public let limits: Limits
    public private(set) var presets: [Preset]
    public private(set) var activeFilter: DisplayFilter
    public private(set) var recentHistory: DisplayFilterPresetHistory
    public private(set) var selectedPresetName: String?
    public private(set) var version: UInt64

    public var activeExpression: DisplayFilterExpression { activeFilter.expression }
    public var history: DisplayFilterPresetHistory { recentHistory }
    public var selectedPreset: Preset? {
        guard let selectedPresetName else { return nil }
        return presets.first { Self.exactlyEqual($0.name, selectedPresetName) }
    }

    public var startIndex: Int { presets.startIndex }
    public var endIndex: Int { presets.endIndex }

    public subscript(position: Int) -> Preset {
        presets[position]
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.limits == rhs.limits
            && exactlyEqual(lhs.presets, rhs.presets)
            && exactlyEqual(lhs.activeFilter, rhs.activeFilter)
            && exactlyEqual(lhs.recentHistory, rhs.recentHistory)
            && exactlyEqual(lhs.selectedPresetName, rhs.selectedPresetName)
            && lhs.version == rhs.version
    }

    public init(limits: Limits = .default) {
        self.init(
            historyCapacity: Swift.min(
                DisplayFilterPresetHistory.defaultCapacity,
                limits.maximumHistoryEntries
            ),
            limits: limits
        )
    }

    public init(historyCapacity: Int, limits: Limits = .default) {
        precondition(
            historyCapacity > 0 && historyCapacity <= limits.maximumHistoryEntries,
            "Display filter preset history capacity is outside configured limits"
        )
        self.limits = limits
        presets = []
        activeFilter = DisplayFilterPreset.allRows.filter
        recentHistory = DisplayFilterPresetHistory(capacity: historyCapacity)
        selectedPresetName = nil
        version = 0
    }

    public init(
        presets: [Preset],
        activeFilter: DisplayFilter = DisplayFilterPreset.allRows.filter,
        selectedPresetName: String? = nil,
        version: UInt64 = 0,
        limits: Limits = .default
    ) throws {
        try self.init(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: DisplayFilterPresetHistory(
                capacity: Swift.min(
                    DisplayFilterPresetHistory.defaultCapacity,
                    limits.maximumHistoryEntries
                )
            ),
            selectedPresetName: selectedPresetName,
            version: version,
            limits: limits
        )
    }

    public init(
        presets: [Preset],
        activeFilter: DisplayFilter = DisplayFilterPreset.allRows.filter,
        recentHistory: DisplayFilterPresetHistory,
        selectedPresetName requestedSelectedPresetName: String? = nil,
        version: UInt64 = 0,
        limits: Limits = .default
    ) throws {
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        let selectedPresetName = try Self.resolvedSelectedPresetName(
            requestedSelectedPresetName,
            activeFilter: activeFilter,
            presets: presets,
            limits: limits,
            work: &work
        )
        try Self.validate(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: selectedPresetName,
            limits: limits,
            work: &work
        )
        try Task.checkCancellation()
        self.limits = limits
        self.presets = presets
        self.activeFilter = activeFilter
        self.recentHistory = recentHistory
        self.selectedPresetName = selectedPresetName
        self.version = version
    }

    public init(
        presets: [Preset],
        activeFilter: DisplayFilter = DisplayFilterPreset.allRows.filter,
        recentHistory: DisplayFilterHistory,
        selectedPresetName: String? = nil,
        version: UInt64 = 0,
        limits: Limits = .default
    ) throws {
        try self.init(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: DisplayFilterPresetHistory(
                Array(recentHistory),
                capacity: recentHistory.capacity
            ),
            selectedPresetName: selectedPresetName,
            version: version,
            limits: limits
        )
    }

    @discardableResult
    public mutating func add(
        name: String,
        filter: DisplayFilter,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        let preset = try Self.makePreset(name: name, filter: filter, limits: limits, work: &work)
        let key = Self.canonicalNameKey(preset.name)
        guard try index(forCanonicalKey: key, work: &work) == nil else {
            throw DisplayFilterPresetsError.duplicatePresetName(preset.name)
        }

        var candidatePresets = presets
        candidatePresets.append(preset)
        try commit(
            presets: candidatePresets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: selectedPresetName,
            work: &work
        )
        return true
    }

    @discardableResult
    public mutating func add(
        _ preset: Preset,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        try add(
            name: preset.name,
            filter: preset.filter,
            expectedVersion: expectedVersion
        )
    }

    @discardableResult
    public mutating func update(
        named name: String,
        newName: String? = nil,
        filter: DisplayFilter,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        let lookupName = try Self.canonicalizedPresetName(
            name,
            maximumUTF8Bytes: limits.maximumPresetNameUTF8Bytes,
            work: &work
        )
        let lookupKey = Self.canonicalNameKey(lookupName)
        guard let targetIndex = try index(forCanonicalKey: lookupKey, work: &work) else {
            throw DisplayFilterPresetsError.presetNotFound(lookupName)
        }
        let replacement = try Self.makePreset(
            name: newName ?? presets[targetIndex].name,
            filter: filter,
            limits: limits,
            work: &work
        )
        let replacementKey = Self.canonicalNameKey(replacement.name)
        if let duplicateIndex = try index(forCanonicalKey: replacementKey, work: &work),
            duplicateIndex != targetIndex
        {
            throw DisplayFilterPresetsError.duplicatePresetName(replacement.name)
        }
        _ = try work.consumeUTF8Bytes(in: presets[targetIndex].name)
        _ = try work.consumeUTF8Bytes(in: replacement.name)
        try Self.chargeFilterComparison(
            presets[targetIndex].filter,
            replacement.filter,
            limits: limits,
            work: &work
        )
        guard !Self.exactlyEqual(presets[targetIndex], replacement) else { return false }

        var candidatePresets = presets
        candidatePresets[targetIndex] = replacement
        let updatesSelectedPreset = selectedPresetName.map(Self.canonicalNameKey) == lookupKey
        let candidateSelectedPresetName =
            updatesSelectedPreset && Self.exactlyEqual(replacement.filter, activeFilter)
            ? replacement.name
            : (updatesSelectedPreset ? nil : selectedPresetName)
        try commit(
            presets: candidatePresets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: candidateSelectedPresetName,
            work: &work
        )
        return true
    }

    @discardableResult
    public mutating func update(
        named name: String,
        to preset: Preset,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        try update(
            named: name,
            newName: preset.name,
            filter: preset.filter,
            expectedVersion: expectedVersion
        )
    }

    @discardableResult
    public mutating func remove(
        named name: String,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        let canonicalName = try Self.canonicalizedPresetName(
            name,
            maximumUTF8Bytes: limits.maximumPresetNameUTF8Bytes,
            work: &work
        )
        guard
            let index = try index(
                forCanonicalKey: Self.canonicalNameKey(canonicalName),
                work: &work
            )
        else {
            return false
        }

        var candidatePresets = presets
        let removedPreset = candidatePresets.remove(at: index)
        let candidateSelectedPresetName =
            selectedPresetName.map { Self.exactlyEqual($0, removedPreset.name) } == true
            ? nil
            : selectedPresetName
        try commit(
            presets: candidatePresets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: candidateSelectedPresetName,
            work: &work
        )
        return true
    }

    @discardableResult
    public mutating func select(
        named name: String,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        expectedVersion: UInt64? = nil
    ) async throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        let canonicalName = try Self.canonicalizedPresetName(
            name,
            maximumUTF8Bytes: limits.maximumPresetNameUTF8Bytes,
            work: &work
        )
        guard
            let index = try index(
                forCanonicalKey: Self.canonicalNameKey(canonicalName),
                work: &work
            )
        else {
            throw DisplayFilterPresetsError.presetNotFound(canonicalName)
        }
        return try await setActiveFilter(
            presets[index].filter,
            selectedPresetName: presets[index].name,
            applying: apply,
            work: &work
        )
    }

    @discardableResult
    public mutating func setActiveExpression(
        _ expression: DisplayFilterExpression,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        expectedVersion: UInt64? = nil
    ) async throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        var filter = activeFilter
        filter.expression = expression
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        try Self.chargeFilterComparison(filter, activeFilter, limits: limits, work: &work)
        let selectedPresetName =
            Self.exactlyEqual(filter, activeFilter) ? self.selectedPresetName : nil
        return try await setActiveFilter(
            filter,
            selectedPresetName: selectedPresetName,
            applying: apply,
            work: &work
        )
    }

    @discardableResult
    public mutating func setActiveFilter(
        _ filter: DisplayFilter,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        expectedVersion: UInt64? = nil
    ) async throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        try Self.chargeFilterComparison(filter, activeFilter, limits: limits, work: &work)
        let selectedPresetName =
            Self.exactlyEqual(filter, activeFilter) ? self.selectedPresetName : nil
        return try await setActiveFilter(
            filter,
            selectedPresetName: selectedPresetName,
            applying: apply,
            work: &work
        )
    }

    @discardableResult
    public mutating func removeFromHistory(
        _ filter: DisplayFilter,
        expectedVersion: UInt64? = nil
    ) throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        var candidateHistory = recentHistory
        guard
            try Self.removeExactly(
                filter,
                from: &candidateHistory,
                limits: limits,
                work: &work
            )
        else {
            return false
        }
        try commit(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: candidateHistory,
            selectedPresetName: selectedPresetName,
            work: &work
        )
        return true
    }

    @discardableResult
    public mutating func clearHistory(expectedVersion: UInt64? = nil) throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        guard !recentHistory.isEmpty else { return false }
        var candidateHistory = recentHistory
        candidateHistory.removeAll(keepingCapacity: true)
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        try commit(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: candidateHistory,
            selectedPresetName: selectedPresetName,
            work: &work
        )
        return true
    }

    /// Restores the all-rows filter and clears history. Presets are cleared unless retained.
    @discardableResult
    public mutating func reset(
        keepingPresets: Bool = false,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        expectedVersion: UInt64? = nil
    ) async throws -> Bool {
        try beginMutation(expectedVersion: expectedVersion)
        let candidatePresets = keepingPresets ? presets : []
        let candidateFilter = DisplayFilterPreset.allRows.filter
        var candidateHistory = recentHistory
        candidateHistory.removeAll(keepingCapacity: true)
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        try Self.chargeFilterComparison(
            candidateFilter,
            activeFilter,
            limits: limits,
            work: &work
        )
        guard
            (!keepingPresets && !presets.isEmpty)
                || !Self.exactlyEqual(candidateFilter, activeFilter)
                || !recentHistory.isEmpty
                || selectedPresetName != nil
        else {
            return false
        }

        try await commitAfterApplying(
            presets: candidatePresets,
            activeFilter: candidateFilter,
            recentHistory: candidateHistory,
            selectedPresetName: nil,
            applying: apply,
            work: &work
        )
        return true
    }

    /// Returns compact deterministic JSON. Runtime limits are policy and are not persisted.
    public func encodedData() throws -> Data {
        try Task.checkCancellation()
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        try Self.validate(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: selectedPresetName,
            limits: limits,
            work: &work
        )
        let encodedSize = try preflightEncodedSize(work: &work)
        try work.consume(encodedSize)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(DisplayFilterPresetsWireState(self))
        if data.count > encodedSize {
            try work.consume(data.count - encodedSize)
        }
        guard data.count <= limits.maximumOutputBytes else {
            throw DisplayFilterPresetsError.outputTooLarge(
                maximumBytes: limits.maximumOutputBytes
            )
        }
        try Task.checkCancellation()
        return data
    }

    private func preflightEncodedSize(
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> Int {
        var output = DisplayFilterPresetOutputBudget(
            maximum: limits.maximumOutputBytes,
            work: work
        )
        try output.addASCII("{\"activeFilter\":")
        try output.add(activeFilter)
        try output.addASCII(",\"historyCapacity\":")
        try output.addASCII(String(recentHistory.capacity))
        try output.addASCII(",\"presets\":[")
        for (index, preset) in presets.enumerated() {
            if index > 0 { try output.addASCII(",") }
            try output.addASCII("{\"filter\":")
            try output.add(preset.filter)
            try output.addASCII(",\"name\":")
            try output.addJSONString(preset.name)
            try output.addASCII("}")
        }
        try output.addASCII("],\"recentHistory\":[")
        for (index, filter) in recentHistory.enumerated() {
            if index > 0 { try output.addASCII(",") }
            try output.add(filter)
        }
        try output.addASCII("],\"schemaVersion\":")
        try output.addASCII(String(Self.currentSchemaVersion))
        try output.addASCII(",\"selectedPresetName\":")
        if let selectedPresetName {
            try output.addJSONString(selectedPresetName)
        } else {
            try output.addASCII("null")
        }
        try output.addASCII(",\"stateVersion\":")
        try output.addASCII(String(version))
        try output.addASCII("}")
        work = output.work
        return output.count
    }

    /// Decodes only after bounded structural validation of every JSON token and object key.
    public static func decode(
        from data: Data,
        limits: Limits = .default
    ) throws -> DisplayFilterPresets {
        try Task.checkCancellation()
        guard data.count <= limits.maximumInputBytes else {
            throw DisplayFilterPresetsError.inputTooLarge(
                maximumBytes: limits.maximumInputBytes
            )
        }
        var work = DisplayFilterPresetWorkBudget(maximum: limits.maximumWork)
        try work.consume(data.count)
        try work.consume(data.count)
        try data.withUnsafeBytes { rawBuffer in
            var scanner = DisplayFilterPresetsJSONScanner(
                bytes: rawBuffer.bindMemory(to: UInt8.self),
                limits: limits
            )
            try scanner.validate()
        }
        let wire: DisplayFilterPresetsWireState
        do {
            wire = try JSONDecoder().decode(DisplayFilterPresetsWireState.self, from: data)
        } catch {
            throw DisplayFilterPresetsError.invalidJSON
        }

        guard wire.historyCapacity > 0,
            wire.historyCapacity <= limits.maximumHistoryEntries
        else {
            throw DisplayFilterPresetsError.invalidHistoryCapacity(wire.historyCapacity)
        }
        guard wire.recentHistory.count <= wire.historyCapacity,
            wire.recentHistory.count <= limits.maximumHistoryEntries
        else {
            throw DisplayFilterPresetsError.tooManyHistoryEntries(
                maximumCount: Swift.min(wire.historyCapacity, limits.maximumHistoryEntries)
            )
        }

        try Task.checkCancellation()
        let history: DisplayFilterPresetHistory
        do {
            history = try DisplayFilterPresetHistory(
                wire.recentHistory.map(\.filter),
                capacity: wire.historyCapacity
            )
        } catch let error as DisplayFilterError {
            throw presetsError(for: error)
        }
        try Task.checkCancellation()
        let decodedPresets = wire.presets.map {
            Preset(validatedName: $0.name, filter: $0.filter.filter)
        }
        try Self.validate(
            presets: decodedPresets,
            activeFilter: wire.activeFilter.filter,
            recentHistory: history,
            selectedPresetName: wire.selectedPresetName,
            limits: limits,
            work: &work,
            requireCanonicalNames: true
        )
        try Task.checkCancellation()
        return DisplayFilterPresets(
            uncheckedPresets: decodedPresets,
            activeFilter: wire.activeFilter.filter,
            recentHistory: history,
            selectedPresetName: wire.selectedPresetName,
            version: wire.stateVersion,
            limits: limits
        )
    }

    fileprivate static func canonicalizedPresetName(
        _ name: String,
        maximumUTF8Bytes: Int,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> String {
        guard
            try boundedUTF8ByteCount(
                name,
                maximum: maximumUTF8Bytes,
                work: &work
            ) != nil
        else {
            throw DisplayFilterPresetsError.presetNameTooLarge(
                maximumBytes: maximumUTF8Bytes
            )
        }
        let canonical = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !canonical.isEmpty else { throw DisplayFilterPresetsError.emptyPresetName }
        guard
            try boundedUTF8ByteCount(
                canonical,
                maximum: maximumUTF8Bytes,
                work: &work
            ) != nil
        else {
            throw DisplayFilterPresetsError.presetNameTooLarge(
                maximumBytes: maximumUTF8Bytes
            )
        }
        guard !canonical.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw DisplayFilterPresetsError.invalidPresetName(canonical)
        }
        return canonical
    }

    private init(
        uncheckedPresets presets: [Preset],
        activeFilter: DisplayFilter,
        recentHistory: DisplayFilterPresetHistory,
        selectedPresetName: String?,
        version: UInt64,
        limits: Limits
    ) {
        self.limits = limits
        self.presets = presets
        self.activeFilter = activeFilter
        self.recentHistory = recentHistory
        self.selectedPresetName = selectedPresetName
        self.version = version
    }

    private mutating func beginMutation(expectedVersion: UInt64?) throws {
        try Task.checkCancellation()
        if let expectedVersion, expectedVersion != version {
            throw DisplayFilterPresetsError.staleVersion(
                expected: expectedVersion,
                actual: version
            )
        }
    }

    private mutating func setActiveFilter(
        _ filter: DisplayFilter,
        selectedPresetName: String?,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        work: inout DisplayFilterPresetWorkBudget
    ) async throws -> Bool {
        var totalExpressionBytes: Int?
        try Self.validate(
            filter,
            limits: limits,
            totalExpressionBytes: &totalExpressionBytes,
            work: &work
        )
        let historyUpdate = try Self.recordExactly(
            filter,
            in: recentHistory,
            limits: limits,
            work: &work
        )
        try Self.chargeFilterComparison(filter, activeFilter, limits: limits, work: &work)
        guard
            !Self.exactlyEqual(filter, activeFilter)
                || historyUpdate.changed
                || !Self.exactlyEqual(selectedPresetName, self.selectedPresetName)
        else {
            return false
        }
        try await commitAfterApplying(
            presets: presets,
            activeFilter: filter,
            recentHistory: historyUpdate.history,
            selectedPresetName: selectedPresetName,
            applying: apply,
            work: &work
        )
        return true
    }

    private mutating func commitAfterApplying(
        presets: [Preset],
        activeFilter: DisplayFilter,
        recentHistory: DisplayFilterPresetHistory,
        selectedPresetName: String?,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void,
        work: inout DisplayFilterPresetWorkBudget
    ) async throws {
        let nextVersion = try validatedNextVersion(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: selectedPresetName,
            work: &work
        )
        try Self.chargeFilterComparison(
            activeFilter,
            self.activeFilter,
            limits: limits,
            work: &work
        )
        if !Self.exactlyEqual(activeFilter, self.activeFilter) {
            do {
                try apply(activeFilter)
                try Task.checkCancellation()
            } catch {
                let applicationError = error
                do {
                    try await Self.rollback(to: self.activeFilter, applying: apply)
                } catch {
                    throw DisplayFilterPresetsRollbackError(
                        applicationError: applicationError,
                        rollbackError: error
                    )
                }
                throw applicationError
            }
        }
        applyCommit(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: selectedPresetName,
            version: nextVersion
        )
    }

    private mutating func commit(
        presets: [Preset],
        activeFilter: DisplayFilter,
        recentHistory: DisplayFilterPresetHistory,
        selectedPresetName: String?,
        work: inout DisplayFilterPresetWorkBudget
    ) throws {
        let nextVersion = try validatedNextVersion(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: selectedPresetName,
            work: &work
        )
        applyCommit(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: selectedPresetName,
            version: nextVersion
        )
    }

    private func validatedNextVersion(
        presets: [Preset],
        activeFilter: DisplayFilter,
        recentHistory: DisplayFilterPresetHistory,
        selectedPresetName: String?,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> UInt64 {
        guard version < UInt64.max else { throw DisplayFilterPresetsError.versionExhausted }
        try Self.validate(
            presets: presets,
            activeFilter: activeFilter,
            recentHistory: recentHistory,
            selectedPresetName: selectedPresetName,
            limits: limits,
            work: &work
        )
        try Task.checkCancellation()
        return version + 1
    }

    private mutating func applyCommit(
        presets: [Preset],
        activeFilter: DisplayFilter,
        recentHistory: DisplayFilterPresetHistory,
        selectedPresetName: String?,
        version: UInt64
    ) {
        self.presets = presets
        self.activeFilter = activeFilter
        self.recentHistory = recentHistory
        self.selectedPresetName = selectedPresetName
        self.version = version
    }

    private func index(
        forCanonicalKey key: String,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> Int? {
        for (index, preset) in presets.enumerated() {
            _ = try work.consumeUTF8Bytes(in: preset.name)
            try work.consume(1)
            if Self.canonicalNameKey(preset.name) == key { return index }
        }
        return nil
    }

    private static func makePreset(
        name: String,
        filter: DisplayFilter,
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> Preset {
        let canonicalName = try canonicalizedPresetName(
            name,
            maximumUTF8Bytes: limits.maximumPresetNameUTF8Bytes,
            work: &work
        )
        var totalExpressionBytes: Int?
        try validate(
            filter,
            limits: limits,
            totalExpressionBytes: &totalExpressionBytes,
            work: &work
        )
        return Preset(validatedName: canonicalName, filter: filter)
    }

    private static func rollback(
        to filter: DisplayFilter,
        applying apply: @escaping @Sendable (DisplayFilter) throws -> Void
    ) async throws {
        try await Task.detached {
            try apply(filter)
        }.value
    }

    private static func canonicalNameKey(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).precomposedStringWithCanonicalMapping
    }

    private static func exactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    private static func exactlyEqual(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.some(let lhs), .some(let rhs)): exactlyEqual(lhs, rhs)
        default: false
        }
    }

    private static func exactlyEqual(
        _ lhs: DisplayFilterExpression,
        _ rhs: DisplayFilterExpression
    ) -> Bool {
        switch (lhs, rhs) {
        case (.literal(let lhs), .literal(let rhs)),
            (.regularExpression(let lhs), .regularExpression(let rhs)):
            exactlyEqual(lhs, rhs)
        default:
            false
        }
    }

    private static func exactlyEqual(_ lhs: DisplayFilter, _ rhs: DisplayFilter) -> Bool {
        exactlyEqual(lhs.expression, rhs.expression)
            && lhs.caseSensitive == rhs.caseSensitive
            && lhs.invert == rhs.invert
            && lhs.predicate == rhs.predicate
    }

    private static func exactlyEqual(_ lhs: Preset, _ rhs: Preset) -> Bool {
        exactlyEqual(lhs.name, rhs.name) && exactlyEqual(lhs.filter, rhs.filter)
    }

    private static func exactlyEqual(_ lhs: [Preset], _ rhs: [Preset]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy(exactlyEqual)
    }

    private static func exactlyEqual(
        _ lhs: DisplayFilterPresetHistory,
        _ rhs: DisplayFilterPresetHistory
    ) -> Bool {
        guard lhs.capacity == rhs.capacity, lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy(exactlyEqual)
    }

    private static func resolvedSelectedPresetName(
        _ requestedName: String?,
        activeFilter: DisplayFilter,
        presets: [Preset],
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> String? {
        if let requestedName {
            let canonicalName = try canonicalizedPresetName(
                requestedName,
                maximumUTF8Bytes: limits.maximumPresetNameUTF8Bytes,
                work: &work
            )
            let key = canonicalNameKey(canonicalName)
            var selectedPreset: Preset?
            for preset in presets {
                _ = try work.consumeUTF8Bytes(in: preset.name)
                try work.consume(1)
                if canonicalNameKey(preset.name) == key {
                    selectedPreset = preset
                    break
                }
            }
            guard let selectedPreset else {
                throw DisplayFilterPresetsError.presetNotFound(canonicalName)
            }
            try chargeFilterComparison(
                selectedPreset.filter,
                activeFilter,
                limits: limits,
                work: &work
            )
            guard exactlyEqual(selectedPreset.filter, activeFilter) else {
                throw DisplayFilterPresetsError.selectedPresetFilterMismatch(selectedPreset.name)
            }
            return selectedPreset.name
        }
        return nil
    }

    private static func chargeFilterComparison(
        _ lhs: DisplayFilter,
        _ rhs: DisplayFilter,
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget
    ) throws {
        _ = try expressionByteCount(lhs, limits: limits, work: &work)
        try work.consume(1)
        _ = try expressionByteCount(rhs, limits: limits, work: &work)
        try work.consume(1)
    }

    private static func expressionByteCount(
        _ filter: DisplayFilter,
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> Int {
        guard
            let byteCount = try boundedUTF8ByteCount(
                filter.expression.text,
                maximum: limits.maximumExpressionUTF8Bytes,
                work: &work
            )
        else {
            throw DisplayFilterPresetsError.expressionTooLarge(
                maximumBytes: limits.maximumExpressionUTF8Bytes
            )
        }
        return byteCount
    }

    private static func removeExactly(
        _ filter: DisplayFilter,
        from history: inout DisplayFilterPresetHistory,
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> Bool {
        let target = try exactFilterIdentity(filter, limits: limits, work: &work)
        let targetEntries: Set<ExactFilterIdentity> = [target]
        var entries: [DisplayFilter] = []
        var removed = false
        entries.reserveCapacity(history.count)
        for entry in history {
            let identity = try exactFilterIdentity(entry, limits: limits, work: &work)
            if targetEntries.contains(identity) {
                removed = true
            } else {
                entries.append(entry)
            }
        }
        guard removed else { return false }
        history = try makeHistory(
            entries: entries,
            capacity: history.capacity,
            limits: limits,
            work: &work
        )
        return true
    }

    private static func recordExactly(
        _ filter: DisplayFilter,
        in history: DisplayFilterPresetHistory,
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> (history: DisplayFilterPresetHistory, changed: Bool) {
        let target = try exactFilterIdentity(filter, limits: limits, work: &work)
        let targetEntries: Set<ExactFilterIdentity> = [target]
        var iterator = history.makeIterator()
        var entries = [filter]
        var representableEntries: Set<ExactFilterIdentity> = [target]
        entries.reserveCapacity(history.capacity)

        if let first = iterator.next() {
            let identity = try exactFilterIdentity(first, limits: limits, work: &work)
            if targetEntries.contains(identity) {
                return (history, false)
            }
            if representableEntries.insert(identity).inserted,
                entries.count < history.capacity
            {
                entries.append(first)
            }
        }
        while let entry = iterator.next() {
            let identity = try exactFilterIdentity(entry, limits: limits, work: &work)
            if !targetEntries.contains(identity), representableEntries.insert(identity).inserted,
                entries.count < history.capacity
            {
                entries.append(entry)
            }
        }
        return (
            try makeHistory(
                entries: entries,
                capacity: history.capacity,
                limits: limits,
                work: &work
            ),
            true
        )
    }

    private static func exactFilterIdentity(
        _ filter: DisplayFilter,
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> ExactFilterIdentity {
        let expressionBytes = try expressionByteCount(filter, limits: limits, work: &work)
        try work.consume(expressionBytes + 1)
        return ExactFilterIdentity(filter)
    }

    private static func makeHistory(
        entries: [DisplayFilter],
        capacity: Int,
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> DisplayFilterPresetHistory {
        for entry in entries {
            let expressionBytes = try expressionByteCount(entry, limits: limits, work: &work)
            try work.consume(expressionBytes + 1)
        }
        do {
            return try DisplayFilterPresetHistory(entries, capacity: capacity)
        } catch let error as DisplayFilterError {
            throw presetsError(for: error)
        }
    }

    private static func presetsError(for error: DisplayFilterError) -> DisplayFilterPresetsError {
        switch error {
        case .duplicateHistoryEntry:
            .duplicateHistoryEntry
        case .invalidHistoryCapacity(let capacity):
            .invalidHistoryCapacity(capacity)
        case .tooManyHistoryEntries(let maximumEntries):
            .tooManyHistoryEntries(maximumCount: maximumEntries)
        default:
            .invalidFilter(error)
        }
    }

    private static func validate(
        presets: [Preset],
        activeFilter: DisplayFilter,
        recentHistory: DisplayFilterPresetHistory,
        selectedPresetName: String?,
        limits: Limits,
        work: inout DisplayFilterPresetWorkBudget,
        requireCanonicalNames: Bool = false
    ) throws {
        guard presets.count <= limits.maximumPresetCount else {
            throw DisplayFilterPresetsError.tooManyPresets(
                maximumCount: limits.maximumPresetCount
            )
        }
        guard recentHistory.capacity > 0,
            recentHistory.capacity <= limits.maximumHistoryEntries
        else {
            throw DisplayFilterPresetsError.invalidHistoryCapacity(recentHistory.capacity)
        }
        guard recentHistory.count <= recentHistory.capacity,
            recentHistory.count <= limits.maximumHistoryEntries
        else {
            throw DisplayFilterPresetsError.tooManyHistoryEntries(
                maximumCount: Swift.min(
                    recentHistory.capacity,
                    limits.maximumHistoryEntries
                )
            )
        }

        var canonicalNames: Set<String> = []
        var totalNameBytes = 0
        for preset in presets {
            let canonical = try canonicalizedPresetName(
                preset.name,
                maximumUTF8Bytes: limits.maximumPresetNameUTF8Bytes,
                work: &work
            )
            if requireCanonicalNames, !exactlyEqual(canonical, preset.name) {
                throw DisplayFilterPresetsError.nonCanonicalPresetName(preset.name)
            }
            let byteCount = try work.consumeUTF8Bytes(in: canonical)
            try work.consume(1)
            guard byteCount <= limits.maximumTotalPresetNameUTF8Bytes - totalNameBytes
            else {
                throw DisplayFilterPresetsError.totalPresetNamesTooLarge(
                    maximumBytes: limits.maximumTotalPresetNameUTF8Bytes
                )
            }
            totalNameBytes += byteCount
            guard canonicalNames.insert(canonicalNameKey(canonical)).inserted else {
                throw DisplayFilterPresetsError.duplicatePresetName(canonical)
            }
        }

        if let selectedPresetName {
            let canonical = try canonicalizedPresetName(
                selectedPresetName,
                maximumUTF8Bytes: limits.maximumPresetNameUTF8Bytes,
                work: &work
            )
            if requireCanonicalNames, !exactlyEqual(canonical, selectedPresetName) {
                throw DisplayFilterPresetsError.nonCanonicalPresetName(selectedPresetName)
            }
            var selectedPreset: Preset?
            for preset in presets {
                _ = try work.consumeUTF8Bytes(in: preset.name)
                try work.consume(1)
                if exactlyEqual(preset.name, selectedPresetName) {
                    selectedPreset = preset
                    break
                }
            }
            guard let selectedPreset else {
                throw DisplayFilterPresetsError.presetNotFound(selectedPresetName)
            }
            try chargeFilterComparison(
                selectedPreset.filter,
                activeFilter,
                limits: limits,
                work: &work
            )
            guard exactlyEqual(selectedPreset.filter, activeFilter) else {
                throw DisplayFilterPresetsError.selectedPresetFilterMismatch(selectedPresetName)
            }
        }

        var totalExpressionBytes: Int? = 0
        try validate(
            activeFilter,
            limits: limits,
            totalExpressionBytes: &totalExpressionBytes,
            work: &work
        )
        for preset in presets {
            try validate(
                preset.filter,
                limits: limits,
                totalExpressionBytes: &totalExpressionBytes,
                work: &work
            )
        }
        var historyEntries: Set<ExactFilterIdentity> = []
        historyEntries.reserveCapacity(recentHistory.count)
        for filter in recentHistory {
            let identity = try exactFilterIdentity(filter, limits: limits, work: &work)
            guard historyEntries.insert(identity).inserted else {
                throw DisplayFilterPresetsError.duplicateHistoryEntry
            }
            try validate(
                filter,
                limits: limits,
                totalExpressionBytes: &totalExpressionBytes,
                work: &work
            )
        }
    }

    fileprivate static func validate(
        _ filter: DisplayFilter,
        limits: Limits,
        totalExpressionBytes: inout Int?,
        work: inout DisplayFilterPresetWorkBudget
    ) throws {
        guard
            let expressionBytes = try boundedUTF8ByteCount(
                filter.expression.text,
                maximum: limits.maximumExpressionUTF8Bytes,
                work: &work
            )
        else {
            throw DisplayFilterPresetsError.expressionTooLarge(
                maximumBytes: limits.maximumExpressionUTF8Bytes
            )
        }
        try work.consume(1)
        if let total = totalExpressionBytes {
            guard expressionBytes <= limits.maximumTotalExpressionUTF8Bytes - total else {
                throw DisplayFilterPresetsError.totalExpressionsTooLarge(
                    maximumBytes: limits.maximumTotalExpressionUTF8Bytes
                )
            }
            totalExpressionBytes = total + expressionBytes
        }
        do {
            try filter.validate()
        } catch let error as DisplayFilterError {
            throw DisplayFilterPresetsError.invalidFilter(error)
        }
        try Task.checkCancellation()
    }

    private static func boundedUTF8ByteCount(
        _ value: String,
        maximum: Int,
        work: inout DisplayFilterPresetWorkBudget
    ) throws -> Int? {
        var count = 0
        var pendingWork = 0
        for _ in value.utf8 {
            guard count < maximum else {
                try work.consume(pendingWork + 1)
                return nil
            }
            count += 1
            pendingWork += 1
            if pendingWork == 4_096 || pendingWork > work.remaining {
                try work.consume(pendingWork)
                pendingWork = 0
            }
        }
        if pendingWork > 0 {
            try work.consume(pendingWork)
        } else {
            try Task.checkCancellation()
        }
        return count
    }

}

private struct ExactFilterIdentity: Hashable {
    let filter: DisplayFilter

    init(_ filter: DisplayFilter) {
        self.filter = filter
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.filter.caseSensitive == rhs.filter.caseSensitive,
            lhs.filter.invert == rhs.filter.invert,
            lhs.filter.predicate == rhs.filter.predicate
        else {
            return false
        }
        switch (lhs.filter.expression, rhs.filter.expression) {
        case (.literal(let lhs), .literal(let rhs)),
            (.regularExpression(let lhs), .regularExpression(let rhs)):
            return lhs.utf8.elementsEqual(rhs.utf8)
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch filter.expression {
        case .literal(let text):
            hasher.combine(0 as UInt8)
            hasher.combine(text.utf8.count)
            for byte in text.utf8 { hasher.combine(byte) }
        case .regularExpression(let text):
            hasher.combine(1 as UInt8)
            hasher.combine(text.utf8.count)
            for byte in text.utf8 { hasher.combine(byte) }
        }
        hasher.combine(filter.caseSensitive)
        hasher.combine(filter.invert)
        hasher.combine(filter.predicate.rawValue)
    }
}

private struct DisplayFilterPresetWorkBudget {
    let maximum: Int
    private(set) var completed = 0

    var remaining: Int { maximum - completed }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximum - completed else {
            throw DisplayFilterPresetsError.workLimitExceeded(maximumWork: maximum)
        }
        completed += amount
        try Task.checkCancellation()
    }

    mutating func consumeUTF8Bytes(in value: String) throws -> Int {
        var count = 0
        var pendingWork = 0
        for _ in value.utf8 {
            count += 1
            pendingWork += 1
            if pendingWork == 4_096 || pendingWork > remaining {
                try consume(pendingWork)
                pendingWork = 0
            }
        }
        try consume(pendingWork)
        return count
    }
}

private struct DisplayFilterPresetOutputBudget {
    let maximum: Int
    private(set) var count = 0
    private(set) var work: DisplayFilterPresetWorkBudget

    init(maximum: Int, work: DisplayFilterPresetWorkBudget) {
        self.maximum = maximum
        self.work = work
    }

    mutating func add(_ filter: DisplayFilter) throws {
        try addASCII("{\"caseSensitive\":")
        try addASCII(filter.caseSensitive ? "true" : "false")
        try addASCII(",\"expression\":{\"kind\":")
        switch filter.expression {
        case .literal(let text):
            try addJSONString("literal")
            try addASCII(",\"text\":")
            try addJSONString(text)
        case .regularExpression(let text):
            try addJSONString("regularExpression")
            try addASCII(",\"text\":")
            try addJSONString(text)
        }
        try addASCII("},\"invert\":")
        try addASCII(filter.invert ? "true" : "false")
        try addASCII(",\"predicate\":")
        try addJSONString(filter.predicate.rawValue)
        try addASCII("}")
    }

    mutating func addASCII(_ value: String) throws {
        try addBytes(value.utf8.count)
    }

    mutating func addJSONString(_ value: String) throws {
        try addBytes(1)
        var pendingBytes = 0
        for scalar in value.unicodeScalars {
            let byteCount: Int
            switch scalar.value {
            case 0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x22, 0x5C:
                byteCount = 2
            case 0x00...0x1F:
                byteCount = 6
            case 0x20...0x7F:
                byteCount = 1
            case 0x80...0x7FF:
                byteCount = 2
            case 0x800...0xFFFF:
                byteCount = 3
            default:
                byteCount = 4
            }
            guard byteCount <= maximum - count - pendingBytes else {
                throw DisplayFilterPresetsError.outputTooLarge(maximumBytes: maximum)
            }
            pendingBytes += byteCount
            if pendingBytes >= 4_096 || pendingBytes > work.remaining {
                try addBytes(pendingBytes)
                pendingBytes = 0
            }
        }
        try addBytes(pendingBytes + 1)
    }

    private mutating func addBytes(_ addedCount: Int) throws {
        guard addedCount >= 0, addedCount <= maximum - count else {
            throw DisplayFilterPresetsError.outputTooLarge(maximumBytes: maximum)
        }
        try work.consume(addedCount)
        count += addedCount
    }
}

private struct DisplayFilterPresetsWireState: Codable {
    let schemaVersion: Int
    let stateVersion: UInt64
    let activeFilter: DisplayFilterPresetWireFilter
    let historyCapacity: Int
    let recentHistory: [DisplayFilterPresetWireFilter]
    let presets: [DisplayFilterPresetWirePreset]
    let selectedPresetName: String?

    private static let version1Fields: Set<String> = [
        "schemaVersion", "stateVersion", "activeFilter", "historyCapacity",
        "recentHistory", "presets"
    ]
    private static let version2Fields: Set<String> = [
        "schemaVersion", "stateVersion", "activeFilter", "historyCapacity",
        "recentHistory", "presets", "selectedPresetName"
    ]

    init(_ state: DisplayFilterPresets) {
        schemaVersion = DisplayFilterPresets.currentSchemaVersion
        stateVersion = state.version
        activeFilter = DisplayFilterPresetWireFilter(state.activeFilter)
        historyCapacity = state.recentHistory.capacity
        recentHistory = state.recentHistory.map(DisplayFilterPresetWireFilter.init)
        presets = state.presets.map(DisplayFilterPresetWirePreset.init)
        selectedPresetName = state.selectedPresetName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DisplayFilterPresetCodingKey.self)
        schemaVersion = try container.decode(
            Int.self,
            forKey: DisplayFilterPresetCodingKey("schemaVersion")
        )
        guard schemaVersion == 1 || schemaVersion == DisplayFilterPresets.currentSchemaVersion else {
            throw DisplayFilterPresetsError.unsupportedSchemaVersion(schemaVersion)
        }
        try requireDisplayFilterPresetFields(
            container,
            expected: schemaVersion == 1 ? Self.version1Fields : Self.version2Fields
        )
        stateVersion = try container.decode(
            UInt64.self,
            forKey: DisplayFilterPresetCodingKey("stateVersion")
        )
        activeFilter = try container.decode(
            DisplayFilterPresetWireFilter.self,
            forKey: DisplayFilterPresetCodingKey("activeFilter")
        )
        historyCapacity = try container.decode(
            Int.self,
            forKey: DisplayFilterPresetCodingKey("historyCapacity")
        )

        var historyContainer = try container.nestedUnkeyedContainer(
            forKey: DisplayFilterPresetCodingKey("recentHistory")
        )
        var decodedHistory: [DisplayFilterPresetWireFilter] = []
        decodedHistory.reserveCapacity(
            min(historyContainer.count ?? 0, DisplayFilterPresetHistory.maximumCapacity)
        )
        while !historyContainer.isAtEnd {
            guard decodedHistory.count < DisplayFilterPresetHistory.maximumCapacity else {
                throw DisplayFilterPresetsError.tooManyHistoryEntries(
                    maximumCount: DisplayFilterPresetHistory.maximumCapacity
                )
            }
            decodedHistory.append(try historyContainer.decode(DisplayFilterPresetWireFilter.self))
        }
        recentHistory = decodedHistory

        var presetsContainer = try container.nestedUnkeyedContainer(
            forKey: DisplayFilterPresetCodingKey("presets")
        )
        var decodedPresets: [DisplayFilterPresetWirePreset] = []
        decodedPresets.reserveCapacity(
            min(presetsContainer.count ?? 0, DisplayFilterPresets.maximumPresetCount)
        )
        while !presetsContainer.isAtEnd {
            guard decodedPresets.count < DisplayFilterPresets.maximumPresetCount else {
                throw DisplayFilterPresetsError.tooManyPresets(
                    maximumCount: DisplayFilterPresets.maximumPresetCount
                )
            }
            decodedPresets.append(try presetsContainer.decode(DisplayFilterPresetWirePreset.self))
        }
        presets = decodedPresets
        selectedPresetName =
            schemaVersion == 1
            ? nil
            : try container.decodeIfPresent(
                String.self,
                forKey: DisplayFilterPresetCodingKey("selectedPresetName")
            )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DisplayFilterPresetCodingKey.self)
        try container.encode(
            schemaVersion,
            forKey: DisplayFilterPresetCodingKey("schemaVersion")
        )
        try container.encode(
            stateVersion,
            forKey: DisplayFilterPresetCodingKey("stateVersion")
        )
        try container.encode(
            activeFilter,
            forKey: DisplayFilterPresetCodingKey("activeFilter")
        )
        try container.encode(
            historyCapacity,
            forKey: DisplayFilterPresetCodingKey("historyCapacity")
        )
        try container.encode(
            recentHistory,
            forKey: DisplayFilterPresetCodingKey("recentHistory")
        )
        try container.encode(presets, forKey: DisplayFilterPresetCodingKey("presets"))
        try container.encode(
            selectedPresetName,
            forKey: DisplayFilterPresetCodingKey("selectedPresetName")
        )
    }
}

private struct DisplayFilterPresetWirePreset: Codable {
    let name: String
    let filter: DisplayFilterPresetWireFilter

    private static let fields: Set<String> = ["name", "filter"]

    init(_ preset: NamedDisplayFilterPreset) {
        name = preset.name
        filter = DisplayFilterPresetWireFilter(preset.filter)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DisplayFilterPresetCodingKey.self)
        try requireDisplayFilterPresetFields(container, expected: Self.fields)
        name = try container.decode(
            String.self,
            forKey: DisplayFilterPresetCodingKey("name")
        )
        filter = try container.decode(
            DisplayFilterPresetWireFilter.self,
            forKey: DisplayFilterPresetCodingKey("filter")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DisplayFilterPresetCodingKey.self)
        try container.encode(name, forKey: DisplayFilterPresetCodingKey("name"))
        try container.encode(filter, forKey: DisplayFilterPresetCodingKey("filter"))
    }
}

private struct DisplayFilterPresetWireFilter: Codable {
    let expression: DisplayFilterPresetWireExpression
    let caseSensitive: Bool
    let invert: Bool
    let predicate: DisplayFilterRowPredicate

    private static let fields: Set<String> = [
        "expression", "caseSensitive", "invert", "predicate"
    ]

    init(_ filter: DisplayFilter) {
        expression = DisplayFilterPresetWireExpression(filter.expression)
        caseSensitive = filter.caseSensitive
        invert = filter.invert
        predicate = filter.predicate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DisplayFilterPresetCodingKey.self)
        try requireDisplayFilterPresetFields(container, expected: Self.fields)
        expression = try container.decode(
            DisplayFilterPresetWireExpression.self,
            forKey: DisplayFilterPresetCodingKey("expression")
        )
        caseSensitive = try container.decode(
            Bool.self,
            forKey: DisplayFilterPresetCodingKey("caseSensitive")
        )
        invert = try container.decode(
            Bool.self,
            forKey: DisplayFilterPresetCodingKey("invert")
        )
        predicate = try container.decode(
            DisplayFilterRowPredicate.self,
            forKey: DisplayFilterPresetCodingKey("predicate")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DisplayFilterPresetCodingKey.self)
        try container.encode(expression, forKey: DisplayFilterPresetCodingKey("expression"))
        try container.encode(
            caseSensitive,
            forKey: DisplayFilterPresetCodingKey("caseSensitive")
        )
        try container.encode(invert, forKey: DisplayFilterPresetCodingKey("invert"))
        try container.encode(predicate, forKey: DisplayFilterPresetCodingKey("predicate"))
    }

    var filter: DisplayFilter {
        DisplayFilter(
            expression: expression.expression,
            caseSensitive: caseSensitive,
            invert: invert,
            predicate: predicate
        )
    }
}

private struct DisplayFilterPresetWireExpression: Codable {
    let kind: String
    let text: String

    private static let fields: Set<String> = ["kind", "text"]

    init(_ expression: DisplayFilterExpression) {
        switch expression {
        case .literal(let text):
            kind = "literal"
            self.text = text
        case .regularExpression(let text):
            kind = "regularExpression"
            self.text = text
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DisplayFilterPresetCodingKey.self)
        try requireDisplayFilterPresetFields(container, expected: Self.fields)
        kind = try container.decode(
            String.self,
            forKey: DisplayFilterPresetCodingKey("kind")
        )
        guard kind == "literal" || kind == "regularExpression" else {
            throw DisplayFilterPresetsError.unknownExpressionKind(kind)
        }
        text = try container.decode(
            String.self,
            forKey: DisplayFilterPresetCodingKey("text")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DisplayFilterPresetCodingKey.self)
        try container.encode(kind, forKey: DisplayFilterPresetCodingKey("kind"))
        try container.encode(text, forKey: DisplayFilterPresetCodingKey("text"))
    }

    var expression: DisplayFilterExpression {
        kind == "literal" ? .literal(text) : .regularExpression(text)
    }
}

private struct DisplayFilterPresetCodingKey: CodingKey, Hashable {
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

private func requireDisplayFilterPresetFields<Value>(
    _ container: KeyedDecodingContainer<Value>,
    expected: Set<String>
) throws where Value: CodingKey {
    let actual = Set(container.allKeys.map(\.stringValue))
    if let unknown = actual.subtracting(expected).sorted().first {
        throw DisplayFilterPresetsError.unknownField(unknown)
    }
    guard actual == expected else {
        throw DecodingError.dataCorrupted(
            .init(codingPath: container.codingPath, debugDescription: "Missing persistence field.")
        )
    }
}

private struct DisplayFilterPresetsJSONScanner {
    private let bytes: UnsafeBufferPointer<UInt8>
    private let maximumStringUTF8Bytes: Int
    private let maximumTotalStringUTF8Bytes: Int
    private var index = 0
    private var valueCount = 0
    private var totalStringUTF8Bytes = 0
    private var nextCancellationIndex = 0

    init(bytes: UnsafeBufferPointer<UInt8>, limits: DisplayFilterPresetLimits) {
        self.bytes = bytes
        maximumStringUTF8Bytes = max(
            limits.maximumPresetNameUTF8Bytes,
            limits.maximumExpressionUTF8Bytes,
            256
        )
        maximumTotalStringUTF8Bytes = min(
            limits.maximumInputBytes,
            limits.maximumTotalPresetNameUTF8Bytes
                + limits.maximumTotalExpressionUTF8Bytes + 64 * 1024
        )
    }

    mutating func validate() throws {
        try skipWhitespace()
        try parseValue(depth: 0)
        try skipWhitespace()
        guard index == bytes.count else { throw DisplayFilterPresetsError.invalidJSON }
    }

    private mutating func parseValue(depth: Int) throws {
        guard valueCount < DisplayFilterPresets.maximumJSONValueCount else {
            throw DisplayFilterPresetsError.tooManyJSONValues(
                maximumValues: DisplayFilterPresets.maximumJSONValueCount
            )
        }
        valueCount += 1
        try checkCancellation()
        guard let byte = currentByte else { throw DisplayFilterPresetsError.invalidJSON }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString(maximumBytes: maximumStringUTF8Bytes)
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw DisplayFilterPresetsError.invalidJSON
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
            try incrementContainerCount(&elementCount)
            let key = try parseString(
                maximumBytes: DisplayFilterPresets.maximumJSONKeyUTF8Bytes
            )
            guard keys.insert(key).inserted else {
                throw DisplayFilterPresetsError.duplicateJSONKey(key)
            }
            try skipWhitespace()
            guard consume(0x3A) else { throw DisplayFilterPresetsError.invalidJSON }
            try skipWhitespace()
            try parseValue(depth: depth)
            try skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw DisplayFilterPresetsError.invalidJSON }
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
            try incrementContainerCount(&elementCount)
            try parseValue(depth: depth)
            try skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw DisplayFilterPresetsError.invalidJSON }
            try skipWhitespace()
        }
    }

    private mutating func parseString(maximumBytes: Int) throws -> String {
        let start = index
        guard consume(0x22) else { throw DisplayFilterPresetsError.invalidJSON }
        while let byte = currentByte {
            try checkCancellation()
            index += 1
            switch byte {
            case 0x22:
                let decoded: String
                do {
                    decoded = try JSONDecoder().decode(
                        String.self,
                        from: Data(bytes[start..<index])
                    )
                } catch {
                    throw DisplayFilterPresetsError.invalidJSON
                }
                let byteCount = decoded.utf8.count
                guard byteCount <= maximumBytes else {
                    throw DisplayFilterPresetsError.jsonStringTooLarge(
                        maximumBytes: maximumBytes
                    )
                }
                guard byteCount <= maximumTotalStringUTF8Bytes - totalStringUTF8Bytes
                else {
                    throw DisplayFilterPresetsError.jsonStringTooLarge(
                        maximumBytes: maximumTotalStringUTF8Bytes
                    )
                }
                totalStringUTF8Bytes += byteCount
                return decoded
            case 0x00...0x1F:
                throw DisplayFilterPresetsError.invalidJSON
            case 0x5C:
                try parseEscape()
            default:
                break
            }
        }
        throw DisplayFilterPresetsError.invalidJSON
    }

    private mutating func parseEscape() throws {
        guard let escaped = currentByte else { throw DisplayFilterPresetsError.invalidJSON }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74:
            return
        case 0x75:
            for _ in 0..<4 {
                guard let byte = currentByte, Self.hexValue(byte) != nil else {
                    throw DisplayFilterPresetsError.invalidJSON
                }
                index += 1
            }
        default:
            throw DisplayFilterPresetsError.invalidJSON
        }
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = try consumeNumberByte(0x2D, start: start)
        guard let first = currentByte else { throw DisplayFilterPresetsError.invalidJSON }
        if first == 0x30 {
            try advanceNumberByte(start: start)
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw DisplayFilterPresetsError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw DisplayFilterPresetsError.invalidJSON
            }
            repeat {
                try advanceNumberByte(start: start)
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if try consumeNumberByte(0x2E, start: start) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw DisplayFilterPresetsError.invalidJSON
            }
            repeat {
                try advanceNumberByte(start: start)
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        var hasExponent = try consumeNumberByte(0x65, start: start)
        if !hasExponent {
            hasExponent = try consumeNumberByte(0x45, start: start)
        }
        if hasExponent {
            if try !consumeNumberByte(0x2B, start: start) {
                _ = try consumeNumberByte(0x2D, start: start)
            }
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw DisplayFilterPresetsError.invalidJSON
            }
            repeat {
                try advanceNumberByte(start: start)
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
    }

    private mutating func consumeNumberByte(_ byte: UInt8, start: Int) throws -> Bool {
        guard currentByte == byte else { return false }
        try advanceNumberByte(start: start)
        return true
    }

    private mutating func advanceNumberByte(start: Int) throws {
        guard index - start < DisplayFilterPresets.maximumJSONNumberBytes else {
            throw DisplayFilterPresetsError.jsonNumberTooLarge(
                maximumBytes: DisplayFilterPresets.maximumJSONNumberBytes
            )
        }
        index += 1
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else {
            throw DisplayFilterPresetsError.invalidJSON
        }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw DisplayFilterPresetsError.invalidJSON }
            index += 1
        }
    }

    private mutating func incrementContainerCount(_ count: inout Int) throws {
        guard count < DisplayFilterPresets.maximumJSONContainerElements else {
            throw DisplayFilterPresetsError.jsonContainerTooLarge(
                maximumElements: DisplayFilterPresets.maximumJSONContainerElements
            )
        }
        count += 1
        try checkCancellation()
    }

    private func validateDepth(_ depth: Int) throws {
        guard depth <= DisplayFilterPresets.maximumJSONNestingDepth else {
            throw DisplayFilterPresetsError.jsonNestingTooDeep(
                maximumDepth: DisplayFilterPresets.maximumJSONNestingDepth
            )
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            try checkCancellation()
            index += 1
        }
    }

    private mutating func checkCancellation() throws {
        guard index >= nextCancellationIndex else { return }
        try Task.checkCancellation()
        nextCancellationIndex = index + 4_096
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
