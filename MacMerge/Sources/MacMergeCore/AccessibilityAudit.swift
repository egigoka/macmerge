import Foundation

enum AccessibilityAuditTestHooks {
    @TaskLocal static var canonicalArchiveComparisonCheckpoint: (@Sendable (Int) -> Void)?
}

/// Caller-owned stable identity. This model never derives identity from labels, positions, or objects.
public struct AccessibilityStableID: RawRepresentable, Comparable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        accessibilityCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

public struct AccessibilityContrastEvidenceToken: RawRepresentable, Comparable, Equatable, Hashable,
    Sendable
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        accessibilityCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

public struct AccessibilityDifferentiateWithoutColorEvidenceToken: RawRepresentable, Comparable,
    Equatable, Hashable, Sendable
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        accessibilityCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

public struct AccessibilityLocalizationExpansionEvidenceToken: RawRepresentable, Comparable,
    Equatable, Hashable, Sendable
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        accessibilityCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

public enum AccessibilitySemanticRole: String, CaseIterable, Equatable, Hashable, Sendable {
    case application
    case window
    case dialog
    case alert
    case group
    case toolbar
    case button
    case toggle
    case checkBox
    case radioButton
    case link
    case textField
    case searchField
    case comboBox
    case menu
    case menuItem
    case tabList
    case tab
    case list
    case listItem
    case table
    case row
    case cell
    case tree
    case treeItem
    case slider
    case stepper
    case progressIndicator
    case image
    case staticText
    case heading
    case separator
    case command
    case customControl
    case presentation

    fileprivate var isControl: Bool {
        switch self {
        case .button, .toggle, .checkBox, .radioButton, .link, .textField, .searchField,
            .comboBox, .menuItem, .tab, .slider, .stepper, .command, .customControl:
            true
        default:
            false
        }
    }

    fileprivate var supportsCheckedState: Bool {
        self == .toggle || self == .checkBox || self == .radioButton || self == .menuItem
    }

    fileprivate var requiresCheckedState: Bool {
        self == .toggle || self == .checkBox || self == .radioButton
    }

    fileprivate var supportsSelectedState: Bool {
        self == .radioButton || self == .menuItem || self == .tab || self == .listItem
            || self == .row || self == .cell || self == .treeItem
    }

    fileprivate var supportsKeyboardFocus: Bool {
        switch self {
        case .button, .toggle, .checkBox, .radioButton, .link, .textField, .searchField,
            .comboBox, .menu, .menuItem, .tab, .list, .listItem, .table, .row, .cell,
            .tree, .treeItem, .slider, .stepper, .command, .customControl:
            true
        default:
            false
        }
    }

    fileprivate var allowedActions: Set<AccessibilitySemanticActionKind> {
        let custom: Set<AccessibilitySemanticActionKind> = [.custom]
        switch self {
        case .window, .dialog, .alert:
            return [.dismiss, .custom]
        case .button, .link, .tab, .listItem, .row, .cell, .treeItem, .command:
            return [.activate, .custom]
        case .toggle, .checkBox, .radioButton:
            return [.toggle, .custom]
        case .textField, .searchField:
            return [.setValue, .custom]
        case .comboBox:
            return [.setValue, .showMenu, .custom]
        case .menu:
            return [.showMenu, .dismiss, .custom]
        case .menuItem:
            return [.activate, .toggle, .showMenu, .custom]
        case .slider:
            return [.increment, .decrement, .setValue, .custom]
        case .stepper:
            return [.increment, .decrement, .custom]
        case .customControl:
            return Set(AccessibilitySemanticActionKind.allCases)
        case .application, .group, .toolbar, .tabList, .list, .table, .tree,
            .progressIndicator, .image, .staticText, .heading:
            return custom
        case .separator, .presentation:
            return []
        }
    }

    fileprivate var allowedContentFields: Set<AccessibilitySemanticContentField> {
        switch self {
        case .presentation:
            return []
        case .separator:
            return [.label]
        case .application, .window, .dialog, .alert, .group, .toolbar, .menu, .tabList,
            .list, .table, .tree:
            return [.label]
        case .button, .link, .menuItem, .tab, .image, .command:
            return [.label, .hint]
        case .listItem, .row, .cell, .treeItem, .staticText, .heading, .progressIndicator:
            return Set(AccessibilitySemanticContentField.allCases)
        case .toggle, .checkBox, .radioButton:
            return [.label, .hint]
        case .textField, .searchField, .comboBox, .slider, .stepper, .customControl:
            return Set(AccessibilitySemanticContentField.allCases)
        }
    }

    fileprivate func requiredActions(
        checkedState: AccessibilityCheckedState
    ) -> Set<AccessibilitySemanticActionKind> {
        switch self {
        case .button, .link, .tab, .command:
            return [.activate]
        case .toggle, .checkBox, .radioButton:
            return [.toggle]
        case .textField, .searchField:
            return [.setValue]
        case .comboBox:
            return [.setValue, .showMenu]
        case .menuItem:
            return checkedState == .notApplicable ? [.activate] : [.toggle]
        case .slider:
            return [.increment, .decrement, .setValue]
        case .stepper:
            return [.increment, .decrement]
        case .application, .window, .dialog, .alert, .group, .toolbar, .listItem, .menu,
            .tabList, .list, .table, .row, .cell, .tree, .treeItem, .progressIndicator,
            .image, .staticText, .heading, .separator, .customControl, .presentation:
            return []
        }
    }

}

private enum AccessibilitySemanticContentField: String, CaseIterable, Hashable {
    case label
    case value
    case hint
}

private struct AccessibilityLocalizationSubject: Hashable {
    let id: AccessibilityStableID
    let field: AccessibilityLocalizedField
}

public enum AccessibilityCheckedState: String, CaseIterable, Equatable, Hashable, Sendable {
    case notApplicable
    case off
    case on
    case mixed
}

public enum AccessibilitySelectedState: String, CaseIterable, Equatable, Hashable, Sendable {
    case notApplicable
    case notSelected
    case selected
}

public enum AccessibilitySemanticActionKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case activate
    case toggle
    case increment
    case decrement
    case setValue
    case showMenu
    case dismiss
    case custom
}

public struct AccessibilitySemanticAction: Equatable, Hashable, Identifiable, Sendable {
    public let id: AccessibilityStableID
    public let kind: AccessibilitySemanticActionKind
    public let label: String?
    public let localizationExpansionEvidenceTokens: [AccessibilityLocalizationExpansionEvidenceToken]

    public init(
        id: AccessibilityStableID,
        kind: AccessibilitySemanticActionKind,
        label: String? = nil,
        localizationExpansionEvidenceTokens:
            [AccessibilityLocalizationExpansionEvidenceToken] = []
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.localizationExpansionEvidenceTokens = localizationExpansionEvidenceTokens
    }
}

public enum AccessibilityKeyboardModifier: String, CaseIterable, Equatable, Hashable, Sendable {
    case command
    case control
    case option
    case shift
    case function
}

public struct AccessibilityKeyboardShortcut: Equatable, Hashable, Identifiable, Sendable {
    public let id: AccessibilityStableID
    public let key: String
    public let modifiers: Set<AccessibilityKeyboardModifier>
    public let actionID: AccessibilityStableID
    public let discoverabilityTitle: String?
    public let localizationExpansionEvidenceTokens: [AccessibilityLocalizationExpansionEvidenceToken]

    public init(
        id: AccessibilityStableID,
        key: String,
        modifiers: Set<AccessibilityKeyboardModifier> = [],
        actionID: AccessibilityStableID,
        discoverabilityTitle: String? = nil,
        localizationExpansionEvidenceTokens:
            [AccessibilityLocalizationExpansionEvidenceToken] = []
    ) {
        self.id = id
        self.key = key.precomposedStringWithCanonicalMapping
        self.modifiers = modifiers
        self.actionID = actionID
        self.discoverabilityTitle = discoverabilityTitle
        self.localizationExpansionEvidenceTokens = localizationExpansionEvidenceTokens
    }

    public var canonicalChord: String {
        let modifiers = AccessibilityKeyboardModifier.allCases.filter(modifiers.contains).map(
            \.rawValue
        )
        let key = AccessibilityAuditValidation.canonicalShortcutKey(key)
        return modifiers.joined(separator: "+") + ":" + String(key.utf8.count) + ":" + key
    }
}

public struct AccessibilitySemanticElement: Equatable, Identifiable, Sendable {
    public let id: AccessibilityStableID
    public let parentID: AccessibilityStableID?
    public let role: AccessibilitySemanticRole
    public let label: String?
    public let value: String?
    public let hint: String?
    public let isEnabled: Bool
    public let checkedState: AccessibilityCheckedState
    public let selectedState: AccessibilitySelectedState
    public let isHiddenFromAssistiveTechnology: Bool
    public let isKeyboardFocusable: Bool
    public let actions: [AccessibilitySemanticAction]
    public let keyboardShortcuts: [AccessibilityKeyboardShortcut]
    public let requiresContrastEvidence: Bool
    public let contrastEvidenceTokens: [AccessibilityContrastEvidenceToken]
    public let usesColorToConveyMeaning: Bool
    public let differentiateWithoutColorEvidenceTokens: [AccessibilityDifferentiateWithoutColorEvidenceToken]
    public let requiresLocalizationExpansionEvidence: Bool
    public let localizationExpansionEvidenceTokens: [AccessibilityLocalizationExpansionEvidenceToken]

    public init(
        id: AccessibilityStableID,
        parentID: AccessibilityStableID? = nil,
        role: AccessibilitySemanticRole,
        label: String? = nil,
        value: String? = nil,
        hint: String? = nil,
        isEnabled: Bool = true,
        checkedState: AccessibilityCheckedState = .notApplicable,
        selectedState: AccessibilitySelectedState = .notApplicable,
        isHiddenFromAssistiveTechnology: Bool = false,
        isKeyboardFocusable: Bool = false,
        actions: [AccessibilitySemanticAction] = [],
        keyboardShortcuts: [AccessibilityKeyboardShortcut] = [],
        requiresContrastEvidence: Bool = false,
        contrastEvidenceTokens: [AccessibilityContrastEvidenceToken] = [],
        usesColorToConveyMeaning: Bool = false,
        differentiateWithoutColorEvidenceTokens:
            [AccessibilityDifferentiateWithoutColorEvidenceToken] = [],
        requiresLocalizationExpansionEvidence: Bool = false,
        localizationExpansionEvidenceTokens:
            [AccessibilityLocalizationExpansionEvidenceToken] = []
    ) {
        self.id = id
        self.parentID = parentID
        self.role = role
        self.label = label
        self.value = value
        self.hint = hint
        self.isEnabled = isEnabled
        self.checkedState = checkedState
        self.selectedState = selectedState
        self.isHiddenFromAssistiveTechnology = isHiddenFromAssistiveTechnology
        self.isKeyboardFocusable = isKeyboardFocusable
        self.actions = actions
        self.keyboardShortcuts = keyboardShortcuts
        self.requiresContrastEvidence = requiresContrastEvidence
        self.contrastEvidenceTokens = contrastEvidenceTokens
        self.usesColorToConveyMeaning = usesColorToConveyMeaning
        self.differentiateWithoutColorEvidenceTokens =
            differentiateWithoutColorEvidenceTokens
        self.requiresLocalizationExpansionEvidence = requiresLocalizationExpansionEvidence
        self.localizationExpansionEvidenceTokens = localizationExpansionEvidenceTokens
    }

    fileprivate func populatedLocalizedFields(
        budget: inout AccessibilityWorkBudget
    ) throws -> Set<AccessibilityLocalizedField> {
        var fields: Set<AccessibilityLocalizedField> = []
        if try !AccessibilityAuditValidation.isBlank(label, budget: &budget) {
            fields.insert(.label)
        }
        if try !AccessibilityAuditValidation.isBlank(value, budget: &budget) {
            fields.insert(.value)
        }
        if try !AccessibilityAuditValidation.isBlank(hint, budget: &budget) {
            fields.insert(.hint)
        }
        return fields
    }

    fileprivate func supportsContrastSurface(
        _ surface: AccessibilityContrastSurface,
        budget: inout AccessibilityWorkBudget
    ) throws -> Bool {
        switch surface {
        case .text:
            return try !AccessibilityAuditValidation.isBlank(label, budget: &budget)
                || !AccessibilityAuditValidation.isBlank(value, budget: &budget)
        case .largeText:
            return try !AccessibilityAuditValidation.isBlank(label, budget: &budget)
                || !AccessibilityAuditValidation.isBlank(value, budget: &budget)
        case .graphicalObject:
            return role == .image || role.isControl || role == .progressIndicator
                || role == .separator
        case .focusIndicator:
            return isKeyboardFocusable
        case .custom:
            return role == .customControl
        }
    }
}

public enum AccessibilityAnnouncementKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case status
    case update
    case confirmation
    case warning
    case error
}

/// Declarative announcement contract. Presence does not establish that a runtime delivered it.
public struct AccessibilityAnnouncement: Equatable, Identifiable, Sendable {
    public let id: AccessibilityStableID
    public let kind: AccessibilityAnnouncementKind
    public let message: String
    public let relatedElementID: AccessibilityStableID?
    public let triggerActionID: AccessibilityStableID?
    public let localizationExpansionEvidenceTokens: [AccessibilityLocalizationExpansionEvidenceToken]

    public init(
        id: AccessibilityStableID,
        kind: AccessibilityAnnouncementKind,
        message: String,
        relatedElementID: AccessibilityStableID? = nil,
        triggerActionID: AccessibilityStableID? = nil,
        localizationExpansionEvidenceTokens:
            [AccessibilityLocalizationExpansionEvidenceToken] = []
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.relatedElementID = relatedElementID
        self.triggerActionID = triggerActionID
        self.localizationExpansionEvidenceTokens = localizationExpansionEvidenceTokens
    }
}

public enum AccessibilityEvidenceOrigin: String, CaseIterable, Equatable, Hashable, Sendable {
    case designSpecification
    case automatedMeasurement
    case manualMeasurement
    case callerAssertion
}

public enum AccessibilityContrastSurface: String, CaseIterable, Equatable, Hashable, Sendable {
    case text
    case largeText
    case graphicalObject
    case focusIndicator
    case custom
}

/// Caller-supplied contrast measurement in thousandths, avoiding floating-point wire ambiguity.
public struct AccessibilityContrastEvidence: Equatable, Hashable, Identifiable, Sendable {
    public var id: AccessibilityContrastEvidenceToken { token }

    public let token: AccessibilityContrastEvidenceToken
    public let subjectID: AccessibilityStableID
    public let surface: AccessibilityContrastSurface
    public let measuredRatioThousandths: Int
    public let requiredRatioThousandths: Int
    public let origin: AccessibilityEvidenceOrigin
    public let source: String

    public init(
        token: AccessibilityContrastEvidenceToken,
        subjectID: AccessibilityStableID,
        surface: AccessibilityContrastSurface,
        measuredRatioThousandths: Int,
        requiredRatioThousandths: Int,
        origin: AccessibilityEvidenceOrigin,
        source: String
    ) {
        self.token = token
        self.subjectID = subjectID
        self.surface = surface
        self.measuredRatioThousandths = measuredRatioThousandths
        self.requiredRatioThousandths = requiredRatioThousandths
        self.origin = origin
        self.source = source.precomposedStringWithCanonicalMapping
    }
}

public enum AccessibilityNonColorCue: String, CaseIterable, Equatable, Hashable, Sendable {
    case text
    case icon
    case shape
    case pattern
    case position
    case sound
    case haptic
}

public struct AccessibilityDifferentiateWithoutColorEvidence: Equatable, Hashable, Identifiable,
    Sendable
{
    public var id: AccessibilityDifferentiateWithoutColorEvidenceToken { token }

    public let token: AccessibilityDifferentiateWithoutColorEvidenceToken
    public let meaning: String
    public let nonColorCues: Set<AccessibilityNonColorCue>
    public let origin: AccessibilityEvidenceOrigin
    public let source: String

    public init(
        token: AccessibilityDifferentiateWithoutColorEvidenceToken,
        meaning: String,
        nonColorCues: Set<AccessibilityNonColorCue>,
        origin: AccessibilityEvidenceOrigin,
        source: String
    ) {
        self.token = token
        self.meaning = meaning.precomposedStringWithCanonicalMapping
        self.nonColorCues = nonColorCues
        self.origin = origin
        self.source = source.precomposedStringWithCanonicalMapping
    }
}

public enum AccessibilityLocalizedField: String, CaseIterable, Equatable, Hashable, Sendable {
    case label
    case value
    case hint
    case actionLabel
    case shortcutTitle
    case announcement
}

public enum AccessibilityLocalizationExpansionOutcome: String, CaseIterable, Equatable, Hashable,
    Sendable
{
    case fits
    case wraps
    case scrolls
    case truncates
    case unknown
}

/// Caller-supplied localization expansion observation for one semantic subject and field.
public struct AccessibilityLocalizationExpansionEvidence: Equatable, Hashable, Identifiable,
    Sendable
{
    public var id: AccessibilityLocalizationExpansionEvidenceToken { token }

    public let token: AccessibilityLocalizationExpansionEvidenceToken
    public let subjectID: AccessibilityStableID
    public let field: AccessibilityLocalizedField
    public let localeIdentifier: String
    public let baselineText: String
    public let expandedText: String
    public let outcome: AccessibilityLocalizationExpansionOutcome
    public let origin: AccessibilityEvidenceOrigin
    public let source: String

    public init(
        token: AccessibilityLocalizationExpansionEvidenceToken,
        subjectID: AccessibilityStableID,
        field: AccessibilityLocalizedField,
        localeIdentifier: String,
        baselineText: String,
        expandedText: String,
        outcome: AccessibilityLocalizationExpansionOutcome,
        origin: AccessibilityEvidenceOrigin,
        source: String
    ) {
        self.token = token
        self.subjectID = subjectID
        self.field = field
        self.localeIdentifier = localeIdentifier.precomposedStringWithCanonicalMapping
        self.baselineText = baselineText.precomposedStringWithCanonicalMapping
        self.expandedText = expandedText.precomposedStringWithCanonicalMapping
        self.outcome = outcome
        self.origin = origin
        self.source = source.precomposedStringWithCanonicalMapping
    }
}

/// Persistable evidence only. Evidence values remain caller assertions; decoding does not verify them.
public struct AccessibilityAuditEvidence: Equatable, Sendable {
    public let contrast: [AccessibilityContrastEvidence]
    public let differentiateWithoutColor: [AccessibilityDifferentiateWithoutColorEvidence]
    public let localizationExpansion: [AccessibilityLocalizationExpansionEvidence]

    public init(
        contrast: [AccessibilityContrastEvidence] = [],
        differentiateWithoutColor: [AccessibilityDifferentiateWithoutColorEvidence] = [],
        localizationExpansion: [AccessibilityLocalizationExpansionEvidence] = []
    ) {
        self.contrast = contrast
        self.differentiateWithoutColor = differentiateWithoutColor
        self.localizationExpansion = localizationExpansion
    }

    public static func == (left: Self, right: Self) -> Bool {
        accessibilityUnorderedEqual(left.contrast, right.contrast)
            && accessibilityUnorderedEqual(
                left.differentiateWithoutColor,
                right.differentiateWithoutColor
            )
            && accessibilityUnorderedEqual(
                left.localizationExpansion,
                right.localizationExpansion
            )
    }

    public func encodedData(limits: AccessibilityAuditLimits = .default) throws -> Data {
        try AccessibilityAuditEvidenceArchive.encode(self, limits: limits)
    }

    public static func decode(
        from data: Data,
        limits: AccessibilityAuditLimits = .default
    ) throws -> Self {
        try AccessibilityAuditEvidenceArchive.decode(data, limits: limits)
    }
}

/// UI-independent semantic input. It contains no platform accessibility objects or runtime probes.
public struct AccessibilityCommandControlSnapshot: Equatable, Sendable {
    public let id: AccessibilityStableID
    public let rootElementID: AccessibilityStableID
    public let elements: [AccessibilitySemanticElement]
    public let focusOrder: [AccessibilityStableID]
    public let announcements: [AccessibilityAnnouncement]
    public let evidence: AccessibilityAuditEvidence

    public init(
        id: AccessibilityStableID,
        rootElementID: AccessibilityStableID,
        elements: [AccessibilitySemanticElement],
        focusOrder: [AccessibilityStableID] = [],
        announcements: [AccessibilityAnnouncement] = [],
        evidence: AccessibilityAuditEvidence = AccessibilityAuditEvidence()
    ) {
        self.id = id
        self.rootElementID = rootElementID
        self.elements = elements
        self.focusOrder = focusOrder
        self.announcements = announcements
        self.evidence = evidence
    }
}

public struct AccessibilityAuditLimits: Equatable, Sendable {
    public static let `default` = AccessibilityAuditLimits()

    public let maximumElements: Int
    public let maximumActions: Int
    public let maximumKeyboardShortcuts: Int
    public let maximumAnnouncements: Int
    public let maximumEvidenceRecordsPerKind: Int
    public let maximumEvidenceReferences: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumWorkUnits: Int
    public let maximumIssues: Int
    public let maximumExactSnapshotUTF8Bytes: Int
    public let maximumEvidenceArchiveBytes: Int

    public init(
        maximumElements: Int = 10_000,
        maximumActions: Int = 40_000,
        maximumKeyboardShortcuts: Int = 40_000,
        maximumAnnouncements: Int = 10_000,
        maximumEvidenceRecordsPerKind: Int = 40_000,
        maximumEvidenceReferences: Int = 120_000,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumWorkUnits: Int = 64 * 1_024 * 1_024,
        maximumIssues: Int = 100_000,
        maximumExactSnapshotUTF8Bytes: Int = 32 * 1_024 * 1_024,
        maximumEvidenceArchiveBytes: Int = 32 * 1_024 * 1_024
    ) {
        self.maximumElements = maximumElements
        self.maximumActions = maximumActions
        self.maximumKeyboardShortcuts = maximumKeyboardShortcuts
        self.maximumAnnouncements = maximumAnnouncements
        self.maximumEvidenceRecordsPerKind = maximumEvidenceRecordsPerKind
        self.maximumEvidenceReferences = maximumEvidenceReferences
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumIssues = maximumIssues
        self.maximumExactSnapshotUTF8Bytes = maximumExactSnapshotUTF8Bytes
        self.maximumEvidenceArchiveBytes = maximumEvidenceArchiveBytes
    }
}

public enum AccessibilityAuditSeverity: String, CaseIterable, Comparable, Equatable, Hashable,
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

public enum AccessibilityAuditIssueCode: String, CaseIterable, Equatable, Hashable, Sendable {
    case invalidStableIdentifier
    case duplicateStableIdentifier
    case missingRootElement
    case rootHasParent
    case unknownParent
    case hierarchyCycle
    case hierarchyNotRooted
    case emptySemanticText
    case missingControlLabel
    case semanticContentRoleMismatch
    case hiddenControlHasActions
    case hiddenElementIsFocusable
    case keyboardFocusRoleMismatch
    case checkedStateRoleMismatch
    case selectedStateRoleMismatch
    case missingRequiredState
    case actionRoleMismatch
    case missingRequiredAction
    case duplicateActionKind
    case duplicateCustomActionLabel
    case invalidKeyboardShortcut
    case shortcutTargetsUnknownAction
    case duplicateKeyboardShortcut
    case unmodifiedKeyboardShortcut
    case keyboardAccessMissing
    case focusOrderContainsDuplicate
    case focusOrderTargetsUnknownElement
    case nonFocusableElementInFocusOrder
    case disabledElementInFocusOrder
    case focusableElementMissingFromFocusOrder
    case announcementMessageMissing
    case announcementTargetsUnknownElement
    case announcementTargetsUnknownAction
    case duplicateEvidenceToken
    case requiredContrastEvidenceMissing
    case contrastEvidenceReferenceMissing
    case contrastEvidenceSurfaceMismatch
    case contrastBelowRequiredRatio
    case invalidContrastRatio
    case differentiateWithoutColorEvidenceMissing
    case differentiateWithoutColorReferenceMissing
    case colorOnlyDifferentiation
    case localizationExpansionEvidenceMissing
    case localizationExpansionReferenceMissing
    case localizationSubjectMissing
    case localizationTruncates
    case localizationOutcomeUnknown
    case orphanEvidence
    case invalidEvidence
}

public struct AccessibilityAuditIssue: Equatable, Identifiable, Sendable {
    public struct ID: RawRepresentable, Comparable, Equatable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            accessibilityCompareUTF8(left.rawValue, right.rawValue) < 0
        }

        fileprivate init(
            code: AccessibilityAuditIssueCode,
            subjectComponents: [String]
        ) {
            var value = accessibilityLengthPrefixed(code.rawValue)
            for component in subjectComponents {
                value.append(accessibilityLengthPrefixed(component))
            }
            rawValue = value
        }
    }

    public let id: ID
    public let severity: AccessibilityAuditSeverity
    public let code: AccessibilityAuditIssueCode
    public let subject: String?
    public let message: String

    fileprivate init(
        severity: AccessibilityAuditSeverity,
        code: AccessibilityAuditIssueCode,
        subject: String?,
        identityComponents: [String]? = nil,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.subject = subject
        self.message = message
        id = ID(
            code: code,
            subjectComponents: identityComponents ?? subject.map { [$0] } ?? []
        )
    }
}

public struct AccessibilityAuditReport: Equatable, Sendable {
    /// Audit scope is intentionally narrower than platform or assistive-technology conformance.
    public static let scopeStatement =
        "Static checks of caller-supplied semantic snapshot and evidence only; not runtime accessibility compliance."

    public let formatVersion: Int
    public let snapshotID: AccessibilityStableID
    public let issues: [AccessibilityAuditIssue]

    public var highestSeverity: AccessibilityAuditSeverity? { issues.first?.severity }
    public var containsErrors: Bool { issues.contains { $0.severity == .error } }

    fileprivate init(
        formatVersion: Int,
        snapshotID: AccessibilityStableID,
        issues: [AccessibilityAuditIssue]
    ) {
        self.formatVersion = formatVersion
        self.snapshotID = snapshotID
        self.issues = issues
    }
}

public enum AccessibilityAuditError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimit(name: String, value: Int, maximum: Int)
    case countLimitExceeded(kind: String, maximum: Int)
    case stringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximum: Int)
    case issueLimitExceeded(maximum: Int)
    case exactSnapshotTooLarge(maximumUTF8Bytes: Int)
    case evidenceArchiveTooLarge(maximumBytes: Int)
    case invalidEvidence(field: String)
    case invalidEvidenceArchive
    case unsupportedEvidenceArchiveVersion(Int)
    case evidenceArchiveChecksumMismatch
    case nonCanonicalEvidenceArchive

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value, let maximum):
            "Accessibility-audit limit \(name) is invalid (\(value)); expected 0...\(maximum)."
        case .countLimitExceeded(let kind, let maximum):
            "Accessibility snapshot exceeds the \(maximum)-\(kind) limit."
        case .stringTooLarge(let field, let maximumUTF8Bytes):
            "Accessibility field \(field) exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .totalStringsTooLarge(let maximumUTF8Bytes):
            "Accessibility snapshot strings exceed the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .workLimitExceeded(let maximum):
            "Accessibility audit exceeds the \(maximum)-unit work limit."
        case .issueLimitExceeded(let maximum):
            "Accessibility audit exceeds the \(maximum)-issue limit."
        case .exactSnapshotTooLarge(let maximumUTF8Bytes):
            "Exact accessibility snapshot exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .evidenceArchiveTooLarge(let maximumBytes):
            "Accessibility evidence archive exceeds the \(maximumBytes)-byte limit."
        case .invalidEvidence(let field):
            "Accessibility evidence is invalid at \(field)."
        case .invalidEvidenceArchive:
            "Accessibility evidence archive has invalid framing or field data."
        case .unsupportedEvidenceArchiveVersion(let version):
            "Unsupported accessibility evidence archive version: \(version)."
        case .evidenceArchiveChecksumMismatch:
            "Accessibility evidence archive checksum does not match its payload."
        case .nonCanonicalEvidenceArchive:
            "Accessibility evidence archive is valid but not in canonical wire form."
        }
    }
}

/// Deterministic semantic checks and exact snapshot rendering. No AX, AppKit, or runtime calls occur.
public enum AccessibilityAudit: Sendable {
    public static let exactSnapshotFormatVersion = 2

    public static func audit(
        _ snapshot: AccessibilityCommandControlSnapshot,
        limits: AccessibilityAuditLimits = .default
    ) throws -> AccessibilityAuditReport {
        var context = try AccessibilityAuditContext(snapshot: snapshot, limits: limits)
        try context.run()
        let issues = try context.sortedIssues()
        return AccessibilityAuditReport(
            formatVersion: exactSnapshotFormatVersion,
            snapshotID: snapshot.id,
            issues: issues
        )
    }

    public static func exactSnapshot(
        of snapshot: AccessibilityCommandControlSnapshot,
        limits: AccessibilityAuditLimits = .default
    ) throws -> String {
        var context = try AccessibilityAuditContext(snapshot: snapshot, limits: limits)
        try context.run()
        return try AccessibilityExactSnapshotEncoder.encode(
            snapshot,
            issues: context.sortedIssues(),
            limits: limits,
            budget: &context.budget
        )
    }

    public static func exactSnapshotData(
        of snapshot: AccessibilityCommandControlSnapshot,
        limits: AccessibilityAuditLimits = .default
    ) throws -> Data {
        var context = try AccessibilityAuditContext(snapshot: snapshot, limits: limits)
        try context.run()
        let issues = try context.sortedIssues()
        let exactSnapshot = try AccessibilityExactSnapshotEncoder.encode(
            snapshot,
            issues: issues,
            limits: limits,
            budget: &context.budget
        )
        var data = Data()
        for byte in exactSnapshot.utf8 {
            try context.budget.consume(1)
            data.append(byte)
        }
        return data
    }
}

/// Canonical, strict, versioned persistence for caller-supplied audit evidence.
public enum AccessibilityAuditEvidenceArchive: Sendable {
    public static let currentFormatVersion = 2
    private static let magic = Data("MMAXEVID".utf8)

    public static func encode(
        _ evidence: AccessibilityAuditEvidence,
        limits: AccessibilityAuditLimits = .default
    ) throws -> Data {
        try AccessibilityAuditValidation.validate(limits)
        var budget = AccessibilityWorkBudget(maximum: limits.maximumWorkUnits)
        return try encode(evidence, limits: limits, budget: &budget)
    }

    private static func encode(
        _ evidence: AccessibilityAuditEvidence,
        limits: AccessibilityAuditLimits,
        budget: inout AccessibilityWorkBudget
    ) throws -> Data {
        try AccessibilityAuditValidation.preflight(evidence, limits: limits, budget: &budget)
        try validateEvidence(evidence, budget: &budget)

        let contrast = try accessibilityStableSortedByBudgetedKey(
            evidence.contrast,
            budget: &budget,
            key: { item, budget in
                try accessibilityOrderingKey([item.token.rawValue], budget: &budget)
            }
        )
        let differentiation = try accessibilityStableSortedByBudgetedKey(
            evidence.differentiateWithoutColor,
            budget: &budget,
            key: { item, budget in
                try accessibilityOrderingKey([item.token.rawValue], budget: &budget)
            }
        )
        let localization = try accessibilityStableSortedByBudgetedKey(
            evidence.localizationExpansion,
            budget: &budget,
            key: { item, budget in
                try accessibilityOrderingKey([item.token.rawValue], budget: &budget)
            }
        )

        var archive = AccessibilityEvidenceWriter(
            maximumBytes: limits.maximumEvidenceArchiveBytes,
            budget: budget
        )
        try archive.appendRaw(magic)
        try archive.appendUInt16(UInt16(currentFormatVersion))
        try archive.appendUInt16(0)
        let payloadLengthOffset = archive.data.count
        try archive.appendUInt32(0)
        let checksumOffset = archive.data.count
        try archive.appendUInt64(0)
        let payloadStart = archive.data.endIndex

        try archive.appendCount(contrast.count)
        for item in contrast {
            try budget.consume(1)
            try archive.append(item.token.rawValue)
            try archive.append(item.subjectID.rawValue)
            try archive.appendEnum(item.surface, allCases: AccessibilityContrastSurface.allCases)
            try archive.appendInteger(item.measuredRatioThousandths)
            try archive.appendInteger(item.requiredRatioThousandths)
            try archive.appendEnum(item.origin, allCases: AccessibilityEvidenceOrigin.allCases)
            try archive.append(item.source)
        }
        try archive.appendCount(differentiation.count)
        for item in differentiation {
            try budget.consume(1)
            try archive.append(item.token.rawValue)
            try archive.append(item.meaning)
            try archive.appendCueMask(item.nonColorCues)
            try archive.appendEnum(item.origin, allCases: AccessibilityEvidenceOrigin.allCases)
            try archive.append(item.source)
        }
        try archive.appendCount(localization.count)
        for item in localization {
            try budget.consume(1)
            try archive.append(item.token.rawValue)
            try archive.append(item.subjectID.rawValue)
            try archive.appendEnum(item.field, allCases: AccessibilityLocalizedField.allCases)
            try archive.append(item.localeIdentifier)
            try archive.append(item.baselineText)
            try archive.append(item.expandedText)
            try archive.appendEnum(
                item.outcome,
                allCases: AccessibilityLocalizationExpansionOutcome.allCases
            )
            try archive.appendEnum(item.origin, allCases: AccessibilityEvidenceOrigin.allCases)
            try archive.append(item.source)
        }

        let payload = archive.data[payloadStart..<archive.data.endIndex]
        guard let payloadLength = UInt32(exactly: payload.count) else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        let checksum = try accessibilityFNV1a64(payload, budget: &budget)
        try archive.overwriteUInt32(payloadLength, at: payloadLengthOffset)
        try archive.overwriteUInt64(checksum, at: checksumOffset)
        return archive.data
    }

    public static func decode(
        _ data: Data,
        limits: AccessibilityAuditLimits = .default
    ) throws -> AccessibilityAuditEvidence {
        try AccessibilityAuditValidation.validate(limits)
        guard data.count <= limits.maximumEvidenceArchiveBytes else {
            throw AccessibilityAuditError.evidenceArchiveTooLarge(
                maximumBytes: limits.maximumEvidenceArchiveBytes
            )
        }
        var budget = AccessibilityWorkBudget(maximum: limits.maximumWorkUnits)
        var reader = AccessibilityEvidenceReader(data: data, limits: limits, budget: budget)
        guard try reader.readRaw(count: magic.count) == magic else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        let version = Int(try reader.readUInt16())
        guard version == currentFormatVersion else {
            throw AccessibilityAuditError.unsupportedEvidenceArchiveVersion(version)
        }
        guard try reader.readUInt16() == 0 else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        let payloadLength = Int(try reader.readUInt32())
        let expectedChecksum = try reader.readUInt64()
        guard payloadLength == reader.remainingCount else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        let payload = try reader.readRaw(count: payloadLength)
        guard reader.isAtEnd else { throw AccessibilityAuditError.invalidEvidenceArchive }
        let actualChecksum = try accessibilityFNV1a64(payload, budget: &budget)
        guard expectedChecksum == actualChecksum else {
            throw AccessibilityAuditError.evidenceArchiveChecksumMismatch
        }

        var payloadReader = AccessibilityEvidenceReader(
            data: payload,
            limits: limits,
            budget: budget
        )
        let contrastCount = try payloadReader.readCount(
            maximum: limits.maximumEvidenceRecordsPerKind,
            kind: "contrast-evidence",
            minimumRecordBytes: 36
        )
        var contrast: [AccessibilityContrastEvidence] = []
        try budget.consume(contrastCount)
        contrast.reserveCapacity(contrastCount)
        var previousContrastKey: [UInt8]?
        var hasCanonicalRecordOrder = true
        for _ in 0..<contrastCount {
            try budget.consume(1)
            let token = try payloadReader.readString()
            let tokenKey = try accessibilityOrderingKey([token], budget: &budget)
            if let previousContrastKey {
                try budget.consume(min(previousContrastKey.count, tokenKey.count) + 1)
                if accessibilityCompareBytes(previousContrastKey, tokenKey) >= 0 {
                    hasCanonicalRecordOrder = false
                }
            }
            previousContrastKey = tokenKey
            contrast.append(
                AccessibilityContrastEvidence(
                    token: AccessibilityContrastEvidenceToken(rawValue: token),
                    subjectID: AccessibilityStableID(rawValue: try payloadReader.readString()),
                    surface: try payloadReader.readEnum(AccessibilityContrastSurface.self),
                    measuredRatioThousandths: try payloadReader.readInteger(),
                    requiredRatioThousandths: try payloadReader.readInteger(),
                    origin: try payloadReader.readEnum(AccessibilityEvidenceOrigin.self),
                    source: try payloadReader.readString()
                ))
        }
        let differentiationCount = try payloadReader.readCount(
            maximum: limits.maximumEvidenceRecordsPerKind,
            kind: "differentiate-without-color-evidence",
            minimumRecordBytes: 20
        )
        var differentiation: [AccessibilityDifferentiateWithoutColorEvidence] = []
        try budget.consume(differentiationCount)
        differentiation.reserveCapacity(differentiationCount)
        var previousDifferentiationKey: [UInt8]?
        for _ in 0..<differentiationCount {
            try budget.consume(1)
            let token = try payloadReader.readString()
            let tokenKey = try accessibilityOrderingKey([token], budget: &budget)
            if let previousDifferentiationKey {
                try budget.consume(min(previousDifferentiationKey.count, tokenKey.count) + 1)
                if accessibilityCompareBytes(previousDifferentiationKey, tokenKey) >= 0 {
                    hasCanonicalRecordOrder = false
                }
            }
            previousDifferentiationKey = tokenKey
            differentiation.append(
                AccessibilityDifferentiateWithoutColorEvidence(
                    token: AccessibilityDifferentiateWithoutColorEvidenceToken(rawValue: token),
                    meaning: try payloadReader.readString(),
                    nonColorCues: try payloadReader.readCueMask(),
                    origin: try payloadReader.readEnum(AccessibilityEvidenceOrigin.self),
                    source: try payloadReader.readString()
                ))
        }
        let localizationCount = try payloadReader.readCount(
            maximum: limits.maximumEvidenceRecordsPerKind,
            kind: "localization-expansion-evidence",
            minimumRecordBytes: 36
        )
        var localization: [AccessibilityLocalizationExpansionEvidence] = []
        try budget.consume(localizationCount)
        localization.reserveCapacity(localizationCount)
        var previousLocalizationKey: [UInt8]?
        for _ in 0..<localizationCount {
            try budget.consume(1)
            let token = try payloadReader.readString()
            let tokenKey = try accessibilityOrderingKey([token], budget: &budget)
            if let previousLocalizationKey {
                try budget.consume(min(previousLocalizationKey.count, tokenKey.count) + 1)
                if accessibilityCompareBytes(previousLocalizationKey, tokenKey) >= 0 {
                    hasCanonicalRecordOrder = false
                }
            }
            previousLocalizationKey = tokenKey
            localization.append(
                AccessibilityLocalizationExpansionEvidence(
                    token: AccessibilityLocalizationExpansionEvidenceToken(rawValue: token),
                    subjectID: AccessibilityStableID(rawValue: try payloadReader.readString()),
                    field: try payloadReader.readEnum(AccessibilityLocalizedField.self),
                    localeIdentifier: try payloadReader.readString(),
                    baselineText: try payloadReader.readString(),
                    expandedText: try payloadReader.readString(),
                    outcome: try payloadReader.readEnum(
                        AccessibilityLocalizationExpansionOutcome.self
                    ),
                    origin: try payloadReader.readEnum(AccessibilityEvidenceOrigin.self),
                    source: try payloadReader.readString()
                ))
        }
        guard payloadReader.isAtEnd else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }

        let evidence = AccessibilityAuditEvidence(
            contrast: contrast,
            differentiateWithoutColor: differentiation,
            localizationExpansion: localization
        )
        try AccessibilityAuditValidation.preflight(evidence, limits: limits, budget: &budget)
        try validateEvidence(evidence, budget: &budget)
        guard payloadReader.hasCanonicalStringsAndCollections, hasCanonicalRecordOrder else {
            throw AccessibilityAuditError.nonCanonicalEvidenceArchive
        }
        let canonicalData = try encode(evidence, limits: limits, budget: &budget)
        guard try accessibilityEqualData(data, canonicalData, budget: &budget) else {
            throw AccessibilityAuditError.nonCanonicalEvidenceArchive
        }
        return evidence
    }

    private static func validateEvidence(
        _ evidence: AccessibilityAuditEvidence,
        budget: inout AccessibilityWorkBudget
    ) throws {
        var contrastTokens: Set<AccessibilityContrastEvidenceToken> = []
        let orderedContrast = try accessibilityStableSortedByBudgetedKey(
            evidence.contrast,
            budget: &budget,
            key: accessibilityContrastOrderingKey
        )
        for item in orderedContrast {
            try budget.consume(1)
            let hasValidToken = try AccessibilityAuditValidation.isValidIdentifier(
                item.token.rawValue,
                budget: &budget
            )
            let hasValidSubject = try AccessibilityAuditValidation.isValidIdentifier(
                item.subjectID.rawValue,
                budget: &budget
            )
            let hasSource = try !AccessibilityAuditValidation.isBlank(
                item.source,
                budget: &budget
            )
            guard hasValidToken, contrastTokens.insert(item.token).inserted, hasValidSubject,
                (1_000...21_000).contains(item.measuredRatioThousandths),
                (1_000...21_000).contains(item.requiredRatioThousandths),
                hasSource
            else {
                throw AccessibilityAuditError.invalidEvidence(field: "contrast")
            }
        }
        var differentiationTokens: Set<AccessibilityDifferentiateWithoutColorEvidenceToken> = []
        let orderedDifferentiation = try accessibilityStableSortedByBudgetedKey(
            evidence.differentiateWithoutColor,
            budget: &budget,
            key: accessibilityDifferentiationOrderingKey
        )
        for item in orderedDifferentiation {
            try budget.consume(1)
            let hasValidToken = try AccessibilityAuditValidation.isValidIdentifier(
                item.token.rawValue,
                budget: &budget
            )
            let hasMeaning = try !AccessibilityAuditValidation.isBlank(
                item.meaning,
                budget: &budget
            )
            let hasSource = try !AccessibilityAuditValidation.isBlank(
                item.source,
                budget: &budget
            )
            guard hasValidToken, differentiationTokens.insert(item.token).inserted, hasMeaning,
                !item.nonColorCues.isEmpty, hasSource
            else {
                throw AccessibilityAuditError.invalidEvidence(field: "differentiateWithoutColor")
            }
        }
        var localizationTokens: Set<AccessibilityLocalizationExpansionEvidenceToken> = []
        let orderedLocalization = try accessibilityStableSortedByBudgetedKey(
            evidence.localizationExpansion,
            budget: &budget,
            key: accessibilityLocalizationOrderingKey
        )
        for item in orderedLocalization {
            try budget.consume(1)
            let hasValidToken = try AccessibilityAuditValidation.isValidIdentifier(
                item.token.rawValue,
                budget: &budget
            )
            let hasValidSubject = try AccessibilityAuditValidation.isValidIdentifier(
                item.subjectID.rawValue,
                budget: &budget
            )
            let hasValidLocale = try AccessibilityAuditValidation.isValidLocaleIdentifier(
                item.localeIdentifier,
                budget: &budget
            )
            let hasBaseline = try !AccessibilityAuditValidation.isBlank(
                item.baselineText,
                budget: &budget
            )
            let hasExpandedText = try !AccessibilityAuditValidation.isBlank(
                item.expandedText,
                budget: &budget
            )
            let hasSource = try !AccessibilityAuditValidation.isBlank(
                item.source,
                budget: &budget
            )
            guard hasValidToken, localizationTokens.insert(item.token).inserted,
                hasValidSubject, hasValidLocale, hasBaseline, hasExpandedText, hasSource
            else {
                throw AccessibilityAuditError.invalidEvidence(field: "localizationExpansion")
            }
        }
    }
}

private struct AccessibilityAuditContext {
    let snapshot: AccessibilityCommandControlSnapshot
    let limits: AccessibilityAuditLimits
    var budget: AccessibilityWorkBudget
    private var issues: [AccessibilityAuditIssue] = []
    private var issueIDs: Set<AccessibilityAuditIssue.ID> = []

    init(snapshot: AccessibilityCommandControlSnapshot, limits: AccessibilityAuditLimits) throws {
        try AccessibilityAuditValidation.validate(limits)
        var budget = AccessibilityWorkBudget(maximum: limits.maximumWorkUnits)
        try AccessibilityAuditValidation.preflight(snapshot, limits: limits, budget: &budget)
        self.snapshot = snapshot
        self.limits = limits
        self.budget = budget
    }

    mutating func run() throws {
        try Task.checkCancellation()
        var elementByID: [AccessibilityStableID: AccessibilitySemanticElement] = [:]
        var allStableIDs: Set<AccessibilityStableID> = []
        var stableIDCounts: [AccessibilityStableID: Int] = [snapshot.id: 1]
        for element in snapshot.elements {
            try budget.consume(1)
            stableIDCounts[element.id, default: 0] += 1
            for action in element.actions {
                try budget.consume(1)
                stableIDCounts[action.id, default: 0] += 1
            }
            for shortcut in element.keyboardShortcuts {
                try budget.consume(1)
                stableIDCounts[shortcut.id, default: 0] += 1
            }
        }
        for announcement in snapshot.announcements {
            try budget.consume(1)
            stableIDCounts[announcement.id, default: 0] += 1
        }
        try registerStableID(snapshot.id, field: "snapshot.id", occupied: &allStableIDs)
        try inspectStableID(snapshot.rootElementID, field: "snapshot.rootElementID")

        let orderedElements = try accessibilityStableSortedByBudgetedKey(
            snapshot.elements,
            budget: &budget,
            key: accessibilityElementOrderingKey
        )
        for element in orderedElements {
            try budget.consume(1)
            try registerStableID(
                element.id,
                field: "element.id",
                occupied: &allStableIDs
            )
            if elementByID[element.id] != nil {
                try add(
                    .error,
                    .duplicateStableIdentifier,
                    subject: element.id.rawValue,
                    "Element stable identifier is duplicated."
                )
            } else {
                elementByID[element.id] = element
            }
        }

        if let root = elementByID[snapshot.rootElementID] {
            if root.parentID != nil {
                try add(
                    .error,
                    .rootHasParent,
                    subject: root.id.rawValue,
                    "Root element must not have a parent."
                )
            }
        } else {
            try add(
                .error,
                .missingRootElement,
                subject: snapshot.rootElementID.rawValue,
                "Root element identifier does not resolve to an element."
            )
        }

        try inspectElements(
            elements: orderedElements,
            elementByID: elementByID,
            stableIDCounts: stableIDCounts,
            allStableIDs: &allStableIDs
        )
        try inspectHierarchy(elements: orderedElements, elementByID: elementByID)
        try inspectFocusOrder(elements: orderedElements, elementByID: elementByID)
        try inspectAnnouncements(
            elements: orderedElements,
            elementByID: elementByID,
            allStableIDs: &allStableIDs
        )
        try inspectEvidence(elementByID: elementByID)
    }

    mutating func sortedIssues() throws -> [AccessibilityAuditIssue] {
        try accessibilityStableSortedByBudgetedKey(
            issues,
            budget: &budget,
            key: { issue, budget in
                try accessibilityOrderingKey(
                    [
                        String(9 - issue.severity.rank),
                        issue.code.rawValue,
                        issue.subject ?? "",
                        issue.message,
                        issue.id.rawValue
                    ], budget: &budget)
            }
        )
    }

    private mutating func inspectStableID(
        _ id: AccessibilityStableID,
        field: String
    ) throws {
        if try !AccessibilityAuditValidation.isValidIdentifier(
            id.rawValue,
            budget: &budget
        ) {
            try add(
                .error,
                .invalidStableIdentifier,
                subject: id.rawValue,
                "\(field) must be a nonempty printable identifier without whitespace."
            )
        }
    }

    private mutating func registerStableID(
        _ id: AccessibilityStableID,
        field: String,
        occupied: inout Set<AccessibilityStableID>
    ) throws {
        try inspectStableID(id, field: field)
        if !occupied.insert(id).inserted {
            try add(
                .error,
                .duplicateStableIdentifier,
                subject: id.rawValue,
                "Stable identifier is reused by multiple semantic subjects."
            )
        }
    }

    private mutating func inspectElements(
        elements: [AccessibilitySemanticElement],
        elementByID: [AccessibilityStableID: AccessibilitySemanticElement],
        stableIDCounts: [AccessibilityStableID: Int],
        allStableIDs: inout Set<AccessibilityStableID>
    ) throws {
        var shortcutCountByChord: [String: Int] = [:]
        var accessEligibleShortcutCountByChord: [String: Int] = [:]
        var keyboardAccessRecords:
            [(
                element: AccessibilitySemanticElement,
                validActionIDs: Set<AccessibilityStableID>,
                bindings: [(actionID: AccessibilityStableID, chord: String)]
            )] = []
        for element in elements {
            try budget.consume(1)
            for shortcut in element.keyboardShortcuts {
                try budget.consume(1)
                let chord = try accessibilityCanonicalChord(shortcut, budget: &budget)
                shortcutCountByChord[chord, default: 0] += 1
            }
        }

        for element in elements {
            try budget.consume(1)
            let actions = try accessibilityStableSortedByBudgetedKey(
                element.actions,
                budget: &budget,
                key: accessibilityActionOrderingKey
            )
            let shortcuts = try accessibilityStableSortedByBudgetedKey(
                element.keyboardShortcuts,
                budget: &budget,
                key: accessibilityShortcutOrderingKey
            )
            if let parentID = element.parentID {
                try inspectStableID(parentID, field: "element.parentID")
                if elementByID[parentID] == nil {
                    try add(
                        .error,
                        .unknownParent,
                        subject: element.id.rawValue,
                        "Element parent identifier does not resolve to an element."
                    )
                }
            }
            try inspectSemanticText(element)
            try inspectRoleSpecificContent(element)
            if element.role.isControl || element.role == .image || !element.actions.isEmpty,
                !element.isHiddenFromAssistiveTechnology,
                try AccessibilityAuditValidation.isBlank(element.label, budget: &budget)
            {
                try add(
                    .error,
                    .missingControlLabel,
                    subject: element.id.rawValue,
                    "Exposed control or image has no nonblank semantic label."
                )
            }
            if element.isHiddenFromAssistiveTechnology, !element.actions.isEmpty {
                try add(
                    .warning,
                    .hiddenControlHasActions,
                    subject: element.id.rawValue,
                    "Element hidden from assistive technology still declares actions."
                )
            }
            if element.isHiddenFromAssistiveTechnology, element.isKeyboardFocusable {
                try add(
                    .error,
                    .hiddenElementIsFocusable,
                    subject: element.id.rawValue,
                    "Element hidden from assistive technology is keyboard focusable."
                )
            }
            if element.isKeyboardFocusable, !element.role.supportsKeyboardFocus {
                try add(
                    .error,
                    .keyboardFocusRoleMismatch,
                    subject: element.id.rawValue,
                    "Declared role does not support keyboard focus."
                )
            }
            if element.checkedState != .notApplicable, !element.role.supportsCheckedState {
                try add(
                    .error,
                    .checkedStateRoleMismatch,
                    subject: element.id.rawValue,
                    "Checked state is not applicable to declared role."
                )
            }
            if element.role == .radioButton, element.checkedState == .mixed {
                try add(
                    .error,
                    .checkedStateRoleMismatch,
                    subject: element.id.rawValue,
                    "Radio button cannot declare a mixed checked state."
                )
            }
            if element.role.requiresCheckedState, element.checkedState == .notApplicable {
                try add(
                    .error,
                    .missingRequiredState,
                    subject: element.id.rawValue + "/checked",
                    identityComponents: [element.id.rawValue, "checked"],
                    "Checked-state role has no declared checked state."
                )
            }
            if element.role == .tab, element.selectedState == .notApplicable {
                try add(
                    .error,
                    .missingRequiredState,
                    subject: element.id.rawValue + "/selected",
                    identityComponents: [element.id.rawValue, "selected"],
                    "Tab has no declared selected state."
                )
            }
            if element.selectedState != .notApplicable, !element.role.supportsSelectedState {
                try add(
                    .error,
                    .selectedStateRoleMismatch,
                    subject: element.id.rawValue,
                    "Selected state is not applicable to declared role."
                )
            }

            var actionKinds: Set<AccessibilitySemanticActionKind> = []
            var localActionIDs: Set<AccessibilityStableID> = []
            var validLocalActionIDs: Set<AccessibilityStableID> = []
            var customActionLabelCounts: [String: Int] = [:]
            for action in actions {
                try budget.consume(1)
                guard action.kind == .custom else { continue }
                if let label = action.label,
                    try !AccessibilityAuditValidation.isBlank(label, budget: &budget)
                {
                    customActionLabelCounts[
                        try AccessibilityAuditValidation.semanticTextIdentity(
                            label,
                            budget: &budget
                        ),
                        default: 0
                    ] += 1
                }
            }
            for action in actions {
                try budget.consume(1)
                let hasValidID = try AccessibilityAuditValidation.isValidIdentifier(
                    action.id.rawValue,
                    budget: &budget
                )
                let hasGloballyUniqueID = stableIDCounts[action.id] == 1
                let hasValidCustomLabel: Bool
                if action.kind != .custom {
                    hasValidCustomLabel = true
                } else if let label = action.label {
                    hasValidCustomLabel =
                        try !AccessibilityAuditValidation.isBlank(label, budget: &budget)
                        && customActionLabelCounts[
                            try AccessibilityAuditValidation.semanticTextIdentity(
                                label,
                                budget: &budget
                            )
                        ] == 1
                } else {
                    hasValidCustomLabel = false
                }
                try registerStableID(
                    action.id,
                    field: "element.actions.id",
                    occupied: &allStableIDs
                )
                let isLocallyUnique = localActionIDs.insert(action.id).inserted
                if !isLocallyUnique || !hasGloballyUniqueID {
                    try add(
                        .error,
                        .duplicateStableIdentifier,
                        subject: action.id.rawValue,
                        "Action stable identifier is duplicated."
                    )
                }
                let roleAllowsAction = element.role.allowedActions.contains(action.kind)
                if hasValidID, isLocallyUnique, hasGloballyUniqueID, roleAllowsAction,
                    hasValidCustomLabel
                {
                    validLocalActionIDs.insert(action.id)
                    if action.kind != .custom, !actionKinds.insert(action.kind).inserted {
                        try add(
                            .warning,
                            .duplicateActionKind,
                            subject: element.id.rawValue + "/" + action.kind.rawValue,
                            identityComponents: [element.id.rawValue, action.kind.rawValue],
                            "Element declares an action kind more than once."
                        )
                    }
                }
                if !roleAllowsAction {
                    try add(
                        .error,
                        .actionRoleMismatch,
                        subject: element.id.rawValue + "/" + action.id.rawValue,
                        identityComponents: [element.id.rawValue, action.id.rawValue],
                        "Action kind is not applicable to declared role."
                    )
                }
                if let label = action.label,
                    try AccessibilityAuditValidation.isBlank(label, budget: &budget)
                {
                    try add(
                        .warning,
                        .emptySemanticText,
                        subject: action.id.rawValue + "/label",
                        "Action label is present but blank."
                    )
                }
                if action.kind == .custom,
                    try AccessibilityAuditValidation.isBlank(action.label, budget: &budget)
                {
                    try add(
                        .error,
                        .missingControlLabel,
                        subject: action.id.rawValue,
                        "Custom action has no nonblank semantic label."
                    )
                } else if action.kind == .custom, let label = action.label {
                    let key = try AccessibilityAuditValidation.semanticTextIdentity(
                        label,
                        budget: &budget
                    )
                    if customActionLabelCounts[key, default: 0] > 1 {
                        try add(
                            .error,
                            .duplicateCustomActionLabel,
                            subject: element.id.rawValue + "/" + key,
                            identityComponents: [element.id.rawValue, key],
                            "Custom action labels must be unique on their element."
                        )
                    }
                }
            }
            try inspectRequiredActions(
                element,
                actionKinds: actionKinds,
                validActionIDs: validLocalActionIDs
            )

            var accessEligibleShortcutBindings: [(actionID: AccessibilityStableID, chord: String)] = []
            var localShortcutIDs: Set<AccessibilityStableID> = []
            for shortcut in shortcuts {
                try budget.consume(1)
                let chord = try accessibilityCanonicalChord(shortcut, budget: &budget)
                let hasValidShortcutID = try AccessibilityAuditValidation.isValidIdentifier(
                    shortcut.id.rawValue,
                    budget: &budget
                )
                let hasGloballyUniqueShortcutID = stableIDCounts[shortcut.id] == 1
                try registerStableID(
                    shortcut.id,
                    field: "element.keyboardShortcuts.id",
                    occupied: &allStableIDs
                )
                try inspectStableID(shortcut.actionID, field: "element.keyboardShortcuts.actionID")
                let hasValidKey = try AccessibilityAuditValidation.isValidShortcutKey(
                    shortcut.key,
                    budget: &budget
                )
                let isPrintableKey =
                    try AccessibilityAuditValidation.isPrintableShortcutCharacter(
                        shortcut.key,
                        budget: &budget
                    )
                let hasModifier = !shortcut.modifiers.isEmpty || !isPrintableKey
                let hasUniqueID = localShortcutIDs.insert(shortcut.id).inserted
                if !hasValidKey {
                    try add(
                        .error,
                        .invalidKeyboardShortcut,
                        subject: shortcut.id.rawValue,
                        "Keyboard shortcut key must use canonical physical-key grammar."
                    )
                }
                if !validLocalActionIDs.contains(shortcut.actionID) {
                    try add(
                        .error,
                        .shortcutTargetsUnknownAction,
                        subject: element.id.rawValue + "/" + chord,
                        identityComponents: [element.id.rawValue, chord],
                        "Keyboard shortcut does not target an action on its element."
                    )
                } else if hasValidShortcutID, hasGloballyUniqueShortcutID, hasUniqueID, hasValidKey,
                    hasModifier
                {
                    accessEligibleShortcutBindings.append((shortcut.actionID, chord))
                    accessEligibleShortcutCountByChord[chord, default: 0] += 1
                }
                if shortcut.modifiers.isEmpty,
                    try AccessibilityAuditValidation.isPrintableShortcutCharacter(
                        shortcut.key,
                        budget: &budget
                    )
                {
                    try add(
                        .error,
                        .unmodifiedKeyboardShortcut,
                        subject: element.id.rawValue + "/" + chord,
                        identityComponents: [element.id.rawValue, chord],
                        "Single-character keyboard shortcut has no modifier."
                    )
                }
                if shortcutCountByChord[chord, default: 0] > 1 {
                    try add(
                        .error,
                        .duplicateKeyboardShortcut,
                        subject: chord,
                        identityComponents: [chord],
                        "Keyboard shortcut chord is assigned more than once."
                    )
                }
                if let title = shortcut.discoverabilityTitle,
                    try AccessibilityAuditValidation.isBlank(title, budget: &budget)
                {
                    try add(
                        .warning,
                        .emptySemanticText,
                        subject: shortcut.id.rawValue + "/shortcut-title",
                        identityComponents: [shortcut.id.rawValue, "shortcut-title"],
                        "Keyboard shortcut discoverability title is present but blank."
                    )
                }
            }
            keyboardAccessRecords.append(
                (element, validLocalActionIDs, accessEligibleShortcutBindings)
            )
        }
        for record in keyboardAccessRecords {
            var shortcutActionIDs: Set<AccessibilityStableID> = []
            for binding in record.bindings {
                try budget.consume(1)
                if accessEligibleShortcutCountByChord[binding.chord] == 1 {
                    shortcutActionIDs.insert(binding.actionID)
                }
            }
            try inspectKeyboardAccess(
                record.element,
                validActionIDs: record.validActionIDs,
                shortcutActionIDs: shortcutActionIDs
            )
        }
    }

    private mutating func inspectSemanticText(_ element: AccessibilitySemanticElement) throws {
        for (field, value) in [
            ("label", element.label),
            ("value", element.value),
            ("hint", element.hint)
        ] {
            try budget.consume(1)
            if let value,
                try AccessibilityAuditValidation.isBlank(value, budget: &budget)
            {
                try add(
                    .warning,
                    .emptySemanticText,
                    subject: element.id.rawValue + "/" + field,
                    "Semantic text is present but blank."
                )
            }
        }
    }

    private mutating func inspectRoleSpecificContent(
        _ element: AccessibilitySemanticElement
    ) throws {
        let populated: [(AccessibilitySemanticContentField, String)] = [
            (.label, element.label ?? ""),
            (.value, element.value ?? ""),
            (.hint, element.hint ?? "")
        ]
        for (field, value) in populated {
            try budget.consume(1)
            guard try !AccessibilityAuditValidation.isBlank(value, budget: &budget),
                !element.role.allowedContentFields.contains(field)
            else { continue }
            try add(
                .error,
                .semanticContentRoleMismatch,
                subject: element.id.rawValue + "/" + field.rawValue,
                identityComponents: [element.id.rawValue, field.rawValue],
                "Semantic content field is not applicable to declared role."
            )
        }
    }

    private mutating func inspectRequiredActions(
        _ element: AccessibilitySemanticElement,
        actionKinds: Set<AccessibilitySemanticActionKind>,
        validActionIDs: Set<AccessibilityStableID>
    ) throws {
        guard element.isEnabled, !element.isHiddenFromAssistiveTechnology else { return }
        if element.role == .customControl, validActionIDs.isEmpty {
            try add(
                .error,
                .missingRequiredAction,
                subject: element.id.rawValue + "/action",
                identityComponents: [element.id.rawValue, "action"],
                "Enabled custom control has no valid semantic action."
            )
        }
        let required = element.role.requiredActions(checkedState: element.checkedState)
        for action in required {
            try budget.consume(1)
            guard !actionKinds.contains(action) else { continue }
            try add(
                .error,
                .missingRequiredAction,
                subject: element.id.rawValue + "/" + action.rawValue,
                identityComponents: [element.id.rawValue, action.rawValue],
                "Enabled control is missing required semantic action."
            )
        }
    }

    private mutating func inspectKeyboardAccess(
        _ element: AccessibilitySemanticElement,
        validActionIDs: Set<AccessibilityStableID>,
        shortcutActionIDs: Set<AccessibilityStableID>
    ) throws {
        guard element.isEnabled, !element.isHiddenFromAssistiveTechnology else { return }
        guard !element.isKeyboardFocusable else { return }
        for actionID in validActionIDs {
            try budget.consume(1)
            guard !shortcutActionIDs.contains(actionID) else { continue }
            try add(
                .error,
                .keyboardAccessMissing,
                subject: element.id.rawValue + "/" + actionID.rawValue,
                identityComponents: [element.id.rawValue, actionID.rawValue],
                "Enabled action has no valid keyboard shortcut."
            )
        }
    }

    private mutating func inspectHierarchy(
        elements: [AccessibilitySemanticElement],
        elementByID: [AccessibilityStableID: AccessibilitySemanticElement]
    ) throws {
        for element in elements {
            try budget.consume(1)
            var path: [AccessibilityStableID] = []
            var pathIndexes: [AccessibilityStableID: Int] = [:]
            var current: AccessibilityStableID? = element.id
            var reachedRoot = false
            while let currentID = current {
                try budget.consume(1)
                if let cycleStart = pathIndexes[currentID] {
                    var cycleID = currentID
                    for id in path[cycleStart...] {
                        try budget.consume(1)
                        if try accessibilityCompareUTF8(
                            id.rawValue,
                            cycleID.rawValue,
                            budget: &budget
                        ) < 0 {
                            cycleID = id
                        }
                    }
                    try add(
                        .error,
                        .hierarchyCycle,
                        subject: cycleID.rawValue,
                        "Element parent relationships contain a cycle."
                    )
                    break
                }
                pathIndexes[currentID] = path.count
                path.append(currentID)
                guard let currentElement = elementByID[currentID] else { break }
                if currentID == snapshot.rootElementID, currentElement.parentID == nil {
                    reachedRoot = true
                    break
                }
                current = currentElement.parentID
            }
            if !reachedRoot, current == nil {
                try add(
                    .error,
                    .hierarchyNotRooted,
                    subject: element.id.rawValue,
                    "Element parent chain does not terminate at declared root."
                )
            }
        }
    }

    private mutating func inspectFocusOrder(
        elements: [AccessibilitySemanticElement],
        elementByID: [AccessibilityStableID: AccessibilitySemanticElement]
    ) throws {
        var focused: Set<AccessibilityStableID> = []
        for id in snapshot.focusOrder {
            try budget.consume(1)
            try inspectStableID(id, field: "focusOrder")
            if !focused.insert(id).inserted {
                try add(
                    .error,
                    .focusOrderContainsDuplicate,
                    subject: id.rawValue,
                    "Focus order contains the same element more than once."
                )
            }
            guard let element = elementByID[id] else {
                try add(
                    .error,
                    .focusOrderTargetsUnknownElement,
                    subject: id.rawValue,
                    "Focus order identifier does not resolve to an element."
                )
                continue
            }
            if !element.isKeyboardFocusable {
                try add(
                    .error,
                    .nonFocusableElementInFocusOrder,
                    subject: id.rawValue,
                    "Focus order contains an element not declared keyboard focusable."
                )
            }
            if !element.isEnabled {
                try add(
                    .warning,
                    .disabledElementInFocusOrder,
                    subject: id.rawValue,
                    "Focus order contains a disabled element."
                )
            }
        }
        for element in elements {
            try budget.consume(1)
            guard element.isKeyboardFocusable, element.isEnabled,
                !element.isHiddenFromAssistiveTechnology, !focused.contains(element.id)
            else { continue }
            try add(
                .error,
                .focusableElementMissingFromFocusOrder,
                subject: element.id.rawValue,
                "Enabled keyboard-focusable element is absent from focus order."
            )
        }
    }

    private mutating func inspectAnnouncements(
        elements: [AccessibilitySemanticElement],
        elementByID: [AccessibilityStableID: AccessibilitySemanticElement],
        allStableIDs: inout Set<AccessibilityStableID>
    ) throws {
        var actionIDs: Set<AccessibilityStableID> = []
        for element in elements {
            try budget.consume(1)
            for action in element.actions {
                try budget.consume(1)
                actionIDs.insert(action.id)
            }
        }
        let announcements = try accessibilityStableSortedByBudgetedKey(
            snapshot.announcements,
            budget: &budget,
            key: accessibilityAnnouncementOrderingKey
        )
        for announcement in announcements {
            try budget.consume(1)
            try registerStableID(
                announcement.id,
                field: "announcement.id",
                occupied: &allStableIDs
            )
            if try AccessibilityAuditValidation.isBlank(
                announcement.message,
                budget: &budget
            ) {
                try add(
                    .error,
                    .announcementMessageMissing,
                    subject: announcement.id.rawValue,
                    "Announcement message is blank."
                )
            }
            if let id = announcement.relatedElementID, elementByID[id] == nil {
                try inspectStableID(id, field: "announcement.relatedElementID")
                try add(
                    .error,
                    .announcementTargetsUnknownElement,
                    subject: announcement.id.rawValue,
                    "Announcement related element does not exist."
                )
            }
            if let id = announcement.relatedElementID, elementByID[id] != nil {
                try inspectStableID(id, field: "announcement.relatedElementID")
            }
            if let id = announcement.triggerActionID {
                try inspectStableID(id, field: "announcement.triggerActionID")
                if !actionIDs.contains(id) {
                    try add(
                        .error,
                        .announcementTargetsUnknownAction,
                        subject: announcement.id.rawValue,
                        "Announcement trigger action does not exist."
                    )
                }
            }
        }
    }

    private mutating func inspectEvidence(
        elementByID: [AccessibilityStableID: AccessibilitySemanticElement]
    ) throws {
        var contrastByToken: [AccessibilityContrastEvidenceToken: AccessibilityContrastEvidence] = [:]
        var seenContrastTokens: Set<AccessibilityContrastEvidenceToken> = []
        let orderedContrast = try accessibilityStableSortedByBudgetedKey(
            snapshot.evidence.contrast,
            budget: &budget,
            key: accessibilityContrastOrderingKey
        )
        for evidence in orderedContrast {
            try budget.consume(1)
            if !seenContrastTokens.insert(evidence.token).inserted {
                try add(
                    .error,
                    .duplicateEvidenceToken,
                    subject: "contrast/" + evidence.token.rawValue,
                    identityComponents: ["contrast", evidence.token.rawValue],
                    "Contrast evidence token is duplicated."
                )
            }
            let hasValidSubject = try AccessibilityAuditValidation.isValidIdentifier(
                evidence.subjectID.rawValue,
                budget: &budget
            )
            let hasSource = try !AccessibilityAuditValidation.isBlank(
                evidence.source,
                budget: &budget
            )
            let isStructurallyValid =
                try AccessibilityAuditValidation.isValidIdentifier(
                    evidence.token.rawValue,
                    budget: &budget
                ) && hasValidSubject && hasSource
            if !isStructurallyValid {
                try add(
                    .error,
                    .invalidEvidence,
                    subject: "contrast/" + evidence.token.rawValue,
                    identityComponents: ["contrast", evidence.token.rawValue],
                    "Contrast evidence has an invalid token or blank source."
                )
            } else if contrastByToken[evidence.token] == nil {
                contrastByToken[evidence.token] = evidence
            }
            if !(1_000...21_000).contains(evidence.measuredRatioThousandths)
                || !(1_000...21_000).contains(evidence.requiredRatioThousandths)
            {
                try add(
                    .error,
                    .invalidContrastRatio,
                    subject: evidence.token.rawValue,
                    "Physical contrast ratios must be within 1000...21000 thousandths."
                )
            } else if evidence.measuredRatioThousandths < evidence.requiredRatioThousandths {
                try add(
                    .error,
                    .contrastBelowRequiredRatio,
                    subject: evidence.token.rawValue,
                    "Measured contrast ratio is below caller-supplied required ratio."
                )
            }
            if let subject = elementByID[evidence.subjectID] {
                if try !subject.supportsContrastSurface(evidence.surface, budget: &budget) {
                    try add(
                        .error,
                        .contrastEvidenceSurfaceMismatch,
                        subject: "contrast/" + evidence.token.rawValue,
                        identityComponents: ["contrast", evidence.token.rawValue, "surface"],
                        "Contrast evidence surface is inapplicable to its semantic subject."
                    )
                }
            } else {
                try add(
                    .error,
                    .contrastEvidenceSurfaceMismatch,
                    subject: "contrast/" + evidence.token.rawValue,
                    identityComponents: ["contrast", evidence.token.rawValue, "subject"],
                    "Contrast evidence subject does not resolve to an element."
                )
            }
        }

        var differentiationByToken:
            [AccessibilityDifferentiateWithoutColorEvidenceToken:
                AccessibilityDifferentiateWithoutColorEvidence] = [:]
        var seenDifferentiationTokens: Set<AccessibilityDifferentiateWithoutColorEvidenceToken> = []
        let orderedDifferentiation = try accessibilityStableSortedByBudgetedKey(
            snapshot.evidence.differentiateWithoutColor,
            budget: &budget,
            key: accessibilityDifferentiationOrderingKey
        )
        for evidence in orderedDifferentiation {
            try budget.consume(1)
            if !seenDifferentiationTokens.insert(evidence.token).inserted {
                try add(
                    .error,
                    .duplicateEvidenceToken,
                    subject: "differentiateWithoutColor/" + evidence.token.rawValue,
                    identityComponents: ["differentiateWithoutColor", evidence.token.rawValue],
                    "Differentiate-without-color evidence token is duplicated."
                )
            }
            let isStructurallyValid =
                try AccessibilityAuditValidation.isValidIdentifier(
                    evidence.token.rawValue,
                    budget: &budget
                ) && !AccessibilityAuditValidation.isBlank(evidence.meaning, budget: &budget)
                && !AccessibilityAuditValidation.isBlank(evidence.source, budget: &budget)
            if !isStructurallyValid {
                try add(
                    .error,
                    .invalidEvidence,
                    subject: "differentiateWithoutColor/" + evidence.token.rawValue,
                    identityComponents: ["differentiateWithoutColor", evidence.token.rawValue],
                    "Differentiate-without-color evidence has invalid or blank fields."
                )
            } else if differentiationByToken[evidence.token] == nil {
                differentiationByToken[evidence.token] = evidence
            }
            if evidence.nonColorCues.isEmpty {
                try add(
                    .error,
                    .colorOnlyDifferentiation,
                    subject: evidence.token.rawValue,
                    "Evidence declares no non-color cue."
                )
            }
        }

        var localizationByToken:
            [AccessibilityLocalizationExpansionEvidenceToken:
                AccessibilityLocalizationExpansionEvidence] = [:]
        var seenLocalizationTokens: Set<AccessibilityLocalizationExpansionEvidenceToken> = []
        var localizedTextBySubject: [AccessibilityLocalizationSubject: String] = [:]
        var actionOwnerByID: [AccessibilityStableID: AccessibilityStableID] = [:]
        let orderedElements = try accessibilityStableSortedByBudgetedKey(
            snapshot.elements,
            budget: &budget,
            key: accessibilityElementOrderingKey
        )
        for element in orderedElements {
            try budget.consume(1)
            if let label = element.label {
                localizedTextBySubject[
                    AccessibilityLocalizationSubject(id: element.id, field: .label),
                    default: label
                ] = label
            }
            if let value = element.value {
                localizedTextBySubject[
                    AccessibilityLocalizationSubject(id: element.id, field: .value),
                    default: value
                ] = value
            }
            if let hint = element.hint {
                localizedTextBySubject[
                    AccessibilityLocalizationSubject(id: element.id, field: .hint),
                    default: hint
                ] = hint
            }
            let actions = try accessibilityStableSortedByBudgetedKey(
                element.actions,
                budget: &budget,
                key: accessibilityActionOrderingKey
            )
            for action in actions {
                try budget.consume(1)
                actionOwnerByID[action.id] = element.id
                if let label = action.label {
                    localizedTextBySubject[
                        AccessibilityLocalizationSubject(id: action.id, field: .actionLabel),
                        default: label
                    ] = label
                }
            }
            let shortcuts = try accessibilityStableSortedByBudgetedKey(
                element.keyboardShortcuts,
                budget: &budget,
                key: accessibilityShortcutOrderingKey
            )
            for shortcut in shortcuts {
                try budget.consume(1)
                if let title = shortcut.discoverabilityTitle {
                    localizedTextBySubject[
                        AccessibilityLocalizationSubject(id: shortcut.id, field: .shortcutTitle),
                        default: title
                    ] = title
                }
            }
        }
        let orderedAnnouncements = try accessibilityStableSortedByBudgetedKey(
            snapshot.announcements,
            budget: &budget,
            key: accessibilityAnnouncementOrderingKey
        )
        for announcement in orderedAnnouncements {
            try budget.consume(1)
            localizedTextBySubject[
                AccessibilityLocalizationSubject(id: announcement.id, field: .announcement),
                default: announcement.message
            ] = announcement.message
        }
        let orderedLocalization = try accessibilityStableSortedByBudgetedKey(
            snapshot.evidence.localizationExpansion,
            budget: &budget,
            key: accessibilityLocalizationOrderingKey
        )
        for evidence in orderedLocalization {
            try budget.consume(1)
            if !seenLocalizationTokens.insert(evidence.token).inserted {
                try add(
                    .error,
                    .duplicateEvidenceToken,
                    subject: "localizationExpansion/" + evidence.token.rawValue,
                    identityComponents: ["localizationExpansion", evidence.token.rawValue],
                    "Localization expansion evidence token is duplicated."
                )
            }
            let hasValidSubject = try AccessibilityAuditValidation.isValidIdentifier(
                evidence.subjectID.rawValue,
                budget: &budget
            )
            let hasValidLocale = try AccessibilityAuditValidation.isValidLocaleIdentifier(
                evidence.localeIdentifier,
                budget: &budget
            )
            let isStructurallyValid =
                try AccessibilityAuditValidation.isValidIdentifier(
                    evidence.token.rawValue,
                    budget: &budget
                ) && hasValidSubject && hasValidLocale
                && !AccessibilityAuditValidation.isBlank(evidence.baselineText, budget: &budget)
                && !AccessibilityAuditValidation.isBlank(evidence.expandedText, budget: &budget)
                && !AccessibilityAuditValidation.isBlank(evidence.source, budget: &budget)
            if !isStructurallyValid {
                try add(
                    .error,
                    .invalidEvidence,
                    subject: "localizationExpansion/" + evidence.token.rawValue,
                    identityComponents: ["localizationExpansion", evidence.token.rawValue],
                    "Localization expansion evidence has invalid or blank fields."
                )
            } else if localizationByToken[evidence.token] == nil {
                localizationByToken[evidence.token] = evidence
            }
            let semanticBaseline = localizedTextBySubject[
                AccessibilityLocalizationSubject(id: evidence.subjectID, field: evidence.field)
            ]
            let normalizedSemanticBaseline = try semanticBaseline.map {
                try AccessibilityAuditValidation.normalizedText($0, budget: &budget)
            }
            let normalizedEvidenceBaseline = try AccessibilityAuditValidation.normalizedText(
                evidence.baselineText,
                budget: &budget
            )
            if normalizedSemanticBaseline != normalizedEvidenceBaseline {
                try add(
                    .error,
                    .localizationSubjectMissing,
                    subject: evidence.token.rawValue,
                    "Localization expansion baseline does not match declared subject and field."
                )
            }
            switch evidence.outcome {
            case .truncates:
                try add(
                    .error,
                    .localizationTruncates,
                    subject: evidence.token.rawValue,
                    "Caller-supplied localization expansion evidence reports truncation."
                )
            case .unknown:
                try add(
                    .warning,
                    .localizationOutcomeUnknown,
                    subject: evidence.token.rawValue,
                    "Caller-supplied localization expansion outcome is unknown."
                )
            case .fits, .wraps, .scrolls:
                break
            }
        }

        var usedContrast: Set<AccessibilityContrastEvidenceToken> = []
        var usedDifferentiation: Set<AccessibilityDifferentiateWithoutColorEvidenceToken> = []
        var usedLocalization: Set<AccessibilityLocalizationExpansionEvidenceToken> = []
        for element in orderedElements {
            try budget.consume(1)
            if element.requiresContrastEvidence, element.contrastEvidenceTokens.isEmpty {
                try add(
                    .error,
                    .requiredContrastEvidenceMissing,
                    subject: element.id.rawValue,
                    "Element requires contrast evidence but declares no evidence token."
                )
            }
            for token in element.contrastEvidenceTokens {
                try budget.consume(1)
                usedContrast.insert(token)
                if let evidence = contrastByToken[token] {
                    let supportsSurface = try element.supportsContrastSurface(
                        evidence.surface,
                        budget: &budget
                    )
                    if evidence.subjectID != element.id || !supportsSurface {
                        try add(
                            .error,
                            .contrastEvidenceSurfaceMismatch,
                            subject: element.id.rawValue + "/" + token.rawValue,
                            identityComponents: [element.id.rawValue, token.rawValue],
                            "Contrast evidence targets another subject or an inapplicable surface."
                        )
                    }
                } else {
                    try add(
                        .error,
                        .contrastEvidenceReferenceMissing,
                        subject: element.id.rawValue + "/" + token.rawValue,
                        identityComponents: [element.id.rawValue, token.rawValue],
                        "Element references missing contrast evidence."
                    )
                }
            }
            if element.usesColorToConveyMeaning,
                element.differentiateWithoutColorEvidenceTokens.isEmpty
            {
                try add(
                    .error,
                    .differentiateWithoutColorEvidenceMissing,
                    subject: element.id.rawValue,
                    "Color-conveyed meaning has no non-color differentiation evidence token."
                )
            }
            for token in element.differentiateWithoutColorEvidenceTokens {
                try budget.consume(1)
                usedDifferentiation.insert(token)
                if differentiationByToken[token] == nil {
                    try add(
                        .error,
                        .differentiateWithoutColorReferenceMissing,
                        subject: element.id.rawValue + "/" + token.rawValue,
                        identityComponents: [element.id.rawValue, token.rawValue],
                        "Element references missing differentiate-without-color evidence."
                    )
                }
            }
            if element.requiresLocalizationExpansionEvidence,
                element.localizationExpansionEvidenceTokens.isEmpty
            {
                try add(
                    .error,
                    .localizationExpansionEvidenceMissing,
                    subject: element.id.rawValue,
                    "Element requires localization expansion evidence but declares no token."
                )
            }
            var referencedLocalizationFields: Set<AccessibilityLocalizedField> = []
            for token in element.localizationExpansionEvidenceTokens {
                try budget.consume(1)
                usedLocalization.insert(token)
                if let evidence = localizationByToken[token] {
                    if evidence.subjectID != element.id
                        || ![.label, .value, .hint].contains(evidence.field)
                    {
                        try add(
                            .error,
                            .localizationExpansionReferenceMissing,
                            subject: element.id.rawValue + "/" + token.rawValue,
                            identityComponents: [element.id.rawValue, token.rawValue],
                            "Localization evidence token targets another subject or field."
                        )
                    } else {
                        referencedLocalizationFields.insert(evidence.field)
                    }
                } else {
                    try add(
                        .error,
                        .localizationExpansionReferenceMissing,
                        subject: element.id.rawValue + "/" + token.rawValue,
                        identityComponents: [element.id.rawValue, token.rawValue],
                        "Element references missing localization expansion evidence."
                    )
                }
            }
            if element.requiresLocalizationExpansionEvidence {
                for field in try element.populatedLocalizedFields(budget: &budget) {
                    try budget.consume(1)
                    guard !referencedLocalizationFields.contains(field) else { continue }
                    try add(
                        .error,
                        .localizationExpansionEvidenceMissing,
                        subject: element.id.rawValue + "/" + field.rawValue,
                        identityComponents: [element.id.rawValue, field.rawValue],
                        "Required localization expansion evidence is missing for semantic field."
                    )
                }
            }
            let actions = try accessibilityStableSortedByBudgetedKey(
                element.actions,
                budget: &budget,
                key: accessibilityActionOrderingKey
            )
            for action in actions {
                try budget.consume(1)
                let hasMatchingEvidence = try inspectLocalizationReferences(
                    action.localizationExpansionEvidenceTokens,
                    subjectID: action.id,
                    field: .actionLabel,
                    evidenceByToken: localizationByToken,
                    used: &usedLocalization
                )
                if element.requiresLocalizationExpansionEvidence,
                    try !AccessibilityAuditValidation.isBlank(action.label, budget: &budget),
                    !hasMatchingEvidence
                {
                    try add(
                        .error,
                        .localizationExpansionEvidenceMissing,
                        subject: action.id.rawValue + "/" + AccessibilityLocalizedField.actionLabel.rawValue,
                        identityComponents: [
                            action.id.rawValue, AccessibilityLocalizedField.actionLabel.rawValue
                        ],
                        "Required localization expansion evidence is missing for action label."
                    )
                }
            }
            let shortcuts = try accessibilityStableSortedByBudgetedKey(
                element.keyboardShortcuts,
                budget: &budget,
                key: accessibilityShortcutOrderingKey
            )
            for shortcut in shortcuts {
                try budget.consume(1)
                let hasMatchingEvidence = try inspectLocalizationReferences(
                    shortcut.localizationExpansionEvidenceTokens,
                    subjectID: shortcut.id,
                    field: .shortcutTitle,
                    evidenceByToken: localizationByToken,
                    used: &usedLocalization
                )
                if element.requiresLocalizationExpansionEvidence,
                    try !AccessibilityAuditValidation.isBlank(
                        shortcut.discoverabilityTitle,
                        budget: &budget
                    ),
                    !hasMatchingEvidence
                {
                    try add(
                        .error,
                        .localizationExpansionEvidenceMissing,
                        subject: shortcut.id.rawValue + "/"
                            + AccessibilityLocalizedField.shortcutTitle.rawValue,
                        identityComponents: [
                            shortcut.id.rawValue, AccessibilityLocalizedField.shortcutTitle.rawValue
                        ],
                        "Required localization expansion evidence is missing for shortcut title."
                    )
                }
            }
        }
        for announcement in orderedAnnouncements {
            try budget.consume(1)
            let hasMatchingEvidence = try inspectLocalizationReferences(
                announcement.localizationExpansionEvidenceTokens,
                subjectID: announcement.id,
                field: .announcement,
                evidenceByToken: localizationByToken,
                used: &usedLocalization
            )
            let relatedElementRequiresEvidence =
                announcement.relatedElementID.flatMap {
                    elementByID[$0]?.requiresLocalizationExpansionEvidence
                } == true
            let triggerElementRequiresEvidence =
                announcement.triggerActionID.flatMap {
                    actionOwnerByID[$0]
                }.flatMap {
                    elementByID[$0]?.requiresLocalizationExpansionEvidence
                } == true
            if relatedElementRequiresEvidence || triggerElementRequiresEvidence,
                try !AccessibilityAuditValidation.isBlank(
                    announcement.message,
                    budget: &budget
                ),
                !hasMatchingEvidence
            {
                try add(
                    .error,
                    .localizationExpansionEvidenceMissing,
                    subject: announcement.id.rawValue + "/"
                        + AccessibilityLocalizedField.announcement.rawValue,
                    identityComponents: [
                        announcement.id.rawValue, AccessibilityLocalizedField.announcement.rawValue
                    ],
                    "Required localization expansion evidence is missing for announcement."
                )
            }
        }

        for token in contrastByToken.keys {
            try budget.consume(1)
            guard !usedContrast.contains(token) else { continue }
            try add(
                .advisory,
                .orphanEvidence,
                subject: "contrast/" + token.rawValue,
                "Contrast evidence is not referenced by an element."
            )
        }
        for token in differentiationByToken.keys {
            try budget.consume(1)
            guard !usedDifferentiation.contains(token) else { continue }
            try add(
                .advisory,
                .orphanEvidence,
                subject: "differentiateWithoutColor/" + token.rawValue,
                "Differentiate-without-color evidence is not referenced by an element."
            )
        }
        for token in localizationByToken.keys {
            try budget.consume(1)
            guard !usedLocalization.contains(token) else { continue }
            try add(
                .advisory,
                .orphanEvidence,
                subject: "localizationExpansion/" + token.rawValue,
                "Localization expansion evidence is not referenced by an element."
            )
        }
    }

    private mutating func inspectLocalizationReferences(
        _ tokens: [AccessibilityLocalizationExpansionEvidenceToken],
        subjectID: AccessibilityStableID,
        field: AccessibilityLocalizedField,
        evidenceByToken:
            [AccessibilityLocalizationExpansionEvidenceToken:
            AccessibilityLocalizationExpansionEvidence],
        used: inout Set<AccessibilityLocalizationExpansionEvidenceToken>
    ) throws -> Bool {
        var hasMatchingEvidence = false
        for token in tokens {
            try budget.consume(1)
            used.insert(token)
            guard let evidence = evidenceByToken[token], evidence.subjectID == subjectID,
                evidence.field == field
            else {
                try add(
                    .error,
                    .localizationExpansionReferenceMissing,
                    subject: subjectID.rawValue + "/" + token.rawValue,
                    identityComponents: [subjectID.rawValue, token.rawValue],
                    "Localization evidence reference is missing or targets another subject or field."
                )
                continue
            }
            hasMatchingEvidence = true
        }
        return hasMatchingEvidence
    }

    private mutating func add(
        _ severity: AccessibilityAuditSeverity,
        _ code: AccessibilityAuditIssueCode,
        subject: String?,
        identityComponents: [String]? = nil,
        _ message: String
    ) throws {
        if let subject {
            try budget.consume(1)
            for _ in subject.utf8 { try budget.consume(1) }
        }
        if let identityComponents {
            for component in identityComponents {
                try budget.consume(1)
                for _ in component.utf8 { try budget.consume(1) }
            }
        }
        let issue = AccessibilityAuditIssue(
            severity: severity,
            code: code,
            subject: subject,
            identityComponents: identityComponents,
            message: message
        )
        guard issueIDs.insert(issue.id).inserted else { return }
        guard issues.count < limits.maximumIssues else {
            throw AccessibilityAuditError.issueLimitExceeded(maximum: limits.maximumIssues)
        }
        issues.append(issue)
    }
}

private enum AccessibilityAuditValidation {
    private static let hardMaximumCount = 1_000_000
    private static let hardMaximumBytes = Int(UInt32.max)
    private static let hardMaximumWork = 1_000_000_000
    private static let grandfatheredLocaleIdentifiers: Set<String> = [
        "art-lojban", "cel-gaulish", "en-GB-oed", "i-ami", "i-bnn", "i-default",
        "i-enochian", "i-hak", "i-klingon", "i-lux", "i-mingo", "i-navajo", "i-pwn",
        "i-tao", "i-tay", "i-tsu", "no-bok", "no-nyn", "sgn-BE-FR", "sgn-BE-NL",
        "sgn-CH-DE", "zh-guoyu", "zh-hakka", "zh-min", "zh-min-nan", "zh-xiang"
    ]

    static func validate(_ limits: AccessibilityAuditLimits) throws {
        try validate(limits.maximumElements, name: "maximumElements", maximum: hardMaximumCount)
        try validate(limits.maximumActions, name: "maximumActions", maximum: hardMaximumCount)
        try validate(
            limits.maximumKeyboardShortcuts,
            name: "maximumKeyboardShortcuts",
            maximum: hardMaximumCount
        )
        try validate(
            limits.maximumAnnouncements,
            name: "maximumAnnouncements",
            maximum: hardMaximumCount
        )
        try validate(
            limits.maximumEvidenceRecordsPerKind,
            name: "maximumEvidenceRecordsPerKind",
            maximum: hardMaximumCount
        )
        try validate(
            limits.maximumEvidenceReferences,
            name: "maximumEvidenceReferences",
            maximum: hardMaximumCount
        )
        try validate(
            limits.maximumStringUTF8Bytes,
            name: "maximumStringUTF8Bytes",
            maximum: hardMaximumBytes
        )
        try validate(
            limits.maximumTotalStringUTF8Bytes,
            name: "maximumTotalStringUTF8Bytes",
            maximum: hardMaximumBytes
        )
        try validate(
            limits.maximumWorkUnits,
            name: "maximumWorkUnits",
            maximum: hardMaximumWork
        )
        try validate(limits.maximumIssues, name: "maximumIssues", maximum: hardMaximumCount)
        try validate(
            limits.maximumExactSnapshotUTF8Bytes,
            name: "maximumExactSnapshotUTF8Bytes",
            maximum: hardMaximumBytes
        )
        try validate(
            limits.maximumEvidenceArchiveBytes,
            name: "maximumEvidenceArchiveBytes",
            maximum: hardMaximumBytes
        )
    }

    static func preflight(
        _ snapshot: AccessibilityCommandControlSnapshot,
        limits: AccessibilityAuditLimits,
        budget: inout AccessibilityWorkBudget
    ) throws {
        guard snapshot.elements.count <= limits.maximumElements else {
            throw AccessibilityAuditError.countLimitExceeded(
                kind: "element",
                maximum: limits.maximumElements
            )
        }
        guard snapshot.focusOrder.count <= limits.maximumElements else {
            throw AccessibilityAuditError.countLimitExceeded(
                kind: "focus-order-entry",
                maximum: limits.maximumElements
            )
        }
        guard snapshot.announcements.count <= limits.maximumAnnouncements else {
            throw AccessibilityAuditError.countLimitExceeded(
                kind: "announcement",
                maximum: limits.maximumAnnouncements
            )
        }
        var actionCount = 0
        var shortcutCount = 0
        var evidenceReferenceCount = 0
        var totalStringBytes = 0
        for element in snapshot.elements {
            try budget.consume(1)
            actionCount = try adding(element.actions.count, to: actionCount)
            guard actionCount <= limits.maximumActions else {
                throw AccessibilityAuditError.countLimitExceeded(
                    kind: "action",
                    maximum: limits.maximumActions
                )
            }
            shortcutCount = try adding(element.keyboardShortcuts.count, to: shortcutCount)
            guard shortcutCount <= limits.maximumKeyboardShortcuts else {
                throw AccessibilityAuditError.countLimitExceeded(
                    kind: "keyboard-shortcut",
                    maximum: limits.maximumKeyboardShortcuts
                )
            }
            for count in [
                element.contrastEvidenceTokens.count,
                element.differentiateWithoutColorEvidenceTokens.count,
                element.localizationExpansionEvidenceTokens.count
            ] {
                evidenceReferenceCount = try adding(count, to: evidenceReferenceCount)
                guard evidenceReferenceCount <= limits.maximumEvidenceReferences else {
                    throw AccessibilityAuditError.countLimitExceeded(
                        kind: "evidence-reference",
                        maximum: limits.maximumEvidenceReferences
                    )
                }
            }
            for action in element.actions {
                try budget.consume(1)
                evidenceReferenceCount = try adding(
                    action.localizationExpansionEvidenceTokens.count,
                    to: evidenceReferenceCount
                )
                guard evidenceReferenceCount <= limits.maximumEvidenceReferences else {
                    throw AccessibilityAuditError.countLimitExceeded(
                        kind: "evidence-reference",
                        maximum: limits.maximumEvidenceReferences
                    )
                }
            }
            for shortcut in element.keyboardShortcuts {
                try budget.consume(1)
                evidenceReferenceCount = try adding(
                    shortcut.localizationExpansionEvidenceTokens.count,
                    to: evidenceReferenceCount
                )
                guard evidenceReferenceCount <= limits.maximumEvidenceReferences else {
                    throw AccessibilityAuditError.countLimitExceeded(
                        kind: "evidence-reference",
                        maximum: limits.maximumEvidenceReferences
                    )
                }
            }
        }
        for announcement in snapshot.announcements {
            try budget.consume(1)
            evidenceReferenceCount = try adding(
                announcement.localizationExpansionEvidenceTokens.count,
                to: evidenceReferenceCount
            )
            guard evidenceReferenceCount <= limits.maximumEvidenceReferences else {
                throw AccessibilityAuditError.countLimitExceeded(
                    kind: "evidence-reference",
                    maximum: limits.maximumEvidenceReferences
                )
            }
        }
        guard actionCount <= limits.maximumActions else {
            throw AccessibilityAuditError.countLimitExceeded(
                kind: "action",
                maximum: limits.maximumActions
            )
        }
        guard shortcutCount <= limits.maximumKeyboardShortcuts else {
            throw AccessibilityAuditError.countLimitExceeded(
                kind: "keyboard-shortcut",
                maximum: limits.maximumKeyboardShortcuts
            )
        }
        guard evidenceReferenceCount <= limits.maximumEvidenceReferences else {
            throw AccessibilityAuditError.countLimitExceeded(
                kind: "evidence-reference",
                maximum: limits.maximumEvidenceReferences
            )
        }
        try consume(snapshot.id.rawValue, field: "snapshot.id", total: &totalStringBytes, limits: limits, budget: &budget)
        try consume(
            snapshot.rootElementID.rawValue,
            field: "snapshot.rootElementID",
            total: &totalStringBytes,
            limits: limits,
            budget: &budget
        )
        for element in snapshot.elements {
            try budget.consume(1)
            try consume(
                element.id.rawValue,
                field: "element.id",
                total: &totalStringBytes,
                limits: limits,
                budget: &budget
            )
            if let parentID = element.parentID {
                try consume(
                    parentID.rawValue,
                    field: "element.parentID",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
            for (field, value) in [
                ("element.label", element.label),
                ("element.value", element.value),
                ("element.hint", element.hint)
            ] {
                if let value {
                    try consume(
                        value,
                        field: field,
                        total: &totalStringBytes,
                        limits: limits,
                        budget: &budget
                    )
                }
            }
            for action in element.actions {
                try consume(
                    action.id.rawValue,
                    field: "action.id",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
                if let label = action.label {
                    try consume(
                        label,
                        field: "action.label",
                        total: &totalStringBytes,
                        limits: limits,
                        budget: &budget
                    )
                }
                for token in action.localizationExpansionEvidenceTokens {
                    try consume(
                        token.rawValue,
                        field: "action.localizationExpansionEvidenceToken",
                        total: &totalStringBytes,
                        limits: limits,
                        budget: &budget
                    )
                }
            }
            for shortcut in element.keyboardShortcuts {
                try consume(
                    shortcut.id.rawValue,
                    field: "shortcut.id",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
                try consume(
                    shortcut.key,
                    field: "shortcut.key",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
                try consume(
                    shortcut.actionID.rawValue,
                    field: "shortcut.actionID",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
                if let title = shortcut.discoverabilityTitle {
                    try consume(
                        title,
                        field: "shortcut.discoverabilityTitle",
                        total: &totalStringBytes,
                        limits: limits,
                        budget: &budget
                    )
                }
                for token in shortcut.localizationExpansionEvidenceTokens {
                    try consume(
                        token.rawValue,
                        field: "shortcut.localizationExpansionEvidenceToken",
                        total: &totalStringBytes,
                        limits: limits,
                        budget: &budget
                    )
                }
            }
            for token in element.contrastEvidenceTokens {
                try consume(
                    token.rawValue,
                    field: "element.contrastEvidenceToken",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
            for token in element.differentiateWithoutColorEvidenceTokens {
                try consume(
                    token.rawValue,
                    field: "element.differentiateWithoutColorEvidenceToken",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
            for token in element.localizationExpansionEvidenceTokens {
                try consume(
                    token.rawValue,
                    field: "element.localizationExpansionEvidenceToken",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
        }
        for id in snapshot.focusOrder {
            try consume(
                id.rawValue,
                field: "focusOrder",
                total: &totalStringBytes,
                limits: limits,
                budget: &budget
            )
        }
        for announcement in snapshot.announcements {
            try consume(
                announcement.id.rawValue,
                field: "announcement.id",
                total: &totalStringBytes,
                limits: limits,
                budget: &budget
            )
            try consume(
                announcement.message,
                field: "announcement.message",
                total: &totalStringBytes,
                limits: limits,
                budget: &budget
            )
            if let id = announcement.relatedElementID {
                try consume(
                    id.rawValue,
                    field: "announcement.relatedElementID",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
            if let id = announcement.triggerActionID {
                try consume(
                    id.rawValue,
                    field: "announcement.triggerActionID",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
            for token in announcement.localizationExpansionEvidenceTokens {
                try consume(
                    token.rawValue,
                    field: "announcement.localizationExpansionEvidenceToken",
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
        }
        try preflight(
            snapshot.evidence,
            limits: limits,
            budget: &budget,
            totalStringBytes: &totalStringBytes
        )
    }

    static func preflight(
        _ evidence: AccessibilityAuditEvidence,
        limits: AccessibilityAuditLimits,
        budget: inout AccessibilityWorkBudget
    ) throws {
        var totalStringBytes = 0
        try preflight(
            evidence,
            limits: limits,
            budget: &budget,
            totalStringBytes: &totalStringBytes
        )
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        for scalar in value.unicodeScalars {
            if scalar.properties.isWhitespace || scalar.value <= 0x1F
                || (0x7F...0x9F).contains(scalar.value)
                || scalar.properties.generalCategory == .format
                || scalar.properties.isNoncharacterCodePoint
            {
                return false
            }
        }
        return true
    }

    static func isValidIdentifier(
        _ value: String,
        budget: inout AccessibilityWorkBudget
    ) throws -> Bool {
        try budget.consume(1)
        guard !value.isEmpty else { return false }
        for scalar in value.unicodeScalars {
            try budget.consume(1)
            if scalar.properties.isWhitespace || scalar.value <= 0x1F
                || (0x7F...0x9F).contains(scalar.value)
                || scalar.properties.generalCategory == .format
                || scalar.properties.isNoncharacterCodePoint
            {
                return false
            }
        }
        return true
    }

    static func semanticTextIdentity(_ value: String) -> String {
        let scalars = value.unicodeScalars
        let first = scalars.firstIndex { !isSemanticBlankScalar($0) } ?? scalars.endIndex
        let last =
            scalars.lastIndex { !isSemanticBlankScalar($0) }.map {
                scalars.index(after: $0)
            } ?? first
        return String(scalars[first..<last]).precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func semanticTextIdentity(
        _ value: String,
        budget: inout AccessibilityWorkBudget
    ) throws -> String {
        try budget.consume(1)
        for _ in value.utf8 { try budget.consume(1) }
        return semanticTextIdentity(value)
    }

    static func normalizedText(
        _ value: String,
        budget: inout AccessibilityWorkBudget
    ) throws -> String {
        try budget.consume(1)
        for _ in value.utf8 { try budget.consume(1) }
        return value.precomposedStringWithCanonicalMapping
    }

    static func canonicalShortcutKey(_ value: String) -> String {
        guard value.utf8.count == 1, let byte = value.utf8.first, (0x41...0x5A).contains(byte)
        else {
            return value
        }
        return String(UnicodeScalar(byte + 0x20))
    }

    static func isPrintableShortcutCharacter(_ value: String) -> Bool {
        guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first else {
            return false
        }
        return scalar.value >= 0x21 && scalar.value <= 0x7E
    }

    static func isPrintableShortcutCharacter(
        _ value: String,
        budget: inout AccessibilityWorkBudget
    ) throws -> Bool {
        try budget.consume(1)
        for _ in value.utf8 { try budget.consume(1) }
        return isPrintableShortcutCharacter(value)
    }

    static func isValidShortcutKey(_ value: String) -> Bool {
        if isPrintableShortcutCharacter(value) {
            return value == canonicalShortcutKey(value)
        }
        switch value {
        case "backspace", "delete", "down", "end", "escape", "home", "left", "pagedown",
            "pageup", "return", "right", "space", "tab", "up":
            return true
        default:
            guard value.count >= 2, value.count <= 3, value.first == "f",
                let number = Int(value.dropFirst())
            else {
                return false
            }
            return (1...24).contains(number) && value == "f\(number)"
        }
    }

    static func isValidShortcutKey(
        _ value: String,
        budget: inout AccessibilityWorkBudget
    ) throws -> Bool {
        try budget.consume(1)
        for _ in value.utf8 { try budget.consume(1) }
        return isValidShortcutKey(value)
    }

    static func isValidLocaleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255, !value.contains("_") else { return false }
        if grandfatheredLocaleIdentifiers.contains(value) { return true }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        var index = 0
        if parts[0] == "x" {
            return parts.count > 1 && parts.dropFirst().allSatisfy(isLowercaseAlphaNumericSubtag)
        }
        guard (2...8).contains(parts[0].count), isLowercaseAlphaSubtag(parts[0]) else {
            return false
        }
        index += 1
        if parts[0].count <= 3 {
            var extlangCount = 0
            while index < parts.count, parts[index].count == 3,
                isLowercaseAlphaSubtag(parts[index]), extlangCount < 3
            {
                index += 1
                extlangCount += 1
            }
        }
        if index < parts.count, parts[index].count == 4 {
            let script = parts[index]
            guard isTitlecaseAlphaSubtag(script) else { return false }
            index += 1
        }
        if index < parts.count {
            let region = parts[index]
            if (region.count == 2 && isUppercaseAlphaSubtag(region))
                || (region.count == 3 && region.utf8.allSatisfy({ (0x30...0x39).contains($0) }))
            {
                index += 1
            }
        }
        var variants: Set<Substring> = []
        while index < parts.count, isCanonicalVariant(parts[index]) {
            guard variants.insert(parts[index]).inserted else { return false }
            index += 1
        }
        var extensionSingletons: Set<Substring> = []
        while index < parts.count, parts[index].count == 1, parts[index] != "x" {
            let singleton = parts[index]
            guard isLowercaseAlphaNumericSubtag(singleton),
                extensionSingletons.insert(singleton).inserted
            else {
                return false
            }
            index += 1
            let extensionStart = index
            while index < parts.count, (2...8).contains(parts[index].count),
                isLowercaseAlphaNumericSubtag(parts[index])
            {
                index += 1
            }
            guard index > extensionStart else { return false }
        }
        if index < parts.count, parts[index] == "x" {
            index += 1
            let privateUseStart = index
            while index < parts.count, isLowercaseAlphaNumericSubtag(parts[index]) {
                index += 1
            }
            guard index > privateUseStart else { return false }
        }
        return index == parts.count
    }

    static func isValidLocaleIdentifier(
        _ value: String,
        budget: inout AccessibilityWorkBudget
    ) throws -> Bool {
        try budget.consume(1)
        for _ in value.utf8 { try budget.consume(1) }
        return isValidLocaleIdentifier(value)
    }

    private static func isLowercaseAlphaSubtag(_ value: Substring) -> Bool {
        value.utf8.allSatisfy { (0x61...0x7A).contains($0) }
    }

    private static func isUppercaseAlphaSubtag(_ value: Substring) -> Bool {
        value.utf8.allSatisfy { (0x41...0x5A).contains($0) }
    }

    private static func isTitlecaseAlphaSubtag(_ value: Substring) -> Bool {
        guard let first = value.utf8.first, (0x41...0x5A).contains(first) else { return false }
        return value.utf8.dropFirst().allSatisfy { (0x61...0x7A).contains($0) }
    }

    private static func isLowercaseAlphaNumericSubtag(_ value: Substring) -> Bool {
        (1...8).contains(value.count)
            && value.utf8.allSatisfy {
                (0x30...0x39).contains($0) || (0x61...0x7A).contains($0)
            }
    }

    private static func isCanonicalVariant(_ value: Substring) -> Bool {
        guard isLowercaseAlphaNumericSubtag(value) else { return false }
        return (5...8).contains(value.count)
            || (value.count == 4 && value.utf8.first.map { (0x30...0x39).contains($0) } == true)
    }

    static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.unicodeScalars.allSatisfy(isSemanticBlankScalar)
    }

    static func isBlank(
        _ value: String?,
        budget: inout AccessibilityWorkBudget
    ) throws -> Bool {
        guard let value else {
            try budget.consume(1)
            return true
        }
        for scalar in value.unicodeScalars {
            try budget.consume(1)
            if !isSemanticBlankScalar(scalar) { return false }
        }
        return true
    }

    private static func isSemanticBlankScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar.properties.generalCategory == .format
            || scalar.properties.isNoncharacterCodePoint || scalar.value <= 0x1F
            || (0x7F...0x9F).contains(scalar.value)
    }

    private static func preflight(
        _ evidence: AccessibilityAuditEvidence,
        limits: AccessibilityAuditLimits,
        budget: inout AccessibilityWorkBudget,
        totalStringBytes: inout Int
    ) throws {
        for (kind, count) in [
            ("contrast-evidence", evidence.contrast.count),
            ("differentiate-without-color-evidence", evidence.differentiateWithoutColor.count),
            ("localization-expansion-evidence", evidence.localizationExpansion.count)
        ] where count > limits.maximumEvidenceRecordsPerKind {
            throw AccessibilityAuditError.countLimitExceeded(
                kind: kind,
                maximum: limits.maximumEvidenceRecordsPerKind
            )
        }
        for item in evidence.contrast {
            try budget.consume(1)
            try consume(item.token.rawValue, field: "contrast.token", total: &totalStringBytes, limits: limits, budget: &budget)
            try consume(item.subjectID.rawValue, field: "contrast.subjectID", total: &totalStringBytes, limits: limits, budget: &budget)
            try consume(item.source, field: "contrast.source", total: &totalStringBytes, limits: limits, budget: &budget)
        }
        for item in evidence.differentiateWithoutColor {
            try budget.consume(1)
            try consume(item.token.rawValue, field: "differentiateWithoutColor.token", total: &totalStringBytes, limits: limits, budget: &budget)
            try consume(item.meaning, field: "differentiateWithoutColor.meaning", total: &totalStringBytes, limits: limits, budget: &budget)
            try consume(item.source, field: "differentiateWithoutColor.source", total: &totalStringBytes, limits: limits, budget: &budget)
        }
        for item in evidence.localizationExpansion {
            try budget.consume(1)
            for (field, value) in [
                ("localizationExpansion.token", item.token.rawValue),
                ("localizationExpansion.subjectID", item.subjectID.rawValue),
                ("localizationExpansion.localeIdentifier", item.localeIdentifier),
                ("localizationExpansion.baselineText", item.baselineText),
                ("localizationExpansion.expandedText", item.expandedText),
                ("localizationExpansion.source", item.source)
            ] {
                try consume(
                    value,
                    field: field,
                    total: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
        }
    }

    private static func validate(_ value: Int, name: String, maximum: Int) throws {
        guard value >= 0, value <= maximum else {
            throw AccessibilityAuditError.invalidLimit(
                name: name,
                value: value,
                maximum: maximum
            )
        }
    }

    private static func consume(
        _ value: String,
        field: String,
        total: inout Int,
        limits: AccessibilityAuditLimits,
        budget: inout AccessibilityWorkBudget
    ) throws {
        try budget.consume(1)
        var count = 0
        for _ in value.utf8 {
            if count == limits.maximumStringUTF8Bytes {
                throw AccessibilityAuditError.stringTooLarge(
                    field: field,
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            if count == limits.maximumTotalStringUTF8Bytes - total {
                throw AccessibilityAuditError.totalStringsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
                )
            }
            count += 1
            try budget.consume(1)
        }
        total += count
    }

    private static func adding(_ value: Int, to total: Int) throws -> Int {
        let (result, overflow) = total.addingReportingOverflow(value)
        guard !overflow else {
            throw AccessibilityAuditError.countLimitExceeded(kind: "nested-value", maximum: .max)
        }
        return result
    }
}

private final class AccessibilityWorkBudgetStorage {
    var consumed = 0
}

private struct AccessibilityWorkBudget {
    private let storage: AccessibilityWorkBudgetStorage
    let maximum: Int

    init(maximum: Int) {
        storage = AccessibilityWorkBudgetStorage()
        self.maximum = maximum
    }

    mutating func consume(_ amount: Int) throws {
        try Task.checkCancellation()
        guard amount >= 0, amount <= maximum - storage.consumed else {
            throw AccessibilityAuditError.workLimitExceeded(maximum: maximum)
        }
        storage.consumed += amount
    }

    func remaining(after amount: Int) -> Int? {
        guard amount >= 0, amount <= maximum - storage.consumed else { return nil }
        return maximum - storage.consumed - amount
    }
}

private func accessibilityEqualData(
    _ left: Data,
    _ right: Data,
    budget: inout AccessibilityWorkBudget
) throws -> Bool {
    try Task.checkCancellation()
    guard left.count == right.count else { return false }
    var leftStart = left.startIndex
    var rightStart = right.startIndex
    var offset = 0
    while leftStart != left.endIndex {
        AccessibilityAuditTestHooks.canonicalArchiveComparisonCheckpoint?(offset)
        let count = min(4_096, left.distance(from: leftStart, to: left.endIndex))
        let leftEnd = left.index(leftStart, offsetBy: count)
        let rightEnd = right.index(rightStart, offsetBy: count)
        try budget.consume(count + 1)
        guard left[leftStart..<leftEnd].elementsEqual(right[rightStart..<rightEnd]) else {
            return false
        }
        leftStart = leftEnd
        rightStart = rightEnd
        offset += count
    }
    return true
}

private enum AccessibilityExactSnapshotEncoder {
    static func encode(
        _ snapshot: AccessibilityCommandControlSnapshot,
        issues: [AccessibilityAuditIssue],
        limits: AccessibilityAuditLimits,
        budget: inout AccessibilityWorkBudget
    ) throws -> String {
        var output = AccessibilitySnapshotOutput(
            maximumBytes: limits.maximumExactSnapshotUTF8Bytes,
            budget: budget
        )
        try output.append("MACMERGE-ACCESSIBILITY-SNAPSHOT\t")
        try output.appendInteger(AccessibilityAudit.exactSnapshotFormatVersion)
        try output.append("\nSCOPE\t")
        try output.appendField(AccessibilityAuditReport.scopeStatement)
        try output.append("\nSNAPSHOT\t")
        try output.appendField(snapshot.id.rawValue)
        try output.append("\tROOT\t")
        try output.appendField(snapshot.rootElementID.rawValue)
        try output.append("\n")

        let elements = try accessibilityStableSortedByBudgetedKey(
            snapshot.elements,
            budget: &budget,
            key: accessibilityElementOrderingKey
        )
        for element in elements {
            try budget.consume(1)
            try output.append("ELEMENT\t")
            try output.appendField(element.id.rawValue)
            try output.append("\tPARENT\t")
            try output.appendOptionalField(element.parentID?.rawValue)
            try output.append("\tROLE\t")
            try output.appendField(element.role.rawValue)
            try output.append("\tLABEL\t")
            try output.appendOptionalField(element.label)
            try output.append("\tVALUE\t")
            try output.appendOptionalField(element.value)
            try output.append("\tHINT\t")
            try output.appendOptionalField(element.hint)
            try output.append("\tENABLED\t")
            try output.appendBoolean(element.isEnabled)
            try output.append("\tCHECKED\t")
            try output.appendField(element.checkedState.rawValue)
            try output.append("\tSELECTED\t")
            try output.appendField(element.selectedState.rawValue)
            try output.append("\tHIDDEN\t")
            try output.appendBoolean(element.isHiddenFromAssistiveTechnology)
            try output.append("\tFOCUSABLE\t")
            try output.appendBoolean(element.isKeyboardFocusable)
            try output.append("\tCONTRAST-REQUIRED\t")
            try output.appendBoolean(element.requiresContrastEvidence)
            try output.append("\tUSES-COLOR\t")
            try output.appendBoolean(element.usesColorToConveyMeaning)
            try output.append("\tLOCALIZATION-REQUIRED\t")
            try output.appendBoolean(element.requiresLocalizationExpansionEvidence)
            try output.append("\n")

            let actions = try accessibilityStableSortedByBudgetedKey(
                element.actions,
                budget: &budget,
                key: accessibilityActionOrderingKey
            )
            for action in actions {
                try budget.consume(1)
                try output.append("ACTION\t")
                try output.appendField(element.id.rawValue)
                try output.append("\t")
                try output.appendField(action.id.rawValue)
                try output.append("\t")
                try output.appendField(action.kind.rawValue)
                try output.append("\t")
                try output.appendOptionalField(action.label)
                try output.append("\n")
                try appendTokens(
                    action.localizationExpansionEvidenceTokens,
                    prefix: "LOCALIZATION-REF",
                    owner: action.id,
                    output: &output,
                    budget: &budget
                )
            }

            let shortcuts = try accessibilityStableSortedByBudgetedKey(
                element.keyboardShortcuts,
                budget: &budget,
                key: accessibilityShortcutOrderingKey
            )
            for shortcut in shortcuts {
                try budget.consume(1)
                try output.append("SHORTCUT\t")
                try output.appendField(element.id.rawValue)
                try output.append("\t")
                try output.appendField(shortcut.id.rawValue)
                try output.append("\t")
                try output.appendField(
                    accessibilityCanonicalChord(shortcut, budget: &budget)
                )
                try output.append("\t")
                try output.appendField(shortcut.actionID.rawValue)
                try output.append("\t")
                try output.appendOptionalField(shortcut.discoverabilityTitle)
                try output.append("\n")
                try appendTokens(
                    shortcut.localizationExpansionEvidenceTokens,
                    prefix: "LOCALIZATION-REF",
                    owner: shortcut.id,
                    output: &output,
                    budget: &budget
                )
            }
            try appendTokens(
                element.contrastEvidenceTokens,
                prefix: "CONTRAST-REF",
                owner: element.id,
                output: &output,
                budget: &budget
            )
            try appendTokens(
                element.differentiateWithoutColorEvidenceTokens,
                prefix: "NONCOLOR-REF",
                owner: element.id,
                output: &output,
                budget: &budget
            )
            try appendTokens(
                element.localizationExpansionEvidenceTokens,
                prefix: "LOCALIZATION-REF",
                owner: element.id,
                output: &output,
                budget: &budget
            )
        }

        for (index, id) in snapshot.focusOrder.enumerated() {
            try budget.consume(1)
            try output.append("FOCUS\t")
            try output.appendInteger(index)
            try output.append("\t")
            try output.appendField(id.rawValue)
            try output.append("\n")
        }

        let announcements = try accessibilityStableSortedByBudgetedKey(
            snapshot.announcements,
            budget: &budget,
            key: accessibilityAnnouncementOrderingKey
        )
        for announcement in announcements {
            try budget.consume(1)
            try output.append("ANNOUNCEMENT\t")
            try output.appendField(announcement.id.rawValue)
            try output.append("\t")
            try output.appendField(announcement.kind.rawValue)
            try output.append("\t")
            try output.appendField(announcement.message)
            try output.append("\tELEMENT\t")
            try output.appendOptionalField(announcement.relatedElementID?.rawValue)
            try output.append("\tACTION\t")
            try output.appendOptionalField(announcement.triggerActionID?.rawValue)
            try output.append("\n")
            try appendTokens(
                announcement.localizationExpansionEvidenceTokens,
                prefix: "LOCALIZATION-REF",
                owner: announcement.id,
                output: &output,
                budget: &budget
            )
        }

        let contrast = try accessibilityStableSortedByBudgetedKey(
            snapshot.evidence.contrast,
            budget: &budget,
            key: accessibilityContrastOrderingKey
        )
        for evidence in contrast {
            try budget.consume(1)
            try output.append("CONTRAST\t")
            try output.appendField(evidence.token.rawValue)
            try output.append("\t")
            try output.appendField(evidence.subjectID.rawValue)
            try output.append("\t")
            try output.appendField(evidence.surface.rawValue)
            try output.append("\tMEASURED-THOUSANDTHS\t")
            try output.appendInteger(evidence.measuredRatioThousandths)
            try output.append("\tREQUIRED-THOUSANDTHS\t")
            try output.appendInteger(evidence.requiredRatioThousandths)
            try output.append("\t")
            try output.appendField(evidence.origin.rawValue)
            try output.append("\t")
            try output.appendField(evidence.source)
            try output.append("\n")
        }

        let differentiation = try accessibilityStableSortedByBudgetedKey(
            snapshot.evidence.differentiateWithoutColor,
            budget: &budget,
            key: accessibilityDifferentiationOrderingKey
        )
        for evidence in differentiation {
            try budget.consume(1)
            var cueValues: [String] = []
            for cue in AccessibilityNonColorCue.allCases {
                try budget.consume(1)
                if evidence.nonColorCues.contains(cue) { cueValues.append(cue.rawValue) }
            }
            let cues = cueValues.joined(separator: ",")
            try output.append("NONCOLOR\t")
            try output.appendField(evidence.token.rawValue)
            try output.append("\t")
            try output.appendField(evidence.meaning)
            try output.append("\t")
            try output.appendField(cues)
            try output.append("\t")
            try output.appendField(evidence.origin.rawValue)
            try output.append("\t")
            try output.appendField(evidence.source)
            try output.append("\n")
        }

        let localization = try accessibilityStableSortedByBudgetedKey(
            snapshot.evidence.localizationExpansion,
            budget: &budget,
            key: accessibilityLocalizationOrderingKey
        )
        for evidence in localization {
            try budget.consume(1)
            try output.append("LOCALIZATION\t")
            try output.appendField(evidence.token.rawValue)
            try output.append("\t")
            try output.appendField(evidence.subjectID.rawValue)
            try output.append("\t")
            try output.appendField(evidence.field.rawValue)
            try output.append("\t")
            try output.appendField(evidence.localeIdentifier)
            try output.append("\t")
            try output.appendField(evidence.baselineText)
            try output.append("\t")
            try output.appendField(evidence.expandedText)
            try output.append("\t")
            try output.appendField(evidence.outcome.rawValue)
            try output.append("\t")
            try output.appendField(evidence.origin.rawValue)
            try output.append("\t")
            try output.appendField(evidence.source)
            try output.append("\n")
        }

        for issue in issues {
            try output.append("ISSUE\t")
            try output.appendField(issue.severity.rawValue)
            try output.append("\t")
            try output.appendField(issue.code.rawValue)
            try output.append("\t")
            try output.appendOptionalField(issue.subject)
            try output.append("\t")
            try output.appendField(issue.message)
            try output.append("\n")
        }
        try output.append("END\n")
        return output.value
    }

    private static func appendTokens<Token: RawRepresentable>(
        _ tokens: [Token],
        prefix: String,
        owner: AccessibilityStableID,
        output: inout AccessibilitySnapshotOutput,
        budget: inout AccessibilityWorkBudget
    ) throws where Token.RawValue == String {
        let tokens = try accessibilitySortedTokenStrings(
            accessibilityTokenStrings(tokens, budget: &budget),
            budget: &budget
        )
        for token in tokens {
            try output.append(prefix)
            try output.append("\t")
            try output.appendField(owner.rawValue)
            try output.append("\t")
            try output.appendField(token)
            try output.append("\n")
        }
    }
}

private struct AccessibilitySnapshotOutput {
    private(set) var value = ""
    private(set) var byteCount = 0
    private let maximumBytes: Int
    private var budget: AccessibilityWorkBudget

    init(maximumBytes: Int, budget: AccessibilityWorkBudget) {
        self.maximumBytes = maximumBytes
        self.budget = budget
        value.reserveCapacity(min(maximumBytes, 4_096))
    }

    mutating func append(_ string: String) throws {
        try budget.consume(1)
        var count = 0
        let maximumCount = min(maximumBytes - byteCount, budget.remaining(after: 0) ?? 0)
        for _ in string.utf8 {
            if count == maximumCount {
                if maximumCount == maximumBytes - byteCount {
                    throw AccessibilityAuditError.exactSnapshotTooLarge(
                        maximumUTF8Bytes: maximumBytes
                    )
                }
                throw AccessibilityAuditError.workLimitExceeded(maximum: budget.maximum)
            }
            count += 1
            try budget.consume(1)
        }
        value.append(string)
        byteCount += count
    }

    mutating func appendInteger(_ integer: Int) throws {
        try append(String(integer))
    }

    mutating func appendBoolean(_ value: Bool) throws {
        try append(value ? "true" : "false")
    }

    mutating func appendOptionalField(_ field: String?) throws {
        guard let field else {
            try append("-")
            return
        }
        try appendField(field)
    }

    mutating func appendField(_ field: String) throws {
        let isSingleHyphen = field == "-"
        for (index, scalar) in field.unicodeScalars.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            switch scalar.value {
            case 0x09: try append("\\t")
            case 0x0A: try append("\\n")
            case 0x0D: try append("\\r")
            case 0x5C: try append("\\\\")
            case 0x2D where isSingleHyphen:
                try append("\\-")
            case let value where value <= 0x1F || (0x7F...0x9F).contains(value):
                try append("\\u{")
                try append(String(value, radix: 16, uppercase: true))
                try append("}")
            default:
                try append(String(scalar))
            }
        }
    }
}

private struct AccessibilityEvidenceWriter {
    private(set) var data = Data()
    private let maximumBytes: Int
    private var budget: AccessibilityWorkBudget

    init(maximumBytes: Int, budget: AccessibilityWorkBudget) {
        self.maximumBytes = maximumBytes
        self.budget = budget
        data.reserveCapacity(min(maximumBytes, 4_096))
    }

    mutating func append(_ string: String) throws {
        let lengthOffset = data.count
        try appendUInt32(0)
        let start = data.endIndex
        try appendRawCollection(string.utf8)
        guard let length = UInt32(exactly: data.distance(from: start, to: data.endIndex)) else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        try overwriteUInt32(length, at: lengthOffset)
    }

    mutating func appendCount(_ value: Int) throws {
        guard value >= 0, value <= Int(UInt32.max) else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        try appendUInt32(UInt32(value))
    }

    mutating func appendInteger(_ value: Int) throws {
        guard let wireValue = Int64(exactly: value) else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        try appendUInt64(UInt64(bitPattern: wireValue))
    }

    mutating func appendEnum<Value: RawRepresentable>(
        _ value: Value,
        allCases: [Value]
    ) throws where Value.RawValue == String {
        var isKnown = false
        for candidate in allCases {
            try budget.consume(1)
            if candidate.rawValue == value.rawValue {
                isKnown = true
                break
            }
        }
        guard isKnown else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        try append(value.rawValue)
    }

    mutating func appendCueMask(_ cues: Set<AccessibilityNonColorCue>) throws {
        var orderedCues: [AccessibilityNonColorCue] = []
        for cue in AccessibilityNonColorCue.allCases {
            try budget.consume(1)
            if cues.contains(cue) { orderedCues.append(cue) }
        }
        try appendCount(orderedCues.count)
        for cue in orderedCues {
            try budget.consume(1)
            try append(cue.rawValue)
        }
    }

    mutating func appendUInt16(_ value: UInt16) throws {
        try appendRaw([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8)
        ])
    }

    mutating func appendUInt32(_ value: UInt32) throws {
        try appendRaw((0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32($0 * 8)) })
    }

    mutating func appendUInt64(_ value: UInt64) throws {
        try appendRaw((0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64($0 * 8)) })
    }

    mutating func overwriteUInt32(_ value: UInt32, at offset: Int) throws {
        try overwrite(
            (0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32($0 * 8)) },
            at: offset
        )
    }

    mutating func overwriteUInt64(_ value: UInt64, at offset: Int) throws {
        try overwrite(
            (0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64($0 * 8)) },
            at: offset
        )
    }

    mutating func appendRaw(_ bytes: [UInt8]) throws {
        try appendRawCollection(bytes)
    }

    mutating func appendRaw(_ bytes: Data) throws {
        try appendRawCollection(bytes)
    }

    private mutating func appendRawCollection<Bytes: Collection>(_ bytes: Bytes) throws
    where Bytes.Element == UInt8 {
        var start = bytes.startIndex
        while start != bytes.endIndex {
            let end =
                bytes.index(start, offsetBy: 4_096, limitedBy: bytes.endIndex)
                ?? bytes.endIndex
            let chunk = bytes[start..<end]
            let count = chunk.count
            guard count <= maximumBytes - data.count else {
                throw AccessibilityAuditError.evidenceArchiveTooLarge(maximumBytes: maximumBytes)
            }
            try budget.consume(count + 1)
            data.append(contentsOf: chunk)
            start = end
        }
    }

    private mutating func overwrite(_ bytes: [UInt8], at offset: Int) throws {
        try budget.consume(bytes.count + 1)
        guard offset >= data.startIndex, offset <= data.endIndex - bytes.count else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
}

private struct AccessibilityEvidenceReader {
    private let bytes: Data
    private var index: Data.Index
    private var totalStringBytes = 0
    private let limits: AccessibilityAuditLimits
    private var budget: AccessibilityWorkBudget
    private(set) var hasCanonicalStringsAndCollections = true

    init(data: Data, limits: AccessibilityAuditLimits, budget: AccessibilityWorkBudget) {
        bytes = data
        index = data.startIndex
        self.limits = limits
        self.budget = budget
    }

    var remainingCount: Int { bytes.distance(from: index, to: bytes.endIndex) }
    var isAtEnd: Bool { index == bytes.endIndex }

    mutating func readRaw(count: Int) throws -> Data {
        try budget.consume(count + 1)
        guard count >= 0, count <= remainingCount else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        let end = bytes.index(index, offsetBy: count)
        defer { index = end }
        return bytes[index..<end]
    }

    mutating func readUInt16() throws -> UInt16 {
        let value = try readRaw(count: 2)
        return value.enumerated().reduce(into: UInt16(0)) {
            $0 |= UInt16($1.element) << UInt16($1.offset * 8)
        }
    }

    mutating func readUInt32() throws -> UInt32 {
        let value = try readRaw(count: 4)
        return value.enumerated().reduce(into: UInt32(0)) {
            $0 |= UInt32($1.element) << UInt32($1.offset * 8)
        }
    }

    mutating func readUInt64() throws -> UInt64 {
        let value = try readRaw(count: 8)
        return value.enumerated().reduce(into: UInt64(0)) {
            $0 |= UInt64($1.element) << UInt64($1.offset * 8)
        }
    }

    mutating func readInteger() throws -> Int {
        let wireValue = Int64(bitPattern: try readUInt64())
        guard let value = Int(exactly: wireValue) else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        return value
    }

    mutating func readString() throws -> String {
        let count = Int(try readUInt32())
        guard count <= limits.maximumStringUTF8Bytes else {
            throw AccessibilityAuditError.stringTooLarge(
                field: "evidenceArchive",
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        guard count <= limits.maximumTotalStringUTF8Bytes - totalStringBytes else {
            throw AccessibilityAuditError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        totalStringBytes += count
        let bytes = try readRaw(count: count)
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        let canonicalUTF8 = string.precomposedStringWithCanonicalMapping.utf8
        if !bytes.elementsEqual(canonicalUTF8) {
            hasCanonicalStringsAndCollections = false
        }
        return string
    }

    mutating func readSchemaTag() throws -> String {
        let count = Int(try readUInt32())
        guard count <= 64 else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        let bytes = try readRaw(count: count)
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        return string
    }

    mutating func readCount(
        maximum: Int,
        kind: String,
        minimumRecordBytes: Int
    ) throws -> Int {
        let count = Int(try readUInt32())
        guard count <= maximum else {
            throw AccessibilityAuditError.countLimitExceeded(kind: kind, maximum: maximum)
        }
        guard count <= remainingCount / minimumRecordBytes else {
            throw AccessibilityAuditError.invalidEvidenceArchive
        }
        return count
    }

    mutating func readEnum<Value>(_ type: Value.Type) throws -> Value
    where Value: CaseIterable & RawRepresentable, Value.RawValue == String {
        let raw = try readSchemaTag()
        for value in Value.allCases {
            try budget.consume(1)
            if value.rawValue == raw { return value }
        }
        throw AccessibilityAuditError.invalidEvidenceArchive
    }

    mutating func readCueMask() throws -> Set<AccessibilityNonColorCue> {
        let count = try readCount(
            maximum: AccessibilityNonColorCue.allCases.count,
            kind: "non-color-cue",
            minimumRecordBytes: 5
        )
        var cues: Set<AccessibilityNonColorCue> = []
        var previousIndex: Int?
        for _ in 0..<count {
            try budget.consume(1)
            let raw = try readSchemaTag()
            guard let cue = AccessibilityNonColorCue(rawValue: raw),
                let index = AccessibilityNonColorCue.allCases.firstIndex(of: cue),
                cues.insert(cue).inserted
            else {
                throw AccessibilityAuditError.invalidEvidenceArchive
            }
            if let previousIndex, index <= previousIndex {
                hasCanonicalStringsAndCollections = false
            }
            previousIndex = index
        }
        return cues
    }
}

private func accessibilityStableSortedByBudgetedKey<Value>(
    _ values: [Value],
    budget: inout AccessibilityWorkBudget,
    key: (Value, inout AccessibilityWorkBudget) throws -> [UInt8]
) throws -> [Value] {
    guard values.count > 1 else { return values }
    try Task.checkCancellation()
    try accessibilityConsumeSortAllocations(values.count, budget: &budget)
    var source: [(offset: Int, key: [UInt8], element: Value)] = []
    source.reserveCapacity(values.count)
    for (offset, value) in values.enumerated() {
        try budget.consume(1)
        source.append((offset, try key(value, &budget), value))
    }
    var destination = source
    var width = 1
    while width < source.count {
        try budget.consume(source.count)
        var lowerBound = 0
        while lowerBound < source.count {
            let middle = min(lowerBound + width, source.count)
            let upperBound = min(middle + width, source.count)
            var left = lowerBound
            var right = middle
            var output = lowerBound
            while left < middle, right < upperBound {
                try budget.consume(min(source[right].key.count, source[left].key.count) + 1)
                let comparison = accessibilityCompareBytes(source[right].key, source[left].key)
                if comparison < 0 {
                    destination[output] = source[right]
                    right += 1
                } else {
                    destination[output] = source[left]
                    left += 1
                }
                output += 1
            }
            while left < middle {
                destination[output] = source[left]
                left += 1
                output += 1
            }
            while right < upperBound {
                destination[output] = source[right]
                right += 1
                output += 1
            }
            lowerBound = upperBound
        }
        swap(&source, &destination)
        width = width > source.count / 2 ? source.count : width * 2
    }
    var result: [Value] = []
    result.reserveCapacity(source.count)
    for item in source {
        try budget.consume(1)
        result.append(item.element)
    }
    return result
}

private func accessibilityConsumeSortAllocations(
    _ count: Int,
    budget: inout AccessibilityWorkBudget
) throws {
    guard count <= Int.max / 3 else {
        throw AccessibilityAuditError.workLimitExceeded(maximum: budget.maximum)
    }
    try budget.consume(count * 3)
}

private func accessibilityOrderingKey(
    _ components: [String],
    budget: inout AccessibilityWorkBudget
) throws -> [UInt8] {
    var result: [UInt8] = []
    for component in components {
        try budget.consume(8)
        let lengthOffset = result.count
        result.append(contentsOf: repeatElement(0, count: 8))
        var length: UInt64 = 0
        for byte in component.utf8 {
            try budget.consume(1)
            guard length < UInt64.max else {
                throw AccessibilityAuditError.workLimitExceeded(maximum: budget.maximum)
            }
            result.append(byte)
            length += 1
        }
        for offset in 0..<8 {
            result[lengthOffset + offset] = UInt8(
                truncatingIfNeeded: length >> UInt64(offset * 8)
            )
        }
    }
    return result
}

private func accessibilityLengthPrefixed(_ value: String) -> String {
    String(value.utf8.count) + ":" + value
}

private func accessibilityElementOrderingKey(
    _ element: AccessibilitySemanticElement,
    budget: inout AccessibilityWorkBudget
) throws -> [UInt8] {
    let actions = try accessibilityStableSortedByBudgetedKey(
        element.actions,
        budget: &budget,
        key: accessibilityActionOrderingKey
    )
    let shortcuts = try accessibilityStableSortedByBudgetedKey(
        element.keyboardShortcuts,
        budget: &budget,
        key: accessibilityShortcutOrderingKey
    )
    let contrastTokens = try accessibilitySortedTokenStrings(
        accessibilityTokenStrings(element.contrastEvidenceTokens, budget: &budget),
        budget: &budget
    )
    let differentiationTokens = try accessibilitySortedTokenStrings(
        accessibilityTokenStrings(
            element.differentiateWithoutColorEvidenceTokens,
            budget: &budget
        ),
        budget: &budget
    )
    let localizationTokens = try accessibilitySortedTokenStrings(
        accessibilityTokenStrings(
            element.localizationExpansionEvidenceTokens,
            budget: &budget
        ),
        budget: &budget
    )
    let contrastTokenKey = try accessibilityTokenListKey(contrastTokens, budget: &budget)
    let differentiationTokenKey = try accessibilityTokenListKey(
        differentiationTokens,
        budget: &budget
    )
    let localizationTokenKey = try accessibilityTokenListKey(
        localizationTokens,
        budget: &budget
    )
    var result = try accessibilityOrderingKey(
        [
            element.id.rawValue,
            element.parentID == nil ? "0" : "1",
            element.parentID?.rawValue ?? "",
            element.role.rawValue,
            element.label == nil ? "0" : "1",
            element.label ?? "",
            element.value == nil ? "0" : "1",
            element.value ?? "",
            element.hint == nil ? "0" : "1",
            element.hint ?? "",
            String(element.isEnabled),
            element.checkedState.rawValue,
            element.selectedState.rawValue,
            String(element.isHiddenFromAssistiveTechnology),
            String(element.isKeyboardFocusable),
            String(element.requiresContrastEvidence),
            String(element.usesColorToConveyMeaning),
            String(element.requiresLocalizationExpansionEvidence),
            contrastTokenKey,
            differentiationTokenKey,
            localizationTokenKey,
            String(element.actions.count),
            String(element.keyboardShortcuts.count)
        ], budget: &budget)
    for action in actions {
        result.append(contentsOf: try accessibilityActionOrderingKey(action, budget: &budget))
    }
    for shortcut in shortcuts {
        result.append(contentsOf: try accessibilityShortcutOrderingKey(shortcut, budget: &budget))
    }
    return result
}

private func accessibilityActionOrderingKey(
    _ action: AccessibilitySemanticAction,
    budget: inout AccessibilityWorkBudget
) throws -> [UInt8] {
    let tokens = try accessibilitySortedTokenStrings(
        accessibilityTokenStrings(
            action.localizationExpansionEvidenceTokens,
            budget: &budget
        ),
        budget: &budget
    )
    let tokenKey = try accessibilityTokenListKey(tokens, budget: &budget)
    return try accessibilityOrderingKey(
        [
            action.id.rawValue,
            action.kind.rawValue,
            action.label == nil ? "0" : "1",
            action.label ?? "",
            tokenKey
        ], budget: &budget)
}

private func accessibilityShortcutOrderingKey(
    _ shortcut: AccessibilityKeyboardShortcut,
    budget: inout AccessibilityWorkBudget
) throws -> [UInt8] {
    let tokens = try accessibilitySortedTokenStrings(
        accessibilityTokenStrings(
            shortcut.localizationExpansionEvidenceTokens,
            budget: &budget
        ),
        budget: &budget
    )
    let tokenKey = try accessibilityTokenListKey(tokens, budget: &budget)
    return try accessibilityOrderingKey(
        [
            shortcut.id.rawValue,
            accessibilityCanonicalChord(shortcut, budget: &budget),
            shortcut.actionID.rawValue,
            shortcut.discoverabilityTitle == nil ? "0" : "1",
            shortcut.discoverabilityTitle ?? "",
            tokenKey
        ], budget: &budget)
}

private func accessibilityAnnouncementOrderingKey(
    _ announcement: AccessibilityAnnouncement,
    budget: inout AccessibilityWorkBudget
) throws -> [UInt8] {
    let tokens = try accessibilitySortedTokenStrings(
        accessibilityTokenStrings(
            announcement.localizationExpansionEvidenceTokens,
            budget: &budget
        ),
        budget: &budget
    )
    let tokenKey = try accessibilityTokenListKey(tokens, budget: &budget)
    return try accessibilityOrderingKey(
        [
            announcement.id.rawValue,
            announcement.kind.rawValue,
            announcement.message,
            announcement.relatedElementID == nil ? "0" : "1",
            announcement.relatedElementID?.rawValue ?? "",
            announcement.triggerActionID == nil ? "0" : "1",
            announcement.triggerActionID?.rawValue ?? "",
            tokenKey
        ], budget: &budget)
}

private func accessibilityContrastOrderingKey(
    _ evidence: AccessibilityContrastEvidence,
    budget: inout AccessibilityWorkBudget
) throws -> [UInt8] {
    try accessibilityOrderingKey(
        [
            evidence.token.rawValue,
            evidence.subjectID.rawValue,
            evidence.surface.rawValue,
            String(evidence.measuredRatioThousandths),
            String(evidence.requiredRatioThousandths),
            evidence.origin.rawValue,
            evidence.source
        ], budget: &budget)
}

private func accessibilityDifferentiationOrderingKey(
    _ evidence: AccessibilityDifferentiateWithoutColorEvidence,
    budget: inout AccessibilityWorkBudget
) throws -> [UInt8] {
    var cueValues: [String] = []
    for cue in AccessibilityNonColorCue.allCases {
        try budget.consume(1)
        if evidence.nonColorCues.contains(cue) { cueValues.append(cue.rawValue) }
    }
    let cues = cueValues.joined(separator: ",")
    return try accessibilityOrderingKey(
        [
            evidence.token.rawValue,
            evidence.meaning,
            cues,
            evidence.origin.rawValue,
            evidence.source
        ], budget: &budget)
}

private func accessibilityLocalizationOrderingKey(
    _ evidence: AccessibilityLocalizationExpansionEvidence,
    budget: inout AccessibilityWorkBudget
) throws -> [UInt8] {
    try accessibilityOrderingKey(
        [
            evidence.token.rawValue,
            evidence.subjectID.rawValue,
            evidence.field.rawValue,
            evidence.localeIdentifier,
            evidence.baselineText,
            evidence.expandedText,
            evidence.outcome.rawValue,
            evidence.origin.rawValue,
            evidence.source
        ], budget: &budget)
}

private func accessibilityDecimalDigitCount(_ value: Int) -> Int {
    var value = value
    var count = 1
    while value >= 10 {
        value /= 10
        count += 1
    }
    return count
}

private func accessibilityCanonicalChord(
    _ shortcut: AccessibilityKeyboardShortcut,
    budget: inout AccessibilityWorkBudget
) throws -> String {
    var modifiers: [String] = []
    for modifier in AccessibilityKeyboardModifier.allCases {
        try budget.consume(1)
        if shortcut.modifiers.contains(modifier) { modifiers.append(modifier.rawValue) }
    }
    var keyBytes: [UInt8] = []
    for byte in shortcut.key.utf8 {
        try budget.consume(1)
        keyBytes.append(byte)
    }
    if keyBytes.count == 1, (0x41...0x5A).contains(keyBytes[0]) {
        keyBytes[0] += 0x20
    }
    let key = String(decoding: keyBytes, as: UTF8.self)
    let chord = modifiers.joined(separator: "+") + ":" + String(keyBytes.count) + ":" + key
    try budget.consume(1)
    for _ in chord.utf8 { try budget.consume(1) }
    return chord
}

private func accessibilityTokenListKey(
    _ tokens: [String],
    budget: inout AccessibilityWorkBudget
) throws -> String {
    var result = accessibilityLengthPrefixed(String(tokens.count))
    for token in tokens {
        try budget.consume(1)
        for _ in token.utf8 { try budget.consume(1) }
        result.append(accessibilityLengthPrefixed(token))
    }
    return result
}

private func accessibilityTokenStrings<Token: RawRepresentable>(
    _ tokens: [Token],
    budget: inout AccessibilityWorkBudget
) throws -> [String] where Token.RawValue == String {
    var result: [String] = []
    result.reserveCapacity(tokens.count)
    for token in tokens {
        try budget.consume(1)
        result.append(token.rawValue)
    }
    return result
}

private func accessibilitySortedTokenStrings(
    _ tokens: [String],
    budget: inout AccessibilityWorkBudget
) throws -> [String] {
    try accessibilityStableSortedByBudgetedKey(
        tokens,
        budget: &budget,
        key: { token, budget in
            var key: [UInt8] = []
            for byte in token.utf8 {
                try budget.consume(1)
                key.append(byte)
            }
            return key
        }
    )
}

private func accessibilityUnorderedEqual<Value: Hashable>(
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

private func accessibilityCompareBytes(_ left: [UInt8], _ right: [UInt8]) -> Int {
    for (leftByte, rightByte) in zip(left, right) {
        if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
    }
    if left.count == right.count { return 0 }
    return left.count < right.count ? -1 : 1
}

private func accessibilityCompareUTF8(_ left: String, _ right: String) -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        switch (leftIterator.next(), rightIterator.next()) {
        case (let leftByte?, let rightByte?):
            if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
        case (nil, nil):
            return 0
        case (nil, _?):
            return -1
        case (_?, nil):
            return 1
        }
    }
}

private func accessibilityCompareUTF8(
    _ left: String,
    _ right: String,
    budget: inout AccessibilityWorkBudget
) throws -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        try budget.consume(1)
        switch (leftIterator.next(), rightIterator.next()) {
        case (let leftByte?, let rightByte?):
            if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
        case (nil, nil):
            return 0
        case (nil, _?):
            return -1
        case (_?, nil):
            return 1
        }
    }
}

private func accessibilityFNV1a64(
    _ data: Data,
    budget: inout AccessibilityWorkBudget
) throws -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
        try budget.consume(1)
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return hash
}
