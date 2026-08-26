/// UI-independent command state shared by menus, toolbars, shortcuts, and action guards.
public enum ComparisonCommandState: Sendable {
    public typealias Side = MergeCommandPolicy.Side

    /// Stable semantic command identity. Toolbar identities map one-to-one through
    /// `init(_:)` and `toolbarCommand`; remaining cases are menu-only commands.
    public enum Identifier: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
        case newComparison
        case openComparison
        case openLeft
        case openMiddle
        case openRight
        case save
        case saveLeft
        case saveMiddle
        case saveRight
        case saveLeftAs
        case saveMiddleAs
        case saveRightAs
        case undo
        case redo
        case selectLineDifference
        case selectPreviousLineDifference
        case nextDifference
        case previousDifference
        case nextConflict
        case previousConflict
        case firstConflict
        case currentConflict
        case lastConflict
        case firstDifference
        case currentDifference
        case lastDifference
        case copyToRight
        case copyToLeft
        case copyToRightAndAdvance
        case copyToLeftAndAdvance
        case copyAllToRight
        case copyAllToLeft
        case autoMerge
        case firstComparedFile
        case previousComparedFile
        case nextComparedFile
        case lastComparedFile
        case leftReadOnly
        case middleReadOnly
        case rightReadOnly
        case mergeMode
        case reloadFromDisk
        case changePane
        case changePaneBack
        case options
        case refresh

        public init(_ command: ToolbarConfiguration.Command) {
            switch command {
            case .newComparison: self = .newComparison
            case .openComparison: self = .openComparison
            case .save: self = .save
            case .undo: self = .undo
            case .redo: self = .redo
            case .selectLineDifference: self = .selectLineDifference
            case .nextDifference: self = .nextDifference
            case .previousDifference: self = .previousDifference
            case .nextConflict: self = .nextConflict
            case .previousConflict: self = .previousConflict
            case .firstDifference: self = .firstDifference
            case .currentDifference: self = .currentDifference
            case .lastDifference: self = .lastDifference
            case .copyToRight: self = .copyToRight
            case .copyToLeft: self = .copyToLeft
            case .copyToRightAndAdvance: self = .copyToRightAndAdvance
            case .copyToLeftAndAdvance: self = .copyToLeftAndAdvance
            case .copyAllToRight: self = .copyAllToRight
            case .copyAllToLeft: self = .copyAllToLeft
            case .autoMerge: self = .autoMerge
            case .firstComparedFile: self = .firstComparedFile
            case .previousComparedFile: self = .previousComparedFile
            case .nextComparedFile: self = .nextComparedFile
            case .lastComparedFile: self = .lastComparedFile
            case .options: self = .options
            case .refresh: self = .refresh
            }
        }

        public var toolbarCommand: ToolbarConfiguration.Command? {
            switch self {
            case .newComparison: .newComparison
            case .openComparison: .openComparison
            case .save: .save
            case .undo: .undo
            case .redo: .redo
            case .selectLineDifference: .selectLineDifference
            case .nextDifference: .nextDifference
            case .previousDifference: .previousDifference
            case .nextConflict: .nextConflict
            case .previousConflict: .previousConflict
            case .firstDifference: .firstDifference
            case .currentDifference: .currentDifference
            case .lastDifference: .lastDifference
            case .copyToRight: .copyToRight
            case .copyToLeft: .copyToLeft
            case .copyToRightAndAdvance: .copyToRightAndAdvance
            case .copyToLeftAndAdvance: .copyToLeftAndAdvance
            case .copyAllToRight: .copyAllToRight
            case .copyAllToLeft: .copyAllToLeft
            case .autoMerge: .autoMerge
            case .firstComparedFile: .firstComparedFile
            case .previousComparedFile: .previousComparedFile
            case .nextComparedFile: .nextComparedFile
            case .lastComparedFile: .lastComparedFile
            case .options: .options
            case .refresh: .refresh
            case .openLeft, .openMiddle, .openRight,
                .saveLeft, .saveMiddle, .saveRight,
                .saveLeftAs, .saveMiddleAs, .saveRightAs,
                .selectPreviousLineDifference,
                .firstConflict, .currentConflict, .lastConflict,
                .leftReadOnly, .middleReadOnly, .rightReadOnly,
                .mergeMode, .reloadFromDisk, .changePane, .changePaneBack:
                nil
            }
        }
    }

    public enum ComparisonLifecycle: Equatable, Hashable, Sendable {
        case loading
        case refreshing
        case stale
        case failed
        case canceled
        case currentSuccess

        public init(_ lifecycle: MergeCommandPolicy.ComparisonLifecycle) {
            switch lifecycle {
            case .loading: self = .loading
            case .stale: self = .stale
            case .failed: self = .failed
            case .currentSuccess: self = .currentSuccess
            }
        }

        /// Lossy adapter for policies that predate refresh and cancellation states.
        public var mergeCommandLifecycle: MergeCommandPolicy.ComparisonLifecycle {
            switch self {
            case .loading, .refreshing: .loading
            case .stale: .stale
            case .failed, .canceled: .failed
            case .currentSuccess: .currentSuccess
            }
        }
    }

    public struct PaneState: Equatable, Hashable, Sendable {
        public let isLoaded: Bool
        public let isEditable: Bool
        public let isDirty: Bool
        public let isUntitled: Bool
        /// True only after a caller has established that the backing file differs from its
        /// opened identity. Untitled panes cannot have an external change.
        public let hasExternalChange: Bool

        public init(
            isLoaded: Bool = false,
            isEditable: Bool = false,
            isDirty: Bool = false,
            isUntitled: Bool = false,
            hasExternalChange: Bool = false
        ) {
            self.isLoaded = isLoaded
            self.isEditable = isEditable
            self.isDirty = isDirty
            self.isUntitled = isUntitled
            self.hasExternalChange = hasExternalChange
        }

        public init(
            _ state: MergeCommandPolicy.SideState,
            isUntitled: Bool = false,
            hasExternalChange: Bool = false
        ) {
            isLoaded = state.isLoaded
            isEditable = state.isEditable
            isDirty = state.isDirty
            self.isUntitled = isUntitled
            self.hasExternalChange = hasExternalChange
        }

        public var isReadOnly: Bool { isLoaded && !isEditable }
        public var isReloadable: Bool { isLoaded && !isUntitled }

        public var mergeCommandState: MergeCommandPolicy.SideState {
            MergeCommandPolicy.SideState(
                isLoaded: isLoaded,
                isEditable: isEditable,
                isDirty: isDirty
            )
        }
    }

    public enum Layout: Equatable, Hashable, Sendable {
        case twoPane
        case threePane(
            middle: PaneState,
            automaticMergeDestination: Side,
            supportsAutomaticMerge: Bool = false,
            isAutomaticMergeEligible: Bool = false
        )

        public var isThreePane: Bool {
            guard case .threePane = self else { return false }
            return true
        }

        public var middle: PaneState? {
            guard case .threePane(let middle, _, _, _) = self else { return nil }
            return middle
        }

        public var automaticMergeDestination: Side? {
            guard case .threePane(_, let destination, _, _) = self else { return nil }
            return destination
        }

        public var supportsAutomaticMerge: Bool {
            guard case .threePane(_, _, let isSupported, _) = self else { return false }
            return isSupported
        }

        public var isAutomaticMergeEligible: Bool {
            guard case .threePane(_, _, _, let isEligible) = self else { return false }
            return isEligible
        }
    }

    public enum VisualPosition: Equatable, Hashable, Sendable {
        case left
        case middle
        case right
    }

    public enum VisualDirection: Equatable, Hashable, Sendable {
        case left
        case right
    }

    public struct CopyRoute: Equatable, Hashable, Sendable {
        public let source: Side
        public let destination: Side
        public let sourcePosition: VisualPosition
        public let destinationPosition: VisualPosition

        public init(
            source: Side,
            destination: Side,
            sourcePosition: VisualPosition,
            destinationPosition: VisualPosition
        ) {
            self.source = source
            self.destination = destination
            self.sourcePosition = sourcePosition
            self.destinationPosition = destinationPosition
        }
    }

    public enum LayoutContextError: Error, Equatable, Sendable {
        case invalidVisualOrder([Side])
        case activePaneNotPresent(Side)
    }

    /// Snapshot of logical pane ownership in current visual order.
    ///
    /// Command resolution consumes this value rather than consulting mutable UI layout state.
    public struct LayoutContext: Equatable, Hashable, Sendable {
        public let visualOrder: [Side]
        public let activePane: Side

        public init(visualOrder: [Side], activePane: Side) throws {
            let expectedSides: Set<Side>
            switch visualOrder.count {
            case 2: expectedSides = [.left, .right]
            case 3: expectedSides = Set(Side.allCases)
            default: throw LayoutContextError.invalidVisualOrder(visualOrder)
            }
            guard Set(visualOrder) == expectedSides else {
                throw LayoutContextError.invalidVisualOrder(visualOrder)
            }
            guard visualOrder.contains(activePane) else {
                throw LayoutContextError.activePaneNotPresent(activePane)
            }
            self.visualOrder = visualOrder
            self.activePane = activePane
        }

        /// Captures a validated `PaneLayout` without retaining or mutating it.
        public init(_ paneLayout: PaneLayout) {
            visualOrder = paneLayout.visualOrder.map(Self.side(for:))
            activePane = Self.side(for: paneLayout.activePane)
        }

        public func side(at position: VisualPosition) -> Side? {
            switch position {
            case .left: visualOrder.first
            case .middle: visualOrder.count == 3 ? visualOrder[1] : nil
            case .right: visualOrder.last
            }
        }

        public func visualPosition(of side: Side) -> VisualPosition? {
            guard let index = visualOrder.firstIndex(of: side) else { return nil }
            if index == visualOrder.startIndex { return .left }
            if index == visualOrder.index(before: visualOrder.endIndex) { return .right }
            return .middle
        }

        public func copyRoute(toward direction: VisualDirection) -> CopyRoute? {
            guard let activeIndex = visualOrder.firstIndex(of: activePane), visualOrder.count > 1 else {
                return nil
            }
            switch direction {
            case .left:
                let destinationIndex = max(activeIndex - 1, visualOrder.startIndex)
                return CopyRoute(
                    source: visualOrder[destinationIndex + 1],
                    destination: visualOrder[destinationIndex],
                    sourcePosition: visualPosition(at: destinationIndex + 1),
                    destinationPosition: visualPosition(at: destinationIndex)
                )
            case .right:
                let destinationIndex = min(activeIndex + 1, visualOrder.index(before: visualOrder.endIndex))
                return CopyRoute(
                    source: visualOrder[destinationIndex - 1],
                    destination: visualOrder[destinationIndex],
                    sourcePosition: visualPosition(at: destinationIndex - 1),
                    destinationPosition: visualPosition(at: destinationIndex)
                )
            }
        }

        public func copyRoute(for command: Identifier) -> CopyRoute? {
            switch command {
            case .copyToLeft, .copyToLeftAndAdvance, .copyAllToLeft:
                copyRoute(toward: .left)
            case .copyToRight, .copyToRightAndAdvance, .copyAllToRight:
                copyRoute(toward: .right)
            case .newComparison, .openComparison, .openLeft, .openMiddle, .openRight,
                .save, .saveLeft, .saveMiddle, .saveRight,
                .saveLeftAs, .saveMiddleAs, .saveRightAs,
                .undo, .redo, .selectLineDifference, .selectPreviousLineDifference,
                .nextDifference, .previousDifference,
                .nextConflict, .previousConflict, .firstConflict, .currentConflict, .lastConflict,
                .firstDifference, .currentDifference, .lastDifference,
                .autoMerge,
                .firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile,
                .leftReadOnly, .middleReadOnly, .rightReadOnly,
                .mergeMode, .reloadFromDisk, .changePane, .changePaneBack, .options, .refresh:
                nil
            }
        }

        fileprivate init(defaultFor layout: Layout) {
            switch layout {
            case .twoPane:
                visualOrder = [.left, .right]
            case .threePane:
                visualOrder = [.left, .middle, .right]
            }
            activePane = .left
        }

        fileprivate func normalized(for layout: Layout) -> LayoutContext {
            let expectedSides: Set<Side> =
                layout.isThreePane ? Set(Side.allCases) : [.left, .right]
            guard visualOrder.count == expectedSides.count,
                Set(visualOrder) == expectedSides,
                expectedSides.contains(activePane)
            else {
                return LayoutContext(defaultFor: layout)
            }
            return self
        }

        private static func side(for identity: PaneIdentity) -> Side {
            switch identity {
            case .left: .left
            case .middle: .middle
            case .right: .right
            }
        }

        private func visualPosition(at index: Int) -> VisualPosition {
            if index == visualOrder.startIndex { return .left }
            if index == visualOrder.index(before: visualOrder.endIndex) { return .right }
            return .middle
        }
    }

    /// Caller-computed, cursor-relative difference destinations. False never implies that the
    /// comparison is equal; it means this particular command has no valid target.
    public struct DifferenceNavigation: Equatable, Hashable, Sendable {
        public static let unavailable = DifferenceNavigation()

        public let canSelectLineDifference: Bool
        public let canSelectPreviousLineDifference: Bool
        public let canSelectNextDifference: Bool
        public let canSelectPreviousDifference: Bool
        public let canSelectFirstDifference: Bool
        public let canSelectCurrentDifference: Bool
        public let canSelectLastDifference: Bool

        public init(
            canSelectLineDifference: Bool = false,
            canSelectPreviousLineDifference: Bool = false,
            canSelectNextDifference: Bool = false,
            canSelectPreviousDifference: Bool = false,
            canSelectFirstDifference: Bool = false,
            canSelectCurrentDifference: Bool = false,
            canSelectLastDifference: Bool = false
        ) {
            self.canSelectLineDifference = canSelectLineDifference
            self.canSelectPreviousLineDifference = canSelectPreviousLineDifference
            self.canSelectNextDifference = canSelectNextDifference
            self.canSelectPreviousDifference = canSelectPreviousDifference
            self.canSelectFirstDifference = canSelectFirstDifference
            self.canSelectCurrentDifference = canSelectCurrentDifference
            self.canSelectLastDifference = canSelectLastDifference
        }
    }

    /// Conflict commands remain unsupported until a document model declares integration with a
    /// conflict index. Targets are cursor-relative and do not wrap.
    public struct ConflictNavigationState: Equatable, Hashable, Sendable {
        public static let unsupported = ConflictNavigationState()

        public let isSupported: Bool
        public let hasConflicts: Bool
        public let canSelectFirstConflict: Bool
        public let canSelectNextConflict: Bool
        public let canSelectPreviousConflict: Bool
        public let canSelectCurrentConflict: Bool
        public let canSelectLastConflict: Bool

        public init(
            isSupported: Bool = false,
            hasConflicts: Bool = false,
            canSelectFirstConflict: Bool = false,
            canSelectNextConflict: Bool = false,
            canSelectPreviousConflict: Bool = false,
            canSelectCurrentConflict: Bool = false,
            canSelectLastConflict: Bool = false
        ) {
            self.isSupported = isSupported
            self.hasConflicts = hasConflicts
            self.canSelectFirstConflict = canSelectFirstConflict
            self.canSelectNextConflict = canSelectNextConflict
            self.canSelectPreviousConflict = canSelectPreviousConflict
            self.canSelectCurrentConflict = canSelectCurrentConflict
            self.canSelectLastConflict = canSelectLastConflict
        }
    }

    /// Command states supplied by `DirectoryPairNavigator` once folder-comparison routing exists.
    public struct ComparedFileNavigation: Equatable, Hashable, Sendable {
        public static let unsupported = ComparedFileNavigation()

        public let isSupported: Bool
        public let canSelectFirst: Bool
        public let canSelectPrevious: Bool
        public let canSelectNext: Bool
        public let canSelectLast: Bool

        public init(
            isSupported: Bool = false,
            canSelectFirst: Bool = false,
            canSelectPrevious: Bool = false,
            canSelectNext: Bool = false,
            canSelectLast: Bool = false
        ) {
            self.isSupported = isSupported
            self.canSelectFirst = canSelectFirst
            self.canSelectPrevious = canSelectPrevious
            self.canSelectNext = canSelectNext
            self.canSelectLast = canSelectLast
        }

        public init(_ states: DirectoryPairNavigationCommandStates) {
            isSupported = true
            canSelectFirst = states.first
            canSelectPrevious = states.previous
            canSelectNext = states.next
            canSelectLast = states.last
        }
    }

    public struct Context: Equatable, Hashable, Sendable {
        public let left: PaneState
        public let right: PaneState
        public let layout: Layout
        public let layoutContext: LayoutContext
        public let comparisonLifecycle: ComparisonLifecycle
        /// True when selection or cursor resolves to a significant difference.
        public let hasSelection: Bool
        public let hasSignificantDifferences: Bool
        /// Undo/redo already routed for current responder. Policy never guesses native editor state.
        public let canUndo: Bool
        public let canRedo: Bool
        public let differenceNavigation: DifferenceNavigation
        public let conflictNavigation: ConflictNavigationState
        public let comparedFileNavigation: ComparedFileNavigation
        /// Pane switching is responder-specific, so callers must declare both directions.
        public let canChangePane: Bool
        public let canChangePaneBack: Bool
        public let isMergeMode: Bool
        /// Covers session persistence/teardown phases not represented by comparison lifecycle.
        public let isSessionLocked: Bool

        public init(
            left: PaneState = PaneState(),
            right: PaneState = PaneState(),
            layout: Layout = .twoPane,
            layoutContext: LayoutContext? = nil,
            lifecycle: ComparisonLifecycle = .currentSuccess,
            hasSelection: Bool = false,
            hasSignificantDifferences: Bool = false,
            canUndo: Bool = false,
            canRedo: Bool = false,
            differenceNavigation: DifferenceNavigation = .unavailable,
            conflictNavigation: ConflictNavigationState = .unsupported,
            comparedFileNavigation: ComparedFileNavigation = .unsupported,
            canChangePane: Bool = false,
            canChangePaneBack: Bool = false,
            isMergeMode: Bool = false,
            isSessionLocked: Bool = false
        ) {
            self.left = left
            self.right = right
            self.layout = layout
            self.layoutContext =
                layoutContext?.normalized(for: layout) ?? LayoutContext(defaultFor: layout)
            comparisonLifecycle = lifecycle
            self.hasSelection = hasSelection
            self.hasSignificantDifferences = hasSignificantDifferences
            self.canUndo = canUndo
            self.canRedo = canRedo
            self.differenceNavigation = differenceNavigation
            self.conflictNavigation = conflictNavigation
            self.comparedFileNavigation = comparedFileNavigation
            self.canChangePane = canChangePane
            self.canChangePaneBack = canChangePaneBack
            self.isMergeMode = isMergeMode
            self.isSessionLocked = isSessionLocked
        }

        public init(
            left: PaneState = PaneState(),
            right: PaneState = PaneState(),
            layout: Layout = .twoPane,
            layoutContext: LayoutContext? = nil,
            comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle,
            hasSelection: Bool = false,
            hasSignificantDifferences: Bool = false,
            canUndo: Bool = false,
            canRedo: Bool = false,
            differenceNavigation: DifferenceNavigation = .unavailable,
            conflictNavigation: ConflictNavigationState = .unsupported,
            comparedFileNavigation: ComparedFileNavigation = .unsupported,
            canChangePane: Bool = false,
            canChangePaneBack: Bool = false,
            isMergeMode: Bool = false,
            isSessionLocked: Bool = false
        ) {
            self.init(
                left: left,
                right: right,
                layout: layout,
                layoutContext: layoutContext,
                lifecycle: ComparisonLifecycle(comparisonLifecycle),
                hasSelection: hasSelection,
                hasSignificantDifferences: hasSignificantDifferences,
                canUndo: canUndo,
                canRedo: canRedo,
                differenceNavigation: differenceNavigation,
                conflictNavigation: conflictNavigation,
                comparedFileNavigation: comparedFileNavigation,
                canChangePane: canChangePane,
                canChangePaneBack: canChangePaneBack,
                isMergeMode: isMergeMode,
                isSessionLocked: isSessionLocked
            )
        }

        public var isEmpty: Bool { activePanes.allSatisfy { !$0.state.isLoaded } }
        public var isThreePane: Bool { layout.isThreePane }

        public var mergeCommandState: MergeCommandPolicy.State {
            let mergeLayout: MergeCommandPolicy.State.Layout
            switch layout {
            case .twoPane:
                mergeLayout = .twoWay
            case .threePane(let middle, let destination, _, let isEligible):
                mergeLayout = .threeWay(
                    middle: middle.mergeCommandState,
                    autoMergeDestination: destination,
                    isAutoMergeEligible: isEligible
                )
            }
            return MergeCommandPolicy.State(
                left: left.mergeCommandState,
                right: right.mergeCommandState,
                layout: mergeLayout,
                comparisonLifecycle: comparisonLifecycle.mergeCommandLifecycle,
                hasSelection: hasSelection,
                hasSignificantDifferences: hasSignificantDifferences
            )
        }

        public subscript(side: Side) -> PaneState? {
            switch side {
            case .left: left
            case .middle: layout.middle
            case .right: right
            }
        }

        public func side(at position: VisualPosition) -> Side? {
            layoutContext.side(at: position)
        }

        public func pane(at position: VisualPosition) -> PaneState? {
            side(at: position).flatMap { self[$0] }
        }

        fileprivate var activePanes: [(side: Side, state: PaneState)] {
            layoutContext.visualOrder.compactMap { side in
                self[side].map { (side, $0) }
            }
        }
    }

    public enum DifferenceTarget: Equatable, Hashable, Sendable {
        case line
        case previousLine
        case next
        case previous
        case first
        case current
        case last
    }

    public enum ConflictTarget: Equatable, Hashable, Sendable {
        case first
        case previous
        case current
        case next
        case last
    }

    public enum ComparedFileTarget: Equatable, Hashable, Sendable {
        case first
        case previous
        case next
        case last
    }

    /// Ordered predicates an action must revalidate immediately before execution.
    public enum ExecutionPrecondition: Equatable, Hashable, Sendable {
        case sessionUnlocked
        case comparisonNotLoading
        case currentComparison
        case anyPaneLoaded
        case allPanesLoaded
        case paneExists(Side)
        case paneLoaded(Side)
        case paneEditable(Side)
        case paneDirty(Side)
        case paneUnchangedExternally(Side)
        case anyDirtyPane
        case dirtyPanesEditable
        case dirtyPanesUnchangedExternally
        case hasSignificantDifferences
        case hasSelection
        case undoAvailable
        case redoAvailable
        case differenceTarget(DifferenceTarget)
        case threePane
        case conflictNavigationSupported
        case hasConflicts
        case conflictTarget(ConflictTarget)
        case automaticMergeSupported
        case automaticMergeEligible
        case allPanesClean
        case comparedFileNavigationSupported
        case comparedFileTarget(ComparedFileTarget)
        case anyReloadablePane
        case changePaneAvailable
        case changePaneBackAvailable
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case sessionLocked
        case comparisonLoading
        case comparisonRefreshing
        case comparisonStale
        case comparisonFailed
        case comparisonCanceled
        case noComparison
        case requiresThreePane
        case sideNotLoaded(Side)
        case destinationReadOnly(Side)
        case sideReadOnly(Side)
        case noSelection
        case noSignificantDifferences
        case noUnsavedChanges
        case noUnsavedChangesOnSide(Side)
        case unsavedChanges(Side)
        case externalChange(Side)
        case noUndo
        case noRedo
        case noLineDifference
        case noPreviousLineDifference
        case noNextDifference
        case noPreviousDifference
        case noFirstDifference
        case noCurrentDifference
        case noLastDifference
        case noConflicts
        case noFirstConflict
        case noNextConflict
        case noPreviousConflict
        case noCurrentConflict
        case noLastConflict
        case noFirstComparedFile
        case noPreviousComparedFile
        case noNextComparedFile
        case noLastComparedFile
        case noReloadablePane
        case paneChangeUnavailable
        case paneChangeBackUnavailable
        case automaticMergeUnavailable
        case unsupportedCommand(Identifier)
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

    public enum CheckedState: Equatable, Hashable, Sendable {
        case notApplicable
        case off
        case on
    }

    /// Semantic label choice; presentation layers own localized strings and punctuation.
    public enum TitleVariant: Equatable, Hashable, Sendable {
        case standard
        case saveAs(Side)
        case copy(to: VisualPosition)
        case copyAll(to: VisualPosition)
        case makeReadOnly(Side)
        case makeEditable(Side)
        case reloadWithUnsavedChanges
    }

    public struct Resolution: Equatable, Hashable, Sendable {
        public let command: Identifier
        public let availability: Availability
        public let checkedState: CheckedState
        public let titleVariant: TitleVariant
        public let copyRoute: CopyRoute?
        /// Matrix order is significant: availability reports the first failed predicate.
        public let executionPreconditions: [ExecutionPrecondition]

        public init(
            command: Identifier,
            availability: Availability,
            checkedState: CheckedState,
            titleVariant: TitleVariant,
            copyRoute: CopyRoute? = nil,
            executionPreconditions: [ExecutionPrecondition]
        ) {
            self.command = command
            self.availability = availability
            self.checkedState = checkedState
            self.titleVariant = titleVariant
            self.copyRoute = copyRoute
            self.executionPreconditions = executionPreconditions
        }

        public var isEnabled: Bool { availability.isEnabled }
        public var canExecute: Bool { isEnabled }
        public var disabledReason: DisabledReason? { availability.disabledReason }
        public var isChecked: Bool { checkedState == .on }
    }

    public static func resolve(_ command: Identifier, in context: Context) -> Resolution {
        let preconditions = executionPreconditions(for: command, in: context)
        let availability: Availability
        if context.isSessionLocked, preconditions.first == .sessionUnlocked {
            availability = .disabled(.sessionLocked)
        } else if let mergeCommand = mergeCommand(for: command) {
            availability = mergeAvailability(
                command,
                mergeCommand: mergeCommand,
                context: context
            )
        } else if let reason = preconditions.lazy.compactMap({
            failedReason(for: $0, command: command, context: context)
        }).first {
            availability = .disabled(reason)
        } else {
            availability = .enabled
        }

        return Resolution(
            command: command,
            availability: availability,
            checkedState: checkedState(for: command, in: context),
            titleVariant: titleVariant(for: command, in: context),
            copyRoute: context.layoutContext.copyRoute(for: command),
            executionPreconditions: preconditions
        )
    }

    public static func resolveToolbarCommand(
        _ command: ToolbarConfiguration.Command,
        in context: Context
    ) -> Resolution {
        resolve(Identifier(command), in: context)
    }

    /// All semantic commands in stable `Identifier.allCases` order.
    public static func resolveAll(in context: Context) -> [Resolution] {
        Identifier.allCases.map { resolve($0, in: context) }
    }

    /// Persisted toolbar commands in stable `ToolbarConfiguration.Command.allCases` order.
    public static func resolveToolbar(in context: Context) -> [Resolution] {
        ToolbarConfiguration.Command.allCases.map { resolveToolbarCommand($0, in: context) }
    }

    public static func canExecute(_ command: Identifier, in context: Context) -> Bool {
        resolve(command, in: context).canExecute
    }

    private static func executionPreconditions(
        for command: Identifier,
        in context: Context
    ) -> [ExecutionPrecondition] {
        switch command {
        case .newComparison, .openComparison, .openLeft, .openRight:
            [.sessionUnlocked, .comparisonNotLoading]
        case .openMiddle:
            [.sessionUnlocked, .comparisonNotLoading, .paneExists(.middle)]
        case .save:
            [
                .sessionUnlocked,
                .comparisonNotLoading,
                .anyPaneLoaded,
                .anyDirtyPane,
                .dirtyPanesEditable,
                .dirtyPanesUnchangedExternally
            ]
        case .saveLeft:
            savePreconditions(for: .left)
        case .saveMiddle:
            savePreconditions(for: .middle)
        case .saveRight:
            savePreconditions(for: .right)
        case .saveLeftAs:
            saveAsPreconditions(for: .left)
        case .saveMiddleAs:
            saveAsPreconditions(for: .middle)
        case .saveRightAs:
            saveAsPreconditions(for: .right)
        case .undo:
            [.sessionUnlocked, .comparisonNotLoading, .undoAvailable]
        case .redo:
            [.sessionUnlocked, .comparisonNotLoading, .redoAvailable]
        case .selectLineDifference:
            differencePreconditions(target: .line)
        case .selectPreviousLineDifference:
            differencePreconditions(target: .previousLine)
        case .nextDifference:
            differencePreconditions(target: .next)
        case .previousDifference:
            differencePreconditions(target: .previous)
        case .firstDifference:
            differencePreconditions(target: .first)
        case .currentDifference:
            differencePreconditions(target: .current)
        case .lastDifference:
            differencePreconditions(target: .last)
        case .nextConflict:
            conflictPreconditions(target: .next)
        case .previousConflict:
            conflictPreconditions(target: .previous)
        case .firstConflict:
            conflictPreconditions(target: .first)
        case .currentConflict:
            conflictPreconditions(target: .current)
        case .lastConflict:
            conflictPreconditions(target: .last)
        case .copyToRight, .copyToRightAndAdvance:
            directionalMergePreconditions(route: context.layoutContext.copyRoute(for: command))
        case .copyToLeft, .copyToLeftAndAdvance:
            directionalMergePreconditions(route: context.layoutContext.copyRoute(for: command))
        case .copyAllToRight:
            copyAllPreconditions(route: context.layoutContext.copyRoute(for: command))
        case .copyAllToLeft:
            copyAllPreconditions(route: context.layoutContext.copyRoute(for: command))
        case .autoMerge:
            automaticMergePreconditions(destination: context.layout.automaticMergeDestination)
        case .firstComparedFile:
            comparedFilePreconditions(target: .first)
        case .previousComparedFile:
            comparedFilePreconditions(target: .previous)
        case .nextComparedFile:
            comparedFilePreconditions(target: .next)
        case .lastComparedFile:
            comparedFilePreconditions(target: .last)
        case .leftReadOnly:
            readOnlyPreconditions(for: .left)
        case .middleReadOnly:
            readOnlyPreconditions(for: .middle)
        case .rightReadOnly:
            readOnlyPreconditions(for: .right)
        case .mergeMode, .options:
            []
        case .reloadFromDisk:
            [.sessionUnlocked, .comparisonNotLoading, .anyReloadablePane]
        case .changePane:
            [
                .sessionUnlocked,
                .comparisonNotLoading,
                .allPanesLoaded,
                .changePaneAvailable
            ]
        case .changePaneBack:
            [
                .sessionUnlocked,
                .comparisonNotLoading,
                .allPanesLoaded,
                .changePaneBackAvailable
            ]
        case .refresh:
            [.sessionUnlocked, .comparisonNotLoading, .allPanesLoaded]
        }
    }

    private static func savePreconditions(for side: Side) -> [ExecutionPrecondition] {
        [
            .sessionUnlocked,
            .comparisonNotLoading,
            .paneExists(side),
            .paneLoaded(side),
            .paneEditable(side),
            .paneDirty(side),
            .paneUnchangedExternally(side)
        ]
    }

    private static func saveAsPreconditions(for side: Side) -> [ExecutionPrecondition] {
        [
            .sessionUnlocked,
            .comparisonNotLoading,
            .paneExists(side),
            .paneLoaded(side)
        ]
    }

    private static func differencePreconditions(
        target: DifferenceTarget
    ) -> [ExecutionPrecondition] {
        [
            .sessionUnlocked,
            .currentComparison,
            .allPanesLoaded,
            .hasSignificantDifferences,
            .differenceTarget(target)
        ]
    }

    private static func conflictPreconditions(
        target: ConflictTarget
    ) -> [ExecutionPrecondition] {
        [
            .sessionUnlocked,
            .currentComparison,
            .allPanesLoaded,
            .conflictNavigationSupported,
            .hasConflicts,
            .conflictTarget(target)
        ]
    }

    private static func directionalMergePreconditions(
        route: CopyRoute?
    ) -> [ExecutionPrecondition] {
        var result: [ExecutionPrecondition] = [
            .sessionUnlocked,
            .currentComparison
        ]
        guard let route else {
            result.append(.allPanesLoaded)
            return result
        }
        result.append(contentsOf: [
            .paneLoaded(route.source),
            .paneLoaded(route.destination),
            .paneEditable(route.destination),
            .hasSignificantDifferences,
            .hasSelection
        ])
        return result
    }

    private static func copyAllPreconditions(route: CopyRoute?) -> [ExecutionPrecondition] {
        var result: [ExecutionPrecondition] = [
            .sessionUnlocked,
            .currentComparison
        ]
        guard let route else {
            result.append(.allPanesLoaded)
            return result
        }
        result.append(contentsOf: [
            .paneLoaded(route.source),
            .paneLoaded(route.destination),
            .paneEditable(route.destination),
            .hasSignificantDifferences
        ])
        return result
    }

    private static func automaticMergePreconditions(
        destination: Side?
    ) -> [ExecutionPrecondition] {
        var result: [ExecutionPrecondition] = [
            .sessionUnlocked,
            .currentComparison,
            .threePane,
            .automaticMergeSupported,
            .automaticMergeEligible,
            .allPanesLoaded
        ]
        if let destination { result.append(.paneEditable(destination)) }
        result.append(.allPanesClean)
        return result
    }

    private static func comparedFilePreconditions(
        target: ComparedFileTarget
    ) -> [ExecutionPrecondition] {
        [
            .sessionUnlocked,
            .comparisonNotLoading,
            .comparedFileNavigationSupported,
            .comparedFileTarget(target)
        ]
    }

    private static func readOnlyPreconditions(for side: Side) -> [ExecutionPrecondition] {
        [
            .sessionUnlocked,
            .comparisonNotLoading,
            .paneExists(side),
            .paneLoaded(side)
        ]
    }

    private static func mergeCommand(for command: Identifier) -> MergeCommandPolicy.Command? {
        switch command {
        case .saveLeft: .saveLeft
        case .saveMiddle: .saveMiddle
        case .saveRight: .saveRight
        case .autoMerge: .autoMerge
        case .newComparison, .openComparison, .openLeft, .openMiddle, .openRight, .save,
            .saveLeftAs, .saveMiddleAs, .saveRightAs, .undo, .redo,
            .selectLineDifference, .selectPreviousLineDifference,
            .nextDifference, .previousDifference,
            .nextConflict, .previousConflict, .firstConflict, .currentConflict, .lastConflict,
            .firstDifference, .currentDifference, .lastDifference,
            .copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance,
            .copyAllToRight, .copyAllToLeft,
            .firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile,
            .leftReadOnly, .middleReadOnly, .rightReadOnly, .mergeMode, .reloadFromDisk,
            .changePane, .changePaneBack, .options, .refresh:
            nil
        }
    }

    private static func mergeAvailability(
        _ command: Identifier,
        mergeCommand: MergeCommandPolicy.Command,
        context: Context
    ) -> Availability {
        if context.comparisonLifecycle == .refreshing {
            return .disabled(.comparisonRefreshing)
        }
        if command == .autoMerge,
            let reason = lifecycleDisabledReason(context.comparisonLifecycle)
        {
            return .disabled(reason)
        }
        if command == .autoMerge {
            guard context.isThreePane else { return .disabled(.requiresThreePane) }
            guard context.layout.supportsAutomaticMerge else {
                return .disabled(.unsupportedCommand(.autoMerge))
            }
        }

        let availability = MergeCommandPolicy.evaluate(context.mergeCommandState)[mergeCommand]
        if let reason = availability.disabledReason {
            if reason == .sideNotLoaded(.middle), !context.isThreePane {
                return .disabled(.requiresThreePane)
            }
            return .disabled(disabledReason(from: reason))
        }

        if let side = saveSide(for: command), context[side]?.hasExternalChange == true {
            return .disabled(.externalChange(side))
        }
        return .enabled
    }

    private static func saveSide(for command: Identifier) -> Side? {
        switch command {
        case .saveLeft: .left
        case .saveMiddle: .middle
        case .saveRight: .right
        case .newComparison, .openComparison, .openLeft, .openMiddle, .openRight, .save,
            .saveLeftAs, .saveMiddleAs, .saveRightAs, .undo, .redo,
            .selectLineDifference, .selectPreviousLineDifference,
            .nextDifference, .previousDifference,
            .nextConflict, .previousConflict, .firstConflict, .currentConflict, .lastConflict,
            .firstDifference, .currentDifference, .lastDifference,
            .copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance,
            .copyAllToRight, .copyAllToLeft, .autoMerge,
            .firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile,
            .leftReadOnly, .middleReadOnly, .rightReadOnly, .mergeMode, .reloadFromDisk,
            .changePane, .changePaneBack, .options, .refresh:
            nil
        }
    }

    private static func disabledReason(
        from reason: MergeCommandPolicy.DisabledReason
    ) -> DisabledReason {
        switch reason {
        case .sideNotLoaded(let side): .sideNotLoaded(side)
        case .destinationNotEditable(let side): .destinationReadOnly(side)
        case .sideNotEditable(let side): .sideReadOnly(side)
        case .noSelection: .noSelection
        case .noSignificantDifferences: .noSignificantDifferences
        case .noUnsavedChanges(let side): .noUnsavedChangesOnSide(side)
        case .unsavedChanges(let side): .unsavedChanges(side)
        case .comparisonLoading: .comparisonLoading
        case .comparisonStale: .comparisonStale
        case .comparisonFailed: .comparisonFailed
        case .autoMergeUnavailable: .automaticMergeUnavailable
        }
    }

    private static func failedReason(
        for precondition: ExecutionPrecondition,
        command: Identifier,
        context: Context
    ) -> DisabledReason? {
        switch precondition {
        case .sessionUnlocked:
            return context.isSessionLocked ? .sessionLocked : nil
        case .comparisonNotLoading:
            switch context.comparisonLifecycle {
            case .loading: return .comparisonLoading
            case .refreshing: return .comparisonRefreshing
            case .stale, .failed, .canceled, .currentSuccess: return nil
            }
        case .currentComparison:
            return lifecycleDisabledReason(context.comparisonLifecycle)
        case .anyPaneLoaded:
            return context.activePanes.contains { $0.state.isLoaded } ? nil : .noComparison
        case .allPanesLoaded:
            guard context.activePanes.contains(where: { $0.state.isLoaded }) else {
                return .noComparison
            }
            return context.activePanes.first(where: { !$0.state.isLoaded }).map {
                .sideNotLoaded($0.side)
            }
        case .paneExists(let side):
            return side == .middle && !context.isThreePane ? .requiresThreePane : nil
        case .paneLoaded(let side):
            guard side != .middle || context.isThreePane else { return .requiresThreePane }
            return context[side]?.isLoaded == true ? nil : .sideNotLoaded(side)
        case .paneEditable(let side):
            guard side != .middle || context.isThreePane else { return .requiresThreePane }
            guard let pane = context[side], pane.isLoaded else { return .sideNotLoaded(side) }
            return pane.isEditable ? nil : .destinationReadOnly(side)
        case .paneDirty(let side):
            guard side != .middle || context.isThreePane else { return .requiresThreePane }
            guard let pane = context[side], pane.isLoaded else { return .sideNotLoaded(side) }
            return pane.isDirty ? nil : .noUnsavedChangesOnSide(side)
        case .paneUnchangedExternally(let side):
            return context[side]?.hasExternalChange == true ? .externalChange(side) : nil
        case .anyDirtyPane:
            return context.activePanes.contains { $0.state.isDirty } ? nil : .noUnsavedChanges
        case .dirtyPanesEditable:
            for pane in context.activePanes where pane.state.isDirty {
                if !pane.state.isLoaded { return .sideNotLoaded(pane.side) }
                if !pane.state.isEditable { return .sideReadOnly(pane.side) }
            }
            return nil
        case .dirtyPanesUnchangedExternally:
            return context.activePanes.first(where: {
                $0.state.isDirty && $0.state.hasExternalChange
            }).map { DisabledReason.externalChange($0.side) }
        case .hasSignificantDifferences:
            return context.hasSignificantDifferences ? nil : .noSignificantDifferences
        case .hasSelection:
            return context.hasSelection ? nil : .noSelection
        case .undoAvailable:
            return context.canUndo ? nil : .noUndo
        case .redoAvailable:
            return context.canRedo ? nil : .noRedo
        case .differenceTarget(let target):
            return differenceDisabledReason(target, context: context)
        case .threePane:
            return context.isThreePane ? nil : .requiresThreePane
        case .conflictNavigationSupported:
            return context.conflictNavigation.isSupported ? nil : .unsupportedCommand(command)
        case .hasConflicts:
            return context.conflictNavigation.hasConflicts ? nil : .noConflicts
        case .conflictTarget(let target):
            return conflictDisabledReason(target, context: context)
        case .automaticMergeSupported:
            return context.layout.supportsAutomaticMerge
                ? nil : .unsupportedCommand(.autoMerge)
        case .automaticMergeEligible:
            return context.layout.isAutomaticMergeEligible ? nil : .automaticMergeUnavailable
        case .allPanesClean:
            return context.activePanes.first(where: { $0.state.isDirty }).map {
                DisabledReason.unsavedChanges($0.side)
            }
        case .comparedFileNavigationSupported:
            return context.comparedFileNavigation.isSupported
                ? nil : .unsupportedCommand(command)
        case .comparedFileTarget(let target):
            return comparedFileDisabledReason(target, context: context)
        case .anyReloadablePane:
            return context.activePanes.contains { $0.state.isReloadable }
                ? nil : .noReloadablePane
        case .changePaneAvailable:
            return context.canChangePane ? nil : .paneChangeUnavailable
        case .changePaneBackAvailable:
            return context.canChangePaneBack ? nil : .paneChangeBackUnavailable
        }
    }

    private static func lifecycleDisabledReason(
        _ lifecycle: ComparisonLifecycle
    ) -> DisabledReason? {
        switch lifecycle {
        case .loading: .comparisonLoading
        case .refreshing: .comparisonRefreshing
        case .stale: .comparisonStale
        case .failed: .comparisonFailed
        case .canceled: .comparisonCanceled
        case .currentSuccess: nil
        }
    }

    private static func differenceDisabledReason(
        _ target: DifferenceTarget,
        context: Context
    ) -> DisabledReason? {
        switch target {
        case .line:
            context.differenceNavigation.canSelectLineDifference ? nil : .noLineDifference
        case .previousLine:
            context.differenceNavigation.canSelectPreviousLineDifference
                ? nil : .noPreviousLineDifference
        case .next:
            context.differenceNavigation.canSelectNextDifference ? nil : .noNextDifference
        case .previous:
            context.differenceNavigation.canSelectPreviousDifference ? nil : .noPreviousDifference
        case .first:
            context.differenceNavigation.canSelectFirstDifference
                ? nil : .noFirstDifference
        case .current:
            context.differenceNavigation.canSelectCurrentDifference ? nil : .noCurrentDifference
        case .last:
            context.differenceNavigation.canSelectLastDifference
                ? nil : .noLastDifference
        }
    }

    private static func conflictDisabledReason(
        _ target: ConflictTarget,
        context: Context
    ) -> DisabledReason? {
        switch target {
        case .first:
            context.conflictNavigation.canSelectFirstConflict ? nil : .noFirstConflict
        case .previous:
            context.conflictNavigation.canSelectPreviousConflict ? nil : .noPreviousConflict
        case .current:
            context.conflictNavigation.canSelectCurrentConflict ? nil : .noCurrentConflict
        case .next:
            context.conflictNavigation.canSelectNextConflict ? nil : .noNextConflict
        case .last:
            context.conflictNavigation.canSelectLastConflict ? nil : .noLastConflict
        }
    }

    private static func comparedFileDisabledReason(
        _ target: ComparedFileTarget,
        context: Context
    ) -> DisabledReason? {
        switch target {
        case .first:
            context.comparedFileNavigation.canSelectFirst ? nil : .noFirstComparedFile
        case .previous:
            context.comparedFileNavigation.canSelectPrevious ? nil : .noPreviousComparedFile
        case .next:
            context.comparedFileNavigation.canSelectNext ? nil : .noNextComparedFile
        case .last:
            context.comparedFileNavigation.canSelectLast ? nil : .noLastComparedFile
        }
    }

    private static func checkedState(
        for command: Identifier,
        in context: Context
    ) -> CheckedState {
        switch command {
        case .leftReadOnly:
            context.left.isReadOnly ? .on : .off
        case .middleReadOnly:
            context.layout.middle?.isReadOnly == true ? .on : .off
        case .rightReadOnly:
            context.right.isReadOnly ? .on : .off
        case .mergeMode:
            context.isMergeMode ? .on : .off
        case .newComparison, .openComparison, .openLeft, .openMiddle, .openRight, .save,
            .saveLeft, .saveMiddle, .saveRight,
            .saveLeftAs, .saveMiddleAs, .saveRightAs,
            .undo, .redo, .selectLineDifference, .selectPreviousLineDifference,
            .nextDifference, .previousDifference,
            .nextConflict, .previousConflict, .firstConflict, .currentConflict, .lastConflict,
            .firstDifference, .currentDifference, .lastDifference,
            .copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance,
            .copyAllToRight, .copyAllToLeft, .autoMerge,
            .firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile,
            .reloadFromDisk, .changePane, .changePaneBack, .options, .refresh:
            .notApplicable
        }
    }

    private static func titleVariant(
        for command: Identifier,
        in context: Context
    ) -> TitleVariant {
        switch command {
        case .save:
            let dirtyPanes = context.activePanes.filter { $0.state.isDirty }
            if dirtyPanes.count == 1, dirtyPanes[0].state.isUntitled {
                return .saveAs(dirtyPanes[0].side)
            }
            return .standard
        case .saveLeft:
            return context.left.isUntitled ? .saveAs(.left) : .standard
        case .saveMiddle:
            return context.layout.middle?.isUntitled == true ? .saveAs(.middle) : .standard
        case .saveRight:
            return context.right.isUntitled ? .saveAs(.right) : .standard
        case .saveLeftAs:
            return .saveAs(.left)
        case .saveMiddleAs:
            return .saveAs(.middle)
        case .saveRightAs:
            return .saveAs(.right)
        case .leftReadOnly:
            return context.left.isReadOnly ? .makeEditable(.left) : .makeReadOnly(.left)
        case .middleReadOnly:
            return context.layout.middle?.isReadOnly == true
                ? .makeEditable(.middle) : .makeReadOnly(.middle)
        case .rightReadOnly:
            return context.right.isReadOnly ? .makeEditable(.right) : .makeReadOnly(.right)
        case .reloadFromDisk:
            return context.activePanes.contains { $0.state.isReloadable && $0.state.isDirty }
                ? .reloadWithUnsavedChanges : .standard
        case .copyToRight, .copyToRightAndAdvance:
            return context.layoutContext.copyRoute(for: command).map {
                .copy(to: $0.destinationPosition)
            } ?? .standard
        case .copyToLeft, .copyToLeftAndAdvance:
            return context.layoutContext.copyRoute(for: command).map {
                .copy(to: $0.destinationPosition)
            } ?? .standard
        case .copyAllToRight:
            return context.layoutContext.copyRoute(for: command).map {
                .copyAll(to: $0.destinationPosition)
            } ?? .standard
        case .copyAllToLeft:
            return context.layoutContext.copyRoute(for: command).map {
                .copyAll(to: $0.destinationPosition)
            } ?? .standard
        case .newComparison, .openComparison, .openLeft, .openMiddle, .openRight, .undo, .redo,
            .selectLineDifference, .selectPreviousLineDifference,
            .nextDifference, .previousDifference,
            .nextConflict, .previousConflict, .firstConflict, .currentConflict, .lastConflict,
            .firstDifference, .currentDifference, .lastDifference,
            .autoMerge,
            .firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile,
            .mergeMode, .changePane, .changePaneBack, .options, .refresh:
            return .standard
        }
    }
}
