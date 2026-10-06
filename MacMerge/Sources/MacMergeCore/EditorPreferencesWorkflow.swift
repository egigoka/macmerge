import Foundation

/// UI-independent preference editing, persistence, and application planning for editor settings.
public enum EditorPreferencesWorkflow: Sendable {
    public static let currentPersistenceVersion = 1

    public enum Page: String, CaseIterable, Codable, Hashable, Sendable {
        case general
        case compareAndMerge
        case syntax
    }

    public enum TabInsertion: String, CaseIterable, Codable, Hashable, Sendable {
        case tabs
        case spaces
    }

    public enum SelectedDifferenceCopyGranularity: String, CaseIterable, Codable, Hashable,
        Sendable
    {
        case difference
        case inlineDifference
        case line
        case character
    }

    public enum LineDifferenceGranularity: String, CaseIterable, Codable, Hashable, Sendable {
        case character
        case word
    }

    public enum WordBreakMode: String, CaseIterable, Codable, Hashable, Sendable {
        case whitespace
        case whitespaceOrCustomCharacters
    }

    public struct EditingPreferences: Codable, Equatable, Hashable, Sendable {
        public static let minimumTabWidth = 1
        public static let maximumTabWidth = 64
        public static let `default` = EditingPreferences(validatedTabWidth: 4, tabInsertion: .tabs)

        public let tabWidth: Int
        public let tabInsertion: TabInsertion

        public init(tabWidth: Int = 4, tabInsertion: TabInsertion = .tabs) throws {
            guard (Self.minimumTabWidth...Self.maximumTabWidth).contains(tabWidth) else {
                throw Error.invalidTabWidth(tabWidth)
            }
            self.tabWidth = tabWidth
            self.tabInsertion = tabInsertion
        }

        fileprivate init(validatedTabWidth tabWidth: Int, tabInsertion: TabInsertion) {
            self.tabWidth = tabWidth
            self.tabInsertion = tabInsertion
        }

        private enum CodingKeys: String, CodingKey {
            case tabInsertion
            case tabWidth
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                tabWidth: container.decode(Int.self, forKey: .tabWidth),
                tabInsertion: container.decode(TabInsertion.self, forKey: .tabInsertion)
            )
        }

        fileprivate func validate() throws {
            guard (Self.minimumTabWidth...Self.maximumTabWidth).contains(tabWidth) else {
                throw Error.invalidTabWidth(tabWidth)
            }
        }
    }

    public struct CompareAndMergePreferences: Codable, Equatable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public static let `default` = CompareAndMergePreferences(
            uncheckedAutomaticRescanAfterEdit: false,
            copyGranularity: .character,
            lineDifferenceGranularity: .word,
            wordBreakMode: .whitespace,
            wordBreakCharacters: "",
            automaticMergeDestination: .middle
        )

        public let automaticRescanAfterEdit: Bool
        public let copyGranularity: SelectedDifferenceCopyGranularity
        public let lineDifferenceGranularity: LineDifferenceGranularity
        public let wordBreakMode: WordBreakMode
        public let wordBreakCharacters: String
        public let automaticMergeDestination: MergeCommandPolicy.Side

        public init(
            automaticRescanAfterEdit: Bool = false,
            copyGranularity: SelectedDifferenceCopyGranularity = .character,
            lineDifferenceGranularity: LineDifferenceGranularity = .word,
            wordBreakMode: WordBreakMode = .whitespace,
            wordBreakCharacters: String = "",
            automaticMergeDestination: MergeCommandPolicy.Side = .middle
        ) throws {
            self.automaticRescanAfterEdit = automaticRescanAfterEdit
            self.copyGranularity = copyGranularity
            self.lineDifferenceGranularity = lineDifferenceGranularity
            self.wordBreakMode = wordBreakMode
            self.wordBreakCharacters = try normalizedBoundedString(
                wordBreakCharacters,
                field: .wordBreakCharacters,
                maximumUTF8Bytes: Limits.hardMaximumStringUTF8Bytes,
                allowsEmpty: true
            )
            self.automaticMergeDestination = automaticMergeDestination
            try validate(maximumWordBreakCharactersUTF8Bytes: Limits.hardMaximumStringUTF8Bytes)
        }

        fileprivate init(
            uncheckedAutomaticRescanAfterEdit automaticRescanAfterEdit: Bool,
            copyGranularity: SelectedDifferenceCopyGranularity,
            lineDifferenceGranularity: LineDifferenceGranularity,
            wordBreakMode: WordBreakMode,
            wordBreakCharacters: String,
            automaticMergeDestination: MergeCommandPolicy.Side
        ) {
            self.automaticRescanAfterEdit = automaticRescanAfterEdit
            self.copyGranularity = copyGranularity
            self.lineDifferenceGranularity = lineDifferenceGranularity
            self.wordBreakMode = wordBreakMode
            self.wordBreakCharacters = wordBreakCharacters
            self.automaticMergeDestination = automaticMergeDestination
        }

        public var description: String {
            "EditorPreferencesWorkflow.CompareAndMergePreferences(rescan: \(automaticRescanAfterEdit), copy: \(copyGranularity.rawValue), line: \(lineDifferenceGranularity.rawValue), merge: \(automaticMergeDestination), wordBreakCharacters: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "automaticRescanAfterEdit": automaticRescanAfterEdit,
                    "copyGranularity": copyGranularity,
                    "lineDifferenceGranularity": lineDifferenceGranularity,
                    "wordBreakMode": wordBreakMode,
                    "automaticMergeDestination": automaticMergeDestination,
                    "wordBreakCharacters": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        fileprivate func validate(maximumWordBreakCharactersUTF8Bytes: Int) throws {
            try validateBoundedString(
                wordBreakCharacters,
                field: .wordBreakCharacters,
                maximumUTF8Bytes: maximumWordBreakCharactersUTF8Bytes,
                allowsEmpty: true
            )
            if wordBreakMode == .whitespace, !wordBreakCharacters.isEmpty {
                throw Error.inconsistentWordBreakCharacters
            }
        }

        private enum CodingKeys: String, CodingKey {
            case automaticMergeDestination
            case automaticRescanAfterEdit
            case copyGranularity
            case lineDifferenceGranularity
            case wordBreakCharacters
            case wordBreakMode
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                automaticRescanAfterEdit: container.decode(
                    Bool.self,
                    forKey: .automaticRescanAfterEdit
                ),
                copyGranularity: container.decode(
                    SelectedDifferenceCopyGranularity.self,
                    forKey: .copyGranularity
                ),
                lineDifferenceGranularity: container.decode(
                    LineDifferenceGranularity.self,
                    forKey: .lineDifferenceGranularity
                ),
                wordBreakMode: container.decode(WordBreakMode.self, forKey: .wordBreakMode),
                wordBreakCharacters: container.decode(
                    String.self,
                    forKey: .wordBreakCharacters
                ),
                automaticMergeDestination: container.decode(
                    MergeSideWire.self,
                    forKey: .automaticMergeDestination
                ).side
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(
                MergeSideWire(automaticMergeDestination),
                forKey: .automaticMergeDestination
            )
            try container.encode(automaticRescanAfterEdit, forKey: .automaticRescanAfterEdit)
            try container.encode(copyGranularity, forKey: .copyGranularity)
            try container.encode(lineDifferenceGranularity, forKey: .lineDifferenceGranularity)
            try container.encode(wordBreakCharacters, forKey: .wordBreakCharacters)
            try container.encode(wordBreakMode, forKey: .wordBreakMode)
        }

        private enum MergeSideWire: String, Codable {
            case left
            case middle
            case right

            init(_ side: MergeCommandPolicy.Side) {
                switch side {
                case .left: self = .left
                case .middle: self = .middle
                case .right: self = .right
                }
            }

            var side: MergeCommandPolicy.Side {
                switch self {
                case .left: .left
                case .middle: .middle
                case .right: .right
                }
            }
        }
    }

    public struct ColorSchemeIdentifier: Codable, Comparable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public static let maximumUTF8Bytes = 128
        public static let standard = ColorSchemeIdentifier(uncheckedRawValue: "macmerge.standard")
        public static let monochrome = ColorSchemeIdentifier(uncheckedRawValue: "macmerge.monochrome")

        public let rawValue: String

        public init(_ rawValue: String) throws {
            try validatePortableIdentifier(
                rawValue,
                field: .colorSchemeIdentifier,
                maximumUTF8Bytes: Self.maximumUTF8Bytes,
                allowsEditorColorSchemeSeparators: true
            )
            self.rawValue = rawValue
        }

        fileprivate init(uncheckedRawValue: String) {
            rawValue = uncheckedRawValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            try self.init(container.decode(String.self))
        }

        public func encode(to encoder: Encoder) throws {
            try validatePortableIdentifier(
                rawValue,
                field: .colorSchemeIdentifier,
                maximumUTF8Bytes: Self.maximumUTF8Bytes,
                allowsEditorColorSchemeSeparators: true
            )
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public var description: String { "<redacted>" }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["rawValue": "<redacted>"],
                displayStyle: .struct
            )
        }

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue.utf8.lexicographicallyPrecedes(right.rawValue.utf8)
        }
    }

    public struct ColorSchemeSelection: Codable, Equatable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public static let `default` = ColorSchemeSelection(selectedIdentifier: .standard)

        public let selectedIdentifier: ColorSchemeIdentifier

        public init(selectedIdentifier: ColorSchemeIdentifier = .standard) {
            self.selectedIdentifier = selectedIdentifier
        }

        public init(selectedScheme: EditorColorScheme) throws {
            try selectedScheme.validate()
            selectedIdentifier = try ColorSchemeIdentifier(selectedScheme.identifier)
        }

        public var description: String {
            "EditorPreferencesWorkflow.ColorSchemeSelection(identifier: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["selectedIdentifier": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct SyntaxPreferences: Equatable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public static let `default` = SyntaxPreferences(
            isHighlightingEnabled: true,
            selection: .none
        )

        public let isHighlightingEnabled: Bool
        public let selection: SyntaxSchemeSelection

        public init(
            isHighlightingEnabled: Bool = true,
            selection: SyntaxSchemeSelection = .none
        ) {
            self.isHighlightingEnabled = isHighlightingEnabled
            self.selection = selection
        }

        public var description: String {
            "EditorPreferencesWorkflow.SyntaxPreferences(enabled: \(isHighlightingEnabled), selection: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "isHighlightingEnabled": isHighlightingEnabled,
                    "selection": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Revision: Codable, Comparable, Hashable, Sendable {
        public let lineage: UInt64
        public let generation: UInt64

        public init(lineage: UInt64, generation: UInt64) {
            self.lineage = lineage
            self.generation = generation
        }

        fileprivate func advanced() throws -> Revision {
            guard generation < UInt64.max else { throw Error.revisionExhausted(lineage: lineage) }
            return Revision(lineage: lineage, generation: generation + 1)
        }

        public static func < (left: Self, right: Self) -> Bool {
            left.lineage == right.lineage
                ? left.generation < right.generation
                : left.lineage < right.lineage
        }
    }

    public struct Limits: Codable, Equatable, Hashable, Sendable {
        public static let hardMaximumPersistenceBytes = 64 * 1_024
        public static let hardMaximumColorSchemeCount = 4_096
        public static let hardMaximumPersistenceItemCount = 4_096
        public static let hardMaximumJSONDepth = 16
        public static let hardMaximumStringUTF8Bytes = 16 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 1 * 1_024 * 1_024
        public static let hardMaximumWorkUnits = 16 * 1_024 * 1_024
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumPersistenceBytes: Int
        public let maximumColorSchemeCount: Int
        public let maximumPersistenceItemCount: Int
        public let maximumJSONDepth: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumPersistenceBytes: Int = 16 * 1_024,
            maximumColorSchemeCount: Int = 512,
            maximumPersistenceItemCount: Int = 256,
            maximumJSONDepth: Int = 8,
            maximumStringUTF8Bytes: Int = 4 * 1_024,
            maximumTotalStringUTF8Bytes: Int = 256 * 1_024,
            maximumWorkUnits: Int = 1 * 1_024 * 1_024,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumPersistenceBytes = maximumPersistenceBytes
            self.maximumColorSchemeCount = maximumColorSchemeCount
            self.maximumPersistenceItemCount = maximumPersistenceItemCount
            self.maximumJSONDepth = maximumJSONDepth
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (1...Self.hardMaximumPersistenceBytes).contains(maximumPersistenceBytes)
            else { throw Error.invalidLimit(.persistenceBytes) }
            guard (1...Self.hardMaximumColorSchemeCount).contains(maximumColorSchemeCount)
            else { throw Error.invalidLimit(.colorSchemeCount) }
            guard
                (1...Self.hardMaximumPersistenceItemCount).contains(
                    maximumPersistenceItemCount
                )
            else { throw Error.invalidLimit(.persistenceItemCount) }
            guard (1...Self.hardMaximumJSONDepth).contains(maximumJSONDepth)
            else { throw Error.invalidLimit(.jsonDepth) }
            guard (1...Self.hardMaximumStringUTF8Bytes).contains(maximumStringUTF8Bytes)
            else { throw Error.invalidLimit(.stringUTF8Bytes) }
            guard
                (maximumStringUTF8Bytes...Self.hardMaximumTotalStringUTF8Bytes).contains(
                    maximumTotalStringUTF8Bytes
                )
            else { throw Error.invalidLimit(.totalStringUTF8Bytes) }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits)
            else { throw Error.invalidLimit(.workUnits) }
            guard
                (1...Self.hardMaximumCancellationCheckInterval).contains(
                    cancellationCheckInterval
                )
            else { throw Error.invalidLimit(.cancellationCheckInterval) }
        }
    }

    public enum Limit: String, CaseIterable, Codable, Hashable, Sendable {
        case persistenceBytes
        case colorSchemeCount
        case persistenceItemCount
        case jsonDepth
        case stringUTF8Bytes
        case totalStringUTF8Bytes
        case workUnits
        case cancellationCheckInterval
    }

    public enum StringField: String, CaseIterable, Codable, Hashable, Sendable {
        case fontFamily
        case wordBreakCharacters
        case syntaxSchemeIdentifier
        case colorSchemeIdentifier
        case colorSchemeDisplayName
        case colorToken
    }

    public struct State: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public static func defaults(
            lineage: UInt64 = 0,
            limits: Limits = .default,
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws -> State {
            let lineage = lineage == 0 ? freshLineage() : lineage
            return try State(
                revision: Revision(lineage: lineage, generation: 0),
                display: .default,
                view: .default,
                editing: .default,
                compareAndMerge: .default,
                syntax: .default,
                colorScheme: .default,
                limits: limits,
                cancellationCheck: cancellationCheck
            )
        }

        public let revision: Revision
        public let display: EditorDisplayPreferences
        public let view: EditorViewPolicy
        public let editing: EditingPreferences
        public let compareAndMerge: CompareAndMergePreferences
        public let syntax: SyntaxPreferences
        public let colorScheme: ColorSchemeSelection
        public let limits: Limits

        public init(
            revision: Revision,
            display: EditorDisplayPreferences,
            view: EditorViewPolicy,
            editing: EditingPreferences = .default,
            compareAndMerge: CompareAndMergePreferences = .default,
            syntax: SyntaxPreferences = .default,
            colorScheme: ColorSchemeSelection = .default,
            limits: Limits = .default,
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws {
            var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
            try EditorPreferencesWorkflow.validateState(
                revision: revision,
                display: display,
                view: view,
                editing: editing,
                compareAndMerge: compareAndMerge,
                syntax: syntax,
                colorScheme: colorScheme,
                work: &work
            )
            try work.finish()
            self.init(
                validatedRevision: revision,
                display: display,
                view: view,
                editing: editing,
                compareAndMerge: compareAndMerge,
                syntax: syntax,
                colorScheme: colorScheme,
                limits: limits
            )
        }

        public init(
            revision: Revision,
            display: EditorDisplayPreferences,
            locksPanes: Bool = false,
            editing: EditingPreferences = .default,
            compareAndMerge: CompareAndMergePreferences = .default,
            syntax: SyntaxPreferences = .default,
            colorScheme: ColorSchemeSelection = .default,
            limits: Limits = .default,
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws {
            try self.init(
                revision: revision,
                display: display,
                view: EditorViewPolicy(
                    locksPanes: locksPanes,
                    displayPreferences: display
                ),
                editing: editing,
                compareAndMerge: compareAndMerge,
                syntax: syntax,
                colorScheme: colorScheme,
                limits: limits,
                cancellationCheck: cancellationCheck
            )
        }

        public var cas: StateCAS { StateCAS(state: self) }

        public var description: String {
            "EditorPreferencesWorkflow.State(revision: \(revision), settings: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["revision": revision, "settings": "<redacted>"],
                displayStyle: .struct
            )
        }

        public func validate(
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws {
            var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
            try EditorPreferencesWorkflow.validateState(
                revision: revision,
                display: display,
                view: view,
                editing: editing,
                compareAndMerge: compareAndMerge,
                syntax: syntax,
                colorScheme: colorScheme,
                work: &work
            )
            try work.finish()
        }

        fileprivate init(
            validatedRevision revision: Revision,
            display: EditorDisplayPreferences,
            view: EditorViewPolicy,
            editing: EditingPreferences,
            compareAndMerge: CompareAndMergePreferences,
            syntax: SyntaxPreferences,
            colorScheme: ColorSchemeSelection,
            limits: Limits
        ) {
            self.revision = revision
            self.display = display
            self.view = view
            self.editing = editing
            self.compareAndMerge = compareAndMerge
            self.syntax = syntax
            self.colorScheme = colorScheme
            self.limits = limits
        }
    }

    public struct StateCAS: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let revision: Revision
        private let state: State

        fileprivate init(state: State) {
            revision = state.revision
            self.state = state
        }

        public var description: String {
            "EditorPreferencesWorkflow.StateCAS(revision: \(revision), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["revision": revision, "contents": "<redacted>"],
                displayStyle: .struct
            )
        }

        public func matches(
            _ current: State,
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws -> Bool {
            do {
                try validate(current, cancellationCheck: cancellationCheck)
                return true
            } catch Error.staleRevision, Error.stateContentsChanged {
                return false
            }
        }

        public static func == (left: Self, right: Self) -> Bool {
            left.revision == right.revision && left.state == right.state
        }

        public func validate(
            _ current: State,
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws {
            do {
                try cancellationCheck()
            } catch {
                throw Error.cancelled
            }
            guard current.revision == revision else {
                throw Error.staleRevision(expected: revision, actual: current.revision)
            }
            guard current == state else { throw Error.stateContentsChanged(revision) }
            do {
                try cancellationCheck()
            } catch {
                throw Error.cancelled
            }
        }
    }

    public struct ColorSchemeCatalog: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let revision: SyntaxSchemeCatalogRevision
        public let schemes: [EditorColorScheme]
        public let limits: Limits

        public init(
            revision: SyntaxSchemeCatalogRevision,
            schemes: [EditorColorScheme] = EditorColorScheme.builtIns,
            limits: Limits = .default,
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws {
            try limits.validate()
            guard revision.lineage != 0 else { throw Error.invalidLineage }
            guard schemes.count <= limits.maximumColorSchemeCount else {
                throw Error.tooManyColorSchemes(maximum: limits.maximumColorSchemeCount)
            }
            var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
            try work.checkCancellation()
            var validated = schemes
            for scheme in validated {
                try chargeColorScheme(scheme, work: &work)
                do {
                    try scheme.validate()
                } catch let error as EditorColorSchemeError {
                    throw Error.invalidColorScheme(error)
                }
            }
            validated = try sortedColorSchemes(validated, work: &work)
            for index in validated.indices.dropFirst() {
                try work.consume(items: 1)
                guard validated[index - 1].identifier != validated[index].identifier else {
                    throw Error.duplicateColorSchemeIdentifier
                }
            }
            try work.finish()
            self.revision = revision
            self.schemes = validated
            self.limits = limits
        }

        public var description: String {
            "EditorPreferencesWorkflow.ColorSchemeCatalog(revision: \(revision), count: \(schemes.count), schemes: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "revision": revision,
                    "schemeCount": schemes.count,
                    "schemes": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func scheme(with identifier: ColorSchemeIdentifier) -> EditorColorScheme? {
            var lower = schemes.startIndex
            var upper = schemes.endIndex
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if schemes[middle].identifier.utf8.lexicographicallyPrecedes(identifier.rawValue.utf8) {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            guard lower < schemes.endIndex, schemes[lower].identifier == identifier.rawValue else {
                return nil
            }
            return schemes[lower]
        }

        fileprivate var fingerprint: ColorSchemeCatalogFingerprint {
            ColorSchemeCatalogFingerprint(revision: revision, schemes: schemes, limits: limits)
        }
    }

    public struct ColorSchemeCatalogFingerprint: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let revision: SyntaxSchemeCatalogRevision
        private let schemes: [EditorColorScheme]
        private let limits: Limits

        fileprivate init(
            revision: SyntaxSchemeCatalogRevision,
            schemes: [EditorColorScheme],
            limits: Limits
        ) {
            self.revision = revision
            self.schemes = schemes
            self.limits = limits
        }

        public var description: String {
            "EditorPreferencesWorkflow.ColorSchemeCatalogFingerprint(revision: \(revision), schemes: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "revision": revision,
                    "schemeCount": schemes.count,
                    "schemes": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        fileprivate func matches(
            _ catalog: ColorSchemeCatalog,
            cancellationCheck: @escaping @Sendable () throws -> Void
        ) throws -> Bool {
            var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
            try work.checkCancellation()
            guard revision == catalog.revision,
                limits == catalog.limits,
                schemes.count == catalog.schemes.count
            else {
                return false
            }
            for (expected, actual) in zip(schemes, catalog.schemes) {
                try chargeColorScheme(expected, work: &work)
                try chargeColorScheme(actual, work: &work)
                guard expected == actual else {
                    try work.finish()
                    return false
                }
            }
            try work.finish()
            return true
        }
    }

    public struct ResolvedSchemes: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let syntax: SyntaxSchemeResolution?
        public let color: EditorColorScheme
        public let colorCatalogFingerprint: ColorSchemeCatalogFingerprint

        fileprivate init(
            syntax: SyntaxSchemeResolution?,
            color: EditorColorScheme,
            colorCatalogFingerprint: ColorSchemeCatalogFingerprint
        ) {
            self.syntax = syntax
            self.color = color
            self.colorCatalogFingerprint = colorCatalogFingerprint
        }

        public var description: String {
            "EditorPreferencesWorkflow.ResolvedSchemes(syntax: <redacted>, color: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["syntax": "<redacted>", "color": "<redacted>"],
                displayStyle: .struct
            )
        }

        public func validate(
            syntaxCatalog: SyntaxSchemeCatalog,
            colorCatalog: ColorSchemeCatalog,
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws {
            do {
                try cancellationCheck()
            } catch {
                throw Error.cancelled
            }
            if let syntax {
                do {
                    try syntax.validate(against: syntaxCatalog)
                } catch is CancellationError {
                    throw Error.cancelled
                } catch SyntaxSchemeCatalogError.cancelled {
                    throw Error.cancelled
                } catch let error as SyntaxSchemeCatalogError {
                    throw Error.syntaxCatalog(error)
                }
                do {
                    try cancellationCheck()
                } catch {
                    throw Error.cancelled
                }
            }
            guard
                try colorCatalogFingerprint.matches(
                    colorCatalog,
                    cancellationCheck: cancellationCheck
                )
            else {
                throw Error.staleColorSchemeCatalog(
                    expected: colorCatalogFingerprint.revision,
                    actual: colorCatalog.revision
                )
            }
        }
    }

    public enum IntentKind: String, CaseIterable, Codable, Hashable, Sendable {
        case setDisplay
        case setView
        case setEditing
        case setCompareAndMerge
        case setSyntax
        case setColorScheme
        case reset
        case resetAll
    }

    public enum Intent: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case setDisplay(EditorDisplayPreferences)
        case setView(EditorViewPolicy)
        case setEditing(EditingPreferences)
        case setCompareAndMerge(CompareAndMergePreferences)
        case setSyntax(SyntaxPreferences)
        case setColorScheme(ColorSchemeSelection)
        case reset(Page)
        case resetAll

        public var kind: IntentKind {
            switch self {
            case .setDisplay: .setDisplay
            case .setView: .setView
            case .setEditing: .setEditing
            case .setCompareAndMerge: .setCompareAndMerge
            case .setSyntax: .setSyntax
            case .setColorScheme: .setColorScheme
            case .reset: .reset
            case .resetAll: .resetAll
            }
        }

        public var page: Page? {
            switch self {
            case .setDisplay, .setView, .setEditing:
                .general
            case .setCompareAndMerge:
                .compareAndMerge
            case .setSyntax, .setColorScheme:
                .syntax
            case .reset(let page):
                page
            case .resetAll:
                nil
            }
        }

        public var description: String {
            let pageName = page?.rawValue ?? "all"
            return "EditorPreferencesWorkflow.Intent(kind: \(kind.rawValue), page: \(pageName), payload: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "kind": kind.rawValue,
                    "page": page?.rawValue ?? "all",
                    "payload": "<redacted>"
                ],
                displayStyle: .enum
            )
        }
    }

    public enum PersistenceEffect: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case store(Data)

        public var description: String {
            "EditorPreferencesWorkflow.PersistenceEffect.store(<redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["payload": "<redacted>"], displayStyle: .enum)
        }
    }

    public enum ApplicationEffect: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case apply(State, resolvedSchemes: ResolvedSchemes)

        public var description: String {
            "EditorPreferencesWorkflow.ApplicationEffect.apply(<redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["payload": "<redacted>"], displayStyle: .enum)
        }
    }

    public enum RequiredEffect: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case commitExclusiveTransaction(PersistenceReceipt, successor: Revision)

        public var description: String {
            switch self {
            case .commitExclusiveTransaction(let receipt, let revision):
                "EditorPreferencesWorkflow.RequiredEffect.commitExclusiveTransaction(\(receipt), successor: \(revision))"
            }
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["effect": description], displayStyle: .enum)
        }
    }

    public struct PersistenceReceipt: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let persistenceVersion: Int
        public let byteCount: Int
        private let canonicalData: Data

        fileprivate init(canonicalData: Data) {
            persistenceVersion = currentPersistenceVersion
            byteCount = canonicalData.count
            self.canonicalData = canonicalData
        }

        public func matches(canonicalData: Data) -> Bool {
            byteCount == canonicalData.count && self.canonicalData == canonicalData
        }

        public var description: String {
            "EditorPreferencesWorkflow.PersistenceReceipt(version: \(persistenceVersion), bytes: \(byteCount), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "persistenceVersion": persistenceVersion,
                    "byteCount": byteCount,
                    "canonicalData": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct PlanningReceipt: Equatable, Hashable, Sendable {
        public let expectedRevision: Revision
        public let successorRevision: Revision
        public let changedPages: [Page]
        public let persistence: PersistenceReceipt
        public let plannedWorkUnits: Int

        public var persistedByteCount: Int { persistence.byteCount }
    }

    public struct Plan: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let expectedStateCAS: StateCAS
        public let successor: State
        public let resolvedSchemes: ResolvedSchemes
        public let persistence: PersistenceEffect
        public let application: ApplicationEffect
        public let receipt: PlanningReceipt
        public let executorContract: ExecutorContract

        fileprivate init(
            expectedStateCAS: StateCAS,
            successor: State,
            resolvedSchemes: ResolvedSchemes,
            persistenceData: Data,
            changedPages: [Page],
            plannedWorkUnits: Int
        ) {
            self.expectedStateCAS = expectedStateCAS
            self.successor = successor
            self.resolvedSchemes = resolvedSchemes
            persistence = .store(persistenceData)
            application = .apply(successor, resolvedSchemes: resolvedSchemes)
            receipt = PlanningReceipt(
                expectedRevision: expectedStateCAS.revision,
                successorRevision: successor.revision,
                changedPages: changedPages,
                persistence: PersistenceReceipt(canonicalData: persistenceData),
                plannedWorkUnits: plannedWorkUnits
            )
            executorContract = .required
        }

        public var requiredEffects: [RequiredEffect] {
            [
                .commitExclusiveTransaction(
                    receipt.persistence,
                    successor: receipt.successorRevision
                )
            ]
        }

        public var description: String {
            "EditorPreferencesWorkflow.Plan(expected: \(receipt.expectedRevision), successor: \(receipt.successorRevision), pages: \(receipt.changedPages.map(\.rawValue)), payload: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "receipt": receipt,
                    "requiredEffects": requiredEffects,
                    "payload": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func validateCurrentState(
            _ current: State,
            syntaxCatalog: SyntaxSchemeCatalog,
            colorCatalog: ColorSchemeCatalog,
            cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
        ) throws {
            try expectedStateCAS.validate(current, cancellationCheck: cancellationCheck)
            try resolvedSchemes.validate(
                syntaxCatalog: syntaxCatalog,
                colorCatalog: colorCatalog,
                cancellationCheck: cancellationCheck
            )
        }

        /// Executes through one opaque lease in one synchronous executor isolation turn.
        public func execute<Executor: PlanExecutor>(
            on executor: isolated Executor,
            syntaxCatalog: SyntaxSchemeCatalog,
            colorCatalog: ColorSchemeCatalog
        ) throws -> ExecutionOutcome {
            try checkTaskCancellation()
            let lease = ExecutorLease(plan: self)
            let outcome = executor.execute(
                lease,
                syntaxCatalog: syntaxCatalog,
                colorCatalog: colorCatalog
            )
            guard outcome.leaseIdentifier == lease.identifier else {
                throw Error.invalidExecutionOutcome
            }
            return outcome
        }
    }

    public enum ExecutorCASContract: String, Codable, Hashable, Sendable {
        case acquireExclusiveLeaseByExactRevisionAndContentsBeforeTransaction
    }

    public enum ExecutorPersistenceContract: String, Codable, Hashable, Sendable {
        case publishExactVersionedBytesWithoutRegenerationInsideTransaction
    }

    public enum ExecutorStateContract: String, Codable, Hashable, Sendable {
        case replaceWithExactPlannedSuccessorInsideTransaction
    }

    public enum ExecutorApplicationContract: String, Codable, Hashable, Sendable {
        case validatePinnedCatalogsAndApplyExactTypedStateBeforeLeaseRelease
    }

    public enum ExecutorCancellationContract: String, Codable, Hashable, Sendable {
        case cancelBeforeTransactionOrReportWholeTransactionUncertain
    }

    public enum ExecutorReconciliationContract: String, Codable, Hashable, Sendable {
        case reconcilePersistenceStateAndEditorsToPredecessorOrSuccessorBeforeDefiniteOutcome
    }

    public struct ExecutorContract: Codable, Equatable, Hashable, Sendable {
        public static let required = ExecutorContract()

        public let cas: ExecutorCASContract
        public let persistence: ExecutorPersistenceContract
        public let state: ExecutorStateContract
        public let application: ExecutorApplicationContract
        public let cancellation: ExecutorCancellationContract
        public let reconciliation: ExecutorReconciliationContract

        public init() {
            cas = .acquireExclusiveLeaseByExactRevisionAndContentsBeforeTransaction
            persistence = .publishExactVersionedBytesWithoutRegenerationInsideTransaction
            state = .replaceWithExactPlannedSuccessorInsideTransaction
            application = .validatePinnedCatalogsAndApplyExactTypedStateBeforeLeaseRelease
            cancellation = .cancelBeforeTransactionOrReportWholeTransactionUncertain
            reconciliation =
                .reconcilePersistenceStateAndEditorsToPredecessorOrSuccessorBeforeDefiniteOutcome
        }
    }

    public enum ExecutionFailureReason: String, CaseIterable, Codable, Hashable, Sendable {
        case cancelled
        case staleState
        case persistenceUnavailable
        case stateOwnerUnavailable
        case editorApplicationUnavailable
        case schemeCatalogChanged
        case contractUnsupported
        case rejected
    }

    public struct ExecutionReceipt: Equatable, Hashable, Sendable {
        public let planning: PlanningReceipt
        public let completedEffects: [RequiredEffect]
        fileprivate let leaseIdentifier: UUID

        fileprivate init(lease: ExecutorLease) {
            let plan = lease.plan
            planning = plan.receipt
            completedEffects = plan.requiredEffects
            leaseIdentifier = lease.identifier
        }
    }

    public struct ExecutionNonCommitReceipt: Equatable, Hashable, Sendable {
        public let planning: PlanningReceipt
        public let blockedEffect: RequiredEffect
        public let reason: ExecutionFailureReason
        fileprivate let leaseIdentifier: UUID

        fileprivate init(lease: ExecutorLease, reason: ExecutionFailureReason) {
            planning = lease.plan.receipt
            blockedEffect = lease.plan.requiredEffects[0]
            self.reason = reason
            leaseIdentifier = lease.identifier
        }
    }

    public struct ExecutionUncertaintyReceipt: Equatable, Hashable, Sendable {
        public let planning: PlanningReceipt
        public let completedEffects: [RequiredEffect]
        public let uncertainEffects: [RequiredEffect]
        public let unattemptedEffects: [RequiredEffect]
        fileprivate let leaseIdentifier: UUID

        fileprivate init(lease: ExecutorLease, uncertainEffects: [RequiredEffect]) {
            planning = lease.plan.receipt
            completedEffects = []
            self.uncertainEffects = uncertainEffects
            unattemptedEffects = []
            leaseIdentifier = lease.identifier
        }
    }

    public enum ExecutionOutcome: Equatable, Hashable, Sendable {
        case completed(ExecutionReceipt)
        case notCommitted(ExecutionNonCommitReceipt)
        case effectUncertain(ExecutionUncertaintyReceipt)

        fileprivate var leaseIdentifier: UUID {
            switch self {
            case .completed(let receipt): receipt.leaseIdentifier
            case .notCommitted(let receipt): receipt.leaseIdentifier
            case .effectUncertain(let receipt): receipt.leaseIdentifier
            }
        }
    }

    public enum ExecutionOutcomeFactory: Sendable {
        /// Call only after exclusive transaction fully commits and executor reconciles any ambiguity.
        public static func completed(lease: ExecutorLease) -> ExecutionOutcome {
            .completed(ExecutionReceipt(lease: lease))
        }

        public static func notCommitted(
            lease: ExecutorLease,
            reason: ExecutionFailureReason
        ) throws -> ExecutionOutcome {
            let plan = lease.plan
            guard let effect = plan.requiredEffects.first,
                isValid(reason: reason, for: effect)
            else { throw Error.invalidExecutionOutcome }
            return .notCommitted(
                ExecutionNonCommitReceipt(lease: lease, reason: reason)
            )
        }

        public static func effectUncertain(
            lease: ExecutorLease,
            uncertainEffectIndices: [Int] = [0]
        ) throws -> ExecutionOutcome {
            let plan = lease.plan
            let effects = plan.requiredEffects
            guard uncertainEffectIndices.count <= effects.count else {
                throw Error.invalidExecutionOutcome
            }
            let indices = uncertainEffectIndices.sorted()
            guard !indices.isEmpty,
                Set(indices).count == indices.count,
                indices.allSatisfy(effects.indices.contains),
                indices == Array(effects.indices)
            else { throw Error.invalidExecutionOutcome }
            return .effectUncertain(
                ExecutionUncertaintyReceipt(
                    lease: lease,
                    uncertainEffects: indices.map { effects[$0] }
                )
            )
        }

        private static func isValid(
            reason: ExecutionFailureReason,
            for effect: RequiredEffect
        ) -> Bool {
            switch (reason, effect) {
            case (.cancelled, _), (.staleState, _), (.contractUnsupported, _), (.rejected, _):
                true
            case (.persistenceUnavailable, .commitExclusiveTransaction),
                (.stateOwnerUnavailable, .commitExclusiveTransaction),
                (.editorApplicationUnavailable, .commitExclusiveTransaction),
                (.schemeCatalogChanged, .commitExclusiveTransaction):
                true
            }
        }
    }

    /// Side-effect owner must hold one exclusive lease through exact CAS, persistence, state, editor
    /// application, and any reconciliation. Workflow performs no I/O or UI.
    public protocol PlanExecutor: Actor {
        func execute(
            _ lease: ExecutorLease,
            syntaxCatalog: SyntaxSchemeCatalog,
            colorCatalog: ColorSchemeCatalog
        ) -> ExecutionOutcome
    }

    public struct ExecutorLease: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        fileprivate let identifier: UUID
        fileprivate let plan: Plan

        fileprivate init(plan: Plan) {
            identifier = UUID()
            self.plan = plan
        }

        public var expectedStateCAS: StateCAS { plan.expectedStateCAS }
        public var successor: State { plan.successor }
        public var resolvedSchemes: ResolvedSchemes { plan.resolvedSchemes }
        public var persistence: PersistenceEffect { plan.persistence }
        public var application: ApplicationEffect { plan.application }
        public var requiredEffect: RequiredEffect { plan.requiredEffects[0] }
        public var executorContract: ExecutorContract { plan.executorContract }

        public func isSameLease(as other: Self) -> Bool {
            identifier == other.identifier
        }

        public var description: String {
            "EditorPreferencesWorkflow.ExecutorLease(<opaque>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["lease": "<opaque>"], displayStyle: .struct)
        }
    }

    public enum Error: Swift.Error, Equatable, LocalizedError, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        case cancelled
        case invalidLimit(Limit)
        case invalidTabWidth(Int)
        case stringTooLarge(field: StringField, maximumUTF8Bytes: Int)
        case invalidString(field: StringField)
        case inconsistentWordBreakCharacters
        case inconsistentDisplayAndViewState
        case invalidSyntaxSelection
        case invalidLineage
        case tooManyColorSchemes(maximum: Int)
        case duplicateColorSchemeIdentifier
        case invalidColorScheme(EditorColorSchemeError)
        case missingColorScheme
        case syntaxCatalog(SyntaxSchemeCatalogError)
        case staleColorSchemeCatalog(
            expected: SyntaxSchemeCatalogRevision,
            actual: SyntaxSchemeCatalogRevision
        )
        case unsupportedPersistenceVersion(Int)
        case persistenceInputTooLarge(maximumBytes: Int)
        case persistenceOutputTooLarge(maximumBytes: Int)
        case tooManyPersistenceItems(maximum: Int)
        case jsonTooDeep(maximumDepth: Int)
        case malformedPersistence
        case nonCanonicalPersistence
        case totalStringsTooLarge(maximumUTF8Bytes: Int)
        case workLimitExceeded(maximumWorkUnits: Int)
        case staleRevision(expected: Revision, actual: Revision)
        case stateContentsChanged(Revision)
        case revisionExhausted(lineage: UInt64)
        case noChanges
        case invalidExecutionOutcome

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "Editor preference operation was cancelled."
            case .invalidLimit(let limit):
                "Invalid editor preference limit: \(limit.rawValue)."
            case .invalidTabWidth(let width):
                "Editor tab width must be between \(EditingPreferences.minimumTabWidth) and \(EditingPreferences.maximumTabWidth): \(width)."
            case .stringTooLarge(let field, let maximum):
                "Editor preference field \(field.rawValue) exceeds \(maximum) UTF-8 bytes."
            case .invalidString(let field):
                "Editor preference field \(field.rawValue) is invalid."
            case .inconsistentWordBreakCharacters:
                "Whitespace-only word breaks cannot include custom break characters."
            case .inconsistentDisplayAndViewState:
                "Editor display and View policy flags disagree."
            case .invalidSyntaxSelection:
                "Editor syntax selection is invalid."
            case .invalidLineage:
                "Editor preference revision lineage must be nonzero."
            case .tooManyColorSchemes(let maximum):
                "Editor color scheme catalog exceeds \(maximum) schemes."
            case .duplicateColorSchemeIdentifier:
                "Editor color scheme catalog contains a duplicate identifier."
            case .invalidColorScheme:
                "Editor color scheme catalog contains an invalid scheme."
            case .missingColorScheme:
                "Selected editor color scheme is unavailable."
            case .syntaxCatalog:
                "Editor syntax scheme resolution failed."
            case .staleColorSchemeCatalog:
                "Editor color scheme resolution belongs to a stale catalog."
            case .unsupportedPersistenceVersion(let version):
                "Unsupported editor preference persistence version: \(version)."
            case .persistenceInputTooLarge(let maximum):
                "Editor preference input exceeds \(maximum) bytes."
            case .persistenceOutputTooLarge(let maximum):
                "Editor preference output exceeds \(maximum) bytes."
            case .tooManyPersistenceItems(let maximum):
                "Editor preference persistence exceeds \(maximum) JSON values."
            case .jsonTooDeep(let maximumDepth):
                "Editor preference persistence exceeds \(maximumDepth) JSON nesting levels."
            case .malformedPersistence:
                "Editor preference persistence is malformed."
            case .nonCanonicalPersistence:
                "Editor preference persistence is not canonical."
            case .totalStringsTooLarge(let maximum):
                "Editor preference strings exceed \(maximum) aggregate UTF-8 bytes."
            case .workLimitExceeded(let maximum):
                "Editor preference work exceeds \(maximum) units."
            case .staleRevision:
                "Editor preferences changed since planning."
            case .stateContentsChanged:
                "Editor preference contents changed without a revision change."
            case .revisionExhausted:
                "Editor preference revision generation is exhausted."
            case .noChanges:
                "Editor preference intent makes no changes."
            case .invalidExecutionOutcome:
                "Editor preference execution outcome contradicts its plan."
            }
        }

        public var description: String { errorDescription ?? "Editor preference operation failed." }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["details": "<redacted>"], displayStyle: .enum)
        }
    }

    public static func resolve(
        _ state: State,
        syntaxCatalog: SyntaxSchemeCatalog,
        colorCatalog: ColorSchemeCatalog,
        cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
    ) throws -> ResolvedSchemes {
        var work = try Work(limits: state.limits, cancellationCheck: cancellationCheck)
        try validateState(state, work: &work)
        let resolution = try resolveValidated(
            state,
            syntaxCatalog: syntaxCatalog,
            colorCatalog: colorCatalog,
            work: &work
        )
        try work.finish()
        return resolution
    }

    private static func resolveValidated(
        _ state: State,
        syntaxCatalog: SyntaxSchemeCatalog,
        colorCatalog: ColorSchemeCatalog,
        work: inout Work
    ) throws -> ResolvedSchemes {
        try work.checkCancellation()
        let syntaxResolution: SyntaxSchemeResolution?
        if state.syntax.isHighlightingEnabled {
            do {
                syntaxResolution = try syntaxCatalog.resolve(
                    state.syntax.selection,
                    language: state.display.syntaxHighlightingLanguage,
                    mode: .textComparison
                )
            } catch SyntaxSchemeCatalogError.cancelled {
                throw Error.cancelled
            } catch let error as SyntaxSchemeCatalogError {
                throw Error.syntaxCatalog(error)
            }
            try work.consume(items: 1)
        } else {
            syntaxResolution = nil
        }
        let color =
            colorCatalog.scheme(with: state.colorScheme.selectedIdentifier)
            ?? colorCatalog.scheme(with: .standard)
            ?? colorCatalog.schemes.first
        guard let color else {
            throw Error.missingColorScheme
        }
        try work.consume(items: 1)
        try work.checkCancellation()
        return ResolvedSchemes(
            syntax: syntaxResolution,
            color: color,
            colorCatalogFingerprint: colorCatalog.fingerprint
        )
    }

    public static func plan(
        intent: Intent,
        current: State,
        syntaxCatalog: SyntaxSchemeCatalog,
        colorCatalog: ColorSchemeCatalog,
        cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
    ) throws -> Plan {
        var work = try Work(limits: current.limits, cancellationCheck: cancellationCheck)
        try validateState(current, work: &work)

        var display = current.display
        var locksPanes = current.view.locksPanes
        var editing = current.editing
        var compareAndMerge = current.compareAndMerge
        var syntax = current.syntax
        var colorScheme = current.colorScheme

        switch intent {
        case .setDisplay(let value):
            display = value
        case .setView(let value):
            locksPanes = value.locksPanes
            display = value.applying(to: display)
        case .setEditing(let value):
            editing = value
        case .setCompareAndMerge(let value):
            compareAndMerge = value
        case .setSyntax(let value):
            syntax = value
        case .setColorScheme(let value):
            colorScheme = value
        case .reset(.general):
            display = .default
            locksPanes = EditorViewPolicy.default.locksPanes
            editing = .default
        case .reset(.compareAndMerge):
            compareAndMerge = .default
        case .reset(.syntax):
            syntax = .default
            colorScheme = .default
        case .resetAll:
            display = .default
            locksPanes = EditorViewPolicy.default.locksPanes
            editing = .default
            compareAndMerge = .default
            syntax = .default
            colorScheme = .default
        }

        let successorRevision = try current.revision.advanced()
        let successorView = EditorViewPolicy(
            locksPanes: locksPanes,
            displayPreferences: display
        )
        try validateState(
            revision: successorRevision,
            display: display,
            view: successorView,
            editing: editing,
            compareAndMerge: compareAndMerge,
            syntax: syntax,
            colorScheme: colorScheme,
            work: &work
        )
        let successor = State(
            validatedRevision: successorRevision,
            display: display,
            view: successorView,
            editing: editing,
            compareAndMerge: compareAndMerge,
            syntax: syntax,
            colorScheme: colorScheme,
            limits: current.limits
        )
        guard successorWithoutRevision(successor) != successorWithoutRevision(current) else {
            throw Error.noChanges
        }
        let resolvedSchemes = try resolveValidated(
            successor,
            syntaxCatalog: syntaxCatalog,
            colorCatalog: colorCatalog,
            work: &work
        )
        try work.consume(items: Page.allCases.count)
        let data = try encodeValidated(successor, work: &work)
        try work.finish()
        return Plan(
            expectedStateCAS: current.cas,
            successor: successor,
            resolvedSchemes: resolvedSchemes,
            persistenceData: data,
            changedPages: changedPages(from: current, to: successor),
            plannedWorkUnits: work.consumed
        )
    }

    /// Canonical, compact schema-1 JSON containing one complete typed snapshot.
    public static func encode(
        _ state: State,
        cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
    ) throws -> Data {
        var work = try Work(limits: state.limits, cancellationCheck: cancellationCheck)
        try validateState(state, work: &work)
        let data = try encodeValidated(state, work: &work)
        try work.finish()
        return data
    }

    private static func encodeValidated(_ state: State, work: inout Work) throws -> Data {
        try work.checkCancellation()
        let display: Data
        let view: Data
        let syntax: Data
        do {
            display = try state.display.encodedData()
            view = try state.view.encodedData(cancellationCheck: work.cancellationCheck)
            syntax = try state.syntax.selection.encodedData(
                limits: syntaxLimits(from: state.limits)
            )
        } catch is CancellationError {
            throw Error.cancelled
        } catch let error as EditorViewPolicyError where error == .cancelled {
            throw Error.cancelled
        } catch SyntaxSchemeCatalogError.cancelled {
            throw Error.cancelled
        } catch let error as SyntaxSchemeCatalogError {
            throw Error.syntaxCatalog(error)
        } catch {
            throw Error.malformedPersistence
        }
        try work.consume(bytes: display.count + view.count + syntax.count)
        var writer = PersistenceCanonicalWriter(limits: state.limits)
        let data = try writer.encode(
            state: state,
            display: display,
            view: view,
            syntaxSelection: syntax,
            work: &work
        )
        var preflight = PersistenceJSONPreflight(data: data, limits: state.limits)
        _ = try preflight.validate(work: &work)
        return data
    }

    /// Strictly accepts canonical output from `encode(_:cancellationCheck:)` under caller limits.
    public static func decode(
        from data: Data,
        limits: Limits = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
    ) throws -> State {
        try limits.validate()
        guard data.count <= limits.maximumPersistenceBytes else {
            throw Error.persistenceInputTooLarge(maximumBytes: limits.maximumPersistenceBytes)
        }
        var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
        try work.checkCancellation()
        let snapshot = try ownedDataSnapshot(data, work: &work)
        var preflight = PersistenceJSONPreflight(data: snapshot, limits: limits)
        let persistenceVersion = try preflight.validate(work: &work)
        guard persistenceVersion == currentPersistenceVersion else {
            throw Error.unsupportedPersistenceVersion(persistenceVersion)
        }
        try work.checkCancellation()
        let wire: PersistenceWire
        do {
            wire = try JSONDecoder().decode(PersistenceWire.self, from: snapshot)
        } catch {
            throw Error.malformedPersistence
        }
        let display: EditorDisplayPreferences
        let view: EditorViewPolicy
        let syntaxSelection: SyntaxSchemeSelection
        do {
            display = try EditorDisplayPreferences.decode(from: wire.display)
            view = try EditorViewPolicy.decode(
                from: wire.view,
                cancellationCheck: cancellationCheck
            )
            syntaxSelection = try SyntaxSchemeSelection.decode(
                from: wire.syntaxSelection,
                limits: syntaxLimits(from: limits)
            )
        } catch is CancellationError {
            throw Error.cancelled
        } catch let error as EditorViewPolicyError where error == .cancelled {
            throw Error.cancelled
        } catch let error as SyntaxSchemeCatalogError where error == .cancelled {
            throw Error.cancelled
        } catch {
            throw Error.malformedPersistence
        }
        try validateState(
            revision: wire.revision,
            display: display,
            view: view,
            editing: wire.editing,
            compareAndMerge: wire.compareAndMerge,
            syntax: SyntaxPreferences(
                isHighlightingEnabled: wire.syntaxHighlightingEnabled,
                selection: syntaxSelection
            ),
            colorScheme: wire.colorScheme,
            work: &work
        )
        let state = State(
            validatedRevision: wire.revision,
            display: display,
            view: view,
            editing: wire.editing,
            compareAndMerge: wire.compareAndMerge,
            syntax: SyntaxPreferences(
                isHighlightingEnabled: wire.syntaxHighlightingEnabled,
                selection: syntaxSelection
            ),
            colorScheme: wire.colorScheme,
            limits: limits
        )
        let canonical = try encodeValidated(state, work: &work)
        guard canonical == snapshot else { throw Error.nonCanonicalPersistence }
        try work.finish()
        return state
    }

    /// Missing persistence uses defaults. Present invalid persistence fails closed with typed errors.
    public static func restore(
        from data: Data?,
        defaultLineage: UInt64 = 0,
        limits: Limits = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = checkTaskCancellation
    ) throws -> State {
        guard let data else {
            return try State.defaults(
                lineage: defaultLineage,
                limits: limits,
                cancellationCheck: cancellationCheck
            )
        }
        return try decode(from: data, limits: limits, cancellationCheck: cancellationCheck)
    }

    public static func checkTaskCancellation() throws {
        do {
            try Task<Never, Never>.checkCancellation()
        } catch {
            throw Error.cancelled
        }
    }

    private struct PersistenceWire: Codable {
        let persistenceVersion: Int
        let revision: Revision
        let display: Data
        let view: Data
        let editing: EditingPreferences
        let compareAndMerge: CompareAndMergePreferences
        let syntaxHighlightingEnabled: Bool
        let syntaxSelection: Data
        let colorScheme: ColorSchemeSelection
    }

    private struct PersistenceCanonicalWriter {
        private var data = Data()
        private let maximumBytes: Int

        init(limits: Limits) {
            maximumBytes = limits.maximumPersistenceBytes
            data.reserveCapacity(min(maximumBytes, 4 * 1_024))
        }

        mutating func encode(
            state: State,
            display: Data,
            view: Data,
            syntaxSelection: Data,
            work: inout Work
        ) throws -> Data {
            guard work.limits.maximumPersistenceItemCount >= 21 else {
                throw Error.tooManyPersistenceItems(
                    maximum: work.limits.maximumPersistenceItemCount
                )
            }
            guard work.limits.maximumJSONDepth >= 2 else {
                throw Error.jsonTooDeep(maximumDepth: work.limits.maximumJSONDepth)
            }
            try append("{\"colorScheme\":{\"selectedIdentifier\":", work: &work)
            try append(string: state.colorScheme.selectedIdentifier.rawValue, work: &work)
            try append("},\"compareAndMerge\":{\"automaticMergeDestination\":", work: &work)
            try append(
                string: mergeSideWireValue(state.compareAndMerge.automaticMergeDestination),
                work: &work
            )
            try append(",\"automaticRescanAfterEdit\":", work: &work)
            try append(boolean: state.compareAndMerge.automaticRescanAfterEdit, work: &work)
            try append(",\"copyGranularity\":", work: &work)
            try append(string: state.compareAndMerge.copyGranularity.rawValue, work: &work)
            try append(",\"lineDifferenceGranularity\":", work: &work)
            try append(
                string: state.compareAndMerge.lineDifferenceGranularity.rawValue,
                work: &work
            )
            try append(",\"wordBreakCharacters\":", work: &work)
            try append(string: state.compareAndMerge.wordBreakCharacters, work: &work)
            try append(",\"wordBreakMode\":", work: &work)
            try append(string: state.compareAndMerge.wordBreakMode.rawValue, work: &work)
            try append("},\"display\":", work: &work)
            try append(string: display.base64EncodedString(), work: &work)
            try append(",\"editing\":{\"tabInsertion\":", work: &work)
            try append(string: state.editing.tabInsertion.rawValue, work: &work)
            try append(",\"tabWidth\":", work: &work)
            try append(integer: state.editing.tabWidth, work: &work)
            try append("},\"persistenceVersion\":", work: &work)
            try append(integer: currentPersistenceVersion, work: &work)
            try append(",\"revision\":{\"generation\":", work: &work)
            try append(integer: state.revision.generation, work: &work)
            try append(",\"lineage\":", work: &work)
            try append(integer: state.revision.lineage, work: &work)
            try append("},\"syntaxHighlightingEnabled\":", work: &work)
            try append(boolean: state.syntax.isHighlightingEnabled, work: &work)
            try append(",\"syntaxSelection\":", work: &work)
            try append(string: syntaxSelection.base64EncodedString(), work: &work)
            try append(",\"view\":", work: &work)
            try append(string: view.base64EncodedString(), work: &work)
            try append("}", work: &work)
            return data
        }

        private mutating func append(_ value: StaticString, work: inout Work) throws {
            let bytes = value.withUTF8Buffer { Array($0) }
            try append(bytes, work: &work)
        }

        private mutating func append(string value: String, work: inout Work) throws {
            try append("\"", work: &work)
            for byte in value.utf8 {
                if byte == 0x22 || byte == 0x5C {
                    try append(byte: 0x5C, work: &work)
                }
                try append(byte: byte, work: &work)
            }
            try append("\"", work: &work)
        }

        private mutating func append(boolean value: Bool, work: inout Work) throws {
            try append(value ? "true" : "false", work: &work)
        }

        private mutating func append(integer value: Int, work: inout Work) throws {
            try append(bytes: String(value).utf8, work: &work)
        }

        private mutating func append(integer value: UInt64, work: inout Work) throws {
            try append(bytes: String(value).utf8, work: &work)
        }

        private mutating func append(byte: UInt8, work: inout Work) throws {
            guard data.count < maximumBytes else {
                throw Error.persistenceOutputTooLarge(maximumBytes: maximumBytes)
            }
            data.append(byte)
            try work.consume(bytes: 1)
        }

        private mutating func append<Bytes: Collection>(
            _ bytes: Bytes,
            work: inout Work
        ) throws where Bytes.Element == UInt8 {
            guard bytes.count <= maximumBytes - data.count else {
                throw Error.persistenceOutputTooLarge(maximumBytes: maximumBytes)
            }
            data.append(contentsOf: bytes)
            try work.consume(bytes: bytes.count)
        }

        private mutating func append<Bytes: Collection>(
            bytes: Bytes,
            work: inout Work
        ) throws where Bytes.Element == UInt8 {
            try append(bytes, work: &work)
        }
    }

    private struct StateWithoutRevision: Equatable {
        let display: EditorDisplayPreferences
        let view: EditorViewPolicy
        let editing: EditingPreferences
        let compareAndMerge: CompareAndMergePreferences
        let syntax: SyntaxPreferences
        let colorScheme: ColorSchemeSelection
        let limits: Limits
    }

    private static func successorWithoutRevision(_ state: State) -> StateWithoutRevision {
        StateWithoutRevision(
            display: state.display,
            view: state.view,
            editing: state.editing,
            compareAndMerge: state.compareAndMerge,
            syntax: state.syntax,
            colorScheme: state.colorScheme,
            limits: state.limits
        )
    }

    private static func changedPages(from current: State, to successor: State) -> [Page] {
        Page.allCases.filter { page in
            switch page {
            case .general:
                current.display != successor.display || current.view != successor.view
                    || current.editing != successor.editing
            case .compareAndMerge:
                current.compareAndMerge != successor.compareAndMerge
            case .syntax:
                current.syntax != successor.syntax || current.colorScheme != successor.colorScheme
            }
        }
    }

    private static func validateSyntaxSelection(_ selection: SyntaxSchemeSelection) throws {
        guard selection.schemaVersion == SyntaxSchemeSelection.currentSchemaVersion else {
            throw Error.invalidSyntaxSelection
        }
    }

    private static func validateState(_ state: State, work: inout Work) throws {
        try validateState(
            revision: state.revision,
            display: state.display,
            view: state.view,
            editing: state.editing,
            compareAndMerge: state.compareAndMerge,
            syntax: state.syntax,
            colorScheme: state.colorScheme,
            work: &work
        )
    }

    private static func validateState(
        revision: Revision,
        display: EditorDisplayPreferences,
        view: EditorViewPolicy,
        editing: EditingPreferences,
        compareAndMerge: CompareAndMergePreferences,
        syntax: SyntaxPreferences,
        colorScheme: ColorSchemeSelection,
        work: inout Work
    ) throws {
        try work.checkCancellation()
        guard revision.lineage != 0 else { throw Error.invalidLineage }
        try display.validate()
        try view.validate()
        try editing.validate()
        try compareAndMerge.validate(
            maximumWordBreakCharactersUTF8Bytes: work.limits.maximumStringUTF8Bytes
        )
        guard
            view
                == EditorViewPolicy(
                    locksPanes: view.locksPanes,
                    displayPreferences: display
                )
        else {
            throw Error.inconsistentDisplayAndViewState
        }
        try validateSyntaxSelection(syntax.selection)
        try validatePortableIdentifier(
            colorScheme.selectedIdentifier.rawValue,
            field: .colorSchemeIdentifier,
            maximumUTF8Bytes: min(
                work.limits.maximumStringUTF8Bytes,
                ColorSchemeIdentifier.maximumUTF8Bytes
            ),
            allowsEditorColorSchemeSeparators: true
        )
        try work.consume(string: display.font.familyName ?? "", field: .fontFamily)
        try work.consume(string: compareAndMerge.wordBreakCharacters)
        try work.consume(
            string: syntax.selection.selectedIdentifier?.rawValue ?? "",
            field: .syntaxSchemeIdentifier
        )
        try work.consume(
            string: syntax.selection.fallbackIdentifier?.rawValue ?? "",
            field: .syntaxSchemeIdentifier
        )
        try work.consume(
            string: colorScheme.selectedIdentifier.rawValue,
            field: .colorSchemeIdentifier
        )
    }

    private static func mergeSideWireValue(_ side: MergeCommandPolicy.Side) -> String {
        switch side {
        case .left: "left"
        case .middle: "middle"
        case .right: "right"
        }
    }

    private static func ownedDataSnapshot(_ source: Data, work: inout Work) throws -> Data {
        var snapshot = Data()
        snapshot.reserveCapacity(source.count)
        try source.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + work.limits.cancellationCheckInterval, bytes.count)
                snapshot.append(contentsOf: bytes[offset..<end])
                try work.consume(bytes: end - offset)
                offset = end
            }
        }
        try work.checkCancellation()
        return snapshot
    }

    private static func syntaxLimits(from limits: Limits) throws -> SyntaxSchemeCatalogLimits {
        do {
            return try SyntaxSchemeCatalogLimits(
                maximumCustomSchemeCount: min(
                    limits.maximumColorSchemeCount,
                    SyntaxSchemeCatalogLimits.hardMaximumCustomSchemeCount
                ),
                maximumDisplayNameUTF8Bytes: min(
                    limits.maximumStringUTF8Bytes,
                    SyntaxSchemeCatalogLimits.hardMaximumDisplayNameUTF8Bytes
                ),
                maximumPersistenceBytes: min(
                    limits.maximumPersistenceBytes,
                    SyntaxSchemeCatalogLimits.hardMaximumPersistenceBytes
                ),
                maximumJSONDepth: min(
                    limits.maximumJSONDepth,
                    SyntaxSchemeCatalogLimits.hardMaximumJSONDepth
                ),
                maximumWorkUnits: min(
                    limits.maximumWorkUnits,
                    SyntaxSchemeCatalogLimits.hardMaximumWorkUnits
                ),
                cancellationCheckInterval: min(
                    limits.cancellationCheckInterval,
                    SyntaxSchemeCatalogLimits.hardMaximumCancellationCheckInterval
                )
            )
        } catch let error as SyntaxSchemeCatalogError {
            throw Error.syntaxCatalog(error)
        }
    }

    private static func sortedColorSchemes(
        _ values: [EditorColorScheme],
        work: inout Work
    ) throws -> [EditorColorScheme] {
        guard values.count > 1 else {
            try work.checkCancellation()
            return values
        }

        var source = values
        var destination = values
        var width = 1
        while width < source.count {
            var lower = 0
            while lower < source.count {
                let middle = min(lower + width, source.count)
                let upper = min(middle + width, source.count)
                var left = lower
                var right = middle
                var output = lower
                while left < middle || right < upper {
                    try work.consume(items: 1)
                    if right == upper
                        || (left < middle
                            && !source[right].identifier.utf8.lexicographicallyPrecedes(
                                source[left].identifier.utf8
                            ))
                    {
                        destination[output] = source[left]
                        left += 1
                    } else {
                        destination[output] = source[right]
                        right += 1
                    }
                    output += 1
                }
                lower = upper
            }
            swap(&source, &destination)
            width = width > source.count / 2 ? source.count : width * 2
        }
        try work.checkCancellation()
        return source
    }

    private static func chargeColorScheme(
        _ scheme: EditorColorScheme,
        work: inout Work
    ) throws {
        try work.consume(items: 1)
        try work.consume(string: scheme.identifier, field: .colorSchemeIdentifier)
        try work.consume(string: scheme.displayName, field: .colorSchemeDisplayName)
        for palette in scheme.palettes {
            try work.consume(items: 1)
            for definition in palette.definitions {
                try work.consume(items: 1)
                try work.consume(string: definition.token.rawValue, field: .colorToken)
            }
            for assignment in palette.assignments {
                try work.consume(items: 1)
                try work.consume(string: assignment.token.rawValue, field: .colorToken)
            }
        }
        try work.consume(items: scheme.differenceDecorations.count)
    }

    private struct PersistenceJSONPreflight {
        private let bytes: Data
        private let limits: Limits
        private var index = 0
        private var valueCount = 0
        private var persistenceVersion: Int?

        init(data: Data, limits: Limits) {
            bytes = data
            self.limits = limits
        }

        mutating func validate(work: inout Work) throws -> Int {
            try work.checkCancellation()
            try skipWhitespace(work: &work)
            try parseValue(depth: 0, capturesPersistenceVersion: true, work: &work)
            try skipWhitespace(work: &work)
            guard index == bytes.count, let persistenceVersion else {
                throw Error.malformedPersistence
            }
            try work.checkCancellation()
            return persistenceVersion
        }

        private mutating func parseValue(
            depth: Int,
            capturesPersistenceVersion: Bool = false,
            work: inout Work
        ) throws {
            valueCount += 1
            guard valueCount <= limits.maximumPersistenceItemCount,
                let byte = currentByte
            else {
                if valueCount > limits.maximumPersistenceItemCount {
                    throw Error.tooManyPersistenceItems(
                        maximum: limits.maximumPersistenceItemCount
                    )
                }
                throw Error.malformedPersistence
            }
            switch byte {
            case 0x7B:
                try parseObject(
                    depth: depth + 1,
                    capturesPersistenceVersion: capturesPersistenceVersion,
                    work: &work
                )
            case 0x5B:
                try parseArray(depth: depth + 1, work: &work)
            case 0x22:
                _ = try parseString(work: &work)
            case 0x74:
                try consumeLiteral([0x74, 0x72, 0x75, 0x65], work: &work)
            case 0x66:
                try consumeLiteral([0x66, 0x61, 0x6C, 0x73, 0x65], work: &work)
            case 0x6E:
                try consumeLiteral([0x6E, 0x75, 0x6C, 0x6C], work: &work)
            case 0x2D, 0x30...0x39:
                try parseNumber(work: &work)
            default:
                throw Error.malformedPersistence
            }
        }

        private mutating func parseObject(
            depth: Int,
            capturesPersistenceVersion: Bool,
            work: inout Work
        ) throws {
            try validate(depth: depth)
            try require(0x7B, work: &work)
            try skipWhitespace(work: &work)
            if try consume(0x7D, work: &work) { return }
            while true {
                let key = try parseString(capturing: capturesPersistenceVersion, work: &work)
                try skipWhitespace(work: &work)
                try require(0x3A, work: &work)
                try skipWhitespace(work: &work)
                if capturesPersistenceVersion, key == "persistenceVersion" {
                    guard persistenceVersion == nil else { throw Error.malformedPersistence }
                    persistenceVersion = try parseCanonicalInt(work: &work)
                } else {
                    try parseValue(depth: depth, work: &work)
                }
                try skipWhitespace(work: &work)
                if try consume(0x7D, work: &work) { return }
                try require(0x2C, work: &work)
                try skipWhitespace(work: &work)
            }
        }

        private mutating func parseArray(depth: Int, work: inout Work) throws {
            try validate(depth: depth)
            try require(0x5B, work: &work)
            try skipWhitespace(work: &work)
            if try consume(0x5D, work: &work) { return }
            while true {
                try parseValue(depth: depth, work: &work)
                try skipWhitespace(work: &work)
                if try consume(0x5D, work: &work) { return }
                try require(0x2C, work: &work)
                try skipWhitespace(work: &work)
            }
        }

        private mutating func parseString(
            capturing: Bool = false,
            work: inout Work
        ) throws -> String? {
            try require(0x22, work: &work)
            var captured: [UInt8] = []
            while let byte = currentByte {
                try advance(work: &work)
                switch byte {
                case 0x22:
                    guard capturing else { return nil }
                    guard let value = String(bytes: captured, encoding: .utf8) else {
                        throw Error.malformedPersistence
                    }
                    return value
                case 0x5C:
                    guard let escaped = currentByte else { throw Error.malformedPersistence }
                    try advance(work: &work)
                    switch escaped {
                    case 0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74:
                        if capturing { throw Error.malformedPersistence }
                    case 0x75:
                        for _ in 0..<4 {
                            guard let hex = currentByte, isASCIIHexDigit(hex) else {
                                throw Error.malformedPersistence
                            }
                            try advance(work: &work)
                        }
                    default:
                        throw Error.malformedPersistence
                    }
                case 0x00...0x1F:
                    throw Error.malformedPersistence
                default:
                    if capturing { captured.append(byte) }
                }
            }
            throw Error.malformedPersistence
        }

        private mutating func parseCanonicalInt(work: inout Work) throws -> Int {
            let start = index
            try parseNumber(work: &work)
            let source = String(decoding: bytes[start..<index], as: UTF8.self)
            guard let value = Int(source), String(value) == source else {
                throw Error.malformedPersistence
            }
            return value
        }

        private mutating func parseNumber(work: inout Work) throws {
            _ = try consume(0x2D, work: &work)
            if try consume(0x30, work: &work) {
                if let byte = currentByte, (0x30...0x39).contains(byte) {
                    throw Error.malformedPersistence
                }
            } else {
                guard try consumeDigit(in: 0x31...0x39, work: &work) else {
                    throw Error.malformedPersistence
                }
                while try consumeDigit(in: 0x30...0x39, work: &work) {}
            }
            if try consume(0x2E, work: &work) {
                guard try consumeDigit(in: 0x30...0x39, work: &work) else {
                    throw Error.malformedPersistence
                }
                while try consumeDigit(in: 0x30...0x39, work: &work) {}
            }
            if currentByte == 0x65 || currentByte == 0x45 {
                try advance(work: &work)
                if currentByte == 0x2B || currentByte == 0x2D {
                    try advance(work: &work)
                }
                guard try consumeDigit(in: 0x30...0x39, work: &work) else {
                    throw Error.malformedPersistence
                }
                while try consumeDigit(in: 0x30...0x39, work: &work) {}
            }
        }

        private mutating func consumeLiteral(_ literal: [UInt8], work: inout Work) throws {
            guard literal.count <= bytes.count - index else {
                throw Error.malformedPersistence
            }
            for byte in literal { try require(byte, work: &work) }
        }

        private mutating func require(_ byte: UInt8, work: inout Work) throws {
            guard try consume(byte, work: &work) else { throw Error.malformedPersistence }
        }

        private mutating func consume(_ byte: UInt8, work: inout Work) throws -> Bool {
            guard currentByte == byte else { return false }
            try advance(work: &work)
            return true
        }

        private mutating func consumeDigit(
            in range: ClosedRange<UInt8>,
            work: inout Work
        ) throws -> Bool {
            guard let byte = currentByte, range.contains(byte) else { return false }
            try advance(work: &work)
            return true
        }

        private mutating func skipWhitespace(work: inout Work) throws {
            while let byte = currentByte,
                byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
            {
                try advance(work: &work)
            }
        }

        private mutating func advance(work: inout Work) throws {
            guard index < bytes.count else { throw Error.malformedPersistence }
            index += 1
            try work.consume(bytes: 1)
        }

        private func validate(depth: Int) throws {
            guard depth <= limits.maximumJSONDepth else {
                throw Error.jsonTooDeep(maximumDepth: limits.maximumJSONDepth)
            }
        }

        private var currentByte: UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        private func isASCIIHexDigit(_ byte: UInt8) -> Bool {
            (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte)
                || (0x61...0x66).contains(byte)
        }
    }

    private struct Work {
        let limits: Limits
        let cancellationCheck: @Sendable () throws -> Void
        private(set) var consumed = 0
        private var stringBytes = 0

        init(
            limits: Limits,
            cancellationCheck: @escaping @Sendable () throws -> Void
        ) throws {
            try limits.validate()
            self.limits = limits
            self.cancellationCheck = cancellationCheck
        }

        mutating func consume(items: Int) throws {
            try consume(items)
        }

        mutating func consume(bytes: Int) throws {
            try consume(bytes)
        }

        mutating func consume(string: String, field: StringField = .wordBreakCharacters) throws {
            let count = string.utf8.count
            guard count <= limits.maximumStringUTF8Bytes else {
                throw Error.stringTooLarge(
                    field: field,
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            guard count <= limits.maximumTotalStringUTF8Bytes - stringBytes else {
                throw Error.totalStringsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
                )
            }
            stringBytes += count
            try consume(count)
        }

        mutating func checkCancellation() throws {
            do {
                try cancellationCheck()
            } catch {
                throw Error.cancelled
            }
        }

        mutating func finish() throws {
            try checkCancellation()
        }

        private mutating func consume(_ amount: Int) throws {
            guard amount >= 0, amount <= limits.maximumWorkUnits - consumed else {
                throw Error.workLimitExceeded(maximumWorkUnits: limits.maximumWorkUnits)
            }
            let previous = consumed
            consumed += amount
            if previous / limits.cancellationCheckInterval
                != consumed / limits.cancellationCheckInterval
            {
                try checkCancellation()
            }
        }
    }
}

private func validateBoundedString(
    _ value: String,
    field: EditorPreferencesWorkflow.StringField,
    maximumUTF8Bytes: Int,
    allowsEmpty: Bool
) throws {
    guard value.utf8.count <= maximumUTF8Bytes else {
        throw EditorPreferencesWorkflow.Error.stringTooLarge(
            field: field,
            maximumUTF8Bytes: maximumUTF8Bytes
        )
    }
    guard allowsEmpty || !value.isEmpty,
        value == value.precomposedStringWithCanonicalMapping,
        !value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
                || CharacterSet.newlines.contains($0)
                || (0x202A...0x202E).contains($0.value)
                || (0x2066...0x2069).contains($0.value)
        })
    else {
        throw EditorPreferencesWorkflow.Error.invalidString(field: field)
    }
}

private func normalizedBoundedString(
    _ value: String,
    field: EditorPreferencesWorkflow.StringField,
    maximumUTF8Bytes: Int,
    allowsEmpty: Bool
) throws -> String {
    guard value.utf8.prefix(maximumUTF8Bytes + 1).count <= maximumUTF8Bytes else {
        throw EditorPreferencesWorkflow.Error.stringTooLarge(
            field: field,
            maximumUTF8Bytes: maximumUTF8Bytes
        )
    }
    let normalized = value.precomposedStringWithCanonicalMapping
    try validateBoundedString(
        normalized,
        field: field,
        maximumUTF8Bytes: maximumUTF8Bytes,
        allowsEmpty: allowsEmpty
    )
    return normalized
}

private func freshLineage() -> UInt64 {
    var lineage: UInt64 = 0
    repeat {
        let uuid = UUID().uuid
        lineage = withUnsafeBytes(of: uuid) { rawBuffer in
            rawBuffer.prefix(MemoryLayout<UInt64>.size).enumerated().reduce(0) { value, pair in
                value | UInt64(pair.element) << UInt64(pair.offset * 8)
            }
        }
    } while lineage == 0
    return lineage
}

private func validatePortableIdentifier(
    _ value: String,
    field: EditorPreferencesWorkflow.StringField,
    maximumUTF8Bytes: Int,
    allowsEditorColorSchemeSeparators: Bool = false
) throws {
    try validateBoundedString(
        value,
        field: field,
        maximumUTF8Bytes: maximumUTF8Bytes,
        allowsEmpty: false
    )
    guard let first = value.utf8.first, let last = value.utf8.last,
        isEditorPreferenceASCIIAlphanumeric(first),
        isEditorPreferenceASCIIAlphanumeric(last),
        value.utf8.allSatisfy({
            isEditorPreferenceASCIIAlphanumeric($0)
                || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
                || (allowsEditorColorSchemeSeparators && ($0 == 0x2F || $0 == 0x3A))
        })
    else {
        throw EditorPreferencesWorkflow.Error.invalidString(field: field)
    }
}

private func isEditorPreferenceASCIIAlphanumeric(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)
        || (0x61...0x7A).contains(byte)
}
