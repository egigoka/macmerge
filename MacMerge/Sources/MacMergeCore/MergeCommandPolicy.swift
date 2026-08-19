public enum MergeCommandPolicy: Sendable {
    public enum ComparisonLifecycle: Equatable, Hashable, Sendable {
        case loading
        case stale
        case failed
        case currentSuccess
    }

    public enum Side: CaseIterable, Equatable, Hashable, Sendable {
        case left
        case middle
        case right
    }

    public struct SideState: Equatable, Hashable, Sendable {
        public let isLoaded: Bool
        public let isEditable: Bool
        public let isDirty: Bool

        public init(isLoaded: Bool, isEditable: Bool, isDirty: Bool) {
            self.isLoaded = isLoaded
            self.isEditable = isEditable
            self.isDirty = isDirty
        }
    }

    public struct State: Equatable, Hashable, Sendable {
        public enum Layout: Equatable, Hashable, Sendable {
            case twoWay
            case threeWay(
                middle: SideState,
                autoMergeDestination: Side,
                isAutoMergeEligible: Bool = false
            )
        }

        public let left: SideState
        public let right: SideState
        public let layout: Layout
        public let comparisonLifecycle: ComparisonLifecycle
        /// True when the current selection or cursor resolves to at least one mergeable difference.
        public let hasSelection: Bool
        /// Pairwise left/right differences. Automatic three-way merge does not depend on this.
        public let hasSignificantDifferences: Bool

        public init(
            left: SideState,
            right: SideState,
            layout: Layout = .twoWay,
            comparisonLifecycle: ComparisonLifecycle = .currentSuccess,
            hasSelection: Bool,
            hasSignificantDifferences: Bool
        ) {
            self.left = left
            self.right = right
            self.layout = layout
            self.comparisonLifecycle = comparisonLifecycle
            self.hasSelection = hasSelection
            self.hasSignificantDifferences = hasSignificantDifferences
        }

        public var middle: SideState? {
            guard case .threeWay(let middle, _, _) = layout else { return nil }
            return middle
        }

        public var autoMergeDestination: Side? {
            guard case .threeWay(_, let destination, _) = layout else { return nil }
            return destination
        }

        public var isAutoMergeEligible: Bool {
            guard case .threeWay(_, _, let isEligible) = layout else { return false }
            return isEligible
        }

        public var isThreeWay: Bool { middle != nil }
        public var isCurrentSuccess: Bool { comparisonLifecycle == .currentSuccess }

        public subscript(side: Side) -> SideState? {
            switch side {
            case .left:
                left
            case .middle:
                middle
            case .right:
                right
            }
        }
    }

    public enum Command: CaseIterable, Equatable, Hashable, Sendable {
        case leftToRight
        case rightToLeft
        case leftToRightAndAdvance
        case rightToLeftAndAdvance
        case copyAllToRight
        case copyAllToLeft
        case saveLeft
        case saveMiddle
        case saveRight
        case autoMerge
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case sideNotLoaded(Side)
        case destinationNotEditable(Side)
        case sideNotEditable(Side)
        case noSelection
        case noSignificantDifferences
        case noUnsavedChanges(Side)
        case unsavedChanges(Side)
        case comparisonLoading
        case comparisonStale
        case comparisonFailed
        case autoMergeUnavailable
    }

    public enum Availability: Equatable, Hashable, Sendable {
        case enabled
        case disabled(DisabledReason)

        public var isEnabled: Bool {
            self == .enabled
        }

        public var disabledReason: DisabledReason? {
            guard case .disabled(let reason) = self else { return nil }
            return reason
        }
    }

    public struct CommandStates: Equatable, Hashable, Sendable {
        public let leftToRight: Availability
        public let rightToLeft: Availability
        public let leftToRightAndAdvance: Availability
        public let rightToLeftAndAdvance: Availability
        public let copyAllToRight: Availability
        public let copyAllToLeft: Availability
        public let saveLeft: Availability
        public let saveMiddle: Availability
        public let saveRight: Availability
        public let autoMerge: Availability

        public init(
            leftToRight: Availability,
            rightToLeft: Availability,
            leftToRightAndAdvance: Availability,
            rightToLeftAndAdvance: Availability,
            copyAllToRight: Availability,
            copyAllToLeft: Availability,
            saveLeft: Availability,
            saveMiddle: Availability,
            saveRight: Availability,
            autoMerge: Availability
        ) {
            self.leftToRight = leftToRight
            self.rightToLeft = rightToLeft
            self.leftToRightAndAdvance = leftToRightAndAdvance
            self.rightToLeftAndAdvance = rightToLeftAndAdvance
            self.copyAllToRight = copyAllToRight
            self.copyAllToLeft = copyAllToLeft
            self.saveLeft = saveLeft
            self.saveMiddle = saveMiddle
            self.saveRight = saveRight
            self.autoMerge = autoMerge
        }

        public subscript(command: Command) -> Availability {
            switch command {
            case .leftToRight:
                leftToRight
            case .rightToLeft:
                rightToLeft
            case .leftToRightAndAdvance:
                leftToRightAndAdvance
            case .rightToLeftAndAdvance:
                rightToLeftAndAdvance
            case .copyAllToRight:
                copyAllToRight
            case .copyAllToLeft:
                copyAllToLeft
            case .saveLeft:
                saveLeft
            case .saveMiddle:
                saveMiddle
            case .saveRight:
                saveRight
            case .autoMerge:
                autoMerge
            }
        }
    }

    /// Returns the first failed predicate from each command's documented matrix order.
    public static func evaluate(_ state: State) -> CommandStates {
        let leftToRight = directionalAvailability(destination: .right, state: state)
        let rightToLeft = directionalAvailability(destination: .left, state: state)

        return CommandStates(
            leftToRight: leftToRight,
            rightToLeft: rightToLeft,
            leftToRightAndAdvance: leftToRight,
            rightToLeftAndAdvance: rightToLeft,
            copyAllToRight: copyAllAvailability(destination: .right, state: state),
            copyAllToLeft: copyAllAvailability(destination: .left, state: state),
            saveLeft: saveAvailability(side: .left, state: state),
            saveMiddle: saveAvailability(side: .middle, state: state),
            saveRight: saveAvailability(side: .right, state: state),
            autoMerge: autoMergeAvailability(state: state)
        )
    }

    /// Matrix order: current successful comparison, both sides loaded, destination editable,
    /// differences present, selection present.
    private static func directionalAvailability(destination: Side, state: State) -> Availability {
        if let reason = commonMergeDisabledReason(destination: destination, state: state) {
            return .disabled(reason)
        }
        guard state.hasSelection else { return .disabled(.noSelection) }
        return .enabled
    }

    /// Matrix order: current successful comparison, both sides loaded, destination editable,
    /// differences present.
    private static func copyAllAvailability(destination: Side, state: State) -> Availability {
        if let reason = commonMergeDisabledReason(destination: destination, state: state) {
            return .disabled(reason)
        }
        return .enabled
    }

    private static func commonMergeDisabledReason(
        destination: Side,
        state: State
    ) -> DisabledReason? {
        if let reason = comparisonDisabledReason(state.comparisonLifecycle) { return reason }
        guard state.left.isLoaded else { return .sideNotLoaded(.left) }
        guard state.right.isLoaded else { return .sideNotLoaded(.right) }
        guard state[destination]?.isEditable == true else {
            return .destinationNotEditable(destination)
        }
        guard state.hasSignificantDifferences else { return .noSignificantDifferences }
        return nil
    }

    private static func comparisonDisabledReason(
        _ lifecycle: ComparisonLifecycle
    ) -> DisabledReason? {
        switch lifecycle {
        case .loading:
            .comparisonLoading
        case .stale:
            .comparisonStale
        case .failed:
            .comparisonFailed
        case .currentSuccess:
            nil
        }
    }

    /// Matrix order: comparison not loading, side loaded, side editable, side dirty.
    private static func saveAvailability(side: Side, state: State) -> Availability {
        guard state.comparisonLifecycle != .loading else {
            return .disabled(.comparisonLoading)
        }
        guard let sideState = state[side] else { return .disabled(.sideNotLoaded(side)) }
        guard sideState.isLoaded else { return .disabled(.sideNotLoaded(side)) }
        guard sideState.isEditable else { return .disabled(.sideNotEditable(side)) }
        guard sideState.isDirty else { return .disabled(.noUnsavedChanges(side)) }
        return .enabled
    }

    /// Matrix order: current successful comparison, eligible three-way comparison, all panes
    /// loaded, destination editable, all panes clean.
    private static func autoMergeAvailability(state: State) -> Availability {
        if let reason = comparisonDisabledReason(state.comparisonLifecycle) {
            return .disabled(reason)
        }
        guard let destination = state.autoMergeDestination else {
            return .disabled(.autoMergeUnavailable)
        }
        guard state.isAutoMergeEligible else { return .disabled(.autoMergeUnavailable) }
        guard state.left.isLoaded else { return .disabled(.sideNotLoaded(.left)) }
        guard state.middle?.isLoaded == true else { return .disabled(.sideNotLoaded(.middle)) }
        guard state.right.isLoaded else { return .disabled(.sideNotLoaded(.right)) }
        guard state[destination]?.isEditable == true else {
            return .disabled(.destinationNotEditable(destination))
        }
        guard !state.left.isDirty else { return .disabled(.unsavedChanges(.left)) }
        guard state.middle?.isDirty == false else { return .disabled(.unsavedChanges(.middle)) }
        guard !state.right.isDirty else { return .disabled(.unsavedChanges(.right)) }
        return .enabled
    }
}
