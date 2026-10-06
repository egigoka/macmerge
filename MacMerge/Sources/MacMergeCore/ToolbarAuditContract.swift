import Foundation

public typealias ToolbarAuditCommand = ToolbarConfiguration.Command
public typealias ToolbarAuditItem = ToolbarConfiguration.Item

public struct ToolbarAuditRevision: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// Caller-owned stable identity. Labels, positions, and platform objects never establish identity.
public struct ToolbarAuditStableID: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        toolbarAuditCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

public struct ToolbarAuditCommandGroup: Hashable, Sendable {
    public let commands: [ToolbarAuditCommand]
    public let hasTrailingSeparator: Bool

    public init(commands: [ToolbarAuditCommand], hasTrailingSeparator: Bool) {
        self.commands = commands
        self.hasTrailingSeparator = hasTrailingSeparator
    }

    public var items: [ToolbarAuditItem] {
        commands.map(ToolbarAuditItem.command)
            + (hasTrailingSeparator ? [.separator] : [])
    }
}

/// Exact command and separator sequence expected from the WinMerge `IDR_MAINFRAME` resource.
public struct ToolbarAuditManifest: Hashable, Sendable {
    public static let canonicalRevision = ToolbarAuditRevision(rawValue: 1)
    public static let canonical = ToolbarAuditManifest(
        revision: canonicalRevision,
        items: ToolbarConfiguration.winMergeDefaultItems
    )

    public let revision: ToolbarAuditRevision
    public let items: [ToolbarAuditItem]

    public init(
        revision: ToolbarAuditRevision = canonicalRevision,
        items: [ToolbarAuditItem] = ToolbarConfiguration.winMergeDefaultItems
    ) {
        self.revision = revision
        self.items = items
    }

    public var commands: [ToolbarAuditCommand] { items.compactMap(\.command) }

    public var groups: [ToolbarAuditCommandGroup] {
        var result: [ToolbarAuditCommandGroup] = []
        var commands: [ToolbarAuditCommand] = []
        for item in items {
            switch item {
            case .command(let command):
                commands.append(command)
            case .separator:
                result.append(
                    ToolbarAuditCommandGroup(
                        commands: commands,
                        hasTrailingSeparator: true
                    )
                )
                commands.removeAll(keepingCapacity: true)
            }
        }
        if !commands.isEmpty {
            result.append(
                ToolbarAuditCommandGroup(
                    commands: commands,
                    hasTrailingSeparator: false
                )
            )
        }
        return result
    }
}

public struct ToolbarAuditSecondaryAction: Identifiable, Hashable, Sendable {
    public let id: ToolbarAuditStableID
    public let accessibility: ToolbarAuditAXMetadata

    public init(id: ToolbarAuditStableID, accessibility: ToolbarAuditAXMetadata) {
        self.id = id
        self.accessibility = accessibility
    }
}

public enum ToolbarAuditSecondaryBehavior: Hashable, Sendable {
    case none
    /// Stable action order must match menu presentation order.
    case menu(actions: [ToolbarAuditSecondaryAction])

    public var actionIDs: [ToolbarAuditStableID] {
        guard case .menu(let actions) = self else { return [] }
        return actions.map(\.id)
    }
}

public struct ToolbarAuditControlBehavior: Hashable, Sendable {
    public let primaryActionID: ToolbarAuditStableID
    public let secondary: ToolbarAuditSecondaryBehavior

    public init(
        primaryActionID: ToolbarAuditStableID,
        secondary: ToolbarAuditSecondaryBehavior = .none
    ) {
        self.primaryActionID = primaryActionID
        self.secondary = secondary
    }

    public var allActionIDs: [ToolbarAuditStableID] {
        [primaryActionID] + secondary.actionIDs
    }
}

public struct ToolbarAuditShortcut: Hashable, Sendable {
    public let key: String
    public let modifiers: Set<AccessibilityKeyboardModifier>
    public let display: String

    public init(
        key: String,
        modifiers: Set<AccessibilityKeyboardModifier> = [],
        display: String
    ) {
        self.key = key.precomposedStringWithCanonicalMapping
        self.modifiers = modifiers
        self.display = display.precomposedStringWithCanonicalMapping
    }

    public var canonicalChord: String {
        let modifiers = AccessibilityKeyboardModifier.allCases
            .filter(modifiers.contains)
            .map(\.rawValue)
        let key = key.lowercased().precomposedStringWithCanonicalMapping
        return modifiers.joined(separator: "+") + ":" + String(key.utf8.count) + ":" + key
    }
}

/// Platform-neutral semantic accessibility fields. `isEnabled` is nil in static requirements and
/// concrete in scenario evidence; lifecycle expectations remain authoritative for enabled state.
public struct ToolbarAuditAXMetadata: Hashable, Sendable {
    public let identifier: ToolbarAuditStableID
    public let role: AccessibilitySemanticRole
    public let label: String
    public let value: String?
    public let hint: String
    public let isEnabled: Bool?
    public let checkedState: AccessibilityCheckedState
    public let selectedState: AccessibilitySelectedState
    public let isKeyboardFocusable: Bool
    public let actions: Set<AccessibilitySemanticActionKind>

    public init(
        identifier: ToolbarAuditStableID,
        role: AccessibilitySemanticRole = .button,
        label: String,
        value: String? = nil,
        hint: String,
        isEnabled: Bool? = nil,
        checkedState: AccessibilityCheckedState = .notApplicable,
        selectedState: AccessibilitySelectedState = .notApplicable,
        isKeyboardFocusable: Bool = true,
        actions: Set<AccessibilitySemanticActionKind> = [.activate]
    ) {
        self.identifier = identifier
        self.role = role
        self.label = label.precomposedStringWithCanonicalMapping
        self.value = value?.precomposedStringWithCanonicalMapping
        self.hint = hint.precomposedStringWithCanonicalMapping
        self.isEnabled = isEnabled
        self.checkedState = checkedState
        self.selectedState = selectedState
        self.isKeyboardFocusable = isKeyboardFocusable
        self.actions = actions
    }
}

public struct ToolbarAuditControlRequirement: Identifiable, Hashable, Sendable {
    public let id: ToolbarAuditStableID
    public let command: ToolbarAuditCommand
    public let behavior: ToolbarAuditControlBehavior
    public let tooltip: String
    public let shortcut: ToolbarAuditShortcut?
    public let accessibility: ToolbarAuditAXMetadata

    public init(
        id: ToolbarAuditStableID,
        command: ToolbarAuditCommand,
        behavior: ToolbarAuditControlBehavior,
        tooltip: String,
        shortcut: ToolbarAuditShortcut? = nil,
        accessibility: ToolbarAuditAXMetadata
    ) {
        self.id = id
        self.command = command
        self.behavior = behavior
        self.tooltip = tooltip.precomposedStringWithCanonicalMapping
        self.shortcut = shortcut
        self.accessibility = accessibility
    }
}

public enum ToolbarAuditLifecycleScenario: String, CaseIterable, Hashable, Sendable {
    case empty
    case loading
    case equal
    case different
    case selected
    case dirty
    case readOnly
    case failed
    case untitled
    case externallyChanged
}

public enum ToolbarAuditAvailability: Hashable, Sendable {
    case enabled
    case disabled(reason: ToolbarAuditStableID)

    public var isEnabled: Bool {
        self == .enabled
    }
}

public struct ToolbarAuditLifecycleExpectation: Hashable, Sendable {
    public let scenario: ToolbarAuditLifecycleScenario
    public let command: ToolbarAuditCommand
    public let actionID: ToolbarAuditStableID
    public let availability: ToolbarAuditAvailability

    public init(
        scenario: ToolbarAuditLifecycleScenario,
        command: ToolbarAuditCommand,
        actionID: ToolbarAuditStableID,
        availability: ToolbarAuditAvailability
    ) {
        self.scenario = scenario
        self.command = command
        self.actionID = actionID
        self.availability = availability
    }
}

public enum ToolbarAuditInvocationKind: String, CaseIterable, Hashable, Sendable {
    case primaryClick
    case menuArrowClick
    case menuItemSelection
    case keyboardActivation
    case voiceOverActivation
    case disabledActivation
}

public enum ToolbarAuditInteractionOutcome: Hashable, Sendable {
    case invoked(actionID: ToolbarAuditStableID)
    case menuPresented(actionIDs: [ToolbarAuditStableID])
    case blocked
    case noOp
    case failed(code: ToolbarAuditStableID)
}

public struct ToolbarAuditInteractionExpectation: Hashable, Sendable {
    public let scenario: ToolbarAuditLifecycleScenario
    public let controlID: ToolbarAuditStableID
    public let actionID: ToolbarAuditStableID
    public let invocation: ToolbarAuditInvocationKind
    public let outcome: ToolbarAuditInteractionOutcome

    public init(
        scenario: ToolbarAuditLifecycleScenario,
        controlID: ToolbarAuditStableID,
        actionID: ToolbarAuditStableID,
        invocation: ToolbarAuditInvocationKind,
        outcome: ToolbarAuditInteractionOutcome
    ) {
        self.scenario = scenario
        self.controlID = controlID
        self.actionID = actionID
        self.invocation = invocation
        self.outcome = outcome
    }
}

public enum ToolbarAuditScreenshotContext: String, CaseIterable, Hashable, Sendable {
    case freshWindow
    case loadedComparison
}

public struct ToolbarAuditScreenshotExpectation: Hashable, Sendable {
    public let context: ToolbarAuditScreenshotContext
    public let requiresAccessibilitySidecar: Bool

    public init(
        context: ToolbarAuditScreenshotContext,
        requiresAccessibilitySidecar: Bool = true
    ) {
        self.context = context
        self.requiresAccessibilitySidecar = requiresAccessibilitySidecar
    }
}

/// Complete, UI-independent requirement set. Localized text remains explicit caller input.
public struct ToolbarAuditContract: Hashable, Sendable {
    public typealias Command = ToolbarAuditCommand
    public typealias Item = ToolbarAuditItem
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let requiredLifecycleScenarios = ToolbarAuditLifecycleScenario.allCases
    public static let requiredInvocationKinds = ToolbarAuditInvocationKind.allCases
    public static let requiredScreenshotExpectations = ToolbarAuditScreenshotContext.allCases.map {
        ToolbarAuditScreenshotExpectation(context: $0)
    }

    public let revision: ToolbarAuditRevision
    public let manifest: ToolbarAuditManifest
    public let controls: [ToolbarAuditControlRequirement]
    public let lifecycleExpectations: [ToolbarAuditLifecycleExpectation]
    public let interactionExpectations: [ToolbarAuditInteractionExpectation]
    public let screenshotExpectations: [ToolbarAuditScreenshotExpectation]

    public init(
        revision: ToolbarAuditRevision,
        manifest: ToolbarAuditManifest = .canonical,
        controls: [ToolbarAuditControlRequirement],
        lifecycleExpectations: [ToolbarAuditLifecycleExpectation],
        interactionExpectations: [ToolbarAuditInteractionExpectation],
        screenshotExpectations: [ToolbarAuditScreenshotExpectation] =
            ToolbarAuditContract.requiredScreenshotExpectations
    ) {
        self.revision = revision
        self.manifest = manifest
        self.controls = controls
        self.lifecycleExpectations = lifecycleExpectations
        self.interactionExpectations = interactionExpectations
        self.screenshotExpectations = screenshotExpectations
    }

    public func audit(
        evidence: ToolbarAuditEvidence,
        limits: ToolbarAuditLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ToolbarAuditReport {
        try ToolbarAudit.audit(
            contract: self,
            evidence: evidence,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }
}

public struct ToolbarAuditControlObservation: Identifiable, Hashable, Sendable {
    public let id: ToolbarAuditStableID
    public let command: ToolbarAuditCommand
    public let behavior: ToolbarAuditControlBehavior
    public let tooltip: String?
    public let shortcut: ToolbarAuditShortcut?
    public let accessibility: ToolbarAuditAXMetadata
    public let availability: ToolbarAuditAvailability

    public init(
        id: ToolbarAuditStableID,
        command: ToolbarAuditCommand,
        behavior: ToolbarAuditControlBehavior,
        tooltip: String?,
        shortcut: ToolbarAuditShortcut? = nil,
        accessibility: ToolbarAuditAXMetadata,
        availability: ToolbarAuditAvailability
    ) {
        self.id = id
        self.command = command
        self.behavior = behavior
        self.tooltip = tooltip?.precomposedStringWithCanonicalMapping
        self.shortcut = shortcut
        self.accessibility = accessibility
        self.availability = availability
    }
}

/// One exact AX/presentation observation for one lifecycle matrix row.
public struct ToolbarAuditSurfaceEvidence: Hashable, Sendable {
    public let scenario: ToolbarAuditLifecycleScenario
    public let manifestRevision: ToolbarAuditRevision
    public let items: [ToolbarAuditItem]
    public let controls: [ToolbarAuditControlObservation]
    public let source: String

    public init(
        scenario: ToolbarAuditLifecycleScenario,
        manifestRevision: ToolbarAuditRevision,
        items: [ToolbarAuditItem],
        controls: [ToolbarAuditControlObservation],
        source: String
    ) {
        self.scenario = scenario
        self.manifestRevision = manifestRevision
        self.items = items
        self.controls = controls
        self.source = source.precomposedStringWithCanonicalMapping
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.scenario == right.scenario
            && left.manifestRevision == right.manifestRevision
            && left.items == right.items
            && toolbarAuditUnorderedEqual(left.controls, right.controls)
            && left.source == right.source
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(scenario)
        hasher.combine(manifestRevision)
        hasher.combine(items)
        toolbarAuditHashUnordered(controls, into: &hasher)
        hasher.combine(source)
    }
}

public struct ToolbarAuditInteractionEvidence: Hashable, Sendable {
    public let scenario: ToolbarAuditLifecycleScenario
    public let controlID: ToolbarAuditStableID
    public let actionID: ToolbarAuditStableID
    public let invocation: ToolbarAuditInvocationKind
    public let outcome: ToolbarAuditInteractionOutcome
    public let source: String

    public init(
        scenario: ToolbarAuditLifecycleScenario,
        controlID: ToolbarAuditStableID,
        actionID: ToolbarAuditStableID,
        invocation: ToolbarAuditInvocationKind,
        outcome: ToolbarAuditInteractionOutcome,
        source: String
    ) {
        self.scenario = scenario
        self.controlID = controlID
        self.actionID = actionID
        self.invocation = invocation
        self.outcome = outcome
        self.source = source.precomposedStringWithCanonicalMapping
    }
}

public struct ToolbarAuditArtifactDigest: Hashable, Sendable {
    public enum Algorithm: String, CaseIterable, Hashable, Sendable {
        case sha256
    }

    public let algorithm: Algorithm
    public let lowercaseHex: String

    public init(algorithm: Algorithm = .sha256, lowercaseHex: String) {
        self.algorithm = algorithm
        self.lowercaseHex = lowercaseHex.precomposedStringWithCanonicalMapping
    }
}

public struct ToolbarAuditScreenshotEvidence: Hashable, Sendable {
    public let context: ToolbarAuditScreenshotContext
    public let manifestRevision: ToolbarAuditRevision
    public let items: [ToolbarAuditItem]
    public let screenshotDigest: ToolbarAuditArtifactDigest
    public let accessibilitySidecarDigest: ToolbarAuditArtifactDigest?
    public let source: String

    public init(
        context: ToolbarAuditScreenshotContext,
        manifestRevision: ToolbarAuditRevision,
        items: [ToolbarAuditItem],
        screenshotDigest: ToolbarAuditArtifactDigest,
        accessibilitySidecarDigest: ToolbarAuditArtifactDigest? = nil,
        source: String
    ) {
        self.context = context
        self.manifestRevision = manifestRevision
        self.items = items
        self.screenshotDigest = screenshotDigest
        self.accessibilitySidecarDigest = accessibilitySidecarDigest
        self.source = source.precomposedStringWithCanonicalMapping
    }
}

/// Caller-supplied observations only. Archive decoding verifies framing, not claimed UI behavior.
public struct ToolbarAuditEvidence: Hashable, Sendable {
    public let contractRevision: ToolbarAuditRevision
    public let surfaces: [ToolbarAuditSurfaceEvidence]
    public let interactions: [ToolbarAuditInteractionEvidence]
    public let screenshots: [ToolbarAuditScreenshotEvidence]

    public init(
        contractRevision: ToolbarAuditRevision,
        surfaces: [ToolbarAuditSurfaceEvidence],
        interactions: [ToolbarAuditInteractionEvidence],
        screenshots: [ToolbarAuditScreenshotEvidence]
    ) {
        self.contractRevision = contractRevision
        self.surfaces = surfaces
        self.interactions = interactions
        self.screenshots = screenshots
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.contractRevision == right.contractRevision
            && toolbarAuditUnorderedEqual(left.surfaces, right.surfaces)
            && toolbarAuditUnorderedEqual(left.interactions, right.interactions)
            && toolbarAuditUnorderedEqual(left.screenshots, right.screenshots)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(contractRevision)
        toolbarAuditHashUnordered(surfaces, into: &hasher)
        toolbarAuditHashUnordered(interactions, into: &hasher)
        toolbarAuditHashUnordered(screenshots, into: &hasher)
    }

    public func encodedData(
        limits: ToolbarAuditLimits = .default,
        cancellationCheck: @escaping ToolbarAuditContract.CancellationCheck = {
            try Task.checkCancellation()
        }
    ) throws -> Data {
        try ToolbarAuditEvidenceArchive.encode(
            self,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    public static func decode(
        from data: Data,
        limits: ToolbarAuditLimits = .default,
        cancellationCheck: @escaping ToolbarAuditContract.CancellationCheck = {
            try Task.checkCancellation()
        }
    ) throws -> Self {
        try ToolbarAuditEvidenceArchive.decode(
            data,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }
}

public enum ToolbarAuditFindingSeverity: String, CaseIterable, Comparable, Hashable, Sendable {
    case advisory
    case warning
    case error

    public static func < (left: Self, right: Self) -> Bool {
        toolbarAuditEnumRank(left) < toolbarAuditEnumRank(right)
    }
}

public enum ToolbarAuditFindingCode: String, CaseIterable, Hashable, Sendable {
    case contractManifestMismatch
    case controlRequirementMissing
    case unexpectedControlRequirement
    case lifecycleRequirementMissing
    case interactionRequirementMissing
    case screenshotRequirementMissing
    case lifecycleEvidenceMissing
    case commandOrderMismatch
    case commandGroupingMismatch
    case controlEvidenceMissing
    case unexpectedControlEvidence
    case controlIdentityMismatch
    case primaryBehaviorMismatch
    case secondaryBehaviorMismatch
    case secondaryAccessibilityMismatch
    case secondaryAvailabilityMismatch
    case tooltipMissing
    case tooltipMismatch
    case shortcutMissing
    case shortcutMismatch
    case duplicateShortcut
    case accessibilityIdentifierMismatch
    case duplicateAccessibilityIdentifier
    case accessibilityRoleMismatch
    case accessibilityLabelMissing
    case accessibilityLabelMismatch
    case duplicateAccessibilityLabel
    case accessibilityValueMismatch
    case accessibilityHintMissing
    case accessibilityHintMismatch
    case accessibilityCheckedStateMismatch
    case accessibilitySelectedStateMismatch
    case accessibilityFocusMismatch
    case accessibilityActionsMismatch
    case availabilityMismatch
    case accessibilityEnabledStateMismatch
    case interactionEvidenceMissing
    case interactionOutcomeMismatch
    case disabledActivationSucceeded
    case unexpectedInteractionEvidence
    case screenshotEvidenceMissing
    case screenshotOrderMismatch
    case screenshotGroupingMismatch
    case screenshotAccessibilitySidecarMissing
    case unexpectedScreenshotEvidence
}

public struct ToolbarAuditFinding: Identifiable, Hashable, Sendable {
    public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue.precomposedStringWithCanonicalMapping
        }

        public static func < (left: Self, right: Self) -> Bool {
            toolbarAuditCompareUTF8(left.rawValue, right.rawValue) < 0
        }
    }

    public let id: ID
    public let severity: ToolbarAuditFindingSeverity
    public let code: ToolbarAuditFindingCode
    public let command: ToolbarAuditCommand?
    public let scenario: ToolbarAuditLifecycleScenario?
    public let subjectID: ToolbarAuditStableID?
    public let message: String

    fileprivate init(
        severity: ToolbarAuditFindingSeverity,
        code: ToolbarAuditFindingCode,
        command: ToolbarAuditCommand? = nil,
        scenario: ToolbarAuditLifecycleScenario? = nil,
        subjectID: ToolbarAuditStableID? = nil,
        discriminator: String = "",
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.command = command
        self.scenario = scenario
        self.subjectID = subjectID
        self.message = message
        id = ID(
            rawValue: [
                code.rawValue,
                command?.rawValue ?? "",
                scenario?.rawValue ?? "",
                subjectID?.rawValue ?? "",
                discriminator
            ].map(toolbarAuditLengthPrefixed).joined()
        )
    }
}

public struct ToolbarAuditReport: Hashable, Sendable {
    public static let scopeStatement =
        "Static checks of caller-supplied toolbar requirements and evidence; not runtime UI or VoiceOver conformance."

    public let formatVersion: Int
    public let contractRevision: ToolbarAuditRevision
    public let manifestRevision: ToolbarAuditRevision
    public let findings: [ToolbarAuditFinding]

    public var highestSeverity: ToolbarAuditFindingSeverity? { findings.first?.severity }
    public var containsErrors: Bool { findings.contains { $0.severity == .error } }
    public var passed: Bool { findings.isEmpty }

    fileprivate init(
        formatVersion: Int,
        contractRevision: ToolbarAuditRevision,
        manifestRevision: ToolbarAuditRevision,
        findings: [ToolbarAuditFinding]
    ) {
        self.formatVersion = formatVersion
        self.contractRevision = contractRevision
        self.manifestRevision = manifestRevision
        self.findings = findings
    }
}

public struct ToolbarAuditLimits: Hashable, Sendable {
    public static let hardMaximumManifestItems = ToolbarOverflowPlan.Limits.hardMaximumItemCount
    public static let hardMaximumControls = ToolbarConfiguration.Command.allCases.count
    public static let hardMaximumSecondaryActions = 1_024
    public static let hardMaximumLifecycleExpectations = 4_096
    public static let hardMaximumInteractionRecords = 65_536
    public static let hardMaximumScreenshots = 64
    public static let hardMaximumStringUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumWorkUnits = 512 * 1_024 * 1_024
    public static let hardMaximumFindings = 100_000
    public static let hardMaximumArchiveBytes = 32 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 4_096
    public static let `default` = ToolbarAuditLimits()

    public let maximumManifestItems: Int
    public let maximumControls: Int
    public let maximumSecondaryActions: Int
    public let maximumLifecycleExpectations: Int
    public let maximumInteractionRecords: Int
    public let maximumScreenshots: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumWorkUnits: Int
    public let maximumFindings: Int
    public let maximumArchiveBytes: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumManifestItems: Int = hardMaximumManifestItems,
        maximumControls: Int = hardMaximumControls,
        maximumSecondaryActions: Int = 256,
        maximumLifecycleExpectations: Int = 1_024,
        maximumInteractionRecords: Int = 4_096,
        maximumScreenshots: Int = 16,
        maximumStringUTF8Bytes: Int = 16 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumWorkUnits: Int = hardMaximumWorkUnits,
        maximumFindings: Int = 16_384,
        maximumArchiveBytes: Int = 8 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) {
        self.maximumManifestItems = maximumManifestItems
        self.maximumControls = maximumControls
        self.maximumSecondaryActions = maximumSecondaryActions
        self.maximumLifecycleExpectations = maximumLifecycleExpectations
        self.maximumInteractionRecords = maximumInteractionRecords
        self.maximumScreenshots = maximumScreenshots
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumFindings = maximumFindings
        self.maximumArchiveBytes = maximumArchiveBytes
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ToolbarAuditError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimit(name: String, value: Int, maximum: Int)
    case countLimitExceeded(kind: String, maximum: Int)
    case stringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximum: Int)
    case findingLimitExceeded(maximum: Int)
    case invalidContract(field: String)
    case invalidEvidence(field: String)
    case staleEvidence(expected: ToolbarAuditRevision, actual: ToolbarAuditRevision)
    case staleManifest(expected: ToolbarAuditRevision, actual: ToolbarAuditRevision)
    case cancelled
    case archiveTooLarge(maximumBytes: Int)
    case invalidArchive
    case unsupportedArchiveVersion(Int)
    case archiveChecksumMismatch
    case nonCanonicalArchive

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value, let maximum):
            "Toolbar-audit limit \(name) is invalid (\(value)); supported maximum is \(maximum)."
        case .countLimitExceeded(let kind, let maximum):
            "Toolbar audit exceeds the \(maximum)-\(kind) limit."
        case .stringTooLarge(let field, let maximumUTF8Bytes):
            "Toolbar-audit field \(field) exceeds \(maximumUTF8Bytes) UTF-8 bytes."
        case .totalStringsTooLarge(let maximumUTF8Bytes):
            "Toolbar-audit strings exceed \(maximumUTF8Bytes) UTF-8 bytes."
        case .workLimitExceeded(let maximum):
            "Toolbar audit exceeds the \(maximum)-unit work limit."
        case .findingLimitExceeded(let maximum):
            "Toolbar audit exceeds the \(maximum)-finding limit."
        case .invalidContract(let field):
            "Toolbar audit contract is invalid at \(field)."
        case .invalidEvidence(let field):
            "Toolbar audit evidence is invalid at \(field)."
        case .staleEvidence(let expected, let actual):
            "Toolbar evidence revision \(actual.rawValue) does not match contract revision \(expected.rawValue)."
        case .staleManifest(let expected, let actual):
            "Toolbar manifest evidence revision \(actual.rawValue) does not match \(expected.rawValue)."
        case .cancelled:
            "Toolbar audit was cancelled."
        case .archiveTooLarge(let maximumBytes):
            "Toolbar evidence archive exceeds \(maximumBytes) bytes."
        case .invalidArchive:
            "Toolbar evidence archive has invalid framing or field data."
        case .unsupportedArchiveVersion(let version):
            "Unsupported toolbar evidence archive version: \(version)."
        case .archiveChecksumMismatch:
            "Toolbar evidence archive checksum does not match its payload."
        case .nonCanonicalArchive:
            "Toolbar evidence archive is valid but not in canonical wire form."
        }
    }
}

/// Deterministic contract/evidence comparison. No AppKit, AX runtime, or screenshot calls occur.
public enum ToolbarAudit: Sendable {
    public static let reportFormatVersion = 1

    public static func audit(
        contract: ToolbarAuditContract,
        evidence: ToolbarAuditEvidence,
        limits: ToolbarAuditLimits = .default,
        cancellationCheck: @escaping ToolbarAuditContract.CancellationCheck = {
            try Task.checkCancellation()
        }
    ) throws -> ToolbarAuditReport {
        try ToolbarAuditValidation.validate(limits)
        var budget = ToolbarAuditWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try budget.checkCancellation()
        do {
            try ToolbarAuditValidation.validate(contract, limits: limits, budget: &budget)
        } catch ToolbarAuditError.invalidEvidence(let field) {
            throw ToolbarAuditError.invalidContract(field: field)
        }
        guard evidence.contractRevision == contract.revision else {
            throw ToolbarAuditError.staleEvidence(
                expected: contract.revision,
                actual: evidence.contractRevision
            )
        }
        try ToolbarAuditValidation.validate(evidence, limits: limits, budget: &budget)
        for scenario in ToolbarAuditLifecycleScenario.allCases {
            guard let surface = evidence.surfaces.first(where: { $0.scenario == scenario }),
                surface.manifestRevision != contract.manifest.revision
            else { continue }
            throw ToolbarAuditError.staleManifest(
                expected: contract.manifest.revision,
                actual: surface.manifestRevision
            )
        }
        for context in ToolbarAuditScreenshotContext.allCases {
            guard let screenshot = evidence.screenshots.first(where: { $0.context == context }),
                screenshot.manifestRevision != contract.manifest.revision
            else { continue }
            throw ToolbarAuditError.staleManifest(
                expected: contract.manifest.revision,
                actual: screenshot.manifestRevision
            )
        }

        var context = ToolbarAuditContext(
            contract: contract,
            evidence: evidence,
            limits: limits,
            budget: budget
        )
        try context.run()
        return ToolbarAuditReport(
            formatVersion: reportFormatVersion,
            contractRevision: contract.revision,
            manifestRevision: contract.manifest.revision,
            findings: try context.sortedFindings()
        )
    }
}

private struct ToolbarAuditContext {
    let contract: ToolbarAuditContract
    let evidence: ToolbarAuditEvidence
    let limits: ToolbarAuditLimits
    var budget: ToolbarAuditWorkBudget
    private var findings: [ToolbarAuditFinding] = []

    init(
        contract: ToolbarAuditContract,
        evidence: ToolbarAuditEvidence,
        limits: ToolbarAuditLimits,
        budget: ToolbarAuditWorkBudget
    ) {
        self.contract = contract
        self.evidence = evidence
        self.limits = limits
        self.budget = budget
    }

    mutating func run() throws {
        try inspectContractCoverage()
        try inspectSurfaces()
        try inspectInteractions()
        try inspectScreenshots()
    }

    mutating func sortedFindings() throws -> [ToolbarAuditFinding] {
        try toolbarAuditStableSorted(findings, by: toolbarAuditFindingLess, budget: &budget)
    }

    private mutating func inspectContractCoverage() throws {
        try budget.consume()
        if contract.manifest != ToolbarAuditManifest.canonical {
            try add(
                .error,
                .contractManifestMismatch,
                message: "Contract manifest differs from the canonical WinMerge command grouping or order."
            )
        }

        let manifestCommands = Set(contract.manifest.commands)
        let requirementsByCommand = Dictionary(
            uniqueKeysWithValues: contract.controls.map {
                ($0.command, $0)
            })
        let requiredCommands = Set(contract.controls.map(\.command))
        for command in contract.manifest.commands where !requiredCommands.contains(command) {
            try budget.consume()
            try add(
                .error,
                .controlRequirementMissing,
                command: command,
                message: "Manifest command has no control requirement."
            )
        }
        for requirement in contract.controls where !manifestCommands.contains(requirement.command) {
            try budget.consume()
            try add(
                .error,
                .unexpectedControlRequirement,
                command: requirement.command,
                subjectID: requirement.id,
                message: "Control requirement does not belong to the manifest."
            )
        }

        let lifecycleKeys = Set(contract.lifecycleExpectations.map(ToolbarAuditLifecycleKey.init))
        for scenario in ToolbarAuditLifecycleScenario.allCases {
            for command in contract.manifest.commands {
                try budget.consume()
                guard let requirement = requirementsByCommand[command] else { continue }
                for actionID in requirement.behavior.allActionIDs {
                    let key = ToolbarAuditLifecycleKey(
                        scenario: scenario,
                        command: command,
                        actionID: actionID
                    )
                    guard !lifecycleKeys.contains(key) else { continue }
                    try add(
                        .error,
                        .lifecycleRequirementMissing,
                        command: command,
                        scenario: scenario,
                        subjectID: actionID,
                        message: "Lifecycle matrix has no expectation for this action and scenario."
                    )
                }
            }
        }

        let interactionsByAction = Dictionary(grouping: contract.interactionExpectations, by: \.actionID)
        let disabledScenariosByAction = Dictionary(
            grouping: contract.lifecycleExpectations.filter {
                !$0.availability.isEnabled
            }, by: \.actionID
        ).mapValues { Set($0.map(\.scenario)) }
        for control in contract.controls {
            let primaryInteractions = interactionsByAction[control.behavior.primaryActionID] ?? []
            let primaryKinds = Set(
                primaryInteractions.map(\.invocation)
            )
            let requiredPrimaryKinds: [ToolbarAuditInvocationKind] = [
                .primaryClick, .keyboardActivation, .voiceOverActivation
            ]
            for invocation in requiredPrimaryKinds where !primaryKinds.contains(invocation) {
                try budget.consume()
                try add(
                    .error,
                    .interactionRequirementMissing,
                    command: control.command,
                    subjectID: control.id,
                    discriminator: invocation.rawValue,
                    message: "Primary toolbar action has no \(invocation.rawValue) expectation."
                )
            }
            for actionID in control.behavior.allActionIDs {
                let disabledScenarios = disabledScenariosByAction[actionID] ?? []
                let disabledEvidenceScenarios = Set<ToolbarAuditLifecycleScenario>(
                    (interactionsByAction[actionID] ?? []).compactMap { expectation in
                        guard expectation.invocation == .disabledActivation
                        else { return nil }
                        return expectation.scenario
                    })
                for scenario in disabledScenarios.subtracting(disabledEvidenceScenarios) {
                    try add(
                        .error,
                        .interactionRequirementMissing,
                        command: control.command,
                        scenario: scenario,
                        subjectID: actionID,
                        discriminator: ToolbarAuditInvocationKind.disabledActivation.rawValue,
                        message: "Disabled toolbar action has no blocked-activation expectation."
                    )
                }
            }
            guard case .menu(let actions) = control.behavior.secondary else { continue }
            if !primaryKinds.contains(.menuArrowClick) {
                try add(
                    .error,
                    .interactionRequirementMissing,
                    command: control.command,
                    subjectID: control.id,
                    discriminator: ToolbarAuditInvocationKind.menuArrowClick.rawValue,
                    message: "Split toolbar control has no menu-arrow expectation."
                )
            }
            for action in actions
            where !(interactionsByAction[action.id] ?? []).contains(where: {
                $0.invocation == .menuItemSelection
            }) {
                try add(
                    .error,
                    .interactionRequirementMissing,
                    command: control.command,
                    subjectID: control.id,
                    discriminator: toolbarAuditFindingDiscriminator(
                        ToolbarAuditInvocationKind.menuItemSelection.rawValue,
                        action.id.rawValue
                    ),
                    message: "Secondary toolbar action has no menu-selection expectation."
                )
            }
        }

        let screenshotContexts = Set(contract.screenshotExpectations.map(\.context))
        for context in ToolbarAuditScreenshotContext.allCases where !screenshotContexts.contains(context) {
            try budget.consume()
            try add(
                .error,
                .screenshotRequirementMissing,
                discriminator: context.rawValue,
                message: "Screenshot contract has no \(context.rawValue) expectation."
            )
        }
    }

    private mutating func inspectSurfaces() throws {
        let surfacesByScenario = Dictionary(
            uniqueKeysWithValues: evidence.surfaces.map {
                ($0.scenario, $0)
            })
        let requirementsByCommand = Dictionary(
            uniqueKeysWithValues: contract.controls.map {
                ($0.command, $0)
            })
        let lifecycleByKey = Dictionary(
            uniqueKeysWithValues: contract.lifecycleExpectations.map {
                (ToolbarAuditLifecycleKey($0), $0)
            })

        for scenario in ToolbarAuditLifecycleScenario.allCases {
            try budget.consume()
            guard let surface = surfacesByScenario[scenario] else {
                try add(
                    .error,
                    .lifecycleEvidenceMissing,
                    scenario: scenario,
                    message: "Lifecycle matrix row has no toolbar surface evidence."
                )
                continue
            }
            try inspectItems(
                surface.items,
                expected: contract.manifest.items,
                orderCode: .commandOrderMismatch,
                groupingCode: .commandGroupingMismatch,
                scenario: scenario
            )
            let observationsByCommand = Dictionary(
                uniqueKeysWithValues: surface.controls.map {
                    ($0.command, $0)
                })
            let manifestCommandSet = Set(contract.manifest.commands)
            for command in contract.manifest.commands {
                try budget.consume()
                guard let requirement = requirementsByCommand[command] else { continue }
                guard let observation = observationsByCommand[command] else {
                    try add(
                        .error,
                        .controlEvidenceMissing,
                        command: command,
                        scenario: scenario,
                        subjectID: requirement.id,
                        message: "Toolbar control has no evidence in this lifecycle scenario."
                    )
                    continue
                }
                try inspectControl(
                    observation,
                    requirement: requirement,
                    lifecycle: lifecycleByKey[
                        ToolbarAuditLifecycleKey(
                            scenario: scenario,
                            command: command,
                            actionID: requirement.behavior.primaryActionID
                        )
                    ],
                    lifecycleByKey: lifecycleByKey,
                    scenario: scenario
                )
            }
            for observation in surface.controls where !manifestCommandSet.contains(observation.command) {
                try budget.consume()
                try add(
                    .error,
                    .unexpectedControlEvidence,
                    command: observation.command,
                    scenario: scenario,
                    subjectID: observation.id,
                    message: "Observed control does not belong to the manifest."
                )
            }
            try inspectUniqueAccessibilityMetadata(surface)
        }
    }

    private mutating func inspectControl(
        _ observation: ToolbarAuditControlObservation,
        requirement: ToolbarAuditControlRequirement,
        lifecycle: ToolbarAuditLifecycleExpectation?,
        lifecycleByKey: [ToolbarAuditLifecycleKey: ToolbarAuditLifecycleExpectation],
        scenario: ToolbarAuditLifecycleScenario
    ) throws {
        if observation.id != requirement.id {
            try add(
                .error,
                .controlIdentityMismatch,
                command: requirement.command,
                scenario: scenario,
                subjectID: observation.id,
                message: "Observed control identity differs from its requirement."
            )
        }
        if observation.behavior.primaryActionID != requirement.behavior.primaryActionID {
            try add(
                .error,
                .primaryBehaviorMismatch,
                command: requirement.command,
                scenario: scenario,
                subjectID: requirement.id,
                message: "Primary control action differs from its requirement."
            )
        }
        if observation.behavior.secondary.actionIDs != requirement.behavior.secondary.actionIDs {
            try add(
                .error,
                .secondaryBehaviorMismatch,
                command: requirement.command,
                scenario: scenario,
                subjectID: requirement.id,
                message: "Secondary control behavior or menu order differs from its requirement."
            )
        }
        if case .menu(let expectedActions) = requirement.behavior.secondary,
            case .menu(let observedActions) = observation.behavior.secondary
        {
            let observedByID = Dictionary(uniqueKeysWithValues: observedActions.map { ($0.id, $0) })
            for expectedAction in expectedActions {
                if let observedAX = observedByID[expectedAction.id]?.accessibility,
                    !toolbarAuditAXMetadataMatchesRequirement(
                        observedAX,
                        requirement: expectedAction.accessibility
                    )
                {
                    try add(
                        .error,
                        .secondaryAccessibilityMismatch,
                        command: requirement.command,
                        scenario: scenario,
                        subjectID: expectedAction.id,
                        message: "Secondary action semantic accessibility metadata differs from its requirement."
                    )
                }
                let lifecycle = lifecycleByKey[
                    ToolbarAuditLifecycleKey(
                        scenario: scenario,
                        command: requirement.command,
                        actionID: expectedAction.id
                    )
                ]
                if let lifecycle,
                    observedByID[expectedAction.id]?.accessibility.isEnabled
                        != lifecycle.availability.isEnabled
                {
                    try add(
                        .error,
                        .secondaryAvailabilityMismatch,
                        command: requirement.command,
                        scenario: scenario,
                        subjectID: expectedAction.id,
                        message: "Secondary action enabled state differs from the lifecycle matrix."
                    )
                }
            }
        }
        if observation.tooltip == nil {
            try add(
                .error,
                .tooltipMissing,
                command: requirement.command,
                scenario: scenario,
                subjectID: requirement.id,
                message: "Toolbar control has no tooltip evidence."
            )
        } else if observation.tooltip != requirement.tooltip {
            try add(
                .error,
                .tooltipMismatch,
                command: requirement.command,
                scenario: scenario,
                subjectID: requirement.id,
                message: "Toolbar tooltip differs from the exact required text."
            )
        }
        if requirement.shortcut != nil, observation.shortcut == nil {
            try add(
                .error,
                .shortcutMissing,
                command: requirement.command,
                scenario: scenario,
                subjectID: requirement.id,
                message: "Toolbar control has no required shortcut evidence."
            )
        } else if observation.shortcut != requirement.shortcut {
            try add(
                .error,
                .shortcutMismatch,
                command: requirement.command,
                scenario: scenario,
                subjectID: requirement.id,
                message: "Toolbar shortcut chord or display text differs from its requirement."
            )
        }

        let expectedAX = requirement.accessibility
        let observedAX = observation.accessibility
        if observedAX.identifier != expectedAX.identifier {
            try addAX(.accessibilityIdentifierMismatch, requirement, scenario)
        }
        if observedAX.role != expectedAX.role {
            try addAX(.accessibilityRoleMismatch, requirement, scenario)
        }
        if toolbarAuditIsBlank(observedAX.label) {
            try addAX(.accessibilityLabelMissing, requirement, scenario)
        } else if observedAX.label != expectedAX.label {
            try addAX(.accessibilityLabelMismatch, requirement, scenario)
        }
        if observedAX.value != expectedAX.value {
            try addAX(.accessibilityValueMismatch, requirement, scenario)
        }
        if toolbarAuditIsBlank(observedAX.hint) {
            try addAX(.accessibilityHintMissing, requirement, scenario)
        } else if observedAX.hint != expectedAX.hint {
            try addAX(.accessibilityHintMismatch, requirement, scenario)
        }
        if observedAX.checkedState != expectedAX.checkedState {
            try addAX(.accessibilityCheckedStateMismatch, requirement, scenario)
        }
        if observedAX.selectedState != expectedAX.selectedState {
            try addAX(.accessibilitySelectedStateMismatch, requirement, scenario)
        }
        if observedAX.isKeyboardFocusable != expectedAX.isKeyboardFocusable {
            try addAX(.accessibilityFocusMismatch, requirement, scenario)
        }
        if observedAX.actions != expectedAX.actions {
            try addAX(.accessibilityActionsMismatch, requirement, scenario)
        }
        if let expectedEnabled = expectedAX.isEnabled,
            observedAX.isEnabled != expectedEnabled
        {
            try addAX(.accessibilityEnabledStateMismatch, requirement, scenario)
        }
        if let lifecycle {
            if observation.availability != lifecycle.availability {
                try add(
                    .error,
                    .availabilityMismatch,
                    command: requirement.command,
                    scenario: scenario,
                    subjectID: requirement.id,
                    message: "Observed availability differs from the lifecycle matrix."
                )
            }
            if observedAX.isEnabled != lifecycle.availability.isEnabled {
                try addAX(.accessibilityEnabledStateMismatch, requirement, scenario)
            }
        }
    }

    private mutating func inspectUniqueAccessibilityMetadata(
        _ surface: ToolbarAuditSurfaceEvidence
    ) throws {
        var identifierCounts: [ToolbarAuditStableID: Int] = [:]
        var labelCounts: [String: Int] = [:]
        var shortcutCounts: [String: Int] = [:]
        var accessibilitySubjects:
            [(
                ToolbarAuditCommand, ToolbarAuditStableID, ToolbarAuditAXMetadata, String
            )] = []
        for observation in surface.controls {
            try budget.consume()
            accessibilitySubjects.append(
                (observation.command, observation.id, observation.accessibility, "control")
            )
            if case .menu(let actions) = observation.behavior.secondary {
                for action in actions {
                    try budget.consume()
                    accessibilitySubjects.append(
                        (observation.command, action.id, action.accessibility, "secondaryAction")
                    )
                }
            }
            if let shortcut = observation.shortcut {
                shortcutCounts[shortcut.canonicalChord, default: 0] += 1
            }
        }
        for subject in accessibilitySubjects {
            identifierCounts[subject.2.identifier, default: 0] += 1
            labelCounts[subject.2.label, default: 0] += 1
        }
        for subject in accessibilitySubjects {
            try budget.consume()
            if identifierCounts[subject.2.identifier, default: 0] > 1 {
                try add(
                    .error,
                    .duplicateAccessibilityIdentifier,
                    command: subject.0,
                    scenario: surface.scenario,
                    subjectID: subject.1,
                    discriminator: toolbarAuditFindingDiscriminator(
                        subject.3,
                        subject.2.identifier.rawValue
                    ),
                    message: "Accessibility identifier is not unique in this toolbar."
                )
            }
            if labelCounts[subject.2.label, default: 0] > 1 {
                try add(
                    .error,
                    .duplicateAccessibilityLabel,
                    command: subject.0,
                    scenario: surface.scenario,
                    subjectID: subject.1,
                    discriminator: subject.3,
                    message: "VoiceOver label is not unique in this toolbar."
                )
            }
        }
        for observation in surface.controls {
            try budget.consume()
            if let shortcut = observation.shortcut,
                shortcutCounts[shortcut.canonicalChord, default: 0] > 1
            {
                try add(
                    .error,
                    .duplicateShortcut,
                    command: observation.command,
                    scenario: surface.scenario,
                    subjectID: observation.id,
                    message: "Keyboard shortcut is assigned to multiple toolbar controls."
                )
            }
        }
    }

    private mutating func inspectInteractions() throws {
        let lifecycleByKey = Dictionary(
            uniqueKeysWithValues: contract.lifecycleExpectations.map {
                (ToolbarAuditLifecycleKey($0), $0)
            })
        let controlsByID = Dictionary(uniqueKeysWithValues: contract.controls.map { ($0.id, $0) })
        let expectedByKey = Dictionary(
            uniqueKeysWithValues: contract.interactionExpectations.map {
                (ToolbarAuditInteractionKey($0), $0)
            })
        let actualByKey = Dictionary(
            uniqueKeysWithValues: evidence.interactions.map {
                (ToolbarAuditInteractionKey($0), $0)
            })
        for expectation in contract.interactionExpectations {
            try budget.consume()
            let key = ToolbarAuditInteractionKey(expectation)
            guard let actual = actualByKey[key] else {
                try add(
                    .error,
                    .interactionEvidenceMissing,
                    scenario: expectation.scenario,
                    subjectID: expectation.controlID,
                    discriminator: toolbarAuditFindingDiscriminator(
                        expectation.invocation.rawValue,
                        expectation.actionID.rawValue
                    ),
                    message: "Required interaction has no evidence."
                )
                continue
            }
            if actual.outcome != expectation.outcome {
                try add(
                    .error,
                    .interactionOutcomeMismatch,
                    scenario: expectation.scenario,
                    subjectID: expectation.controlID,
                    discriminator: toolbarAuditFindingDiscriminator(
                        "expectation",
                        expectation.invocation.rawValue,
                        expectation.actionID.rawValue
                    ),
                    message: "Observed interaction outcome differs from its requirement."
                )
            }
            if case .invoked(let invokedActionID) = actual.outcome,
                invokedActionID != actual.actionID
            {
                try add(
                    .error,
                    .interactionOutcomeMismatch,
                    scenario: actual.scenario,
                    subjectID: actual.controlID,
                    discriminator: toolbarAuditFindingDiscriminator(
                        "recordIdentity",
                        actual.invocation.rawValue,
                        actual.actionID.rawValue,
                        invokedActionID.rawValue
                    ),
                    message: "Observed interaction invoked a different action than its record identity."
                )
            }
            let command = controlsByID[actual.controlID]?.command
            let isDisabled =
                command.flatMap { command in
                    lifecycleByKey[
                        ToolbarAuditLifecycleKey(
                            scenario: actual.scenario,
                            command: command,
                            actionID: actual.actionID
                        )
                    ]
                }?.availability.isEnabled == false
            if isDisabled, toolbarAuditOutcomePerformsAction(actual.outcome) {
                try add(
                    .error,
                    .disabledActivationSucceeded,
                    scenario: expectation.scenario,
                    subjectID: expectation.controlID,
                    discriminator: toolbarAuditFindingDiscriminator(
                        expectation.invocation.rawValue,
                        expectation.actionID.rawValue
                    ),
                    message: "Disabled toolbar action was invoked."
                )
            }
        }
        for actual in evidence.interactions
        where expectedByKey[ToolbarAuditInteractionKey(actual)] == nil {
            try budget.consume()
            if case .invoked(let invokedActionID) = actual.outcome,
                invokedActionID != actual.actionID
            {
                try add(
                    .error,
                    .interactionOutcomeMismatch,
                    scenario: actual.scenario,
                    subjectID: actual.controlID,
                    discriminator: toolbarAuditFindingDiscriminator(
                        "recordIdentity",
                        actual.invocation.rawValue,
                        actual.actionID.rawValue,
                        invokedActionID.rawValue
                    ),
                    message: "Observed interaction invoked a different action than its record identity."
                )
                continue
            }
            let command = controlsByID[actual.controlID]?.command
            let isDisabled =
                command.flatMap { command in
                    lifecycleByKey[
                        ToolbarAuditLifecycleKey(
                            scenario: actual.scenario,
                            command: command,
                            actionID: actual.actionID
                        )
                    ]
                }?.availability.isEnabled == false
            if isDisabled, toolbarAuditOutcomePerformsAction(actual.outcome) {
                try add(
                    .error,
                    .disabledActivationSucceeded,
                    scenario: actual.scenario,
                    subjectID: actual.controlID,
                    discriminator: toolbarAuditFindingDiscriminator(
                        actual.invocation.rawValue,
                        actual.actionID.rawValue
                    ),
                    message: "Disabled toolbar action was invoked without a matching expectation."
                )
                continue
            }
            try add(
                .warning,
                .unexpectedInteractionEvidence,
                scenario: actual.scenario,
                subjectID: actual.controlID,
                discriminator: toolbarAuditFindingDiscriminator(
                    actual.invocation.rawValue,
                    actual.actionID.rawValue
                ),
                message: "Interaction evidence has no matching contract expectation."
            )
        }
    }

    private mutating func inspectScreenshots() throws {
        let expectedByContext = Dictionary(
            uniqueKeysWithValues: contract.screenshotExpectations.map {
                ($0.context, $0)
            })
        let actualByContext = Dictionary(
            uniqueKeysWithValues: evidence.screenshots.map {
                ($0.context, $0)
            })
        for expectation in contract.screenshotExpectations {
            try budget.consume()
            guard let actual = actualByContext[expectation.context] else {
                try add(
                    .error,
                    .screenshotEvidenceMissing,
                    discriminator: expectation.context.rawValue,
                    message: "Required screenshot context has no evidence."
                )
                continue
            }
            try inspectItems(
                actual.items,
                expected: contract.manifest.items,
                orderCode: .screenshotOrderMismatch,
                groupingCode: .screenshotGroupingMismatch,
                discriminator: expectation.context.rawValue
            )
            if expectation.requiresAccessibilitySidecar,
                actual.accessibilitySidecarDigest == nil
            {
                try add(
                    .error,
                    .screenshotAccessibilitySidecarMissing,
                    discriminator: expectation.context.rawValue,
                    message: "Screenshot evidence has no required semantic AX sidecar digest."
                )
            }
        }
        for actual in evidence.screenshots where expectedByContext[actual.context] == nil {
            try budget.consume()
            try add(
                .warning,
                .unexpectedScreenshotEvidence,
                discriminator: actual.context.rawValue,
                message: "Screenshot evidence has no matching contract expectation."
            )
        }
    }

    private mutating func inspectItems(
        _ actual: [ToolbarAuditItem],
        expected: [ToolbarAuditItem],
        orderCode: ToolbarAuditFindingCode,
        groupingCode: ToolbarAuditFindingCode,
        scenario: ToolbarAuditLifecycleScenario? = nil,
        discriminator: String = ""
    ) throws {
        guard actual != expected else { return }
        if actual.compactMap(\.command) != expected.compactMap(\.command) {
            try add(
                .error,
                orderCode,
                scenario: scenario,
                discriminator: discriminator,
                message: "Observed toolbar command order differs from the manifest."
            )
        }
        if toolbarAuditSeparatorBoundaries(actual) != toolbarAuditSeparatorBoundaries(expected) {
            try add(
                .error,
                groupingCode,
                scenario: scenario,
                discriminator: discriminator,
                message: "Observed toolbar separator grouping differs from the manifest."
            )
        }
    }

    private mutating func addAX(
        _ code: ToolbarAuditFindingCode,
        _ requirement: ToolbarAuditControlRequirement,
        _ scenario: ToolbarAuditLifecycleScenario
    ) throws {
        try add(
            .error,
            code,
            command: requirement.command,
            scenario: scenario,
            subjectID: requirement.id,
            message: "Observed semantic accessibility metadata differs from its requirement."
        )
    }

    private mutating func add(
        _ severity: ToolbarAuditFindingSeverity,
        _ code: ToolbarAuditFindingCode,
        command: ToolbarAuditCommand? = nil,
        scenario: ToolbarAuditLifecycleScenario? = nil,
        subjectID: ToolbarAuditStableID? = nil,
        discriminator: String = "",
        message: String
    ) throws {
        try budget.consume()
        guard findings.count < limits.maximumFindings else {
            throw ToolbarAuditError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        findings.append(
            ToolbarAuditFinding(
                severity: severity,
                code: code,
                command: command,
                scenario: scenario,
                subjectID: subjectID,
                discriminator: discriminator,
                message: message
            )
        )
    }
}

private struct ToolbarAuditLifecycleKey: Hashable {
    let scenario: ToolbarAuditLifecycleScenario
    let command: ToolbarAuditCommand
    let actionID: ToolbarAuditStableID

    init(
        scenario: ToolbarAuditLifecycleScenario,
        command: ToolbarAuditCommand,
        actionID: ToolbarAuditStableID
    ) {
        self.scenario = scenario
        self.command = command
        self.actionID = actionID
    }

    init(_ value: ToolbarAuditLifecycleExpectation) {
        self.init(
            scenario: value.scenario,
            command: value.command,
            actionID: value.actionID
        )
    }
}

private struct ToolbarAuditInteractionKey: Hashable {
    let scenario: ToolbarAuditLifecycleScenario
    let controlID: ToolbarAuditStableID
    let actionID: ToolbarAuditStableID
    let invocation: ToolbarAuditInvocationKind

    init(_ value: ToolbarAuditInteractionExpectation) {
        scenario = value.scenario
        controlID = value.controlID
        actionID = value.actionID
        invocation = value.invocation
    }

    init(_ value: ToolbarAuditInteractionEvidence) {
        scenario = value.scenario
        controlID = value.controlID
        actionID = value.actionID
        invocation = value.invocation
    }
}

private enum ToolbarAuditValidation {
    static func validate(_ limits: ToolbarAuditLimits) throws {
        try validateLimit(
            limits.maximumManifestItems,
            name: "maximumManifestItems",
            maximum: ToolbarAuditLimits.hardMaximumManifestItems
        )
        try validateLimit(
            limits.maximumControls,
            name: "maximumControls",
            maximum: ToolbarAuditLimits.hardMaximumControls
        )
        try validateLimit(
            limits.maximumSecondaryActions,
            name: "maximumSecondaryActions",
            maximum: ToolbarAuditLimits.hardMaximumSecondaryActions
        )
        try validateLimit(
            limits.maximumLifecycleExpectations,
            name: "maximumLifecycleExpectations",
            maximum: ToolbarAuditLimits.hardMaximumLifecycleExpectations
        )
        try validateLimit(
            limits.maximumInteractionRecords,
            name: "maximumInteractionRecords",
            maximum: ToolbarAuditLimits.hardMaximumInteractionRecords
        )
        try validateLimit(
            limits.maximumScreenshots,
            name: "maximumScreenshots",
            maximum: ToolbarAuditLimits.hardMaximumScreenshots
        )
        try validatePositiveLimit(
            limits.maximumStringUTF8Bytes,
            name: "maximumStringUTF8Bytes",
            maximum: ToolbarAuditLimits.hardMaximumStringUTF8Bytes
        )
        try validatePositiveLimit(
            limits.maximumTotalStringUTF8Bytes,
            name: "maximumTotalStringUTF8Bytes",
            maximum: ToolbarAuditLimits.hardMaximumTotalStringUTF8Bytes
        )
        try validatePositiveLimit(
            limits.maximumWorkUnits,
            name: "maximumWorkUnits",
            maximum: ToolbarAuditLimits.hardMaximumWorkUnits
        )
        try validateLimit(
            limits.maximumFindings,
            name: "maximumFindings",
            maximum: ToolbarAuditLimits.hardMaximumFindings
        )
        try validatePositiveLimit(
            limits.maximumArchiveBytes,
            name: "maximumArchiveBytes",
            maximum: ToolbarAuditLimits.hardMaximumArchiveBytes
        )
        try validatePositiveLimit(
            limits.cancellationCheckInterval,
            name: "cancellationCheckInterval",
            maximum: ToolbarAuditLimits.hardMaximumCancellationCheckInterval
        )
    }

    static func validate(
        _ contract: ToolbarAuditContract,
        limits: ToolbarAuditLimits,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        var strings = ToolbarAuditStringBudget(limits: limits)
        try validateItems(contract.manifest.items, limits: limits, budget: &budget, field: "manifest")
        try validateCount(contract.controls.count, maximum: limits.maximumControls, kind: "control")
        try validateCount(
            contract.lifecycleExpectations.count,
            maximum: limits.maximumLifecycleExpectations,
            kind: "lifecycle-expectation"
        )
        try validateCount(
            contract.interactionExpectations.count,
            maximum: limits.maximumInteractionRecords,
            kind: "interaction-expectation"
        )
        try validateCount(
            contract.screenshotExpectations.count,
            maximum: limits.maximumScreenshots,
            kind: "screenshot-expectation"
        )

        var controlIDs: Set<ToolbarAuditStableID> = []
        var commands: Set<ToolbarAuditCommand> = []
        var actionIDs: Set<ToolbarAuditStableID> = []
        for control in contract.controls {
            try budget.consume()
            try strings.identifier(control.id, field: "controls.id")
            guard controlIDs.insert(control.id).inserted else {
                throw ToolbarAuditError.invalidContract(field: "controls.duplicateID")
            }
            guard commands.insert(control.command).inserted else {
                throw ToolbarAuditError.invalidContract(field: "controls.duplicateCommand")
            }
            try validateBehavior(
                control.behavior,
                maximumSecondaryActions: limits.maximumSecondaryActions,
                requireConcreteEnabledState: false,
                strings: &strings,
                actionIDs: &actionIDs,
                field: "controls.behavior"
            )
            try strings.nonblank(control.tooltip, field: "controls.tooltip")
            if let shortcut = control.shortcut {
                try validateShortcut(shortcut, strings: &strings, field: "controls.shortcut")
            }
            guard control.accessibility.isEnabled == nil else {
                throw ToolbarAuditError.invalidContract(field: "controls.accessibility.isEnabled")
            }
            try validateAX(
                control.accessibility,
                strings: &strings,
                field: "controls.accessibility"
            )
        }
        let controlsByID = Dictionary(uniqueKeysWithValues: contract.controls.map { ($0.id, $0) })

        var lifecycleKeys: Set<ToolbarAuditLifecycleKey> = []
        for expectation in contract.lifecycleExpectations {
            try budget.consume()
            guard lifecycleKeys.insert(ToolbarAuditLifecycleKey(expectation)).inserted else {
                throw ToolbarAuditError.invalidContract(field: "lifecycleExpectations.duplicate")
            }
            guard
                let control = controlsByID.values.first(where: {
                    $0.command == expectation.command
                }), control.behavior.allActionIDs.contains(expectation.actionID)
            else {
                throw ToolbarAuditError.invalidContract(
                    field: "lifecycleExpectations.actionReference"
                )
            }
            try validateAvailability(
                expectation.availability,
                strings: &strings,
                field: "lifecycleExpectations.availability"
            )
        }

        var interactionKeys: Set<ToolbarAuditInteractionKey> = []
        let lifecycleByKey = Dictionary(
            uniqueKeysWithValues: contract.lifecycleExpectations.map {
                (ToolbarAuditLifecycleKey($0), $0)
            })
        for expectation in contract.interactionExpectations {
            try budget.consume()
            guard interactionKeys.insert(ToolbarAuditInteractionKey(expectation)).inserted else {
                throw ToolbarAuditError.invalidContract(field: "interactionExpectations.duplicate")
            }
            guard let control = controlsByID[expectation.controlID],
                control.behavior.allActionIDs.contains(expectation.actionID)
            else {
                throw ToolbarAuditError.invalidContract(field: "interactionExpectations.reference")
            }
            try validateOutcome(
                expectation.outcome,
                maximumActionIDs: limits.maximumSecondaryActions,
                strings: &strings,
                field: "interactionExpectations.outcome"
            )
            try validateInteractionExpectation(expectation, control: control)
            let availability = lifecycleByKey[
                ToolbarAuditLifecycleKey(
                    scenario: expectation.scenario,
                    command: control.command,
                    actionID: expectation.actionID
                )
            ]?.availability
            if availability?.isEnabled == false,
                toolbarAuditOutcomePerformsAction(expectation.outcome)
            {
                throw ToolbarAuditError.invalidContract(
                    field: "interactionExpectations.disabledLifecycleOutcome"
                )
            }
            if expectation.invocation == .disabledActivation,
                availability?.isEnabled != false
            {
                throw ToolbarAuditError.invalidContract(
                    field: "interactionExpectations.enabledDisabledActivation"
                )
            }
        }
        guard
            Set(contract.screenshotExpectations.map(\.context)).count
                == contract.screenshotExpectations.count
        else {
            throw ToolbarAuditError.invalidContract(field: "screenshotExpectations.duplicate")
        }
    }

    static func validate(
        _ evidence: ToolbarAuditEvidence,
        limits: ToolbarAuditLimits,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        var strings = ToolbarAuditStringBudget(limits: limits)
        try validateCount(
            evidence.surfaces.count,
            maximum: ToolbarAuditLifecycleScenario.allCases.count,
            kind: "surface"
        )
        try validateCount(
            evidence.interactions.count,
            maximum: limits.maximumInteractionRecords,
            kind: "interaction-evidence"
        )
        try validateCount(
            evidence.screenshots.count,
            maximum: limits.maximumScreenshots,
            kind: "screenshot-evidence"
        )
        guard Set(evidence.surfaces.map(\.scenario)).count == evidence.surfaces.count else {
            throw ToolbarAuditError.invalidEvidence(field: "surfaces.duplicateScenario")
        }

        for surface in evidence.surfaces {
            try budget.consume()
            try validateItems(surface.items, limits: limits, budget: &budget, field: "surfaces.items")
            try validateCount(surface.controls.count, maximum: limits.maximumControls, kind: "observed-control")
            try strings.nonblank(surface.source, field: "surfaces.source")
            var ids: Set<ToolbarAuditStableID> = []
            var commands: Set<ToolbarAuditCommand> = []
            var actionIDs: Set<ToolbarAuditStableID> = []
            for control in surface.controls {
                try budget.consume()
                try strings.identifier(control.id, field: "surfaces.controls.id")
                guard ids.insert(control.id).inserted else {
                    throw ToolbarAuditError.invalidEvidence(field: "surfaces.controls.duplicateID")
                }
                guard commands.insert(control.command).inserted else {
                    throw ToolbarAuditError.invalidEvidence(field: "surfaces.controls.duplicateCommand")
                }
                try validateBehavior(
                    control.behavior,
                    maximumSecondaryActions: limits.maximumSecondaryActions,
                    requireConcreteEnabledState: true,
                    strings: &strings,
                    actionIDs: &actionIDs,
                    field: "surfaces.controls.behavior"
                )
                if let tooltip = control.tooltip {
                    try strings.nonblank(tooltip, field: "surfaces.controls.tooltip")
                }
                if let shortcut = control.shortcut {
                    try validateShortcut(
                        shortcut,
                        strings: &strings,
                        field: "surfaces.controls.shortcut"
                    )
                }
                guard control.accessibility.isEnabled != nil else {
                    throw ToolbarAuditError.invalidEvidence(
                        field: "surfaces.controls.accessibility.isEnabled"
                    )
                }
                try validateAX(
                    control.accessibility,
                    strings: &strings,
                    field: "surfaces.controls.accessibility"
                )
                try validateAvailability(
                    control.availability,
                    strings: &strings,
                    field: "surfaces.controls.availability"
                )
            }
        }

        var interactionKeys: Set<ToolbarAuditInteractionKey> = []
        for interaction in evidence.interactions {
            try budget.consume()
            try strings.identifier(interaction.controlID, field: "interactions.controlID")
            try strings.identifier(interaction.actionID, field: "interactions.actionID")
            guard interactionKeys.insert(ToolbarAuditInteractionKey(interaction)).inserted else {
                throw ToolbarAuditError.invalidEvidence(field: "interactions.duplicate")
            }
            try validateOutcome(
                interaction.outcome,
                maximumActionIDs: limits.maximumSecondaryActions,
                strings: &strings,
                field: "interactions.outcome"
            )
            try strings.nonblank(interaction.source, field: "interactions.source")
        }

        guard Set(evidence.screenshots.map(\.context)).count == evidence.screenshots.count else {
            throw ToolbarAuditError.invalidEvidence(field: "screenshots.duplicateContext")
        }
        for screenshot in evidence.screenshots {
            try budget.consume()
            try validateItems(
                screenshot.items,
                limits: limits,
                budget: &budget,
                field: "screenshots.items"
            )
            try validateDigest(screenshot.screenshotDigest, strings: &strings, field: "screenshots.digest")
            if let sidecar = screenshot.accessibilitySidecarDigest {
                try validateDigest(sidecar, strings: &strings, field: "screenshots.sidecarDigest")
            }
            try strings.nonblank(screenshot.source, field: "screenshots.source")
        }
    }

    private static func validateItems(
        _ items: [ToolbarAuditItem],
        limits: ToolbarAuditLimits,
        budget: inout ToolbarAuditWorkBudget,
        field: String
    ) throws {
        try validateCount(items.count, maximum: limits.maximumManifestItems, kind: "manifest-item")
        var seen: Set<ToolbarAuditCommand> = []
        var hasCommand = false
        for item in items {
            try budget.consume()
            switch item {
            case .command(let command):
                guard seen.insert(command).inserted else {
                    throw ToolbarAuditError.invalidEvidence(field: field + ".duplicateCommand")
                }
                hasCommand = true
            case .separator:
                guard hasCommand else {
                    throw ToolbarAuditError.invalidEvidence(field: field + ".separator")
                }
                hasCommand = false
            }
        }
    }

    private static func validateBehavior(
        _ behavior: ToolbarAuditControlBehavior,
        maximumSecondaryActions: Int,
        requireConcreteEnabledState: Bool,
        strings: inout ToolbarAuditStringBudget,
        actionIDs: inout Set<ToolbarAuditStableID>,
        field: String
    ) throws {
        try strings.identifier(behavior.primaryActionID, field: field + ".primary")
        guard actionIDs.insert(behavior.primaryActionID).inserted else {
            throw ToolbarAuditError.invalidEvidence(field: field + ".duplicateActionID")
        }
        let secondaryActions: [ToolbarAuditSecondaryAction]
        switch behavior.secondary {
        case .none:
            secondaryActions = []
        case .menu(let actions):
            guard !actions.isEmpty else {
                throw ToolbarAuditError.invalidEvidence(field: field + ".emptyMenu")
            }
            secondaryActions = actions
        }
        try validateCount(
            secondaryActions.count,
            maximum: maximumSecondaryActions,
            kind: "secondary-action"
        )
        for action in secondaryActions {
            try strings.identifier(action.id, field: field + ".secondary.id")
            guard actionIDs.insert(action.id).inserted else {
                throw ToolbarAuditError.invalidEvidence(field: field + ".duplicateActionID")
            }
            guard (action.accessibility.isEnabled != nil) == requireConcreteEnabledState else {
                throw ToolbarAuditError.invalidEvidence(field: field + ".secondary.isEnabled")
            }
            try validateAX(
                action.accessibility,
                strings: &strings,
                field: field + ".secondary.accessibility"
            )
        }
    }

    private static func validateShortcut(
        _ shortcut: ToolbarAuditShortcut,
        strings: inout ToolbarAuditStringBudget,
        field: String
    ) throws {
        try strings.nonblank(shortcut.key, field: field + ".key")
        try strings.nonblank(shortcut.display, field: field + ".display")
        guard !shortcut.key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ToolbarAuditError.invalidEvidence(field: field + ".key")
        }
    }

    private static func validateAX(
        _ metadata: ToolbarAuditAXMetadata,
        strings: inout ToolbarAuditStringBudget,
        field: String
    ) throws {
        try strings.identifier(metadata.identifier, field: field + ".identifier")
        try strings.nonblank(metadata.label, field: field + ".label")
        if let value = metadata.value {
            try strings.nonblank(value, field: field + ".value")
        }
        try strings.nonblank(metadata.hint, field: field + ".hint")
        guard !metadata.actions.isEmpty else {
            throw ToolbarAuditError.invalidEvidence(field: field + ".actions")
        }
    }

    private static func validateAvailability(
        _ availability: ToolbarAuditAvailability,
        strings: inout ToolbarAuditStringBudget,
        field: String
    ) throws {
        guard case .disabled(let reason) = availability else { return }
        try strings.identifier(reason, field: field + ".reason")
    }

    private static func validateOutcome(
        _ outcome: ToolbarAuditInteractionOutcome,
        maximumActionIDs: Int,
        strings: inout ToolbarAuditStringBudget,
        field: String
    ) throws {
        switch outcome {
        case .invoked(let actionID):
            try strings.identifier(actionID, field: field + ".actionID")
        case .menuPresented(let actionIDs):
            try validateCount(
                actionIDs.count,
                maximum: maximumActionIDs,
                kind: "presented-menu-action"
            )
            guard !actionIDs.isEmpty, Set(actionIDs).count == actionIDs.count else {
                throw ToolbarAuditError.invalidEvidence(field: field + ".menu")
            }
            for id in actionIDs {
                try strings.identifier(id, field: field + ".menu.actionID")
            }
        case .failed(let code):
            try strings.identifier(code, field: field + ".code")
        case .blocked, .noOp:
            break
        }
    }

    private static func validateInteractionExpectation(
        _ expectation: ToolbarAuditInteractionExpectation,
        control: ToolbarAuditControlRequirement
    ) throws {
        switch expectation.invocation {
        case .primaryClick, .keyboardActivation, .voiceOverActivation:
            guard expectation.actionID == control.behavior.primaryActionID,
                expectation.outcome == .invoked(actionID: expectation.actionID)
            else {
                throw ToolbarAuditError.invalidContract(
                    field: "interactionExpectations.primaryOutcome"
                )
            }
        case .menuArrowClick:
            guard case .menu(let actions) = control.behavior.secondary,
                expectation.actionID == control.behavior.primaryActionID,
                expectation.outcome == .menuPresented(actionIDs: actions.map(\.id))
            else {
                throw ToolbarAuditError.invalidContract(
                    field: "interactionExpectations.menuArrowOutcome"
                )
            }
        case .menuItemSelection:
            guard control.behavior.secondary.actionIDs.contains(expectation.actionID),
                expectation.outcome == .invoked(actionID: expectation.actionID)
            else {
                throw ToolbarAuditError.invalidContract(
                    field: "interactionExpectations.menuSelectionOutcome"
                )
            }
        case .disabledActivation:
            guard !toolbarAuditOutcomePerformsAction(expectation.outcome) else {
                throw ToolbarAuditError.invalidContract(
                    field: "interactionExpectations.disabledOutcome"
                )
            }
        }
    }

    private static func validateDigest(
        _ digest: ToolbarAuditArtifactDigest,
        strings: inout ToolbarAuditStringBudget,
        field: String
    ) throws {
        try strings.add(digest.lowercaseHex, field: field)
        guard digest.algorithm == .sha256,
            digest.lowercaseHex.utf8.count == 64,
            digest.lowercaseHex.utf8.allSatisfy({
                (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
            })
        else {
            throw ToolbarAuditError.invalidEvidence(field: field)
        }
    }

    private static func validateCount(_ count: Int, maximum: Int, kind: String) throws {
        guard count <= maximum else {
            throw ToolbarAuditError.countLimitExceeded(kind: kind, maximum: maximum)
        }
    }

    private static func validateLimit(_ value: Int, name: String, maximum: Int) throws {
        guard (0...maximum).contains(value) else {
            throw ToolbarAuditError.invalidLimit(name: name, value: value, maximum: maximum)
        }
    }

    private static func validatePositiveLimit(_ value: Int, name: String, maximum: Int) throws {
        guard (1...maximum).contains(value) else {
            throw ToolbarAuditError.invalidLimit(name: name, value: value, maximum: maximum)
        }
    }
}

private struct ToolbarAuditStringBudget {
    let limits: ToolbarAuditLimits
    private var total = 0

    init(limits: ToolbarAuditLimits) {
        self.limits = limits
    }

    mutating func identifier(_ value: ToolbarAuditStableID, field: String) throws {
        try nonblank(value.rawValue, field: field)
        guard !value.rawValue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ToolbarAuditError.invalidEvidence(field: field)
        }
    }

    mutating func nonblank(_ value: String, field: String) throws {
        try add(value, field: field)
        guard !toolbarAuditIsBlank(value) else {
            throw ToolbarAuditError.invalidEvidence(field: field)
        }
    }

    mutating func add(_ value: String, field: String) throws {
        let count = value.utf8.count
        guard count <= limits.maximumStringUTF8Bytes else {
            throw ToolbarAuditError.stringTooLarge(
                field: field,
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        guard total <= limits.maximumTotalStringUTF8Bytes - count else {
            throw ToolbarAuditError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        total += count
    }
}

private struct ToolbarAuditWorkBudget {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: ToolbarAuditContract.CancellationCheck
    private(set) var completed = 0
    private var nextCancellationCheck: Int

    init(
        limits: ToolbarAuditLimits,
        cancellationCheck: @escaping ToolbarAuditContract.CancellationCheck
    ) {
        maximum = limits.maximumWorkUnits
        cancellationCheckInterval = limits.cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
        nextCancellationCheck = limits.cancellationCheckInterval
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0, amount <= maximum, completed <= maximum - amount else {
            throw ToolbarAuditError.workLimitExceeded(maximum: maximum)
        }
        completed += amount
        if completed >= nextCancellationCheck {
            try checkCancellation()
            let (next, overflow) = completed.addingReportingOverflow(cancellationCheckInterval)
            nextCancellationCheck = overflow ? Int.max : next
        }
    }

    func checkCancellation() throws {
        do {
            try cancellationCheck()
        } catch {
            throw ToolbarAuditError.cancelled
        }
    }
}

/// Canonical, versioned binary persistence for toolbar evidence.
public enum ToolbarAuditEvidenceArchive: Sendable {
    public static let currentFormatVersion = 1
    private static let magic = Data("MMTBAUD1".utf8)

    public static func encode(
        _ evidence: ToolbarAuditEvidence,
        limits: ToolbarAuditLimits = .default,
        cancellationCheck: @escaping ToolbarAuditContract.CancellationCheck = {
            try Task.checkCancellation()
        }
    ) throws -> Data {
        try ToolbarAuditValidation.validate(limits)
        var budget = ToolbarAuditWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try budget.checkCancellation()
        try ToolbarAuditValidation.validate(evidence, limits: limits, budget: &budget)
        return try encodeValidated(evidence, limits: limits, budget: &budget)
    }

    public static func decode(
        _ data: Data,
        limits: ToolbarAuditLimits = .default,
        cancellationCheck: @escaping ToolbarAuditContract.CancellationCheck = {
            try Task.checkCancellation()
        }
    ) throws -> ToolbarAuditEvidence {
        try ToolbarAuditValidation.validate(limits)
        guard data.count <= limits.maximumArchiveBytes else {
            throw ToolbarAuditError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
        }
        var budget = ToolbarAuditWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try budget.checkCancellation()
        var reader = ToolbarAuditArchiveReader(data: data, limits: limits)
        guard try reader.readRaw(count: magic.count, budget: &budget) == magic else {
            throw ToolbarAuditError.invalidArchive
        }
        let version = Int(try reader.readUInt16(budget: &budget))
        guard version == currentFormatVersion else {
            throw ToolbarAuditError.unsupportedArchiveVersion(version)
        }
        guard try reader.readUInt16(budget: &budget) == 0 else {
            throw ToolbarAuditError.invalidArchive
        }
        let payloadLength = Int(try reader.readUInt32(budget: &budget))
        let expectedChecksum = try reader.readUInt64(budget: &budget)
        guard payloadLength == reader.remainingCount else {
            throw ToolbarAuditError.invalidArchive
        }
        let payload = try reader.readRaw(count: payloadLength, budget: &budget)
        guard reader.isAtEnd else { throw ToolbarAuditError.invalidArchive }
        guard try toolbarAuditFNV1a64(payload, budget: &budget) == expectedChecksum else {
            throw ToolbarAuditError.archiveChecksumMismatch
        }

        var payloadReader = ToolbarAuditArchiveReader(data: payload, limits: limits)
        let evidence = try payloadReader.readEvidence(budget: &budget)
        guard payloadReader.isAtEnd else { throw ToolbarAuditError.invalidArchive }
        try ToolbarAuditValidation.validate(evidence, limits: limits, budget: &budget)
        guard payloadReader.hasCanonicalStrings else {
            throw ToolbarAuditError.nonCanonicalArchive
        }
        let canonical = try encodeValidated(evidence, limits: limits, budget: &budget)
        guard try toolbarAuditEqualData(data, canonical, budget: &budget) else {
            throw ToolbarAuditError.nonCanonicalArchive
        }
        return evidence
    }

    private static func encodeValidated(
        _ evidence: ToolbarAuditEvidence,
        limits: ToolbarAuditLimits,
        budget: inout ToolbarAuditWorkBudget
    ) throws -> Data {
        let surfaces = try toolbarAuditStableSorted(
            evidence.surfaces,
            by: { left, right, _ in
                toolbarAuditEnumRank(left.scenario) < toolbarAuditEnumRank(right.scenario)
            },
            budget: &budget
        )
        let interactions = try toolbarAuditStableSorted(
            evidence.interactions,
            by: toolbarAuditInteractionEvidenceLess,
            budget: &budget
        )
        let screenshots = try toolbarAuditStableSorted(
            evidence.screenshots,
            by: { left, right, _ in
                toolbarAuditEnumRank(left.context) < toolbarAuditEnumRank(right.context)
            },
            budget: &budget
        )
        var payload = ToolbarAuditArchiveWriter(limits: limits)
        try payload.append(evidence.contractRevision.rawValue, budget: &budget)
        try payload.appendCount(surfaces.count, budget: &budget)
        for surface in surfaces {
            try payload.appendEnum(surface.scenario, budget: &budget)
            try payload.append(surface.manifestRevision.rawValue, budget: &budget)
            try payload.appendItems(surface.items, budget: &budget)
            let controls = try toolbarAuditStableSorted(
                surface.controls,
                by: toolbarAuditControlObservationLess,
                budget: &budget
            )
            try payload.appendCount(controls.count, budget: &budget)
            for control in controls {
                try payload.append(control.id.rawValue, budget: &budget)
                try payload.append(control.command.rawValue, budget: &budget)
                try payload.append(control.behavior, budget: &budget)
                try payload.appendOptional(control.tooltip, budget: &budget)
                try payload.appendOptional(control.shortcut, budget: &budget)
                try payload.append(control.accessibility, budget: &budget)
                try payload.append(control.availability, budget: &budget)
            }
            try payload.append(surface.source, budget: &budget)
        }
        try payload.appendCount(interactions.count, budget: &budget)
        for interaction in interactions {
            try payload.appendEnum(interaction.scenario, budget: &budget)
            try payload.append(interaction.controlID.rawValue, budget: &budget)
            try payload.append(interaction.actionID.rawValue, budget: &budget)
            try payload.appendEnum(interaction.invocation, budget: &budget)
            try payload.append(interaction.outcome, budget: &budget)
            try payload.append(interaction.source, budget: &budget)
        }
        try payload.appendCount(screenshots.count, budget: &budget)
        for screenshot in screenshots {
            try payload.appendEnum(screenshot.context, budget: &budget)
            try payload.append(screenshot.manifestRevision.rawValue, budget: &budget)
            try payload.appendItems(screenshot.items, budget: &budget)
            try payload.append(screenshot.screenshotDigest, budget: &budget)
            try payload.appendOptional(screenshot.accessibilitySidecarDigest, budget: &budget)
            try payload.append(screenshot.source, budget: &budget)
        }

        let checksum = try toolbarAuditFNV1a64(payload.data, budget: &budget)
        var archive = ToolbarAuditArchiveWriter(limits: limits)
        try archive.appendRaw(magic, budget: &budget)
        try archive.append(UInt16(currentFormatVersion), budget: &budget)
        try archive.append(UInt16(0), budget: &budget)
        guard let payloadCount = UInt32(exactly: payload.data.count) else {
            throw ToolbarAuditError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
        }
        try archive.append(payloadCount, budget: &budget)
        try archive.append(checksum, budget: &budget)
        try archive.appendRaw(payload.data, budget: &budget)
        return archive.data
    }
}

private struct ToolbarAuditArchiveWriter {
    private(set) var data = Data()
    let maximumBytes: Int
    let maximumStringUTF8Bytes: Int
    let maximumTotalStringUTF8Bytes: Int
    private var totalStringBytes = 0

    init(limits: ToolbarAuditLimits) {
        maximumBytes = limits.maximumArchiveBytes
        maximumStringUTF8Bytes = limits.maximumStringUTF8Bytes
        maximumTotalStringUTF8Bytes = limits.maximumTotalStringUTF8Bytes
    }

    mutating func appendRaw(
        _ value: Data,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        try budget.consume(value.count)
        guard data.count <= maximumBytes - value.count else {
            throw ToolbarAuditError.archiveTooLarge(maximumBytes: maximumBytes)
        }
        data.append(value)
    }

    mutating func append(_ value: UInt8, budget: inout ToolbarAuditWorkBudget) throws {
        try appendRaw(Data([value]), budget: &budget)
    }

    mutating func append(_ value: UInt16, budget: inout ToolbarAuditWorkBudget) throws {
        try appendRaw(
            Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]),
            budget: &budget
        )
    }

    mutating func append(_ value: UInt32, budget: inout ToolbarAuditWorkBudget) throws {
        try appendRaw(
            Data((0..<4).map { UInt8((value >> UInt32($0 * 8)) & 0xff) }),
            budget: &budget
        )
    }

    mutating func append(_ value: UInt64, budget: inout ToolbarAuditWorkBudget) throws {
        try appendRaw(
            Data((0..<8).map { UInt8((value >> UInt64($0 * 8)) & 0xff) }),
            budget: &budget
        )
    }

    mutating func appendCount(_ count: Int, budget: inout ToolbarAuditWorkBudget) throws {
        guard let value = UInt32(exactly: count) else { throw ToolbarAuditError.invalidArchive }
        try append(value, budget: &budget)
    }

    mutating func append(_ value: String, budget: inout ToolbarAuditWorkBudget) throws {
        let bytes = Data(value.utf8)
        guard bytes.count <= maximumStringUTF8Bytes else {
            throw ToolbarAuditError.stringTooLarge(
                field: "archive.string",
                maximumUTF8Bytes: maximumStringUTF8Bytes
            )
        }
        guard totalStringBytes <= maximumTotalStringUTF8Bytes - bytes.count else {
            throw ToolbarAuditError.totalStringsTooLarge(
                maximumUTF8Bytes: maximumTotalStringUTF8Bytes
            )
        }
        totalStringBytes += bytes.count
        try appendCount(bytes.count, budget: &budget)
        try appendRaw(bytes, budget: &budget)
    }

    mutating func appendOptional(
        _ value: String?,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        guard let value else {
            try append(UInt8(0), budget: &budget)
            return
        }
        try append(UInt8(1), budget: &budget)
        try append(value, budget: &budget)
    }

    mutating func appendEnum<Value: RawRepresentable>(
        _ value: Value,
        budget: inout ToolbarAuditWorkBudget
    ) throws where Value.RawValue == String {
        try append(value.rawValue, budget: &budget)
    }

    mutating func appendItems(
        _ items: [ToolbarAuditItem],
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        try appendCount(items.count, budget: &budget)
        for item in items {
            switch item {
            case .separator:
                try append(UInt8(0), budget: &budget)
            case .command(let command):
                try append(UInt8(1), budget: &budget)
                try append(command.rawValue, budget: &budget)
            }
        }
    }

    mutating func append(
        _ behavior: ToolbarAuditControlBehavior,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        try append(behavior.primaryActionID.rawValue, budget: &budget)
        switch behavior.secondary {
        case .none:
            try append(UInt8(0), budget: &budget)
        case .menu(let actions):
            try append(UInt8(1), budget: &budget)
            try appendCount(actions.count, budget: &budget)
            for action in actions {
                try append(action.id.rawValue, budget: &budget)
                try append(action.accessibility, budget: &budget)
            }
        }
    }

    mutating func appendOptional(
        _ shortcut: ToolbarAuditShortcut?,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        guard let shortcut else {
            try append(UInt8(0), budget: &budget)
            return
        }
        try append(UInt8(1), budget: &budget)
        try append(shortcut.key, budget: &budget)
        let modifiers = AccessibilityKeyboardModifier.allCases.filter(shortcut.modifiers.contains)
        try appendCount(modifiers.count, budget: &budget)
        for modifier in modifiers { try appendEnum(modifier, budget: &budget) }
        try append(shortcut.display, budget: &budget)
    }

    mutating func append(
        _ metadata: ToolbarAuditAXMetadata,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        try append(metadata.identifier.rawValue, budget: &budget)
        try appendEnum(metadata.role, budget: &budget)
        try append(metadata.label, budget: &budget)
        try appendOptional(metadata.value, budget: &budget)
        try append(metadata.hint, budget: &budget)
        switch metadata.isEnabled {
        case nil: try append(UInt8(0), budget: &budget)
        case false?: try append(UInt8(1), budget: &budget)
        case true?: try append(UInt8(2), budget: &budget)
        }
        try appendEnum(metadata.checkedState, budget: &budget)
        try appendEnum(metadata.selectedState, budget: &budget)
        try append(UInt8(metadata.isKeyboardFocusable ? 1 : 0), budget: &budget)
        let actions = AccessibilitySemanticActionKind.allCases.filter(metadata.actions.contains)
        try appendCount(actions.count, budget: &budget)
        for action in actions { try appendEnum(action, budget: &budget) }
    }

    mutating func append(
        _ availability: ToolbarAuditAvailability,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        switch availability {
        case .enabled:
            try append(UInt8(0), budget: &budget)
        case .disabled(let reason):
            try append(UInt8(1), budget: &budget)
            try append(reason.rawValue, budget: &budget)
        }
    }

    mutating func append(
        _ outcome: ToolbarAuditInteractionOutcome,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        switch outcome {
        case .invoked(let actionID):
            try append(UInt8(0), budget: &budget)
            try append(actionID.rawValue, budget: &budget)
        case .menuPresented(let actionIDs):
            try append(UInt8(1), budget: &budget)
            try appendCount(actionIDs.count, budget: &budget)
            for id in actionIDs { try append(id.rawValue, budget: &budget) }
        case .blocked:
            try append(UInt8(2), budget: &budget)
        case .noOp:
            try append(UInt8(3), budget: &budget)
        case .failed(let code):
            try append(UInt8(4), budget: &budget)
            try append(code.rawValue, budget: &budget)
        }
    }

    mutating func append(
        _ digest: ToolbarAuditArtifactDigest,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        try appendEnum(digest.algorithm, budget: &budget)
        try append(digest.lowercaseHex, budget: &budget)
    }

    mutating func appendOptional(
        _ digest: ToolbarAuditArtifactDigest?,
        budget: inout ToolbarAuditWorkBudget
    ) throws {
        guard let digest else {
            try append(UInt8(0), budget: &budget)
            return
        }
        try append(UInt8(1), budget: &budget)
        try append(digest, budget: &budget)
    }
}

private struct ToolbarAuditArchiveReader {
    let data: Data
    let limits: ToolbarAuditLimits
    private var offset = 0
    private var totalStringBytes = 0
    private(set) var hasCanonicalStrings = true

    init(data: Data, limits: ToolbarAuditLimits) {
        self.data = data
        self.limits = limits
    }

    var remainingCount: Int { data.count - offset }
    var isAtEnd: Bool { offset == data.count }

    mutating func readEvidence(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> ToolbarAuditEvidence {
        let contractRevision = ToolbarAuditRevision(rawValue: try readUInt64(budget: &budget))
        let surfaceCount = try readCount(
            maximum: ToolbarAuditLifecycleScenario.allCases.count,
            minimumRecordBytes: 24,
            budget: &budget
        )
        var surfaces: [ToolbarAuditSurfaceEvidence] = []
        surfaces.reserveCapacity(surfaceCount)
        for _ in 0..<surfaceCount {
            let scenario: ToolbarAuditLifecycleScenario = try readEnum(budget: &budget)
            let manifestRevision = ToolbarAuditRevision(rawValue: try readUInt64(budget: &budget))
            let items = try readItems(budget: &budget)
            let controlCount = try readCount(
                maximum: limits.maximumControls,
                minimumRecordBytes: 32,
                budget: &budget
            )
            var controls: [ToolbarAuditControlObservation] = []
            controls.reserveCapacity(controlCount)
            for _ in 0..<controlCount {
                let id = ToolbarAuditStableID(rawValue: try readString(budget: &budget))
                let command: ToolbarAuditCommand = try readEnum(budget: &budget)
                let behavior = try readBehavior(budget: &budget)
                let tooltip = try readOptionalString(budget: &budget)
                let shortcut = try readOptionalShortcut(budget: &budget)
                let accessibility = try readAX(budget: &budget)
                let availability = try readAvailability(budget: &budget)
                controls.append(
                    ToolbarAuditControlObservation(
                        id: id,
                        command: command,
                        behavior: behavior,
                        tooltip: tooltip,
                        shortcut: shortcut,
                        accessibility: accessibility,
                        availability: availability
                    )
                )
            }
            surfaces.append(
                ToolbarAuditSurfaceEvidence(
                    scenario: scenario,
                    manifestRevision: manifestRevision,
                    items: items,
                    controls: controls,
                    source: try readString(budget: &budget)
                )
            )
        }
        let interactionCount = try readCount(
            maximum: limits.maximumInteractionRecords,
            minimumRecordBytes: 24,
            budget: &budget
        )
        var interactions: [ToolbarAuditInteractionEvidence] = []
        interactions.reserveCapacity(interactionCount)
        for _ in 0..<interactionCount {
            interactions.append(
                ToolbarAuditInteractionEvidence(
                    scenario: try readEnum(budget: &budget),
                    controlID: ToolbarAuditStableID(rawValue: try readString(budget: &budget)),
                    actionID: ToolbarAuditStableID(rawValue: try readString(budget: &budget)),
                    invocation: try readEnum(budget: &budget),
                    outcome: try readOutcome(budget: &budget),
                    source: try readString(budget: &budget)
                )
            )
        }
        let screenshotCount = try readCount(
            maximum: limits.maximumScreenshots,
            minimumRecordBytes: 32,
            budget: &budget
        )
        var screenshots: [ToolbarAuditScreenshotEvidence] = []
        screenshots.reserveCapacity(screenshotCount)
        for _ in 0..<screenshotCount {
            screenshots.append(
                ToolbarAuditScreenshotEvidence(
                    context: try readEnum(budget: &budget),
                    manifestRevision: ToolbarAuditRevision(
                        rawValue: try readUInt64(budget: &budget)
                    ),
                    items: try readItems(budget: &budget),
                    screenshotDigest: try readDigest(budget: &budget),
                    accessibilitySidecarDigest: try readOptionalDigest(budget: &budget),
                    source: try readString(budget: &budget)
                )
            )
        }
        return ToolbarAuditEvidence(
            contractRevision: contractRevision,
            surfaces: surfaces,
            interactions: interactions,
            screenshots: screenshots
        )
    }

    mutating func readRaw(
        count: Int,
        budget: inout ToolbarAuditWorkBudget
    ) throws -> Data {
        guard count >= 0, count <= remainingCount else { throw ToolbarAuditError.invalidArchive }
        try budget.consume(count)
        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    mutating func readUInt8(budget: inout ToolbarAuditWorkBudget) throws -> UInt8 {
        let raw = try readRaw(count: 1, budget: &budget)
        return raw[raw.startIndex]
    }

    mutating func readUInt16(budget: inout ToolbarAuditWorkBudget) throws -> UInt16 {
        let raw = try readRaw(count: 2, budget: &budget)
        return raw.enumerated().reduce(0) { $0 | (UInt16($1.element) << UInt16($1.offset * 8)) }
    }

    mutating func readUInt32(budget: inout ToolbarAuditWorkBudget) throws -> UInt32 {
        let raw = try readRaw(count: 4, budget: &budget)
        return raw.enumerated().reduce(0) { $0 | (UInt32($1.element) << UInt32($1.offset * 8)) }
    }

    mutating func readUInt64(budget: inout ToolbarAuditWorkBudget) throws -> UInt64 {
        let raw = try readRaw(count: 8, budget: &budget)
        return raw.enumerated().reduce(0) { $0 | (UInt64($1.element) << UInt64($1.offset * 8)) }
    }

    mutating func readCount(
        maximum: Int,
        minimumRecordBytes: Int = 0,
        budget: inout ToolbarAuditWorkBudget
    ) throws -> Int {
        let count = Int(try readUInt32(budget: &budget))
        guard count <= maximum else {
            throw ToolbarAuditError.countLimitExceeded(kind: "archive-record", maximum: maximum)
        }
        if minimumRecordBytes > 0 {
            guard count <= remainingCount / minimumRecordBytes else {
                throw ToolbarAuditError.invalidArchive
            }
        }
        return count
    }

    mutating func readString(budget: inout ToolbarAuditWorkBudget) throws -> String {
        let count = try readCount(maximum: limits.maximumStringUTF8Bytes, budget: &budget)
        guard totalStringBytes <= limits.maximumTotalStringUTF8Bytes - count else {
            throw ToolbarAuditError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        totalStringBytes += count
        let raw = try readRaw(count: count, budget: &budget)
        guard let value = String(data: raw, encoding: .utf8) else {
            throw ToolbarAuditError.invalidArchive
        }
        if value != value.precomposedStringWithCanonicalMapping {
            hasCanonicalStrings = false
        }
        return value
    }

    mutating func readOptionalString(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> String? {
        switch try readUInt8(budget: &budget) {
        case 0: nil
        case 1: try readString(budget: &budget)
        default: throw ToolbarAuditError.invalidArchive
        }
    }

    mutating func readEnum<Value: RawRepresentable>(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> Value where Value.RawValue == String {
        guard let value = Value(rawValue: try readString(budget: &budget)) else {
            throw ToolbarAuditError.invalidArchive
        }
        return value
    }

    mutating func readItems(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> [ToolbarAuditItem] {
        let count = try readCount(
            maximum: limits.maximumManifestItems,
            minimumRecordBytes: 1,
            budget: &budget
        )
        var items: [ToolbarAuditItem] = []
        items.reserveCapacity(count)
        for _ in 0..<count {
            switch try readUInt8(budget: &budget) {
            case 0:
                items.append(.separator)
            case 1:
                let command: ToolbarAuditCommand = try readEnum(budget: &budget)
                items.append(.command(command))
            default:
                throw ToolbarAuditError.invalidArchive
            }
        }
        return items
    }

    mutating func readBehavior(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> ToolbarAuditControlBehavior {
        let primary = ToolbarAuditStableID(rawValue: try readString(budget: &budget))
        let secondary: ToolbarAuditSecondaryBehavior
        switch try readUInt8(budget: &budget) {
        case 0:
            secondary = .none
        case 1:
            let count = try readCount(
                maximum: limits.maximumSecondaryActions,
                budget: &budget
            )
            var actions: [ToolbarAuditSecondaryAction] = []
            actions.reserveCapacity(count)
            for _ in 0..<count {
                actions.append(
                    ToolbarAuditSecondaryAction(
                        id: ToolbarAuditStableID(rawValue: try readString(budget: &budget)),
                        accessibility: try readAX(budget: &budget)
                    )
                )
            }
            secondary = .menu(actions: actions)
        default:
            throw ToolbarAuditError.invalidArchive
        }
        return ToolbarAuditControlBehavior(primaryActionID: primary, secondary: secondary)
    }

    mutating func readOptionalShortcut(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> ToolbarAuditShortcut? {
        switch try readUInt8(budget: &budget) {
        case 0:
            return nil
        case 1:
            let key = try readString(budget: &budget)
            let count = try readCount(
                maximum: AccessibilityKeyboardModifier.allCases.count,
                budget: &budget
            )
            var modifiers: Set<AccessibilityKeyboardModifier> = []
            for _ in 0..<count {
                let modifier: AccessibilityKeyboardModifier = try readEnum(budget: &budget)
                guard modifiers.insert(modifier).inserted else {
                    throw ToolbarAuditError.invalidArchive
                }
            }
            return ToolbarAuditShortcut(
                key: key,
                modifiers: modifiers,
                display: try readString(budget: &budget)
            )
        default:
            throw ToolbarAuditError.invalidArchive
        }
    }

    mutating func readAX(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> ToolbarAuditAXMetadata {
        let identifier = ToolbarAuditStableID(rawValue: try readString(budget: &budget))
        let role: AccessibilitySemanticRole = try readEnum(budget: &budget)
        let label = try readString(budget: &budget)
        let value = try readOptionalString(budget: &budget)
        let hint = try readString(budget: &budget)
        let isEnabled: Bool?
        switch try readUInt8(budget: &budget) {
        case 0: isEnabled = nil
        case 1: isEnabled = false
        case 2: isEnabled = true
        default: throw ToolbarAuditError.invalidArchive
        }
        let checkedState: AccessibilityCheckedState = try readEnum(budget: &budget)
        let selectedState: AccessibilitySelectedState = try readEnum(budget: &budget)
        let isKeyboardFocusable: Bool
        switch try readUInt8(budget: &budget) {
        case 0: isKeyboardFocusable = false
        case 1: isKeyboardFocusable = true
        default: throw ToolbarAuditError.invalidArchive
        }
        let actionCount = try readCount(
            maximum: AccessibilitySemanticActionKind.allCases.count,
            budget: &budget
        )
        var actions: Set<AccessibilitySemanticActionKind> = []
        for _ in 0..<actionCount {
            let action: AccessibilitySemanticActionKind = try readEnum(budget: &budget)
            guard actions.insert(action).inserted else { throw ToolbarAuditError.invalidArchive }
        }
        return ToolbarAuditAXMetadata(
            identifier: identifier,
            role: role,
            label: label,
            value: value,
            hint: hint,
            isEnabled: isEnabled,
            checkedState: checkedState,
            selectedState: selectedState,
            isKeyboardFocusable: isKeyboardFocusable,
            actions: actions
        )
    }

    mutating func readAvailability(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> ToolbarAuditAvailability {
        switch try readUInt8(budget: &budget) {
        case 0: .enabled
        case 1: .disabled(reason: ToolbarAuditStableID(rawValue: try readString(budget: &budget)))
        default: throw ToolbarAuditError.invalidArchive
        }
    }

    mutating func readOutcome(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> ToolbarAuditInteractionOutcome {
        switch try readUInt8(budget: &budget) {
        case 0:
            .invoked(actionID: ToolbarAuditStableID(rawValue: try readString(budget: &budget)))
        case 1:
            .menuPresented(actionIDs: try readStableIDs(budget: &budget))
        case 2:
            .blocked
        case 3:
            .noOp
        case 4:
            .failed(code: ToolbarAuditStableID(rawValue: try readString(budget: &budget)))
        default:
            throw ToolbarAuditError.invalidArchive
        }
    }

    mutating func readDigest(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> ToolbarAuditArtifactDigest {
        ToolbarAuditArtifactDigest(
            algorithm: try readEnum(budget: &budget),
            lowercaseHex: try readString(budget: &budget)
        )
    }

    mutating func readOptionalDigest(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> ToolbarAuditArtifactDigest? {
        switch try readUInt8(budget: &budget) {
        case 0: nil
        case 1: try readDigest(budget: &budget)
        default: throw ToolbarAuditError.invalidArchive
        }
    }

    private mutating func readStableIDs(
        budget: inout ToolbarAuditWorkBudget
    ) throws -> [ToolbarAuditStableID] {
        let count = try readCount(maximum: limits.maximumSecondaryActions, budget: &budget)
        var values: [ToolbarAuditStableID] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(ToolbarAuditStableID(rawValue: try readString(budget: &budget)))
        }
        return values
    }
}

private func toolbarAuditControlRequirementLess(
    _ left: ToolbarAuditControlRequirement,
    _ right: ToolbarAuditControlRequirement
) -> Bool {
    let leftIndex = toolbarAuditCommandRank(left.command)
    let rightIndex = toolbarAuditCommandRank(right.command)
    if leftIndex != rightIndex { return leftIndex < rightIndex }
    return left.id < right.id
}

private func toolbarAuditControlObservationLess(
    _ left: ToolbarAuditControlObservation,
    _ right: ToolbarAuditControlObservation,
    budget: inout ToolbarAuditWorkBudget
) throws -> Bool {
    let leftIndex = toolbarAuditCommandRank(left.command)
    let rightIndex = toolbarAuditCommandRank(right.command)
    if leftIndex != rightIndex { return leftIndex < rightIndex }
    return try toolbarAuditCompareUTF8(left.id.rawValue, right.id.rawValue, budget: &budget) < 0
}

private func toolbarAuditLifecycleExpectationLess(
    _ left: ToolbarAuditLifecycleExpectation,
    _ right: ToolbarAuditLifecycleExpectation
) -> Bool {
    let leftScenario = toolbarAuditEnumRank(left.scenario)
    let rightScenario = toolbarAuditEnumRank(right.scenario)
    if leftScenario != rightScenario { return leftScenario < rightScenario }
    let leftCommand = toolbarAuditCommandRank(left.command)
    let rightCommand = toolbarAuditCommandRank(right.command)
    if leftCommand != rightCommand { return leftCommand < rightCommand }
    return left.actionID < right.actionID
}

private func toolbarAuditInteractionExpectationLess(
    _ left: ToolbarAuditInteractionExpectation,
    _ right: ToolbarAuditInteractionExpectation,
    budget: inout ToolbarAuditWorkBudget
) throws -> Bool {
    try toolbarAuditInteractionLess(
        scenario: left.scenario,
        controlID: left.controlID,
        actionID: left.actionID,
        invocation: left.invocation,
        thanScenario: right.scenario,
        controlID: right.controlID,
        actionID: right.actionID,
        invocation: right.invocation,
        budget: &budget
    )
}

private func toolbarAuditInteractionEvidenceLess(
    _ left: ToolbarAuditInteractionEvidence,
    _ right: ToolbarAuditInteractionEvidence,
    budget: inout ToolbarAuditWorkBudget
) throws -> Bool {
    try toolbarAuditInteractionLess(
        scenario: left.scenario,
        controlID: left.controlID,
        actionID: left.actionID,
        invocation: left.invocation,
        thanScenario: right.scenario,
        controlID: right.controlID,
        actionID: right.actionID,
        invocation: right.invocation,
        budget: &budget
    )
}

private func toolbarAuditInteractionLess(
    scenario: ToolbarAuditLifecycleScenario,
    controlID: ToolbarAuditStableID,
    actionID: ToolbarAuditStableID,
    invocation: ToolbarAuditInvocationKind,
    thanScenario otherScenario: ToolbarAuditLifecycleScenario,
    controlID otherControlID: ToolbarAuditStableID,
    actionID otherActionID: ToolbarAuditStableID,
    invocation otherInvocation: ToolbarAuditInvocationKind,
    budget: inout ToolbarAuditWorkBudget
) throws -> Bool {
    let scenarioRank = toolbarAuditEnumRank(scenario)
    let otherScenarioRank = toolbarAuditEnumRank(otherScenario)
    if scenarioRank != otherScenarioRank { return scenarioRank < otherScenarioRank }
    if controlID != otherControlID {
        return try toolbarAuditCompareUTF8(
            controlID.rawValue,
            otherControlID.rawValue,
            budget: &budget
        ) < 0
    }
    if actionID != otherActionID {
        return try toolbarAuditCompareUTF8(
            actionID.rawValue,
            otherActionID.rawValue,
            budget: &budget
        ) < 0
    }
    return toolbarAuditEnumRank(invocation) < toolbarAuditEnumRank(otherInvocation)
}

private func toolbarAuditFindingLess(
    _ left: ToolbarAuditFinding,
    _ right: ToolbarAuditFinding,
    budget: inout ToolbarAuditWorkBudget
) throws -> Bool {
    if left.severity != right.severity { return left.severity > right.severity }
    let codeComparison = try toolbarAuditCompareUTF8(
        left.code.rawValue,
        right.code.rawValue,
        budget: &budget
    )
    if codeComparison != 0 { return codeComparison < 0 }
    return try toolbarAuditCompareUTF8(left.id.rawValue, right.id.rawValue, budget: &budget) < 0
}

private func toolbarAuditCommandRank(_ command: ToolbarAuditCommand) -> Int {
    ToolbarConfiguration.Command.allCases.firstIndex(of: command) ?? Int.max
}

private func toolbarAuditEnumRank<Value: CaseIterable & Equatable>(_ value: Value) -> Int {
    Value.allCases.enumerated().first { $0.element == value }?.offset ?? Int.max
}

private func toolbarAuditIsBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func toolbarAuditLengthPrefixed(_ value: String) -> String {
    String(value.utf8.count) + ":" + value
}

private func toolbarAuditFindingDiscriminator(_ components: String...) -> String {
    components.map(toolbarAuditLengthPrefixed).joined()
}

private func toolbarAuditSeparatorBoundaries(_ items: [ToolbarAuditItem]) -> [Int] {
    var commandCount = 0
    var boundaries: [Int] = []
    for item in items {
        switch item {
        case .command:
            commandCount += 1
        case .separator:
            boundaries.append(commandCount)
        }
    }
    return boundaries
}

private func toolbarAuditOutcomePerformsAction(_ outcome: ToolbarAuditInteractionOutcome) -> Bool {
    switch outcome {
    case .invoked, .menuPresented:
        true
    case .blocked, .noOp, .failed:
        false
    }
}

private func toolbarAuditAXMetadataMatchesRequirement(
    _ observation: ToolbarAuditAXMetadata,
    requirement: ToolbarAuditAXMetadata
) -> Bool {
    observation.identifier == requirement.identifier
        && observation.role == requirement.role
        && observation.label == requirement.label
        && observation.value == requirement.value
        && observation.hint == requirement.hint
        && observation.checkedState == requirement.checkedState
        && observation.selectedState == requirement.selectedState
        && observation.isKeyboardFocusable == requirement.isKeyboardFocusable
        && observation.actions == requirement.actions
}

private func toolbarAuditUnorderedEqual<Value: Hashable>(
    _ left: [Value],
    _ right: [Value]
) -> Bool {
    guard left.count == right.count else { return false }
    var counts: [Value: Int] = [:]
    for value in left { counts[value, default: 0] += 1 }
    for value in right {
        guard let count = counts[value], count > 0 else { return false }
        if count == 1 {
            counts.removeValue(forKey: value)
        } else {
            counts[value] = count - 1
        }
    }
    return counts.isEmpty
}

private func toolbarAuditStableSorted<Value>(
    _ values: [Value],
    by areInIncreasingOrder: (Value, Value, inout ToolbarAuditWorkBudget) throws -> Bool,
    budget: inout ToolbarAuditWorkBudget
) throws -> [Value] {
    guard values.count > 1 else {
        try budget.consume(values.count)
        return values
    }
    var source = values
    var destination = values
    var width = 1
    while width < values.count {
        var start = 0
        while start < values.count {
            let middle = min(start + width, values.count)
            let end = min(middle + width, values.count)
            var left = start
            var right = middle
            var output = start
            while left < middle || right < end {
                try budget.consume()
                let takeLeft: Bool
                if right >= end {
                    takeLeft = true
                } else if left >= middle {
                    takeLeft = false
                } else {
                    takeLeft = try !areInIncreasingOrder(source[right], source[left], &budget)
                }
                if takeLeft {
                    destination[output] = source[left]
                    left += 1
                } else {
                    destination[output] = source[right]
                    right += 1
                }
                output += 1
            }
            start = end
        }
        swap(&source, &destination)
        let (nextWidth, overflow) = width.multipliedReportingOverflow(by: 2)
        width = overflow ? values.count : nextWidth
    }
    return source
}

private func toolbarAuditHashUnordered<Value: Hashable>(
    _ values: [Value],
    into hasher: inout Hasher
) {
    hasher.combine(values.count)
    var aggregate = 0
    for value in values {
        var itemHasher = Hasher()
        itemHasher.combine(value)
        aggregate ^= itemHasher.finalize()
    }
    hasher.combine(aggregate)
}

private func toolbarAuditCompareUTF8(_ left: String, _ right: String) -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        switch (leftIterator.next(), rightIterator.next()) {
        case (nil, nil):
            return 0
        case (nil, _?):
            return -1
        case (_?, nil):
            return 1
        case (let leftByte?, let rightByte?):
            if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
        }
    }
}

private func toolbarAuditCompareUTF8(
    _ left: String,
    _ right: String,
    budget: inout ToolbarAuditWorkBudget
) throws -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        let leftByte = leftIterator.next()
        let rightByte = rightIterator.next()
        if leftByte != nil || rightByte != nil {
            try budget.consume()
        }
        switch (leftByte, rightByte) {
        case (nil, nil):
            return 0
        case (nil, _?):
            return -1
        case (_?, nil):
            return 1
        case (let leftByte?, let rightByte?):
            if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
        }
    }
}

private func toolbarAuditFNV1a64(
    _ data: Data,
    budget: inout ToolbarAuditWorkBudget
) throws -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
        try budget.consume()
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}

private func toolbarAuditEqualData(
    _ left: Data,
    _ right: Data,
    budget: inout ToolbarAuditWorkBudget
) throws -> Bool {
    guard left.count == right.count else { return false }
    for (leftByte, rightByte) in zip(left, right) {
        try budget.consume()
        if leftByte != rightByte { return false }
    }
    return true
}
