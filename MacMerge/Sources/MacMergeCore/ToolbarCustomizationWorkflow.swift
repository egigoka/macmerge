import Foundation

/// UI-independent, bounded customization transactions over authoritative `ToolbarConfiguration`.
public enum ToolbarCustomizationWorkflow: Sendable {
    public typealias Command = ToolbarConfiguration.Command
    public typealias Item = ToolbarConfiguration.Item
    public typealias Visibility = ToolbarConfiguration.Visibility
    public typealias Size = ToolbarConfiguration.Size
    public typealias CancellationCheck = @Sendable () -> Bool

    /// These capabilities describe value planning only. They do not imply an AppKit customization
    /// palette, native toolbar behavior, accessibility conformance, or runtime UI verification.
    public enum Capability: String, CaseIterable, Codable, Hashable, Sendable {
        case editAuthoritativeConfiguration
        case previewAuthoritativeOverflow
        case bindSemanticCommandState
        case canonicalConfigurationPersistence
        case exactConfigurationCompareAndSwap
    }

    public static let capabilities = Capability.allCases
    public static let capabilityScopeStatement =
        "UI-independent configuration and semantic command-state planning only; no native toolbar customization UI is created or verified."

    public struct ConfigurationIdentity: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue.uuidString < right.rawValue.uuidString
        }
    }

    public struct ConfigurationRevision: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }

        fileprivate var successor: Self? {
            guard rawValue < .max else { return nil }
            return Self(rawValue: rawValue + 1)
        }
    }

    public struct ConfigurationReference: Codable, Equatable, Hashable, Sendable {
        public let identity: ConfigurationIdentity
        public let revision: ConfigurationRevision

        public init(identity: ConfigurationIdentity, revision: ConfigurationRevision) {
            self.identity = identity
            self.revision = revision
        }
    }

    /// Commands may appear at most once under `ToolbarConfiguration`; required commands must appear.
    public struct Policy: Equatable, Hashable, Sendable {
        public static let permissive = Policy()

        public let requiredCommands: Set<Command>

        public init(requiredCommands: Set<Command> = []) {
            self.requiredCommands = requiredCommands
        }

        public var canonicalRequiredCommands: [Command] {
            Command.allCases.filter(requiredCommands.contains)
        }
    }

    public enum Limit: String, CaseIterable, Codable, Hashable, Sendable {
        case items
        case requiredCommands
        case transactionEdits
        case persistenceBytes
        case workUnits
        case cancellationCheckInterval
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumItemCount = ToolbarConfiguration.maximumItemCount
        public static let hardMaximumRequiredCommandCount = Command.allCases.count
        public static let hardMaximumTransactionEditCount = 4_096
        public static let hardMaximumPersistenceBytes = ToolbarConfiguration.maximumEncodedBytes
        public static let hardMaximumWorkUnits = 16 * 1_024 * 1_024
        public static let hardMaximumCancellationCheckInterval = 65_536
        public static let `default` = Limits()

        public let maximumItemCount: Int
        public let maximumRequiredCommandCount: Int
        public let maximumTransactionEditCount: Int
        public let maximumPersistenceBytes: Int
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumItemCount: Int = hardMaximumItemCount,
            maximumRequiredCommandCount: Int = hardMaximumRequiredCommandCount,
            maximumTransactionEditCount: Int = 1_024,
            maximumPersistenceBytes: Int = hardMaximumPersistenceBytes,
            maximumWorkUnits: Int = 256 * 1_024,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumItemCount = maximumItemCount
            self.maximumRequiredCommandCount = maximumRequiredCommandCount
            self.maximumTransactionEditCount = maximumTransactionEditCount
            self.maximumPersistenceBytes = maximumPersistenceBytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            try Self.validate(
                maximumItemCount,
                limit: .items,
                range: 0...Self.hardMaximumItemCount
            )
            try Self.validate(
                maximumRequiredCommandCount,
                limit: .requiredCommands,
                range: 0...Self.hardMaximumRequiredCommandCount
            )
            try Self.validate(
                maximumTransactionEditCount,
                limit: .transactionEdits,
                range: 0...Self.hardMaximumTransactionEditCount
            )
            try Self.validate(
                maximumPersistenceBytes,
                limit: .persistenceBytes,
                range: 1...Self.hardMaximumPersistenceBytes
            )
            try Self.validate(
                maximumWorkUnits,
                limit: .workUnits,
                range: 1...Self.hardMaximumWorkUnits
            )
            try Self.validate(
                cancellationCheckInterval,
                limit: .cancellationCheckInterval,
                range: 1...Self.hardMaximumCancellationCheckInterval
            )
        }

        private static func validate(
            _ value: Int,
            limit: Limit,
            range: ClosedRange<Int>
        ) throws {
            guard range.contains(value) else {
                throw WorkflowError.invalidLimit(limit, value: value)
            }
        }
    }

    /// Validated immutable owner state. Revisions must never be reused for different contents.
    public struct Snapshot: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let identity: ConfigurationIdentity
        public let revision: ConfigurationRevision
        public let configuration: ToolbarConfiguration
        public let policy: Policy
        public let limits: Limits

        public init(
            identity: ConfigurationIdentity = ConfigurationIdentity(),
            revision: ConfigurationRevision = ConfigurationRevision(rawValue: 0),
            configuration: ToolbarConfiguration = .winMergeDefault,
            policy: Policy = .permissive,
            limits: Limits = .default,
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws {
            var budget = try WorkBudget(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try ToolbarCustomizationWorkflow.validate(
                configuration,
                policy: policy,
                limits: limits,
                budget: &budget
            )
            _ = try ToolbarCustomizationWorkflow.canonicalData(
                for: configuration,
                limits: limits,
                budget: &budget
            )
            try budget.finish()

            self.identity = identity
            self.revision = revision
            self.configuration = configuration
            self.policy = policy
            self.limits = limits
        }

        public var reference: ConfigurationReference {
            ConfigurationReference(identity: identity, revision: revision)
        }

        public var cas: ConfigurationCAS { ConfigurationCAS(snapshot: self) }
        public var isCustomized: Bool { configuration.isCustomized }

        public var description: String {
            "ToolbarCustomizationWorkflow.Snapshot(revision: \(revision.rawValue), items: \(configuration.items.count), configuration: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "identity": identity,
                    "revision": revision,
                    "itemCount": configuration.items.count,
                    "requiredCommandCount": policy.requiredCommands.count,
                    "configuration": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func canonicalPersistence(
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws -> CanonicalPersistence {
            var budget = try WorkBudget(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            let data = try ToolbarCustomizationWorkflow.canonicalData(
                for: configuration,
                limits: limits,
                budget: &budget
            )
            try budget.finish()
            return CanonicalPersistence(reference: reference, data: data)
        }

        fileprivate init(
            identity: ConfigurationIdentity,
            revision: ConfigurationRevision,
            configuration: ToolbarConfiguration,
            policy: Policy,
            limits: Limits
        ) {
            self.identity = identity
            self.revision = revision
            self.configuration = configuration
            self.policy = policy
            self.limits = limits
        }
    }

    /// Collision-free CAS: reference equality is necessary, and exact bounded contents must match.
    public struct ConfigurationCAS: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let reference: ConfigurationReference
        private let configuration: ToolbarConfiguration
        private let policy: Policy
        private let limits: Limits

        fileprivate init(snapshot: Snapshot) {
            reference = snapshot.reference
            configuration = snapshot.configuration
            policy = snapshot.policy
            limits = snapshot.limits
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.ConfigurationCAS(revision: \(reference.revision.rawValue), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["reference": reference, "contents": "<redacted>"],
                displayStyle: .struct
            )
        }

        public func matches(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws -> Bool {
            do {
                try validate(snapshot, cancellationCheck: cancellationCheck)
                return true
            } catch WorkflowError.staleConfiguration,
                WorkflowError.configurationChangedWithoutRevision
            {
                return false
            }
        }

        public func validate(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws {
            var budget = try WorkBudget(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try validate(snapshot, budget: &budget)
            try budget.finish()
        }

        fileprivate func validate(
            _ snapshot: Snapshot,
            budget: inout WorkBudget
        ) throws {
            try budget.consume()
            guard snapshot.reference == reference else {
                throw WorkflowError.staleConfiguration(
                    expected: reference,
                    actual: snapshot.reference
                )
            }
            try budget.consume(configuration.items.count + snapshot.configuration.items.count)
            try budget.consume(policy.requiredCommands.count + snapshot.policy.requiredCommands.count)
            guard configuration == snapshot.configuration,
                policy == snapshot.policy,
                limits == snapshot.limits
            else {
                throw WorkflowError.configurationChangedWithoutRevision(reference)
            }
        }
    }

    public enum EditKind: String, CaseIterable, Codable, Hashable, Sendable {
        case setVisibility
        case setSize
        case addCommand
        case addSeparator
        case removeCommand
        case removeCommandAt
        case removeSeparator
        case removeItem
        case moveItem
        case resetToWinMergeDefaults
    }

    /// Indices use `ToolbarConfiguration` insertion-boundary semantics.
    public enum Edit: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case setVisibility(Visibility)
        case setSize(Size)
        case addCommand(Command, at: Int)
        case addSeparator(at: Int)
        case removeCommand(Command)
        case removeCommandAt(Int)
        case removeSeparator(at: Int)
        case removeItem(at: Int)
        case moveItem(from: Int, to: Int)
        case resetToWinMergeDefaults

        public var kind: EditKind {
            switch self {
            case .setVisibility: .setVisibility
            case .setSize: .setSize
            case .addCommand: .addCommand
            case .addSeparator: .addSeparator
            case .removeCommand: .removeCommand
            case .removeCommandAt: .removeCommandAt
            case .removeSeparator: .removeSeparator
            case .removeItem: .removeItem
            case .moveItem: .moveItem
            case .resetToWinMergeDefaults: .resetToWinMergeDefaults
            }
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.Edit(kind: \(kind.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["kind": kind, "details": "<redacted>"],
                displayStyle: .enum
            )
        }
    }

    public enum Decision: String, CaseIterable, Codable, Hashable, Sendable {
        case apply
        case cancel
    }

    public struct Transaction: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let expectedConfiguration: ConfigurationCAS
        public let edits: [Edit]

        public init(expectedConfiguration: ConfigurationCAS, edits: [Edit]) {
            self.expectedConfiguration = expectedConfiguration
            self.edits = edits
        }

        public init(snapshot: Snapshot, edits: [Edit]) {
            self.init(expectedConfiguration: snapshot.cas, edits: edits)
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.Transaction(revision: \(expectedConfiguration.reference.revision.rawValue), edits: \(edits.count), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "expectedConfiguration": expectedConfiguration.reference,
                    "editCount": edits.count,
                    "edits": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum PlanningDisposition: String, CaseIterable, Codable, Hashable, Sendable {
        case replacementPlanned
        case unchanged
        case cancelled
    }

    public enum Disposition: String, CaseIterable, Codable, Hashable, Sendable {
        case applied
        case unchanged
        case cancelled
    }

    public struct EditReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let editIndex: Int
        public let edit: Edit
        public let resultingItemCount: Int

        fileprivate init(editIndex: Int, edit: Edit, resultingItemCount: Int) {
            self.editIndex = editIndex
            self.edit = edit
            self.resultingItemCount = resultingItemCount
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.EditReceipt(index: \(editIndex), kind: \(edit.kind.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "editIndex": editIndex,
                    "kind": edit.kind,
                    "resultingItemCount": resultingItemCount,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Deterministic planning receipt: planning reads no clock, random source, UI state, or platform
    /// object. Actual mutation is proven only by an `ExecutionReceipt` with `.applied` disposition.
    public struct PlanningReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let decision: Decision
        public let disposition: PlanningDisposition
        public let expectedConfiguration: ConfigurationReference
        public let observedConfiguration: ConfigurationReference
        public let resultingConfiguration: ConfigurationReference
        public let edits: [EditReceipt]
        public let resultingItemCount: Int
        public let persistenceByteCount: Int?
        public let workPerformed: Int

        fileprivate init(
            decision: Decision,
            disposition: PlanningDisposition,
            expectedConfiguration: ConfigurationReference,
            observedConfiguration: ConfigurationReference,
            resultingConfiguration: ConfigurationReference,
            edits: [EditReceipt],
            resultingItemCount: Int,
            persistenceByteCount: Int?,
            workPerformed: Int
        ) {
            self.decision = decision
            self.disposition = disposition
            self.expectedConfiguration = expectedConfiguration
            self.observedConfiguration = observedConfiguration
            self.resultingConfiguration = resultingConfiguration
            self.edits = edits
            self.resultingItemCount = resultingItemCount
            self.persistenceByteCount = persistenceByteCount
            self.workPerformed = workPerformed
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.PlanningReceipt(decision: \(decision.rawValue), disposition: \(disposition.rawValue), edits: \(edits.count), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "decision": decision,
                    "disposition": disposition,
                    "expectedConfiguration": expectedConfiguration,
                    "resultingConfiguration": resultingConfiguration,
                    "editCount": edits.count,
                    "resultingItemCount": resultingItemCount,
                    "persistenceByteCount": persistenceByteCount as Any,
                    "workPerformed": workPerformed,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Exact canonical bytes from `ToolbarConfiguration.encodedData()`. Revision is out-of-band.
    public struct CanonicalPersistence: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let reference: ConfigurationReference
        public let data: Data

        fileprivate init(reference: ConfigurationReference, data: Data) {
            self.reference = reference
            self.data = data
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.CanonicalPersistence(revision: \(reference.revision.rawValue), bytes: \(data.count), data: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "reference": reference,
                    "byteCount": data.count,
                    "data": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Successor configuration and persistence bytes form one indivisible replacement value.
    public struct AtomicReplacement: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let successor: Snapshot
        public let persistence: CanonicalPersistence

        fileprivate init(successor: Snapshot, persistence: CanonicalPersistence) {
            self.successor = successor
            self.persistence = persistence
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.AtomicReplacement(revision: \(successor.revision.rawValue), configuration: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "successor": successor.reference,
                    "persistenceByteCount": persistence.data.count,
                    "configuration": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum PlannedOperation: Equatable, Sendable {
        case none
        case replace(AtomicReplacement)
    }

    public enum ExecutorCASContract: String, Codable, Hashable, Sendable {
        case compareExactIdentityRevisionConfigurationPolicyAndLimits
    }

    public enum ExecutorReplacementContract: String, Codable, Hashable, Sendable {
        case replaceSuccessorAndCanonicalBytesAtomicallyOnce
    }

    public enum ExecutorCancellationContract: String, Codable, Hashable, Sendable {
        case successfulCancellationCheckImmediatelyBeforeReplacementIsCommitPoint
    }

    public enum ExecutorUIContract: String, Codable, Hashable, Sendable {
        case noNativeToolbarCustomizationUIIsCreatedOrVerified
    }

    /// Mandatory boundary for alternate executors. `Store` is the in-memory reference authority.
    public struct ExecutorContract: Codable, Equatable, Hashable, Sendable {
        public static let required = ExecutorContract()

        public let cas: ExecutorCASContract
        public let replacement: ExecutorReplacementContract
        public let cancellation: ExecutorCancellationContract
        public let ui: ExecutorUIContract

        public init() {
            cas = .compareExactIdentityRevisionConfigurationPolicyAndLimits
            replacement = .replaceSuccessorAndCanonicalBytesAtomicallyOnce
            cancellation = .successfulCancellationCheckImmediatelyBeforeReplacementIsCommitPoint
            ui = .noNativeToolbarCustomizationUIIsCreatedOrVerified
        }
    }

    public struct Plan: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let expectedConfigurationCAS: ConfigurationCAS
        public let operation: PlannedOperation
        public let receipt: PlanningReceipt
        public let executorContract: ExecutorContract

        fileprivate init(
            expectedConfigurationCAS: ConfigurationCAS,
            operation: PlannedOperation,
            receipt: PlanningReceipt
        ) {
            self.expectedConfigurationCAS = expectedConfigurationCAS
            self.operation = operation
            self.receipt = receipt
            executorContract = .required
        }

        public var successor: Snapshot? {
            guard case .replace(let replacement) = operation else { return nil }
            return replacement.successor
        }

        public var canonicalPersistence: CanonicalPersistence? {
            guard case .replace(let replacement) = operation else { return nil }
            return replacement.persistence
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.Plan(disposition: \(receipt.disposition.rawValue), expectedRevision: \(expectedConfigurationCAS.reference.revision.rawValue), operation: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "expectedConfiguration": expectedConfigurationCAS.reference,
                    "receipt": receipt,
                    "executorContract": executorContract,
                    "operation": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        /// Apply and unchanged plans require exact currency. Cancel plans never authorize mutation.
        public func validateCurrentSnapshot(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws {
            guard receipt.decision == .apply else { return }
            try expectedConfigurationCAS.validate(
                snapshot,
                cancellationCheck: cancellationCheck
            )
        }
    }

    public struct ExecutionReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let planningReceipt: PlanningReceipt
        public let disposition: Disposition
        public let finalConfiguration: ConfigurationReference
        /// Present only when this execution performed the planned atomic replacement.
        public let canonicalPersistence: CanonicalPersistence?

        fileprivate init(
            plan: Plan,
            disposition: Disposition,
            finalConfiguration: ConfigurationReference,
            canonicalPersistence: CanonicalPersistence?
        ) {
            planningReceipt = plan.receipt
            self.disposition = disposition
            self.finalConfiguration = finalConfiguration
            self.canonicalPersistence = canonicalPersistence
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.ExecutionReceipt(disposition: \(disposition.rawValue), finalRevision: \(finalConfiguration.revision.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "disposition": disposition,
                    "finalConfiguration": finalConfiguration,
                    "persistenceByteCount": canonicalPersistence?.data.count as Any,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum ExecutionOutcome: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case applied(ExecutionReceipt)
        case unchanged(ExecutionReceipt)
        case cancelled(ExecutionReceipt)

        public var receipt: ExecutionReceipt {
            switch self {
            case .applied(let receipt), .unchanged(let receipt), .cancelled(let receipt):
                receipt
            }
        }

        public var disposition: Disposition { receipt.disposition }

        public var description: String {
            "ToolbarCustomizationWorkflow.ExecutionOutcome(disposition: \(disposition.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "disposition": disposition,
                    "finalConfiguration": receipt.finalConfiguration,
                    "details": "<redacted>"
                ],
                displayStyle: .enum
            )
        }
    }

    /// Actor-isolated, storage-neutral reference authority. It performs no AppKit or filesystem I/O.
    public actor Store {
        private struct State: Sendable {
            let snapshot: Snapshot
            let persistence: CanonicalPersistence
        }

        private var state: State

        public init(
            identity: ConfigurationIdentity = ConfigurationIdentity(),
            revision: ConfigurationRevision = ConfigurationRevision(rawValue: 0),
            configuration: ToolbarConfiguration = .winMergeDefault,
            policy: Policy = .permissive,
            limits: Limits = .default,
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws {
            var budget = try WorkBudget(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try ToolbarCustomizationWorkflow.validate(
                configuration,
                policy: policy,
                limits: limits,
                budget: &budget
            )
            let data = try ToolbarCustomizationWorkflow.canonicalData(
                for: configuration,
                limits: limits,
                budget: &budget
            )
            try budget.finish()
            let snapshot = Snapshot(
                identity: identity,
                revision: revision,
                configuration: configuration,
                policy: policy,
                limits: limits
            )
            let persistence = CanonicalPersistence(
                reference: snapshot.reference,
                data: data
            )
            state = State(snapshot: snapshot, persistence: persistence)
        }

        public init(
            canonicalConfigurationData: Data,
            identity: ConfigurationIdentity = ConfigurationIdentity(),
            revision: ConfigurationRevision = ConfigurationRevision(rawValue: 0),
            policy: Policy = .permissive,
            limits: Limits = .default,
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws {
            let snapshot = try ToolbarCustomizationWorkflow.restoreSnapshot(
                from: canonicalConfigurationData,
                identity: identity,
                revision: revision,
                policy: policy,
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            state = State(
                snapshot: snapshot,
                persistence: CanonicalPersistence(
                    reference: snapshot.reference,
                    data: canonicalConfigurationData
                )
            )
        }

        public func snapshot() -> Snapshot { state.snapshot }

        public func canonicalPersistence() -> CanonicalPersistence {
            state.persistence
        }

        /// Successful cancellation sampling is the commit point. Actor isolation keeps this check
        /// and the indivisible state replacement in one turn; later cancellation does not roll it back.
        private func commitReplacement(
            _ replacement: AtomicReplacement,
            cancellationCheck: CancellationCheck
        ) throws {
            guard !cancellationCheck() else { throw WorkflowError.cancelled }
            state = State(
                snapshot: replacement.successor,
                persistence: replacement.persistence
            )
        }

        /// Planning and commit run without suspension, so no intermediate draft is observable.
        public func finish(
            _ transaction: Transaction,
            decision: Decision,
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws -> ExecutionOutcome {
            let plan = try ToolbarCustomizationWorkflow.plan(
                transaction,
                decision: decision,
                in: state.snapshot,
                cancellationCheck: cancellationCheck
            )
            switch plan.operation {
            case .none:
                guard !cancellationCheck() else { throw WorkflowError.cancelled }
                let receipt = ExecutionReceipt(
                    plan: plan,
                    disposition: decision == .cancel ? .cancelled : .unchanged,
                    finalConfiguration: state.snapshot.reference,
                    canonicalPersistence: nil
                )
                return decision == .cancel ? .cancelled(receipt) : .unchanged(receipt)
            case .replace(let replacement):
                try commitReplacement(
                    replacement,
                    cancellationCheck: cancellationCheck
                )
                return .applied(
                    ExecutionReceipt(
                        plan: plan,
                        disposition: .applied,
                        finalConfiguration: replacement.successor.reference,
                        canonicalPersistence: replacement.persistence
                    )
                )
            }
        }

        /// Commits a previously created plan or rejects it when another edit won the CAS.
        public func commit(
            _ plan: Plan,
            cancellationCheck: @escaping CancellationCheck = {
                Task<Never, Never>.isCancelled
            }
        ) throws -> ExecutionOutcome {
            guard !cancellationCheck() else { throw WorkflowError.cancelled }

            if plan.receipt.decision == .cancel {
                return .cancelled(
                    ExecutionReceipt(
                        plan: plan,
                        disposition: .cancelled,
                        finalConfiguration: state.snapshot.reference,
                        canonicalPersistence: nil
                    )
                )
            }

            try plan.expectedConfigurationCAS.validate(
                state.snapshot,
                cancellationCheck: cancellationCheck
            )
            switch plan.operation {
            case .none:
                return .unchanged(
                    ExecutionReceipt(
                        plan: plan,
                        disposition: .unchanged,
                        finalConfiguration: state.snapshot.reference,
                        canonicalPersistence: nil
                    )
                )
            case .replace(let replacement):
                try commitReplacement(
                    replacement,
                    cancellationCheck: cancellationCheck
                )
                return .applied(
                    ExecutionReceipt(
                        plan: plan,
                        disposition: .applied,
                        finalConfiguration: replacement.successor.reference,
                        canonicalPersistence: replacement.persistence
                    )
                )
            }
        }
    }

    /// Exact `ToolbarConfiguration.layout` result bound to the configuration CAS used to create it.
    public struct OverflowPreview: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let expectedConfiguration: ConfigurationCAS
        public let layout: ToolbarConfiguration.Layout
        public let workPerformed: Int

        fileprivate init(
            expectedConfiguration: ConfigurationCAS,
            layout: ToolbarConfiguration.Layout,
            workPerformed: Int
        ) {
            self.expectedConfiguration = expectedConfiguration
            self.layout = layout
            self.workPerformed = workPerformed
        }

        public var visibleItems: [Item] { layout.visibleItems }
        public var overflowItems: [Item] { layout.overflowItems }
        public var showsOverflowControl: Bool { layout.showsOverflowButton }

        public var description: String {
            "ToolbarCustomizationWorkflow.OverflowPreview(visible: \(layout.visibleItems.count), overflow: \(layout.overflowItems.count), items: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "expectedConfiguration": expectedConfiguration.reference,
                    "visibleItemCount": layout.visibleItems.count,
                    "overflowItemCount": layout.overflowItems.count,
                    "showsOverflowControl": layout.showsOverflowButton,
                    "workPerformed": workPerformed,
                    "items": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Dynamic command capability from shared menu/toolbar command policy, not native UI evidence.
    public struct CommandCapabilityBinding: Equatable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let command: Command
        public let semanticCommand: ComparisonCommandState.Identifier
        public let configuredItemIndex: Int?
        public let isRequired: Bool
        public let resolution: ComparisonCommandState.Resolution

        fileprivate init(
            command: Command,
            configuredItemIndex: Int?,
            isRequired: Bool,
            resolution: ComparisonCommandState.Resolution
        ) {
            self.command = command
            semanticCommand = ComparisonCommandState.Identifier(command)
            self.configuredItemIndex = configuredItemIndex
            self.isRequired = isRequired
            self.resolution = resolution
        }

        public var isIncludedInConfiguration: Bool { configuredItemIndex != nil }
        public var availability: ComparisonCommandState.Availability { resolution.availability }
        public var canExecuteSemantically: Bool { resolution.canExecute }

        public var description: String {
            "ToolbarCustomizationWorkflow.CommandCapabilityBinding(command: \(command.rawValue), included: \(isIncludedInConfiguration), semanticState: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "command": command,
                    "configuredItemIndex": configuredItemIndex as Any,
                    "isRequired": isRequired,
                    "semanticState": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct CommandCapabilityPlan: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public static let scopeStatement = ToolbarCustomizationWorkflow.capabilityScopeStatement

        public let expectedConfiguration: ConfigurationCAS
        /// Stable `ToolbarConfiguration.Command.allCases` order.
        public let bindings: [CommandCapabilityBinding]
        public let workPerformed: Int

        fileprivate init(
            expectedConfiguration: ConfigurationCAS,
            bindings: [CommandCapabilityBinding],
            workPerformed: Int
        ) {
            self.expectedConfiguration = expectedConfiguration
            self.bindings = bindings
            self.workPerformed = workPerformed
        }

        public func binding(for command: Command) -> CommandCapabilityBinding? {
            bindings.first { $0.command == command }
        }

        public var description: String {
            "ToolbarCustomizationWorkflow.CommandCapabilityPlan(bindings: \(bindings.count), semanticState: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "expectedConfiguration": expectedConfiguration.reference,
                    "bindingCount": bindings.count,
                    "workPerformed": workPerformed,
                    "semanticState": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public static func validate(
        _ configuration: ToolbarConfiguration,
        policy: Policy = .permissive,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            Task<Never, Never>.isCancelled
        }
    ) throws {
        var budget = try WorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try validate(
            configuration,
            policy: policy,
            limits: limits,
            budget: &budget
        )
        try budget.finish()
    }

    /// Plans all edits against a private candidate. Any failure discards the complete candidate.
    public static func plan(
        _ transaction: Transaction,
        decision: Decision,
        in snapshot: Snapshot,
        cancellationCheck: @escaping CancellationCheck = {
            Task<Never, Never>.isCancelled
        }
    ) throws -> Plan {
        var budget = try WorkBudget(
            limits: snapshot.limits,
            cancellationCheck: cancellationCheck
        )
        if decision == .cancel {
            try budget.finish()
            return Plan(
                expectedConfigurationCAS: transaction.expectedConfiguration,
                operation: .none,
                receipt: PlanningReceipt(
                    decision: .cancel,
                    disposition: .cancelled,
                    expectedConfiguration: transaction.expectedConfiguration.reference,
                    observedConfiguration: snapshot.reference,
                    resultingConfiguration: snapshot.reference,
                    edits: [],
                    resultingItemCount: snapshot.configuration.items.count,
                    persistenceByteCount: nil,
                    workPerformed: budget.consumed
                )
            )
        }

        guard transaction.edits.count <= snapshot.limits.maximumTransactionEditCount else {
            throw WorkflowError.tooManyTransactionEdits(
                maximum: snapshot.limits.maximumTransactionEditCount
            )
        }
        try budget.consume(transaction.edits.count)

        try transaction.expectedConfiguration.validate(snapshot, budget: &budget)
        var candidate = snapshot.configuration
        var editReceipts: [EditReceipt] = []
        editReceipts.reserveCapacity(transaction.edits.count)
        for (index, edit) in transaction.edits.enumerated() {
            try apply(edit, to: &candidate, budget: &budget)
            editReceipts.append(
                EditReceipt(
                    editIndex: index,
                    edit: edit,
                    resultingItemCount: candidate.items.count
                )
            )
        }
        try validate(
            candidate,
            policy: snapshot.policy,
            limits: snapshot.limits,
            budget: &budget
        )

        guard candidate != snapshot.configuration else {
            try budget.finish()
            return Plan(
                expectedConfigurationCAS: transaction.expectedConfiguration,
                operation: .none,
                receipt: PlanningReceipt(
                    decision: .apply,
                    disposition: .unchanged,
                    expectedConfiguration: transaction.expectedConfiguration.reference,
                    observedConfiguration: snapshot.reference,
                    resultingConfiguration: snapshot.reference,
                    edits: editReceipts,
                    resultingItemCount: candidate.items.count,
                    persistenceByteCount: nil,
                    workPerformed: budget.consumed
                )
            )
        }
        guard let nextRevision = snapshot.revision.successor else {
            throw WorkflowError.revisionExhausted
        }

        let successor = Snapshot(
            identity: snapshot.identity,
            revision: nextRevision,
            configuration: candidate,
            policy: snapshot.policy,
            limits: snapshot.limits
        )
        let data = try canonicalData(
            for: candidate,
            limits: snapshot.limits,
            budget: &budget
        )
        let persistence = CanonicalPersistence(
            reference: successor.reference,
            data: data
        )
        let replacement = AtomicReplacement(
            successor: successor,
            persistence: persistence
        )
        try budget.finish()
        return Plan(
            expectedConfigurationCAS: transaction.expectedConfiguration,
            operation: .replace(replacement),
            receipt: PlanningReceipt(
                decision: .apply,
                disposition: .replacementPlanned,
                expectedConfiguration: transaction.expectedConfiguration.reference,
                observedConfiguration: snapshot.reference,
                resultingConfiguration: successor.reference,
                edits: editReceipts,
                resultingItemCount: candidate.items.count,
                persistenceByteCount: data.count,
                workPerformed: budget.consumed
            )
        )
    }

    /// Uses `ToolbarConfiguration.layout` directly, preserving its separator and hidden-size rules.
    public static func previewOverflow(
        in snapshot: Snapshot,
        availableWidth: Double,
        metrics: ToolbarConfiguration.LayoutMetrics? = nil,
        cancellationCheck: @escaping CancellationCheck = {
            Task<Never, Never>.isCancelled
        }
    ) throws -> OverflowPreview {
        var budget = try WorkBudget(
            limits: snapshot.limits,
            cancellationCheck: cancellationCheck
        )
        try budget.consume(snapshot.configuration.items.count)
        if let metrics { try budget.consume(metrics.commandWidths.count) }
        let layout: ToolbarConfiguration.Layout
        do {
            layout = try snapshot.configuration.layout(
                availableWidth: availableWidth,
                metrics: metrics
            )
        } catch let error as ToolbarConfigurationError {
            throw WorkflowError.overflowPreview(error)
        } catch {
            throw WorkflowError.overflowPreview(.invalidAvailableWidth)
        }
        try budget.finish()
        return OverflowPreview(
            expectedConfiguration: snapshot.cas,
            layout: layout,
            workPerformed: budget.consumed
        )
    }

    /// Binds each persisted toolbar identity to shared `ComparisonCommandState` semantics.
    public static func bindCommandCapabilities(
        in snapshot: Snapshot,
        context: ComparisonCommandState.Context,
        cancellationCheck: @escaping CancellationCheck = {
            Task<Never, Never>.isCancelled
        }
    ) throws -> CommandCapabilityPlan {
        var budget = try WorkBudget(
            limits: snapshot.limits,
            cancellationCheck: cancellationCheck
        )
        var configuredIndices: [Command: Int] = [:]
        configuredIndices.reserveCapacity(snapshot.configuration.commands.count)
        for (index, item) in snapshot.configuration.items.enumerated() {
            try budget.consume()
            guard case .command(let command) = item else { continue }
            configuredIndices[command] = index
        }

        var bindings: [CommandCapabilityBinding] = []
        bindings.reserveCapacity(Command.allCases.count)
        for command in Command.allCases {
            try budget.consume()
            bindings.append(
                CommandCapabilityBinding(
                    command: command,
                    configuredItemIndex: configuredIndices[command],
                    isRequired: snapshot.policy.requiredCommands.contains(command),
                    resolution: ComparisonCommandState.resolveToolbarCommand(
                        command,
                        in: context
                    )
                )
            )
        }
        try budget.finish()
        return CommandCapabilityPlan(
            expectedConfiguration: snapshot.cas,
            bindings: bindings,
            workPerformed: budget.consumed
        )
    }

    /// Restores only canonical bytes produced by authoritative `ToolbarConfiguration.encodedData()`.
    public static func restoreSnapshot(
        from data: Data,
        identity: ConfigurationIdentity = ConfigurationIdentity(),
        revision: ConfigurationRevision = ConfigurationRevision(rawValue: 0),
        policy: Policy = .permissive,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            Task<Never, Never>.isCancelled
        }
    ) throws -> Snapshot {
        var budget = try WorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        guard data.count <= limits.maximumPersistenceBytes else {
            throw WorkflowError.persistenceTooLarge(
                maximumBytes: limits.maximumPersistenceBytes
            )
        }
        try budget.consume(data.count)
        let configuration: ToolbarConfiguration
        do {
            configuration = try ToolbarConfiguration.decode(from: data)
        } catch let error as ToolbarConfigurationError {
            throw WorkflowError.invalidConfiguration(error)
        } catch {
            throw WorkflowError.malformedPersistence
        }
        try validate(
            configuration,
            policy: policy,
            limits: limits,
            budget: &budget
        )
        let canonical = try canonicalData(
            for: configuration,
            limits: limits,
            budget: &budget
        )
        guard canonical == data else { throw WorkflowError.nonCanonicalPersistence }
        try budget.finish()
        return Snapshot(
            identity: identity,
            revision: revision,
            configuration: configuration,
            policy: policy,
            limits: limits
        )
    }

    fileprivate struct WorkBudget {
        let maximum: Int
        let cancellationCheckInterval: Int
        let cancellationCheck: CancellationCheck
        private(set) var consumed = 0
        private var nextCancellationCheck = 0

        init(
            limits: Limits,
            cancellationCheck: @escaping CancellationCheck
        ) throws {
            try limits.validate()
            maximum = limits.maximumWorkUnits
            cancellationCheckInterval = limits.cancellationCheckInterval
            self.cancellationCheck = cancellationCheck
            nextCancellationCheck = limits.cancellationCheckInterval
            guard !cancellationCheck() else { throw WorkflowError.cancelled }
        }

        mutating func consume(_ units: Int = 1) throws {
            try charge(units, checkingCancellation: false)
        }

        mutating func precharge(_ units: Int) throws {
            try charge(units, checkingCancellation: true)
        }

        private mutating func charge(
            _ units: Int,
            checkingCancellation: Bool
        ) throws {
            guard units >= 0 else { throw WorkflowError.arithmeticOverflow }
            let (value, overflow) = consumed.addingReportingOverflow(units)
            guard !overflow else { throw WorkflowError.arithmeticOverflow }
            guard value <= maximum else {
                throw WorkflowError.workLimitExceeded(maximum: maximum)
            }
            if checkingCancellation || value >= nextCancellationCheck {
                consumed = value
                guard !cancellationCheck() else { throw WorkflowError.cancelled }
                let (next, nextOverflow) = value.addingReportingOverflow(
                    cancellationCheckInterval
                )
                nextCancellationCheck = nextOverflow ? .max : next
            }
            consumed = value
        }

        mutating func finish() throws {
            guard !cancellationCheck() else { throw WorkflowError.cancelled }
        }
    }

    private static func validate(
        _ configuration: ToolbarConfiguration,
        policy: Policy,
        limits: Limits,
        budget: inout WorkBudget
    ) throws {
        guard policy.requiredCommands.count <= limits.maximumRequiredCommandCount else {
            throw WorkflowError.tooManyRequiredCommands(
                maximum: limits.maximumRequiredCommandCount
            )
        }
        guard configuration.items.count <= limits.maximumItemCount else {
            throw WorkflowError.tooManyItems(maximum: limits.maximumItemCount)
        }

        var commands: Set<Command> = []
        commands.reserveCapacity(configuration.commands.count)
        for item in configuration.items {
            try budget.consume()
            guard case .command(let command) = item else { continue }
            guard commands.insert(command).inserted else {
                throw WorkflowError.duplicateCommand(command)
            }
        }
        for command in policy.canonicalRequiredCommands {
            try budget.consume()
            guard commands.contains(command) else {
                throw WorkflowError.requiredCommandMissing(command)
            }
        }
        do {
            try configuration.validate()
        } catch let error as ToolbarConfigurationError {
            throw mapConfigurationError(error)
        } catch {
            throw WorkflowError.malformedPersistence
        }
    }

    private static func canonicalData(
        for configuration: ToolbarConfiguration,
        limits: Limits,
        budget: inout WorkBudget
    ) throws -> Data {
        let expectedByteCount = try canonicalEncodedByteCount(for: configuration)
        guard expectedByteCount <= limits.maximumPersistenceBytes else {
            throw WorkflowError.persistenceTooLarge(
                maximumBytes: limits.maximumPersistenceBytes
            )
        }
        try budget.precharge(expectedByteCount)

        let data: Data
        do {
            data = try configuration.encodedData()
        } catch let error as ToolbarConfigurationError {
            throw mapConfigurationError(error)
        } catch {
            throw WorkflowError.malformedPersistence
        }
        guard data.count == expectedByteCount else { throw WorkflowError.malformedPersistence }
        return data
    }

    /// Exact byte count for `ToolbarConfiguration.encodedData()`'s compact, sorted-key JSON wire form.
    private static func canonicalEncodedByteCount(
        for configuration: ToolbarConfiguration
    ) throws -> Int {
        var byteCount = #"{"items":[],"schemaVersion":,"size":"","visibility":""}"#.utf8.count

        func add(_ count: Int) throws {
            let (value, overflow) = byteCount.addingReportingOverflow(count)
            guard !overflow else { throw WorkflowError.arithmeticOverflow }
            byteCount = value
        }

        try add(String(configuration.schemaVersion).utf8.count)
        try add(configuration.size.rawValue.utf8.count)
        try add(configuration.visibility.rawValue.utf8.count)
        for (index, item) in configuration.items.enumerated() {
            if index > 0 { try add(1) }
            try add(2)
            switch item {
            case .command(let command):
                try add(command.rawValue.utf8.count)
            case .separator:
                try add("separator".utf8.count)
            }
        }
        return byteCount
    }

    private static func apply(
        _ edit: Edit,
        to candidate: inout ToolbarConfiguration,
        budget: inout WorkBudget
    ) throws {
        try budget.consume()
        do {
            switch edit {
            case .setVisibility(let visibility):
                candidate.visibility = visibility
            case .setSize(let size):
                candidate.size = size
            case .addCommand(let command, let index):
                try budget.consume(candidate.items.count)
                try candidate.insert(.command(command), at: index)
            case .addSeparator(let index):
                try budget.consume(candidate.items.count)
                try candidate.insert(.separator, at: index)
            case .removeCommand(let command):
                var foundIndex: Int?
                for (index, item) in candidate.items.enumerated() {
                    try budget.consume()
                    if item == .command(command) {
                        foundIndex = index
                        break
                    }
                }
                guard let foundIndex else {
                    throw WorkflowError.commandNotPresent(command)
                }
                try budget.consume(candidate.items.count)
                _ = try candidate.removeItem(at: foundIndex)
            case .removeCommandAt(let index):
                guard candidate.items.indices.contains(index) else {
                    throw WorkflowError.invalidItemIndex(index)
                }
                guard case .command = candidate.items[index] else {
                    throw WorkflowError.expectedCommand(at: index)
                }
                try budget.consume(candidate.items.count)
                _ = try candidate.removeItem(at: index)
            case .removeSeparator(let index):
                guard candidate.items.indices.contains(index) else {
                    throw WorkflowError.invalidItemIndex(index)
                }
                guard candidate.items[index] == .separator else {
                    throw WorkflowError.expectedSeparator(at: index)
                }
                try budget.consume(candidate.items.count)
                _ = try candidate.removeItem(at: index)
            case .removeItem(let index):
                try budget.consume(candidate.items.count)
                _ = try candidate.removeItem(at: index)
            case .moveItem(let sourceIndex, let destinationIndex):
                try budget.consume(candidate.items.count)
                try candidate.moveItem(
                    from: sourceIndex,
                    to: destinationIndex
                )
            case .resetToWinMergeDefaults:
                try budget.consume(ToolbarConfiguration.winMergeDefaultItems.count)
                candidate.resetToWinMergeDefaults()
            }
        } catch let error as WorkflowError {
            throw error
        } catch let error as ToolbarConfigurationError {
            throw mapConfigurationError(error)
        } catch {
            throw WorkflowError.malformedPersistence
        }
    }

    private static func mapConfigurationError(
        _ error: ToolbarConfigurationError
    ) -> WorkflowError {
        switch error {
        case .duplicateCommand(let command):
            .duplicateCommand(command)
        case .tooManyItems(let maximum):
            .tooManyItems(maximum: maximum)
        case .invalidItemIndex(let index):
            .invalidItemIndex(index)
        default:
            .invalidConfiguration(error)
        }
    }
}

public enum ToolbarCustomizationWorkflowError: Error, Equatable, LocalizedError, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public typealias Command = ToolbarCustomizationWorkflow.Command
    public typealias ConfigurationReference =
        ToolbarCustomizationWorkflow.ConfigurationReference
    public typealias Limit = ToolbarCustomizationWorkflow.Limit

    case cancelled
    case invalidLimit(Limit, value: Int)
    case tooManyItems(maximum: Int)
    case tooManyRequiredCommands(maximum: Int)
    case tooManyTransactionEdits(maximum: Int)
    case duplicateCommand(Command)
    case requiredCommandMissing(Command)
    case commandNotPresent(Command)
    case invalidItemIndex(Int)
    case expectedCommand(at: Int)
    case expectedSeparator(at: Int)
    case revisionExhausted
    case staleConfiguration(expected: ConfigurationReference, actual: ConfigurationReference)
    case configurationChangedWithoutRevision(ConfigurationReference)
    case persistenceTooLarge(maximumBytes: Int)
    case malformedPersistence
    case nonCanonicalPersistence
    case workLimitExceeded(maximum: Int)
    case arithmeticOverflow
    case invalidConfiguration(ToolbarConfigurationError)
    case overflowPreview(ToolbarConfigurationError)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Toolbar customization was cancelled."
        case .invalidLimit(let limit, let value):
            "Toolbar customization limit \(limit.rawValue) is invalid (\(value))."
        case .tooManyItems(let maximum):
            "Toolbar customization exceeds the \(maximum)-item limit."
        case .tooManyRequiredCommands(let maximum):
            "Toolbar customization exceeds the \(maximum)-required-command limit."
        case .tooManyTransactionEdits(let maximum):
            "Toolbar customization transaction exceeds the \(maximum)-edit limit."
        case .duplicateCommand(let command):
            "Toolbar command appears more than once: \(command.rawValue)."
        case .requiredCommandMissing(let command):
            "Required toolbar command is missing: \(command.rawValue)."
        case .commandNotPresent(let command):
            "Toolbar command is not present: \(command.rawValue)."
        case .invalidItemIndex(let index):
            "Toolbar item index is invalid: \(index)."
        case .expectedCommand(let index):
            "Toolbar item at index \(index) is not a command."
        case .expectedSeparator(let index):
            "Toolbar item at index \(index) is not a separator."
        case .revisionExhausted:
            "Toolbar configuration revision is exhausted."
        case .staleConfiguration:
            "Toolbar configuration changed concurrently."
        case .configurationChangedWithoutRevision:
            "Toolbar configuration contents changed without advancing its revision."
        case .persistenceTooLarge(let maximumBytes):
            "Toolbar configuration persistence exceeds \(maximumBytes) bytes."
        case .malformedPersistence:
            "Toolbar configuration persistence is malformed."
        case .nonCanonicalPersistence:
            "Toolbar configuration persistence is not canonical."
        case .workLimitExceeded(let maximum):
            "Toolbar customization exceeds the \(maximum)-unit work limit."
        case .arithmeticOverflow:
            "Toolbar customization work accounting overflowed."
        case .invalidConfiguration:
            "Toolbar configuration violates the authoritative configuration contract."
        case .overflowPreview:
            "Toolbar overflow preview inputs are invalid."
        }
    }

    public var description: String {
        errorDescription ?? "Toolbar customization failed."
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "description": description,
                "details": "<redacted>"
            ],
            displayStyle: .enum
        )
    }
}

extension ToolbarCustomizationWorkflow {
    public typealias WorkflowError = ToolbarCustomizationWorkflowError
}
