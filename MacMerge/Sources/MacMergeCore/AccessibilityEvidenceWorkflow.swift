import CryptoKit
import Foundation

public struct AccessibilityEvidenceRevision: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// Exact identity and monotonically advancing caller-owned revision.
public struct AccessibilityEvidenceRevisionReference: Comparable, Hashable, Sendable {
    public let id: AccessibilityStableID
    public let revision: AccessibilityEvidenceRevision

    public init(id: AccessibilityStableID, revision: AccessibilityEvidenceRevision) {
        self.id = id
        self.revision = revision
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.id != right.id { return left.id < right.id }
        return left.revision < right.revision
    }
}

public enum AccessibilityEvidenceAppearance: String, CaseIterable, Hashable, Sendable {
    case light
    case dark
}

/// Caller-captured runtime settings for one semantic snapshot. This type does not read system state.
public struct AccessibilityEvidenceEnvironment: Equatable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let fullKeyboardAccessEnabled: Bool
    public let voiceOverEnabled: Bool
    public let increasedContrastEnabled: Bool
    public let differentiateWithoutColorEnabled: Bool
    public let appearance: AccessibilityEvidenceAppearance
    public let localeIdentifier: String
    /// 1000 is baseline size; values above 1000 represent expansion.
    public let localizationExpansionThousandths: Int

    public init(
        fullKeyboardAccessEnabled: Bool,
        voiceOverEnabled: Bool,
        increasedContrastEnabled: Bool,
        differentiateWithoutColorEnabled: Bool,
        appearance: AccessibilityEvidenceAppearance,
        localeIdentifier: String,
        localizationExpansionThousandths: Int = 1_000
    ) {
        self.fullKeyboardAccessEnabled = fullKeyboardAccessEnabled
        self.voiceOverEnabled = voiceOverEnabled
        self.increasedContrastEnabled = increasedContrastEnabled
        self.differentiateWithoutColorEnabled = differentiateWithoutColorEnabled
        self.appearance = appearance
        self.localeIdentifier = localeIdentifier.precomposedStringWithCanonicalMapping
        self.localizationExpansionThousandths = localizationExpansionThousandths
    }

    public var description: String { "AccessibilityEvidenceEnvironment(<redacted>)" }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["environment": "<redacted>"], displayStyle: .struct)
    }
}

/// Digests for exact executable resources and signing identity used by a production build.
public struct AccessibilityEvidenceBuildBinding: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let artifactSHA256: [UInt8]
    public let signingIdentitySHA256: [UInt8]

    public init(artifactSHA256: [UInt8], signingIdentitySHA256: [UInt8]) {
        self.artifactSHA256 = artifactSHA256
        self.signingIdentitySHA256 = signingIdentitySHA256
    }

    public var description: String { "AccessibilityEvidenceBuildBinding(digests: <redacted>)" }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["digests": "<redacted>"], displayStyle: .struct)
    }
}

/// Canonical identity for one runtime capture. Values are caller-captured, then validated and bound.
public struct AccessibilityEvidenceCaptureProvenance: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let capturedAtUnixMilliseconds: UInt64
    public let runNonce: [UInt8]
    public let collector: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let buildBinding: AccessibilityEvidenceBuildBinding

    public init(
        capturedAtUnixMilliseconds: UInt64,
        runNonce: [UInt8],
        collector: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding
    ) {
        self.capturedAtUnixMilliseconds = capturedAtUnixMilliseconds
        self.runNonce = runNonce
        self.collector = collector
        self.build = build
        self.buildBinding = buildBinding
    }

    public var description: String {
        "AccessibilityEvidenceCaptureProvenance(collector: \(collector.id.rawValue)/\(collector.revision.rawValue), build: \(build.id.rawValue)/\(build.revision.rawValue), capture: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "collector": collector,
                "build": build,
                "capture": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum AccessibilityEvidenceEnvironmentCheck: String, CaseIterable, Hashable, Sendable {
    case fullKeyboardAccess
    case voiceOverActivation
    case increasedContrast
    case differentiateWithoutColor
    case darkMode
    case localizationExpansion
}

/// One production control and every scenario in which it must resolve in the semantic snapshot.
public struct AccessibilityProductionControl: Identifiable, Equatable, Sendable {
    public let id: AccessibilityStableID
    public let scenarioIDs: [AccessibilityStableID]

    public init(id: AccessibilityStableID, scenarioIDs: [AccessibilityStableID]) {
        self.id = id
        self.scenarioIDs = scenarioIDs
    }
}

public struct AccessibilityEvidenceActionPostcondition: Identifiable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var id: AccessibilityStableID { actionID }

    public let actionID: AccessibilityStableID
    public let snapshotSHA256: [UInt8]

    public init(actionID: AccessibilityStableID, snapshotSHA256: [UInt8]) {
        self.actionID = actionID
        self.snapshotSHA256 = snapshotSHA256
    }

    public var description: String {
        "AccessibilityEvidenceActionPostcondition(actionID: \(actionID.rawValue), digest: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["actionID": actionID, "snapshotSHA256": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public struct AccessibilityEvidenceInventoryScenario: Identifiable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var id: AccessibilityStableID { reference.id }

    public let reference: AccessibilityEvidenceRevisionReference
    public let environment: AccessibilityEvidenceEnvironment
    /// Expected platform-neutral semantics. Runtime evidence remains separate and caller-supplied.
    public let expectedSnapshot: AccessibilityCommandControlSnapshot
    public let requiredEnvironmentChecks: Set<AccessibilityEvidenceEnvironmentCheck>
    public let actionPostconditions: [AccessibilityEvidenceActionPostcondition]

    public init(
        reference: AccessibilityEvidenceRevisionReference,
        environment: AccessibilityEvidenceEnvironment,
        expectedSnapshot: AccessibilityCommandControlSnapshot,
        requiredEnvironmentChecks: Set<AccessibilityEvidenceEnvironmentCheck>,
        actionPostconditions: [AccessibilityEvidenceActionPostcondition] = []
    ) {
        self.reference = reference
        self.environment = environment
        self.expectedSnapshot = expectedSnapshot
        self.requiredEnvironmentChecks = requiredEnvironmentChecks
        self.actionPostconditions = actionPostconditions
    }

    public var description: String {
        "AccessibilityEvidenceInventoryScenario(id: \(id.rawValue), revision: \(reference.revision.rawValue), semantics: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "environment": "<redacted>",
                "requiredEnvironmentChecks": requiredEnvironmentChecks,
                "actionPostconditionCount": actionPostconditions.count,
                "expectedSnapshot": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Exact app/build-bound production inventory. Controls are matched only by caller-owned stable ID.
public struct AccessibilityProductionControlInventory: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let buildBinding: AccessibilityEvidenceBuildBinding
    public let reference: AccessibilityEvidenceRevisionReference
    public let controls: [AccessibilityProductionControl]
    public let scenarios: [AccessibilityEvidenceInventoryScenario]
    /// Coverage promised by this inventory. Default requires every supported environment check.
    public let requiredEnvironmentChecks: Set<AccessibilityEvidenceEnvironmentCheck>

    public init(
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding,
        reference: AccessibilityEvidenceRevisionReference,
        controls: [AccessibilityProductionControl],
        scenarios: [AccessibilityEvidenceInventoryScenario]
    ) {
        self.app = app
        self.build = build
        self.buildBinding = buildBinding
        self.reference = reference
        self.controls = controls
        self.scenarios = scenarios
        requiredEnvironmentChecks = Set(AccessibilityEvidenceEnvironmentCheck.allCases)
    }

    public var description: String {
        "AccessibilityProductionControlInventory(app: \(app.id.rawValue)/\(app.revision.rawValue), build: \(build.id.rawValue)/\(build.revision.rawValue), inventory: \(reference.id.rawValue)/\(reference.revision.rawValue), controls: \(controls.count), scenarios: \(scenarios.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "app": app,
                "build": build,
                "buildBinding": "<redacted>",
                "reference": reference,
                "controlCount": controls.count,
                "scenarioCount": scenarios.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum AccessibilityEvidenceRequirementKind: String, CaseIterable, Hashable, Sendable {
    case semanticSnapshot
    case semanticRole
    case semanticLabel
    case semanticHierarchy
    case hiddenState
    case focusability
    case keyboardShortcuts
    case fullKeyboardAccess
    case voiceOverActivation
    case increasedContrast
    case differentiateWithoutColor
    case darkMode
    case localizationExpansion
    case focusOrder
    case enabledState
    case checkedState
    case selectedState
    case value
    case hint
    case actionBehavior
    case announcementBehavior
}

/// Canonical matrix coordinate. `discriminator` identifies an action when one subject has several.
public struct AccessibilityEvidenceRequirementKey: Comparable, Hashable, Sendable {
    public let scenarioID: AccessibilityStableID
    public let subjectID: AccessibilityStableID?
    public let kind: AccessibilityEvidenceRequirementKind
    public let discriminator: AccessibilityStableID?

    public init(
        scenarioID: AccessibilityStableID,
        subjectID: AccessibilityStableID? = nil,
        kind: AccessibilityEvidenceRequirementKind,
        discriminator: AccessibilityStableID? = nil
    ) {
        self.scenarioID = scenarioID
        self.subjectID = subjectID
        self.kind = kind
        self.discriminator = discriminator
    }

    public static func < (left: Self, right: Self) -> Bool {
        accessibilityEvidenceCompareComponents(left.sortComponents, right.sortComponents) < 0
    }

    fileprivate var sortComponents: [String] {
        [scenarioID.rawValue, kind.rawValue, subjectID?.rawValue ?? "", discriminator?.rawValue ?? ""]
    }
}

public enum AccessibilityEvidenceConditionOutcome: String, CaseIterable, Hashable, Sendable {
    case satisfied
    case notApplicable
    case notSatisfied
    case inconclusive
    case notObserved
}

public enum AccessibilityEvidenceActionOutcome: String, CaseIterable, Hashable, Sendable {
    case performed
    case blocked
    case failed
    case notObserved
}

public enum AccessibilityEvidenceAnnouncementOutcome: String, CaseIterable, Hashable, Sendable {
    case delivered
    case notDelivered
    case notObserved
}

/// Typed expected or observed matrix value. String-bearing descriptions are always redacted.
public enum AccessibilityEvidenceValue: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    case snapshot(AccessibilityStableID)
    case semanticRole(AccessibilitySemanticRole)
    case semanticLabel(String?)
    case parentID(AccessibilityStableID?)
    case hidden(Bool)
    case focusable(Bool)
    case keyboardShortcuts([AccessibilityStableID])
    case condition(AccessibilityEvidenceConditionOutcome)
    case focusOrder([AccessibilityStableID])
    case enabled(Bool)
    case checked(AccessibilityCheckedState)
    case selected(AccessibilitySelectedState)
    case value(String?)
    case hint(String?)
    case action(
        actionID: AccessibilityStableID,
        kind: AccessibilitySemanticActionKind,
        outcome: AccessibilityEvidenceActionOutcome
    )
    case announcement(
        announcementID: AccessibilityStableID,
        kind: AccessibilityAnnouncementKind,
        outcome: AccessibilityEvidenceAnnouncementOutcome
    )

    public var description: String {
        switch self {
        case .snapshot(let id): "snapshot(\(id.rawValue))"
        case .semanticRole(let role): "semanticRole(\(role.rawValue))"
        case .semanticLabel: "semanticLabel(<redacted>)"
        case .parentID(let id): "parentID(\(id?.rawValue ?? "nil"))"
        case .hidden(let hidden): "hidden(\(hidden))"
        case .focusable(let focusable): "focusable(\(focusable))"
        case .keyboardShortcuts(let ids): "keyboardShortcuts(count: \(ids.count))"
        case .condition(let outcome): "condition(\(outcome.rawValue))"
        case .focusOrder(let ids): "focusOrder(count: \(ids.count))"
        case .enabled(let enabled): "enabled(\(enabled))"
        case .checked(let state): "checked(\(state.rawValue))"
        case .selected(let state): "selected(\(state.rawValue))"
        case .value: "value(<redacted>)"
        case .hint: "hint(<redacted>)"
        case .action(let actionID, let kind, let outcome):
            "action(id: \(actionID.rawValue), kind: \(kind.rawValue), outcome: \(outcome.rawValue))"
        case .announcement(let announcementID, let kind, let outcome):
            "announcement(id: \(announcementID.rawValue), kind: \(kind.rawValue), outcome: \(outcome.rawValue))"
        }
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["value": description], displayStyle: .enum)
    }
}

public enum AccessibilityEvidenceAttachmentKind: String, CaseIterable, Hashable, Sendable {
    case accessibilityTranscript
    case interactionLog
    case measurementRecord
    case structuredTestRecord
}

public enum AccessibilityEvidenceAttachmentResolutionError: Error, Equatable, Sendable {
    case exceedsDeclaredByteCount
}

/// Payload remains caller-owned. Digest, declared byte count, and bounded metadata bind references.
public struct AccessibilityEvidenceAttachment: Identifiable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let id: AccessibilityStableID
    public let kind: AccessibilityEvidenceAttachmentKind
    public let mediaType: String
    public let byteCount: Int
    public let sha256: [UInt8]
    public let source: String

    public init(
        id: AccessibilityStableID,
        kind: AccessibilityEvidenceAttachmentKind,
        mediaType: String,
        byteCount: Int,
        sha256: [UInt8],
        source: String
    ) {
        self.id = id
        self.kind = kind
        self.mediaType = mediaType.precomposedStringWithCanonicalMapping
        self.byteCount = byteCount
        self.sha256 = sha256
        self.source = source.precomposedStringWithCanonicalMapping
    }

    public var description: String {
        "AccessibilityEvidenceAttachment(id: \(id.rawValue), kind: \(kind.rawValue), bytes: \(byteCount), metadata: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "id": id,
                "kind": kind,
                "byteCount": byteCount,
                "sha256": "<redacted>",
                "mediaType": "<redacted>",
                "source": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// One caller-supplied observation. Presence and archive validity do not prove runtime behavior.
public struct AccessibilityBehaviorObservation: Identifiable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let id: AccessibilityStableID
    public let requirement: AccessibilityEvidenceRequirementKey
    public let snapshotID: AccessibilityStableID
    public let value: AccessibilityEvidenceValue
    public let origin: AccessibilityEvidenceOrigin
    public let source: String
    public let attachmentTokens: [AccessibilityStableID]
    /// Required for successful action observations; canonically binds the observed post-action state.
    public let postconditionSnapshot: AccessibilityCommandControlSnapshot?

    public init(
        id: AccessibilityStableID,
        requirement: AccessibilityEvidenceRequirementKey,
        snapshotID: AccessibilityStableID,
        value: AccessibilityEvidenceValue,
        origin: AccessibilityEvidenceOrigin,
        source: String,
        attachmentTokens: [AccessibilityStableID] = [],
        postconditionSnapshot: AccessibilityCommandControlSnapshot? = nil
    ) {
        self.id = id
        self.requirement = requirement
        self.snapshotID = snapshotID
        self.value = value
        self.origin = origin
        self.source = source.precomposedStringWithCanonicalMapping
        self.attachmentTokens = attachmentTokens
        self.postconditionSnapshot = postconditionSnapshot
    }

    public var description: String {
        "AccessibilityBehaviorObservation(id: \(id.rawValue), kind: \(requirement.kind.rawValue), evidence: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "id": id,
                "requirement": requirement,
                "snapshotID": snapshotID,
                "origin": origin,
                "attachmentCount": attachmentTokens.count,
                "postconditionSnapshot": "<redacted>",
                "value": "<redacted>",
                "source": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct AccessibilityScenarioEvidence: Identifiable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var id: AccessibilityStableID { scenario.id }

    public let scenario: AccessibilityEvidenceRevisionReference
    public let environment: AccessibilityEvidenceEnvironment
    public let provenance: AccessibilityEvidenceCaptureProvenance
    public let snapshot: AccessibilityCommandControlSnapshot
    public let observations: [AccessibilityBehaviorObservation]

    public init(
        scenario: AccessibilityEvidenceRevisionReference,
        environment: AccessibilityEvidenceEnvironment,
        provenance: AccessibilityEvidenceCaptureProvenance,
        snapshot: AccessibilityCommandControlSnapshot,
        observations: [AccessibilityBehaviorObservation]
    ) {
        self.scenario = scenario
        self.environment = environment
        self.provenance = provenance
        self.snapshot = snapshot
        self.observations = observations
    }

    public var description: String {
        "AccessibilityScenarioEvidence(id: \(id.rawValue), revision: \(scenario.revision.rawValue), observations: \(observations.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "scenario": scenario,
                "environment": "<redacted>",
                "provenance": "<redacted>",
                "observationCount": observations.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Caller-supplied evidence only. No initializer performs AX, UI, screenshot, or filesystem work.
public struct AccessibilityEvidenceBundle: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: AccessibilityEvidenceRevisionReference
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let buildBinding: AccessibilityEvidenceBuildBinding
    public let inventory: AccessibilityEvidenceRevisionReference
    public let scenarios: [AccessibilityScenarioEvidence]
    public let attachments: [AccessibilityEvidenceAttachment]

    public init(
        reference: AccessibilityEvidenceRevisionReference,
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding,
        inventory: AccessibilityEvidenceRevisionReference,
        scenarios: [AccessibilityScenarioEvidence],
        attachments: [AccessibilityEvidenceAttachment] = []
    ) {
        self.reference = reference
        self.app = app
        self.build = build
        self.buildBinding = buildBinding
        self.inventory = inventory
        self.scenarios = scenarios
        self.attachments = attachments
    }

    public var description: String {
        "AccessibilityEvidenceBundle(reference: \(reference.id.rawValue)/\(reference.revision.rawValue), scenarios: \(scenarios.count), attachments: \(attachments.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "app": app,
                "build": build,
                "buildBinding": "<redacted>",
                "inventory": inventory,
                "scenarioCount": scenarios.count,
                "attachmentCount": attachments.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct AccessibilityEvidenceWorkflowLimits: Equatable, Sendable {
    public static let hardMaximumCount = 1_000_000
    public static let hardMaximumTotalItems = 2_000_000
    public static let hardMaximumStringUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 128 * 1_024 * 1_024
    public static let hardMaximumAttachmentBytes = 1 * 1_024 * 1_024 * 1_024
    public static let hardMaximumTotalAttachmentBytes: UInt64 = 1 << 40
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let hardMaximumArchiveBytes = 512 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = AccessibilityEvidenceWorkflowLimits()

    public let maximumControls: Int
    public let maximumScenarios: Int
    public let maximumElements: Int
    public let maximumObservations: Int
    public let maximumRequiredRequirements: Int
    public let maximumAttachments: Int
    public let maximumAttachmentTokens: Int
    public let maximumAttachmentTokensPerObservation: Int
    public let maximumTotalItems: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumAttachmentBytes: Int
    public let maximumTotalAttachmentBytes: UInt64
    public let maximumWorkUnits: UInt64
    public let maximumFindings: Int
    public let maximumArchiveBytes: Int
    public let cancellationCheckInterval: Int
    public let semanticAuditLimits: AccessibilityAuditLimits

    public init(
        maximumControls: Int = 20_000,
        maximumScenarios: Int = 1_024,
        maximumElements: Int = 100_000,
        maximumObservations: Int = 1_000_000,
        maximumRequiredRequirements: Int = 1_000_000,
        maximumAttachments: Int = 100_000,
        maximumAttachmentTokens: Int = 1_000_000,
        maximumAttachmentTokensPerObservation: Int = 64,
        maximumTotalItems: Int = 2_000_000,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 32 * 1_024 * 1_024,
        maximumAttachmentBytes: Int = 256 * 1_024 * 1_024,
        maximumTotalAttachmentBytes: UInt64 = 1 << 32,
        maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
        maximumFindings: Int = 200_000,
        maximumArchiveBytes: Int = 128 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 256,
        semanticAuditLimits: AccessibilityAuditLimits = .default
    ) {
        self.maximumControls = maximumControls
        self.maximumScenarios = maximumScenarios
        self.maximumElements = maximumElements
        self.maximumObservations = maximumObservations
        self.maximumRequiredRequirements = maximumRequiredRequirements
        self.maximumAttachments = maximumAttachments
        self.maximumAttachmentTokens = maximumAttachmentTokens
        self.maximumAttachmentTokensPerObservation = maximumAttachmentTokensPerObservation
        self.maximumTotalItems = maximumTotalItems
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumAttachmentBytes = maximumAttachmentBytes
        self.maximumTotalAttachmentBytes = maximumTotalAttachmentBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumFindings = maximumFindings
        self.maximumArchiveBytes = maximumArchiveBytes
        self.cancellationCheckInterval = cancellationCheckInterval
        self.semanticAuditLimits = semanticAuditLimits
    }
}

public enum AccessibilityEvidenceLimit: String, CaseIterable, Hashable, Sendable {
    case controls
    case scenarios
    case elements
    case observations
    case requiredRequirements
    case attachments
    case attachmentTokens
    case attachmentTokensPerObservation
    case totalItems
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case attachmentBytes
    case totalAttachmentBytes
    case workUnits
    case findings
    case archiveBytes
    case cancellationCheckInterval
}

public enum AccessibilityEvidenceWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(AccessibilityEvidenceLimit)
    case countLimitExceeded(kind: AccessibilityEvidenceLimit, maximum: Int)
    case stringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case attachmentTooLarge(maximumBytes: Int)
    case totalAttachmentsTooLarge(maximumBytes: UInt64)
    case workLimitExceeded(maximum: UInt64)
    case findingLimitExceeded(maximum: Int)
    case invalidInventory(field: String)
    case invalidEvidence(field: String)
    case staleApp(
        expected: AccessibilityEvidenceRevisionReference,
        actual: AccessibilityEvidenceRevisionReference
    )
    case staleBuild(
        expected: AccessibilityEvidenceRevisionReference,
        actual: AccessibilityEvidenceRevisionReference
    )
    case staleInventory(
        expected: AccessibilityEvidenceRevisionReference,
        actual: AccessibilityEvidenceRevisionReference
    )
    case staleScenario(
        expected: AccessibilityEvidenceRevisionReference,
        actual: AccessibilityEvidenceRevisionReference
    )
    case staleEvidence(
        expected: AccessibilityEvidenceRevisionReference,
        actual: AccessibilityEvidenceRevisionReference
    )
    case inventoryContentsChanged(AccessibilityEvidenceRevisionReference)
    case evidenceContentsChanged(AccessibilityEvidenceRevisionReference)
    case archiveTooLarge(maximumBytes: Int)
    case invalidArchive
    case unsupportedArchiveVersion(Int)
    case archiveChecksumMismatch
    case nonCanonicalArchive

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Accessibility evidence workflow was cancelled."
        case .invalidLimit(let limit):
            "Accessibility evidence limit is invalid: \(limit.rawValue)."
        case .countLimitExceeded(let kind, let maximum):
            "Accessibility evidence exceeds the \(maximum)-\(kind.rawValue) limit."
        case .stringTooLarge(let field, let maximum):
            "Accessibility evidence field \(field) exceeds \(maximum) UTF-8 bytes."
        case .totalStringsTooLarge(let maximum):
            "Accessibility evidence strings exceed \(maximum) UTF-8 bytes."
        case .attachmentTooLarge(let maximum):
            "Accessibility evidence attachment exceeds \(maximum) declared bytes."
        case .totalAttachmentsTooLarge(let maximum):
            "Accessibility evidence attachments exceed \(maximum) declared bytes."
        case .workLimitExceeded(let maximum):
            "Accessibility evidence processing exceeds \(maximum) work units."
        case .findingLimitExceeded(let maximum):
            "Accessibility evidence processing exceeds \(maximum) findings."
        case .invalidInventory(let field):
            "Accessibility production inventory is invalid at \(field); contents are redacted."
        case .invalidEvidence(let field):
            "Accessibility evidence is invalid at \(field); contents are redacted."
        case .staleApp:
            "Accessibility evidence belongs to another app identity or revision."
        case .staleBuild:
            "Accessibility evidence belongs to another build identity or revision."
        case .staleInventory:
            "Accessibility evidence belongs to another inventory identity or revision."
        case .staleScenario:
            "Accessibility evidence belongs to another scenario revision."
        case .staleEvidence:
            "Accessibility evidence revision changed before compare-and-swap validation."
        case .inventoryContentsChanged:
            "Accessibility inventory contents changed without an inventory revision change."
        case .evidenceContentsChanged:
            "Accessibility evidence contents changed without an evidence revision change."
        case .archiveTooLarge(let maximum):
            "Accessibility evidence archive exceeds \(maximum) bytes."
        case .invalidArchive:
            "Accessibility evidence archive has invalid framing or field data."
        case .unsupportedArchiveVersion(let version):
            "Unsupported accessibility evidence archive version: \(version)."
        case .archiveChecksumMismatch:
            "Accessibility evidence archive checksum does not match its payload."
        case .nonCanonicalArchive:
            "Accessibility evidence archive is valid but not in canonical wire form."
        }
    }
}

public enum AccessibilityEvidenceFindingSeverity: String, CaseIterable, Comparable, Hashable,
    Sendable
{
    case advisory
    case warning
    case error

    public static func < (left: Self, right: Self) -> Bool {
        left.rank < right.rank
    }

    fileprivate var rank: Int {
        switch self {
        case .advisory: 0
        case .warning: 1
        case .error: 2
        }
    }
}

public enum AccessibilityEvidenceFindingCode: String, CaseIterable, Hashable, Sendable {
    case duplicateScenarioEvidence
    case missingScenarioEvidence
    case unexpectedScenarioEvidence
    case environmentMismatch
    case semanticSnapshotMismatch
    case semanticElementMissing
    case unexpectedSemanticElement
    case semanticElementMismatch
    case focusOrderMismatch
    case announcementMismatch
    case snapshotAuditIssue
    case duplicateAttachmentToken
    case duplicateObservationToken
    case duplicateEvidence
    case assertionOnlyEvidence
    case emptyAttachmentEvidence
    case invalidActionPostcondition
    case missingEvidence
    case unexpectedEvidence
    case evidenceValueMismatch
    case attachmentReferenceMissing
    case orphanAttachment
}

public enum AccessibilityEvidenceFindingSubject: Hashable, Sendable {
    case bundle
    case scenario(AccessibilityStableID)
    case element(scenarioID: AccessibilityStableID, elementID: AccessibilityStableID)
    case requirement(AccessibilityEvidenceRequirementKey)
    case observation(AccessibilityStableID)
    case attachment(AccessibilityStableID)

    fileprivate var identityComponents: [String] {
        switch self {
        case .bundle: ["bundle"]
        case .scenario(let id): ["scenario", id.rawValue]
        case .element(let scenarioID, let elementID):
            ["element", scenarioID.rawValue, elementID.rawValue]
        case .requirement(let key): ["requirement"] + key.sortComponents
        case .observation(let id): ["observation", id.rawValue]
        case .attachment(let id): ["attachment", id.rawValue]
        }
    }
}

public struct AccessibilityEvidenceFinding: Identifiable, Hashable, Sendable {
    public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            accessibilityEvidenceCompareUTF8(left.rawValue, right.rawValue) < 0
        }
    }

    public let id: ID
    public let severity: AccessibilityEvidenceFindingSeverity
    public let code: AccessibilityEvidenceFindingCode
    public let subject: AccessibilityEvidenceFindingSubject
    /// Fixed, non-payload-bearing wording. Semantic text and evidence sources are never included.
    public let message: String

    fileprivate init(
        severity: AccessibilityEvidenceFindingSeverity,
        code: AccessibilityEvidenceFindingCode,
        subject: AccessibilityEvidenceFindingSubject,
        discriminator: String = ""
    ) {
        self.severity = severity
        self.code = code
        self.subject = subject
        message = accessibilityEvidenceFindingMessage(code)
        id = ID(
            rawValue: ([code.rawValue] + subject.identityComponents + [discriminator])
                .map(accessibilityEvidenceFrame).joined()
        )
    }
}

public enum AccessibilityEvidenceCompletenessStatus: String, CaseIterable, Hashable, Sendable {
    case complete
    case missing
    case duplicate
    case mismatched
    case invalid
    case assertionOnly
}

public struct AccessibilityEvidenceCompletenessCell: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public let requirement: AccessibilityEvidenceRequirementKey
    public let expected: AccessibilityEvidenceValue
    public let observed: AccessibilityEvidenceValue?
    public let evidenceCount: Int
    public let status: AccessibilityEvidenceCompletenessStatus

    fileprivate init(
        requirement: AccessibilityEvidenceRequirementKey,
        expected: AccessibilityEvidenceValue,
        observed: AccessibilityEvidenceValue?,
        evidenceCount: Int,
        status: AccessibilityEvidenceCompletenessStatus
    ) {
        self.requirement = requirement
        self.expected = expected
        self.observed = observed
        self.evidenceCount = evidenceCount
        self.status = status
    }

    public var description: String {
        "AccessibilityEvidenceCompletenessCell(kind: \(requirement.kind.rawValue), count: \(evidenceCount), status: \(status.rawValue), values: <redacted>)"
    }

    public var debugDescription: String { description }
}

public struct AccessibilityEvidenceCompletenessMatrix: Equatable, Sendable {
    public let cells: [AccessibilityEvidenceCompletenessCell]

    fileprivate init(cells: [AccessibilityEvidenceCompletenessCell]) {
        self.cells = cells
    }

    public var requiredCount: Int { cells.count }
    public var completeCount: Int { cells.count(where: { $0.status == .complete }) }
    public var missingCount: Int { cells.count(where: { $0.status == .missing }) }
    public var duplicateCount: Int { cells.count(where: { $0.status == .duplicate }) }
    public var mismatchedCount: Int { cells.count(where: { $0.status == .mismatched }) }
    public var invalidCount: Int { cells.count(where: { $0.status == .invalid }) }
    public var assertionOnlyCount: Int { cells.count(where: { $0.status == .assertionOnly }) }
    public var isComplete: Bool { completeCount == requiredCount }
}

public struct AccessibilityEvidenceReport: Equatable, Sendable {
    public static let scopeStatement =
        "Deterministic validation of caller-supplied, build-bound semantic captures and verified attachment-backed observations for declared role, label, hierarchy, visibility, focusability, shortcuts, state, action postconditions, announcements, contrast, non-color, dark appearance, and localization requirements; not independent runtime accessibility or production compliance."

    public let formatVersion: Int
    public let inventory: AccessibilityEvidenceRevisionReference
    public let evidence: AccessibilityEvidenceRevisionReference
    public let matrix: AccessibilityEvidenceCompletenessMatrix
    public let findings: [AccessibilityEvidenceFinding]

    public var highestSeverity: AccessibilityEvidenceFindingSeverity? { findings.first?.severity }
    public var containsErrors: Bool { findings.contains { $0.severity == .error } }
    /// Means only that every declared matrix cell has one exact, measured, attachment-backed observation and no finding.
    public var isEvidenceCompleteAndValid: Bool { matrix.isComplete && findings.isEmpty }

    fileprivate init(
        formatVersion: Int,
        inventory: AccessibilityEvidenceRevisionReference,
        evidence: AccessibilityEvidenceRevisionReference,
        matrix: AccessibilityEvidenceCompletenessMatrix,
        findings: [AccessibilityEvidenceFinding]
    ) {
        self.formatVersion = formatVersion
        self.inventory = inventory
        self.evidence = evidence
        self.matrix = matrix
        self.findings = findings
    }
}

public struct AccessibilityEvidenceCanonicalArchive: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let data: Data
    public let sha256: [UInt8]

    fileprivate init(data: Data, sha256: [UInt8]) {
        self.data = data
        self.sha256 = sha256
    }

    public var description: String {
        "AccessibilityEvidenceCanonicalArchive(bytes: \(data.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["byteCount": data.count, "data": "<redacted>", "sha256": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Deterministic content receipt. Digests are SHA-256 over canonical inventory and archive bytes.
public struct AccessibilityEvidenceReceipt: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let formatVersion: Int
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let inventory: AccessibilityEvidenceRevisionReference
    public let evidence: AccessibilityEvidenceRevisionReference
    public let buildBinding: AccessibilityEvidenceBuildBinding
    public let inventorySHA256: [UInt8]
    public let evidenceArchiveSHA256: [UInt8]
    public let requiredEvidenceCount: Int
    public let completeEvidenceCount: Int
    public let findingCount: Int
    public let archiveByteCount: Int

    fileprivate init(
        formatVersion: Int,
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        inventory: AccessibilityEvidenceRevisionReference,
        evidence: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding,
        inventorySHA256: [UInt8],
        evidenceArchiveSHA256: [UInt8],
        requiredEvidenceCount: Int,
        completeEvidenceCount: Int,
        findingCount: Int,
        archiveByteCount: Int
    ) {
        self.formatVersion = formatVersion
        self.app = app
        self.build = build
        self.inventory = inventory
        self.evidence = evidence
        self.buildBinding = buildBinding
        self.inventorySHA256 = inventorySHA256
        self.evidenceArchiveSHA256 = evidenceArchiveSHA256
        self.requiredEvidenceCount = requiredEvidenceCount
        self.completeEvidenceCount = completeEvidenceCount
        self.findingCount = findingCount
        self.archiveByteCount = archiveByteCount
    }

    public var description: String {
        "AccessibilityEvidenceReceipt(inventory: \(inventory.id.rawValue)/\(inventory.revision.rawValue), evidence: \(evidence.id.rawValue)/\(evidence.revision.rawValue), required: \(requiredEvidenceCount), complete: \(completeEvidenceCount), findings: \(findingCount), digests: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "formatVersion": formatVersion,
                "app": app,
                "build": build,
                "inventory": inventory,
                "evidence": evidence,
                "buildBinding": "<redacted>",
                "requiredEvidenceCount": requiredEvidenceCount,
                "completeEvidenceCount": completeEvidenceCount,
                "findingCount": findingCount,
                "archiveByteCount": archiveByteCount,
                "digests": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public func validateCurrent(
        inventory currentInventory: AccessibilityProductionControlInventory,
        evidence currentEvidence: AccessibilityEvidenceBundle,
        limits: AccessibilityEvidenceWorkflowLimits = .default,
        attachmentResolver: AccessibilityEvidenceWorkflow.AttachmentResolver,
        cancellationCheck: @escaping AccessibilityEvidenceWorkflow.CancellationCheck = {
            Task.isCancelled
        }
    ) throws {
        try AccessibilityEvidenceWorkflow.validate(
            receipt: self,
            inventory: currentInventory,
            evidence: currentEvidence,
            limits: limits,
            attachmentResolver: attachmentResolver,
            cancellationCheck: cancellationCheck
        )
    }
}

public struct AccessibilityEvidenceWorkflowResult: Equatable, Sendable {
    public let report: AccessibilityEvidenceReport
    public let archive: AccessibilityEvidenceCanonicalArchive
    public let receipt: AccessibilityEvidenceReceipt

    fileprivate init(
        report: AccessibilityEvidenceReport,
        archive: AccessibilityEvidenceCanonicalArchive,
        receipt: AccessibilityEvidenceReceipt
    ) {
        self.report = report
        self.archive = archive
        self.receipt = receipt
    }
}

/// UI-independent evidence comparison and persistence. All observations and attachment metadata are
/// caller-supplied; this workflow never invokes AX, assistive technology, UI, screenshots, or I/O.
public enum AccessibilityEvidenceWorkflow: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool
    /// Resolver must stop before returning more than `declaredByteCount` bytes and throw
    /// `AccessibilityEvidenceAttachmentResolutionError.exceedsDeclaredByteCount` on overflow.
    public typealias AttachmentResolver = (
        _ id: AccessibilityStableID,
        _ declaredByteCount: Int,
        _ cancellationCheck: CancellationCheck
    ) throws -> Data

    public static let reportFormatVersion = 2
    public static let archiveFormatVersion = 2
    private static let archiveMagic = Data("MMAXEWF2".utf8)

    /// Canonical attachment payload for one measured observation and its exact capture provenance.
    public static func canonicalAttachmentData(
        for observation: AccessibilityBehaviorObservation,
        capturedIn scenario: AccessibilityScenarioEvidence,
        limits: AccessibilityEvidenceWorkflowLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try AccessibilityEvidenceValidation.validateLimits(limits)
        let budget = try AccessibilityEvidenceWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        guard scenario.observations.contains(where: { $0.id == observation.id }) else {
            throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                field: "attachment.observationBinding"
            )
        }
        let data = try AccessibilityEvidenceCanonicalEncoder.encodeAttachmentPayload(
            observation,
            scenario: scenario,
            limits: limits,
            budget: budget
        )
        guard data.count <= limits.maximumAttachmentBytes else {
            throw AccessibilityEvidenceWorkflowError.attachmentTooLarge(
                maximumBytes: limits.maximumAttachmentBytes
            )
        }
        try budget.finish()
        return data
    }

    public static func evaluate(
        inventory: AccessibilityProductionControlInventory,
        evidence: AccessibilityEvidenceBundle,
        limits: AccessibilityEvidenceWorkflowLimits = .default,
        attachmentResolver: AttachmentResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> AccessibilityEvidenceWorkflowResult {
        do {
            let budget = try AccessibilityEvidenceWorkBudget(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try AccessibilityEvidenceValidation.validate(
                inventory: inventory,
                evidence: evidence,
                limits: limits,
                attachmentResolver: attachmentResolver,
                cancellationCheck: cancellationCheck,
                budget: budget
            )
            try validateBinding(inventory: inventory, evidence: evidence, budget: budget)

            var context = AccessibilityEvidenceEvaluationContext(
                inventory: inventory,
                evidence: evidence,
                limits: limits,
                budget: budget
            )
            let report = try context.run()
            let archive = try canonicalArchive(
                for: evidence,
                boundTo: inventory,
                limits: limits,
                budget: budget
            )
            let inventoryData = try AccessibilityEvidenceCanonicalEncoder.encodeInventory(
                inventory,
                limits: limits,
                budget: budget
            )
            let inventoryDigest = try accessibilityEvidenceSHA256(inventoryData, budget: budget)
            let receipt = AccessibilityEvidenceReceipt(
                formatVersion: reportFormatVersion,
                app: inventory.app,
                build: inventory.build,
                inventory: inventory.reference,
                evidence: evidence.reference,
                buildBinding: inventory.buildBinding,
                inventorySHA256: inventoryDigest,
                evidenceArchiveSHA256: archive.sha256,
                requiredEvidenceCount: report.matrix.requiredCount,
                completeEvidenceCount: report.matrix.completeCount,
                findingCount: report.findings.count,
                archiveByteCount: archive.data.count
            )
            try budget.finish()
            return AccessibilityEvidenceWorkflowResult(
                report: report,
                archive: archive,
                receipt: receipt
            )
        } catch is CancellationError {
            throw AccessibilityEvidenceWorkflowError.cancelled
        }
    }

    public static func canonicalArchive(
        for evidence: AccessibilityEvidenceBundle,
        boundTo inventory: AccessibilityProductionControlInventory,
        limits: AccessibilityEvidenceWorkflowLimits = .default,
        attachmentResolver: AttachmentResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> AccessibilityEvidenceCanonicalArchive {
        do {
            let budget = try AccessibilityEvidenceWorkBudget(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try AccessibilityEvidenceValidation.validate(
                inventory: inventory,
                evidence: evidence,
                limits: limits,
                attachmentResolver: attachmentResolver,
                cancellationCheck: cancellationCheck,
                budget: budget
            )
            try validateBinding(inventory: inventory, evidence: evidence, budget: budget)
            let archive = try canonicalArchive(
                for: evidence,
                boundTo: inventory,
                limits: limits,
                budget: budget
            )
            try budget.finish()
            return archive
        } catch is CancellationError {
            throw AccessibilityEvidenceWorkflowError.cancelled
        }
    }

    /// Verifies framing, checksum, canonical bytes, and exact bundle/inventory binding.
    public static func validate(
        archive: Data,
        for evidence: AccessibilityEvidenceBundle,
        boundTo inventory: AccessibilityProductionControlInventory,
        limits: AccessibilityEvidenceWorkflowLimits = .default,
        attachmentResolver: AttachmentResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        do {
            let budget = try AccessibilityEvidenceWorkBudget(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try AccessibilityEvidenceValidation.validate(
                inventory: inventory,
                evidence: evidence,
                limits: limits,
                attachmentResolver: attachmentResolver,
                cancellationCheck: cancellationCheck,
                budget: budget
            )
            try validateBinding(inventory: inventory, evidence: evidence, budget: budget)
            try AccessibilityEvidenceArchiveValidation.validate(
                archive,
                limits: limits,
                budget: budget
            )
            let canonical = try canonicalArchive(
                for: evidence,
                boundTo: inventory,
                limits: limits,
                budget: budget
            )
            guard try accessibilityEvidenceDataEqual(archive, canonical.data, budget: budget) else {
                throw AccessibilityEvidenceWorkflowError.nonCanonicalArchive
            }
            try budget.finish()
        } catch is CancellationError {
            throw AccessibilityEvidenceWorkflowError.cancelled
        }
    }

    /// Exact compare-and-swap validation for owner state and canonical contents.
    public static func validate(
        receipt: AccessibilityEvidenceReceipt,
        inventory: AccessibilityProductionControlInventory,
        evidence: AccessibilityEvidenceBundle,
        limits: AccessibilityEvidenceWorkflowLimits = .default,
        attachmentResolver: AttachmentResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        do {
            let budget = try AccessibilityEvidenceWorkBudget(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            guard receipt.formatVersion == reportFormatVersion,
                receipt.inventorySHA256.count == SHA256.byteCount,
                receipt.evidenceArchiveSHA256.count == SHA256.byteCount,
                receipt.requiredEvidenceCount >= 0,
                receipt.completeEvidenceCount >= 0,
                receipt.completeEvidenceCount <= receipt.requiredEvidenceCount,
                receipt.findingCount >= 0,
                receipt.archiveByteCount >= 0
            else {
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                    field: "receipt"
                )
            }
            guard inventory.app == receipt.app else {
                throw AccessibilityEvidenceWorkflowError.staleApp(
                    expected: receipt.app,
                    actual: inventory.app
                )
            }
            guard inventory.build == receipt.build else {
                throw AccessibilityEvidenceWorkflowError.staleBuild(
                    expected: receipt.build,
                    actual: inventory.build
                )
            }
            guard inventory.buildBinding == receipt.buildBinding else {
                throw AccessibilityEvidenceWorkflowError.evidenceContentsChanged(
                    evidence.reference
                )
            }
            guard inventory.reference == receipt.inventory else {
                throw AccessibilityEvidenceWorkflowError.staleInventory(
                    expected: receipt.inventory,
                    actual: inventory.reference
                )
            }
            guard evidence.reference == receipt.evidence else {
                throw AccessibilityEvidenceWorkflowError.staleEvidence(
                    expected: receipt.evidence,
                    actual: evidence.reference
                )
            }
            try AccessibilityEvidenceValidation.validate(
                inventory: inventory,
                evidence: evidence,
                limits: limits,
                attachmentResolver: attachmentResolver,
                cancellationCheck: cancellationCheck,
                budget: budget
            )
            try validateBinding(inventory: inventory, evidence: evidence, budget: budget)
            let inventoryData = try AccessibilityEvidenceCanonicalEncoder.encodeInventory(
                inventory,
                limits: limits,
                budget: budget
            )
            let inventoryDigest = try accessibilityEvidenceSHA256(inventoryData, budget: budget)
            guard inventoryDigest == receipt.inventorySHA256 else {
                throw AccessibilityEvidenceWorkflowError.inventoryContentsChanged(
                    inventory.reference
                )
            }
            let archive = try canonicalArchive(
                for: evidence,
                boundTo: inventory,
                limits: limits,
                budget: budget
            )
            guard archive.sha256 == receipt.evidenceArchiveSHA256,
                archive.data.count == receipt.archiveByteCount
            else {
                throw AccessibilityEvidenceWorkflowError.evidenceContentsChanged(
                    evidence.reference
                )
            }
            var context = AccessibilityEvidenceEvaluationContext(
                inventory: inventory,
                evidence: evidence,
                limits: limits,
                budget: budget
            )
            let report = try context.run()
            guard report.matrix.requiredCount == receipt.requiredEvidenceCount,
                report.matrix.completeCount == receipt.completeEvidenceCount,
                report.findings.count == receipt.findingCount
            else {
                throw AccessibilityEvidenceWorkflowError.evidenceContentsChanged(
                    evidence.reference
                )
            }
            try budget.finish()
        } catch is CancellationError {
            throw AccessibilityEvidenceWorkflowError.cancelled
        }
    }

    private static func canonicalArchive(
        for evidence: AccessibilityEvidenceBundle,
        boundTo inventory: AccessibilityProductionControlInventory,
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) throws -> AccessibilityEvidenceCanonicalArchive {
        let payload = try AccessibilityEvidenceCanonicalEncoder.encodeEvidence(
            evidence,
            limits: limits,
            budget: budget
        )
        let inventoryData = try AccessibilityEvidenceCanonicalEncoder.encodeInventory(
            inventory,
            limits: limits,
            budget: budget
        )
        let inventoryDigest = try accessibilityEvidenceSHA256(inventoryData, budget: budget)
        let payloadDigest = try accessibilityEvidenceSHA256(payload, budget: budget)
        let writer = AccessibilityEvidenceWriter(limits: limits, budget: budget)
        try writer.appendRaw(archiveMagic)
        try writer.appendUInt16(UInt16(archiveFormatVersion))
        try writer.appendUInt16(0)
        try writer.appendUInt64(UInt64(payload.count))
        try writer.appendRaw(inventoryDigest)
        try writer.appendRaw(payloadDigest)
        try writer.appendRaw(payload)
        let archiveDigest = try accessibilityEvidenceSHA256(writer.data, budget: budget)
        return AccessibilityEvidenceCanonicalArchive(data: writer.data, sha256: archiveDigest)
    }

    private static func validateBinding(
        inventory: AccessibilityProductionControlInventory,
        evidence: AccessibilityEvidenceBundle,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        guard evidence.app == inventory.app else {
            throw AccessibilityEvidenceWorkflowError.staleApp(
                expected: inventory.app,
                actual: evidence.app
            )
        }
        guard evidence.build == inventory.build else {
            throw AccessibilityEvidenceWorkflowError.staleBuild(
                expected: inventory.build,
                actual: evidence.build
            )
        }
        guard evidence.buildBinding == inventory.buildBinding else {
            throw AccessibilityEvidenceWorkflowError.staleBuild(
                expected: inventory.build,
                actual: evidence.build
            )
        }
        guard evidence.inventory == inventory.reference else {
            throw AccessibilityEvidenceWorkflowError.staleInventory(
                expected: inventory.reference,
                actual: evidence.inventory
            )
        }
        let expectedByID = try accessibilityEvidenceDictionary(
            inventory.scenarios,
            budget: budget,
            key: \.id
        )
        for scenario in evidence.scenarios {
            try budget.consume()
            guard let expected = expectedByID[scenario.id] else { continue }
            guard scenario.scenario == expected.reference else {
                throw AccessibilityEvidenceWorkflowError.staleScenario(
                    expected: expected.reference,
                    actual: scenario.scenario
                )
            }
            guard scenario.provenance.build == inventory.build,
                scenario.provenance.buildBinding == inventory.buildBinding
            else {
                throw AccessibilityEvidenceWorkflowError.staleBuild(
                    expected: inventory.build,
                    actual: scenario.provenance.build
                )
            }
        }
    }
}

private struct AccessibilityEvidenceExpectedRequirement {
    let key: AccessibilityEvidenceRequirementKey
    let value: AccessibilityEvidenceValue
    let requiredPostconditionSnapshotSHA256: [UInt8]?

    init(
        key: AccessibilityEvidenceRequirementKey,
        value: AccessibilityEvidenceValue,
        requiredPostconditionSnapshotSHA256: [UInt8]? = nil
    ) {
        self.key = key
        self.value = value
        self.requiredPostconditionSnapshotSHA256 = requiredPostconditionSnapshotSHA256
    }
}

private struct AccessibilityEvidenceEvaluationContext {
    let inventory: AccessibilityProductionControlInventory
    let evidence: AccessibilityEvidenceBundle
    let limits: AccessibilityEvidenceWorkflowLimits
    let budget: AccessibilityEvidenceWorkBudget
    private var findings: [AccessibilityEvidenceFinding] = []
    private var findingIDs: Set<AccessibilityEvidenceFinding.ID> = []

    init(
        inventory: AccessibilityProductionControlInventory,
        evidence: AccessibilityEvidenceBundle,
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) {
        self.inventory = inventory
        self.evidence = evidence
        self.limits = limits
        self.budget = budget
    }

    mutating func run() throws -> AccessibilityEvidenceReport {
        let expectedScenarios = try accessibilityEvidenceDictionary(
            inventory.scenarios,
            budget: budget,
            key: \.id
        )
        let observedByScenario = try accessibilityEvidenceGroupedDictionary(
            evidence.scenarios,
            budget: budget,
            key: \.id
        )
        let required = try expectedRequirements()
        var invalidRequirementKeys: Set<AccessibilityEvidenceRequirementKey> = []

        for scenario in try accessibilityEvidenceSortedByID(
            inventory.scenarios,
            budget: budget,
            id: \.id
        ) {
            try budget.consume()
            let observed = observedByScenario[scenario.id] ?? []
            if observed.isEmpty {
                try add(.error, .missingScenarioEvidence, subject: .scenario(scenario.id))
                continue
            }
            if observed.count > 1 {
                try add(
                    .error,
                    .duplicateScenarioEvidence,
                    subject: .scenario(scenario.id),
                    discriminator: String(observed.count)
                )
            }
            for candidate in observed {
                try compareScenario(candidate, expected: scenario)
            }
        }
        for scenarioID in try accessibilityEvidenceSorted(
            Array(observedByScenario.keys),
            budget: budget
        )
        where expectedScenarios[scenarioID] == nil {
            try add(.error, .unexpectedScenarioEvidence, subject: .scenario(scenarioID))
        }

        let attachmentsByID = try accessibilityEvidenceGroupedDictionary(
            evidence.attachments,
            budget: budget,
            key: \.id
        )
        var attachmentCounts: [AccessibilityStableID: Int] = [:]
        var emptyAttachmentIDs: Set<AccessibilityStableID> = []
        var attachmentsByDigest: [[UInt8]: [AccessibilityEvidenceAttachment]] = [:]
        attachmentCounts.reserveCapacity(attachmentsByID.count)
        for (id, attachments) in attachmentsByID {
            try budget.consume()
            attachmentCounts[id] = attachments.count
            if attachments.count == 1 {
                attachmentsByDigest[attachments[0].sha256, default: []].append(attachments[0])
            }
            if attachments.contains(where: { $0.byteCount == 0 }) {
                emptyAttachmentIDs.insert(id)
            }
        }
        for id in try accessibilityEvidenceSorted(Array(attachmentCounts.keys), budget: budget)
        where attachmentCounts[id, default: 0] > 1 {
            try add(
                .error,
                .duplicateAttachmentToken,
                subject: .attachment(id),
                discriminator: String(attachmentCounts[id, default: 0])
            )
        }

        var usedAttachmentIDs: Set<AccessibilityStableID> = []
        var observationCounts: [AccessibilityStableID: Int] = [:]
        var observationsByRequirement: [AccessibilityEvidenceRequirementKey: [AccessibilityBehaviorObservation]] = [:]
        let expectedByKey = try accessibilityEvidenceDictionary(
            required,
            budget: budget,
            key: \.key,
            rejectingDuplicates: true
        )
        for scenario in evidence.scenarios {
            for observation in scenario.observations {
                try budget.consume()
                observationCounts[observation.id, default: 0] += 1
                observationsByRequirement[observation.requirement, default: []].append(observation)
                let canonicalAttachment = try AccessibilityEvidenceCanonicalEncoder.encodeAttachmentPayload(
                    observation,
                    scenario: scenario,
                    limits: limits,
                    budget: budget
                )
                let canonicalAttachmentDigest = try accessibilityEvidenceSHA256(
                    canonicalAttachment,
                    budget: budget
                )
                let boundAttachmentIDs = Set(
                    attachmentsByDigest[canonicalAttachmentDigest, default: []].filter {
                        $0.byteCount == canonicalAttachment.count
                            && ($0.kind == .measurementRecord
                                || $0.kind == .structuredTestRecord)
                    }.map(\.id)
                )
                if !observation.attachmentTokens.contains(where: boundAttachmentIDs.contains) {
                    invalidRequirementKeys.insert(observation.requirement)
                    try add(
                        .error,
                        .attachmentReferenceMissing,
                        subject: .observation(observation.id),
                        discriminator: "canonical-record"
                    )
                }
                if try !accessibilityEvidenceObservationMatchesScopedEvidence(
                    observation,
                    snapshot: scenario.snapshot,
                    environment: scenario.environment,
                    budget: budget
                ) {
                    invalidRequirementKeys.insert(observation.requirement)
                    try add(
                        .error,
                        .evidenceValueMismatch,
                        subject: .requirement(observation.requirement),
                        discriminator: "scoped-evidence"
                    )
                }
                for attachmentID in observation.attachmentTokens {
                    try budget.consume()
                    usedAttachmentIDs.insert(attachmentID)
                    guard attachmentCounts[attachmentID] == 1 else {
                        invalidRequirementKeys.insert(observation.requirement)
                        try add(
                            .error,
                            .attachmentReferenceMissing,
                            subject: .observation(observation.id),
                            discriminator: attachmentID.rawValue
                        )
                        continue
                    }
                    if emptyAttachmentIDs.contains(attachmentID) {
                        invalidRequirementKeys.insert(observation.requirement)
                        try add(
                            .error,
                            .emptyAttachmentEvidence,
                            subject: .observation(observation.id),
                            discriminator: attachmentID.rawValue
                        )
                    }
                }
                if expectedByKey[observation.requirement] == nil {
                    try add(
                        .warning,
                        .unexpectedEvidence,
                        subject: .requirement(observation.requirement)
                    )
                }
            }
        }
        for id in try accessibilityEvidenceSorted(Array(observationCounts.keys), budget: budget)
        where observationCounts[id, default: 0] > 1 {
            try add(
                .error,
                .duplicateObservationToken,
                subject: .observation(id),
                discriminator: String(observationCounts[id, default: 0])
            )
        }
        for id in try accessibilityEvidenceSorted(Array(attachmentCounts.keys), budget: budget)
        where !usedAttachmentIDs.contains(id) {
            try add(.warning, .orphanAttachment, subject: .attachment(id))
        }

        var cells: [AccessibilityEvidenceCompletenessCell] = []
        cells.reserveCapacity(required.count)
        for requirement in required {
            try budget.consume()
            let observations = observationsByRequirement[requirement.key] ?? []
            let observedValue = try canonicalObservedValue(observations)
            let status: AccessibilityEvidenceCompletenessStatus
            let attachmentCount = observations.first?.attachmentTokens.count ?? 0
            let assertionOnly = observations.contains { $0.origin == .callerAssertion }
            let invalidPostcondition = try observations.contains {
                guard accessibilityEvidenceActionSucceeded($0.value) else { return false }
                guard let snapshot = $0.postconditionSnapshot,
                    let expectedDigest = requirement.requiredPostconditionSnapshotSHA256
                else { return true }
                let digest = try accessibilityEvidenceCanonicalSnapshotSHA256(
                    snapshot,
                    limits: limits.semanticAuditLimits,
                    budget: budget
                )
                return digest != expectedDigest
            }
            let unexpectedPostcondition = observations.contains {
                !accessibilityEvidenceActionSucceeded($0.value)
                    && $0.postconditionSnapshot != nil
            }
            if observations.count > 1 {
                try add(
                    .error,
                    .duplicateEvidence,
                    subject: .requirement(requirement.key),
                    discriminator: String(observations.count)
                )
            }
            if assertionOnly {
                try add(
                    .error,
                    .assertionOnlyEvidence,
                    subject: .requirement(requirement.key)
                )
            }
            if invalidPostcondition || unexpectedPostcondition {
                try add(
                    .error,
                    .invalidActionPostcondition,
                    subject: .requirement(requirement.key)
                )
            }
            if invalidRequirementKeys.contains(requirement.key) || invalidPostcondition
                || unexpectedPostcondition
            {
                status = .invalid
            } else if observations.isEmpty {
                status = .missing
                try add(
                    .error,
                    .missingEvidence,
                    subject: .requirement(requirement.key)
                )
            } else if observations.count > 1 {
                status = .duplicate
            } else if assertionOnly {
                status = .assertionOnly
            } else if attachmentCount == 0 {
                status = .invalid
                try add(
                    .error,
                    .emptyAttachmentEvidence,
                    subject: .requirement(requirement.key)
                )
            } else if try !accessibilityEvidenceValuesEqual(
                observedValue,
                requirement.value,
                limits: limits,
                budget: budget
            ) {
                status = .mismatched
                try add(
                    .error,
                    .evidenceValueMismatch,
                    subject: .requirement(requirement.key)
                )
            } else {
                status = .complete
            }
            cells.append(
                AccessibilityEvidenceCompletenessCell(
                    requirement: requirement.key,
                    expected: requirement.value,
                    observed: observedValue,
                    evidenceCount: observations.count,
                    status: status
                )
            )
        }

        let sortedFindings = try findings.sorted { left, right in
            try budget.consume()
            if left.severity != right.severity {
                return left.severity.rank > right.severity.rank
            }
            if left.code != right.code {
                return accessibilityEvidenceCompareUTF8(left.code.rawValue, right.code.rawValue) < 0
            }
            return left.id < right.id
        }
        return AccessibilityEvidenceReport(
            formatVersion: AccessibilityEvidenceWorkflow.reportFormatVersion,
            inventory: inventory.reference,
            evidence: evidence.reference,
            matrix: AccessibilityEvidenceCompletenessMatrix(cells: cells),
            findings: sortedFindings
        )
    }

    private mutating func expectedRequirements() throws -> [AccessibilityEvidenceExpectedRequirement] {
        var result: [AccessibilityEvidenceExpectedRequirement] = []
        for scenario in try accessibilityEvidenceSortedByID(
            inventory.scenarios,
            budget: budget,
            id: \.id
        ) {
            try budget.consume()
            var actionCount = 0
            var scopedEvidenceCount = 0
            for element in scenario.expectedSnapshot.elements {
                actionCount = try accessibilityEvidenceAddCount(
                    element.actions.count,
                    to: actionCount,
                    maximum: limits.maximumRequiredRequirements
                )
                if scenario.requiredEnvironmentChecks.contains(.increasedContrast) {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        max(1, element.contrastEvidenceTokens.count),
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                }
                if scenario.requiredEnvironmentChecks.contains(.darkMode) {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        max(1, element.contrastEvidenceTokens.count),
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                }
                if scenario.requiredEnvironmentChecks.contains(.differentiateWithoutColor) {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        max(1, element.differentiateWithoutColorEvidenceTokens.count),
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                }
                if scenario.requiredEnvironmentChecks.contains(.localizationExpansion) {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        max(1, element.localizationExpansionEvidenceTokens.count),
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                    for action in element.actions {
                        scopedEvidenceCount = try accessibilityEvidenceAddCount(
                            action.localizationExpansionEvidenceTokens.count,
                            to: scopedEvidenceCount,
                            maximum: limits.maximumRequiredRequirements
                        )
                    }
                    for shortcut in element.keyboardShortcuts {
                        scopedEvidenceCount = try accessibilityEvidenceAddCount(
                            shortcut.localizationExpansionEvidenceTokens.count,
                            to: scopedEvidenceCount,
                            maximum: limits.maximumRequiredRequirements
                        )
                    }
                }
                if scenario.requiredEnvironmentChecks.contains(.fullKeyboardAccess),
                    element.actions.isEmpty
                {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        1,
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                }
                if scenario.requiredEnvironmentChecks.contains(.fullKeyboardAccess),
                    !element.actions.isEmpty, element.keyboardShortcuts.isEmpty
                {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        1,
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                }
                if scenario.requiredEnvironmentChecks.contains(.voiceOverActivation),
                    !element.actions.isEmpty
                {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        1,
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                }
                if scenario.requiredEnvironmentChecks.contains(.voiceOverActivation),
                    element.actions.isEmpty
                {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        1,
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                }
            }
            if scenario.requiredEnvironmentChecks.contains(.localizationExpansion) {
                for announcement in scenario.expectedSnapshot.announcements {
                    scopedEvidenceCount = try accessibilityEvidenceAddCount(
                        announcement.localizationExpansionEvidenceTokens.count,
                        to: scopedEvidenceCount,
                        maximum: limits.maximumRequiredRequirements
                    )
                }
            }
            let actionMultiplier =
                1
                + (scenario.requiredEnvironmentChecks.contains(.fullKeyboardAccess) ? 1 : 0)
                + (scenario.requiredEnvironmentChecks.contains(.voiceOverActivation) ? 1 : 0)
            var requiredCount = 2
            let (elementRequirementCount, elementRequirementOverflow) =
                scenario.expectedSnapshot.elements.count.multipliedReportingOverflow(by: 11)
            let (actionRequirementCount, actionRequirementOverflow) =
                actionCount.multipliedReportingOverflow(by: actionMultiplier)
            guard !elementRequirementOverflow, !actionRequirementOverflow else {
                throw AccessibilityEvidenceWorkflowError.countLimitExceeded(
                    kind: .requiredRequirements,
                    maximum: limits.maximumRequiredRequirements
                )
            }
            for count in [
                elementRequirementCount,
                scopedEvidenceCount,
                actionRequirementCount,
                scenario.expectedSnapshot.announcements.count
            ] {
                requiredCount = try accessibilityEvidenceAddCount(
                    count,
                    to: requiredCount,
                    maximum: limits.maximumRequiredRequirements
                )
            }
            guard result.count <= limits.maximumRequiredRequirements,
                requiredCount <= limits.maximumRequiredRequirements - result.count
            else {
                throw AccessibilityEvidenceWorkflowError.countLimitExceeded(
                    kind: .requiredRequirements,
                    maximum: limits.maximumRequiredRequirements
                )
            }
            try budget.consume(UInt64(requiredCount))
            result.append(
                AccessibilityEvidenceExpectedRequirement(
                    key: AccessibilityEvidenceRequirementKey(
                        scenarioID: scenario.id,
                        kind: .semanticSnapshot
                    ),
                    value: .snapshot(scenario.expectedSnapshot.id)
                )
            )
            result.append(
                AccessibilityEvidenceExpectedRequirement(
                    key: AccessibilityEvidenceRequirementKey(
                        scenarioID: scenario.id,
                        kind: .focusOrder
                    ),
                    value: .focusOrder(scenario.expectedSnapshot.focusOrder)
                )
            )
            for element in try accessibilityEvidenceSortedByID(
                scenario.expectedSnapshot.elements,
                budget: budget,
                id: \.id
            ) {
                try budget.consume()
                let subject = element.id
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .semanticRole
                        ),
                        value: .semanticRole(element.role)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .semanticLabel
                        ),
                        value: .semanticLabel(element.label)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .semanticHierarchy
                        ),
                        value: .parentID(element.parentID)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .hiddenState
                        ),
                        value: .hidden(element.isHiddenFromAssistiveTechnology)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .focusability
                        ),
                        value: .focusable(element.isKeyboardFocusable)
                    )
                )
                let shortcutIDs = element.keyboardShortcuts.map(\.id).sorted()
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .keyboardShortcuts
                        ),
                        value: .keyboardShortcuts(shortcutIDs)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .enabledState
                        ),
                        value: .enabled(element.isEnabled)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .checkedState
                        ),
                        value: .checked(element.checkedState)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .selectedState
                        ),
                        value: .selected(element.selectedState)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .value
                        ),
                        value: .value(element.value)
                    )
                )
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: subject,
                            kind: .hint
                        ),
                        value: .hint(element.hint)
                    )
                )
                for action in try accessibilityEvidenceSortedByID(
                    element.actions,
                    budget: budget,
                    id: \.id
                ) {
                    try budget.consume()
                    guard
                        let postcondition = scenario.actionPostconditions.first(where: {
                            $0.actionID == action.id
                        })
                    else {
                        throw AccessibilityEvidenceWorkflowError.invalidInventory(
                            field: "scenarios.actionPostconditions"
                        )
                    }
                    let actionValue = AccessibilityEvidenceValue.action(
                        actionID: action.id,
                        kind: action.kind,
                        outcome: element.isEnabled ? .performed : .blocked
                    )
                    result.append(
                        AccessibilityEvidenceExpectedRequirement(
                            key: AccessibilityEvidenceRequirementKey(
                                scenarioID: scenario.id,
                                subjectID: subject,
                                kind: .actionBehavior,
                                discriminator: action.id
                            ),
                            value: actionValue,
                            requiredPostconditionSnapshotSHA256: postcondition.snapshotSHA256
                        )
                    )
                    if scenario.requiredEnvironmentChecks.contains(.fullKeyboardAccess) {
                        result.append(
                            AccessibilityEvidenceExpectedRequirement(
                                key: AccessibilityEvidenceRequirementKey(
                                    scenarioID: scenario.id,
                                    subjectID: subject,
                                    kind: .fullKeyboardAccess,
                                    discriminator: action.id
                                ),
                                value: actionValue,
                                requiredPostconditionSnapshotSHA256: postcondition.snapshotSHA256
                            )
                        )
                    }
                    if scenario.requiredEnvironmentChecks.contains(.voiceOverActivation) {
                        result.append(
                            AccessibilityEvidenceExpectedRequirement(
                                key: AccessibilityEvidenceRequirementKey(
                                    scenarioID: scenario.id,
                                    subjectID: subject,
                                    kind: .voiceOverActivation,
                                    discriminator: action.id
                                ),
                                value: actionValue,
                                requiredPostconditionSnapshotSHA256: postcondition.snapshotSHA256
                            )
                        )
                    }
                }
            }
            try appendScopedEnvironmentRequirements(for: scenario, to: &result)
            for announcement in try accessibilityEvidenceSortedByID(
                scenario.expectedSnapshot.announcements,
                budget: budget,
                id: \.id
            ) {
                try budget.consume()
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: announcement.relatedElementID,
                            kind: .announcementBehavior,
                            discriminator: announcement.id
                        ),
                        value: .announcement(
                            announcementID: announcement.id,
                            kind: announcement.kind,
                            outcome: .delivered
                        )
                    )
                )
            }
        }
        guard result.count <= limits.maximumRequiredRequirements else {
            throw AccessibilityEvidenceWorkflowError.countLimitExceeded(
                kind: .requiredRequirements,
                maximum: limits.maximumRequiredRequirements
            )
        }
        return try result.sorted { left, right in
            try budget.consume(
                UInt64(
                    left.key.sortComponents.joined().utf8.count
                        + right.key.sortComponents.joined().utf8.count + 1
                )
            )
            return left.key < right.key
        }
    }

    private func appendScopedEnvironmentRequirements(
        for scenario: AccessibilityEvidenceInventoryScenario,
        to result: inout [AccessibilityEvidenceExpectedRequirement]
    ) throws {
        let environmentKinds = Set(scenario.requiredEnvironmentChecks.map(accessibilityEvidenceRequirementKind))
        for element in scenario.expectedSnapshot.elements {
            try budget.consume()
            if environmentKinds.contains(.increasedContrast) {
                try appendTokenRequirements(
                    element.contrastEvidenceTokens.map(\.rawValue),
                    scenarioID: scenario.id,
                    subjectID: element.id,
                    kind: .increasedContrast,
                    to: &result
                )
            }
            if environmentKinds.contains(.differentiateWithoutColor) {
                try appendTokenRequirements(
                    element.differentiateWithoutColorEvidenceTokens.map(\.rawValue),
                    scenarioID: scenario.id,
                    subjectID: element.id,
                    kind: .differentiateWithoutColor,
                    to: &result
                )
            }
            if environmentKinds.contains(.darkMode) {
                try appendTokenRequirements(
                    element.contrastEvidenceTokens.map(\.rawValue),
                    scenarioID: scenario.id,
                    subjectID: element.id,
                    kind: .darkMode,
                    to: &result
                )
            }
            if environmentKinds.contains(.fullKeyboardAccess), element.actions.isEmpty {
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: element.id,
                            kind: .fullKeyboardAccess
                        ),
                        value: .condition(.notApplicable)
                    )
                )
            }
            if environmentKinds.contains(.fullKeyboardAccess), !element.actions.isEmpty,
                element.keyboardShortcuts.isEmpty
            {
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: element.id,
                            kind: .fullKeyboardAccess
                        ),
                        value: .condition(.notSatisfied)
                    )
                )
            }
            if environmentKinds.contains(.voiceOverActivation), element.actions.isEmpty {
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: element.id,
                            kind: .voiceOverActivation
                        ),
                        value: .condition(.notApplicable)
                    )
                )
            }
            if environmentKinds.contains(.voiceOverActivation), !element.actions.isEmpty {
                result.append(
                    AccessibilityEvidenceExpectedRequirement(
                        key: AccessibilityEvidenceRequirementKey(
                            scenarioID: scenario.id,
                            subjectID: element.id,
                            kind: .voiceOverActivation
                        ),
                        value: .condition(.satisfied)
                    )
                )
            }
            if environmentKinds.contains(.localizationExpansion) {
                try appendTokenRequirements(
                    element.localizationExpansionEvidenceTokens.map(\.rawValue),
                    scenarioID: scenario.id,
                    subjectID: element.id,
                    kind: .localizationExpansion,
                    to: &result
                )
                for action in element.actions {
                    for token in action.localizationExpansionEvidenceTokens {
                        try budget.consume()
                        result.append(
                            AccessibilityEvidenceExpectedRequirement(
                                key: AccessibilityEvidenceRequirementKey(
                                    scenarioID: scenario.id,
                                    subjectID: action.id,
                                    kind: .localizationExpansion,
                                    discriminator: AccessibilityStableID(rawValue: token.rawValue)
                                ),
                                value: .condition(.satisfied)
                            )
                        )
                    }
                }
                for shortcut in element.keyboardShortcuts {
                    for token in shortcut.localizationExpansionEvidenceTokens {
                        try budget.consume()
                        result.append(
                            AccessibilityEvidenceExpectedRequirement(
                                key: AccessibilityEvidenceRequirementKey(
                                    scenarioID: scenario.id,
                                    subjectID: shortcut.id,
                                    kind: .localizationExpansion,
                                    discriminator: AccessibilityStableID(rawValue: token.rawValue)
                                ),
                                value: .condition(.satisfied)
                            )
                        )
                    }
                }
            }
        }
        if environmentKinds.contains(.localizationExpansion) {
            for announcement in scenario.expectedSnapshot.announcements {
                for token in announcement.localizationExpansionEvidenceTokens {
                    try budget.consume()
                    result.append(
                        AccessibilityEvidenceExpectedRequirement(
                            key: AccessibilityEvidenceRequirementKey(
                                scenarioID: scenario.id,
                                subjectID: announcement.id,
                                kind: .localizationExpansion,
                                discriminator: AccessibilityStableID(rawValue: token.rawValue)
                            ),
                            value: .condition(.satisfied)
                        )
                    )
                }
            }
        }
    }

    private func appendTokenRequirements(
        _ tokens: [String],
        scenarioID: AccessibilityStableID,
        subjectID: AccessibilityStableID,
        kind: AccessibilityEvidenceRequirementKind,
        to result: inout [AccessibilityEvidenceExpectedRequirement]
    ) throws {
        if tokens.isEmpty {
            let expected: AccessibilityEvidenceConditionOutcome
            switch kind {
            case .increasedContrast:
                expected = .notApplicable
            case .differentiateWithoutColor:
                expected = .notApplicable
            case .darkMode, .localizationExpansion:
                expected = .notSatisfied
            default:
                expected = .notObserved
            }
            result.append(
                AccessibilityEvidenceExpectedRequirement(
                    key: AccessibilityEvidenceRequirementKey(
                        scenarioID: scenarioID,
                        subjectID: subjectID,
                        kind: kind
                    ),
                    value: .condition(expected)
                )
            )
            return
        }
        for token in tokens {
            try budget.consume()
            result.append(
                AccessibilityEvidenceExpectedRequirement(
                    key: AccessibilityEvidenceRequirementKey(
                        scenarioID: scenarioID,
                        subjectID: subjectID,
                        kind: kind,
                        discriminator: AccessibilityStableID(rawValue: token)
                    ),
                    value: .condition(.satisfied)
                )
            )
        }
    }

    private mutating func compareScenario(
        _ observed: AccessibilityScenarioEvidence,
        expected: AccessibilityEvidenceInventoryScenario
    ) throws {
        try budget.consume()
        if observed.environment != expected.environment {
            try add(.error, .environmentMismatch, subject: .scenario(expected.id))
        }
        let expectedSnapshot = expected.expectedSnapshot
        let observedSnapshot = observed.snapshot
        let expectedSnapshotData: Data
        let observedSnapshotData: Data
        do {
            expectedSnapshotData = try accessibilityEvidenceCanonicalSnapshotData(
                of: accessibilityEvidenceSnapshotWithoutAuditEvidence(expectedSnapshot),
                limits: limits.semanticAuditLimits,
                budget: budget
            )
            observedSnapshotData = try accessibilityEvidenceCanonicalSnapshotData(
                of: accessibilityEvidenceSnapshotWithoutAuditEvidence(observedSnapshot),
                limits: limits.semanticAuditLimits,
                budget: budget
            )
        } catch is CancellationError {
            throw AccessibilityEvidenceWorkflowError.cancelled
        } catch let error as AccessibilityEvidenceWorkflowError {
            throw error
        } catch {
            throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                field: "scenario.snapshot"
            )
        }
        if try !accessibilityEvidenceDataEqual(
            expectedSnapshotData,
            observedSnapshotData,
            budget: budget
        ) {
            try add(.error, .semanticSnapshotMismatch, subject: .scenario(expected.id))
        }
        if expectedSnapshot.focusOrder != observedSnapshot.focusOrder {
            try add(.error, .focusOrderMismatch, subject: .scenario(expected.id))
        }

        let expectedElements = try accessibilityEvidenceGroupedDictionary(
            expectedSnapshot.elements,
            budget: budget,
            key: \.id
        )
        let observedElements = try accessibilityEvidenceGroupedDictionary(
            observedSnapshot.elements,
            budget: budget,
            key: \.id
        )
        for id in try accessibilityEvidenceSorted(Array(expectedElements.keys), budget: budget) {
            guard let expectedValues = expectedElements[id] else { continue }
            guard let observedValues = observedElements[id] else {
                try add(
                    .error,
                    .semanticElementMissing,
                    subject: .element(scenarioID: expected.id, elementID: id)
                )
                continue
            }
            guard expectedValues.count == 1, observedValues.count == 1,
                try accessibilityEvidenceSemanticElementEqual(
                    expectedValues[0],
                    observedValues[0],
                    budget: budget
                )
            else {
                try add(
                    .error,
                    .semanticElementMismatch,
                    subject: .element(scenarioID: expected.id, elementID: id)
                )
                continue
            }
        }
        for id in try accessibilityEvidenceSorted(Array(observedElements.keys), budget: budget)
        where expectedElements[id] == nil {
            try add(
                .error,
                .unexpectedSemanticElement,
                subject: .element(scenarioID: expected.id, elementID: id)
            )
        }
        if try !accessibilityEvidenceAnnouncementsEqual(
            expectedSnapshot.announcements,
            observedSnapshot.announcements,
            budget: budget
        ) {
            try add(.error, .announcementMismatch, subject: .scenario(expected.id))
        }

        do {
            try accessibilityEvidenceDebitNestedAudit(
                observedSnapshot,
                budget: budget
            )
            let report = try AccessibilityAudit.audit(
                observedSnapshot,
                limits: limits.semanticAuditLimits
            )
            try budget.checkCancellation()
            var occurrenceByCode: [AccessibilityAuditIssueCode: Int] = [:]
            for issue in report.issues {
                try budget.consume()
                let occurrence = occurrenceByCode[issue.code, default: 0]
                occurrenceByCode[issue.code] = occurrence + 1
                try add(
                    accessibilityEvidenceSeverity(issue.severity),
                    .snapshotAuditIssue,
                    subject: .scenario(expected.id),
                    discriminator: issue.code.rawValue + ":" + String(occurrence)
                )
            }
        } catch is CancellationError {
            throw AccessibilityEvidenceWorkflowError.cancelled
        } catch let error as AccessibilityEvidenceWorkflowError {
            throw error
        } catch is AccessibilityAuditError {
            throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                field: "scenario.snapshot.audit"
            )
        }
    }

    private func canonicalObservedValue(
        _ observations: [AccessibilityBehaviorObservation]
    ) throws -> AccessibilityEvidenceValue? {
        var selected: (key: Data, value: AccessibilityEvidenceValue)?
        for observation in observations {
            try budget.consume()
            let key = try AccessibilityEvidenceCanonicalEncoder.encodeValue(
                observation.value,
                limits: limits,
                budget: budget
            )
            if selected == nil
                || accessibilityEvidenceCompareBytes(key, selected?.key ?? Data()) < 0
            {
                selected = (key, observation.value)
            }
        }
        return selected?.value
    }

    private mutating func add(
        _ severity: AccessibilityEvidenceFindingSeverity,
        _ code: AccessibilityEvidenceFindingCode,
        subject: AccessibilityEvidenceFindingSubject,
        discriminator: String = ""
    ) throws {
        try budget.consume()
        let finding = AccessibilityEvidenceFinding(
            severity: severity,
            code: code,
            subject: subject,
            discriminator: discriminator
        )
        guard findingIDs.insert(finding.id).inserted else { return }
        guard findings.count < limits.maximumFindings else {
            throw AccessibilityEvidenceWorkflowError.findingLimitExceeded(
                maximum: limits.maximumFindings
            )
        }
        findings.append(finding)
    }
}

private enum AccessibilityEvidenceValidation {
    static func validate(
        inventory: AccessibilityProductionControlInventory,
        evidence: AccessibilityEvidenceBundle,
        limits: AccessibilityEvidenceWorkflowLimits,
        attachmentResolver: AccessibilityEvidenceWorkflow.AttachmentResolver,
        cancellationCheck: @escaping AccessibilityEvidenceWorkflow.CancellationCheck,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        try validateLimits(limits)
        try budget.checkCancellation()
        try validateReference(inventory.app, field: "inventory.app", budget: budget)
        try validateReference(inventory.build, field: "inventory.build", budget: budget)
        try validateBuildBinding(
            inventory.buildBinding,
            field: "inventory.buildBinding",
            evidenceField: false
        )
        try validateReference(inventory.reference, field: "inventory.reference", budget: budget)
        try validateReference(evidence.reference, field: "evidence.reference", budget: budget)
        try validateReference(evidence.app, field: "evidence.app", budget: budget)
        try validateReference(evidence.build, field: "evidence.build", budget: budget)
        try validateBuildBinding(
            evidence.buildBinding,
            field: "evidence.buildBinding",
            evidenceField: true
        )
        try validateReference(evidence.inventory, field: "evidence.inventory", budget: budget)

        try requireCount(inventory.controls.count, limit: limits.maximumControls, kind: .controls)
        try requireCount(inventory.scenarios.count, limit: limits.maximumScenarios, kind: .scenarios)
        try requireCount(evidence.scenarios.count, limit: limits.maximumScenarios, kind: .scenarios)
        try requireCount(evidence.attachments.count, limit: limits.maximumAttachments, kind: .attachments)

        var stringBudget = AccessibilityEvidenceStringBudget(limits: limits, work: budget)
        var totalItems = 0
        var totalElements = 0
        var totalFocusOrderEntries = 0
        var totalObservations = 0
        var totalAttachmentTokens = 0
        var totalAttachmentBytes: UInt64 = 0
        var controlIDs: Set<AccessibilityStableID> = []
        var scenarioIDs: Set<AccessibilityStableID> = []

        for reference in [inventory.app, inventory.build, inventory.reference] {
            try stringBudget.consume(reference.id.rawValue, field: "inventory.reference.id")
        }
        for control in inventory.controls {
            try budget.consume()
            totalItems = try add(control.scenarioIDs.count + 1, to: totalItems)
            guard controlIDs.insert(control.id).inserted else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(field: "controls.id")
            }
            try validateID(control.id, field: "controls.id", budget: budget)
            try stringBudget.consume(control.id.rawValue, field: "controls.id")
            guard !control.scenarioIDs.isEmpty else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "controls.scenarioIDs"
                )
            }
            var localScenarioIDs: Set<AccessibilityStableID> = []
            for scenarioID in control.scenarioIDs {
                try budget.consume()
                guard localScenarioIDs.insert(scenarioID).inserted else {
                    throw AccessibilityEvidenceWorkflowError.invalidInventory(
                        field: "controls.scenarioIDs"
                    )
                }
                try validateID(scenarioID, field: "controls.scenarioIDs", budget: budget)
                try stringBudget.consume(scenarioID.rawValue, field: "controls.scenarioIDs")
            }
        }
        for scenario in inventory.scenarios {
            try budget.consume()
            totalItems = try add(1, to: totalItems)
            guard scenarioIDs.insert(scenario.id).inserted else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(field: "scenarios.id")
            }
            try validateReference(scenario.reference, field: "scenarios.reference", budget: budget)
            try stringBudget.consume(scenario.id.rawValue, field: "scenarios.id")
            try validateEnvironment(scenario.environment, field: "scenarios.environment")
            try consumeEnvironment(
                scenario.environment,
                field: "scenarios.environment",
                stringBudget: &stringBudget
            )
            totalElements = try add(scenario.expectedSnapshot.elements.count, to: totalElements)
            totalFocusOrderEntries = try add(
                scenario.expectedSnapshot.focusOrder.count,
                to: totalFocusOrderEntries
            )
            try validateActionPostconditions(scenario, budget: budget)
            try validateFocusOrder(
                scenario.expectedSnapshot.focusOrder,
                field: "scenarios.expectedSnapshot.focusOrder",
                evidenceField: false,
                budget: budget
            )
            try validateSnapshotStringBounds(
                scenario.expectedSnapshot,
                field: "scenarios.expectedSnapshot",
                stringBudget: &stringBudget,
                budget: budget
            )
            try validateSnapshotEvidenceOrigins(
                scenario.expectedSnapshot,
                field: "scenarios.expectedSnapshot",
                allowDesignSpecification: true,
                budget: budget
            )
            let auditReport: AccessibilityAuditReport
            do {
                try accessibilityEvidenceDebitNestedAudit(
                    scenario.expectedSnapshot,
                    budget: budget
                )
                auditReport = try AccessibilityAudit.audit(
                    scenario.expectedSnapshot,
                    limits: limits.semanticAuditLimits
                )
                try budget.checkCancellation()
            } catch is CancellationError {
                throw AccessibilityEvidenceWorkflowError.cancelled
            } catch let error as AccessibilityEvidenceWorkflowError {
                throw error
            } catch {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "scenarios.expectedSnapshot"
                )
            }
            guard !auditReport.containsErrors else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "scenarios.expectedSnapshot"
                )
            }
        }
        guard
            inventory.requiredEnvironmentChecks
                == Set(
                    AccessibilityEvidenceEnvironmentCheck.allCases
                )
        else {
            throw AccessibilityEvidenceWorkflowError.invalidInventory(
                field: "requiredEnvironmentChecks"
            )
        }
        let inventoryScenarioIDs = scenarioIDs
        let inventoriedControlIDs = controlIDs
        let inventoryScenarioByID = try accessibilityEvidenceDictionary(
            inventory.scenarios,
            budget: budget,
            key: \.id
        )
        var inventoryElementIDsByScenario: [AccessibilityStableID: Set<AccessibilityStableID>] = [:]
        for scenario in inventory.scenarios {
            try budget.consume(UInt64(scenario.expectedSnapshot.elements.count) + 1)
            inventoryElementIDsByScenario[scenario.id] = Set(scenario.expectedSnapshot.elements.map(\.id))
        }
        var scenarioIDsByControlID: [AccessibilityStableID: Set<AccessibilityStableID>] = [:]
        for control in inventory.controls {
            try budget.consume(UInt64(control.scenarioIDs.count) + 1)
            scenarioIDsByControlID[control.id] = Set(control.scenarioIDs)
        }
        var allVisibleSemanticControlIDs: Set<AccessibilityStableID> = []
        for scenario in inventory.scenarios {
            for element in scenario.expectedSnapshot.elements
            where !element.isHiddenFromAssistiveTechnology
                && accessibilityEvidenceIsSemanticControl(element)
            {
                try budget.consume()
                allVisibleSemanticControlIDs.insert(element.id)
            }
        }
        guard inventoriedControlIDs == allVisibleSemanticControlIDs else {
            throw AccessibilityEvidenceWorkflowError.invalidInventory(
                field: "controls.completeness"
            )
        }
        for control in inventory.controls {
            guard Set(control.scenarioIDs).isSubset(of: inventoryScenarioIDs) else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "controls.scenarioIDs"
                )
            }
            for scenarioID in control.scenarioIDs {
                guard inventoryElementIDsByScenario[scenarioID]?.contains(control.id) == true
                else {
                    throw AccessibilityEvidenceWorkflowError.invalidInventory(
                        field: "controls.scenarioBinding"
                    )
                }
            }
            for check in inventory.requiredEnvironmentChecks {
                guard
                    control.scenarioIDs.contains(where: { scenarioID in
                        guard let scenario = inventoryScenarioByID[scenarioID] else { return false }
                        return scenario.requiredEnvironmentChecks.contains(check)
                            && accessibilityEvidenceEnvironmentSatisfies(
                                scenario.environment,
                                check: check
                            )
                            && scenario.expectedSnapshot.elements.contains(where: {
                                $0.id == control.id && !$0.isHiddenFromAssistiveTechnology
                            })
                    })
                else {
                    throw AccessibilityEvidenceWorkflowError.invalidInventory(
                        field: "controls.environmentCoverage"
                    )
                }
            }
        }
        for scenario in inventory.scenarios {
            guard
                scenario.requiredEnvironmentChecks.isSubset(
                    of: inventory.requiredEnvironmentChecks
                )
            else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "scenarios.requiredEnvironmentChecks"
                )
            }
            guard
                scenario.requiredEnvironmentChecks.allSatisfy({
                    accessibilityEvidenceEnvironmentSatisfies(scenario.environment, check: $0)
                })
            else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "scenarios.environmentCoverage"
                )
            }
            let exposedControlIDs = Set(
                scenario.expectedSnapshot.elements.filter {
                    !$0.isHiddenFromAssistiveTechnology
                        && accessibilityEvidenceIsSemanticControl($0)
                }.map(\.id)
            )
            guard exposedControlIDs.isSubset(of: inventoriedControlIDs) else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "scenarios.uninventoriedControl"
                )
            }
            for controlID in exposedControlIDs {
                guard scenarioIDsByControlID[controlID]?.contains(scenario.id) == true
                else {
                    throw AccessibilityEvidenceWorkflowError.invalidInventory(
                        field: "scenarios.controlBinding"
                    )
                }
            }
        }
        for check in inventory.requiredEnvironmentChecks {
            guard
                inventory.scenarios.contains(where: {
                    $0.requiredEnvironmentChecks.contains(check)
                        && accessibilityEvidenceEnvironmentSatisfies($0.environment, check: check)
                })
            else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "requiredEnvironmentChecks.coverage"
                )
            }
        }
        guard
            inventory.scenarios.map(\.environment).contains(where: {
                $0.appearance == .light
            }),
            inventory.scenarios.map(\.environment).contains(where: {
                $0.appearance == .dark
            })
        else {
            throw AccessibilityEvidenceWorkflowError.invalidInventory(
                field: "scenarios.appearanceCoverage"
            )
        }

        for reference in [evidence.reference, evidence.app, evidence.build, evidence.inventory] {
            try stringBudget.consume(reference.id.rawValue, field: "evidence.reference.id")
        }
        for scenario in evidence.scenarios {
            try budget.consume()
            totalItems = try add(1, to: totalItems)
            try validateReference(scenario.scenario, field: "evidence.scenario", budget: budget)
            try stringBudget.consume(scenario.id.rawValue, field: "evidence.scenario.id")
            try validateEnvironment(scenario.environment, field: "evidence.environment")
            try validateProvenance(scenario.provenance, budget: budget)
            try stringBudget.consume(
                scenario.provenance.collector.id.rawValue,
                field: "evidence.provenance.collector.id"
            )
            try stringBudget.consume(
                scenario.provenance.build.id.rawValue,
                field: "evidence.provenance.build.id"
            )
            try consumeEnvironment(
                scenario.environment,
                field: "evidence.environment",
                stringBudget: &stringBudget
            )
            totalElements = try add(scenario.snapshot.elements.count, to: totalElements)
            totalFocusOrderEntries = try add(
                scenario.snapshot.focusOrder.count,
                to: totalFocusOrderEntries
            )
            try validateFocusOrder(
                scenario.snapshot.focusOrder,
                field: "evidence.snapshot.focusOrder",
                evidenceField: true,
                budget: budget
            )
            totalObservations = try add(scenario.observations.count, to: totalObservations)
            try validateSnapshotStringBounds(
                scenario.snapshot,
                field: "evidence.snapshot",
                stringBudget: &stringBudget,
                budget: budget
            )
            try validateSnapshotEvidenceOrigins(
                scenario.snapshot,
                field: "evidence.snapshot",
                allowDesignSpecification: false,
                budget: budget
            )
            let snapshotElementIDs = Set(scenario.snapshot.elements.map(\.id))
            var auxiliarySubjectIDs: Set<AccessibilityStableID> = []
            for element in scenario.snapshot.elements {
                for action in element.actions { auxiliarySubjectIDs.insert(action.id) }
                for shortcut in element.keyboardShortcuts { auxiliarySubjectIDs.insert(shortcut.id) }
            }
            for announcement in scenario.snapshot.announcements {
                auxiliarySubjectIDs.insert(announcement.id)
            }
            for observation in scenario.observations {
                try budget.consume()
                totalItems = try add(1, to: totalItems)
                guard observation.requirement.scenarioID == scenario.id else {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.requirement.scenarioID"
                    )
                }
                if let subjectID = observation.requirement.subjectID,
                    !snapshotElementIDs.contains(subjectID),
                    !auxiliarySubjectIDs.contains(subjectID)
                {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.requirement.subjectID"
                    )
                }
                try validateID(observation.id, field: "observations.id", budget: budget)
                try validateRequirement(observation.requirement, budget: budget)
                try validateID(observation.snapshotID, field: "observations.snapshotID", budget: budget)
                guard observation.snapshotID == scenario.snapshot.id else {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.snapshotID"
                    )
                }
                try stringBudget.consume(observation.source, field: "observations.source")
                guard try !isBlank(observation.source, budget: budget) else {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.source"
                    )
                }
                guard
                    observation.origin == .automatedMeasurement
                        || observation.origin == .manualMeasurement
                        || observation.origin == .callerAssertion
                else {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.origin"
                    )
                }
                guard
                    observation.attachmentTokens.count
                        <= limits.maximumAttachmentTokensPerObservation
                else {
                    throw AccessibilityEvidenceWorkflowError.countLimitExceeded(
                        kind: .attachmentTokensPerObservation,
                        maximum: limits.maximumAttachmentTokensPerObservation
                    )
                }
                totalAttachmentTokens = try add(
                    observation.attachmentTokens.count,
                    to: totalAttachmentTokens
                )
                try validateValue(
                    observation.value,
                    for: observation.requirement,
                    budget: budget
                )
                if case .action(let actionID, _, _) = observation.value,
                    actionID != observation.requirement.discriminator
                {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.value.actionID"
                    )
                }
                if case .announcement(let announcementID, _, _) = observation.value,
                    announcementID != observation.requirement.discriminator
                {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.value.announcementID"
                    )
                }
                switch observation.value {
                case .focusOrder(let ids), .keyboardShortcuts(let ids):
                    totalFocusOrderEntries = try add(ids.count, to: totalFocusOrderEntries)
                default:
                    break
                }
                if let postcondition = observation.postconditionSnapshot {
                    totalElements = try add(postcondition.elements.count, to: totalElements)
                    totalFocusOrderEntries = try add(
                        postcondition.focusOrder.count,
                        to: totalFocusOrderEntries
                    )
                    try validateSnapshotStringBounds(
                        postcondition,
                        field: "observations.postconditionSnapshot",
                        stringBudget: &stringBudget,
                        budget: budget
                    )
                    try validateFocusOrder(
                        postcondition.focusOrder,
                        field: "observations.postconditionSnapshot.focusOrder",
                        evidenceField: true,
                        budget: budget
                    )
                    try validateSnapshotEvidenceOrigins(
                        postcondition,
                        field: "observations.postconditionSnapshot",
                        allowDesignSpecification: false,
                        budget: budget
                    )
                }
                let observationStrings: [(String, String?)] = [
                    ("observations.id", observation.id.rawValue),
                    ("observations.snapshotID", observation.snapshotID.rawValue),
                    ("observations.scenarioID", observation.requirement.scenarioID.rawValue),
                    ("observations.subjectID", observation.requirement.subjectID?.rawValue),
                    ("observations.discriminator", observation.requirement.discriminator?.rawValue),
                    ("observations.source", nil)
                ]
                for (field, value) in observationStrings {
                    if let value { try stringBudget.consume(value, field: field) }
                }
                try consumeValue(
                    observation.value,
                    field: "observations.value",
                    stringBudget: &stringBudget
                )
                var localAttachments: Set<AccessibilityStableID> = []
                for token in observation.attachmentTokens {
                    guard localAttachments.insert(token).inserted else {
                        throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                            field: "observations.attachmentTokens"
                        )
                    }
                    try validateID(token, field: "observations.attachmentTokens", budget: budget)
                    try stringBudget.consume(
                        token.rawValue,
                        field: "observations.attachmentTokens"
                    )
                }
            }
        }
        totalItems = try add(totalElements, to: totalItems)
        totalItems = try add(totalFocusOrderEntries, to: totalItems)
        totalItems = try add(totalAttachmentTokens, to: totalItems)
        for attachment in evidence.attachments {
            try budget.consume()
            totalItems = try add(1, to: totalItems)
            try validateID(attachment.id, field: "attachments.id", budget: budget)
            try stringBudget.consume(attachment.mediaType, field: "attachments.mediaType")
            try stringBudget.consume(attachment.source, field: "attachments.source")
            guard try !isBlank(attachment.mediaType, budget: budget),
                try !isBlank(attachment.source, budget: budget),
                attachment.byteCount >= 0, attachment.byteCount <= limits.maximumAttachmentBytes,
                attachment.sha256.count == SHA256.byteCount
            else {
                if attachment.byteCount > limits.maximumAttachmentBytes {
                    throw AccessibilityEvidenceWorkflowError.attachmentTooLarge(
                        maximumBytes: limits.maximumAttachmentBytes
                    )
                }
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(field: "attachments")
            }
            let (nextTotal, overflow) = totalAttachmentBytes.addingReportingOverflow(
                UInt64(attachment.byteCount)
            )
            guard !overflow, nextTotal <= limits.maximumTotalAttachmentBytes else {
                throw AccessibilityEvidenceWorkflowError.totalAttachmentsTooLarge(
                    maximumBytes: limits.maximumTotalAttachmentBytes
                )
            }
            totalAttachmentBytes = nextTotal
            let bytes: Data
            do {
                bytes = try attachmentResolver(
                    attachment.id,
                    attachment.byteCount,
                    cancellationCheck
                )
            } catch is CancellationError {
                throw AccessibilityEvidenceWorkflowError.cancelled
            } catch let error as AccessibilityEvidenceWorkflowError {
                throw error
            } catch {
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                    field: "attachments.resolver"
                )
            }
            guard bytes.count == attachment.byteCount else {
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                    field: "attachments.byteCount"
                )
            }
            try budget.checkCancellation()
            let digest = try accessibilityEvidenceSHA256(bytes, budget: budget)
            guard digest == attachment.sha256 else {
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                    field: "attachments.sha256"
                )
            }
            try stringBudget.consume(attachment.id.rawValue, field: "attachments.id")
        }
        try requireCount(totalElements, limit: limits.maximumElements, kind: .elements)
        try requireCount(
            totalFocusOrderEntries,
            limit: limits.maximumElements,
            kind: .elements
        )
        try requireCount(
            totalObservations,
            limit: limits.maximumObservations,
            kind: .observations
        )
        try requireCount(
            totalAttachmentTokens,
            limit: limits.maximumAttachmentTokens,
            kind: .attachmentTokens
        )
        try requireCount(totalItems, limit: limits.maximumTotalItems, kind: .totalItems)
    }

    static func validateLimits(_ limits: AccessibilityEvidenceWorkflowLimits) throws {
        let intLimits: [(AccessibilityEvidenceLimit, Int, Int)] = [
            (.controls, limits.maximumControls, AccessibilityEvidenceWorkflowLimits.hardMaximumCount),
            (.scenarios, limits.maximumScenarios, AccessibilityEvidenceWorkflowLimits.hardMaximumCount),
            (.elements, limits.maximumElements, AccessibilityEvidenceWorkflowLimits.hardMaximumCount),
            (.observations, limits.maximumObservations, AccessibilityEvidenceWorkflowLimits.hardMaximumCount),
            (
                .requiredRequirements,
                limits.maximumRequiredRequirements,
                AccessibilityEvidenceWorkflowLimits.hardMaximumCount
            ),
            (.attachments, limits.maximumAttachments, AccessibilityEvidenceWorkflowLimits.hardMaximumCount),
            (.attachmentTokens, limits.maximumAttachmentTokens, AccessibilityEvidenceWorkflowLimits.hardMaximumCount),
            (
                .attachmentTokensPerObservation,
                limits.maximumAttachmentTokensPerObservation,
                AccessibilityEvidenceWorkflowLimits.hardMaximumCount
            ),
            (
                .totalItems,
                limits.maximumTotalItems,
                AccessibilityEvidenceWorkflowLimits.hardMaximumTotalItems
            ),
            (
                .stringUTF8Bytes,
                limits.maximumStringUTF8Bytes,
                AccessibilityEvidenceWorkflowLimits.hardMaximumStringUTF8Bytes
            ),
            (
                .totalStringUTF8Bytes,
                limits.maximumTotalStringUTF8Bytes,
                AccessibilityEvidenceWorkflowLimits.hardMaximumTotalStringUTF8Bytes
            ),
            (
                .attachmentBytes,
                limits.maximumAttachmentBytes,
                AccessibilityEvidenceWorkflowLimits.hardMaximumAttachmentBytes
            ),
            (.findings, limits.maximumFindings, AccessibilityEvidenceWorkflowLimits.hardMaximumCount),
            (
                .archiveBytes,
                limits.maximumArchiveBytes,
                AccessibilityEvidenceWorkflowLimits.hardMaximumArchiveBytes
            ),
            (
                .cancellationCheckInterval,
                limits.cancellationCheckInterval,
                AccessibilityEvidenceWorkflowLimits.hardMaximumCancellationCheckInterval
            )
        ]
        for (kind, value, maximum) in intLimits {
            guard value > 0, value <= maximum else {
                throw AccessibilityEvidenceWorkflowError.invalidLimit(kind)
            }
        }
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= AccessibilityEvidenceWorkflowLimits.hardMaximumWorkUnits
        else {
            throw AccessibilityEvidenceWorkflowError.invalidLimit(.workUnits)
        }
        guard limits.maximumTotalAttachmentBytes > 0,
            limits.maximumTotalAttachmentBytes
                <= AccessibilityEvidenceWorkflowLimits.hardMaximumTotalAttachmentBytes
        else {
            throw AccessibilityEvidenceWorkflowError.invalidLimit(.totalAttachmentBytes)
        }
    }

    private static func validateReference(
        _ reference: AccessibilityEvidenceRevisionReference,
        field: String,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        try validateID(reference.id, field: field + ".id", budget: budget)
    }

    private static func validateBuildBinding(
        _ binding: AccessibilityEvidenceBuildBinding,
        field: String,
        evidenceField: Bool
    ) throws {
        guard binding.artifactSHA256.count == SHA256.byteCount,
            binding.signingIdentitySHA256.count == SHA256.byteCount,
            binding.artifactSHA256.contains(where: { $0 != 0 }),
            binding.signingIdentitySHA256.contains(where: { $0 != 0 })
        else {
            if evidenceField {
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(field: field)
            }
            throw AccessibilityEvidenceWorkflowError.invalidInventory(field: field)
        }
    }

    private static func validateProvenance(
        _ provenance: AccessibilityEvidenceCaptureProvenance,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        guard provenance.capturedAtUnixMilliseconds > 0,
            (16...64).contains(provenance.runNonce.count)
        else {
            throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                field: "evidence.provenance"
            )
        }
        try budget.consume(UInt64(provenance.runNonce.count) + 1)
        try validateReference(
            provenance.collector,
            field: "evidence.provenance.collector",
            budget: budget
        )
        try validateReference(
            provenance.build,
            field: "evidence.provenance.build",
            budget: budget
        )
        try validateBuildBinding(
            provenance.buildBinding,
            field: "evidence.provenance.buildBinding",
            evidenceField: true
        )
    }

    private static func validateActionPostconditions(
        _ scenario: AccessibilityEvidenceInventoryScenario,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        var expectedActionIDs: Set<AccessibilityStableID> = []
        for element in scenario.expectedSnapshot.elements {
            try budget.consume()
            for action in element.actions {
                try budget.consume()
                expectedActionIDs.insert(action.id)
            }
        }
        var postconditionIDs: Set<AccessibilityStableID> = []
        for postcondition in scenario.actionPostconditions {
            try budget.consume(UInt64(postcondition.snapshotSHA256.count) + 1)
            try validateID(
                postcondition.actionID,
                field: "scenarios.actionPostconditions.actionID",
                budget: budget
            )
            guard postconditionIDs.insert(postcondition.actionID).inserted,
                postcondition.snapshotSHA256.count == SHA256.byteCount
            else {
                throw AccessibilityEvidenceWorkflowError.invalidInventory(
                    field: "scenarios.actionPostconditions"
                )
            }
        }
        guard postconditionIDs == expectedActionIDs else {
            throw AccessibilityEvidenceWorkflowError.invalidInventory(
                field: "scenarios.actionPostconditions"
            )
        }
    }

    private static func validateFocusOrder(
        _ focusOrder: [AccessibilityStableID],
        field: String,
        evidenceField: Bool,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        var seen: Set<AccessibilityStableID> = []
        for id in focusOrder {
            try budget.consume()
            try validateID(id, field: field, budget: budget)
            guard seen.insert(id).inserted else {
                if evidenceField {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(field: field)
                }
                throw AccessibilityEvidenceWorkflowError.invalidInventory(field: field)
            }
        }
    }

    private static func validateSnapshotEvidenceOrigins(
        _ snapshot: AccessibilityCommandControlSnapshot,
        field: String,
        allowDesignSpecification: Bool,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        let origins =
            snapshot.evidence.contrast.map(\.origin)
            + snapshot.evidence.differentiateWithoutColor.map(\.origin)
            + snapshot.evidence.localizationExpansion.map(\.origin)
        for origin in origins {
            try budget.consume()
            let valid =
                origin == .automatedMeasurement || origin == .manualMeasurement
                || (allowDesignSpecification && origin == .designSpecification)
            guard valid else {
                if allowDesignSpecification {
                    throw AccessibilityEvidenceWorkflowError.invalidInventory(
                        field: field + ".evidence.origin"
                    )
                }
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                    field: field + ".evidence.origin"
                )
            }
        }
    }

    private static func validateID(
        _ id: AccessibilityStableID,
        field: String,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        try budget.consume(UInt64(id.rawValue.utf8.count) + 1)
        guard accessibilityEvidenceIsValidIdentifier(id.rawValue) else {
            if field.hasPrefix("evidence") || field.hasPrefix("observations")
                || field.hasPrefix("attachments")
            {
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(field: field)
            }
            throw AccessibilityEvidenceWorkflowError.invalidInventory(field: field)
        }
    }

    private static func validateEnvironment(
        _ environment: AccessibilityEvidenceEnvironment,
        field: String
    ) throws {
        guard accessibilityEvidenceIsValidLocaleIdentifier(environment.localeIdentifier),
            (1_000...10_000).contains(environment.localizationExpansionThousandths)
        else {
            if field.hasPrefix("evidence") {
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(field: field)
            }
            throw AccessibilityEvidenceWorkflowError.invalidInventory(field: field)
        }
    }

    private static func consumeEnvironment(
        _ environment: AccessibilityEvidenceEnvironment,
        field: String,
        stringBudget: inout AccessibilityEvidenceStringBudget
    ) throws {
        try stringBudget.consume(
            environment.localeIdentifier,
            field: field + ".localeIdentifier"
        )
    }

    private static func validateRequirement(
        _ requirement: AccessibilityEvidenceRequirementKey,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        try validateID(
            requirement.scenarioID,
            field: "observations.requirement.scenarioID",
            budget: budget
        )
        if let subjectID = requirement.subjectID {
            try validateID(
                subjectID,
                field: "observations.requirement.subjectID",
                budget: budget
            )
        }
        if let discriminator = requirement.discriminator {
            try validateID(
                discriminator,
                field: "observations.requirement.discriminator",
                budget: budget
            )
        }
        let requiresSubject: Bool
        let requiresDiscriminator: Bool
        switch requirement.kind {
        case .semanticSnapshot, .focusOrder:
            requiresSubject = false
            requiresDiscriminator = false
        case .increasedContrast, .differentiateWithoutColor, .localizationExpansion:
            requiresSubject = true
            requiresDiscriminator = requirement.discriminator != nil
        case .darkMode:
            requiresSubject = true
            requiresDiscriminator = requirement.discriminator != nil
        case .fullKeyboardAccess, .voiceOverActivation:
            let isScenarioCondition =
                requirement.subjectID == nil
                && requirement.discriminator == nil
            let isSubjectApplicability =
                requirement.subjectID != nil
                && requirement.discriminator == nil
            let isActionObservation =
                requirement.subjectID != nil
                && requirement.discriminator != nil
            guard isScenarioCondition || isSubjectApplicability || isActionObservation else {
                throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                    field: "observations.requirement.shape"
                )
            }
            return
        case .semanticRole, .semanticLabel, .semanticHierarchy, .hiddenState, .focusability,
            .keyboardShortcuts, .enabledState, .checkedState, .selectedState, .value, .hint:
            requiresSubject = true
            requiresDiscriminator = false
        case .actionBehavior:
            requiresSubject = true
            requiresDiscriminator = true
        case .announcementBehavior:
            requiresSubject = requirement.subjectID != nil
            requiresDiscriminator = true
        }
        guard (requirement.subjectID != nil) == requiresSubject,
            (requirement.discriminator != nil) == requiresDiscriminator
        else {
            throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                field: "observations.requirement.shape"
            )
        }
    }

    private static func validateValue(
        _ value: AccessibilityEvidenceValue,
        for requirement: AccessibilityEvidenceRequirementKey,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        try budget.consume()
        let valid: Bool
        switch (requirement.kind, value) {
        case (.semanticSnapshot, .snapshot): valid = true
        case (.semanticRole, .semanticRole): valid = true
        case (.semanticLabel, .semanticLabel): valid = true
        case (.semanticHierarchy, .parentID): valid = true
        case (.hiddenState, .hidden): valid = true
        case (.focusability, .focusable): valid = true
        case (.keyboardShortcuts, .keyboardShortcuts): valid = true
        case (.increasedContrast, .condition),
            (.fullKeyboardAccess, .condition),
            (.voiceOverActivation, .condition),
            (.differentiateWithoutColor, .condition),
            (.darkMode, .condition),
            (.localizationExpansion, .condition):
            valid = true
        case (.fullKeyboardAccess, .action), (.voiceOverActivation, .action):
            valid = requirement.subjectID != nil && requirement.discriminator != nil
        case (.focusOrder, .focusOrder): valid = true
        case (.enabledState, .enabled): valid = true
        case (.checkedState, .checked): valid = true
        case (.selectedState, .selected): valid = true
        case (.value, .value): valid = true
        case (.hint, .hint): valid = true
        case (.actionBehavior, .action): valid = true
        case (.announcementBehavior, .announcement): valid = true
        default: valid = false
        }
        guard valid else {
            throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                field: "observations.value.kind"
            )
        }
        switch (requirement.kind, value) {
        case (.focusOrder, .focusOrder(let ids)):
            var seen: Set<AccessibilityStableID> = []
            for id in ids {
                try validateID(id, field: "observations.value.focusOrder", budget: budget)
                guard seen.insert(id).inserted else {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.value.focusOrder"
                    )
                }
            }
        case (.keyboardShortcuts, .keyboardShortcuts(let ids)):
            var seen: Set<AccessibilityStableID> = []
            for id in ids {
                try validateID(id, field: "observations.value.keyboardShortcuts", budget: budget)
                guard seen.insert(id).inserted else {
                    throw AccessibilityEvidenceWorkflowError.invalidEvidence(
                        field: "observations.value.keyboardShortcuts"
                    )
                }
            }
        default:
            break
        }
    }

    private static func consumeValue(
        _ value: AccessibilityEvidenceValue,
        field: String,
        stringBudget: inout AccessibilityEvidenceStringBudget
    ) throws {
        switch value {
        case .snapshot(let id):
            try stringBudget.consume(id.rawValue, field: field + ".snapshotID")
        case .semanticRole, .hidden, .focusable:
            break
        case .semanticLabel(let value):
            if let value { try stringBudget.consume(value, field: field + ".semanticLabel") }
        case .parentID(let id):
            if let id { try stringBudget.consume(id.rawValue, field: field + ".parentID") }
        case .keyboardShortcuts(let ids):
            for id in ids {
                try stringBudget.consume(id.rawValue, field: field + ".keyboardShortcuts")
            }
        case .condition, .enabled, .checked, .selected:
            break
        case .focusOrder(let ids):
            for id in ids {
                try stringBudget.consume(id.rawValue, field: field + ".focusOrder")
            }
        case .value(let value), .hint(let value):
            if let value { try stringBudget.consume(value, field: field + ".text") }
        case .action(let actionID, _, _):
            try stringBudget.consume(actionID.rawValue, field: field + ".actionID")
        case .announcement(let announcementID, _, _):
            try stringBudget.consume(
                announcementID.rawValue,
                field: field + ".announcementID"
            )
        }
    }

    private static func validateSnapshotStringBounds(
        _ snapshot: AccessibilityCommandControlSnapshot,
        field: String,
        stringBudget: inout AccessibilityEvidenceStringBudget,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        try stringBudget.consume(snapshot.id.rawValue, field: field + ".id")
        try stringBudget.consume(snapshot.rootElementID.rawValue, field: field + ".rootElementID")
        for element in snapshot.elements {
            try budget.consume()
            try stringBudget.consume(element.id.rawValue, field: field + ".element.id")
            if let parentID = element.parentID {
                try stringBudget.consume(parentID.rawValue, field: field + ".element.parentID")
            }
            for (name, value) in [
                ("label", element.label), ("value", element.value), ("hint", element.hint)
            ] {
                if let value {
                    try stringBudget.consume(value, field: field + ".element." + name)
                }
            }
            for action in element.actions {
                try stringBudget.consume(action.id.rawValue, field: field + ".action.id")
                if let label = action.label {
                    try stringBudget.consume(label, field: field + ".action.label")
                }
                for token in action.localizationExpansionEvidenceTokens {
                    try stringBudget.consume(
                        token.rawValue,
                        field: field + ".action.localizationToken"
                    )
                }
            }
            for shortcut in element.keyboardShortcuts {
                try stringBudget.consume(shortcut.id.rawValue, field: field + ".shortcut.id")
                try stringBudget.consume(shortcut.key, field: field + ".shortcut.key")
                try stringBudget.consume(
                    shortcut.actionID.rawValue,
                    field: field + ".shortcut.actionID"
                )
                if let title = shortcut.discoverabilityTitle {
                    try stringBudget.consume(title, field: field + ".shortcut.title")
                }
                for token in shortcut.localizationExpansionEvidenceTokens {
                    try stringBudget.consume(
                        token.rawValue,
                        field: field + ".shortcut.localizationToken"
                    )
                }
            }
            for token in element.contrastEvidenceTokens {
                try stringBudget.consume(token.rawValue, field: field + ".contrastToken")
            }
            for token in element.differentiateWithoutColorEvidenceTokens {
                try stringBudget.consume(token.rawValue, field: field + ".nonColorToken")
            }
            for token in element.localizationExpansionEvidenceTokens {
                try stringBudget.consume(token.rawValue, field: field + ".localizationToken")
            }
        }
        for id in snapshot.focusOrder {
            try stringBudget.consume(id.rawValue, field: field + ".focusOrder")
        }
        for announcement in snapshot.announcements {
            try stringBudget.consume(
                announcement.id.rawValue,
                field: field + ".announcement.id"
            )
            try stringBudget.consume(
                announcement.message,
                field: field + ".announcement.message"
            )
            if let relatedElementID = announcement.relatedElementID {
                try stringBudget.consume(
                    relatedElementID.rawValue,
                    field: field + ".announcement.relatedElementID"
                )
            }
            if let triggerActionID = announcement.triggerActionID {
                try stringBudget.consume(
                    triggerActionID.rawValue,
                    field: field + ".announcement.triggerActionID"
                )
            }
            for token in announcement.localizationExpansionEvidenceTokens {
                try stringBudget.consume(
                    token.rawValue,
                    field: field + ".announcement.localizationToken"
                )
            }
        }
        for item in snapshot.evidence.contrast {
            for (name, value) in [
                ("token", item.token.rawValue),
                ("subjectID", item.subjectID.rawValue),
                ("source", item.source)
            ] {
                try stringBudget.consume(value, field: field + ".contrast." + name)
            }
        }
        for item in snapshot.evidence.differentiateWithoutColor {
            for (name, value) in [
                ("token", item.token.rawValue),
                ("meaning", item.meaning),
                ("source", item.source)
            ] {
                try stringBudget.consume(value, field: field + ".nonColor." + name)
            }
        }
        for item in snapshot.evidence.localizationExpansion {
            for (name, value) in [
                ("token", item.token.rawValue),
                ("subjectID", item.subjectID.rawValue),
                ("locale", item.localeIdentifier),
                ("baseline", item.baselineText),
                ("expanded", item.expandedText),
                ("source", item.source)
            ] {
                try stringBudget.consume(value, field: field + ".localization." + name)
            }
        }
    }

    private static func requireCount(
        _ count: Int,
        limit: Int,
        kind: AccessibilityEvidenceLimit
    ) throws {
        guard count <= limit else {
            throw AccessibilityEvidenceWorkflowError.countLimitExceeded(
                kind: kind,
                maximum: limit
            )
        }
    }

    private static func add(_ value: Int, to total: Int) throws -> Int {
        let (result, overflow) = total.addingReportingOverflow(value)
        guard !overflow else {
            throw AccessibilityEvidenceWorkflowError.countLimitExceeded(
                kind: .totalItems,
                maximum: .max
            )
        }
        return result
    }

    private static func isBlank(
        _ value: String,
        budget: AccessibilityEvidenceWorkBudget
    ) throws -> Bool {
        for scalar in value.unicodeScalars {
            try budget.consume()
            if !(scalar.properties.isWhitespace || scalar.properties.generalCategory == .format
                || scalar.properties.isNoncharacterCodePoint || scalar.value <= 0x1F
                || (0x7F...0x9F).contains(scalar.value))
            {
                return false
            }
        }
        return true
    }
}

private enum AccessibilityEvidenceCanonicalEncoder {
    static func encodeInventory(
        _ inventory: AccessibilityProductionControlInventory,
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) throws -> Data {
        let writer = AccessibilityEvidenceWriter(limits: limits, budget: budget)
        try writer.appendString("MACMERGE-ACCESSIBILITY-INVENTORY")
        try appendReference(inventory.app, to: writer)
        try appendReference(inventory.build, to: writer)
        try appendBuildBinding(inventory.buildBinding, to: writer)
        try appendReference(inventory.reference, to: writer)
        try writer.appendStrings(
            inventory.requiredEnvironmentChecks.map(\.rawValue).sorted(
                by: { accessibilityEvidenceCompareUTF8($0, $1) < 0 }
            )
        )

        var controlRecords: [Data] = []
        controlRecords.reserveCapacity(inventory.controls.count)
        for control in inventory.controls {
            try budget.consume()
            let record = AccessibilityEvidenceWriter(limits: limits, budget: budget)
            try record.appendString(control.id.rawValue)
            try record.appendStrings(
                control.scenarioIDs.map(\.rawValue).sorted(
                    by: { accessibilityEvidenceCompareUTF8($0, $1) < 0 }
                )
            )
            controlRecords.append(record.data)
        }
        try writer.appendRecords(try accessibilityEvidenceSortedData(controlRecords, budget: budget))

        var scenarioRecords: [Data] = []
        scenarioRecords.reserveCapacity(inventory.scenarios.count)
        for scenario in inventory.scenarios {
            try budget.consume()
            let record = AccessibilityEvidenceWriter(limits: limits, budget: budget)
            try appendReference(scenario.reference, to: record)
            try appendEnvironment(scenario.environment, to: record)
            try record.appendStrings(
                scenario.requiredEnvironmentChecks.map(\.rawValue).sorted(
                    by: { accessibilityEvidenceCompareUTF8($0, $1) < 0 }
                )
            )
            let snapshot = try accessibilityEvidenceCanonicalSnapshotData(
                of: scenario.expectedSnapshot,
                limits: limits.semanticAuditLimits,
                budget: budget
            )
            try record.appendData(snapshot)
            var postconditionRecords: [Data] = []
            postconditionRecords.reserveCapacity(scenario.actionPostconditions.count)
            for postcondition in scenario.actionPostconditions {
                try budget.consume()
                let postconditionRecord = AccessibilityEvidenceWriter(limits: limits, budget: budget)
                try postconditionRecord.appendString(postcondition.actionID.rawValue)
                try postconditionRecord.appendData(Data(postcondition.snapshotSHA256))
                postconditionRecords.append(postconditionRecord.data)
            }
            try record.appendRecords(
                try accessibilityEvidenceSortedData(postconditionRecords, budget: budget)
            )
            scenarioRecords.append(record.data)
        }
        try writer.appendRecords(try accessibilityEvidenceSortedData(scenarioRecords, budget: budget))
        return writer.data
    }

    static func encodeEvidence(
        _ evidence: AccessibilityEvidenceBundle,
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) throws -> Data {
        let writer = AccessibilityEvidenceWriter(limits: limits, budget: budget)
        try writer.appendString("MACMERGE-ACCESSIBILITY-EVIDENCE")
        try appendReference(evidence.reference, to: writer)
        try appendReference(evidence.app, to: writer)
        try appendReference(evidence.build, to: writer)
        try appendBuildBinding(evidence.buildBinding, to: writer)
        try appendReference(evidence.inventory, to: writer)

        var scenarioRecords: [Data] = []
        scenarioRecords.reserveCapacity(evidence.scenarios.count)
        for scenario in evidence.scenarios {
            try budget.consume()
            let record = AccessibilityEvidenceWriter(limits: limits, budget: budget)
            try appendReference(scenario.scenario, to: record)
            try appendEnvironment(scenario.environment, to: record)
            try appendProvenance(scenario.provenance, to: record)
            let snapshot = try accessibilityEvidenceCanonicalSnapshotData(
                of: scenario.snapshot,
                limits: limits.semanticAuditLimits,
                budget: budget
            )
            try record.appendData(snapshot)
            var observationRecords: [Data] = []
            observationRecords.reserveCapacity(scenario.observations.count)
            for observation in scenario.observations {
                try budget.consume()
                observationRecords.append(
                    try encodeObservation(observation, limits: limits, budget: budget)
                )
            }
            try record.appendRecords(
                try accessibilityEvidenceSortedData(observationRecords, budget: budget)
            )
            scenarioRecords.append(record.data)
        }
        try writer.appendRecords(try accessibilityEvidenceSortedData(scenarioRecords, budget: budget))

        var attachmentRecords: [Data] = []
        attachmentRecords.reserveCapacity(evidence.attachments.count)
        for attachment in evidence.attachments {
            try budget.consume()
            let record = AccessibilityEvidenceWriter(limits: limits, budget: budget)
            try record.appendString(attachment.id.rawValue)
            try record.appendString(attachment.kind.rawValue)
            try record.appendString(attachment.mediaType)
            try record.appendUInt64(UInt64(attachment.byteCount))
            try record.appendData(Data(attachment.sha256))
            try record.appendString(attachment.source)
            attachmentRecords.append(record.data)
        }
        try writer.appendRecords(
            try accessibilityEvidenceSortedData(attachmentRecords, budget: budget)
        )
        return writer.data
    }

    static func encodeValue(
        _ value: AccessibilityEvidenceValue,
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) throws -> Data {
        let writer = AccessibilityEvidenceWriter(limits: limits, budget: budget)
        try appendValue(value, to: writer)
        return writer.data
    }

    static func encodeAttachmentPayload(
        _ observation: AccessibilityBehaviorObservation,
        scenario: AccessibilityScenarioEvidence,
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) throws -> Data {
        let writer = AccessibilityEvidenceWriter(limits: limits, budget: budget)
        try writer.appendString("MACMERGE-ACCESSIBILITY-OBSERVATION")
        try appendReference(scenario.scenario, to: writer)
        try appendEnvironment(scenario.environment, to: writer)
        try appendProvenance(scenario.provenance, to: writer)
        try writer.appendData(
            Data(
                accessibilityEvidenceCanonicalSnapshotSHA256(
                    scenario.snapshot,
                    limits: limits.semanticAuditLimits,
                    budget: budget
                )
            )
        )
        try writer.appendData(encodeObservation(observation, limits: limits, budget: budget))
        return writer.data
    }

    private static func encodeObservation(
        _ observation: AccessibilityBehaviorObservation,
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) throws -> Data {
        let writer = AccessibilityEvidenceWriter(limits: limits, budget: budget)
        try writer.appendString(observation.id.rawValue)
        try appendRequirement(observation.requirement, to: writer)
        try writer.appendString(observation.snapshotID.rawValue)
        try appendValue(observation.value, to: writer)
        try writer.appendString(observation.origin.rawValue)
        try writer.appendString(observation.source)
        try writer.appendStrings(
            observation.attachmentTokens.map(\.rawValue).sorted(
                by: { accessibilityEvidenceCompareUTF8($0, $1) < 0 }
            )
        )
        if let postcondition = observation.postconditionSnapshot {
            try writer.appendRaw([1])
            try writer.appendData(
                accessibilityEvidenceCanonicalSnapshotData(
                    of: postcondition,
                    limits: limits.semanticAuditLimits,
                    budget: budget
                )
            )
        } else {
            try writer.appendRaw([0])
        }
        return writer.data
    }

    private static func appendReference(
        _ reference: AccessibilityEvidenceRevisionReference,
        to writer: AccessibilityEvidenceWriter
    ) throws {
        try writer.appendString(reference.id.rawValue)
        try writer.appendUInt64(reference.revision.rawValue)
    }

    private static func appendEnvironment(
        _ environment: AccessibilityEvidenceEnvironment,
        to writer: AccessibilityEvidenceWriter
    ) throws {
        try writer.appendBool(environment.fullKeyboardAccessEnabled)
        try writer.appendBool(environment.voiceOverEnabled)
        try writer.appendBool(environment.increasedContrastEnabled)
        try writer.appendBool(environment.differentiateWithoutColorEnabled)
        try writer.appendString(environment.appearance.rawValue)
        try writer.appendString(environment.localeIdentifier)
        try writer.appendUInt64(UInt64(environment.localizationExpansionThousandths))
    }

    private static func appendBuildBinding(
        _ binding: AccessibilityEvidenceBuildBinding,
        to writer: AccessibilityEvidenceWriter
    ) throws {
        try writer.appendData(Data(binding.artifactSHA256))
        try writer.appendData(Data(binding.signingIdentitySHA256))
    }

    private static func appendProvenance(
        _ provenance: AccessibilityEvidenceCaptureProvenance,
        to writer: AccessibilityEvidenceWriter
    ) throws {
        try writer.appendUInt64(provenance.capturedAtUnixMilliseconds)
        try writer.appendData(Data(provenance.runNonce))
        try appendReference(provenance.collector, to: writer)
        try appendReference(provenance.build, to: writer)
        try appendBuildBinding(provenance.buildBinding, to: writer)
    }

    private static func appendRequirement(
        _ requirement: AccessibilityEvidenceRequirementKey,
        to writer: AccessibilityEvidenceWriter
    ) throws {
        try writer.appendString(requirement.scenarioID.rawValue)
        try writer.appendOptionalString(requirement.subjectID?.rawValue)
        try writer.appendString(requirement.kind.rawValue)
        try writer.appendOptionalString(requirement.discriminator?.rawValue)
    }

    private static func appendValue(
        _ value: AccessibilityEvidenceValue,
        to writer: AccessibilityEvidenceWriter
    ) throws {
        switch value {
        case .snapshot(let id):
            try writer.appendString("snapshot")
            try writer.appendString(id.rawValue)
        case .semanticRole(let role):
            try writer.appendString("semanticRole")
            try writer.appendString(role.rawValue)
        case .semanticLabel(let label):
            try writer.appendString("semanticLabel")
            try writer.appendOptionalString(label)
        case .parentID(let id):
            try writer.appendString("parentID")
            try writer.appendOptionalString(id?.rawValue)
        case .hidden(let hidden):
            try writer.appendString("hidden")
            try writer.appendBool(hidden)
        case .focusable(let focusable):
            try writer.appendString("focusable")
            try writer.appendBool(focusable)
        case .keyboardShortcuts(let ids):
            try writer.appendString("keyboardShortcuts")
            try writer.appendStrings(ids.map(\.rawValue).sorted())
        case .condition(let outcome):
            try writer.appendString("condition")
            try writer.appendString(outcome.rawValue)
        case .focusOrder(let ids):
            try writer.appendString("focusOrder")
            try writer.appendStrings(ids.map(\.rawValue))
        case .enabled(let enabled):
            try writer.appendString("enabled")
            try writer.appendBool(enabled)
        case .checked(let state):
            try writer.appendString("checked")
            try writer.appendString(state.rawValue)
        case .selected(let state):
            try writer.appendString("selected")
            try writer.appendString(state.rawValue)
        case .value(let value):
            try writer.appendString("value")
            try writer.appendOptionalString(value)
        case .hint(let hint):
            try writer.appendString("hint")
            try writer.appendOptionalString(hint)
        case .action(let actionID, let kind, let outcome):
            try writer.appendString("action")
            try writer.appendString(actionID.rawValue)
            try writer.appendString(kind.rawValue)
            try writer.appendString(outcome.rawValue)
        case .announcement(let announcementID, let kind, let outcome):
            try writer.appendString("announcement")
            try writer.appendString(announcementID.rawValue)
            try writer.appendString(kind.rawValue)
            try writer.appendString(outcome.rawValue)
        }
    }
}

private enum AccessibilityEvidenceArchiveValidation {
    static func validate(
        _ archive: Data,
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) throws {
        guard archive.count <= limits.maximumArchiveBytes else {
            throw AccessibilityEvidenceWorkflowError.archiveTooLarge(
                maximumBytes: limits.maximumArchiveBytes
            )
        }
        let reader = AccessibilityEvidenceReader(data: archive, budget: budget)
        guard try reader.readData(count: 8) == Data("MMAXEWF2".utf8) else {
            throw AccessibilityEvidenceWorkflowError.invalidArchive
        }
        let version = Int(try reader.readUInt16())
        guard version == AccessibilityEvidenceWorkflow.archiveFormatVersion else {
            throw AccessibilityEvidenceWorkflowError.unsupportedArchiveVersion(version)
        }
        guard try reader.readUInt16() == 0 else {
            throw AccessibilityEvidenceWorkflowError.invalidArchive
        }
        let payloadLength = try reader.readUInt64()
        guard payloadLength <= UInt64(Int.max), Int(payloadLength) == reader.remainingCount - 64 else {
            throw AccessibilityEvidenceWorkflowError.invalidArchive
        }
        _ = try reader.readData(count: 32)
        let expectedDigest = try reader.readData(count: 32)
        let payload = try reader.readData(count: Int(payloadLength))
        guard reader.isAtEnd else {
            throw AccessibilityEvidenceWorkflowError.invalidArchive
        }
        let actualDigest = Data(try accessibilityEvidenceSHA256(payload, budget: budget))
        guard try accessibilityEvidenceDataEqual(expectedDigest, actualDigest, budget: budget) else {
            throw AccessibilityEvidenceWorkflowError.archiveChecksumMismatch
        }
    }
}

private final class AccessibilityEvidenceWriter {
    private(set) var data = Data()
    private let limits: AccessibilityEvidenceWorkflowLimits
    private let budget: AccessibilityEvidenceWorkBudget

    init(
        limits: AccessibilityEvidenceWorkflowLimits,
        budget: AccessibilityEvidenceWorkBudget
    ) {
        self.limits = limits
        self.budget = budget
        data.reserveCapacity(min(limits.maximumArchiveBytes, 4_096))
    }

    func appendBool(_ value: Bool) throws {
        try appendRaw([value ? 1 : 0])
    }

    func appendOptionalString(_ value: String?) throws {
        guard let value else {
            try appendRaw([0])
            return
        }
        try appendRaw([1])
        try appendString(value)
    }

    func appendOptionalData(_ value: Data?) throws {
        guard let value else {
            try appendRaw([0])
            return
        }
        try appendRaw([1])
        try appendData(value)
    }

    func appendString(_ value: String) throws {
        let normalized = value.precomposedStringWithCanonicalMapping
        try appendCount(normalized.utf8.count)
        try appendRaw(normalized.utf8)
    }

    func appendStrings(_ values: [String]) throws {
        try appendCount(values.count)
        for value in values {
            try appendString(value)
        }
    }

    func appendData(_ value: Data) throws {
        try appendCount(value.count)
        try appendRaw(value)
    }

    func appendRecords(_ records: [Data]) throws {
        try appendCount(records.count)
        for record in records {
            try appendData(record)
        }
    }

    func appendCount(_ value: Int) throws {
        guard value >= 0 else { throw AccessibilityEvidenceWorkflowError.invalidArchive }
        try appendUInt64(UInt64(value))
    }

    func appendUInt16(_ value: UInt16) throws {
        try appendRaw([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8)
        ])
    }

    func appendUInt64(_ value: UInt64) throws {
        try appendRaw((0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64($0 * 8)) })
    }

    func appendRaw<Bytes: Collection>(_ bytes: Bytes) throws where Bytes.Element == UInt8 {
        var start = bytes.startIndex
        while start != bytes.endIndex {
            let end =
                bytes.index(start, offsetBy: 4_096, limitedBy: bytes.endIndex)
                ?? bytes.endIndex
            let chunk = bytes[start..<end]
            guard chunk.count <= limits.maximumArchiveBytes - data.count else {
                throw AccessibilityEvidenceWorkflowError.archiveTooLarge(
                    maximumBytes: limits.maximumArchiveBytes
                )
            }
            try budget.consume(UInt64(chunk.count) + 1)
            data.append(contentsOf: chunk)
            start = end
        }
    }
}

private final class AccessibilityEvidenceReader {
    private let data: Data
    private let budget: AccessibilityEvidenceWorkBudget
    private var offset = 0

    init(data: Data, budget: AccessibilityEvidenceWorkBudget) {
        self.data = Data(data)
        self.budget = budget
    }

    var remainingCount: Int { data.count - offset }
    var isAtEnd: Bool { offset == data.count }

    func readUInt16() throws -> UInt16 {
        let bytes = try readData(count: 2)
        return UInt16(bytes[bytes.startIndex])
            | UInt16(bytes[bytes.index(after: bytes.startIndex)]) << 8
    }

    func readUInt64() throws -> UInt64 {
        let bytes = try readData(count: 8)
        var result: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            result |= UInt64(byte) << UInt64(index * 8)
        }
        return result
    }

    func readData(count: Int) throws -> Data {
        guard count >= 0, count <= remainingCount else {
            throw AccessibilityEvidenceWorkflowError.invalidArchive
        }
        try budget.consume(UInt64(count) + 1)
        let end = offset + count
        let result = data.subdata(in: offset..<end)
        offset = end
        return result
    }
}

private final class AccessibilityEvidenceWorkBudget {
    private let maximum: UInt64
    private let interval: UInt64
    private let cancellationCheck: AccessibilityEvidenceWorkflow.CancellationCheck
    private var consumed: UInt64 = 0
    private var sinceCancellationCheck: UInt64 = 0

    init(
        limits: AccessibilityEvidenceWorkflowLimits,
        cancellationCheck: @escaping AccessibilityEvidenceWorkflow.CancellationCheck
    ) throws {
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= AccessibilityEvidenceWorkflowLimits.hardMaximumWorkUnits
        else {
            throw AccessibilityEvidenceWorkflowError.invalidLimit(.workUnits)
        }
        guard limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval
                <= AccessibilityEvidenceWorkflowLimits.hardMaximumCancellationCheckInterval
        else {
            throw AccessibilityEvidenceWorkflowError.invalidLimit(.cancellationCheckInterval)
        }
        maximum = limits.maximumWorkUnits
        interval = UInt64(limits.cancellationCheckInterval)
        self.cancellationCheck = cancellationCheck
    }

    func consume(_ amount: UInt64 = 1) throws {
        let (next, overflow) = consumed.addingReportingOverflow(amount)
        guard !overflow, next <= maximum else {
            throw AccessibilityEvidenceWorkflowError.workLimitExceeded(maximum: maximum)
        }
        consumed = next
        let (nextInterval, intervalOverflow) = sinceCancellationCheck.addingReportingOverflow(amount)
        sinceCancellationCheck = intervalOverflow ? interval : nextInterval
        if sinceCancellationCheck >= interval {
            sinceCancellationCheck = 0
            try checkCancellation()
        }
    }

    func checkCancellation() throws {
        if cancellationCheck() { throw AccessibilityEvidenceWorkflowError.cancelled }
    }

    func finish() throws {
        try checkCancellation()
    }
}

private struct AccessibilityEvidenceStringBudget {
    let limits: AccessibilityEvidenceWorkflowLimits
    let work: AccessibilityEvidenceWorkBudget
    private var total = 0

    init(
        limits: AccessibilityEvidenceWorkflowLimits,
        work: AccessibilityEvidenceWorkBudget
    ) {
        self.limits = limits
        self.work = work
    }

    mutating func consume(_ value: String, field: String) throws {
        let count = value.utf8.count
        guard count <= limits.maximumStringUTF8Bytes else {
            throw AccessibilityEvidenceWorkflowError.stringTooLarge(
                field: field,
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        guard count <= limits.maximumTotalStringUTF8Bytes - total else {
            throw AccessibilityEvidenceWorkflowError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        try work.consume(UInt64(count) + 1)
        total += count
    }
}

private func accessibilityEvidenceRequirementKind(
    _ check: AccessibilityEvidenceEnvironmentCheck
) -> AccessibilityEvidenceRequirementKind {
    switch check {
    case .fullKeyboardAccess: .fullKeyboardAccess
    case .voiceOverActivation: .voiceOverActivation
    case .increasedContrast: .increasedContrast
    case .differentiateWithoutColor: .differentiateWithoutColor
    case .darkMode: .darkMode
    case .localizationExpansion: .localizationExpansion
    }
}

private func accessibilityEvidenceEnvironmentSatisfies(
    _ environment: AccessibilityEvidenceEnvironment,
    check: AccessibilityEvidenceEnvironmentCheck
) -> Bool {
    switch check {
    case .fullKeyboardAccess: environment.fullKeyboardAccessEnabled
    case .voiceOverActivation: environment.voiceOverEnabled
    case .increasedContrast: environment.increasedContrastEnabled
    case .differentiateWithoutColor: environment.differentiateWithoutColorEnabled
    case .darkMode: environment.appearance == .dark
    case .localizationExpansion: environment.localizationExpansionThousandths > 1_000
    }
}

private func accessibilityEvidenceIsSemanticControl(
    _ element: AccessibilitySemanticElement
) -> Bool {
    switch element.role {
    case .button, .toggle, .checkBox, .radioButton, .link, .textField, .searchField,
        .comboBox, .menu, .menuItem, .tab, .list, .listItem, .table, .row, .cell,
        .tree, .treeItem, .slider, .stepper, .command, .customControl:
        true
    default:
        element.isKeyboardFocusable || !element.actions.isEmpty || !element.keyboardShortcuts.isEmpty
    }
}

private func accessibilityEvidenceActionSucceeded(_ value: AccessibilityEvidenceValue) -> Bool {
    guard case .action(_, _, let outcome) = value else { return false }
    return outcome == .performed
}

private func accessibilityEvidenceCanonicalSnapshotSHA256(
    _ snapshot: AccessibilityCommandControlSnapshot,
    limits: AccessibilityAuditLimits,
    budget: AccessibilityEvidenceWorkBudget
) throws -> [UInt8] {
    try accessibilityEvidenceSHA256(
        accessibilityEvidenceCanonicalSnapshotData(
            of: snapshot,
            limits: limits,
            budget: budget
        ),
        budget: budget
    )
}

private func accessibilityEvidenceSnapshotWithoutAuditEvidence(
    _ snapshot: AccessibilityCommandControlSnapshot
) -> AccessibilityCommandControlSnapshot {
    AccessibilityCommandControlSnapshot(
        id: snapshot.id,
        rootElementID: snapshot.rootElementID,
        elements: snapshot.elements,
        focusOrder: snapshot.focusOrder,
        announcements: snapshot.announcements
    )
}

private func accessibilityEvidenceValuesEqual(
    _ left: AccessibilityEvidenceValue?,
    _ right: AccessibilityEvidenceValue,
    limits: AccessibilityEvidenceWorkflowLimits,
    budget: AccessibilityEvidenceWorkBudget
) throws -> Bool {
    guard let left else { return false }
    let leftData = try AccessibilityEvidenceCanonicalEncoder.encodeValue(
        left,
        limits: limits,
        budget: budget
    )
    let rightData = try AccessibilityEvidenceCanonicalEncoder.encodeValue(
        right,
        limits: limits,
        budget: budget
    )
    return try accessibilityEvidenceDataEqual(leftData, rightData, budget: budget)
}

private func accessibilityEvidenceObservationMatchesScopedEvidence(
    _ observation: AccessibilityBehaviorObservation,
    snapshot: AccessibilityCommandControlSnapshot,
    environment: AccessibilityEvidenceEnvironment,
    budget: AccessibilityEvidenceWorkBudget
) throws -> Bool {
    guard let subjectID = observation.requirement.subjectID else { return true }
    let token = observation.requirement.discriminator?.rawValue
    switch observation.requirement.kind {
    case .increasedContrast, .darkMode:
        guard let token else {
            let expected: AccessibilityEvidenceValue =
                observation.requirement.kind == .darkMode
                ? .condition(.notSatisfied) : .condition(.notApplicable)
            return observation.value == expected
                && snapshot.elements.first(where: { $0.id == subjectID })?
                    .contrastEvidenceTokens.isEmpty == true
        }
        for evidence in snapshot.evidence.contrast {
            try budget.consume()
            if evidence.subjectID == subjectID,
                evidence.token.rawValue == token
            {
                return evidence.measuredRatioThousandths >= evidence.requiredRatioThousandths
                    && (evidence.origin == .automatedMeasurement
                        || evidence.origin == .manualMeasurement)
            }
        }
        return false
    case .differentiateWithoutColor:
        guard let token else {
            return observation.value == .condition(.notApplicable)
                && snapshot.elements.first(where: { $0.id == subjectID })?
                    .differentiateWithoutColorEvidenceTokens.isEmpty == true
        }
        let subject = snapshot.elements.first(where: { $0.id == subjectID })
        guard
            subject?.differentiateWithoutColorEvidenceTokens.contains(where: {
                $0.rawValue == token
            }) == true
        else { return false }
        for evidence in snapshot.evidence.differentiateWithoutColor {
            try budget.consume()
            if evidence.token.rawValue == token {
                return !evidence.nonColorCues.isEmpty
                    && (evidence.origin == .automatedMeasurement
                        || evidence.origin == .manualMeasurement)
            }
        }
        return false
    case .localizationExpansion:
        guard let token else {
            return observation.value == .condition(.notSatisfied)
                && snapshot.elements.first(where: { $0.id == subjectID })?
                    .localizationExpansionEvidenceTokens.isEmpty == true
        }
        for evidence in snapshot.evidence.localizationExpansion {
            try budget.consume()
            if evidence.token.rawValue == token, evidence.subjectID == subjectID,
                evidence.localeIdentifier == environment.localeIdentifier
            {
                let baselineCount = max(1, evidence.baselineText.utf8.count)
                let expandedThousandths = evidence.expandedText.utf8.count * 1_000 / baselineCount
                return evidence.outcome != .truncates && evidence.outcome != .unknown
                    && expandedThousandths >= environment.localizationExpansionThousandths
                    && (evidence.origin == .automatedMeasurement
                        || evidence.origin == .manualMeasurement)
            }
        }
        return false
    case .fullKeyboardAccess, .voiceOverActivation:
        if observation.requirement.discriminator == nil {
            guard let element = snapshot.elements.first(where: { $0.id == subjectID }) else {
                return false
            }
            if observation.requirement.kind == .fullKeyboardAccess, !element.actions.isEmpty {
                return observation.value == .condition(.notSatisfied)
                    && element.keyboardShortcuts.isEmpty
            }
            if observation.requirement.kind == .voiceOverActivation, !element.actions.isEmpty {
                return observation.value == .condition(.satisfied)
            }
            return observation.value == .condition(.notApplicable) && element.actions.isEmpty
        }
        return true
    default:
        return true
    }
}

private func accessibilityEvidenceSeverity(
    _ severity: AccessibilityAuditSeverity
) -> AccessibilityEvidenceFindingSeverity {
    switch severity {
    case .advisory: .advisory
    case .warning: .warning
    case .error: .error
    }
}

private func accessibilityEvidenceSemanticElementEqual(
    _ left: AccessibilitySemanticElement,
    _ right: AccessibilitySemanticElement,
    budget: AccessibilityEvidenceWorkBudget
) throws -> Bool {
    try budget.consume()
    return try left.id == right.id
        && left.parentID == right.parentID
        && left.role == right.role
        && accessibilityEvidenceCanonicalOptionalString(left.label)
            == accessibilityEvidenceCanonicalOptionalString(right.label)
        && accessibilityEvidenceCanonicalOptionalString(left.value)
            == accessibilityEvidenceCanonicalOptionalString(right.value)
        && accessibilityEvidenceCanonicalOptionalString(left.hint)
            == accessibilityEvidenceCanonicalOptionalString(right.hint)
        && left.isEnabled == right.isEnabled
        && left.checkedState == right.checkedState
        && left.selectedState == right.selectedState
        && left.isHiddenFromAssistiveTechnology == right.isHiddenFromAssistiveTechnology
        && left.isKeyboardFocusable == right.isKeyboardFocusable
        && accessibilityEvidenceUnorderedEqualByCanonicalData(
            left.actions,
            right.actions,
            budget: budget,
            encode: accessibilityEvidenceCanonicalActionData
        )
        && accessibilityEvidenceUnorderedEqualByCanonicalData(
            left.keyboardShortcuts,
            right.keyboardShortcuts,
            budget: budget,
            encode: accessibilityEvidenceCanonicalShortcutData
        )
        && left.requiresContrastEvidence == right.requiresContrastEvidence
        && accessibilityEvidenceUnorderedHashableEqual(
            left.contrastEvidenceTokens,
            right.contrastEvidenceTokens,
            budget: budget
        )
        && left.usesColorToConveyMeaning == right.usesColorToConveyMeaning
        && accessibilityEvidenceUnorderedHashableEqual(
            left.differentiateWithoutColorEvidenceTokens,
            right.differentiateWithoutColorEvidenceTokens,
            budget: budget
        )
        && left.requiresLocalizationExpansionEvidence
            == right.requiresLocalizationExpansionEvidence
        && accessibilityEvidenceUnorderedHashableEqual(
            left.localizationExpansionEvidenceTokens,
            right.localizationExpansionEvidenceTokens,
            budget: budget
        )
}

private func accessibilityEvidenceAnnouncementsEqual(
    _ left: [AccessibilityAnnouncement],
    _ right: [AccessibilityAnnouncement],
    budget: AccessibilityEvidenceWorkBudget
) throws -> Bool {
    try accessibilityEvidenceUnorderedEqualByCanonicalData(
        left,
        right,
        budget: budget,
        encode: accessibilityEvidenceCanonicalAnnouncementData
    )
}

private func accessibilityEvidenceUnorderedHashableEqual<Value: Hashable>(
    _ left: [Value],
    _ right: [Value],
    budget: AccessibilityEvidenceWorkBudget
) throws -> Bool {
    try budget.consume(UInt64(left.count + right.count) + 1)
    guard left.count == right.count else { return false }
    var counts: [Value: Int] = [:]
    counts.reserveCapacity(left.count)
    for value in left {
        try budget.consume()
        counts[value, default: 0] += 1
    }
    for value in right {
        try budget.consume()
        guard let count = counts[value] else { return false }
        if count == 1 {
            counts.removeValue(forKey: value)
        } else {
            counts[value] = count - 1
        }
    }
    return counts.isEmpty
}

private func accessibilityEvidenceUnorderedEqualByCanonicalData<Value>(
    _ left: [Value],
    _ right: [Value],
    budget: AccessibilityEvidenceWorkBudget,
    encode: (Value, AccessibilityEvidenceWorkBudget) throws -> Data
) throws -> Bool {
    try budget.consume()
    guard left.count == right.count else { return false }
    var counts: [Data: Int] = [:]
    counts.reserveCapacity(left.count)
    for value in left {
        try budget.consume()
        counts[try encode(value, budget), default: 0] += 1
    }
    for value in right {
        try budget.consume()
        let data = try encode(value, budget)
        guard let count = counts[data] else { return false }
        if count == 1 {
            counts.removeValue(forKey: data)
        } else {
            counts[data] = count - 1
        }
    }
    return counts.isEmpty
}

private func accessibilityEvidenceCanonicalAnnouncementData(
    _ announcement: AccessibilityAnnouncement,
    budget: AccessibilityEvidenceWorkBudget
) throws -> Data {
    let limits = AccessibilityEvidenceWorkflowLimits.default
    let writer = AccessibilityEvidenceWriter(limits: limits, budget: budget)
    try writer.appendString(announcement.id.rawValue)
    try writer.appendString(announcement.kind.rawValue)
    try writer.appendString(announcement.message.precomposedStringWithCanonicalMapping)
    try writer.appendOptionalString(announcement.relatedElementID?.rawValue)
    try writer.appendOptionalString(announcement.triggerActionID?.rawValue)
    try writer.appendStrings(
        announcement.localizationExpansionEvidenceTokens.map(\.rawValue).sorted()
    )
    return writer.data
}

private func accessibilityEvidenceCanonicalActionData(
    _ action: AccessibilitySemanticAction,
    budget: AccessibilityEvidenceWorkBudget
) throws -> Data {
    let writer = AccessibilityEvidenceWriter(limits: .default, budget: budget)
    try writer.appendString(action.id.rawValue)
    try writer.appendString(action.kind.rawValue)
    try writer.appendOptionalString(
        action.label?.precomposedStringWithCanonicalMapping
    )
    try writer.appendStrings(action.localizationExpansionEvidenceTokens.map(\.rawValue).sorted())
    return writer.data
}

private func accessibilityEvidenceCanonicalShortcutData(
    _ shortcut: AccessibilityKeyboardShortcut,
    budget: AccessibilityEvidenceWorkBudget
) throws -> Data {
    let writer = AccessibilityEvidenceWriter(limits: .default, budget: budget)
    try writer.appendString(shortcut.id.rawValue)
    try writer.appendString(shortcut.canonicalChord)
    try writer.appendString(shortcut.actionID.rawValue)
    try writer.appendOptionalString(
        shortcut.discoverabilityTitle?.precomposedStringWithCanonicalMapping
    )
    try writer.appendStrings(shortcut.localizationExpansionEvidenceTokens.map(\.rawValue).sorted())
    return writer.data
}

private func accessibilityEvidenceCanonicalOptionalString(_ value: String?) -> String? {
    value?.precomposedStringWithCanonicalMapping
}

private func accessibilityEvidenceFindingMessage(
    _ code: AccessibilityEvidenceFindingCode
) -> String {
    switch code {
    case .duplicateScenarioEvidence:
        "Scenario has duplicate caller-supplied evidence records."
    case .missingScenarioEvidence:
        "Required production scenario has no caller-supplied evidence."
    case .unexpectedScenarioEvidence:
        "Evidence contains a scenario absent from the production inventory."
    case .environmentMismatch:
        "Observed environment differs from the exact required scenario environment."
    case .semanticSnapshotMismatch:
        "Observed semantic snapshot identity or root differs from inventory."
    case .semanticElementMissing:
        "Inventory control is missing from the observed semantic snapshot."
    case .unexpectedSemanticElement:
        "Observed semantic element is absent from the production inventory snapshot."
    case .semanticElementMismatch:
        "Observed role, label, value, hint, state, focusability, or actions differ from inventory."
    case .focusOrderMismatch:
        "Observed focus order differs from the exact inventory order."
    case .announcementMismatch:
        "Observed announcement declarations differ from inventory."
    case .snapshotAuditIssue:
        "Observed semantic snapshot produced an accessibility-audit finding."
    case .duplicateAttachmentToken:
        "Attachment token is duplicated."
    case .duplicateObservationToken:
        "Observation token is duplicated."
    case .duplicateEvidence:
        "Completeness matrix cell has duplicate observations."
    case .assertionOnlyEvidence:
        "Completeness matrix cell contains an assertion, not measured evidence."
    case .emptyAttachmentEvidence:
        "Measured observation has no verified attachment."
    case .invalidActionPostcondition:
        "Successful action lacks a verified canonical post-action snapshot."
    case .missingEvidence:
        "Completeness matrix cell has no observation."
    case .unexpectedEvidence:
        "Observation does not correspond to an inventory completeness requirement."
    case .evidenceValueMismatch:
        "Observed behavior differs from the inventory expectation."
    case .attachmentReferenceMissing:
        "Observation references a missing or duplicated attachment token."
    case .orphanAttachment:
        "Attachment is not referenced by any observation."
    }
}

private func accessibilityEvidenceFrame(_ value: String) -> String {
    String(value.utf8.count) + ":" + value
}

private func accessibilityEvidenceIsValidIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty else { return false }
    return value.unicodeScalars.allSatisfy {
        !$0.properties.isWhitespace && $0.value > 0x1F
            && !(0x7F...0x9F).contains($0.value)
            && $0.properties.generalCategory != .format
            && !$0.properties.isNoncharacterCodePoint
    }
}

private func accessibilityEvidenceIsValidLocaleIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 255, !value.contains("_") else { return false }
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else { return false }
    return parts.allSatisfy { part in
        (1...8).contains(part.utf8.count)
            && part.utf8.allSatisfy {
                (0x30...0x39).contains($0) || (0x41...0x5A).contains($0)
                    || (0x61...0x7A).contains($0)
            }
    }
}

private func accessibilityEvidenceCompareComponents(
    _ left: [String],
    _ right: [String]
) -> Int {
    for (leftValue, rightValue) in zip(left, right) {
        let order = accessibilityEvidenceCompareUTF8(leftValue, rightValue)
        if order != 0 { return order }
    }
    if left.count == right.count { return 0 }
    return left.count < right.count ? -1 : 1
}

private func accessibilityEvidenceCompareUTF8(_ left: String, _ right: String) -> Int {
    left.utf8.lexicographicallyPrecedes(right.utf8)
        ? -1
        : right.utf8.lexicographicallyPrecedes(left.utf8) ? 1 : 0
}

private func accessibilityEvidenceCompareBytes(_ left: Data, _ right: Data) -> Int {
    let sharedCount = min(left.count, right.count)
    for index in 0..<sharedCount {
        let leftByte = left[left.startIndex + index]
        let rightByte = right[right.startIndex + index]
        if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
    }
    if left.count == right.count { return 0 }
    return left.count < right.count ? -1 : 1
}

private func accessibilityEvidenceSortedData(
    _ values: [Data],
    budget: AccessibilityEvidenceWorkBudget
) throws -> [Data] {
    try values.sorted { left, right in
        try budget.consume(UInt64(min(left.count, right.count)) + 1)
        return accessibilityEvidenceCompareBytes(left, right) < 0
    }
}

private func accessibilityEvidenceSorted<Value: Comparable>(
    _ values: [Value],
    budget: AccessibilityEvidenceWorkBudget
) throws -> [Value] {
    try values.sorted { left, right in
        try budget.consume()
        return left < right
    }
}

private func accessibilityEvidenceSortedByID<Value>(
    _ values: [Value],
    budget: AccessibilityEvidenceWorkBudget,
    id: KeyPath<Value, AccessibilityStableID>
) throws -> [Value] {
    try values.sorted { left, right in
        try budget.consume()
        return left[keyPath: id] < right[keyPath: id]
    }
}

private func accessibilityEvidenceDictionary<Value, Key: Hashable>(
    _ values: [Value],
    budget: AccessibilityEvidenceWorkBudget,
    key: KeyPath<Value, Key>,
    rejectingDuplicates: Bool = false
) throws -> [Key: Value] {
    try budget.consume(UInt64(values.count) + 1)
    var result: [Key: Value] = [:]
    result.reserveCapacity(values.count)
    for value in values {
        try budget.consume()
        let keyValue = value[keyPath: key]
        if rejectingDuplicates, result[keyValue] != nil {
            throw AccessibilityEvidenceWorkflowError.invalidInventory(
                field: "requirements.duplicateKey"
            )
        }
        result[keyValue] = value
    }
    return result
}

private func accessibilityEvidenceAddCount(
    _ value: Int,
    to total: Int,
    maximum: Int
) throws -> Int {
    let (result, overflow) = total.addingReportingOverflow(value)
    guard !overflow, result <= maximum else {
        throw AccessibilityEvidenceWorkflowError.countLimitExceeded(
            kind: .requiredRequirements,
            maximum: maximum
        )
    }
    return result
}

private func accessibilityEvidenceGroupedDictionary<Value, Key: Hashable>(
    _ values: [Value],
    budget: AccessibilityEvidenceWorkBudget,
    key: KeyPath<Value, Key>
) throws -> [Key: [Value]] {
    try budget.consume(UInt64(values.count) + 1)
    var result: [Key: [Value]] = [:]
    result.reserveCapacity(values.count)
    for value in values {
        try budget.consume()
        result[value[keyPath: key], default: []].append(value)
    }
    return result
}

private func accessibilityEvidenceSHA256(
    _ data: Data,
    budget: AccessibilityEvidenceWorkBudget
) throws -> [UInt8] {
    var hasher = SHA256()
    var offset = 0
    while offset < data.count {
        let count = min(4_096, data.count - offset)
        try budget.consume(UInt64(count) + 1)
        hasher.update(data: data.subdata(in: offset..<(offset + count)))
        offset += count
    }
    return Array(hasher.finalize())
}

private func accessibilityEvidenceDataEqual(
    _ left: Data,
    _ right: Data,
    budget: AccessibilityEvidenceWorkBudget
) throws -> Bool {
    let left = Data(left)
    let right = Data(right)
    guard left.count == right.count else { return false }
    var offset = 0
    while offset < left.count {
        let count = min(4_096, left.count - offset)
        try budget.consume(UInt64(count) + 1)
        guard left[offset..<(offset + count)].elementsEqual(right[offset..<(offset + count)]) else {
            return false
        }
        offset += count
    }
    return true
}

private func accessibilityEvidenceCanonicalSnapshotData(
    of snapshot: AccessibilityCommandControlSnapshot,
    limits: AccessibilityAuditLimits,
    budget: AccessibilityEvidenceWorkBudget
) throws -> Data {
    var elements: [AccessibilitySemanticElement] = []
    elements.reserveCapacity(snapshot.elements.count)
    for element in snapshot.elements {
        try budget.consume()
        var actions: [AccessibilitySemanticAction] = []
        actions.reserveCapacity(element.actions.count)
        for action in element.actions {
            try budget.consume()
            actions.append(
                AccessibilitySemanticAction(
                    id: action.id,
                    kind: action.kind,
                    label: action.label?.precomposedStringWithCanonicalMapping,
                    localizationExpansionEvidenceTokens:
                        action.localizationExpansionEvidenceTokens
                )
            )
        }
        var shortcuts: [AccessibilityKeyboardShortcut] = []
        shortcuts.reserveCapacity(element.keyboardShortcuts.count)
        for shortcut in element.keyboardShortcuts {
            try budget.consume()
            shortcuts.append(
                AccessibilityKeyboardShortcut(
                    id: shortcut.id,
                    key: shortcut.key,
                    modifiers: shortcut.modifiers,
                    actionID: shortcut.actionID,
                    discoverabilityTitle: shortcut.discoverabilityTitle?
                        .precomposedStringWithCanonicalMapping,
                    localizationExpansionEvidenceTokens:
                        shortcut.localizationExpansionEvidenceTokens
                )
            )
        }
        elements.append(
            AccessibilitySemanticElement(
                id: element.id,
                parentID: element.parentID,
                role: element.role,
                label: element.label?.precomposedStringWithCanonicalMapping,
                value: element.value?.precomposedStringWithCanonicalMapping,
                hint: element.hint?.precomposedStringWithCanonicalMapping,
                isEnabled: element.isEnabled,
                checkedState: element.checkedState,
                selectedState: element.selectedState,
                isHiddenFromAssistiveTechnology: element.isHiddenFromAssistiveTechnology,
                isKeyboardFocusable: element.isKeyboardFocusable,
                actions: actions,
                keyboardShortcuts: shortcuts,
                requiresContrastEvidence: element.requiresContrastEvidence,
                contrastEvidenceTokens: element.contrastEvidenceTokens,
                usesColorToConveyMeaning: element.usesColorToConveyMeaning,
                differentiateWithoutColorEvidenceTokens:
                    element.differentiateWithoutColorEvidenceTokens,
                requiresLocalizationExpansionEvidence:
                    element.requiresLocalizationExpansionEvidence,
                localizationExpansionEvidenceTokens:
                    element.localizationExpansionEvidenceTokens
            )
        )
    }
    var announcements: [AccessibilityAnnouncement] = []
    announcements.reserveCapacity(snapshot.announcements.count)
    for announcement in snapshot.announcements {
        try budget.consume()
        announcements.append(
            AccessibilityAnnouncement(
                id: announcement.id,
                kind: announcement.kind,
                message: announcement.message.precomposedStringWithCanonicalMapping,
                relatedElementID: announcement.relatedElementID,
                triggerActionID: announcement.triggerActionID,
                localizationExpansionEvidenceTokens:
                    announcement.localizationExpansionEvidenceTokens
            )
        )
    }
    var contrast: [AccessibilityContrastEvidence] = []
    contrast.reserveCapacity(snapshot.evidence.contrast.count)
    for item in snapshot.evidence.contrast {
        try budget.consume()
        contrast.append(
            AccessibilityContrastEvidence(
                token: item.token,
                subjectID: item.subjectID,
                surface: item.surface,
                measuredRatioThousandths: item.measuredRatioThousandths,
                requiredRatioThousandths: item.requiredRatioThousandths,
                origin: item.origin,
                source: item.source.precomposedStringWithCanonicalMapping
            )
        )
    }
    var differentiateWithoutColor: [AccessibilityDifferentiateWithoutColorEvidence] = []
    differentiateWithoutColor.reserveCapacity(snapshot.evidence.differentiateWithoutColor.count)
    for item in snapshot.evidence.differentiateWithoutColor {
        try budget.consume()
        differentiateWithoutColor.append(
            AccessibilityDifferentiateWithoutColorEvidence(
                token: item.token,
                meaning: item.meaning.precomposedStringWithCanonicalMapping,
                nonColorCues: item.nonColorCues,
                origin: item.origin,
                source: item.source.precomposedStringWithCanonicalMapping
            )
        )
    }
    var localizationExpansion: [AccessibilityLocalizationExpansionEvidence] = []
    localizationExpansion.reserveCapacity(snapshot.evidence.localizationExpansion.count)
    for item in snapshot.evidence.localizationExpansion {
        try budget.consume()
        localizationExpansion.append(
            AccessibilityLocalizationExpansionEvidence(
                token: item.token,
                subjectID: item.subjectID,
                field: item.field,
                localeIdentifier: item.localeIdentifier,
                baselineText: item.baselineText.precomposedStringWithCanonicalMapping,
                expandedText: item.expandedText.precomposedStringWithCanonicalMapping,
                outcome: item.outcome,
                origin: item.origin,
                source: item.source.precomposedStringWithCanonicalMapping
            )
        )
    }
    let normalized = AccessibilityCommandControlSnapshot(
        id: snapshot.id,
        rootElementID: snapshot.rootElementID,
        elements: elements,
        focusOrder: snapshot.focusOrder,
        announcements: announcements,
        evidence: AccessibilityAuditEvidence(
            contrast: contrast,
            differentiateWithoutColor: differentiateWithoutColor,
            localizationExpansion: localizationExpansion
        )
    )
    try accessibilityEvidenceDebitNestedAudit(normalized, budget: budget)
    try budget.checkCancellation()
    let data = try AccessibilityAudit.exactSnapshotData(of: normalized, limits: limits)
    try budget.consume(UInt64(data.count) + 1)
    try budget.checkCancellation()
    return data
}

private func accessibilityEvidenceDebitNestedAudit(
    _ snapshot: AccessibilityCommandControlSnapshot,
    budget: AccessibilityEvidenceWorkBudget
) throws {
    var units =
        snapshot.elements.count + snapshot.focusOrder.count
        + snapshot.announcements.count + 1
    for element in snapshot.elements {
        let (withActions, actionsOverflow) = units.addingReportingOverflow(element.actions.count)
        let (withShortcuts, shortcutsOverflow) = withActions.addingReportingOverflow(
            element.keyboardShortcuts.count
        )
        guard !actionsOverflow, !shortcutsOverflow else {
            throw AccessibilityEvidenceWorkflowError.workLimitExceeded(maximum: .max)
        }
        units = withShortcuts
    }
    try budget.consume(UInt64(units))
}
