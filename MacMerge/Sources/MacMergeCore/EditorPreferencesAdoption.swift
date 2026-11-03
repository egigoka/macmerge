import Foundation

/// UI-independent adoption planning for General, Compare/Merge, and Syntax editor settings.
///
/// Planning authority stays in `EditorPreferencesWorkflow`. This namespace only projects a
/// planned successor `State` plus its `ResolvedSchemes` onto editor-consumed target snapshots,
/// and forwards exact compare-and-swap, canonical persistence, lease, stale, limit,
/// cancellation, and receipt semantics to the workflow. It performs no native page rendering,
/// editor mutation, persistence I/O, or UI work; executors own snapshots and leases.
public enum EditorPreferencesAdoption: Sendable {
    public typealias Core = EditorPreferencesWorkflow
    public typealias State = Core.State
    public typealias StateCAS = Core.StateCAS
    public typealias Limits = Core.Limits
    public typealias Intent = Core.Intent
    public typealias Page = Core.Page
    public typealias ResolvedSchemes = Core.ResolvedSchemes
    public typealias ColorSchemeCatalog = Core.ColorSchemeCatalog
    public typealias PlanningReceipt = Core.PlanningReceipt
    public typealias PersistenceReceipt = Core.PersistenceReceipt
    public typealias PersistenceEffect = Core.PersistenceEffect
    public typealias ApplicationEffect = Core.ApplicationEffect
    public typealias RequiredEffect = Core.RequiredEffect
    public typealias ExecutorContract = Core.ExecutorContract
    public typealias ExecutorLease = Core.ExecutorLease
    public typealias ExecutionOutcome = Core.ExecutionOutcome
    public typealias ExecutionReceipt = Core.ExecutionReceipt
    public typealias ExecutionNonCommitReceipt = Core.ExecutionNonCommitReceipt
    public typealias ExecutionUncertaintyReceipt = Core.ExecutionUncertaintyReceipt
    public typealias ExecutionFailureReason = Core.ExecutionFailureReason

    /// General-page editor targets: display flags, pane view policy, and tab editing options.
    public struct GeneralTargets: Equatable, Sendable {
        public let display: EditorDisplayPreferences
        public let view: EditorViewPolicy
        public let editing: Core.EditingPreferences

        public init(
            display: EditorDisplayPreferences,
            view: EditorViewPolicy,
            editing: Core.EditingPreferences
        ) {
            self.display = display
            self.view = view
            self.editing = editing
        }
    }

    /// Compare/Merge-page editor targets: rescan, copy/line granularity, word breaks, merge side.
    public struct CompareMergeTargets: Equatable, Sendable {
        public let preferences: Core.CompareAndMergePreferences

        public init(preferences: Core.CompareAndMergePreferences) {
            self.preferences = preferences
        }
    }

    /// Syntax-page editor targets: highlighting flag, requested selection, resolved syntax
    /// scheme (nil when highlighting is disabled), and resolved color scheme.
    ///
    /// Color fallback is deterministic and owned by the workflow: the selected identifier,
    /// then `.standard`, then the first catalog scheme. `didFallBackColorScheme` reports when
    /// the resolved scheme identifier differs from the requested selection.
    public struct SyntaxTargets: Equatable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let isHighlightingEnabled: Bool
        public let selection: SyntaxSchemeSelection
        public let syntax: SyntaxSchemeResolution?
        public let color: EditorColorScheme
        public let didFallBackColorScheme: Bool

        public init(
            selection: SyntaxSchemeSelection,
            isHighlightingEnabled: Bool,
            resolved: ResolvedSchemes,
            requestedColor: Core.ColorSchemeIdentifier
        ) {
            self.isHighlightingEnabled = isHighlightingEnabled
            self.selection = selection
            syntax = resolved.syntax
            color = resolved.color
            didFallBackColorScheme = resolved.color.identifier != requestedColor.rawValue
        }

        public var description: String {
            "EditorPreferencesAdoption.SyntaxTargets(enabled: \(isHighlightingEnabled), schemes: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "isHighlightingEnabled": isHighlightingEnabled,
                    "syntax": "<redacted>",
                    "color": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Editor-consumed projection of one planned successor state. No page or editor is claimed.
    public struct EditorTargets: Equatable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let general: GeneralTargets
        public let compareAndMerge: CompareMergeTargets
        public let syntax: SyntaxTargets

        public init(state: State, resolvedSchemes: ResolvedSchemes) {
            general = GeneralTargets(
                display: state.display,
                view: state.view,
                editing: state.editing
            )
            compareAndMerge = CompareMergeTargets(preferences: state.compareAndMerge)
            syntax = SyntaxTargets(
                selection: state.syntax.selection,
                isHighlightingEnabled: state.syntax.isHighlightingEnabled,
                resolved: resolvedSchemes,
                requestedColor: state.colorScheme.selectedIdentifier
            )
        }

        public var description: String {
            "EditorPreferencesAdoption.EditorTargets(<redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["targets": "<redacted>"], displayStyle: .struct)
        }
    }

    /// A workflow plan bound to its derived editor targets. The workflow plan remains the
    /// compare-and-swap, persistence, lease, and receipt authority.
    public struct AdoptedPlan: Equatable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let workflowPlan: Core.Plan
        public let targets: EditorTargets

        fileprivate init(workflowPlan: Core.Plan) {
            self.workflowPlan = workflowPlan
            targets = EditorTargets(
                state: workflowPlan.successor,
                resolvedSchemes: workflowPlan.resolvedSchemes
            )
        }

        public var expectedStateCAS: StateCAS { workflowPlan.expectedStateCAS }
        public var successor: State { workflowPlan.successor }
        public var resolvedSchemes: ResolvedSchemes { workflowPlan.resolvedSchemes }
        public var persistence: PersistenceEffect { workflowPlan.persistence }
        public var application: ApplicationEffect { workflowPlan.application }
        public var receipt: PlanningReceipt { workflowPlan.receipt }
        public var requiredEffects: [RequiredEffect] { workflowPlan.requiredEffects }
        public var executorContract: ExecutorContract { workflowPlan.executorContract }
        public var changedPages: [Page] { receipt.changedPages }
        public var didFallBackColorScheme: Bool { targets.syntax.didFallBackColorScheme }

        public var description: String {
            "EditorPreferencesAdoption.AdoptedPlan(expected: \(receipt.expectedRevision), successor: \(receipt.successorRevision), pages: \(changedPages.map(\.rawValue)), payload: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["receipt": receipt, "payload": "<redacted>"],
                displayStyle: .struct
            )
        }

        /// Exact CAS plus pinned-catalog validation. Throws stale, catalog, or cancelled errors.
        public func validateCurrentState(
            _ current: State,
            syntaxCatalog: SyntaxSchemeCatalog,
            colorCatalog: ColorSchemeCatalog,
            cancellationCheck: @escaping @Sendable () throws -> Void = Core.checkTaskCancellation
        ) throws {
            try workflowPlan.validateCurrentState(
                current,
                syntaxCatalog: syntaxCatalog,
                colorCatalog: colorCatalog,
                cancellationCheck: cancellationCheck
            )
        }

        /// Executes through one opaque exclusive lease in one synchronous executor turn.
        /// The lease covers exact CAS, canonical persistence, state replacement, editor
        /// application, and any reconciliation before a definite outcome.
        public func execute<Executor: Core.PlanExecutor>(
            on executor: isolated Executor,
            syntaxCatalog: SyntaxSchemeCatalog,
            colorCatalog: ColorSchemeCatalog
        ) throws -> ExecutionOutcome {
            try workflowPlan.execute(
                on: executor,
                syntaxCatalog: syntaxCatalog,
                colorCatalog: colorCatalog
            )
        }
    }

    /// Pure projection of a successor state onto editor targets. No validation side effects
    /// beyond what the workflow plan already performed.
    public static func editorTargets(
        state: State,
        resolvedSchemes: ResolvedSchemes
    ) -> EditorTargets {
        EditorTargets(state: state, resolvedSchemes: resolvedSchemes)
    }

    /// Plans one intent against the caller's current state and catalogs, then projects the
    /// successor onto editor targets. Exact state/catalog CAS, limits, and cancellation flow
    /// through the workflow; throws `noChanges`, stale-content, catalog, limit, or cancelled
    /// errors without side effects.
    public static func plan(
        intent: Intent,
        current: State,
        syntaxCatalog: SyntaxSchemeCatalog,
        colorCatalog: ColorSchemeCatalog,
        cancellationCheck: @escaping @Sendable () throws -> Void = Core.checkTaskCancellation
    ) throws -> AdoptedPlan {
        let workflowPlan = try Core.plan(
            intent: intent,
            current: current,
            syntaxCatalog: syntaxCatalog,
            colorCatalog: colorCatalog,
            cancellationCheck: cancellationCheck
        )
        return AdoptedPlan(workflowPlan: workflowPlan)
    }

    /// Canonical, compact schema-1 bytes for one complete typed snapshot.
    public static func encode(
        _ state: State,
        cancellationCheck: @escaping @Sendable () throws -> Void = Core.checkTaskCancellation
    ) throws -> Data {
        try Core.encode(state, cancellationCheck: cancellationCheck)
    }

    /// Strictly accepts canonical output from `encode(_:cancellationCheck:)` under caller limits.
    public static func decode(
        from data: Data,
        limits: Limits = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = Core.checkTaskCancellation
    ) throws -> State {
        try Core.decode(from: data, limits: limits, cancellationCheck: cancellationCheck)
    }

    /// Missing persistence uses defaults. Present invalid persistence fails closed.
    public static func restore(
        from data: Data?,
        defaultLineage: UInt64 = 0,
        limits: Limits = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = Core.checkTaskCancellation
    ) throws -> State {
        try Core.restore(
            from: data,
            defaultLineage: defaultLineage,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }
}
