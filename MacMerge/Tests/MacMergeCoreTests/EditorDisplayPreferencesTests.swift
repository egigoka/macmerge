import Foundation
import MacMergeCore
import XCTest

final class EditorDisplayPreferencesTests: XCTestCase {
    private static let defaultFontJSON =
        #""font":{"family":"systemMonospaced","pointSize":12}"#

    private static let defaultJSON =
        #"{"font":{"family":"systemMonospaced","pointSize":12},"#
        + #""schemaVersion":1,"showsEndOfLineMarkers":false,"showsLineDifferences":true,"#
        + #""showsLineNumbers":false,"showsMargins":false,"showsTopMargin":false,"#
        + #""showsWhitespace":false,"syntaxHighlightingLanguage":"plainText","#
        + #""wrapsLines":false,"zoomStep":10}"#

    func testDefaultsMirrorExpectedEditorState() throws {
        let preferences = EditorDisplayPreferences.default

        XCTAssertEqual(preferences, EditorDisplayPreferences())
        XCTAssertEqual(preferences.schemaVersion, EditorDisplayPreferences.currentSchemaVersion)
        XCTAssertEqual(preferences.schemaVersion, 1)
        XCTAssertEqual(preferences.font, .default)
        XCTAssertTrue(preferences.font.usesSystemMonospacedFont)
        XCTAssertNil(preferences.font.familyName)
        XCTAssertEqual(preferences.font.pointSize, 12)
        XCTAssertTrue(preferences.isUsingDefaultFont)
        XCTAssertEqual(preferences.zoomStep, EditorDisplayPreferences.normalZoomStep)
        XCTAssertEqual(preferences.zoomPercentage, 100)
        XCTAssertEqual(preferences.zoomScale, 1)
        XCTAssertEqual(preferences.effectiveFontPointSize, 12)
        XCTAssertTrue(preferences.canZoomIn)
        XCTAssertTrue(preferences.canZoomOut)
        XCTAssertEqual(preferences.syntaxHighlightingLanguage, .plainText)
        XCTAssertFalse(preferences.showsWhitespace)
        XCTAssertFalse(preferences.showsEndOfLineMarkers)
        XCTAssertTrue(preferences.showsLineDifferences)
        XCTAssertFalse(preferences.showsLineNumbers)
        XCTAssertFalse(preferences.showsMargins)
        XCTAssertFalse(preferences.showsTopMargin)
        XCTAssertFalse(preferences.wrapsLines)
        XCTAssertNoThrow(try preferences.validate())
        XCTAssertEqual(try preferences.encodedData(), Data(Self.defaultJSON.utf8))
    }

    func testFontDescriptorsAcceptSupportedFamiliesAndExactBounds() throws {
        let named = try EditorFontDescriptor(familyName: "JetBrains Mono", pointSize: 13.5)
        XCTAssertEqual(named.family, .named("JetBrains Mono"))
        XCTAssertEqual(named.familyName, "JetBrains Mono")
        XCTAssertFalse(named.usesSystemMonospacedFont)
        XCTAssertEqual(named.pointSize, 13.5)

        let minimum = try EditorFontDescriptor(
            systemMonospacedPointSize: EditorFontDescriptor.minimumPointSize
        )
        let maximum = try EditorFontDescriptor(
            systemMonospacedPointSize: EditorFontDescriptor.maximumPointSize
        )
        XCTAssertEqual(minimum.pointSize, 1)
        XCTAssertEqual(maximum.pointSize, 72)

        let exactASCIIName = String(
            repeating: "x",
            count: EditorFontDescriptor.maximumFamilyNameUTF8Bytes
        )
        let exactMultibyteName = String(
            repeating: "\u{00E9}",
            count: EditorFontDescriptor.maximumFamilyNameUTF8Bytes / 2
        )
        for name in [exactASCIIName, exactMultibyteName] {
            XCTAssertEqual(name.utf8.count, EditorFontDescriptor.maximumFamilyNameUTF8Bytes)
            XCTAssertEqual(
                try EditorFontDescriptor(familyName: name, pointSize: 12).familyName,
                name
            )
        }
    }

    func testFontDescriptorsRejectInvalidNamesSizesAndNonfiniteValues() {
        for name in ["", " ", "\t\n", "Mono\u{0000}"] {
            assertFontError(.invalidFamilyName) {
                _ = try EditorFontDescriptor(familyName: name, pointSize: 12)
            }
        }

        let oversizedName =
            String(
                repeating: "\u{00E9}",
                count: EditorFontDescriptor.maximumFamilyNameUTF8Bytes / 2
            ) + "x"
        XCTAssertEqual(oversizedName.utf8.count, EditorFontDescriptor.maximumFamilyNameUTF8Bytes + 1)
        assertFontError(
            .familyNameTooLarge(
                maximumUTF8Bytes: EditorFontDescriptor.maximumFamilyNameUTF8Bytes
            )
        ) {
            _ = try EditorFontDescriptor(familyName: oversizedName, pointSize: 12)
        }

        let invalidPointSizes = [
            -Double.infinity,
            EditorFontDescriptor.minimumPointSize.nextDown,
            EditorFontDescriptor.maximumPointSize.nextUp,
            Double.infinity,
            Double.nan
        ]
        for pointSize in invalidPointSizes {
            assertFontError(.invalidPointSize(pointSize)) {
                _ = try EditorFontDescriptor(familyName: "Mono", pointSize: pointSize)
            }
            assertFontError(.invalidPointSize(pointSize)) {
                _ = try EditorFontDescriptor(systemMonospacedPointSize: pointSize)
            }
        }
    }

    func testFontDescriptorRejectsDefaultIgnorableOnlyFamilyName() throws {
        let defaultIgnorableOnly = "\u{FE0F}\u{FE0F}"
        let scalar = try XCTUnwrap(defaultIgnorableOnly.unicodeScalars.first)
        XCTAssertTrue(scalar.properties.isDefaultIgnorableCodePoint)
        XCTAssertFalse(scalar.properties.isWhitespace)
        XCTAssertFalse(CharacterSet.controlCharacters.contains(scalar))

        assertFontError(.invalidFamilyName) {
            _ = try EditorFontDescriptor(
                familyName: defaultIgnorableOnly,
                pointSize: 12
            )
        }

        let visibleNameWithDefaultIgnorableScalar = "Mono\u{FE0F}"
        XCTAssertEqual(
            try EditorFontDescriptor(
                familyName: visibleNameWithDefaultIgnorableScalar,
                pointSize: 12
            ).familyName,
            visibleNameWithDefaultIgnorableScalar
        )
    }

    func testZoomActionsCoverEveryStepAndStopAtBounds() throws {
        XCTAssertEqual(EditorDisplayPreferences.minimumZoomStep, 1)
        XCTAssertEqual(EditorDisplayPreferences.normalZoomStep, 10)
        XCTAssertEqual(EditorDisplayPreferences.maximumZoomStep, 80)

        var preferences = try EditorDisplayPreferences(
            font: .default,
            zoomStep: EditorDisplayPreferences.minimumZoomStep
        )
        XCTAssertFalse(preferences.canZoomOut)
        XCTAssertTrue(preferences.canZoomIn)
        XCTAssertEqual(preferences.zoomPercentage, 10)
        XCTAssertEqual(preferences.zoomScale, 0.1, accuracy: 0.000_000_001)
        XCTAssertEqual(preferences.effectiveFontPointSize, 1.2, accuracy: 0.000_000_001)
        XCTAssertFalse(preferences.zoomOut())
        XCTAssertEqual(preferences.zoomStep, EditorDisplayPreferences.minimumZoomStep)

        for expectedStep in (EditorDisplayPreferences.minimumZoomStep + 1)...EditorDisplayPreferences.maximumZoomStep {
            XCTAssertTrue(preferences.zoomIn())
            XCTAssertEqual(preferences.zoomStep, expectedStep)
        }
        XCTAssertFalse(preferences.canZoomIn)
        XCTAssertTrue(preferences.canZoomOut)
        XCTAssertEqual(preferences.zoomPercentage, 800)
        XCTAssertEqual(preferences.zoomScale, 8)
        XCTAssertEqual(preferences.effectiveFontPointSize, 96)
        XCTAssertFalse(preferences.zoomIn())
        XCTAssertEqual(preferences.zoomStep, EditorDisplayPreferences.maximumZoomStep)

        for expectedStep in stride(
            from: EditorDisplayPreferences.maximumZoomStep - 1,
            through: EditorDisplayPreferences.minimumZoomStep,
            by: -1
        ) {
            XCTAssertTrue(preferences.zoomOut())
            XCTAssertEqual(preferences.zoomStep, expectedStep)
        }
        XCTAssertTrue(preferences.zoomToNormal())
        XCTAssertEqual(preferences.zoomStep, EditorDisplayPreferences.normalZoomStep)
        XCTAssertFalse(preferences.zoomToNormal())
        XCTAssertTrue(preferences.zoomIn())
        XCTAssertTrue(preferences.zoomOut())
        XCTAssertEqual(preferences.zoomStep, EditorDisplayPreferences.normalZoomStep)
    }

    func testZoomSetterAndInitializerEnforceBoundsWithoutMutation() throws {
        var preferences = EditorDisplayPreferences.default
        try preferences.setZoomStep(EditorDisplayPreferences.minimumZoomStep)
        XCTAssertEqual(preferences.zoomStep, EditorDisplayPreferences.minimumZoomStep)
        try preferences.setZoomStep(EditorDisplayPreferences.maximumZoomStep)
        XCTAssertEqual(preferences.zoomStep, EditorDisplayPreferences.maximumZoomStep)

        for invalidStep in [
            Int.min,
            EditorDisplayPreferences.minimumZoomStep - 1,
            EditorDisplayPreferences.maximumZoomStep + 1,
            Int.max
        ] {
            let previousStep = preferences.zoomStep
            assertPreferencesError(.invalidZoomStep(invalidStep)) {
                try preferences.setZoomStep(invalidStep)
            }
            XCTAssertEqual(preferences.zoomStep, previousStep)
            assertPreferencesError(.invalidZoomStep(invalidStep)) {
                _ = try EditorDisplayPreferences(font: .default, zoomStep: invalidStep)
            }
        }
    }

    func testFontLanguageTogglesAndReset() throws {
        var preferences = EditorDisplayPreferences.default
        let customFont = try EditorFontDescriptor(familyName: "SF Mono", pointSize: 14)

        preferences.setFont(customFont)
        XCTAssertEqual(preferences.font, customFont)
        XCTAssertFalse(preferences.isUsingDefaultFont)
        preferences.useDefaultFont()
        XCTAssertEqual(preferences.font, .default)
        XCTAssertTrue(preferences.isUsingDefaultFont)

        assertToggle(&preferences, keyPath: \.showsWhitespace) {
            $0.toggleWhitespace()
        }
        assertToggle(&preferences, keyPath: \.showsWhitespace) {
            $0.toggleWhitespace()
        }
        assertToggle(&preferences, keyPath: \.showsEndOfLineMarkers) {
            $0.toggleEndOfLineMarkers()
        }
        assertToggle(&preferences, keyPath: \.showsEndOfLineMarkers) {
            $0.toggleEndOfLineMarkers()
        }
        assertToggle(&preferences, keyPath: \.showsLineDifferences) {
            $0.toggleLineDifferences()
        }
        assertToggle(&preferences, keyPath: \.showsLineDifferences) {
            $0.toggleLineDifferences()
        }
        assertToggle(&preferences, keyPath: \.showsLineNumbers) {
            $0.toggleLineNumbers()
        }
        assertToggle(&preferences, keyPath: \.showsLineNumbers) {
            $0.toggleLineNumbers()
        }
        assertToggle(&preferences, keyPath: \.showsMargins) {
            $0.toggleMargins()
        }
        assertToggle(&preferences, keyPath: \.showsMargins) {
            $0.toggleMargins()
        }
        assertToggle(&preferences, keyPath: \.showsTopMargin) {
            $0.toggleTopMargin()
        }
        assertToggle(&preferences, keyPath: \.showsTopMargin) {
            $0.toggleTopMargin()
        }
        assertToggle(&preferences, keyPath: \.wrapsLines) {
            $0.toggleWrapLines()
        }
        assertToggle(&preferences, keyPath: \.wrapsLines) {
            $0.toggleWrapLines()
        }
        XCTAssertEqual(preferences, .default)

        for language in SyntaxHighlightingLanguage.allCases {
            preferences.syntaxHighlightingLanguage = language
            XCTAssertEqual(
                try EditorDisplayPreferences.decode(from: preferences.encodedData())
                    .syntaxHighlightingLanguage,
                language
            )
        }

        preferences.setFont(customFont)
        try preferences.setZoomStep(37)
        preferences.syntaxHighlightingLanguage = .markdown
        assertToggle(&preferences, keyPath: \.showsWhitespace) {
            $0.toggleWhitespace()
        }
        assertToggle(&preferences, keyPath: \.showsEndOfLineMarkers) {
            $0.toggleEndOfLineMarkers()
        }
        assertToggle(&preferences, keyPath: \.showsLineDifferences) {
            $0.toggleLineDifferences()
        }
        assertToggle(&preferences, keyPath: \.showsLineNumbers) {
            $0.toggleLineNumbers()
        }
        assertToggle(&preferences, keyPath: \.showsMargins) {
            $0.toggleMargins()
        }
        assertToggle(&preferences, keyPath: \.showsTopMargin) {
            $0.toggleTopMargin()
        }
        assertToggle(&preferences, keyPath: \.wrapsLines) {
            $0.toggleWrapLines()
        }
        XCTAssertNotEqual(preferences, .default)

        preferences.reset()
        XCTAssertEqual(preferences, .default)
    }

    func testRoundTripUsesDeterministicCompactSortedJSON() throws {
        let preferences = try EditorDisplayPreferences(
            font: EditorFontDescriptor(familyName: "JetBrains Mono", pointSize: 15.5),
            zoomStep: 13,
            syntaxHighlightingLanguage: .swift,
            showsWhitespace: true,
            showsEndOfLineMarkers: true,
            showsLineDifferences: false,
            showsLineNumbers: true,
            showsMargins: true,
            showsTopMargin: true,
            wrapsLines: true
        )
        let expectedJSON =
            #"{"font":{"family":"named","familyName":"JetBrains Mono","pointSize":15.5},"#
            + #""schemaVersion":1,"showsEndOfLineMarkers":true,"showsLineDifferences":false,"#
            + #""showsLineNumbers":true,"showsMargins":true,"showsTopMargin":true,"#
            + #""showsWhitespace":true,"syntaxHighlightingLanguage":"swift","#
            + #""wrapsLines":true,"zoomStep":13}"#

        let first = try preferences.encodedData()
        let second = try preferences.encodedData()

        XCTAssertEqual(first, second)
        XCTAssertEqual(String(decoding: first, as: UTF8.self), expectedJSON)
        XCTAssertFalse(first.contains(0x0A))
        XCTAssertLessThanOrEqual(first.count, EditorDisplayPreferences.maximumEncodedBytes)
        XCTAssertEqual(try EditorDisplayPreferences.decode(from: first), preferences)
        XCTAssertEqual(
            try EditorDisplayPreferences.decode(from: first).encodedData(),
            first
        )
        requireSendable(preferences)
        requireSendable(EditorDisplayPreferencesError.invalidZoomStep(0))
        requireSendable(EditorFontDescriptorError.invalidFamilyName)
    }

    func testDecodeEnforcesExactEncodedByteBoundary() throws {
        var exactBoundary = try EditorDisplayPreferences.default.encodedData()
        XCTAssertLessThan(exactBoundary.count, EditorDisplayPreferences.maximumEncodedBytes)
        exactBoundary.append(
            Data(
                repeating: 0x20,
                count: EditorDisplayPreferences.maximumEncodedBytes - exactBoundary.count
            )
        )

        XCTAssertEqual(exactBoundary.count, EditorDisplayPreferences.maximumEncodedBytes)
        XCTAssertEqual(
            try EditorDisplayPreferences.decode(from: exactBoundary),
            .default
        )

        var oversized = exactBoundary
        oversized.append(0x20)
        assertPreferencesError(
            .encodedDataTooLarge(maximumBytes: EditorDisplayPreferences.maximumEncodedBytes)
        ) {
            _ = try EditorDisplayPreferences.decode(from: oversized)
        }
    }

    func testDecodeRejectsTruncatedJSONLiteralsWithoutTrapping() {
        for payload in ["t", "tr", "tru", "f", "fa", "fal", "fals", "n", "nu", "nul"] {
            XCTAssertThrowsError(
                try EditorDisplayPreferences.decode(from: Data(payload.utf8)),
                "Truncated literal must fail: \(payload)"
            )
        }
    }

    func testDecodeRejectsLiteralAndEscapedEquivalentDuplicateKeysAtEveryObjectDepth() {
        let payloads = [
            (
                "literal root duplicate",
                replacing(
                    #""schemaVersion":1"#,
                    with: #""schemaVersion":1,"schemaVersion":1"#
                )
            ),
            (
                "escaped-equivalent root duplicate",
                replacing(
                    #""schemaVersion":1"#,
                    with: #""schemaVersion":1,"schema\u0056ersion":1"#
                )
            ),
            (
                "literal nested duplicate",
                replacing(
                    #""family":"systemMonospaced""#,
                    with: #""family":"systemMonospaced","family":"systemMonospaced""#
                )
            ),
            (
                "escaped-equivalent nested duplicate",
                replacing(
                    #""family":"systemMonospaced""#,
                    with: #""family":"systemMonospaced","fam\u0069ly":"systemMonospaced""#
                )
            )
        ]

        for (message, payload) in payloads {
            XCTAssertThrowsError(
                try EditorDisplayPreferences.decode(from: payload),
                message
            )
        }
    }

    func testDecodeRejectsUnsupportedSchemaAndInvalidSemanticValues() {
        for version in [Int.min, 0, 2, Int.max] {
            assertPreferencesError(.unsupportedSchemaVersion(version)) {
                _ = try EditorDisplayPreferences.decode(
                    from: replacing(#""schemaVersion":1"#, with: #""schemaVersion":\#(version)"#)
                )
            }
        }

        for zoomStep in [
            EditorDisplayPreferences.minimumZoomStep - 1,
            EditorDisplayPreferences.maximumZoomStep + 1
        ] {
            assertPreferencesError(.invalidZoomStep(zoomStep)) {
                _ = try EditorDisplayPreferences.decode(
                    from: replacing(#""zoomStep":10"#, with: #""zoomStep":\#(zoomStep)"#)
                )
            }
        }

        for language in ["", "Swift", "objectiveC"] {
            assertPreferencesError(.invalidSyntaxHighlightingLanguage(language)) {
                _ = try EditorDisplayPreferences.decode(
                    from: replacing(
                        #""syntaxHighlightingLanguage":"plainText"#,
                        with: #""syntaxHighlightingLanguage":"\#(language)"#
                    )
                )
            }
        }

        for pointSize in [0.0, 73.0] {
            assertFontError(.invalidPointSize(pointSize)) {
                _ = try EditorDisplayPreferences.decode(
                    from: replacing(#""pointSize":12"#, with: #""pointSize":\#(pointSize)"#)
                )
            }
        }
    }

    func testDecodeRequiresEveryRootAndNestedSchemaFieldWithExactTypes() throws {
        let requiredRootKeys = [
            "schemaVersion",
            "font",
            "zoomStep",
            "syntaxHighlightingLanguage",
            "showsWhitespace",
            "showsEndOfLineMarkers",
            "showsLineDifferences",
            "showsLineNumbers",
            "showsMargins",
            "showsTopMargin",
            "wrapsLines"
        ]
        let root = try defaultRootObject()
        XCTAssertEqual(Set(root.keys), Set(requiredRootKeys))

        for key in requiredRootKeys {
            var missingField = root
            missingField.removeValue(forKey: key)
            assertDecodingError(
                try JSONSerialization.data(withJSONObject: missingField),
                message: "Missing root key should fail: \(key)"
            )
        }

        let invalidRootValues: [(key: String, value: Any)] = [
            ("schemaVersion", "1"),
            ("font", "systemMonospaced"),
            ("zoomStep", "10"),
            ("syntaxHighlightingLanguage", false),
            ("showsWhitespace", "false"),
            ("showsEndOfLineMarkers", 0),
            ("showsLineDifferences", NSNull()),
            ("showsLineNumbers", "false"),
            ("showsMargins", 0),
            ("showsTopMargin", NSNull()),
            ("wrapsLines", "false")
        ]
        for (key, invalidValue) in invalidRootValues {
            var wrongType = root
            wrongType[key] = invalidValue
            assertDecodingError(
                try JSONSerialization.data(withJSONObject: wrongType),
                message: "Wrong root value type should fail: \(key)"
            )
        }

        for key in ["family", "pointSize"] {
            var missingNestedField = root
            var font = try XCTUnwrap(missingNestedField["font"] as? [String: Any])
            font.removeValue(forKey: key)
            missingNestedField["font"] = font
            assertDecodingError(
                try JSONSerialization.data(withJSONObject: missingNestedField),
                message: "Missing font key should fail: \(key)"
            )
        }

        var namedWithoutName = root
        var namedFont = try XCTUnwrap(namedWithoutName["font"] as? [String: Any])
        namedFont["family"] = "named"
        namedFont.removeValue(forKey: "familyName")
        namedWithoutName["font"] = namedFont
        assertDecodingError(try JSONSerialization.data(withJSONObject: namedWithoutName))

        var systemWithName = root
        var systemFont = try XCTUnwrap(systemWithName["font"] as? [String: Any])
        systemFont["familyName"] = "Mono"
        systemWithName["font"] = systemFont
        assertFontError(.invalidFamilyName) {
            _ = try EditorDisplayPreferences.decode(
                from: JSONSerialization.data(withJSONObject: systemWithName)
            )
        }
    }

    func testDecodeRejectsUnknownRootAndNestedKeys() throws {
        var unknownRoot = try defaultRootObject()
        unknownRoot["zeta"] = true
        unknownRoot["alpha"] = true
        assertUnknownKeys(
            try JSONSerialization.data(withJSONObject: unknownRoot),
            codingPath: [],
            description: "Unknown keys: alpha, zeta."
        )

        var unknownNested = try defaultRootObject()
        var font = try XCTUnwrap(unknownNested["font"] as? [String: Any])
        font["weight"] = "regular"
        font["future"] = false
        unknownNested["font"] = font
        assertUnknownKeys(
            try JSONSerialization.data(withJSONObject: unknownNested),
            codingPath: ["font"],
            description: "Unknown keys: future, weight."
        )
    }

    func testDecodeRejectsMalformedNonfiniteAndInvalidFontWireValues() {
        let malformedPayloads = [
            Data(),
            Data("null".utf8),
            Data("[]".utf8),
            Data("{".utf8),
            Data((Self.defaultJSON + " trailing").utf8),
            Data([0xFF]),
            replacing(#""pointSize":12"#, with: #""pointSize":1e400"#),
            replacing(#""pointSize":12"#, with: #""pointSize":NaN"#),
            replacing(#""pointSize":12"#, with: #""pointSize":"Infinity"#),
            replacing(#""zoomStep":10"#, with: #""zoomStep":1.5"#),
            replacing(
                Self.defaultFontJSON,
                with: #""font":{"family":"unknown","pointSize":12}"#
            ),
            replacing(
                Self.defaultFontJSON,
                with: #""font":{"family":"named","familyName":null,"pointSize":12}"#
            )
        ]

        for payload in malformedPayloads {
            XCTAssertThrowsError(try EditorDisplayPreferences.decode(from: payload))
        }
    }

    func testRestorationReturnsCompleteSnapshotOrDeterministicDefaults() throws {
        let custom = try EditorDisplayPreferences(
            font: EditorFontDescriptor(familyName: "SF Mono", pointSize: 16),
            zoomStep: 24,
            syntaxHighlightingLanguage: .json,
            showsWhitespace: true,
            showsEndOfLineMarkers: true,
            showsLineDifferences: false,
            showsLineNumbers: true,
            showsMargins: true,
            showsTopMargin: true,
            wrapsLines: true
        )
        let encoded = try custom.encodedData()
        XCTAssertEqual(EditorDisplayPreferences.restored(from: encoded), custom)
        XCTAssertEqual(EditorDisplayPreferences.restored(from: nil), .default)

        var oversized = encoded
        oversized.append(
            Data(
                repeating: 0x20,
                count: EditorDisplayPreferences.maximumEncodedBytes - encoded.count + 1
            )
        )
        let invalidPayloads = [
            Data(),
            Data("{".utf8),
            Data([0xFF]),
            oversized,
            replacing(#""schemaVersion":1"#, with: #""schemaVersion":2"#),
            replacing(
                #""syntaxHighlightingLanguage":"plainText"#,
                with: #""syntaxHighlightingLanguage":"future"#
            ),
            replacing(#""showsWhitespace":false"#, with: #""showsWhitespace":true,"future":1"#),
            replacing(#""wrapsLines":false"#, with: #""wrapsLines":"false"#)
        ]

        for payload in invalidPayloads {
            XCTAssertEqual(EditorDisplayPreferences.restored(from: payload), .default)
        }
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func assertToggle(
        _ preferences: inout EditorDisplayPreferences,
        keyPath: WritableKeyPath<EditorDisplayPreferences, Bool>,
        file: StaticString = #filePath,
        line: UInt = #line,
        action: (inout EditorDisplayPreferences) -> Bool
    ) {
        let before = preferences
        var expected = before
        expected[keyPath: keyPath].toggle()

        let returnedValue = action(&preferences)

        XCTAssertEqual(returnedValue, expected[keyPath: keyPath], file: file, line: line)
        XCTAssertNotEqual(
            preferences[keyPath: keyPath],
            before[keyPath: keyPath],
            "Target preference did not mutate",
            file: file,
            line: line
        )
        XCTAssertEqual(
            preferences,
            expected,
            "Toggle mutated untargeted preferences",
            file: file,
            line: line
        )
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }

    private func defaultRootObject() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Self.defaultJSON.utf8)) as? [String: Any]
        )
    }

    private func assertFontError(
        _ expected: EditorFontDescriptorError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? EditorFontDescriptorError, expected, file: file, line: line)
        }
    }

    private func assertPreferencesError(
        _ expected: EditorDisplayPreferencesError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? EditorDisplayPreferencesError, expected, file: file, line: line)
        }
    }

    private func assertDecodingError(
        _ data: Data,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try EditorDisplayPreferences.decode(from: data),
            message,
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                error is DecodingError,
                "Expected DecodingError, got \(error)",
                file: file,
                line: line
            )
        }
    }

    private func assertUnknownKeys(
        _ data: Data,
        codingPath: [String],
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try EditorDisplayPreferences.decode(from: data),
            file: file,
            line: line
        ) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected dataCorrupted, got \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), codingPath, file: file, line: line)
            XCTAssertEqual(context.debugDescription, description, file: file, line: line)
        }
    }

    private func replacing(_ target: String, with replacement: String) -> Data {
        let replaced = Self.defaultJSON.replacingOccurrences(of: target, with: replacement)
        XCTAssertNotEqual(replaced, Self.defaultJSON, "Test fixture replacement did not match")
        return Data(replaced.utf8)
    }
}
