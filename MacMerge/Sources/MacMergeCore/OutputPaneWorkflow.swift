import Foundation

/// UI-independent, bounded planning for output-pane state and side effects.
public enum OutputPaneWorkflow: Sendable {
    public typealias EntryID = OutputPaneLog.Entry.ID

    public struct LogIdentity: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }

        public static func < (left: LogIdentity, right: LogIdentity) -> Bool {
            left.rawValue.uuidString < right.rawValue.uuidString
        }
    }

    public struct SnapshotReference: Codable, Equatable, Hashable, Sendable {
        public let identity: LogIdentity
        public let revision: UInt64

        public init(identity: LogIdentity, revision: UInt64) {
            self.identity = identity
            self.revision = revision
        }

        public init(_ snapshot: Snapshot) {
            identity = snapshot.identity
            revision = snapshot.revision
        }
    }

    public enum Visibility: String, CaseIterable, Codable, Hashable, Sendable {
        case hidden
        case visible
    }

    public enum VisibilityPersistence: String, CaseIterable, Codable, Hashable, Sendable {
        case sessionOnly
        case persisted
    }

    public struct VisibilityPreference: Codable, Hashable, Sendable {
        public static let `default` = VisibilityPreference()

        public let visibility: Visibility
        public let persistence: VisibilityPersistence

        public init(
            visibility: Visibility = .hidden,
            persistence: VisibilityPersistence = .sessionOnly
        ) {
            self.visibility = visibility
            self.persistence = persistence
        }

        public init(restoring persisted: PersistedVisibilityPreference) throws {
            guard persisted.schemaVersion == PersistedVisibilityPreference.currentSchemaVersion else {
                throw WorkflowError.unsupportedPreferenceSchemaVersion(persisted.schemaVersion)
            }
            visibility = persisted.visibility
            persistence = .persisted
        }
    }

    /// Storage-neutral value. Presence in storage means visibility persistence is enabled.
    public struct PersistedVisibilityPreference: Codable, Hashable, Sendable {
        public static let currentSchemaVersion = 1

        public let schemaVersion: Int
        public let visibility: Visibility

        public init(visibility: Visibility) {
            schemaVersion = Self.currentSchemaVersion
            self.visibility = visibility
        }

        public init(schemaVersion: Int, visibility: Visibility) {
            self.schemaVersion = schemaVersion
            self.visibility = visibility
        }
    }

    public enum MessageSensitivity: String, CaseIterable, Codable, Hashable, Sendable {
        case standard
        case securitySensitive
    }

    public enum SensitiveCopyPolicy: String, CaseIterable, Codable, Hashable, Sendable {
        /// Any copy scope containing sensitive messages is disabled.
        case deny
        /// Each sensitive message is replaced by `redactionMarker`.
        case redact
        /// Raw sensitive text requires an explicit authorization on each copy intent.
        case requireExplicitAuthorization
    }

    public struct SeverityMask: OptionSet, Codable, Hashable, Sendable {
        public static let debug = SeverityMask(rawValue: 1 << 0)
        public static let info = SeverityMask(rawValue: 1 << 1)
        public static let warning = SeverityMask(rawValue: 1 << 2)
        public static let error = SeverityMask(rawValue: 1 << 3)
        public static let all: SeverityMask = [.debug, .info, .warning, .error]

        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public func contains(_ severity: OutputPaneLog.Severity) -> Bool {
            let mask: SeverityMask
            switch severity {
            case .debug: mask = .debug
            case .info: mask = .info
            case .warning: mask = .warning
            case .error: mask = .error
            }
            return rawValue & mask.rawValue != 0
        }
    }

    public struct Filter: Codable, Hashable, Sendable {
        public static let all = Filter()

        public let severities: SeverityMask
        public let text: String?
        public let caseSensitive: Bool

        public init(
            severities: SeverityMask = .all,
            text: String? = nil,
            caseSensitive: Bool = false
        ) {
            self.severities = severities
            self.text = text
            self.caseSensitive = caseSensitive
        }

        public var isUnfiltered: Bool {
            severities == .all && (text?.isEmpty ?? true)
        }
    }

    public enum Limit: String, CaseIterable, Codable, Hashable, Sendable {
        case retainedItems
        case selectedItems
        case appendText
        case retainedText
        case filterText
        case copyText
        case workUnits
        case aggregateWorkUnits
        case cancellationCheckInterval
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumRetainedItemCount = 100_000
        public static let hardMaximumSelectedItemCount = 100_000
        /// `OutputPaneLog.append` has no cancellation callback, so workflow admission keeps its
        /// sanitization pass inside a fixed request-independent atomic envelope.
        public static let hardMaximumAppendUTF8Bytes = 1 * 1_024 * 1_024
        public static let hardMaximumRetainedUTF8Bytes = 8 * 1_024 * 1_024
        public static let hardMaximumFilterUTF8Bytes = 64 * 1_024
        public static let hardMaximumCopyUTF8Bytes = 16 * 1_024 * 1_024
        public static let hardMaximumWorkUnits: UInt64 = 1 << 40
        public static let hardMaximumCancellationCheckInterval: UInt64 = 1 * 1_024 * 1_024
        public static let `default` = Limits()

        public let maximumRetainedItemCount: Int
        public let maximumSelectedItemCount: Int
        public let maximumAppendUTF8Bytes: Int
        public let maximumRetainedUTF8Bytes: Int
        public let maximumFilterUTF8Bytes: Int
        public let maximumCopyUTF8Bytes: Int
        public let maximumWorkUnits: UInt64
        public let maximumAggregateWorkUnits: UInt64
        public let cancellationCheckInterval: UInt64

        public init(
            maximumRetainedItemCount: Int = OutputPaneLog.Limits.defaultMaximumEntryCount,
            maximumSelectedItemCount: Int = OutputPaneLog.Limits.defaultMaximumEntryCount,
            maximumAppendUTF8Bytes: Int = 1 * 1_024 * 1_024,
            maximumRetainedUTF8Bytes: Int = OutputPaneLog.Limits.defaultMaximumUTF8Bytes,
            maximumFilterUTF8Bytes: Int = 16 * 1_024,
            maximumCopyUTF8Bytes: Int = 16 * 1_024 * 1_024,
            maximumWorkUnits: UInt64 = 256 * 1_024 * 1_024,
            maximumAggregateWorkUnits: UInt64 = 1 * 1_024 * 1_024 * 1_024,
            cancellationCheckInterval: UInt64 = 64 * 1_024
        ) {
            self.maximumRetainedItemCount = maximumRetainedItemCount
            self.maximumSelectedItemCount = maximumSelectedItemCount
            self.maximumAppendUTF8Bytes = maximumAppendUTF8Bytes
            self.maximumRetainedUTF8Bytes = maximumRetainedUTF8Bytes
            self.maximumFilterUTF8Bytes = maximumFilterUTF8Bytes
            self.maximumCopyUTF8Bytes = maximumCopyUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.maximumAggregateWorkUnits = maximumAggregateWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }
    }

    /// Immutable owner state. Owners must never reuse a revision for different state.
    public struct Snapshot: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let identity: LogIdentity
        public let revision: UInt64
        public let log: OutputPaneLog
        public let visibilityPreference: VisibilityPreference
        public let filter: Filter
        public let sensitiveCopyPolicy: SensitiveCopyPolicy
        public let securitySensitiveMessageIDs: Set<EntryID>
        public let visibleEntries: [OutputPaneLog.Entry]
        public let limits: Limits

        public init(
            identity: LogIdentity = LogIdentity(),
            revision: UInt64 = 0,
            log: OutputPaneLog = OutputPaneLog(),
            visibilityPreference: VisibilityPreference = .default,
            filter: Filter = .all,
            sensitiveCopyPolicy: SensitiveCopyPolicy = .redact,
            securitySensitiveMessageIDs: Set<EntryID> = [],
            limits: Limits = .default
        ) throws {
            do {
                var budget = try WorkBudget(limits: limits)
                self = try Self.validated(
                    identity: identity,
                    revision: revision,
                    log: log,
                    visibilityPreference: visibilityPreference,
                    filter: filter,
                    sensitiveCopyPolicy: sensitiveCopyPolicy,
                    securitySensitiveMessageIDs: securitySensitiveMessageIDs,
                    limits: limits,
                    budget: &budget
                )
                try budget.finish()
            } catch is CancellationError {
                throw WorkflowError.cancelled
            }
        }

        public var reference: SnapshotReference { SnapshotReference(self) }
        public var cas: SnapshotCAS { SnapshotCAS(snapshot: self) }
        public var isVisible: Bool { visibilityPreference.visibility == .visible }

        public var description: String {
            "OutputPaneWorkflow.Snapshot(identity: \(identity.rawValue), revision: \(revision), messages: \(log.entries.count), selected: \(log.selectedIDs.count), text: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "identity": identity,
                    "revision": revision,
                    "messageCount": log.entries.count,
                    "selectedMessageCount": log.selectedIDs.count,
                    "securitySensitiveMessageCount": securitySensitiveMessageIDs.count,
                    "text": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(identity)
            hasher.combine(revision)
            hasher.combine(log.limits.maximumEntryCount)
            hasher.combine(log.limits.maximumUTF8Bytes)
            for entry in log.entries {
                hasher.combine(entry.id)
                hasher.combine(entry.severity.rawValue)
                hasher.combine(entry.timestamp)
                hasher.combine(entry.text)
                hasher.combine(entry.utf8ByteCount)
                hasher.combine(entry.wasSanitized)
            }
            for id in log.selectedIDs.sorted() { hasher.combine(id) }
            hasher.combine(log.retainedUTF8ByteCount)
            hasher.combine(visibilityPreference)
            hasher.combine(filter)
            hasher.combine(sensitiveCopyPolicy)
            for id in securitySensitiveMessageIDs.sorted() { hasher.combine(id) }
            hasher.combine(limits)
        }

        public func entry(withID id: EntryID) -> OutputPaneLog.Entry? {
            log.entries.first { $0.id == id }
        }

        public func sensitivity(of id: EntryID) -> MessageSensitivity? {
            guard entry(withID: id) != nil else { return nil }
            return securitySensitiveMessageIDs.contains(id) ? .securitySensitive : .standard
        }

        fileprivate init(
            identity: LogIdentity,
            revision: UInt64,
            log: OutputPaneLog,
            visibilityPreference: VisibilityPreference,
            filter: Filter,
            sensitiveCopyPolicy: SensitiveCopyPolicy,
            securitySensitiveMessageIDs: Set<EntryID>,
            visibleEntries: [OutputPaneLog.Entry],
            limits: Limits
        ) {
            self.identity = identity
            self.revision = revision
            self.log = log
            self.visibilityPreference = visibilityPreference
            self.filter = filter
            self.sensitiveCopyPolicy = sensitiveCopyPolicy
            self.securitySensitiveMessageIDs = securitySensitiveMessageIDs
            self.visibleEntries = visibleEntries
            self.limits = limits
        }

        fileprivate static func validated(
            identity: LogIdentity,
            revision: UInt64,
            log: OutputPaneLog,
            visibilityPreference: VisibilityPreference,
            filter: Filter,
            sensitiveCopyPolicy: SensitiveCopyPolicy,
            securitySensitiveMessageIDs: Set<EntryID>,
            limits: Limits,
            budget: inout WorkBudget
        ) throws -> Snapshot {
            try validate(limits)
            guard log.limits.maximumEntryCount <= limits.maximumRetainedItemCount else {
                throw WorkflowError.incompatibleLogLimit(.retainedItems)
            }
            guard log.limits.maximumUTF8Bytes <= limits.maximumRetainedUTF8Bytes else {
                throw WorkflowError.incompatibleLogLimit(.retainedText)
            }
            guard log.entries.count <= limits.maximumRetainedItemCount else {
                throw WorkflowError.tooManyItems(maximum: limits.maximumRetainedItemCount)
            }
            guard log.selectedIDs.count <= limits.maximumSelectedItemCount else {
                throw WorkflowError.tooManySelectedItems(
                    maximum: limits.maximumSelectedItemCount
                )
            }
            guard log.retainedUTF8ByteCount <= limits.maximumRetainedUTF8Bytes else {
                throw WorkflowError.retainedTextTooLarge(
                    maximumUTF8Bytes: limits.maximumRetainedUTF8Bytes
                )
            }
            let filterUTF8ByteCount = try validate(filter, limits: limits, budget: &budget)
            let casWork = try requiredCASWorkUnits(
                log: log,
                sensitiveMessageCount: securitySensitiveMessageIDs.count,
                filterUTF8ByteCount: filterUTF8ByteCount
            )
            guard casWork <= limits.maximumWorkUnits else {
                throw WorkflowError.workLimitExceeded(maximumUnits: limits.maximumWorkUnits)
            }

            let retainedIDs = Set(log.entries.map(\.id))
            if let unknownID =
                securitySensitiveMessageIDs
                .subtracting(retainedIDs)
                .sorted()
                .first
            {
                throw WorkflowError.securityMetadataReferencesUnknownMessage(unknownID)
            }
            try budget.consume(items: log.entries.count)
            try budget.consume(items: securitySensitiveMessageIDs.count)

            let visibleEntries = try filteredEntries(
                in: log,
                filter: filter,
                budget: &budget
            )
            let visibleIDs = Set(visibleEntries.map(\.id))
            if let hiddenSelection = log.selectedIDs.subtracting(visibleIDs).sorted().first {
                throw WorkflowError.selectionReferencesFilteredMessage(hiddenSelection)
            }
            return Snapshot(
                identity: identity,
                revision: revision,
                log: log,
                visibilityPreference: visibilityPreference,
                filter: filter,
                sensitiveCopyPolicy: sensitiveCopyPolicy,
                securitySensitiveMessageIDs: securitySensitiveMessageIDs,
                visibleEntries: visibleEntries,
                limits: limits
            )
        }
    }

    /// Exact compare-and-swap expectation, including `OutputPaneLog`'s private next-ID state.
    public struct SnapshotCAS: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let reference: SnapshotReference
        private let snapshot: Snapshot

        fileprivate init(snapshot: Snapshot) {
            reference = snapshot.reference
            self.snapshot = snapshot
        }

        public var description: String {
            "OutputPaneWorkflow.SnapshotCAS(identity: \(reference.identity.rawValue), revision: \(reference.revision), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["reference": reference, "contents": "<redacted>"],
                displayStyle: .struct
            )
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(reference)
            hasher.combine(snapshot)
        }

        public func matches(_ current: Snapshot) throws -> Bool {
            do {
                try validate(current)
                return true
            } catch WorkflowError.staleLog, WorkflowError.logContentsChanged {
                return false
            }
        }

        public func validate(_ current: Snapshot) throws {
            do {
                try Task<Never, Never>.checkCancellation()
                guard current.reference == reference else {
                    try Task<Never, Never>.checkCancellation()
                    throw WorkflowError.staleLog(
                        expected: reference,
                        actual: current.reference
                    )
                }
                var budget = try WorkBudget(limits: snapshot.limits)
                let matches = try exactlyMatches(snapshot, current, budget: &budget)
                try budget.finish()
                guard matches else {
                    throw WorkflowError.logContentsChanged(reference)
                }
            } catch is CancellationError {
                throw WorkflowError.cancelled
            }
        }
    }

    public struct AppendIntent: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let severity: OutputPaneLog.Severity
        public let timestamp: Date
        public let text: String
        public let sensitivity: MessageSensitivity

        public init(
            severity: OutputPaneLog.Severity,
            timestamp: Date,
            text: String,
            sensitivity: MessageSensitivity = .standard
        ) {
            self.severity = severity
            self.timestamp = timestamp
            self.text = text
            self.sensitivity = sensitivity
        }

        public var description: String {
            "OutputPaneWorkflow.AppendIntent(severity: \(severity.rawValue), sensitivity: \(sensitivity.rawValue), text: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "severity": severity,
                    "timestamp": timestamp,
                    "sensitivity": sensitivity,
                    "text": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(severity.rawValue)
            hasher.combine(timestamp)
            hasher.combine(text)
            hasher.combine(sensitivity)
        }
    }

    public enum SelectionIntent: Equatable, Hashable, Sendable {
        case replace(EntryID)
        case extend(EntryID)
        case toggle(EntryID)
        case set(Set<EntryID>)
        case clear
    }

    public enum FilterIntent: Equatable, Hashable, Sendable {
        case set(Filter)
        case clear
    }

    public enum CopyScope: Equatable, Hashable, Sendable {
        case selection
        case message(EntryID)
        case visibleMessages
    }

    public enum SensitiveCopyAuthorization: String, CaseIterable, Codable, Hashable, Sendable {
        case none
        case explicitUserApproval
    }

    public struct CopyIntent: Equatable, Hashable, Sendable {
        public let scope: CopyScope
        public let authorization: SensitiveCopyAuthorization

        public init(
            scope: CopyScope = .selection,
            authorization: SensitiveCopyAuthorization = .none
        ) {
            self.scope = scope
            self.authorization = authorization
        }
    }

    public enum Intent: Equatable, Hashable, Sendable {
        case toggleVisibility
        case setVisibility(Visibility)
        case setVisibilityPersistence(VisibilityPersistence)
        case select(SelectionIntent)
        case copy(CopyIntent)
        case selectAll
        case clearAll
        case append(AppendIntent)
        case filter(FilterIntent)
        case setSensitiveCopyPolicy(SensitiveCopyPolicy)

        public var command: Command {
            switch self {
            case .toggleVisibility: .toggleVisibility
            case .setVisibility: .setVisibility
            case .setVisibilityPersistence: .setVisibilityPersistence
            case .select(let selection):
                if case .clear = selection { .clearSelection } else { .selectMessage }
            case .copy: .copy
            case .selectAll: .selectAll
            case .clearAll: .clearAll
            case .append: .append
            case .filter: .setFilter
            case .setSensitiveCopyPolicy: .setSensitiveCopyPolicy
            }
        }

        fileprivate var mutatesState: Bool {
            return true
        }
    }

    public enum Command: String, CaseIterable, Codable, Hashable, Sendable {
        case toggleVisibility
        case setVisibility
        case setVisibilityPersistence
        case selectMessage
        case clearSelection
        case copy
        case selectAll
        case clearAll
        case append
        case setFilter
        case setSensitiveCopyPolicy
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case noMessages
        case noVisibleMessages
        case noSelection
        case allVisibleMessagesSelected
        case unknownMessage(EntryID)
        case messageFiltered(EntryID)
        case noStateChange
        case revisionExhausted
        case securitySensitiveCopyDenied(messageCount: Int)
        case securitySensitiveCopyRequiresAuthorization(messageCount: Int)
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

    public enum CheckedState: String, CaseIterable, Codable, Hashable, Sendable {
        case notCheckable
        case off
        case on
    }

    public struct CommandState: Equatable, Hashable, Sendable {
        public let command: Command
        public let expectedSnapshot: SnapshotReference
        public let availability: Availability
        public let checkedState: CheckedState
        public let plannedWorkUnits: UInt64

        fileprivate init(
            command: Command,
            expectedSnapshot: SnapshotReference,
            availability: Availability,
            checkedState: CheckedState,
            plannedWorkUnits: UInt64
        ) {
            self.command = command
            self.expectedSnapshot = expectedSnapshot
            self.availability = availability
            self.checkedState = checkedState
            self.plannedWorkUnits = plannedWorkUnits
        }

        public var isEnabled: Bool { availability.isEnabled }
        public var canExecute: Bool { isEnabled }
        public var isChecked: Bool { checkedState == .on }
        public var disabledReason: DisabledReason? { availability.disabledReason }
    }

    public struct AppendPlanningReceipt: Equatable, Hashable, Sendable {
        public let appendedMessageID: EntryID
        public let evictedMessageIDs: [EntryID]
        public let evictedUTF8ByteCount: Int
        public let wasSanitized: Bool
        public let sensitivity: MessageSensitivity

        fileprivate init(result: OutputPaneLog.AppendResult, sensitivity: MessageSensitivity) {
            appendedMessageID = result.entry.id
            evictedMessageIDs = result.evictedIDs
            evictedUTF8ByteCount = result.evictedUTF8ByteCount
            wasSanitized = result.entry.wasSanitized
            self.sensitivity = sensitivity
        }
    }

    public struct SelectionPlanningReceipt: Equatable, Hashable, Sendable {
        public let selectedMessageIDs: [EntryID]

        fileprivate init(selectedMessageIDs: Set<EntryID>) {
            self.selectedMessageIDs = selectedMessageIDs.sorted()
        }
    }

    public struct FilterPlanningReceipt: Equatable, Hashable, Sendable {
        public let filter: Filter
        public let visibleMessageCount: Int
        public let deselectedMessageCount: Int

        fileprivate init(filter: Filter, visibleMessageCount: Int, deselectedMessageCount: Int) {
            self.filter = filter
            self.visibleMessageCount = visibleMessageCount
            self.deselectedMessageCount = deselectedMessageCount
        }
    }

    public struct CopySummary: Equatable, Hashable, Sendable {
        public let scope: CopyScope
        public let messageIDs: [EntryID]
        public let utf8ByteCount: Int
        public let redactedMessageCount: Int
        public let disclosedSensitiveMessageCount: Int

        fileprivate init(
            scope: CopyScope,
            messageIDs: [EntryID],
            utf8ByteCount: Int,
            redactedMessageCount: Int,
            disclosedSensitiveMessageCount: Int
        ) {
            self.scope = scope
            self.messageIDs = messageIDs
            self.utf8ByteCount = utf8ByteCount
            self.redactedMessageCount = redactedMessageCount
            self.disclosedSensitiveMessageCount = disclosedSensitiveMessageCount
        }
    }

    public enum PlanningResult: Equatable, Hashable, Sendable {
        case visibility(VisibilityPreference)
        case selection(SelectionPlanningReceipt)
        case copied(CopySummary)
        case selectedAll(SelectionPlanningReceipt)
        case clearedAll(messageCount: Int, utf8ByteCount: Int)
        case appended(AppendPlanningReceipt)
        case filtered(FilterPlanningReceipt)
        case sensitiveCopyPolicy(SensitiveCopyPolicy)
    }

    /// Deterministic plan identity: no random value, wall-clock read, or platform state.
    public struct PlanningReceipt: Equatable, Hashable, Sendable {
        public let command: Command
        public let expectedSnapshot: SnapshotReference
        public let successorSnapshot: SnapshotReference?
        public let result: PlanningResult
        public let plannedWorkUnits: UInt64

        fileprivate init(
            command: Command,
            expectedSnapshot: SnapshotReference,
            successorSnapshot: SnapshotReference?,
            result: PlanningResult,
            plannedWorkUnits: UInt64
        ) {
            self.command = command
            self.expectedSnapshot = expectedSnapshot
            self.successorSnapshot = successorSnapshot
            self.result = result
            self.plannedWorkUnits = plannedWorkUnits
        }
    }

    public enum VisibilityPersistenceEffect: Equatable, Hashable, Sendable {
        case none
        case store(PersistedVisibilityPreference)
        case removeStoredPreference
    }

    /// Exact clipboard text. Descriptions intentionally never expose payload contents.
    public struct CopyPayload: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let text: String
        public let summary: CopySummary

        fileprivate init(text: String, summary: CopySummary) {
            self.text = text
            self.summary = summary
        }

        public var description: String {
            "OutputPaneWorkflow.CopyPayload(messages: \(summary.messageIDs.count), bytes: \(summary.utf8ByteCount), text: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "text": "<redacted>",
                    "messageCount": summary.messageIDs.count,
                    "utf8ByteCount": summary.utf8ByteCount
                ],
                displayStyle: .struct
            )
        }
    }

    public enum PlannedOperation: Equatable, Hashable, Sendable {
        case replaceState(
            successor: Snapshot,
            visibilityPersistence: VisibilityPersistenceEffect
        )
        /// Successor commits first while CAS remains held, making copy plans one-shot.
        case replaceStateAndClipboard(successor: Snapshot, payload: CopyPayload)
    }

    public enum RequiredEffect: Equatable, Hashable, Sendable {
        case storeVisibilityPreference(PersistedVisibilityPreference)
        case removeStoredVisibilityPreference
        case replaceState(SnapshotReference)
        case replaceClipboard(CopySummary)
    }

    public struct Plan: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let expectedSnapshotCAS: SnapshotCAS
        public let operation: PlannedOperation
        public let receipt: PlanningReceipt
        public let executorContract: ExecutorContract

        fileprivate init(
            expectedSnapshotCAS: SnapshotCAS,
            operation: PlannedOperation,
            receipt: PlanningReceipt
        ) {
            self.expectedSnapshotCAS = expectedSnapshotCAS
            self.operation = operation
            self.receipt = receipt
            executorContract = .required
        }

        public var expectedSnapshot: SnapshotReference {
            expectedSnapshotCAS.reference
        }

        public var description: String {
            "OutputPaneWorkflow.Plan(command: \(receipt.command.rawValue), expected: \(expectedSnapshot.identity.rawValue)/\(expectedSnapshot.revision), payload: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "command": receipt.command,
                    "expectedSnapshot": expectedSnapshot,
                    "successorSnapshot": receipt.successorSnapshot as Any,
                    "requiredEffects": requiredEffects,
                    "payload": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public var successor: Snapshot? {
            switch operation {
            case .replaceState(let successor, _), .replaceStateAndClipboard(let successor, _):
                return successor
            }
        }

        public var requiredEffects: [RequiredEffect] {
            switch operation {
            case .replaceState(let successor, let persistence):
                let persistenceEffect: RequiredEffect?
                switch persistence {
                case .none:
                    persistenceEffect = nil
                case .store(let preference):
                    persistenceEffect = .storeVisibilityPreference(preference)
                case .removeStoredPreference:
                    persistenceEffect = .removeStoredVisibilityPreference
                }
                return [persistenceEffect, .replaceState(successor.reference)].compactMap { $0 }
            case .replaceStateAndClipboard(let successor, let payload):
                return [
                    .replaceState(successor.reference),
                    .replaceClipboard(payload.summary)
                ]
            }
        }

        public func validateCurrentSnapshot(_ snapshot: Snapshot) throws {
            try expectedSnapshotCAS.validate(snapshot)
        }
    }

    public enum ExecutorLogCASContract: String, Codable, Hashable, Sendable {
        case holdExactIdentityRevisionAndContentsThroughEffects
    }

    public enum ExecutorStateContract: String, Codable, Hashable, Sendable {
        case commitExactPlannedSuccessorWithoutRegeneration
    }

    public enum ExecutorPersistenceContract: String, Codable, Hashable, Sendable {
        case publishExactPreferenceBeforeStateCommitWhileHoldingCASLease
    }

    public enum ExecutorClipboardContract: String, Codable, Hashable, Sendable {
        case replaceExactPlannedTextAfterSuccessorCommitWhileHoldingCASLease
    }

    public enum ExecutorSecurityContract: String, Codable, Hashable, Sendable {
        case neverPublishSensitiveTextUnlessPlanExplicitlyAuthorizesIt
    }

    public enum ExecutorCancellationContract: String, Codable, Hashable, Sendable {
        case cancelBeforeEffectsOrReportCompletedOrUncertainEffects
    }

    /// Mandatory boundary for app/platform executors. Planner performs no UI, pasteboard, or storage I/O.
    public struct ExecutorContract: Codable, Hashable, Sendable {
        public static let required = ExecutorContract()

        public let logCAS: ExecutorLogCASContract
        public let state: ExecutorStateContract
        public let persistence: ExecutorPersistenceContract
        public let clipboard: ExecutorClipboardContract
        public let security: ExecutorSecurityContract
        public let cancellation: ExecutorCancellationContract

        public init() {
            logCAS = .holdExactIdentityRevisionAndContentsThroughEffects
            state = .commitExactPlannedSuccessorWithoutRegeneration
            persistence = .publishExactPreferenceBeforeStateCommitWhileHoldingCASLease
            clipboard = .replaceExactPlannedTextAfterSuccessorCommitWhileHoldingCASLease
            security = .neverPublishSensitiveTextUnlessPlanExplicitlyAuthorizesIt
            cancellation = .cancelBeforeEffectsOrReportCompletedOrUncertainEffects
        }
    }

    public enum ExecutionNonCommitReason: String, CaseIterable, Codable, Hashable, Sendable {
        case cancelled
        case staleSnapshot
        case ownerStateUnavailable
        case visibilityPreferenceStorageUnavailable
        case clipboardUnavailable
        case contractUnsupported
        case rejected
    }

    public struct ExecutionReceipt: Equatable, Hashable, Sendable {
        public let planningReceipt: PlanningReceipt
        public let completedEffects: [RequiredEffect]

        fileprivate init(plan: Plan) {
            planningReceipt = plan.receipt
            completedEffects = plan.requiredEffects
        }
    }

    public struct ExecutionNonCommitReceipt: Equatable, Hashable, Sendable {
        public let planningReceipt: PlanningReceipt
        public let blockedEffect: RequiredEffect
        public let reason: ExecutionNonCommitReason

        fileprivate init(
            plan: Plan,
            blockedEffect: RequiredEffect,
            reason: ExecutionNonCommitReason
        ) {
            planningReceipt = plan.receipt
            self.blockedEffect = blockedEffect
            self.reason = reason
        }
    }

    public struct ExecutionFailureReceipt: Equatable, Hashable, Sendable {
        public let planningReceipt: PlanningReceipt
        /// Stable plan prefix proven complete before failure.
        public let completedEffects: [RequiredEffect]
        public let failedEffect: RequiredEffect
        public let reason: ExecutionNonCommitReason
        /// Stable plan suffix proven not attempted.
        public let unattemptedEffects: [RequiredEffect]

        fileprivate init(
            plan: Plan,
            completedEffects: [RequiredEffect],
            failedEffect: RequiredEffect,
            reason: ExecutionNonCommitReason,
            unattemptedEffects: [RequiredEffect]
        ) {
            planningReceipt = plan.receipt
            self.completedEffects = completedEffects
            self.failedEffect = failedEffect
            self.reason = reason
            self.unattemptedEffects = unattemptedEffects
        }
    }

    public struct ExecutionUncertaintyReceipt: Equatable, Hashable, Sendable {
        public let planningReceipt: PlanningReceipt
        /// Stable plan prefix proven complete before uncertainty began.
        public let completedEffects: [RequiredEffect]
        /// Stable plan order; each listed effect may or may not have completed.
        public let uncertainEffects: [RequiredEffect]
        /// Stable plan suffix proven not attempted.
        public let unattemptedEffects: [RequiredEffect]

        fileprivate init(
            plan: Plan,
            completedEffects: [RequiredEffect],
            uncertainEffects: [RequiredEffect],
            unattemptedEffects: [RequiredEffect]
        ) {
            planningReceipt = plan.receipt
            self.completedEffects = completedEffects
            self.uncertainEffects = uncertainEffects
            self.unattemptedEffects = unattemptedEffects
        }
    }

    public enum ExecutionOutcome: Equatable, Hashable, Sendable {
        case completed(ExecutionReceipt)
        /// Conforming executors use this only when no required effect occurred.
        case notCommitted(ExecutionNonCommitReceipt)
        case failedAfterEffects(ExecutionFailureReceipt)
        case effectUncertain(ExecutionUncertaintyReceipt)
    }

    /// Seals deterministic receipts so public outcomes cannot contradict a plan.
    public enum ExecutionOutcomeFactory: Sendable {
        public static func completed(plan: Plan) -> ExecutionOutcome {
            .completed(ExecutionReceipt(plan: plan))
        }

        public static func notCommitted(
            plan: Plan,
            blockedEffectIndex: Int = 0,
            reason: ExecutionNonCommitReason
        ) throws -> ExecutionOutcome {
            let effects = plan.requiredEffects
            guard blockedEffectIndex == 0,
                let blockedEffect = effects.first,
                isValid(reason: reason, for: blockedEffect)
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return .notCommitted(
                ExecutionNonCommitReceipt(
                    plan: plan,
                    blockedEffect: blockedEffect,
                    reason: reason
                )
            )
        }

        public static func failed(
            plan: Plan,
            completedEffectCount: Int,
            reason: ExecutionNonCommitReason
        ) throws -> ExecutionOutcome {
            let requiredEffects = plan.requiredEffects
            guard completedEffectCount > 0, completedEffectCount < requiredEffects.count else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let failedEffect = requiredEffects[completedEffectCount]
            guard isValid(reason: reason, for: failedEffect) else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return .failedAfterEffects(
                ExecutionFailureReceipt(
                    plan: plan,
                    completedEffects: Array(requiredEffects.prefix(completedEffectCount)),
                    failedEffect: failedEffect,
                    reason: reason,
                    unattemptedEffects: Array(requiredEffects.dropFirst(completedEffectCount + 1))
                )
            )
        }

        public static func effectUncertain(
            plan: Plan,
            completedEffectCount: Int = 0,
            uncertainEffectIndices: [Int]
        ) throws -> ExecutionOutcome {
            let requiredEffects = plan.requiredEffects
            let indices = uncertainEffectIndices.sorted()
            guard completedEffectCount >= 0,
                completedEffectCount < requiredEffects.count,
                !indices.isEmpty,
                Set(indices).count == indices.count,
                indices.allSatisfy(requiredEffects.indices.contains),
                indices.first == completedEffectCount,
                let lastIndex = indices.last,
                completedEffectCount <= lastIndex,
                indices == Array(completedEffectCount...lastIndex)
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let lastUncertainIndex = indices[indices.count - 1]
            return .effectUncertain(
                ExecutionUncertaintyReceipt(
                    plan: plan,
                    completedEffects: Array(requiredEffects.prefix(completedEffectCount)),
                    uncertainEffects: indices.map { requiredEffects[$0] },
                    unattemptedEffects: Array(requiredEffects.dropFirst(lastUncertainIndex + 1))
                )
            )
        }

        private static func isValid(
            reason: ExecutionNonCommitReason,
            for effect: RequiredEffect
        ) -> Bool {
            switch (reason, effect) {
            case (.cancelled, _), (.staleSnapshot, _), (.contractUnsupported, _), (.rejected, _):
                true
            case (.ownerStateUnavailable, .replaceState):
                true
            case (.visibilityPreferenceStorageUnavailable, .storeVisibilityPreference),
                (.visibilityPreferenceStorageUnavailable, .removeStoredVisibilityPreference):
                true
            case (.clipboardUnavailable, .replaceClipboard):
                true
            default:
                false
            }
        }
    }

    /// Side-effect implementation supplied by owner/app layer. It must enforce `ExecutorContract.required`.
    public protocol PlanExecutor: Sendable {
        func execute(_ plan: Plan) async -> ExecutionOutcome
    }

    public enum TextField: String, CaseIterable, Codable, Hashable, Sendable {
        case appendMessage
        case filter
    }

    public enum WorkflowError: Swift.Error, Equatable, LocalizedError, Sendable {
        case cancelled
        case invalidLimit(Limit)
        case incompatibleLogLimit(Limit)
        case tooManyItems(maximum: Int)
        case tooManySelectedItems(maximum: Int)
        case textTooLarge(field: TextField, maximumUTF8Bytes: Int)
        case retainedTextTooLarge(maximumUTF8Bytes: Int)
        case copyTextTooLarge(maximumUTF8Bytes: Int)
        case workLimitExceeded(maximumUnits: UInt64)
        case invalidSeverityMask(UInt8)
        case securityMetadataReferencesUnknownMessage(EntryID)
        case selectionReferencesFilteredMessage(EntryID)
        case unsupportedPreferenceSchemaVersion(Int)
        case staleLog(expected: SnapshotReference, actual: SnapshotReference)
        case logContentsChanged(SnapshotReference)
        case commandDisabled(command: Command, reason: DisabledReason)
        case invalidExecutionOutcome
        case outputLog(OutputPaneLogError)
        case arithmeticOverflow

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "Output-pane workflow was cancelled."
            case .invalidLimit(let limit):
                "Invalid output-pane workflow limit: \(limit.rawValue)."
            case .incompatibleLogLimit(let limit):
                "Output-pane log exceeds workflow limit capability: \(limit.rawValue)."
            case .tooManyItems(let maximum):
                "Output-pane workflow cannot retain more than \(maximum) messages."
            case .tooManySelectedItems(let maximum):
                "Output-pane workflow cannot select more than \(maximum) messages."
            case .textTooLarge(let field, let maximum):
                "Output-pane \(field.rawValue) text exceeds \(maximum) UTF-8 bytes."
            case .retainedTextTooLarge(let maximum):
                "Output-pane retained text exceeds \(maximum) UTF-8 bytes."
            case .copyTextTooLarge(let maximum):
                "Output-pane copy text exceeds \(maximum) UTF-8 bytes."
            case .workLimitExceeded(let maximum):
                "Output-pane workflow exceeds \(maximum) work units."
            case .invalidSeverityMask(let value):
                "Output-pane severity mask contains unsupported bits: \(value)."
            case .securityMetadataReferencesUnknownMessage(let id):
                "Output-pane security metadata references unknown message \(id.rawValue)."
            case .selectionReferencesFilteredMessage(let id):
                "Output-pane selection references filtered message \(id.rawValue)."
            case .unsupportedPreferenceSchemaVersion(let version):
                "Unsupported output-pane visibility preference schema version: \(version)."
            case .staleLog(let expected, let actual):
                "Output-pane plan expects log \(expected.identity.rawValue) revision \(expected.revision), not log \(actual.identity.rawValue) revision \(actual.revision)."
            case .logContentsChanged:
                "Output-pane log changed without advancing its identity and revision."
            case .commandDisabled(let command, _):
                "Output-pane command is disabled: \(command.rawValue)."
            case .invalidExecutionOutcome:
                "Output-pane execution outcome contradicts required effect order."
            case .outputLog(let error):
                error.localizedDescription
            case .arithmeticOverflow:
                "Output-pane workflow size calculation overflowed."
            }
        }
    }

    public static let redactionMarker = "[REDACTED]"

    /// Resolves exact state for one concrete intent without performing side effects.
    public static func commandState(
        for intent: Intent,
        in snapshot: Snapshot
    ) throws -> CommandState {
        do {
            var budget = try WorkBudget(limits: snapshot.limits)
            let draft = try makeDraft(intent, in: snapshot, budget: &budget)
            try budget.finish()
            return CommandState(
                command: intent.command,
                expectedSnapshot: snapshot.reference,
                availability: draft.availability,
                checkedState: draft.checkedState,
                plannedWorkUnits: budget.consumed
            )
        } catch is CancellationError {
            throw WorkflowError.cancelled
        }
    }

    /// Stable order for direct pane controls.
    public static func primaryCommandStates(in snapshot: Snapshot) throws -> [CommandState] {
        do {
            let intents: [Intent] = [
                .toggleVisibility,
                .copy(CopyIntent()),
                .selectAll,
                .clearAll
            ]
            var aggregateBudget = try WorkBudget(
                limits: snapshot.limits,
                maximum: snapshot.limits.maximumAggregateWorkUnits
            )
            var states: [CommandState] = []
            states.reserveCapacity(intents.count)
            for intent in intents {
                try Task<Never, Never>.checkCancellation()
                var commandBudget = try WorkBudget(limits: snapshot.limits)
                let draft = try makeDraft(intent, in: snapshot, budget: &commandBudget)
                try commandBudget.finish()
                try aggregateBudget.consume(commandBudget.consumed)
                states.append(
                    CommandState(
                        command: intent.command,
                        expectedSnapshot: snapshot.reference,
                        availability: draft.availability,
                        checkedState: draft.checkedState,
                        plannedWorkUnits: commandBudget.consumed
                    )
                )
            }
            try aggregateBudget.finish()
            return states
        } catch is CancellationError {
            throw WorkflowError.cancelled
        }
    }

    /// Builds an immutable plan. Disabled intents produce a typed error and no plan.
    public static func plan(_ intent: Intent, in snapshot: Snapshot) throws -> Plan {
        do {
            var budget = try WorkBudget(limits: snapshot.limits)
            let draft = try makeDraft(intent, in: snapshot, budget: &budget)
            try budget.finish()
            guard case .enabled = draft.availability else {
                throw WorkflowError.commandDisabled(
                    command: intent.command,
                    reason: draft.availability.disabledReason!
                )
            }
            guard let operation = draft.operation, let result = draft.result else {
                throw WorkflowError.commandDisabled(
                    command: intent.command,
                    reason: .noStateChange
                )
            }
            let successorReference =
                switch operation {
                case .replaceState(let successor, _), .replaceStateAndClipboard(let successor, _):
                    successor.reference
                }
            let receipt = PlanningReceipt(
                command: intent.command,
                expectedSnapshot: snapshot.reference,
                successorSnapshot: successorReference,
                result: result,
                plannedWorkUnits: budget.consumed
            )
            return Plan(
                expectedSnapshotCAS: snapshot.cas,
                operation: operation,
                receipt: receipt
            )
        } catch is CancellationError {
            throw WorkflowError.cancelled
        }
    }
}

extension OutputPaneWorkflow {
    fileprivate struct Draft {
        let availability: Availability
        let checkedState: CheckedState
        let operation: PlannedOperation?
        let result: PlanningResult?

        static func disabled(
            _ reason: DisabledReason,
            checkedState: CheckedState = .notCheckable
        ) -> Draft {
            Draft(
                availability: .disabled(reason),
                checkedState: checkedState,
                operation: nil,
                result: nil
            )
        }

        static func enabled(
            checkedState: CheckedState = .notCheckable,
            operation: PlannedOperation,
            result: PlanningResult
        ) -> Draft {
            Draft(
                availability: .enabled,
                checkedState: checkedState,
                operation: operation,
                result: result
            )
        }
    }

    fileprivate struct WorkBudget {
        let maximum: UInt64
        let cancellationCheckInterval: UInt64
        private(set) var consumed: UInt64 = 0
        private var nextCancellationCheck: UInt64 = 0

        init(limits: Limits, maximum: UInt64? = nil) throws {
            try OutputPaneWorkflow.validate(limits)
            self.maximum = maximum ?? limits.maximumWorkUnits
            cancellationCheckInterval = limits.cancellationCheckInterval
            nextCancellationCheck = 0
            try checkCancellation(force: true)
        }

        mutating func consume(_ units: UInt64) throws {
            let (value, overflow) = consumed.addingReportingOverflow(units)
            guard !overflow else { throw WorkflowError.arithmeticOverflow }
            guard value <= maximum else {
                throw WorkflowError.workLimitExceeded(maximumUnits: maximum)
            }
            consumed = value
            try checkCancellation(force: false)
        }

        mutating func consume(bytes: Int) throws {
            guard bytes >= 0 else { throw WorkflowError.arithmeticOverflow }
            try consume(UInt64(bytes))
        }

        mutating func consume(items: Int) throws {
            guard items >= 0 else { throw WorkflowError.arithmeticOverflow }
            try consume(UInt64(items))
        }

        mutating func finish() throws {
            try checkCancellation(force: true)
        }

        private mutating func checkCancellation(force: Bool) throws {
            guard force || consumed >= nextCancellationCheck else { return }
            try Task<Never, Never>.checkCancellation()
            let (next, overflow) = consumed.addingReportingOverflow(cancellationCheckInterval)
            nextCancellationCheck = overflow ? .max : next
        }
    }

    fileprivate static func makeDraft(
        _ intent: Intent,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        try budget.consume(1)
        if intent.mutatesState, snapshot.revision == .max {
            return .disabled(
                .revisionExhausted,
                checkedState: checkedState(for: intent, snapshot: snapshot)
            )
        }

        switch intent {
        case .toggleVisibility:
            let visibility: Visibility = snapshot.isVisible ? .hidden : .visible
            return try visibilityDraft(visibility, snapshot: snapshot, budget: &budget)
        case .setVisibility(let visibility):
            return try visibilityDraft(visibility, snapshot: snapshot, budget: &budget)
        case .setVisibilityPersistence(let persistence):
            return try persistenceDraft(persistence, snapshot: snapshot, budget: &budget)
        case .select(let selection):
            return try selectionDraft(selection, snapshot: snapshot, budget: &budget)
        case .copy(let copyIntent):
            return try copyDraft(copyIntent, snapshot: snapshot, budget: &budget)
        case .selectAll:
            return try selectAllDraft(snapshot: snapshot, budget: &budget)
        case .clearAll:
            return try clearAllDraft(snapshot: snapshot, budget: &budget)
        case .append(let appendIntent):
            return try appendDraft(appendIntent, snapshot: snapshot, budget: &budget)
        case .filter(let filterIntent):
            return try filterDraft(filterIntent, snapshot: snapshot, budget: &budget)
        case .setSensitiveCopyPolicy(let policy):
            return try copyPolicyDraft(policy, snapshot: snapshot, budget: &budget)
        }
    }

    fileprivate static func checkedState(for intent: Intent, snapshot: Snapshot) -> CheckedState {
        switch intent {
        case .toggleVisibility, .setVisibility:
            snapshot.isVisible ? .on : .off
        case .setVisibilityPersistence:
            snapshot.visibilityPreference.persistence == .persisted ? .on : .off
        default:
            .notCheckable
        }
    }

    fileprivate static func visibilityDraft(
        _ visibility: Visibility,
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        let checkedState: CheckedState = snapshot.isVisible ? .on : .off
        guard visibility != snapshot.visibilityPreference.visibility else {
            return .disabled(.noStateChange, checkedState: checkedState)
        }
        let preference = VisibilityPreference(
            visibility: visibility,
            persistence: snapshot.visibilityPreference.persistence
        )
        let persistenceEffect: VisibilityPersistenceEffect =
            preference.persistence == .persisted
            ? .store(PersistedVisibilityPreference(visibility: visibility))
            : .none
        let successor = try successor(
            of: snapshot,
            visibilityPreference: preference,
            budget: &budget
        )
        return .enabled(
            checkedState: checkedState,
            operation: .replaceState(
                successor: successor,
                visibilityPersistence: persistenceEffect
            ),
            result: .visibility(preference)
        )
    }

    fileprivate static func persistenceDraft(
        _ persistence: VisibilityPersistence,
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        let checkedState: CheckedState =
            snapshot.visibilityPreference.persistence == .persisted ? .on : .off
        guard persistence != snapshot.visibilityPreference.persistence else {
            return .disabled(.noStateChange, checkedState: checkedState)
        }
        let preference = VisibilityPreference(
            visibility: snapshot.visibilityPreference.visibility,
            persistence: persistence
        )
        let effect: VisibilityPersistenceEffect
        switch persistence {
        case .sessionOnly:
            effect = .removeStoredPreference
        case .persisted:
            effect = .store(
                PersistedVisibilityPreference(visibility: preference.visibility)
            )
        }
        let successor = try successor(
            of: snapshot,
            visibilityPreference: preference,
            budget: &budget
        )
        return .enabled(
            checkedState: checkedState,
            operation: .replaceState(successor: successor, visibilityPersistence: effect),
            result: .visibility(preference)
        )
    }

    fileprivate static func selectionDraft(
        _ intent: SelectionIntent,
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        var log = snapshot.log
        let visibleIDs = Set(snapshot.visibleEntries.map(\.id))
        try budget.consume(items: snapshot.visibleEntries.count)

        switch intent {
        case .replace(let id):
            if let disabled = selectionDisabledReason(id, snapshot: snapshot, visibleIDs: visibleIDs) {
                return .disabled(disabled)
            }
            guard log.select(id) else { return .disabled(.noStateChange) }
        case .extend(let id):
            if let disabled = selectionDisabledReason(id, snapshot: snapshot, visibleIDs: visibleIDs) {
                return .disabled(disabled)
            }
            guard log.select(id, extendingSelection: true) else {
                return .disabled(.noStateChange)
            }
        case .toggle(let id):
            if let disabled = selectionDisabledReason(id, snapshot: snapshot, visibleIDs: visibleIDs) {
                return .disabled(disabled)
            }
            guard log.toggleSelection(id) else { return .disabled(.noStateChange) }
        case .set(let ids):
            guard ids.count <= snapshot.limits.maximumSelectedItemCount else {
                throw WorkflowError.tooManySelectedItems(
                    maximum: snapshot.limits.maximumSelectedItemCount
                )
            }
            try budget.consume(items: ids.count)
            let retainedIDs = Set(snapshot.log.entries.map(\.id))
            if let unknown = ids.subtracting(retainedIDs).sorted().first {
                return .disabled(.unknownMessage(unknown))
            }
            if let hidden = ids.subtracting(visibleIDs).sorted().first {
                return .disabled(.messageFiltered(hidden))
            }
            guard log.setSelection(ids) else { return .disabled(.noStateChange) }
        case .clear:
            guard log.clearSelection() else { return .disabled(.noSelection) }
        }

        let successor = try successor(of: snapshot, log: log, budget: &budget)
        let receipt = SelectionPlanningReceipt(selectedMessageIDs: log.selectedIDs)
        return .enabled(
            operation: .replaceState(successor: successor, visibilityPersistence: .none),
            result: .selection(receipt)
        )
    }

    fileprivate static func selectionDisabledReason(
        _ id: EntryID,
        snapshot: Snapshot,
        visibleIDs: Set<EntryID>
    ) -> DisabledReason? {
        guard snapshot.entry(withID: id) != nil else { return .unknownMessage(id) }
        guard visibleIDs.contains(id) else { return .messageFiltered(id) }
        return nil
    }

    fileprivate static func selectAllDraft(
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        guard !snapshot.log.entries.isEmpty else { return .disabled(.noMessages) }
        guard !snapshot.visibleEntries.isEmpty else { return .disabled(.noVisibleMessages) }
        guard snapshot.visibleEntries.count <= snapshot.limits.maximumSelectedItemCount else {
            throw WorkflowError.tooManySelectedItems(
                maximum: snapshot.limits.maximumSelectedItemCount
            )
        }

        var log = snapshot.log
        let visibleIDs = Set(snapshot.visibleEntries.map(\.id))
        try budget.consume(items: snapshot.visibleEntries.count)
        let changed: Bool
        if snapshot.filter.isUnfiltered {
            changed = log.selectAll()
        } else {
            changed = log.setSelection(visibleIDs)
        }
        guard changed else { return .disabled(.allVisibleMessagesSelected) }

        let successor = try successor(of: snapshot, log: log, budget: &budget)
        let receipt = SelectionPlanningReceipt(selectedMessageIDs: log.selectedIDs)
        return .enabled(
            operation: .replaceState(successor: successor, visibilityPersistence: .none),
            result: .selectedAll(receipt)
        )
    }

    fileprivate static func clearAllDraft(
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        guard !snapshot.log.entries.isEmpty else { return .disabled(.noMessages) }
        let removedCount = snapshot.log.entries.count
        let removedBytes = snapshot.log.retainedUTF8ByteCount
        var log = snapshot.log
        guard log.clear() else { return .disabled(.noMessages) }
        try budget.consume(items: removedCount)
        let successor = try successor(
            of: snapshot,
            log: log,
            securitySensitiveMessageIDs: [],
            budget: &budget
        )
        return .enabled(
            operation: .replaceState(successor: successor, visibilityPersistence: .none),
            result: .clearedAll(messageCount: removedCount, utf8ByteCount: removedBytes)
        )
    }

    fileprivate static func appendDraft(
        _ intent: AppendIntent,
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        _ = try measure(
            intent.text,
            maximumUTF8Bytes: snapshot.limits.maximumAppendUTF8Bytes,
            field: .appendMessage,
            budget: &budget
        )
        var log = snapshot.log
        let result: OutputPaneLog.AppendResult
        do {
            result = try log.append(
                severity: intent.severity,
                timestamp: intent.timestamp,
                text: intent.text
            )
        } catch let error as OutputPaneLogError {
            throw WorkflowError.outputLog(error)
        }
        try budget.consume(bytes: result.entry.utf8ByteCount)

        var sensitiveIDs = snapshot.securitySensitiveMessageIDs
        for id in result.evictedIDs {
            try budget.consume(1)
            sensitiveIDs.remove(id)
        }
        if intent.sensitivity == .securitySensitive {
            sensitiveIDs.insert(result.entry.id)
        }
        let successor = try successor(
            of: snapshot,
            log: log,
            securitySensitiveMessageIDs: sensitiveIDs,
            budget: &budget
        )
        return .enabled(
            operation: .replaceState(successor: successor, visibilityPersistence: .none),
            result: .appended(
                AppendPlanningReceipt(result: result, sensitivity: intent.sensitivity)
            )
        )
    }

    fileprivate static func filterDraft(
        _ intent: FilterIntent,
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        let filter: Filter
        switch intent {
        case .set(let value): filter = value
        case .clear: filter = .all
        }
        _ = try validate(filter, limits: snapshot.limits, budget: &budget)
        guard filter != snapshot.filter else { return .disabled(.noStateChange) }

        let visibleEntries = try filteredEntries(
            in: snapshot.log,
            filter: filter,
            budget: &budget
        )
        let visibleIDs = Set(visibleEntries.map(\.id))
        var log = snapshot.log
        let previousSelectionCount = log.selectedIDs.count
        _ = log.setSelection(log.selectedIDs.intersection(visibleIDs))
        let deselectedCount = previousSelectionCount - log.selectedIDs.count
        let successor = try successor(
            of: snapshot,
            log: log,
            filter: filter,
            budget: &budget
        )
        return .enabled(
            operation: .replaceState(successor: successor, visibilityPersistence: .none),
            result: .filtered(
                FilterPlanningReceipt(
                    filter: filter,
                    visibleMessageCount: visibleEntries.count,
                    deselectedMessageCount: deselectedCount
                )
            )
        )
    }

    fileprivate static func copyPolicyDraft(
        _ policy: SensitiveCopyPolicy,
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        guard policy != snapshot.sensitiveCopyPolicy else {
            return .disabled(.noStateChange)
        }
        let successor = try successor(
            of: snapshot,
            sensitiveCopyPolicy: policy,
            budget: &budget
        )
        return .enabled(
            operation: .replaceState(successor: successor, visibilityPersistence: .none),
            result: .sensitiveCopyPolicy(policy)
        )
    }

    fileprivate static func copyDraft(
        _ intent: CopyIntent,
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Draft {
        let entries: [OutputPaneLog.Entry]
        switch intent.scope {
        case .selection:
            var selectedEntries: [OutputPaneLog.Entry] = []
            selectedEntries.reserveCapacity(snapshot.log.selectedIDs.count)
            for entry in snapshot.log.entries {
                try budget.consume(1)
                if snapshot.log.selectedIDs.contains(entry.id) {
                    selectedEntries.append(entry)
                }
            }
            entries = selectedEntries
            guard !entries.isEmpty else { return .disabled(.noSelection) }
        case .message(let id):
            var matchingEntry: OutputPaneLog.Entry?
            for entry in snapshot.log.entries {
                try budget.consume(1)
                if entry.id == id {
                    matchingEntry = entry
                    break
                }
            }
            guard let matchingEntry else {
                return .disabled(.unknownMessage(id))
            }
            var isVisible = false
            for entry in snapshot.visibleEntries {
                try budget.consume(1)
                if entry.id == id {
                    isVisible = true
                    break
                }
            }
            guard isVisible else {
                return .disabled(.messageFiltered(id))
            }
            entries = [matchingEntry]
        case .visibleMessages:
            entries = snapshot.visibleEntries
            guard !entries.isEmpty else {
                return .disabled(snapshot.log.entries.isEmpty ? .noMessages : .noVisibleMessages)
            }
        }

        var messageIDs: [EntryID] = []
        messageIDs.reserveCapacity(entries.count)
        var sensitiveCount = 0
        for entry in entries {
            try budget.consume(1)
            messageIDs.append(entry.id)
            if snapshot.securitySensitiveMessageIDs.contains(entry.id) {
                sensitiveCount += 1
            }
        }
        if sensitiveCount > 0 {
            switch snapshot.sensitiveCopyPolicy {
            case .deny:
                return .disabled(.securitySensitiveCopyDenied(messageCount: sensitiveCount))
            case .redact:
                break
            case .requireExplicitAuthorization:
                guard intent.authorization == .explicitUserApproval else {
                    return .disabled(
                        .securitySensitiveCopyRequiresAuthorization(
                            messageCount: sensitiveCount
                        )
                    )
                }
            }
        }

        let redacts = sensitiveCount > 0 && snapshot.sensitiveCopyPolicy == .redact
        let text: String
        let byteCount: Int
        if redacts {
            (text, byteCount) = try redactedCopyText(
                entries,
                snapshot: snapshot,
                budget: &budget
            )
        } else {
            (text, byteCount) = try unredactedCopyText(
                entries,
                maximumUTF8Bytes: snapshot.limits.maximumCopyUTF8Bytes,
                budget: &budget
            )
        }
        let summary = CopySummary(
            scope: intent.scope,
            messageIDs: messageIDs,
            utf8ByteCount: byteCount,
            redactedMessageCount: redacts ? sensitiveCount : 0,
            disclosedSensitiveMessageCount: redacts ? 0 : sensitiveCount
        )
        let successor = try successor(of: snapshot, budget: &budget)
        return .enabled(
            operation: .replaceStateAndClipboard(
                successor: successor,
                payload: CopyPayload(text: text, summary: summary)
            ),
            result: .copied(summary)
        )
    }

    fileprivate static func redactedCopyText(
        _ entries: [OutputPaneLog.Entry],
        snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> (text: String, utf8ByteCount: Int) {
        let markerBytes = redactionMarker.utf8.count
        var requiredBytes = max(0, entries.count - 1)
        for entry in entries {
            try budget.consume(1)
            let added =
                snapshot.securitySensitiveMessageIDs.contains(entry.id)
                ? markerBytes
                : entry.utf8ByteCount
            requiredBytes = try checkedAdd(requiredBytes, added)
            guard requiredBytes <= snapshot.limits.maximumCopyUTF8Bytes else {
                throw WorkflowError.copyTextTooLarge(
                    maximumUTF8Bytes: snapshot.limits.maximumCopyUTF8Bytes
                )
            }
        }
        var result = ""
        result.reserveCapacity(requiredBytes)
        for (index, entry) in entries.enumerated() {
            if index > 0 {
                try appendCopyComponent(
                    "\n",
                    expectedUTF8ByteCount: 1,
                    to: &result,
                    budget: &budget
                )
            }
            if snapshot.securitySensitiveMessageIDs.contains(entry.id) {
                try appendCopyComponent(
                    redactionMarker,
                    expectedUTF8ByteCount: markerBytes,
                    to: &result,
                    budget: &budget
                )
            } else {
                try appendCopyComponent(
                    entry.text,
                    expectedUTF8ByteCount: entry.utf8ByteCount,
                    to: &result,
                    budget: &budget
                )
            }
        }
        return (result, requiredBytes)
    }

    fileprivate static func unredactedCopyText(
        _ entries: [OutputPaneLog.Entry],
        maximumUTF8Bytes: Int,
        budget: inout WorkBudget
    ) throws -> (text: String, utf8ByteCount: Int) {
        var requiredBytes = max(0, entries.count - 1)
        for entry in entries {
            try budget.consume(1)
            requiredBytes = try checkedAdd(requiredBytes, entry.utf8ByteCount)
        }
        guard requiredBytes <= maximumUTF8Bytes else {
            throw WorkflowError.copyTextTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
        }
        var result = ""
        result.reserveCapacity(requiredBytes)
        for (index, entry) in entries.enumerated() {
            if index > 0 {
                try appendCopyComponent(
                    "\n",
                    expectedUTF8ByteCount: 1,
                    to: &result,
                    budget: &budget
                )
            }
            try appendCopyComponent(
                entry.text,
                expectedUTF8ByteCount: entry.utf8ByteCount,
                to: &result,
                budget: &budget
            )
        }
        return (result, requiredBytes)
    }

    fileprivate static func appendCopyComponent(
        _ component: String,
        expectedUTF8ByteCount: Int,
        to result: inout String,
        budget: inout WorkBudget
    ) throws {
        guard expectedUTF8ByteCount >= 0 else { throw WorkflowError.arithmeticOverflow }
        let scalars = component.unicodeScalars
        var chunkStart = scalars.startIndex
        var index = chunkStart
        var chunkBytes = 0
        var totalBytes = 0
        let chunkLimit = Int(budget.cancellationCheckInterval)

        while index != scalars.endIndex {
            let scalarBytes = utf8ByteCount(of: scalars[index].value)
            chunkBytes = try checkedAdd(chunkBytes, scalarBytes)
            totalBytes = try checkedAdd(totalBytes, scalarBytes)
            let nextIndex = scalars.index(after: index)
            if chunkBytes >= chunkLimit {
                try budget.consume(bytes: chunkBytes)
                result.append(contentsOf: component[chunkStart..<nextIndex])
                chunkStart = nextIndex
                chunkBytes = 0
            }
            index = nextIndex
        }
        if chunkBytes > 0 {
            try budget.consume(bytes: chunkBytes)
            result.append(contentsOf: component[chunkStart..<scalars.endIndex])
        }
        guard totalBytes == expectedUTF8ByteCount else {
            throw WorkflowError.arithmeticOverflow
        }
    }

    fileprivate static func utf8ByteCount(of value: UInt32) -> Int {
        switch value {
        case ...0x7F: 1
        case ...0x7FF: 2
        case ...0xFFFF: 3
        default: 4
        }
    }

    fileprivate static func successor(
        of snapshot: Snapshot,
        log: OutputPaneLog? = nil,
        visibilityPreference: VisibilityPreference? = nil,
        filter: Filter? = nil,
        sensitiveCopyPolicy: SensitiveCopyPolicy? = nil,
        securitySensitiveMessageIDs: Set<EntryID>? = nil,
        budget: inout WorkBudget
    ) throws -> Snapshot {
        guard snapshot.revision < .max else {
            throw WorkflowError.commandDisabled(
                command: .append,
                reason: .revisionExhausted
            )
        }
        return try Snapshot.validated(
            identity: snapshot.identity,
            revision: snapshot.revision + 1,
            log: log ?? snapshot.log,
            visibilityPreference: visibilityPreference ?? snapshot.visibilityPreference,
            filter: filter ?? snapshot.filter,
            sensitiveCopyPolicy: sensitiveCopyPolicy ?? snapshot.sensitiveCopyPolicy,
            securitySensitiveMessageIDs: securitySensitiveMessageIDs
                ?? snapshot.securitySensitiveMessageIDs,
            limits: snapshot.limits,
            budget: &budget
        )
    }

    fileprivate static func validate(_ limits: Limits) throws {
        guard
            (1...Limits.hardMaximumRetainedItemCount).contains(
                limits.maximumRetainedItemCount
            )
        else {
            throw WorkflowError.invalidLimit(.retainedItems)
        }
        guard
            (1...Limits.hardMaximumSelectedItemCount).contains(
                limits.maximumSelectedItemCount
            ), limits.maximumSelectedItemCount <= limits.maximumRetainedItemCount
        else {
            throw WorkflowError.invalidLimit(.selectedItems)
        }
        guard
            (1...Limits.hardMaximumAppendUTF8Bytes).contains(
                limits.maximumAppendUTF8Bytes
            ), limits.maximumAppendUTF8Bytes <= limits.maximumRetainedUTF8Bytes
        else {
            throw WorkflowError.invalidLimit(.appendText)
        }
        guard
            (1...Limits.hardMaximumRetainedUTF8Bytes).contains(
                limits.maximumRetainedUTF8Bytes
            )
        else {
            throw WorkflowError.invalidLimit(.retainedText)
        }
        guard
            (0...Limits.hardMaximumFilterUTF8Bytes).contains(
                limits.maximumFilterUTF8Bytes
            )
        else {
            throw WorkflowError.invalidLimit(.filterText)
        }
        guard
            (1...Limits.hardMaximumCopyUTF8Bytes).contains(
                limits.maximumCopyUTF8Bytes
            )
        else {
            throw WorkflowError.invalidLimit(.copyText)
        }
        guard (1...Limits.hardMaximumWorkUnits).contains(limits.maximumWorkUnits) else {
            throw WorkflowError.invalidLimit(.workUnits)
        }
        guard
            (limits.maximumWorkUnits...Limits.hardMaximumWorkUnits).contains(
                limits.maximumAggregateWorkUnits
            )
        else {
            throw WorkflowError.invalidLimit(.aggregateWorkUnits)
        }
        guard
            (1...Limits.hardMaximumCancellationCheckInterval).contains(
                limits.cancellationCheckInterval
            )
        else {
            throw WorkflowError.invalidLimit(.cancellationCheckInterval)
        }
    }

    fileprivate static func validate(
        _ filter: Filter,
        limits: Limits,
        budget: inout WorkBudget
    ) throws -> Int {
        guard filter.severities.rawValue & ~SeverityMask.all.rawValue == 0 else {
            throw WorkflowError.invalidSeverityMask(filter.severities.rawValue)
        }
        if let text = filter.text {
            return try measure(
                text,
                maximumUTF8Bytes: limits.maximumFilterUTF8Bytes,
                field: .filter,
                budget: &budget
            )
        }
        return 0
    }

    fileprivate static func filteredEntries(
        in log: OutputPaneLog,
        filter: Filter,
        budget: inout WorkBudget
    ) throws -> [OutputPaneLog.Entry] {
        if filter.isUnfiltered {
            try budget.consume(items: log.entries.count)
            return log.entries
        }
        var result: [OutputPaneLog.Entry] = []
        result.reserveCapacity(log.entries.count)
        for entry in log.entries {
            try budget.consume(1)
            guard filter.severities.contains(entry.severity) else { continue }
            guard let query = filter.text, !query.isEmpty else {
                result.append(entry)
                continue
            }
            try budget.consume(bytes: entry.utf8ByteCount)
            let options: String.CompareOptions =
                filter.caseSensitive
                ? [.literal]
                : [.caseInsensitive, .literal]
            if entry.text.range(
                of: query,
                options: options,
                locale: Locale(identifier: "en_US_POSIX")
            ) != nil {
                result.append(entry)
            }
        }
        return result
    }

    fileprivate static func measure(
        _ text: String,
        maximumUTF8Bytes: Int,
        field: TextField,
        budget: inout WorkBudget
    ) throws -> Int {
        var count = 0
        for _ in text.utf8 {
            guard count < maximumUTF8Bytes else {
                throw WorkflowError.textTooLarge(
                    field: field,
                    maximumUTF8Bytes: maximumUTF8Bytes
                )
            }
            count += 1
            try budget.consume(1)
        }
        return count
    }

    fileprivate static func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
        let (value, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw WorkflowError.arithmeticOverflow }
        return value
    }

    fileprivate static func checkedMultiply(_ left: Int, _ right: Int) throws -> Int {
        let (value, overflow) = left.multipliedReportingOverflow(by: right)
        guard !overflow else { throw WorkflowError.arithmeticOverflow }
        return value
    }

    fileprivate static func requiredCASWorkUnits(
        log: OutputPaneLog,
        sensitiveMessageCount: Int,
        filterUTF8ByteCount: Int
    ) throws -> UInt64 {
        let retainedItemWork = try checkedMultiply(log.entries.count, 3)
        let selectedItemWork = try checkedMultiply(log.selectedIDs.count, 3)
        let itemWork = try checkedAdd(
            try checkedAdd(retainedItemWork, selectedItemWork),
            try checkedAdd(sensitiveMessageCount, filterUTF8ByteCount)
        )
        let total = try checkedAdd(
            try checkedAdd(itemWork, log.retainedUTF8ByteCount),
            1
        )
        return UInt64(total)
    }

    fileprivate static func exactlyMatches(
        _ expected: Snapshot,
        _ actual: Snapshot,
        budget: inout WorkBudget
    ) throws -> Bool {
        guard expected.reference == actual.reference,
            expected.visibilityPreference == actual.visibilityPreference,
            expected.filter.severities == actual.filter.severities,
            expected.filter.caseSensitive == actual.filter.caseSensitive,
            expected.sensitiveCopyPolicy == actual.sensitiveCopyPolicy,
            expected.limits == actual.limits,
            expected.log.limits == actual.log.limits,
            expected.log.entries.count == actual.log.entries.count,
            expected.log.selectedIDs.count == actual.log.selectedIDs.count,
            expected.log.retainedUTF8ByteCount == actual.log.retainedUTF8ByteCount,
            expected.securitySensitiveMessageIDs.count
                == actual.securitySensitiveMessageIDs.count
        else {
            return false
        }
        guard
            try equalOptionalUTF8(
                expected.filter.text,
                actual.filter.text,
                budget: &budget
            )
        else {
            return false
        }
        for (expectedEntry, actualEntry) in zip(expected.log.entries, actual.log.entries) {
            try budget.consume(1)
            guard expectedEntry.id == actualEntry.id,
                expectedEntry.severity == actualEntry.severity,
                expectedEntry.timestamp == actualEntry.timestamp,
                expectedEntry.utf8ByteCount == actualEntry.utf8ByteCount,
                expectedEntry.wasSanitized == actualEntry.wasSanitized,
                try equalUTF8(expectedEntry.text, actualEntry.text, budget: &budget)
            else {
                return false
            }
        }
        for id in expected.log.selectedIDs {
            try budget.consume(1)
            guard actual.log.selectedIDs.contains(id) else { return false }
        }
        for id in expected.securitySensitiveMessageIDs {
            try budget.consume(1)
            guard actual.securitySensitiveMessageIDs.contains(id) else { return false }
        }
        return try nextIdentifierMatches(expected.log, actual.log, budget: &budget)
    }

    fileprivate static func equalUTF8(
        _ expected: String,
        _ actual: String,
        budget: inout WorkBudget
    ) throws -> Bool {
        var expectedIterator = expected.utf8.makeIterator()
        var actualIterator = actual.utf8.makeIterator()
        while let expectedByte = expectedIterator.next() {
            try budget.consume(1)
            guard actualIterator.next() == expectedByte else { return false }
        }
        return actualIterator.next() == nil
    }

    fileprivate static func equalOptionalUTF8(
        _ expected: String?,
        _ actual: String?,
        budget: inout WorkBudget
    ) throws -> Bool {
        switch (expected, actual) {
        case (nil, nil):
            return true
        case (let expected?, let actual?):
            return try equalUTF8(expected, actual, budget: &budget)
        default:
            return false
        }
    }

    /// A zero-byte append on value copies exposes otherwise-private next-ID state without mutating
    /// owner state. Matching terminal exhaustion also proves both logs consumed the same ID space.
    fileprivate static func nextIdentifierMatches(
        _ expected: OutputPaneLog,
        _ actual: OutputPaneLog,
        budget: inout WorkBudget
    ) throws -> Bool {
        try budget.consume(1)
        var expectedProbe = expected
        var actualProbe = actual
        let timestamp = Date(timeIntervalSinceReferenceDate: 0)
        let expectedID: EntryID?
        let actualID: EntryID?
        try budget.consume(items: expected.entries.count)
        try budget.consume(items: expected.selectedIDs.count)
        do {
            expectedID = try expectedProbe.append(
                severity: .debug,
                timestamp: timestamp,
                text: ""
            ).entry.id
        } catch OutputPaneLogError.identifierSpaceExhausted {
            expectedID = nil
        } catch let error as OutputPaneLogError {
            throw WorkflowError.outputLog(error)
        }
        try budget.consume(items: actual.entries.count)
        try budget.consume(items: actual.selectedIDs.count)
        do {
            actualID = try actualProbe.append(
                severity: .debug,
                timestamp: timestamp,
                text: ""
            ).entry.id
        } catch OutputPaneLogError.identifierSpaceExhausted {
            actualID = nil
        } catch let error as OutputPaneLogError {
            throw WorkflowError.outputLog(error)
        }
        return expectedID == actualID
    }
}
