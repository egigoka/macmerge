import Foundation

/// UI-independent routing for Tools commands. Planning validates delegated payload feasibility and
/// retains caller-supplied workflow values exactly without acquiring authority or performing effects.
public enum ToolsCommandWorkflow: Sendable {
    public enum Command: String, CaseIterable, Codable, Hashable, Sendable {
        case filters
        case generatePatch
        case generateReport
        case generateArchive
    }

    public enum IntentKind: String, CaseIterable, Codable, Hashable, Sendable {
        case configuration
        case execution
    }

    public struct WorkspaceIdentity: RawRepresentable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var description: String { "ToolsCommandWorkflow.WorkspaceIdentity(<opaque>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    public struct WorkspaceReference: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let identity: WorkspaceIdentity
        public let revision: UInt64

        public init(identity: WorkspaceIdentity, revision: UInt64) {
            self.identity = identity
            self.revision = revision
        }

        public var description: String { "ToolsCommandWorkflow.WorkspaceReference(<opaque>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    public struct ComparisonIdentity: RawRepresentable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var description: String { "ToolsCommandWorkflow.ComparisonIdentity(<opaque>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    public struct ComparisonReference: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let identity: ComparisonIdentity
        public let revision: UInt64

        public init(identity: ComparisonIdentity, revision: UInt64) {
            self.identity = identity
            self.revision = revision
        }

        public var description: String { "ToolsCommandWorkflow.ComparisonReference(<opaque>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    public struct SourceIdentity: RawRepresentable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var description: String { "ToolsCommandWorkflow.SourceIdentity(<opaque>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    public struct SourceReference: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let identity: SourceIdentity
        public let revision: UInt64

        public init(identity: SourceIdentity, revision: UInt64) {
            self.identity = identity
            self.revision = revision
        }

        public var description: String { "ToolsCommandWorkflow.SourceReference(<opaque>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    /// Opaque owner-issued association between one command payload and current comparison state.
    /// Owners must advance `revision` whenever payload construction inputs change and never reuse an
    /// identity/revision pair for another payload.
    public struct ExecutionBindingIdentity: RawRepresentable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var description: String {
            "ToolsCommandWorkflow.ExecutionBindingIdentity(<opaque>)"
        }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    public struct ExecutionBindingReference: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let identity: ExecutionBindingIdentity
        public let revision: UInt64

        public init(identity: ExecutionBindingIdentity, revision: UInt64) {
            self.identity = identity
            self.revision = revision
        }

        public var description: String {
            "ToolsCommandWorkflow.ExecutionBindingReference(<opaque>)"
        }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    public struct ExecutionPayloadIdentity: Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        private let rawValue: UUID

        fileprivate init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionPayloadIdentity(<opaque>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<opaque>"], displayStyle: .struct)
        }
    }

    public struct ExecutionPayloadBinding: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let owner: ExecutionBindingReference
        public let payload: ExecutionPayloadIdentity

        fileprivate init(owner: ExecutionBindingReference, payload: ExecutionPayloadIdentity) {
            self.owner = owner
            self.payload = payload
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionPayloadBinding(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct ExecutionBindings: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let filters: ExecutionPayloadBinding?
        public let patch: ExecutionPayloadBinding?
        public let report: ExecutionPayloadBinding?
        public let archive: ExecutionPayloadBinding?

        public init(
            filters: ExecutionPayloadBinding? = nil,
            patch: ExecutionPayloadBinding? = nil,
            report: ExecutionPayloadBinding? = nil,
            archive: ExecutionPayloadBinding? = nil
        ) {
            self.filters = filters
            self.patch = patch
            self.report = report
            self.archive = archive
        }

        public subscript(command: Command) -> ExecutionPayloadBinding? {
            switch command {
            case .filters: filters
            case .generatePatch: patch
            case .generateReport: report
            case .generateArchive: archive
            }
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionBindings(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    /// Exact owner-issued command target. Source order is semantic and must be stable for one
    /// comparison revision.
    public struct CommandTarget: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let workspace: WorkspaceReference
        public let comparison: ComparisonReference
        public let sources: [SourceReference]

        public init(
            workspace: WorkspaceReference,
            comparison: ComparisonReference,
            sources: [SourceReference]
        ) throws {
            guard sources.count <= CurrentState.hardMaximumSourceReferences else {
                throw WorkflowError.tooManySourceReferences(
                    maximum: CurrentState.hardMaximumSourceReferences
                )
            }
            var identities: Set<SourceIdentity> = []
            identities.reserveCapacity(sources.count)
            for (index, source) in sources.enumerated() {
                if index & 0xFF == 0 {
                    do {
                        try Task.checkCancellation()
                    } catch {
                        throw WorkflowError.cancelled
                    }
                }
                guard identities.insert(source.identity).inserted else {
                    throw WorkflowError.duplicateSourceIdentity(source.identity)
                }
            }
            do {
                try Task.checkCancellation()
            } catch {
                throw WorkflowError.cancelled
            }
            self.workspace = workspace
            self.comparison = comparison
            self.sources = sources
        }

        public var description: String {
            "ToolsCommandWorkflow.CommandTarget(workspace:<opaque>, comparison:<opaque>, sources:\(sources.count))"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "workspace": "<opaque>",
                    "comparison": "<opaque>",
                    "sourceCount": sources.count
                ],
                displayStyle: .struct
            )
        }

    }

    public enum ComparisonLifecycle: String, CaseIterable, Codable, Hashable, Sendable {
        case noComparison
        case loading
        case refreshing
        case stale
        case failed
        case cancelled
        case current
    }

    /// Complete owner state consumed by command validation. Any state affecting routing must be
    /// represented by one of these values or by advancing an enclosed revision.
    public struct CurrentState: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public static let hardMaximumSourceReferences = 65_536

        public let workspace: WorkspaceReference?
        public let target: CommandTarget?
        public let executionBindings: ExecutionBindings
        public let lifecycle: ComparisonLifecycle
        public let isSessionLocked: Bool

        public init(
            workspace: WorkspaceReference? = nil,
            target: CommandTarget? = nil,
            executionBindings: ExecutionBindings = ExecutionBindings(),
            lifecycle: ComparisonLifecycle,
            isSessionLocked: Bool = false
        ) throws {
            guard (target == nil) == (lifecycle == .noComparison),
                target.map({ $0.workspace == workspace }) ?? true
            else {
                throw WorkflowError.invalidCurrentState
            }
            self.workspace = workspace
            self.target = target
            self.executionBindings = executionBindings
            self.lifecycle = lifecycle
            self.isSessionLocked = isSessionLocked
        }

        public var description: String {
            "ToolsCommandWorkflow.CurrentState(lifecycle:\(lifecycle.rawValue), workspace:\(workspace == nil ? "none" : "<opaque>"), target:\(target == nil ? "none" : "<opaque>"), session:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "lifecycle": lifecycle.rawValue,
                    "hasWorkspace": workspace != nil,
                    "hasTarget": target != nil,
                    "executionBindings": "<opaque>",
                    "session": "<redacted>",
                    "target": "<opaque>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum CapabilityUnavailableReason: String, CaseIterable, Codable, Hashable, Sendable {
        case unsupported
        case policyRestricted
        case configurationUnavailable
        case plannerUnavailable
        case executorUnavailable
    }

    public enum Support: Hashable, Sendable {
        case supported
        case unavailable(CapabilityUnavailableReason)

        public var isSupported: Bool { self == .supported }

        public var unavailableReason: CapabilityUnavailableReason? {
            guard case .unavailable(let reason) = self else { return nil }
            return reason
        }
    }

    public struct CommandCapability: Hashable, Sendable {
        public let configuration: Support
        public let execution: Support

        public init(configuration: Support, execution: Support) {
            self.configuration = configuration
            self.execution = execution
        }

        public func support(for kind: IntentKind) -> Support {
            switch kind {
            case .configuration: configuration
            case .execution: execution
            }
        }
    }

    /// Capabilities describe integration supplied by owner and platform layers; they are not inferred
    /// from request values or mutable UI state.
    public struct Capabilities: Hashable, Sendable {
        public let filters: CommandCapability
        public let patch: CommandCapability
        public let report: CommandCapability
        public let archive: CommandCapability

        public init(
            filters: CommandCapability,
            patch: CommandCapability,
            report: CommandCapability,
            archive: CommandCapability
        ) {
            self.filters = filters
            self.patch = patch
            self.report = report
            self.archive = archive
        }

        public subscript(command: Command) -> CommandCapability {
            switch command {
            case .filters: filters
            case .generatePatch: patch
            case .generateReport: report
            case .generateArchive: archive
            }
        }
    }

    public struct Context: Hashable, Sendable {
        public let capabilities: Capabilities
        public let currentState: CurrentState

        public init(capabilities: Capabilities, currentState: CurrentState) {
            self.capabilities = capabilities
            self.currentState = currentState
        }
    }

    /// Exact compare-and-swap token for routing state and integration capability state.
    public struct ContextCAS: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let expected: Context

        public init(_ context: Context) {
            expected = context
        }

        public func matches(
            _ actual: Context,
            limits: Limits = .default
        ) throws -> Bool {
            do {
                try validate(actual, limits: limits)
                return true
            } catch WorkflowError.capabilitiesChanged,
                WorkflowError.staleWorkspace,
                WorkflowError.staleComparison,
                WorkflowError.sourceReferencesChanged,
                WorkflowError.currentStateChanged
            {
                return false
            }
        }

        public func validate(
            _ actual: Context,
            limits: Limits = .default
        ) throws {
            do {
                try ToolsCommandWorkflow.validate(limits)
                var work = WorkBudget(limits: limits)
                guard actual.capabilities == expected.capabilities else {
                    throw WorkflowError.capabilitiesChanged
                }
                try work.consume(4)
                let expectedState = expected.currentState
                let actualState = actual.currentState
                guard actualState.workspace == expectedState.workspace else {
                    throw WorkflowError.staleWorkspace(
                        expected: expectedState.workspace,
                        actual: actualState.workspace
                    )
                }
                guard actualState.target?.comparison == expectedState.target?.comparison else {
                    throw WorkflowError.staleComparison(
                        expected: expectedState.target?.comparison,
                        actual: actualState.target?.comparison
                    )
                }
                let expectedSources = expectedState.target?.sources ?? []
                let actualSources = actualState.target?.sources ?? []
                guard expectedSources.count == actualSources.count else {
                    throw WorkflowError.sourceReferencesChanged
                }
                guard expectedSources.count <= limits.maximumSourceReferences else {
                    throw WorkflowError.tooManySourceReferences(
                        maximum: limits.maximumSourceReferences
                    )
                }
                for index in expectedSources.indices {
                    try work.consume(1)
                    guard expectedSources[index] == actualSources[index] else {
                        throw WorkflowError.sourceReferencesChanged
                    }
                }
                guard actualState.lifecycle == expectedState.lifecycle,
                    actualState.isSessionLocked == expectedState.isSessionLocked,
                    actualState.executionBindings == expectedState.executionBindings,
                    (actualState.target == nil) == (expectedState.target == nil)
                else {
                    throw WorkflowError.currentStateChanged
                }
                try work.finish()
            } catch {
                if Task.isCancelled { throw WorkflowError.cancelled }
                throw error
            }
        }

        public var description: String {
            "ToolsCommandWorkflow.ContextCAS(expected:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["expected": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct FilenameFilterConfiguration: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let enabled: Bool
        public let rules: [FilenameFilterRule]
        public let defaultDecision: FilenameFilterDecision
        public let matchSemantics: FilenameFilterMatchSemantics
        public let casePolicy: FilenameFilterCasePolicy
        public let limits: FilenameFilterLimits

        public init(
            enabled: Bool = true,
            rules: [FilenameFilterRule],
            defaultDecision: FilenameFilterDecision = .include,
            matchSemantics: FilenameFilterMatchSemantics = .lastMatchWins,
            casePolicy: FilenameFilterCasePolicy = .sensitive,
            limits: FilenameFilterLimits = .default
        ) {
            self.enabled = enabled
            self.rules = rules
            self.defaultDecision = defaultDecision
            self.matchSemantics = matchSemantics
            self.casePolicy = casePolicy
            self.limits = limits
        }

        public var description: String {
            "ToolsCommandWorkflow.FilenameFilterConfiguration(enabled:\(enabled), rules:\(rules.count), values:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["enabled": enabled, "ruleCount": rules.count, "values": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    /// Current filter models for configuration routing. Pattern, replacement, and expression text is
    /// intentionally absent from descriptions and mirrors.
    public struct FiltersConfiguration: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let filename: FilenameFilterConfiguration?
        public let display: DisplayFilter?
        public let lineFiltersEnabled: Bool
        public let lineFilters: [LineFilterRule]
        public let substitutionsEnabled: Bool
        public let substitutions: [SubstitutionRule]

        public init(
            filename: FilenameFilterConfiguration? = nil,
            display: DisplayFilter? = nil,
            lineFiltersEnabled: Bool = true,
            lineFilters: [LineFilterRule] = [],
            substitutionsEnabled: Bool = true,
            substitutions: [SubstitutionRule] = []
        ) {
            self.filename = filename
            self.display = display
            self.lineFiltersEnabled = lineFiltersEnabled
            self.lineFilters = lineFilters
            self.substitutionsEnabled = substitutionsEnabled
            self.substitutions = substitutions
        }

        public var description: String {
            "ToolsCommandWorkflow.FiltersConfiguration(filename:\(filename != nil), display:\(display != nil), lineRules:\(lineFilters.count), substitutions:\(substitutions.count), values:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "hasFilename": filename != nil,
                    "hasDisplay": display != nil,
                    "lineRuleCount": lineFilters.count,
                    "substitutionCount": substitutions.count,
                    "values": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Configuration routing may carry an existing request for deterministic validated prepopulation.
    /// It is advisory only and cannot be passed to an executor without a separate execution invocation.
    public enum ConfigurationIntent: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case filters(FiltersConfiguration)
        case patch(PatchGenerationRequest?)
        case report(ComparisonReportWorkflowRequest?)
        case archive(ArchiveGenerationRequest?)

        public var command: Command {
            switch self {
            case .filters: .filters
            case .patch: .generatePatch
            case .report: .generateReport
            case .archive: .generateArchive
            }
        }

        public var description: String {
            "ToolsCommandWorkflow.ConfigurationIntent.\(command.rawValue)(<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["command": command.rawValue, "value": "<redacted>"],
                displayStyle: .enum
            )
        }
    }

    public struct FilterExecutionRequest: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let ownerBinding: ExecutionBindingReference
        public let payloadIdentity: ExecutionPayloadIdentity
        public let condition: FilterTestCondition
        public let limits: FilterTestLimits

        fileprivate init(
            ownerBinding: ExecutionBindingReference,
            payloadIdentity: ExecutionPayloadIdentity,
            condition: FilterTestCondition,
            limits: FilterTestLimits = .default
        ) {
            self.ownerBinding = ownerBinding
            self.payloadIdentity = payloadIdentity
            self.condition = condition
            self.limits = limits
        }

        public var description: String {
            "ToolsCommandWorkflow.FilterExecutionRequest(<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "ownerBinding": "<opaque>",
                    "condition": "<redacted>",
                    "limits": limits
                ],
                displayStyle: .struct
            )
        }
    }

    public struct PatchExecutionRequest: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let ownerBinding: ExecutionBindingReference
        public let payloadIdentity: ExecutionPayloadIdentity
        public let request: PatchGenerationRequest

        fileprivate init(
            ownerBinding: ExecutionBindingReference,
            payloadIdentity: ExecutionPayloadIdentity,
            request: PatchGenerationRequest
        ) {
            self.ownerBinding = ownerBinding
            self.payloadIdentity = payloadIdentity
            self.request = request
        }

        public var description: String {
            "ToolsCommandWorkflow.PatchExecutionRequest(target:<opaque>, request:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["target": "<opaque>", "request": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct ReportExecutionRequest: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let ownerBinding: ExecutionBindingReference
        public let payloadIdentity: ExecutionPayloadIdentity
        public let request: ComparisonReportWorkflowRequest
        public let expectedSnapshot: ComparisonReportWorkflowSnapshotReference

        fileprivate init(
            ownerBinding: ExecutionBindingReference,
            payloadIdentity: ExecutionPayloadIdentity,
            request: ComparisonReportWorkflowRequest,
            expectedSnapshot: ComparisonReportWorkflowSnapshotReference
        ) {
            self.ownerBinding = ownerBinding
            self.payloadIdentity = payloadIdentity
            self.request = request
            self.expectedSnapshot = expectedSnapshot
        }

        public var description: String {
            "ToolsCommandWorkflow.ReportExecutionRequest(snapshot:<opaque>, request:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["snapshot": "<opaque>", "request": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct ArchiveExecutionRequest: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let ownerBinding: ExecutionBindingReference
        public let payloadIdentity: ExecutionPayloadIdentity
        public let request: ArchiveGenerationRequest
        public let expectedSnapshot: ArchiveGenerationSnapshotReference

        fileprivate init(
            ownerBinding: ExecutionBindingReference,
            payloadIdentity: ExecutionPayloadIdentity,
            request: ArchiveGenerationRequest,
            expectedSnapshot: ArchiveGenerationSnapshotReference
        ) {
            self.ownerBinding = ownerBinding
            self.payloadIdentity = payloadIdentity
            self.request = request
            self.expectedSnapshot = expectedSnapshot
        }

        public var description: String {
            "ToolsCommandWorkflow.ArchiveExecutionRequest(snapshot:<opaque>, request:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["snapshot": "<opaque>", "request": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public enum ExecutionIntent: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case filters(FilterExecutionRequest)
        case patch(PatchExecutionRequest)
        case report(ReportExecutionRequest)
        case archive(ArchiveExecutionRequest)

        public var command: Command {
            switch self {
            case .filters: .filters
            case .patch: .generatePatch
            case .report: .generateReport
            case .archive: .generateArchive
            }
        }

        public var description: String {
            "ToolsCommandWorkflow.ExecutionIntent.\(command.rawValue)(<redacted>)"
        }

        public var ownerBinding: ExecutionBindingReference {
            switch self {
            case .filters(let request): request.ownerBinding
            case .patch(let request): request.ownerBinding
            case .report(let request): request.ownerBinding
            case .archive(let request): request.ownerBinding
            }
        }

        public var payloadIdentity: ExecutionPayloadIdentity {
            switch self {
            case .filters(let request): request.payloadIdentity
            case .patch(let request): request.payloadIdentity
            case .report(let request): request.payloadIdentity
            case .archive(let request): request.payloadIdentity
            }
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["command": command.rawValue, "value": "<redacted>"],
                displayStyle: .enum
            )
        }
    }

    /// Atomically issues exact owner-state and payload bindings with their execution intent.
    public enum ExecutionIntentFactory: Sendable {
        public static func filters(
            ownerBinding: ExecutionBindingReference,
            condition: FilterTestCondition,
            limits: FilterTestLimits = .default
        ) -> (binding: ExecutionPayloadBinding, intent: ExecutionIntent) {
            issue(ownerBinding: ownerBinding) { payload in
                .filters(
                    FilterExecutionRequest(
                        ownerBinding: ownerBinding,
                        payloadIdentity: payload,
                        condition: condition,
                        limits: limits
                    )
                )
            }
        }

        public static func patch(
            ownerBinding: ExecutionBindingReference,
            request: PatchGenerationRequest
        ) -> (binding: ExecutionPayloadBinding, intent: ExecutionIntent) {
            issue(ownerBinding: ownerBinding) { payload in
                .patch(
                    PatchExecutionRequest(
                        ownerBinding: ownerBinding,
                        payloadIdentity: payload,
                        request: request
                    )
                )
            }
        }

        public static func report(
            ownerBinding: ExecutionBindingReference,
            request: ComparisonReportWorkflowRequest,
            expectedSnapshot: ComparisonReportWorkflowSnapshotReference
        ) -> (binding: ExecutionPayloadBinding, intent: ExecutionIntent) {
            issue(ownerBinding: ownerBinding) { payload in
                .report(
                    ReportExecutionRequest(
                        ownerBinding: ownerBinding,
                        payloadIdentity: payload,
                        request: request,
                        expectedSnapshot: expectedSnapshot
                    )
                )
            }
        }

        public static func archive(
            ownerBinding: ExecutionBindingReference,
            request: ArchiveGenerationRequest,
            expectedSnapshot: ArchiveGenerationSnapshotReference
        ) -> (binding: ExecutionPayloadBinding, intent: ExecutionIntent) {
            issue(ownerBinding: ownerBinding) { payload in
                .archive(
                    ArchiveExecutionRequest(
                        ownerBinding: ownerBinding,
                        payloadIdentity: payload,
                        request: request,
                        expectedSnapshot: expectedSnapshot
                    )
                )
            }
        }

        private static func issue(
            ownerBinding: ExecutionBindingReference,
            intent: (ExecutionPayloadIdentity) -> ExecutionIntent
        ) -> (binding: ExecutionPayloadBinding, intent: ExecutionIntent) {
            let payload = ExecutionPayloadIdentity(rawValue: UUID())
            return (
                ExecutionPayloadBinding(owner: ownerBinding, payload: payload),
                intent(payload)
            )
        }
    }

    public enum Intent: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case configuration(ConfigurationIntent)
        case execution(ExecutionIntent)

        public var kind: IntentKind {
            switch self {
            case .configuration: .configuration
            case .execution: .execution
            }
        }

        public var command: Command {
            switch self {
            case .configuration(let intent): intent.command
            case .execution(let intent): intent.command
            }
        }

        public var description: String {
            "ToolsCommandWorkflow.Intent.\(kind.rawValue)(command:\(command.rawValue), value:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "kind": kind.rawValue,
                    "command": command.rawValue,
                    "value": "<redacted>"
                ],
                displayStyle: .enum
            )
        }
    }

    /// Invocation binds intent to exact workspace, comparison, and ordered source revisions captured
    /// before configuration or execution was requested.
    public struct Invocation: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let target: CommandTarget
        public let intent: Intent

        public init(target: CommandTarget, intent: Intent) {
            self.target = target
            self.intent = intent
        }

        public var description: String {
            "ToolsCommandWorkflow.Invocation(command:\(intent.command.rawValue), kind:\(intent.kind.rawValue), target:<opaque>, value:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "command": intent.command.rawValue,
                    "kind": intent.kind.rawValue,
                    "target": "<opaque>",
                    "value": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        fileprivate func executionBindingMatches(_ state: CurrentState) -> Bool {
            guard case .execution(let execution) = intent else { return true }
            return state.executionBindings[execution.command]
                == ExecutionPayloadBinding(
                    owner: execution.ownerBinding,
                    payload: execution.payloadIdentity
                )
        }
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case sessionLocked
        case noWorkspace
        case noComparison
        case comparisonLoading
        case comparisonRefreshing
        case comparisonStale
        case comparisonFailed
        case comparisonCancelled
        case commandTargetChanged
        case executionBindingUnavailable(Command)
        case executionBindingChanged(Command)
        case capabilityUnavailable(IntentKind, CapabilityUnavailableReason)
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

    public struct CommandState: Equatable, Hashable, Sendable {
        public let command: Command
        public let intentKind: IntentKind
        public let expectedContext: ContextCAS
        public let availability: Availability

        fileprivate init(
            command: Command,
            intentKind: IntentKind,
            context: Context,
            availability: Availability
        ) {
            self.command = command
            self.intentKind = intentKind
            expectedContext = ContextCAS(context)
            self.availability = availability
        }

        public var isEnabled: Bool { availability.isEnabled }
        public var canExecute: Bool { isEnabled }
        public var disabledReason: DisabledReason? { availability.disabledReason }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case sourceReferences
        case boundItems
        case filterConditions
        case filterConditionDepth
        case filterRules
        case requiredEffects
        case workUnits
        case cancellationCheckInterval
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumSourceReferences = CurrentState.hardMaximumSourceReferences
        public static let hardMaximumBoundItems = 65_536
        public static let hardMaximumFilterConditions = 65_536
        public static let hardMaximumFilterConditionDepth = 256
        public static let hardMaximumFilterRules = 65_536
        public static let hardMaximumRequiredEffects = 16
        public static let hardMaximumWorkUnits: UInt64 = 16 * 1_024 * 1_024
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumSourceReferences: Int
        public let maximumBoundItems: Int
        public let maximumFilterConditions: Int
        public let maximumFilterConditionDepth: Int
        public let maximumFilterRules: Int
        public let maximumRequiredEffects: Int
        public let maximumWorkUnits: UInt64
        public let cancellationCheckInterval: Int

        public init(
            maximumSourceReferences: Int = 4_096,
            maximumBoundItems: Int = 32_768,
            maximumFilterConditions: Int = 4_096,
            maximumFilterConditionDepth: Int = 64,
            maximumFilterRules: Int = 4_096,
            maximumRequiredEffects: Int = 8,
            maximumWorkUnits: UInt64 = 1 * 1_024 * 1_024,
            cancellationCheckInterval: Int = 256
        ) {
            self.maximumSourceReferences = maximumSourceReferences
            self.maximumBoundItems = maximumBoundItems
            self.maximumFilterConditions = maximumFilterConditions
            self.maximumFilterConditionDepth = maximumFilterConditionDepth
            self.maximumFilterRules = maximumFilterRules
            self.maximumRequiredEffects = maximumRequiredEffects
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }
    }

    public enum AuthorityRequirement: Equatable, Hashable, Sendable, CustomStringConvertible {
        /// Owner must hold exact routing state through each validation effect.
        case ownerStateLease(ContextCAS)
        case patch(PatchGenerationExecutorContract)
        case report(ComparisonReportExecutorContract)
        /// Executor enforces exact requirements emitted by the delegated archive plan.
        case archive(ArchiveGenerationExecutorContract)

        public var description: String {
            switch self {
            case .ownerStateLease: "ownerStateLease(<opaque>)"
            case .patch: "patch(<required-contract>)"
            case .report: "report(<required-contract>)"
            case .archive: "archive(<required-contract>)"
            }
        }
    }

    /// Stable effect order. The executor passes a delegated planner's exact returned plan to the
    /// immediately following matching execution effect; it may not regenerate or rewrite requests.
    public enum RequiredEffect: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case validateCurrentContext
        case routeConfiguration(ConfigurationIntent)
        case evaluateFilters(FilterExecutionRequest)
        case planPatch(PatchExecutionRequest)
        case planReport(ReportExecutionRequest)
        case planArchive(ArchiveExecutionRequest)
        case revalidateCurrentContext
        case executePatchPlan
        case executeReportPlan
        case executeArchivePlan

        public var description: String {
            switch self {
            case .validateCurrentContext: "validateCurrentContext"
            case .routeConfiguration(let intent):
                "routeConfiguration(command:\(intent.command.rawValue), value:<redacted>)"
            case .evaluateFilters: "evaluateFilters(<redacted>)"
            case .planPatch: "planPatch(request:<redacted>)"
            case .planReport: "planReport(request:<redacted>, snapshot:<opaque>)"
            case .planArchive: "planArchive(request:<redacted>, snapshot:<opaque>)"
            case .revalidateCurrentContext: "revalidateCurrentContext"
            case .executePatchPlan: "executePatchPlan"
            case .executeReportPlan: "executeReportPlan"
            case .executeArchivePlan: "executeArchivePlan"
            }
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["effect": description, "value": "<redacted>"], displayStyle: .enum)
        }
    }

    public struct PlanningReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let planIdentifier: UUID
        public let command: Command
        public let intentKind: IntentKind
        public let target: CommandTarget
        public let requiredEffectCount: Int
        public let plannedWorkUnits: UInt64

        fileprivate init(
            planIdentifier: UUID,
            invocation: Invocation,
            requiredEffectCount: Int,
            plannedWorkUnits: UInt64
        ) {
            self.planIdentifier = planIdentifier
            command = invocation.intent.command
            intentKind = invocation.intent.kind
            target = invocation.target
            self.requiredEffectCount = requiredEffectCount
            self.plannedWorkUnits = plannedWorkUnits
        }

        public static func == (left: PlanningReceipt, right: PlanningReceipt) -> Bool {
            left.planIdentifier == right.planIdentifier
        }

        public var description: String {
            "ToolsCommandWorkflow.PlanningReceipt(command:\(command.rawValue), kind:\(intentKind.rawValue), effects:\(requiredEffectCount), work:\(plannedWorkUnits), target:<opaque>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "command": command.rawValue,
                    "intentKind": intentKind.rawValue,
                    "requiredEffectCount": requiredEffectCount,
                    "plannedWorkUnits": plannedWorkUnits,
                    "target": "<opaque>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum StateValidationContract: String, Hashable, Sendable {
        case exactCapabilityWorkspaceComparisonAndOrderedSourceCASBeforeRoutingAndExecution
    }

    public enum RequestBindingContract: String, Hashable, Sendable {
        case preserveExactRequestsReferencesLimitsAndConfigurationWithoutRegeneration
    }

    public enum AuthorityContract: String, Hashable, Sendable {
        case enforceDelegatedContractAndPlanAuthorityWithinOwnerStateLease
    }

    public enum EffectOrderContract: String, Hashable, Sendable {
        case executeEveryRequiredEffectOnceInOrderUsingImmediateDelegatedPlan
    }

    public enum CancellationContract: String, Hashable, Sendable {
        case boundedChecksBeforeEffectsAndTerminalReceiptOrUncertaintyAfterEffectsStart
    }

    public enum OutcomeContract: String, Hashable, Sendable {
        case reportCompletedPrefixFailedEffectUnattemptedSuffixAndContiguousUncertainty
    }

    public struct ExecutorContract: Hashable, Sendable {
        public static let required = ExecutorContract()

        public let stateValidation =
            StateValidationContract
            .exactCapabilityWorkspaceComparisonAndOrderedSourceCASBeforeRoutingAndExecution
        public let requestBinding =
            RequestBindingContract
            .preserveExactRequestsReferencesLimitsAndConfigurationWithoutRegeneration
        public let authority =
            AuthorityContract.enforceDelegatedContractAndPlanAuthorityWithinOwnerStateLease
        public let effectOrder =
            EffectOrderContract.executeEveryRequiredEffectOnceInOrderUsingImmediateDelegatedPlan
        public let cancellation =
            CancellationContract
            .boundedChecksBeforeEffectsAndTerminalReceiptOrUncertaintyAfterEffectsStart
        public let outcomes =
            OutcomeContract
            .reportCompletedPrefixFailedEffectUnattemptedSuffixAndContiguousUncertainty

        public init() {}
    }

    public struct Plan: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let identifier: UUID
        public let expectedContext: ContextCAS
        public let invocation: Invocation
        public let authorityRequirements: [AuthorityRequirement]
        public let requiredEffects: [RequiredEffect]
        public let receipt: PlanningReceipt
        public let limits: Limits
        public let executorContract: ExecutorContract

        fileprivate init(
            identifier: UUID,
            context: Context,
            invocation: Invocation,
            authorityRequirements: [AuthorityRequirement],
            requiredEffects: [RequiredEffect],
            receipt: PlanningReceipt,
            limits: Limits
        ) {
            self.identifier = identifier
            expectedContext = ContextCAS(context)
            self.invocation = invocation
            self.authorityRequirements = authorityRequirements
            self.requiredEffects = requiredEffects
            self.receipt = receipt
            self.limits = limits
            executorContract = .required
        }

        public static func == (left: Plan, right: Plan) -> Bool {
            left.identifier == right.identifier
        }

        public func validateCurrentContext(_ context: Context) throws {
            try expectedContext.validate(context, limits: limits)
        }

        public var description: String {
            "ToolsCommandWorkflow.Plan(command:\(receipt.command.rawValue), kind:\(receipt.intentKind.rawValue), effects:\(requiredEffects.count), target:<opaque>, payload:<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "command": receipt.command.rawValue,
                    "intentKind": receipt.intentKind.rawValue,
                    "authorityRequirementCount": authorityRequirements.count,
                    "requiredEffectCount": requiredEffects.count,
                    "target": "<opaque>",
                    "payload": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public final class ExecutionSession: @unchecked Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let identifier = UUID()
        fileprivate let expectedPlan: Plan
        private let lock = NSLock()
        private var completedEffectCount = 0
        private var inFlightEffect: EffectPermit?
        private var preparedBinding: PreparedBinding?
        private var completedResult: CommandResult?
        private var terminalOutcome: ExecutionOutcome?
        private var terminalOutcomeIdentifier: UUID?

        private struct PreparedBinding {
            let identifier: UUID
            let operation: PreparedOperation
        }

        fileprivate init(plan: Plan) {
            expectedPlan = plan
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionSession(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .class)
        }

        public func beginNextEffect(plan: Plan) throws -> EffectPermit {
            try Task.checkCancellation()
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                completedResult == nil,
                plan.identifier == expectedPlan.identifier,
                inFlightEffect == nil,
                completedEffectCount < plan.requiredEffects.count
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let permit = EffectPermit(
                identifier: UUID(),
                sessionIdentifier: identifier,
                planIdentifier: plan.identifier,
                effectIndex: completedEffectCount,
                effect: plan.requiredEffects[completedEffectCount]
            )
            inFlightEffect = permit
            return permit
        }

        public func completeContextValidation(
            plan: Plan,
            permit: EffectPermit,
            currentContext: Context
        ) throws {
            try plan.validateCurrentContext(currentContext)
            lock.lock()
            defer { lock.unlock() }
            guard valid(permit: permit, plan: plan),
                permit.effectIndex < plan.requiredEffects.count - 1
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            switch permit.effect {
            case .validateCurrentContext, .revalidateCurrentContext:
                completeInFlightEffect()
            default:
                throw WorkflowError.invalidExecutionOutcome
            }
        }

        private func prepare(
            plan: Plan,
            operation: PreparedOperation,
            completing permit: EffectPermit? = nil
        ) throws -> PreparedEffectsReceipt {
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                preparedBinding == nil,
                completedResult == nil,
                plan.identifier == expectedPlan.identifier
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            if let permit {
                guard valid(permit: permit, plan: plan),
                    ToolsCommandWorkflow.operation(operation, completes: permit.effect)
                else {
                    throw WorkflowError.invalidExecutionOutcome
                }
                completeInFlightEffect()
            } else {
                guard inFlightEffect == nil,
                    completedEffectCount == plan.requiredEffects.count - 1
                else {
                    throw WorkflowError.invalidExecutionOutcome
                }
            }
            let binding = PreparedBinding(identifier: UUID(), operation: operation)
            preparedBinding = binding
            return PreparedEffectsReceipt(
                sessionIdentifier: identifier,
                planIdentifier: plan.identifier,
                preparationIdentifier: binding.identifier,
                planningReceipt: plan.receipt,
                operation: operation
            )
        }

        private func record(
            plan: Plan,
            preparation: PreparedEffectsReceipt,
            permit: EffectPermit,
            result: CommandResult
        ) throws -> CompletedEffectsReceipt {
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                completedResult == nil,
                plan.identifier == expectedPlan.identifier,
                preparation.sessionIdentifier == identifier,
                preparation.planIdentifier == plan.identifier,
                preparation.planningReceipt.planIdentifier == plan.identifier,
                let preparedBinding,
                preparedBinding.identifier == preparation.preparationIdentifier,
                valid(permit: permit, plan: plan),
                permit.effectIndex == plan.requiredEffects.count - 1,
                ToolsCommandWorkflow.result(
                    result,
                    matches: plan,
                    preparationIdentifier: preparation.preparationIdentifier,
                    operation: preparedBinding.operation
                ),
                ToolsCommandWorkflow.sessionIdentifier(for: result) == identifier
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            completeInFlightEffect()
            completedResult = result
            return CompletedEffectsReceipt(
                sessionIdentifier: identifier,
                planIdentifier: plan.identifier,
                preparationIdentifier: preparation.preparationIdentifier,
                planningReceipt: plan.receipt,
                result: result
            )
        }

        fileprivate func finishCompleted(
            plan: Plan,
            receipt: CompletedEffectsReceipt
        ) throws -> ExecutionOutcome {
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                plan.identifier == expectedPlan.identifier,
                completedEffectCount == plan.requiredEffects.count,
                inFlightEffect == nil,
                receipt.sessionIdentifier == identifier,
                receipt.planIdentifier == plan.identifier,
                receipt.planningReceipt.planIdentifier == plan.identifier,
                receipt.preparationIdentifier == preparedBinding?.identifier,
                completedResult.map({ ToolsCommandWorkflow.resultsHaveSameBinding($0, receipt.result) })
                    == true
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return seal(.completed(ExecutionReceipt(plan: plan, result: receipt.result, session: self)))
        }

        fileprivate func finishNotCommitted(
            plan: Plan,
            reason: ExecutionReason
        ) throws -> ExecutionOutcome {
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                plan.identifier == expectedPlan.identifier,
                completedEffectCount == 0,
                inFlightEffect == nil,
                preparedBinding == nil,
                completedResult == nil,
                reason != .cancelled,
                reason == .authorityUnavailable
                    || ToolsCommandWorkflow.isValid(reason: reason, for: plan.requiredEffects[0])
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return seal(
                .notCommitted(ExecutionNonCommitReceipt(plan: plan, reason: reason, session: self))
            )
        }

        fileprivate func finishFailed(
            plan: Plan,
            claimedCompletedEffectCount: Int,
            reason: ExecutionReason
        ) throws -> ExecutionOutcome {
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                plan.identifier == expectedPlan.identifier,
                let inFlightEffect,
                inFlightEffect.effectIndex == completedEffectCount,
                claimedCompletedEffectCount == completedEffectCount,
                completedEffectCount < plan.requiredEffects.count,
                reason != .cancelled,
                ToolsCommandWorkflow.isValid(reason: reason, for: inFlightEffect.effect)
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            if completedEffectCount == 0 {
                return seal(
                    .notCommitted(
                        ExecutionNonCommitReceipt(plan: plan, reason: reason, session: self)
                    )
                )
            }
            return seal(
                .failedAfterEffects(
                    ExecutionFailureReceipt(
                        plan: plan,
                        completedEffectCount: completedEffectCount,
                        reason: reason,
                        session: self
                    )
                )
            )
        }

        fileprivate func finishCancelled(
            plan: Plan,
            claimedCompletedEffectCount: Int
        ) throws -> ExecutionOutcome {
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                plan.identifier == expectedPlan.identifier,
                inFlightEffect == nil,
                claimedCompletedEffectCount == completedEffectCount,
                completedEffectCount < plan.requiredEffects.count
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return seal(
                .cancelled(
                    ExecutionCancellationReceipt(
                        plan: plan,
                        completedEffectCount: completedEffectCount,
                        session: self
                    )
                )
            )
        }

        fileprivate func finishUncertain(
            plan: Plan,
            claimedCompletedEffectCount: Int,
            claimedUncertainEffectIndices: [Int]
        ) throws -> ExecutionOutcome {
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                plan.identifier == expectedPlan.identifier,
                let inFlightEffect,
                inFlightEffect.effectIndex == completedEffectCount,
                claimedCompletedEffectCount == completedEffectCount,
                claimedUncertainEffectIndices == [inFlightEffect.effectIndex]
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return seal(
                .effectUncertain(
                    ExecutionUncertaintyReceipt(
                        plan: plan,
                        completedEffectCount: completedEffectCount,
                        uncertainEffectIndices: [inFlightEffect.effectIndex],
                        session: self
                    )
                )
            )
        }

        fileprivate func normalize(_ outcome: ExecutionOutcome) -> ExecutionOutcome {
            lock.lock()
            defer { lock.unlock() }
            let binding = ToolsCommandWorkflow.outcomeBinding(for: outcome)
            if binding.sessionIdentifier == identifier,
                binding.planIdentifier == expectedPlan.identifier,
                binding.outcomeIdentifier == terminalOutcomeIdentifier,
                let terminalOutcome
            {
                return terminalOutcome
            }
            if let terminalOutcome { return terminalOutcome }
            if completedEffectCount == expectedPlan.requiredEffects.count,
                inFlightEffect == nil,
                let completedResult
            {
                return seal(
                    .completed(
                        ExecutionReceipt(
                            plan: expectedPlan,
                            result: completedResult,
                            session: self
                        )
                    )
                )
            }
            if Task.isCancelled, inFlightEffect == nil,
                completedEffectCount < expectedPlan.requiredEffects.count
            {
                return seal(
                    .cancelled(
                        ExecutionCancellationReceipt(
                            plan: expectedPlan,
                            completedEffectCount: completedEffectCount,
                            session: self
                        )
                    )
                )
            }
            let firstUncertain = min(
                inFlightEffect?.effectIndex ?? completedEffectCount,
                expectedPlan.requiredEffects.count - 1
            )
            let invalid = ExecutionOutcome.effectUncertain(
                ExecutionUncertaintyReceipt(
                    plan: expectedPlan,
                    completedEffectCount: min(completedEffectCount, firstUncertain),
                    uncertainEffectIndices: Array(firstUncertain..<expectedPlan.requiredEffects.count),
                    session: self
                )
            )
            return seal(invalid)
        }

        public func prepareConfigurationEffects(plan: Plan) throws -> PreparedEffectsReceipt {
            try Task.checkCancellation()
            guard case .configuration = plan.invocation.intent else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return try prepare(plan: plan, operation: .configuration)
        }

        public func prepareFilterEffects(plan: Plan) throws -> PreparedEffectsReceipt {
            try Task.checkCancellation()
            guard case .execution(.filters) = plan.invocation.intent else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return try prepare(plan: plan, operation: .filters)
        }

        public func preparePatchEffects(
            plan: Plan,
            permit: EffectPermit
        ) throws -> PreparedEffectsReceipt {
            try Task.checkCancellation()
            guard case .execution(.patch(let binding)) = plan.invocation.intent else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let delegatedPlan = try PatchGenerationWorkflow.plan(binding.request)
            return try prepare(
                plan: plan,
                operation: .patch(delegatedPlan),
                completing: permit
            )
        }

        public func prepareReportEffects(
            plan: Plan,
            permit: EffectPermit
        ) throws -> PreparedEffectsReceipt {
            try Task.checkCancellation()
            guard case .execution(.report(let binding)) = plan.invocation.intent else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let delegatedPlan = try ComparisonReportWorkflowPlanner.plan(
                binding.request,
                expecting: binding.expectedSnapshot
            )
            return try prepare(
                plan: plan,
                operation: .report(delegatedPlan),
                completing: permit
            )
        }

        public func prepareArchiveEffects(
            plan: Plan,
            permit: EffectPermit
        ) throws -> PreparedEffectsReceipt {
            try Task.checkCancellation()
            guard case .execution(.archive(let binding)) = plan.invocation.intent else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let delegatedPlan = try ArchiveGenerationWorkflow.plan(binding.request)
            return try prepare(
                plan: plan,
                operation: .archive(delegatedPlan),
                completing: permit
            )
        }

        public func completeConfigurationEffects(
            plan: Plan,
            preparation: PreparedEffectsReceipt,
            permit: EffectPermit
        ) throws -> CompletedEffectsReceipt {
            try Task.checkCancellation()
            guard
                case .configuration = try authenticatedOperation(
                    plan: plan,
                    preparation: preparation
                )
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return try record(
                plan: plan,
                preparation: preparation,
                permit: permit,
                result: .configuration(
                    ConfigurationReceipt(plan: plan, preparation: preparation, session: self)
                )
            )
        }

        public func completeFilterEffects(
            plan: Plan,
            preparation: PreparedEffectsReceipt,
            permit: EffectPermit,
            evaluation: FilterTestEvaluation
        ) throws -> CompletedEffectsReceipt {
            try Task.checkCancellation()
            guard case .execution(.filters(let request)) = plan.invocation.intent,
                case .filters = try authenticatedOperation(plan: plan, preparation: preparation),
                evaluation
                    == (try FilterTestEvaluator.evaluate(request.condition, limits: request.limits))
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return try record(
                plan: plan,
                preparation: preparation,
                permit: permit,
                result: .filters(
                    FilterCommandResult(
                        request: request,
                        evaluation: evaluation,
                        preparation: preparation,
                        session: self
                    )
                )
            )
        }

        public func executePatchEffects(
            plan: Plan,
            preparation: PreparedEffectsReceipt,
            with executor: any PatchGenerationPlanExecutor
        ) async throws -> CompletedEffectsReceipt {
            guard case .execution(.patch(let request)) = plan.invocation.intent,
                case .patch(let delegatedPlan) = try authenticatedOperation(
                    plan: plan,
                    preparation: preparation
                )
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let permit = try beginNextEffect(plan: plan)
            let outcome = await PatchGenerationWorkflow.execute(delegatedPlan, with: executor)
            return try record(
                plan: plan,
                preparation: preparation,
                permit: permit,
                result: .patch(
                    PatchCommandResult(
                        request: request,
                        delegatedPlan: delegatedPlan,
                        outcome: outcome,
                        preparation: preparation,
                        session: self
                    )
                )
            )
        }

        public func executeReportEffects(
            plan: Plan,
            preparation: PreparedEffectsReceipt,
            with executor: any ComparisonReportPlanExecutor
        ) async throws -> CompletedEffectsReceipt {
            guard case .execution(.report(let request)) = plan.invocation.intent,
                case .report(let delegatedPlan) = try authenticatedOperation(
                    plan: plan,
                    preparation: preparation
                )
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let permit = try beginNextEffect(plan: plan)
            let outcome = await executor.execute(
                delegatedPlan,
                validating: request.request.snapshot,
                linkedReports: request.request.linkedReports
            )
            let boundOutcome = ToolsCommandWorkflow.boundReportOutcome(
                outcome,
                to: delegatedPlan
            )
            guard boundOutcome == outcome else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return try record(
                plan: plan,
                preparation: preparation,
                permit: permit,
                result: .report(
                    ReportCommandResult(
                        request: request,
                        delegatedPlan: delegatedPlan,
                        outcome: boundOutcome,
                        preparation: preparation,
                        session: self
                    )
                )
            )
        }

        public func executeArchiveEffects(
            plan: Plan,
            preparation: PreparedEffectsReceipt,
            currentSnapshot: @escaping @Sendable () async throws -> ArchiveGenerationComparisonSnapshot,
            with executor: any ArchiveGenerationPlanExecutor
        ) async throws -> CompletedEffectsReceipt {
            guard case .execution(.archive(let request)) = plan.invocation.intent,
                case .archive(let delegatedPlan) = try authenticatedOperation(
                    plan: plan,
                    preparation: preparation
                )
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            let permit = try beginNextEffect(plan: plan)
            let outcome = await executor.execute(delegatedPlan, currentSnapshot: currentSnapshot)
            let boundOutcome = ToolsCommandWorkflow.boundArchiveOutcome(outcome, to: delegatedPlan)
            guard boundOutcome == outcome else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return try record(
                plan: plan,
                preparation: preparation,
                permit: permit,
                result: .archive(
                    ArchiveCommandResult(
                        request: request,
                        delegatedPlan: delegatedPlan,
                        outcome: boundOutcome,
                        preparation: preparation,
                        session: self
                    )
                )
            )
        }

        private func authenticatedOperation(
            plan: Plan,
            preparation: PreparedEffectsReceipt
        ) throws -> PreparedOperation {
            lock.lock()
            defer { lock.unlock() }
            guard terminalOutcome == nil,
                plan.identifier == expectedPlan.identifier,
                preparation.sessionIdentifier == identifier,
                preparation.planIdentifier == plan.identifier,
                preparation.planningReceipt.planIdentifier == plan.identifier,
                let preparedBinding,
                preparedBinding.identifier == preparation.preparationIdentifier
            else {
                throw WorkflowError.invalidExecutionOutcome
            }
            return preparedBinding.operation
        }

        private func valid(permit: EffectPermit, plan: Plan) -> Bool {
            guard let inFlightEffect else { return false }
            return plan.identifier == expectedPlan.identifier
                && permit.identifier == inFlightEffect.identifier
                && permit.sessionIdentifier == identifier
                && permit.planIdentifier == plan.identifier
                && permit.effectIndex == completedEffectCount
                && permit.effectIndex == inFlightEffect.effectIndex
                && permit.effectIndex < plan.requiredEffects.count
        }

        private func completeInFlightEffect() {
            completedEffectCount += 1
            inFlightEffect = nil
        }

        private func seal(_ outcome: ExecutionOutcome) -> ExecutionOutcome {
            terminalOutcome = outcome
            terminalOutcomeIdentifier = ToolsCommandWorkflow.outcomeBinding(for: outcome).outcomeIdentifier
            return outcome
        }
    }

    public struct EffectPermit: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let identifier: UUID
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        fileprivate let effectIndex: Int
        public let effect: RequiredEffect

        public var description: String { "ToolsCommandWorkflow.EffectPermit(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public enum PreparedOperation: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case configuration
        case filters
        case patch(PatchGenerationPlan)
        case report(ComparisonReportWorkflowPlan)
        case archive(ArchiveGenerationPlan)

        public var description: String { "ToolsCommandWorkflow.PreparedOperation(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .enum)
        }
    }

    public struct PreparedEffectsReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        fileprivate let preparationIdentifier: UUID
        public let planningReceipt: PlanningReceipt
        public let operation: PreparedOperation

        public static func == (left: PreparedEffectsReceipt, right: PreparedEffectsReceipt) -> Bool {
            left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
                && left.preparationIdentifier == right.preparationIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.PreparedEffectsReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct CompletedEffectsReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        fileprivate let preparationIdentifier: UUID
        public let planningReceipt: PlanningReceipt
        public let result: CommandResult

        public static func == (left: CompletedEffectsReceipt, right: CompletedEffectsReceipt) -> Bool {
            left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
                && left.preparationIdentifier == right.preparationIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.CompletedEffectsReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct ConfigurationReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let command: Command
        public let target: CommandTarget
        public let intent: ConfigurationIntent
        public let expectedContext: ContextCAS
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        fileprivate let preparationIdentifier: UUID

        fileprivate init(
            plan: Plan,
            preparation: PreparedEffectsReceipt,
            session: ExecutionSession
        ) {
            command = plan.receipt.command
            target = plan.receipt.target
            guard case .configuration(let intent) = plan.invocation.intent else {
                preconditionFailure("Configuration receipt requires configuration intent")
            }
            self.intent = intent
            expectedContext = plan.expectedContext
            sessionIdentifier = session.identifier
            planIdentifier = plan.identifier
            preparationIdentifier = preparation.preparationIdentifier
        }

        public static func == (left: ConfigurationReceipt, right: ConfigurationReceipt) -> Bool {
            left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
                && left.preparationIdentifier == right.preparationIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.ConfigurationReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct FilterCommandResult: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let request: FilterExecutionRequest
        public let evaluation: FilterTestEvaluation
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        fileprivate let preparationIdentifier: UUID

        fileprivate init(
            request: FilterExecutionRequest,
            evaluation: FilterTestEvaluation,
            preparation: PreparedEffectsReceipt,
            session: ExecutionSession
        ) {
            self.request = request
            self.evaluation = evaluation
            sessionIdentifier = session.identifier
            planIdentifier = preparation.planIdentifier
            preparationIdentifier = preparation.preparationIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.FilterCommandResult(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct PatchCommandResult: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let request: PatchExecutionRequest
        public let delegatedPlan: PatchGenerationPlan
        public let outcome: PatchGenerationExecutionOutcome
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        fileprivate let preparationIdentifier: UUID

        fileprivate init(
            request: PatchExecutionRequest,
            delegatedPlan: PatchGenerationPlan,
            outcome: PatchGenerationExecutionOutcome,
            preparation: PreparedEffectsReceipt,
            session: ExecutionSession
        ) {
            self.request = request
            self.delegatedPlan = delegatedPlan
            self.outcome = outcome
            sessionIdentifier = session.identifier
            planIdentifier = preparation.planIdentifier
            preparationIdentifier = preparation.preparationIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.PatchCommandResult(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct ReportCommandResult: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let request: ReportExecutionRequest
        public let delegatedPlan: ComparisonReportWorkflowPlan
        public let outcome: ComparisonReportExecutionOutcome
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        fileprivate let preparationIdentifier: UUID

        fileprivate init(
            request: ReportExecutionRequest,
            delegatedPlan: ComparisonReportWorkflowPlan,
            outcome: ComparisonReportExecutionOutcome,
            preparation: PreparedEffectsReceipt,
            session: ExecutionSession
        ) {
            self.request = request
            self.delegatedPlan = delegatedPlan
            self.outcome = outcome
            sessionIdentifier = session.identifier
            planIdentifier = preparation.planIdentifier
            preparationIdentifier = preparation.preparationIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.ReportCommandResult(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct ArchiveCommandResult: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let request: ArchiveExecutionRequest
        public let delegatedPlan: ArchiveGenerationPlan
        public let outcome: ArchiveGenerationExecutionOutcome
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        fileprivate let preparationIdentifier: UUID

        fileprivate init(
            request: ArchiveExecutionRequest,
            delegatedPlan: ArchiveGenerationPlan,
            outcome: ArchiveGenerationExecutionOutcome,
            preparation: PreparedEffectsReceipt,
            session: ExecutionSession
        ) {
            self.request = request
            self.delegatedPlan = delegatedPlan
            self.outcome = outcome
            sessionIdentifier = session.identifier
            planIdentifier = preparation.planIdentifier
            preparationIdentifier = preparation.preparationIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.ArchiveCommandResult(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    /// Terminal delegated result. Existing workflow outcomes remain intact, including their own
    /// publication uncertainty and partial-publication evidence.
    public enum CommandResult: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case configuration(ConfigurationReceipt)
        case filters(FilterCommandResult)
        case patch(PatchCommandResult)
        case report(ReportCommandResult)
        case archive(ArchiveCommandResult)

        public var command: Command {
            switch self {
            case .configuration(let receipt): receipt.command
            case .filters: .filters
            case .patch: .generatePatch
            case .report: .generateReport
            case .archive: .generateArchive
            }
        }

        public var description: String {
            "ToolsCommandWorkflow.CommandResult.\(command.rawValue)(<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["command": command.rawValue, "value": "<redacted>"],
                displayStyle: .enum
            )
        }
    }

    public enum ExecutionReason: String, CaseIterable, Codable, Hashable, Sendable {
        case cancelled
        case staleContext
        case authorityUnavailable
        case delegatedPlanningFailed
        case delegatedExecutionFailed
        case contractUnsupported
        case rejected
    }

    public struct ExecutionReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let outcomeIdentifier: UUID
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        public let planningReceipt: PlanningReceipt
        public let completedEffects: [RequiredEffect]
        public let result: CommandResult

        fileprivate init(plan: Plan, result: CommandResult, session: ExecutionSession) {
            outcomeIdentifier = UUID()
            sessionIdentifier = session.identifier
            planIdentifier = plan.identifier
            planningReceipt = plan.receipt
            completedEffects = plan.requiredEffects
            self.result = result
        }

        public static func == (left: ExecutionReceipt, right: ExecutionReceipt) -> Bool {
            left.outcomeIdentifier == right.outcomeIdentifier
                && left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct ExecutionNonCommitReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let outcomeIdentifier: UUID
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        public let planningReceipt: PlanningReceipt
        public let blockedEffect: RequiredEffect
        public let reason: ExecutionReason
        public let unattemptedEffects: [RequiredEffect]

        fileprivate init(plan: Plan, reason: ExecutionReason, session: ExecutionSession) {
            outcomeIdentifier = UUID()
            sessionIdentifier = session.identifier
            planIdentifier = plan.identifier
            planningReceipt = plan.receipt
            blockedEffect = plan.requiredEffects[0]
            self.reason = reason
            unattemptedEffects = Array(plan.requiredEffects.dropFirst())
        }

        public static func == (left: ExecutionNonCommitReceipt, right: ExecutionNonCommitReceipt) -> Bool {
            left.outcomeIdentifier == right.outcomeIdentifier
                && left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionNonCommitReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct ExecutionFailureReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let outcomeIdentifier: UUID
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        public let planningReceipt: PlanningReceipt
        public let completedEffects: [RequiredEffect]
        public let failedEffect: RequiredEffect
        public let reason: ExecutionReason
        public let unattemptedEffects: [RequiredEffect]

        fileprivate init(
            plan: Plan,
            completedEffectCount: Int,
            reason: ExecutionReason,
            session: ExecutionSession
        ) {
            outcomeIdentifier = UUID()
            sessionIdentifier = session.identifier
            planIdentifier = plan.identifier
            planningReceipt = plan.receipt
            completedEffects = Array(plan.requiredEffects.prefix(completedEffectCount))
            failedEffect = plan.requiredEffects[completedEffectCount]
            self.reason = reason
            unattemptedEffects = Array(plan.requiredEffects.dropFirst(completedEffectCount + 1))
        }

        public static func == (left: ExecutionFailureReceipt, right: ExecutionFailureReceipt) -> Bool {
            left.outcomeIdentifier == right.outcomeIdentifier
                && left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionFailureReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct ExecutionCancellationReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let outcomeIdentifier: UUID
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        public let planningReceipt: PlanningReceipt
        public let completedEffects: [RequiredEffect]
        public let unattemptedEffects: [RequiredEffect]

        fileprivate init(plan: Plan, completedEffectCount: Int, session: ExecutionSession) {
            outcomeIdentifier = UUID()
            sessionIdentifier = session.identifier
            planIdentifier = plan.identifier
            planningReceipt = plan.receipt
            completedEffects = Array(plan.requiredEffects.prefix(completedEffectCount))
            unattemptedEffects = Array(plan.requiredEffects.dropFirst(completedEffectCount))
        }

        public static func == (
            left: ExecutionCancellationReceipt,
            right: ExecutionCancellationReceipt
        ) -> Bool {
            left.outcomeIdentifier == right.outcomeIdentifier
                && left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionCancellationReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct ExecutionUncertaintyReceipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate let outcomeIdentifier: UUID
        fileprivate let sessionIdentifier: UUID
        fileprivate let planIdentifier: UUID
        public let planningReceipt: PlanningReceipt
        public let completedEffects: [RequiredEffect]
        public let uncertainEffects: [RequiredEffect]
        public let unattemptedEffects: [RequiredEffect]

        fileprivate init(
            plan: Plan,
            completedEffectCount: Int,
            uncertainEffectIndices: [Int],
            session: ExecutionSession
        ) {
            outcomeIdentifier = UUID()
            sessionIdentifier = session.identifier
            planIdentifier = plan.identifier
            planningReceipt = plan.receipt
            completedEffects = Array(plan.requiredEffects.prefix(completedEffectCount))
            uncertainEffects = uncertainEffectIndices.map { plan.requiredEffects[$0] }
            unattemptedEffects = Array(
                plan.requiredEffects.dropFirst(uncertainEffectIndices[uncertainEffectIndices.count - 1] + 1)
            )
        }

        public static func == (
            left: ExecutionUncertaintyReceipt,
            right: ExecutionUncertaintyReceipt
        ) -> Bool {
            left.outcomeIdentifier == right.outcomeIdentifier
                && left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
        }

        public var description: String { "ToolsCommandWorkflow.ExecutionUncertaintyReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public enum ExecutionOutcome: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        case completed(ExecutionReceipt)
        /// No required effect occurred.
        case notCommitted(ExecutionNonCommitReceipt)
        case failedAfterEffects(ExecutionFailureReceipt)
        case cancelled(ExecutionCancellationReceipt)
        case effectUncertain(ExecutionUncertaintyReceipt)

        public var description: String { "ToolsCommandWorkflow.ExecutionOutcome(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .enum)
        }
    }

    fileprivate static func result(
        _ result: CommandResult,
        matches plan: Plan,
        preparationIdentifier: UUID,
        operation: PreparedOperation
    ) -> Bool {
        switch (plan.invocation.intent, result) {
        case (.configuration(let intent), .configuration(let receipt)):
            guard receipt.command == intent.command,
                receipt.planIdentifier == plan.identifier,
                receipt.preparationIdentifier == preparationIdentifier
            else { return false }
            return true
        case (.execution(.filters), .filters(let result)):
            return result.planIdentifier == plan.identifier
                && result.preparationIdentifier == preparationIdentifier
        case (.execution(.patch), .patch(let result)):
            guard case .patch = operation else { return false }
            return result.planIdentifier == plan.identifier
                && result.preparationIdentifier == preparationIdentifier
        case (.execution(.report), .report(let result)):
            guard case .report = operation else { return false }
            return result.planIdentifier == plan.identifier
                && result.preparationIdentifier == preparationIdentifier
        case (.execution(.archive), .archive(let result)):
            guard case .archive = operation else { return false }
            return result.planIdentifier == plan.identifier
                && result.preparationIdentifier == preparationIdentifier
        default:
            return false
        }
    }

    fileprivate static func operation(
        _ operation: PreparedOperation,
        completes effect: RequiredEffect
    ) -> Bool {
        switch (operation, effect) {
        case (.patch, .planPatch), (.report, .planReport), (.archive, .planArchive): true
        default: false
        }
    }

    fileprivate static func resultsHaveSameBinding(
        _ left: CommandResult,
        _ right: CommandResult
    ) -> Bool {
        switch (left, right) {
        case (.configuration(let left), .configuration(let right)):
            left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
                && left.preparationIdentifier == right.preparationIdentifier
        case (.filters(let left), .filters(let right)):
            left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
                && left.preparationIdentifier == right.preparationIdentifier
        case (.patch(let left), .patch(let right)):
            left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
                && left.preparationIdentifier == right.preparationIdentifier
        case (.report(let left), .report(let right)):
            left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
                && left.preparationIdentifier == right.preparationIdentifier
        case (.archive(let left), .archive(let right)):
            left.sessionIdentifier == right.sessionIdentifier
                && left.planIdentifier == right.planIdentifier
                && left.preparationIdentifier == right.preparationIdentifier
        default:
            false
        }
    }

    fileprivate static func sessionIdentifier(for result: CommandResult) -> UUID {
        switch result {
        case .configuration(let receipt): receipt.sessionIdentifier
        case .filters(let result): result.sessionIdentifier
        case .patch(let result): result.sessionIdentifier
        case .report(let result): result.sessionIdentifier
        case .archive(let result): result.sessionIdentifier
        }
    }

    fileprivate static func boundReportOutcome(
        _ outcome: ComparisonReportExecutionOutcome,
        to plan: ComparisonReportWorkflowPlan
    ) -> ComparisonReportExecutionOutcome {
        switch outcome {
        case .completed(let result):
            return ComparisonReportExecutionOutcomeFactory.completed(
                plan: plan,
                dispositions: result.outputs.map(\.disposition),
                openOutcome: result.openOutcome
            )
        case .failed(let failure):
            return ComparisonReportExecutionOutcomeFactory.failed(
                plan: plan,
                code: failure.code,
                outputIdentity: failure.outputIdentity,
                completedDispositions: failure.completedOutputs.map(\.disposition)
            )
        case .cancelled(let cancellation):
            return ComparisonReportExecutionOutcomeFactory.cancelled(
                plan: plan,
                completedDispositions: cancellation.completedOutputs.map(\.disposition)
            )
        case .publicationUncertain(let uncertainty):
            let completedCount = uncertainty.completedOutputs.count
            let uncertainIndices: [Int]
            if uncertainty.outputIdentities.count == 1,
                completedCount < plan.outputs.count,
                uncertainty.outputIdentities[0]
                    == plan.outputs[completedCount].destination.outputIdentity
            {
                uncertainIndices = [completedCount]
            } else {
                uncertainIndices = []
            }
            return ComparisonReportExecutionOutcomeFactory.publicationUncertain(
                plan: plan,
                uncertainOutputIndices: uncertainIndices,
                completedDispositions: uncertainty.completedOutputs.map(\.disposition)
            )
        }
    }

    fileprivate static func archiveOutcome(
        _ outcome: ArchiveGenerationExecutionOutcome,
        matches plan: ArchiveGenerationPlan
    ) -> Bool {
        switch outcome {
        case .completed(let receipt):
            let disposition: ArchiveGenerationExecutionDisposition
            switch plan.destination.intent {
            case .createNew: disposition = .created
            case .replaceExisting: disposition = .replaced
            }
            return receipt.planSHA256 == plan.receipt.planSHA256
                && receipt.disposition == disposition
                && receipt.archivedItemCount == plan.manifest.entries.count
                && receipt.archivedSourceByteCount == plan.manifest.totalUncompressedByteCount
                && receipt.committedByteCount <= plan.manifest.planningArchiveByteEnvelope
                && receipt.archiveContentSHA256.count == 32
        case .failed(let failure):
            return failure.destinationURL == plan.destination.intent.canonicalURL
        case .cancelled(let cancellation):
            return !cancellation.publicationStarted
        case .publicationUncertain(let uncertainty):
            return uncertainty.destinationURL == plan.destination.intent.canonicalURL
                && uncertainty.planSHA256 == plan.receipt.planSHA256
        }
    }

    fileprivate static func boundArchiveOutcome(
        _ outcome: ArchiveGenerationExecutionOutcome,
        to plan: ArchiveGenerationPlan
    ) -> ArchiveGenerationExecutionOutcome {
        switch outcome {
        case .completed:
            return archiveOutcome(outcome, matches: plan)
                ? outcome
                : ArchiveGenerationExecutionOutcomeFactory.publicationUncertain(plan: plan)
        case .failed(let failure):
            return ArchiveGenerationExecutionOutcomeFactory.failed(
                plan: plan,
                code: failure.code
            )
        case .cancelled:
            return ArchiveGenerationExecutionOutcomeFactory.cancelled(plan: plan)
        case .publicationUncertain:
            return ArchiveGenerationExecutionOutcomeFactory.publicationUncertain(plan: plan)
        }
    }

    private struct OutcomeBinding {
        let outcomeIdentifier: UUID
        let sessionIdentifier: UUID
        let planIdentifier: UUID
    }

    private static func outcomeBinding(for outcome: ExecutionOutcome) -> OutcomeBinding {
        switch outcome {
        case .completed(let receipt):
            OutcomeBinding(
                outcomeIdentifier: receipt.outcomeIdentifier,
                sessionIdentifier: receipt.sessionIdentifier,
                planIdentifier: receipt.planIdentifier
            )
        case .notCommitted(let receipt):
            OutcomeBinding(
                outcomeIdentifier: receipt.outcomeIdentifier,
                sessionIdentifier: receipt.sessionIdentifier,
                planIdentifier: receipt.planIdentifier
            )
        case .failedAfterEffects(let receipt):
            OutcomeBinding(
                outcomeIdentifier: receipt.outcomeIdentifier,
                sessionIdentifier: receipt.sessionIdentifier,
                planIdentifier: receipt.planIdentifier
            )
        case .cancelled(let receipt):
            OutcomeBinding(
                outcomeIdentifier: receipt.outcomeIdentifier,
                sessionIdentifier: receipt.sessionIdentifier,
                planIdentifier: receipt.planIdentifier
            )
        case .effectUncertain(let receipt):
            OutcomeBinding(
                outcomeIdentifier: receipt.outcomeIdentifier,
                sessionIdentifier: receipt.sessionIdentifier,
                planIdentifier: receipt.planIdentifier
            )
        }
    }

    /// Seals outer receipts. Delegated workflow factories remain authoritative for their nested
    /// terminal outcomes.
    public enum ExecutionOutcomeFactory: Sendable {
        public static func completed(
            plan: Plan,
            session: ExecutionSession,
            receipt: CompletedEffectsReceipt
        ) throws -> ExecutionOutcome {
            try session.finishCompleted(plan: plan, receipt: receipt)
        }

        public static func notCommitted(
            plan: Plan,
            session: ExecutionSession,
            reason: ExecutionReason
        ) throws -> ExecutionOutcome {
            try session.finishNotCommitted(plan: plan, reason: reason)
        }

        public static func failed(
            plan: Plan,
            session: ExecutionSession,
            completedEffectCount: Int,
            reason: ExecutionReason
        ) throws -> ExecutionOutcome {
            try session.finishFailed(
                plan: plan,
                claimedCompletedEffectCount: completedEffectCount,
                reason: reason
            )
        }

        public static func cancelled(
            plan: Plan,
            session: ExecutionSession,
            completedEffectCount: Int = 0
        ) throws -> ExecutionOutcome {
            try session.finishCancelled(
                plan: plan,
                claimedCompletedEffectCount: completedEffectCount
            )
        }

        public static func effectUncertain(
            plan: Plan,
            session: ExecutionSession,
            completedEffectCount: Int = 0,
            uncertainEffectIndices: [Int]
        ) throws -> ExecutionOutcome {
            try session.finishUncertain(
                plan: plan,
                claimedCompletedEffectCount: completedEffectCount,
                claimedUncertainEffectIndices: uncertainEffectIndices
            )
        }
    }

    fileprivate static func isValid(reason: ExecutionReason, for effect: RequiredEffect) -> Bool {
        switch (reason, effect) {
        case (.staleContext, .validateCurrentContext),
            (.staleContext, .revalidateCurrentContext),
            (.authorityUnavailable, .executePatchPlan),
            (.authorityUnavailable, .executeReportPlan),
            (.authorityUnavailable, .executeArchivePlan),
            (.delegatedPlanningFailed, .planPatch),
            (.delegatedPlanningFailed, .planReport),
            (.delegatedPlanningFailed, .planArchive),
            (.delegatedExecutionFailed, .evaluateFilters),
            (.delegatedExecutionFailed, .executePatchPlan),
            (.delegatedExecutionFailed, .executeReportPlan),
            (.delegatedExecutionFailed, .executeArchivePlan),
            (.contractUnsupported, _),
            (.rejected, _):
            true
        case (.cancelled, _):
            false
        default:
            false
        }
    }

    /// Side-effect implementation supplied by owner/app layer. It must enforce
    /// `ExecutorContract.required`, obtain current context independently, and return a sealed outcome.
    public protocol PlanExecutor: Sendable {
        func execute(
            _ plan: Plan,
            session: ExecutionSession,
            currentContext: @escaping @Sendable () async throws -> Context
        ) async -> ExecutionOutcome
    }

    /// Workflow-owned entry point. Returned outcomes are always normalized to this exact plan/session.
    public static func execute(
        _ plan: Plan,
        with executor: any PlanExecutor,
        currentContext: @escaping @Sendable () async throws -> Context
    ) async -> ExecutionOutcome {
        let session = ExecutionSession(plan: plan)
        if Task.isCancelled,
            let cancelled = try? ExecutionOutcomeFactory.cancelled(plan: plan, session: session)
        {
            return cancelled
        }
        let outcome = await executor.execute(plan, session: session, currentContext: currentContext)
        return session.normalize(outcome)
    }

    public enum WorkflowError: Error, Equatable, LocalizedError, Sendable {
        case cancelled
        case invalidCurrentState
        case invalidFilterTestLimits
        case duplicateSourceIdentity(SourceIdentity)
        case tooManySourceReferences(maximum: Int)
        case invalidLimit(Limit)
        case boundItemLimitExceeded(maximum: Int)
        case filterConditionLimitExceeded(maximum: Int)
        case filterConditionDepthExceeded(maximum: Int)
        case filterRuleLimitExceeded(maximum: Int)
        case requiredEffectLimitExceeded(maximum: Int)
        case workLimitExceeded(maximumUnits: UInt64)
        case commandTargetChanged
        case capabilitiesChanged
        case staleWorkspace(expected: WorkspaceReference?, actual: WorkspaceReference?)
        case staleComparison(expected: ComparisonReference?, actual: ComparisonReference?)
        case sourceReferencesChanged
        case currentStateChanged
        case executionBindingChanged(Command)
        case delegatedReferenceMismatch(Command)
        case commandDisabled(command: Command, reason: DisabledReason)
        case invalidExecutionOutcome
        case arithmeticOverflow

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "Tools command planning was cancelled."
            case .invalidCurrentState:
                "Tools command state has an inconsistent comparison lifecycle and target."
            case .invalidFilterTestLimits:
                "Tools command filter-test limits exceed the workflow hard envelope."
            case .duplicateSourceIdentity:
                "Tools command state repeats an opaque source identity."
            case .tooManySourceReferences(let maximum):
                "Tools command state exceeds the \(maximum)-source limit."
            case .invalidLimit(let limit):
                "Invalid Tools command workflow limit: \(limit.rawValue)."
            case .boundItemLimitExceeded(let maximum):
                "Tools command routing exceeds the \(maximum)-item binding limit."
            case .filterConditionLimitExceeded(let maximum):
                "Tools command routing exceeds the \(maximum)-condition filter limit."
            case .filterConditionDepthExceeded(let maximum):
                "Tools command routing exceeds the \(maximum)-level filter-condition depth limit."
            case .filterRuleLimitExceeded(let maximum):
                "Tools command routing exceeds the \(maximum)-rule filter limit."
            case .requiredEffectLimitExceeded(let maximum):
                "Tools command routing exceeds the \(maximum)-effect limit."
            case .workLimitExceeded(let maximum):
                "Tools command routing exceeds the \(maximum)-unit work limit."
            case .commandTargetChanged:
                "Tools command target no longer matches current workspace, comparison, and sources."
            case .capabilitiesChanged:
                "Tools command integration capabilities changed after planning."
            case .staleWorkspace:
                "Tools command workspace identity or revision is stale."
            case .staleComparison:
                "Tools command comparison identity or revision is stale."
            case .sourceReferencesChanged:
                "Tools command source identities, revisions, or order changed after planning."
            case .currentStateChanged:
                "Tools command owner state changed after planning."
            case .executionBindingChanged(let command):
                "Tools command \(command.rawValue) payload binding changed after planning."
            case .delegatedReferenceMismatch(let command):
                "Tools command \(command.rawValue) request does not match its exact delegated snapshot reference."
            case .commandDisabled(let command, _):
                "Tools command is disabled: \(command.rawValue)."
            case .invalidExecutionOutcome:
                "Tools command execution outcome contradicts required effect order or intent."
            case .arithmeticOverflow:
                "Tools command routing size calculation overflowed."
            }
        }
    }

    /// Resolves Tools menu state. Menu activation always starts as configuration intent.
    public static func commandState(for command: Command, in context: Context) -> CommandState {
        commandState(for: command, intentKind: .configuration, in: context)
    }

    public static func commandState(
        for command: Command,
        intentKind: IntentKind,
        in context: Context
    ) -> CommandState {
        CommandState(
            command: command,
            intentKind: intentKind,
            context: context,
            availability: availability(for: command, intentKind: intentKind, in: context)
        )
    }

    public static func commandState(
        for invocation: Invocation,
        in context: Context,
        limits: Limits = .default
    ) throws -> CommandState {
        do {
            try Task.checkCancellation()
            let resolved = commandState(
                for: invocation.intent.command,
                intentKind: invocation.intent.kind,
                in: context
            )
            try validate(limits)
            guard invocation.target.sources.count <= limits.maximumSourceReferences else {
                throw WorkflowError.tooManySourceReferences(maximum: limits.maximumSourceReferences)
            }
            var work = WorkBudget(limits: limits)
            guard
                try targetsEqual(
                    invocation.target,
                    context.currentState.target,
                    limits: limits,
                    work: &work
                )
            else {
                try work.finish()
                return CommandState(
                    command: invocation.intent.command,
                    intentKind: invocation.intent.kind,
                    context: context,
                    availability: .disabled(.commandTargetChanged)
                )
            }
            guard invocation.executionBindingMatches(context.currentState) else {
                try work.finish()
                return CommandState(
                    command: invocation.intent.command,
                    intentKind: invocation.intent.kind,
                    context: context,
                    availability: .disabled(.executionBindingChanged(invocation.intent.command))
                )
            }
            try work.consume(1)
            try validate(invocation, limits: limits, work: &work)
            let effects = requiredEffects(for: invocation.intent)
            guard effects.count <= limits.maximumRequiredEffects else {
                throw WorkflowError.requiredEffectLimitExceeded(
                    maximum: limits.maximumRequiredEffects
                )
            }
            try work.consume(UInt64(effects.count))
            try work.finish()
            return resolved
        } catch {
            if Task.isCancelled { throw WorkflowError.cancelled }
            throw error
        }
    }

    public static func commandStates(in context: Context) -> [CommandState] {
        Command.allCases.map { commandState(for: $0, in: context) }
    }

    /// Constructs routing and validates complete delegated payload feasibility. Delegated execution
    /// still occurs later as explicit required effects under an authenticated execution session.
    public static func plan(
        _ invocation: Invocation,
        in context: Context,
        limits: Limits = .default
    ) throws -> Plan {
        do {
            try Task.checkCancellation()
            try validate(limits)
            guard invocation.target.sources.count <= limits.maximumSourceReferences else {
                throw WorkflowError.tooManySourceReferences(maximum: limits.maximumSourceReferences)
            }
            var work = WorkBudget(limits: limits)
            guard
                try targetsEqual(
                    invocation.target,
                    context.currentState.target,
                    limits: limits,
                    work: &work
                )
            else {
                throw WorkflowError.commandTargetChanged
            }
            guard invocation.executionBindingMatches(context.currentState) else {
                throw WorkflowError.executionBindingChanged(invocation.intent.command)
            }
            let state = commandState(
                for: invocation.intent.command,
                intentKind: invocation.intent.kind,
                in: context
            )
            guard state.isEnabled else {
                throw WorkflowError.commandDisabled(
                    command: invocation.intent.command,
                    reason: state.disabledReason!
                )
            }

            try work.consume(1)
            try validate(invocation, limits: limits, work: &work)
            let effects = requiredEffects(for: invocation.intent)
            guard effects.count <= limits.maximumRequiredEffects else {
                throw WorkflowError.requiredEffectLimitExceeded(
                    maximum: limits.maximumRequiredEffects
                )
            }
            try work.consume(UInt64(effects.count))
            try work.finish()

            let identifier = UUID()
            let receipt = PlanningReceipt(
                planIdentifier: identifier,
                invocation: invocation,
                requiredEffectCount: effects.count,
                plannedWorkUnits: work.consumed
            )
            return Plan(
                identifier: identifier,
                context: context,
                invocation: invocation,
                authorityRequirements: authorityRequirements(
                    for: invocation,
                    context: context
                ),
                requiredEffects: effects,
                receipt: receipt,
                limits: limits
            )
        } catch {
            if Task.isCancelled { throw WorkflowError.cancelled }
            throw error
        }
    }
}

extension ToolsCommandWorkflow {
    fileprivate struct WorkBudget {
        let limits: Limits
        private(set) var consumed: UInt64 = 0
        private var workSinceCancellationCheck = 0

        init(limits: Limits) {
            self.limits = limits
        }

        mutating func consume(_ amount: UInt64) throws {
            let (next, overflow) = consumed.addingReportingOverflow(amount)
            guard !overflow else { throw WorkflowError.arithmeticOverflow }
            guard next <= limits.maximumWorkUnits else {
                throw WorkflowError.workLimitExceeded(maximumUnits: limits.maximumWorkUnits)
            }
            consumed = next
            let boundedAmount = min(amount, UInt64(Int.max))
            let (nextCheck, checkOverflow) = workSinceCancellationCheck.addingReportingOverflow(
                Int(boundedAmount)
            )
            workSinceCancellationCheck = checkOverflow ? limits.cancellationCheckInterval : nextCheck
            if workSinceCancellationCheck >= limits.cancellationCheckInterval {
                try Task.checkCancellation()
                workSinceCancellationCheck = 0
            }
        }

        mutating func finish() throws {
            try Task.checkCancellation()
        }
    }

    fileprivate static func availability(
        for command: Command,
        intentKind: IntentKind,
        in context: Context
    ) -> Availability {
        let state = context.currentState
        if state.isSessionLocked { return .disabled(.sessionLocked) }
        guard state.target != nil else {
            return .disabled(state.workspace == nil ? .noWorkspace : .noComparison)
        }
        switch state.lifecycle {
        case .noComparison: return .disabled(.noComparison)
        case .loading: return .disabled(.comparisonLoading)
        case .refreshing: return .disabled(.comparisonRefreshing)
        case .stale: return .disabled(.comparisonStale)
        case .failed: return .disabled(.comparisonFailed)
        case .cancelled: return .disabled(.comparisonCancelled)
        case .current: break
        }
        let support = context.capabilities[command].support(for: intentKind)
        if let reason = support.unavailableReason {
            return .disabled(.capabilityUnavailable(intentKind, reason))
        }
        if intentKind == .execution, state.executionBindings[command] == nil {
            return .disabled(.executionBindingUnavailable(command))
        }
        return .enabled
    }

    fileprivate static func validate(_ limits: Limits) throws {
        guard (0...Limits.hardMaximumSourceReferences).contains(limits.maximumSourceReferences) else {
            throw WorkflowError.invalidLimit(.sourceReferences)
        }
        guard (0...Limits.hardMaximumBoundItems).contains(limits.maximumBoundItems) else {
            throw WorkflowError.invalidLimit(.boundItems)
        }
        guard (0...Limits.hardMaximumFilterConditions).contains(limits.maximumFilterConditions) else {
            throw WorkflowError.invalidLimit(.filterConditions)
        }
        guard
            (1...Limits.hardMaximumFilterConditionDepth).contains(
                limits.maximumFilterConditionDepth
            )
        else {
            throw WorkflowError.invalidLimit(.filterConditionDepth)
        }
        guard (0...Limits.hardMaximumFilterRules).contains(limits.maximumFilterRules) else {
            throw WorkflowError.invalidLimit(.filterRules)
        }
        guard (1...Limits.hardMaximumRequiredEffects).contains(limits.maximumRequiredEffects) else {
            throw WorkflowError.invalidLimit(.requiredEffects)
        }
        guard limits.maximumWorkUnits <= Limits.hardMaximumWorkUnits else {
            throw WorkflowError.invalidLimit(.workUnits)
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
        _ invocation: Invocation,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        guard invocation.target.sources.count <= limits.maximumSourceReferences else {
            throw WorkflowError.tooManySourceReferences(maximum: limits.maximumSourceReferences)
        }
        try work.consume(UInt64(invocation.target.sources.count))

        switch invocation.intent {
        case .configuration(let intent):
            try validate(intent, limits: limits, work: &work)
        case .execution(let intent):
            try validate(intent, limits: limits, work: &work)
        }
    }

    fileprivate static func targetsEqual(
        _ expected: CommandTarget,
        _ actual: CommandTarget?,
        limits: Limits,
        work: inout WorkBudget
    ) throws -> Bool {
        guard let actual,
            expected.workspace == actual.workspace,
            expected.comparison == actual.comparison,
            expected.sources.count == actual.sources.count,
            expected.sources.count <= limits.maximumSourceReferences
        else {
            return false
        }
        for index in expected.sources.indices {
            try work.consume(1)
            guard expected.sources[index] == actual.sources[index] else { return false }
        }
        return true
    }

    fileprivate static func validate(
        _ intent: ConfigurationIntent,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        switch intent {
        case .filters(let configuration):
            let filenameRules = configuration.filename?.rules.count ?? 0
            let (partial, firstOverflow) = filenameRules.addingReportingOverflow(
                configuration.lineFilters.count
            )
            let (ruleCount, secondOverflow) = partial.addingReportingOverflow(
                configuration.substitutions.count
            )
            guard !firstOverflow, !secondOverflow else {
                throw WorkflowError.arithmeticOverflow
            }
            guard ruleCount <= limits.maximumFilterRules else {
                throw WorkflowError.filterRuleLimitExceeded(maximum: limits.maximumFilterRules)
            }
            try work.consume(UInt64(ruleCount))
            if let filename = configuration.filename {
                guard filename.rules.count <= filename.limits.maximumRuleCount else {
                    throw WorkflowError.filterRuleLimitExceeded(
                        maximum: filename.limits.maximumRuleCount
                    )
                }
                _ = try FilenameFilter(
                    rules: filename.rules,
                    defaultDecision: filename.defaultDecision,
                    matchSemantics: filename.matchSemantics,
                    casePolicy: filename.casePolicy,
                    limits: filename.limits
                )
            }
            try configuration.display?.validate()
            let validationOptions = LineDiffOptions(
                lineFiltersEnabled: configuration.lineFiltersEnabled,
                lineFilters: configuration.lineFilters,
                substitutionsEnabled: configuration.substitutionsEnabled,
                substitutions: configuration.substitutions
            )
            _ = try LineDiff.compare(left: "", right: "", options: validationOptions)
        case .patch(let request):
            try validateBoundItemCount(request?.sources.count ?? 0, limits: limits, work: &work)
            if let request { _ = try PatchGenerationWorkflow.plan(request) }
        case .report(let request):
            try validateBoundItemCount(request?.linkedReports.count ?? 0, limits: limits, work: &work)
            if let request { _ = try ComparisonReportWorkflowPlanner.plan(request) }
        case .archive(let request):
            try validateBoundItemCount(
                request?.snapshot.entries.count ?? 0,
                limits: limits,
                work: &work
            )
            if let request { _ = try ArchiveGenerationWorkflow.plan(request) }
        }
    }

    fileprivate static func validate(
        _ intent: ExecutionIntent,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        switch intent {
        case .filters(let request):
            try validateFilterLimits(request.limits)
            try validate(request.condition, limits: limits, work: &work)
            _ = try FilterTestEvaluator.evaluate(request.condition, limits: request.limits)
        case .patch(let binding):
            try validateBoundItemCount(binding.request.sources.count, limits: limits, work: &work)
            _ = try PatchGenerationWorkflow.plan(binding.request)
        case .report(let binding):
            guard
                ComparisonReportWorkflowSnapshotReference(binding.request.snapshot)
                    == binding.expectedSnapshot
            else {
                throw WorkflowError.delegatedReferenceMismatch(.generateReport)
            }
            try validateBoundItemCount(
                binding.request.linkedReports.count,
                limits: limits,
                work: &work
            )
            _ = try ComparisonReportWorkflowPlanner.plan(
                binding.request,
                expecting: binding.expectedSnapshot
            )
        case .archive(let binding):
            guard
                ArchiveGenerationSnapshotReference(binding.request.snapshot)
                    == binding.expectedSnapshot
            else {
                throw WorkflowError.delegatedReferenceMismatch(.generateArchive)
            }
            try validateBoundItemCount(
                binding.request.snapshot.entries.count,
                limits: limits,
                work: &work
            )
            _ = try ArchiveGenerationWorkflow.plan(binding.request)
        }
    }

    fileprivate static func validate(
        _ root: FilterTestCondition,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        var pending = [(condition: root, depth: 1)]
        var conditionCount = 0
        var ruleCount = 0
        while let current = pending.popLast() {
            let condition = current.condition
            guard current.depth <= limits.maximumFilterConditionDepth else {
                throw WorkflowError.filterConditionDepthExceeded(
                    maximum: limits.maximumFilterConditionDepth
                )
            }
            conditionCount += 1
            guard conditionCount <= limits.maximumFilterConditions else {
                throw WorkflowError.filterConditionLimitExceeded(
                    maximum: limits.maximumFilterConditions
                )
            }
            try work.consume(1)
            switch condition {
            case .test(let test):
                let count: Int
                switch test {
                case .filename(let value): count = value.rules.count
                case .display: count = 1
                case .line(let value): count = value.rules.count
                case .substitution(let value): count = value.rules.count
                }
                let (next, overflow) = ruleCount.addingReportingOverflow(count)
                guard !overflow else { throw WorkflowError.arithmeticOverflow }
                ruleCount = next
                guard ruleCount <= limits.maximumFilterRules else {
                    throw WorkflowError.filterRuleLimitExceeded(maximum: limits.maximumFilterRules)
                }
                try work.consume(UInt64(count))
            case .all(let children), .any(let children):
                guard pending.count <= limits.maximumFilterConditions - conditionCount,
                    children.count
                        <= limits.maximumFilterConditions - conditionCount - pending.count
                else {
                    throw WorkflowError.filterConditionLimitExceeded(
                        maximum: limits.maximumFilterConditions
                    )
                }
                let (childDepth, overflow) = current.depth.addingReportingOverflow(1)
                guard !overflow else { throw WorkflowError.arithmeticOverflow }
                for child in children.reversed() {
                    try work.consume(1)
                    pending.append((condition: child, depth: childDepth))
                }
            case .not(let child):
                let (childDepth, overflow) = current.depth.addingReportingOverflow(1)
                guard !overflow else { throw WorkflowError.arithmeticOverflow }
                pending.append((condition: child, depth: childDepth))
            }
        }
    }

    fileprivate static func validateFilterLimits(_ limits: FilterTestLimits) throws {
        guard limits.maximumCaseCount <= FilterTestLimits.default.maximumCaseCount,
            limits.maximumCollectionCount <= FilterTestLimits.default.maximumCollectionCount,
            limits.maximumConditionDepth <= FilterTestLimits.default.maximumConditionDepth,
            limits.maximumPatternUTF8Bytes <= FilterTestLimits.default.maximumPatternUTF8Bytes,
            limits.maximumReplacementUTF8Bytes <= FilterTestLimits.default.maximumReplacementUTF8Bytes,
            limits.maximumTotalPatternUTF8Bytes
                <= FilterTestLimits.default.maximumTotalPatternUTF8Bytes,
            limits.maximumInputUTF8Bytes <= FilterTestLimits.default.maximumInputUTF8Bytes,
            limits.maximumTotalInputUTF8Bytes <= FilterTestLimits.default.maximumTotalInputUTF8Bytes,
            limits.maximumOutputUTF8Bytes <= FilterTestLimits.default.maximumOutputUTF8Bytes,
            limits.maximumWork <= FilterTestLimits.default.maximumWork,
            limits.maximumResults <= FilterTestLimits.default.maximumResults
        else {
            throw WorkflowError.invalidFilterTestLimits
        }
    }

    fileprivate static func validateBoundItemCount(
        _ count: Int,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        guard count <= limits.maximumBoundItems else {
            throw WorkflowError.boundItemLimitExceeded(maximum: limits.maximumBoundItems)
        }
        try work.consume(UInt64(count))
    }

    fileprivate static func requiredEffects(for intent: Intent) -> [RequiredEffect] {
        switch intent {
        case .configuration(let configuration):
            return [.validateCurrentContext, .routeConfiguration(configuration)]
        case .execution(.filters(let request)):
            return [.validateCurrentContext, .evaluateFilters(request)]
        case .execution(.patch(let binding)):
            return [
                .validateCurrentContext,
                .planPatch(binding),
                .revalidateCurrentContext,
                .executePatchPlan
            ]
        case .execution(.report(let request)):
            return [
                .validateCurrentContext,
                .planReport(request),
                .revalidateCurrentContext,
                .executeReportPlan
            ]
        case .execution(.archive(let request)):
            return [
                .validateCurrentContext,
                .planArchive(request),
                .revalidateCurrentContext,
                .executeArchivePlan
            ]
        }
    }

    fileprivate static func authorityRequirements(
        for invocation: Invocation,
        context: Context
    ) -> [AuthorityRequirement] {
        let owner = AuthorityRequirement.ownerStateLease(ContextCAS(context))
        switch invocation.intent {
        case .configuration, .execution(.filters):
            return [owner]
        case .execution(.patch):
            return [owner, .patch(.required)]
        case .execution(.report):
            return [owner, .report(.required)]
        case .execution(.archive):
            return [owner, .archive(.required)]
        }
    }
}
