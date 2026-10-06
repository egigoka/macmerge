import Foundation
import MacMergeCore
import XCTest

private typealias Workflow = EditorPreferencesWorkflow

final class EditorPreferencesWorkflowTests: XCTestCase {
    func testPublicPageAndIntentContractsAreExact() throws {
        XCTAssertEqual(Workflow.currentPersistenceVersion, 1)
        XCTAssertEqual(Workflow.Page.allCases, [.general, .compareAndMerge, .syntax])
        XCTAssertEqual(Workflow.Page.allCases.map(\.rawValue), ["general", "compareAndMerge", "syntax"])
        XCTAssertEqual(Workflow.TabInsertion.allCases, [.tabs, .spaces])
        XCTAssertEqual(
            Workflow.SelectedDifferenceCopyGranularity.allCases,
            [.difference, .inlineDifference, .line, .character]
        )
        XCTAssertEqual(Workflow.LineDifferenceGranularity.allCases, [.character, .word])
        XCTAssertEqual(Workflow.WordBreakMode.allCases, [.whitespace, .whitespaceOrCustomCharacters])

        let intents: [(Workflow.Intent, Workflow.IntentKind, Workflow.Page?)] = [
            (.setDisplay(.default), .setDisplay, .general),
            (.setView(.default), .setView, .general),
            (.setEditing(.default), .setEditing, .general),
            (.setCompareAndMerge(.default), .setCompareAndMerge, .compareAndMerge),
            (.setSyntax(.default), .setSyntax, .syntax),
            (.setColorScheme(.default), .setColorScheme, .syntax),
            (.reset(.general), .reset, .general),
            (.reset(.compareAndMerge), .reset, .compareAndMerge),
            (.reset(.syntax), .reset, .syntax),
            (.resetAll, .resetAll, nil)
        ]
        for (intent, kind, page) in intents {
            XCTAssertEqual(intent.kind, kind)
            XCTAssertEqual(intent.page, page)
        }
        XCTAssertEqual(
            Workflow.IntentKind.allCases,
            [
                .setDisplay, .setView, .setEditing, .setCompareAndMerge, .setSyntax,
                .setColorScheme, .reset, .resetAll
            ]
        )
        XCTAssertEqual(
            Workflow.Limit.allCases,
            [
                .persistenceBytes, .colorSchemeCount, .persistenceItemCount, .jsonDepth,
                .stringUTF8Bytes, .totalStringUTF8Bytes, .workUnits, .cancellationCheckInterval
            ]
        )
        XCTAssertEqual(
            Workflow.StringField.allCases,
            [
                .fontFamily, .wordBreakCharacters, .syntaxSchemeIdentifier,
                .colorSchemeIdentifier, .colorSchemeDisplayName, .colorToken
            ]
        )
        XCTAssertEqual(SyntaxHighlightingLanguage.allCases, [.plainText, .swift, .cLike, .json, .markdown])
        XCTAssertEqual(SyntaxSchemeOrigin.allCases, [.builtIn, .custom])
        XCTAssertEqual(
            SyntaxSchemeApplicationMode.allCases,
            [.textComparison, .threeWayTextComparison, .conflictComparison, .textEditor]
        )
        XCTAssertEqual(
            SyntaxSchemeSelectionRejection.allCases,
            [.unavailable, .unsupportedLanguage, .unsupportedMode]
        )
        XCTAssertEqual(
            SyntaxSchemeResolutionSource.allCases,
            [.selected, .explicitFallback, .languageDefault]
        )
        XCTAssertEqual(MergeCommandPolicy.Side.allCases, [.left, .middle, .right])
        XCTAssertEqual(EditorBuiltInColorScheme.allCases, [.standard, .monochrome])
    }

    func testEveryMirroredDisplayAndViewLeafMustAgree() throws {
        let display = try customDisplay()
        let matching = EditorViewPolicy(locksPanes: true, displayPreferences: display)

        XCTAssertEqual(matching.showsWhitespace, display.showsWhitespace)
        XCTAssertEqual(matching.showsEndOfLineMarkers, display.showsEndOfLineMarkers)
        XCTAssertEqual(matching.showsLineDifferences, display.showsLineDifferences)
        XCTAssertEqual(matching.showsLineNumbers, display.showsLineNumbers)
        XCTAssertEqual(matching.showsMargins, display.showsMargins)
        XCTAssertEqual(matching.showsTopMargins, display.showsTopMargin)
        XCTAssertEqual(matching.wrapsLines, display.wrapsLines)

        let mismatches: [(String, EditorViewPolicy)] = [
            (
                "showsWhitespace",
                EditorViewPolicy(
                    locksPanes: true,
                    showsWhitespace: false,
                    showsEndOfLineMarkers: true,
                    showsLineDifferences: false,
                    showsLineNumbers: true,
                    showsMargins: true,
                    showsTopMargins: true,
                    wrapsLines: true
                )
            ),
            (
                "showsEndOfLineMarkers",
                EditorViewPolicy(
                    locksPanes: true,
                    showsWhitespace: true,
                    showsEndOfLineMarkers: false,
                    showsLineDifferences: false,
                    showsLineNumbers: true,
                    showsMargins: true,
                    showsTopMargins: true,
                    wrapsLines: true
                )
            ),
            (
                "showsLineDifferences",
                EditorViewPolicy(
                    locksPanes: true,
                    showsWhitespace: true,
                    showsEndOfLineMarkers: true,
                    showsLineDifferences: true,
                    showsLineNumbers: true,
                    showsMargins: true,
                    showsTopMargins: true,
                    wrapsLines: true
                )
            ),
            (
                "showsLineNumbers",
                EditorViewPolicy(
                    locksPanes: true,
                    showsWhitespace: true,
                    showsEndOfLineMarkers: true,
                    showsLineDifferences: false,
                    showsLineNumbers: false,
                    showsMargins: true,
                    showsTopMargins: true,
                    wrapsLines: true
                )
            ),
            (
                "showsMargins",
                EditorViewPolicy(
                    locksPanes: true,
                    showsWhitespace: true,
                    showsEndOfLineMarkers: true,
                    showsLineDifferences: false,
                    showsLineNumbers: true,
                    showsMargins: false,
                    showsTopMargins: true,
                    wrapsLines: true
                )
            ),
            (
                "showsTopMargin",
                EditorViewPolicy(
                    locksPanes: true,
                    showsWhitespace: true,
                    showsEndOfLineMarkers: true,
                    showsLineDifferences: false,
                    showsLineNumbers: true,
                    showsMargins: true,
                    showsTopMargins: false,
                    wrapsLines: true
                )
            ),
            (
                "wrapsLines",
                EditorViewPolicy(
                    locksPanes: true,
                    showsWhitespace: true,
                    showsEndOfLineMarkers: true,
                    showsLineDifferences: false,
                    showsLineNumbers: true,
                    showsMargins: true,
                    showsTopMargins: true,
                    wrapsLines: false
                )
            )
        ]
        for (leaf, view) in mismatches {
            assertWorkflowError(.inconsistentDisplayAndViewState, leaf) {
                _ = try Workflow.State(
                    revision: Workflow.Revision(lineage: 1, generation: 0),
                    display: display,
                    view: view
                )
            }
        }
    }

    func testDefaultsUseFreshNonzeroLineageAndExactSettings() throws {
        let first = try Workflow.State.defaults()

        XCTAssertNotEqual(first.revision.lineage, 0)
        XCTAssertEqual(first.revision.generation, 0)
        XCTAssertEqual(first.display, .default)
        XCTAssertEqual(first.view, .default)
        XCTAssertEqual(first.editing, .default)
        XCTAssertEqual(first.compareAndMerge, .default)
        XCTAssertEqual(first.syntax, .default)
        XCTAssertEqual(first.colorScheme, .default)
        XCTAssertEqual(first.limits, .default)
        XCTAssertTrue(first.display.font.usesSystemMonospacedFont)
        XCTAssertEqual(first.display.font.pointSize, 12)
        XCTAssertEqual(first.display.zoomStep, 10)
        XCTAssertEqual(first.display.syntaxHighlightingLanguage, .plainText)
        XCTAssertFalse(first.display.showsWhitespace)
        XCTAssertFalse(first.display.showsEndOfLineMarkers)
        XCTAssertTrue(first.display.showsLineDifferences)
        XCTAssertFalse(first.display.showsLineNumbers)
        XCTAssertFalse(first.display.showsMargins)
        XCTAssertFalse(first.display.showsTopMargin)
        XCTAssertFalse(first.display.wrapsLines)
        XCTAssertFalse(first.view.locksPanes)
        XCTAssertEqual(first.editing.tabWidth, 4)
        XCTAssertEqual(first.editing.tabInsertion, .tabs)
        XCTAssertFalse(first.compareAndMerge.automaticRescanAfterEdit)
        XCTAssertEqual(first.compareAndMerge.copyGranularity, .character)
        XCTAssertEqual(first.compareAndMerge.lineDifferenceGranularity, .word)
        XCTAssertEqual(first.compareAndMerge.wordBreakMode, .whitespace)
        XCTAssertEqual(first.compareAndMerge.wordBreakCharacters, "")
        XCTAssertEqual(first.compareAndMerge.automaticMergeDestination, .middle)
        XCTAssertTrue(first.syntax.isHighlightingEnabled)
        XCTAssertNil(first.syntax.selection.selectedIdentifier)
        XCTAssertNil(first.syntax.selection.fallbackIdentifier)
        XCTAssertEqual(first.colorScheme.selectedIdentifier.rawValue, "macmerge.standard")
        XCTAssertNoThrow(try first.validate())

        let explicit = try Workflow.State.defaults(lineage: 41)
        XCTAssertEqual(explicit.revision, Workflow.Revision(lineage: 41, generation: 0))
        assertWorkflowError(.invalidLineage) {
            _ = try Workflow.State(
                revision: Workflow.Revision(lineage: 0, generation: 0),
                display: .default,
                locksPanes: false
            )
        }
        assertWorkflowError(.inconsistentDisplayAndViewState) {
            _ = try Workflow.State(
                revision: Workflow.Revision(lineage: 1, generation: 0),
                display: .default,
                view: EditorViewPolicy(showsWhitespace: true)
            )
        }
    }

    func testEditingPreferencesEnforceExactBoundsAndDefaults() throws {
        XCTAssertEqual(Workflow.EditingPreferences.minimumTabWidth, 1)
        XCTAssertEqual(Workflow.EditingPreferences.maximumTabWidth, 64)
        XCTAssertEqual(Workflow.EditingPreferences.default.tabWidth, 4)
        XCTAssertEqual(Workflow.EditingPreferences.default.tabInsertion, .tabs)

        let minimum = try Workflow.EditingPreferences(tabWidth: 1, tabInsertion: .tabs)
        let maximum = try Workflow.EditingPreferences(tabWidth: 64, tabInsertion: .spaces)
        XCTAssertEqual(minimum.tabWidth, 1)
        XCTAssertEqual(maximum.tabWidth, 64)
        XCTAssertEqual(maximum.tabInsertion, .spaces)
        for width in [Int.min, 0, 65, Int.max] {
            assertWorkflowError(.invalidTabWidth(width)) {
                _ = try Workflow.EditingPreferences(tabWidth: width)
            }
        }
        assertWorkflowError(.invalidTabWidth(0)) {
            _ = try JSONDecoder().decode(
                Workflow.EditingPreferences.self,
                from: Data(#"{"tabWidth":0,"tabInsertion":"tabs"}"#.utf8)
            )
        }
    }

    func testCompareAndMergePreferencesNormalizeAndValidateStrings() throws {
        let decomposed = "e\u{301}/:;"
        let preferences = try Workflow.CompareAndMergePreferences(
            automaticRescanAfterEdit: true,
            copyGranularity: .inlineDifference,
            lineDifferenceGranularity: .character,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: decomposed,
            automaticMergeDestination: .right
        )

        XCTAssertEqual(preferences.wordBreakCharacters, "é/:;")
        XCTAssertEqual(preferences.automaticRescanAfterEdit, true)
        XCTAssertEqual(preferences.copyGranularity, .inlineDifference)
        XCTAssertEqual(preferences.lineDifferenceGranularity, .character)
        XCTAssertEqual(preferences.wordBreakMode, .whitespaceOrCustomCharacters)
        XCTAssertEqual(preferences.automaticMergeDestination, .right)
        XCTAssertEqual(Workflow.CompareAndMergePreferences.default.wordBreakCharacters, "")
        XCTAssertEqual(Workflow.CompareAndMergePreferences.default.automaticMergeDestination, .middle)

        assertWorkflowError(.inconsistentWordBreakCharacters) {
            _ = try Workflow.CompareAndMergePreferences(
                wordBreakMode: .whitespace,
                wordBreakCharacters: ";"
            )
        }
        for invalid in ["line\nbreak", "\u{0000}", "\u{202E}"] {
            assertWorkflowError(.invalidString(field: .wordBreakCharacters)) {
                _ = try Workflow.CompareAndMergePreferences(
                    wordBreakMode: .whitespaceOrCustomCharacters,
                    wordBreakCharacters: invalid
                )
            }
        }
        assertWorkflowError(
            .stringTooLarge(
                field: .wordBreakCharacters,
                maximumUTF8Bytes: Workflow.Limits.hardMaximumStringUTF8Bytes
            )
        ) {
            _ = try Workflow.CompareAndMergePreferences(
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: String(
                    repeating: "x",
                    count: Workflow.Limits.hardMaximumStringUTF8Bytes + 1
                )
            )
        }
    }

    func testColorSchemeIdentifierAcceptsColonSlashAndPortableGrammar() throws {
        let punctuation = try Workflow.ColorSchemeIdentifier("A0-._/:z9")
        XCTAssertEqual(punctuation.rawValue, "A0-._/:z9")
        XCTAssertEqual(Workflow.ColorSchemeIdentifier.standard.rawValue, "macmerge.standard")
        XCTAssertEqual(Workflow.ColorSchemeIdentifier.monochrome.rawValue, "macmerge.monochrome")
        XCTAssertEqual(Workflow.ColorSchemeIdentifier.maximumUTF8Bytes, 128)

        let exact = String(repeating: "a", count: Workflow.ColorSchemeIdentifier.maximumUTF8Bytes)
        XCTAssertEqual(try Workflow.ColorSchemeIdentifier(exact).rawValue, exact)
        for invalid in ["", "-a", "a-", "/a", "a/", ":a", "a:", ".", "a b", "a@b", "a\\b", "é"] {
            assertWorkflowError(.invalidString(field: .colorSchemeIdentifier), invalid) {
                _ = try Workflow.ColorSchemeIdentifier(invalid)
            }
        }
        assertWorkflowError(
            .stringTooLarge(
                field: .colorSchemeIdentifier,
                maximumUTF8Bytes: Workflow.ColorSchemeIdentifier.maximumUTF8Bytes
            )
        ) {
            _ = try Workflow.ColorSchemeIdentifier(exact + "a")
        }

        let custom = try makeColorScheme(identifier: "vendor:theme/dark", displayName: "Vendor Dark")
        let selection = try Workflow.ColorSchemeSelection(selectedScheme: custom)
        XCTAssertEqual(selection.selectedIdentifier.rawValue, "vendor:theme/dark")
    }

    func testSyntaxSchemeIdentifierGrammarAndStrictDecodeBoundaries() throws {
        XCTAssertEqual(SyntaxSchemeIdentifier.maximumUTF8Bytes, 128)
        XCTAssertEqual(try SyntaxSchemeIdentifier("A0-._z9").rawValue, "A0-._z9")
        let exact = String(repeating: "a", count: SyntaxSchemeIdentifier.maximumUTF8Bytes)
        XCTAssertEqual(try SyntaxSchemeIdentifier(exact).rawValue, exact)

        for invalid in [
            "", "-a", "a-", ".a", "a.", "_a", "a_", "a/b", "a:b", "a b", "a@b",
            "a\\b", "é"
        ] {
            assertSyntaxCatalogError(.invalidIdentifier, invalid) {
                _ = try SyntaxSchemeIdentifier(invalid)
            }
        }
        assertSyntaxCatalogError(
            .identifierTooLarge(maximumUTF8Bytes: SyntaxSchemeIdentifier.maximumUTF8Bytes)
        ) {
            _ = try SyntaxSchemeIdentifier(exact + "a")
        }

        let valid = SyntaxSchemeSelection(
            selectedIdentifier: try SyntaxSchemeIdentifier(exact),
            fallbackIdentifier: try SyntaxSchemeIdentifier("A0-._z9")
        )
        XCTAssertEqual(try SyntaxSchemeSelection.decode(from: valid.encodedData()), valid)

        let invalidIdentifiers = ["-a", "a-", "a/b", "a:b", "a b", "é", exact + "a"]
        for identifier in invalidIdentifiers {
            let encodedIdentifier = identifier == "é" ? #"\u00E9"# : identifier
            let payload = Data(
                (#"{"fallbackIdentifier":null,"schemaVersion":1,"selectedIdentifier":""#
                    + encodedIdentifier
                    + #""}"#).utf8
            )
            let expected: SyntaxSchemeCatalogError =
                identifier.utf8.count > SyntaxSchemeIdentifier.maximumUTF8Bytes
                ? .identifierTooLarge(maximumUTF8Bytes: SyntaxSchemeIdentifier.maximumUTF8Bytes)
                : .invalidIdentifier
            assertSyntaxCatalogError(expected, identifier) {
                _ = try SyntaxSchemeSelection.decode(from: payload)
            }
        }
    }

    func testColorCatalogSortsLooksUpAndRejectsInvalidStructure() throws {
        let zulu = try makeColorScheme(identifier: "zulu/theme", displayName: "Zulu")
        let alpha = try makeColorScheme(identifier: "alpha:theme", displayName: "Alpha")
        let revision = SyntaxSchemeCatalogRevision(lineage: 7, generation: 3)
        let catalog = try Workflow.ColorSchemeCatalog(
            revision: revision,
            schemes: [zulu, EditorColorScheme.standard, alpha]
        )

        XCTAssertEqual(catalog.revision, revision)
        XCTAssertEqual(
            catalog.schemes.map(\.identifier),
            ["alpha:theme", "macmerge.standard", "zulu/theme"]
        )
        XCTAssertEqual(
            catalog.scheme(with: try Workflow.ColorSchemeIdentifier("alpha:theme")),
            alpha
        )
        XCTAssertNil(catalog.scheme(with: try Workflow.ColorSchemeIdentifier("missing/theme")))

        assertWorkflowError(.invalidLineage) {
            _ = try Workflow.ColorSchemeCatalog(
                revision: SyntaxSchemeCatalogRevision(lineage: 0, generation: 0)
            )
        }
        assertWorkflowError(.duplicateColorSchemeIdentifier) {
            _ = try Workflow.ColorSchemeCatalog(
                revision: revision,
                schemes: [EditorColorScheme.standard, EditorColorScheme.standard]
            )
        }
        let oneScheme = makeLimits(maximumColorSchemeCount: 1)
        assertWorkflowError(.tooManyColorSchemes(maximum: 1)) {
            _ = try Workflow.ColorSchemeCatalog(
                revision: revision,
                schemes: [EditorColorScheme.standard, EditorColorScheme.monochrome],
                limits: oneScheme
            )
        }
    }

    func testResolveUsesExactSelectedSyntaxAndColorSchemes() throws {
        let catalogs = try makeCatalogs()
        let state = try makeCustomizedState(catalogs: catalogs)
        let resolved = try Workflow.resolve(
            state,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        XCTAssertEqual(resolved.syntax?.scheme, catalogs.selectedSyntax)
        XCTAssertEqual(resolved.syntax?.source, .selected)
        XCTAssertNil(resolved.syntax?.selectedRejection)
        XCTAssertEqual(resolved.syntax?.requestedLanguage, .swift)
        XCTAssertEqual(resolved.syntax?.applicationMode, .textComparison)
        XCTAssertEqual(resolved.color, catalogs.customColor)
        XCTAssertNoThrow(
            try resolved.validate(
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        )
    }

    func testResolveUsesSyntaxFallbackAndDeterministicColorFallbacks() throws {
        let selectedID = try SyntaxSchemeIdentifier("custom.editor-only")
        let fallbackID = try SyntaxSchemeIdentifier("custom.fallback")
        let selected = try makeSyntaxScheme(
            id: selectedID,
            name: "Editor Only",
            modes: [.textEditor]
        )
        let fallback = try makeSyntaxScheme(id: fallbackID, name: "Fallback")
        let syntaxCatalog = try SyntaxSchemeCatalog(
            customSchemes: [selected, fallback],
            revision: SyntaxSchemeCatalogRevision(lineage: 8, generation: 1)
        )
        let customColor = try makeColorScheme(identifier: "fallback/custom", displayName: "Custom")
        let standardCatalog = try Workflow.ColorSchemeCatalog(
            revision: SyntaxSchemeCatalogRevision(lineage: 9, generation: 1),
            schemes: [customColor, EditorColorScheme.standard]
        )
        let missingColor = try Workflow.ColorSchemeIdentifier("missing/color")
        let state = try makeState(
            display: customDisplay(),
            syntax: Workflow.SyntaxPreferences(
                selection: SyntaxSchemeSelection(
                    selectedIdentifier: selectedID,
                    fallbackIdentifier: fallbackID
                )
            ),
            colorScheme: Workflow.ColorSchemeSelection(selectedIdentifier: missingColor)
        )
        let standardFallback = try Workflow.resolve(
            state,
            syntaxCatalog: syntaxCatalog,
            colorCatalog: standardCatalog
        )

        XCTAssertEqual(standardFallback.syntax?.scheme, fallback)
        XCTAssertEqual(standardFallback.syntax?.source, .explicitFallback)
        XCTAssertEqual(standardFallback.syntax?.selectedRejection, .unsupportedMode)
        XCTAssertEqual(standardFallback.color, .standard)

        let firstOnlyCatalog = try Workflow.ColorSchemeCatalog(
            revision: SyntaxSchemeCatalogRevision(lineage: 9, generation: 2),
            schemes: [customColor]
        )
        XCTAssertEqual(
            try Workflow.resolve(
                state,
                syntaxCatalog: syntaxCatalog,
                colorCatalog: firstOnlyCatalog
            ).color,
            customColor
        )
        let emptyCatalog = try Workflow.ColorSchemeCatalog(
            revision: SyntaxSchemeCatalogRevision(lineage: 9, generation: 3),
            schemes: []
        )
        assertWorkflowError(.missingColorScheme) {
            _ = try Workflow.resolve(
                state,
                syntaxCatalog: syntaxCatalog,
                colorCatalog: emptyCatalog
            )
        }
    }

    func testResolveCoversSyntaxFallbackMatrixAndMultipleCustomColorOrder() throws {
        let applicableSelected = try makeSyntaxScheme(
            id: SyntaxSchemeIdentifier("matrix.selected"),
            name: "Selected"
        )
        let languageMismatch = try SyntaxScheme(
            id: SyntaxSchemeIdentifier("matrix.language"),
            displayName: "Language",
            supportedLanguages: [.json],
            applicationModes: [.textComparison]
        )
        let modeMismatch = try makeSyntaxScheme(
            id: SyntaxSchemeIdentifier("matrix.mode"),
            name: "Mode",
            modes: [.textEditor]
        )
        let applicableFallback = try makeSyntaxScheme(
            id: SyntaxSchemeIdentifier("matrix.fallback"),
            name: "Fallback"
        )
        let missing = try SyntaxSchemeIdentifier("matrix.missing")
        let syntaxCatalog = try SyntaxSchemeCatalog(
            customSchemes: [modeMismatch, applicableFallback, languageMismatch, applicableSelected],
            revision: SyntaxSchemeCatalogRevision(lineage: 80, generation: 4)
        )
        let firstColor = try makeColorScheme(identifier: "alpha/custom", displayName: "Alpha")
        let secondColor = try makeColorScheme(identifier: "zulu/custom", displayName: "Zulu")
        let colorCatalog = try Workflow.ColorSchemeCatalog(
            revision: SyntaxSchemeCatalogRevision(lineage: 81, generation: 5),
            schemes: [secondColor, firstColor]
        )

        let cases:
            [(
                String,
                SyntaxSchemeSelection,
                SyntaxScheme,
                SyntaxSchemeResolutionSource,
                SyntaxSchemeSelectionRejection?,
                SyntaxSchemeSelectionRejection?
            )] = [
                (
                    "selected",
                    SyntaxSchemeSelection(
                        selectedIdentifier: applicableSelected.id,
                        fallbackIdentifier: applicableFallback.id
                    ),
                    applicableSelected,
                    .selected,
                    nil,
                    nil
                ),
                (
                    "missing selected",
                    SyntaxSchemeSelection(
                        selectedIdentifier: missing,
                        fallbackIdentifier: applicableFallback.id
                    ),
                    applicableFallback,
                    .explicitFallback,
                    .unavailable,
                    nil
                ),
                (
                    "language-mismatched selected",
                    SyntaxSchemeSelection(
                        selectedIdentifier: languageMismatch.id,
                        fallbackIdentifier: applicableFallback.id
                    ),
                    applicableFallback,
                    .explicitFallback,
                    .unsupportedLanguage,
                    nil
                ),
                (
                    "mode-mismatched selected",
                    SyntaxSchemeSelection(
                        selectedIdentifier: modeMismatch.id,
                        fallbackIdentifier: applicableFallback.id
                    ),
                    applicableFallback,
                    .explicitFallback,
                    .unsupportedMode,
                    nil
                ),
                (
                    "missing both",
                    SyntaxSchemeSelection(selectedIdentifier: missing, fallbackIdentifier: missing),
                    try XCTUnwrap(syntaxCatalog.scheme(withIdentifier: .builtInSwift)),
                    .languageDefault,
                    .unavailable,
                    .unavailable
                ),
                (
                    "unsupported fallback language",
                    SyntaxSchemeSelection(
                        selectedIdentifier: missing,
                        fallbackIdentifier: languageMismatch.id
                    ),
                    try XCTUnwrap(syntaxCatalog.scheme(withIdentifier: .builtInSwift)),
                    .languageDefault,
                    .unavailable,
                    .unsupportedLanguage
                ),
                (
                    "unsupported fallback mode",
                    SyntaxSchemeSelection(
                        selectedIdentifier: missing,
                        fallbackIdentifier: modeMismatch.id
                    ),
                    try XCTUnwrap(syntaxCatalog.scheme(withIdentifier: .builtInSwift)),
                    .languageDefault,
                    .unavailable,
                    .unsupportedMode
                ),
                (
                    "no identifiers",
                    .none,
                    try XCTUnwrap(syntaxCatalog.scheme(withIdentifier: .builtInSwift)),
                    .languageDefault,
                    nil,
                    nil
                )
            ]

        for (name, selection, scheme, source, selectedRejection, fallbackRejection) in cases {
            let state = try makeState(
                display: customDisplay(),
                syntax: Workflow.SyntaxPreferences(selection: selection),
                colorScheme: Workflow.ColorSchemeSelection(
                    selectedIdentifier: Workflow.ColorSchemeIdentifier("missing/color")
                )
            )
            let resolved = try Workflow.resolve(
                state,
                syntaxCatalog: syntaxCatalog,
                colorCatalog: colorCatalog
            )
            XCTAssertEqual(resolved.syntax?.scheme, scheme, name)
            XCTAssertEqual(resolved.syntax?.source, source, name)
            XCTAssertEqual(resolved.syntax?.selectedRejection, selectedRejection, name)
            XCTAssertEqual(resolved.syntax?.fallbackRejection, fallbackRejection, name)
            XCTAssertEqual(resolved.color, firstColor, name)
        }

        XCTAssertEqual(colorCatalog.schemes, [firstColor, secondColor])
        let reversedColorCatalog = try Workflow.ColorSchemeCatalog(
            revision: colorCatalog.revision,
            schemes: [firstColor, secondColor]
        )
        let missingColorState = try makeState(
            syntax: Workflow.SyntaxPreferences(isHighlightingEnabled: false),
            colorScheme: Workflow.ColorSchemeSelection(
                selectedIdentifier: Workflow.ColorSchemeIdentifier("missing/color")
            )
        )
        XCTAssertEqual(
            try Workflow.resolve(
                missingColorState,
                syntaxCatalog: syntaxCatalog,
                colorCatalog: reversedColorCatalog
            ).color,
            firstColor
        )
    }

    func testResolveDisablesSyntaxWithoutResolvingInvalidSelection() throws {
        let catalogs = try makeCatalogs()
        let state = try makeState(
            display: customDisplay(),
            syntax: Workflow.SyntaxPreferences(
                isHighlightingEnabled: false,
                selection: SyntaxSchemeSelection(
                    selectedIdentifier: try SyntaxSchemeIdentifier("unavailable.selected"),
                    fallbackIdentifier: try SyntaxSchemeIdentifier("unavailable.fallback")
                )
            ),
            colorScheme: Workflow.ColorSchemeSelection(
                selectedIdentifier: try Workflow.ColorSchemeIdentifier(catalogs.customColor.identifier)
            )
        )

        let resolved = try Workflow.resolve(
            state,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        XCTAssertNil(resolved.syntax)
        XCTAssertEqual(resolved.color, catalogs.customColor)
    }

    func testGeneralSettingPlansMutateOnlyExactOwnedSettings() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let display = EditorDisplayPreferences.default

        let displayPlan = try plan(.setDisplay(display), current: current, catalogs: catalogs)
        XCTAssertEqual(displayPlan.successor.display, display)
        XCTAssertEqual(
            displayPlan.successor.view,
            EditorViewPolicy(locksPanes: current.view.locksPanes, displayPreferences: display)
        )
        XCTAssertEqual(displayPlan.successor.editing, current.editing)
        assertUntouchedNonGeneralSettings(displayPlan.successor, equalTo: current)
        XCTAssertEqual(displayPlan.successor.limits, current.limits)
        XCTAssertEqual(displayPlan.receipt.changedPages, [.general])

        let view = EditorViewPolicy.default
        let viewPlan = try plan(.setView(view), current: current, catalogs: catalogs)
        XCTAssertEqual(viewPlan.successor.view, view)
        XCTAssertEqual(viewPlan.successor.display, view.applying(to: current.display))
        XCTAssertEqual(viewPlan.successor.display.font, current.display.font)
        XCTAssertEqual(viewPlan.successor.display.zoomStep, current.display.zoomStep)
        XCTAssertEqual(
            viewPlan.successor.display.syntaxHighlightingLanguage,
            current.display.syntaxHighlightingLanguage
        )
        XCTAssertEqual(viewPlan.successor.editing, current.editing)
        assertUntouchedNonGeneralSettings(viewPlan.successor, equalTo: current)
        XCTAssertEqual(viewPlan.successor.limits, current.limits)
        XCTAssertEqual(viewPlan.receipt.changedPages, [.general])

        let editing = try Workflow.EditingPreferences(tabWidth: 2, tabInsertion: .tabs)
        let editingPlan = try plan(.setEditing(editing), current: current, catalogs: catalogs)
        XCTAssertEqual(editingPlan.successor.editing, editing)
        XCTAssertEqual(editingPlan.successor.display, current.display)
        XCTAssertEqual(editingPlan.successor.view, current.view)
        assertUntouchedNonGeneralSettings(editingPlan.successor, equalTo: current)
        XCTAssertEqual(editingPlan.successor.limits, current.limits)
        XCTAssertEqual(editingPlan.receipt.changedPages, [.general])
        XCTAssertEqual(
            try Workflow.decode(from: persistenceData(from: editingPlan.persistence)),
            editingPlan.successor
        )
    }

    func testCompareSyntaxAndColorPlansIntegrateExactValuesAndEffects() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let compare = Workflow.CompareAndMergePreferences.default
        let comparePlan = try plan(
            .setCompareAndMerge(compare),
            current: current,
            catalogs: catalogs
        )
        XCTAssertEqual(comparePlan.successor.compareAndMerge, compare)
        XCTAssertEqual(comparePlan.receipt.changedPages, [.compareAndMerge])
        XCTAssertEqual(comparePlan.successor.display, current.display)
        XCTAssertEqual(comparePlan.successor.view, current.view)
        XCTAssertEqual(comparePlan.successor.editing, current.editing)
        XCTAssertEqual(comparePlan.successor.syntax, current.syntax)
        XCTAssertEqual(comparePlan.successor.colorScheme, current.colorScheme)
        XCTAssertEqual(comparePlan.successor.limits, current.limits)

        let syntax = Workflow.SyntaxPreferences(
            isHighlightingEnabled: false,
            selection: current.syntax.selection
        )
        let syntaxPlan = try plan(.setSyntax(syntax), current: current, catalogs: catalogs)
        XCTAssertEqual(syntaxPlan.successor.syntax, syntax)
        XCTAssertNil(syntaxPlan.resolvedSchemes.syntax)
        XCTAssertEqual(syntaxPlan.receipt.changedPages, [.syntax])
        XCTAssertEqual(syntaxPlan.successor.display, current.display)
        XCTAssertEqual(syntaxPlan.successor.view, current.view)
        XCTAssertEqual(syntaxPlan.successor.editing, current.editing)
        XCTAssertEqual(syntaxPlan.successor.compareAndMerge, current.compareAndMerge)
        XCTAssertEqual(syntaxPlan.successor.colorScheme, current.colorScheme)
        XCTAssertEqual(syntaxPlan.successor.limits, current.limits)

        let colorSelection = Workflow.ColorSchemeSelection.default
        let colorPlan = try plan(
            .setColorScheme(colorSelection),
            current: current,
            catalogs: catalogs
        )
        XCTAssertEqual(colorPlan.successor.colorScheme, colorSelection)
        XCTAssertEqual(colorPlan.resolvedSchemes.color, .standard)
        XCTAssertEqual(colorPlan.receipt.changedPages, [.syntax])
        XCTAssertEqual(colorPlan.successor.display, current.display)
        XCTAssertEqual(colorPlan.successor.view, current.view)
        XCTAssertEqual(colorPlan.successor.editing, current.editing)
        XCTAssertEqual(colorPlan.successor.compareAndMerge, current.compareAndMerge)
        XCTAssertEqual(colorPlan.successor.syntax, current.syntax)
        XCTAssertEqual(colorPlan.successor.limits, current.limits)

        guard case .apply(let appliedState, let appliedSchemes) = colorPlan.application else {
            return XCTFail("Expected apply effect")
        }
        XCTAssertEqual(appliedState, colorPlan.successor)
        XCTAssertEqual(appliedSchemes, colorPlan.resolvedSchemes)
        XCTAssertEqual(
            try Workflow.decode(from: persistenceData(from: colorPlan.persistence)),
            colorPlan.successor
        )
    }

    func testPageResetsAndResetAllAreIsolatedAndComplete() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)

        let generalPlan = try plan(.reset(.general), current: current, catalogs: catalogs)
        let general = generalPlan.successor
        XCTAssertEqual(general.display, .default)
        XCTAssertEqual(general.view, .default)
        XCTAssertEqual(general.editing, .default)
        XCTAssertEqual(general.compareAndMerge, current.compareAndMerge)
        XCTAssertEqual(general.syntax, current.syntax)
        XCTAssertEqual(general.colorScheme, current.colorScheme)
        XCTAssertEqual(general.limits, current.limits)
        XCTAssertEqual(generalPlan.receipt.changedPages, [.general])

        let comparePlan = try plan(
            .reset(.compareAndMerge),
            current: current,
            catalogs: catalogs
        )
        let compare = comparePlan.successor
        XCTAssertEqual(compare.compareAndMerge, .default)
        XCTAssertEqual(compare.display, current.display)
        XCTAssertEqual(compare.view, current.view)
        XCTAssertEqual(compare.editing, current.editing)
        XCTAssertEqual(compare.syntax, current.syntax)
        XCTAssertEqual(compare.colorScheme, current.colorScheme)
        XCTAssertEqual(compare.limits, current.limits)
        XCTAssertEqual(comparePlan.receipt.changedPages, [.compareAndMerge])

        let syntaxPlan = try plan(.reset(.syntax), current: current, catalogs: catalogs)
        let syntax = syntaxPlan.successor
        XCTAssertEqual(syntax.syntax, .default)
        XCTAssertEqual(syntax.colorScheme, .default)
        XCTAssertEqual(syntax.display, current.display)
        XCTAssertEqual(syntax.view, current.view)
        XCTAssertEqual(syntax.editing, current.editing)
        XCTAssertEqual(syntax.compareAndMerge, current.compareAndMerge)
        XCTAssertEqual(syntax.limits, current.limits)
        XCTAssertEqual(syntaxPlan.receipt.changedPages, [.syntax])

        let allPlan = try plan(.resetAll, current: current, catalogs: catalogs)
        let all = allPlan.successor
        XCTAssertEqual(all.display, .default)
        XCTAssertEqual(all.view, .default)
        XCTAssertEqual(all.editing, .default)
        XCTAssertEqual(all.compareAndMerge, .default)
        XCTAssertEqual(all.syntax, .default)
        XCTAssertEqual(all.colorScheme, .default)
        XCTAssertEqual(all.limits, current.limits)
        XCTAssertEqual(all.revision.lineage, current.revision.lineage)
        XCTAssertEqual(all.revision.generation, current.revision.generation + 1)
        XCTAssertEqual(allPlan.receipt.changedPages, [.general, .compareAndMerge, .syntax])
    }

    func testNoChangeAndRevisionExhaustionFailBeforeProducingPlan() throws {
        let catalogs = try makeCatalogs()
        let current = try Workflow.State.defaults(lineage: 77)
        let noChanges: [Workflow.Intent] = [
            .setDisplay(current.display),
            .setView(current.view),
            .setEditing(current.editing),
            .setCompareAndMerge(current.compareAndMerge),
            .setSyntax(current.syntax),
            .setColorScheme(current.colorScheme),
            .reset(.general),
            .reset(.compareAndMerge),
            .reset(.syntax),
            .resetAll
        ]
        for intent in noChanges {
            assertWorkflowError(.noChanges, intent.kind.rawValue) {
                _ = try self.plan(intent, current: current, catalogs: catalogs)
            }
        }

        let exhausted = try makeState(
            revision: Workflow.Revision(lineage: 77, generation: UInt64.max)
        )
        assertWorkflowError(.revisionExhausted(lineage: 77)) {
            _ = try self.plan(
                .setEditing(try Workflow.EditingPreferences(tabWidth: 8)),
                current: exhausted,
                catalogs: catalogs
            )
        }
    }

    func testStateCASBindsNonzeroLineageRevisionAndExactContents() throws {
        let current = try Workflow.State.defaults(lineage: 77)
        let cas = current.cas
        let equivalent = try makeState(revision: current.revision)
        XCTAssertEqual(cas.revision, current.revision)
        XCTAssertTrue(try cas.matches(current))
        XCTAssertTrue(try cas.matches(equivalent))
        XCTAssertNoThrow(try cas.validate(equivalent))

        let stale = try makeState(
            revision: Workflow.Revision(lineage: 77, generation: 1)
        )
        XCTAssertFalse(try cas.matches(stale))
        assertWorkflowError(
            .staleRevision(expected: current.revision, actual: stale.revision)
        ) {
            try cas.validate(stale)
        }
        let foreignLineage = try makeState(
            revision: Workflow.Revision(lineage: 78, generation: current.revision.generation)
        )
        XCTAssertFalse(try cas.matches(foreignLineage))
        assertWorkflowError(
            .staleRevision(expected: current.revision, actual: foreignLineage.revision)
        ) {
            try cas.validate(foreignLineage)
        }

        let changedContents = try makeState(
            revision: current.revision,
            editing: Workflow.EditingPreferences(tabWidth: 8, tabInsertion: .spaces)
        )
        XCTAssertFalse(try cas.matches(changedContents))
        assertWorkflowError(.stateContentsChanged(current.revision)) {
            try cas.validate(changedContents)
        }
    }

    func testPlanPinsStateAndFullSyntaxAndColorCatalogContents() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let plan = try self.plan(
            .setEditing(try Workflow.EditingPreferences(tabWidth: 2, tabInsertion: .spaces)),
            current: current,
            catalogs: catalogs
        )
        XCTAssertNoThrow(
            try plan.validateCurrentState(
                current,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        )

        let changedCurrent = try replacingState(
            current,
            editing: Workflow.EditingPreferences(tabWidth: 3, tabInsertion: .spaces)
        )
        assertWorkflowError(.stateContentsChanged(current.revision)) {
            try plan.validateCurrentState(
                changedCurrent,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        }

        let changedSyntax = try makeSyntaxScheme(
            id: catalogs.selectedSyntax.id,
            name: "Changed Selected"
        )
        let changedSyntaxCatalog = try SyntaxSchemeCatalog(
            customSchemes: [changedSyntax, catalogs.fallbackSyntax],
            revision: catalogs.syntax.revision
        )
        assertWorkflowError(
            .syntaxCatalog(
                .staleCatalog(
                    expected: catalogs.syntax.revision,
                    actual: changedSyntaxCatalog.revision
                )
            )
        ) {
            try plan.validateCurrentState(
                current,
                syntaxCatalog: changedSyntaxCatalog,
                colorCatalog: catalogs.color
            )
        }

        let changedColor = try makeColorScheme(
            identifier: catalogs.customColor.identifier,
            displayName: "Changed Color"
        )
        let changedColorCatalog = try Workflow.ColorSchemeCatalog(
            revision: catalogs.color.revision,
            schemes: [EditorColorScheme.standard, changedColor]
        )
        assertWorkflowError(
            .staleColorSchemeCatalog(
                expected: catalogs.color.revision,
                actual: changedColorCatalog.revision
            )
        ) {
            try plan.validateCurrentState(
                current,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: changedColorCatalog
            )
        }
    }

    func testCanonicalPersistenceHasExactOrderValuesAndRoundTrip() throws {
        let catalogs = try makeCatalogs()
        let state = try makeCustomizedState(
            catalogs: catalogs,
            revision: Workflow.Revision(lineage: 77, generation: 9)
        )
        let data = try Workflow.encode(state)
        let display = try state.display.encodedData().base64EncodedString()
        let view = try state.view.encodedData().base64EncodedString()
        let syntax = try state.syntax.selection.encodedData().base64EncodedString()
        let expected =
            #"{"colorScheme":{"selectedIdentifier":"vendor:theme/dark"},"compareAndMerge":{"automaticMergeDestination":"right","automaticRescanAfterEdit":true,"copyGranularity":"inlineDifference","lineDifferenceGranularity":"character","wordBreakCharacters":"é/:;","wordBreakMode":"whitespaceOrCustomCharacters"},"display":""#
            + display
            + #"","editing":{"tabInsertion":"spaces","tabWidth":8},"persistenceVersion":1,"revision":{"generation":9,"lineage":77},"syntaxHighlightingEnabled":true,"syntaxSelection":""#
            + syntax
            + #"","view":""#
            + view
            + #""}"#

        XCTAssertEqual(data, Data(expected.utf8))
        XCTAssertEqual(try Workflow.encode(state), data)
        XCTAssertEqual(try Workflow.decode(from: data), state)
        XCTAssertEqual(try Workflow.encode(Workflow.decode(from: data)), data)
        XCTAssertFalse(data.contains(0x0A))
        XCTAssertFalse(data.contains(0x0D))
        XCTAssertFalse(data.contains(0x09))

        let restoredDefault = try Workflow.restore(from: nil, defaultLineage: 901)
        XCTAssertEqual(restoredDefault.revision, Workflow.Revision(lineage: 901, generation: 0))
        XCTAssertEqual(try Workflow.restore(from: data), state)
    }

    func testDecodeRejectsNoncanonicalWhitespaceUnknownDuplicateAndNormalizedForms() throws {
        let state = try Workflow.State.defaults(lineage: 77)
        let canonical = try Workflow.encode(state)
        let source = String(decoding: canonical, as: UTF8.self)
        let fixtures = [
            Data(("{ " + source.dropFirst()).utf8),
            replacing(source, "}", with: ",\"unknown\":true}", fromEnd: true),
            replacing(source, #""tabWidth":4"#, with: #""tabWidth":4,"tabWidth":4"#),
            replacing(source, #""generation":0,"lineage":77"#, with: #""lineage":77,"generation":0"#)
        ]
        for (index, fixture) in fixtures.enumerated() {
            assertWorkflowError(.nonCanonicalPersistence, "Fixture \(index)") {
                _ = try Workflow.decode(from: fixture)
            }
        }

        let catalogs = try makeCatalogs()
        let normalizedState = try makeCustomizedState(catalogs: catalogs)
        let normalized = String(decoding: try Workflow.encode(normalizedState), as: UTF8.self)
        let decomposed = replacing(normalized, "é/:;", with: "e\u{301}/:;")
        assertWorkflowError(.nonCanonicalPersistence) {
            _ = try Workflow.decode(from: decomposed)
        }
    }

    func testDecodeChecksPersistenceVersionBeforeTypedSemanticsAndCanonicality() throws {
        let source = String(
            decoding: try Workflow.encode(Workflow.State.defaults(lineage: 77)),
            as: UTF8.self
        )
        let unsupportedAndInvalid =
            source
            .replacingOccurrences(of: #""persistenceVersion":1"#, with: #""persistenceVersion":2"#)
            .replacingOccurrences(of: #""tabWidth":4"#, with: #""tabWidth":0"#)
        assertWorkflowError(.unsupportedPersistenceVersion(2)) {
            _ = try Workflow.decode(from: Data(unsupportedAndInvalid.utf8))
        }

        let unsupportedAndNoncanonical =
            " "
            + source.replacingOccurrences(
                of: #""persistenceVersion":1"#,
                with: #""persistenceVersion":99"#
            )
        assertWorkflowError(.unsupportedPersistenceVersion(99)) {
            _ = try Workflow.decode(from: Data(unsupportedAndNoncanonical.utf8))
        }
        assertWorkflowError(.malformedPersistence) {
            _ = try Workflow.decode(
                from: Data(
                    source.replacingOccurrences(
                        of: #""persistenceVersion":1"#,
                        with: #""persistenceVersion":2.0"#
                    ).utf8
                )
            )
        }
    }

    func testDecodeRejectsMalformedTruncatedDuplicateVersionAndSemanticData() throws {
        let source = String(
            decoding: try Workflow.encode(Workflow.State.defaults(lineage: 77)),
            as: UTF8.self
        )
        let malformed: [Data] = [
            Data(),
            Data("null".utf8),
            Data("[]".utf8),
            Data("{".utf8),
            Data("t".utf8),
            Data("tr".utf8),
            Data("fals".utf8),
            Data("nul".utf8),
            Data([0x22, 0xFF, 0x22]),
            Data((source + " trailing").utf8),
            replacing(
                source,
                #""persistenceVersion":1"#,
                with: #""persistenceVersion":1,"persistenceVersion":1"#
            ),
            replacing(source, #""tabWidth":4"#, with: #""tabWidth":false"#),
            replacing(
                source,
                #""wordBreakCharacters":"","wordBreakMode":"whitespace"#,
                with: #""wordBreakCharacters":";","wordBreakMode":"whitespace"#
            ),
            replacing(source, #""lineage":77"#, with: #""lineage":18446744073709551616"#)
        ]
        for (index, fixture) in malformed.enumerated() {
            assertWorkflowError(.malformedPersistence, "Fixture \(index)") {
                _ = try Workflow.decode(from: fixture)
            }
        }
        let escapedEquivalentVersion = replacing(
            source,
            #""persistenceVersion":1"#,
            with: #""persistenceVersion":1,"persistence\u0056ersion":1"#
        )
        assertWorkflowError(.nonCanonicalPersistence) {
            _ = try Workflow.decode(from: escapedEquivalentVersion)
        }
        assertWorkflowError(.malformedPersistence) {
            _ = try Workflow.restore(from: Data("{".utf8))
        }
    }

    func testLimitsValidateAndDepthAndItemBoundsAreExact() throws {
        let invalid: [(Workflow.Limits, Workflow.Limit)] = [
            (makeLimits(maximumPersistenceBytes: 0), .persistenceBytes),
            (makeLimits(maximumColorSchemeCount: 0), .colorSchemeCount),
            (makeLimits(maximumPersistenceItemCount: 0), .persistenceItemCount),
            (makeLimits(maximumJSONDepth: 0), .jsonDepth),
            (makeLimits(maximumStringUTF8Bytes: 0), .stringUTF8Bytes),
            (
                makeLimits(
                    maximumStringUTF8Bytes: 4_096,
                    maximumTotalStringUTF8Bytes: 4_095
                ),
                .totalStringUTF8Bytes
            ),
            (makeLimits(maximumWorkUnits: 0), .workUnits),
            (makeLimits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (
                makeLimits(
                    maximumPersistenceBytes: Workflow.Limits.hardMaximumPersistenceBytes + 1
                ),
                .persistenceBytes
            ),
            (
                makeLimits(
                    maximumColorSchemeCount: Workflow.Limits.hardMaximumColorSchemeCount + 1
                ),
                .colorSchemeCount
            ),
            (
                makeLimits(
                    maximumPersistenceItemCount:
                        Workflow.Limits.hardMaximumPersistenceItemCount + 1
                ),
                .persistenceItemCount
            ),
            (
                makeLimits(maximumJSONDepth: Workflow.Limits.hardMaximumJSONDepth + 1),
                .jsonDepth
            ),
            (
                makeLimits(
                    maximumStringUTF8Bytes: Workflow.Limits.hardMaximumStringUTF8Bytes + 1,
                    maximumTotalStringUTF8Bytes:
                        Workflow.Limits.hardMaximumTotalStringUTF8Bytes
                ),
                .stringUTF8Bytes
            ),
            (
                makeLimits(
                    maximumTotalStringUTF8Bytes:
                        Workflow.Limits.hardMaximumTotalStringUTF8Bytes + 1
                ),
                .totalStringUTF8Bytes
            ),
            (
                makeLimits(maximumWorkUnits: Workflow.Limits.hardMaximumWorkUnits + 1),
                .workUnits
            ),
            (
                makeLimits(
                    cancellationCheckInterval:
                        Workflow.Limits.hardMaximumCancellationCheckInterval + 1
                ),
                .cancellationCheckInterval
            )
        ]
        for (limits, field) in invalid {
            assertWorkflowError(.invalidLimit(field), field.rawValue) {
                try limits.validate()
            }
        }

        let canonical = try Workflow.encode(Workflow.State.defaults(lineage: 77))
        let exact = makeLimits(maximumPersistenceItemCount: 21, maximumJSONDepth: 2)
        XCTAssertEqual(try Workflow.decode(from: canonical, limits: exact).revision.lineage, 77)

        let tooFewItems = makeLimits(maximumPersistenceItemCount: 20, maximumJSONDepth: 2)
        assertWorkflowError(.tooManyPersistenceItems(maximum: 20)) {
            _ = try Workflow.decode(from: canonical, limits: tooFewItems)
        }
        let tooShallow = makeLimits(maximumPersistenceItemCount: 21, maximumJSONDepth: 1)
        assertWorkflowError(.jsonTooDeep(maximumDepth: 1)) {
            _ = try Workflow.decode(from: canonical, limits: tooShallow)
        }

        let nested = Data(#"{"persistenceVersion":1,"x":[[]]}"#.utf8)
        assertWorkflowError(.jsonTooDeep(maximumDepth: 2)) {
            _ = try Workflow.decode(from: nested, limits: exact)
        }
        let excessiveItems = Data(#"{"persistenceVersion":1,"x":[0,0]}"#.utf8)
        let threeItems = makeLimits(maximumPersistenceItemCount: 3, maximumJSONDepth: 2)
        assertWorkflowError(.tooManyPersistenceItems(maximum: 3)) {
            _ = try Workflow.decode(from: excessiveItems, limits: threeItems)
        }
    }

    func testPersistenceDataBoundsAcceptExactAndRejectOneByteLess() throws {
        let original = try Workflow.State.defaults(lineage: 77)
        let data = try Workflow.encode(original)
        let exactLimits = makeLimits(maximumPersistenceBytes: data.count)
        let exactState = try replacingLimits(in: original, with: exactLimits)

        XCTAssertEqual(try Workflow.encode(exactState), data)
        XCTAssertEqual(try Workflow.decode(from: data, limits: exactLimits), exactState)

        let shortLimits = makeLimits(maximumPersistenceBytes: data.count - 1)
        let shortState = try replacingLimits(in: original, with: shortLimits)
        assertWorkflowError(.persistenceOutputTooLarge(maximumBytes: data.count - 1)) {
            _ = try Workflow.encode(shortState)
        }
        assertWorkflowError(.persistenceInputTooLarge(maximumBytes: data.count - 1)) {
            _ = try Workflow.decode(from: data, limits: shortLimits)
        }
    }

    func testStringAggregateAndPlanningWorkBoundsAreEnforced() throws {
        let shortStringLimits = makeLimits(
            maximumStringUTF8Bytes: 16,
            maximumTotalStringUTF8Bytes: 256
        )
        assertWorkflowError(
            .stringTooLarge(field: .colorSchemeIdentifier, maximumUTF8Bytes: 16)
        ) {
            _ = try Workflow.State.defaults(lineage: 77, limits: shortStringLimits)
        }

        let aggregateLimits = makeLimits(
            maximumStringUTF8Bytes: 128,
            maximumTotalStringUTF8Bytes: 128
        )
        let largeDisplay = try EditorDisplayPreferences(
            font: EditorFontDescriptor(familyName: String(repeating: "f", count: 100), pointSize: 12)
        )
        let compare = try Workflow.CompareAndMergePreferences(
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: String(repeating: ";", count: 20)
        )
        assertWorkflowError(.totalStringsTooLarge(maximumUTF8Bytes: 128)) {
            _ = try self.makeState(
                display: largeDisplay,
                compareAndMerge: compare,
                limits: aggregateLimits
            )
        }

        let catalogs = try makeCatalogs()
        let current = try Workflow.State.defaults(lineage: 77)
        let intent = Workflow.Intent.setEditing(
            try Workflow.EditingPreferences(tabWidth: 8, tabInsertion: .spaces)
        )
        let baseline = try plan(intent, current: current, catalogs: catalogs)
        XCTAssertGreaterThan(baseline.receipt.plannedWorkUnits, 1)

        let exactLimits = makeLimits(maximumWorkUnits: baseline.receipt.plannedWorkUnits)
        let exactState = try replacingLimits(in: current, with: exactLimits)
        let exact = try plan(intent, current: exactState, catalogs: catalogs)
        XCTAssertEqual(exact.receipt.plannedWorkUnits, baseline.receipt.plannedWorkUnits)

        let shortLimits = makeLimits(maximumWorkUnits: baseline.receipt.plannedWorkUnits - 1)
        let shortState = try replacingLimits(in: current, with: shortLimits)
        assertWorkflowError(
            .workLimitExceeded(maximumWorkUnits: baseline.receipt.plannedWorkUnits - 1)
        ) {
            _ = try self.plan(intent, current: shortState, catalogs: catalogs)
        }
    }

    func testDecodeOwnsSnapshotWhenCallerDataBackingMutates() throws {
        let original = try Workflow.encode(Workflow.State.defaults(lineage: 77))
        let backing = EditorPreferencesMutableDataBacking(original)
        let interval = 64
        let limits = makeLimits(cancellationCheckInterval: interval)
        let snapshotCompletionCheck = original.count / interval + 2
        let probe = EditorPreferencesCancellationProbe(performOnCheck: snapshotCompletionCheck) {
            backing.overwriteFirstByte(with: UInt8(ascii: "x"))
        }

        let decoded = try Workflow.decode(
            from: backing.data,
            limits: limits,
            cancellationCheck: { try probe.check() }
        )

        XCTAssertEqual(decoded.revision.lineage, 77)
        XCTAssertEqual(backing.data.first, UInt8(ascii: "x"))
        XCTAssertGreaterThan(probe.count, snapshotCompletionCheck)
        XCTAssertEqual(try Workflow.encode(decoded), original)
        assertWorkflowError(.malformedPersistence) {
            _ = try Workflow.decode(from: backing.data, limits: limits)
        }
    }

    func testInjectedCancellationMapsAndForwardsAcrossPublicOperations() throws {
        let catalogs = try makeCatalogs()
        let state = try Workflow.State.defaults(lineage: 77)
        let data = try Workflow.encode(state)
        let operations: [(String, (EditorPreferencesCancellationProbe) throws -> Void)] = [
            (
                "defaults",
                { probe in
                    _ = try Workflow.State.defaults(cancellationCheck: { try probe.check() })
                }
            ),
            ("state validation", { probe in try state.validate(cancellationCheck: { try probe.check() }) }),
            (
                "CAS validation",
                { probe in
                    try state.cas.validate(state, cancellationCheck: { try probe.check() })
                }
            ),
            (
                "color catalog",
                { probe in
                    _ = try Workflow.ColorSchemeCatalog(
                        revision: SyntaxSchemeCatalogRevision(lineage: 1, generation: 0),
                        cancellationCheck: { try probe.check() }
                    )
                }
            ),
            (
                "resolve",
                { probe in
                    _ = try Workflow.resolve(
                        state,
                        syntaxCatalog: catalogs.syntax,
                        colorCatalog: catalogs.color,
                        cancellationCheck: { try probe.check() }
                    )
                }
            ),
            (
                "plan",
                { probe in
                    _ = try Workflow.plan(
                        intent: .setEditing(Workflow.EditingPreferences(tabWidth: 8)),
                        current: state,
                        syntaxCatalog: catalogs.syntax,
                        colorCatalog: catalogs.color,
                        cancellationCheck: { try probe.check() }
                    )
                }
            ),
            (
                "encode",
                { probe in
                    _ = try Workflow.encode(state, cancellationCheck: { try probe.check() })
                }
            ),
            (
                "decode",
                { probe in
                    _ = try Workflow.decode(from: data, cancellationCheck: { try probe.check() })
                }
            ),
            (
                "restore",
                { probe in
                    _ = try Workflow.restore(from: nil, cancellationCheck: { try probe.check() })
                }
            )
        ]
        for (name, operation) in operations {
            let baseline = EditorPreferencesCancellationProbe()
            try operation(baseline)
            XCTAssertGreaterThan(baseline.count, 1, name)
            let late = EditorPreferencesCancellationProbe(throwOnCheck: baseline.count)
            assertWorkflowError(.cancelled, name) {
                try operation(late)
            }
            XCTAssertEqual(late.count, baseline.count, name)
        }
    }

    func testTaskCancellationMapsAndPreventsExecutorEntry() async throws {
        let catalogs = try makeCatalogs()
        let state = try Workflow.State.defaults(lineage: 77)
        let data = try Workflow.encode(state)
        let plan = try self.plan(
            .setEditing(try Workflow.EditingPreferences(tabWidth: 8)),
            current: state,
            catalogs: catalogs
        )

        await assertPreCancelled { try Workflow.checkTaskCancellation() }
        await assertPreCancelled { try Workflow.encode(state) }
        await assertPreCancelled { try Workflow.decode(from: data) }
        await assertPreCancelled {
            try Workflow.resolve(
                state,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        }
        await assertPreCancelled {
            try Workflow.plan(
                intent: .setEditing(Workflow.EditingPreferences(tabWidth: 8)),
                current: state,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        }

        let executor = EditorPreferencesTestExecutor(mode: .completed)
        await assertPreCancelled {
            try await plan.execute(
                on: executor,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        }
        let executionCount = await executor.executionCount()
        XCTAssertEqual(executionCount, 0)
    }

    func testExecutorContractRequiresOneExactExclusiveTransaction() async throws {
        let catalogs = try makeCatalogs()
        let current = try Workflow.State.defaults(lineage: 77)
        let plan = try self.plan(
            .setEditing(try Workflow.EditingPreferences(tabWidth: 8, tabInsertion: .spaces)),
            current: current,
            catalogs: catalogs
        )
        let executor = EditorPreferencesTestExecutor(mode: .completed, initialState: current)
        let outcome = try await plan.execute(
            on: executor,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected completed outcome")
        }
        let executionCount = await executor.executionCount()
        let capturedLease = await executor.capturedExecutorLease()
        let capturedSyntaxCatalog = await executor.capturedSyntaxSchemeCatalog()
        let capturedColorCatalog = await executor.capturedColorSchemeCatalog()
        let reconciliation = await executor.reconciliation()
        let persistedData = await executor.persistedData()
        let appliedState = await executor.appliedState()
        let executorError = await executor.outcomeFactoryError()
        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(receipt.planning, plan.receipt)
        XCTAssertEqual(receipt.completedEffects, plan.requiredEffects)
        let lease = try XCTUnwrap(capturedLease)
        XCTAssertEqual(capturedSyntaxCatalog, catalogs.syntax)
        XCTAssertEqual(capturedColorCatalog, catalogs.color)
        XCTAssertEqual(reconciliation, .successor)
        XCTAssertEqual(persistedData, persistenceData(from: plan.persistence))
        XCTAssertEqual(appliedState, plan.successor)
        XCTAssertNil(executorError)
        XCTAssertEqual(lease.expectedStateCAS, plan.expectedStateCAS)
        XCTAssertEqual(lease.successor, plan.successor)
        XCTAssertEqual(lease.resolvedSchemes, plan.resolvedSchemes)
        XCTAssertEqual(lease.persistence, plan.persistence)
        XCTAssertEqual(lease.application, plan.application)
        XCTAssertEqual(lease.requiredEffect, plan.requiredEffects[0])
        XCTAssertEqual(lease.executorContract, .required)

        let contract = plan.executorContract
        XCTAssertEqual(contract.cas, .acquireExclusiveLeaseByExactRevisionAndContentsBeforeTransaction)
        XCTAssertEqual(contract.persistence, .publishExactVersionedBytesWithoutRegenerationInsideTransaction)
        XCTAssertEqual(contract.state, .replaceWithExactPlannedSuccessorInsideTransaction)
        XCTAssertEqual(contract.application, .validatePinnedCatalogsAndApplyExactTypedStateBeforeLeaseRelease)
        XCTAssertEqual(contract.cancellation, .cancelBeforeTransactionOrReportWholeTransactionUncertain)
        XCTAssertEqual(
            contract.reconciliation,
            .reconcilePersistenceStateAndEditorsToPredecessorOrSuccessorBeforeDefiniteOutcome
        )
        XCTAssertEqual(plan.requiredEffects.count, 1)
        guard case .commitExclusiveTransaction(let persistence, let successor) = plan.requiredEffects[0] else {
            return XCTFail("Expected exclusive transaction effect")
        }
        XCTAssertEqual(persistence, plan.receipt.persistence)
        XCTAssertEqual(successor, plan.successor.revision)

        let secondExecutor = EditorPreferencesTestExecutor(mode: .completed, initialState: current)
        _ = try await plan.execute(
            on: secondExecutor,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        let capturedSecondLease = await secondExecutor.capturedExecutorLease()
        let secondLease = try XCTUnwrap(capturedSecondLease)
        XCTAssertFalse(lease.isSameLease(as: secondLease))
    }

    func testExecutorFailureReasonsProduceDefiniteReconciledNoncommitReceipts() async throws {
        let catalogs = try makeCatalogs()
        let plan = try self.plan(
            .setEditing(try Workflow.EditingPreferences(tabWidth: 8)),
            current: Workflow.State.defaults(lineage: 77),
            catalogs: catalogs
        )
        XCTAssertEqual(
            Workflow.ExecutionFailureReason.allCases,
            [
                .cancelled, .staleState, .persistenceUnavailable, .stateOwnerUnavailable,
                .editorApplicationUnavailable, .schemeCatalogChanged, .contractUnsupported, .rejected
            ]
        )

        for reason in Workflow.ExecutionFailureReason.allCases {
            let executor = EditorPreferencesTestExecutor(
                mode: .notCommitted(reason),
                initialState: try Workflow.State.defaults(lineage: 77)
            )
            let outcome = try await plan.execute(
                on: executor,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
            guard case .notCommitted(let receipt) = outcome else {
                XCTFail("Expected noncommit for \(reason)")
                continue
            }
            XCTAssertEqual(receipt.planning, plan.receipt)
            XCTAssertEqual(receipt.blockedEffect, plan.requiredEffects[0])
            XCTAssertEqual(receipt.reason, reason)
            let factoryError = await executor.outcomeFactoryError()
            let reconciliation = await executor.reconciliation()
            XCTAssertNil(factoryError)
            XCTAssertEqual(reconciliation, .predecessor)
        }
    }

    func testExecutorUncertainOutcomeOwnsWholeTransactionAndRejectsPartialClaims() async throws {
        let catalogs = try makeCatalogs()
        let plan = try self.plan(
            .setEditing(try Workflow.EditingPreferences(tabWidth: 8)),
            current: Workflow.State.defaults(lineage: 77),
            catalogs: catalogs
        )
        let executor = EditorPreferencesTestExecutor(
            mode: .uncertain([0]),
            initialState: try Workflow.State.defaults(lineage: 77)
        )
        let outcome = try await plan.execute(
            on: executor,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        guard case .effectUncertain(let receipt) = outcome else {
            return XCTFail("Expected uncertain outcome")
        }
        XCTAssertEqual(receipt.planning, plan.receipt)
        XCTAssertEqual(receipt.completedEffects, [])
        XCTAssertEqual(receipt.uncertainEffects, plan.requiredEffects)
        XCTAssertEqual(receipt.unattemptedEffects, [])
        let reconciliation = await executor.reconciliation()
        XCTAssertEqual(reconciliation, .uncertain)

        for indices in [[], [0, 0], [1], [-1], [0, 1]] {
            let invalid = EditorPreferencesTestExecutor(mode: .uncertain(indices))
            _ = try await plan.execute(
                on: invalid,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
            let factoryError = await invalid.outcomeFactoryError()
            XCTAssertEqual(factoryError, .invalidExecutionOutcome)
        }
    }

    func testPlanRejectsOutcomeFromForeignExclusiveLease() async throws {
        let catalogs = try makeCatalogs()
        let current = try Workflow.State.defaults(lineage: 77)
        let plan = try self.plan(
            .setEditing(try Workflow.EditingPreferences(tabWidth: 8)),
            current: current,
            catalogs: catalogs
        )
        let firstExecutor = EditorPreferencesTestExecutor(mode: .completed, initialState: current)
        let foreign = try await plan.execute(
            on: firstExecutor,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        let replayingExecutor = EditorPreferencesTestExecutor(mode: .foreign(foreign))

        do {
            _ = try await plan.execute(
                on: replayingExecutor,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
            XCTFail("Foreign lease outcome unexpectedly accepted")
        } catch let error as Workflow.Error {
            XCTAssertEqual(error, .invalidExecutionOutcome)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let executionCount = await replayingExecutor.executionCount()
        XCTAssertEqual(executionCount, 1)
    }

    func testPlanningReceiptsAreDeterministicDataOwningAndDescriptionsAreRedacted() throws {
        let catalogs = try makeCatalogs(secret: true)
        let current = try makeCustomizedState(catalogs: catalogs)
        let intent = Workflow.Intent.setEditing(
            try Workflow.EditingPreferences(tabWidth: 2, tabInsertion: .spaces)
        )
        let first = try plan(intent, current: current, catalogs: catalogs)
        let second = try plan(intent, current: current, catalogs: catalogs)

        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.requiredEffects, second.requiredEffects)
        XCTAssertEqual(first.persistence, second.persistence)
        XCTAssertEqual(first.receipt.expectedRevision, current.revision)
        XCTAssertEqual(first.receipt.successorRevision, first.successor.revision)
        XCTAssertEqual(
            first.receipt.persistence.persistenceVersion,
            Workflow.currentPersistenceVersion
        )
        XCTAssertGreaterThan(first.receipt.plannedWorkUnits, 0)
        let canonical = persistenceData(from: first.persistence)
        XCTAssertEqual(first.receipt.persistedByteCount, canonical.count)
        XCTAssertTrue(first.receipt.persistence.matches(canonicalData: canonical))
        var changed = canonical
        changed[changed.startIndex] ^= 0x01
        XCTAssertFalse(first.receipt.persistence.matches(canonicalData: changed))
        XCTAssertEqual(persistenceData(from: first.persistence), canonical)

        let secretValues = [
            "secret.selected",
            "secret.fallback",
            "secret:color/path",
            "SECRET-WORD",
            "Secret Selected",
            "Secret Fallback",
            "Secret Color"
        ]
        let values: [Any] = [
            current.compareAndMerge,
            current.colorScheme.selectedIdentifier,
            current.colorScheme,
            current.syntax,
            current,
            current.cas,
            catalogs.color,
            first.resolvedSchemes,
            intent,
            first.persistence,
            first.application,
            first.receipt.persistence,
            first,
            first.requiredEffects[0],
            Workflow.Error.stateContentsChanged(current.revision)
        ]
        for value in values {
            let rendered = redactedRendering(of: value)
            XCTAssertTrue(rendered.contains("<redacted>"), rendered)
            for secret in secretValues {
                XCTAssertFalse(rendered.contains(secret), rendered)
            }
        }
    }

    private struct Catalogs: Sendable {
        let selectedSyntax: SyntaxScheme
        let fallbackSyntax: SyntaxScheme
        let syntax: SyntaxSchemeCatalog
        let customColor: EditorColorScheme
        let color: Workflow.ColorSchemeCatalog
    }

    private func makeCatalogs(secret: Bool = false) throws -> Catalogs {
        let selectedID = try SyntaxSchemeIdentifier(secret ? "secret.selected" : "custom.selected")
        let fallbackID = try SyntaxSchemeIdentifier(secret ? "secret.fallback" : "custom.fallback")
        let selected = try makeSyntaxScheme(id: selectedID, name: secret ? "Secret Selected" : "Selected")
        let fallback = try makeSyntaxScheme(id: fallbackID, name: secret ? "Secret Fallback" : "Fallback")
        let syntax = try SyntaxSchemeCatalog(
            customSchemes: [fallback, selected],
            revision: SyntaxSchemeCatalogRevision(lineage: 30, generation: 4)
        )
        let colorIdentifier = secret ? "secret:color/path" : "vendor:theme/dark"
        let customColor = try makeColorScheme(
            identifier: colorIdentifier,
            displayName: secret ? "Secret Color" : "Vendor Dark"
        )
        let color = try Workflow.ColorSchemeCatalog(
            revision: SyntaxSchemeCatalogRevision(lineage: 31, generation: 5),
            schemes: [customColor, EditorColorScheme.standard]
        )
        return Catalogs(
            selectedSyntax: selected,
            fallbackSyntax: fallback,
            syntax: syntax,
            customColor: customColor,
            color: color
        )
    }

    private func makeSyntaxScheme(
        id: SyntaxSchemeIdentifier,
        name: String,
        modes: [SyntaxSchemeApplicationMode] = [.textComparison]
    ) throws -> SyntaxScheme {
        try SyntaxScheme(
            id: id,
            displayName: name,
            supportedLanguages: [.swift],
            applicationModes: modes
        )
    }

    private func makeColorScheme(identifier: String, displayName: String) throws -> EditorColorScheme {
        try EditorColorScheme(
            identifier: identifier,
            displayName: displayName,
            palettes: EditorColorScheme.standard.palettes,
            differenceDecorations: EditorColorScheme.standard.differenceDecorations
        )
    }

    private func customDisplay() throws -> EditorDisplayPreferences {
        try EditorDisplayPreferences(
            font: EditorFontDescriptor(familyName: "SF Mono", pointSize: 14),
            zoomStep: 17,
            syntaxHighlightingLanguage: .swift,
            showsWhitespace: true,
            showsEndOfLineMarkers: true,
            showsLineDifferences: false,
            showsLineNumbers: true,
            showsMargins: true,
            showsTopMargin: true,
            wrapsLines: true
        )
    }

    private func customComparePreferences(secret: Bool = false) throws -> Workflow.CompareAndMergePreferences {
        try Workflow.CompareAndMergePreferences(
            automaticRescanAfterEdit: true,
            copyGranularity: .inlineDifference,
            lineDifferenceGranularity: .character,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: secret ? "SECRET-WORD" : "e\u{301}/:;",
            automaticMergeDestination: .right
        )
    }

    private func makeCustomizedState(
        catalogs: Catalogs,
        revision: Workflow.Revision = Workflow.Revision(lineage: 77, generation: 0)
    ) throws -> Workflow.State {
        try makeState(
            revision: revision,
            display: customDisplay(),
            locksPanes: true,
            editing: Workflow.EditingPreferences(tabWidth: 8, tabInsertion: .spaces),
            compareAndMerge: customComparePreferences(
                secret: catalogs.selectedSyntax.id.rawValue.hasPrefix("secret.")
            ),
            syntax: Workflow.SyntaxPreferences(
                selection: SyntaxSchemeSelection(
                    selectedIdentifier: catalogs.selectedSyntax.id,
                    fallbackIdentifier: catalogs.fallbackSyntax.id
                )
            ),
            colorScheme: Workflow.ColorSchemeSelection(
                selectedIdentifier: Workflow.ColorSchemeIdentifier(catalogs.customColor.identifier)
            )
        )
    }

    private func makeState(
        revision: Workflow.Revision = Workflow.Revision(lineage: 77, generation: 0),
        display: EditorDisplayPreferences = .default,
        locksPanes: Bool = false,
        editing: Workflow.EditingPreferences = .default,
        compareAndMerge: Workflow.CompareAndMergePreferences = .default,
        syntax: Workflow.SyntaxPreferences = .default,
        colorScheme: Workflow.ColorSchemeSelection = .default,
        limits: Workflow.Limits = .default
    ) throws -> Workflow.State {
        try Workflow.State(
            revision: revision,
            display: display,
            locksPanes: locksPanes,
            editing: editing,
            compareAndMerge: compareAndMerge,
            syntax: syntax,
            colorScheme: colorScheme,
            limits: limits
        )
    }

    private func replacingState(
        _ state: Workflow.State,
        editing: Workflow.EditingPreferences
    ) throws -> Workflow.State {
        try Workflow.State(
            revision: state.revision,
            display: state.display,
            view: state.view,
            editing: editing,
            compareAndMerge: state.compareAndMerge,
            syntax: state.syntax,
            colorScheme: state.colorScheme,
            limits: state.limits
        )
    }

    private func replacingLimits(
        in state: Workflow.State,
        with limits: Workflow.Limits
    ) throws -> Workflow.State {
        try Workflow.State(
            revision: state.revision,
            display: state.display,
            view: state.view,
            editing: state.editing,
            compareAndMerge: state.compareAndMerge,
            syntax: state.syntax,
            colorScheme: state.colorScheme,
            limits: limits
        )
    }

    private func plan(
        _ intent: Workflow.Intent,
        current: Workflow.State,
        catalogs: Catalogs
    ) throws -> Workflow.Plan {
        try Workflow.plan(
            intent: intent,
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
    }

    private func persistenceData(from effect: Workflow.PersistenceEffect) -> Data {
        switch effect {
        case .store(let data): data
        }
    }

    private func assertUntouchedNonGeneralSettings(
        _ successor: Workflow.State,
        equalTo current: Workflow.State,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(successor.compareAndMerge, current.compareAndMerge, file: file, line: line)
        XCTAssertEqual(successor.syntax, current.syntax, file: file, line: line)
        XCTAssertEqual(successor.colorScheme, current.colorScheme, file: file, line: line)
    }

    private func makeLimits(
        maximumPersistenceBytes: Int = Workflow.Limits.default.maximumPersistenceBytes,
        maximumColorSchemeCount: Int = Workflow.Limits.default.maximumColorSchemeCount,
        maximumPersistenceItemCount: Int = Workflow.Limits.default.maximumPersistenceItemCount,
        maximumJSONDepth: Int = Workflow.Limits.default.maximumJSONDepth,
        maximumStringUTF8Bytes: Int = Workflow.Limits.default.maximumStringUTF8Bytes,
        maximumTotalStringUTF8Bytes: Int = Workflow.Limits.default.maximumTotalStringUTF8Bytes,
        maximumWorkUnits: Int = Workflow.Limits.default.maximumWorkUnits,
        cancellationCheckInterval: Int = Workflow.Limits.default.cancellationCheckInterval
    ) -> Workflow.Limits {
        Workflow.Limits(
            maximumPersistenceBytes: maximumPersistenceBytes,
            maximumColorSchemeCount: maximumColorSchemeCount,
            maximumPersistenceItemCount: maximumPersistenceItemCount,
            maximumJSONDepth: maximumJSONDepth,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func replacing(
        _ source: String,
        _ target: String,
        with replacement: String,
        fromEnd: Bool = false
    ) -> Data {
        let range =
            fromEnd
            ? source.range(of: target, options: .backwards)
            : source.range(of: target)
        guard let range else {
            XCTFail("Fixture replacement did not match: \(target)")
            return Data(source.utf8)
        }
        var result = source
        result.replaceSubrange(range, with: replacement)
        return Data(result.utf8)
    }

    private func redactedRendering(of value: Any) -> String {
        let reflectedChildren = Mirror(reflecting: value).children.map {
            "\($0.label ?? "_")=\(String(describing: $0.value))"
        }.joined(separator: " ")
        return [String(describing: value), String(reflecting: value), reflectedChildren]
            .joined(separator: " ")
    }

    private func assertWorkflowError<T>(
        _ expected: Workflow.Error,
        _ context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), context, file: file, line: line) { error in
            XCTAssertEqual(error as? Workflow.Error, expected, context, file: file, line: line)
        }
    }

    private func assertSyntaxCatalogError<T>(
        _ expected: SyntaxSchemeCatalogError,
        _ context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
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

    private func assertPreCancelled<T: Sendable>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping @Sendable () async throws -> T
    ) async {
        let result = await Task.detached { @Sendable () -> Workflow.Error? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await operation()
                return nil
            } catch let error as Workflow.Error {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(result, .cancelled, file: file, line: line)
    }
}

private enum EditorPreferencesProbeError: Error {
    case stop
}

private final class EditorPreferencesCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let throwOnCheck: Int?
    private let performOnCheck: Int?
    private let action: (@Sendable () -> Void)?
    private var storedCount = 0

    init(
        throwOnCheck: Int? = nil,
        performOnCheck: Int? = nil,
        action: (@Sendable () -> Void)? = nil
    ) {
        self.throwOnCheck = throwOnCheck
        self.performOnCheck = performOnCheck
        self.action = action
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    func check() throws {
        lock.lock()
        storedCount += 1
        let current = storedCount
        lock.unlock()
        if current == performOnCheck { action?() }
        if current == throwOnCheck { throw EditorPreferencesProbeError.stop }
    }
}

private final class EditorPreferencesMutableDataBacking: @unchecked Sendable {
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

private enum EditorPreferencesExecutorMode: Sendable {
    case completed
    case notCommitted(Workflow.ExecutionFailureReason)
    case uncertain([Int])
    case foreign(Workflow.ExecutionOutcome)
}

private enum EditorPreferencesReconciliation: Sendable {
    case predecessor
    case successor
    case uncertain
}

private actor EditorPreferencesTestExecutor: Workflow.PlanExecutor {
    private let mode: EditorPreferencesExecutorMode
    private var state: Workflow.State?
    private var count = 0
    private var lease: Workflow.ExecutorLease?
    private var syntaxCatalog: SyntaxSchemeCatalog?
    private var colorCatalog: Workflow.ColorSchemeCatalog?
    private var storedPersistence: Data?
    private var storedAppliedState: Workflow.State?
    private var storedReconciliation: EditorPreferencesReconciliation?
    private var factoryError: Workflow.Error?

    init(mode: EditorPreferencesExecutorMode, initialState: Workflow.State? = nil) {
        self.mode = mode
        state = initialState
    }

    func execute(
        _ lease: Workflow.ExecutorLease,
        syntaxCatalog: SyntaxSchemeCatalog,
        colorCatalog: Workflow.ColorSchemeCatalog
    ) -> Workflow.ExecutionOutcome {
        count += 1
        self.lease = lease
        self.syntaxCatalog = syntaxCatalog
        self.colorCatalog = colorCatalog
        switch mode {
        case .completed:
            do {
                let current = try XCTUnwrap(state)
                try lease.expectedStateCAS.validate(current)
                try lease.resolvedSchemes.validate(
                    syntaxCatalog: syntaxCatalog,
                    colorCatalog: colorCatalog
                )
                let data: Data
                switch lease.persistence {
                case .store(let canonicalData):
                    data = canonicalData
                }
                guard try Workflow.decode(from: data, limits: lease.successor.limits) == lease.successor
                else {
                    throw Workflow.Error.invalidExecutionOutcome
                }
                guard
                    case .apply(let appliedState, let resolvedSchemes) = lease.application,
                    appliedState == lease.successor,
                    resolvedSchemes == lease.resolvedSchemes
                else {
                    throw Workflow.Error.invalidExecutionOutcome
                }
                storedPersistence = data
                state = lease.successor
                storedAppliedState = appliedState
                storedReconciliation = .successor
            } catch let error as Workflow.Error {
                factoryError = error
            } catch {
                factoryError = .invalidExecutionOutcome
            }
            return Workflow.ExecutionOutcomeFactory.completed(lease: lease)
        case .notCommitted(let reason):
            storedReconciliation = .predecessor
            do {
                return try Workflow.ExecutionOutcomeFactory.notCommitted(
                    lease: lease,
                    reason: reason
                )
            } catch let error as Workflow.Error {
                factoryError = error
                return Workflow.ExecutionOutcomeFactory.completed(lease: lease)
            } catch {
                return Workflow.ExecutionOutcomeFactory.completed(lease: lease)
            }
        case .uncertain(let indices):
            storedReconciliation = .uncertain
            do {
                return try Workflow.ExecutionOutcomeFactory.effectUncertain(
                    lease: lease,
                    uncertainEffectIndices: indices
                )
            } catch let error as Workflow.Error {
                factoryError = error
                return Workflow.ExecutionOutcomeFactory.completed(lease: lease)
            } catch {
                return Workflow.ExecutionOutcomeFactory.completed(lease: lease)
            }
        case .foreign(let outcome):
            return outcome
        }
    }

    func executionCount() -> Int {
        count
    }

    func capturedExecutorLease() -> Workflow.ExecutorLease? {
        lease
    }

    func capturedSyntaxSchemeCatalog() -> SyntaxSchemeCatalog? {
        syntaxCatalog
    }

    func capturedColorSchemeCatalog() -> Workflow.ColorSchemeCatalog? {
        colorCatalog
    }

    func persistedData() -> Data? {
        storedPersistence
    }

    func appliedState() -> Workflow.State? {
        storedAppliedState
    }

    func reconciliation() -> EditorPreferencesReconciliation? {
        storedReconciliation
    }

    func outcomeFactoryError() -> Workflow.Error? {
        factoryError
    }
}
