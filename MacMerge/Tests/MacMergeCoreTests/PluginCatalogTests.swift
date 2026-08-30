import CryptoKit
import Foundation
import XCTest

@testable import MacMergeCore

final class PluginCatalogTests: XCTestCase {
    func testCapabilityMappingsAndUnsupportedOperationsAreExplicit() throws {
        let mappings: [PluginCapability: ExternalToolCapability?] = [
            .unpacker: .unpacker,
            .prediffer: .prediffer,
            .editor: .editorScript,
            .copy: .copyingScript,
            .transform: nil
        ]

        XCTAssertEqual(Set(mappings.keys), Set(PluginCapability.allCases))
        for capability in PluginCapability.allCases {
            XCTAssertEqual(capability.externalToolCapability, mappings[capability]!)
        }

        let catalog = try PluginCatalog()
        XCTAssertEqual(
            catalog.reloadOutcome(),
            PluginCatalogOperationOutcome(
                operation: .reload,
                status: .unsupported,
                reason: .pluginReloadUnsupported
            )
        )
        XCTAssertEqual(
            catalog.inProcessLoadingOutcome(),
            PluginCatalogOperationOutcome(
                operation: .inProcessLoading,
                status: .unsupported,
                reason: .inProcessExtensionsUnsupported
            )
        )
    }

    func testMetadataIsCanonicalValidatedSortedAndFilterable() throws {
        let settingZ = try PluginSettingSchema(
            key: "zeta",
            title: "Zeta",
            constraint: .boolean,
            defaultValue: .boolean(false)
        )
        let settingA = try PluginSettingSchema(
            key: "alpha",
            title: "Alpha",
            constraint: .choice(["safe", "fast"]),
            defaultValue: .choice("safe")
        )
        let metadata = try PluginMatchMetadata(
            fileExtensions: [".TXT", "Markdown"],
            contentTypeIdentifiers: ["PUBLIC.PLAIN-TEXT"]
        )
        let zulu = try PluginCatalogItem(
            id: PluginIdentifier("plugin.zulu"),
            displayName: "Zulu",
            summary: "Reviewed metadata",
            version: "1.2.3-beta",
            capability: .transform,
            manualEligible: true,
            automaticEligible: false,
            matchMetadata: metadata,
            settings: [settingZ, settingA]
        )
        let alpha = try PluginCatalogItem(
            id: PluginIdentifier("plugin.alpha"),
            displayName: "Alpha",
            version: "1",
            capability: .transform,
            manualEligible: false,
            matchMetadata: PluginMatchMetadata(fileExtensions: ["csv"])
        )
        let policy = try privacyPolicy(
            for: zulu,
            classifications: ["alpha": .nonSecret, "zeta": .nonSecret]
        )
        let catalog = try PluginCatalog(items: [zulu, alpha], settingPrivacyPolicy: policy)

        XCTAssertEqual(metadata.fileExtensions, ["markdown", "txt"])
        XCTAssertEqual(metadata.contentTypeIdentifiers, ["public.plain-text"])
        XCTAssertEqual(zulu.settings.map(\.key), ["alpha", "zeta"])
        XCTAssertEqual(catalog.items.map(\.id.rawValue), ["plugin.alpha", "plugin.zulu"])
        XCTAssertEqual(catalog.item(withIdentifier: zulu.id), zulu)
        XCTAssertEqual(
            try catalog.items(matching: PluginCatalogFilter(mode: .manual)).map(\.id),
            [zulu.id]
        )
        XCTAssertEqual(
            try catalog.items(matching: PluginCatalogFilter(fileExtension: ".tXt")).map(\.id),
            [zulu.id]
        )
        XCTAssertEqual(
            try catalog.items(
                matching: PluginCatalogFilter(contentTypeIdentifier: "PUBLIC.PLAIN-TEXT")
            ).map(\.id),
            [zulu.id]
        )
        XCTAssertEqual(
            try catalog.items(matching: PluginCatalogFilter(capability: .unpacker)),
            []
        )

        assertCatalogError(.invalidIdentifier) {
            try PluginIdentifier("../plugin")
        }
        assertCatalogError(.invalidMetadata(field: "displayName")) {
            try PluginCatalogItem(
                id: PluginIdentifier("plugin.control"),
                displayName: "unsafe\nname",
                version: "1",
                capability: .transform
            )
        }
        assertCatalogError(.duplicateMatchValue) {
            try PluginMatchMetadata(fileExtensions: ["TXT", ".txt"])
        }
        assertCatalogError(.duplicateItemIdentifier) {
            try PluginCatalog(items: [alpha, alpha])
        }
        assertCatalogError(.duplicateSettingKey) {
            try PluginCatalogItem(
                id: PluginIdentifier("plugin.duplicate-setting"),
                displayName: "Duplicate",
                version: "1",
                capability: .transform,
                settings: [settingA, settingA]
            )
        }
        assertCatalogError(.invalidExternalToolRuleIdentifier) {
            try PluginCatalogItem(
                id: PluginIdentifier("plugin.transform-rule"),
                displayName: "Transform",
                version: "1",
                capability: .transform,
                externalToolRuleIdentifier: "reviewed-rule"
            )
        }
    }

    func testPreferencesValidateReferencesValuesAndAutomaticInvariants() throws {
        let item = try mixedSettingsItem()
        let policy = try mixedPrivacyPolicy(for: item)
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [item.id],
            automaticPluginIdentifiers: [item.id],
            preferredAutomaticPluginIdentifiers: [item.id],
            settingValues: [
                item.id: [
                    "enabled": .boolean(true),
                    "mode": .choice("fast"),
                    "profile": .string("reviewed"),
                    "retries": .integer(7)
                ]
            ]
        )

        XCTAssertEqual(preferences.enabledPluginIdentifiers, [item.id])
        XCTAssertEqual(preferences.automaticPluginIdentifiers, [item.id])
        XCTAssertEqual(preferences.preferredAutomaticPluginIdentifiers, [item.id])
        XCTAssertEqual(preferences.settingValues[item.id]?["retries"], .integer(7))

        assertCatalogError(.automaticPreferenceRequiresEnabledPlugin) {
            try PluginCatalogPreferences(
                catalog: catalog,
                automaticPluginIdentifiers: [item.id]
            )
        }
        assertCatalogError(.preferredPluginMustBeAutomatic) {
            try PluginCatalogPreferences(
                catalog: catalog,
                enabledPluginIdentifiers: [item.id],
                preferredAutomaticPluginIdentifiers: [item.id]
            )
        }
        assertCatalogError(.duplicatePreferredPlugin) {
            try PluginCatalogPreferences(
                catalog: catalog,
                enabledPluginIdentifiers: [item.id],
                automaticPluginIdentifiers: [item.id],
                preferredAutomaticPluginIdentifiers: [item.id, item.id]
            )
        }
        assertCatalogError(.preferenceReferencesUnknownPlugin) {
            try PluginCatalogPreferences(
                catalog: catalog,
                enabledPluginIdentifiers: [PluginIdentifier("plugin.missing")]
            )
        }
        assertCatalogError(.preferenceReferencesUnknownSetting) {
            try PluginCatalogPreferences(
                catalog: catalog,
                settingValues: [item.id: ["missing": .boolean(true)]]
            )
        }
        assertCatalogError(.invalidSettingValue) {
            try PluginCatalogPreferences(
                catalog: catalog,
                settingValues: [item.id: ["retries": .integer(11)]]
            )
        }
        assertCatalogError(.invalidSettingValue) {
            try PluginCatalogPreferences(
                catalog: catalog,
                settingValues: [item.id: ["mode": .choice("unreviewed")]]
            )
        }
    }

    func testEligibilitySelectionNeverUsesRegistrationOrderAsAuthority() throws {
        let fixture = try makeExternalFixture()
        let rules = [
            makeRule(fixture, identifier: "rule-alpha"),
            makeRule(fixture, identifier: "rule-beta", executableURL: fixture.alternateExecutableURL)
        ]
        let externalPolicy = try ExternalToolPolicy(externalExecutableRules: rules)
        let authority = MutableAuthorityState(now: referenceDate, generation: 7)
        let verifier = try authorizationVerifier(authority: authority)
        let alpha = try executableItem(
            identifier: "plugin.alpha",
            displayName: "Alpha",
            automaticEligible: true,
            matchExtension: "txt",
            ruleIdentifier: "rule-alpha"
        )
        let beta = try executableItem(
            identifier: "plugin.beta",
            displayName: "Beta",
            automaticEligible: true,
            matchExtension: "txt",
            ruleIdentifier: "rule-beta"
        )
        let catalog = try PluginCatalog(
            items: [beta, alpha],
            authorizationVerifier: verifier
        )
        let authorizations = try Dictionary(
            uniqueKeysWithValues: [alpha, beta].map { item in
                (
                    item.id,
                    try verifier.issue(
                        for: item,
                        trust: .bundled,
                        approval: .automatic,
                        externalToolPolicy: externalPolicy,
                        expiresAt: expiryDate
                    )
                )
            }
        )
        let unordered = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [alpha.id, beta.id],
            automaticPluginIdentifiers: [alpha.id, beta.id]
        )

        XCTAssertEqual(
            try catalog.eligibleItems(
                matching: PluginCatalogFilter(fileExtension: "TXT"),
                mode: .automatic,
                authorizations: authorizations,
                preferences: unordered,
                externalToolPolicy: externalPolicy
            ).map(\.id),
            [alpha.id, beta.id]
        )
        assertAmbiguous(
            try catalog.select(
                mode: .automatic,
                authorizations: authorizations,
                preferences: unordered,
                externalToolPolicy: externalPolicy
            ),
            identifiers: [alpha.id, beta.id]
        )

        let preferred = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [alpha.id, beta.id],
            automaticPluginIdentifiers: [alpha.id, beta.id],
            preferredAutomaticPluginIdentifiers: [beta.id]
        )
        assertSelected(
            try catalog.select(
                mode: .automatic,
                authorizations: authorizations,
                preferences: preferred,
                externalToolPolicy: externalPolicy
            ),
            identifier: beta.id
        )
        assertSelected(
            try catalog.select(
                matching: PluginCatalogFilter(identifier: alpha.id),
                mode: .automatic,
                authorizations: authorizations,
                preferences: unordered,
                externalToolPolicy: externalPolicy
            ),
            identifier: alpha.id
        )
        assertNoMatch(
            try catalog.select(
                matching: PluginCatalogFilter(fileExtension: "csv"),
                mode: .automatic,
                authorizations: authorizations,
                preferences: unordered,
                externalToolPolicy: externalPolicy
            )
        )
    }

    func testAuthorizationRequiresCurrentOpaqueAuthorityAndFiniteFutureExpiry() throws {
        let fixture = try makeExternalFixture()
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let item = try executableItem(automaticEligible: true)
        let authority = MutableAuthorityState(now: referenceDate, generation: 41)
        let verifier = try authorizationVerifier(authority: authority)

        assertCatalogError(.invalidAuthorizationVerifierKey) {
            try PluginAuthorizationVerifier(
                authenticationKey: Data(repeating: 0x11, count: 31),
                authorityDomainIdentifier: authorityDomain(),
                authorityStateProvider: authority
            )
        }
        for invalidExpiry in [
            referenceDate.addingTimeInterval(-1),
            referenceDate,
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: .nan)
        ] {
            assertCatalogError(.invalidAuthorizationExpiry) {
                try verifier.issue(
                    for: item,
                    trust: .bundled,
                    approval: .automatic,
                    externalToolPolicy: policy,
                    expiresAt: invalidExpiry
                )
            }
        }

        authority.set(now: Date(timeIntervalSinceReferenceDate: .nan), generation: 41)
        assertCatalogError(.invalidAuthorizationAuthorityState) {
            try verifier.issue(
                for: item,
                trust: .bundled,
                approval: .automatic,
                externalToolPolicy: policy,
                expiresAt: expiryDate
            )
        }
        authority.set(now: referenceDate, generation: 41)
        let authorization = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .automatic,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )
        let catalog = try PluginCatalog(items: [item], authorizationVerifier: verifier)
        let preferences = try enabledPreferences(for: item, in: catalog, automatic: true)

        XCTAssertEqual(authority.readCount, 6)
        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .automatic,
                authorization: authorization,
                preferences: preferences,
                policy: policy
            ).reason,
            .eligible
        )
        XCTAssertEqual(authority.readCount, 7)

        authority.set(now: Date(timeIntervalSinceReferenceDate: .infinity), generation: 41)
        assertCatalogError(.invalidAuthorizationAuthorityState) {
            try catalog.decision(
                for: item.id,
                mode: .automatic,
                authorization: authorization,
                preferences: preferences,
                externalToolPolicy: policy
            )
        }
    }

    func testAuthorizationRejectsReplayForgeryRevocationAndExpiry() throws {
        let fixture = try makeExternalFixture()
        let policy = try ExternalToolPolicy(
            externalExecutableRules: [
                makeRule(fixture, identifier: "reviewed-rule"),
                makeRule(
                    fixture,
                    identifier: "other-rule",
                    executableURL: fixture.alternateExecutableURL
                )
            ]
        )
        let item = try executableItem(automaticEligible: true)
        let otherItem = try executableItem(
            identifier: "plugin.other",
            displayName: "Other",
            ruleIdentifier: "other-rule"
        )
        let authority = MutableAuthorityState(now: referenceDate, generation: 9)
        let verifier = try authorizationVerifier(authority: authority, keyByte: 0x22)
        let catalog = try PluginCatalog(
            items: [item, otherItem],
            authorizationVerifier: verifier
        )
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [item.id, otherItem.id]
        )
        let authorization = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .manual,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )

        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: otherItem,
                mode: .manual,
                authorization: authorization,
                preferences: preferences,
                policy: policy
            ).reason,
            .authorizationInvalid
        )

        let foreignVerifier = try authorizationVerifier(authority: authority, keyByte: 0x23)
        let forged = try foreignVerifier.issue(
            for: item,
            trust: .bundled,
            approval: .manual,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )
        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: forged,
                preferences: preferences,
                policy: policy
            ).reason,
            .authorizationInvalid
        )

        authority.set(now: referenceDate, generation: 10)
        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: authorization,
                preferences: preferences,
                policy: policy
            ).reason,
            .authorizationInvalid
        )

        authority.set(now: expiryDate, generation: 9)
        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: authorization,
                preferences: preferences,
                policy: policy
            ).reason,
            .authorizationInvalid
        )
    }

    func testAuthorizationBindsEveryCatalogMetadataField() throws {
        let fixture = try makeExternalFixture()
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let authority = MutableAuthorityState(now: referenceDate, generation: 3)
        let verifier = try authorizationVerifier(authority: authority)
        let baseline = try executableItem()
        let authorization = try verifier.issue(
            for: baseline,
            trust: .bundled,
            approval: .manual,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )
        let mutations = try [
            executableItem(identifier: "plugin.changed"),
            executableItem(displayName: "Changed display name"),
            executableItem(summary: "Changed summary"),
            executableItem(version: "2"),
            executableItem(manualEligible: false, automaticEligible: true),
            executableItem(automaticEligible: true),
            executableItem(matchExtension: "csv")
        ]

        for mutation in mutations {
            let catalog = try PluginCatalog(items: [mutation], authorizationVerifier: verifier)
            let preferences = try enabledPreferences(
                for: mutation,
                in: catalog,
                automatic: !mutation.manualEligible
            )
            let outcome = try decision(
                catalog: catalog,
                item: mutation,
                mode: mutation.manualEligible ? .manual : .automatic,
                authorization: authorization,
                preferences: preferences,
                policy: policy
            )
            XCTAssertEqual(outcome.reason, .authorizationInvalid, mutation.description)
        }

        let setting = try PluginSettingSchema(
            key: "mode",
            title: "Mode",
            constraint: .boolean,
            defaultValue: .boolean(false)
        )
        let withSetting = try executableItem(settings: [setting])
        let settingPolicy = try privacyPolicy(
            for: withSetting,
            classifications: ["mode": .nonSecret]
        )
        let settingCatalog = try PluginCatalog(
            items: [withSetting],
            settingPrivacyPolicy: settingPolicy,
            authorizationVerifier: verifier
        )
        let settingPreferences = try enabledPreferences(for: withSetting, in: settingCatalog)
        XCTAssertEqual(
            try decision(
                catalog: settingCatalog,
                item: withSetting,
                mode: .manual,
                authorization: authorization,
                preferences: settingPreferences,
                policy: policy
            ).reason,
            .authorizationInvalid
        )
    }

    func testAuthorizationBindsFullExternalExecutableRule() throws {
        let fixture = try makeExternalFixture()
        let baselineRule = makeRule(fixture)
        let baselinePolicy = try ExternalToolPolicy(externalExecutableRules: [baselineRule])
        let item = try executableItem(automaticEligible: true)
        let authority = MutableAuthorityState(now: referenceDate, generation: 5)
        let verifier = try authorizationVerifier(authority: authority)
        let authorization = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .automatic,
            externalToolPolicy: baselinePolicy,
            expiresAt: expiryDate
        )
        let catalog = try PluginCatalog(items: [item], authorizationVerifier: verifier)
        let preferences = try enabledPreferences(for: item, in: catalog, automatic: true)

        let ruleMutations: [(String, ExternalToolExecutableRule)] =
            [
                (
                    "executableURL",
                    makeRule(fixture, executableURL: fixture.alternateExecutableURL)
                ),
                (
                    "permittedWorkingDirectories",
                    makeRule(fixture, permittedWorkingDirectories: [tree(fixture.root)])
                ),
                (
                    "permittedReadScopes",
                    makeRule(fixture, permittedReadScopes: [exact(fixture.root)])
                ),
                (
                    "permittedWriteScopes",
                    makeRule(fixture, permittedWriteScopes: [exact(fixture.outputDirectory)])
                ),
                (
                    "allowedEnvironmentKeys",
                    makeRule(fixture, allowedEnvironmentKeys: ["SAFE", "TERM"])
                ),
                (
                    "argumentConstraints",
                    makeRule(fixture, argumentConstraints: [.oneOf(["safe", "fast"])])
                ),
                (
                    "networkIsolation",
                    makeRule(
                        fixture,
                        isolationPolicy: ExternalToolIsolationPolicy(network: .allowed)
                    )
                ),
                (
                    "childProcessIsolation",
                    makeRule(
                        fixture,
                        isolationPolicy: ExternalToolIsolationPolicy(childProcesses: .allowed)
                    )
                ),
                (
                    "IPCIsolation",
                    makeRule(
                        fixture,
                        isolationPolicy: ExternalToolIsolationPolicy(
                            interprocessCommunication: .allowed
                        )
                    )
                )
            ] + limitRuleMutations(fixture)

        for (field, mutatedRule) in ruleMutations {
            let mutatedPolicy = try ExternalToolPolicy(externalExecutableRules: [mutatedRule])
            XCTAssertEqual(
                try decision(
                    catalog: catalog,
                    item: item,
                    mode: .automatic,
                    authorization: authorization,
                    preferences: preferences,
                    policy: mutatedPolicy
                ).reason,
                .authorizationInvalid,
                field
            )
        }
    }

    func testAuthorizationBindsReviewedExecutableDigestAndRoutingFields() throws {
        let fixture = try makeExternalFixture()
        let originalRule = makeRule(fixture)
        let originalPolicy = try ExternalToolPolicy(externalExecutableRules: [originalRule])
        let item = try executableItem()
        let authority = MutableAuthorityState(now: referenceDate, generation: 1)
        let verifier = try authorizationVerifier(authority: authority)
        let authorization = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .manual,
            externalToolPolicy: originalPolicy,
            expiresAt: expiryDate
        )
        let catalog = try PluginCatalog(items: [item], authorizationVerifier: verifier)
        let preferences = try enabledPreferences(for: item, in: catalog)

        let changedBytes = Data([0x7F, 0x4D, 0x55, 0x54, 0x41, 0x54, 0x45, 0x44, 0x21])
        XCTAssertEqual(changedBytes.count, fixture.executableData.count)
        try changedBytes.write(to: fixture.executableURL)
        try setPermissions(0o700, on: fixture.executableURL)
        let changedRule = makeRule(
            fixture,
            approvedExecutableSHA256: digest(changedBytes)
        )
        let changedPolicy = try ExternalToolPolicy(externalExecutableRules: [changedRule])
        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: authorization,
                preferences: preferences,
                policy: changedPolicy
            ).reason,
            .authorizationInvalid
        )

        let missingRuleItem = try executableItem(ruleIdentifier: "missing-rule")
        let missingCatalog = try PluginCatalog(
            items: [missingRuleItem],
            authorizationVerifier: verifier
        )
        let missingPreferences = try enabledPreferences(for: missingRuleItem, in: missingCatalog)
        XCTAssertEqual(
            try decision(
                catalog: missingCatalog,
                item: missingRuleItem,
                mode: .manual,
                authorization: authorization,
                preferences: missingPreferences,
                policy: changedPolicy
            ).reason,
            .externalToolRuleNotConfigured
        )

        let mismatchRule = makeRule(
            fixture,
            capability: .prediffer,
            approvedExecutableSHA256: digest(changedBytes)
        )
        let mismatchPolicy = try ExternalToolPolicy(externalExecutableRules: [mismatchRule])
        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: authorization,
                preferences: preferences,
                policy: mismatchPolicy
            ).reason,
            .externalToolPolicy(.explicitExternalExecutableRuleRequired)
        )
    }

    func testAuthorizationTrustAndApprovalRemainActionSpecific() throws {
        let fixture = try makeExternalFixture()
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let item = try executableItem(automaticEligible: true)
        let authority = MutableAuthorityState(now: referenceDate, generation: 1)
        let verifier = try authorizationVerifier(authority: authority)
        let catalog = try PluginCatalog(items: [item], authorizationVerifier: verifier)
        let manualPreferences = try enabledPreferences(for: item, in: catalog)
        let automaticPreferences = try enabledPreferences(for: item, in: catalog, automatic: true)

        for trust in PluginTrustState.allCases {
            let authorization = try verifier.issue(
                for: item,
                trust: trust,
                approval: .automatic,
                externalToolPolicy: policy,
                expiresAt: expiryDate
            )
            let manual = try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: authorization,
                preferences: manualPreferences,
                policy: policy
            )
            let automatic = try decision(
                catalog: catalog,
                item: item,
                mode: .automatic,
                authorization: authorization,
                preferences: automaticPreferences,
                policy: policy
            )
            switch trust {
            case .bundled, .trustedPublisher:
                XCTAssertTrue(manual.isEligible, trust.rawValue)
                XCTAssertTrue(automatic.isEligible, trust.rawValue)
            case .localDevelopment:
                XCTAssertTrue(manual.isEligible)
                XCTAssertEqual(automatic.reason, .trustDoesNotPermitAutomaticUse)
            case .untrusted, .revoked, .invalid:
                XCTAssertEqual(manual.reason, .trustDoesNotPermitManualUse)
                XCTAssertEqual(automatic.reason, .trustDoesNotPermitAutomaticUse)
            }
        }

        let manualOnly = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .manual,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )
        XCTAssertTrue(
            try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: manualOnly,
                preferences: manualPreferences,
                policy: policy
            ).isEligible
        )
        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .automatic,
                authorization: manualOnly,
                preferences: automaticPreferences,
                policy: policy
            ).reason,
            .automaticApprovalRequired
        )

        let denied = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .notApproved,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )
        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: denied,
                preferences: manualPreferences,
                policy: policy
            ).reason,
            .manualApprovalRequired
        )
    }

    func testPrivacyClassificationsAreExternallyMintedAndMetadataBound() throws {
        let secret = try PluginSettingSchema(
            key: "token",
            title: "Token",
            constraint: .string(maximumUTF8Bytes: 256)
        )
        let item = try PluginCatalogItem(
            id: PluginIdentifier("plugin.privacy"),
            displayName: "Privacy",
            version: "1",
            capability: .transform,
            settings: [secret]
        )
        let identity = try item.settingIdentity(forKey: "token")
        let policy = try PluginSettingPrivacyPolicy(classifications: [identity: .secret])
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)

        XCTAssertEqual(try catalog.settingPrivacy(for: item.id, key: "token"), .secret)
        XCTAssertNil(try catalog.settingPrivacy(for: item.id, key: "missing"))
        XCTAssertNil(
            try catalog.settingPrivacy(
                for: PluginIdentifier("plugin.missing"),
                key: "token"
            )
        )
        assertCatalogError(.preferenceReferencesUnknownSetting) {
            try item.settingIdentity(forKey: "raw-plugin-authored-key")
        }

        let changedSetting = try PluginSettingSchema(
            key: "token",
            title: "Changed externally reviewed title",
            constraint: .string(maximumUTF8Bytes: 256)
        )
        let changedItem = try PluginCatalogItem(
            id: item.id,
            displayName: item.displayName,
            version: item.version,
            capability: item.capability,
            settings: [changedSetting]
        )
        assertCatalogError(.missingTrustedSettingClassification) {
            try PluginCatalog(items: [changedItem], settingPrivacyPolicy: policy)
        }
        assertCatalogError(.unexpectedTrustedSettingClassification) {
            try PluginCatalog(settingPrivacyPolicy: policy)
        }
        assertCatalogError(.missingTrustedSettingClassification) {
            try PluginCatalog(items: [item])
        }
    }

    func testPrivacyClassificationPropagatesCancellation() async throws {
        let item = try mixedSettingsItem()
        let policy = try mixedPrivacyPolicy(for: item)
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)

        let queryCancelled = await Task.detached { @Sendable [catalog, identifier = item.id] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try catalog.settingPrivacy(for: identifier, key: "token")
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(queryCancelled)

        let constructionCancelled = await Task.detached { @Sendable [item, policy] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(constructionCancelled)
    }

    func testSecretDefaultsMissingNonSecretDefaultsAndSecretPersistenceAreRejected() throws {
        let secretWithDefault = try PluginSettingSchema(
            key: "token",
            title: "Token",
            constraint: .string(maximumUTF8Bytes: 256),
            defaultValue: .string("must-not-be-metadata")
        )
        let secretDefaultItem = try PluginCatalogItem(
            id: PluginIdentifier("plugin.secret-default"),
            displayName: "Secret Default",
            version: "1",
            capability: .transform,
            settings: [secretWithDefault]
        )
        let secretDefaultPolicy = try privacyPolicy(
            for: secretDefaultItem,
            classifications: ["token": .secret]
        )
        assertCatalogError(.secretSettingCannotHaveDefaultValue) {
            try PluginCatalog(
                items: [secretDefaultItem],
                settingPrivacyPolicy: secretDefaultPolicy
            )
        }

        let missingDefault = try PluginSettingSchema(
            key: "profile",
            title: "Profile",
            constraint: .string(maximumUTF8Bytes: 256)
        )
        let missingDefaultItem = try PluginCatalogItem(
            id: PluginIdentifier("plugin.missing-default"),
            displayName: "Missing Default",
            version: "1",
            capability: .transform,
            settings: [missingDefault]
        )
        let missingDefaultPolicy = try privacyPolicy(
            for: missingDefaultItem,
            classifications: ["profile": .nonSecret]
        )
        assertCatalogError(.nonSecretSettingRequiresDefaultValue) {
            try PluginCatalog(
                items: [missingDefaultItem],
                settingPrivacyPolicy: missingDefaultPolicy
            )
        }

        let secret = try PluginSettingSchema(
            key: "token",
            title: "Token",
            constraint: .string(maximumUTF8Bytes: 256)
        )
        let item = try PluginCatalogItem(
            id: PluginIdentifier("plugin.secret"),
            displayName: "Secret",
            version: "1",
            capability: .transform,
            settings: [secret]
        )
        let policy = try privacyPolicy(for: item, classifications: ["token": .secret])
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)
        assertCatalogError(.secretSettingCannotBePersisted) {
            try PluginCatalogPreferences(
                catalog: catalog,
                settingValues: [item.id: ["token": .string("plaintext-secret")]]
            )
        }
        assertCatalogError(.secretSettingRequiresKeychainCapability) {
            try catalog.resolvedSettings(
                for: item.id,
                preferences: PluginCatalogPreferences(catalog: catalog)
            )
        }
    }

    func testKeychainCapabilityValidatesMintingInputsAndFiniteAuthority() throws {
        let resolver = RecordingKeychainResolver()
        let authorityState = MutableAuthorityState(now: referenceDate, generation: 17)
        let authority = try keychainAuthority(
            resolver: resolver,
            authority: authorityState
        )
        let item = try keychainItem()
        let identity = try item.settingIdentity(forKey: "secret-a")
        let operation = try PluginSettingKeychainOperation(identifier: "resolve.v1")

        assertCatalogError(.invalidKeychainAuthorityKey) {
            try PluginSettingKeychainAuthority(
                authenticationKey: Data(repeating: 0x44, count: 31),
                authorityDomainIdentifier: authorityDomain(),
                resolver: resolver,
                authorityStateProvider: authorityState
            )
        }
        for invalidOperation in ["", "contains space", String(repeating: "a", count: 257)] {
            assertCatalogError(.invalidKeychainOperation) {
                try PluginSettingKeychainOperation(identifier: invalidOperation)
            }
        }
        for invalidReference in [
            Data(),
            Data(
                repeating: 0xAA,
                count: PluginSettingKeychainCapability.maximumPersistentReferenceBytes + 1
            )
        ] {
            assertCatalogError(.invalidKeychainPersistentReference) {
                try authority.issue(
                    for: identity,
                    operation: operation,
                    keychainPersistentReference: invalidReference,
                    expiresAt: expiryDate
                )
            }
        }
        for invalidExpiry in [
            referenceDate,
            referenceDate.addingTimeInterval(-1),
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity)
        ] {
            assertCatalogError(.invalidKeychainCapabilityExpiry) {
                try authority.issue(
                    for: identity,
                    operation: operation,
                    keychainPersistentReference: Data("reference".utf8),
                    expiresAt: invalidExpiry
                )
            }
        }

        authorityState.set(now: Date(timeIntervalSinceReferenceDate: .nan), generation: 17)
        assertCatalogError(.invalidKeychainAuthorityState) {
            try authority.issue(
                for: identity,
                operation: operation,
                keychainPersistentReference: Data("reference".utf8),
                expiresAt: expiryDate
            )
        }
    }

    func testKeychainCapabilityBindsIdentityReferenceOperationGenerationAndExpiry() throws {
        let events = SecurityEventLog()
        let resolver = RecordingKeychainResolver(events: events)
        let authorityState = MutableAuthorityState(
            now: referenceDate,
            generation: 71,
            events: events
        )
        let authority = try keychainAuthority(
            resolver: resolver,
            authority: authorityState
        )
        let item = try keychainItem()
        let policy = try privacyPolicy(
            for: item,
            classifications: [
                "public": .nonSecret,
                "secret-a": .secret,
                "secret-b": .secret
            ]
        )
        let catalog = try PluginCatalog(
            items: [item],
            settingPrivacyPolicy: policy,
            keychainAuthority: authority
        )
        let preferences = try PluginCatalogPreferences(catalog: catalog)
        let identityA = try item.settingIdentity(forKey: "secret-a")
        let operationA = try PluginSettingKeychainOperation(identifier: "resolve-a")
        let operationB = try PluginSettingKeychainOperation(identifier: "resolve-b")
        let referenceA = Data("KEYCHAIN-REFERENCE-A".utf8)
        let referenceB = Data("KEYCHAIN-REFERENCE-B".utf8)
        let capabilityA = try authority.issue(
            for: identityA,
            operation: operationA,
            keychainPersistentReference: referenceA,
            expiresAt: expiryDate
        )
        let capabilityB = try authority.issue(
            for: identityA,
            operation: operationB,
            keychainPersistentReference: referenceB,
            expiresAt: expiryDate.addingTimeInterval(1)
        )
        XCTAssertNotEqual(capabilityA, capabilityB)

        let resolved = try catalog.resolvedSettings(
            for: item.id,
            preferences: preferences,
            keychainCapabilities: [
                "secret-a": capabilityA,
                "secret-b": try authority.issue(
                    for: item.settingIdentity(forKey: "secret-b"),
                    operation: operationA,
                    keychainPersistentReference: referenceA,
                    expiresAt: expiryDate
                )
            ]
        )
        XCTAssertEqual(resolved["public"], .nonSecret(.boolean(false)))
        XCTAssertEqual(resolved["secret-a"], .secret(capabilityA))

        events.clear()
        try catalog.performSecretSettingOperation(
            for: item.id,
            key: "secret-a",
            capability: capabilityA
        )
        XCTAssertEqual(events.values, ["authority", "resolver"])
        XCTAssertEqual(
            resolver.calls,
            [KeychainCall(operation: "resolve-a", persistentReference: referenceA)]
        )

        assertCatalogError(.invalidKeychainCapability) {
            try catalog.performSecretSettingOperation(
                for: item.id,
                key: "secret-b",
                capability: capabilityA
            )
        }

        resolver.reset()
        events.clear()
        authorityState.set(now: referenceDate, generation: 72)
        assertCatalogError(.invalidKeychainCapability) {
            try catalog.performSecretSettingOperation(
                for: item.id,
                key: "secret-a",
                capability: capabilityA
            )
        }
        XCTAssertEqual(events.values, ["authority"])
        XCTAssertTrue(resolver.calls.isEmpty)

        authorityState.set(now: expiryDate, generation: 71)
        events.clear()
        assertCatalogError(.invalidKeychainCapability) {
            try catalog.performSecretSettingOperation(
                for: item.id,
                key: "secret-a",
                capability: capabilityA
            )
        }
        XCTAssertEqual(events.values, ["authority"])
        XCTAssertTrue(resolver.calls.isEmpty)
    }

    func testKeychainGrantForgeryLeakAndRevocationFailBeforeResolver() throws {
        let resolver = RecordingKeychainResolver()
        let authorityState = MutableAuthorityState(now: referenceDate, generation: 4)
        let trustedAuthority = try keychainAuthority(
            resolver: resolver,
            authority: authorityState,
            keyByte: 0x51
        )
        let foreignAuthority = try keychainAuthority(
            resolver: resolver,
            authority: authorityState,
            keyByte: 0x52
        )
        let item = try keychainItem()
        let policy = try privacyPolicy(
            for: item,
            classifications: [
                "public": .nonSecret,
                "secret-a": .secret,
                "secret-b": .secret
            ]
        )
        let catalog = try PluginCatalog(
            items: [item],
            settingPrivacyPolicy: policy,
            keychainAuthority: trustedAuthority
        )
        let identity = try item.settingIdentity(forKey: "secret-a")
        let operation = try PluginSettingKeychainOperation(identifier: "resolve")
        let forged = try foreignAuthority.issue(
            for: identity,
            operation: operation,
            keychainPersistentReference: Data("foreign-reference".utf8),
            expiresAt: expiryDate
        )
        assertCatalogError(.invalidKeychainCapability) {
            try catalog.performSecretSettingOperation(
                for: item.id,
                key: "secret-a",
                capability: forged
            )
        }
        XCTAssertTrue(resolver.calls.isEmpty)

        let valid = try trustedAuthority.issue(
            for: identity,
            operation: operation,
            keychainPersistentReference: Data("leaked-reference".utf8),
            expiresAt: expiryDate
        )
        let changedItem = try keychainItem(version: "2")
        let changedPolicy = try privacyPolicy(
            for: changedItem,
            classifications: [
                "public": .nonSecret,
                "secret-a": .secret,
                "secret-b": .secret
            ]
        )
        let changedCatalog = try PluginCatalog(
            items: [changedItem],
            settingPrivacyPolicy: changedPolicy,
            keychainAuthority: trustedAuthority
        )
        assertCatalogError(.invalidKeychainCapability) {
            try changedCatalog.performSecretSettingOperation(
                for: changedItem.id,
                key: "secret-a",
                capability: valid
            )
        }
        XCTAssertTrue(resolver.calls.isEmpty)

        authorityState.set(now: referenceDate, generation: 5)
        assertCatalogError(.secretSettingRequiresKeychainCapability) {
            try catalog.resolvedSettings(
                for: item.id,
                preferences: PluginCatalogPreferences(catalog: catalog),
                keychainCapabilities: ["secret-a": valid]
            )
        }
        XCTAssertTrue(resolver.calls.isEmpty)
    }

    func testKeychainAuthorityChecksCurrentStateImmediatelyBeforeResolverAndMapsFailures() throws {
        let events = SecurityEventLog()
        let resolver = RecordingKeychainResolver(events: events)
        let authorityState = MutableAuthorityState(
            now: referenceDate,
            generation: 8,
            events: events
        )
        let authority = try keychainAuthority(
            resolver: resolver,
            authority: authorityState
        )
        let item = try keychainItem()
        let policy = try privacyPolicy(
            for: item,
            classifications: [
                "public": .nonSecret,
                "secret-a": .secret,
                "secret-b": .secret
            ]
        )
        let catalog = try PluginCatalog(
            items: [item],
            settingPrivacyPolicy: policy,
            keychainAuthority: authority
        )
        let capability = try authority.issue(
            for: item.settingIdentity(forKey: "secret-a"),
            operation: PluginSettingKeychainOperation(identifier: "resolve"),
            keychainPersistentReference: Data("opaque-reference".utf8),
            expiresAt: expiryDate
        )

        events.clear()
        try catalog.performSecretSettingOperation(
            for: item.id,
            key: "secret-a",
            capability: capability
        )
        XCTAssertEqual(events.values, ["authority", "resolver"])

        resolver.reset(mode: .failure)
        assertCatalogError(.keychainOperationFailed) {
            try catalog.performSecretSettingOperation(
                for: item.id,
                key: "secret-a",
                capability: capability
            )
        }

        resolver.reset(mode: .cancellation)
        XCTAssertThrowsError(
            try catalog.performSecretSettingOperation(
                for: item.id,
                key: "secret-a",
                capability: capability
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }

        resolver.reset()
        authorityState.set(now: Date(timeIntervalSinceReferenceDate: .infinity), generation: 8)
        assertCatalogError(.invalidKeychainAuthorityState) {
            try catalog.performSecretSettingOperation(
                for: item.id,
                key: "secret-a",
                capability: capability
            )
        }
        XCTAssertTrue(resolver.calls.isEmpty)
    }

    func testOpaqueSecurityValuesAndPreferencesRedactSensitiveMaterial() throws {
        let externalFixture = try makeExternalFixture()
        let externalPolicy = try ExternalToolPolicy(
            externalExecutableRules: [makeRule(externalFixture)]
        )
        let authorizationState = MutableAuthorityState(now: referenceDate, generation: 1)
        let verifier = try authorizationVerifier(authority: authorizationState, keyByte: 0x61)
        let executable = try executableItem()
        let authorization = try verifier.issue(
            for: executable,
            trust: .bundled,
            approval: .manual,
            externalToolPolicy: externalPolicy,
            expiresAt: expiryDate
        )
        let settingsItem = try mixedSettingsItem()
        let privacy = try mixedPrivacyPolicy(for: settingsItem)
        let preferencesCatalog = try PluginCatalog(
            items: [settingsItem],
            settingPrivacyPolicy: privacy
        )
        let secretValue = "PLAINTEXT-SETTING-VALUE"
        let preferences = try PluginCatalogPreferences(
            catalog: preferencesCatalog,
            settingValues: [settingsItem.id: ["profile": .string(secretValue)]]
        )
        let resolver = RecordingKeychainResolver()
        let keychainState = MutableAuthorityState(now: referenceDate, generation: 1)
        let keychainAuthority = try self.keychainAuthority(
            resolver: resolver,
            authority: keychainState,
            keyByte: 0x62
        )
        let keychainCatalogItem = try keychainItem()
        let keychainCapability = try keychainAuthority.issue(
            for: keychainCatalogItem.settingIdentity(forKey: "secret-a"),
            operation: PluginSettingKeychainOperation(identifier: "resolve"),
            keychainPersistentReference: Data("RAW-PERSISTENT-REFERENCE".utf8),
            expiresAt: expiryDate
        )

        let redactedValues: [Any] = [
            PluginSettingValue.string(secretValue),
            try settingsItem.settingIdentity(forKey: "profile"),
            privacy,
            preferences,
            authorization,
            verifier,
            keychainCapability,
            keychainAuthority,
            PluginResolvedSettingValue.secret(keychainCapability)
        ]
        let forbiddenData = [
            Data(repeating: 0x61, count: 32),
            Data(repeating: 0x62, count: 32),
            authorization.authorityDomainIdentifier,
            authorization.authenticationCode,
            keychainCapability.authorityDomainIdentifier,
            keychainCapability.persistentReference,
            keychainCapability.authenticationCode
        ]
        for value in redactedValues {
            let output = diagnostics(value)
            XCTAssertFalse(output.contains(secretValue), output)
            XCTAssertFalse(output.contains("RAW-PERSISTENT-REFERENCE"), output)
            XCTAssertFalse(output.contains(Data(repeating: 0x61, count: 32).base64EncodedString()))
            XCTAssertFalse(output.contains(Data(repeating: 0x62, count: 32).base64EncodedString()))
            XCTAssertTrue(Set(mirroredData(in: value)).isDisjoint(with: forbiddenData))
        }

        let encoded = try preferences.encodedData(for: preferencesCatalog)
        XCTAssertTrue(encoded.contains(Data(secretValue.utf8)))
        XCTAssertFalse(encoded.contains(Data("RAW-PERSISTENT-REFERENCE".utf8)))
        XCTAssertFalse(encoded.contains(Data("token".utf8)))
    }

    func testCanonicalSchemaOneRoundTripsWithExactStableBytes() throws {
        XCTAssertEqual(PluginCatalogPreferences.currentSchemaVersion, 1)
        let emptyCatalog = try PluginCatalog()
        let empty = try PluginCatalogPreferences(catalog: emptyCatalog)
        let expectedEmpty = Data(
            "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":1,\"settings\":[]}"
                .utf8
        )
        XCTAssertEqual(try empty.encodedData(for: emptyCatalog), expectedEmpty)
        XCTAssertEqual(
            try PluginCatalogPreferences.decode(from: expectedEmpty, for: emptyCatalog),
            empty
        )

        let item = try mixedSettingsItem()
        let policy = try mixedPrivacyPolicy(for: item)
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [item.id],
            automaticPluginIdentifiers: [item.id],
            preferredAutomaticPluginIdentifiers: [item.id],
            settingValues: [
                item.id: [
                    "profile": .string("reviewed"),
                    "enabled": .boolean(true),
                    "retries": .integer(4),
                    "mode": .choice("fast")
                ]
            ]
        )
        let data = try preferences.encodedData(for: catalog)
        XCTAssertEqual(try PluginCatalogPreferences.decode(from: data, for: catalog), preferences)
        XCTAssertEqual(try preferences.encodedData(for: catalog), data)
        XCTAssertFalse(data.contains(Data("token".utf8)))
    }

    func testPersistenceRejectsUnknownMissingDuplicateMalformedAndNoncanonicalJSON() throws {
        let first = try PluginCatalogItem(
            id: PluginIdentifier("plugin.a"),
            displayName: "A",
            version: "1",
            capability: .transform
        )
        let second = try PluginCatalogItem(
            id: PluginIdentifier("plugin.b"),
            displayName: "B",
            version: "1",
            capability: .transform
        )
        let catalog = try PluginCatalog(items: [first, second])
        let canonical = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [first.id, second.id]
        ).encodedData(for: catalog)

        let cases: [(PluginCatalogError, String)] = [
            (
                .unknownPersistenceKey,
                "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":1,\"settings\":[],\"unknown\":true}"
            ),
            (
                .unknownPersistenceKey,
                "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":1}"
            ),
            (
                .duplicatePersistenceKey,
                "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":1,\"schemaVersion\":1,\"settings\":[]}"
            ),
            (
                .duplicatePersistenceKey,
                "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[\"plugin.a\",\"plugin.a\"],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":1,\"settings\":[]}"
            ),
            (
                .unsupportedSchemaVersion(2),
                "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":2,\"settings\":[]}"
            ),
            (
                .malformedPersistence,
                "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":01,\"settings\":[]}"
            )
        ]
        for (expected, json) in cases {
            assertCatalogError(expected, context: json) {
                try PluginCatalogPreferences.decode(from: Data(json.utf8), for: catalog)
            }
        }

        assertCatalogError(.nonCanonicalPersistence) {
            try PluginCatalogPreferences.decode(
                from: Data([0x20]) + canonical,
                for: catalog
            )
        }
        let reversedIdentifiers = String(decoding: canonical, as: UTF8.self)
            .replacingOccurrences(
                of: "[\"plugin.a\",\"plugin.b\"]",
                with: "[\"plugin.b\",\"plugin.a\"]"
            )
        assertCatalogError(.nonCanonicalPersistence) {
            try PluginCatalogPreferences.decode(
                from: Data(reversedIdentifiers.utf8),
                for: catalog
            )
        }
    }

    func testPersistenceRejectsNestedDuplicateAndWrongValueShapes() throws {
        let setting = try PluginSettingSchema(
            key: "enabled",
            title: "Enabled",
            constraint: .boolean,
            defaultValue: .boolean(false)
        )
        let item = try PluginCatalogItem(
            id: PluginIdentifier("plugin.settings"),
            displayName: "Settings",
            version: "1",
            capability: .transform,
            settings: [setting]
        )
        let policy = try privacyPolicy(
            for: item,
            classifications: ["enabled": .nonSecret]
        )
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)
        let prefix =
            "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":1,\"settings\":"
        let suffix = "}"
        let cases: [(PluginCatalogError, String)] = [
            (
                .duplicatePersistenceKey,
                prefix
                    + "[{\"pluginIdentifier\":\"plugin.settings\",\"values\":[]},{\"pluginIdentifier\":\"plugin.settings\",\"values\":[]}]"
                    + suffix
            ),
            (
                .duplicatePersistenceKey,
                prefix
                    + "[{\"pluginIdentifier\":\"plugin.settings\",\"values\":[{\"booleanValue\":true,\"key\":\"enabled\",\"kind\":\"boolean\"},{\"booleanValue\":false,\"key\":\"enabled\",\"kind\":\"boolean\"}]}]"
                    + suffix
            ),
            (
                .unknownPersistenceKey,
                prefix
                    + "[{\"pluginIdentifier\":\"plugin.settings\",\"values\":[{\"booleanValue\":true,\"key\":\"enabled\",\"kind\":\"boolean\",\"stringValue\":\"forged\"}]}]"
                    + suffix
            ),
            (
                .malformedPersistence,
                prefix
                    + "[{\"pluginIdentifier\":\"plugin.settings\",\"values\":[{\"booleanValue\":null,\"key\":\"enabled\",\"kind\":\"boolean\"}]}]"
                    + suffix
            )
        ]

        for (expected, json) in cases {
            assertCatalogError(expected, context: json) {
                try PluginCatalogPreferences.decode(from: Data(json.utf8), for: catalog)
            }
        }
    }

    func testPersistenceEnforcesExactOneMiBInputAndBoundedOutput() throws {
        XCTAssertEqual(PluginCatalogLimits.hardMaximumPersistenceBytes, 1_048_576)
        XCTAssertEqual(PluginCatalogLimits.default.maximumPersistenceBytes, 1_048_576)
        let emptyCatalog = try PluginCatalog()
        let canonical = try PluginCatalogPreferences(catalog: emptyCatalog).encodedData(
            for: emptyCatalog
        )
        let exactMiB =
            canonical
            + Data(
                repeating: 0x20,
                count: PluginCatalogLimits.hardMaximumPersistenceBytes - canonical.count
            )
        XCTAssertEqual(exactMiB.count, PluginCatalogLimits.hardMaximumPersistenceBytes)
        assertCatalogError(.nonCanonicalPersistence) {
            try PluginCatalogPreferences.decode(from: exactMiB, for: emptyCatalog)
        }
        assertCatalogError(
            .persistenceDataTooLarge(
                maximumBytes: PluginCatalogLimits.hardMaximumPersistenceBytes
            )
        ) {
            try PluginCatalogPreferences.decode(
                from: exactMiB + Data([0x20]),
                for: emptyCatalog
            )
        }

        let setting = try PluginSettingSchema(
            key: "profile",
            title: "Profile",
            constraint: .string(maximumUTF8Bytes: 3_000),
            defaultValue: .string("")
        )
        let item = try PluginCatalogItem(
            id: PluginIdentifier("plugin.output"),
            displayName: "Output",
            version: "1",
            capability: .transform,
            settings: [setting]
        )
        let privacy = try privacyPolicy(
            for: item,
            classifications: ["profile": .nonSecret]
        )
        let baselineCatalog = try PluginCatalog(items: [item], settingPrivacyPolicy: privacy)
        let value = String(repeating: "x", count: 2_000)
        let baselinePreferences = try PluginCatalogPreferences(
            catalog: baselineCatalog,
            settingValues: [item.id: ["profile": .string(value)]]
        )
        let encoded = try baselinePreferences.encodedData(for: baselineCatalog)
        XCTAssertGreaterThan(encoded.count, 1_024)

        let exactLimits = try PluginCatalogLimits(maximumPersistenceBytes: encoded.count)
        let exactCatalog = try PluginCatalog(
            items: [item],
            settingPrivacyPolicy: privacy,
            limits: exactLimits
        )
        let exactPreferences = try PluginCatalogPreferences(
            catalog: exactCatalog,
            settingValues: [item.id: ["profile": .string(value)]]
        )
        XCTAssertEqual(try exactPreferences.encodedData(for: exactCatalog), encoded)

        let shortLimits = try PluginCatalogLimits(maximumPersistenceBytes: encoded.count - 1)
        let shortCatalog = try PluginCatalog(
            items: [item],
            settingPrivacyPolicy: privacy,
            limits: shortLimits
        )
        let shortPreferences = try PluginCatalogPreferences(
            catalog: shortCatalog,
            settingValues: [item.id: ["profile": .string(value)]]
        )
        assertCatalogError(.persistenceOutputTooLarge(maximumBytes: encoded.count - 1)) {
            try shortPreferences.encodedData(for: shortCatalog)
        }
    }

    func testJSONDepthValueAndWorkBudgetsFailClosed() throws {
        let depthLimits = try PluginCatalogLimits(maximumJSONDepth: 4)
        let depthCatalog = try PluginCatalog(limits: depthLimits)
        assertCatalogError(.jsonTooDeep(maximumDepth: 4)) {
            try PluginCatalogPreferences.decode(
                from: Data("[[[[[]]]]]".utf8),
                for: depthCatalog
            )
        }

        let valueLimits = try PluginCatalogLimits(maximumJSONValueCount: 32)
        let valueCatalog = try PluginCatalog(limits: valueLimits)
        let tooManyValues = "[" + Array(repeating: "null", count: 32).joined(separator: ",") + "]"
        assertCatalogError(.jsonValueLimitExceeded(maximumValues: 32)) {
            try PluginCatalogPreferences.decode(
                from: Data(tooManyValues.utf8),
                for: valueCatalog
            )
        }

        let workLimits = try PluginCatalogLimits(
            maximumPersistenceBytes: 1_024,
            maximumWork: 1_024
        )
        let workCatalog = try PluginCatalog(limits: workLimits)
        let canonical = try PluginCatalogPreferences(catalog: workCatalog).encodedData(
            for: workCatalog
        )
        let workExhaustion =
            canonical
            + Data(
                repeating: 0x20,
                count: workLimits.maximumPersistenceBytes - canonical.count
            )
        assertCatalogError(.workLimitExceeded(maximumWork: 1_024)) {
            try PluginCatalogPreferences.decode(from: workExhaustion, for: workCatalog)
        }
    }

    func testCatalogPersistenceAndSelectionHonorPreCancellation() async throws {
        let item = try mixedSettingsItem()
        let privacy = try mixedPrivacyPolicy(for: item)
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: privacy)
        let preferences = try PluginCatalogPreferences(catalog: catalog)
        let data = try preferences.encodedData(for: catalog)

        let encodeCancelled = await Task.detached { @Sendable [catalog, preferences] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try preferences.encodedData(for: catalog)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(encodeCancelled)

        let decodeCancelled = await Task.detached { @Sendable [catalog, data] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try PluginCatalogPreferences.decode(from: data, for: catalog)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(decodeCancelled)

        let selectionCancelled = await Task.detached { @Sendable [catalog, preferences] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try catalog.select(
                    mode: .manual,
                    authorizations: [:],
                    preferences: preferences
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(selectionCancelled)

        let decisionCancelled = await Task.detached { @Sendable [catalog, preferences] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try catalog.decision(
                    for: item.id,
                    mode: .manual,
                    authorization: nil,
                    preferences: preferences
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(decisionCancelled)
    }

    func testDeniedDecisionsAndSelectionsExposeExactState() throws {
        let fixture = try makeExternalFixture()
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let item = try executableItem(automaticEligible: true)
        let authority = MutableAuthorityState(now: referenceDate, generation: 1)
        let verifier = try authorizationVerifier(authority: authority)
        let authorization = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .automatic,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )
        let catalog = try PluginCatalog(items: [item], authorizationVerifier: verifier)
        let disabled = try PluginCatalogPreferences(catalog: catalog)
        let manual = try enabledPreferences(for: item, in: catalog)

        let cases:
            [(
                PluginInvocationMode,
                PluginAuthorization?,
                PluginCatalogPreferences,
                ExternalToolPolicy,
                PluginCatalogAvailabilityStatus,
                PluginCatalogEligibilityReason
            )] = [
                (.manual, authorization, disabled, policy, .disabled, .pluginNotEnabled),
                (.automatic, authorization, manual, policy, .disabled, .automaticUseNotEnabled),
                (.manual, nil, manual, policy, .disabled, .authorizationMissing),
                (
                    .manual,
                    authorization,
                    manual,
                    .default,
                    .disabled,
                    .externalToolPolicy(.explicitExternalExecutableRuleRequired)
                )
            ]
        for (mode, suppliedAuthorization, preferences, selectedPolicy, status, reason) in cases {
            let actual = try XCTUnwrap(
                catalog.decision(
                    for: item.id,
                    mode: mode,
                    authorization: suppliedAuthorization,
                    preferences: preferences,
                    externalToolPolicy: selectedPolicy
                )
            )
            XCTAssertEqual(
                actual,
                PluginCatalogEligibilityDecision(
                    identifier: item.id,
                    capability: item.capability,
                    mode: mode,
                    status: status,
                    reason: reason
                )
            )
            assertNoMatch(
                try catalog.select(
                    mode: mode,
                    authorizations: suppliedAuthorization.map { [item.id: $0] } ?? [:],
                    preferences: preferences,
                    externalToolPolicy: selectedPolicy
                )
            )
        }

        let verifierlessCatalog = try PluginCatalog(items: [item])
        let verifierlessPreferences = try enabledPreferences(for: item, in: verifierlessCatalog)
        XCTAssertEqual(
            try decision(
                catalog: verifierlessCatalog,
                item: item,
                mode: .manual,
                authorization: authorization,
                preferences: verifierlessPreferences,
                policy: policy
            ),
            PluginCatalogEligibilityDecision(
                identifier: item.id,
                capability: item.capability,
                mode: .manual,
                status: .disabled,
                reason: .authorizationInvalid
            )
        )
    }

    func testAuthorizationKeyDomainBoundariesAndIssueRejectionMatrix() throws {
        let authority = MutableAuthorityState(now: referenceDate, generation: 1)
        for count in [0, 31, 33] {
            assertCatalogError(.invalidAuthorizationVerifierKey, context: "key=\(count)") {
                try PluginAuthorizationVerifier(
                    authenticationKey: Data(repeating: 0x11, count: count),
                    authorityDomainIdentifier: authorityDomain(),
                    authorityStateProvider: authority
                )
            }
        }
        for count in [0, 31, 33] {
            assertCatalogError(
                .invalidAuthorizationAuthorityDomainIdentifier,
                context: "domain=\(count)"
            ) {
                try PluginAuthorizationVerifier(
                    authenticationKey: Data(
                        repeating: 0x11,
                        count: PluginAuthorizationVerifier.authenticationKeyByteCount
                    ),
                    authorityDomainIdentifier: Data(repeating: 0x22, count: count),
                    authorityStateProvider: authority
                )
            }
        }
        _ = try authorizationVerifier(authority: authority)

        let fixture = try makeExternalFixture()
        let verifier = try authorizationVerifier(authority: authority)
        let transform = try PluginCatalogItem(
            id: PluginIdentifier("plugin.transform"),
            displayName: "Transform",
            version: "1",
            capability: .transform
        )
        let missingRule = try executableItem(ruleIdentifier: "missing")
        let mismatchedPolicy = try ExternalToolPolicy(
            externalExecutableRules: [makeRule(fixture, capability: .prediffer)]
        )
        let cases: [(PluginCatalogItem, ExternalToolPolicy)] = [
            (transform, .default),
            (missingRule, try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])),
            (try executableItem(), mismatchedPolicy)
        ]
        for (item, policy) in cases {
            assertCatalogError(.authorizationSubjectUnavailable, context: item.id.rawValue) {
                try verifier.issue(
                    for: item,
                    trust: .bundled,
                    approval: .manual,
                    externalToolPolicy: policy,
                    expiresAt: expiryDate
                )
            }
        }
    }

    func testAuthorizationRejectsSameKeyAuthorityDomainReplay() throws {
        let fixture = try makeExternalFixture()
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let item = try executableItem()
        let authority = MutableAuthorityState(now: referenceDate, generation: 4)
        let trusted = try authorizationVerifier(authority: authority, keyByte: 0x77, domainByte: 0x10)
        let foreign = try authorizationVerifier(authority: authority, keyByte: 0x77, domainByte: 0x11)
        let replay = try foreign.issue(
            for: item,
            trust: .bundled,
            approval: .manual,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )
        let catalog = try PluginCatalog(items: [item], authorizationVerifier: trusted)
        let preferences = try enabledPreferences(for: item, in: catalog)

        XCTAssertEqual(
            try decision(
                catalog: catalog,
                item: item,
                mode: .manual,
                authorization: replay,
                preferences: preferences,
                policy: policy
            ).reason,
            .authorizationInvalid
        )
        XCTAssertNotEqual(trusted, foreign)
    }

    func testAuthorizationRejectsEachTamperedAuthenticatedField() throws {
        let fixture = try makeExternalFixture()
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let item = try executableItem()
        let authority = MutableAuthorityState(now: referenceDate, generation: 9)
        let verifier = try authorizationVerifier(authority: authority)
        let valid = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .manual,
            externalToolPolicy: policy,
            expiresAt: expiryDate
        )
        let catalog = try PluginCatalog(items: [item], authorizationVerifier: verifier)
        let preferences = try enabledPreferences(for: item, in: catalog)
        func copy(
            domain: Data? = nil,
            trust: PluginTrustState? = nil,
            approval: PluginApprovalState? = nil,
            generation: UInt64? = nil,
            expiresAt: Date? = nil,
            code: Data? = nil
        ) -> PluginAuthorization {
            PluginAuthorization(
                authorityDomainIdentifier: domain ?? valid.authorityDomainIdentifier,
                trust: trust ?? valid.trust,
                approval: approval ?? valid.approval,
                revocationGeneration: generation ?? valid.revocationGeneration,
                expiresAt: expiresAt ?? valid.expiresAt,
                authenticationCode: code ?? valid.authenticationCode
            )
        }
        let mutations: [(String, PluginAuthorization)] = [
            ("domain", copy(domain: authorityDomain(byte: 0xFF))),
            ("trust", copy(trust: .trustedPublisher)),
            ("approval", copy(approval: .automatic)),
            ("generation", copy(generation: valid.revocationGeneration + 1)),
            ("expiry", copy(expiresAt: valid.expiresAt.addingTimeInterval(1))),
            ("MAC", copy(code: Data(repeating: 0, count: valid.authenticationCode.count)))
        ]
        for (field, authorization) in mutations {
            XCTAssertEqual(
                try decision(
                    catalog: catalog,
                    item: item,
                    mode: .manual,
                    authorization: authorization,
                    preferences: preferences,
                    policy: policy
                ).reason,
                .authorizationInvalid,
                field
            )
        }
    }

    func testKeychainInputBoundariesAreExact() throws {
        let resolver = RecordingKeychainResolver()
        let state = MutableAuthorityState(now: referenceDate, generation: 1)
        for count in [0, 31, 33] {
            assertCatalogError(.invalidKeychainAuthorityKey, context: "key=\(count)") {
                try PluginSettingKeychainAuthority(
                    authenticationKey: Data(repeating: 0x44, count: count),
                    authorityDomainIdentifier: authorityDomain(),
                    resolver: resolver,
                    authorityStateProvider: state
                )
            }
        }
        for count in [0, 31, 33] {
            assertCatalogError(
                .invalidKeychainAuthorityDomainIdentifier,
                context: "domain=\(count)"
            ) {
                try PluginSettingKeychainAuthority(
                    authenticationKey: Data(
                        repeating: 0x44,
                        count: PluginSettingKeychainAuthority.authenticationKeyByteCount
                    ),
                    authorityDomainIdentifier: Data(repeating: 0x55, count: count),
                    resolver: resolver,
                    authorityStateProvider: state
                )
            }
        }
        for count in [1, PluginSettingKeychainOperation.maximumIdentifierUTF8Bytes] {
            XCTAssertNoThrow(
                try PluginSettingKeychainOperation(identifier: String(repeating: "a", count: count))
            )
        }
        let authority = try keychainAuthority(resolver: resolver, authority: state)
        let identity = try keychainItem().settingIdentity(forKey: "secret-a")
        let operation = try PluginSettingKeychainOperation(identifier: "resolve")
        for count in [1, PluginSettingKeychainCapability.maximumPersistentReferenceBytes] {
            XCTAssertNoThrow(
                try authority.issue(
                    for: identity,
                    operation: operation,
                    keychainPersistentReference: Data(repeating: 0xAA, count: count),
                    expiresAt: expiryDate
                )
            )
        }
    }

    func testKeychainResolutionMatrixHasExactResultsAndZeroResolverSideEffects() throws {
        let resolver = RecordingKeychainResolver()
        let state = MutableAuthorityState(now: referenceDate, generation: 1)
        let authority = try keychainAuthority(resolver: resolver, authority: state)
        let item = try keychainItem()
        let policy = try privacyPolicy(
            for: item,
            classifications: ["public": .nonSecret, "secret-a": .secret, "secret-b": .secret]
        )
        let catalog = try PluginCatalog(
            items: [item],
            settingPrivacyPolicy: policy,
            keychainAuthority: authority
        )
        let preferences = try PluginCatalogPreferences(catalog: catalog)
        let operation = try PluginSettingKeychainOperation(identifier: "resolve")
        let first = try authority.issue(
            for: item.settingIdentity(forKey: "secret-a"),
            operation: operation,
            keychainPersistentReference: Data("first".utf8),
            expiresAt: expiryDate
        )
        let second = try authority.issue(
            for: item.settingIdentity(forKey: "secret-b"),
            operation: operation,
            keychainPersistentReference: Data("second".utf8),
            expiresAt: expiryDate
        )

        XCTAssertEqual(
            try catalog.resolvedSettings(
                for: item.id,
                preferences: preferences,
                keychainCapabilities: ["secret-a": first, "secret-b": second]
            ),
            [
                "public": .nonSecret(.boolean(false)),
                "secret-a": .secret(first),
                "secret-b": .secret(second)
            ]
        )
        XCTAssertTrue(resolver.calls.isEmpty)

        let failureCases: [[String: PluginSettingKeychainCapability]] = [
            [:],
            ["secret-a": first],
            ["secret-a": first, "secret-b": first]
        ]
        for capabilities in failureCases {
            assertCatalogError(.secretSettingRequiresKeychainCapability) {
                try catalog.resolvedSettings(
                    for: item.id,
                    preferences: preferences,
                    keychainCapabilities: capabilities
                )
            }
            XCTAssertTrue(resolver.calls.isEmpty)
        }
    }

    func testKeychainRejectsTamperedFieldsAndSameKeyDomainReplayBeforeResolver() throws {
        let resolver = RecordingKeychainResolver()
        let state = MutableAuthorityState(now: referenceDate, generation: 3)
        let trusted = try keychainAuthority(
            resolver: resolver,
            authority: state,
            keyByte: 0x66,
            domainByte: 0x20
        )
        let foreign = try keychainAuthority(
            resolver: resolver,
            authority: state,
            keyByte: 0x66,
            domainByte: 0x21
        )
        let item = try keychainItem()
        let policy = try privacyPolicy(
            for: item,
            classifications: ["public": .nonSecret, "secret-a": .secret, "secret-b": .secret]
        )
        let catalog = try PluginCatalog(
            items: [item],
            settingPrivacyPolicy: policy,
            keychainAuthority: trusted
        )
        let identity = try item.settingIdentity(forKey: "secret-a")
        let operation = try PluginSettingKeychainOperation(identifier: "resolve")
        let valid = try trusted.issue(
            for: identity,
            operation: operation,
            keychainPersistentReference: Data("reference".utf8),
            expiresAt: expiryDate
        )
        func copy(
            domain: Data? = nil,
            settingIdentity: PluginSettingIdentity? = nil,
            operation: PluginSettingKeychainOperation? = nil,
            reference: Data? = nil,
            generation: UInt64? = nil,
            expiresAt: Date? = nil,
            code: Data? = nil
        ) -> PluginSettingKeychainCapability {
            PluginSettingKeychainCapability(
                authorityDomainIdentifier: domain ?? valid.authorityDomainIdentifier,
                settingIdentity: settingIdentity ?? valid.settingIdentity,
                operation: operation ?? valid.operation,
                persistentReference: reference ?? valid.persistentReference,
                revocationGeneration: generation ?? valid.revocationGeneration,
                expiresAt: expiresAt ?? valid.expiresAt,
                authenticationCode: code ?? valid.authenticationCode
            )
        }
        let mutations: [(String, PluginSettingKeychainCapability)] = [
            ("domain", copy(domain: authorityDomain(byte: 0xFF))),
            ("identity", copy(settingIdentity: try item.settingIdentity(forKey: "secret-b"))),
            (
                "operation",
                copy(operation: try PluginSettingKeychainOperation(identifier: "other"))
            ),
            ("reference", copy(reference: Data("other".utf8))),
            ("generation", copy(generation: valid.revocationGeneration + 1)),
            ("expiry", copy(expiresAt: valid.expiresAt.addingTimeInterval(1))),
            ("MAC", copy(code: Data(repeating: 0, count: valid.authenticationCode.count))),
            (
                "domain replay",
                try foreign.issue(
                    for: identity,
                    operation: operation,
                    keychainPersistentReference: Data("reference".utf8),
                    expiresAt: expiryDate
                )
            )
        ]
        for (field, capability) in mutations {
            assertCatalogError(.invalidKeychainCapability, context: field) {
                try catalog.performSecretSettingOperation(
                    for: item.id,
                    key: "secret-a",
                    capability: capability
                )
            }
            XCTAssertTrue(resolver.calls.isEmpty, field)
        }
        XCTAssertNotEqual(trusted, foreign)
    }

    func testCancellationAfterAuthoritySamplingAndResolverResultsWins() async throws {
        let fixture = try makeExternalFixture()
        let externalPolicy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let executable = try executableItem()
        let authorizationState = MutableAuthorityState(now: referenceDate, generation: 1)
        let verifier = try authorizationVerifier(authority: authorizationState)
        authorizationState.cancelCurrentTaskOnNextRead()
        let expiresAt = expiryDate
        let issueCancelled = await Task.detached { @Sendable [verifier, executable] in
            do {
                _ = try verifier.issue(
                    for: executable,
                    trust: .bundled,
                    approval: .manual,
                    externalToolPolicy: externalPolicy,
                    expiresAt: expiresAt
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(issueCancelled)

        let resolver = RecordingKeychainResolver()
        let keychainState = MutableAuthorityState(now: referenceDate, generation: 1)
        let keychainAuthority = try self.keychainAuthority(
            resolver: resolver,
            authority: keychainState
        )
        let item = try keychainItem()
        let privacy = try privacyPolicy(
            for: item,
            classifications: ["public": .nonSecret, "secret-a": .secret, "secret-b": .secret]
        )
        let catalog = try PluginCatalog(
            items: [item],
            settingPrivacyPolicy: privacy,
            keychainAuthority: keychainAuthority
        )
        let capability = try keychainAuthority.issue(
            for: item.settingIdentity(forKey: "secret-a"),
            operation: PluginSettingKeychainOperation(identifier: "resolve"),
            keychainPersistentReference: Data("reference".utf8),
            expiresAt: expiryDate
        )
        keychainState.cancelCurrentTaskOnNextRead()
        let sampledCancellation = await performSecretOperationResult(
            catalog: catalog,
            item: item,
            capability: capability
        )
        XCTAssertEqual(sampledCancellation, .cancelled)
        XCTAssertTrue(resolver.calls.isEmpty)

        for mode in [RecordingKeychainResolver.Mode.cancelThenSuccess, .cancelThenFailure] {
            resolver.reset(mode: mode)
            let result = await performSecretOperationResult(
                catalog: catalog,
                item: item,
                capability: capability
            )
            XCTAssertEqual(result, .cancelled, "\(mode)")
            XCTAssertEqual(resolver.calls.count, 1)
        }
    }

    func testAttackerControlledSettingKeysAreRedactedFromErrorsAndReflection() throws {
        let sensitiveKey = "attacker-key-material"
        let schema = try PluginSettingSchema(
            key: sensitiveKey,
            title: "Sensitive",
            constraint: .string(maximumUTF8Bytes: 64),
            defaultValue: .string("plaintext")
        )
        XCTAssertFalse(diagnostics(schema).contains(sensitiveKey))

        let invalidKey = "attacker key\nsecret"
        do {
            _ = try PluginSettingSchema(
                key: invalidKey,
                title: "Invalid",
                constraint: .boolean,
                defaultValue: .boolean(false)
            )
            XCTFail("Expected invalid setting schema")
        } catch {
            let output = diagnostics(error)
            XCTAssertFalse(output.contains(invalidKey), output)
            XCTAssertFalse(output.contains("secret"), output)
            XCTAssertEqual(error as? PluginCatalogError, .invalidSettingSchema)
        }
    }

    func testTrustedPlaintextRoundTripsWhileAdversarialPersistenceFailsClosed() throws {
        let item = try mixedSettingsItem()
        let policy = try mixedPrivacyPolicy(for: item)
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)
        let plaintext = "trusted visible preference"
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            settingValues: [item.id: ["profile": .string(plaintext)]]
        )
        let trusted = try preferences.encodedData(for: catalog)
        XCTAssertTrue(trusted.contains(Data(plaintext.utf8)))
        XCTAssertEqual(try PluginCatalogPreferences.decode(from: trusted, for: catalog), preferences)

        let rootPrefix =
            "{\"automaticPluginIdentifiers\":[],\"enabledPluginIdentifiers\":[],\"preferredAutomaticPluginIdentifiers\":[],\"schemaVersion\":1,\"settings\":"
        let adversarial = [
            "null}",
            "[{\"pluginIdentifier\":\"plugin.settings\",\"values\":[{\"key\":\"profile\",\"kind\":\"string\",\"stringValue\":\"line\\nfeed\"}]}]}",
            "[{\"pluginIdentifier\":\"plugin.settings\",\"values\":[{\"integerValue\":1,\"key\":\"profile\",\"kind\":\"string\"}]}]}",
            "[{\"pluginIdentifier\":\"plugin.settings\",\"values\":[{\"key\":\"token\",\"kind\":\"string\",\"stringValue\":\"plaintext-secret\"}]}]}"
        ]
        for payload in adversarial {
            XCTAssertThrowsError(
                try PluginCatalogPreferences.decode(
                    from: Data((rootPrefix + payload).utf8),
                    for: catalog
                ),
                payload
            )
        }
    }

    func testRichGoldenPersistenceIsExactAndRejectsBoundaryViolations() throws {
        let item = try mixedSettingsItem()
        let policy = try mixedPrivacyPolicy(for: item)
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [item.id],
            automaticPluginIdentifiers: [item.id],
            preferredAutomaticPluginIdentifiers: [item.id],
            settingValues: [
                item.id: [
                    "enabled": .boolean(true),
                    "mode": .choice("fast"),
                    "profile": .string("reviewed"),
                    "retries": .integer(4)
                ]
            ]
        )
        let golden = Data(
            "{\"automaticPluginIdentifiers\":[\"plugin.settings\"],\"enabledPluginIdentifiers\":[\"plugin.settings\"],\"preferredAutomaticPluginIdentifiers\":[\"plugin.settings\"],\"schemaVersion\":1,\"settings\":[{\"pluginIdentifier\":\"plugin.settings\",\"values\":[{\"booleanValue\":true,\"key\":\"enabled\",\"kind\":\"boolean\"},{\"key\":\"mode\",\"kind\":\"choice\",\"stringValue\":\"fast\"},{\"key\":\"profile\",\"kind\":\"string\",\"stringValue\":\"reviewed\"},{\"integerValue\":4,\"key\":\"retries\",\"kind\":\"integer\"}]}]}"
                .utf8
        )
        XCTAssertEqual(try preferences.encodedData(for: catalog), golden)
        XCTAssertEqual(try PluginCatalogPreferences.decode(from: golden, for: catalog), preferences)
        assertCatalogError(.nonCanonicalPersistence) {
            try PluginCatalogPreferences.decode(from: golden + [0x0A], for: catalog)
        }
        assertCatalogError(
            .persistenceDataTooLarge(maximumBytes: PluginCatalogLimits.hardMaximumPersistenceBytes)
        ) {
            try PluginCatalogPreferences.decode(
                from: Data(
                    repeating: 0x20,
                    count: PluginCatalogLimits.hardMaximumPersistenceBytes + 1
                ),
                for: catalog
            )
        }
    }

    func testEveryLimitRejectsOutOfRangeValues() throws {
        let invalid: [() throws -> PluginCatalogLimits] = [
            { try PluginCatalogLimits(maximumItemCount: 0) },
            { try PluginCatalogLimits(maximumSettingsPerItem: 0) },
            { try PluginCatalogLimits(maximumMatchValuesPerItem: 0) },
            { try PluginCatalogLimits(maximumChoiceCount: 0) },
            { try PluginCatalogLimits(maximumMetadataStringUTF8Bytes: 255) },
            { try PluginCatalogLimits(maximumPreferencePluginCount: 0) },
            { try PluginCatalogLimits(maximumPreferenceValueCount: 0) },
            { try PluginCatalogLimits(maximumPreferenceStringUTF8Bytes: 255) },
            { try PluginCatalogLimits(maximumPersistenceBytes: 1_023) },
            { try PluginCatalogLimits(maximumJSONDepth: 3) },
            { try PluginCatalogLimits(maximumJSONValueCount: 31) },
            { try PluginCatalogLimits(maximumPersistenceBytes: 2_048, maximumWork: 2_047) }
        ]
        for constructor in invalid {
            assertCatalogError(.invalidLimits) {
                try constructor()
            }
        }
        XCTAssertNoThrow(
            try PluginCatalogLimits(
                maximumItemCount: 1,
                maximumSettingsPerItem: 1,
                maximumMatchValuesPerItem: 1,
                maximumChoiceCount: 1,
                maximumMetadataStringUTF8Bytes: 256,
                maximumPreferencePluginCount: 1,
                maximumPreferenceValueCount: 1,
                maximumPreferenceStringUTF8Bytes: 256,
                maximumPersistenceBytes: 1_024,
                maximumJSONDepth: 4,
                maximumJSONValueCount: 32,
                maximumWork: 1_024
            )
        )
    }

    func testPersistenceCancellationDuringBoundedScanFailsClosed() async throws {
        let catalog = try PluginCatalog()
        let inputs = [
            Data(repeating: 0x20, count: PluginCatalogLimits.default.maximumPersistenceBytes),
            Data([0x22])
                + Data(
                    repeating: 0x61,
                    count: PluginCatalogLimits.default.maximumPersistenceBytes - 1
                )
        ]
        for data in inputs {
            let gate = PersistenceScanCancellationGate()
            let task = Task.detached { @Sendable [catalog, data, gate] in
                PluginCatalogTestHooks.$persistenceScanCheckpoint.withValue({ index in
                    if index == 4_096 { gate.checkpoint() }
                }) {
                    do {
                        _ = try PluginCatalogPreferences.decode(from: data, for: catalog)
                        return PersistenceCancellationResult.completed
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .failed(String(describing: error))
                    }
                }
            }
            defer {
                task.cancel()
                gate.release()
            }
            try await gate.waitUntilReached()
            task.cancel()
            gate.release()
            switch await task.value {
            case .cancelled:
                break
            case .completed:
                XCTFail("Bounded scan completed after cancellation")
            case .failed(let error):
                XCTFail("Cancellation mapped to persistence failure: \(error)")
            }
        }
    }

    private var referenceDate: Date {
        Date(timeIntervalSinceReferenceDate: 1_000_000)
    }

    private var expiryDate: Date {
        referenceDate.addingTimeInterval(3_600)
    }

    private func mixedSettingsItem() throws -> PluginCatalogItem {
        try PluginCatalogItem(
            id: PluginIdentifier("plugin.settings"),
            displayName: "Settings",
            version: "1",
            capability: .transform,
            automaticEligible: true,
            settings: [
                PluginSettingSchema(
                    key: "enabled",
                    title: "Enabled",
                    constraint: .boolean,
                    defaultValue: .boolean(false)
                ),
                PluginSettingSchema(
                    key: "retries",
                    title: "Retries",
                    constraint: .integer(minimum: 0, maximum: 10),
                    defaultValue: .integer(3)
                ),
                PluginSettingSchema(
                    key: "profile",
                    title: "Profile",
                    constraint: .string(maximumUTF8Bytes: 128),
                    defaultValue: .string("safe")
                ),
                PluginSettingSchema(
                    key: "mode",
                    title: "Mode",
                    constraint: .choice(["safe", "fast"]),
                    defaultValue: .choice("safe")
                ),
                PluginSettingSchema(
                    key: "token",
                    title: "Token",
                    constraint: .string(maximumUTF8Bytes: 1_024)
                )
            ]
        )
    }

    private func mixedPrivacyPolicy(for item: PluginCatalogItem) throws
        -> PluginSettingPrivacyPolicy
    {
        try privacyPolicy(
            for: item,
            classifications: [
                "enabled": .nonSecret,
                "mode": .nonSecret,
                "profile": .nonSecret,
                "retries": .nonSecret,
                "token": .secret
            ]
        )
    }

    private func keychainItem(version: String = "1") throws -> PluginCatalogItem {
        try PluginCatalogItem(
            id: PluginIdentifier("plugin.keychain"),
            displayName: "Keychain",
            version: version,
            capability: .transform,
            settings: [
                PluginSettingSchema(
                    key: "public",
                    title: "Public",
                    constraint: .boolean,
                    defaultValue: .boolean(false)
                ),
                PluginSettingSchema(
                    key: "secret-a",
                    title: "Secret A",
                    constraint: .string(maximumUTF8Bytes: 256)
                ),
                PluginSettingSchema(
                    key: "secret-b",
                    title: "Secret B",
                    constraint: .string(maximumUTF8Bytes: 256)
                )
            ]
        )
    }

    private func privacyPolicy(
        for item: PluginCatalogItem,
        classifications: [String: PluginSettingPrivacy]
    ) throws -> PluginSettingPrivacyPolicy {
        var trusted: [PluginSettingIdentity: PluginSettingPrivacy] = [:]
        for (key, privacy) in classifications {
            trusted[try item.settingIdentity(forKey: key)] = privacy
        }
        return try PluginSettingPrivacyPolicy(classifications: trusted)
    }

    private func executableItem(
        identifier: String = "plugin.reviewed",
        displayName: String = "Reviewed Plugin",
        summary: String? = "Reviewed summary",
        version: String = "1",
        capability: PluginCapability = .unpacker,
        manualEligible: Bool = true,
        automaticEligible: Bool = false,
        matchExtension: String = "txt",
        settings: [PluginSettingSchema] = [],
        ruleIdentifier: String = "reviewed-rule"
    ) throws -> PluginCatalogItem {
        try PluginCatalogItem(
            id: PluginIdentifier(identifier),
            displayName: displayName,
            summary: summary,
            version: version,
            capability: capability,
            manualEligible: manualEligible,
            automaticEligible: automaticEligible,
            matchMetadata: PluginMatchMetadata(fileExtensions: [matchExtension]),
            settings: settings,
            externalToolRuleIdentifier: ruleIdentifier
        )
    }

    private func authorizationVerifier(
        authority: MutableAuthorityState,
        keyByte: UInt8 = 0x21,
        domainByte: UInt8 = 0x31
    ) throws -> PluginAuthorizationVerifier {
        try PluginAuthorizationVerifier(
            authenticationKey: Data(
                repeating: keyByte,
                count: PluginAuthorizationVerifier.authenticationKeyByteCount
            ),
            authorityDomainIdentifier: authorityDomain(byte: domainByte),
            authorityStateProvider: authority
        )
    }

    private func keychainAuthority(
        resolver: RecordingKeychainResolver,
        authority: MutableAuthorityState,
        keyByte: UInt8 = 0x41,
        domainByte: UInt8 = 0x51
    ) throws -> PluginSettingKeychainAuthority {
        try PluginSettingKeychainAuthority(
            authenticationKey: Data(
                repeating: keyByte,
                count: PluginSettingKeychainAuthority.authenticationKeyByteCount
            ),
            authorityDomainIdentifier: authorityDomain(byte: domainByte),
            resolver: resolver,
            authorityStateProvider: authority
        )
    }

    private func authorityDomain(byte: UInt8 = 0x31) -> Data {
        Data(
            repeating: byte,
            count: PluginAuthorizationVerifier.authorityDomainIdentifierByteCount
        )
    }

    private func performSecretOperationResult(
        catalog: PluginCatalog,
        item: PluginCatalogItem,
        capability: PluginSettingKeychainCapability
    ) async -> SecretOperationResult {
        await Task.detached { @Sendable in
            do {
                try catalog.performSecretSettingOperation(
                    for: item.id,
                    key: "secret-a",
                    capability: capability
                )
                return SecretOperationResult.completed
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed
            }
        }.value
    }

    private func enabledPreferences(
        for item: PluginCatalogItem,
        in catalog: PluginCatalog,
        automatic: Bool = false
    ) throws -> PluginCatalogPreferences {
        try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [item.id],
            automaticPluginIdentifiers: automatic ? [item.id] : []
        )
    }

    private func decision(
        catalog: PluginCatalog,
        item: PluginCatalogItem,
        mode: PluginInvocationMode,
        authorization: PluginAuthorization?,
        preferences: PluginCatalogPreferences,
        policy: ExternalToolPolicy
    ) throws -> PluginCatalogEligibilityDecision {
        try XCTUnwrap(
            catalog.decision(
                for: item.id,
                mode: mode,
                authorization: authorization,
                preferences: preferences,
                externalToolPolicy: policy
            )
        )
    }

    private func makeExternalFixture() throws -> ExternalFixture {
        let temporaryDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = temporaryDirectory.appending(
            path: "MacMergePluginCatalogTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try setPermissions(0o700, on: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let executableData = Data([0x7F, 0x4D, 0x41, 0x43, 0x4D, 0x45, 0x52, 0x47, 0x45])
        let executableURL = root.appending(path: "reviewed-tool")
        let alternateExecutableURL = root.appending(path: "alternate-tool")
        try executableData.write(to: executableURL)
        try executableData.write(to: alternateExecutableURL)
        try setPermissions(0o700, on: executableURL)
        try setPermissions(0o700, on: alternateExecutableURL)
        let outputDirectory = root.appending(path: "output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: false
        )
        try setPermissions(0o700, on: outputDirectory)
        return ExternalFixture(
            root: root,
            executableURL: executableURL,
            alternateExecutableURL: alternateExecutableURL,
            outputDirectory: outputDirectory,
            executableData: executableData
        )
    }

    private func makeRule(
        _ fixture: ExternalFixture,
        identifier: String = "reviewed-rule",
        capability: ExternalToolCapability = .unpacker,
        executableURL: URL? = nil,
        approvedExecutableSHA256: [UInt8]? = nil,
        permittedWorkingDirectories: [ExternalToolPathScope]? = nil,
        permittedReadScopes: [ExternalToolPathScope]? = nil,
        permittedWriteScopes: [ExternalToolPathScope] = [],
        allowedEnvironmentKeys: [String] = ["SAFE"],
        argumentConstraints: [ExternalToolArgumentConstraint] = [.value],
        isolationPolicy: ExternalToolIsolationPolicy = .default,
        limits: ExternalToolInvocationLimits? = nil
    ) -> ExternalToolExecutableRule {
        let selectedURL = executableURL ?? fixture.executableURL
        return ExternalToolExecutableRule(
            identifier: identifier,
            capability: capability,
            executableURL: selectedURL,
            approvedExecutableSHA256: approvedExecutableSHA256 ?? digest(fixture.executableData),
            permittedWorkingDirectories: permittedWorkingDirectories ?? [exact(fixture.root)],
            permittedReadScopes: permittedReadScopes ?? [tree(fixture.root)],
            permittedWriteScopes: permittedWriteScopes,
            allowedEnvironmentKeys: allowedEnvironmentKeys,
            argumentConstraints: argumentConstraints,
            isolationPolicy: isolationPolicy,
            limits: limits ?? baselineInvocationLimits()
        )
    }

    private func baselineInvocationLimits(
        maximumArgumentCount: Int = 8,
        maximumArgumentUTF8Bytes: Int = 32,
        maximumTotalArgumentUTF8Bytes: Int = 128,
        maximumEnvironmentEntryCount: Int = 8,
        maximumEnvironmentKeyUTF8Bytes: Int = 32,
        maximumEnvironmentValueUTF8Bytes: Int = 32,
        maximumTotalEnvironmentUTF8Bytes: Int = 128,
        maximumScopeCount: Int = 16,
        maximumPathUTF8Bytes: Int = 4_096,
        maximumTotalPathUTF8Bytes: Int = 65_536,
        timeoutSeconds: TimeInterval = 30,
        standardOutputLimitBytes: Int = 1_024,
        standardErrorLimitBytes: Int = 1_024,
        combinedOutputLimitBytes: Int = 2_048
    ) -> ExternalToolInvocationLimits {
        try! ExternalToolInvocationLimits(
            maximumArgumentCount: maximumArgumentCount,
            maximumArgumentUTF8Bytes: maximumArgumentUTF8Bytes,
            maximumTotalArgumentUTF8Bytes: maximumTotalArgumentUTF8Bytes,
            maximumEnvironmentEntryCount: maximumEnvironmentEntryCount,
            maximumEnvironmentKeyUTF8Bytes: maximumEnvironmentKeyUTF8Bytes,
            maximumEnvironmentValueUTF8Bytes: maximumEnvironmentValueUTF8Bytes,
            maximumTotalEnvironmentUTF8Bytes: maximumTotalEnvironmentUTF8Bytes,
            maximumScopeCount: maximumScopeCount,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes,
            timeoutSeconds: timeoutSeconds,
            standardOutputLimitBytes: standardOutputLimitBytes,
            standardErrorLimitBytes: standardErrorLimitBytes,
            combinedOutputLimitBytes: combinedOutputLimitBytes
        )
    }

    private func limitRuleMutations(_ fixture: ExternalFixture)
        -> [(String, ExternalToolExecutableRule)]
    {
        [
            ("maximumArgumentCount", makeRule(fixture, limits: baselineInvocationLimits(maximumArgumentCount: 9))),
            ("maximumArgumentUTF8Bytes", makeRule(fixture, limits: baselineInvocationLimits(maximumArgumentUTF8Bytes: 33))),
            ("maximumTotalArgumentUTF8Bytes", makeRule(fixture, limits: baselineInvocationLimits(maximumTotalArgumentUTF8Bytes: 129))),
            ("maximumEnvironmentEntryCount", makeRule(fixture, limits: baselineInvocationLimits(maximumEnvironmentEntryCount: 9))),
            ("maximumEnvironmentKeyUTF8Bytes", makeRule(fixture, limits: baselineInvocationLimits(maximumEnvironmentKeyUTF8Bytes: 33))),
            ("maximumEnvironmentValueUTF8Bytes", makeRule(fixture, limits: baselineInvocationLimits(maximumEnvironmentValueUTF8Bytes: 33))),
            ("maximumTotalEnvironmentUTF8Bytes", makeRule(fixture, limits: baselineInvocationLimits(maximumTotalEnvironmentUTF8Bytes: 129))),
            ("maximumScopeCount", makeRule(fixture, limits: baselineInvocationLimits(maximumScopeCount: 17))),
            ("maximumPathUTF8Bytes", makeRule(fixture, limits: baselineInvocationLimits(maximumPathUTF8Bytes: 4_097))),
            ("maximumTotalPathUTF8Bytes", makeRule(fixture, limits: baselineInvocationLimits(maximumTotalPathUTF8Bytes: 65_537))),
            ("timeoutSeconds", makeRule(fixture, limits: baselineInvocationLimits(timeoutSeconds: 31))),
            ("standardOutputLimitBytes", makeRule(fixture, limits: baselineInvocationLimits(standardOutputLimitBytes: 1_025))),
            ("standardErrorLimitBytes", makeRule(fixture, limits: baselineInvocationLimits(standardErrorLimitBytes: 1_025))),
            ("combinedOutputLimitBytes", makeRule(fixture, limits: baselineInvocationLimits(combinedOutputLimitBytes: 2_049)))
        ]
    }

    private func exact(_ url: URL) -> ExternalToolPathScope {
        ExternalToolPathScope(url: url, kind: .exactItem)
    }

    private func tree(_ url: URL) -> ExternalToolPathScope {
        ExternalToolPathScope(url: url, kind: .directoryTree)
    }

    private func setPermissions(_ permissions: Int, on url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }

    private func digest(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func diagnostics(_ value: Any) -> String {
        let mirrorValues = Mirror(reflecting: value).children.map {
            "\($0.label ?? "<nil>")=\(String(reflecting: $0.value))"
        }
        return ([String(describing: value), String(reflecting: value)] + mirrorValues)
            .joined(separator: "\n")
    }

    private func mirroredData(in value: Any, depth: Int = 0) -> [Data] {
        if let data = value as? Data { return [data] }
        guard depth < 8 else { return [] }
        return Mirror(reflecting: value).children.flatMap {
            mirroredData(in: $0.value, depth: depth + 1)
        }
    }

    private func assertNoMatch(
        _ outcome: PluginCatalogSelectionOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .noMatch = outcome else {
            XCTFail("Expected no match, got \(outcome)", file: file, line: line)
            return
        }
    }

    private func assertSelected(
        _ outcome: PluginCatalogSelectionOutcome,
        identifier: PluginIdentifier,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .selected(let item) = outcome else {
            XCTFail("Expected selection, got \(outcome)", file: file, line: line)
            return
        }
        XCTAssertEqual(item.id, identifier, file: file, line: line)
    }

    private func assertAmbiguous(
        _ outcome: PluginCatalogSelectionOutcome,
        identifiers: [PluginIdentifier],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .ambiguous(let actual) = outcome else {
            XCTFail("Expected ambiguity, got \(outcome)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, identifiers, file: file, line: line)
    }

    private func assertCatalogError<T>(
        _ expected: PluginCatalogError,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> T
    ) {
        XCTAssertThrowsError(try expression(), context, file: file, line: line) { error in
            XCTAssertEqual(error as? PluginCatalogError, expected, context, file: file, line: line)
        }
    }
}

private struct ExternalFixture {
    let root: URL
    let executableURL: URL
    let alternateExecutableURL: URL
    let outputDirectory: URL
    let executableData: Data
}

private final class MutableAuthorityState: PluginAuthorizationAuthorityStateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var state: PluginAuthorizationAuthorityState
    private var reads = 0
    private var cancelOnNextRead = false
    private let events: SecurityEventLog?

    init(
        now: Date,
        generation: UInt64,
        events: SecurityEventLog? = nil
    ) {
        state = PluginAuthorizationAuthorityState(
            revocationGeneration: generation,
            currentTime: now
        )
        self.events = events
    }

    var readCount: Int {
        lock.withLock { reads }
    }

    func set(now: Date, generation: UInt64) {
        lock.withLock {
            state = PluginAuthorizationAuthorityState(
                revocationGeneration: generation,
                currentTime: now
            )
        }
    }

    func cancelCurrentTaskOnNextRead() {
        lock.withLock { cancelOnNextRead = true }
    }

    func currentPluginAuthorizationAuthorityState() -> PluginAuthorizationAuthorityState {
        let (current, shouldCancel) = lock.withLock {
            reads += 1
            let shouldCancel = cancelOnNextRead
            cancelOnNextRead = false
            return (state, shouldCancel)
        }
        events?.append("authority")
        if shouldCancel {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return current
    }
}

private struct KeychainCall: Equatable, Sendable {
    let operation: String
    let persistentReference: Data
}

private final class RecordingKeychainResolver: PluginSettingKeychainResolving, @unchecked Sendable {
    enum Mode: Sendable {
        case success
        case cancellation
        case failure
        case cancelThenSuccess
        case cancelThenFailure
    }

    private let lock = NSLock()
    private var recordedCalls: [KeychainCall] = []
    private var mode: Mode
    private let events: SecurityEventLog?

    init(mode: Mode = .success, events: SecurityEventLog? = nil) {
        self.mode = mode
        self.events = events
    }

    var calls: [KeychainCall] {
        lock.withLock { recordedCalls }
    }

    func reset(mode: Mode = .success) {
        lock.withLock {
            recordedCalls = []
            self.mode = mode
        }
    }

    func perform(
        operation: PluginSettingKeychainOperation,
        keychainPersistentReference: Data
    ) throws {
        let selectedMode = lock.withLock {
            recordedCalls.append(
                KeychainCall(
                    operation: operation.identifier,
                    persistentReference: keychainPersistentReference
                )
            )
            return mode
        }
        events?.append("resolver")
        switch selectedMode {
        case .success:
            return
        case .cancellation:
            throw CancellationError()
        case .failure:
            throw KeychainResolverFailure.failed
        case .cancelThenSuccess:
            withUnsafeCurrentTask { $0?.cancel() }
            return
        case .cancelThenFailure:
            withUnsafeCurrentTask { $0?.cancel() }
            throw KeychainResolverFailure.failed
        }
    }
}

private enum KeychainResolverFailure: Error {
    case failed
}

private enum SecretOperationResult: Equatable {
    case completed
    case cancelled
    case failed
}

private enum PersistenceCancellationResult: Equatable {
    case completed
    case cancelled
    case failed(String)
}

private final class PersistenceScanCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var reachedCheckpoint = false
    private var released = false

    func checkpoint() {
        lock.withLock { reachedCheckpoint = true }
        releaseSemaphore.wait()
    }

    func waitUntilReached() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !lock.withLock({ reachedCheckpoint }) {
            guard clock.now < deadline else { throw PersistenceScanGateError.timedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func release() {
        let shouldSignal = lock.withLock {
            guard !released else { return false }
            released = true
            return true
        }
        if shouldSignal { releaseSemaphore.signal() }
    }
}

private enum PersistenceScanGateError: Error {
    case timedOut
}

private final class SecurityEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }

    func clear() {
        lock.withLock { storage.removeAll(keepingCapacity: true) }
    }
}
