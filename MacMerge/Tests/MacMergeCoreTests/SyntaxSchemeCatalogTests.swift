import Foundation
import MacMergeCore
import XCTest

final class SyntaxSchemeCatalogTests: XCTestCase {
    func testBuiltInAndCustomIdentifiersHaveStableNamespacesAndLanguageDefaults() throws {
        let expected: [(SyntaxHighlightingLanguage, SyntaxSchemeIdentifier, String)] = [
            (.plainText, .builtInPlainText, "macmerge.syntax.plain-text"),
            (.swift, .builtInSwift, "macmerge.syntax.swift"),
            (.cLike, .builtInCLike, "macmerge.syntax.c-like"),
            (.json, .builtInJSON, "macmerge.syntax.json"),
            (.markdown, .builtInMarkdown, "macmerge.syntax.markdown")
        ]

        XCTAssertEqual(SyntaxSchemeCatalog.builtInSchemes.count, expected.count)
        for (language, identifier, rawValue) in expected {
            XCTAssertEqual(identifier.rawValue, rawValue)
            XCTAssertEqual(SyntaxSchemeIdentifier.builtIn(for: language), identifier)
            XCTAssertEqual(SyntaxSchemeCatalog.defaultIdentifier(for: language), identifier)
            let scheme = try XCTUnwrap(
                SyntaxSchemeCatalog.builtInSchemes.first { $0.id == identifier }
            )
            XCTAssertEqual(scheme.origin, .builtIn)
            XCTAssertEqual(scheme.supportedLanguages, [language])
        }

        let customID = try SyntaxSchemeIdentifier("example.syntax.swift")
        let custom = try makeScheme(id: customID, name: "Example", languages: [.swift])
        XCTAssertEqual(custom.id, customID)
        XCTAssertEqual(custom.origin, .custom)
        XCTAssertEqual(customID.description, customID.rawValue)

        XCTAssertNoThrow(
            try SyntaxSchemeIdentifier(String(repeating: "a", count: SyntaxSchemeIdentifier.maximumUTF8Bytes))
        )
        assertCatalogError(
            .identifierTooLarge(maximumUTF8Bytes: SyntaxSchemeIdentifier.maximumUTF8Bytes)
        ) {
            _ = try SyntaxSchemeIdentifier(
                String(repeating: "a", count: SyntaxSchemeIdentifier.maximumUTF8Bytes + 1)
            )
        }
        for invalid in ["", "-leading", "trailing-", "contains/slash", "nonascii-é"] {
            assertCatalogError(.invalidIdentifier, invalid) {
                _ = try SyntaxSchemeIdentifier(invalid)
            }
        }

        let reservedID = try SyntaxSchemeIdentifier("macmerge.syntax.custom")
        assertCatalogError(.reservedCustomIdentifier) {
            _ = try self.makeScheme(id: reservedID, name: "Reserved", languages: [.swift])
        }
    }

    func testCustomSchemeNormalizesMetadataAndRejectsDuplicates() throws {
        let reversedReferences = Array(SyntaxScheme.canonicalColorRoleReferences.reversed())
        let scheme = try SyntaxScheme(
            id: SyntaxSchemeIdentifier("custom.normalized"),
            displayName: "Cafe\u{301}",
            supportedLanguages: [.markdown, .swift],
            applicationModes: [.textEditor, .textComparison],
            colorRoleReferences: reversedReferences
        )

        XCTAssertEqual(scheme.displayName, "Café")
        XCTAssertEqual(scheme.supportedLanguages, [.swift, .markdown])
        XCTAssertEqual(scheme.applicationModes, [.textComparison, .textEditor])
        XCTAssertEqual(scheme.colorRoleReferences, SyntaxScheme.canonicalColorRoleReferences)

        let id = try SyntaxSchemeIdentifier("custom.duplicate-metadata")
        assertCatalogError(.duplicateSupportedLanguage(.swift)) {
            _ = try self.makeScheme(
                id: id,
                name: "Languages",
                languages: [.swift, .swift]
            )
        }
        assertCatalogError(.duplicateApplicationMode(.textEditor)) {
            _ = try self.makeScheme(
                id: id,
                name: "Modes",
                languages: [.swift],
                modes: [.textEditor, .textEditor]
            )
        }

        let first = try makeScheme(id: id, name: "First", languages: [.swift])
        let second = try makeScheme(id: id, name: "Second", languages: [.json])
        assertCatalogError(.duplicateSchemeIdentifier(id)) {
            _ = try SyntaxSchemeCatalog(customSchemes: [first, second])
        }
    }

    func testCatalogOrderAndLookupAreDeterministicAcrossRegistrationOrder() throws {
        let alpha = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.alpha"),
            name: "Zulu Display Name",
            languages: [.swift]
        )
        let zulu = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.zulu"),
            name: "Alpha Display Name",
            languages: [.swift]
        )
        let forward = try SyntaxSchemeCatalog(customSchemes: [alpha, zulu])
        let reverse = try SyntaxSchemeCatalog(customSchemes: [zulu, alpha])
        let expectedIDs = (SyntaxSchemeCatalog.builtInSchemes.map(\.id) + [alpha.id, zulu.id])
            .sorted()

        XCTAssertEqual(forward.schemes.map(\.id), expectedIDs)
        XCTAssertEqual(reverse.schemes.map(\.id), expectedIDs)
        XCTAssertEqual(Array(forward).map(\.id), expectedIDs)
        XCTAssertEqual(forward.scheme(withIdentifier: alpha.id), alpha)
        XCTAssertEqual(forward.scheme(withIdentifier: zulu.id), zulu)
        XCTAssertNil(forward.scheme(withIdentifier: try SyntaxSchemeIdentifier("custom.missing")))
        XCTAssertEqual(
            SyntaxSchemeCatalog.builtInSchemes.map(\.id),
            expectedIDs.filter {
                $0.rawValue.hasPrefix("macmerge.syntax.")
            })
    }

    func testLanguageAndModeApplicabilityIsExactAndReturnedInStableOrder() throws {
        let multi = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.multi"),
            name: "Multi",
            languages: [.json, .swift],
            modes: [.textEditor, .conflictComparison]
        )
        let swiftEditor = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.swift-editor"),
            name: "Swift Editor",
            languages: [.swift],
            modes: [.textEditor]
        )
        let catalog = try SyntaxSchemeCatalog(customSchemes: [swiftEditor, multi])

        XCTAssertTrue(multi.supports(language: .swift, mode: .textEditor))
        XCTAssertTrue(multi.supports(language: .json, mode: .conflictComparison))
        XCTAssertFalse(multi.supports(language: .markdown, mode: .textEditor))
        XCTAssertFalse(multi.supports(language: .swift, mode: .textComparison))

        let editorMatches = try catalog.schemes(supporting: .swift, in: .textEditor)
        XCTAssertEqual(
            editorMatches.map(\.id),
            [.builtInSwift, multi.id, swiftEditor.id].sorted()
        )
        XCTAssertEqual(
            try catalog.schemes(supporting: .swift, in: .textComparison).map(\.id),
            [.builtInSwift]
        )
        for builtIn in SyntaxSchemeCatalog.builtInSchemes {
            for mode in SyntaxSchemeApplicationMode.allCases {
                XCTAssertTrue(
                    builtIn.supports(language: builtIn.supportedLanguages[0], mode: mode),
                    "\(builtIn.id): \(mode.rawValue)"
                )
            }
        }
    }

    func testResolutionPrefersApplicableSelectedScheme() throws {
        let selected = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.selected"),
            name: "Selected",
            languages: [.swift],
            modes: [.textComparison]
        )
        let fallback = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.fallback"),
            name: "Fallback",
            languages: [.swift],
            modes: [.textComparison]
        )
        let catalog = try SyntaxSchemeCatalog(customSchemes: [fallback, selected])
        let resolution = try catalog.resolve(
            SyntaxSchemeSelection(
                selectedIdentifier: selected.id,
                fallbackIdentifier: fallback.id
            ),
            language: .swift,
            mode: .textComparison
        )

        XCTAssertEqual(resolution.scheme, selected)
        XCTAssertEqual(resolution.source, .selected)
        XCTAssertNil(resolution.selectedRejection)
        XCTAssertNil(resolution.fallbackRejection)
        XCTAssertEqual(resolution.requestedLanguage, .swift)
        XCTAssertEqual(resolution.applicationMode, .textComparison)
        XCTAssertEqual(resolution.expectedCatalogRevision, catalog.revision)
    }

    func testResolutionUsesFallbackThenLanguageDefaultWithTypedRejections() throws {
        let selected = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.editor-only"),
            name: "Editor Only",
            languages: [.swift],
            modes: [.textEditor]
        )
        let fallback = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.swift-fallback"),
            name: "Swift Fallback",
            languages: [.swift],
            modes: [.textComparison]
        )
        let catalog = try SyntaxSchemeCatalog(customSchemes: [selected, fallback])
        let fallbackResolution = try catalog.resolve(
            SyntaxSchemeSelection(
                selectedIdentifier: selected.id,
                fallbackIdentifier: fallback.id
            ),
            language: .swift,
            mode: .textComparison
        )

        XCTAssertEqual(fallbackResolution.scheme, fallback)
        XCTAssertEqual(fallbackResolution.source, .explicitFallback)
        XCTAssertEqual(fallbackResolution.selectedRejection, .unsupportedMode)
        XCTAssertNil(fallbackResolution.fallbackRejection)

        let unknown = try SyntaxSchemeIdentifier("custom.unknown")
        let defaultResolution = try catalog.resolve(
            SyntaxSchemeSelection(
                selectedIdentifier: unknown,
                fallbackIdentifier: fallback.id
            ),
            language: .json,
            mode: .textEditor
        )
        XCTAssertEqual(defaultResolution.scheme.id, .builtInJSON)
        XCTAssertEqual(defaultResolution.source, .languageDefault)
        XCTAssertEqual(defaultResolution.selectedRejection, .unavailable)
        XCTAssertEqual(defaultResolution.fallbackRejection, .unsupportedLanguage)

        let unsupportedModeResolution = try catalog.resolve(
            SyntaxSchemeSelection(fallbackIdentifier: selected.id),
            language: .swift,
            mode: .conflictComparison
        )
        XCTAssertEqual(unsupportedModeResolution.scheme.id, .builtInSwift)
        XCTAssertEqual(unsupportedModeResolution.fallbackRejection, .unsupportedMode)

        let noneResolution = try catalog.resolve(
            .none,
            language: .markdown,
            mode: .threeWayTextComparison
        )
        XCTAssertEqual(noneResolution.scheme.id, .builtInMarkdown)
        XCTAssertEqual(noneResolution.source, .languageDefault)
        XCTAssertNil(noneResolution.selectedRejection)
        XCTAssertNil(noneResolution.fallbackRejection)
    }

    func testTokenToColorRoleMappingIsCompleteBidirectionalAndStrict() throws {
        let expected: [(SyntaxTokenKind, EditorColorRole)] = [
            (.keyword, .syntaxKeyword),
            (.string, .syntaxString),
            (.comment, .syntaxComment),
            (.number, .syntaxNumber),
            (.literal, .syntaxLiteral),
            (.heading, .syntaxHeading),
            (.emphasis, .syntaxEmphasis),
            (.code, .syntaxCode),
            (.link, .syntaxLink)
        ]

        XCTAssertEqual(expected.map(\.0), SyntaxTokenKind.allCases)
        XCTAssertEqual(SyntaxScheme.canonicalColorRoleReferences.count, expected.count)
        for (tokenKind, colorRole) in expected {
            XCTAssertEqual(tokenKind.editorColorRole, colorRole)
            XCTAssertEqual(colorRole.syntaxTokenKind, tokenKind)
            let reference = try SyntaxSchemeColorRoleReference(
                tokenKind: tokenKind,
                colorRole: colorRole
            )
            XCTAssertEqual(reference.tokenKind, tokenKind)
            XCTAssertEqual(reference.colorRole, colorRole)
        }
        XCTAssertNil(EditorColorRole.textForeground.syntaxTokenKind)

        assertCatalogError(
            .incompatibleColorRole(tokenKind: .keyword, colorRole: .syntaxString)
        ) {
            _ = try SyntaxSchemeColorRoleReference(
                tokenKind: .keyword,
                colorRole: .syntaxString
            )
        }

        let id = try SyntaxSchemeIdentifier("custom.roles")
        let missing = Array(SyntaxScheme.canonicalColorRoleReferences.dropLast())
        assertCatalogError(.missingColorRoleReference(.link)) {
            _ = try SyntaxScheme(
                id: id,
                displayName: "Missing",
                supportedLanguages: [.swift],
                colorRoleReferences: missing
            )
        }
        let duplicate = missing + [SyntaxScheme.canonicalColorRoleReferences[0]]
        assertCatalogError(.duplicateColorRoleReference(.keyword)) {
            _ = try SyntaxScheme(
                id: id,
                displayName: "Duplicate",
                supportedLanguages: [.swift],
                colorRoleReferences: duplicate
            )
        }
        assertCatalogError(.tooManyColorRoleReferences(maximum: SyntaxTokenKind.allCases.count)) {
            _ = try SyntaxScheme(
                id: id,
                displayName: "Too Many",
                supportedLanguages: [.swift],
                colorRoleReferences: SyntaxScheme.canonicalColorRoleReferences
                    + [SyntaxScheme.canonicalColorRoleReferences[0]]
            )
        }
    }

    func testSelectionPersistenceIsRedactedCanonicalAndStableIDOnly() throws {
        let selected = try SyntaxSchemeIdentifier("private.selected")
        let fallback = try SyntaxSchemeIdentifier("private.fallback")
        let selection = SyntaxSchemeSelection(
            selectedIdentifier: selected,
            fallbackIdentifier: fallback
        )
        let expected = Data(
            #"{"fallbackIdentifier":"private.fallback","schemaVersion":1,"selectedIdentifier":"private.selected"}"#.utf8
        )

        XCTAssertEqual(SyntaxSchemeSelection.currentSchemaVersion, 1)
        XCTAssertEqual(try selection.encodedData(), expected)
        XCTAssertEqual(try selection.redactedEncodedData(), expected)
        XCTAssertEqual(try SyntaxSchemeSelection.decode(from: expected), selection)
        XCTAssertEqual(try SyntaxSchemeSelection.decodeRedacted(from: expected), selection)

        for redactedDescription in [selection.description, selection.debugDescription] {
            XCTAssertTrue(redactedDescription.contains("<redacted>"))
            XCTAssertFalse(redactedDescription.contains(selected.rawValue))
            XCTAssertFalse(redactedDescription.contains(fallback.rawValue))
        }
        let reflectedValues = Mirror(reflecting: selection).children.map {
            String(describing: $0.value)
        }.joined(separator: " ")
        XCTAssertFalse(reflectedValues.contains(selected.rawValue))
        XCTAssertFalse(reflectedValues.contains(fallback.rawValue))

        let scheme = try makeScheme(id: selected, name: "Secret Display Name", languages: [.swift])
        let catalog = try SyntaxSchemeCatalog(customSchemes: [scheme])
        for redactedDescription in [
            scheme.description,
            scheme.debugDescription,
            catalog.description,
            catalog.debugDescription,
            catalog.fingerprint.description,
            catalog.fingerprint.debugDescription
        ] {
            XCTAssertTrue(redactedDescription.contains("<redacted>"))
            XCTAssertFalse(redactedDescription.contains(selected.rawValue))
            XCTAssertFalse(redactedDescription.contains("Secret Display Name"))
        }
        XCTAssertFalse(String(decoding: expected, as: UTF8.self).contains("Secret Display Name"))
    }

    func testPersistenceRejectsUnsupportedSchemaUnknownFieldsAndMalformedShapes() throws {
        assertCatalogError(.unsupportedSchemaVersion(2)) {
            _ = try SyntaxSchemeSelection.decode(
                from: Data(
                    #"{"fallbackIdentifier":null,"schemaVersion":2,"selectedIdentifier":null}"#.utf8
                )
            )
        }
        assertCatalogError(.nonCanonicalPersistence) {
            _ = try SyntaxSchemeSelection.decode(
                from: Data(
                    #"{"fallbackIdentifier":null,"schemaVersion":1,"selectedIdentifier":null,"unknown":true}"#.utf8
                )
            )
        }
        assertCatalogError(.nonCanonicalPersistence) {
            _ = try SyntaxSchemeSelection.decode(
                from: Data(
                    #"{ "fallbackIdentifier": null, "schemaVersion": 1, "selectedIdentifier": null }"#.utf8
                )
            )
        }
        for malformed in [
            #"{"schemaVersion":1,"selectedIdentifier":null}"#,
            #"{"fallbackIdentifier":null,"schemaVersion":"1","selectedIdentifier":null}"#,
            #"{"fallbackIdentifier":null,"schemaVersion":1,"selectedIdentifier":false}"#,
            #"{"fallbackIdentifier":null,"schemaVersion":1,"selectedIdentifier":null"#
        ] {
            assertCatalogError(.malformedPersistence, malformed) {
                _ = try SyntaxSchemeSelection.decode(from: Data(malformed.utf8))
            }
        }
        assertCatalogError(.invalidIdentifier) {
            _ = try SyntaxSchemeSelection.decode(
                from: Data(
                    #"{"fallbackIdentifier":null,"schemaVersion":1,"selectedIdentifier":"invalid/id"}"#.utf8
                )
            )
        }
    }

    func testPersistenceDepthSizeAndWorkLimitsAreStrictAtBoundaries() throws {
        let selection = SyntaxSchemeSelection(
            selectedIdentifier: try SyntaxSchemeIdentifier("custom.selected")
        )
        let data = try selection.encodedData()
        let exactPersistence = try limits(maximumPersistenceBytes: data.count)

        XCTAssertEqual(try selection.encodedData(limits: exactPersistence), data)
        XCTAssertEqual(
            try SyntaxSchemeSelection.decode(from: data, limits: exactPersistence),
            selection
        )

        let oneByteShort = try limits(maximumPersistenceBytes: data.count - 1)
        assertCatalogError(.persistenceOutputTooLarge(maximumBytes: data.count - 1)) {
            _ = try selection.encodedData(limits: oneByteShort)
        }
        assertCatalogError(.persistenceInputTooLarge(maximumBytes: data.count - 1)) {
            _ = try SyntaxSchemeSelection.decode(from: data, limits: oneByteShort)
        }

        let depthLimit = try limits(maximumJSONDepth: 1)
        XCTAssertEqual(
            try SyntaxSchemeSelection.decode(from: data, limits: depthLimit),
            selection
        )
        let nested = Data(
            #"{"fallbackIdentifier":null,"nested":{},"schemaVersion":1,"selectedIdentifier":null}"#.utf8
        )
        assertCatalogError(.jsonTooDeep(maximumDepth: 1)) {
            _ = try SyntaxSchemeSelection.decode(from: nested, limits: depthLimit)
        }

        let exactEncodingWork = try limits(maximumWorkUnits: data.count)
        XCTAssertEqual(try selection.encodedData(limits: exactEncodingWork), data)
        let insufficientEncodingWork = try limits(maximumWorkUnits: data.count - 1)
        assertCatalogError(.workLimitExceeded(maximumWorkUnits: data.count - 1)) {
            _ = try selection.encodedData(limits: insufficientEncodingWork)
        }

        let exactDecodingWork = try limits(maximumWorkUnits: data.count)
        XCTAssertEqual(
            try SyntaxSchemeSelection.decode(from: data, limits: exactDecodingWork),
            selection
        )
        let insufficientDecodingWork = try limits(maximumWorkUnits: data.count - 1)
        assertCatalogError(.workLimitExceeded(maximumWorkUnits: data.count - 1)) {
            _ = try SyntaxSchemeSelection.decode(from: data, limits: insufficientDecodingWork)
        }

        assertCatalogError(.invalidLimits) {
            _ = try SyntaxSchemeCatalogLimits(maximumJSONDepth: 0)
        }
        assertCatalogError(.invalidLimits) {
            _ = try SyntaxSchemeCatalogLimits(
                maximumCustomSchemeCount: SyntaxSchemeCatalogLimits.hardMaximumCustomSchemeCount + 1
            )
        }
    }

    func testRestoreUsesDecodedSelectionOrCallerFallbackWithoutAcceptingInvalidData() throws {
        let fallback = SyntaxSchemeSelection(
            selectedIdentifier: try SyntaxSchemeIdentifier("custom.safe-fallback")
        )
        let persisted = SyntaxSchemeSelection(
            selectedIdentifier: try SyntaxSchemeIdentifier("custom.persisted")
        )

        XCTAssertEqual(
            try SyntaxSchemeSelection.restored(from: nil, fallback: fallback),
            fallback
        )
        XCTAssertEqual(
            try SyntaxSchemeSelection.restored(
                from: Data("not-json".utf8),
                fallback: fallback
            ),
            fallback
        )
        XCTAssertEqual(
            try SyntaxSchemeSelection.restored(
                from: try persisted.encodedData(),
                fallback: fallback
            ),
            persisted
        )
    }

    func testResolutionFingerprintDetectsRevisionAndContentStaleness() throws {
        let revision = SyntaxSchemeCatalogRevision(lineage: 7, generation: 11)
        let originalScheme = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.original"),
            name: "Original",
            languages: [.swift]
        )
        let original = try SyntaxSchemeCatalog(
            customSchemes: [originalScheme],
            revision: revision
        )
        let resolution = try original.resolve(
            .none,
            language: .swift,
            mode: .textComparison
        )
        let equivalent = try SyntaxSchemeCatalog(
            customSchemes: [originalScheme],
            revision: revision
        )

        XCTAssertTrue(try resolution.isCurrent(in: original))
        XCTAssertTrue(try resolution.isCurrent(in: equivalent))
        XCTAssertNoThrow(try resolution.validate(against: equivalent))

        let changedSchemeMetadata = try makeScheme(
            id: originalScheme.id,
            name: "Changed",
            languages: [.swift]
        )
        let changedMetadata = try SyntaxSchemeCatalog(
            customSchemes: [changedSchemeMetadata],
            revision: revision
        )
        XCTAssertEqual(changedMetadata.schemes.count, original.schemes.count)
        XCTAssertFalse(try resolution.isCurrent(in: changedMetadata))
        assertCatalogError(.staleCatalog(expected: revision, actual: revision)) {
            try resolution.validate(against: changedMetadata)
        }

        let changedLimits = try limits(
            maximumWorkUnits: SyntaxSchemeCatalogLimits.default.maximumWorkUnits + 1
        )
        let limitsOnlyChange = try SyntaxSchemeCatalog(
            customSchemes: [originalScheme],
            revision: revision,
            limits: changedLimits
        )
        XCTAssertEqual(limitsOnlyChange.schemes, original.schemes)
        XCTAssertFalse(try resolution.isCurrent(in: limitsOnlyChange))
        assertCatalogError(.staleCatalog(expected: revision, actual: revision)) {
            try resolution.validate(against: limitsOnlyChange)
        }

        let added = try makeScheme(
            id: SyntaxSchemeIdentifier("custom.added"),
            name: "Added",
            languages: [.swift]
        )
        let changedContent = try SyntaxSchemeCatalog(
            customSchemes: [originalScheme, added],
            revision: revision
        )
        XCTAssertFalse(try resolution.isCurrent(in: changedContent))
        assertCatalogError(.staleCatalog(expected: revision, actual: revision)) {
            try resolution.validate(against: changedContent)
        }

        let nextRevision = SyntaxSchemeCatalogRevision(lineage: 7, generation: 12)
        let changedRevision = try SyntaxSchemeCatalog(
            customSchemes: [originalScheme],
            revision: nextRevision
        )
        XCTAssertFalse(try resolution.isCurrent(in: changedRevision))
        assertCatalogError(.staleCatalog(expected: revision, actual: nextRevision)) {
            try resolution.validate(against: changedRevision)
        }
    }

    func testPreCancelledConstructionQueriesPersistenceAndFreshnessReturnTypedError() async throws {
        let id = try SyntaxSchemeIdentifier("custom.cancel")
        let scheme = try makeScheme(id: id, name: "Cancel", languages: [.swift])
        let catalog = try SyntaxSchemeCatalog(customSchemes: [scheme])
        let selection = SyntaxSchemeSelection(selectedIdentifier: id)
        let data = try selection.encodedData()
        let resolution = try catalog.resolve(
            selection,
            language: .swift,
            mode: .textComparison
        )
        let operations: [(String, @Sendable () throws -> Void)] = [
            (
                "scheme construction",
                {
                    _ = try SyntaxScheme(
                        id: id,
                        displayName: "Cancelled",
                        supportedLanguages: [.swift]
                    )
                }
            ),
            ("catalog construction", { _ = try SyntaxSchemeCatalog(customSchemes: [scheme]) }),
            ("applicability query", { _ = try catalog.schemes(supporting: .swift, in: .textEditor) }),
            (
                "resolution",
                {
                    _ = try catalog.resolve(
                        selection,
                        language: .swift,
                        mode: .textComparison
                    )
                }
            ),
            ("encode", { _ = try selection.encodedData() }),
            ("decode", { _ = try SyntaxSchemeSelection.decode(from: data) }),
            ("restore", { _ = try SyntaxSchemeSelection.restored(from: data) }),
            ("freshness", { _ = try resolution.isCurrent(in: catalog) }),
            ("validation", { try resolution.validate(against: catalog) })
        ]

        for (name, operation) in operations {
            let error = await Task.detached { @Sendable () -> SyntaxSchemeCatalogError? in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    try operation()
                    return nil
                } catch let error as SyntaxSchemeCatalogError {
                    return error
                } catch {
                    return nil
                }
            }.value
            XCTAssertEqual(error, .cancelled, name)
        }
    }

    func testWorkLimitsBoundSchemeAndCatalogValidation() throws {
        let id = try SyntaxSchemeIdentifier("custom.work")
        let oneUnit = try limits(maximumWorkUnits: 1)

        assertCatalogError(.workLimitExceeded(maximumWorkUnits: 1)) {
            _ = try self.makeScheme(
                id: id,
                name: "Work",
                languages: [.swift],
                limits: oneUnit
            )
        }
        assertCatalogError(.workLimitExceeded(maximumWorkUnits: 1)) {
            _ = try SyntaxSchemeCatalog(limits: oneUnit)
        }
    }

    func testCustomSchemeCountLimitAcceptsExactMaximumAndRejectsOneOver() throws {
        let customSchemes = try (0..<3).map { index in
            try makeScheme(
                id: SyntaxSchemeIdentifier("custom.count-\(index)"),
                name: "Count \(index)",
                languages: [.swift]
            )
        }
        let countLimit = 2
        let countLimits = try limits(maximumCustomSchemeCount: countLimit)

        XCTAssertEqual(
            try SyntaxSchemeCatalog(
                customSchemes: Array(customSchemes.prefix(countLimit)),
                limits: countLimits
            ).schemes.count,
            SyntaxSchemeCatalog.builtInSchemes.count + countLimit
        )
        assertCatalogError(.tooManyCustomSchemes(maximum: countLimit)) {
            _ = try SyntaxSchemeCatalog(
                customSchemes: customSchemes,
                limits: countLimits
            )
        }
    }

    func testDuplicateScanAcceptsAllUniqueAtExactBudgetAndRejectsOneUnder() throws {
        let customSchemes = try ["alpha", "zulu"].map { suffix in
            try makeScheme(
                id: SyntaxSchemeIdentifier("custom.unique-\(suffix)"),
                name: "Unique \(suffix)",
                languages: [.swift]
            )
        }
        let schemeCount = SyntaxSchemeCatalog.builtInSchemes.count + customSchemes.count
        let exactWork =
            SyntaxSchemeCatalog.builtInSchemes.reduce(0) { $0 + validationWork(for: $1) }
            + customSchemes.reduce(0) { $0 + 1 + validationWork(for: $1) }
            + mergeSortWork(for: schemeCount)
            + schemeCount - 1

        XCTAssertNoThrow(
            try SyntaxSchemeCatalog(
                customSchemes: customSchemes,
                limits: limits(maximumWorkUnits: exactWork)
            )
        )
        assertCatalogError(.workLimitExceeded(maximumWorkUnits: exactWork - 1)) {
            _ = try SyntaxSchemeCatalog(
                customSchemes: customSchemes,
                limits: self.limits(maximumWorkUnits: exactWork - 1)
            )
        }
    }

    func testDuplicateScanConsumesBudgetBeforeReportingLateDuplicate() throws {
        let duplicateID = try SyntaxSchemeIdentifier("zz.duplicate")
        let first = try makeScheme(
            id: duplicateID,
            name: "First Duplicate",
            languages: [.swift]
        )
        let second = try makeScheme(
            id: duplicateID,
            name: "Second Duplicate",
            languages: [.json]
        )
        let customSchemes = [first, second]
        let schemeCount = SyntaxSchemeCatalog.builtInSchemes.count + customSchemes.count
        let workBeforeDuplicateScan =
            SyntaxSchemeCatalog.builtInSchemes.reduce(0) { $0 + validationWork(for: $1) }
            + customSchemes.reduce(0) { $0 + 1 + validationWork(for: $1) }
            + mergeSortWork(for: schemeCount)
        let comparisonsBeforeLateDuplicate = schemeCount - 2
        let insufficientWork = workBeforeDuplicateScan + comparisonsBeforeLateDuplicate
        let exactWork = insufficientWork + 1

        assertCatalogError(.workLimitExceeded(maximumWorkUnits: insufficientWork)) {
            _ = try SyntaxSchemeCatalog(
                customSchemes: customSchemes,
                limits: self.limits(maximumWorkUnits: insufficientWork)
            )
        }
        assertCatalogError(.duplicateSchemeIdentifier(duplicateID)) {
            _ = try SyntaxSchemeCatalog(
                customSchemes: customSchemes,
                limits: self.limits(maximumWorkUnits: exactWork)
            )
        }
    }

    private func makeScheme(
        id: SyntaxSchemeIdentifier,
        name: String,
        languages: [SyntaxHighlightingLanguage],
        modes: [SyntaxSchemeApplicationMode] = SyntaxSchemeApplicationMode.allCases,
        limits: SyntaxSchemeCatalogLimits = .default
    ) throws -> SyntaxScheme {
        try SyntaxScheme(
            id: id,
            displayName: name,
            supportedLanguages: languages,
            applicationModes: modes,
            limits: limits
        )
    }

    private func limits(
        maximumCustomSchemeCount: Int = SyntaxSchemeCatalogLimits.default.maximumCustomSchemeCount,
        maximumPersistenceBytes: Int = SyntaxSchemeCatalogLimits.default.maximumPersistenceBytes,
        maximumJSONDepth: Int = SyntaxSchemeCatalogLimits.default.maximumJSONDepth,
        maximumWorkUnits: Int = SyntaxSchemeCatalogLimits.default.maximumWorkUnits
    ) throws -> SyntaxSchemeCatalogLimits {
        try SyntaxSchemeCatalogLimits(
            maximumCustomSchemeCount: maximumCustomSchemeCount,
            maximumPersistenceBytes: maximumPersistenceBytes,
            maximumJSONDepth: maximumJSONDepth,
            maximumWorkUnits: maximumWorkUnits
        )
    }

    private func assertCatalogError(
        _ expected: SyntaxSchemeCatalogError,
        _ context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), context, file: file, line: line) { error in
            XCTAssertEqual(
                error as? SyntaxSchemeCatalogError,
                expected,
                context,
                file: file,
                line: line
            )
        }
    }

    private func validationWork(for scheme: SyntaxScheme) -> Int {
        scheme.id.rawValue.utf8.count + scheme.displayName.utf8.count + 1
            + scheme.supportedLanguages.count
            + scheme.applicationModes.count
            + scheme.colorRoleReferences.count
    }

    private func mergeSortWork(for count: Int) -> Int {
        guard count > 1 else { return 0 }
        var work = 0
        var width = 1
        while width < count {
            work += count
            width = width > count / 2 ? count : width * 2
        }
        return work
    }
}
