import Foundation

/// UI-independent routing for the global Edit-menu "Copy With Line Numbers" command.
///
/// Planning only: resolves the Edit-menu selection (explicit multi-row selection with
/// focused-row fallback), derives side-aware AX enablement, and produces checked
/// pasteboard-write intents bound to an exact snapshot CAS. This file claims no menu,
/// dialog, view, pasteboard, or owner-transfer-service behavior; the Edit menu adopts
/// it by owning snapshots, applying returned intents through its executor, and
/// rendering returned enablement as label/value/hint state.
public enum NumberedCopyMenuRouting: Sendable {
    public typealias Side = MultiRowNumberedCopyWorkflowSide
    public typealias WorkflowLimits = MultiRowNumberedCopyWorkflowLimits
    public typealias Snapshot = MultiRowNumberedCopyWorkflowSnapshot
    public typealias SnapshotReference = MultiRowNumberedCopyWorkflowSnapshotReference
    public typealias DisabledReason = MultiRowNumberedCopyWorkflowDisabledReason

    /// Caller-supplied Edit-menu invocation. `side` selects the copy source pane;
    /// empty `explicitRanges` falls back to `focusedRow`, matching row-context behavior
    /// for a single focused row.
    public struct MenuRequest: Equatable, Sendable {
        public let side: Side
        public let style: MultiRowNumberedCopyWorkflowCopyStyle
        public let explicitRanges: [Range<Int>]
        public let focusedRow: Int?
        public let formatOptions: NumberedTextCopyOptions

        public init(
            side: Side,
            style: MultiRowNumberedCopyWorkflowCopyStyle = .numbered,
            explicitRanges: [Range<Int>] = [],
            focusedRow: Int? = nil,
            formatOptions: NumberedTextCopyOptions = NumberedTextCopyOptions()
        ) {
            self.side = side
            self.style = style
            self.explicitRanges = explicitRanges
            self.focusedRow = focusedRow
            self.formatOptions = formatOptions
        }

        public init(
            side: Side,
            style: MultiRowNumberedCopyWorkflowCopyStyle = .numbered,
            explicitSelection: IndexSet,
            focusedRow: Int? = nil,
            formatOptions: NumberedTextCopyOptions = NumberedTextCopyOptions()
        ) {
            self.init(
                side: side,
                style: style,
                explicitRanges: explicitSelection.rangeView.map { $0.lowerBound..<$0.upperBound },
                focusedRow: focusedRow,
                formatOptions: formatOptions
            )
        }

        fileprivate var intent: MultiRowNumberedCopyWorkflowIntent {
            MultiRowNumberedCopyWorkflowIntent(
                side: side,
                style: style,
                origin: .editMenu,
                formatOptions: formatOptions
            )
        }
    }

    /// Bounds for every pass behind Edit-menu routing. The workflow core keeps its
    /// own defaults; this guards the values routing can observe without trapping.
    public struct Limits: Equatable, Sendable {
        public static let `default` = Limits()

        public let workflow: WorkflowLimits

        public init(workflow: WorkflowLimits = .default) {
            self.workflow = workflow
        }
    }

    /// AX-ready enablement derived from one snapshot without planning a payload.
    public struct Enablement: Equatable, Sendable {
        public let side: Side
        public let isEnabled: Bool
        public let disabledReason: DisabledReason?
        public let accessibilityLabel: String
        public let accessibilityHint: String
        public let expectedSnapshot: SnapshotReference
        public let workUnitsConsumed: UInt64

        public var canExecute: Bool { isEnabled }
    }

    /// Checked pasteboard-write intent. The executor writes `payload` to its owner
    /// transfer service exactly once, then attests with matching evidence.
    public struct PasteboardWriteIntent: Equatable, Sendable {
        public let plan: MultiRowNumberedCopyWorkflowPlan
        public let payload: String
        public let payloadUTF8ByteCount: Int
        public let expectedSnapshot: SnapshotReference
        public let requiredEffects: [MultiRowNumberedCopyWorkflowRequiredEffect]
        public let executorContract: MultiRowNumberedCopyWorkflowExecutorContract

        fileprivate init(plan: MultiRowNumberedCopyWorkflowPlan) {
            self.plan = plan
            payload = plan.payload
            payloadUTF8ByteCount = plan.receipt.payloadUTF8ByteCount
            expectedSnapshot = plan.expectedSnapshot
            requiredEffects = plan.requiredEffects
            executorContract = plan.executorContract
        }

        /// Rejects a forged or concurrently advanced snapshot before any write.
        public func validateCurrentSnapshot(_ snapshot: Snapshot) throws {
            do {
                try plan.validateCurrentSnapshot(snapshot)
            } catch is CancellationError {
                throw NumberedCopyMenuRoutingError.cancelled
            } catch let error as MultiRowNumberedCopyWorkflowError where error == .cancelled {
                throw NumberedCopyMenuRoutingError.cancelled
            } catch let error as MultiRowNumberedCopyWorkflowError {
                throw NumberedCopyMenuRoutingError.workflow(error)
            }
        }
    }

    /// Resolves the Edit-menu selection to ordered, non-overlapping row ranges.
    public static func resolveSelection(
        _ request: MenuRequest,
        rowCount: Int,
        limits: Limits = .default
    ) throws -> [Range<Int>] {
        do {
            try Task.checkCancellation()
            return try MultiRowNumberedCopyWorkflow.resolveEditMenuSelection(
                explicitRanges: request.explicitRanges,
                focusedRow: request.focusedRow,
                rowCount: rowCount,
                limits: limits.workflow
            )
        } catch is CancellationError {
            throw NumberedCopyMenuRoutingError.cancelled
        } catch let error as MultiRowNumberedCopyWorkflowError where error == .cancelled {
            throw NumberedCopyMenuRoutingError.cancelled
        } catch let error as MultiRowNumberedCopyWorkflowError {
            throw NumberedCopyMenuRoutingError.workflow(error)
        }
    }

    /// Resolves the Edit-menu selection from an `IndexSet`, as delivered by table views.
    public static func resolveSelection(
        side _: Side,
        style _: MultiRowNumberedCopyWorkflowCopyStyle = .numbered,
        explicitSelection: IndexSet,
        focusedRow: Int?,
        rowCount: Int,
        formatOptions _: NumberedTextCopyOptions = NumberedTextCopyOptions(),
        limits: Limits = .default
    ) throws -> [Range<Int>] {
        do {
            try Task.checkCancellation()
            return try MultiRowNumberedCopyWorkflow.resolveEditMenuSelection(
                explicitSelection: explicitSelection,
                focusedRow: focusedRow,
                rowCount: rowCount,
                limits: limits.workflow
            )
        } catch is CancellationError {
            throw NumberedCopyMenuRoutingError.cancelled
        } catch let error as MultiRowNumberedCopyWorkflowError where error == .cancelled {
            throw NumberedCopyMenuRoutingError.cancelled
        } catch let error as MultiRowNumberedCopyWorkflowError {
            throw NumberedCopyMenuRoutingError.workflow(error)
        }
    }

    /// Derives menu/AX enablement for one Edit-menu invocation in one snapshot.
    public static func enablement(
        for request: MenuRequest,
        in snapshot: Snapshot,
        limits: Limits = .default
    ) throws -> Enablement {
        do {
            try Task.checkCancellation()
            let resolvedSelection = try MultiRowNumberedCopyWorkflow.resolveEditMenuSelection(
                explicitRanges: request.explicitRanges,
                focusedRow: request.focusedRow,
                rowCount: snapshot.comparisonRows.count,
                limits: limits.workflow
            )
            guard snapshot.selection.rowRanges == resolvedSelection else {
                throw MultiRowNumberedCopyWorkflowError.selectionChanged
            }
            let state = try MultiRowNumberedCopyWorkflow.commandState(
                for: request.intent,
                in: snapshot,
                limits: limits.workflow
            )
            try Task.checkCancellation()
            return Enablement(
                side: request.side,
                isEnabled: state.isEnabled,
                disabledReason: state.disabledReason,
                accessibilityLabel: accessibilityLabel(for: request),
                accessibilityHint: accessibilityHint(
                    side: request.side,
                    disabledReason: state.disabledReason
                ),
                expectedSnapshot: state.expectedSnapshot,
                workUnitsConsumed: state.workUnitsConsumed
            )
        } catch is CancellationError {
            throw NumberedCopyMenuRoutingError.cancelled
        } catch let error as MultiRowNumberedCopyWorkflowError where error == .cancelled {
            throw NumberedCopyMenuRoutingError.cancelled
        } catch let error as MultiRowNumberedCopyWorkflowError {
            throw NumberedCopyMenuRoutingError.workflow(error)
        }
    }

    /// Plans a checked pasteboard-write intent; the executor performs the write.
    public static func plan(
        _ request: MenuRequest,
        in snapshot: Snapshot,
        limits: Limits = .default
    ) throws -> PasteboardWriteIntent {
        do {
            try Task.checkCancellation()
            let resolvedSelection = try MultiRowNumberedCopyWorkflow.resolveEditMenuSelection(
                explicitRanges: request.explicitRanges,
                focusedRow: request.focusedRow,
                rowCount: snapshot.comparisonRows.count,
                limits: limits.workflow
            )
            guard snapshot.selection.rowRanges == resolvedSelection else {
                throw MultiRowNumberedCopyWorkflowError.selectionChanged
            }
            let planned = try MultiRowNumberedCopyWorkflow.plan(
                intent: request.intent,
                in: snapshot,
                limits: limits.workflow
            )
            try Task.checkCancellation()
            guard planned.payload.utf8.count == planned.receipt.payloadUTF8ByteCount else {
                throw NumberedCopyMenuRoutingError.workflow(.invalidCopyEvidence)
            }
            return PasteboardWriteIntent(plan: planned)
        } catch is CancellationError {
            throw NumberedCopyMenuRoutingError.cancelled
        } catch let error as MultiRowNumberedCopyWorkflowError where error == .cancelled {
            throw NumberedCopyMenuRoutingError.cancelled
        } catch let error as MultiRowNumberedCopyWorkflowError {
            throw NumberedCopyMenuRoutingError.workflow(error)
        } catch let error as NumberedCopyMenuRoutingError {
            throw error
        }
    }

    private static func accessibilityLabel(for request: MenuRequest) -> String {
        let style = request.style == .numbered ? "with line numbers" : "selected lines"
        return "Copy \(request.side.rawValue) \(style)"
    }

    private static func accessibilityHint(
        side: Side,
        disabledReason: DisabledReason?
    ) -> String {
        switch disabledReason {
        case nil:
            "Copies the selected \(side.rawValue) rows to the clipboard."
        case .comparisonNotCurrent:
            "Unavailable while the comparison is not current."
        case .sourceNotLoaded(let missing):
            "Unavailable because the \(missing.rawValue) source is not loaded."
        case .emptySelection:
            "Select at least one row to copy."
        case .noCopyableSourceLines(let missing):
            "The selection has no \(missing.rawValue) lines to copy."
        }
    }
}

public enum NumberedCopyMenuRoutingError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case workflow(MultiRowNumberedCopyWorkflowError)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Edit-menu numbered copy was cancelled."
        case .workflow(let error):
            error.localizedDescription
        }
    }
}
