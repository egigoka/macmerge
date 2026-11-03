import Foundation

/// Pane-bound command planner over ``ConflictComparisonPlan``.
///
/// Binds parsed-conflict navigation and resolution/apply intents to comparison-pane
/// roles (Base/Theirs/Mine). Planning only: it performs no pane rendering, document
/// mutation, filesystem access, or UI. Exact compare-and-swap, receipts, transform
/// limits, and capability/read-only policy are inherited from
/// ``ConflictComparisonWorkflow`` via delegation. Save/apply execution and native
/// panes remain missing; an executor must enforce
/// ``ConflictComparisonExecutorContract/required`` and call
/// `validateCurrentSnapshot` before recording a choice or beginning an apply CAS.
public enum ConflictPaneCommands: Sendable {
    public enum Pane: String, CaseIterable, Equatable, Hashable, Sendable {
        case base
        case theirs
        case mine

        public var role: ConflictComparisonRole {
            switch self {
            case .base: .base
            case .theirs: .theirs
            case .mine: .mine
            }
        }

        public var choice: ConflictComparisonResolutionChoice {
            switch self {
            case .base: .base
            case .theirs: .theirs
            case .mine: .mine
            }
        }

        public var requiredCapability: ConflictComparisonCapability {
            switch self {
            case .base: .chooseBase
            case .theirs: .chooseTheirs
            case .mine: .chooseMine
            }
        }
    }

    public enum Command: Equatable, Hashable, Sendable {
        case firstConflict
        case currentConflict
        case previousConflict
        case nextConflict
        case lastConflict
        case clearSelection
        case select(ConflictNavigationTarget.ID)
        case choose(Pane, ConflictNavigationTarget.ID)
        case apply(Pane, ConflictNavigationTarget.ID)
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case missingNavigateCapability
        case missingChooseCapability(Pane)
        case missingApplyCapability
        case readOnlyDocument
        case baseUnavailableInTwoWay
        case staleSelection
        case noTargetConflict
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

    public struct CommandStates: Equatable, Hashable, Sendable {
        public let first: Availability
        public let current: Availability
        public let previous: Availability
        public let next: Availability
        public let last: Availability
        public let chooseBase: Availability
        public let chooseTheirs: Availability
        public let chooseMine: Availability
        public let applyBase: Availability
        public let applyTheirs: Availability
        public let applyMine: Availability

        public init(
            first: Availability,
            current: Availability,
            previous: Availability,
            next: Availability,
            last: Availability,
            chooseBase: Availability,
            chooseTheirs: Availability,
            chooseMine: Availability,
            applyBase: Availability,
            applyTheirs: Availability,
            applyMine: Availability
        ) {
            self.first = first
            self.current = current
            self.previous = previous
            self.next = next
            self.last = last
            self.chooseBase = chooseBase
            self.chooseTheirs = chooseTheirs
            self.chooseMine = chooseMine
            self.applyBase = applyBase
            self.applyTheirs = applyTheirs
            self.applyMine = applyMine
        }

        public func availability(for pane: Pane, action: ConflictComparisonResolutionAction) -> Availability {
            switch action {
            case .choose:
                switch pane {
                case .base: chooseBase
                case .theirs: chooseTheirs
                case .mine: chooseMine
                }
            case .apply:
                switch pane {
                case .base: applyBase
                case .theirs: applyTheirs
                case .mine: applyMine
                }
            }
        }
    }

    public enum ResolvedPlan: Equatable, Hashable, Sendable {
        case navigation(ConflictComparisonNavigationPlan)
        case resolution(ConflictComparisonResolutionPlan)

        public var snapshotCAS: ConflictComparisonSnapshotCAS {
            switch self {
            case .navigation(let plan): plan.snapshotCAS
            case .resolution(let plan): plan.snapshotCAS
            }
        }

        public var executorContract: ConflictComparisonExecutorContract {
            .required
        }

        public var authorizesMutation: Bool {
            guard case .resolution(let plan) = self else { return false }
            return plan.authorizesMutation
        }
    }

    public static func states(
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) throws -> CommandStates {
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
        return CommandStates(
            first: navigationAvailability(.first, in: plan, selection: selection),
            current: navigationAvailability(.current, in: plan, selection: selection),
            previous: navigationAvailability(.previous, in: plan, selection: selection),
            next: navigationAvailability(.next, in: plan, selection: selection),
            last: navigationAvailability(.last, in: plan, selection: selection),
            chooseBase: chooseAvailability(
                .base, in: plan, selection: selection, targetID: selection.selectedConflictID
            ),
            chooseTheirs: chooseAvailability(
                .theirs, in: plan, selection: selection, targetID: selection.selectedConflictID
            ),
            chooseMine: chooseAvailability(
                .mine, in: plan, selection: selection, targetID: selection.selectedConflictID
            ),
            applyBase: applyAvailability(
                .base, in: plan, selection: selection, targetID: selection.selectedConflictID
            ),
            applyTheirs: applyAvailability(
                .theirs, in: plan, selection: selection, targetID: selection.selectedConflictID
            ),
            applyMine: applyAvailability(
                .mine, in: plan, selection: selection, targetID: selection.selectedConflictID
            )
        )
    }

    public static func availability(
        of command: Command,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) -> Availability {
        switch command {
        case .firstConflict:
            return navigationAvailability(.first, in: plan, selection: selection)
        case .currentConflict:
            return navigationAvailability(.current, in: plan, selection: selection)
        case .previousConflict:
            return navigationAvailability(.previous, in: plan, selection: selection)
        case .nextConflict:
            return navigationAvailability(.next, in: plan, selection: selection)
        case .lastConflict:
            return navigationAvailability(.last, in: plan, selection: selection)
        case .clearSelection:
            guard plan.capabilities.contains(.navigate) else {
                return .disabled(.missingNavigateCapability)
            }
            guard selection.snapshot == plan.snapshotCAS.reference else {
                return .disabled(.staleSelection)
            }
            return .enabled
        case .select(let id):
            return selectAvailability(id, in: plan, selection: selection)
        case .choose(let pane, let targetID):
            return chooseAvailability(pane, in: plan, selection: selection, targetID: targetID)
        case .apply(let pane, let targetID):
            return applyAvailability(pane, in: plan, selection: selection, targetID: targetID)
        }
    }

    /// Plans one pane-bound command against exact owner/snapshot state.
    ///
    /// Validates `snapshot` against the plan CAS (exact identity, generation, contents,
    /// transform limits) before delegating to the workflow, so stale or forged state
    /// fails before any navigation or resolution receipt is issued.
    public static func resolve(
        _ command: Command,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState,
        validating snapshot: ConflictComparisonParsedDocumentSnapshot
    ) throws -> ResolvedPlan {
        do {
            try Task.checkCancellation()
            try plan.validateCurrentSnapshot(snapshot)
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
        switch command {
        case .firstConflict:
            return try resolveNavigation(.first, in: plan, selection: selection)
        case .currentConflict:
            return try resolveNavigation(.current, in: plan, selection: selection)
        case .previousConflict:
            return try resolveNavigation(.previous, in: plan, selection: selection)
        case .nextConflict:
            return try resolveNavigation(.next, in: plan, selection: selection)
        case .lastConflict:
            return try resolveNavigation(.last, in: plan, selection: selection)
        case .clearSelection:
            return try resolveNavigationIntent(.clear, in: plan, selection: selection)
        case .select(let id):
            return try resolveNavigationIntent(.select(id), in: plan, selection: selection)
        case .choose(let pane, let targetID):
            return try resolveResolution(pane: pane, targetID: targetID, action: .choose, in: plan, selection: selection)
        case .apply(let pane, let targetID):
            return try resolveResolution(pane: pane, targetID: targetID, action: .apply, in: plan, selection: selection)
        }
    }

    private static func resolveNavigation(
        _ command: ConflictComparisonNavigationCommand,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) throws -> ResolvedPlan {
        try resolveNavigationIntent(.command(command), in: plan, selection: selection)
    }

    private static func resolveNavigationIntent(
        _ intent: ConflictComparisonSelectionIntent,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) throws -> ResolvedPlan {
        do {
            try Task.checkCancellation()
            let request = ConflictComparisonNavigationRequest(state: selection, intent: intent)
            return .navigation(try plan.navigationPlan(request))
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
    }

    private static func resolveResolution(
        pane: Pane,
        targetID: ConflictNavigationTarget.ID,
        action: ConflictComparisonResolutionAction,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) throws -> ResolvedPlan {
        do {
            try Task.checkCancellation()
            let intent = ConflictComparisonResolutionIntent(
                snapshot: selection.snapshot,
                targetID: targetID,
                choice: pane.choice,
                action: action
            )
            return .resolution(try plan.resolutionPlan(intent))
        } catch is CancellationError {
            throw ConflictComparisonWorkflowError.cancelled
        }
    }

    private static func navigationAvailability(
        _ command: ConflictComparisonNavigationCommand,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) -> Availability {
        guard plan.capabilities.contains(.navigate) else {
            return .disabled(.missingNavigateCapability)
        }
        guard selection.snapshot == plan.snapshotCAS.reference else {
            return .disabled(.staleSelection)
        }
        guard navigationTarget(command, in: plan, selection: selection) != nil else {
            return .disabled(.noTargetConflict)
        }
        return .enabled
    }

    private static func navigationTarget(
        _ command: ConflictComparisonNavigationCommand,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) -> ConflictNavigationTarget? {
        let origin = validatedSelection(selection, in: plan.navigation)
        switch command {
        case .first:
            return plan.navigation.first
        case .current:
            return plan.navigation.current(
                selectedConflict: origin,
                cursorRow: selection.cursorSourceLine
            )
        case .previous:
            return plan.navigation.previous(
                before: origin,
                cursorRow: selection.cursorSourceLine
            )
        case .next:
            return plan.navigation.next(
                after: origin,
                cursorRow: selection.cursorSourceLine
            )
        case .last:
            return plan.navigation.last
        }
    }

    private static func validatedSelection(
        _ selection: ConflictComparisonSelectionState,
        in navigation: ConflictNavigationIndex
    ) -> ConflictNavigationTarget? {
        guard let id = selection.selectedConflictID,
            id.generation == navigation.generation,
            let target = navigation.conflict(at: id.ordinal),
            target.id == id
        else {
            return nil
        }
        return target
    }

    private static func selectAvailability(
        _ id: ConflictNavigationTarget.ID,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) -> Availability {
        guard plan.capabilities.contains(.navigate) else {
            return .disabled(.missingNavigateCapability)
        }
        return validatedTargetAvailability(id, in: plan, selection: selection) ?? .enabled
    }

    private static func chooseAvailability(
        _ pane: Pane,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState,
        targetID: ConflictNavigationTarget.ID?
    ) -> Availability {
        if pane == .base, plan.mapping.topology != .diff3 {
            return .disabled(.baseUnavailableInTwoWay)
        }
        guard plan.capabilities.contains(pane.requiredCapability) else {
            return .disabled(.missingChooseCapability(pane))
        }
        guard let targetID else {
            return .disabled(.noTargetConflict)
        }
        return validatedTargetAvailability(targetID, in: plan, selection: selection) ?? .enabled
    }

    private static func applyAvailability(
        _ pane: Pane,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState,
        targetID: ConflictNavigationTarget.ID?
    ) -> Availability {
        if pane == .base, plan.mapping.topology != .diff3 {
            return .disabled(.baseUnavailableInTwoWay)
        }
        guard plan.capabilities.contains(pane.requiredCapability) else {
            return .disabled(.missingChooseCapability(pane))
        }
        guard plan.capabilities.contains(.applyResolution) else {
            return .disabled(.missingApplyCapability)
        }
        guard !plan.isReadOnly else {
            return .disabled(.readOnlyDocument)
        }
        guard let targetID else {
            return .disabled(.noTargetConflict)
        }
        return validatedTargetAvailability(targetID, in: plan, selection: selection) ?? .enabled
    }

    private static func validatedTargetAvailability(
        _ id: ConflictNavigationTarget.ID,
        in plan: ConflictComparisonPlan,
        selection: ConflictComparisonSelectionState
    ) -> Availability? {
        guard selection.snapshot == plan.snapshotCAS.reference else {
            return .disabled(.staleSelection)
        }
        guard id.generation == plan.navigation.generation else {
            return .disabled(.staleSelection)
        }
        guard let target = plan.navigation.conflict(at: id.ordinal), target.id == id else {
            return .disabled(.noTargetConflict)
        }
        return nil
    }
}
