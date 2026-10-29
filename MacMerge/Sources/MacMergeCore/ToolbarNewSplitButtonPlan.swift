import Foundation

/// UI-independent presentation plan for WinMerge's `ID_FILE_NEW` toolbar split button.
///
/// WinMerge marks `ID_FILE_NEW` with `TBSTYLE_DROPDOWN` and enables `TBSTYLE_EX_DRAWDDARROWS`
/// (`Src/MainFrm.cpp`), so the toolbar shows a primary button plus a separate drop-down arrow.
/// Clicking the button runs `ID_FILE_NEW` (two-pane Text). Clicking the arrow shows
/// `IDR_POPUP_NEW` from `Src/Merge.rc`: Text, Table, Binary, Image, Webpage, Folder.
///
/// The macOS toolbar also offers WinMerge's File menu `New (&3 panes)` submenu from the same
/// split button. That submenu is a documented macOS exception: WinMerge exposes it only from the
/// File menu, while the Mac toolbar keeps every New action reachable from one control.
///
/// The app renders this plan through `ToolbarCommandLayout.makeControl(.newComparison)`. The Mac
/// toolbar has no overflow handling yet, so this plan models only the visible split button.
public struct ToolbarNewSplitButtonPlan: Equatable, Sendable {
    public typealias CommandID = NewDocumentRoutingPolicy.CommandID
    public typealias Mode = NewDocumentRoutingPolicy.Mode
    public typealias PaneCount = NewDocumentRoutingPolicy.PaneCount

    /// Provenance of each action so audits can separate WinMerge parity from Mac exceptions.
    public enum Source: String, CaseIterable, Hashable, Sendable {
        /// `IDR_POPUP_NEW`, the WinMerge toolbar drop-down menu.
        case winMergeToolbarPopup
        /// File menu `New (&3 panes)`, surfaced in the toolbar as a macOS exception.
        case winMergeFileMenuThreePaneExtension
    }

    public enum SectionKind: String, CaseIterable, Hashable, Sendable {
        case twoPane
        case threePane
    }

    /// How a section's entries appear inside the split button's menu.
    public enum SectionPresentation: String, CaseIterable, Hashable, Sendable {
        case inline
        case submenu
    }

    /// Controls whether the three-pane exception is offered from the toolbar menu.
    public enum ThreePaneVariants: String, CaseIterable, Hashable, Sendable {
        /// Strict WinMerge `IDR_POPUP_NEW` parity: two-pane actions only.
        case omitted
        /// macOS exception: a `New (3 panes)` submenu after a separator.
        case submenu
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        /// The shared New command gate is closed, for example while a comparison is working.
        case newCommandUnavailable
        /// The app cannot yet create a document of this mode and pane count.
        case notImplemented(mode: Mode, paneCount: PaneCount)
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

    /// One selectable New action.
    public struct Entry: Equatable, Hashable, Sendable, Identifiable {
        public let commandID: CommandID
        /// Display title with WinMerge's `&` mnemonic marker removed.
        public let title: String
        /// WinMerge resource text, including the `&` mnemonic marker.
        public let resourceTitle: String
        /// Lowercased mnemonic character from the resource title, if any.
        public let mnemonic: Character?
        /// Self-contained label for VoiceOver, including the pane count.
        public let accessibilityLabel: String
        public let source: Source
        public let availability: Availability

        public var id: String { commandID.rawValue }
        public var isEnabled: Bool { availability.isEnabled }
        public var isPrimaryAction: Bool { commandID == ToolbarNewSplitButtonPlan.primaryCommandID }
    }

    /// A separator-delimited group of entries.
    public struct Section: Equatable, Hashable, Sendable, Identifiable {
        public let kind: SectionKind
        /// Submenu title when `presentation == .submenu`, without mnemonic marker.
        public let title: String?
        /// WinMerge resource title for the submenu, including the `&` marker.
        public let resourceTitle: String?
        public let presentation: SectionPresentation
        public let entries: [Entry]

        public var id: String { kind.rawValue }
    }

    public static let primaryCommandID: CommandID = .twoPaneText
    /// Visible button label. This is a macOS addition: WinMerge's `ID_FILE_NEW` string-table
    /// prompt (`"\nNew Documents (Ctrl+N)"`, `Src/Merge.rc`) has an empty label part, so the
    /// Windows toolbar shows only an icon.
    public static let primaryTitle = "New"
    /// Tooltip text of the `ID_FILE_NEW` string-table prompt, without the shortcut.
    public static let primaryAccessibilityLabel = "New Documents"
    /// Tooltip of the `ID_FILE_NEW` string-table prompt, with `Ctrl+N` spelled from the
    /// `FileLifecycleShortcuts` catalog (`Command-N`).
    public static let primaryHelp = "New Documents (\(FileLifecycleShortcuts.helpText(.new)))"
    public static let secondaryActionsAccessibilityHint = "Shows more New comparison types."

    /// Commands the macOS app can currently create. Others stay visible but disabled.
    public static let currentlyImplementedCommands: Set<CommandID> = [.twoPaneText]

    public let primaryCommandID: CommandID
    public let primaryAvailability: Availability
    public let sections: [Section]

    /// Every entry in menu order.
    public var entries: [Entry] { sections.flatMap(\.entries) }

    /// True when every WinMerge `IDR_POPUP_NEW` command is present in the menu.
    public var representsEveryToolbarPopupCommand: Bool {
        let present = Set(entries.lazy.filter { $0.source == .winMergeToolbarPopup }.map(\.commandID))
        return Self.toolbarPopupResources.allSatisfy { present.contains($0.commandID) }
    }

    public func entry(for commandID: CommandID) -> Entry? {
        entries.first { $0.commandID == commandID }
    }

    /// Builds the plan for the given command gate and implementation coverage.
    ///
    /// - Parameters:
    ///   - isNewCommandEnabled: The shared `ID_FILE_NEW` gate, for example `!model.isWorking`.
    ///   - implementedCommands: Commands that can create a document today.
    ///   - threePaneVariants: Whether to offer the File-menu three-pane submenu.
    public static func make(
        isNewCommandEnabled: Bool,
        implementedCommands: Set<CommandID> = currentlyImplementedCommands,
        threePaneVariants: ThreePaneVariants = .submenu
    ) -> ToolbarNewSplitButtonPlan {
        func availability(_ commandID: CommandID) -> Availability {
            guard isNewCommandEnabled else { return .disabled(.newCommandUnavailable) }
            guard implementedCommands.contains(commandID) else {
                return .disabled(
                    .notImplemented(mode: commandID.mode, paneCount: commandID.paneCount))
            }
            return .enabled
        }

        func entry(_ resource: ResourceItem, source: Source) -> Entry {
            Entry(
                commandID: resource.commandID,
                title: Self.strippingMnemonic(resource.resourceTitle),
                resourceTitle: resource.resourceTitle,
                mnemonic: Self.mnemonic(in: resource.resourceTitle),
                accessibilityLabel: Self.accessibilityLabel(for: resource.commandID),
                source: source,
                availability: availability(resource.commandID)
            )
        }

        var sections = [
            Section(
                kind: .twoPane,
                title: nil,
                resourceTitle: nil,
                presentation: .inline,
                entries: toolbarPopupResources.map { entry($0, source: .winMergeToolbarPopup) }
            )
        ]
        if threePaneVariants == .submenu {
            sections.append(
                Section(
                    kind: .threePane,
                    title: strippingMnemonic(threePaneSubmenuResourceTitle),
                    resourceTitle: threePaneSubmenuResourceTitle,
                    presentation: .submenu,
                    entries: threePaneResources.map {
                        entry($0, source: .winMergeFileMenuThreePaneExtension)
                    }
                )
            )
        }

        return ToolbarNewSplitButtonPlan(
            primaryCommandID: primaryCommandID,
            primaryAvailability: availability(primaryCommandID),
            sections: sections
        )
    }

    // MARK: - WinMerge resources

    struct ResourceItem: Equatable, Sendable {
        let commandID: CommandID
        let resourceTitle: String
    }

    /// `IDR_POPUP_NEW` in `Src/Merge.rc`, exact order and text.
    static let toolbarPopupResources: [ResourceItem] = [
        ResourceItem(commandID: .twoPaneText, resourceTitle: "&Text"),
        ResourceItem(commandID: .twoPaneTable, resourceTitle: "T&able"),
        ResourceItem(commandID: .twoPaneBinary, resourceTitle: "&Binary"),
        ResourceItem(commandID: .twoPaneImage, resourceTitle: "&Image"),
        ResourceItem(commandID: .twoPaneWebpage, resourceTitle: "&Webpage"),
        ResourceItem(commandID: .twoPaneFolder, resourceTitle: "&Folder")
    ]

    /// File menu `New (&3 panes)` popup in `Src/Merge.rc`, exact order and text.
    static let threePaneSubmenuResourceTitle = "New (&3 panes)"
    static let threePaneResources: [ResourceItem] = [
        ResourceItem(commandID: .threePaneText, resourceTitle: "&Text"),
        ResourceItem(commandID: .threePaneTable, resourceTitle: "T&able"),
        ResourceItem(commandID: .threePaneBinary, resourceTitle: "&Binary"),
        ResourceItem(commandID: .threePaneImage, resourceTitle: "&Image"),
        ResourceItem(commandID: .threePaneWebpage, resourceTitle: "&Webpage"),
        ResourceItem(commandID: .threePaneFolder, resourceTitle: "&Folder")
    ]

    /// Removes single `&` mnemonic markers and collapses `&&` to a literal `&`.
    static func strippingMnemonic(_ resourceTitle: String) -> String {
        var result = ""
        result.reserveCapacity(resourceTitle.count)
        var pendingAmpersand = false
        for character in resourceTitle {
            if character == "&" {
                if pendingAmpersand {
                    result.append("&")
                    pendingAmpersand = false
                } else {
                    pendingAmpersand = true
                }
                continue
            }
            pendingAmpersand = false
            result.append(character)
        }
        return result
    }

    /// The character after the first single `&`, lowercased.
    static func mnemonic(in resourceTitle: String) -> Character? {
        var iterator = resourceTitle.makeIterator()
        while let character = iterator.next() {
            guard character == "&" else { continue }
            guard let next = iterator.next() else { return nil }
            if next == "&" { continue }
            return Character(next.lowercased())
        }
        return nil
    }

    static func accessibilityLabel(for commandID: CommandID) -> String {
        let mode: String
        switch commandID.mode {
        case .text: mode = "Text"
        case .table: mode = "Table"
        case .binary: mode = "Binary"
        case .image: mode = "Image"
        case .webpage: mode = "Webpage"
        case .folder: mode = "Folder"
        }
        switch commandID.paneCount {
        case .two: return "New \(mode) Comparison"
        case .three: return "New 3-Pane \(mode) Comparison"
        }
    }
}
