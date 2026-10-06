import CryptoKit
import Foundation

/// Caller-owned lineage and generation for one complete plugin-management state.
/// Owners must never reuse a revision for different catalog, preference, or policy state.
public struct PluginManagementRevision: Codable, Comparable, Hashable, Sendable {
    public let lineage: UInt64
    public let generation: UInt64

    public init(lineage: UInt64, generation: UInt64) {
        self.lineage = lineage
        self.generation = generation
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.lineage == right.lineage
            ? left.generation < right.generation
            : left.lineage < right.lineage
    }

    fileprivate func successor() throws(PluginManagementWorkflowError) -> Self {
        guard generation < UInt64.max else {
            throw PluginManagementWorkflowError.revisionExhausted(self)
        }
        return Self(lineage: lineage, generation: generation + 1)
    }
}

public struct PluginManagementWorkflowLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumListedItemCount = PluginCatalogLimits.hardMaximumItemCount
    public static let hardMaximumWorkUnits = PluginCatalogLimits.hardMaximumWork
    public static let hardMaximumCancellationCheckInterval = 4_096

    public static let `default` = Self(
        maximumListedItemCount: 1_024,
        maximumWorkUnits: 8 * 1_024 * 1_024,
        cancellationCheckInterval: 64,
        validated: ()
    )

    public let maximumListedItemCount: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumListedItemCount: Int = 1_024,
        maximumWorkUnits: Int = 8 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) throws(PluginManagementWorkflowError) {
        guard
            (1...Self.hardMaximumListedItemCount).contains(maximumListedItemCount),
            (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits),
            (1...Self.hardMaximumCancellationCheckInterval).contains(
                cancellationCheckInterval
            )
        else {
            throw PluginManagementWorkflowError.invalidLimits
        }
        self.init(
            maximumListedItemCount: maximumListedItemCount,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval,
            validated: ()
        )
    }

    private init(
        maximumListedItemCount: Int,
        maximumWorkUnits: Int,
        cancellationCheckInterval: Int,
        validated: Void
    ) {
        self.maximumListedItemCount = maximumListedItemCount
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

/// Complete immutable owner state. Construction performs no discovery, loading, execution, or I/O.
public struct PluginManagementSnapshot:
    Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let revision: PluginManagementRevision
    public let catalog: PluginCatalog
    public let preferences: PluginCatalogPreferences
    public let externalToolPolicy: ExternalToolPolicy

    public init(
        revision: PluginManagementRevision,
        catalog: PluginCatalog,
        preferences: PluginCatalogPreferences,
        externalToolPolicy: ExternalToolPolicy = .default
    ) throws(PluginManagementWorkflowError) {
        try pluginManagementCheckCancellation()
        try pluginManagementMapCatalogError {
            try catalog.validate(preferences: preferences)
        }
        self.revision = revision
        self.catalog = catalog
        self.preferences = preferences
        self.externalToolPolicy = externalToolPolicy
    }

    public var cas: PluginManagementSnapshotCAS {
        PluginManagementSnapshotCAS(snapshot: self, limits: .default)
    }

    public func cas(
        limits: PluginManagementWorkflowLimits
    ) -> PluginManagementSnapshotCAS {
        PluginManagementSnapshotCAS(snapshot: self, limits: limits)
    }

    fileprivate func exactlyMatches(_ other: Self) -> Bool {
        revision == other.revision && catalog == other.catalog
            && preferences == other.preferences
            && externalToolPolicy == other.externalToolPolicy
    }

    public var description: String {
        "PluginManagementSnapshot(revision: \(revision), plugins: \(catalog.items.count), state: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "revision": revision,
                "pluginCount": catalog.items.count,
                "catalog": "<redacted>",
                "preferences": "<redacted>",
                "externalToolPolicy": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Exact compare-and-swap expectation. Revision equality alone never proves current state.
public struct PluginManagementSnapshotCAS:
    Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let revision: PluginManagementRevision
    private let snapshot: PluginManagementSnapshot
    private let limits: PluginManagementWorkflowLimits

    fileprivate init(
        snapshot: PluginManagementSnapshot,
        limits: PluginManagementWorkflowLimits
    ) {
        revision = snapshot.revision
        self.snapshot = snapshot
        self.limits = limits
    }

    public func matches(
        _ current: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) -> Bool {
        do {
            try validate(current)
            return true
        } catch PluginManagementWorkflowError.staleSnapshot,
            PluginManagementWorkflowError.snapshotContentsChanged
        {
            return false
        }
    }

    public func validate(
        _ current: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) {
        var work = PluginManagementWorkBudget(limits: limits)
        try validate(current, work: &work)
    }

    fileprivate var workflowLimits: PluginManagementWorkflowLimits { limits }

    fileprivate func validate(
        _ current: PluginManagementSnapshot,
        work: inout PluginManagementWorkBudget
    ) throws(PluginManagementWorkflowError) {
        try pluginManagementCheckCancellation()
        guard current.revision == revision else {
            throw PluginManagementWorkflowError.staleSnapshot(
                expected: revision,
                actual: current.revision
            )
        }
        try pluginManagementChargeSnapshot(snapshot, work: &work)
        try pluginManagementChargeSnapshot(current, work: &work)
        try pluginManagementCheckCancellation()
        // Full equality includes private trusted authorities. Cost is preflighted from bounded public
        // state; authority equality is one bounded atomic comparison.
        guard snapshot.exactlyMatches(current) else {
            throw PluginManagementWorkflowError.snapshotContentsChanged(revision: revision)
        }
        try pluginManagementCheckCancellation()
    }

    public var description: String {
        "PluginManagementSnapshotCAS(revision: \(revision), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["revision": revision, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public enum PluginManagementInvocationIntent: String, CaseIterable, Hashable, Sendable {
    case disabled
    case manual
    case automatic
}

/// Policy binding observation only. It does not carry an executable plan or authority.
public enum PluginManagementExternalToolBinding: Equatable, Sendable {
    case executionBackendUnavailable
    case ruleReferenceMissing(ExternalToolCapability)
    case ruleNotConfigured(ruleIdentifier: String, capability: ExternalToolCapability)
    case ruleCapabilityMismatch(
        ruleIdentifier: String,
        expected: ExternalToolCapability,
        actual: ExternalToolCapability
    )
    case bound(
        ruleIdentifier: String,
        capability: ExternalToolCapability,
        policyDecision: ExternalToolCapabilityDecision
    )
}

public struct PluginManagementListEntry: Equatable, Sendable {
    public let item: PluginCatalogItem
    public let invocationIntent: PluginManagementInvocationIntent
    public let preferredAutomaticRank: Int?
    public let externalToolBinding: PluginManagementExternalToolBinding
    public let manualDecision: PluginCatalogEligibilityDecision
    public let automaticDecision: PluginCatalogEligibilityDecision

    fileprivate init(
        item: PluginCatalogItem,
        invocationIntent: PluginManagementInvocationIntent,
        preferredAutomaticRank: Int?,
        externalToolBinding: PluginManagementExternalToolBinding,
        manualDecision: PluginCatalogEligibilityDecision,
        automaticDecision: PluginCatalogEligibilityDecision
    ) {
        self.item = item
        self.invocationIntent = invocationIntent
        self.preferredAutomaticRank = preferredAutomaticRank
        self.externalToolBinding = externalToolBinding
        self.manualDecision = manualDecision
        self.automaticDecision = automaticDecision
    }
}

public enum PluginManagementSettingValueSource: String, CaseIterable, Hashable, Sendable {
    case preference
    case catalogDefault
    case secretNotExposed
}

public struct PluginManagementSettingEntry:
    Equatable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let schema: PluginSettingSchema
    public let privacy: PluginSettingPrivacy
    public let valueSource: PluginManagementSettingValueSource
    /// Present only for nonsecret settings. Secret material never enters this workflow.
    public let value: PluginSettingValue?

    fileprivate init(
        schema: PluginSettingSchema,
        privacy: PluginSettingPrivacy,
        valueSource: PluginManagementSettingValueSource,
        value: PluginSettingValue?
    ) {
        self.schema = schema
        self.privacy = privacy
        self.valueSource = valueSource
        self.value = value
    }

    public var description: String {
        "PluginManagementSettingEntry(kind: \(schema.constraint.kind.rawValue), privacy: \(privacy.rawValue), source: \(valueSource.rawValue), value: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": schema.constraint.kind,
                "privacy": privacy,
                "valueSource": valueSource,
                "value": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct PluginManagementSelectionRequest: Equatable, Hashable, Sendable {
    public let filter: PluginCatalogFilter
    public let mode: PluginInvocationMode

    public init(
        filter: PluginCatalogFilter = .all,
        mode: PluginInvocationMode
    ) {
        self.filter = filter
        self.mode = mode
    }
}

/// Package-trusted launch boundary. Current state and authorization must be sampled from the same
/// actor immediately before it consumes a selection; no suspension occurs between revalidation and
/// consumption.
package protocol PluginManagementSelectionConsumer: Actor {
    func currentPluginManagementSnapshotAtLaunch() -> PluginManagementSnapshot
    func currentPluginAuthorizationsAtLaunch() -> [PluginIdentifier: PluginAuthorization]
    func consumePluginManagementSelectionAtLaunch(
        _ authorization: PluginManagementSelectionLaunchAuthorization
    ) throws(PluginManagementWorkflowError)
}

/// Nonforgeable callback-scoped authorization. It yields the outcome once, only to the consumer actor
/// selected by the receipt; retaining or forwarding it beyond that synchronous callback fails closed.
package struct PluginManagementSelectionLaunchAuthorization:
    Sendable, CustomReflectable, CustomStringConvertible, CustomDebugStringConvertible
{
    private let outcome: PluginCatalogSelectionOutcome
    private let consumptionGate: PluginManagementSelectionConsumptionGate
    private let consumerIdentifier: ObjectIdentifier
    private let claimIdentifier: UUID

    fileprivate init(
        outcome: PluginCatalogSelectionOutcome,
        consumptionGate: PluginManagementSelectionConsumptionGate,
        consumerIdentifier: ObjectIdentifier,
        claimIdentifier: UUID
    ) {
        self.outcome = outcome
        self.consumptionGate = consumptionGate
        self.consumerIdentifier = consumerIdentifier
        self.claimIdentifier = claimIdentifier
    }

    package func consume<Consumer: Actor>(
        on consumer: isolated Consumer
    ) throws(PluginManagementWorkflowError) -> PluginCatalogSelectionOutcome {
        guard ObjectIdentifier(consumer) == consumerIdentifier,
            consumptionGate.consumeOutcome(
                owner: consumerIdentifier,
                claimIdentifier: claimIdentifier
            )
        else {
            throw PluginManagementWorkflowError.selectionAlreadyConsumed
        }
        return outcome
    }

    package var description: String {
        "PluginManagementSelectionLaunchAuthorization(<opaque>)"
    }

    package var debugDescription: String { description }

    package var customMirror: Mirror {
        Mirror(self, children: ["authorization": "<opaque>"], displayStyle: .struct)
    }
}

/// Deterministic selection capability. Copies share one consumption gate, and the outcome is exposed
/// only to a package-trusted consumer after exact state, current trust, approval, revocation, and
/// expiry are revalidated at its synchronous launch boundary.
public struct PluginManagementSelectionReceipt:
    Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let expectedSnapshot: PluginManagementSnapshotCAS
    public let request: PluginManagementSelectionRequest
    private let outcome: PluginCatalogSelectionOutcome
    private let maximumResultCount: Int
    private let consumptionGate: PluginManagementSelectionConsumptionGate

    fileprivate init(
        expectedSnapshot: PluginManagementSnapshotCAS,
        request: PluginManagementSelectionRequest,
        outcome: PluginCatalogSelectionOutcome,
        maximumResultCount: Int
    ) {
        self.expectedSnapshot = expectedSnapshot
        self.request = request
        self.outcome = outcome
        self.maximumResultCount = maximumResultCount
        consumptionGate = PluginManagementSelectionConsumptionGate()
    }

    package func consume<Consumer: PluginManagementSelectionConsumer>(
        on consumer: isolated Consumer
    ) throws(PluginManagementWorkflowError) {
        let consumerIdentifier = ObjectIdentifier(consumer)
        guard let claimIdentifier = consumptionGate.claim(owner: consumerIdentifier) else {
            throw PluginManagementWorkflowError.selectionAlreadyConsumed
        }
        defer { consumptionGate.invalidate() }

        try pluginManagementCheckCancellation()
        let currentSnapshot = consumer.currentPluginManagementSnapshotAtLaunch()
        let authorizations = consumer.currentPluginAuthorizationsAtLaunch()
        try validate(
            currentSnapshot: currentSnapshot,
            authorizations: authorizations
        )
        try pluginManagementCheckCancellation()
        try consumer.consumePluginManagementSelectionAtLaunch(
            PluginManagementSelectionLaunchAuthorization(
                outcome: outcome,
                consumptionGate: consumptionGate,
                consumerIdentifier: consumerIdentifier,
                claimIdentifier: claimIdentifier
            )
        )
        guard
            consumptionGate.didConsumeOutcome(
                owner: consumerIdentifier,
                claimIdentifier: claimIdentifier
            )
        else {
            throw PluginManagementWorkflowError.invalidSelectionConsumption
        }
    }

    private func validate(
        currentSnapshot: PluginManagementSnapshot,
        authorizations: [PluginIdentifier: PluginAuthorization]
    ) throws(PluginManagementWorkflowError) {
        var work = PluginManagementWorkBudget(limits: expectedSnapshot.workflowLimits)
        try expectedSnapshot.validate(currentSnapshot, work: &work)
        let candidates = try pluginManagementMapCatalogError {
            try currentSnapshot.catalog.items(matching: request.filter)
        }
        guard candidates.count <= maximumResultCount else {
            throw PluginManagementWorkflowError.resultLimitExceeded(
                maximum: maximumResultCount
            )
        }
        for item in candidates {
            try pluginManagementChargeDecision(
                item: item,
                policy: currentSnapshot.externalToolPolicy,
                repetitions: 1,
                work: &work
            )
        }
        let currentOutcome = try pluginManagementMapCatalogError {
            try currentSnapshot.catalog.select(
                matching: request.filter,
                mode: request.mode,
                authorizations: authorizations,
                preferences: currentSnapshot.preferences,
                externalToolPolicy: currentSnapshot.externalToolPolicy
            )
        }
        try pluginManagementValidateSelectionOutcome(
            currentOutcome,
            maximumResultCount: maximumResultCount
        )
        guard currentOutcome == outcome else {
            throw PluginManagementWorkflowError.selectionAuthorizationChanged
        }
        if case .selected(let selectedItem) = currentOutcome {
            try pluginManagementChargeDecision(
                item: selectedItem,
                policy: currentSnapshot.externalToolPolicy,
                repetitions: 1,
                work: &work
            )
            guard
                let finalDecision = try pluginManagementMapCatalogError({
                    try currentSnapshot.catalog.decision(
                        for: selectedItem.id,
                        mode: request.mode,
                        authorization: authorizations[selectedItem.id],
                        preferences: currentSnapshot.preferences,
                        externalToolPolicy: currentSnapshot.externalToolPolicy
                    )
                }),
                finalDecision.isEligible
            else {
                throw PluginManagementWorkflowError.selectionAuthorizationChanged
            }
        }
        try pluginManagementCheckCancellation()
    }

    public var description: String {
        "PluginManagementSelectionReceipt(revision: \(expectedSnapshot.revision), mode: \(request.mode.rawValue), outcome: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "revision": expectedSnapshot.revision,
                "mode": request.mode,
                "outcome": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

private final class PluginManagementSelectionConsumptionGate: @unchecked Sendable {
    private enum State {
        case available
        case claimed(owner: ObjectIdentifier, identifier: UUID)
        case outcomeConsumed(owner: ObjectIdentifier, identifier: UUID)
        case invalidated
    }

    private let lock = NSLock()
    private var state: State = .available

    func claim(owner: ObjectIdentifier) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard case .available = state else { return nil }
        let identifier = UUID()
        state = .claimed(owner: owner, identifier: identifier)
        return identifier
    }

    func invalidate() {
        lock.lock()
        state = .invalidated
        lock.unlock()
    }

    func consumeOutcome(owner: ObjectIdentifier, claimIdentifier: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard
            case .claimed(let currentOwner, let currentIdentifier) = state,
            currentOwner == owner,
            currentIdentifier == claimIdentifier
        else { return false }
        state = .outcomeConsumed(owner: owner, identifier: claimIdentifier)
        return true
    }

    func didConsumeOutcome(owner: ObjectIdentifier, claimIdentifier: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard
            case .outcomeConsumed(let currentOwner, let currentIdentifier) = state
        else { return false }
        return currentOwner == owner && currentIdentifier == claimIdentifier
    }
}

public enum PluginManagementCatalogMutationKind: String, CaseIterable, Hashable, Sendable {
    case add
    case update
    case remove
    case reload
}

public enum PluginManagementEditKind: String, CaseIterable, Hashable, Sendable {
    case setEnabled
    case setInvocationMode
    case setSetting
    case removeSetting
    case reorderAutomaticPlugins
    case addCatalogItem
    case updateCatalogItem
    case removeCatalogItem
}

/// Management intent only. Catalog metadata mutation cases are explicitly fail-closed because a new
/// `PluginCatalog` cannot preserve its private trusted privacy, authorization, and Keychain state.
public enum PluginManagementEditIntent:
    Equatable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case setEnabled(identifier: PluginIdentifier, enabled: Bool)
    case setInvocationMode(identifier: PluginIdentifier, mode: PluginInvocationMode)
    case setSetting(identifier: PluginIdentifier, key: String, value: PluginSettingValue)
    case removeSetting(identifier: PluginIdentifier, key: String)
    case reorderAutomaticPlugins([PluginIdentifier])
    case addCatalogItem(PluginCatalogItem)
    case updateCatalogItem(PluginCatalogItem)
    case removeCatalogItem(PluginIdentifier)

    public var kind: PluginManagementEditKind {
        switch self {
        case .setEnabled: .setEnabled
        case .setInvocationMode: .setInvocationMode
        case .setSetting: .setSetting
        case .removeSetting: .removeSetting
        case .reorderAutomaticPlugins: .reorderAutomaticPlugins
        case .addCatalogItem: .addCatalogItem
        case .updateCatalogItem: .updateCatalogItem
        case .removeCatalogItem: .removeCatalogItem
        }
    }

    public var description: String {
        "PluginManagementEditIntent(kind: \(kind.rawValue), payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["kind": kind, "payload": "<redacted>"],
            displayStyle: .enum
        )
    }
}

/// Redacted summary of exact canonical preference bytes retained by a plan.
public struct PluginManagementPersistenceReceipt:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let schemaVersion: Int
    public let byteCount: Int
    private let canonicalSHA256: [UInt8]

    fileprivate init(canonicalData: Data) {
        schemaVersion = PluginCatalogPreferences.currentSchemaVersion
        byteCount = canonicalData.count
        canonicalSHA256 = Array(SHA256.hash(data: canonicalData))
    }

    package func matches(canonicalData: Data) -> Bool {
        byteCount == canonicalData.count
            && canonicalSHA256 == Array(SHA256.hash(data: canonicalData))
    }

    public var description: String {
        "PluginManagementPersistenceReceipt(schemaVersion: \(schemaVersion), bytes: \(byteCount), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "schemaVersion": schemaVersion,
                "byteCount": byteCount,
                "canonicalSHA256": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum PluginManagementExecutorSnapshotContract: String, Hashable, Sendable {
    case holdExactSnapshotCASUntilStateAndPersistenceCommit
}

public enum PluginManagementExecutorPersistenceContract: String, Hashable, Sendable {
    case publishExactCanonicalRedactedPreferencesWithoutRegeneration
}

public enum PluginManagementExecutorSecurityContract: String, Hashable, Sendable {
    case trustedHostOnlyNeverExecuteInspectOrExportSecrets
}

public enum PluginManagementExecutorCancellationContract: String, Hashable, Sendable {
    case cancelBeforeCommitOrReturnExactCompletedReceipt
}

public struct PluginManagementExecutorContract: Hashable, Sendable {
    public static let required = Self()

    public let snapshot =
        PluginManagementExecutorSnapshotContract.holdExactSnapshotCASUntilStateAndPersistenceCommit
    public let persistence =
        PluginManagementExecutorPersistenceContract.publishExactCanonicalRedactedPreferencesWithoutRegeneration
    public let security =
        PluginManagementExecutorSecurityContract.trustedHostOnlyNeverExecuteInspectOrExportSecrets
    public let cancellation =
        PluginManagementExecutorCancellationContract.cancelBeforeCommitOrReturnExactCompletedReceipt

    public init() {}
}

public struct PluginManagementEditPlanningReceipt:
    Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let expectedRevision: PluginManagementRevision
    public let projectedRevision: PluginManagementRevision
    public let editKind: PluginManagementEditKind
    public let persistence: PluginManagementPersistenceReceipt
    private let expectedSnapshot: PluginManagementSnapshotCAS
    private let projectedSnapshot: PluginManagementSnapshot

    fileprivate init(
        expectedSnapshot: PluginManagementSnapshotCAS,
        projectedSnapshot: PluginManagementSnapshot,
        editKind: PluginManagementEditKind,
        persistence: PluginManagementPersistenceReceipt
    ) {
        expectedRevision = expectedSnapshot.revision
        projectedRevision = projectedSnapshot.revision
        self.editKind = editKind
        self.persistence = persistence
        self.expectedSnapshot = expectedSnapshot
        self.projectedSnapshot = projectedSnapshot
    }

    public var description: String {
        "PluginManagementEditPlanningReceipt(expected: \(expectedRevision), projected: \(projectedRevision), kind: \(editKind.rawValue), payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "expectedRevision": expectedRevision,
                "projectedRevision": projectedRevision,
                "editKind": editKind,
                "persistence": persistence
            ],
            displayStyle: .struct
        )
    }
}

/// Immutable preference edit plan. Projected state is not proof that persistence or CAS committed.
public struct PluginManagementEditPlan:
    Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let expectedSnapshot: PluginManagementSnapshotCAS
    public let intent: PluginManagementEditIntent
    public let projectedSnapshot: PluginManagementSnapshot
    public let receipt: PluginManagementEditPlanningReceipt
    public let executorContract: PluginManagementExecutorContract
    fileprivate let canonicalPersistenceData: Data

    fileprivate init(
        expectedSnapshot: PluginManagementSnapshotCAS,
        intent: PluginManagementEditIntent,
        projectedSnapshot: PluginManagementSnapshot,
        canonicalPersistenceData: Data
    ) {
        self.expectedSnapshot = expectedSnapshot
        self.intent = intent
        self.projectedSnapshot = projectedSnapshot
        receipt = PluginManagementEditPlanningReceipt(
            expectedSnapshot: expectedSnapshot,
            projectedSnapshot: projectedSnapshot,
            editKind: intent.kind,
            persistence: PluginManagementPersistenceReceipt(
                canonicalData: canonicalPersistenceData
            )
        )
        executorContract = .required
        self.canonicalPersistenceData = canonicalPersistenceData
    }

    public func validateCurrentSnapshot(
        _ snapshot: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) {
        try expectedSnapshot.validate(snapshot)
    }

    public var description: String {
        "PluginManagementEditPlan(expected: \(expectedSnapshot.revision), projected: \(projectedSnapshot.revision), kind: \(intent.kind.rawValue), payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "expectedRevision": expectedSnapshot.revision,
                "projectedRevision": projectedSnapshot.revision,
                "editKind": intent.kind,
                "persistence": receipt.persistence,
                "payload": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Opaque capability handed only to package-trusted state/persistence executors.
public struct PluginManagementExecutorLease:
    Sendable, CustomReflectable, CustomStringConvertible, CustomDebugStringConvertible
{
    private let identifier: UUID
    private let plan: PluginManagementEditPlan
    private let gate: PluginManagementExecutorLeaseGate

    fileprivate init(plan: PluginManagementEditPlan) {
        identifier = UUID()
        self.plan = plan
        gate = PluginManagementExecutorLeaseGate()
    }

    /// Claims this lease for one executor. Copies share the gate and cannot claim again.
    package func consume<Executor: Actor>(
        on executor: isolated Executor
    ) throws(PluginManagementWorkflowError) -> PluginManagementExecutorLeaseContents {
        guard gate.claim(owner: ObjectIdentifier(executor)) else {
            throw PluginManagementWorkflowError.executorLeaseAlreadyConsumed
        }
        return PluginManagementExecutorLeaseContents(plan: plan)
    }

    fileprivate func isSameLease(as other: Self) -> Bool {
        identifier == other.identifier && gate === other.gate
    }

    fileprivate func isClaimed<Executor: Actor>(by executor: isolated Executor) -> Bool {
        gate.isClaimed(owner: ObjectIdentifier(executor))
    }

    fileprivate func invalidate() {
        gate.invalidate()
    }

    public var description: String { "PluginManagementExecutorLease(<opaque>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["lease": "<opaque>"], displayStyle: .struct)
    }
}

package struct PluginManagementExecutorLeaseContents:
    Sendable, CustomReflectable, CustomStringConvertible, CustomDebugStringConvertible
{
    package let expectedSnapshot: PluginManagementSnapshotCAS
    package let projectedSnapshot: PluginManagementSnapshot
    package let canonicalPersistenceData: Data
    package let persistenceReceipt: PluginManagementPersistenceReceipt

    fileprivate init(plan: PluginManagementEditPlan) {
        expectedSnapshot = plan.expectedSnapshot
        projectedSnapshot = plan.projectedSnapshot
        canonicalPersistenceData = plan.canonicalPersistenceData
        persistenceReceipt = plan.receipt.persistence
    }

    package var description: String {
        "PluginManagementExecutorLeaseContents(<redacted>)"
    }

    package var debugDescription: String { description }

    package var customMirror: Mirror {
        Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
    }
}

private final class PluginManagementExecutorLeaseGate: @unchecked Sendable {
    private enum State {
        case available
        case claimed(owner: ObjectIdentifier)
        case invalidated
    }

    private let lock = NSLock()
    private var state: State = .available

    func claim(owner: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .available = state else { return false }
        state = .claimed(owner: owner)
        return true
    }

    func isClaimed(owner: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .claimed(let currentOwner) = state else { return false }
        return currentOwner == owner
    }

    func invalidate() {
        lock.lock()
        state = .invalidated
        lock.unlock()
    }
}

public enum PluginManagementExecutionNonCommitReason: String, CaseIterable, Hashable, Sendable {
    case cancelled
    case staleSnapshot
    case persistenceUnavailable
    case ownerStateUnavailable
    case contractUnsupported
    case rejected
}

package struct PluginManagementExecutorReport:
    Sendable, CustomReflectable, CustomStringConvertible, CustomDebugStringConvertible
{
    fileprivate enum Storage: Sendable {
        case committed(
            lease: PluginManagementExecutorLease,
            snapshot: PluginManagementSnapshot,
            canonicalPersistenceData: Data
        )
        case notCommitted(
            lease: PluginManagementExecutorLease,
            currentSnapshot: PluginManagementSnapshot,
            reason: PluginManagementExecutionNonCommitReason
        )
        case staleSnapshot(
            lease: PluginManagementExecutorLease,
            observedRevision: PluginManagementRevision
        )
    }

    fileprivate let storage: Storage

    package static func committed(
        lease: PluginManagementExecutorLease,
        snapshot: PluginManagementSnapshot,
        canonicalPersistenceData: Data
    ) -> Self {
        Self(
            storage: .committed(
                lease: lease,
                snapshot: snapshot,
                canonicalPersistenceData: canonicalPersistenceData
            )
        )
    }

    package static func notCommitted(
        lease: PluginManagementExecutorLease,
        currentSnapshot: PluginManagementSnapshot,
        reason: PluginManagementExecutionNonCommitReason
    ) throws(PluginManagementWorkflowError) -> Self {
        guard reason != .staleSnapshot else {
            throw PluginManagementWorkflowError.invalidExecutorCommit
        }
        return Self(
            storage: .notCommitted(
                lease: lease,
                currentSnapshot: currentSnapshot,
                reason: reason
            )
        )
    }

    package static func staleSnapshot(
        lease: PluginManagementExecutorLease,
        observedRevision: PluginManagementRevision
    ) -> Self {
        Self(storage: .staleSnapshot(lease: lease, observedRevision: observedRevision))
    }

    package var description: String { "PluginManagementExecutorReport(<redacted>)" }
    package var debugDescription: String { description }

    package var customMirror: Mirror {
        Mirror(self, children: ["report": "<redacted>"], displayStyle: .struct)
    }
}

/// Trusted app/platform boundary. Implementations must perform one exact CAS and publish the lease's
/// canonical bytes without regeneration. This workflow supplies no executor.
package protocol PluginManagementPlanExecutor: Actor {
    func compareAndCommit(
        _ lease: PluginManagementExecutorLease
    ) throws(PluginManagementWorkflowError) -> PluginManagementExecutorReport
}

/// Opaque proof returned only after trusted executor output matches the complete plan.
public struct PluginManagementExecutionReceipt:
    Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let planning: PluginManagementEditPlanningReceipt
    public let committedRevision: PluginManagementRevision
    public let persistence: PluginManagementPersistenceReceipt

    fileprivate init(plan: PluginManagementEditPlan) {
        planning = plan.receipt
        committedRevision = plan.projectedSnapshot.revision
        persistence = plan.receipt.persistence
    }

    public var description: String {
        "PluginManagementExecutionReceipt(revision: \(committedRevision), kind: \(planning.editKind.rawValue), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "committedRevision": committedRevision,
                "editKind": planning.editKind,
                "persistence": persistence,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension PluginManagementEditPlan {
    /// Executes one synchronous actor-isolated CAS. Public callers cannot mint leases or receipts.
    package func execute<Executor: PluginManagementPlanExecutor>(
        on executor: isolated Executor
    ) throws(PluginManagementWorkflowError) -> PluginManagementExecutionReceipt {
        try pluginManagementCheckCancellation()
        var work = PluginManagementWorkBudget(limits: expectedSnapshot.workflowLimits)
        try pluginManagementChargeSnapshot(projectedSnapshot, work: &work)
        try work.consume(canonicalPersistenceData.count)
        try work.consume(canonicalPersistenceData.count)
        try pluginManagementCheckCancellation()
        let lease = PluginManagementExecutorLease(plan: self)
        defer { lease.invalidate() }
        let report = try executor.compareAndCommit(lease)
        guard lease.isClaimed(by: executor) else {
            throw PluginManagementWorkflowError.invalidExecutorCommit
        }
        switch report.storage {
        case .committed(let returnedLease, let snapshot, let persistenceData):
            guard returnedLease.isSameLease(as: lease),
                snapshot.exactlyMatches(projectedSnapshot),
                persistenceData == canonicalPersistenceData,
                receipt.persistence.matches(canonicalData: persistenceData)
            else {
                throw PluginManagementWorkflowError.invalidExecutorCommit
            }
            return PluginManagementExecutionReceipt(plan: self)
        case .notCommitted(let returnedLease, let currentSnapshot, let reason):
            guard returnedLease.isSameLease(as: lease), reason != .staleSnapshot else {
                throw PluginManagementWorkflowError.invalidExecutorCommit
            }
            try expectedSnapshot.validate(currentSnapshot, work: &work)
            throw PluginManagementWorkflowError.executionNotCommitted(reason)
        case .staleSnapshot(let returnedLease, let observedRevision):
            guard returnedLease.isSameLease(as: lease),
                observedRevision != expectedSnapshot.revision
            else {
                throw PluginManagementWorkflowError.invalidExecutorCommit
            }
            throw PluginManagementWorkflowError.executionNotCommitted(.staleSnapshot)
        }
    }
}

/// Exact reload observation request. Existing catalog semantics report reload as unsupported.
public struct PluginManagementReloadRequest:
    Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let expectedSnapshot: PluginManagementSnapshotCAS
    public let operationOutcome: PluginCatalogOperationOutcome

    fileprivate init(
        snapshot: PluginManagementSnapshot,
        limits: PluginManagementWorkflowLimits
    ) {
        expectedSnapshot = snapshot.cas(limits: limits)
        operationOutcome = snapshot.catalog.reloadOutcome(
            externalToolPolicy: snapshot.externalToolPolicy
        )
    }

    public func validateCurrentSnapshot(
        _ snapshot: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) {
        try expectedSnapshot.validate(snapshot)
    }

    public var description: String {
        "PluginManagementReloadRequest(revision: \(expectedSnapshot.revision), status: \(operationOutcome.status.rawValue), state: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "revision": expectedSnapshot.revision,
                "status": operationOutcome.status,
                "reason": operationOutcome.reason,
                "state": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum PluginManagementReloadDisposition: Equatable, Hashable, Sendable {
    case unavailable(PluginCatalogOperationOutcome)
}

/// Validated result, not execution success. No successful reload receipt is exposed while the
/// catalog's external-tool policy explicitly rejects plugin reload.
public struct PluginManagementReloadResult:
    Equatable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let validatedRevision: PluginManagementRevision
    public let disposition: PluginManagementReloadDisposition

    fileprivate init(
        validatedRevision: PluginManagementRevision,
        disposition: PluginManagementReloadDisposition
    ) {
        self.validatedRevision = validatedRevision
        self.disposition = disposition
    }

    public var description: String {
        "PluginManagementReloadResult(revision: \(validatedRevision), disposition: unavailable)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "validatedRevision": validatedRevision,
                "disposition": "unavailable"
            ],
            displayStyle: .struct
        )
    }
}

public enum PluginManagementWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case cancelled
    case revisionExhausted(PluginManagementRevision)
    case resultLimitExceeded(maximum: Int)
    case workLimitExceeded(maximum: Int)
    case staleSnapshot(
        expected: PluginManagementRevision,
        actual: PluginManagementRevision
    )
    case snapshotContentsChanged(revision: PluginManagementRevision)
    case unknownPlugin(PluginIdentifier)
    case unknownSetting(identifier: PluginIdentifier, key: String)
    case manualUseNotDeclared(PluginIdentifier)
    case automaticUseNotDeclared(PluginIdentifier)
    case secretSettingRequiresTrustedStorage(identifier: PluginIdentifier, key: String)
    case catalogMutationUnavailable(PluginManagementCatalogMutationKind)
    case noChange
    case selectionAlreadyConsumed
    case invalidSelectionConsumption
    case selectionAuthorizationChanged
    case executorLeaseAlreadyConsumed
    case invalidExecutorCommit
    case executionNotCommitted(PluginManagementExecutionNonCommitReason)
    case catalog(PluginCatalogError)
    case unexpectedCatalogFailure

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Plugin management limits are invalid."
        case .cancelled:
            "Plugin management operation was cancelled."
        case .revisionExhausted:
            "Plugin management revision cannot advance."
        case .resultLimitExceeded(let maximum):
            "Plugin management result exceeds the \(maximum)-item limit."
        case .workLimitExceeded(let maximum):
            "Plugin management operation exceeds the \(maximum)-unit work limit."
        case .staleSnapshot:
            "Plugin management operation belongs to a stale snapshot."
        case .snapshotContentsChanged:
            "Plugin management state changed without a matching revision change."
        case .unknownPlugin(let identifier):
            "Unknown plugin identifier: \(identifier.rawValue)."
        case .unknownSetting(let identifier, let key):
            "Plugin \(identifier.rawValue) has no setting named \(key)."
        case .manualUseNotDeclared(let identifier):
            "Plugin \(identifier.rawValue) does not declare manual use."
        case .automaticUseNotDeclared(let identifier):
            "Plugin \(identifier.rawValue) does not declare automatic use."
        case .secretSettingRequiresTrustedStorage(let identifier, let key):
            "Secret setting \(identifier.rawValue).\(key) requires trusted Keychain integration."
        case .catalogMutationUnavailable(let kind):
            "Plugin catalog \(kind.rawValue) is unavailable because trusted catalog state cannot be safely preserved."
        case .noChange:
            "Plugin management intent does not change state."
        case .selectionAlreadyConsumed:
            "Plugin selection capability has already been consumed or invalidated."
        case .invalidSelectionConsumption:
            "Plugin selection consumer did not consume its launch authorization exactly once."
        case .selectionAuthorizationChanged:
            "Plugin selection changed after current trust or approval validation."
        case .executorLeaseAlreadyConsumed:
            "Plugin management executor lease has already been consumed or invalidated."
        case .invalidExecutorCommit:
            "Plugin management executor returned a commit that does not match its opaque lease."
        case .executionNotCommitted(let reason):
            "Plugin management executor did not commit: \(reason.rawValue)."
        case .catalog(let error):
            error.localizedDescription
        case .unexpectedCatalogFailure:
            "Plugin catalog operation failed without a recognized typed error."
        }
    }
}

/// UI-independent management projection and planning. It never discovers, loads, or executes plugins.
public struct PluginManagementWorkflow: Sendable {
    public let limits: PluginManagementWorkflowLimits

    public init(limits: PluginManagementWorkflowLimits = .default) {
        self.limits = limits
    }

    /// Returns stable identifier order regardless of registration or authorization dictionary order.
    public func list(
        snapshot: PluginManagementSnapshot,
        matching filter: PluginCatalogFilter = .all,
        authorizations: [PluginIdentifier: PluginAuthorization] = [:]
    ) throws(PluginManagementWorkflowError) -> [PluginManagementListEntry] {
        try pluginManagementCheckCancellation()
        var work = PluginManagementWorkBudget(limits: limits)
        try pluginManagementChargeSnapshot(snapshot, work: &work)
        let items = try pluginManagementMapCatalogError {
            try snapshot.catalog.items(matching: filter)
        }
        guard items.count <= limits.maximumListedItemCount else {
            throw PluginManagementWorkflowError.resultLimitExceeded(
                maximum: limits.maximumListedItemCount
            )
        }

        let preferredRanks = Dictionary(
            uniqueKeysWithValues:
                snapshot.preferences.preferredAutomaticPluginIdentifiers.enumerated().map {
                    ($0.element, $0.offset)
                }
        )
        var result: [PluginManagementListEntry] = []
        result.reserveCapacity(items.count)
        for item in items {
            try pluginManagementChargeDecision(
                item: item,
                policy: snapshot.externalToolPolicy,
                repetitions: 3,
                work: &work
            )
            let manualDecision = try pluginManagementMapCatalogError {
                try snapshot.catalog.decision(
                    for: item.id,
                    mode: .manual,
                    authorization: authorizations[item.id],
                    preferences: snapshot.preferences,
                    externalToolPolicy: snapshot.externalToolPolicy
                )
            }
            let automaticDecision = try pluginManagementMapCatalogError {
                try snapshot.catalog.decision(
                    for: item.id,
                    mode: .automatic,
                    authorization: authorizations[item.id],
                    preferences: snapshot.preferences,
                    externalToolPolicy: snapshot.externalToolPolicy
                )
            }
            guard let manualDecision, let automaticDecision else {
                throw PluginManagementWorkflowError.unknownPlugin(item.id)
            }
            result.append(
                PluginManagementListEntry(
                    item: item,
                    invocationIntent: Self.invocationIntent(
                        for: item.id,
                        preferences: snapshot.preferences
                    ),
                    preferredAutomaticRank: preferredRanks[item.id],
                    externalToolBinding: try Self.externalToolBinding(
                        for: item,
                        policy: snapshot.externalToolPolicy
                    ),
                    manualDecision: manualDecision,
                    automaticDecision: automaticDecision
                )
            )
        }
        return result
    }

    /// Returns setting schema order from the catalog. Secret values are always absent.
    public func settings(
        for identifier: PluginIdentifier,
        snapshot: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) -> [PluginManagementSettingEntry] {
        try pluginManagementCheckCancellation()
        var work = PluginManagementWorkBudget(limits: limits)
        try pluginManagementChargeSnapshot(snapshot, work: &work)
        guard let item = snapshot.catalog.item(withIdentifier: identifier) else {
            throw PluginManagementWorkflowError.unknownPlugin(identifier)
        }
        guard item.settings.count <= limits.maximumListedItemCount else {
            throw PluginManagementWorkflowError.resultLimitExceeded(
                maximum: limits.maximumListedItemCount
            )
        }
        var result: [PluginManagementSettingEntry] = []
        result.reserveCapacity(item.settings.count)
        for schema in item.settings {
            try work.consume(schema.key.utf8.count + 1)
            try pluginManagementChargeSettingIdentity(item: item, schema: schema, work: &work)
            guard
                let privacy = try pluginManagementMapCatalogError({
                    try snapshot.catalog.settingPrivacy(for: identifier, key: schema.key)
                })
            else {
                throw PluginManagementWorkflowError.unknownSetting(
                    identifier: identifier,
                    key: schema.key
                )
            }
            switch privacy {
            case .secret:
                result.append(
                    PluginManagementSettingEntry(
                        schema: schema,
                        privacy: privacy,
                        valueSource: .secretNotExposed,
                        value: nil
                    )
                )
            case .nonSecret:
                let preferredValue = snapshot.preferences.settingValues[identifier]?[schema.key]
                guard let value = preferredValue ?? schema.defaultValue else {
                    throw PluginManagementWorkflowError.catalog(
                        .nonSecretSettingRequiresDefaultValue
                    )
                }
                result.append(
                    PluginManagementSettingEntry(
                        schema: schema,
                        privacy: privacy,
                        valueSource: preferredValue == nil ? .catalogDefault : .preference,
                        value: value
                    )
                )
            }
        }
        return result
    }

    public func select(
        _ request: PluginManagementSelectionRequest,
        snapshot: PluginManagementSnapshot,
        authorizations: [PluginIdentifier: PluginAuthorization]
    ) throws(PluginManagementWorkflowError) -> PluginManagementSelectionReceipt {
        try pluginManagementCheckCancellation()
        var work = PluginManagementWorkBudget(limits: limits)
        try pluginManagementChargeSnapshot(snapshot, work: &work)
        let candidates = try pluginManagementMapCatalogError {
            try snapshot.catalog.items(matching: request.filter)
        }
        guard candidates.count <= limits.maximumListedItemCount else {
            throw PluginManagementWorkflowError.resultLimitExceeded(
                maximum: limits.maximumListedItemCount
            )
        }
        for item in candidates {
            try pluginManagementChargeDecision(
                item: item,
                policy: snapshot.externalToolPolicy,
                repetitions: 1,
                work: &work
            )
        }
        let outcome = try pluginManagementMapCatalogError {
            try snapshot.catalog.select(
                matching: request.filter,
                mode: request.mode,
                authorizations: authorizations,
                preferences: snapshot.preferences,
                externalToolPolicy: snapshot.externalToolPolicy
            )
        }
        try pluginManagementValidateSelectionOutcome(
            outcome,
            maximumResultCount: limits.maximumListedItemCount
        )
        return PluginManagementSelectionReceipt(
            expectedSnapshot: snapshot.cas(limits: limits),
            request: request,
            outcome: outcome,
            maximumResultCount: limits.maximumListedItemCount
        )
    }

    /// Plans one preference mutation and retains exact canonical persistence bytes privately.
    public func plan(
        _ intent: PluginManagementEditIntent,
        snapshot: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) -> PluginManagementEditPlan {
        try pluginManagementCheckCancellation()
        var work = PluginManagementWorkBudget(limits: limits)
        try pluginManagementChargeSnapshot(snapshot, work: &work)
        switch intent {
        case .addCatalogItem:
            throw PluginManagementWorkflowError.catalogMutationUnavailable(.add)
        case .updateCatalogItem:
            throw PluginManagementWorkflowError.catalogMutationUnavailable(.update)
        case .removeCatalogItem:
            throw PluginManagementWorkflowError.catalogMutationUnavailable(.remove)
        default:
            break
        }

        var enabled = snapshot.preferences.enabledPluginIdentifiers
        var automatic = snapshot.preferences.automaticPluginIdentifiers
        var preferred = snapshot.preferences.preferredAutomaticPluginIdentifiers
        var values = snapshot.preferences.settingValues

        switch intent {
        case .setEnabled(let identifier, let isEnabled):
            try work.consume(identifier.rawValue.utf8.count + 1)
            _ = try requireItem(identifier, in: snapshot.catalog)
            if isEnabled {
                enabled.insert(identifier)
            } else {
                enabled.remove(identifier)
                automatic.remove(identifier)
                preferred.removeAll { $0 == identifier }
            }
        case .setInvocationMode(let identifier, let mode):
            try work.consume(identifier.rawValue.utf8.count + 1)
            let item = try requireItem(identifier, in: snapshot.catalog)
            switch mode {
            case .manual:
                guard item.manualEligible else {
                    throw PluginManagementWorkflowError.manualUseNotDeclared(identifier)
                }
                enabled.insert(identifier)
                automatic.remove(identifier)
                preferred.removeAll { $0 == identifier }
            case .automatic:
                guard item.automaticEligible else {
                    throw PluginManagementWorkflowError.automaticUseNotDeclared(identifier)
                }
                enabled.insert(identifier)
                automatic.insert(identifier)
            }
        case .setSetting(let identifier, let key, let value):
            try work.consume(identifier.rawValue.utf8.count + key.utf8.count + 1)
            try pluginManagementChargeSettingValue(value, work: &work)
            let item = try requireItem(identifier, in: snapshot.catalog)
            try requireSetting(key, on: item)
            try requireNonSecretSetting(key, identifier: identifier, snapshot: snapshot)
            values[identifier, default: [:]][key] = value
        case .removeSetting(let identifier, let key):
            try work.consume(identifier.rawValue.utf8.count + key.utf8.count + 1)
            let item = try requireItem(identifier, in: snapshot.catalog)
            try requireSetting(key, on: item)
            try requireNonSecretSetting(key, identifier: identifier, snapshot: snapshot)
            values[identifier]?.removeValue(forKey: key)
            if values[identifier]?.isEmpty == true {
                values.removeValue(forKey: identifier)
            }
        case .reorderAutomaticPlugins(let identifiers):
            for identifier in identifiers {
                try work.consume(identifier.rawValue.utf8.count + 1)
            }
            preferred = identifiers
        case .addCatalogItem, .updateCatalogItem, .removeCatalogItem:
            preconditionFailure("Catalog mutations are rejected before preference projection")
        }

        try pluginManagementChargeCatalog(snapshot.catalog, work: &work)
        try pluginManagementChargePreferenceState(
            enabled: enabled,
            automatic: automatic,
            preferred: preferred,
            values: values,
            work: &work
        )
        let projectedPreferences = try pluginManagementMapCatalogError {
            try PluginCatalogPreferences(
                catalog: snapshot.catalog,
                enabledPluginIdentifiers: enabled,
                automaticPluginIdentifiers: automatic,
                preferredAutomaticPluginIdentifiers: preferred,
                settingValues: values
            )
        }
        guard projectedPreferences != snapshot.preferences else {
            throw PluginManagementWorkflowError.noChange
        }
        let projectedRevision = try snapshot.revision.successor()
        try pluginManagementChargeCatalog(snapshot.catalog, work: &work)
        try pluginManagementChargePreferences(projectedPreferences, work: &work)
        let projectedSnapshot = try PluginManagementSnapshot(
            revision: projectedRevision,
            catalog: snapshot.catalog,
            preferences: projectedPreferences,
            externalToolPolicy: snapshot.externalToolPolicy
        )
        try pluginManagementChargeCatalog(snapshot.catalog, work: &work)
        try pluginManagementChargePreferences(projectedPreferences, work: &work)
        try work.consume(snapshot.catalog.limits.maximumPersistenceBytes)
        try work.consume(snapshot.catalog.limits.maximumPersistenceBytes)
        let canonicalData = try pluginManagementMapCatalogError {
            try projectedPreferences.encodedData(for: snapshot.catalog)
        }
        try pluginManagementCheckCancellation()
        return PluginManagementEditPlan(
            expectedSnapshot: snapshot.cas(limits: limits),
            intent: intent,
            projectedSnapshot: projectedSnapshot,
            canonicalPersistenceData: canonicalData
        )
    }

    public func reloadRequest(
        snapshot: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) -> PluginManagementReloadRequest {
        try pluginManagementCheckCancellation()
        var work = PluginManagementWorkBudget(limits: limits)
        try pluginManagementChargeSnapshot(snapshot, work: &work)
        let request = PluginManagementReloadRequest(snapshot: snapshot, limits: limits)
        try pluginManagementCheckCancellation()
        return request
    }

    /// Revalidates exact state and reports existing fail-closed reload availability.
    public func reloadResult(
        for request: PluginManagementReloadRequest,
        currentSnapshot: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) -> PluginManagementReloadResult {
        var work = PluginManagementWorkBudget(limits: request.expectedSnapshot.workflowLimits)
        try request.expectedSnapshot.validate(currentSnapshot, work: &work)
        try work.consume(1)
        let currentOutcome = currentSnapshot.catalog.reloadOutcome(
            externalToolPolicy: currentSnapshot.externalToolPolicy
        )
        try pluginManagementCheckCancellation()
        guard currentOutcome == request.operationOutcome else {
            throw PluginManagementWorkflowError.snapshotContentsChanged(
                revision: currentSnapshot.revision
            )
        }
        guard !currentOutcome.isSupported else {
            throw PluginManagementWorkflowError.catalogMutationUnavailable(.reload)
        }
        return PluginManagementReloadResult(
            validatedRevision: currentSnapshot.revision,
            disposition: .unavailable(currentOutcome)
        )
    }

    private func requireItem(
        _ identifier: PluginIdentifier,
        in catalog: PluginCatalog
    ) throws(PluginManagementWorkflowError) -> PluginCatalogItem {
        try pluginManagementCheckCancellation()
        guard let item = catalog.item(withIdentifier: identifier) else {
            throw PluginManagementWorkflowError.unknownPlugin(identifier)
        }
        return item
    }

    private func requireSetting(
        _ key: String,
        on item: PluginCatalogItem
    ) throws(PluginManagementWorkflowError) {
        try pluginManagementCheckCancellation()
        guard item.settings.contains(where: { $0.key == key }) else {
            throw PluginManagementWorkflowError.unknownSetting(
                identifier: item.id,
                key: key
            )
        }
    }

    private func requireNonSecretSetting(
        _ key: String,
        identifier: PluginIdentifier,
        snapshot: PluginManagementSnapshot
    ) throws(PluginManagementWorkflowError) {
        let privacy = try pluginManagementMapCatalogError {
            try snapshot.catalog.settingPrivacy(for: identifier, key: key)
        }
        guard let privacy else {
            throw PluginManagementWorkflowError.unknownSetting(
                identifier: identifier,
                key: key
            )
        }
        guard privacy == .nonSecret else {
            throw PluginManagementWorkflowError.secretSettingRequiresTrustedStorage(
                identifier: identifier,
                key: key
            )
        }
    }

    private static func invocationIntent(
        for identifier: PluginIdentifier,
        preferences: PluginCatalogPreferences
    ) -> PluginManagementInvocationIntent {
        guard preferences.enabledPluginIdentifiers.contains(identifier) else { return .disabled }
        return preferences.automaticPluginIdentifiers.contains(identifier) ? .automatic : .manual
    }

    private static func externalToolBinding(
        for item: PluginCatalogItem,
        policy: ExternalToolPolicy
    ) throws(PluginManagementWorkflowError) -> PluginManagementExternalToolBinding {
        try pluginManagementCheckCancellation()
        guard let capability = item.capability.externalToolCapability else {
            return .executionBackendUnavailable
        }
        guard let ruleIdentifier = item.externalToolRuleIdentifier else {
            return .ruleReferenceMissing(capability)
        }
        var matchedRule: ExternalToolExecutableRule?
        for (index, rule) in policy.externalExecutableRules.enumerated() {
            if index.isMultiple(of: 64) {
                try pluginManagementCheckCancellation()
            }
            if rule.identifier == ruleIdentifier {
                matchedRule = rule
                break
            }
        }
        guard let rule = matchedRule else {
            return .ruleNotConfigured(
                ruleIdentifier: ruleIdentifier,
                capability: capability
            )
        }
        guard rule.capability == capability else {
            return .ruleCapabilityMismatch(
                ruleIdentifier: ruleIdentifier,
                expected: capability,
                actual: rule.capability
            )
        }
        try pluginManagementCheckCancellation()
        return .bound(
            ruleIdentifier: ruleIdentifier,
            capability: capability,
            policyDecision: ExternalToolCapabilityDecision(
                capability: capability,
                status: .supported,
                reason: .explicitExternalExecutableRuleConfigured
            )
        )
    }
}

private struct PluginManagementWorkBudget {
    let limits: PluginManagementWorkflowLimits
    private var consumed = 0

    init(limits: PluginManagementWorkflowLimits) {
        self.limits = limits
    }

    mutating func consume(_ amount: Int = 1) throws(PluginManagementWorkflowError) {
        guard amount >= 0, amount <= limits.maximumWorkUnits - consumed else {
            throw PluginManagementWorkflowError.workLimitExceeded(
                maximum: limits.maximumWorkUnits
            )
        }
        var remaining = amount
        while remaining > 0 {
            let untilCheckpoint =
                limits.cancellationCheckInterval
                - consumed % limits.cancellationCheckInterval
            let step = min(remaining, untilCheckpoint)
            consumed += step
            remaining -= step
            if consumed.isMultiple(of: limits.cancellationCheckInterval) {
                try pluginManagementCheckCancellation()
            }
        }
    }
}

private func pluginManagementChargeCatalog(
    _ catalog: PluginCatalog,
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    try work.consume(1)
    for item in catalog.items {
        try pluginManagementChargeItem(item, work: &work)
    }
}

private func pluginManagementChargeSnapshot(
    _ snapshot: PluginManagementSnapshot,
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    try pluginManagementChargeCatalog(snapshot.catalog, work: &work)
    try pluginManagementChargePreferences(snapshot.preferences, work: &work)
    for rule in snapshot.externalToolPolicy.externalExecutableRules {
        try pluginManagementChargeRule(rule, work: &work)
    }
}

private func pluginManagementChargeRule(
    _ rule: ExternalToolExecutableRule,
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    try work.consume(
        rule.identifier.utf8.count + rule.executableURL.absoluteString.utf8.count
            + rule.approvedExecutableSHA256.count + 1
    )
    for scope in rule.permittedWorkingDirectories {
        try work.consume(scope.url.absoluteString.utf8.count + 1)
    }
    for scope in rule.permittedReadScopes {
        try work.consume(scope.url.absoluteString.utf8.count + 1)
    }
    for scope in rule.permittedWriteScopes {
        try work.consume(scope.url.absoluteString.utf8.count + 1)
    }
    for key in rule.allowedEnvironmentKeys {
        try work.consume(key.utf8.count + 1)
    }
    for constraint in rule.argumentConstraints {
        switch constraint {
        case .exact(let value):
            try work.consume(value.utf8.count + 1)
        case .oneOf(let values):
            for value in values {
                try work.consume(value.utf8.count + 1)
            }
        case .value, .readPath, .writePath:
            try work.consume(1)
        }
    }
}

private func pluginManagementChargeItem(
    _ item: PluginCatalogItem,
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    try work.consume(
        item.id.rawValue.utf8.count + item.displayName.utf8.count
            + (item.summary?.utf8.count ?? 0) + item.version.utf8.count
            + (item.externalToolRuleIdentifier?.utf8.count ?? 0) + 1
    )
    for value in item.matchMetadata.fileExtensions + item.matchMetadata.contentTypeIdentifiers {
        try work.consume(value.utf8.count + 1)
    }
    for schema in item.settings {
        try work.consume(
            schema.key.utf8.count + schema.title.utf8.count
                + (schema.summary?.utf8.count ?? 0) + 1
        )
        if case .choice(let choices) = schema.constraint {
            for choice in choices {
                try work.consume(choice.utf8.count + 1)
            }
        }
        if let value = schema.defaultValue {
            try pluginManagementChargeSettingValue(value, work: &work)
        }
    }
}

private func pluginManagementChargeSettingIdentity(
    item: PluginCatalogItem,
    schema: PluginSettingSchema,
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    try work.consume(
        item.id.rawValue.utf8.count + item.version.utf8.count
            + schema.key.utf8.count + schema.title.utf8.count
            + (schema.summary?.utf8.count ?? 0) + 1
    )
    if case .choice(let choices) = schema.constraint {
        for choice in choices {
            try work.consume(choice.utf8.count + 1)
        }
    }
    if let value = schema.defaultValue {
        try pluginManagementChargeSettingValue(value, work: &work)
    }
}

private func pluginManagementChargePreferences(
    _ preferences: PluginCatalogPreferences,
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    try pluginManagementChargePreferenceState(
        enabled: preferences.enabledPluginIdentifiers,
        automatic: preferences.automaticPluginIdentifiers,
        preferred: preferences.preferredAutomaticPluginIdentifiers,
        values: preferences.settingValues,
        work: &work
    )
}

private func pluginManagementChargePreferenceState(
    enabled: Set<PluginIdentifier>,
    automatic: Set<PluginIdentifier>,
    preferred: [PluginIdentifier],
    values: [PluginIdentifier: [String: PluginSettingValue]],
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    for identifier in enabled {
        try work.consume(identifier.rawValue.utf8.count + 1)
    }
    for identifier in automatic {
        try work.consume(identifier.rawValue.utf8.count + 1)
    }
    for identifier in preferred {
        try work.consume(identifier.rawValue.utf8.count + 1)
    }
    for (identifier, namespace) in values {
        try work.consume(identifier.rawValue.utf8.count + 1)
        for (key, value) in namespace {
            try work.consume(key.utf8.count + 1)
            try pluginManagementChargeSettingValue(value, work: &work)
        }
    }
}

private func pluginManagementChargeSettingValue(
    _ value: PluginSettingValue,
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    switch value {
    case .boolean, .integer:
        try work.consume(1)
    case .string(let value), .choice(let value):
        try work.consume(value.utf8.count + 1)
    }
}

private func pluginManagementChargeDecision(
    item: PluginCatalogItem,
    policy: ExternalToolPolicy,
    repetitions: Int,
    work: inout PluginManagementWorkBudget
) throws(PluginManagementWorkflowError) {
    for _ in 0..<repetitions {
        try pluginManagementChargeItem(item, work: &work)
        for rule in policy.externalExecutableRules {
            try pluginManagementChargeRule(rule, work: &work)
        }
    }
}

private func pluginManagementValidateSelectionOutcome(
    _ outcome: PluginCatalogSelectionOutcome,
    maximumResultCount: Int
) throws(PluginManagementWorkflowError) {
    if case .ambiguous(let identifiers) = outcome,
        identifiers.count > maximumResultCount
    {
        throw PluginManagementWorkflowError.resultLimitExceeded(maximum: maximumResultCount)
    }
}

private func pluginManagementCheckCancellation() throws(PluginManagementWorkflowError) {
    if Task.isCancelled {
        throw PluginManagementWorkflowError.cancelled
    }
}

private func pluginManagementMapCatalogError<Value>(
    _ operation: () throws -> Value
) throws(PluginManagementWorkflowError) -> Value {
    do {
        return try operation()
    } catch let error as PluginManagementWorkflowError {
        throw error
    } catch let error as PluginCatalogError {
        throw PluginManagementWorkflowError.catalog(error)
    } catch is CancellationError {
        throw PluginManagementWorkflowError.cancelled
    } catch {
        throw PluginManagementWorkflowError.unexpectedCatalogFailure
    }
}
