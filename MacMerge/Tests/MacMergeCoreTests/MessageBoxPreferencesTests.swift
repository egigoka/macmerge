import Foundation
import MacMergeCore
import XCTest

final class MessageBoxPreferencesTests: XCTestCase {
    func testTokensEnforceBoundedASCIIGrammar() throws {
        XCTAssertEqual(MessageBoxIdentifier.maximumUTF8Bytes, 128)
        XCTAssertEqual(MessageBoxOutcomeIdentifier.maximumUTF8Bytes, 64)
        XCTAssertEqual(MessageBoxLocalizationToken.maximumUTF8Bytes, 256)
        XCTAssertEqual(MessageBoxAccessibilityToken.maximumUTF8Bytes, 256)

        let messageMaximum =
            "m"
            + String(
                repeating: "x",
                count: MessageBoxIdentifier.maximumUTF8Bytes - 1
            )
        let outcomeMaximum =
            "o"
            + String(
                repeating: "x",
                count: MessageBoxOutcomeIdentifier.maximumUTF8Bytes - 1
            )
        let localizationMaximum =
            "l"
            + String(
                repeating: "x",
                count: MessageBoxLocalizationToken.maximumUTF8Bytes - 1
            )
        let accessibilityMaximum =
            "a"
            + String(
                repeating: "x",
                count: MessageBoxAccessibilityToken.maximumUTF8Bytes - 1
            )

        XCTAssertEqual(try MessageBoxIdentifier(messageMaximum).rawValue, messageMaximum)
        XCTAssertEqual(try MessageBoxOutcomeIdentifier(outcomeMaximum).rawValue, outcomeMaximum)
        XCTAssertEqual(
            try MessageBoxLocalizationToken(localizationMaximum).rawValue,
            localizationMaximum
        )
        XCTAssertEqual(
            try MessageBoxAccessibilityToken(accessibilityMaximum).rawValue,
            accessibilityMaximum
        )

        for valid in ["0", "9", "A", "Z", "a", "z", "A0-Z._z"] {
            XCTAssertEqual(try MessageBoxIdentifier(valid).rawValue, valid)
            XCTAssertEqual(try MessageBoxOutcomeIdentifier(valid).rawValue, valid)
            XCTAssertEqual(try MessageBoxLocalizationToken(valid).rawValue, valid)
            XCTAssertEqual(try MessageBoxAccessibilityToken(valid).rawValue, valid)
        }

        for invalid in [
            "", "-leading", ".leading", "_leading", "A,", "A/", "A:", "A@", "A[", "A\\",
            "A]", "A^", "A`", "A{",
            "has space", "slash/value", "caf\u{00E9}"
        ] {
            assertInvalidToken { _ = try MessageBoxIdentifier(invalid) }
            assertInvalidToken { _ = try MessageBoxOutcomeIdentifier(invalid) }
            assertInvalidToken { _ = try MessageBoxLocalizationToken(invalid) }
            assertInvalidToken { _ = try MessageBoxAccessibilityToken(invalid) }
        }
        assertInvalidToken { _ = try MessageBoxIdentifier(messageMaximum + "x") }
        assertInvalidToken { _ = try MessageBoxOutcomeIdentifier(outcomeMaximum + "x") }
        assertInvalidToken { _ = try MessageBoxLocalizationToken(localizationMaximum + "x") }
        assertInvalidToken { _ = try MessageBoxAccessibilityToken(accessibilityMaximum + "x") }

        let oversizedPayload = "a" + String(repeating: "\u{00E9}", count: 128)
        let boundedPayload = "a" + String(repeating: "\u{00E9}", count: 62) + "..."
        XCTAssertEqual(boundedPayload.utf8.count, 128)
        assertPreferencesError(.invalidToken(boundedPayload)) {
            _ = try MessageBoxIdentifier(oversizedPayload)
        }
    }

    func testLimitsAcceptBoundariesAndRejectEveryInvalidDimension() throws {
        XCTAssertEqual(MessageBoxDefinition.hardMaximumOutcomeCount, 16)
        XCTAssertEqual(MessageBoxPreferencesLimits.hardMaximumDefinitionCount, 256)
        XCTAssertEqual(MessageBoxPreferencesLimits.hardMaximumOutcomeCountPerMessage, 16)
        XCTAssertEqual(MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount, 256)
        XCTAssertEqual(MessageBoxPreferencesLimits.hardMaximumEncodedBytes, 65_536)
        XCTAssertEqual(MessageBoxPreferencesLimits.default.maximumDefinitionCount, 128)
        XCTAssertEqual(MessageBoxPreferencesLimits.default.maximumOutcomeCountPerMessage, 8)
        XCTAssertEqual(MessageBoxPreferencesLimits.default.maximumRememberedOutcomeCount, 128)
        XCTAssertEqual(MessageBoxPreferencesLimits.default.maximumEncodedBytes, 32_768)
        XCTAssertEqual(MessageBoxPreferences.currentSchemaVersion, 1)

        XCTAssertNoThrow(
            try MessageBoxPreferencesLimits(
                maximumDefinitionCount: 1,
                maximumOutcomeCountPerMessage: 1,
                maximumRememberedOutcomeCount: 1,
                maximumEncodedBytes: 256
            )
        )
        XCTAssertNoThrow(
            try MessageBoxPreferencesLimits(
                maximumDefinitionCount: MessageBoxPreferencesLimits.hardMaximumDefinitionCount,
                maximumOutcomeCountPerMessage: MessageBoxPreferencesLimits.hardMaximumOutcomeCountPerMessage,
                maximumRememberedOutcomeCount: MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount,
                maximumEncodedBytes: MessageBoxPreferencesLimits.hardMaximumEncodedBytes
            )
        )

        let invalidCases: [(String, Int, () throws -> Void)] = [
            (
                "maximumDefinitionCount", 0,
                {
                    _ = try MessageBoxPreferencesLimits(maximumDefinitionCount: 0)
                }
            ),
            (
                "maximumDefinitionCount",
                MessageBoxPreferencesLimits.hardMaximumDefinitionCount + 1,
                {
                    _ = try MessageBoxPreferencesLimits(
                        maximumDefinitionCount: MessageBoxPreferencesLimits.hardMaximumDefinitionCount + 1
                    )
                }
            ),
            (
                "maximumOutcomeCountPerMessage", 0,
                {
                    _ = try MessageBoxPreferencesLimits(maximumOutcomeCountPerMessage: 0)
                }
            ),
            (
                "maximumOutcomeCountPerMessage",
                MessageBoxPreferencesLimits.hardMaximumOutcomeCountPerMessage + 1,
                {
                    _ = try MessageBoxPreferencesLimits(
                        maximumOutcomeCountPerMessage: MessageBoxPreferencesLimits.hardMaximumOutcomeCountPerMessage + 1
                    )
                }
            ),
            (
                "maximumRememberedOutcomeCount", 0,
                {
                    _ = try MessageBoxPreferencesLimits(maximumRememberedOutcomeCount: 0)
                }
            ),
            (
                "maximumRememberedOutcomeCount",
                MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount + 1,
                {
                    _ = try MessageBoxPreferencesLimits(
                        maximumDefinitionCount: MessageBoxPreferencesLimits.hardMaximumDefinitionCount,
                        maximumRememberedOutcomeCount: MessageBoxPreferencesLimits.hardMaximumRememberedOutcomeCount + 1
                    )
                }
            ),
            (
                "maximumRememberedOutcomeCount", 2,
                {
                    _ = try MessageBoxPreferencesLimits(
                        maximumDefinitionCount: 1,
                        maximumRememberedOutcomeCount: 2
                    )
                }
            ),
            (
                "maximumEncodedBytes", 255,
                {
                    _ = try MessageBoxPreferencesLimits(maximumEncodedBytes: 255)
                }
            ),
            (
                "maximumEncodedBytes",
                MessageBoxPreferencesLimits.hardMaximumEncodedBytes + 1,
                {
                    _ = try MessageBoxPreferencesLimits(
                        maximumEncodedBytes: MessageBoxPreferencesLimits.hardMaximumEncodedBytes + 1
                    )
                }
            )
        ]

        for (name, value, operation) in invalidCases {
            assertPreferencesError(.invalidLimit(name: name, value: value), operation: operation)
        }
    }

    func testCatalogSortsTrustedDefinitionsAndEnforcesCatalogLimits() throws {
        let zeta = try makeDefinition(identifier: "zeta")
        let alpha = try makeDefinition(identifier: "alpha")
        let catalog = try MessageBoxCatalog(definitions: [zeta, alpha])

        XCTAssertEqual(catalog.definitions.map(\.identifier.rawValue), ["alpha", "zeta"])
        XCTAssertEqual(catalog.definition(for: alpha.identifier), alpha)
        XCTAssertNil(catalog.definition(for: try messageIdentifier("missing")))

        assertPreferencesError(.duplicateMessageIdentifier(alpha.identifier)) {
            _ = try MessageBoxCatalog(definitions: [alpha, zeta, alpha])
        }

        let oneDefinitionLimit = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 1,
            maximumRememberedOutcomeCount: 1
        )
        assertPreferencesError(.tooManyDefinitions(maximumCount: 1)) {
            _ = try MessageBoxCatalog(
                definitions: [alpha, zeta],
                limits: oneDefinitionLimit
            )
        }

        let twoButtonDefinition = try makeDefinition(
            identifier: "two-buttons",
            buttons: [("first", .normal), ("second", .normal)],
            defaultOutcome: "first"
        )
        let oneOutcomeLimit = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 1,
            maximumOutcomeCountPerMessage: 1,
            maximumRememberedOutcomeCount: 1
        )
        let exactOutcomeCatalog = try MessageBoxCatalog(
            definitions: [alpha],
            limits: oneOutcomeLimit
        )
        XCTAssertEqual(exactOutcomeCatalog.definitions, [alpha])
        assertPreferencesError(
            .tooManyOutcomes(message: twoButtonDefinition.identifier, maximumCount: 1)
        ) {
            _ = try MessageBoxCatalog(
                definitions: [twoButtonDefinition],
                limits: oneOutcomeLimit
            )
        }
    }

    func testDefinitionPreservesTrustedMetadataButtonOrderAndRoles() throws {
        let definition = try makeDefinition(
            identifier: "trusted-prompt",
            buttons: [("later", .normal), ("cancel", .cancel)],
            defaultOutcome: "later",
            cancellationOutcome: "cancel"
        )

        XCTAssertEqual(definition.identifier.rawValue, "trusted-prompt")
        XCTAssertEqual(definition.category, .nonDestructive)
        XCTAssertEqual(definition.availableOutcomes.map(\.rawValue), ["later", "cancel"])
        XCTAssertEqual(definition.defaultButton.outcome.rawValue, "later")
        XCTAssertEqual(definition.defaultButton.role, .normal)
        XCTAssertEqual(definition.cancellationButton?.outcome.rawValue, "cancel")
        XCTAssertEqual(definition.cancellationButton?.role, .cancel)
        XCTAssertEqual(definition.button(for: try outcomeIdentifier("cancel")), definition.buttons[1])
        XCTAssertNil(definition.button(for: try outcomeIdentifier("missing")))
        XCTAssertEqual(definition.metadata.titleLocalizationToken.rawValue, "message.trusted-prompt.title")
        XCTAssertEqual(definition.metadata.messageLocalizationToken.rawValue, "message.trusted-prompt.body")
        XCTAssertEqual(definition.metadata.accessibilityToken.rawValue, "message.trusted-prompt.accessibility")
        XCTAssertEqual(
            definition.metadata.suppressionLocalizationToken?.rawValue,
            "message.trusted-prompt.suppression"
        )
        XCTAssertEqual(
            definition.metadata.suppressionAccessibilityToken?.rawValue,
            "message.trusted-prompt.suppression-accessibility"
        )
        XCTAssertTrue(definition.allowsSuppression)
        XCTAssertTrue(definition.canBeSuppressed)
        XCTAssertNoThrow(try definition.validate())
    }

    func testDefinitionRejectsInvalidOutcomeDefaultAndCancellationContracts() throws {
        let identifier = try messageIdentifier("invalid-definition")
        let metadata = try makeMetadata(identifier: identifier.rawValue, suppression: false)
        let normal = try makeButton(outcome: "normal", role: .normal, message: identifier.rawValue)
        let cancel = try makeButton(outcome: "cancel", role: .cancel, message: identifier.rawValue)
        let destructive = try makeButton(
            outcome: "delete",
            role: .destructive,
            message: identifier.rawValue
        )
        let alternateCancel = try makeButton(
            outcome: "dismiss",
            role: .cancel,
            message: identifier.rawValue
        )

        let maximumButtons = try (0..<16).map {
            try makeButton(
                outcome: "outcome-\($0)",
                role: .normal,
                message: identifier.rawValue
            )
        }
        let maximumDefinition = try MessageBoxDefinition(
            identifier: identifier,
            category: .nonDestructive,
            metadata: metadata,
            buttons: maximumButtons,
            defaultOutcome: maximumButtons[0].outcome
        )
        XCTAssertEqual(maximumDefinition.buttons.count, 16)

        assertPreferencesError(.messageHasNoOutcomes(identifier)) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [],
                defaultOutcome: normal.outcome
            )
        }

        let excessiveButtons = try (0...MessageBoxDefinition.hardMaximumOutcomeCount).map {
            try makeButton(
                outcome: "outcome-\($0)",
                role: .normal,
                message: identifier.rawValue
            )
        }
        assertPreferencesError(
            .tooManyOutcomes(
                message: identifier,
                maximumCount: MessageBoxDefinition.hardMaximumOutcomeCount
            )
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: excessiveButtons,
                defaultOutcome: excessiveButtons[0].outcome
            )
        }

        assertPreferencesError(.duplicateOutcome(message: identifier, outcome: normal.outcome)) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal, normal],
                defaultOutcome: normal.outcome
            )
        }

        let duplicateAccessibility = MessageBoxButton(
            outcome: try outcomeIdentifier("other"),
            titleLocalizationToken: try localizationToken("button.other.title"),
            accessibilityToken: normal.accessibilityToken
        )
        assertPreferencesError(
            .duplicateButtonAccessibilityToken(
                message: identifier,
                token: normal.accessibilityToken
            )
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal, duplicateAccessibility],
                defaultOutcome: normal.outcome
            )
        }

        let unavailable = try outcomeIdentifier("unavailable")
        assertPreferencesError(
            .defaultOutcomeUnavailable(message: identifier, outcome: unavailable)
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal],
                defaultOutcome: unavailable
            )
        }
        assertPreferencesError(
            .destructiveDefaultOutcome(message: identifier, outcome: destructive.outcome)
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .destructive,
                metadata: metadata,
                buttons: [destructive],
                defaultOutcome: destructive.outcome
            )
        }
        assertPreferencesError(
            .destructiveDefaultOutcome(message: identifier, outcome: destructive.outcome)
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal, destructive],
                defaultOutcome: destructive.outcome
            )
        }
        assertPreferencesError(
            .cancellationOutcomeUnavailable(message: identifier, outcome: unavailable)
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal],
                defaultOutcome: normal.outcome,
                cancellationOutcome: unavailable
            )
        }
        assertPreferencesError(
            .cancellationOutcomeIsNotCancel(message: identifier, outcome: normal.outcome)
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal],
                defaultOutcome: normal.outcome,
                cancellationOutcome: normal.outcome
            )
        }
        assertPreferencesError(
            .cancellationOutcomeIsNotCancel(message: identifier, outcome: destructive.outcome)
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal, destructive],
                defaultOutcome: normal.outcome,
                cancellationOutcome: destructive.outcome
            )
        }
        assertPreferencesError(
            .unexpectedCancelButton(message: identifier, outcome: cancel.outcome)
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal, cancel],
                defaultOutcome: normal.outcome
            )
        }
        assertPreferencesError(
            .unexpectedCancelButton(message: identifier, outcome: alternateCancel.outcome)
        ) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: metadata,
                buttons: [normal, cancel, alternateCancel],
                defaultOutcome: normal.outcome,
                cancellationOutcome: cancel.outcome
            )
        }

        let cancelDefault = try MessageBoxDefinition(
            identifier: identifier,
            category: .nonDestructive,
            metadata: metadata,
            buttons: [cancel],
            defaultOutcome: cancel.outcome,
            cancellationOutcome: cancel.outcome
        )
        XCTAssertEqual(cancelDefault.defaultButton.role, .cancel)
        XCTAssertEqual(cancelDefault.cancellationButton, cancelDefault.defaultButton)
    }

    func testSuppressionRequiresExplicitSafeCategoryAndNoDestructiveButton() throws {
        for category in [MessageBoxCategory.informational, .nonDestructive] {
            let definition = try makeDefinition(
                identifier: "safe-\(category.rawValue)",
                category: category
            )
            XCTAssertTrue(definition.canBeSuppressed)
            XCTAssertFalse(category.permanentlyForbidsSuppression)
        }

        for category in [
            MessageBoxCategory.destructive,
            .security,
            .dataLoss,
            .error
        ] {
            let identifier = try messageIdentifier("unsafe-\(category.rawValue)")
            XCTAssertTrue(category.permanentlyForbidsSuppression)
            assertPreferencesError(.suppressionForbidden(message: identifier, category: category)) {
                _ = try makeDefinition(
                    identifier: identifier.rawValue,
                    category: category
                )
            }
        }

        let destructiveIdentifier = try messageIdentifier("destructive-button")
        assertPreferencesError(
            .suppressionForbidden(
                message: destructiveIdentifier,
                category: .nonDestructive
            )
        ) {
            _ = try makeDefinition(
                identifier: destructiveIdentifier.rawValue,
                buttons: [("continue", .normal), ("delete", .destructive)],
                defaultOutcome: "continue"
            )
        }

        let nonSuppressible = try makeDefinition(
            identifier: "explicitly-disabled",
            category: .security,
            allowsSuppression: false
        )
        XCTAssertFalse(nonSuppressible.allowsSuppression)
        XCTAssertFalse(nonSuppressible.canBeSuppressed)
    }

    func testSuppressionMetadataMustBeCompleteAndMatchPolicy() throws {
        let identifier = try messageIdentifier("metadata-policy")
        let button = try makeButton(
            outcome: "continue",
            role: .normal,
            message: identifier.rawValue
        )
        let outcome = button.outcome

        assertPreferencesError(.missingSuppressionMetadata(identifier)) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: try makeMetadata(identifier: identifier.rawValue, suppression: false),
                buttons: [button],
                defaultOutcome: outcome,
                allowsSuppression: true
            )
        }
        assertPreferencesError(.incompleteSuppressionMetadata(identifier)) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: try makeMetadata(
                    identifier: identifier.rawValue,
                    suppressionLocalization: true,
                    suppressionAccessibility: false
                ),
                buttons: [button],
                defaultOutcome: outcome,
                allowsSuppression: true
            )
        }
        assertPreferencesError(.incompleteSuppressionMetadata(identifier)) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: try makeMetadata(
                    identifier: identifier.rawValue,
                    suppressionLocalization: false,
                    suppressionAccessibility: true
                ),
                buttons: [button],
                defaultOutcome: outcome,
                allowsSuppression: true
            )
        }
        assertPreferencesError(.unexpectedSuppressionMetadata(identifier)) {
            _ = try MessageBoxDefinition(
                identifier: identifier,
                category: .nonDestructive,
                metadata: try makeMetadata(identifier: identifier.rawValue, suppression: true),
                buttons: [button],
                defaultOutcome: outcome,
                allowsSuppression: false
            )
        }
    }

    func testSafeDefaultAndCancellationOutcomesCanDriveSuppression() throws {
        let definition = try makeDefinition(
            identifier: "safe-choice",
            buttons: [("continue", .normal), ("cancel", .cancel)],
            defaultOutcome: "continue",
            cancellationOutcome: "cancel"
        )
        let catalog = try MessageBoxCatalog(definitions: [definition])
        let continueOutcome = try outcomeIdentifier("continue")
        let cancelOutcome = try outcomeIdentifier("cancel")
        var preferences = MessageBoxPreferences()

        XCTAssertEqual(preferences.decision(for: definition.identifier, in: catalog), .present)
        XCTAssertTrue(preferences.decision(for: definition.identifier, in: catalog).requiresPresentation)
        XCTAssertFalse(preferences.isSuppressed(definition.identifier, in: catalog))

        try preferences.remember(continueOutcome, for: definition.identifier, in: catalog)
        XCTAssertEqual(
            preferences.rememberedOutcome(for: definition.identifier, in: catalog),
            continueOutcome
        )
        XCTAssertEqual(
            preferences.decision(for: definition.identifier, in: catalog),
            .useRememberedOutcome(continueOutcome)
        )
        XCTAssertFalse(preferences.decision(for: definition.identifier, in: catalog).requiresPresentation)

        try preferences.record(
            cancelOutcome,
            suppressFutureMessages: true,
            for: definition.identifier,
            in: catalog
        )
        XCTAssertEqual(
            preferences.rememberedOutcome(for: definition.identifier, in: catalog),
            cancelOutcome
        )
        XCTAssertTrue(preferences.isSuppressed(definition.identifier, in: catalog))
        XCTAssertEqual(preferences.count, 1)
    }

    func testRecordValidatesResponsesAndNeverSuppressesDestructiveOutcomes() throws {
        let definition = try makeDefinition(
            identifier: "destructive-response",
            category: .destructive,
            buttons: [("continue", .normal), ("delete", .destructive)],
            defaultOutcome: "continue",
            allowsSuppression: false
        )
        let catalog = try MessageBoxCatalog(definitions: [definition])
        let continueOutcome = try outcomeIdentifier("continue")
        let deleteOutcome = try outcomeIdentifier("delete")
        let unavailable = try outcomeIdentifier("forged")
        let original = try makeDefinition(
            identifier: definition.identifier.rawValue,
            buttons: [("continue", .normal)],
            defaultOutcome: "continue"
        )
        let originalCatalog = try MessageBoxCatalog(definitions: [original])
        var preferences = MessageBoxPreferences()

        try preferences.remember(
            continueOutcome,
            for: definition.identifier,
            in: originalCatalog
        )
        try preferences.record(
            deleteOutcome,
            suppressFutureMessages: false,
            for: definition.identifier,
            in: catalog
        )
        XCTAssertEqual(
            preferences.rememberedOutcome(for: definition.identifier, in: originalCatalog),
            continueOutcome
        )
        try preferences.record(
            continueOutcome,
            suppressFutureMessages: false,
            for: definition.identifier,
            in: catalog
        )
        XCTAssertEqual(
            preferences.rememberedOutcome(for: definition.identifier, in: originalCatalog),
            continueOutcome
        )
        let baseline = preferences

        assertPreferencesError(
            .outcomeUnavailable(message: definition.identifier, outcome: unavailable)
        ) {
            try preferences.record(
                unavailable,
                suppressFutureMessages: false,
                for: definition.identifier,
                in: catalog
            )
        }
        XCTAssertEqual(preferences, baseline)
        assertPreferencesError(
            .destructiveOutcomeCannotBeRemembered(
                message: definition.identifier,
                outcome: deleteOutcome
            )
        ) {
            try preferences.record(
                deleteOutcome,
                suppressFutureMessages: true,
                for: definition.identifier,
                in: catalog
            )
        }
        XCTAssertEqual(preferences, baseline)
        assertPreferencesError(.messageDoesNotAllowSuppression(definition.identifier)) {
            try preferences.record(
                continueOutcome,
                suppressFutureMessages: true,
                for: definition.identifier,
                in: catalog
            )
        }
        XCTAssertEqual(preferences, baseline)
    }

    func testUnknownAndStaleCatalogEntriesFailClosed() throws {
        let original = try makeDefinition(
            identifier: "evolving-prompt",
            buttons: [("keep", .normal), ("alternate", .normal)],
            defaultOutcome: "keep"
        )
        let originalCatalog = try MessageBoxCatalog(definitions: [original])
        let keep = try outcomeIdentifier("keep")
        var preferences = MessageBoxPreferences()
        try preferences.remember(keep, for: original.identifier, in: originalCatalog)

        let unknown = try messageIdentifier("unknown-prompt")
        XCTAssertNil(preferences.rememberedOutcome(for: unknown, in: originalCatalog))
        XCTAssertEqual(preferences.decision(for: unknown, in: originalCatalog), .present)
        assertPreferencesError(.unknownMessageIdentifier(unknown)) {
            try preferences.remember(keep, for: unknown, in: originalCatalog)
        }
        assertPreferencesError(.unknownMessageIdentifier(unknown)) {
            try preferences.record(
                keep,
                suppressFutureMessages: false,
                for: unknown,
                in: originalCatalog
            )
        }

        let suppressionRemoved = try makeDefinition(
            identifier: original.identifier.rawValue,
            buttons: [("keep", .normal)],
            defaultOutcome: "keep",
            allowsSuppression: false
        )
        let suppressionRemovedCatalog = try MessageBoxCatalog(definitions: [suppressionRemoved])
        XCTAssertNil(
            preferences.rememberedOutcome(
                for: original.identifier,
                in: suppressionRemovedCatalog
            )
        )
        assertPreferencesError(.messageDoesNotAllowSuppression(original.identifier)) {
            try preferences.validate(against: suppressionRemovedCatalog)
        }
        assertPreferencesError(.messageDoesNotAllowSuppression(original.identifier)) {
            _ = try preferences.encodedData(against: suppressionRemovedCatalog)
        }

        let outcomeRemoved = try makeDefinition(
            identifier: original.identifier.rawValue,
            buttons: [("replacement", .normal)],
            defaultOutcome: "replacement"
        )
        let outcomeRemovedCatalog = try MessageBoxCatalog(definitions: [outcomeRemoved])
        XCTAssertNil(
            preferences.rememberedOutcome(for: original.identifier, in: outcomeRemovedCatalog)
        )
        assertPreferencesError(
            .outcomeUnavailable(message: original.identifier, outcome: keep)
        ) {
            try preferences.validate(against: outcomeRemovedCatalog)
        }

        let removedCatalog = try MessageBoxCatalog(definitions: [])
        XCTAssertNil(preferences.rememberedOutcome(for: original.identifier, in: removedCatalog))
        XCTAssertEqual(preferences.decision(for: original.identifier, in: removedCatalog), .present)
        XCTAssertFalse(preferences.isSuppressed(original.identifier, in: removedCatalog))
        assertPreferencesError(.unknownMessageIdentifier(original.identifier)) {
            try preferences.validate(against: removedCatalog)
        }
        assertPreferencesError(.unknownMessageIdentifier(original.identifier)) {
            _ = try preferences.encodedData(against: removedCatalog)
        }
    }

    func testRecordCapacityUsesMinimumLimitAndResetReleasesCapacity() throws {
        let definitions = try ["one", "two", "three"].map {
            try makeDefinition(
                identifier: $0,
                buttons: [("first", .normal), ("second", .normal)],
                defaultOutcome: "first"
            )
        }
        let first = try outcomeIdentifier("first")
        let second = try outcomeIdentifier("second")
        let missing = try messageIdentifier("missing")

        for (preferencesCap, catalogCap, effectiveCap) in [(3, 2, 2), (1, 3, 1)] {
            let preferencesLimits = try MessageBoxPreferencesLimits(
                maximumDefinitionCount: 3,
                maximumRememberedOutcomeCount: preferencesCap
            )
            let catalogLimits = try MessageBoxPreferencesLimits(
                maximumDefinitionCount: 3,
                maximumRememberedOutcomeCount: catalogCap
            )
            let catalog = try MessageBoxCatalog(
                definitions: definitions,
                limits: catalogLimits
            )
            var preferences = MessageBoxPreferences(limits: preferencesLimits)

            for definition in definitions.prefix(effectiveCap) {
                try preferences.remember(first, for: definition.identifier, in: catalog)
            }
            XCTAssertEqual(preferences.count, effectiveCap)

            let blockedDefinition = definitions[effectiveCap]
            assertPreferencesError(.tooManyRememberedOutcomes(maximumCount: effectiveCap)) {
                try preferences.remember(first, for: blockedDefinition.identifier, in: catalog)
            }

            try preferences.record(
                second,
                suppressFutureMessages: true,
                for: definitions[0].identifier,
                in: catalog
            )
            XCTAssertEqual(
                preferences.rememberedOutcome(for: definitions[0].identifier, in: catalog),
                second
            )
            XCTAssertEqual(preferences.count, effectiveCap)
            XCTAssertFalse(preferences.reset(missing))
            XCTAssertTrue(preferences.reset(definitions[0].identifier))
            XCTAssertFalse(preferences.reset(definitions[0].identifier))

            try preferences.remember(first, for: blockedDefinition.identifier, in: catalog)
            XCTAssertEqual(preferences.count, effectiveCap)
            XCTAssertEqual(preferences.resetAll(), effectiveCap)
            XCTAssertEqual(preferences.resetAll(), 0)
            XCTAssertTrue(preferences.isEmpty)
        }
    }

    func testValidationAndCatalogAwareEncodingUseBothCountAndByteLimits() throws {
        let definitions = try ["one", "two", "three"].map {
            try makeDefinition(identifier: $0)
        }
        let sourceLimits = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 3,
            maximumRememberedOutcomeCount: 3,
            maximumEncodedBytes: 1_024
        )
        let sourceCatalog = try MessageBoxCatalog(definitions: definitions, limits: sourceLimits)
        var preferences = MessageBoxPreferences(limits: sourceLimits)
        let accept = try outcomeIdentifier("accept")
        try preferences.remember(accept, for: definitions[0].identifier, in: sourceCatalog)
        try preferences.remember(accept, for: definitions[1].identifier, in: sourceCatalog)

        let countLimitedCatalog = try MessageBoxCatalog(
            definitions: definitions,
            limits: MessageBoxPreferencesLimits(
                maximumDefinitionCount: 3,
                maximumRememberedOutcomeCount: 1,
                maximumEncodedBytes: 1_024
            )
        )
        assertPreferencesError(.tooManyRememberedOutcomes(maximumCount: 1)) {
            try preferences.validate(against: countLimitedCatalog)
        }
        assertPreferencesError(.tooManyRememberedOutcomes(maximumCount: 1)) {
            _ = try preferences.encodedData(against: countLimitedCatalog)
        }

        let longIdentifier = String(repeating: "m", count: MessageBoxIdentifier.maximumUTF8Bytes)
        let longOutcome = String(
            repeating: "o",
            count: MessageBoxOutcomeIdentifier.maximumUTF8Bytes
        )
        let largeDefinition = try makeDefinition(
            identifier: longIdentifier,
            buttons: [(longOutcome, .normal)],
            defaultOutcome: longOutcome
        )
        let roomyLimits = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 1,
            maximumRememberedOutcomeCount: 1,
            maximumEncodedBytes: 1_024
        )
        let roomyCatalog = try MessageBoxCatalog(
            definitions: [largeDefinition],
            limits: roomyLimits
        )
        var roomyPreferences = MessageBoxPreferences(limits: roomyLimits)
        try roomyPreferences.remember(
            try outcomeIdentifier(longOutcome),
            for: largeDefinition.identifier,
            in: roomyCatalog
        )
        let roomyData = try roomyPreferences.encodedData()
        XCTAssertGreaterThan(roomyData.count, 256)

        let exactLimits = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 1,
            maximumRememberedOutcomeCount: 1,
            maximumEncodedBytes: roomyData.count
        )
        var exactPreferences = MessageBoxPreferences(limits: exactLimits)
        try exactPreferences.remember(
            try outcomeIdentifier(longOutcome),
            for: largeDefinition.identifier,
            in: roomyCatalog
        )
        XCTAssertEqual(try exactPreferences.encodedData(), roomyData)

        let belowExactLimits = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 1,
            maximumRememberedOutcomeCount: 1,
            maximumEncodedBytes: roomyData.count - 1
        )
        var belowExactPreferences = MessageBoxPreferences(limits: belowExactLimits)
        try belowExactPreferences.remember(
            try outcomeIdentifier(longOutcome),
            for: largeDefinition.identifier,
            in: roomyCatalog
        )
        assertPreferencesError(.encodedDataTooLarge(maximumBytes: roomyData.count - 1)) {
            _ = try belowExactPreferences.encodedData()
        }

        let tightLimits = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 1,
            maximumRememberedOutcomeCount: 1,
            maximumEncodedBytes: 256
        )
        let tightCatalog = try MessageBoxCatalog(
            definitions: [largeDefinition],
            limits: tightLimits
        )
        assertPreferencesError(.encodedDataTooLarge(maximumBytes: 256)) {
            _ = try roomyPreferences.encodedData(against: tightCatalog)
        }

        var tightPreferences = MessageBoxPreferences(limits: tightLimits)
        try tightPreferences.remember(
            try outcomeIdentifier(longOutcome),
            for: largeDefinition.identifier,
            in: roomyCatalog
        )
        assertPreferencesError(.encodedDataTooLarge(maximumBytes: 256)) {
            _ = try tightPreferences.encodedData(against: roomyCatalog)
        }
    }

    func testDecodeEnforcesCatalogCountAndExactByteLimits() throws {
        let definitions = try ["one", "two"].map { try makeDefinition(identifier: $0) }
        let limits = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 2,
            maximumRememberedOutcomeCount: 1,
            maximumEncodedBytes: 256
        )
        let catalog = try MessageBoxCatalog(definitions: definitions, limits: limits)
        let excessiveEntries = wireData(
            entries: [("one", "accept"), ("two", "accept")]
        )
        assertPreferencesError(.tooManyRememberedOutcomes(maximumCount: 1)) {
            _ = try MessageBoxPreferences.decode(from: excessiveEntries, catalog: catalog)
        }
        let exactEntry = try MessageBoxPreferences.decode(
            from: wireData(entries: [(definitions[0].identifier.rawValue, "accept")]),
            catalog: catalog
        )
        XCTAssertEqual(exactEntry.count, 1)
        XCTAssertEqual(
            exactEntry.rememberedOutcome(for: definitions[0].identifier, in: catalog)?.rawValue,
            "accept"
        )

        var exactBoundary = wireData(entries: [])
        exactBoundary.append(Data(repeating: 0x20, count: 256 - exactBoundary.count))
        XCTAssertEqual(exactBoundary.count, 256)
        let decoded = try MessageBoxPreferences.decode(from: exactBoundary, catalog: catalog)
        XCTAssertTrue(decoded.isEmpty)
        XCTAssertEqual(decoded.limits, limits)

        var oversized = exactBoundary
        oversized.append(0x20)
        assertPreferencesError(.encodedDataTooLarge(maximumBytes: 256)) {
            _ = try MessageBoxPreferences.decode(from: oversized, catalog: catalog)
        }
        XCTAssertEqual(try MessageBoxPreferences.restored(from: nil, catalog: catalog), decoded)
    }

    func testSchemaMigrationRejectsOrResetsWithoutGuessing() throws {
        let definition = try makeDefinition(identifier: "known")
        let catalog = try MessageBoxCatalog(definitions: [definition])

        for version in [-1, 0, 2, Int32.max] {
            let data = Data(
                "{\"rememberedOutcomes\":[],\"schemaVersion\":\(version)}".utf8
            )
            assertPreferencesError(.unsupportedSchemaVersion(Int(version))) {
                _ = try MessageBoxPreferences.decode(from: data, catalog: catalog)
            }
        }

        let unsupportedWithUnusableCurrentSchemaPayload = Data(
            #"{"rememberedOutcomes":"not-current-schema","schemaVersion":2}"#.utf8
        )
        let reset = try MessageBoxPreferences.decode(
            from: unsupportedWithUnusableCurrentSchemaPayload,
            catalog: catalog,
            migrationPolicy: .resetToDefaults
        )
        XCTAssertTrue(reset.isEmpty)
        XCTAssertEqual(reset.limits, catalog.limits)

        let restoredReset = try MessageBoxPreferences.restored(
            from: unsupportedWithUnusableCurrentSchemaPayload,
            catalog: catalog,
            migrationPolicy: .resetToDefaults
        )
        XCTAssertTrue(restoredReset.isEmpty)
        XCTAssertEqual(restoredReset.limits, catalog.limits)

        let currentData = wireData(entries: [(definition.identifier.rawValue, "accept")])
        let restoredCurrent = try MessageBoxPreferences.restored(
            from: currentData,
            catalog: catalog,
            migrationPolicy: .resetToDefaults
        )
        XCTAssertEqual(restoredCurrent.count, 1)
        XCTAssertEqual(
            restoredCurrent.rememberedOutcome(for: definition.identifier, in: catalog)?.rawValue,
            "accept"
        )

        let malformedCurrentSchema = Data(
            #"{"rememberedOutcomes":"not-current-schema","schemaVersion":1}"#.utf8
        )
        XCTAssertThrowsError(
            try MessageBoxPreferences.restored(
                from: malformedCurrentSchema,
                catalog: catalog,
                migrationPolicy: .resetToDefaults
            )
        )
        assertPreferencesError(
            .unknownMessageIdentifier(try messageIdentifier("forged-message"))
        ) {
            _ = try MessageBoxPreferences.restored(
                from: wireData(entries: [("forged-message", "accept")]),
                catalog: catalog,
                migrationPolicy: .resetToDefaults
            )
        }
    }

    func testDecodeRejectsDuplicateJSONKeysAndRememberedMessages() throws {
        let definition = try makeDefinition(identifier: "known")
        let catalog = try MessageBoxCatalog(definitions: [definition])
        let duplicatePayloads: [(Data, MessageBoxPreferencesError)] = [
            (
                Data(
                    #"{"schemaVersion":1,"schemaVersion":1,"rememberedOutcomes":[]}"#.utf8
                ),
                .duplicateJSONKey("schemaVersion")
            ),
            (
                Data(
                    #"{"schemaVersion":1,"schema\u0056ersion":1,"rememberedOutcomes":[]}"#.utf8
                ),
                .duplicateJSONKey("schemaVersion")
            ),
            (
                Data(
                    #"{"rememberedOutcomes":[{"messageIdentifier":"known","message\u0049dentifier":"known","outcome":"accept"}],"schemaVersion":1}"#.utf8
                ),
                .duplicateJSONKey("messageIdentifier")
            )
        ]

        for (payload, expected) in duplicatePayloads {
            assertPreferencesError(expected) {
                _ = try MessageBoxPreferences.decode(from: payload, catalog: catalog)
            }
        }

        let duplicateEntries = wireData(
            entries: [(definition.identifier.rawValue, "accept"), (definition.identifier.rawValue, "accept")]
        )
        assertPreferencesError(.duplicateRememberedMessage(definition.identifier)) {
            _ = try MessageBoxPreferences.decode(from: duplicateEntries, catalog: catalog)
        }
    }

    func testDecodeRejectsUnknownAndForgedSafetyMetadataFields() throws {
        let catalog = try MessageBoxCatalog(
            definitions: [try makeDefinition(identifier: "known")]
        )
        for unknownRoot in ["alpha", "zeta"] {
            let data = Data(
                "{\"\(unknownRoot)\":true,\"rememberedOutcomes\":[],\"schemaVersion\":1}"
                    .utf8
            )
            assertPreferencesError(.unknownField(unknownRoot)) {
                _ = try MessageBoxPreferences.decode(from: data, catalog: catalog)
            }
        }

        for (field, value) in [
            ("allowsSuppression", "true"),
            ("category", "\"informational\"")
        ] {
            let data = Data(
                "{\"rememberedOutcomes\":[{\"messageIdentifier\":\"known\",\"outcome\":\"accept\",\"\(field)\":\(value)}],\"schemaVersion\":1}"
                    .utf8
            )
            assertPreferencesError(.unknownField(field)) {
                _ = try MessageBoxPreferences.decode(from: data, catalog: catalog)
            }
        }

        let forgedUnknownMessage = wireData(entries: [("forged-message", "accept")])
        assertPreferencesError(
            .unknownMessageIdentifier(try messageIdentifier("forged-message"))
        ) {
            _ = try MessageBoxPreferences.decode(from: forgedUnknownMessage, catalog: catalog)
        }

        let forgedOutcome = try outcomeIdentifier("forged-outcome")
        assertPreferencesError(
            .outcomeUnavailable(message: try messageIdentifier("known"), outcome: forgedOutcome)
        ) {
            _ = try MessageBoxPreferences.decode(
                from: wireData(entries: [("known", forgedOutcome.rawValue)]),
                catalog: catalog
            )
        }

        let nonSuppressible = try makeDefinition(
            identifier: "non-suppressible",
            category: .security,
            allowsSuppression: false
        )
        let nonSuppressibleCatalog = try MessageBoxCatalog(definitions: [nonSuppressible])
        assertPreferencesError(.messageDoesNotAllowSuppression(nonSuppressible.identifier)) {
            _ = try MessageBoxPreferences.decode(
                from: wireData(entries: [(nonSuppressible.identifier.rawValue, "accept")]),
                catalog: nonSuppressibleCatalog
            )
        }
    }

    func testDecodeRejectsMalformedJSONInvalidTokensAndWireTypes() throws {
        let catalog = try MessageBoxCatalog(
            definitions: [try makeDefinition(identifier: "known")]
        )
        let valid = wireData(entries: [])
        let scannerFailures = [
            Data(),
            Data("{".utf8),
            valid + Data(" trailing".utf8),
            Data([0xFF]),
            Data("tru".utf8),
            Data(#"{"rememberedOutcomes":[],"schemaVersion":01}"#.utf8),
            Data(#"{"rememberedOutcomes":[],"schemaVersion":1e}"#.utf8),
            Data(#"{"rememberedOutcomes":[],"schemaVersion":+1}"#.utf8),
            Data("{\"rememberedOutcomes\":[],\"schemaVersion\":1,\"bad\u{0000}key\":0}".utf8)
        ]
        for payload in scannerFailures {
            assertPreferencesError(.invalidJSON) {
                _ = try MessageBoxPreferences.decode(from: payload, catalog: catalog)
            }
        }

        let wireTypeFailures = [
            Data("null".utf8),
            Data("[]".utf8),
            Data(#"{"rememberedOutcomes":[]}"#.utf8),
            Data(#"{"rememberedOutcomes":[],"schemaVersion":"1"}"#.utf8),
            Data(#"{"rememberedOutcomes":{},"schemaVersion":1}"#.utf8),
            Data(
                #"{"rememberedOutcomes":[{"messageIdentifier":"known"}],"schemaVersion":1}"#.utf8
            )
        ]
        for payload in wireTypeFailures {
            XCTAssertThrowsError(
                try MessageBoxPreferences.decode(from: payload, catalog: catalog)
            )
        }

        let invalidToken = Data(
            #"{"rememberedOutcomes":[{"messageIdentifier":"bad value","outcome":"accept"}],"schemaVersion":1}"#.utf8
        )
        assertPreferencesError(.invalidToken("bad value")) {
            _ = try MessageBoxPreferences.decode(from: invalidToken, catalog: catalog)
        }
        let invalidOutcomeToken = Data(
            #"{"rememberedOutcomes":[{"messageIdentifier":"known","outcome":"bad value"}],"schemaVersion":1}"#.utf8
        )
        assertPreferencesError(.invalidToken("bad value")) {
            _ = try MessageBoxPreferences.decode(from: invalidOutcomeToken, catalog: catalog)
        }
    }

    func testStrictJSONScannerEnforcesDepthContainerValueStringAndNumberBounds() throws {
        let catalog = try MessageBoxCatalog(definitions: [])

        let maximumDepth = Data(
            (String(repeating: "[", count: 8) + "null" + String(repeating: "]", count: 8)).utf8
        )
        assertScannerAccepts(
            maximumDepth,
            catalog: catalog
        )

        let excessiveDepth = Data(
            (String(repeating: "[", count: 9) + "null" + String(repeating: "]", count: 9)).utf8
        )
        assertPreferencesError(.jsonNestingTooDeep(maximumDepth: 8)) {
            _ = try MessageBoxPreferences.decode(from: excessiveDepth, catalog: catalog)
        }

        let maximumContainer = Data(
            ("[" + [String](repeating: "0", count: 264).joined(separator: ",") + "]").utf8
        )
        assertScannerAccepts(
            maximumContainer,
            catalog: catalog
        )

        let excessiveContainer = Data(
            ("[" + [String](repeating: "0", count: 265).joined(separator: ",") + "]").utf8
        )
        assertPreferencesError(.jsonContainerTooLarge(maximumElements: 264)) {
            _ = try MessageBoxPreferences.decode(from: excessiveContainer, catalog: catalog)
        }

        let fullLeaf = "[" + [String](repeating: "0", count: 256).joined(separator: ",") + "]"
        let excessiveValues = Data(
            ("[" + [String](repeating: fullLeaf, count: 4).joined(separator: ",") + "]").utf8
        )
        let partialLeaf = "[" + [String](repeating: "0", count: 251).joined(separator: ",") + "]"
        let maximumValues = Data(
            ("[" + [String](repeating: fullLeaf, count: 3).joined(separator: ",") + "," + partialLeaf + "]").utf8
        )
        assertScannerAccepts(
            maximumValues,
            catalog: catalog
        )
        assertPreferencesError(.tooManyJSONValues(maximumValues: 1_024)) {
            _ = try MessageBoxPreferences.decode(from: excessiveValues, catalog: catalog)
        }

        let maximumString = Data(
            ("\"" + String(repeating: "s", count: 256) + "\"").utf8
        )
        assertScannerAccepts(
            maximumString,
            catalog: catalog
        )

        let excessiveString = Data(
            ("\"" + String(repeating: "s", count: 257) + "\"").utf8
        )
        assertPreferencesError(.jsonStringTooLarge(maximumBytes: 256)) {
            _ = try MessageBoxPreferences.decode(from: excessiveString, catalog: catalog)
        }

        let maximumNumber = Data(String(repeating: "1", count: 32).utf8)
        assertScannerAccepts(
            maximumNumber,
            catalog: catalog
        )

        let excessiveNumber = Data(("1" + String(repeating: "0", count: 32)).utf8)
        assertPreferencesError(.jsonNumberTooLarge(maximumBytes: 32)) {
            _ = try MessageBoxPreferences.decode(from: excessiveNumber, catalog: catalog)
        }
    }

    func testDecodeUsesImmutableSnapshotWhenCallerBackingMutates() throws {
        let definition = try makeDefinition(identifier: "snapshot")
        let catalog = try MessageBoxCatalog(definitions: [definition])
        let source = wireData(entries: [(definition.identifier.rawValue, "accept")])
        let baselineProbe = CancellationProbe()
        _ = try MessageBoxPreferences.decode(
            from: source,
            catalog: catalog,
            cancellationCheck: { try baselineProbe.check() }
        )
        let backing = MutableDataBacking(source)
        XCTAssertEqual(baselineProbe.checkCount, 5)
        let probe = CancellationProbe(performOnCheck: 2) {
            backing.overwriteFirstByte(with: 0x78)
        }

        let decoded = try MessageBoxPreferences.decode(
            from: backing.data,
            catalog: catalog,
            cancellationCheck: { try probe.check() }
        )

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(
            decoded.rememberedOutcome(for: definition.identifier, in: catalog)?.rawValue,
            "accept"
        )
        XCTAssertEqual(backing.data.first, 0x78)
        XCTAssertEqual(probe.checkCount, baselineProbe.checkCount)
        assertPreferencesError(.invalidJSON) {
            _ = try MessageBoxPreferences.decode(from: backing.data, catalog: catalog)
        }
    }

    func testCancellationPrecedesCatalogSizeSchemaAndSemanticFailures() throws {
        let first = try makeDefinition(identifier: "first")
        let second = try makeDefinition(identifier: "second")
        let oneDefinitionLimit = try MessageBoxPreferencesLimits(
            maximumDefinitionCount: 1,
            maximumRememberedOutcomeCount: 1
        )
        let catalogProbe = CancellationProbe(throwOnCheck: 1)
        assertCancellation {
            _ = try MessageBoxCatalog(
                definitions: [first, second],
                limits: oneDefinitionLimit,
                cancellationCheck: { try catalogProbe.check() }
            )
        }
        XCTAssertEqual(catalogProbe.checkCount, 1)

        let byteLimitedCatalog = try MessageBoxCatalog(
            definitions: [first],
            limits: MessageBoxPreferencesLimits(
                maximumDefinitionCount: 1,
                maximumRememberedOutcomeCount: 1,
                maximumEncodedBytes: 256
            )
        )
        let decodeSizeProbe = CancellationProbe(throwOnCheck: 1)
        assertCancellation {
            _ = try MessageBoxPreferences.decode(
                from: Data(repeating: 0x20, count: 257),
                catalog: byteLimitedCatalog,
                cancellationCheck: { try decodeSizeProbe.check() }
            )
        }

        let sourceCatalog = try MessageBoxCatalog(definitions: [first])
        var preferences = MessageBoxPreferences()
        try preferences.remember(
            try outcomeIdentifier("accept"),
            for: first.identifier,
            in: sourceCatalog
        )
        let staleDefinition = try makeDefinition(
            identifier: first.identifier.rawValue,
            allowsSuppression: false
        )
        let staleCatalog = try MessageBoxCatalog(definitions: [staleDefinition])
        let validateProbe = CancellationProbe(throwOnCheck: 1)
        assertCancellation {
            try preferences.validate(
                against: staleCatalog,
                cancellationCheck: { try validateProbe.check() }
            )
        }

        let encodeProbe = CancellationProbe(throwOnCheck: 1)
        assertCancellation {
            _ = try preferences.encodedData(cancellationCheck: { try encodeProbe.check() })
        }

        let schemaProbe = CancellationProbe(throwOnCheck: 1)
        assertCancellation {
            _ = try MessageBoxPreferences.decode(
                from: Data(#"{"rememberedOutcomes":[],"schemaVersion":2}"#.utf8),
                catalog: sourceCatalog,
                migrationPolicy: .resetToDefaults,
                cancellationCheck: { try schemaProbe.check() }
            )
        }

        let restoreProbe = CancellationProbe(throwOnCheck: 1)
        assertCancellation {
            _ = try MessageBoxPreferences.restored(
                from: nil,
                catalog: sourceCatalog,
                cancellationCheck: { try restoreProbe.check() }
            )
        }

        let laterCatalogProbe = CancellationProbe(throwOnCheck: 4)
        assertCancellation {
            _ = try MessageBoxCatalog(
                definitions: [first, second],
                cancellationCheck: { try laterCatalogProbe.check() }
            )
        }
        XCTAssertEqual(laterCatalogProbe.checkCount, 4)

        let secondPreferencesDefinition = try makeDefinition(identifier: "second-preference")
        let multiItemCatalog = try MessageBoxCatalog(
            definitions: [first, secondPreferencesDefinition]
        )
        try preferences.remember(
            try outcomeIdentifier("accept"),
            for: secondPreferencesDefinition.identifier,
            in: multiItemCatalog
        )
        let laterValidateProbe = CancellationProbe(throwOnCheck: 4)
        assertCancellation {
            try preferences.validate(
                against: multiItemCatalog,
                cancellationCheck: { try laterValidateProbe.check() }
            )
        }
        XCTAssertEqual(laterValidateProbe.checkCount, 4)

        let laterEncodeProbe = CancellationProbe(throwOnCheck: 2)
        assertCancellation {
            _ = try preferences.encodedData(
                cancellationCheck: { try laterEncodeProbe.check() }
            )
        }
        XCTAssertEqual(laterEncodeProbe.checkCount, 2)

        let forwardedRestoreProbe = CancellationProbe(throwOnCheck: 2)
        assertCancellation {
            _ = try MessageBoxPreferences.restored(
                from: wireData(entries: []),
                catalog: sourceCatalog,
                cancellationCheck: { try forwardedRestoreProbe.check() }
            )
        }
        XCTAssertEqual(forwardedRestoreProbe.checkCount, 2)
    }

    func testCancellationRunsInsideWhitespaceAndNumberLoopsBeforeParseErrors() throws {
        let catalog = try MessageBoxCatalog(definitions: [])
        let whitespacePayload = Data(
            (String(repeating: " ", count: 3_072) + "?").utf8
        )
        assertPreferencesError(.invalidJSON) {
            _ = try MessageBoxPreferences.decode(from: whitespacePayload, catalog: catalog)
        }
        let whitespaceProbe = CancellationProbe(throwOnCheck: 4)
        assertCancellation {
            _ = try MessageBoxPreferences.decode(
                from: whitespacePayload,
                catalog: catalog,
                cancellationCheck: { try whitespaceProbe.check() }
            )
        }
        XCTAssertEqual(whitespaceProbe.checkCount, 4)

        let numberPayload = Data(
            ("{\"schemaVersion\":"
                + String(repeating: "9", count: 2_048)
                + ",\"rememberedOutcomes\":[]}").utf8
        )
        assertPreferencesError(.jsonNumberTooLarge(maximumBytes: 32)) {
            _ = try MessageBoxPreferences.decode(from: numberPayload, catalog: catalog)
        }
        let numberProbe = CancellationProbe(throwOnCheck: 3)
        assertCancellation {
            _ = try MessageBoxPreferences.decode(
                from: numberPayload,
                catalog: catalog,
                cancellationCheck: { try numberProbe.check() }
            )
        }
        XCTAssertEqual(numberProbe.checkCount, 3)
    }

    func testCancellationRunsInLaterEntryAndEscapeLoops() throws {
        let definitions = try ["one", "two", "three"].map {
            try makeDefinition(identifier: $0)
        }
        let catalog = try MessageBoxCatalog(definitions: definitions)
        let entries = definitions.map { ($0.identifier.rawValue, "accept") }
        let entryPayload = wireData(entries: entries)
        let entryBaseline = CancellationProbe()
        _ = try MessageBoxPreferences.decode(
            from: entryPayload,
            catalog: catalog,
            cancellationCheck: { try entryBaseline.check() }
        )
        XCTAssertEqual(entryBaseline.checkCount, 7)

        let entryProbe = CancellationProbe(throwOnCheck: 6)
        assertCancellation {
            _ = try MessageBoxPreferences.decode(
                from: entryPayload,
                catalog: catalog,
                cancellationCheck: { try entryProbe.check() }
            )
        }
        XCTAssertEqual(entryProbe.checkCount, 6)

        let shortEscapedPayload = Data(#""\u0061""#.utf8)
        let shortEscapeProbe = CancellationProbe()
        assertDecodingError {
            _ = try MessageBoxPreferences.decode(
                from: shortEscapedPayload,
                catalog: catalog,
                cancellationCheck: { try shortEscapeProbe.check() }
            )
        }
        let escapedPayload = Data(
            ("\"" + String(repeating: "\\u0061", count: 256) + "\"").utf8
        )
        let escapeBaseline = CancellationProbe()
        assertDecodingError {
            _ = try MessageBoxPreferences.decode(
                from: escapedPayload,
                catalog: catalog,
                cancellationCheck: { try escapeBaseline.check() }
            )
        }
        XCTAssertEqual(shortEscapeProbe.checkCount, 3)
        XCTAssertEqual(escapeBaseline.checkCount, shortEscapeProbe.checkCount + 1)

        let escapeProbe = CancellationProbe(throwOnCheck: 3)
        assertCancellation {
            _ = try MessageBoxPreferences.decode(
                from: escapedPayload,
                catalog: catalog,
                cancellationCheck: { try escapeProbe.check() }
            )
        }
        XCTAssertEqual(escapeProbe.checkCount, 3)
    }

    func testDeterministicCatalogAwareRoundTripUsesSortedCompactJSON() throws {
        let zeta = try makeDefinition(
            identifier: "zeta",
            buttons: [("later", .normal)],
            defaultOutcome: "later"
        )
        let alpha = try makeDefinition(identifier: "alpha")
        let catalog = try MessageBoxCatalog(definitions: [zeta, alpha])
        var preferences = MessageBoxPreferences()
        try preferences.remember(
            try outcomeIdentifier("later"),
            for: zeta.identifier,
            in: catalog
        )
        try preferences.remember(
            try outcomeIdentifier("accept"),
            for: alpha.identifier,
            in: catalog
        )

        let first = try preferences.encodedData(against: catalog)
        let second = try preferences.encodedData(against: catalog)
        let expected =
            #"{"rememberedOutcomes":[{"messageIdentifier":"alpha","outcome":"accept"},{"messageIdentifier":"zeta","outcome":"later"}],"schemaVersion":1}"#

        XCTAssertEqual(first, second)
        XCTAssertEqual(String(decoding: first, as: UTF8.self), expected)
        XCTAssertFalse(first.contains(0x0A))
        XCTAssertEqual(
            preferences.rememberedMessageIdentifiers.map(\.rawValue),
            ["alpha", "zeta"]
        )

        let decoded = try MessageBoxPreferences.decode(from: first, catalog: catalog)
        XCTAssertEqual(decoded, preferences)
        XCTAssertEqual(try decoded.encodedData(against: catalog), first)
        requireSendable(catalog)
        requireSendable(decoded)
        requireSendable(MessageBoxPreferencesError.invalidJSON)
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }

    private func messageIdentifier(_ rawValue: String) throws -> MessageBoxIdentifier {
        try MessageBoxIdentifier(rawValue)
    }

    private func outcomeIdentifier(_ rawValue: String) throws -> MessageBoxOutcomeIdentifier {
        try MessageBoxOutcomeIdentifier(rawValue)
    }

    private func localizationToken(_ rawValue: String) throws -> MessageBoxLocalizationToken {
        try MessageBoxLocalizationToken(rawValue)
    }

    private func accessibilityToken(_ rawValue: String) throws -> MessageBoxAccessibilityToken {
        try MessageBoxAccessibilityToken(rawValue)
    }

    private func makeDefinition(
        identifier rawIdentifier: String,
        category: MessageBoxCategory = .nonDestructive,
        buttons: [(String, MessageBoxButtonRole)] = [("accept", .normal)],
        defaultOutcome rawDefaultOutcome: String = "accept",
        cancellationOutcome rawCancellationOutcome: String? = nil,
        allowsSuppression: Bool = true
    ) throws -> MessageBoxDefinition {
        let identifier = try messageIdentifier(rawIdentifier)
        return try MessageBoxDefinition(
            identifier: identifier,
            category: category,
            metadata: makeMetadata(
                identifier: rawIdentifier,
                suppression: allowsSuppression
            ),
            buttons: try buttons.map {
                try makeButton(
                    outcome: $0.0,
                    role: $0.1,
                    message: rawIdentifier
                )
            },
            defaultOutcome: outcomeIdentifier(rawDefaultOutcome),
            cancellationOutcome: try rawCancellationOutcome.map(outcomeIdentifier),
            allowsSuppression: allowsSuppression
        )
    }

    private func makeButton(
        outcome rawOutcome: String,
        role: MessageBoxButtonRole,
        message: String
    ) throws -> MessageBoxButton {
        MessageBoxButton(
            outcome: try outcomeIdentifier(rawOutcome),
            role: role,
            titleLocalizationToken: try localizationToken(
                "button.\(message).\(rawOutcome).title"
            ),
            accessibilityToken: try accessibilityToken(
                "button.\(message).\(rawOutcome).accessibility"
            )
        )
    }

    private func makeMetadata(
        identifier: String,
        suppression: Bool
    ) throws -> MessageBoxMetadata {
        try makeMetadata(
            identifier: identifier,
            suppressionLocalization: suppression,
            suppressionAccessibility: suppression
        )
    }

    private func makeMetadata(
        identifier: String,
        suppressionLocalization: Bool,
        suppressionAccessibility: Bool
    ) throws -> MessageBoxMetadata {
        MessageBoxMetadata(
            titleLocalizationToken: try localizationToken("message.\(identifier).title"),
            messageLocalizationToken: try localizationToken("message.\(identifier).body"),
            accessibilityToken: try accessibilityToken(
                "message.\(identifier).accessibility"
            ),
            suppressionLocalizationToken: try suppressionLocalization
                ? localizationToken("message.\(identifier).suppression")
                : nil,
            suppressionAccessibilityToken: try suppressionAccessibility
                ? accessibilityToken("message.\(identifier).suppression-accessibility")
                : nil
        )
    }

    private func wireData(
        schemaVersion: Int = MessageBoxPreferences.currentSchemaVersion,
        entries: [(String, String)]
    ) -> Data {
        let encodedEntries = entries.map {
            "{\"messageIdentifier\":\"\($0.0)\",\"outcome\":\"\($0.1)\"}"
        }.joined(separator: ",")
        return Data(
            "{\"rememberedOutcomes\":[\(encodedEntries)],\"schemaVersion\":\(schemaVersion)}".utf8
        )
    }

    private func assertScannerAccepts(
        _ data: Data,
        catalog: MessageBoxCatalog,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertDecodingError(file: file, line: line) {
            _ = try MessageBoxPreferences.decode(from: data, catalog: catalog)
        }
    }

    private func assertDecodingError(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertTrue(
                error is DecodingError,
                "Expected DecodingError, got \(error)",
                file: file,
                line: line
            )
        }
    }

    private func assertInvalidToken(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case MessageBoxPreferencesError.invalidToken = error else {
                XCTFail("Expected invalidToken, got \(error)", file: file, line: line)
                return
            }
        }
    }

    private func assertPreferencesError(
        _ expected: MessageBoxPreferencesError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? MessageBoxPreferencesError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertCancellation(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertTrue(
                error is CancellationError,
                "Expected CancellationError, got \(error)",
                file: file,
                line: line
            )
        }
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let throwOnCheck: Int?
    private let performOnCheck: Int?
    private let action: (@Sendable () -> Void)?
    private var storedCheckCount = 0

    init(
        throwOnCheck: Int? = nil,
        performOnCheck: Int? = nil,
        action: (@Sendable () -> Void)? = nil
    ) {
        self.throwOnCheck = throwOnCheck
        self.performOnCheck = performOnCheck
        self.action = action
    }

    var checkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCheckCount
    }

    func check() throws {
        lock.lock()
        storedCheckCount += 1
        let currentCheck = storedCheckCount
        lock.unlock()

        if currentCheck == performOnCheck { action?() }
        if currentCheck == throwOnCheck { throw CancellationError() }
    }
}

private final class MutableDataBacking: @unchecked Sendable {
    private let storage: UnsafeMutableRawPointer
    private let count: Int
    let data: Data

    init(_ source: Data) {
        count = source.count
        storage = UnsafeMutableRawPointer.allocate(
            byteCount: source.count,
            alignment: MemoryLayout<UInt8>.alignment
        )
        source.copyBytes(
            to: storage.assumingMemoryBound(to: UInt8.self),
            count: source.count
        )
        data = Data(bytesNoCopy: storage, count: source.count, deallocator: .none)
    }

    deinit {
        storage.deallocate()
    }

    func overwriteFirstByte(with byte: UInt8) {
        guard count > 0 else { return }
        storage.storeBytes(of: byte, as: UInt8.self)
    }
}
