import Foundation

/// Mutation executor for `BinaryHexEditingPolicy` plans.
///
/// Owns live pane snapshots and plans mutation-free through the policy: planning never
/// touches actor state, and commits install one planned `BinaryHexExecutionState` atomically
/// through exact compare-and-swap only. Performs no filesystem, pasteboard, text parsing,
/// implicit character-set detection, or UI work, and claims no panes or menus.
public actor BinaryHexEditExecutor: BinaryHexPlanExecutor {
    private var panes: [BinaryHexPane: BinaryHexPaneSnapshot]

    public init(panes: [BinaryHexPane: BinaryHexPaneSnapshot] = [:]) {
        self.panes = panes
    }

    public func setPane(_ snapshot: BinaryHexPaneSnapshot) {
        panes[snapshot.pane] = snapshot
    }

    public func snapshot(of pane: BinaryHexPane) -> BinaryHexPaneSnapshot? {
        panes[pane]
    }

    /// Atomic in-memory mutation boundary. Synchronous, without suspension: compares complete
    /// live pane state with `transaction.expectedPane` byte-for-byte, commits nothing on
    /// mismatch, and otherwise installs `executionState` with a fresh never-reused revision
    /// when `requiresNewRevision` is set. Throws `.cancelled` only before commit.
    public func compareAndExecute(
        _ transaction: BinaryHexExecutionTransaction
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionOutcome {
        try checkCancellation()
        guard let live = panes[transaction.expectedPane.pane] else {
            throw BinaryHexPolicyError.inconsistentPlan
        }
        let expected = transaction.expectedPane
        guard live.pane == expected.pane,
            live.version.identity == expected.version.identity,
            live.version.revision == expected.version.revision,
            live.selection == expected.selection,
            live.displaySettings == expected.displaySettings,
            live.isReadOnly == expected.isReadOnly,
            live.isDirty == expected.isDirty,
            live.maximumByteCount == expected.maximumByteCount
        else {
            return .notCommitted(currentPane: live)
        }
        let interval = max(1, transaction.limits.cancellationCheckInterval)
        guard try bytesEqual(live.data, expected.data, checkInterval: interval) else {
            return .notCommitted(currentPane: live)
        }
        guard try bytesEqual(live.persistedData, expected.persistedData, checkInterval: interval)
        else {
            return .notCommitted(currentPane: live)
        }
        let committedVersion: BinaryHexContentVersion
        if transaction.requiresNewRevision {
            committedVersion = BinaryHexContentVersion(
                identity: expected.version.identity,
                revision: expected.version.revision &+ 1
            )
        } else {
            committedVersion = expected.version
        }
        let committed = BinaryHexPaneSnapshot(
            pane: expected.pane,
            version: committedVersion,
            data: transaction.executionState.data,
            persistedData: transaction.executionState.persistedData,
            maximumByteCount: transaction.executionState.maximumByteCount,
            selection: transaction.executionState.selection,
            displaySettings: transaction.executionState.displaySettings,
            isReadOnly: transaction.executionState.isReadOnly,
            isDirty: transaction.executionState.isDirty
        )
        panes[expected.pane] = committed
        return .committed(BinaryHexExecutionReceipt(transaction: transaction, committedPane: committed))
    }

    /// Plans `intent` against the live snapshot without mutating actor state.
    public func plan(
        _ intent: BinaryHexIntent,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexEditingPlan {
        guard let live = panes[pane] else { throw BinaryHexPolicyError.inconsistentPlan }
        return try BinaryHexEditingPolicy.plan(intent, in: live, limits: limits)
    }

    /// Plans mutation-free, then commits through exact CAS with a policy-validated receipt.
    public func run(
        _ intent: BinaryHexIntent,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try plan(intent, for: pane, limits: limits).execute(on: self)
    }

    public func insert(
        _ payload: BinaryHexPayload,
        at target: BinaryHexEditTarget,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try run(.edit(.insert(payload: payload, target: target)), for: pane, limits: limits)
    }

    public func overwrite(
        _ payload: BinaryHexPayload,
        at target: BinaryHexEditTarget,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try run(.edit(.overwrite(payload: payload, target: target)), for: pane, limits: limits)
    }

    public func delete(
        selection: BinaryHexSelection? = nil,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try run(.edit(.delete(selection: selection)), for: pane, limits: limits)
    }

    public func find(
        _ intent: BinaryHexFindIntent,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try run(.find(intent), for: pane, limits: limits)
    }

    public func replace(
        _ intent: BinaryHexReplaceIntent,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try run(.replace(intent), for: pane, limits: limits)
    }

    public func goTo(
        _ intent: BinaryHexGoToIntent,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try run(.goTo(intent), for: pane, limits: limits)
    }

    public func select(
        _ intent: BinaryHexSelectionIntent,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try run(.selection(intent), for: pane, limits: limits)
    }

    public func updateDisplaySettings(
        _ settings: BinaryHexDisplaySettings,
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try run(.displaySettings(settings), for: pane, limits: limits)
    }

    public func status(
        for pane: BinaryHexPane,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexPaneStatus {
        guard let live = panes[pane] else { throw BinaryHexPolicyError.inconsistentPlan }
        return try BinaryHexEditingPolicy.status(for: live, limits: limits)
    }

    public func selection(
        atAlignedOffset offset: Int,
        side: BinaryHexComparisonSide,
        in comparison: BinaryComparisonResult,
        surface: BinaryHexSelectionSurface = .bytes
    ) throws(BinaryHexPolicyError) -> BinaryHexSelection {
        try BinaryHexEditingPolicy.selection(atAlignedOffset: offset, side: side, in: comparison, surface: surface)
    }
}

private func binaryHexExecutorCheckCancellation() throws(BinaryHexPolicyError) {
    do {
        try Task<Never, Never>.checkCancellation()
    } catch {
        throw BinaryHexPolicyError.cancelled
    }
}

extension BinaryHexEditExecutor {
    private func checkCancellation() throws(BinaryHexPolicyError) {
        try binaryHexExecutorCheckCancellation()
    }

    private func bytesEqual(
        _ left: Data,
        _ right: Data,
        checkInterval: Int
    ) throws(BinaryHexPolicyError) -> Bool {
        guard left.count == right.count else { return false }
        var offset = 0
        while offset < left.count {
            if offset.isMultiple(of: checkInterval) {
                try checkCancellation()
            }
            let end = min(offset + checkInterval, left.count)
            var index = offset
            while index < end {
                let leftByte = left[left.index(left.startIndex, offsetBy: index)]
                let rightByte = right[right.index(right.startIndex, offsetBy: index)]
                guard leftByte == rightByte else { return false }
                index += 1
            }
            offset = end
        }
        return true
    }
}
