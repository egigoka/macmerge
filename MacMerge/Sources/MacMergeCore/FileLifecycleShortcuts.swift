import Foundation

/// Single source of truth for the standard file/application lifecycle shortcuts: New
/// `Command-N`, Open `Command-O`, Save `Command-S`, Close `Command-W`, and Quit `Command-Q`.
///
/// The app menu, `KeyboardShortcutPolicy`, `ShortcutCoverageAudit`, `KeyboardShortcutStateMatrix`,
/// and the toolbar help text all derive these chords from `bindings`. `verifyCatalogConsistency`
/// proves the policy, audit inventory, and state matrix route each chord to the expected command,
/// and `verifyMenu` checks a captured menu inventory (for example the live `NSApp.mainMenu`) binds
/// each chord exactly once to the expected title and location.
///
/// Action identity is verified from the menu only for AppKit-owned items (`terminate:`). SwiftUI
/// bridged items (New, Open, Save, Close) report the SwiftUI bridge selector, so their action
/// identity rests on policy routing plus the app's own dispatch tests, not on the captured menu.
/// This does not claim keyboard-event delivery, VoiceOver, or packaged-app parity on its own.
public enum FileLifecycleShortcuts {
    public typealias Policy = KeyboardShortcutPolicy

    public enum Command: String, CaseIterable, Comparable, Hashable, Sendable {
        case new
        case open
        case save
        case close
        case quit

        public static func < (left: Self, right: Self) -> Bool {
            left.rank < right.rank
        }

        private var rank: Int {
            switch self {
            case .new: 0
            case .open: 1
            case .save: 2
            case .close: 3
            case .quit: 4
            }
        }
    }

    /// Who performs the command once the menu item is invoked.
    public enum MenuAction: Hashable, Sendable {
        /// A MacMerge SwiftUI command; AppKit reports the SwiftUI bridge selector, so identity
        /// is established by menu title plus policy routing.
        case applicationCommand(ComparisonCommandState.Identifier)
        /// A standard AppKit menu item that sends this selector itself (verified from the menu).
        case appKitSelector(String)
        /// A MacMerge SwiftUI command that sends this standard selector down the responder
        /// chain. AppKit reports the SwiftUI bridge selector, so menu verification checks title
        /// and location; the dispatched selector is fixed here.
        case responderChainSelector(String)

        /// Selector name the menu item ultimately sends, when it is an AppKit selector.
        public var dispatchedSelector: String? {
            switch self {
            case .applicationCommand: nil
            case .appKitSelector(let selector), .responderChainSelector(let selector): selector
            }
        }
    }

    public enum MenuLocation: String, CaseIterable, Hashable, Sendable {
        /// The application menu (first top-level menu, titled after the app).
        case applicationMenu
        case fileMenu
    }

    public struct Binding: Hashable, Sendable {
        public let command: Command
        /// Unshifted lowercase key character, as used by SwiftUI `KeyEquivalent`.
        public let key: Character
        public let modifiers: Set<Policy.Modifier>
        public let chord: Policy.Chord
        public let menuTitle: String
        public let menuLocation: MenuLocation
        public let menuAction: MenuAction
        public let auditCommand: ShortcutCoverageAudit.ApplicationCommand

        /// Throws when the key and modifiers do not form a policy chord. `catalogFindings(_:)`
        /// additionally rejects keys and modifiers the menu bridge cannot represent exactly.
        public init(
            command: Command,
            key: Character,
            modifiers: Set<Policy.Modifier>,
            menuTitle: String,
            menuLocation: MenuLocation,
            menuAction: MenuAction,
            auditCommand: ShortcutCoverageAudit.ApplicationCommand
        ) throws(KeyboardShortcutPolicyError) {
            self.command = command
            self.key = key
            self.modifiers = modifiers
            self.chord = try Policy.Chord(.character(key), modifiers: modifiers)
            self.menuTitle = menuTitle
            self.menuLocation = menuLocation
            self.menuAction = menuAction
            self.auditCommand = auditCommand
        }

        public var policyKey: Policy.Key { .character(key) }

        /// Comparison command routed by `KeyboardShortcutPolicy`, or `nil` for AppKit-owned
        /// commands that the policy must leave unhandled.
        public var comparisonCommand: ComparisonCommandState.Identifier? {
            if case .applicationCommand(let command) = menuAction { return command }
            return nil
        }

        /// Menu titles may carry an app-name suffix (`Quit MacMerge`); match by prefix there.
        public func matchesTitle(_ title: String) -> Bool {
            switch command {
            case .quit: title == menuTitle || title.hasPrefix(menuTitle + " ")
            case .new, .open, .save, .close: title == menuTitle
            }
        }
    }

    public static let bindings: [Binding] = makeCatalog()

    private static func makeCatalog() -> [Binding] {
        do {
            return try makeCatalogThrowing()
        } catch {
            // A catalog edit produced an unrepresentable chord; every catalog test fails here.
            preconditionFailure("FileLifecycleShortcuts catalog entry is invalid: \(error)")
        }
    }

    private static func makeCatalogThrowing() throws(KeyboardShortcutPolicyError) -> [Binding] {
        [
            try Binding(
                command: .new,
                key: "n",
                modifiers: [.command],
                menuTitle: "New Text Comparison",
                menuLocation: .fileMenu,
                menuAction: .applicationCommand(.newComparison),
                auditCommand: .comparison(.newComparison)
            ),
            try Binding(
                command: .open,
                key: "o",
                modifiers: [.command],
                menuTitle: "Open...",
                menuLocation: .fileMenu,
                menuAction: .applicationCommand(.openComparison),
                auditCommand: .comparison(.openComparison)
            ),
            try Binding(
                command: .save,
                key: "s",
                modifiers: [.command],
                menuTitle: "Save",
                menuLocation: .fileMenu,
                menuAction: .applicationCommand(.save),
                auditCommand: .comparison(.save)
            ),
            try Binding(
                command: .close,
                key: "w",
                modifiers: [.command],
                menuTitle: "Close",
                menuLocation: .fileMenu,
                menuAction: .responderChainSelector("performClose:"),
                auditCommand: .close
            ),
            try Binding(
                command: .quit,
                key: "q",
                modifiers: [.command],
                menuTitle: "Quit",
                menuLocation: .applicationMenu,
                menuAction: .appKitSelector("terminate:"),
                auditCommand: .quit
            )
        ]
    }

    public static func binding(for command: Command) -> Binding {
        guard let binding = bindings.first(where: { $0.command == command }) else {
            preconditionFailure("FileLifecycleShortcuts catalog is missing \(command)")
        }
        return binding
    }

    public static func key(_ command: Command) -> Policy.Key { binding(for: command).policyKey }

    public static func modifiers(_ command: Command) -> Set<Policy.Modifier> {
        binding(for: command).modifiers
    }

    /// Shortcut as spelled in toolbar help text, e.g. `Command-O`.
    public static func helpText(_ command: Command) -> String {
        helpText(for: binding(for: command))
    }

    /// Help-text spelling for any binding: modifiers in macOS menu order, then the key.
    public static func helpText(for binding: Binding) -> String {
        let order: [(Policy.Modifier, String)] = [
            (.control, "Control"), (.option, "Option"), (.shift, "Shift"),
            (.command, "Command"), (.function, "Function")
        ]
        let names = order.filter { binding.modifiers.contains($0.0) }.map(\.1)
        return (names + [String(binding.key).uppercased()]).joined(separator: "-")
    }

    /// `KeyboardShortcutStateMatrix` row that must carry the catalog chord.
    public static func matrixShortcutID(
        _ command: Command
    ) -> KeyboardShortcutStateMatrix.ShortcutID {
        switch command {
        case .new: .newCommandN
        case .open: .openCommandO
        case .save: .saveCommandS
        case .close: .closeCommandW
        case .quit: .quitCommandQ
        }
    }

    // MARK: - Findings

    public enum Finding: Hashable, Sendable {
        /// Catalog itself is malformed (duplicate command or chord).
        case catalogDuplicateCommand(Command)
        case catalogDuplicateChord(Command, Command)
        case catalogMissingCommand(Command)
        /// Catalog key is not a lowercase ASCII letter or digit, so SwiftUI `KeyEquivalent`
        /// and the policy chord could disagree (uppercase implies Shift in AppKit).
        case catalogUnsupportedKey(Command, Character)
        /// Catalog modifier cannot be expressed by the SwiftUI menu bridge (Function).
        case catalogUnsupportedModifier(Command, Policy.Modifier)
        /// `KeyboardShortcutStateMatrix` has no row for the command.
        case matrixDescriptorMissing(Command)
        /// The matrix row carries a different chord than the catalog.
        case matrixDescriptorChordMismatch(Command, observed: Policy.Chord)
        /// The matrix row routes to a different command or system-command flag than the catalog.
        case matrixDescriptorCommandMismatch(Command)
        /// `KeyboardShortcutPolicy` has no entry for an app-owned command at the catalog chord.
        case policyBindingMissing(Command)
        /// `KeyboardShortcutPolicy` binds the command at a chord the catalog does not declare.
        case policyBindingUnexpectedChord(Command, Policy.Chord)
        /// Resolving the catalog chord in a satisfying context did not route to the command.
        case policyRouteMismatch(Command, Policy.EditorFocus, Policy.Route)
        /// `ShortcutCoverageAudit.Inventory` has no binding for the command at the catalog chord.
        case auditBindingMissing(Command)
        case auditBindingUnexpectedChord(Command, Policy.Chord)
        case auditBindingDescriptorMismatch(Command)
        /// Another audit binding claims the catalog chord for a different command.
        case auditChordClaimedByOtherCommand(Command, ShortcutCoverageAudit.ApplicationCommand)
        /// Captured menu has no item bound to the catalog chord.
        case menuItemMissing(Command)
        /// More than one captured menu item is bound to the catalog chord.
        case menuItemDuplicated(Command, count: Int)
        /// The item bound to the chord has an unexpected title.
        case menuItemTitleMismatch(Command, observed: String)
        /// The item bound to the chord sits under the wrong top-level menu.
        case menuItemLocationMismatch(Command, observed: MenuLocation?)
        /// The item bound to the chord does not invoke the expected AppKit selector.
        case menuItemActionMismatch(Command, observed: String?)
        /// A catalog-titled item exists but is bound to a different chord or none.
        case menuItemTitleBoundElsewhere(Command, observedKeyEquivalent: String)
        case menuInventoryTooLarge(maximum: Int)
    }

    // MARK: - Policy and audit consistency

    /// Verifies the catalog against the policy and coverage-audit inventory. Empty means every
    /// app-owned chord resolves to its command (with and without editable text focus) and every
    /// AppKit-owned chord is left unhandled by the policy so the responder chain receives it.
    public static func verifyCatalogConsistency(
        policy: KeyboardShortcutPolicy,
        inventory: ShortcutCoverageAudit.Inventory = .canonical,
        matrixDescriptors: [KeyboardShortcutStateMatrix.ShortcutDescriptor] =
            KeyboardShortcutStateMatrix.canonicalDescriptors
    ) throws(KeyboardShortcutPolicyError) -> [Finding] {
        var findings = catalogFindings(bindings)

        for binding in bindings {
            findings.append(contentsOf: try policyFindings(for: binding, policy: policy))
            findings.append(contentsOf: auditFindings(for: binding, inventory: inventory))
            findings.append(contentsOf: matrixFindings(for: binding, descriptors: matrixDescriptors))
        }
        return findings
    }

    private static func matrixFindings(
        for binding: Binding,
        descriptors: [KeyboardShortcutStateMatrix.ShortcutDescriptor]
    ) -> [Finding] {
        let id = matrixShortcutID(binding.command)
        guard let descriptor = descriptors.first(where: { $0.id == id }) else {
            return [.matrixDescriptorMissing(binding.command)]
        }
        var findings: [Finding] = []
        if descriptor.chord != binding.chord {
            findings.append(.matrixDescriptorChordMismatch(binding.command, observed: descriptor.chord))
        }
        let isSystem = binding.comparisonCommand == nil
        if descriptor.applicationCommand != binding.comparisonCommand
            || descriptor.isSystemCommand != isSystem
        {
            findings.append(.matrixDescriptorCommandMismatch(binding.command))
        }
        return findings
    }

    /// Policy context where every catalog command's coarse conditions hold.
    public static func satisfyingContext(
        editorFocus: Policy.EditorFocus
    ) -> Policy.Context {
        Policy.Context(
            lifecycle: .different,
            isDirty: true,
            hasSelection: true,
            isReadOnly: false,
            editorFocus: editorFocus
        )
    }

    /// Structural checks on a catalog: unique commands and chords, every command present, and
    /// only keys and modifiers the SwiftUI menu bridge represents exactly.
    public static func catalogFindings(_ bindings: [Binding]) -> [Finding] {
        var findings: [Finding] = []
        var seenCommands: Set<Command> = []
        var commandByChord: [Policy.Chord: Command] = [:]
        for binding in bindings {
            if !isSupportedCatalogKey(binding.key) {
                findings.append(.catalogUnsupportedKey(binding.command, binding.key))
            }
            if binding.modifiers.contains(.function) {
                findings.append(.catalogUnsupportedModifier(binding.command, .function))
            }
            if !seenCommands.insert(binding.command).inserted {
                findings.append(.catalogDuplicateCommand(binding.command))
            }
            if let existing = commandByChord[binding.chord] {
                findings.append(.catalogDuplicateChord(existing, binding.command))
            } else {
                commandByChord[binding.chord] = binding.command
            }
        }
        for command in Command.allCases where !seenCommands.contains(command) {
            findings.append(.catalogMissingCommand(command))
        }
        return findings
    }

    private static func isSupportedCatalogKey(_ key: Character) -> Bool {
        guard key.unicodeScalars.count == 1, let scalar = key.unicodeScalars.first else {
            return false
        }
        return (0x61...0x7A).contains(scalar.value) || (0x30...0x39).contains(scalar.value)
    }

    private static func policyFindings(
        for binding: Binding,
        policy: KeyboardShortcutPolicy
    ) throws(KeyboardShortcutPolicyError) -> [Finding] {
        var findings: [Finding] = []
        if let command = binding.comparisonCommand {
            let entries = policy.commandShortcuts.filter { $0.command == command }
            if !entries.contains(where: { $0.chord == binding.chord }) {
                findings.append(.policyBindingMissing(binding.command))
            }
            for entry in entries where entry.chord != binding.chord {
                findings.append(.policyBindingUnexpectedChord(binding.command, entry.chord))
            }
        }

        for focus in [Policy.EditorFocus.none, .editable] {
            let resolution = try policy.resolve(
                binding.chord,
                in: satisfyingContext(editorFocus: focus)
            )
            let expected: Policy.Route =
                binding.comparisonCommand.map(Policy.Route.applicationCommand) ?? .unhandled
            if resolution.route != expected {
                findings.append(.policyRouteMismatch(binding.command, focus, resolution.route))
            }
        }
        return findings
    }

    private static func auditFindings(
        for binding: Binding,
        inventory: ShortcutCoverageAudit.Inventory
    ) -> [Finding] {
        var findings: [Finding] = []
        let entries = inventory.bindings.filter { $0.command == binding.auditCommand }
        let matching = entries.filter { $0.policyChord == binding.chord }
        if matching.isEmpty {
            findings.append(.auditBindingMissing(binding.command))
        }
        for entry in entries where entry.policyChord != binding.chord {
            findings.append(.auditBindingUnexpectedChord(binding.command, entry.policyChord))
        }
        let expectedDescriptor = macOSDescriptor(for: binding)
        if matching.contains(where: { $0.shortcut.canonicalized != expectedDescriptor }) {
            findings.append(.auditBindingDescriptorMismatch(binding.command))
        }
        for other in inventory.bindings
        where other.policyChord == binding.chord && other.command != binding.auditCommand {
            findings.append(.auditChordClaimedByOtherCommand(binding.command, other.command))
        }
        return findings
    }

    /// Canonical macOS menu descriptor for a catalog binding.
    public static func macOSDescriptor(for binding: Binding) -> MenuShortcutDescriptor {
        let modifiers = Set(
            binding.modifiers.map { modifier -> MenuShortcutModifier in
                switch modifier {
                case .command: .command
                case .control: .control
                case .option: .option
                case .shift: .shift
                case .function: .function
                }
            })
        return MenuShortcutDescriptor(
            platform: .macOS,
            key: String(binding.key),
            modifiers: modifiers
        ).canonicalized
    }

    // MARK: - Menu inventory verification

    /// One captured menu item. Built from AppKit by the app target; kept platform-neutral here.
    public struct ObservedMenuItem: Hashable, Sendable {
        public let title: String
        /// Raw AppKit `keyEquivalent`; an uppercase letter implies Shift.
        public let keyEquivalent: String
        public let modifiers: Set<Policy.Modifier>
        /// Selector name, e.g. `terminate:`; `nil` when the item has no action.
        public let actionSelector: String?
        /// Top-level menu that contains the item, when known.
        public let location: MenuLocation?

        public init(
            title: String,
            keyEquivalent: String,
            modifiers: Set<Policy.Modifier>,
            actionSelector: String?,
            location: MenuLocation?
        ) {
            self.title = title
            self.keyEquivalent = keyEquivalent
            self.modifiers = modifiers
            self.actionSelector = actionSelector
            self.location = location
        }

        /// Canonical chord, or `nil` when the item has no shortcut or one the policy cannot model.
        public var chord: Policy.Chord? {
            guard keyEquivalent.count == 1, let character = keyEquivalent.first else {
                return nil
            }
            var effectiveModifiers = modifiers
            if character.isUppercase { effectiveModifiers.insert(.shift) }
            return try? Policy.Chord(.character(character), modifiers: effectiveModifiers)
        }
    }

    public static let maximumObservedMenuItems = 8_192

    /// Verifies each catalog chord is bound by exactly one captured menu item with the expected
    /// title, top-level location, and (for AppKit-owned commands) selector. SwiftUI-bridged
    /// items must carry some action; their bridge selector is not otherwise compared.
    public static func verifyMenu(_ items: [ObservedMenuItem]) -> [Finding] {
        guard items.count <= maximumObservedMenuItems else {
            return [.menuInventoryTooLarge(maximum: maximumObservedMenuItems)]
        }
        var itemsByChord: [Policy.Chord: [ObservedMenuItem]] = [:]
        for item in items {
            guard let chord = item.chord else { continue }
            itemsByChord[chord, default: []].append(item)
        }

        var findings: [Finding] = []
        for binding in bindings {
            let bound = itemsByChord[binding.chord] ?? []
            guard let item = bound.first else {
                findings.append(.menuItemMissing(binding.command))
                if let titled = items.first(where: { binding.matchesTitle($0.title) }) {
                    findings.append(
                        .menuItemTitleBoundElsewhere(
                            binding.command,
                            observedKeyEquivalent: titled.keyEquivalent
                        ))
                }
                continue
            }
            if bound.count > 1 {
                findings.append(.menuItemDuplicated(binding.command, count: bound.count))
            }
            if !binding.matchesTitle(item.title) {
                findings.append(.menuItemTitleMismatch(binding.command, observed: item.title))
            }
            if item.location != binding.menuLocation {
                findings.append(.menuItemLocationMismatch(binding.command, observed: item.location))
            }
            if case .appKitSelector(let selector) = binding.menuAction {
                if item.actionSelector != selector {
                    findings.append(
                        .menuItemActionMismatch(binding.command, observed: item.actionSelector))
                }
            } else if item.actionSelector == nil {
                // The bridge selector itself is opaque, but a bridged item with no action is dead.
                findings.append(.menuItemActionMismatch(binding.command, observed: nil))
            }
        }
        return findings
    }
}
