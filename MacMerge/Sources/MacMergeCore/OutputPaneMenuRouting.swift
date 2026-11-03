import Foundation

/// UI-independent routing from output-pane menu/pasteboard commands to ``OutputPaneWorkflow``.
///
/// Planning only: resolves enablement and checked pasteboard/state intents against an
/// exact snapshot CAS and returns values the owner executes. This file claims no pane,
/// menu, dialog, view, pasteboard, or storage behavior; visibility rendering, menu
/// placement, clipboard writes, and preference storage remain with the app executor,
/// which must honor ``OutputPaneWorkflow/ExecutorContract``.
public enum OutputPaneMenuRouting: Sendable {
    public typealias Snapshot = OutputPaneWorkflow.Snapshot
    public typealias SnapshotReference = OutputPaneWorkflow.SnapshotReference
    public typealias Intent = OutputPaneWorkflow.Intent
    public typealias Command = OutputPaneWorkflow.Command
    public typealias DisabledReason = OutputPaneWorkflow.DisabledReason
    public typealias CheckedState = OutputPaneWorkflow.CheckedState
    public typealias RequiredEffect = OutputPaneWorkflow.RequiredEffect
    public typealias ExecutorContract = OutputPaneWorkflow.ExecutorContract
    public typealias WorkflowLimits = OutputPaneWorkflow.Limits

    /// Bounds for the menu pass. Per-intent work stays bounded by the snapshot's
    /// workflow limits; this guards only the number of routed menu items.
    public struct Limits: Equatable, Sendable {
        public static let `default` = Limits()

        public let maximumMenuCommands: Int

        public init(maximumMenuCommands: Int = 16) {
            self.maximumMenuCommands = maximumMenuCommands
        }

        public func validate() throws {
            guard (1...64).contains(maximumMenuCommands) else {
                throw OutputPaneMenuRoutingError.invalidLimits
            }
        }
    }

    /// Menu/AX-ready enablement derived from one snapshot without side effects.
    public struct MenuItemState: Equatable, Sendable {
        public let command: Command
        public let expectedSnapshot: SnapshotReference
        public let isEnabled: Bool
        public let disabledReason: DisabledReason?
        public let checkedState: CheckedState
        public let plannedWorkUnits: UInt64
        public let accessibilityLabel: String
        public let accessibilityHint: String

        public var canExecute: Bool { isEnabled }
        public var isChecked: Bool { checkedState == .on }

        fileprivate init(state: OutputPaneWorkflow.CommandState) {
            command = state.command
            expectedSnapshot = state.expectedSnapshot
            isEnabled = state.isEnabled
            disabledReason = state.disabledReason
            checkedState = state.checkedState
            plannedWorkUnits = state.plannedWorkUnits
            accessibilityLabel = OutputPaneMenuRouting.accessibilityLabel(for: state.command)
            accessibilityHint = OutputPaneMenuRouting.accessibilityHint(
                for: state.command,
                disabledReason: state.disabledReason
            )
        }
    }

    /// Checked state/pasteboard intent. The executor commits the exact successor
    /// first while holding the CAS lease, then performs the remaining required
    /// effects in stable order exactly once.
    public struct RoutedPlan: Equatable, Sendable {
        public let plan: OutputPaneWorkflow.Plan

        fileprivate init(plan: OutputPaneWorkflow.Plan) {
            self.plan = plan
        }

        public var command: Command { plan.receipt.command }
        public var expectedSnapshot: SnapshotReference { plan.expectedSnapshot }
        public var successorSnapshot: SnapshotReference? { plan.receipt.successorSnapshot }
        public var requiredEffects: [RequiredEffect] { plan.requiredEffects }
        public var executorContract: ExecutorContract { plan.executorContract }

        /// Exact clipboard text for copy plans; nil for state-only plans.
        public var clipboardText: String? {
            switch plan.operation {
            case .replaceState:
                return nil
            case .replaceStateAndClipboard(_, let payload):
                return payload.text
            }
        }

        public var copySummary: OutputPaneWorkflow.CopySummary? {
            switch plan.operation {
            case .replaceState:
                return nil
            case .replaceStateAndClipboard(_, let payload):
                return payload.summary
            }
        }

        /// Rejects a forged or concurrently advanced snapshot before any effect.
        public func validateCurrentSnapshot(_ snapshot: Snapshot) throws {
            do {
                try plan.validateCurrentSnapshot(snapshot)
            } catch is CancellationError {
                throw OutputPaneMenuRoutingError.cancelled
            } catch let error as OutputPaneWorkflow.WorkflowError where error == .cancelled {
                throw OutputPaneMenuRoutingError.cancelled
            } catch let error as OutputPaneWorkflow.WorkflowError {
                throw OutputPaneMenuRoutingError.workflow(error)
            }
        }
    }

    /// Resolves enablement for one concrete intent without performing side effects.
    public static func commandState(
        for intent: Intent,
        in snapshot: Snapshot
    ) throws -> MenuItemState {
        do {
            try Task<Never, Never>.checkCancellation()
            let state = try OutputPaneWorkflow.commandState(for: intent, in: snapshot)
            try Task<Never, Never>.checkCancellation()
            return MenuItemState(state: state)
        } catch is CancellationError {
            throw OutputPaneMenuRoutingError.cancelled
        } catch let error as OutputPaneWorkflow.WorkflowError where error == .cancelled {
            throw OutputPaneMenuRoutingError.cancelled
        } catch let error as OutputPaneWorkflow.WorkflowError {
            throw OutputPaneMenuRoutingError.workflow(error)
        }
    }

    /// Stable order for direct pane/menu controls: visibility, copy, select all, clear all.
    public static func menuStates(
        in snapshot: Snapshot,
        limits: Limits = .default
    ) throws -> [MenuItemState] {
        do {
            try Task<Never, Never>.checkCancellation()
            try limits.validate()
            let states = try OutputPaneWorkflow.primaryCommandStates(in: snapshot)
            guard states.count <= limits.maximumMenuCommands else {
                throw OutputPaneMenuRoutingError.invalidLimits
            }
            try Task<Never, Never>.checkCancellation()
            return states.map(MenuItemState.init(state:))
        } catch is CancellationError {
            throw OutputPaneMenuRoutingError.cancelled
        } catch let error as OutputPaneWorkflow.WorkflowError where error == .cancelled {
            throw OutputPaneMenuRoutingError.cancelled
        } catch let error as OutputPaneWorkflow.WorkflowError {
            throw OutputPaneMenuRoutingError.workflow(error)
        } catch let error as OutputPaneMenuRoutingError {
            throw error
        }
    }

    /// Plans a checked intent; the executor performs all required effects.
    /// Disabled intents produce a typed workflow error and no plan.
    public static func plan(
        _ intent: Intent,
        in snapshot: Snapshot
    ) throws -> RoutedPlan {
        do {
            try Task<Never, Never>.checkCancellation()
            let planned = try OutputPaneWorkflow.plan(intent, in: snapshot)
            try Task<Never, Never>.checkCancellation()
            if let summary = RoutedPlan(plan: planned).copySummary {
                guard summary.utf8ByteCount == RoutedPlan(plan: planned).clipboardText?.utf8.count else {
                    throw OutputPaneMenuRoutingError.invalidCopyEvidence
                }
            }
            return RoutedPlan(plan: planned)
        } catch is CancellationError {
            throw OutputPaneMenuRoutingError.cancelled
        } catch let error as OutputPaneWorkflow.WorkflowError where error == .cancelled {
            throw OutputPaneMenuRoutingError.cancelled
        } catch let error as OutputPaneWorkflow.WorkflowError {
            throw OutputPaneMenuRoutingError.workflow(error)
        } catch let error as OutputPaneMenuRoutingError {
            throw error
        }
    }

    private static func accessibilityLabel(for command: Command) -> String {
        switch command {
        case .toggleVisibility:
            "Toggle Output Pane"
        case .setVisibility:
            "Set Output Pane Visibility"
        case .setVisibilityPersistence:
            "Output Pane Visibility Persistence"
        case .selectMessage:
            "Select Output Message"
        case .clearSelection:
            "Clear Output Selection"
        case .copy:
            "Copy Output Messages"
        case .selectAll:
            "Select All Output Messages"
        case .clearAll:
            "Clear All Output Messages"
        case .append:
            "Append Output Message"
        case .setFilter:
            "Set Output Filter"
        case .setSensitiveCopyPolicy:
            "Output Sensitive Copy Policy"
        }
    }

    private static func accessibilityHint(
        for command: Command,
        disabledReason: DisabledReason?
    ) -> String {
        switch disabledReason {
        case nil:
            switch command {
            case .copy:
                "Copies the resolved output messages to the clipboard."
            case .selectAll:
                "Selects all visible output messages."
            case .clearAll:
                "Clears all retained output messages."
            case .toggleVisibility, .setVisibility:
                "Changes output pane visibility."
            default:
                "Applies the output pane command."
            }
        case .noMessages:
            "There are no output messages."
        case .noVisibleMessages:
            "No output messages match the current filter."
        case .noSelection:
            "Select at least one visible output message."
        case .allVisibleMessagesSelected:
            "All visible output messages are already selected."
        case .unknownMessage:
            "The requested output message is no longer retained."
        case .messageFiltered:
            "The requested output message is hidden by the current filter."
        case .noStateChange:
            "The output pane is already in the requested state."
        case .revisionExhausted:
            "The output log cannot advance further."
        case .securitySensitiveCopyDenied:
            "Copy is disabled while the scope contains security-sensitive messages."
        case .securitySensitiveCopyRequiresAuthorization:
            "Copying security-sensitive messages needs explicit approval."
        }
    }
}

public enum OutputPaneMenuRoutingError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimits
    case invalidCopyEvidence
    case workflow(OutputPaneWorkflow.WorkflowError)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Output-pane menu routing was cancelled."
        case .invalidLimits:
            "Output-pane menu routing limits are invalid."
        case .invalidCopyEvidence:
            "Output-pane copy evidence contradicts its payload."
        case .workflow(let error):
            error.localizedDescription
        }
    }
}
