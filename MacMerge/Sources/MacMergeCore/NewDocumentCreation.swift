import Foundation

/// UI-independent creation planner for blank new comparison documents.
///
/// `NewDocumentCreation` maps all twelve WinMerge New commands (two/three-pane
/// Text/Table/Binary/Image/Webpage/Folder) across menu, keyboard, toolbar, and
/// VoiceOver invocation into deterministic blank/source intents. It builds
/// entirely on `NewDocumentRoutingPolicy`: routing validates immutable caller
/// snapshots, plans exact option-bound values, and authorizes one-shot
/// execution through a `CreationLedger`. It never creates a document, presents
/// UI, touches the filesystem, or materializes a pane source.
public enum NewDocumentCreation: Sendable {
    public typealias Policy = NewDocumentRoutingPolicy
    public typealias CommandID = Policy.CommandID
    public typealias Invocation = Policy.Invocation
    public typealias InvocationID = Policy.InvocationID
    public typealias InvocationKind = Policy.InvocationKind
    public typealias LabelIntent = Policy.LabelIntent
    public typealias Limits = Policy.Limits
    public typealias Limit = Policy.Limit
    public typealias Snapshot = Policy.Snapshot
    public typealias SnapshotFingerprint = Policy.SnapshotFingerprint
    public typealias SnapshotIdentity = Policy.SnapshotIdentity
    public typealias Revision = Policy.Revision
    public typealias Request = Policy.Request
    public typealias Receipt = Policy.Receipt
    public typealias ReceiptID = Policy.ReceiptID
    public typealias Presentation = Policy.Presentation
    public typealias DocumentPlan = NewComparisonDocumentPlan
    public typealias CreationError = NewDocumentRoutingPolicyError
    public typealias CancellationCheck = Policy.CancellationCheck

    public static func taskCancellationCheck() throws(CreationError) {
        try Policy.taskCancellationCheck()
    }

    /// Deterministic blank/source intent for one pane. Sources mirror the
    /// defaults `NewComparisonDocumentPlan` materializes: empty text/binary
    /// scratchpads, transparent image intents, blank webpage intents, and
    /// caller-supplied empty-folder requirements.
    public struct PaneIntent: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let pane: DocumentPlan.Pane
        public let source: DocumentPlan.PaneSource

        public init(pane: DocumentPlan.Pane, source: DocumentPlan.PaneSource) {
            self.pane = pane
            self.source = source
        }

        public var description: String {
            "NewDocumentCreation.PaneIntent(pane: \(pane.rawValue), source: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["pane": pane.rawValue, "source": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    /// Planned creation value: exact command binding, localized label intents,
    /// deterministic pane sources, and the exact mode options validated for
    /// the current snapshot. Contains no document, URL, or UI state.
    public struct Intent: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let commandID: CommandID
        public let invocationKind: InvocationKind
        public let menuLabelIntent: LabelIntent
        public let actionLabelIntent: LabelIntent
        public let paneIntents: [PaneIntent]
        public let modeOptions: ComparisonOpenModeOptions
        public let expectedSnapshotFingerprint: SnapshotFingerprint
        public let routingWorkPerformed: Int

        public var mode: DocumentPlan.Mode { commandID.mode }
        public var paneCount: DocumentPlan.PaneCount { commandID.paneCount }

        fileprivate init(
            commandID: CommandID,
            invocationKind: InvocationKind,
            paneIntents: [PaneIntent],
            modeOptions: ComparisonOpenModeOptions,
            expectedSnapshotFingerprint: SnapshotFingerprint,
            routingWorkPerformed: Int
        ) {
            self.commandID = commandID
            self.invocationKind = invocationKind
            menuLabelIntent = NewDocumentCreation.menuLabelIntent(for: commandID.mode)
            actionLabelIntent = NewDocumentCreation.actionLabelIntent(for: commandID)
            self.paneIntents = paneIntents
            self.modeOptions = modeOptions
            self.expectedSnapshotFingerprint = expectedSnapshotFingerprint
            self.routingWorkPerformed = routingWorkPerformed
        }

        public func validateCurrentSnapshot(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck = NewDocumentCreation
                .taskCancellationCheck
        ) throws(CreationError) {
            try expectedSnapshotFingerprint.validateCurrent(
                snapshot,
                cancellationCheck: cancellationCheck
            )
        }

        public var description: String {
            "NewDocumentCreation.Intent(commandID: \(commandID.rawValue), kind: \(invocationKind.rawValue), panes: \(paneIntents.count), bindings: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "commandID": commandID.rawValue,
                    "invocationKind": invocationKind.rawValue,
                    "menuLabelIntent": menuLabelIntent.rawValue,
                    "actionLabelIntent": actionLabelIntent.rawValue,
                    "paneCount": paneIntents.count,
                    "bindings": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Authorized plan pairing a one-shot routing receipt with its intent.
    public struct CreationPlan: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let receipt: Receipt
        public let intent: Intent
        public let routingWorkPerformed: Int
        public let documentPlanningWorkPerformed: Int
        fileprivate let policyPlan: Policy.Plan

        fileprivate init(
            policyPlan: Policy.Plan,
            intent: Intent
        ) {
            receipt = policyPlan.receipt
            self.intent = intent
            routingWorkPerformed = policyPlan.routingWorkPerformed
            documentPlanningWorkPerformed = policyPlan.documentPlanningWorkPerformed
            self.policyPlan = policyPlan
        }

        public func validateCurrentSnapshot(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck = NewDocumentCreation
                .taskCancellationCheck
        ) throws(CreationError) {
            try receipt.validateCurrentSnapshot(
                snapshot,
                cancellationCheck: cancellationCheck
            )
        }

        public var description: String {
            "NewDocumentCreation.CreationPlan(commandID: \(receipt.commandID.rawValue), routingWorkPerformed: \(routingWorkPerformed), intent: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "commandID": receipt.commandID.rawValue,
                    "routingWorkPerformed": routingWorkPerformed,
                    "intent": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// One-shot execution authorization. Consuming returns the planned
    /// `NewComparisonDocumentPlan` exactly once; the host materializes it.
    public struct CreationAuthorization: Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        private let inner: Policy.ExecutionAuthorization
        public let intent: Intent

        fileprivate init(inner: Policy.ExecutionAuthorization, intent: Intent) {
            self.inner = inner
            self.intent = intent
        }

        public func consume(
            cancellationCheck: @escaping CancellationCheck = NewDocumentCreation
                .taskCancellationCheck
        ) async throws(CreationError) -> DocumentPlan {
            try await inner.consume(cancellationCheck: cancellationCheck)
        }

        public var description: String {
            "NewDocumentCreation.CreationAuthorization(commandID: \(intent.commandID.rawValue), authorization: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "commandID": intent.commandID.rawValue, "authorization": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Actor-isolated one-shot ledger. Freshness validation and receipt
    /// consumption happen in one actor turn, matching routing policy semantics.
    public actor CreationLedger: CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        private let inner: Policy.ReceiptLedger

        public init(authoritativeSnapshot: Snapshot) throws(CreationError) {
            inner = try Policy.ReceiptLedger(authoritativeSnapshot: authoritativeSnapshot)
        }

        public nonisolated var id: Policy.ReceiptLedger.ID { inner.id }
        public nonisolated var limits: Limits { inner.limits }
        public nonisolated var description: String {
            "NewDocumentCreation.CreationLedger(id: <redacted>, state: <actor-isolated>)"
        }

        public nonisolated var debugDescription: String { description }

        public nonisolated var customMirror: Mirror {
            Mirror(
                self,
                children: ["id": "<redacted>", "state": "<actor-isolated>"],
                displayStyle: .class
            )
        }

        public func consumedReceiptCount() async -> Int {
            await inner.consumedReceiptCount
        }

        public func updateAuthoritativeSnapshot(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck = NewDocumentCreation
                .taskCancellationCheck
        ) async throws(CreationError) {
            try await inner.updateAuthoritativeSnapshot(
                snapshot,
                cancellationCheck: cancellationCheck
            )
        }

        /// Plans against the current snapshot and binds the receipt to this
        /// ledger. Consume the returned plan through this same ledger exactly
        /// once.
        public func plan(
            _ request: Request,
            currentSnapshot snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck = NewDocumentCreation
                .taskCancellationCheck
        ) throws(CreationError) -> CreationPlan {
            let policyPlan = try Policy.plan(
                request,
                currentSnapshot: snapshot,
                receiptLedger: inner,
                cancellationCheck: cancellationCheck
            )
            return CreationPlan(
                policyPlan: policyPlan,
                intent: Intent(
                    commandID: request.commandID,
                    invocationKind: request.invocation.kind,
                    paneIntents: NewDocumentCreation.blankPaneIntents(
                        for: request.commandID
                    ),
                    modeOptions: snapshot.options.modeOptions(
                        for: request.commandID.mode
                    ),
                    expectedSnapshotFingerprint: request.expectedSnapshotFingerprint,
                    routingWorkPerformed: policyPlan.routingWorkPerformed
                )
            )
        }

        /// Validates fingerprint freshness and consumes the receipt in one turn.
        public func consume(
            _ plan: CreationPlan,
            cancellationCheck: @escaping CancellationCheck = NewDocumentCreation
                .taskCancellationCheck
        ) async throws(CreationError) -> CreationAuthorization {
            let authorization = try await inner.consume(
                plan.policyPlan,
                cancellationCheck: cancellationCheck
            )
            return CreationAuthorization(inner: authorization, intent: plan.intent)
        }
    }

    // MARK: - Label intents (localization lookup only; never display text)

    public static func menuLabelIntent(for mode: DocumentPlan.Mode) -> LabelIntent {
        switch mode {
        case .text: .text
        case .table: .table
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        case .folder: .folder
        }
    }

    public static func actionLabelIntent(for commandID: CommandID) -> LabelIntent {
        switch commandID {
        case .twoPaneText: .twoPaneText
        case .twoPaneTable: .twoPaneTable
        case .twoPaneBinary: .twoPaneBinary
        case .twoPaneImage: .twoPaneImage
        case .twoPaneWebpage: .twoPaneWebpage
        case .twoPaneFolder: .twoPaneFolder
        case .threePaneText: .threePaneText
        case .threePaneTable: .threePaneTable
        case .threePaneBinary: .threePaneBinary
        case .threePaneImage: .threePaneImage
        case .threePaneWebpage: .threePaneWebpage
        case .threePaneFolder: .threePaneFolder
        }
    }

    /// Deterministic blank/source pane intents for a command. Pure: no
    /// snapshot, ledger, document, or I/O involved.
    public static func blankPaneIntents(for commandID: CommandID) -> [PaneIntent] {
        let source: DocumentPlan.PaneSource = {
            switch commandID.mode {
            case .text, .table:
                return .scratchpad(.text(""))
            case .binary:
                return .scratchpad(.binary(Data()))
            case .image:
                return .emptyImage
            case .webpage:
                return .blankWebpage
            case .folder:
                return .requiredSource(.emptyFolder)
            }
        }()
        return commandID.paneCount.panes.map {
            PaneIntent(pane: $0, source: source)
        }
    }

    // MARK: - Routing entry points (delegate to policy; enforce primary-only)

    public static func request(
        for invocation: Invocation,
        in snapshot: Snapshot,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(CreationError) -> Request {
        try Policy.makeRequest(
            for: invocation,
            in: snapshot,
            cancellationCheck: cancellationCheck
        )
    }

    public static func presentation(
        in snapshot: Snapshot,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(CreationError) -> Presentation {
        try Policy.presentation(in: snapshot, cancellationCheck: cancellationCheck)
    }

    public static func intent(
        for invocation: Invocation,
        in snapshot: Snapshot,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(CreationError) -> Intent {
        let request = try request(
            for: invocation,
            in: snapshot,
            cancellationCheck: cancellationCheck
        )
        return try intent(
            for: request,
            in: snapshot,
            cancellationCheck: cancellationCheck
        )
    }

    public static func intent(
        for request: Request,
        in snapshot: Snapshot,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(CreationError) -> Intent {
        try request.validateCurrentSnapshot(
            snapshot,
            cancellationCheck: cancellationCheck
        )
        return Intent(
            commandID: request.commandID,
            invocationKind: request.invocation.kind,
            paneIntents: blankPaneIntents(for: request.commandID),
            modeOptions: snapshot.options.modeOptions(for: request.commandID.mode),
            expectedSnapshotFingerprint: request.expectedSnapshotFingerprint,
            routingWorkPerformed: request.routingWorkPerformed
        )
    }

    /// Plans against the current snapshot and binds the receipt to `ledger`.
    /// Consume the returned plan through the same ledger exactly once.
    public static func plan(
        _ request: Request,
        currentSnapshot snapshot: Snapshot,
        receiptLedger ledger: Policy.ReceiptLedger,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(CreationError) -> CreationPlan {
        let policyPlan = try Policy.plan(
            request,
            currentSnapshot: snapshot,
            receiptLedger: ledger,
            cancellationCheck: cancellationCheck
        )
        return CreationPlan(
            policyPlan: policyPlan,
            intent: Intent(
                commandID: request.commandID,
                invocationKind: request.invocation.kind,
                paneIntents: blankPaneIntents(for: request.commandID),
                modeOptions: snapshot.options.modeOptions(for: request.commandID.mode),
                expectedSnapshotFingerprint: request.expectedSnapshotFingerprint,
                routingWorkPerformed: policyPlan.routingWorkPerformed
            )
        )
    }
}
