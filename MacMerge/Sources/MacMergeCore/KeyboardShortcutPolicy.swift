import Foundation

/// Bounded, UI-independent shortcut audit and routing policy.
///
/// This type decides ownership and availability only. Platform code remains responsible for
/// converting key events to `Chord` values and dispatching an enabled application command or
/// leaving a native text-editing reservation with the responder chain.
public struct KeyboardShortcutPolicy: Equatable, Hashable, Sendable {
    public typealias Command = ComparisonCommandState.Identifier
    public typealias CancellationCheck = @Sendable () throws(KeyboardShortcutPolicyError) -> Void

    public enum LifecycleState: String, CaseIterable, Equatable, Hashable, Sendable {
        case empty
        case loading
        case equal
        case different
        case failed
    }

    public enum EditorFocus: String, CaseIterable, Equatable, Hashable, Sendable {
        case none
        case readOnly
        case editable

        public var ownsInput: Bool { self != .none }
        public var isEditable: Bool { self == .editable }
    }

    public enum Modifier: Int, CaseIterable, Comparable, Equatable, Hashable, Sendable {
        case command
        case control
        case option
        case shift
        case function

        public static func < (left: Modifier, right: Modifier) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public enum SpecialKey: Int, CaseIterable, Comparable, Equatable, Hashable, Sendable {
        case backspace
        case delete
        case downArrow
        case end
        case escape
        case home
        case leftArrow
        case pageDown
        case pageUp
        case `return`
        case rightArrow
        case space
        case tab
        case upArrow

        public static func < (left: SpecialKey, right: SpecialKey) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public enum Key: Equatable, Hashable, Sendable {
        /// One printable ASCII physical-key identity. Letters and shifted US-layout punctuation
        /// are canonicalized to their physical key plus modifier representation.
        case character(Character)
        case function(Int)
        case special(SpecialKey)
    }

    public struct Chord: Comparable, Equatable, Hashable, Sendable {
        public let key: Key
        public let modifiers: Set<Modifier>

        public init(
            _ key: Key,
            modifiers: Set<Modifier> = []
        ) throws(KeyboardShortcutPolicyError) {
            let canonicalKey: Key
            var canonicalModifiers = modifiers
            switch key {
            case .character(let character):
                var scalarIterator = character.unicodeScalars.makeIterator()
                guard let scalar = scalarIterator.next(), scalarIterator.next() == nil,
                    (0x21...0x7E).contains(scalar.value)
                else {
                    throw KeyboardShortcutPolicyError.invalidCharacterKey(character)
                }
                let canonicalCharacter: Character
                if (0x41...0x5A).contains(scalar.value) {
                    canonicalCharacter = Character(
                        String(UnicodeScalar(scalar.value + 0x20)!)
                    )
                } else {
                    canonicalCharacter = Self.unshiftedCharacter(character)
                    if canonicalCharacter != character { canonicalModifiers.insert(.shift) }
                }
                canonicalKey = .character(canonicalCharacter)
            case .function(let number):
                guard (1...24).contains(number) else {
                    throw KeyboardShortcutPolicyError.invalidFunctionKey(number)
                }
                canonicalKey = key
            case .special:
                canonicalKey = key
            }

            if case .character = canonicalKey {
                let commandModifiers: Set<Modifier> = [.command, .control, .option]
                guard !canonicalModifiers.isDisjoint(with: commandModifiers) else {
                    throw KeyboardShortcutPolicyError.printableKeyRequiresCommandModifier
                }
            }
            self.key = canonicalKey
            self.modifiers = canonicalModifiers
        }

        private static func unshiftedCharacter(_ character: Character) -> Character {
            switch character {
            case "!": "1"
            case "@": "2"
            case "#": "3"
            case "$": "4"
            case "%": "5"
            case "^": "6"
            case "&": "7"
            case "*": "8"
            case "(": "9"
            case ")": "0"
            case "_": "-"
            case "+": "="
            case "{": "["
            case "}": "]"
            case "|": "\\"
            case ":": ";"
            case "\"": "'"
            case "<": ","
            case ">": "."
            case "?": "/"
            case "~": "`"
            default: character
            }
        }

        public var canonicalDescription: String {
            let modifierNames = Modifier.allCases.filter(modifiers.contains).map { modifier in
                switch modifier {
                case .command: "command"
                case .control: "control"
                case .option: "option"
                case .shift: "shift"
                case .function: "function"
                }
            }
            let keyName: String
            switch key {
            case .character(let character): keyName = String(character)
            case .function(let number): keyName = "f\(number)"
            case .special(let special): keyName = String(describing: special)
            }
            return (modifierNames + [keyName]).joined(separator: "+")
        }

        public static func < (left: Chord, right: Chord) -> Bool {
            let leftModifiers = left.modifierBits
            let rightModifiers = right.modifierBits
            if leftModifiers != rightModifiers { return leftModifiers < rightModifiers }
            return compare(left.key, right.key)
        }

        private var modifierBits: Int {
            modifiers.reduce(into: 0) { result, modifier in
                result |= 1 << modifier.rawValue
            }
        }

        private static func compare(_ left: Key, _ right: Key) -> Bool {
            switch (left, right) {
            case (.character(let left), .character(let right)):
                return String(left).utf8.lexicographicallyPrecedes(String(right).utf8)
            case (.special(let left), .special(let right)):
                return left < right
            case (.function(let left), .function(let right)):
                return left < right
            case (.character, _):
                return true
            case (.special, .function):
                return true
            case (.special, .character), (.function, _):
                return false
            }
        }
    }

    public struct CommandShortcut: Equatable, Hashable, Sendable {
        public let command: Command
        public let chord: Chord
        /// Base comparison phases where the command can run. Orthogonal document facts are
        /// represented separately so, for example, a selection can remain active while dirty.
        public let enabledLifecycleStates: Set<LifecycleState>
        public let requiresDirty: Bool
        public let requiresSelection: Bool
        public let allowsReadOnly: Bool

        public init(
            command: Command,
            chord: Chord,
            enabledLifecycleStates: Set<LifecycleState> = Set(LifecycleState.allCases),
            requiresDirty: Bool = false,
            requiresSelection: Bool = false,
            allowsReadOnly: Bool = true
        ) {
            self.command = command
            self.chord = chord
            self.enabledLifecycleStates = enabledLifecycleStates
            self.requiresDirty = requiresDirty
            self.requiresSelection = requiresSelection
            self.allowsReadOnly = allowsReadOnly
        }

        fileprivate func conditionFailure(in context: Context) -> CommandConditionFailure? {
            if !enabledLifecycleStates.contains(context.lifecycle) { return .lifecycle }
            if requiresDirty, !context.isDirty { return .dirty }
            if requiresSelection, !context.hasSelection { return .selection }
            if !allowsReadOnly, context.isReadOnly { return .readOnly }
            return nil
        }
    }

    public enum NativeTextEditingCommand: String, CaseIterable, Comparable, Equatable, Hashable,
        Sendable
    {
        case selectAll
        case copy
        case cut
        case paste
        case undo
        case redo
        case find
        case findNext
        case findPrevious
        case moveLeft
        case moveRight
        case moveUp
        case moveDown
        case moveBackward
        case moveForward
        case moveLeftAndModifySelection
        case moveRightAndModifySelection
        case moveUpAndModifySelection
        case moveDownAndModifySelection
        case moveBackwardAndModifySelection
        case moveForwardAndModifySelection
        case moveWordLeft
        case moveWordRight
        case moveWordLeftAndModifySelection
        case moveWordRightAndModifySelection
        case moveParagraphUp
        case moveParagraphDown
        case moveParagraphUpAndModifySelection
        case moveParagraphDownAndModifySelection
        case moveBackwardToParagraphStart
        case moveForwardToParagraphEnd
        case moveLineStart
        case moveLineEnd
        case moveLineStartAndModifySelection
        case moveLineEndAndModifySelection
        case moveDocumentStart
        case moveDocumentEnd
        case moveDocumentStartAndModifySelection
        case moveDocumentEndAndModifySelection
        case scrollDocumentStart
        case scrollDocumentEnd
        case scrollPageUp
        case scrollPageDown
        case movePageUp
        case movePageDown
        case movePageUpAndModifySelection
        case movePageDownAndModifySelection
        case moveToBeginningOfParagraph
        case moveToEndOfParagraph
        case moveToBeginningOfParagraphAndModifySelection
        case moveToEndOfParagraphAndModifySelection
        case insertNewline
        case insertLineBreak
        case insertNewlineIgnoringFieldEditor
        case insertTab
        case insertBacktab
        case insertTabIgnoringFieldEditor
        case insertSpace
        case selectNextKeyView
        case selectPreviousKeyView
        case deleteBackward
        case deleteForward
        case deleteBackwardByDecomposingPreviousCharacter
        case deleteWordBackward
        case deleteWordForward
        case deleteToBeginningOfLine
        case deleteToEndOfLine
        case deleteToEndOfParagraph
        case transpose
        case centerSelectionInVisibleArea
        case cancelOperation
        case complete
        case yank

        public static func < (left: NativeTextEditingCommand, right: NativeTextEditingCommand) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public enum NativeTextEditingApplicability: String, CaseIterable, Equatable, Hashable, Sendable {
        case readOnlyAndEditable
        case readOnly
        case editable

        fileprivate func applies(to focus: EditorFocus) -> Bool {
            switch (self, focus) {
            case (.readOnlyAndEditable, .readOnly), (.readOnlyAndEditable, .editable),
                (.readOnly, .readOnly), (.editable, .editable):
                true
            case (_, .none), (.readOnly, .editable), (.editable, .readOnly):
                false
            }
        }
    }

    public struct NativeTextEditingReservation: Equatable, Hashable, Sendable {
        public let command: NativeTextEditingCommand
        public let chord: Chord
        public let applicability: NativeTextEditingApplicability

        public init(
            command: NativeTextEditingCommand,
            chord: Chord,
            applicability: NativeTextEditingApplicability = .readOnlyAndEditable
        ) {
            self.command = command
            self.chord = chord
            self.applicability = applicability
        }
    }

    public enum CollisionKind: String, CaseIterable, Equatable, Hashable, Sendable {
        /// More than one application shortcut owns the chord in the same focus context.
        case applicationCommands
        /// More than one native reservation owns the chord.
        case nativeTextEditingReservations
        /// Application ownership yields to native text editing only while an editor owns input.
        case editorFocusReservation
    }

    public struct Collision: Equatable, Hashable, Sendable {
        public let chord: Chord
        public let kinds: Set<CollisionKind>
        public let commands: [Command]
        public let nativeTextEditingCommands: [NativeTextEditingCommand]
        public let commandShortcutCount: Int
        public let nativeReservationCount: Int

        fileprivate init(
            chord: Chord,
            kinds: Set<CollisionKind>,
            commands: [Command],
            nativeTextEditingCommands: [NativeTextEditingCommand],
            commandShortcutCount: Int,
            nativeReservationCount: Int
        ) {
            self.chord = chord
            self.kinds = kinds
            self.commands = commands
            self.nativeTextEditingCommands = nativeTextEditingCommands
            self.commandShortcutCount = commandShortcutCount
            self.nativeReservationCount = nativeReservationCount
        }

        public var isConditional: Bool {
            kinds == [.editorFocusReservation]
        }
    }

    public struct Context: Equatable, Hashable, Sendable {
        public let lifecycle: LifecycleState
        public let isDirty: Bool
        public let hasSelection: Bool
        public let isReadOnly: Bool
        public let editorFocus: EditorFocus
        /// Optional exact gate from command-state resolution. It only narrows coarse conditions.
        public let enabledCommands: Set<Command>?

        public init(
            lifecycle: LifecycleState,
            isDirty: Bool = false,
            hasSelection: Bool = false,
            isReadOnly: Bool = false,
            editorFocus: EditorFocus = .none,
            enabledCommands: Set<Command>? = nil
        ) {
            self.lifecycle = lifecycle
            self.isDirty = isDirty
            self.hasSelection = hasSelection
            self.isReadOnly = isReadOnly
            self.editorFocus = editorFocus
            self.enabledCommands = enabledCommands
        }
    }

    public enum CommandConditionFailure: String, CaseIterable, Equatable, Hashable, Sendable {
        case lifecycle
        case dirty
        case selection
        case readOnly
    }

    public enum EnabledReason: Equatable, Hashable, Sendable {
        case applicationCommand(Command)
        case nativeTextEditing(NativeTextEditingCommand)
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case noBinding
        case commandConditions(Command, CommandConditionFailure)
        case commandUnavailable(Command)
        case applicationCollision([Command])
        case nativeTextEditingCollision([NativeTextEditingCommand])
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

    public enum AvailabilityReason: Equatable, Hashable, Sendable {
        case enabled(EnabledReason)
        case disabled(DisabledReason)

        public var availability: Availability {
            switch self {
            case .enabled: .enabled
            case .disabled(let reason): .disabled(reason)
            }
        }
    }

    public enum Route: Equatable, Hashable, Sendable {
        case applicationCommand(Command)
        /// Preserve responder-chain ownership; this is not an instruction to synthesize an event.
        case nativeTextEditing(NativeTextEditingCommand)
        case blocked
        case unhandled
    }

    public struct Resolution: Equatable, Hashable, Sendable {
        public let chord: Chord
        public let route: Route
        public let availabilityReason: AvailabilityReason
        public let matchedCommands: [Command]
        public let matchedNativeTextEditingCommands: [NativeTextEditingCommand]
        public let collision: Collision?

        fileprivate init(
            chord: Chord,
            route: Route,
            availabilityReason: AvailabilityReason,
            matchedCommands: [Command],
            matchedNativeTextEditingCommands: [NativeTextEditingCommand],
            collision: Collision?
        ) {
            self.chord = chord
            self.route = route
            self.availabilityReason = availabilityReason
            self.matchedCommands = matchedCommands
            self.matchedNativeTextEditingCommands = matchedNativeTextEditingCommands
            self.collision = collision
        }

        public var availability: Availability { availabilityReason.availability }
        public var isEnabled: Bool { availability.isEnabled }
        public var canExecute: Bool { isEnabled }
        public var disabledReason: DisabledReason? { availability.disabledReason }
        public var enabledReason: EnabledReason? {
            guard case .enabled(let reason) = availabilityReason else { return nil }
            return reason
        }
        public var applicationCommand: Command? {
            guard isEnabled, case .applicationCommand(let command) = route else { return nil }
            return command
        }
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumCommandShortcutCount = 4_096
        public static let hardMaximumNativeReservationCount = 512
        public static let hardMaximumCollisionCount = 4_096
        public static let hardMaximumWork = 10_000_000
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumCommandShortcutCount: Int
        public let maximumNativeReservationCount: Int
        public let maximumCollisionCount: Int
        public let maximumWork: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumCommandShortcutCount: Int = 1_024,
            maximumNativeReservationCount: Int = 128,
            maximumCollisionCount: Int = 1_024,
            maximumWork: Int = 65_536,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumCommandShortcutCount = maximumCommandShortcutCount
            self.maximumNativeReservationCount = maximumNativeReservationCount
            self.maximumCollisionCount = maximumCollisionCount
            self.maximumWork = maximumWork
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        fileprivate func validate() throws(KeyboardShortcutPolicyError) {
            try validate(
                maximumCommandShortcutCount,
                limit: .commandShortcuts,
                range: 0...Self.hardMaximumCommandShortcutCount
            )
            try validate(
                maximumNativeReservationCount,
                limit: .nativeReservations,
                range: 0...Self.hardMaximumNativeReservationCount
            )
            try validate(
                maximumCollisionCount,
                limit: .collisions,
                range: 0...Self.hardMaximumCollisionCount
            )
            try validate(maximumWork, limit: .work, range: 1...Self.hardMaximumWork)
            try validate(
                cancellationCheckInterval,
                limit: .cancellationCheckInterval,
                range: 1...Self.hardMaximumCancellationCheckInterval
            )
        }

        private func validate(
            _ value: Int,
            limit: Limit,
            range: ClosedRange<Int>
        ) throws(KeyboardShortcutPolicyError) {
            guard range.contains(value) else {
                throw KeyboardShortcutPolicyError.invalidLimit(limit, value: value)
            }
        }
    }

    public enum Limit: String, CaseIterable, Equatable, Hashable, Sendable {
        case commandShortcuts
        case nativeReservations
        case collisions
        case work
        case cancellationCheckInterval
    }

    public let commandShortcuts: [CommandShortcut]
    public let nativeTextEditingReservations: [NativeTextEditingReservation]
    public let collisions: [Collision]
    public let limits: Limits
    private let commandShortcutsByChord: [Chord: [CommandShortcut]]
    private let nativeReservationsByChord: [Chord: [NativeTextEditingReservation]]
    private let collisionsByChord: [Chord: Collision]
    private let orderedChords: [Chord]

    public static func == (left: KeyboardShortcutPolicy, right: KeyboardShortcutPolicy) -> Bool {
        left.commandShortcuts == right.commandShortcuts
            && left.nativeTextEditingReservations == right.nativeTextEditingReservations
            && left.collisions == right.collisions
            && left.limits == right.limits
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(commandShortcuts)
        hasher.combine(nativeTextEditingReservations)
        hasher.combine(collisions)
        hasher.combine(limits)
    }

    public init(
        commandShortcuts: [CommandShortcut],
        nativeTextEditingReservations: [NativeTextEditingReservation] = [],
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            try KeyboardShortcutPolicy.checkTaskCancellation()
        }
    ) throws(KeyboardShortcutPolicyError) {
        try limits.validate()
        guard commandShortcuts.count <= limits.maximumCommandShortcutCount else {
            throw KeyboardShortcutPolicyError.tooManyCommandShortcuts(
                maximum: limits.maximumCommandShortcutCount
            )
        }
        guard nativeTextEditingReservations.count <= limits.maximumNativeReservationCount else {
            throw KeyboardShortcutPolicyError.tooManyNativeReservations(
                maximum: limits.maximumNativeReservationCount
            )
        }

        var work = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try work.checkCancellation()
        for shortcut in commandShortcuts {
            try work.consume()
            guard !shortcut.enabledLifecycleStates.isEmpty else {
                throw KeyboardShortcutPolicyError.emptyLifecycleStates(shortcut.command)
            }
        }

        let sortedShortcuts = try Self.boundedSorted(
            commandShortcuts,
            by: Self.commandShortcutPrecedes,
            work: &work
        )
        let sortedReservations = try Self.boundedSorted(
            nativeTextEditingReservations,
            by: Self.reservationPrecedes,
            work: &work
        )
        let shortcutIndex = try Self.indexCommandShortcuts(sortedShortcuts, work: &work)
        let reservationIndex = try Self.indexReservations(sortedReservations, work: &work)
        var chordSet: Set<Chord> = []
        chordSet.reserveCapacity(shortcutIndex.count + reservationIndex.count)
        for chord in shortcutIndex.keys {
            try work.consume()
            chordSet.insert(chord)
        }
        for chord in reservationIndex.keys {
            try work.consume()
            chordSet.insert(chord)
        }
        var chords: [Chord] = []
        chords.reserveCapacity(chordSet.count)
        for chord in chordSet {
            try work.consume()
            chords.append(chord)
        }
        let sortedChords = try Self.boundedSorted(chords, by: <, work: &work)
        let detectedCollisions = try Self.detectCollisions(
            chords: sortedChords,
            commandShortcutsByChord: shortcutIndex,
            reservationsByChord: reservationIndex,
            limits: limits,
            work: &work
        )
        var collisionIndex: [Chord: Collision] = [:]
        collisionIndex.reserveCapacity(detectedCollisions.count)
        for collision in detectedCollisions {
            try work.consume()
            collisionIndex[collision.chord] = collision
        }
        try work.finish()

        self.commandShortcuts = sortedShortcuts
        self.nativeTextEditingReservations = sortedReservations
        collisions = detectedCollisions
        self.limits = limits
        commandShortcutsByChord = shortcutIndex
        nativeReservationsByChord = reservationIndex
        collisionsByChord = collisionIndex
        orderedChords = sortedChords
    }

    public func resolve(
        _ chord: Chord,
        in context: Context,
        cancellationCheck: @escaping CancellationCheck = {
            try KeyboardShortcutPolicy.checkTaskCancellation()
        }
    ) throws(KeyboardShortcutPolicyError) -> Resolution {
        var work = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try work.checkCancellation()
        let resolution = try resolve(chord, in: context, work: &work)
        try work.finish()
        return resolution
    }

    /// Resolves every known chord in canonical order with one aggregate work budget.
    public func resolveAll(
        in context: Context,
        cancellationCheck: @escaping CancellationCheck = {
            try KeyboardShortcutPolicy.checkTaskCancellation()
        }
    ) throws(KeyboardShortcutPolicyError) -> [Resolution] {
        var work = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try work.checkCancellation()
        var result: [Resolution] = []
        result.reserveCapacity(orderedChords.count)
        for chord in orderedChords {
            try work.consume()
            result.append(try resolve(chord, in: context, work: &work))
        }
        try work.finish()
        return result
    }

    public func collision(for chord: Chord) -> Collision? {
        collisionsByChord[chord]
    }

    /// Current implemented and audited command subset. It intentionally does not claim full
    /// `Merge.rc` accelerator parity.
    public static func makeUnfinishedAudit(
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            try KeyboardShortcutPolicy.checkTaskCancellation()
        }
    ) throws(KeyboardShortcutPolicyError) -> KeyboardShortcutPolicy {
        try KeyboardShortcutPolicy(
            commandShortcuts: unfinishedAuditCommandShortcuts,
            nativeTextEditingReservations: standardNativeTextEditingReservations,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    public static let unfinishedAuditCommandShortcuts: [CommandShortcut] = {
        let workspace: Set<LifecycleState> = [.empty, .equal, .different, .failed]
        let current: Set<LifecycleState> = [.equal, .different]
        let differences: Set<LifecycleState> = [.different]
        let all = Set(LifecycleState.allCases)

        return [
            shortcut(
                .newComparison,
                FileLifecycleShortcuts.key(.new),
                FileLifecycleShortcuts.modifiers(.new),
                workspace
            ),
            shortcut(
                .openComparison,
                FileLifecycleShortcuts.key(.open),
                FileLifecycleShortcuts.modifiers(.open),
                workspace
            ),
            shortcut(
                .save,
                FileLifecycleShortcuts.key(.save),
                FileLifecycleShortcuts.modifiers(.save),
                workspace,
                dirty: true,
                readOnly: false
            ),
            shortcut(.undo, .character("z"), [.command], workspace, readOnly: false),
            shortcut(
                .redo,
                .character("z"),
                [.command, .shift],
                workspace,
                readOnly: false
            ),
            shortcut(.selectLineDifference, .function(4), [], differences),
            shortcut(.selectPreviousLineDifference, .function(4), [.shift], differences),
            shortcut(.nextDifference, .function(8), [], differences),
            shortcut(.nextDifference, .special(.downArrow), [.option], differences),
            shortcut(.previousDifference, .function(7), [], differences),
            shortcut(.previousDifference, .special(.upArrow), [.option], differences),
            shortcut(.nextConflict, .function(8), [.shift], differences),
            shortcut(.nextConflict, .special(.downArrow), [.option, .shift], differences),
            shortcut(.previousConflict, .function(7), [.shift], differences),
            shortcut(.previousConflict, .special(.upArrow), [.option, .shift], differences),
            shortcut(.firstDifference, .special(.home), [.option], differences),
            shortcut(.currentDifference, .special(.return), [.option], differences),
            shortcut(.lastDifference, .special(.end), [.option], differences),
            shortcut(
                .copyToRight,
                .special(.rightArrow),
                [.option],
                differences,
                selected: true,
                readOnly: false
            ),
            shortcut(
                .copyToLeft,
                .special(.leftArrow),
                [.option],
                differences,
                selected: true,
                readOnly: false
            ),
            shortcut(
                .copyToRightAndAdvance,
                .special(.rightArrow),
                [.command, .option],
                differences,
                selected: true,
                readOnly: false
            ),
            shortcut(
                .copyToLeftAndAdvance,
                .special(.leftArrow),
                [.command, .option],
                differences,
                selected: true,
                readOnly: false
            ),
            shortcut(.previousComparedFile, .function(7), [.command], current),
            shortcut(.nextComparedFile, .function(8), [.command], current),
            shortcut(.reloadFromDisk, .function(5), [.command], current),
            shortcut(.refresh, .function(5), [], current.union([.failed])),
            shortcut(.changePane, .function(6), [], current),
            shortcut(.changePaneBack, .function(6), [.shift], current),
            shortcut(.mergeMode, .function(9), [], current),
            shortcut(.options, .character(","), [.command], all)
        ]
    }()

    public static let standardNativeTextEditingReservations: [NativeTextEditingReservation] = {
        [
            reservation(.selectAll, .character("a"), [.command]),
            reservation(.copy, .character("c"), [.command]),
            reservation(.cut, .character("x"), [.command], editable: true),
            reservation(.paste, .character("v"), [.command], editable: true),
            reservation(.undo, .character("z"), [.command], editable: true),
            reservation(.redo, .character("z"), [.command, .shift], editable: true),
            reservation(.find, .character("f"), [.command]),
            reservation(.findNext, .character("g"), [.command]),
            reservation(.findPrevious, .character("g"), [.command, .shift]),
            reservation(.moveLeft, .special(.leftArrow), []),
            reservation(.moveRight, .special(.rightArrow), []),
            reservation(.moveUp, .special(.upArrow), []),
            reservation(.moveDown, .special(.downArrow), []),
            reservation(.moveLeftAndModifySelection, .special(.leftArrow), [.shift]),
            reservation(.moveRightAndModifySelection, .special(.rightArrow), [.shift]),
            reservation(.moveUpAndModifySelection, .special(.upArrow), [.shift]),
            reservation(.moveDownAndModifySelection, .special(.downArrow), [.shift]),
            reservation(.moveWordLeft, .special(.leftArrow), [.option]),
            reservation(.moveWordRight, .special(.rightArrow), [.option]),
            reservation(.moveWordLeftAndModifySelection, .special(.leftArrow), [.option, .shift]),
            reservation(.moveWordRightAndModifySelection, .special(.rightArrow), [.option, .shift]),
            reservation(.moveParagraphUp, .special(.upArrow), [.option]),
            reservation(.moveParagraphDown, .special(.downArrow), [.option]),
            reservation(.moveParagraphUpAndModifySelection, .special(.upArrow), [.option, .shift]),
            reservation(.moveParagraphDownAndModifySelection, .special(.downArrow), [.option, .shift]),
            reservation(.moveLineStart, .special(.leftArrow), [.command]),
            reservation(.moveLineEnd, .special(.rightArrow), [.command]),
            reservation(.moveLineStartAndModifySelection, .special(.leftArrow), [.command, .shift]),
            reservation(.moveLineEndAndModifySelection, .special(.rightArrow), [.command, .shift]),
            reservation(.moveDocumentStart, .special(.upArrow), [.command]),
            reservation(.moveDocumentEnd, .special(.downArrow), [.command]),
            reservation(.moveDocumentStartAndModifySelection, .special(.upArrow), [.command, .shift]),
            reservation(.moveDocumentEndAndModifySelection, .special(.downArrow), [.command, .shift]),
            reservation(.scrollDocumentStart, .special(.home), []),
            reservation(.scrollDocumentEnd, .special(.end), []),
            reservation(.moveDocumentStartAndModifySelection, .special(.home), [.shift]),
            reservation(.moveDocumentEndAndModifySelection, .special(.end), [.shift]),
            reservation(.moveBackwardToParagraphStart, .special(.home), [.option]),
            reservation(.moveForwardToParagraphEnd, .special(.end), [.option]),
            reservation(
                .moveParagraphUpAndModifySelection,
                .special(.home),
                [.option, .shift]
            ),
            reservation(
                .moveParagraphDownAndModifySelection,
                .special(.end),
                [.option, .shift]
            ),
            reservation(.scrollPageUp, .special(.pageUp), []),
            reservation(.scrollPageDown, .special(.pageDown), []),
            reservation(.movePageUp, .special(.pageUp), [.option]),
            reservation(.movePageDown, .special(.pageDown), [.option]),
            reservation(.movePageUpAndModifySelection, .special(.pageUp), [.shift]),
            reservation(.movePageDownAndModifySelection, .special(.pageDown), [.shift]),
            reservation(.scrollPageUp, .special(.upArrow), [.control]),
            reservation(.scrollPageDown, .special(.downArrow), [.control]),
            reservation(.moveLineStart, .special(.leftArrow), [.control]),
            reservation(.moveLineEnd, .special(.rightArrow), [.control]),
            reservation(
                .moveLineStartAndModifySelection,
                .special(.leftArrow),
                [.control, .shift]
            ),
            reservation(
                .moveLineEndAndModifySelection,
                .special(.rightArrow),
                [.control, .shift]
            ),
            reservation(.insertNewline, .special(.return), [], editable: true),
            reservation(.insertLineBreak, .special(.return), [.control], editable: true),
            reservation(
                .insertNewlineIgnoringFieldEditor,
                .special(.return),
                [.option],
                editable: true
            ),
            reservation(.insertTab, .special(.tab), [], editable: true),
            reservation(.insertBacktab, .special(.tab), [.shift], editable: true),
            reservation(.selectNextKeyView, .special(.tab), [.control]),
            reservation(.selectPreviousKeyView, .special(.tab), [.control, .shift]),
            reservation(
                .insertTabIgnoringFieldEditor,
                .special(.tab),
                [.option],
                editable: true
            ),
            reservation(.insertSpace, .special(.space), [], editable: true),
            reservation(.deleteBackward, .special(.backspace), [], editable: true),
            reservation(.deleteForward, .special(.delete), [], editable: true),
            reservation(.deleteWordBackward, .special(.backspace), [.option], editable: true),
            reservation(
                .deleteWordBackward,
                .special(.backspace),
                [.control, .option],
                editable: true
            ),
            reservation(.deleteWordForward, .special(.delete), [.option], editable: true),
            reservation(
                .deleteToBeginningOfLine,
                .special(.backspace),
                [.command],
                editable: true
            ),
            reservation(.deleteToEndOfLine, .special(.delete), [.command], editable: true),
            reservation(.moveToBeginningOfParagraph, .character("a"), [.control]),
            reservation(.moveToEndOfParagraph, .character("e"), [.control]),
            reservation(.moveBackward, .character("b"), [.control]),
            reservation(.insertNewline, .character("c"), [.control], editable: true),
            reservation(.moveForward, .character("f"), [.control]),
            reservation(.insertNewline, .character("j"), [.control], editable: true),
            reservation(.moveUp, .character("p"), [.control]),
            reservation(.moveDown, .character("n"), [.control]),
            reservation(
                .moveToBeginningOfParagraphAndModifySelection,
                .character("a"),
                [.control, .shift]
            ),
            reservation(
                .moveToEndOfParagraphAndModifySelection,
                .character("e"),
                [.control, .shift]
            ),
            reservation(.moveBackwardAndModifySelection, .character("b"), [.control, .shift]),
            reservation(.moveForwardAndModifySelection, .character("f"), [.control, .shift]),
            reservation(.moveUpAndModifySelection, .character("p"), [.control, .shift]),
            reservation(.moveDownAndModifySelection, .character("n"), [.control, .shift]),
            reservation(.scrollPageDown, .character("v"), [.control]),
            reservation(
                .movePageDownAndModifySelection,
                .character("v"),
                [.control, .shift]
            ),
            reservation(.moveWordLeft, .character("b"), [.control, .option]),
            reservation(.moveWordRight, .character("f"), [.control, .option]),
            reservation(
                .moveWordLeftAndModifySelection,
                .character("b"),
                [.control, .option, .shift]
            ),
            reservation(
                .moveWordRightAndModifySelection,
                .character("f"),
                [.control, .option, .shift]
            ),
            reservation(.centerSelectionInVisibleArea, .character("l"), [.control]),
            reservation(.deleteBackward, .character("h"), [.control], editable: true),
            reservation(.deleteForward, .character("d"), [.control], editable: true),
            reservation(.deleteToEndOfParagraph, .character("k"), [.control], editable: true),
            reservation(.transpose, .character("t"), [.control], editable: true),
            reservation(
                .insertNewlineIgnoringFieldEditor,
                .character("o"),
                [.control],
                editable: true
            ),
            reservation(.insertTab, .character("i"), [.control], editable: true),
            reservation(.insertNewline, .character("m"), [.control], editable: true),
            reservation(.yank, .character("y"), [.control], editable: true),
            reservation(.cancelOperation, .special(.escape), []),
            reservation(.cancelOperation, .character("."), [.command]),
            reservation(.complete, .special(.escape), [.option], editable: true),
            reservation(.complete, .function(5), [], editable: true),
            reservation(
                .deleteBackwardByDecomposingPreviousCharacter,
                .special(.backspace),
                [.control],
                editable: true
            )
        ]
    }()

    private func resolve(
        _ chord: Chord,
        in context: Context,
        work: inout WorkBudget
    ) throws(KeyboardShortcutPolicyError) -> Resolution {
        let matchingShortcuts = commandShortcutsByChord[chord] ?? []
        let matchingReservations = nativeReservationsByChord[chord] ?? []
        try work.consume()
        var commands: [Command] = []
        commands.reserveCapacity(matchingShortcuts.count)
        for shortcut in matchingShortcuts {
            try work.consume()
            commands.append(shortcut.command)
        }
        var applicableReservations: [NativeTextEditingReservation] = []
        applicableReservations.reserveCapacity(matchingReservations.count)
        for reservation in matchingReservations {
            try work.consume()
            if reservation.applicability.applies(to: context.editorFocus) {
                applicableReservations.append(reservation)
            }
        }
        var nativeCommands: [NativeTextEditingCommand] = []
        nativeCommands.reserveCapacity(applicableReservations.count)
        for reservation in applicableReservations {
            try work.consume()
            nativeCommands.append(reservation.command)
        }
        let collision = collisionsByChord[chord]

        if !applicableReservations.isEmpty {
            guard applicableReservations.count == 1 else {
                return Resolution(
                    chord: chord,
                    route: .blocked,
                    availabilityReason: .disabled(.nativeTextEditingCollision(nativeCommands)),
                    matchedCommands: commands,
                    matchedNativeTextEditingCommands: nativeCommands,
                    collision: collision
                )
            }
            let reservation = applicableReservations[0]
            return Resolution(
                chord: chord,
                route: .nativeTextEditing(reservation.command),
                availabilityReason: .enabled(.nativeTextEditing(reservation.command)),
                matchedCommands: commands,
                matchedNativeTextEditingCommands: nativeCommands,
                collision: collision
            )
        }

        var conditionShortcuts: [CommandShortcut] = []
        conditionShortcuts.reserveCapacity(matchingShortcuts.count)
        for shortcut in matchingShortcuts {
            try work.consume()
            if shortcut.conditionFailure(in: context) == nil {
                conditionShortcuts.append(shortcut)
            }
        }
        var enabledShortcuts: [CommandShortcut] = []
        enabledShortcuts.reserveCapacity(conditionShortcuts.count)
        for shortcut in conditionShortcuts {
            try work.consume()
            if context.enabledCommands?.contains(shortcut.command) ?? true {
                enabledShortcuts.append(shortcut)
            }
        }

        guard !enabledShortcuts.isEmpty else {
            let reason: DisabledReason
            if let shortcut = conditionShortcuts.first {
                reason = .commandUnavailable(shortcut.command)
            } else if let shortcut = matchingShortcuts.first {
                reason = .commandConditions(
                    shortcut.command,
                    shortcut.conditionFailure(in: context)!
                )
            } else {
                reason = .noBinding
            }
            return Resolution(
                chord: chord,
                route: matchingShortcuts.isEmpty ? .unhandled : .blocked,
                availabilityReason: .disabled(reason),
                matchedCommands: commands,
                matchedNativeTextEditingCommands: nativeCommands,
                collision: collision
            )
        }
        guard enabledShortcuts.count == 1 else {
            var enabledCommands: [Command] = []
            enabledCommands.reserveCapacity(enabledShortcuts.count)
            for shortcut in enabledShortcuts {
                try work.consume()
                enabledCommands.append(shortcut.command)
            }
            return Resolution(
                chord: chord,
                route: .blocked,
                availabilityReason: .disabled(.applicationCollision(enabledCommands)),
                matchedCommands: commands,
                matchedNativeTextEditingCommands: nativeCommands,
                collision: collision
            )
        }

        let shortcut = enabledShortcuts[0]
        return Resolution(
            chord: chord,
            route: .applicationCommand(shortcut.command),
            availabilityReason: .enabled(.applicationCommand(shortcut.command)),
            matchedCommands: commands,
            matchedNativeTextEditingCommands: nativeCommands,
            collision: collision
        )
    }

    private static func detectCollisions(
        chords: [Chord],
        commandShortcutsByChord: [Chord: [CommandShortcut]],
        reservationsByChord: [Chord: [NativeTextEditingReservation]],
        limits: Limits,
        work: inout WorkBudget
    ) throws(KeyboardShortcutPolicyError) -> [Collision] {
        var result: [Collision] = []
        for chord in chords {
            try work.consume()
            let shortcuts = commandShortcutsByChord[chord] ?? []
            let reservations = reservationsByChord[chord] ?? []
            var commands: [Command] = []
            commands.reserveCapacity(shortcuts.count)
            for shortcut in shortcuts {
                try work.consume()
                commands.append(shortcut.command)
            }
            var nativeCommands: [NativeTextEditingCommand] = []
            nativeCommands.reserveCapacity(reservations.count)
            for reservation in reservations {
                try work.consume()
                nativeCommands.append(reservation.command)
            }
            var kinds: Set<CollisionKind> = []
            if try hasApplicationCollision(shortcuts, work: &work) {
                kinds.insert(.applicationCommands)
            }
            if try hasNativeCollision(reservations, work: &work) {
                kinds.insert(.nativeTextEditingReservations)
            }
            if !commands.isEmpty, !nativeCommands.isEmpty { kinds.insert(.editorFocusReservation) }
            guard !kinds.isEmpty else { continue }
            guard result.count < limits.maximumCollisionCount else {
                throw KeyboardShortcutPolicyError.tooManyCollisions(
                    maximum: limits.maximumCollisionCount
                )
            }
            result.append(
                Collision(
                    chord: chord,
                    kinds: kinds,
                    commands: commands,
                    nativeTextEditingCommands: nativeCommands,
                    commandShortcutCount: commands.count,
                    nativeReservationCount: nativeCommands.count
                )
            )
        }
        return result
    }

    private static func hasApplicationCollision(
        _ shortcuts: [CommandShortcut],
        work: inout WorkBudget
    ) throws(KeyboardShortcutPolicyError) -> Bool {
        guard shortcuts.count > 1 else { return false }
        for lifecycle in LifecycleState.allCases {
            for isDirty in [false, true] {
                for hasSelection in [false, true] {
                    for isReadOnly in [false, true] {
                        let context = Context(
                            lifecycle: lifecycle,
                            isDirty: isDirty,
                            hasSelection: hasSelection,
                            isReadOnly: isReadOnly
                        )
                        var activeShortcutCount = 0
                        for shortcut in shortcuts {
                            try work.consume()
                            if shortcut.conditionFailure(in: context) == nil {
                                activeShortcutCount += 1
                                if activeShortcutCount > 1 { return true }
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    private static func hasNativeCollision(
        _ reservations: [NativeTextEditingReservation],
        work: inout WorkBudget
    ) throws(KeyboardShortcutPolicyError) -> Bool {
        guard reservations.count > 1 else { return false }
        for focus in [EditorFocus.readOnly, .editable] {
            var activeReservationCount = 0
            for reservation in reservations {
                try work.consume()
                if reservation.applicability.applies(to: focus) {
                    activeReservationCount += 1
                    if activeReservationCount > 1 { return true }
                }
            }
        }
        return false
    }

    private static func indexCommandShortcuts(
        _ shortcuts: [CommandShortcut],
        work: inout WorkBudget
    ) throws(KeyboardShortcutPolicyError) -> [Chord: [CommandShortcut]] {
        var result: [Chord: [CommandShortcut]] = [:]
        result.reserveCapacity(shortcuts.count)
        for shortcut in shortcuts {
            try work.consume()
            result[shortcut.chord, default: []].append(shortcut)
        }
        return result
    }

    private static func indexReservations(
        _ reservations: [NativeTextEditingReservation],
        work: inout WorkBudget
    ) throws(KeyboardShortcutPolicyError) -> [Chord: [NativeTextEditingReservation]] {
        var result: [Chord: [NativeTextEditingReservation]] = [:]
        result.reserveCapacity(reservations.count)
        for reservation in reservations {
            try work.consume()
            result[reservation.chord, default: []].append(reservation)
        }
        return result
    }

    private static func boundedSorted<Element>(
        _ values: [Element],
        by areInIncreasingOrder: (Element, Element) -> Bool,
        work: inout WorkBudget
    ) throws(KeyboardShortcutPolicyError) -> [Element] {
        guard values.count > 1 else {
            try work.consume(values.count)
            return values
        }
        var source = values
        var destination: [Element] = []
        destination.reserveCapacity(values.count)
        var width = 1

        while width < source.count {
            destination.removeAll(keepingCapacity: true)
            var lowerBound = 0
            while lowerBound < source.count {
                let middle = min(lowerBound + width, source.count)
                let upperBound = min(middle + width, source.count)
                var left = lowerBound
                var right = middle
                while left < middle, right < upperBound {
                    try work.consume()
                    if areInIncreasingOrder(source[right], source[left]) {
                        destination.append(source[right])
                        right += 1
                    } else {
                        destination.append(source[left])
                        left += 1
                    }
                }
                while left < middle {
                    try work.consume()
                    destination.append(source[left])
                    left += 1
                }
                while right < upperBound {
                    try work.consume()
                    destination.append(source[right])
                    right += 1
                }
                lowerBound = upperBound
            }
            swap(&source, &destination)
            width *= 2
        }
        return source
    }

    private static func commandShortcutPrecedes(
        _ left: CommandShortcut,
        _ right: CommandShortcut
    ) -> Bool {
        if left.chord != right.chord { return left.chord < right.chord }
        if left.command != right.command { return left.command.rawValue < right.command.rawValue }
        let leftLifecycleBits = lifecycleBits(left.enabledLifecycleStates)
        let rightLifecycleBits = lifecycleBits(right.enabledLifecycleStates)
        if leftLifecycleBits != rightLifecycleBits { return leftLifecycleBits < rightLifecycleBits }
        return conditionBits(left) < conditionBits(right)
    }

    private static func reservationPrecedes(
        _ left: NativeTextEditingReservation,
        _ right: NativeTextEditingReservation
    ) -> Bool {
        if left.chord != right.chord { return left.chord < right.chord }
        if left.command != right.command { return left.command < right.command }
        return left.applicability.rawValue < right.applicability.rawValue
    }

    private static func lifecycleBits(_ states: Set<LifecycleState>) -> Int {
        LifecycleState.allCases.enumerated().reduce(into: 0) { result, element in
            if states.contains(element.element) { result |= 1 << element.offset }
        }
    }

    private static func conditionBits(_ shortcut: CommandShortcut) -> Int {
        (shortcut.requiresDirty ? 1 : 0)
            | (shortcut.requiresSelection ? 1 << 1 : 0)
            | (!shortcut.allowsReadOnly ? 1 << 2 : 0)
    }

    private static func shortcut(
        _ command: Command,
        _ key: Key,
        _ modifiers: Set<Modifier>,
        _ states: Set<LifecycleState>,
        dirty: Bool = false,
        selected: Bool = false,
        readOnly: Bool = true
    ) -> CommandShortcut {
        CommandShortcut(
            command: command,
            chord: try! Chord(key, modifiers: modifiers),
            enabledLifecycleStates: states,
            requiresDirty: dirty,
            requiresSelection: selected,
            allowsReadOnly: readOnly
        )
    }

    private static func reservation(
        _ command: NativeTextEditingCommand,
        _ key: Key,
        _ modifiers: Set<Modifier>,
        editable: Bool = false
    ) -> NativeTextEditingReservation {
        NativeTextEditingReservation(
            command: command,
            chord: try! Chord(key, modifiers: modifiers),
            applicability: editable ? .editable : .readOnlyAndEditable
        )
    }

    public static func checkTaskCancellation() throws(KeyboardShortcutPolicyError) {
        do {
            try Task.checkCancellation()
        } catch {
            throw .cancelled
        }
    }

    private struct WorkBudget {
        let maximumWork: Int
        let cancellationCheckInterval: Int
        let cancellationCheck: CancellationCheck
        private(set) var completedWork = 0
        private var workAtLastCancellationCheck = 0

        init(limits: Limits, cancellationCheck: @escaping CancellationCheck) {
            maximumWork = limits.maximumWork
            cancellationCheckInterval = limits.cancellationCheckInterval
            self.cancellationCheck = cancellationCheck
        }

        mutating func consume(_ amount: Int = 1) throws(KeyboardShortcutPolicyError) {
            precondition(amount >= 0)
            guard amount <= maximumWork, completedWork <= maximumWork - amount else {
                try checkCancellation()
                throw KeyboardShortcutPolicyError.workLimitExceeded(maximum: maximumWork)
            }
            completedWork += amount
            if completedWork - workAtLastCancellationCheck >= cancellationCheckInterval {
                try checkCancellation()
                workAtLastCancellationCheck = completedWork
            }
        }

        func checkCancellation() throws(KeyboardShortcutPolicyError) {
            try cancellationCheck()
        }

        mutating func finish() throws(KeyboardShortcutPolicyError) {
            try checkCancellation()
            workAtLastCancellationCheck = completedWork
        }
    }
}

public enum KeyboardShortcutPolicyError: Error, Equatable, Hashable, LocalizedError, Sendable {
    case invalidCharacterKey(Character)
    case invalidFunctionKey(Int)
    case printableKeyRequiresCommandModifier
    case invalidLimit(KeyboardShortcutPolicy.Limit, value: Int)
    case tooManyCommandShortcuts(maximum: Int)
    case tooManyNativeReservations(maximum: Int)
    case tooManyCollisions(maximum: Int)
    case emptyLifecycleStates(KeyboardShortcutPolicy.Command)
    case workLimitExceeded(maximum: Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidCharacterKey(let character):
            "Shortcut character must be one printable ASCII physical key: \(character)."
        case .invalidFunctionKey(let number):
            "Shortcut function key must be between F1 and F24, not F\(number)."
        case .printableKeyRequiresCommandModifier:
            "Printable shortcuts require Command, Control, or Option."
        case .invalidLimit(let limit, let value):
            "Invalid keyboard shortcut limit \(limit.rawValue): \(value)."
        case .tooManyCommandShortcuts(let maximum):
            "Keyboard shortcut policy cannot exceed \(maximum) command shortcuts."
        case .tooManyNativeReservations(let maximum):
            "Keyboard shortcut policy cannot exceed \(maximum) native text-editing reservations."
        case .tooManyCollisions(let maximum):
            "Keyboard shortcut policy cannot report more than \(maximum) collisions."
        case .emptyLifecycleStates(let command):
            "Keyboard shortcut \(command.rawValue) has no enabled lifecycle state."
        case .workLimitExceeded(let maximum):
            "Keyboard shortcut policy exceeds the \(maximum)-unit work limit."
        case .cancelled:
            "Keyboard shortcut policy work was canceled."
        }
    }
}
