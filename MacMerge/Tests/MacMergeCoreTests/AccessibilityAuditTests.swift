import Foundation
import XCTest

@testable import MacMergeCore

final class AccessibilityAuditTests: XCTestCase {
    func testRoleSpecificSemanticContentMatrix() throws {
        let expectedMismatches: [AccessibilitySemanticRole: Set<String>] = [
            .application: ["value", "hint"],
            .window: ["value", "hint"],
            .dialog: ["value", "hint"],
            .alert: ["value", "hint"],
            .group: ["value", "hint"],
            .toolbar: ["value", "hint"],
            .button: ["value"],
            .toggle: ["value"],
            .checkBox: ["value"],
            .radioButton: ["value"],
            .link: ["value"],
            .textField: [],
            .searchField: [],
            .comboBox: [],
            .menu: ["value", "hint"],
            .menuItem: ["value"],
            .tabList: ["value", "hint"],
            .tab: ["value"],
            .list: ["value", "hint"],
            .listItem: [],
            .table: ["value", "hint"],
            .row: [],
            .cell: [],
            .tree: ["value", "hint"],
            .treeItem: [],
            .slider: [],
            .stepper: [],
            .progressIndicator: [],
            .image: ["value"],
            .staticText: [],
            .heading: [],
            .separator: ["value", "hint"],
            .command: ["value"],
            .customControl: [],
            .presentation: ["label", "value", "hint"]
        ]
        let children = AccessibilitySemanticRole.allCases.map { role in
            AccessibilitySemanticElement(
                id: id("role-\(role.rawValue)"),
                parentID: id("root"),
                role: role,
                label: "Label",
                value: "Value",
                hint: "Hint",
                isEnabled: false,
                checkedState: checkedState(for: role),
                selectedState: selectedState(for: role)
            )
        }

        let report = try AccessibilityAudit.audit(snapshot(children))
        let expected = AccessibilitySemanticRole.allCases.flatMap { role in
            (expectedMismatches[role] ?? []).map { field in
                expectedIssue(
                    .error,
                    .semanticContentRoleMismatch,
                    subject: "role-\(role.rawValue)/\(field)",
                    identityComponents: ["role-\(role.rawValue)", field],
                    message: "Semantic content field is not applicable to declared role."
                )
            }
        }
        XCTAssertEqual(issueDictionary(report), issueDictionary(expected))
    }

    func testImageAndCustomControlActionRulesRemainDistinct() throws {
        let image = AccessibilitySemanticElement(
            id: id("image"),
            parentID: id("root"),
            role: .image,
            label: "Preview",
            isEnabled: false,
            actions: [
                action("image-custom", .custom, label: "Describe"),
                action("image-activate", .activate)
            ]
        )
        let custom = AccessibilitySemanticElement(
            id: id("custom"),
            parentID: id("root"),
            role: .customControl,
            label: "Canvas",
            isEnabled: false,
            actions: AccessibilitySemanticActionKind.allCases.map {
                action(
                    "custom-\($0.rawValue)",
                    $0,
                    label: $0 == .custom ? "Inspect" : nil
                )
            }
        )
        let emptyCustom = AccessibilitySemanticElement(
            id: id("empty-custom"),
            parentID: id("root"),
            role: .customControl,
            label: "Enabled canvas"
        )

        let report = try AccessibilityAudit.audit(snapshot([image, custom, emptyCustom]))

        XCTAssertEqual(
            Set(issues(report, .actionRoleMismatch).compactMap(\.subject)),
            ["image/image-activate"]
        )
        XCTAssertEqual(
            Set(issues(report, .missingRequiredAction).compactMap(\.subject)),
            ["empty-custom/action"]
        )
    }

    func testActionCompatibilityMatrixForEveryRoleAndActionKind() throws {
        var elements: [AccessibilitySemanticElement] = []
        var expectedMismatches: Set<String> = []
        for role in AccessibilitySemanticRole.allCases {
            for kind in AccessibilitySemanticActionKind.allCases {
                let elementID = "compat-\(role.rawValue)-\(kind.rawValue)"
                let actionID = "action-\(role.rawValue)-\(kind.rawValue)"
                elements.append(
                    AccessibilitySemanticElement(
                        id: id(elementID),
                        parentID: id("root"),
                        role: role,
                        label: "Label",
                        isEnabled: false,
                        checkedState: checkedState(for: role),
                        selectedState: selectedState(for: role),
                        actions: [
                            action(actionID, kind, label: kind == .custom ? "Custom" : nil)
                        ]
                    )
                )
                if !allowedActions(for: role).contains(kind) {
                    expectedMismatches.insert("\(elementID)/\(actionID)")
                }
            }
        }

        let report = try AccessibilityAudit.audit(snapshot(elements))

        let expected = expectedMismatches.map { subject in
            let components = subject.split(separator: "/").map(String.init)
            return expectedIssue(
                .error,
                .actionRoleMismatch,
                subject: subject,
                identityComponents: components,
                message: "Action kind is not applicable to declared role."
            )
        }
        let presentationContentIssues = AccessibilitySemanticActionKind.allCases.map { kind in
            let elementID = "compat-presentation-\(kind.rawValue)"
            return expectedIssue(
                .error,
                .semanticContentRoleMismatch,
                subject: "\(elementID)/label",
                identityComponents: [elementID, "label"],
                message: "Semantic content field is not applicable to declared role."
            )
        }
        XCTAssertEqual(issueDictionary(report), issueDictionary(expected + presentationContentIssues))
    }

    func testRadioButtonCheckedStateIsBinaryAndRequired() throws {
        let states: [(String, AccessibilityCheckedState)] = [
            ("off", .off),
            ("on", .on),
            ("mixed", .mixed),
            ("missing", .notApplicable)
        ]
        let radios = states.map { name, state in
            AccessibilitySemanticElement(
                id: id("radio-\(name)"),
                parentID: id("root"),
                role: .radioButton,
                label: name,
                isEnabled: false,
                checkedState: state
            )
        }

        let report = try AccessibilityAudit.audit(snapshot(radios))

        XCTAssertEqual(
            Set(issues(report, .checkedStateRoleMismatch).compactMap(\.subject)),
            ["radio-mixed"]
        )
        XCTAssertEqual(
            Set(issues(report, .missingRequiredState).compactMap(\.subject)),
            ["radio-missing/checked"]
        )
    }

    func testRequiredSetValueShowMenuAndCustomActions() throws {
        let text = focusableElement("text", role: .textField, actions: [])
        let search = focusableElement(
            "search",
            role: .searchField,
            actions: [action("search-set", .setValue)]
        )
        let combo = focusableElement(
            "combo",
            role: .comboBox,
            actions: [action("combo-set", .setValue)]
        )
        let slider = focusableElement(
            "slider",
            role: .slider,
            actions: [action("slider-up", .increment), action("slider-down", .decrement)]
        )
        let menu = focusableElement("menu", role: .menu, actions: [])
        let custom = focusableElement("custom", role: .customControl, actions: [])
        let elements = [text, search, combo, slider, menu, custom]

        let report = try AccessibilityAudit.audit(
            snapshot(elements, focusOrder: elements.map(\.id))
        )

        XCTAssertEqual(
            Set(issues(report, .missingRequiredAction).compactMap(\.subject)),
            ["text/setValue", "combo/showMenu", "slider/setValue", "custom/action"]
        )
    }

    func testKeyboardAccessRequiresFocusOrValidUniqueShortcutForEachAction() throws {
        let missing = AccessibilitySemanticElement(
            id: id("missing"),
            parentID: id("root"),
            role: .button,
            label: "Missing",
            actions: [action("missing-activate", .activate)]
        )
        let focused = focusableElement(
            "focused",
            role: .button,
            actions: [action("focused-activate", .activate)]
        )
        let shortcut = AccessibilitySemanticElement(
            id: id("shortcut"),
            parentID: id("root"),
            role: .button,
            label: "Shortcut",
            actions: [action("shortcut-activate", .activate)],
            keyboardShortcuts: [
                keyboardShortcut("shortcut-id", key: "k", actionID: "shortcut-activate")
            ]
        )
        let invalidShortcutID = AccessibilitySemanticElement(
            id: id("invalid-id"),
            parentID: id("root"),
            role: .button,
            label: "Invalid ID",
            actions: [action("invalid-id-activate", .activate)],
            keyboardShortcuts: [
                keyboardShortcut("bad id", key: "i", actionID: "invalid-id-activate")
            ]
        )
        let roleInvalidAction = AccessibilitySemanticElement(
            id: id("role-invalid"),
            parentID: id("root"),
            role: .image,
            label: "Image",
            actions: [action("role-invalid-activate", .activate)]
        )

        let report = try AccessibilityAudit.audit(
            snapshot(
                [missing, focused, shortcut, invalidShortcutID, roleInvalidAction],
                focusOrder: [focused.id]
            )
        )

        XCTAssertEqual(
            Set(issues(report, .keyboardAccessMissing).compactMap(\.subject)),
            ["missing/missing-activate", "invalid-id/invalid-id-activate"]
        )
        XCTAssertTrue(
            issues(report, .invalidStableIdentifier).contains { $0.subject == "bad id" }
        )
    }

    func testShortcutPhysicalKeyGrammarCanonicalChordAndGlobalIdentity() throws {
        let validKeys = [
            "a", "!", "backspace", "delete", "down", "end", "escape", "home", "left",
            "pagedown", "pageup", "return", "right", "space", "tab", "up", "f1", "f24"
        ]
        let invalidKeys = ["A", "F1", "f0", "f25", "f01", " ", "é", "🙂", "enter", ""]
        var elements: [AccessibilitySemanticElement] = []
        for (index, key) in (validKeys + invalidKeys).enumerated() {
            let elementID = "key-\(index)"
            let actionID = "key-action-\(index)"
            elements.append(
                AccessibilitySemanticElement(
                    id: id(elementID),
                    parentID: id("root"),
                    role: .button,
                    label: key.isEmpty ? "Empty" : key,
                    isEnabled: false,
                    actions: [action(actionID, .activate)],
                    keyboardShortcuts: [
                        keyboardShortcut("key-shortcut-\(index)", key: key, actionID: actionID)
                    ]
                )
            )
        }
        let globallyReusedID = AccessibilitySemanticElement(
            id: id("reused"),
            parentID: id("root"),
            role: .button,
            label: "Reused",
            isEnabled: false,
            actions: [action("shared-semantic-id", .activate)],
            keyboardShortcuts: [
                keyboardShortcut("shared-semantic-id", key: "r", actionID: "shared-semantic-id")
            ]
        )
        elements.append(globallyReusedID)

        let report = try AccessibilityAudit.audit(snapshot(elements))

        var expected = invalidKeys.indices.map { offset in
            let index = validKeys.count + offset
            return expectedIssue(
                .error,
                .invalidKeyboardShortcut,
                subject: "key-shortcut-\(index)",
                message: "Keyboard shortcut key must use canonical physical-key grammar."
            )
        }
        expected.append(
            expectedIssue(
                .error,
                .duplicateKeyboardShortcut,
                subject: "command:1:a",
                identityComponents: ["command:1:a"],
                message: "Keyboard shortcut chord is assigned more than once."
            )
        )
        expected.append(
            expectedIssue(
                .error,
                .duplicateStableIdentifier,
                subject: "shared-semantic-id",
                message: "Action stable identifier is duplicated."
            )
        )
        expected.append(
            expectedIssue(
                .error,
                .shortcutTargetsUnknownAction,
                subject: "reused/command:1:r",
                identityComponents: ["reused", "command:1:r"],
                message: "Keyboard shortcut does not target an action on its element."
            )
        )
        expected.append(
            expectedIssue(
                .error,
                .missingControlLabel,
                subject: "key-23",
                message: "Exposed control or image has no nonblank semantic label."
            )
        )
        expected.append(
            expectedIssue(
                .warning,
                .emptySemanticText,
                subject: "key-23/label",
                message: "Semantic text is present but blank."
            )
        )
        XCTAssertEqual(issueDictionary(report), issueDictionary(expected))
        let shortcut = AccessibilityKeyboardShortcut(
            id: id("chord"),
            key: "A",
            modifiers: [.shift, .command, .option, .control, .function],
            actionID: id("action")
        )
        XCTAssertEqual(
            shortcut.canonicalChord,
            "command+control+option+shift+function:1:a"
        )
    }

    func testUnmodifiedPrintableAndCanonicalDuplicateShortcutsDoNotProvideAccess() throws {
        let unmodified = AccessibilitySemanticElement(
            id: id("unmodified"),
            parentID: id("root"),
            role: .button,
            label: "Unmodified",
            actions: [action("unmodified-action", .activate)],
            keyboardShortcuts: [
                keyboardShortcut(
                    "unmodified-shortcut",
                    key: "u",
                    actionID: "unmodified-action",
                    modifiers: []
                )
            ]
        )
        let duplicateOne = AccessibilitySemanticElement(
            id: id("duplicate-one"),
            parentID: id("root"),
            role: .button,
            label: "Duplicate one",
            actions: [action("duplicate-one-action", .activate)],
            keyboardShortcuts: [
                keyboardShortcut(
                    "duplicate-one-shortcut",
                    key: "k",
                    actionID: "duplicate-one-action"
                )
            ]
        )
        let duplicateTwo = AccessibilitySemanticElement(
            id: id("duplicate-two"),
            parentID: id("root"),
            role: .button,
            label: "Duplicate two",
            actions: [action("duplicate-two-action", .activate)],
            keyboardShortcuts: [
                keyboardShortcut(
                    "duplicate-two-shortcut",
                    key: "k",
                    actionID: "duplicate-two-action"
                )
            ]
        )

        let report = try AccessibilityAudit.audit(
            snapshot([unmodified, duplicateOne, duplicateTwo])
        )

        XCTAssertEqual(
            issueDictionary(report),
            issueDictionary(
                [
                    expectedIssue(
                        .error,
                        .duplicateKeyboardShortcut,
                        subject: "command:1:k",
                        identityComponents: ["command:1:k"],
                        message: "Keyboard shortcut chord is assigned more than once."
                    ),
                    expectedIssue(
                        .error,
                        .unmodifiedKeyboardShortcut,
                        subject: "unmodified/:1:u",
                        identityComponents: ["unmodified", ":1:u"],
                        message: "Single-character keyboard shortcut has no modifier."
                    )
                ]
                    + [
                        "duplicate-one/duplicate-one-action",
                        "duplicate-two/duplicate-two-action",
                        "unmodified/unmodified-action"
                    ].map { subject in
                        expectedIssue(
                            .error,
                            .keyboardAccessMissing,
                            subject: subject,
                            identityComponents: subject.split(separator: "/").map(String.init),
                            message: "Enabled action has no valid keyboard shortcut."
                        )
                    }
            )
        )
    }

    func testDuplicateShortcutIDsDoNotProvideKeyboardAccessToUniqueActions() throws {
        let first = AccessibilitySemanticElement(
            id: id("first"),
            parentID: id("root"),
            role: .button,
            label: "First",
            actions: [action("first-action", .activate)],
            keyboardShortcuts: [
                keyboardShortcut(
                    "shared-shortcut",
                    key: "f",
                    actionID: "first-action"
                )
            ]
        )
        let second = AccessibilitySemanticElement(
            id: id("second"),
            parentID: id("root"),
            role: .button,
            label: "Second",
            actions: [action("second-action", .activate)],
            keyboardShortcuts: [
                keyboardShortcut(
                    "shared-shortcut",
                    key: "s",
                    actionID: "second-action"
                )
            ]
        )

        let report = try AccessibilityAudit.audit(snapshot([first, second]))

        XCTAssertEqual(
            issueDictionary(report),
            issueDictionary(
                [
                    expectedIssue(
                        .error,
                        .duplicateStableIdentifier,
                        subject: "shared-shortcut",
                        message: "Stable identifier is reused by multiple semantic subjects."
                    )
                ]
                    + ["first/first-action", "second/second-action"].map { subject in
                        expectedIssue(
                            .error,
                            .keyboardAccessMissing,
                            subject: subject,
                            identityComponents: subject.split(separator: "/").map(String.init),
                            message: "Enabled action has no valid keyboard shortcut."
                        )
                    }
            )
        )
    }

    func testInvalidAndDanglingDuplicateChordsDoNotPoisonValidKeyboardAccess() throws {
        let valid = AccessibilitySemanticElement(
            id: id("valid"),
            parentID: id("root"),
            role: .button,
            label: "Valid",
            actions: [action("valid-action", .activate)],
            keyboardShortcuts: [
                keyboardShortcut("valid-shortcut", key: "k", actionID: "valid-action")
            ]
        )
        let invalid = AccessibilitySemanticElement(
            id: id("invalid"),
            parentID: id("root"),
            role: .button,
            label: "Invalid",
            isEnabled: false,
            actions: [action("invalid-action", .activate)],
            keyboardShortcuts: [
                keyboardShortcut("invalid-shortcut", key: "K", actionID: "invalid-action")
            ]
        )
        let dangling = AccessibilitySemanticElement(
            id: id("dangling"),
            parentID: id("root"),
            role: .button,
            label: "Dangling",
            isEnabled: false,
            actions: [action("dangling-action", .activate)],
            keyboardShortcuts: [
                keyboardShortcut("dangling-shortcut", key: "k", actionID: "missing-action")
            ]
        )

        let report = try AccessibilityAudit.audit(snapshot([valid, invalid, dangling]))

        XCTAssertFalse(
            issues(report, .keyboardAccessMissing).contains { $0.subject == "valid/valid-action" }
        )
        XCTAssertEqual(issues(report, .invalidKeyboardShortcut).count, 1)
        XCTAssertEqual(issues(report, .shortcutTargetsUnknownAction).count, 1)
        XCTAssertEqual(issues(report, .duplicateKeyboardShortcut).count, 1)
    }

    func testContrastSurfaceMatrixForEveryRoleAndSurface() throws {
        var elements: [AccessibilitySemanticElement] = []
        var evidence: [AccessibilityContrastEvidence] = []
        var expected: [IssueDescriptor] = []
        for role in AccessibilitySemanticRole.allCases {
            for surface in AccessibilityContrastSurface.allCases {
                let elementID = "surface-\(role.rawValue)-\(surface.rawValue)"
                let token = "token-\(role.rawValue)-\(surface.rawValue)"
                let supportsFocus = supportsKeyboardFocus(for: role)
                let hasText = role != .presentation
                let supportsSurface = supportsContrastSurface(
                    surface,
                    role: role,
                    hasText: hasText,
                    isKeyboardFocusable: supportsFocus
                )
                elements.append(
                    AccessibilitySemanticElement(
                        id: id(elementID),
                        parentID: id("root"),
                        role: role,
                        label: hasText ? "Label" : nil,
                        isEnabled: false,
                        checkedState: checkedState(for: role),
                        selectedState: selectedState(for: role),
                        isKeyboardFocusable: supportsFocus,
                        contrastEvidenceTokens: [contrastToken(token)]
                    )
                )
                evidence.append(contrast(token, subject: elementID, surface: surface))
                if !supportsSurface {
                    expected.append(
                        expectedIssue(
                            .error,
                            .contrastEvidenceSurfaceMismatch,
                            subject: "contrast/\(token)",
                            identityComponents: ["contrast", token, "surface"],
                            message: "Contrast evidence surface is inapplicable to its semantic subject."
                        )
                    )
                    expected.append(
                        expectedIssue(
                            .error,
                            .contrastEvidenceSurfaceMismatch,
                            subject: "\(elementID)/\(token)",
                            identityComponents: [elementID, token],
                            message: "Contrast evidence targets another subject or an inapplicable surface."
                        )
                    )
                }
            }
        }

        let report = try AccessibilityAudit.audit(
            snapshot(elements, evidence: AccessibilityAuditEvidence(contrast: evidence))
        )

        XCTAssertEqual(issueDictionary(report), issueDictionary(expected))
    }

    func testLocalizationBaselineMatrixForEveryField() throws {
        let tokens = Dictionary(
            uniqueKeysWithValues: AccessibilityLocalizedField.allCases.map {
                ($0, localizationToken("baseline-\($0.rawValue)"))
            }
        )
        let action = AccessibilitySemanticAction(
            id: id("baseline-action"),
            kind: .custom,
            label: "Action",
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.actionLabel])]
        )
        let shortcut = AccessibilityKeyboardShortcut(
            id: id("baseline-shortcut"),
            key: "b",
            modifiers: [.command],
            actionID: action.id,
            discoverabilityTitle: "Shortcut",
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.shortcutTitle])]
        )
        let element = AccessibilitySemanticElement(
            id: id("baseline-element"),
            parentID: id("root"),
            role: .customControl,
            label: "Label",
            value: "Value",
            hint: "Hint",
            isEnabled: false,
            actions: [action],
            keyboardShortcuts: [shortcut],
            localizationExpansionEvidenceTokens: [
                try XCTUnwrap(tokens[.label]),
                try XCTUnwrap(tokens[.value]),
                try XCTUnwrap(tokens[.hint])
            ]
        )
        let announcement = AccessibilityAnnouncement(
            id: id("baseline-announcement"),
            kind: .status,
            message: "Announcement",
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.announcement])]
        )
        let subjects: [AccessibilityLocalizedField: String] = [
            .label: "baseline-element",
            .value: "baseline-element",
            .hint: "baseline-element",
            .actionLabel: "baseline-action",
            .shortcutTitle: "baseline-shortcut",
            .announcement: "baseline-announcement"
        ]
        let localizationEvidence = try AccessibilityLocalizedField.allCases.map { field in
            localization(
                "baseline-\(field.rawValue)",
                subject: try XCTUnwrap(subjects[field]),
                field: field,
                baseline: "Wrong baseline"
            )
        }

        let report = try AccessibilityAudit.audit(
            snapshot(
                [element],
                announcements: [announcement],
                evidence: AccessibilityAuditEvidence(localizationExpansion: localizationEvidence)
            )
        )
        let expected = AccessibilityLocalizedField.allCases.map { field in
            expectedIssue(
                .error,
                .localizationSubjectMissing,
                subject: "baseline-\(field.rawValue)",
                message: "Localization expansion baseline does not match declared subject and field."
            )
        }
        XCTAssertEqual(issueDictionary(report), issueDictionary(expected))
    }

    func testLocalizationBaselinesCompareNFCNormalizedSemanticAndEvidenceText() throws {
        let decomposed = "Cafe\u{301}"
        let composed = decomposed.precomposedStringWithCanonicalMapping
        let tokens = Dictionary(
            uniqueKeysWithValues: AccessibilityLocalizedField.allCases.map {
                ($0, localizationToken("nfc-\($0.rawValue)"))
            }
        )
        let action = AccessibilitySemanticAction(
            id: id("nfc-action"),
            kind: .custom,
            label: decomposed,
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.actionLabel])]
        )
        let shortcut = AccessibilityKeyboardShortcut(
            id: id("nfc-shortcut"),
            key: "n",
            modifiers: [.command],
            actionID: action.id,
            discoverabilityTitle: decomposed,
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.shortcutTitle])]
        )
        let element = AccessibilitySemanticElement(
            id: id("nfc-element"),
            parentID: id("root"),
            role: .customControl,
            label: decomposed,
            value: decomposed,
            hint: decomposed,
            isEnabled: false,
            actions: [action],
            keyboardShortcuts: [shortcut],
            localizationExpansionEvidenceTokens: [
                try XCTUnwrap(tokens[.label]),
                try XCTUnwrap(tokens[.value]),
                try XCTUnwrap(tokens[.hint])
            ]
        )
        let announcement = AccessibilityAnnouncement(
            id: id("nfc-announcement"),
            kind: .status,
            message: decomposed,
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.announcement])]
        )
        let subjects: [AccessibilityLocalizedField: String] = [
            .label: "nfc-element",
            .value: "nfc-element",
            .hint: "nfc-element",
            .actionLabel: "nfc-action",
            .shortcutTitle: "nfc-shortcut",
            .announcement: "nfc-announcement"
        ]
        let evidence = try AccessibilityLocalizedField.allCases.map { field in
            localization(
                "nfc-\(field.rawValue)",
                subject: try XCTUnwrap(subjects[field]),
                field: field,
                baseline: composed
            )
        }

        let report = try AccessibilityAudit.audit(
            snapshot(
                [element],
                announcements: [announcement],
                evidence: AccessibilityAuditEvidence(localizationExpansion: evidence)
            )
        )

        XCTAssertTrue(issues(report, .localizationSubjectMissing).isEmpty)
    }

    func testBroadPositiveRoleActionStateShortcutAndEvidenceTablesHaveNoIssues() throws {
        let roleElements = AccessibilitySemanticRole.allCases.map { role in
            let elementID = "positive-\(role.rawValue)"
            return AccessibilitySemanticElement(
                id: id(elementID),
                parentID: id("root"),
                role: role,
                label: role == .presentation ? nil : "Label",
                checkedState: checkedState(for: role),
                selectedState: selectedState(for: role),
                isKeyboardFocusable: supportsKeyboardFocus(for: role),
                actions: requiredActions(for: role).enumerated().map { index, kind in
                    action(
                        "positive-\(role.rawValue)-action-\(index)",
                        kind,
                        label: kind == .custom ? "Custom" : nil
                    )
                }
            )
        }
        let evidenceElements = [
            AccessibilitySemanticElement(
                id: id("positive-text"),
                parentID: id("root"),
                role: .staticText,
                label: "Text",
                contrastEvidenceTokens: [
                    contrastToken("positive-text"), contrastToken("positive-large-text")
                ]
            ),
            AccessibilitySemanticElement(
                id: id("positive-graphic"),
                parentID: id("root"),
                role: .image,
                label: "Graphic",
                contrastEvidenceTokens: [contrastToken("positive-graphic")],
                usesColorToConveyMeaning: true,
                differentiateWithoutColorEvidenceTokens: [nonColorToken("positive-noncolor")]
            ),
            AccessibilitySemanticElement(
                id: id("positive-focus"),
                parentID: id("root"),
                role: .button,
                label: "Focus",
                isKeyboardFocusable: true,
                actions: [action("positive-focus-action", .activate)],
                contrastEvidenceTokens: [contrastToken("positive-focus")]
            ),
            AccessibilitySemanticElement(
                id: id("positive-custom"),
                parentID: id("root"),
                role: .customControl,
                label: "Custom",
                isEnabled: false,
                actions: [action("positive-custom-action", .custom, label: "Custom")],
                contrastEvidenceTokens: [contrastToken("positive-custom")]
            )
        ]
        let localizationElements = [
            ("fits", AccessibilityLocalizationExpansionOutcome.fits),
            ("wraps", .wraps),
            ("scrolls", .scrolls)
        ].map { name, _ in
            AccessibilitySemanticElement(
                id: id("positive-localization-\(name)"),
                parentID: id("root"),
                role: .staticText,
                label: name,
                localizationExpansionEvidenceTokens: [localizationToken(name)]
            )
        }
        let announcements = AccessibilityAnnouncementKind.allCases.map { kind in
            AccessibilityAnnouncement(
                id: id("positive-announcement-\(kind.rawValue)"),
                kind: kind,
                message: "Message"
            )
        }
        let allElements = roleElements + evidenceElements + localizationElements
        let focusOrder = allElements.filter(\.isKeyboardFocusable).map(\.id)
        let evidence = AccessibilityAuditEvidence(
            contrast: [
                contrast("positive-text", subject: "positive-text", surface: .text),
                contrast("positive-large-text", subject: "positive-text", surface: .largeText),
                contrast("positive-graphic", subject: "positive-graphic"),
                contrast("positive-focus", subject: "positive-focus", surface: .focusIndicator),
                contrast("positive-custom", subject: "positive-custom", surface: .custom)
            ],
            differentiateWithoutColor: [
                AccessibilityDifferentiateWithoutColorEvidence(
                    token: nonColorToken("positive-noncolor"),
                    meaning: "Difference",
                    nonColorCues: Set(AccessibilityNonColorCue.allCases),
                    origin: .callerAssertion,
                    source: "source"
                )
            ],
            localizationExpansion: [
                ("fits", AccessibilityLocalizationExpansionOutcome.fits),
                ("wraps", .wraps),
                ("scrolls", .scrolls)
            ].map { name, outcome in
                AccessibilityLocalizationExpansionEvidence(
                    token: localizationToken(name),
                    subjectID: id("positive-localization-\(name)"),
                    field: .label,
                    localeIdentifier: "de-DE",
                    baselineText: name,
                    expandedText: "Expanded \(name)",
                    outcome: outcome,
                    origin: .manualMeasurement,
                    source: "source"
                )
            }
        )

        let report = try AccessibilityAudit.audit(
            snapshot(
                allElements,
                focusOrder: focusOrder,
                announcements: announcements,
                evidence: evidence
            )
        )

        XCTAssertEqual(report.issues, [])
    }

    func testDuplicateCustomActionLabelsUseTrimmedCanonicalCaseInsensitiveIdentity() throws {
        let first = AccessibilitySemanticElement(
            id: id("first"),
            parentID: id("root"),
            role: .customControl,
            label: "First",
            isEnabled: false,
            actions: [
                action("first-one", .custom, label: "  Édit  "),
                action("first-two", .custom, label: "e\u{301}DIT")
            ]
        )
        let second = AccessibilitySemanticElement(
            id: id("second"),
            parentID: id("root"),
            role: .customControl,
            label: "Second",
            isEnabled: false,
            actions: [action("second-one", .custom, label: "ÉDIT")]
        )

        let report = try AccessibilityAudit.audit(snapshot([first, second]))

        XCTAssertEqual(issues(report, .duplicateCustomActionLabel).count, 1)
        XCTAssertEqual(issues(report, .duplicateCustomActionLabel).first?.subject, "first/édit")
    }

    func testEvidenceTokenNamespacesDoNotCollide() throws {
        let shared = "shared"
        let element = AccessibilitySemanticElement(
            id: id("image"),
            parentID: id("root"),
            role: .image,
            label: "Preview",
            contrastEvidenceTokens: [contrastToken(shared)],
            differentiateWithoutColorEvidenceTokens: [nonColorToken(shared)],
            localizationExpansionEvidenceTokens: [localizationToken(shared)]
        )
        let evidence = AccessibilityAuditEvidence(
            contrast: [contrast(shared, subject: "image", surface: .graphicalObject)],
            differentiateWithoutColor: [nonColor(shared)],
            localizationExpansion: [
                localization(shared, subject: "image", field: .label, baseline: "Preview")
            ]
        )

        let report = try AccessibilityAudit.audit(snapshot([element], evidence: evidence))

        XCTAssertTrue(issues(report, .duplicateEvidenceToken).isEmpty)
        XCTAssertTrue(issues(report, .invalidEvidence).isEmpty)
    }

    func testDuplicateEvidenceDetectionIsNamespacedAndIndependentOfInvalidRecords() throws {
        let evidence = AccessibilityAuditEvidence(
            contrast: [
                contrast("dup", subject: "root", source: ""),
                contrast("dup", subject: "root", source: "")
            ],
            differentiateWithoutColor: [
                nonColor("dup", meaning: "", source: "source"),
                nonColor("dup", meaning: "", source: "source")
            ],
            localizationExpansion: [
                localization("dup", subject: "root", locale: "en_US"),
                localization("dup", subject: "root", locale: "en_US")
            ]
        )

        let report = try AccessibilityAudit.audit(snapshot([], evidence: evidence))

        XCTAssertEqual(
            Set(issues(report, .duplicateEvidenceToken).compactMap(\.subject)),
            ["contrast/dup", "differentiateWithoutColor/dup", "localizationExpansion/dup"]
        )
        XCTAssertEqual(
            Set(issues(report, .invalidEvidence).compactMap(\.subject)),
            ["contrast/dup", "differentiateWithoutColor/dup", "localizationExpansion/dup"]
        )
    }

    func testPhysicalContrastRatioBoundariesAndBelowRequirement() throws {
        let validEvidence = AccessibilityAuditEvidence(contrast: [
            contrast("minimum", subject: "image", measured: 1_000, required: 1_000),
            contrast("maximum", subject: "image", measured: 21_000, required: 21_000)
        ])
        XCTAssertNoThrow(try validEvidence.encodedData())

        for invalid in [
            contrast("low-measured", subject: "image", measured: 999),
            contrast("high-measured", subject: "image", measured: 21_001),
            contrast("low-required", subject: "image", required: 999),
            contrast("high-required", subject: "image", required: 21_001)
        ] {
            XCTAssertThrowsError(
                try AccessibilityAuditEvidence(contrast: [invalid]).encodedData(),
                invalid.token.rawValue
            ) {
                XCTAssertEqual(
                    $0 as? AccessibilityAuditError,
                    .invalidEvidence(field: "contrast")
                )
            }
        }

        let image = AccessibilitySemanticElement(
            id: id("image"),
            parentID: id("root"),
            role: .image,
            label: "Preview",
            contrastEvidenceTokens: [contrastToken("below")]
        )
        let report = try AccessibilityAudit.audit(
            snapshot(
                [image],
                evidence: AccessibilityAuditEvidence(contrast: [
                    contrast("below", subject: "image", measured: 4_499, required: 4_500)
                ])
            )
        )
        XCTAssertEqual(issues(report, .contrastBelowRequiredRatio).map(\.subject), ["below"])
    }

    func testContrastEvidenceRequiresExpectedSubjectAndApplicableSurface() throws {
        let separator = AccessibilitySemanticElement(
            id: id("separator"),
            parentID: id("root"),
            role: .separator,
            contrastEvidenceTokens: [contrastToken("separator-graphical")]
        )
        let image = AccessibilitySemanticElement(
            id: id("image"),
            parentID: id("root"),
            role: .image,
            label: "Image",
            contrastEvidenceTokens: [contrastToken("wrong-subject")]
        )
        let plain = AccessibilitySemanticElement(
            id: id("plain"),
            parentID: id("root"),
            role: .staticText,
            contrastEvidenceTokens: [contrastToken("wrong-surface")]
        )
        let custom = AccessibilitySemanticElement(
            id: id("custom"),
            parentID: id("root"),
            role: .customControl,
            label: "Custom",
            isEnabled: false,
            contrastEvidenceTokens: [contrastToken("custom-surface")]
        )
        let evidence = AccessibilityAuditEvidence(contrast: [
            contrast("separator-graphical", subject: "separator", surface: .graphicalObject),
            contrast("wrong-subject", subject: "separator", surface: .graphicalObject),
            contrast("wrong-surface", subject: "plain", surface: .graphicalObject),
            contrast("custom-surface", subject: "custom", surface: .custom)
        ])

        let report = try AccessibilityAudit.audit(
            snapshot([separator, image, plain, custom], evidence: evidence)
        )

        XCTAssertEqual(
            issueDescriptors(issues(report, .contrastEvidenceSurfaceMismatch)),
            [
                expectedIssue(
                    .error,
                    .contrastEvidenceSurfaceMismatch,
                    subject: "image/wrong-subject",
                    identityComponents: ["image", "wrong-subject"],
                    message: "Contrast evidence targets another subject or an inapplicable surface."
                ),
                expectedIssue(
                    .error,
                    .contrastEvidenceSurfaceMismatch,
                    subject: "plain/wrong-surface",
                    identityComponents: ["plain", "wrong-surface"],
                    message: "Contrast evidence targets another subject or an inapplicable surface."
                ),
                expectedIssue(
                    .error,
                    .contrastEvidenceSurfaceMismatch,
                    subject: "contrast/wrong-surface",
                    identityComponents: ["contrast", "wrong-surface", "surface"],
                    message: "Contrast evidence surface is inapplicable to its semantic subject."
                )
            ]
        )
    }

    func testCanonicalLocaleSyntaxAcceptedByEvidenceArchive() throws {
        let validLocales = [
            "en", "zh-Hant-TW", "de-CH-1901", "sl-rozaj-biske", "en-US-u-ca-gregory-x-test",
            "x-private", "i-klingon"
        ]
        for (index, locale) in validLocales.enumerated() {
            let evidence = AccessibilityAuditEvidence(localizationExpansion: [
                localization("locale-\(index)", subject: "subject", locale: locale)
            ])
            XCTAssertNoThrow(try evidence.encodedData(), locale)
        }
    }

    func testNoncanonicalOrMalformedLocaleSyntaxIsRejected() {
        let invalidLocales = [
            "", "en_US", "EN", "en-us", "zh-hant-TW", "en-", "x", "en-x", "en-u",
            "de-1901-1901", "en-u-ca-u-nu", "abcdefghi", "é"
        ]
        for (index, locale) in invalidLocales.enumerated() {
            let evidence = AccessibilityAuditEvidence(localizationExpansion: [
                localization("invalid-locale-\(index)", subject: "subject", locale: locale)
            ])
            XCTAssertThrowsError(try evidence.encodedData(), locale) {
                XCTAssertEqual(
                    $0 as? AccessibilityAuditError,
                    .invalidEvidence(field: "localizationExpansion")
                )
            }
        }
    }

    func testLocalizationEvidenceCoversEverySupportedSemanticField() throws {
        let tokens = Dictionary(
            uniqueKeysWithValues: AccessibilityLocalizedField.allCases.map {
                ($0, localizationToken("localization-\($0.rawValue)"))
            }
        )
        let action = AccessibilitySemanticAction(
            id: id("action"),
            kind: .custom,
            label: "Perform",
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.actionLabel])]
        )
        let shortcut = AccessibilityKeyboardShortcut(
            id: id("shortcut"),
            key: "p",
            modifiers: [.command],
            actionID: action.id,
            discoverabilityTitle: "Perform command",
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.shortcutTitle])]
        )
        let control = AccessibilitySemanticElement(
            id: id("control"),
            parentID: id("root"),
            role: .customControl,
            label: "Control",
            value: "Value",
            hint: "Hint",
            isKeyboardFocusable: true,
            actions: [action],
            keyboardShortcuts: [shortcut],
            requiresLocalizationExpansionEvidence: true,
            localizationExpansionEvidenceTokens: [
                try XCTUnwrap(tokens[.label]),
                try XCTUnwrap(tokens[.value]),
                try XCTUnwrap(tokens[.hint])
            ]
        )
        let announcement = AccessibilityAnnouncement(
            id: id("announcement"),
            kind: .confirmation,
            message: "Completed",
            relatedElementID: control.id,
            triggerActionID: action.id,
            localizationExpansionEvidenceTokens: [try XCTUnwrap(tokens[.announcement])]
        )
        let baselines: [AccessibilityLocalizedField: (String, String)] = [
            .label: ("control", "Control"),
            .value: ("control", "Value"),
            .hint: ("control", "Hint"),
            .actionLabel: ("action", "Perform"),
            .shortcutTitle: ("shortcut", "Perform command"),
            .announcement: ("announcement", "Completed")
        ]
        let evidence = AccessibilityAuditEvidence(
            localizationExpansion: try AccessibilityLocalizedField.allCases.map { field in
                let baseline = try XCTUnwrap(baselines[field])
                return localization(
                    "localization-\(field.rawValue)",
                    subject: baseline.0,
                    field: field,
                    baseline: baseline.1
                )
            }
        )

        let report = try AccessibilityAudit.audit(
            snapshot(
                [control],
                focusOrder: [control.id],
                announcements: [announcement],
                evidence: evidence
            )
        )

        XCTAssertTrue(issues(report, .localizationSubjectMissing).isEmpty)
        XCTAssertTrue(issues(report, .localizationExpansionEvidenceMissing).isEmpty)
        XCTAssertTrue(issues(report, .localizationExpansionReferenceMissing).isEmpty)
        XCTAssertTrue(issues(report, .orphanEvidence).isEmpty)
    }

    func testLocalizationFieldAndBaselineMustMatchReferencedSubject() throws {
        let token = localizationToken("wrong-field")
        let element = AccessibilitySemanticElement(
            id: id("control"),
            parentID: id("root"),
            role: .customControl,
            label: "Label",
            value: "Value",
            isEnabled: false,
            localizationExpansionEvidenceTokens: [token]
        )
        let evidence = AccessibilityAuditEvidence(localizationExpansion: [
            localization(
                "wrong-field",
                subject: "control",
                field: .actionLabel,
                baseline: "Label"
            )
        ])

        let report = try AccessibilityAudit.audit(snapshot([element], evidence: evidence))

        XCTAssertEqual(
            issueDescriptors(report.issues),
            [
                expectedIssue(
                    .error,
                    .localizationSubjectMissing,
                    subject: "wrong-field",
                    message: "Localization expansion baseline does not match declared subject and field."
                ),
                expectedIssue(
                    .error,
                    .localizationExpansionReferenceMissing,
                    subject: "control/wrong-field",
                    identityComponents: ["control", "wrong-field"],
                    message: "Localization evidence token targets another subject or field."
                )
            ]
        )
    }

    func testAuditAndExactSnapshotCanonicalizeEveryNestedUnorderedCollection() throws {
        let actionAlpha = AccessibilitySemanticAction(
            id: id("action-alpha"),
            kind: .custom,
            label: "Alpha",
            localizationExpansionEvidenceTokens: [
                localizationToken("localization-zulu"),
                localizationToken("localization-alpha")
            ]
        )
        let actionZulu = action("action-zulu", .activate)
        let shortcutAlpha = AccessibilityKeyboardShortcut(
            id: id("shortcut-alpha"),
            key: "a",
            modifiers: [.shift, .command],
            actionID: actionAlpha.id,
            discoverabilityTitle: "Alpha shortcut",
            localizationExpansionEvidenceTokens: [
                localizationToken("localization-zulu"),
                localizationToken("localization-alpha")
            ]
        )
        let shortcutZulu = keyboardShortcut(
            "shortcut-zulu",
            key: "z",
            actionID: "action-zulu"
        )
        let alpha = AccessibilitySemanticElement(
            id: id("alpha"),
            parentID: id("root"),
            role: .customControl,
            label: "Alpha",
            isEnabled: false,
            actions: [actionZulu, actionAlpha],
            keyboardShortcuts: [shortcutZulu, shortcutAlpha],
            contrastEvidenceTokens: [contrastToken("contrast-zulu"), contrastToken("contrast-alpha")],
            differentiateWithoutColorEvidenceTokens: [
                nonColorToken("noncolor-zulu"), nonColorToken("noncolor-alpha")
            ],
            localizationExpansionEvidenceTokens: [
                localizationToken("localization-zulu"), localizationToken("localization-alpha")
            ]
        )
        let zulu = AccessibilitySemanticElement(
            id: id("zulu"),
            parentID: id("root"),
            role: .staticText,
            label: "Zulu"
        )
        let announcementAlpha = AccessibilityAnnouncement(
            id: id("announcement-alpha"),
            kind: .status,
            message: "Alpha",
            localizationExpansionEvidenceTokens: [
                localizationToken("localization-zulu"),
                localizationToken("localization-alpha")
            ]
        )
        let announcementZulu = AccessibilityAnnouncement(
            id: id("announcement-zulu"),
            kind: .warning,
            message: "Zulu"
        )
        let evidence = AccessibilityAuditEvidence(
            contrast: [
                contrast("contrast-zulu", subject: "alpha"),
                contrast("contrast-alpha", subject: "alpha")
            ],
            differentiateWithoutColor: [
                nonColor("noncolor-zulu"),
                nonColor("noncolor-alpha")
            ],
            localizationExpansion: [
                localization("localization-zulu", subject: "alpha", baseline: "Alpha"),
                localization("localization-alpha", subject: "alpha", baseline: "Alpha")
            ]
        )
        let first = snapshot(
            [zulu, alpha],
            announcements: [announcementZulu, announcementAlpha],
            evidence: evidence
        )
        let reversedActionAlpha = AccessibilitySemanticAction(
            id: actionAlpha.id,
            kind: actionAlpha.kind,
            label: actionAlpha.label,
            localizationExpansionEvidenceTokens:
                Array(actionAlpha.localizationExpansionEvidenceTokens.reversed())
        )
        let reversedShortcutAlpha = AccessibilityKeyboardShortcut(
            id: shortcutAlpha.id,
            key: shortcutAlpha.key,
            modifiers: shortcutAlpha.modifiers,
            actionID: shortcutAlpha.actionID,
            discoverabilityTitle: shortcutAlpha.discoverabilityTitle,
            localizationExpansionEvidenceTokens:
                Array(shortcutAlpha.localizationExpansionEvidenceTokens.reversed())
        )
        let reversedAlpha = AccessibilitySemanticElement(
            id: alpha.id,
            parentID: alpha.parentID,
            role: alpha.role,
            label: alpha.label,
            isEnabled: alpha.isEnabled,
            actions: [reversedActionAlpha, actionZulu],
            keyboardShortcuts: [reversedShortcutAlpha, shortcutZulu],
            contrastEvidenceTokens: Array(alpha.contrastEvidenceTokens.reversed()),
            differentiateWithoutColorEvidenceTokens:
                Array(alpha.differentiateWithoutColorEvidenceTokens.reversed()),
            localizationExpansionEvidenceTokens:
                Array(alpha.localizationExpansionEvidenceTokens.reversed())
        )
        let second = snapshot(
            [reversedAlpha, zulu],
            announcements: [
                AccessibilityAnnouncement(
                    id: announcementAlpha.id,
                    kind: announcementAlpha.kind,
                    message: announcementAlpha.message,
                    localizationExpansionEvidenceTokens:
                        Array(announcementAlpha.localizationExpansionEvidenceTokens.reversed())
                ),
                announcementZulu
            ],
            evidence: AccessibilityAuditEvidence(
                contrast: Array(evidence.contrast.reversed()),
                differentiateWithoutColor: Array(evidence.differentiateWithoutColor.reversed()),
                localizationExpansion: Array(evidence.localizationExpansion.reversed())
            )
        )

        let firstReport = try AccessibilityAudit.audit(first)
        let secondReport = try AccessibilityAudit.audit(second)
        let exact = try AccessibilityAudit.exactSnapshot(of: first)

        XCTAssertEqual(firstReport, secondReport)
        XCTAssertEqual(exact, try AccessibilityAudit.exactSnapshot(of: second))
        XCTAssertEqual(
            try AccessibilityAudit.exactSnapshotData(of: first),
            Data(exact.utf8)
        )
        XCTAssertEqual(
            exact.components(separatedBy: "\n").filter {
                $0.hasPrefix("ELEMENT\t") || $0.hasPrefix("ACTION\t")
                    || $0.hasPrefix("SHORTCUT\t") || $0.hasPrefix("CONTRAST-REF\t")
                    || $0.hasPrefix("NONCOLOR-REF\t") || $0.hasPrefix("LOCALIZATION-REF\t")
                    || $0.hasPrefix("ANNOUNCEMENT\t") || $0.hasPrefix("CONTRAST\t")
                    || $0.hasPrefix("NONCOLOR\t") || $0.hasPrefix("LOCALIZATION\t")
            }.map { $0.split(separator: "\t").prefix(3).joined(separator: "\t") },
            [
                "ELEMENT\troot\tPARENT",
                "ELEMENT\tzulu\tPARENT",
                "ELEMENT\talpha\tPARENT",
                "ACTION\talpha\taction-zulu",
                "ACTION\talpha\taction-alpha",
                "LOCALIZATION-REF\taction-alpha\tlocalization-alpha",
                "LOCALIZATION-REF\taction-alpha\tlocalization-zulu",
                "SHORTCUT\talpha\tshortcut-zulu",
                "SHORTCUT\talpha\tshortcut-alpha",
                "LOCALIZATION-REF\tshortcut-alpha\tlocalization-alpha",
                "LOCALIZATION-REF\tshortcut-alpha\tlocalization-zulu",
                "CONTRAST-REF\talpha\tcontrast-alpha",
                "CONTRAST-REF\talpha\tcontrast-zulu",
                "NONCOLOR-REF\talpha\tnoncolor-alpha",
                "NONCOLOR-REF\talpha\tnoncolor-zulu",
                "LOCALIZATION-REF\talpha\tlocalization-alpha",
                "LOCALIZATION-REF\talpha\tlocalization-zulu",
                "ANNOUNCEMENT\tannouncement-zulu\twarning",
                "ANNOUNCEMENT\tannouncement-alpha\tstatus",
                "LOCALIZATION-REF\tannouncement-alpha\tlocalization-alpha",
                "LOCALIZATION-REF\tannouncement-alpha\tlocalization-zulu",
                "CONTRAST\tcontrast-zulu\talpha",
                "CONTRAST\tcontrast-alpha\talpha",
                "NONCOLOR\tnoncolor-zulu\tDifference",
                "NONCOLOR\tnoncolor-alpha\tDifference",
                "LOCALIZATION\tlocalization-zulu\talpha",
                "LOCALIZATION\tlocalization-alpha\talpha"
            ]
        )
    }

    func testAuditReportIsCanonicalWhenStableIDsCollideAcrossPermutedElements() throws {
        let shortcutOwnerAction = action("shortcut-owner-action", .activate)
        let shortcutOwner = AccessibilitySemanticElement(
            id: id("a-shortcut-owner"),
            parentID: id("root"),
            role: .customControl,
            label: "Shortcut owner",
            isEnabled: false,
            actions: [shortcutOwnerAction],
            keyboardShortcuts: [
                keyboardShortcut(
                    "shared-nested-id",
                    key: "a",
                    actionID: shortcutOwnerAction.id.rawValue
                )
            ]
        )
        let actionOwner = AccessibilitySemanticElement(
            id: id("z-action-owner"),
            parentID: id("root"),
            role: .customControl,
            label: "Action owner",
            isEnabled: false,
            actions: [action("shared-nested-id", .activate)]
        )
        let first = snapshot([shortcutOwner, actionOwner])
        let second = snapshot([actionOwner, shortcutOwner])

        XCTAssertEqual(try AccessibilityAudit.audit(first), try AccessibilityAudit.audit(second))
        XCTAssertEqual(
            try AccessibilityAudit.exactSnapshotData(of: first),
            try AccessibilityAudit.exactSnapshotData(of: second)
        )
    }

    func testIssueOrderingUsesIdentityWhenDisplayFieldsAreSlashAmbiguous() throws {
        let firstElement = AccessibilitySemanticElement(
            id: id("a"),
            parentID: id("root"),
            role: .staticText,
            label: "First",
            localizationExpansionEvidenceTokens: [localizationToken("b/c")]
        )
        let secondElement = AccessibilitySemanticElement(
            id: id("a/b"),
            parentID: id("root"),
            role: .staticText,
            label: "Second",
            localizationExpansionEvidenceTokens: [localizationToken("c")]
        )
        let first = snapshot([firstElement, secondElement])
        let second = snapshot([secondElement, firstElement])

        XCTAssertEqual(try AccessibilityAudit.audit(first), try AccessibilityAudit.audit(second))
        XCTAssertEqual(
            try AccessibilityAudit.exactSnapshotData(of: first),
            try AccessibilityAudit.exactSnapshotData(of: second)
        )
    }

    func testEvidenceReferenceDeduplicationUsesCanonicalSubjectOrder() throws {
        let actionOwner = AccessibilitySemanticElement(
            id: id("a-action-owner"),
            parentID: id("root"),
            role: .customControl,
            label: "Action owner",
            isEnabled: false,
            actions: [
                AccessibilitySemanticAction(
                    id: id("shared-subject"),
                    kind: .activate,
                    localizationExpansionEvidenceTokens: [localizationToken("missing")]
                )
            ]
        )
        let elementOwner = AccessibilitySemanticElement(
            id: id("shared-subject"),
            parentID: id("root"),
            role: .staticText,
            label: "Element owner",
            localizationExpansionEvidenceTokens: [localizationToken("missing")]
        )
        let first = snapshot([actionOwner, elementOwner])
        let second = snapshot([elementOwner, actionOwner])

        XCTAssertEqual(try AccessibilityAudit.audit(first), try AccessibilityAudit.audit(second))
        XCTAssertEqual(
            try AccessibilityAudit.exactSnapshotData(of: first),
            try AccessibilityAudit.exactSnapshotData(of: second)
        )
    }

    func testIssueOrderingSeverityAndScopeNeverClaimRuntimeCompliance() throws {
        let control = AccessibilitySemanticElement(
            id: id("control"),
            parentID: id("root"),
            role: .button
        )
        let blank = AccessibilitySemanticElement(
            id: id("blank"),
            parentID: id("root"),
            role: .staticText,
            label: " "
        )
        let evidence = AccessibilityAuditEvidence(
            differentiateWithoutColor: [nonColor("orphan")]
        )
        let value = snapshot([blank, control], evidence: evidence)

        let report = try AccessibilityAudit.audit(value)
        let exact = try AccessibilityAudit.exactSnapshot(of: value)

        XCTAssertEqual(AccessibilityAudit.exactSnapshotFormatVersion, 2)
        XCTAssertEqual(report.formatVersion, 2)
        XCTAssertEqual(report.highestSeverity, .error)
        XCTAssertEqual(report.issues.map(\.severity), report.issues.map(\.severity).sorted(by: >))
        XCTAssertEqual(
            AccessibilityAuditReport.scopeStatement,
            "Static checks of caller-supplied semantic snapshot and evidence only; not runtime accessibility compliance."
        )
        XCTAssertTrue(
            exact.hasPrefix("MACMERGE-ACCESSIBILITY-SNAPSHOT\t2\nSCOPE\t")
        )
        XCTAssertTrue(exact.contains(AccessibilityAuditReport.scopeStatement))
        XCTAssertTrue(exact.hasSuffix("END\n"))
    }

    func testAuditWorkLimitIsExactAndPreCancellationIsObserved() async throws {
        let elements = (0..<12).map { index in
            AccessibilitySemanticElement(
                id: id("element-\(index)"),
                parentID: id("root"),
                role: .staticText,
                label: String(repeating: "x", count: 32)
            )
        }
        let value = snapshot(elements)
        let exactWorkCost = 26_393

        XCTAssertNoThrow(
            try AccessibilityAudit.audit(
                value,
                limits: makeLimits(maximumWorkUnits: exactWorkCost)
            )
        )
        XCTAssertThrowsError(
            try AccessibilityAudit.audit(
                value,
                limits: makeLimits(maximumWorkUnits: exactWorkCost - 1)
            )
        ) {
            XCTAssertEqual(
                $0 as? AccessibilityAuditError,
                .workLimitExceeded(maximum: exactWorkCost - 1)
            )
        }

        let task = Task.detached { () throws -> AccessibilityAuditReport in
            withUnsafeCurrentTask { $0?.cancel() }
            return try AccessibilityAudit.audit(value)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled audit unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testEvidenceArchiveV2HasExactCanonicalFramingAndBytes() throws {
        var payload = WireBytes()
        payload.appendUInt32(0)
        payload.appendUInt32(0)
        payload.appendUInt32(0)
        let expected = archive(payload: payload.data)

        let encoded = try AccessibilityAuditEvidence().encodedData()

        XCTAssertEqual(AccessibilityAuditEvidenceArchive.currentFormatVersion, 2)
        XCTAssertEqual(encoded, expected)
        XCTAssertEqual(encoded.count, 36)
        XCTAssertEqual(try AccessibilityAuditEvidence.decode(from: encoded), .init())
        XCTAssertEqual(try AccessibilityAuditEvidence.decode(from: encoded).encodedData(), encoded)
    }

    func testEvidenceArchiveCanonicalizesEveryRecordKindAndCueOrder() throws {
        let contrastAlpha = contrast("contrast-alpha", subject: "subject")
        let contrastZulu = contrast("contrast-zulu", subject: "subject")
        let nonColorAlpha = AccessibilityDifferentiateWithoutColorEvidence(
            token: nonColorToken("noncolor-alpha"),
            meaning: "Alpha",
            nonColorCues: [.haptic, .text, .pattern],
            origin: .designSpecification,
            source: "design"
        )
        let nonColorZulu = nonColor("noncolor-zulu")
        let localizationAlpha = localization("localization-alpha", subject: "subject")
        let localizationZulu = localization("localization-zulu", subject: "subject")
        let forward = AccessibilityAuditEvidence(
            contrast: [contrastZulu, contrastAlpha],
            differentiateWithoutColor: [nonColorZulu, nonColorAlpha],
            localizationExpansion: [localizationZulu, localizationAlpha]
        )
        let reverse = AccessibilityAuditEvidence(
            contrast: [contrastAlpha, contrastZulu],
            differentiateWithoutColor: [nonColorAlpha, nonColorZulu],
            localizationExpansion: [localizationAlpha, localizationZulu]
        )

        let forwardData = try forward.encodedData()
        let reverseData = try reverse.encodedData()
        var payload = WireBytes()
        payload.appendUInt32(2)
        payload.appendContrast(token: "contrast-zulu", subject: "subject")
        payload.appendContrast(token: "contrast-alpha", subject: "subject")
        payload.appendUInt32(2)
        payload.appendDifferentiation(
            token: "noncolor-zulu",
            meaning: "Difference",
            cues: ["text", "icon"],
            origin: "designSpecification",
            source: "design"
        )
        payload.appendDifferentiation(
            token: "noncolor-alpha",
            meaning: "Alpha",
            cues: ["text", "pattern", "haptic"],
            origin: "designSpecification",
            source: "design"
        )
        payload.appendUInt32(2)
        payload.appendLocalization(token: "localization-zulu", subject: "subject")
        payload.appendLocalization(token: "localization-alpha", subject: "subject")

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forwardData, reverseData)
        XCTAssertEqual(forwardData, archive(payload: payload.data))
        XCTAssertEqual(try AccessibilityAuditEvidence.decode(from: forwardData), forward)
        XCTAssertEqual(
            try AccessibilityAuditEvidenceArchive.encode(
                AccessibilityAuditEvidenceArchive.decode(forwardData)
            ),
            forwardData
        )
    }

    func testEvidenceArchiveHandcraftedAllFieldWireDecodesAndReencodesExactly() throws {
        var payload = WireBytes()
        payload.appendUInt32(1)
        payload.appendContrast(
            token: "contrast",
            subject: "subject",
            surface: "focusIndicator",
            measured: 7_000,
            required: 4_500,
            origin: "manualMeasurement",
            source: "contrast source"
        )
        payload.appendUInt32(1)
        payload.appendDifferentiation(
            token: "noncolor",
            meaning: "Changed",
            cues: ["text", "shape", "sound"],
            origin: "callerAssertion",
            source: "noncolor source"
        )
        payload.appendUInt32(1)
        payload.appendLocalization(
            token: "localization",
            subject: "subject",
            field: "shortcutTitle",
            locale: "zh-Hant-TW",
            baseline: "Baseline",
            expanded: "Expanded",
            outcome: "wraps",
            origin: "designSpecification",
            source: "localization source"
        )
        let wire = archive(payload: payload.data)

        let decoded = try AccessibilityAuditEvidenceArchive.decode(wire)

        XCTAssertEqual(
            decoded,
            AccessibilityAuditEvidence(
                contrast: [
                    AccessibilityContrastEvidence(
                        token: contrastToken("contrast"),
                        subjectID: id("subject"),
                        surface: .focusIndicator,
                        measuredRatioThousandths: 7_000,
                        requiredRatioThousandths: 4_500,
                        origin: .manualMeasurement,
                        source: "contrast source"
                    )
                ],
                differentiateWithoutColor: [
                    AccessibilityDifferentiateWithoutColorEvidence(
                        token: nonColorToken("noncolor"),
                        meaning: "Changed",
                        nonColorCues: [.text, .shape, .sound],
                        origin: .callerAssertion,
                        source: "noncolor source"
                    )
                ],
                localizationExpansion: [
                    AccessibilityLocalizationExpansionEvidence(
                        token: localizationToken("localization"),
                        subjectID: id("subject"),
                        field: .shortcutTitle,
                        localeIdentifier: "zh-Hant-TW",
                        baselineText: "Baseline",
                        expandedText: "Expanded",
                        outcome: .wraps,
                        origin: .designSpecification,
                        source: "localization source"
                    )
                ]
            )
        )
        XCTAssertEqual(try decoded.encodedData(), wire)
    }

    func testEvidenceArchiveDecodesNonzeroIndexDataSliceFromSingleBackingBuffer() throws {
        let evidence = AccessibilityAuditEvidence(
            contrast: [contrast("slice", subject: "subject")],
            differentiateWithoutColor: [nonColor("slice")],
            localizationExpansion: [localization("slice", subject: "subject")]
        )
        let encoded = try evidence.encodedData()
        var storage = Data(repeating: 0xA5, count: 17)
        storage.append(encoded)
        storage.append(Data(repeating: 0x5A, count: 19))
        let slice = storage[17..<(17 + encoded.count)]

        XCTAssertEqual(slice.startIndex, 17)
        XCTAssertEqual(try AccessibilityAuditEvidenceArchive.decode(slice), evidence)
    }

    func testArchiveEncodeAndDecodeHaveIndependentExactWorkCosts() throws {
        let evidence = AccessibilityAuditEvidence(
            contrast: [contrast("budget", subject: "subject", source: String(repeating: "s", count: 512))],
            differentiateWithoutColor: [nonColor("budget")],
            localizationExpansion: [localization("budget", subject: "subject")]
        )
        let exactEncodeWorkCost = 2_449
        let exactDecodeWorkCost = 6_428
        let encoded = try evidence.encodedData(
            limits: makeLimits(maximumWorkUnits: exactEncodeWorkCost)
        )

        XCTAssertNoThrow(
            try evidence.encodedData(
                limits: makeLimits(maximumWorkUnits: exactEncodeWorkCost)
            )
        )
        assertWorkLimit(exactEncodeWorkCost - 1) {
            _ = try evidence.encodedData(
                limits: makeLimits(maximumWorkUnits: exactEncodeWorkCost - 1)
            )
        }
        XCTAssertNoThrow(
            try AccessibilityAuditEvidenceArchive.decode(
                encoded,
                limits: makeLimits(maximumWorkUnits: exactDecodeWorkCost)
            )
        )
        assertWorkLimit(exactDecodeWorkCost - 1) {
            _ = try AccessibilityAuditEvidenceArchive.decode(
                encoded,
                limits: makeLimits(maximumWorkUnits: exactDecodeWorkCost - 1)
            )
        }
    }

    func testWriterEmitsExactBytesAcrossFourKilobyteChunksAndHonorsArchiveLimit() throws {
        let source = String(repeating: "s", count: 8_193)
        let evidence = AccessibilityAuditEvidence(
            contrast: [contrast("chunked", subject: "subject", source: source)]
        )
        var payload = WireBytes()
        payload.appendUInt32(1)
        payload.appendContrast(
            token: "chunked",
            subject: "subject",
            surface: "graphicalObject",
            measured: 4_500,
            required: 4_500,
            origin: "automatedMeasurement",
            source: source
        )
        payload.appendUInt32(0)
        payload.appendUInt32(0)
        let expected = archive(payload: payload.data)

        let encoded = try evidence.encodedData()

        XCTAssertEqual(encoded, expected)
        XCTAssertEqual(
            try evidence.encodedData(
                limits: makeLimits(maximumEvidenceArchiveBytes: encoded.count)
            ),
            encoded
        )
        XCTAssertThrowsError(
            try evidence.encodedData(
                limits: makeLimits(maximumEvidenceArchiveBytes: encoded.count - 1)
            )
        ) {
            XCTAssertEqual(
                $0 as? AccessibilityAuditError,
                .evidenceArchiveTooLarge(maximumBytes: encoded.count - 1)
            )
        }
    }

    func testExactByteCanonicalScanObservesInFlightCancellation() async throws {
        let evidence = AccessibilityAuditEvidence(
            contrast: [
                contrast(
                    "canonical-scan",
                    subject: "subject",
                    source: String(repeating: "s", count: 16 * 1_024)
                )
            ]
        )
        let encoded = try evidence.encodedData()
        let result = await Task.detached { @Sendable [encoded] in
            AccessibilityAuditTestHooks.$canonicalArchiveComparisonCheckpoint.withValue(
                { offset in
                    if offset == 4_096 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                },
                operation: {
                    do {
                        _ = try AccessibilityAuditEvidenceArchive.decode(encoded)
                        return AccessibilityCanonicalScanCancellationResult.completed
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .failed(String(describing: error))
                    }
                }
            )
        }.value
        XCTAssertEqual(result, .cancelled)
    }

    func testExactByteCanonicalScanPreservesNoncanonicalUTF8Rejection() {
        var decomposed = WireBytes()
        decomposed.appendUInt32(1)
        decomposed.appendContrast(
            token: "token",
            subject: "subject",
            surface: "graphicalObject",
            measured: 4_500,
            required: 4_500,
            origin: "automatedMeasurement",
            source: "e\u{301}vidence"
        )
        decomposed.appendUInt32(0)
        decomposed.appendUInt32(0)

        assertDecodeError(
            .nonCanonicalEvidenceArchive,
            data: archive(payload: decomposed.data)
        )
    }

    func testDecodeRejectsNoncanonicalRecordAndCueOrderWithValidChecksum() {
        var unorderedRecords = WireBytes()
        unorderedRecords.appendUInt32(2)
        unorderedRecords.appendContrast(token: "zulu", subject: "subject")
        unorderedRecords.appendContrast(token: "beta", subject: "subject")
        unorderedRecords.appendUInt32(0)
        unorderedRecords.appendUInt32(0)

        var unorderedCues = WireBytes()
        unorderedCues.appendUInt32(0)
        unorderedCues.appendUInt32(1)
        unorderedCues.appendString("cues")
        unorderedCues.appendString("Meaning")
        unorderedCues.appendUInt32(2)
        unorderedCues.appendString("icon")
        unorderedCues.appendString("text")
        unorderedCues.appendString("callerAssertion")
        unorderedCues.appendString("source")
        unorderedCues.appendUInt32(0)

        let cases = [
            ("unordered records", unorderedRecords.data),
            ("unordered cues", unorderedCues.data)
        ]
        for (name, payload) in cases {
            XCTAssertThrowsError(
                try AccessibilityAuditEvidenceArchive.decode(archive(payload: payload)),
                name
            ) {
                XCTAssertEqual($0 as? AccessibilityAuditError, .nonCanonicalEvidenceArchive)
            }
        }
    }

    func testEvidenceArchiveStrictHeaderLengthChecksumAndTrailingPayload() throws {
        let canonical = try AccessibilityAuditEvidence().encodedData()
        var badMagic = canonical
        badMagic[0] ^= 0xFF
        var unsupportedVersion = canonical
        unsupportedVersion[8] = 3
        var reservedFlags = canonical
        reservedFlags[10] = 1
        var badLength = canonical
        badLength[12] = 13
        var badChecksum = canonical
        badChecksum[16] ^= 0x01
        var trailingArchive = canonical
        trailingArchive.append(0)
        var trailingPayload = WireBytes()
        trailingPayload.appendUInt32(0)
        trailingPayload.appendUInt32(0)
        trailingPayload.appendUInt32(0)
        trailingPayload.append(0)

        assertDecodeError(.invalidEvidenceArchive, data: Data())
        assertDecodeError(.invalidEvidenceArchive, data: badMagic)
        assertDecodeError(.unsupportedEvidenceArchiveVersion(3), data: unsupportedVersion)
        assertDecodeError(.invalidEvidenceArchive, data: reservedFlags)
        assertDecodeError(.invalidEvidenceArchive, data: badLength)
        assertDecodeError(.evidenceArchiveChecksumMismatch, data: badChecksum)
        assertDecodeError(.invalidEvidenceArchive, data: trailingArchive)
        assertDecodeError(.invalidEvidenceArchive, data: archive(payload: trailingPayload.data))
    }

    func testEveryTruncatedFramingPrefixFailsClosed() throws {
        let canonical = try AccessibilityAuditEvidence(
            contrast: [contrast("prefix", subject: "subject")],
            differentiateWithoutColor: [nonColor("prefix")],
            localizationExpansion: [localization("prefix", subject: "subject")]
        ).encodedData()

        for length in 0..<canonical.count {
            assertDecodeError(
                .invalidEvidenceArchive,
                data: canonical.prefix(length),
                description: "prefix length \(length)"
            )
        }
    }

    func testEvidenceArchiveStrictEnumsUTF8CountsAndCueSet() {
        var unknownEnum = WireBytes()
        unknownEnum.appendUInt32(1)
        unknownEnum.appendContrast(token: "token", subject: "subject", surface: "pixel")
        unknownEnum.appendUInt32(0)
        unknownEnum.appendUInt32(0)

        var invalidUTF8 = WireBytes()
        invalidUTF8.appendUInt32(1)
        invalidUTF8.appendUInt32(1)
        invalidUTF8.append(0xFF)
        invalidUTF8.appendString("subject")
        invalidUTF8.appendString("graphicalObject")
        invalidUTF8.appendInt64(4_500)
        invalidUTF8.appendInt64(4_500)
        invalidUTF8.appendString("automatedMeasurement")
        invalidUTF8.appendString("source")
        invalidUTF8.appendUInt32(0)
        invalidUTF8.appendUInt32(0)

        var duplicateCue = WireBytes()
        duplicateCue.appendUInt32(0)
        duplicateCue.appendUInt32(1)
        duplicateCue.appendString("cues")
        duplicateCue.appendString("Meaning")
        duplicateCue.appendUInt32(2)
        duplicateCue.appendString("text")
        duplicateCue.appendString("text")
        duplicateCue.appendString("callerAssertion")
        duplicateCue.appendString("source")
        duplicateCue.appendUInt32(0)

        for payload in [unknownEnum.data, invalidUTF8.data, duplicateCue.data] {
            assertDecodeError(.invalidEvidenceArchive, data: archive(payload: payload))
        }
    }

    func testImpossibleCountsFailAtEveryNestedCollection() {
        var contrast = WireBytes()
        contrast.appendUInt32(UInt32.max)

        var differentiation = WireBytes()
        differentiation.appendUInt32(0)
        differentiation.appendUInt32(UInt32.max)

        var cues = WireBytes()
        cues.appendUInt32(0)
        cues.appendUInt32(1)
        cues.appendString("cues")
        cues.appendString("Meaning")
        cues.appendUInt32(UInt32.max)

        var localization = WireBytes()
        localization.appendUInt32(0)
        localization.appendUInt32(0)
        localization.appendUInt32(UInt32.max)

        let cases: [(AccessibilityAuditError, Data)] = [
            (
                .countLimitExceeded(kind: "contrast-evidence", maximum: 40_000),
                contrast.data
            ),
            (
                .countLimitExceeded(
                    kind: "differentiate-without-color-evidence",
                    maximum: 40_000
                ),
                differentiation.data
            ),
            (
                .countLimitExceeded(kind: "non-color-cue", maximum: 7),
                cues.data
            ),
            (
                .countLimitExceeded(
                    kind: "localization-expansion-evidence",
                    maximum: 40_000
                ),
                localization.data
            )
        ]
        for (expected, payload) in cases {
            assertDecodeError(expected, data: archive(payload: payload))
        }
    }

    func testEveryArchiveDirectEntrypointEnforcesHardLimitsAndExactBoundaries() throws {
        let evidence = AccessibilityAuditEvidence(
            contrast: [contrast("limit", subject: "subject")]
        )
        let encoded = try evidence.encodedData()
        let exactLimits = makeLimits(
            maximumEvidenceRecordsPerKind: 1,
            maximumStringUTF8Bytes: "measurement".utf8.count,
            maximumTotalStringUTF8Bytes:
                "limit".utf8.count + "subject".utf8.count + "measurement".utf8.count,
            maximumEvidenceArchiveBytes: encoded.count
        )

        XCTAssertEqual(try evidence.encodedData(limits: exactLimits), encoded)
        XCTAssertEqual(try AccessibilityAuditEvidence.decode(from: encoded, limits: exactLimits), evidence)
        XCTAssertEqual(try AccessibilityAuditEvidenceArchive.encode(evidence, limits: exactLimits), encoded)
        XCTAssertEqual(try AccessibilityAuditEvidenceArchive.decode(encoded, limits: exactLimits), evidence)

        let shortStringLimits = makeLimits(maximumStringUTF8Bytes: "measurement".utf8.count - 1)
        let shortStringOperations: [(AccessibilityAuditError, () throws -> Void)] = [
            (
                .stringTooLarge(field: "contrast.source", maximumUTF8Bytes: 10),
                { _ = try evidence.encodedData(limits: shortStringLimits) }
            ),
            (
                .stringTooLarge(field: "evidenceArchive", maximumUTF8Bytes: 10),
                { _ = try AccessibilityAuditEvidence.decode(from: encoded, limits: shortStringLimits) }
            ),
            (
                .stringTooLarge(field: "contrast.source", maximumUTF8Bytes: 10),
                {
                    _ = try AccessibilityAuditEvidenceArchive.encode(
                        evidence,
                        limits: shortStringLimits
                    )
                }
            ),
            (
                .stringTooLarge(field: "evidenceArchive", maximumUTF8Bytes: 10),
                {
                    _ = try AccessibilityAuditEvidenceArchive.decode(
                        encoded,
                        limits: shortStringLimits
                    )
                }
            )
        ]
        for (expected, operation) in shortStringOperations {
            XCTAssertThrowsError(try operation()) {
                XCTAssertEqual($0 as? AccessibilityAuditError, expected)
            }
        }

        let invalidLimits = makeLimits(maximumEvidenceArchiveBytes: -1)
        let operations: [() throws -> Void] = [
            { _ = try evidence.encodedData(limits: invalidLimits) },
            { _ = try AccessibilityAuditEvidence.decode(from: encoded, limits: invalidLimits) },
            { _ = try AccessibilityAuditEvidenceArchive.encode(evidence, limits: invalidLimits) },
            { _ = try AccessibilityAuditEvidenceArchive.decode(encoded, limits: invalidLimits) }
        ]
        for operation in operations {
            XCTAssertThrowsError(try operation()) {
                XCTAssertEqual(
                    $0 as? AccessibilityAuditError,
                    .invalidLimit(
                        name: "maximumEvidenceArchiveBytes",
                        value: -1,
                        maximum: Int(UInt32.max)
                    )
                )
            }
        }

        let hardCount = 1_000_000
        let hardBytes = Int(UInt32.max)
        let hardWork = 1_000_000_000
        let excessiveLimits: [(String, Int, Int, AccessibilityAuditLimits)] = [
            (
                "maximumElements", hardCount + 1, hardCount,
                makeLimits(maximumElements: hardCount + 1)
            ),
            (
                "maximumActions", hardCount + 1, hardCount,
                makeLimits(maximumActions: hardCount + 1)
            ),
            (
                "maximumKeyboardShortcuts", hardCount + 1, hardCount,
                makeLimits(maximumKeyboardShortcuts: hardCount + 1)
            ),
            (
                "maximumAnnouncements", hardCount + 1, hardCount,
                makeLimits(maximumAnnouncements: hardCount + 1)
            ),
            (
                "maximumEvidenceRecordsPerKind", hardCount + 1, hardCount,
                makeLimits(maximumEvidenceRecordsPerKind: hardCount + 1)
            ),
            (
                "maximumEvidenceReferences", hardCount + 1, hardCount,
                makeLimits(maximumEvidenceReferences: hardCount + 1)
            ),
            (
                "maximumStringUTF8Bytes", hardBytes + 1, hardBytes,
                makeLimits(maximumStringUTF8Bytes: hardBytes + 1)
            ),
            (
                "maximumTotalStringUTF8Bytes", hardBytes + 1, hardBytes,
                makeLimits(maximumTotalStringUTF8Bytes: hardBytes + 1)
            ),
            (
                "maximumWorkUnits", hardWork + 1, hardWork,
                makeLimits(maximumWorkUnits: hardWork + 1)
            ),
            (
                "maximumIssues", hardCount + 1, hardCount,
                makeLimits(maximumIssues: hardCount + 1)
            ),
            (
                "maximumExactSnapshotUTF8Bytes", hardBytes + 1, hardBytes,
                makeLimits(maximumExactSnapshotUTF8Bytes: hardBytes + 1)
            ),
            (
                "maximumEvidenceArchiveBytes", hardBytes + 1, hardBytes,
                makeLimits(maximumEvidenceArchiveBytes: hardBytes + 1)
            )
        ]
        for (name, value, maximum, limits) in excessiveLimits {
            let directOperations: [() throws -> Void] = [
                { _ = try evidence.encodedData(limits: limits) },
                { _ = try AccessibilityAuditEvidence.decode(from: encoded, limits: limits) },
                { _ = try AccessibilityAuditEvidenceArchive.encode(evidence, limits: limits) },
                { _ = try AccessibilityAuditEvidenceArchive.decode(encoded, limits: limits) }
            ]
            for operation in directOperations {
                XCTAssertThrowsError(try operation(), name) {
                    XCTAssertEqual(
                        $0 as? AccessibilityAuditError,
                        .invalidLimit(name: name, value: value, maximum: maximum)
                    )
                }
            }
        }
    }

    func testEveryPublicLimitRejectsNegativeValuesWithNamedError() {
        let hardCount = 1_000_000
        let hardBytes = Int(UInt32.max)
        let hardWork = 1_000_000_000
        let cases: [(String, Int, Int, AccessibilityAuditLimits)] = [
            ("maximumElements", -1, hardCount, makeLimits(maximumElements: -1)),
            ("maximumActions", -1, hardCount, makeLimits(maximumActions: -1)),
            (
                "maximumKeyboardShortcuts", -1, hardCount,
                makeLimits(maximumKeyboardShortcuts: -1)
            ),
            ("maximumAnnouncements", -1, hardCount, makeLimits(maximumAnnouncements: -1)),
            (
                "maximumEvidenceRecordsPerKind", -1, hardCount,
                makeLimits(maximumEvidenceRecordsPerKind: -1)
            ),
            (
                "maximumEvidenceReferences", -1, hardCount,
                makeLimits(maximumEvidenceReferences: -1)
            ),
            (
                "maximumStringUTF8Bytes", -1, hardBytes,
                makeLimits(maximumStringUTF8Bytes: -1)
            ),
            (
                "maximumTotalStringUTF8Bytes", -1, hardBytes,
                makeLimits(maximumTotalStringUTF8Bytes: -1)
            ),
            ("maximumWorkUnits", -1, hardWork, makeLimits(maximumWorkUnits: -1)),
            ("maximumIssues", -1, hardCount, makeLimits(maximumIssues: -1)),
            (
                "maximumExactSnapshotUTF8Bytes", -1, hardBytes,
                makeLimits(maximumExactSnapshotUTF8Bytes: -1)
            ),
            (
                "maximumEvidenceArchiveBytes", -1, hardBytes,
                makeLimits(maximumEvidenceArchiveBytes: -1)
            )
        ]

        for (name, value, maximum, limits) in cases {
            XCTAssertThrowsError(try AccessibilityAudit.audit(snapshot([]), limits: limits), name) {
                XCTAssertEqual(
                    $0 as? AccessibilityAuditError,
                    .invalidLimit(name: name, value: value, maximum: maximum)
                )
            }
        }
    }

    func testCountStringIssueSnapshotAndArchiveLimitsFailClosed() throws {
        let oneAction = AccessibilitySemanticElement(
            id: id("button"),
            parentID: id("root"),
            role: .button,
            label: "Button",
            isEnabled: false,
            actions: [action("activate", .activate)],
            keyboardShortcuts: [
                keyboardShortcut("shortcut", key: "b", actionID: "activate")
            ],
            contrastEvidenceTokens: [contrastToken("reference")]
        )
        let oneAnnouncement = AccessibilityAnnouncement(
            id: id("announcement"),
            kind: .status,
            message: "Status"
        )
        let evidence = AccessibilityAuditEvidence(
            contrast: [contrast("reference", subject: "button")]
        )
        let value = snapshot(
            [oneAction],
            announcements: [oneAnnouncement],
            evidence: evidence
        )

        assertAuditError(
            .countLimitExceeded(kind: "element", maximum: 1),
            value,
            limits: makeLimits(maximumElements: 1)
        )
        assertAuditError(
            .countLimitExceeded(kind: "action", maximum: 0),
            value,
            limits: makeLimits(maximumActions: 0)
        )
        assertAuditError(
            .countLimitExceeded(kind: "keyboard-shortcut", maximum: 0),
            value,
            limits: makeLimits(maximumKeyboardShortcuts: 0)
        )
        assertAuditError(
            .countLimitExceeded(kind: "announcement", maximum: 0),
            value,
            limits: makeLimits(maximumAnnouncements: 0)
        )
        assertAuditError(
            .countLimitExceeded(kind: "contrast-evidence", maximum: 0),
            value,
            limits: makeLimits(maximumEvidenceRecordsPerKind: 0)
        )
        assertAuditError(
            .countLimitExceeded(kind: "evidence-reference", maximum: 0),
            value,
            limits: makeLimits(maximumEvidenceReferences: 0)
        )
        assertAuditError(
            .stringTooLarge(field: "snapshot.id", maximumUTF8Bytes: 7),
            value,
            limits: makeLimits(maximumStringUTF8Bytes: 7)
        )
        assertAuditError(
            .totalStringsTooLarge(maximumUTF8Bytes: 8),
            value,
            limits: makeLimits(maximumTotalStringUTF8Bytes: 8)
        )

        let invalid = snapshot([
            AccessibilitySemanticElement(
                id: id("invalid"),
                parentID: id("root"),
                role: .button
            )
        ])
        assertAuditError(
            .issueLimitExceeded(maximum: 0),
            invalid,
            limits: makeLimits(maximumIssues: 0)
        )
        XCTAssertThrowsError(
            try AccessibilityAudit.exactSnapshot(
                of: snapshot([]),
                limits: makeLimits(maximumExactSnapshotUTF8Bytes: 0)
            )
        ) {
            XCTAssertEqual(
                $0 as? AccessibilityAuditError,
                .exactSnapshotTooLarge(maximumUTF8Bytes: 0)
            )
        }
        XCTAssertThrowsError(
            try AccessibilityAuditEvidence().encodedData(
                limits: makeLimits(maximumEvidenceArchiveBytes: 35)
            )
        ) {
            XCTAssertEqual(
                $0 as? AccessibilityAuditError,
                .evidenceArchiveTooLarge(maximumBytes: 35)
            )
        }
        XCTAssertThrowsError(
            try AccessibilityAuditEvidence.decode(
                from: Data(repeating: 0, count: 36),
                limits: makeLimits(maximumEvidenceArchiveBytes: 35)
            )
        ) {
            XCTAssertEqual(
                $0 as? AccessibilityAuditError,
                .evidenceArchiveTooLarge(maximumBytes: 35)
            )
        }
    }

    private func snapshot(
        _ children: [AccessibilitySemanticElement],
        focusOrder: [AccessibilityStableID] = [],
        announcements: [AccessibilityAnnouncement] = [],
        evidence: AccessibilityAuditEvidence = .init()
    ) -> AccessibilityCommandControlSnapshot {
        AccessibilityCommandControlSnapshot(
            id: id("snapshot"),
            rootElementID: id("root"),
            elements: [
                AccessibilitySemanticElement(
                    id: id("root"),
                    role: .application,
                    label: "MacMerge"
                )
            ] + children,
            focusOrder: focusOrder,
            announcements: announcements,
            evidence: evidence
        )
    }

    private func focusableElement(
        _ rawID: String,
        role: AccessibilitySemanticRole,
        actions: [AccessibilitySemanticAction]
    ) -> AccessibilitySemanticElement {
        AccessibilitySemanticElement(
            id: id(rawID),
            parentID: id("root"),
            role: role,
            label: rawID,
            checkedState: checkedState(for: role),
            selectedState: selectedState(for: role),
            isKeyboardFocusable: true,
            actions: actions
        )
    }

    private func id(_ value: String) -> AccessibilityStableID {
        AccessibilityStableID(rawValue: value)
    }

    private func action(
        _ rawID: String,
        _ kind: AccessibilitySemanticActionKind,
        label: String? = nil
    ) -> AccessibilitySemanticAction {
        AccessibilitySemanticAction(id: id(rawID), kind: kind, label: label)
    }

    private func keyboardShortcut(
        _ rawID: String,
        key: String,
        actionID: String,
        modifiers: Set<AccessibilityKeyboardModifier> = [.command]
    ) -> AccessibilityKeyboardShortcut {
        AccessibilityKeyboardShortcut(
            id: id(rawID),
            key: key,
            modifiers: modifiers,
            actionID: id(actionID)
        )
    }

    private func contrastToken(_ value: String) -> AccessibilityContrastEvidenceToken {
        AccessibilityContrastEvidenceToken(rawValue: value)
    }

    private func nonColorToken(
        _ value: String
    ) -> AccessibilityDifferentiateWithoutColorEvidenceToken {
        AccessibilityDifferentiateWithoutColorEvidenceToken(rawValue: value)
    }

    private func localizationToken(
        _ value: String
    ) -> AccessibilityLocalizationExpansionEvidenceToken {
        AccessibilityLocalizationExpansionEvidenceToken(rawValue: value)
    }

    private func contrast(
        _ token: String,
        subject: String,
        surface: AccessibilityContrastSurface = .graphicalObject,
        measured: Int = 4_500,
        required: Int = 4_500,
        source: String = "measurement"
    ) -> AccessibilityContrastEvidence {
        AccessibilityContrastEvidence(
            token: contrastToken(token),
            subjectID: id(subject),
            surface: surface,
            measuredRatioThousandths: measured,
            requiredRatioThousandths: required,
            origin: .automatedMeasurement,
            source: source
        )
    }

    private func nonColor(
        _ token: String,
        meaning: String = "Difference",
        source: String = "design"
    ) -> AccessibilityDifferentiateWithoutColorEvidence {
        AccessibilityDifferentiateWithoutColorEvidence(
            token: nonColorToken(token),
            meaning: meaning,
            nonColorCues: [.text, .icon],
            origin: .designSpecification,
            source: source
        )
    }

    private func localization(
        _ token: String,
        subject: String,
        field: AccessibilityLocalizedField = .label,
        locale: String = "de-DE",
        baseline: String = "Label",
        expanded: String = "Expanded label",
        source: String = "layout"
    ) -> AccessibilityLocalizationExpansionEvidence {
        AccessibilityLocalizationExpansionEvidence(
            token: localizationToken(token),
            subjectID: id(subject),
            field: field,
            localeIdentifier: locale,
            baselineText: baseline,
            expandedText: expanded,
            outcome: .fits,
            origin: .manualMeasurement,
            source: source
        )
    }

    private func checkedState(
        for role: AccessibilitySemanticRole
    ) -> AccessibilityCheckedState {
        [.toggle, .checkBox, .radioButton].contains(role) ? .off : .notApplicable
    }

    private func selectedState(
        for role: AccessibilitySemanticRole
    ) -> AccessibilitySelectedState {
        role == .tab ? .notSelected : .notApplicable
    }

    private func allowedActions(
        for role: AccessibilitySemanticRole
    ) -> Set<AccessibilitySemanticActionKind> {
        switch role {
        case .window, .dialog, .alert:
            [.dismiss, .custom]
        case .button, .link, .tab, .listItem, .row, .cell, .treeItem, .command:
            [.activate, .custom]
        case .toggle, .checkBox, .radioButton:
            [.toggle, .custom]
        case .textField, .searchField:
            [.setValue, .custom]
        case .comboBox:
            [.setValue, .showMenu, .custom]
        case .menu:
            [.showMenu, .dismiss, .custom]
        case .menuItem:
            [.activate, .toggle, .showMenu, .custom]
        case .slider:
            [.increment, .decrement, .setValue, .custom]
        case .stepper:
            [.increment, .decrement, .custom]
        case .customControl:
            Set(AccessibilitySemanticActionKind.allCases)
        case .application, .group, .toolbar, .tabList, .list, .table, .tree,
            .progressIndicator, .image, .staticText, .heading:
            [.custom]
        case .separator, .presentation:
            []
        }
    }

    private func supportsKeyboardFocus(for role: AccessibilitySemanticRole) -> Bool {
        switch role {
        case .button, .toggle, .checkBox, .radioButton, .link, .textField, .searchField,
            .comboBox, .menu, .menuItem, .tab, .list, .listItem, .table, .row, .cell,
            .tree, .treeItem, .slider, .stepper, .command, .customControl:
            true
        default:
            false
        }
    }

    private func requiredActions(
        for role: AccessibilitySemanticRole
    ) -> [AccessibilitySemanticActionKind] {
        switch role {
        case .button, .link, .tab, .command:
            [.activate]
        case .toggle, .checkBox, .radioButton:
            [.toggle]
        case .textField, .searchField:
            [.setValue]
        case .comboBox:
            [.setValue, .showMenu]
        case .menuItem:
            [.activate]
        case .slider:
            [.increment, .decrement, .setValue]
        case .stepper:
            [.increment, .decrement]
        case .customControl:
            [.custom]
        default:
            []
        }
    }

    private func supportsContrastSurface(
        _ surface: AccessibilityContrastSurface,
        role: AccessibilitySemanticRole,
        hasText: Bool,
        isKeyboardFocusable: Bool
    ) -> Bool {
        switch surface {
        case .text, .largeText:
            hasText
        case .graphicalObject:
            switch role {
            case .button, .toggle, .checkBox, .radioButton, .link, .textField, .searchField,
                .comboBox, .menuItem, .tab, .slider, .stepper, .command, .customControl,
                .image, .progressIndicator, .separator:
                true
            default:
                false
            }
        case .focusIndicator:
            isKeyboardFocusable
        case .custom:
            role == .customControl
        }
    }

    private func issues(
        _ report: AccessibilityAuditReport,
        _ code: AccessibilityAuditIssueCode
    ) -> [AccessibilityAuditIssue] {
        report.issues.filter { $0.code == code }
    }

    private struct IssueDescriptor: Equatable {
        let id: String
        let severity: AccessibilityAuditSeverity
        let code: AccessibilityAuditIssueCode
        let subject: String?
        let message: String
    }

    private func expectedIssue(
        _ severity: AccessibilityAuditSeverity,
        _ code: AccessibilityAuditIssueCode,
        subject: String?,
        identityComponents: [String]? = nil,
        message: String
    ) -> IssueDescriptor {
        let components = identityComponents ?? subject.map { [$0] } ?? []
        let id = ([code.rawValue] + components).map {
            "\($0.utf8.count):\($0)"
        }.joined()
        return IssueDescriptor(
            id: id,
            severity: severity,
            code: code,
            subject: subject,
            message: message
        )
    }

    private func issueDescriptors(
        _ issues: [AccessibilityAuditIssue]
    ) -> [IssueDescriptor] {
        issues.map {
            IssueDescriptor(
                id: $0.id.rawValue,
                severity: $0.severity,
                code: $0.code,
                subject: $0.subject,
                message: $0.message
            )
        }
    }

    private func issueDictionary(
        _ report: AccessibilityAuditReport
    ) -> [String: IssueDescriptor] {
        issueDictionary(issueDescriptors(report.issues))
    }

    private func issueDictionary(
        _ issues: [AccessibilityAuditIssue]
    ) -> [String: IssueDescriptor] {
        issueDictionary(issueDescriptors(issues))
    }

    private func issueDictionary(
        _ descriptors: [IssueDescriptor]
    ) -> [String: IssueDescriptor] {
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
    }

    private func assertAuditError(
        _ expected: AccessibilityAuditError,
        _ snapshot: AccessibilityCommandControlSnapshot,
        limits: AccessibilityAuditLimits,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try AccessibilityAudit.audit(snapshot, limits: limits),
            file: file,
            line: line
        ) {
            XCTAssertEqual($0 as? AccessibilityAuditError, expected, file: file, line: line)
        }
    }

    private func assertDecodeError(
        _ expected: AccessibilityAuditError,
        data: Data,
        description: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try AccessibilityAuditEvidenceArchive.decode(data),
            description,
            file: file,
            line: line
        ) {
            XCTAssertEqual($0 as? AccessibilityAuditError, expected, file: file, line: line)
        }
    }

    private func assertWorkLimit(
        _ maximum: Int,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual(
                $0 as? AccessibilityAuditError,
                .workLimitExceeded(maximum: maximum),
                file: file,
                line: line
            )
        }
    }

    private func makeLimits(
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
    ) -> AccessibilityAuditLimits {
        AccessibilityAuditLimits(
            maximumElements: maximumElements,
            maximumActions: maximumActions,
            maximumKeyboardShortcuts: maximumKeyboardShortcuts,
            maximumAnnouncements: maximumAnnouncements,
            maximumEvidenceRecordsPerKind: maximumEvidenceRecordsPerKind,
            maximumEvidenceReferences: maximumEvidenceReferences,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits,
            maximumIssues: maximumIssues,
            maximumExactSnapshotUTF8Bytes: maximumExactSnapshotUTF8Bytes,
            maximumEvidenceArchiveBytes: maximumEvidenceArchiveBytes
        )
    }

    private func archive(
        payload: Data,
        version: UInt16 = 2,
        reserved: UInt16 = 0,
        checksum: UInt64? = nil
    ) -> Data {
        var archive = WireBytes()
        archive.append(contentsOf: Data("MMAXEVID".utf8))
        archive.appendUInt16(version)
        archive.appendUInt16(reserved)
        archive.appendUInt32(UInt32(payload.count))
        archive.appendUInt64(checksum ?? fnv1a64(payload))
        archive.append(contentsOf: payload)
        return archive.data
    }

    private func fnv1a64(_ data: Data) -> UInt64 {
        data.reduce(into: UInt64(14_695_981_039_346_656_037)) { hash, byte in
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
    }
}

private struct WireBytes {
    private(set) var data = Data()

    mutating func append(_ byte: UInt8) {
        data.append(byte)
    }

    mutating func append(contentsOf bytes: Data) {
        data.append(bytes)
    }

    mutating func appendUInt16(_ value: UInt16) {
        for offset in 0..<2 {
            append(UInt8(truncatingIfNeeded: value >> UInt16(offset * 8)))
        }
    }

    mutating func appendUInt32(_ value: UInt32) {
        for offset in 0..<4 {
            append(UInt8(truncatingIfNeeded: value >> UInt32(offset * 8)))
        }
    }

    mutating func appendUInt64(_ value: UInt64) {
        for offset in 0..<8 {
            append(UInt8(truncatingIfNeeded: value >> UInt64(offset * 8)))
        }
    }

    mutating func appendInt64(_ value: Int64) {
        appendUInt64(UInt64(bitPattern: value))
    }

    mutating func appendString(_ value: String) {
        let bytes = Data(value.utf8)
        appendUInt32(UInt32(bytes.count))
        append(contentsOf: bytes)
    }

    mutating func appendContrast(
        token: String,
        subject: String,
        surface: String = "graphicalObject",
        measured: Int64 = 4_500,
        required: Int64 = 4_500,
        origin: String = "automatedMeasurement",
        source: String = "measurement"
    ) {
        appendString(token)
        appendString(subject)
        appendString(surface)
        appendInt64(measured)
        appendInt64(required)
        appendString(origin)
        appendString(source)
    }

    mutating func appendDifferentiation(
        token: String,
        meaning: String,
        cues: [String],
        origin: String,
        source: String
    ) {
        appendString(token)
        appendString(meaning)
        appendUInt32(UInt32(cues.count))
        for cue in cues { appendString(cue) }
        appendString(origin)
        appendString(source)
    }

    mutating func appendLocalization(
        token: String,
        subject: String,
        field: String = "label",
        locale: String = "de-DE",
        baseline: String = "Label",
        expanded: String = "Expanded label",
        outcome: String = "fits",
        origin: String = "manualMeasurement",
        source: String = "layout"
    ) {
        appendString(token)
        appendString(subject)
        appendString(field)
        appendString(locale)
        appendString(baseline)
        appendString(expanded)
        appendString(outcome)
        appendString(origin)
        appendString(source)
    }
}

private enum AccessibilityCanonicalScanCancellationResult: Equatable {
    case completed
    case cancelled
    case failed(String)
}
