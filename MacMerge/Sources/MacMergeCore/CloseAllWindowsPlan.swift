import Foundation

/// Bounded, UI-independent Close All (Command-Option-W) planning plus the
/// `FileLifecycleMenuCapture.verify()` app-wiring hook.
///
/// This model owns no AppKit objects and performs no closing itself. Callers supply the
/// exact open-window set, dirty set, per-window veto snapshot, and session generation;
/// the executor closes one window per ordered step, honors veto/dirty handling, then runs
/// the verify hook. Step order reuses `ComparisonWindowCommandState` close-all semantics
/// (reverse supplied window-cycle order). Veto and dirty types are reused from
/// `ComparisonTabLifecycle`; shortcut spelling reuses `FileLifecycleShortcuts.Policy`.
public enum CloseAllWindowsPlan: Sendable {
    public typealias WindowID = ComparisonTabLifecycle.WindowID
    public typealias CloseVeto = ComparisonTabLifecycle.CloseVeto
    public typealias Policy = FileLifecycleShortcuts.Policy
    public typealias CancellationCheck = @Sendable () throws -> Void

    /// Lane bound: reuses `ComparisonTabLifecycle.Limits.default.maximumWindowCount`.
    public static var maximumWindowCount: Int {
        ComparisonTabLifecycle.Limits.default.maximumWindowCount
    }
    public static let cancellationCheckInterval = 16

    /// Command-Option-W, the standard AppKit Close All chord over File > Close (Command-W).
    public static var closeAllChord: Policy.Chord {
        do {
            return try Policy.Chord(.character("w"), modifiers: [.command, .option])
        } catch {
            preconditionFailure("CloseAllWindowsPlan close-all chord is invalid: \(error)")
        }
    }

    /// Menu title the app wiring must bind the chord to (File menu, alongside Close).
    public static let menuTitle = "Close All"

    /// Spelling used in help text and tooltips.
    public static let helpText = "Command-Option-W"

    /// Single verify hook the app executor must run after wiring Close All.
    public struct VerifyCallPlan: Equatable, Hashable, Sendable {
        public enum Hook: String, CaseIterable, Equatable, Hashable, Sendable {
            /// App-target `FileLifecycleMenuCapture.verify()`, which checks
            /// `FileLifecycleShortcuts.verifyMenu(capture(...))`.
            case fileLifecycleMenuCaptureVerify
        }

        public let hook: Hook
        /// Executor must run the hook after close-all wiring lands, not before.
        public let runAfterCloseWiring: Bool
        /// The hook passes only when the menu findings are empty.
        public let passesWhenNoFindings: Bool

        public static let required = VerifyCallPlan(
            hook: .fileLifecycleMenuCaptureVerify,
            runAfterCloseWiring: true,
            passesWhenNoFindings: true
        )

        public init(hook: Hook, runAfterCloseWiring: Bool, passesWhenNoFindings: Bool) {
            self.hook = hook
            self.runAfterCloseWiring = runAfterCloseWiring
            self.passesWhenNoFindings = passesWhenNoFindings
        }
    }

    /// Ordered per-window close step. Veto snapshots are advisory; the executor still
    /// requests current owner authorization before mutating owner state. Dirty snapshots
    /// are also stale-safe only via `liveRequiresConfirmation(liveDirtyWindowIDs:)` per step.
    public struct CloseStep: Equatable, Hashable, Sendable {
        /// Zero-based position in deterministic close order.
        public let ordinal: Int
        public let windowID: WindowID
        public let requiresConfirmation: Bool
        public let veto: CloseVeto

        public var isVetoed: Bool { veto.isVetoed }

        public init(ordinal: Int, windowID: WindowID, requiresConfirmation: Bool, veto: CloseVeto) {
            self.ordinal = ordinal
            self.windowID = windowID
            self.requiresConfirmation = requiresConfirmation
            self.veto = veto
        }

        /// Fail-closed live dirty recheck. Executor must call per step before closing.
        public func liveRequiresConfirmation(liveDirtyWindowIDs: Set<WindowID>) -> Bool {
            requiresConfirmation || liveDirtyWindowIDs.contains(windowID)
        }
    }

    /// Planner inputs. `vetoes` omits clean closable windows (implicit `.none`).
    public struct Request: Equatable, Hashable, Sendable {
        public let openWindowIDs: [WindowID]
        public let dirtyWindowIDs: Set<WindowID>
        public let vetoes: [WindowID: CloseVeto]
        public let generation: UInt64

        public init(
            openWindowIDs: [WindowID],
            dirtyWindowIDs: Set<WindowID> = [],
            vetoes: [WindowID: CloseVeto] = [:],
            generation: UInt64
        ) {
            self.openWindowIDs = openWindowIDs
            self.dirtyWindowIDs = dirtyWindowIDs
            self.vetoes = vetoes
            self.generation = generation
        }
    }

    /// Planner output: reverse cycle order plus veto/dirty snapshot and verify hook.
    public struct CloseAllPlan: Equatable, Hashable, Sendable {
        public let generation: UInt64
        /// Reverse supplied window-cycle order. Executor closes in this order and
        /// stops at the first owner refusal; vetoed steps are marked, not skipped, so the
        /// executor can preflight every target before any mutation. Executor must recheck
        /// live dirty per step via `liveRequiresConfirmation(for:liveDirtyWindowIDs:)`.
        public let steps: [CloseStep]
        public let dirtyCount: Int
        public let vetoedCount: Int
        /// Sorted ascending for stable diagnostics.
        public let vetoedWindowIDs: [WindowID]
        public let verifyAfterCloseWiring: VerifyCallPlan
        public let workPerformed: Int

        public var isEmpty: Bool { steps.isEmpty }
        public var requiresConfirmationCount: Int { dirtyCount }

        fileprivate init(
            generation: UInt64,
            steps: [CloseStep],
            dirtyCount: Int,
            vetoedCount: Int,
            vetoedWindowIDs: [WindowID],
            verifyAfterCloseWiring: VerifyCallPlan,
            workPerformed: Int
        ) {
            self.generation = generation
            self.steps = steps
            self.dirtyCount = dirtyCount
            self.vetoedCount = vetoedCount
            self.vetoedWindowIDs = vetoedWindowIDs
            self.verifyAfterCloseWiring = verifyAfterCloseWiring
            self.workPerformed = workPerformed
        }

        /// Executor-side check: passes only with zero findings and one bound close-all item.
        public func verifyHookPassed(
            _ findings: [FileLifecycleShortcuts.Finding],
            observedMenuItems: [FileLifecycleShortcuts.ObservedMenuItem]
        ) -> Bool {
            guard findings.isEmpty else { return false }
            return observedMenuItems.contains {
                $0.title == CloseAllWindowsPlan.menuTitle && $0.chord == CloseAllWindowsPlan.closeAllChord
            }
        }

        /// Fail-closed live dirty recheck for one step. Executor must call per step.
        public func liveRequiresConfirmation(
            for step: CloseStep,
            liveDirtyWindowIDs: Set<WindowID>
        ) -> Bool {
            step.liveRequiresConfirmation(liveDirtyWindowIDs: liveDirtyWindowIDs)
        }
    }

    /// Plans every close step in deterministic order. Pure value transform; no UI or mutation.
    public static func plan(
        _ request: Request,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> CloseAllPlan {
        try checked(cancellationCheck)
        guard request.openWindowIDs.count <= maximumWindowCount else {
            throw CloseAllWindowsPlanError.tooManyWindows(maximum: maximumWindowCount)
        }
        guard request.generation < UInt64.max else {
            throw CloseAllWindowsPlanError.generationExhausted
        }
        var seen: Set<WindowID> = []
        seen.reserveCapacity(request.openWindowIDs.count)
        var orderedIDs: [WindowID] = []
        orderedIDs.reserveCapacity(request.openWindowIDs.count)
        for windowID in request.openWindowIDs {
            if !seen.insert(windowID).inserted {
                throw CloseAllWindowsPlanError.duplicateWindowID(windowID)
            }
            orderedIDs.append(windowID)
        }
        for windowID in request.dirtyWindowIDs {
            guard seen.contains(windowID) else {
                throw CloseAllWindowsPlanError.unknownDirtyWindowID(windowID)
            }
        }
        for windowID in request.vetoes.keys {
            guard seen.contains(windowID) else {
                throw CloseAllWindowsPlanError.unknownVetoWindowID(windowID)
            }
        }

        // Reverse supplied window-cycle order, matching `ComparisonWindowCommandState.closeAll`.
        let ordered = orderedIDs.reversed()
        var steps: [CloseStep] = []
        steps.reserveCapacity(ordered.count)
        var dirtyCount = 0
        var vetoedIDs: [WindowID] = []
        for (ordinal, windowID) in ordered.enumerated() {
            if ordinal % cancellationCheckInterval == 0 {
                try checked(cancellationCheck)
            }
            let veto = request.vetoes[windowID] ?? .none
            let requiresConfirmation = request.dirtyWindowIDs.contains(windowID)
            if requiresConfirmation { dirtyCount += 1 }
            if veto.isVetoed { vetoedIDs.append(windowID) }
            steps.append(
                CloseStep(
                    ordinal: ordinal,
                    windowID: windowID,
                    requiresConfirmation: requiresConfirmation,
                    veto: veto
                ))
        }
        try checked(cancellationCheck)
        return CloseAllPlan(
            generation: request.generation,
            steps: steps,
            dirtyCount: dirtyCount,
            vetoedCount: vetoedIDs.count,
            vetoedWindowIDs: vetoedIDs.sorted(),
            verifyAfterCloseWiring: .required,
            workPerformed: steps.count
        )
    }

    private static func checked(_ cancellationCheck: @escaping CancellationCheck) throws {
        do {
            try cancellationCheck()
        } catch let error as CloseAllWindowsPlanError {
            throw error
        } catch {
            throw CloseAllWindowsPlanError.cancelled
        }
    }
}

public enum CloseAllWindowsPlanError: Error, Equatable, LocalizedError, Sendable {
    case tooManyWindows(maximum: Int)
    case duplicateWindowID(CloseAllWindowsPlan.WindowID)
    case unknownDirtyWindowID(CloseAllWindowsPlan.WindowID)
    case unknownVetoWindowID(CloseAllWindowsPlan.WindowID)
    case generationExhausted
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .tooManyWindows(let maximum):
            "Close-all planning exceeds the \(maximum)-window limit."
        case .duplicateWindowID(let windowID):
            "Close-all window identity \(windowID.rawValue) is duplicated."
        case .unknownDirtyWindowID(let windowID):
            "Close-all dirty window \(windowID.rawValue) is not open."
        case .unknownVetoWindowID(let windowID):
            "Close-all veto window \(windowID.rawValue) is not open."
        case .generationExhausted:
            "Close-all session generation is exhausted."
        case .cancelled:
            "Close-all planning was cancelled."
        }
    }
}
