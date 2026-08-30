import Foundation

/// UI-independent sizing, customization, and deterministic overflow planning for the native toolbar.
public struct ToolbarOverflowPlan: Equatable, Sendable {
    public typealias Command = ToolbarConfiguration.Command
    public typealias Item = ToolbarConfiguration.Item
    public typealias CancellationCheck = @Sendable () throws -> Void

    public enum Size: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case none
        case small
        case medium
        case big
        case huge

        public var imageDimension: Double {
            switch self {
            case .none: 0
            case .small: 16
            case .medium: 24
            case .big: 32
            case .huge: 40
            }
        }

        public var defaultCommandWidth: Double {
            self == .none ? 0 : imageDimension + 8
        }

        public init(_ size: ToolbarConfiguration.Size) {
            switch size {
            case .small: self = .small
            case .medium: self = .medium
            case .big: self = .big
            case .huge: self = .huge
            }
        }

        public var toolbarConfigurationSize: ToolbarConfiguration.Size? {
            switch self {
            case .none: nil
            case .small: .small
            case .medium: .medium
            case .big: .big
            case .huge: .huge
            }
        }
    }

    /// Commands that share a separator-delimited section in configured order.
    public struct CommandGroup: Equatable, Sendable {
        public let commands: [Command]
        public let hasTrailingSeparator: Bool

        public init(
            commands: [Command],
            hasTrailingSeparator: Bool
        ) throws {
            guard
                commands.count
                    <= Self.maximumCommandCount(hasTrailingSeparator: hasTrailingSeparator)
            else {
                throw ToolbarOverflowPlanError.tooManyItems(
                    maximumCount: Limits.hardMaximumItemCount
                )
            }
            self.commands = commands
            self.hasTrailingSeparator = hasTrailingSeparator
        }

        public var items: [Item] {
            var items: [Item] = []
            items.reserveCapacity(commands.count + (hasTrailingSeparator ? 1 : 0))
            for command in commands { items.append(.command(command)) }
            if hasTrailingSeparator { items.append(.separator) }
            return items
        }

        fileprivate init(boundedCommands commands: [Command], hasTrailingSeparator: Bool) {
            precondition(
                commands.count
                    <= Self.maximumCommandCount(hasTrailingSeparator: hasTrailingSeparator)
            )
            self.commands = commands
            self.hasTrailingSeparator = hasTrailingSeparator
        }

        private static func maximumCommandCount(hasTrailingSeparator: Bool) -> Int {
            Limits.hardMaximumItemCount - (hasTrailingSeparator ? 1 : 0)
        }
    }

    public struct Limits: Equatable, Sendable {
        public static let hardMaximumItemCount = 64
        public static let hardMaximumGroupCount = 32
        public static let hardMaximumPriorityCount = 64
        public static let hardMaximumPinnedCount = 64
        public static let hardMaximumOverflowItemCount = 64
        public static let hardMaximumWork = 1_000_000
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumItemCount: Int
        public let maximumGroupCount: Int
        public let maximumPriorityCount: Int
        public let maximumPinnedCount: Int
        public let maximumOverflowItemCount: Int
        public let maximumWork: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumItemCount: Int = Limits.hardMaximumItemCount,
            maximumGroupCount: Int = Limits.hardMaximumGroupCount,
            maximumPriorityCount: Int = Limits.hardMaximumPriorityCount,
            maximumPinnedCount: Int = Limits.hardMaximumPinnedCount,
            maximumOverflowItemCount: Int = Limits.hardMaximumOverflowItemCount,
            maximumWork: Int = 32_768,
            cancellationCheckInterval: Int = 16
        ) {
            self.maximumItemCount = maximumItemCount
            self.maximumGroupCount = maximumGroupCount
            self.maximumPriorityCount = maximumPriorityCount
            self.maximumPinnedCount = maximumPinnedCount
            self.maximumOverflowItemCount = maximumOverflowItemCount
            self.maximumWork = maximumWork
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            try Self.validate(
                maximumItemCount,
                name: "maximumItemCount",
                range: 0...Self.hardMaximumItemCount
            )
            try Self.validate(
                maximumGroupCount,
                name: "maximumGroupCount",
                range: 0...Self.hardMaximumGroupCount
            )
            try Self.validate(
                maximumPriorityCount,
                name: "maximumPriorityCount",
                range: 0...Self.hardMaximumPriorityCount
            )
            try Self.validate(
                maximumPinnedCount,
                name: "maximumPinnedCount",
                range: 0...Self.hardMaximumPinnedCount
            )
            try Self.validate(
                maximumOverflowItemCount,
                name: "maximumOverflowItemCount",
                range: 0...Self.hardMaximumOverflowItemCount
            )
            try Self.validate(
                maximumWork,
                name: "maximumWork",
                range: 1...Self.hardMaximumWork
            )
            try Self.validate(
                cancellationCheckInterval,
                name: "cancellationCheckInterval",
                range: 1...Self.hardMaximumCancellationCheckInterval
            )
        }

        private static func validate(
            _ value: Int,
            name: String,
            range: ClosedRange<Int>
        ) throws {
            guard range.contains(value) else {
                throw ToolbarOverflowPlanError.invalidLimit(name: name, value: value)
            }
        }
    }

    public struct Widths: Equatable, Sendable {
        public static let defaultSeparatorWidth = 8.0
        public static let defaultOverflowControlWidth = 28.0
        public static let maximumItemWidth = 1_000_000.0
        public static let maximumAvailableWidth = 1_000_000_000.0

        public let commandWidths: [Command: Double]
        public let separatorWidth: Double
        public let overflowControlWidth: Double

        public init(
            commandWidths: [Command: Double] = [:],
            separatorWidth: Double = Widths.defaultSeparatorWidth,
            overflowControlWidth: Double = Widths.defaultOverflowControlWidth
        ) throws {
            self.commandWidths = commandWidths
            self.separatorWidth = separatorWidth
            self.overflowControlWidth = overflowControlWidth
            try validate()
        }

        public init(_ metrics: ToolbarConfiguration.LayoutMetrics) throws {
            try self.init(
                commandWidths: metrics.commandWidths,
                separatorWidth: metrics.separatorWidth,
                overflowControlWidth: metrics.overflowButtonWidth
            )
        }

        public func toolbarLayoutMetrics() throws -> ToolbarConfiguration.LayoutMetrics {
            try ToolbarConfiguration.LayoutMetrics(
                commandWidths: commandWidths,
                separatorWidth: separatorWidth,
                overflowButtonWidth: overflowControlWidth
            )
        }

        public func width(of item: Item, size: Size) -> Double {
            switch item {
            case .command(let command): commandWidths[command] ?? size.defaultCommandWidth
            case .separator: separatorWidth
            }
        }

        public func validate() throws {
            guard commandWidths.count <= Command.allCases.count else {
                throw ToolbarOverflowPlanError.tooManyCommandWidths(
                    maximumCount: Command.allCases.count
                )
            }
            for (command, width) in commandWidths {
                guard width.isFinite, width > 0, width <= Self.maximumItemWidth else {
                    throw ToolbarOverflowPlanError.invalidCommandWidth(command)
                }
            }
            guard separatorWidth.isFinite,
                separatorWidth >= 0,
                separatorWidth <= Self.maximumItemWidth
            else {
                throw ToolbarOverflowPlanError.invalidSeparatorWidth
            }
            guard overflowControlWidth.isFinite,
                overflowControlWidth > 0,
                overflowControlWidth <= Self.maximumItemWidth
            else {
                throw ToolbarOverflowPlanError.invalidOverflowControlWidth
            }
        }
    }

    /// Persisted toolbar choices. Width measurements and available window width remain transient.
    public struct Customization: Encodable, Equatable, Sendable {
        public static let currentSchemaVersion = 1
        public static let maximumEncodedBytes = 16 * 1_024

        public static let winMergeDefault = Customization(
            schemaVersion: currentSchemaVersion,
            size: .small,
            items: ToolbarOverflowPlan.winMergeDefaultItems,
            priorities: [:],
            pinnedCommands: []
        )

        public let schemaVersion: Int
        public private(set) var size: Size
        public private(set) var items: [Item]
        public private(set) var priorities: [Command: Int]
        public private(set) var pinnedCommands: Set<Command>

        public var commandGroups: [CommandGroup] {
            ToolbarOverflowPlan.commandGroups(from: items)
        }

        public var commands: [Command] {
            items.compactMap(\.command)
        }

        public var isCustomized: Bool {
            self != Self.winMergeDefault
        }

        public init(
            size: Size = .small,
            items: [Item] = ToolbarOverflowPlan.winMergeDefaultItems,
            priorities: [Command: Int] = [:],
            pinnedCommands: Set<Command> = [],
            limits: Limits = .default
        ) throws {
            self.init(
                schemaVersion: Self.currentSchemaVersion,
                size: size,
                items: items,
                priorities: priorities,
                pinnedCommands: pinnedCommands
            )
            try validate(limits: limits)
        }

        public init(
            size: Size = .small,
            groups: [CommandGroup],
            priorities: [Command: Int] = [:],
            pinnedCommands: Set<Command> = [],
            limits: Limits = .default
        ) throws {
            let items = try ToolbarOverflowPlan.flattenedItems(from: groups, limits: limits)
            try self.init(
                size: size,
                items: items,
                priorities: priorities,
                pinnedCommands: pinnedCommands,
                limits: limits
            )
        }

        public init(
            toolbarConfiguration: ToolbarConfiguration,
            priorities: [Command: Int] = [:],
            pinnedCommands: Set<Command> = [],
            limits: Limits = .default
        ) throws {
            try toolbarConfiguration.validate()
            guard toolbarConfiguration.isVisible || toolbarConfiguration.size == .small else {
                throw ToolbarOverflowPlanError.hiddenToolbarSizeNotRepresentable(
                    toolbarConfiguration.size
                )
            }
            let size =
                toolbarConfiguration.isVisible
                ? Size(toolbarConfiguration.size)
                : .none
            try self.init(
                size: size,
                items: toolbarConfiguration.items,
                priorities: priorities,
                pinnedCommands: pinnedCommands,
                limits: limits
            )
        }

        public mutating func setSize(_ size: Size) {
            self.size = size
        }

        public mutating func setItems(
            _ items: [Item],
            limits: Limits = .default
        ) throws {
            var candidate = self
            candidate.items = items
            try candidate.validate(limits: limits)
            self = candidate
        }

        public mutating func setGroups(
            _ groups: [CommandGroup],
            limits: Limits = .default
        ) throws {
            let items = try ToolbarOverflowPlan.flattenedItems(from: groups, limits: limits)
            try setItems(items, limits: limits)
        }

        public mutating func setPriority(
            _ priority: Int?,
            for command: Command,
            limits: Limits = .default
        ) throws {
            var candidate = self
            candidate.priorities[command] = priority
            try candidate.validate(limits: limits)
            self = candidate
        }

        public mutating func setPinned(
            _ isPinned: Bool,
            for command: Command,
            limits: Limits = .default
        ) throws {
            var candidate = self
            if isPinned {
                candidate.pinnedCommands.insert(command)
            } else {
                candidate.pinnedCommands.remove(command)
            }
            try candidate.validate(limits: limits)
            self = candidate
        }

        public mutating func resetToWinMergeDefaults() {
            self = Self.winMergeDefault
        }

        public mutating func reset() {
            resetToWinMergeDefaults()
        }

        public func priority(of command: Command) -> Int {
            priorities[command] ?? 0
        }

        public func validate(limits: Limits = .default) throws {
            try limits.validate()
            guard schemaVersion == Self.currentSchemaVersion else {
                throw ToolbarOverflowPlanError.unsupportedSchemaVersion(schemaVersion)
            }
            try ToolbarOverflowPlan.validate(items: items, limits: limits)
            guard priorities.count <= limits.maximumPriorityCount else {
                throw ToolbarOverflowPlanError.tooManyPriorities(
                    maximumCount: limits.maximumPriorityCount
                )
            }
            guard pinnedCommands.count <= limits.maximumPinnedCount else {
                throw ToolbarOverflowPlanError.tooManyPinnedCommands(
                    maximumCount: limits.maximumPinnedCount
                )
            }

            let commandSet = Set(commands)
            for (command, priority) in priorities {
                guard commandSet.contains(command) else {
                    throw ToolbarOverflowPlanError.priorityForMissingCommand(command)
                }
                guard ToolbarOverflowPlan.priorityRange.contains(priority) else {
                    throw ToolbarOverflowPlanError.invalidPriority(
                        command: command,
                        value: priority
                    )
                }
            }
            for command in pinnedCommands where !commandSet.contains(command) {
                throw ToolbarOverflowPlanError.pinnedCommandMissing(command)
            }
        }

        /// Compact, stable JSON suitable for `UserDefaults` or scene persistence.
        public func encodedData() throws -> Data {
            try validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(self)
            guard data.count <= Self.maximumEncodedBytes else {
                throw ToolbarOverflowPlanError.encodedDataTooLarge(
                    maximumBytes: Self.maximumEncodedBytes
                )
            }
            return data
        }

        /// Decodes only after bounded, duplicate-key-rejecting structural JSON validation.
        public static func decode(from data: Data) throws -> Customization {
            guard data.count <= maximumEncodedBytes else {
                throw ToolbarOverflowPlanError.encodedDataTooLarge(
                    maximumBytes: maximumEncodedBytes
                )
            }
            try ToolbarOverflowPlan.preflightJSON(data)
            let customization = try JSONDecoder().decode(CustomizationWire.self, from: data)
                .customization
            try customization.validate()
            return customization
        }

        public func toolbarConfiguration() throws -> ToolbarConfiguration {
            let visibility: ToolbarConfiguration.Visibility = size == .none ? .hidden : .visible
            return try ToolbarConfiguration(
                visibility: visibility,
                size: size.toolbarConfigurationSize ?? .small,
                items: items
            )
        }

        fileprivate init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ToolbarOverflowCodingKey.self)
            let schemaVersion = try container.decode(
                Int.self,
                forKey: ToolbarOverflowCodingKey("schemaVersion")
            )
            guard schemaVersion == Self.currentSchemaVersion else {
                throw ToolbarOverflowPlanError.unsupportedSchemaVersion(schemaVersion)
            }
            try rejectUnknownFields(container, allowed: Self.codingFields)
            let size = try container.decode(
                Size.self,
                forKey: ToolbarOverflowCodingKey("size")
            )
            let items = try Self.decodeItems(
                from: container,
                forKey: ToolbarOverflowCodingKey("items")
            )
            let priorities = try Self.decodePriorities(
                from: container,
                forKey: ToolbarOverflowCodingKey("priorities")
            )
            let pinnedCommands = try Self.decodePinnedCommands(
                from: container,
                forKey: ToolbarOverflowCodingKey("pinnedCommands")
            )

            self.init(
                schemaVersion: schemaVersion,
                size: size,
                items: items,
                priorities: priorities,
                pinnedCommands: pinnedCommands
            )
            try validate()
        }

        public func encode(to encoder: Encoder) throws {
            try validate()
            var container = encoder.container(keyedBy: ToolbarOverflowCodingKey.self)
            try container.encode(
                schemaVersion,
                forKey: ToolbarOverflowCodingKey("schemaVersion")
            )
            try container.encode(size, forKey: ToolbarOverflowCodingKey("size"))
            try container.encode(
                items.map(Self.wireValue),
                forKey: ToolbarOverflowCodingKey("items")
            )
            let priorityEntries = priorities.map(PriorityEntry.init)
                .sorted { $0.command.rawValue < $1.command.rawValue }
            try container.encode(
                priorityEntries,
                forKey: ToolbarOverflowCodingKey("priorities")
            )
            try container.encode(
                pinnedCommands.sorted { $0.rawValue < $1.rawValue },
                forKey: ToolbarOverflowCodingKey("pinnedCommands")
            )
        }

        private static let codingFields: Set<String> = [
            "schemaVersion", "size", "items", "priorities", "pinnedCommands"
        ]

        private init(
            schemaVersion: Int,
            size: Size,
            items: [Item],
            priorities: [Command: Int],
            pinnedCommands: Set<Command>
        ) {
            self.schemaVersion = schemaVersion
            self.size = size
            self.items = items
            self.priorities = priorities
            self.pinnedCommands = pinnedCommands
        }

        private static func decodeItems(
            from container: KeyedDecodingContainer<ToolbarOverflowCodingKey>,
            forKey key: ToolbarOverflowCodingKey
        ) throws -> [Item] {
            var values = try container.nestedUnkeyedContainer(forKey: key)
            if let count = values.count, count > Limits.hardMaximumItemCount {
                throw ToolbarOverflowPlanError.tooManyItems(
                    maximumCount: Limits.hardMaximumItemCount
                )
            }
            var items: [Item] = []
            items.reserveCapacity(min(values.count ?? 0, Limits.hardMaximumItemCount))
            while !values.isAtEnd {
                guard items.count < Limits.hardMaximumItemCount else {
                    throw ToolbarOverflowPlanError.tooManyItems(
                        maximumCount: Limits.hardMaximumItemCount
                    )
                }
                let value = try values.decode(String.self)
                if value == ToolbarOverflowPlan.separatorWireValue {
                    items.append(.separator)
                } else if let command = Command(rawValue: value) {
                    items.append(.command(command))
                } else {
                    throw ToolbarOverflowPlanError.unknownCommand(value)
                }
            }
            return items
        }

        private static func decodePriorities(
            from container: KeyedDecodingContainer<ToolbarOverflowCodingKey>,
            forKey key: ToolbarOverflowCodingKey
        ) throws -> [Command: Int] {
            var values = try container.nestedUnkeyedContainer(forKey: key)
            if let count = values.count, count > Limits.hardMaximumPriorityCount {
                throw ToolbarOverflowPlanError.tooManyPriorities(
                    maximumCount: Limits.hardMaximumPriorityCount
                )
            }
            var priorities: [Command: Int] = [:]
            priorities.reserveCapacity(
                min(values.count ?? 0, Limits.hardMaximumPriorityCount)
            )
            while !values.isAtEnd {
                guard priorities.count < Limits.hardMaximumPriorityCount else {
                    throw ToolbarOverflowPlanError.tooManyPriorities(
                        maximumCount: Limits.hardMaximumPriorityCount
                    )
                }
                let entry = try values.decode(PriorityEntry.self)
                guard priorities.updateValue(entry.value, forKey: entry.command) == nil else {
                    throw ToolbarOverflowPlanError.duplicatePriority(entry.command)
                }
            }
            return priorities
        }

        private static func decodePinnedCommands(
            from container: KeyedDecodingContainer<ToolbarOverflowCodingKey>,
            forKey key: ToolbarOverflowCodingKey
        ) throws -> Set<Command> {
            var values = try container.nestedUnkeyedContainer(forKey: key)
            if let count = values.count, count > Limits.hardMaximumPinnedCount {
                throw ToolbarOverflowPlanError.tooManyPinnedCommands(
                    maximumCount: Limits.hardMaximumPinnedCount
                )
            }
            var commands: Set<Command> = []
            while !values.isAtEnd {
                guard commands.count < Limits.hardMaximumPinnedCount else {
                    throw ToolbarOverflowPlanError.tooManyPinnedCommands(
                        maximumCount: Limits.hardMaximumPinnedCount
                    )
                }
                let rawCommand = try values.decode(String.self)
                guard let command = Command(rawValue: rawCommand) else {
                    throw ToolbarOverflowPlanError.unknownCommand(rawCommand)
                }
                guard commands.insert(command).inserted else {
                    throw ToolbarOverflowPlanError.duplicatePinnedCommand(command)
                }
            }
            return commands
        }

        private static func wireValue(_ item: Item) -> String {
            switch item {
            case .command(let command): command.rawValue
            case .separator: ToolbarOverflowPlan.separatorWireValue
            }
        }
    }

    private struct CustomizationWire: Decodable {
        let customization: Customization

        init(from decoder: Decoder) throws {
            customization = try Customization(from: decoder)
        }
    }

    /// Exact command and separator order from WinMerge's `IDR_MAINFRAME` resource.
    public static let winMergeDefaultItems = ToolbarConfiguration.winMergeDefaultItems
    public static let winMergeDefaultCommands = winMergeDefaultItems.compactMap(\.command)
    public static let winMergeDefaultGroups = commandGroups(from: winMergeDefaultItems)

    public let size: Size
    public let availableWidth: Double
    public let configuredItems: [Item]
    public let visibleItems: [Item]
    public let overflowItems: [Item]
    public let showsOverflowControl: Bool
    public let occupiedWidth: Double
    public let workPerformed: Int

    public var isToolbarVisible: Bool { size != .none }
    public var visibleCommands: [Command] { visibleItems.compactMap(\.command) }
    public var overflowCommands: [Command] { overflowItems.compactMap(\.command) }
    public var visibleGroups: [CommandGroup] { Self.commandGroups(from: visibleItems) }
    public var overflowGroups: [CommandGroup] { Self.commandGroups(from: overflowItems) }

    /// Commands are partitioned exactly once; separators are normalized independently per side.
    public var allConfiguredCommandsAreRepresented: Bool {
        let configured = configuredItems.compactMap(\.command)
        let represented = visibleCommands + overflowCommands
        return represented.count == configured.count && Set(represented) == Set(configured)
    }

    /// Builds a deterministic partition. Higher priority wins; ties retain configured command order.
    public static func make(
        customization: Customization = .winMergeDefault,
        availableWidth: Double,
        widths: Widths? = nil,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ToolbarOverflowPlan {
        try limits.validate()
        try customization.validate(limits: limits)
        guard availableWidth.isFinite,
            availableWidth >= 0,
            availableWidth <= Widths.maximumAvailableWidth
        else {
            throw ToolbarOverflowPlanError.invalidAvailableWidth
        }
        let widths = try widths ?? Widths()
        try widths.validate()

        var budget = WorkBudget(
            maximumWork: limits.maximumWork,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try budget.checkCancellation()

        if customization.size == .none {
            try validateOverflowCount(customization.items.count, limits: limits)
            return ToolbarOverflowPlan(
                size: .none,
                availableWidth: availableWidth,
                configuredItems: customization.items,
                visibleItems: [],
                overflowItems: customization.items,
                showsOverflowControl: false,
                occupiedWidth: 0,
                workPerformed: budget.completedWork
            )
        }

        let groups = try commandGroups(from: customization.items, budget: &budget)
        let commands = customization.commands
        guard !commands.isEmpty else {
            return ToolbarOverflowPlan(
                size: customization.size,
                availableWidth: availableWidth,
                configuredItems: [],
                visibleItems: [],
                overflowItems: [],
                showsOverflowControl: false,
                occupiedWidth: 0,
                workPerformed: budget.completedWork
            )
        }

        let fullWidth = try measuredWidth(
            of: customization.items,
            size: customization.size,
            widths: widths,
            budget: &budget
        )
        if fullWidth <= availableWidth {
            return ToolbarOverflowPlan(
                size: customization.size,
                availableWidth: availableWidth,
                configuredItems: customization.items,
                visibleItems: customization.items,
                overflowItems: [],
                showsOverflowControl: false,
                occupiedWidth: fullWidth,
                workPerformed: budget.completedWork
            )
        }

        if customization.pinnedCommands.count < commands.count {
            guard widths.overflowControlWidth <= availableWidth else {
                throw ToolbarOverflowPlanError.overflowControlDoesNotFit
            }
        }

        var selected = customization.pinnedCommands
        let nonPinned = try rankedNonPinnedCommands(
            commands,
            priorities: customization.priorities,
            pinnedCommands: customization.pinnedCommands,
            budget: &budget
        )

        var visibleItems = try renderedItems(
            from: groups,
            selecting: selected,
            budget: &budget
        )
        var occupiedWidth = try measuredWidth(
            of: visibleItems,
            size: customization.size,
            widths: widths,
            budget: &budget
        )
        if selected.count < commands.count {
            occupiedWidth = try addingWidth(
                widths.overflowControlWidth,
                to: occupiedWidth
            )
        }
        guard occupiedWidth <= availableWidth else {
            throw ToolbarOverflowPlanError.pinnedCommandsDoNotFit
        }

        for command in nonPinned {
            try budget.consume()
            var candidateSelection = selected
            candidateSelection.insert(command)
            let candidateItems = try renderedItems(
                from: groups,
                selecting: candidateSelection,
                budget: &budget
            )
            var candidateWidth = try measuredWidth(
                of: candidateItems,
                size: customization.size,
                widths: widths,
                budget: &budget
            )
            if candidateSelection.count < commands.count {
                candidateWidth = try addingWidth(
                    widths.overflowControlWidth,
                    to: candidateWidth
                )
            }
            if candidateWidth <= availableWidth {
                selected = candidateSelection
                visibleItems = candidateItems
                occupiedWidth = candidateWidth
            }
        }

        let overflowSelection = Set(commands).subtracting(selected)
        let overflowItems = try renderedItems(
            from: groups,
            selecting: overflowSelection,
            budget: &budget
        )
        try validateOverflowCount(overflowItems.count, limits: limits)

        return ToolbarOverflowPlan(
            size: customization.size,
            availableWidth: availableWidth,
            configuredItems: customization.items,
            visibleItems: visibleItems,
            overflowItems: overflowItems,
            showsOverflowControl: !overflowSelection.isEmpty,
            occupiedWidth: occupiedWidth,
            workPerformed: budget.completedWork
        )
    }

    private static let separatorWireValue = "separator"
    fileprivate static let priorityRange = -1_000_000...1_000_000

    private init(
        size: Size,
        availableWidth: Double,
        configuredItems: [Item],
        visibleItems: [Item],
        overflowItems: [Item],
        showsOverflowControl: Bool,
        occupiedWidth: Double,
        workPerformed: Int
    ) {
        self.size = size
        self.availableWidth = availableWidth
        self.configuredItems = configuredItems
        self.visibleItems = visibleItems
        self.overflowItems = overflowItems
        self.showsOverflowControl = showsOverflowControl
        self.occupiedWidth = occupiedWidth
        self.workPerformed = workPerformed
    }

    private static func validate(items: [Item], limits: Limits) throws {
        guard items.count <= limits.maximumItemCount else {
            throw ToolbarOverflowPlanError.tooManyItems(
                maximumCount: limits.maximumItemCount
            )
        }
        var seen: Set<Command> = []
        var groupCount = 0
        var hasCommandSinceSeparator = false
        for item in items {
            switch item {
            case .command(let command):
                guard seen.insert(command).inserted else {
                    throw ToolbarOverflowPlanError.duplicateCommand(command)
                }
                hasCommandSinceSeparator = true
            case .separator:
                guard hasCommandSinceSeparator else {
                    throw ToolbarOverflowPlanError.misplacedSeparator
                }
                groupCount += 1
                hasCommandSinceSeparator = false
            }
        }
        if hasCommandSinceSeparator { groupCount += 1 }
        guard groupCount <= limits.maximumGroupCount else {
            throw ToolbarOverflowPlanError.tooManyGroups(
                maximumCount: limits.maximumGroupCount
            )
        }
    }

    private static func flattenedItems(
        from groups: [CommandGroup],
        limits: Limits
    ) throws -> [Item] {
        try limits.validate()
        guard groups.count <= limits.maximumGroupCount else {
            throw ToolbarOverflowPlanError.tooManyGroups(
                maximumCount: limits.maximumGroupCount
            )
        }
        for (index, group) in groups.enumerated() {
            guard !group.commands.isEmpty else {
                throw ToolbarOverflowPlanError.emptyGroup(index: index)
            }
            if index < groups.count - 1, !group.hasTrailingSeparator {
                throw ToolbarOverflowPlanError.missingGroupSeparator(index: index)
            }
        }

        var commandCount = 0
        var separatorCount = 0
        for group in groups {
            let (nextCommandCount, commandCountOverflow) = commandCount.addingReportingOverflow(
                group.commands.count
            )
            guard !commandCountOverflow,
                nextCommandCount <= limits.maximumItemCount
            else {
                throw ToolbarOverflowPlanError.tooManyItems(
                    maximumCount: limits.maximumItemCount
                )
            }
            commandCount = nextCommandCount
            if group.hasTrailingSeparator {
                let (nextSeparatorCount, separatorCountOverflow) = separatorCount.addingReportingOverflow(1)
                guard !separatorCountOverflow else {
                    throw ToolbarOverflowPlanError.tooManyItems(
                        maximumCount: limits.maximumItemCount
                    )
                }
                separatorCount = nextSeparatorCount
            }
        }
        let (itemCount, itemCountOverflow) = commandCount.addingReportingOverflow(separatorCount)
        guard !itemCountOverflow, itemCount <= limits.maximumItemCount else {
            throw ToolbarOverflowPlanError.tooManyItems(
                maximumCount: limits.maximumItemCount
            )
        }

        var items: [Item] = []
        items.reserveCapacity(itemCount)
        for group in groups {
            for command in group.commands { items.append(.command(command)) }
            if group.hasTrailingSeparator { items.append(.separator) }
        }
        return items
    }

    private static func commandGroups(from items: [Item]) -> [CommandGroup] {
        var groups: [CommandGroup] = []
        var commands: [Command] = []
        for item in items {
            switch item {
            case .command(let command):
                commands.append(command)
            case .separator:
                if !commands.isEmpty {
                    groups.append(
                        CommandGroup(boundedCommands: commands, hasTrailingSeparator: true)
                    )
                    commands.removeAll(keepingCapacity: true)
                }
            }
        }
        if !commands.isEmpty {
            groups.append(
                CommandGroup(boundedCommands: commands, hasTrailingSeparator: false)
            )
        }
        return groups
    }

    private static func commandGroups(
        from items: [Item],
        budget: inout WorkBudget
    ) throws -> [CommandGroup] {
        var groups: [CommandGroup] = []
        var commands: [Command] = []
        for item in items {
            try budget.consume()
            switch item {
            case .command(let command):
                commands.append(command)
            case .separator:
                groups.append(
                    CommandGroup(boundedCommands: commands, hasTrailingSeparator: true)
                )
                commands.removeAll(keepingCapacity: true)
            }
        }
        if !commands.isEmpty {
            groups.append(
                CommandGroup(boundedCommands: commands, hasTrailingSeparator: false)
            )
        }
        return groups
    }

    private static func renderedItems(
        from groups: [CommandGroup],
        selecting selected: Set<Command>,
        budget: inout WorkBudget
    ) throws -> [Item] {
        struct SelectedGroup {
            let sourceIndex: Int
            let commands: [Command]
        }

        var selectedGroups: [SelectedGroup] = []
        for (sourceIndex, group) in groups.enumerated() {
            var commands: [Command] = []
            for command in group.commands {
                try budget.consume()
                if selected.contains(command) { commands.append(command) }
            }
            if !commands.isEmpty {
                selectedGroups.append(
                    SelectedGroup(sourceIndex: sourceIndex, commands: commands)
                )
            }
        }

        var items: [Item] = []
        for (selectedIndex, selectedGroup) in selectedGroups.enumerated() {
            for command in selectedGroup.commands {
                try budget.consume()
                items.append(.command(command))
            }
            let sourceGroup = groups[selectedGroup.sourceIndex]
            let hasFollowingSelectedGroup = selectedIndex < selectedGroups.count - 1
            let isFinalSourceGroup = selectedGroup.sourceIndex == groups.count - 1
            if sourceGroup.hasTrailingSeparator,
                hasFollowingSelectedGroup || isFinalSourceGroup
            {
                try budget.consume()
                items.append(.separator)
            }
        }
        return items
    }

    private static func rankedNonPinnedCommands(
        _ commands: [Command],
        priorities: [Command: Int],
        pinnedCommands: Set<Command>,
        budget: inout WorkBudget
    ) throws -> [Command] {
        struct RankedCommand {
            let command: Command
            let priority: Int
            let configuredIndex: Int
        }

        var ranked: [RankedCommand] = []
        for (configuredIndex, command) in commands.enumerated() {
            try budget.consume()
            guard !pinnedCommands.contains(command) else { continue }
            let candidate = RankedCommand(
                command: command,
                priority: priorities[command] ?? 0,
                configuredIndex: configuredIndex
            )
            var insertionIndex = ranked.count
            while insertionIndex > 0 {
                try budget.consume()
                let previous = ranked[insertionIndex - 1]
                let candidatePrecedes =
                    candidate.priority > previous.priority
                    || (candidate.priority == previous.priority
                        && candidate.configuredIndex < previous.configuredIndex)
                guard candidatePrecedes else { break }
                insertionIndex -= 1
            }
            ranked.insert(candidate, at: insertionIndex)
        }
        return ranked.map(\.command)
    }

    private static func measuredWidth(
        of items: [Item],
        size: Size,
        widths: Widths,
        budget: inout WorkBudget
    ) throws -> Double {
        var total = 0.0
        for item in items {
            try budget.consume()
            total = try addingWidth(widths.width(of: item, size: size), to: total)
        }
        return total
    }

    private static func addingWidth(_ width: Double, to total: Double) throws -> Double {
        guard total <= Widths.maximumAvailableWidth - width else {
            throw ToolbarOverflowPlanError.widthOverflow
        }
        let result = total + width
        guard result.isFinite else { throw ToolbarOverflowPlanError.widthOverflow }
        return result
    }

    private static func validateOverflowCount(_ count: Int, limits: Limits) throws {
        guard count <= limits.maximumOverflowItemCount else {
            throw ToolbarOverflowPlanError.overflowLimitExceeded(
                maximumCount: limits.maximumOverflowItemCount
            )
        }
    }

    private static func preflightJSON(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            var scanner = ToolbarOverflowJSONScanner(
                bytes: rawBuffer.bindMemory(to: UInt8.self)
            )
            try scanner.validate()
        }
    }
}

extension ToolbarConfiguration {
    public init(overflowCustomization: ToolbarOverflowPlan.Customization) throws {
        self = try overflowCustomization.toolbarConfiguration()
    }
}

public enum ToolbarOverflowPlanError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimit(name: String, value: Int)
    case tooManyItems(maximumCount: Int)
    case tooManyGroups(maximumCount: Int)
    case tooManyPriorities(maximumCount: Int)
    case tooManyPinnedCommands(maximumCount: Int)
    case tooManyCommandWidths(maximumCount: Int)
    case duplicateCommand(ToolbarOverflowPlan.Command)
    case duplicatePriority(ToolbarOverflowPlan.Command)
    case duplicatePinnedCommand(ToolbarOverflowPlan.Command)
    case misplacedSeparator
    case emptyGroup(index: Int)
    case missingGroupSeparator(index: Int)
    case priorityForMissingCommand(ToolbarOverflowPlan.Command)
    case pinnedCommandMissing(ToolbarOverflowPlan.Command)
    case invalidPriority(command: ToolbarOverflowPlan.Command, value: Int)
    case invalidAvailableWidth
    case invalidCommandWidth(ToolbarOverflowPlan.Command)
    case invalidSeparatorWidth
    case invalidOverflowControlWidth
    case widthOverflow
    case hiddenToolbarSizeNotRepresentable(ToolbarConfiguration.Size)
    case overflowControlDoesNotFit
    case pinnedCommandsDoNotFit
    case overflowLimitExceeded(maximumCount: Int)
    case workLimitExceeded(maximumWork: Int)
    case encodedDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case unknownField(String)
    case unknownCommand(String)
    case invalidJSON
    case jsonNestingTooDeep(maximumDepth: Int)
    case jsonContainerTooLarge(maximumElements: Int)
    case tooManyJSONValues(maximumValues: Int)
    case jsonStringTooLarge(maximumBytes: Int)
    case jsonNumberTooLarge(maximumBytes: Int)
    case duplicateJSONKey(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value):
            "Invalid toolbar overflow limit \(name): \(value)."
        case .tooManyItems(let maximumCount):
            "Toolbar customization cannot exceed \(maximumCount) items."
        case .tooManyGroups(let maximumCount):
            "Toolbar customization cannot exceed \(maximumCount) command groups."
        case .tooManyPriorities(let maximumCount):
            "Toolbar customization cannot exceed \(maximumCount) command priorities."
        case .tooManyPinnedCommands(let maximumCount):
            "Toolbar customization cannot exceed \(maximumCount) pinned commands."
        case .tooManyCommandWidths(let maximumCount):
            "Toolbar layout cannot exceed \(maximumCount) command widths."
        case .duplicateCommand(let command):
            "Toolbar command appears more than once: \(command.rawValue)."
        case .duplicatePriority(let command):
            "Toolbar priority appears more than once: \(command.rawValue)."
        case .duplicatePinnedCommand(let command):
            "Pinned toolbar command appears more than once: \(command.rawValue)."
        case .misplacedSeparator:
            "Toolbar separators must follow a nonempty command group."
        case .emptyGroup(let index):
            "Toolbar command group \(index) is empty."
        case .missingGroupSeparator(let index):
            "Toolbar command group \(index) must end with a separator."
        case .priorityForMissingCommand(let command):
            "Toolbar priority refers to missing command \(command.rawValue)."
        case .pinnedCommandMissing(let command):
            "Pinned toolbar command is missing: \(command.rawValue)."
        case .invalidPriority(let command, let value):
            "Priority \(value) for toolbar command \(command.rawValue) is outside the supported range."
        case .invalidAvailableWidth:
            "Available toolbar width must be finite, nonnegative, and bounded."
        case .invalidCommandWidth(let command):
            "Width for toolbar command \(command.rawValue) is invalid."
        case .invalidSeparatorWidth:
            "Toolbar separator width must be finite, nonnegative, and bounded."
        case .invalidOverflowControlWidth:
            "Toolbar overflow control width must be finite, positive, and bounded."
        case .widthOverflow:
            "Toolbar width arithmetic exceeded the supported bound."
        case .hiddenToolbarSizeNotRepresentable(let size):
            "Hidden toolbar size \(size.rawValue) cannot be represented without losing configuration."
        case .overflowControlDoesNotFit:
            "Available toolbar width cannot contain the overflow control."
        case .pinnedCommandsDoNotFit:
            "Pinned toolbar commands and the required overflow control do not fit."
        case .overflowLimitExceeded(let maximumCount):
            "Toolbar overflow cannot exceed \(maximumCount) items."
        case .workLimitExceeded(let maximumWork):
            "Toolbar planning exceeds the \(maximumWork)-unit work limit."
        case .encodedDataTooLarge(let maximumBytes):
            "Toolbar customization exceeds the \(maximumBytes)-byte persistence limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported toolbar customization schema version: \(version)."
        case .unknownField(let field):
            "Unknown toolbar customization field: \(field)."
        case .unknownCommand(let command):
            "Unknown toolbar command: \(command)."
        case .invalidJSON:
            "Toolbar customization is not valid strict JSON."
        case .jsonNestingTooDeep(let maximumDepth):
            "Toolbar customization JSON exceeds \(maximumDepth) nesting levels."
        case .jsonContainerTooLarge(let maximumElements):
            "A toolbar customization JSON container exceeds \(maximumElements) elements."
        case .tooManyJSONValues(let maximumValues):
            "Toolbar customization JSON exceeds \(maximumValues) values."
        case .jsonStringTooLarge(let maximumBytes):
            "A toolbar customization JSON string exceeds \(maximumBytes) UTF-8 bytes."
        case .jsonNumberTooLarge(let maximumBytes):
            "A toolbar customization JSON number exceeds \(maximumBytes) bytes."
        case .duplicateJSONKey(let key):
            "Toolbar customization JSON repeats key \(key)."
        }
    }
}

private struct WorkBudget {
    let maximumWork: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: ToolbarOverflowPlan.CancellationCheck
    private(set) var completedWork = 0

    mutating func consume() throws {
        guard completedWork < maximumWork else {
            throw ToolbarOverflowPlanError.workLimitExceeded(maximumWork: maximumWork)
        }
        completedWork += 1
        if completedWork.isMultiple(of: cancellationCheckInterval) {
            try cancellationCheck()
        }
    }

    func checkCancellation() throws {
        try cancellationCheck()
    }
}

private struct PriorityEntry: Codable {
    static let codingFields: Set<String> = ["command", "value"]

    let command: ToolbarOverflowPlan.Command
    let value: Int

    init(command: ToolbarOverflowPlan.Command, value: Int) {
        self.command = command
        self.value = value
    }

    init(_ element: (key: ToolbarOverflowPlan.Command, value: Int)) {
        command = element.key
        value = element.value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ToolbarOverflowCodingKey.self)
        try rejectUnknownFields(container, allowed: Self.codingFields)
        let rawCommand = try container.decode(
            String.self,
            forKey: ToolbarOverflowCodingKey("command")
        )
        guard let command = ToolbarOverflowPlan.Command(rawValue: rawCommand) else {
            throw ToolbarOverflowPlanError.unknownCommand(rawCommand)
        }
        self.command = command
        value = try container.decode(
            Int.self,
            forKey: ToolbarOverflowCodingKey("value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ToolbarOverflowCodingKey.self)
        try container.encode(
            command.rawValue,
            forKey: ToolbarOverflowCodingKey("command")
        )
        try container.encode(value, forKey: ToolbarOverflowCodingKey("value"))
    }
}

private struct ToolbarOverflowCodingKey: CodingKey, Hashable {
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

private func rejectUnknownFields<Value>(
    _ container: KeyedDecodingContainer<Value>,
    allowed: Set<String>
) throws where Value: CodingKey {
    if let field = container.allKeys.map(\.stringValue)
        .filter({ !allowed.contains($0) })
        .sorted()
        .first
    {
        throw ToolbarOverflowPlanError.unknownField(field)
    }
}

private struct ToolbarOverflowJSONScanner {
    private static let maximumNestingDepth = 8
    private static let maximumContainerElements = 80
    private static let maximumValueCount = 512
    private static let maximumKeyUTF8Bytes = 64
    private static let maximumStringUTF8Bytes = 128
    private static let maximumTotalStringUTF8Bytes = 12 * 1_024
    private static let maximumNumberBytes = 32

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
        guard index == bytes.count else { throw ToolbarOverflowPlanError.invalidJSON }
    }

    private mutating func parseValue(depth: Int) throws {
        guard valueCount < Self.maximumValueCount else {
            throw ToolbarOverflowPlanError.tooManyJSONValues(
                maximumValues: Self.maximumValueCount
            )
        }
        valueCount += 1
        guard let byte = currentByte else { throw ToolbarOverflowPlanError.invalidJSON }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString(maximumBytes: Self.maximumStringUTF8Bytes, capture: false)
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw ToolbarOverflowPlanError.invalidJSON
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
            guard currentByte == 0x22 else { throw ToolbarOverflowPlanError.invalidJSON }
            let key = try parseString(maximumBytes: Self.maximumKeyUTF8Bytes, capture: true)
            guard keys.insert(key).inserted else {
                throw ToolbarOverflowPlanError.duplicateJSONKey(key)
            }
            skipWhitespace()
            guard consume(0x3A) else { throw ToolbarOverflowPlanError.invalidJSON }
            skipWhitespace()
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw ToolbarOverflowPlanError.invalidJSON }
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
            guard consume(0x2C) else { throw ToolbarOverflowPlanError.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseString(maximumBytes: Int, capture: Bool) throws -> String {
        guard consume(0x22) else { throw ToolbarOverflowPlanError.invalidJSON }
        var decodedBytes: [UInt8] = []
        if capture { decodedBytes.reserveCapacity(min(maximumBytes, 32)) }
        var byteCount = 0

        while let byte = currentByte {
            switch byte {
            case 0x22:
                index += 1
                return capture ? String(decoding: decodedBytes, as: UTF8.self) : ""
            case 0x00...0x1F:
                throw ToolbarOverflowPlanError.invalidJSON
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
        throw ToolbarOverflowPlanError.invalidJSON
    }

    private mutating func parseEscape(
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        capture: Bool
    ) throws {
        guard let escaped = currentByte else { throw ToolbarOverflowPlanError.invalidJSON }
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
            try appendEscapedByte(
                0x08,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        case 0x66:
            try appendEscapedByte(
                0x0C,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        case 0x6E:
            try appendEscapedByte(
                0x0A,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        case 0x72:
            try appendEscapedByte(
                0x0D,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        case 0x74:
            try appendEscapedByte(
                0x09,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        case 0x75:
            try appendEscapedScalar(
                parseUnicodeScalar(),
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        default:
            throw ToolbarOverflowPlanError.invalidJSON
        }
    }

    private mutating func parseUnicodeScalar() throws -> UInt32 {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            guard consume(0x5C), consume(0x75) else {
                throw ToolbarOverflowPlanError.invalidJSON
            }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw ToolbarOverflowPlanError.invalidJSON
            }
            return 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
        }
        guard !(0xDC00...0xDFFF).contains(first) else {
            throw ToolbarOverflowPlanError.invalidJSON
        }
        return UInt32(first)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw ToolbarOverflowPlanError.invalidJSON
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
        guard byteCount <= maximumBytes - addedCount else {
            throw ToolbarOverflowPlanError.jsonStringTooLarge(maximumBytes: maximumBytes)
        }
        guard totalStringByteCount <= Self.maximumTotalStringUTF8Bytes - addedCount else {
            throw ToolbarOverflowPlanError.jsonStringTooLarge(
                maximumBytes: Self.maximumTotalStringUTF8Bytes
            )
        }
        byteCount += addedCount
        totalStringByteCount += addedCount
    }

    private func rawUTF8ScalarLength() throws -> Int {
        guard let first = currentByte else { throw ToolbarOverflowPlanError.invalidJSON }
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
            throw ToolbarOverflowPlanError.invalidJSON
        }
        guard index <= bytes.count - length,
            secondRange.contains(bytes[index + 1])
        else {
            throw ToolbarOverflowPlanError.invalidJSON
        }
        for offset in 2..<length where !(0x80...0xBF).contains(bytes[index + offset]) {
            throw ToolbarOverflowPlanError.invalidJSON
        }
        return length
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = consume(0x2D)
        guard let first = currentByte else { throw ToolbarOverflowPlanError.invalidJSON }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw ToolbarOverflowPlanError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw ToolbarOverflowPlanError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw ToolbarOverflowPlanError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x65) || consume(0x45) {
            _ = consume(0x2B) || consume(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw ToolbarOverflowPlanError.invalidJSON
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        guard index - start <= Self.maximumNumberBytes else {
            throw ToolbarOverflowPlanError.jsonNumberTooLarge(
                maximumBytes: Self.maximumNumberBytes
            )
        }
    }

    private func validateDepth(_ depth: Int) throws {
        guard depth <= Self.maximumNestingDepth else {
            throw ToolbarOverflowPlanError.jsonNestingTooDeep(
                maximumDepth: Self.maximumNestingDepth
            )
        }
    }

    private mutating func incrementContainerCount(_ count: inout Int) throws {
        guard count < Self.maximumContainerElements else {
            throw ToolbarOverflowPlanError.jsonContainerTooLarge(
                maximumElements: Self.maximumContainerElements
            )
        }
        count += 1
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else {
            throw ToolbarOverflowPlanError.invalidJSON
        }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw ToolbarOverflowPlanError.invalidJSON }
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
