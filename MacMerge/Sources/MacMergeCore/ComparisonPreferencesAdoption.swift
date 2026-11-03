import Foundation

/// Plan-only adoption of comparison preferences to engine targets.
///
/// Builds on ``ComparisonPreferencesWorkflow`` without owning preference pages,
/// engines, documents, or persistence I/O. The workflow remains the sole owner
/// of revision/content compare-and-swap, canonical persistence, and atomic
/// adoption; this planner only projects an already-planned
/// ``ComparisonPreferencesPlan`` onto the per-mode engine inputs
/// (``ComparisonOpenModeOptions`` plus the folder filename filter) so a future
/// engine executor can apply them without reading page state.
///
/// Every entry point is side-effect free: it validates limits, honors
/// cancellation, and re-verifies the plan's exact revision/content binding
/// before returning targets. Claimed: none of the native preference pages or
/// engine executors.
public enum ComparisonPreferencesAdoption: Sendable {
    /// One mode's engine inputs bound to the plan's exact revision/content CAS.
    public struct EngineTarget: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible
    {
        /// Preference page that owns these engine inputs.
        public let mode: ComparisonPreferencesMode
        /// Engine inputs for this mode.
        public let options: ComparisonOpenModeOptions
        /// Compiled-filter descriptor for folder mode; nil for all other modes.
        public let filenameFilter: ComparisonOpenFilenameFilter?
        /// Revision the plan was computed against.
        public let expectedRevision: ComparisonPreferencesRevision
        /// Revision the engine must publish on success.
        public let adoptedRevision: ComparisonPreferencesRevision
        /// Canonical content SHA the plan was computed against.
        public let expectedSHA256: [UInt8]
        /// Canonical content SHA the engine must publish.
        public let preferencesSHA256: [UInt8]
        /// Domain-level change flag from the originating plan.
        public let didChange: Bool

        fileprivate init(
            mode: ComparisonPreferencesMode,
            options: ComparisonOpenModeOptions,
            filenameFilter: ComparisonOpenFilenameFilter?,
            plan: ComparisonPreferencesPlan
        ) {
            self.mode = mode
            self.options = options
            self.filenameFilter = filenameFilter
            expectedRevision = plan.expectedRevision
            adoptedRevision = plan.resultingRevision
            expectedSHA256 = plan.expectedSHA256
            preferencesSHA256 = plan.resultingSHA256
            didChange = plan.didChange
        }

        public var description: String {
            "ComparisonPreferencesAdoption.EngineTarget(mode: \(mode.rawValue), changed: \(didChange), values: <redacted>)"
        }

        public var debugDescription: String { description }
    }

    /// Engine inputs for exactly one preference page.
    public static func engineOptions(
        for settings: ComparisonPreferencesModeSettings
    ) -> ComparisonOpenModeOptions {
        settings.comparisonOpenModeOptions
    }

    /// Engine inputs for one mode of a complete preference set.
    public static func engineOptions(
        for mode: ComparisonPreferencesMode,
        in preferences: ComparisonPreferences
    ) -> ComparisonOpenModeOptions {
        preferences.settings(for: mode).comparisonOpenModeOptions
    }

    /// Factory defaults projected to engine inputs for one mode.
    public static func defaultEngineOptions(
        for mode: ComparisonPreferencesMode
    ) -> ComparisonOpenModeOptions {
        engineOptions(for: .defaults(for: mode))
    }

    /// Whether page settings equal factory defaults.
    public static func isDefault(_ settings: ComparisonPreferencesModeSettings) -> Bool {
        settings == .defaults(for: settings.mode)
    }

    /// Executor-side filename-filter descriptor for folder comparisons.
    public static func filenameFilter(
        in preferences: ComparisonPreferences
    ) -> ComparisonOpenFilenameFilter {
        preferences.folder.filenameFilter.comparisonOpenFilter
    }

    /// Modes touched by a plan: exactly one page for apply/defaults, all six for reset.
    public static func affectedModes(for plan: ComparisonPreferencesPlan) -> [ComparisonPreferencesMode] {
        if let mode = plan.mode { return [mode] }
        return ComparisonPreferencesMode.allCases
    }

    /// Exact revision/content freshness of a plan against a current snapshot.
    public static func validateFreshness(
        _ plan: ComparisonPreferencesPlan,
        against snapshot: ComparisonPreferencesSnapshot,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        try checkCancellation()
        guard plan.expectedRevision == snapshot.revision else {
            throw ComparisonPreferencesWorkflowError.staleRevision(
                expected: plan.expectedRevision,
                actual: snapshot.revision
            )
        }
        let currentSHA = try snapshot.preferences.canonicalContentSHA256(limits: limits)
        guard currentSHA == plan.expectedSHA256 else {
            throw ComparisonPreferencesWorkflowError.staleSnapshot
        }
        try checkCancellation()
    }

    /// Projects a workflow plan onto engine targets.
    ///
    /// Re-hashes the resulting canonical content under `limits`, so
    /// non-canonical or over-budget plans fail here with the workflow's
    /// persistence errors before any engine sees them.
    public static func targets(
        for plan: ComparisonPreferencesPlan,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> [EngineTarget] {
        try checkCancellation()
        if plan.didChange {
            guard plan.resultingRevision.lineage == plan.expectedRevision.lineage,
                plan.expectedRevision.generation != .max,
                plan.resultingRevision.generation == plan.expectedRevision.generation + 1,
                plan.resultingSHA256 != plan.expectedSHA256
            else {
                throw ComparisonPreferencesWorkflowError.invalidPlan
            }
        } else {
            guard plan.resultingRevision == plan.expectedRevision,
                plan.resultingSHA256 == plan.expectedSHA256
            else {
                throw ComparisonPreferencesWorkflowError.invalidPlan
            }
        }
        let resultingSHA = try plan.preferences.canonicalContentSHA256(limits: limits)
        guard resultingSHA == plan.resultingSHA256 else {
            throw ComparisonPreferencesWorkflowError.invalidPlan
        }
        var result: [EngineTarget] = []
        result.reserveCapacity(affectedModes(for: plan).count)
        for mode in affectedModes(for: plan) {
            try checkCancellation()
            let settings = plan.preferences.settings(for: mode)
            let filter: ComparisonOpenFilenameFilter?
            if case .folder(let folder) = settings {
                filter = folder.filenameFilter.comparisonOpenFilter
            } else {
                filter = nil
            }
            result.append(
                EngineTarget(
                    mode: mode,
                    options: settings.comparisonOpenModeOptions,
                    filenameFilter: filter,
                    plan: plan
                )
            )
        }
        return result
    }

    /// Atomically adopts a plan through the workflow, then projects engine targets.
    ///
    /// Atomicity and the exact revision/content CAS belong to
    /// `ComparisonPreferencesWorkflow.execute(_:using:)`; on executor failure
    /// the workflow requires reload and this helper propagates that state by
    /// rethrowing without returning targets or a receipt.
    @discardableResult
    public static func adopt(
        _ plan: ComparisonPreferencesPlan,
        in workflow: ComparisonPreferencesWorkflow,
        using adopter: any ComparisonPreferencesAdopting
    ) async throws -> (receipt: ComparisonPreferencesReceipt, targets: [EngineTarget]) {
        try checkCancellation()
        let receipt = try await workflow.execute(plan, using: adopter)
        let resolved = try targets(for: plan, limits: workflow.limits)
        return (receipt, resolved)
    }

    /// Canonical bytes for a snapshot; redacted wrapper around the workflow codec.
    public static func canonicalData(
        for snapshot: ComparisonPreferencesSnapshot,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> Data {
        try checkCancellation()
        return try snapshot.encodedData(limits: limits)
    }

    /// Decodes canonical bytes, rejecting non-canonical or over-budget input.
    public static func decodedSnapshot(
        from data: Data,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> ComparisonPreferencesSnapshot {
        try checkCancellation()
        return try ComparisonPreferencesSnapshot.decode(from: data, limits: limits)
    }

    private static func checkCancellation() throws {
        try ComparisonPreferencesWorkflowTestHooks.checkCancellation()
    }
}
