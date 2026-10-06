import Foundation
import MacMergeCore
import XCTest

final class ComparisonPreferencesWorkflowTests: XCTestCase {
    func testModesMapProjectsDefaultsSettingsAndOpenOptionsExhaustively() throws {
        XCTAssertEqual(
            ComparisonPreferencesMode.allCases,
            [.text, .folder, .table, .binary, .image, .webpage]
        )
        XCTAssertNil(ComparisonPreferencesMode(comparisonProjectMode: .automatic))

        for mode in ComparisonPreferencesMode.allCases {
            XCTAssertEqual(ComparisonPreferencesMode(comparisonProjectMode: mode.comparisonProjectMode), mode)
            let settings = ComparisonPreferencesModeSettings.defaults(for: mode)
            XCTAssertEqual(settings.mode, mode)
            XCTAssertEqual(ComparisonPreferences.default.settings(for: mode), settings)
            switch (mode, settings, settings.comparisonOpenModeOptions) {
            case (.text, .text(let value), .text(let twoWay, let threeWay)):
                XCTAssertEqual(value.twoWay, LineDiffOptions())
                XCTAssertEqual(value.threeWay, ThreeWayTextMergeOptions())
                XCTAssertEqual(value.displayFilter, DisplayFilter())
                XCTAssertEqual(twoWay, value.twoWay)
                XCTAssertEqual(threeWay, value.threeWay)
            case (.folder, .folder(let value), .folder(let scanning, let twoWay, let threeWay)):
                XCTAssertEqual(value.scanning, FolderScanOptions())
                XCTAssertEqual(value.twoWay, FolderComparisonOptions())
                XCTAssertEqual(value.threeWay, ThreeWayFolderComparisonOptions())
                XCTAssertEqual(value.filenameFilter, .default)
                XCTAssertEqual(value.resultFilter, DirectoryResultFilter())
                XCTAssertEqual(scanning, value.scanning)
                XCTAssertEqual(twoWay, value.twoWay)
                XCTAssertEqual(threeWay, value.threeWay)
            case (.table, .table(let value), .table(let parsing, let twoWay, let threeWay)):
                XCTAssertEqual(value.parsing, .commaSeparated)
                XCTAssertEqual(value.twoWay, .default)
                XCTAssertEqual(value.threeWay, .default)
                XCTAssertEqual(value.presentation, .default)
                XCTAssertEqual(parsing, value.parsing)
                XCTAssertEqual(twoWay, value.twoWay)
                XCTAssertEqual(threeWay, value.threeWay)
            case (.binary, .binary(let value), .binary(let twoWay, let threeWay)):
                XCTAssertEqual(value.twoWay, BinaryComparisonOptions())
                XCTAssertEqual(value.threeWay, .default)
                XCTAssertEqual(value.bytesPerRow, 16)
                XCTAssertEqual(twoWay, value.twoWay)
                XCTAssertEqual(threeWay, value.threeWay)
            case (.image, .image(let value), .image(let loading, let comparison)):
                XCTAssertEqual(value.loading, .default)
                XCTAssertEqual(value.controls, .default)
                XCTAssertEqual(loading, value.loading)
                XCTAssertEqual(comparison, value.controls.differences.pixelComparison)
            case (.webpage, .webpage(let value), .webpage(let twoWay, let threeWay)):
                XCTAssertEqual(value.twoWay, .default)
                XCTAssertEqual(value.threeWay, .default)
                XCTAssertEqual(value.displayFilter, DisplayFilter())
                XCTAssertEqual(twoWay, value.twoWay)
                XCTAssertEqual(threeWay, value.threeWay)
            default:
                XCTFail("Mismatched settings projection for \(mode)")
            }
            XCTAssertEqual(
                ComparisonPreferences.default.comparisonOpenModeOptions(for: mode.comparisonProjectMode),
                settings.comparisonOpenModeOptions
            )
        }
        XCTAssertNil(ComparisonPreferences.default.comparisonOpenModeOptions(for: .automatic))
    }

    func testEveryModeRetainsCustomSettingsAndProjectsExactEngineOptions() throws {
        let settings = try customSettings()
        var preferences = ComparisonPreferences.default
        var expected = Dictionary(
            uniqueKeysWithValues: ComparisonPreferencesMode.allCases.map {
                ($0, ComparisonPreferencesModeSettings.defaults(for: $0))
            }
        )

        for setting in settings {
            preferences = try preferences.replacing(setting)
            expected[setting.mode] = setting
            for mode in ComparisonPreferencesMode.allCases {
                XCTAssertEqual(preferences.settings(for: mode), expected[mode], "Mode: \(mode)")
            }
            XCTAssertEqual(
                preferences.comparisonOpenModeOptions(for: setting.mode.comparisonProjectMode),
                setting.comparisonOpenModeOptions
            )
        }

        XCTAssertEqual(preferences, try customPreferences())
        assertCustomPreferenceFields(preferences)
        guard case .folder(let folder) = preferences.settings(for: .folder) else {
            return XCTFail("Expected folder settings")
        }
        XCTAssertEqual(folder.filenameFilter.comparisonOpenFilter.rules, folder.filenameFilter.rules)
        XCTAssertEqual(folder.filenameFilter.comparisonOpenFilter.defaultDecision, .exclude)
        XCTAssertEqual(folder.filenameFilter.comparisonOpenFilter.matchSemantics, .firstMatchWins)
        XCTAssertEqual(folder.filenameFilter.comparisonOpenFilter.casePolicy, .insensitive)
        XCTAssertEqual(folder.filenameFilter.comparisonOpenFilter.limits, folder.filenameFilter.limits)
    }

    func testApplyingLineOptionsChangesOnlyTextAndWebpageProjects() throws {
        let preferences = try customPreferences()
        let originalOptions = LineDiffOptions(ignoreBlankLines: true)

        for mode in ComparisonProject.Mode.allCases {
            let project = try ComparisonProject(
                mode: mode,
                sides: [
                    try ComparisonProject.Side(
                        identity: .left,
                        path: URL(fileURLWithPath: "/left"),
                        readOnly: true
                    ),
                    try ComparisonProject.Side(
                        identity: .right,
                        path: URL(fileURLWithPath: "/right")
                    )
                ],
                recursive: true,
                filter: .named("source-filter"),
                lineDiffOptions: originalOptions
            )

            let applied = try preferences.applyingLineOptions(to: project)
            let expected =
                switch mode {
                case .text: preferences.text.twoWay
                case .webpage: preferences.webpage.twoWay.lineDiffOptions
                case .automatic, .folder, .table, .binary, .image: originalOptions
                }
            XCTAssertEqual(applied.lineDiffOptions, expected, "Mode: \(mode)")
            XCTAssertEqual(applied.mode, project.mode)
            XCTAssertEqual(applied.sides, project.sides)
            XCTAssertEqual(applied.recursive, project.recursive)
            XCTAssertEqual(applied.filter, project.filter)
        }
    }

    func testWorkflowLimitDefaultsHardCeilingsAndEveryInvalidBoundary() throws {
        let defaults = ComparisonPreferencesWorkflowLimits.default
        XCTAssertEqual(defaults.maximumOptionItems, 4_096)
        XCTAssertEqual(defaults.maximumOptionStringUTF8Bytes, 64 * 1_024)
        XCTAssertEqual(defaults.maximumTotalOptionStringUTF8Bytes, 4 * 1_024 * 1_024)
        XCTAssertEqual(defaults.maximumPersistenceInputBytes, 8 * 1_024 * 1_024)
        XCTAssertEqual(defaults.maximumPersistenceOutputBytes, 8 * 1_024 * 1_024)
        XCTAssertEqual(defaults.maximumWorkUnits, 64 * 1_024 * 1_024)
        XCTAssertEqual(defaults.cancellationCheckInterval, 4_096)

        let hardMaximums = try ComparisonPreferencesWorkflowLimits(
            maximumOptionItems: ComparisonPreferencesWorkflowLimits.hardMaximumOptionItems,
            maximumOptionStringUTF8Bytes: ComparisonPreferencesWorkflowLimits.hardMaximumOptionStringUTF8Bytes,
            maximumTotalOptionStringUTF8Bytes: ComparisonPreferencesWorkflowLimits.hardMaximumTotalOptionStringUTF8Bytes,
            maximumPersistenceInputBytes: ComparisonPreferencesWorkflowLimits.hardMaximumPersistenceBytes,
            maximumPersistenceOutputBytes: ComparisonPreferencesWorkflowLimits.hardMaximumPersistenceBytes,
            maximumWorkUnits: ComparisonPreferencesWorkflowLimits.hardMaximumWorkUnits,
            cancellationCheckInterval: ComparisonPreferencesWorkflowLimits.hardMaximumCancellationCheckInterval
        )
        XCTAssertEqual(hardMaximums.maximumOptionItems, ComparisonPreferencesWorkflowLimits.hardMaximumOptionItems)
        XCTAssertEqual(
            hardMaximums.maximumOptionStringUTF8Bytes,
            ComparisonPreferencesWorkflowLimits.hardMaximumOptionStringUTF8Bytes
        )
        XCTAssertEqual(
            hardMaximums.maximumTotalOptionStringUTF8Bytes,
            ComparisonPreferencesWorkflowLimits.hardMaximumTotalOptionStringUTF8Bytes
        )
        XCTAssertEqual(
            hardMaximums.maximumPersistenceInputBytes,
            ComparisonPreferencesWorkflowLimits.hardMaximumPersistenceBytes
        )
        XCTAssertEqual(
            hardMaximums.maximumPersistenceOutputBytes,
            ComparisonPreferencesWorkflowLimits.hardMaximumPersistenceBytes
        )
        XCTAssertEqual(hardMaximums.maximumWorkUnits, ComparisonPreferencesWorkflowLimits.hardMaximumWorkUnits)
        XCTAssertEqual(
            hardMaximums.cancellationCheckInterval,
            ComparisonPreferencesWorkflowLimits.hardMaximumCancellationCheckInterval
        )

        let minimums = try ComparisonPreferencesWorkflowLimits(
            maximumOptionItems: 0,
            maximumOptionStringUTF8Bytes: 0,
            maximumTotalOptionStringUTF8Bytes: 0,
            maximumPersistenceInputBytes: 1,
            maximumPersistenceOutputBytes: 1,
            maximumWorkUnits: 1,
            cancellationCheckInterval: 1
        )
        XCTAssertEqual(minimums.maximumOptionItems, 0)
        XCTAssertEqual(minimums.maximumOptionStringUTF8Bytes, 0)
        XCTAssertEqual(minimums.maximumTotalOptionStringUTF8Bytes, 0)
        XCTAssertEqual(minimums.maximumPersistenceInputBytes, 1)
        XCTAssertEqual(minimums.maximumPersistenceOutputBytes, 1)
        XCTAssertEqual(minimums.maximumWorkUnits, 1)
        XCTAssertEqual(minimums.cancellationCheckInterval, 1)

        let invalidCases: [(ComparisonPreferencesLimit, () throws -> Void)] = [
            (.optionItems, { _ = try ComparisonPreferencesWorkflowLimits(maximumOptionItems: -1) }),
            (
                .optionItems,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        maximumOptionItems: ComparisonPreferencesWorkflowLimits.hardMaximumOptionItems + 1
                    )
                }
            ),
            (.optionStringUTF8Bytes, { _ = try ComparisonPreferencesWorkflowLimits(maximumOptionStringUTF8Bytes: -1) }),
            (
                .optionStringUTF8Bytes,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        maximumOptionStringUTF8Bytes: ComparisonPreferencesWorkflowLimits.hardMaximumOptionStringUTF8Bytes + 1
                    )
                }
            ),
            (
                .totalOptionStringUTF8Bytes,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        maximumOptionStringUTF8Bytes: 2,
                        maximumTotalOptionStringUTF8Bytes: 1
                    )
                }
            ),
            (
                .totalOptionStringUTF8Bytes,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        maximumOptionStringUTF8Bytes: 0,
                        maximumTotalOptionStringUTF8Bytes: -1
                    )
                }
            ),
            (
                .totalOptionStringUTF8Bytes,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        maximumTotalOptionStringUTF8Bytes:
                            ComparisonPreferencesWorkflowLimits.hardMaximumTotalOptionStringUTF8Bytes + 1
                    )
                }
            ),
            (.persistenceInputBytes, { _ = try ComparisonPreferencesWorkflowLimits(maximumPersistenceInputBytes: 0) }),
            (
                .persistenceInputBytes,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        maximumPersistenceInputBytes: ComparisonPreferencesWorkflowLimits.hardMaximumPersistenceBytes + 1
                    )
                }
            ),
            (.persistenceOutputBytes, { _ = try ComparisonPreferencesWorkflowLimits(maximumPersistenceOutputBytes: 0) }),
            (
                .persistenceOutputBytes,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        maximumPersistenceOutputBytes: ComparisonPreferencesWorkflowLimits.hardMaximumPersistenceBytes + 1
                    )
                }
            ),
            (.workUnits, { _ = try ComparisonPreferencesWorkflowLimits(maximumWorkUnits: 0) }),
            (
                .workUnits,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        maximumWorkUnits: ComparisonPreferencesWorkflowLimits.hardMaximumWorkUnits + 1
                    )
                }
            ),
            (.cancellationCheckInterval, { _ = try ComparisonPreferencesWorkflowLimits(cancellationCheckInterval: 0) }),
            (
                .cancellationCheckInterval,
                {
                    _ = try ComparisonPreferencesWorkflowLimits(
                        cancellationCheckInterval:
                            ComparisonPreferencesWorkflowLimits.hardMaximumCancellationCheckInterval + 1
                    )
                }
            )
        ]

        for (expected, operation) in invalidCases {
            assertWorkflowError(.invalidLimit(expected), operation)
        }
    }

    func testOptionItemPerStringAndTotalStringLimitsUseExactUTF8Boundaries() throws {
        let oneItemLimits = try limits(
            maximumOptionItems: 1,
            maximumOptionStringUTF8Bytes: 4,
            maximumTotalOptionStringUTF8Bytes: 4
        )
        _ = try TextComparisonPreferences(
            twoWay: LineDiffOptions(
                lineFiltersEnabled: false,
                lineFilters: [LineFilterRule(pattern: "éé")]
            ),
            limits: oneItemLimits
        )

        assertWorkflowError(.tooManyOptionItems(maximumCount: 1)) {
            _ = try TextComparisonPreferences(
                twoWay: LineDiffOptions(
                    lineFiltersEnabled: false,
                    lineFilters: [LineFilterRule(pattern: "a"), LineFilterRule(pattern: "b")]
                ),
                limits: oneItemLimits
            )
        }
        assertWorkflowError(
            .optionStringTooLarge(field: "text.twoWay.lineFilters[0].pattern", maximumUTF8Bytes: 4)
        ) {
            _ = try TextComparisonPreferences(
                twoWay: LineDiffOptions(
                    lineFiltersEnabled: false,
                    lineFilters: [LineFilterRule(pattern: "ééa")]
                ),
                limits: oneItemLimits
            )
        }

        let totalLimits = try limits(
            maximumOptionItems: 2,
            maximumOptionStringUTF8Bytes: 2,
            maximumTotalOptionStringUTF8Bytes: 3
        )
        _ = try TextComparisonPreferences(
            twoWay: LineDiffOptions(
                lineFiltersEnabled: false,
                lineFilters: [LineFilterRule(pattern: "é"), LineFilterRule(pattern: "a")]
            ),
            limits: totalLimits
        )
        assertWorkflowError(.totalOptionStringsTooLarge(maximumUTF8Bytes: 3)) {
            _ = try TextComparisonPreferences(
                twoWay: LineDiffOptions(
                    lineFiltersEnabled: false,
                    lineFilters: [LineFilterRule(pattern: "é"), LineFilterRule(pattern: "ab")]
                ),
                limits: totalLimits
            )
        }
    }

    func testRegexCeilingIsExactly4096UTF8BytesAcrossAllPreferenceSurfaces() throws {
        let exact = String(repeating: "a", count: 4_096)
        let oversized = exact + "a"
        _ = try TextComparisonPreferences(
            twoWay: LineDiffOptions(lineFiltersEnabled: false, lineFilters: [.init(pattern: exact)])
        )
        _ = try TextComparisonPreferences(
            twoWay: LineDiffOptions(
                substitutionsEnabled: false,
                substitutions: [.init(pattern: exact, replacement: "")]
            )
        )
        _ = try TextComparisonPreferences(displayFilter: DisplayFilter(regularExpression: exact))
        _ = try FolderFilenameFilterPreferences(
            rules: [.init(.include, pattern: .regularExpression(exact))]
        )
        _ = try WebpageComparisonPreferences(
            twoWay: WebPageComparisonOptions(
                lineDiffOptions: LineDiffOptions(
                    lineFiltersEnabled: false,
                    lineFilters: [.init(pattern: exact)],
                    substitutionsEnabled: false,
                    substitutions: [.init(pattern: exact, replacement: "")]
                )
            ),
            displayFilter: DisplayFilter(regularExpression: exact)
        )

        let cases: [(String, () throws -> Void)] = [
            (
                "text.twoWay.lineFilters[0].pattern",
                {
                    _ = try TextComparisonPreferences(
                        twoWay: LineDiffOptions(
                            lineFiltersEnabled: false,
                            lineFilters: [.init(pattern: oversized)]
                        )
                    )
                }
            ),
            (
                "text.twoWay.substitutions[0].pattern",
                {
                    _ = try TextComparisonPreferences(
                        twoWay: LineDiffOptions(
                            substitutionsEnabled: false,
                            substitutions: [.init(pattern: oversized, replacement: "")]
                        )
                    )
                }
            ),
            (
                "text.displayFilter.expression",
                { _ = try TextComparisonPreferences(displayFilter: DisplayFilter(regularExpression: oversized)) }
            ),
            (
                "folder.filenameFilter.rules[0].pattern",
                {
                    _ = try FolderFilenameFilterPreferences(
                        rules: [.init(.include, pattern: .regularExpression(oversized))]
                    )
                }
            ),
            (
                "webpage.twoWay.lineDiffOptions.lineFilters[0].pattern",
                {
                    _ = try WebpageComparisonPreferences(
                        twoWay: WebPageComparisonOptions(
                            lineDiffOptions: LineDiffOptions(
                                lineFiltersEnabled: false,
                                lineFilters: [.init(pattern: oversized)]
                            )
                        )
                    )
                }
            ),
            (
                "webpage.twoWay.lineDiffOptions.substitutions[0].pattern",
                {
                    _ = try WebpageComparisonPreferences(
                        twoWay: WebPageComparisonOptions(
                            lineDiffOptions: LineDiffOptions(
                                substitutionsEnabled: false,
                                substitutions: [.init(pattern: oversized, replacement: "")]
                            )
                        )
                    )
                }
            ),
            (
                "webpage.displayFilter.expression",
                { _ = try WebpageComparisonPreferences(displayFilter: DisplayFilter(regularExpression: oversized)) }
            )
        ]
        for (field, operation) in cases {
            assertWorkflowError(.optionStringTooLarge(field: field, maximumUTF8Bytes: 4_096), operation)
        }
    }

    func testTextFolderAndWebpageRejectInvalidRegexesAndLeafCrossFieldValues() throws {
        let invalidRegexes: [(ComparisonPreferencesWorkflowError, () throws -> Void)] = [
            (
                .invalidOption(mode: .text, field: "text.twoWay.regularExpressions"),
                {
                    _ = try TextComparisonPreferences(
                        twoWay: LineDiffOptions(lineFilters: [.init(pattern: "[")])
                    )
                }
            ),
            (
                .invalidOption(mode: .text, field: "displayFilter"),
                { _ = try TextComparisonPreferences(displayFilter: DisplayFilter(regularExpression: "[")) }
            ),
            (
                .invalidOption(mode: .folder, field: "filenameFilter.rules"),
                {
                    _ = try FolderFilenameFilterPreferences(
                        rules: [.init(.include, pattern: .regularExpression("(?=unsupported)"))]
                    )
                }
            ),
            (
                .invalidOption(mode: .webpage, field: "webpage.twoWay.lineDiffOptions.regularExpressions"),
                {
                    _ = try WebpageComparisonPreferences(
                        twoWay: WebPageComparisonOptions(
                            lineDiffOptions: LineDiffOptions(substitutions: [.init(pattern: "[", replacement: "")])
                        )
                    )
                }
            ),
            (
                .invalidOption(mode: .webpage, field: "displayFilter"),
                { _ = try WebpageComparisonPreferences(displayFilter: DisplayFilter(regularExpression: "[")) }
            )
        ]
        for (error, operation) in invalidRegexes {
            assertWorkflowError(error, operation)
        }

        assertWorkflowError(.invalidOption(mode: .text, field: "text.twoWay.commentSyntax")) {
            _ = try TextComparisonPreferences(twoWay: LineDiffOptions(commentSyntax: .cFamily))
        }
        assertWorkflowError(
            .invalidCrossField(mode: .text, fields: "displayFilter.predicate, detectMovedBlocks")
        ) {
            _ = try TextComparisonPreferences(displayFilter: DisplayFilter(predicate: .moved))
        }
        assertWorkflowError(.invalidOption(mode: .folder, field: "resultFilter.pathQuery")) {
            _ = try FolderComparisonPreferences(resultFilter: DirectoryResultFilter(pathQuery: "bad\0query"))
        }
        assertWorkflowError(
            .invalidCrossField(mode: .folder, fields: "scanning.hiddenFilePolicy, resultFilter.hidden")
        ) {
            _ = try FolderComparisonPreferences(
                scanning: FolderScanOptions(hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets),
                resultFilter: DirectoryResultFilter(hidden: .only)
            )
        }
        let noFollowCapacity = FolderScanLimits(
            maximumOpenDirectoryDescriptors: 0,
            maximumPendingEntryNames: 0
        )
        assertWorkflowError(
            .invalidCrossField(mode: .folder, fields: "scanning.symbolicLinkPolicy, scanning.limits")
        ) {
            _ = try FolderComparisonPreferences(
                scanning: FolderScanOptions(
                    symbolicLinkPolicy: .followDirectoriesWithinRoot,
                    limits: noFollowCapacity
                )
            )
        }
        for identifier in ["", "bad\0context"] {
            assertWorkflowError(.invalidOption(mode: .webpage, field: "threeWay.expectedContext.identifier")) {
                _ = try WebpageComparisonPreferences(
                    threeWay: ThreeWayWebPageComparisonOptions(
                        expectedContext: ThreeWayWebPageComparisonContext(identifier: identifier, generation: 1)
                    )
                )
            }
        }
        assertWorkflowError(
            .invalidCrossField(mode: .webpage, fields: "displayFilter.predicate, detectMovedBlocks")
        ) {
            _ = try WebpageComparisonPreferences(displayFilter: DisplayFilter(predicate: .moved))
        }
    }

    func testFilenameFilterPreferencesPreserveRuleOrderSemanticsApplicabilityAndCasePolicy() throws {
        let rules = [
            FilenameFilterRule(.exclude, pattern: .glob("**/*.tmp"), applicability: .files),
            FilenameFilterRule(.include, pattern: .regularExpression("^sources/"), applicability: .files)
        ]
        let first = try FolderFilenameFilterPreferences(
            rules: rules,
            defaultDecision: .exclude,
            matchSemantics: .firstMatchWins,
            casePolicy: .insensitive
        )
        let last = try FolderFilenameFilterPreferences(
            rules: rules,
            defaultDecision: .exclude,
            matchSemantics: .lastMatchWins,
            casePolicy: .insensitive
        )

        let firstFilter = try compiled(first.comparisonOpenFilter)
        let lastFilter = try compiled(last.comparisonOpenFilter)
        XCTAssertEqual(
            try firstFilter.evaluate(relativePath: "Sources/CACHE.TMP", kind: .file).decision,
            .exclude
        )
        XCTAssertEqual(
            try lastFilter.evaluate(relativePath: "Sources/CACHE.TMP", kind: .file).decision,
            .include
        )
        XCTAssertEqual(
            try lastFilter.evaluate(relativePath: "Sources/CACHE.TMP", kind: .directory).decision,
            .exclude
        )
        XCTAssertTrue(firstFilter.diagnostics.isEmpty)
        XCTAssertTrue(lastFilter.diagnostics.isEmpty)
    }

    func testFilenameFilterPreferencesRejectInvalidRulesAndDeclaredLimitMismatch() {
        assertWorkflowError(.invalidOption(mode: .folder, field: "filenameFilter.rules")) {
            _ = try FolderFilenameFilterPreferences(rules: [.init(.exclude, pattern: .glob("["))])
        }
        assertWorkflowError(
            .invalidCrossField(
                mode: .folder,
                fields: "filenameFilter.rules, filenameFilter.limits.maximumRuleCount"
            )
        ) {
            _ = try FolderFilenameFilterPreferences(
                rules: [.init(.include, pattern: .glob("a"))],
                limits: FilenameFilterLimits(maximumRuleCount: 0)
            )
        }
        assertWorkflowError(.invalidOption(mode: .folder, field: "filenameFilter.limits.maximumMatchWork")) {
            _ = try FolderFilenameFilterPreferences(
                limits: FilenameFilterLimits(
                    maximumMatchWork: FilenameFilterLimits.default.maximumMatchWork + 1
                )
            )
        }
    }

    func testModeValidationRejectsCrossFieldAndScalarErrorsForEveryMode() {
        assertWorkflowError(
            .invalidCrossField(mode: .text, fields: "twoWay.algorithm, threeWay.diffAlgorithm")
        ) {
            _ = try TextComparisonPreferences(
                twoWay: LineDiffOptions(algorithm: .minimal),
                threeWay: ThreeWayTextMergeOptions(diffAlgorithm: .histogram)
            )
        }
        assertWorkflowError(.invalidCrossField(mode: .folder, fields: "twoWay, threeWay.comparison")) {
            _ = try FolderComparisonPreferences(
                twoWay: FolderComparisonOptions(method: .contentIfAvailable),
                threeWay: .default
            )
        }
        assertWorkflowError(.invalidCrossField(mode: .table, fields: "parsing, threeWay.parsingOptions")) {
            _ = try TableComparisonPreferences(parsing: .tabSeparated)
        }
        assertWorkflowError(.invalidOption(mode: .binary, field: "bytesPerRow")) {
            _ = try BinaryComparisonPreferences(bytesPerRow: 0)
        }
        assertWorkflowError(.invalidOption(mode: .image, field: "controls.zoom.scale")) {
            _ = try ImageComparisonPreferences(
                controls: ImageToolControlState(zoom: ImageToolZoom(scale: .infinity))
            )
        }
        assertWorkflowError(
            .invalidCrossField(
                mode: .webpage,
                fields: "twoWay.lineDiffOptions.algorithm, threeWay.diffAlgorithm"
            )
        ) {
            _ = try WebpageComparisonPreferences(
                twoWay: WebPageComparisonOptions(lineDiffOptions: LineDiffOptions(algorithm: .patience)),
                threeWay: ThreeWayWebPageComparisonOptions(diffAlgorithm: .histogram)
            )
        }
    }

    func testCanonicalPersistenceIsDeterministicRoundTrippableAndDigestStable() throws {
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 0xA11CE, generation: 42),
            preferences: customPreferences()
        )
        let first = try snapshot.encodedDocument()
        let second = try snapshot.encodedDocument()
        let decoded = try ComparisonPreferencesSnapshot.decodeDocument(from: first.data)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.sha256.count, 32)
        XCTAssertGreaterThan(first.workUnits, first.data.count)
        XCTAssertEqual(decoded.snapshot, snapshot)
        XCTAssertEqual(decoded.sha256, first.sha256)
        XCTAssertGreaterThan(decoded.workUnits, first.workUnits)
        XCTAssertEqual(try decoded.snapshot.encodedData(), first.data)
        XCTAssertFalse(first.data.contains(0x0A))
        XCTAssertFalse(first.data.contains(0x0D))
        XCTAssertFalse(first.data.contains(0x09))
        XCTAssertFalse(first.data.contains(0x20))
    }

    func testCanonicalPersistenceSafelyCarriesScannerTokensInsideStringLeaves() throws {
        let adversary = #"{}[],:\"\\ true false null -12.5e+7 \u005d </script> é"#
        let text = try TextComparisonPreferences(
            twoWay: LineDiffOptions(
                lineFiltersEnabled: false,
                lineFilters: [.init(pattern: NSRegularExpression.escapedPattern(for: adversary))]
            ),
            displayFilter: DisplayFilter(literal: adversary)
        )
        let folder = try FolderComparisonPreferences(
            resultFilter: DirectoryResultFilter(pathQuery: adversary)
        )
        let webpage = try WebpageComparisonPreferences(
            threeWay: ThreeWayWebPageComparisonOptions(
                expectedContext: ThreeWayWebPageComparisonContext(identifier: adversary, generation: 9)
            )
        )
        let preferences = try ComparisonPreferences(text: text, folder: folder, webpage: webpage)
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 10),
            preferences: preferences
        )

        let document = try snapshot.encodedDocument()
        XCTAssertEqual(try ComparisonPreferencesSnapshot.decode(from: document.data), snapshot)
        XCTAssertEqual(try snapshot.encodedData(), document.data)
    }

    func testDefaultPersistenceGoldenStructureSchemaAndDigest() throws {
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 1, generation: 2)
        )
        let document = try snapshot.encodedDocument()
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: document.data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(root.keys),
            Set(["binary", "folder", "image", "revision", "schemaVersion", "table", "text", "webpage"])
        )
        XCTAssertEqual(root["schemaVersion"] as? Int, ComparisonPreferences.currentSchemaVersion)
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        let revision = try XCTUnwrap(root["revision"] as? [String: Any])
        XCTAssertEqual(Set(revision.keys), Set(["generation", "lineage"]))
        XCTAssertEqual(revision["lineage"] as? Int, 1)
        XCTAssertEqual(revision["generation"] as? Int, 2)
        XCTAssertEqual(
            Set(try XCTUnwrap(root["text"] as? [String: Any]).keys),
            Set(["displayFilter", "threeWay", "twoWay"])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["folder"] as? [String: Any]).keys),
            Set(["filenameFilter", "resultFilter", "scanning", "threeWay", "twoWay"])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["table"] as? [String: Any]).keys),
            Set(["parsing", "presentation", "threeWay", "twoWay"])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["binary"] as? [String: Any]).keys),
            Set(["bytesPerRow", "threeWay", "twoWay"])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["image"] as? [String: Any]).keys),
            Set(["controls", "loading"])
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["webpage"] as? [String: Any]).keys),
            Set(["displayFilter", "threeWay", "twoWay"])
        )
        XCTAssertEqual(document.data.count, 5_489)
        XCTAssertEqual(hex(document.sha256), "2f24c3f8689f90a386b67940805efb84f1f3d21fb0404273666e27cbd9cab382")
    }

    func testCanonicalPersistenceNormalizesNegativeZeroAndUnorderedSets() throws {
        let firstStatuses: Set<DirectoryComparisonStatus> = [.error, .pending, .different]
        let secondStatuses = set(insertionOrder: [
            DirectoryComparisonStatus.different, .pending, .error
        ])
        let firstKinds: Set<DirectoryEntryKind> = [.symbolicLink, .file]
        let secondKinds = set(insertionOrder: [DirectoryEntryKind.file, .symbolicLink])
        let firstIdentifiers = set(insertionOrder: ["public.png", "public.jpeg"])
        let secondIdentifiers = set(insertionOrder: ["public.jpeg", "public.png"])
        let first = try normalizedPreferences(
            zero: -0.0,
            statuses: firstStatuses,
            kinds: firstKinds,
            identifiers: firstIdentifiers
        )
        let second = try normalizedPreferences(
            zero: 0.0,
            statuses: secondStatuses,
            kinds: secondKinds,
            identifiers: secondIdentifiers
        )
        let revision = try ComparisonPreferencesRevision(lineage: 9)
        let firstDocument = try ComparisonPreferencesSnapshot(revision: revision, preferences: first).encodedDocument()
        let secondDocument = try ComparisonPreferencesSnapshot(revision: revision, preferences: second).encodedDocument()

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstDocument.data, secondDocument.data)
        XCTAssertEqual(firstDocument.sha256, secondDocument.sha256)
    }

    func testDecodeReportsUnsupportedSchemaVersionsExactly() throws {
        let canonical = try defaultData()
        for version in [Int.min, 0, 2, Int.max] {
            assertWorkflowError(.unsupportedSchemaVersion(version)) {
                _ = try ComparisonPreferencesSnapshot.decode(
                    from: replacing(canonical, #""schemaVersion":1"#, with: #""schemaVersion":\#(version)"#)
                )
            }
        }
    }

    func testDecodeRejectsMalformedDuplicateUnknownMissingAndWrongTypedFields() throws {
        let canonical = try defaultData()
        let malformed = [
            Data(),
            Data("null".utf8),
            Data("[]".utf8),
            Data("{".utf8),
            Data("true".utf8),
            Data([0xFF]),
            replacing(canonical, #""lineage":1"#, with: #""lineage":-1"#),
            replacing(canonical, #""generation":0"#, with: #""generation":1.5"#),
            replacing(canonical, #""schemaVersion":1"#, with: #""schemaVersion":"1"#),
            replacing(canonical, #""schemaVersion":1"#, with: #""schemaVersion":1,"schemaVersion":1"#),
            replacing(canonical, #""schemaVersion":1"#, with: #""schemaVersion":1,"schema\u0056ersion":1"#),
            replacing(canonical, #""schemaVersion":1,"#, with: "")
        ]
        for payload in malformed {
            assertWorkflowError(.malformedPersistence) {
                _ = try ComparisonPreferencesSnapshot.decode(from: payload)
            }
        }

        let unknown = insertingAfterOpeningBrace(#""aardvark":true,"#, in: canonical)
        assertWorkflowError(.nonCanonicalPersistence) {
            _ = try ComparisonPreferencesSnapshot.decode(from: unknown)
        }
    }

    func testDecodeEnforcesSmallerMaterializationLimitsBeforePreferenceConstruction() throws {
        let text = try TextComparisonPreferences(
            twoWay: LineDiffOptions(
                lineFiltersEnabled: false,
                lineFilters: [.init(pattern: "a"), .init(pattern: "b")]
            )
        )
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 11),
            preferences: ComparisonPreferences(text: text)
        )
        let data = try snapshot.encodedData()
        let decodeLimits = try limits(maximumOptionItems: 1)

        assertWorkflowError(.tooManyOptionItems(maximumCount: 1)) {
            _ = try ComparisonPreferencesSnapshot.decode(from: data, limits: decodeLimits)
        }
    }

    func testDecodeRejectsInvalidTargetedWireLeaves() throws {
        let canonical = try defaultData()
        let malformed = [
            replacing(canonical, #""algorithm":"default""#, with: #""algorithm":"future""#),
            replacing(canonical, #""delimiter":",""#, with: #""delimiter":"ab""#)
        ]
        for payload in malformed {
            assertWorkflowError(.malformedPersistence) {
                _ = try ComparisonPreferencesSnapshot.decode(from: payload)
            }
        }
        assertWorkflowError(.invalidOption(mode: .binary, field: "bytesPerRow")) {
            _ = try ComparisonPreferencesSnapshot.decode(
                from: replacing(canonical, #""bytesPerRow":16"#, with: #""bytesPerRow":0"#)
            )
        }
        assertWorkflowError(.invalidOption(mode: .image, field: "controls.zoom.scale")) {
            _ = try ComparisonPreferencesSnapshot.decode(
                from: replacing(
                    canonical,
                    #""scaleBits":4607182418800017408"#,
                    with: #""scaleBits":9218868437227405312"#
                )
            )
        }

        let contextual = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 12),
            preferences: ComparisonPreferences(
                webpage: WebpageComparisonPreferences(
                    threeWay: ThreeWayWebPageComparisonOptions(
                        expectedContext: ThreeWayWebPageComparisonContext(identifier: "context", generation: 1)
                    )
                )
            )
        ).encodedData()
        assertWorkflowError(.invalidOption(mode: .webpage, field: "threeWay.expectedContext.identifier")) {
            _ = try ComparisonPreferencesSnapshot.decode(
                from: replacing(contextual, #""identifier":"context""#, with: #""identifier":"bad\u0000context""#)
            )
        }

        let noncanonicalSet = replacing(
            canonical,
            #""supportedTypeIdentifiers":["com.compuserve.gif""#,
            with: #""supportedTypeIdentifiers":["com.compuserve.gif","com.compuserve.gif""#
        )
        assertWorkflowError(.nonCanonicalPersistence) {
            _ = try ComparisonPreferencesSnapshot.decode(from: noncanonicalSet)
        }
    }

    func testDecodeRejectsNoncanonicalWhitespaceEscapesAndKeyOrder() throws {
        let canonical = try defaultData()
        var leadingWhitespace = Data(" \n".utf8)
        leadingWhitespace.append(canonical)
        var trailingWhitespace = canonical
        trailingWhitespace.append(contentsOf: "\n".utf8)
        let escapedKey = replacing(canonical, #""schemaVersion""#, with: #""schema\u0056ersion""#)
        let reordered = movingSchemaVersionToFront(canonical)

        for payload in [leadingWhitespace, trailingWhitespace, escapedKey, reordered] {
            assertWorkflowError(.nonCanonicalPersistence) {
                _ = try ComparisonPreferencesSnapshot.decode(from: payload)
            }
        }
    }

    func testPersistenceScannerRejectsDepthContainerTokenKeyAndNumberLimits() {
        let tooDeep = Data((String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)).utf8)
        let tooManyContainerItems = Data(("[" + Array(repeating: "0", count: 8_193).joined(separator: ",") + "]").utf8)
        let tokenArray = "[" + Array(repeating: "null", count: 16).joined(separator: ",") + "]"
        let tooManyTokens = Data(("[" + Array(repeating: tokenArray, count: 8_192).joined(separator: ",") + "]").utf8)
        let oversizedKey = Data((#"{""# + String(repeating: "k", count: 129) + #"":0}"#).utf8)
        let oversizedNumber = Data(String(repeating: "1", count: 33).utf8)

        for payload in [tooDeep, tooManyContainerItems, tooManyTokens, oversizedKey, oversizedNumber] {
            assertWorkflowError(.malformedPersistence) {
                _ = try ComparisonPreferencesSnapshot.decode(from: payload)
            }
        }
    }

    func testPersistenceInputAndOutputLimitsUseExactPublicBoundaries() throws {
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 17)
        )
        let canonical = try snapshot.encodedData()
        let exactInput = try limits(maximumPersistenceInputBytes: canonical.count)
        XCTAssertEqual(try ComparisonPreferencesSnapshot.decode(from: canonical, limits: exactInput), snapshot)

        let shortInput = try limits(maximumPersistenceInputBytes: canonical.count - 1)
        assertWorkflowError(.persistenceInputTooLarge(maximumBytes: canonical.count - 1)) {
            _ = try ComparisonPreferencesSnapshot.decode(from: canonical, limits: shortInput)
        }

        let minimumOutput = try minimumSuccessfulOutputLimit(for: snapshot)
        let exactOutput = try limits(maximumPersistenceOutputBytes: minimumOutput)
        XCTAssertEqual(try snapshot.encodedData(limits: exactOutput), canonical)
        let shortOutput = try limits(maximumPersistenceOutputBytes: minimumOutput - 1)
        assertWorkflowError(.persistenceOutputTooLarge(maximumBytes: minimumOutput - 1)) {
            _ = try snapshot.encodedData(limits: shortOutput)
        }
    }

    func testEncodingAndPlanningWorkReceiptsAreExactEnforceableBoundaries() async throws {
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 18)
        )
        let document = try snapshot.encodedDocument()
        let exactEncodingLimits = try limits(maximumWorkUnits: document.workUnits)
        XCTAssertEqual(try snapshot.encodedDocument(limits: exactEncodingLimits).workUnits, document.workUnits)
        let shortEncodingLimits = try limits(maximumWorkUnits: document.workUnits - 1)
        assertWorkflowError(.workLimitExceeded(maximumWorkUnits: document.workUnits - 1)) {
            _ = try snapshot.encodedDocument(limits: shortEncodingLimits)
        }

        let workflow = try ComparisonPreferencesWorkflow(snapshot: snapshot)
        let baselinePlan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: snapshot.revision
        )
        XCTAssertGreaterThan(baselinePlan.planningWorkUnits, 0)
        let exactPlanningLimits = try limits(maximumWorkUnits: baselinePlan.planningWorkUnits)
        let exactWorkflow = try ComparisonPreferencesWorkflow(snapshot: snapshot, limits: exactPlanningLimits)
        let exactPlan = try await exactWorkflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32, limits: exactPlanningLimits))),
            expectedRevision: snapshot.revision
        )
        XCTAssertEqual(exactPlan.planningWorkUnits, baselinePlan.planningWorkUnits)
        let shortPlanningLimits = try limits(maximumWorkUnits: baselinePlan.planningWorkUnits - 1)
        let shortWorkflow = try ComparisonPreferencesWorkflow(snapshot: snapshot, limits: shortPlanningLimits)
        await assertWorkflowError(.workLimitExceeded(maximumWorkUnits: baselinePlan.planningWorkUnits - 1)) {
            _ = try await shortWorkflow.plan(
                .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32, limits: shortPlanningLimits))),
                expectedRevision: snapshot.revision
            )
        }
    }

    func testRevisionRequiresNonzeroLineageOrdersAndCodableRoundTrips() throws {
        assertWorkflowError(.invalidRevisionLineage) {
            _ = try ComparisonPreferencesRevision(lineage: 0)
        }
        let first = try ComparisonPreferencesRevision(lineage: 1, generation: UInt64.max)
        let second = try ComparisonPreferencesRevision(lineage: 2, generation: 0)
        XCTAssertLessThan(first, second)
        let generationZero = try ComparisonPreferencesRevision(lineage: 7, generation: 0)
        let generationOne = try ComparisonPreferencesRevision(lineage: 7, generation: 1)
        XCTAssertLessThan(generationZero, generationOne)
        XCTAssertGreaterThan(generationOne, generationZero)
        XCTAssertEqual([generationOne, generationZero].sorted(), [generationZero, generationOne])
        XCTAssertEqual(first.description, "1/18446744073709551615")
        XCTAssertEqual(try JSONDecoder().decode(ComparisonPreferencesRevision.self, from: JSONEncoder().encode(first)), first)
        assertWorkflowError(.invalidRevisionLineage) {
            _ = try JSONDecoder().decode(
                ComparisonPreferencesRevision.self,
                from: Data(#"{"generation":1,"lineage":0}"#.utf8)
            )
        }
    }

    func testApplyEveryModeAdvancesOneGenerationAndCommitsExactSettings() async throws {
        for setting in try customSettings() {
            let initial = try defaultSnapshot(lineage: UInt64(100 + setting.modeIndex))
            let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
            let plan = try await workflow.plan(.apply(setting), expectedRevision: initial.revision)
            let adopter = TestComparisonPreferencesAdopter(
                revision: plan.expectedRevision,
                digest: plan.expectedSHA256,
                preferences: initial.preferences
            )

            let receipt = try await workflow.execute(plan, using: adopter)
            let committed = try await workflow.snapshot()
            let store = await adopter.state()
            XCTAssertEqual(receipt.intentKind, .apply)
            XCTAssertEqual(receipt.mode, setting.mode)
            XCTAssertEqual(receipt.previousRevision, initial.revision)
            XCTAssertEqual(receipt.revision.generation, initial.revision.generation + 1)
            XCTAssertTrue(receipt.didChange)
            XCTAssertEqual(receipt.preferencesSHA256, plan.resultingSHA256)
            XCTAssertEqual(receipt.planningWorkUnits, plan.planningWorkUnits)
            XCTAssertEqual(committed.preferences.settings(for: setting.mode), setting)
            XCTAssertEqual(committed.revision, receipt.revision)
            XCTAssertEqual(store.revision, receipt.revision)
            XCTAssertEqual(store.digest, receipt.preferencesSHA256)
            XCTAssertEqual(store.preferences, committed.preferences)
            XCTAssertEqual(store.commitCount, 1)
        }
    }

    func testNoOpPlanPreservesRevisionButStillRequiresAtomicAdoption() async throws {
        let initial = try defaultSnapshot(lineage: 200, generation: 7)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(
            .apply(.binary(.default)),
            expectedRevision: initial.revision
        )
        XCTAssertFalse(plan.didChange)
        XCTAssertEqual(plan.resultingRevision, initial.revision)
        XCTAssertEqual(plan.expectedSHA256, plan.resultingSHA256)
        let adopter = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )

        let receipt = try await workflow.execute(plan, using: adopter)
        let state = await adopter.state()
        XCTAssertFalse(receipt.didChange)
        XCTAssertEqual(receipt.previousRevision, initial.revision)
        XCTAssertEqual(receipt.revision, initial.revision)
        XCTAssertEqual(state.compareCount, 1)
        XCTAssertEqual(state.commitCount, 1)
        XCTAssertEqual(state.revision, initial.revision)
        XCTAssertEqual(state.digest, plan.expectedSHA256)
        XCTAssertEqual(state.preferences, initial.preferences)
        let committed = try await workflow.snapshot()
        XCTAssertEqual(committed, initial)
    }

    func testContentDigestsIgnoreRevisionButDistinguishEveryPreferenceChange() async throws {
        let first = try defaultSnapshot(lineage: 201, generation: 3)
        let second = try defaultSnapshot(lineage: 202, generation: 99)
        let firstPlan = try await ComparisonPreferencesWorkflow(snapshot: first).plan(
            .reset,
            expectedRevision: first.revision
        )
        let secondPlan = try await ComparisonPreferencesWorkflow(snapshot: second).plan(
            .reset,
            expectedRevision: second.revision
        )
        XCTAssertEqual(firstPlan.expectedSHA256, secondPlan.expectedSHA256)
        XCTAssertEqual(firstPlan.resultingSHA256, secondPlan.resultingSHA256)
        XCTAssertEqual(firstPlan.expectedRevision, first.revision)
        XCTAssertEqual(firstPlan.resultingRevision, first.revision)
        XCTAssertEqual(secondPlan.expectedRevision, second.revision)
        XCTAssertEqual(secondPlan.resultingRevision, second.revision)

        var digests: Set<Data> = []
        for setting in try customSettings() {
            let workflow = try ComparisonPreferencesWorkflow(snapshot: first)
            let plan = try await workflow.plan(.apply(setting), expectedRevision: first.revision)
            XCTAssertNotEqual(plan.resultingSHA256, plan.expectedSHA256, "Mode: \(setting.mode)")
            XCTAssertTrue(digests.insert(Data(plan.resultingSHA256)).inserted, "Mode: \(setting.mode)")
        }
    }

    func testDefaultsResetOnlyRequestedModeAndFullResetRestoresAllModes() async throws {
        let custom = try customPreferences()
        for mode in ComparisonPreferencesMode.allCases {
            let initial = try ComparisonPreferencesSnapshot(
                revision: ComparisonPreferencesRevision(lineage: UInt64(300 + mode.modeIndex)),
                preferences: custom
            )
            let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
            let plan = try await workflow.plan(.defaults(mode), expectedRevision: initial.revision)
            let adopter = TestComparisonPreferencesAdopter(
                revision: plan.expectedRevision,
                digest: plan.expectedSHA256,
                preferences: initial.preferences
            )
            let receipt = try await workflow.execute(plan, using: adopter)
            XCTAssertEqual(receipt.intentKind, .defaults)
            XCTAssertEqual(receipt.mode, mode)
            let resetSnapshot = try await workflow.snapshot()
            XCTAssertEqual(resetSnapshot.preferences, try custom.resetting(mode))
            for retainedMode in ComparisonPreferencesMode.allCases where retainedMode != mode {
                XCTAssertEqual(
                    resetSnapshot.preferences.settings(for: retainedMode),
                    custom.settings(for: retainedMode),
                    "Reset \(mode) changed \(retainedMode)"
                )
            }
            XCTAssertEqual(
                resetSnapshot.preferences.settings(for: mode),
                ComparisonPreferencesModeSettings.defaults(for: mode)
            )
        }

        let initial = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 399),
            preferences: custom
        )
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)
        let adopter = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )
        let receipt = try await workflow.execute(plan, using: adopter)
        XCTAssertEqual(receipt.intentKind, .reset)
        XCTAssertNil(receipt.mode)
        let resetSnapshot = try await workflow.snapshot()
        XCTAssertEqual(resetSnapshot.preferences, .default)
    }

    func testPlanningAndExecutionRejectStaleRevisionsBeforeExecutorEffects() async throws {
        let initial = try defaultSnapshot(lineage: 400, generation: 5)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let stale = try ComparisonPreferencesRevision(lineage: 400, generation: 4)
        await assertWorkflowError(.staleRevision(expected: stale, actual: initial.revision)) {
            _ = try await workflow.plan(.reset, expectedRevision: stale)
        }

        let firstPlan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: initial.revision
        )
        let stalePlan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 64))),
            expectedRevision: initial.revision
        )
        let firstAdopter = TestComparisonPreferencesAdopter(
            revision: firstPlan.expectedRevision,
            digest: firstPlan.expectedSHA256,
            preferences: initial.preferences
        )
        _ = try await workflow.execute(firstPlan, using: firstAdopter)
        let forbidden = TestComparisonPreferencesAdopter(
            revision: stalePlan.expectedRevision,
            digest: stalePlan.expectedSHA256,
            preferences: initial.preferences
        )
        await assertWorkflowError(
            .staleRevision(expected: stalePlan.expectedRevision, actual: firstPlan.resultingRevision)
        ) {
            _ = try await workflow.execute(stalePlan, using: forbidden)
        }
        let forbiddenState = await forbidden.state()
        XCTAssertEqual(forbiddenState.compareCount, 0)
    }

    func testExecuteRejectsSameRevisionDifferentContentDigestBeforeAdoption() async throws {
        let revision = try ComparisonPreferencesRevision(lineage: 401, generation: 5)
        let planningSnapshot = try ComparisonPreferencesSnapshot(revision: revision)
        let planningWorkflow = try ComparisonPreferencesWorkflow(snapshot: planningSnapshot)
        let plan = try await planningWorkflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: revision
        )
        let externallyChangedPreferences = try ComparisonPreferences(
            image: customImagePreferences()
        )
        let executionSnapshot = try ComparisonPreferencesSnapshot(
            revision: revision,
            preferences: externallyChangedPreferences
        )
        let executionWorkflow = try ComparisonPreferencesWorkflow(snapshot: executionSnapshot)
        let adopter = TestComparisonPreferencesAdopter(
            revision: revision,
            digest: plan.expectedSHA256,
            preferences: externallyChangedPreferences
        )

        await assertWorkflowError(.staleSnapshot) {
            _ = try await executionWorkflow.execute(plan, using: adopter)
        }
        let state = await adopter.state()
        let current = try await executionWorkflow.snapshot()
        XCTAssertEqual(state.compareCount, 0)
        XCTAssertEqual(current, executionSnapshot)
    }

    func testExecutorContractRequiresExactRevisionAndDigestCASWithoutEffectsOnFailure() async throws {
        let initial = try defaultSnapshot(lineage: 500)
        let intent = ComparisonPreferencesIntent.apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32)))

        let successfulWorkflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let successfulPlan = try await successfulWorkflow.plan(intent, expectedRevision: initial.revision)
        let successfulAdopter = TestComparisonPreferencesAdopter(
            revision: successfulPlan.expectedRevision,
            digest: successfulPlan.expectedSHA256,
            preferences: initial.preferences
        )
        _ = try await successfulWorkflow.execute(successfulPlan, using: successfulAdopter)
        let successfulState = await successfulAdopter.state()
        XCTAssertEqual(successfulState.commitCount, 1)

        let revisionWorkflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let revisionPlan = try await revisionWorkflow.plan(intent, expectedRevision: initial.revision)
        let wrongRevision = try ComparisonPreferencesRevision(lineage: 500, generation: 1)
        let revisionRejecting = TestComparisonPreferencesAdopter(
            revision: wrongRevision,
            digest: revisionPlan.expectedSHA256,
            preferences: initial.preferences
        )
        await assertExecutorFailure {
            try await revisionWorkflow.execute(revisionPlan, using: revisionRejecting)
        }
        let revisionState = await revisionRejecting.state()
        XCTAssertEqual(revisionState.revision, wrongRevision)
        XCTAssertEqual(revisionState.commitCount, 0)

        let digestWorkflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let digestPlan = try await digestWorkflow.plan(intent, expectedRevision: initial.revision)
        var wrongDigest = digestPlan.expectedSHA256
        wrongDigest[0] ^= 0xFF
        let digestRejecting = TestComparisonPreferencesAdopter(
            revision: digestPlan.expectedRevision,
            digest: wrongDigest,
            preferences: initial.preferences
        )
        await assertExecutorFailure {
            try await digestWorkflow.execute(digestPlan, using: digestRejecting)
        }
        let digestState = await digestRejecting.state()
        XCTAssertEqual(digestState.digest, wrongDigest)
        XCTAssertEqual(digestState.commitCount, 0)
    }

    func testAdoptionContractAndTransactionReceiptsBindEveryCASField() async throws {
        let initial = try defaultSnapshot(lineage: 600, generation: 10)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(
            .apply(.table(try customTablePreferences())),
            expectedRevision: initial.revision
        )
        let adopter = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )

        let receipt = try await workflow.execute(plan, using: adopter)
        let contracts = await adopter.contracts()
        let recordedReceipt = await adopter.lastExecutorReceipt()
        let contract = try XCTUnwrap(contracts.only)
        let executorReceipt = try XCTUnwrap(recordedReceipt)
        XCTAssertEqual(
            contract.atomicity,
            .exactRevisionAndContentCompareAndSwapWithoutEffectsOnFailure
        )
        XCTAssertEqual(contract.expectedRevision, plan.expectedRevision)
        XCTAssertEqual(contract.adoptedRevision, plan.resultingRevision)
        XCTAssertEqual(contract.expectedPreferencesSHA256, plan.expectedSHA256)
        XCTAssertEqual(contract.preferencesSHA256, plan.resultingSHA256)
        XCTAssertEqual(contract.preferences, plan.preferences)
        XCTAssertEqual(contract.settings(for: .table), .table(try customTablePreferences()))
        XCTAssertEqual(executorReceipt.expectedRevision, contract.expectedRevision)
        XCTAssertEqual(executorReceipt.adoptedRevision, contract.adoptedRevision)
        XCTAssertEqual(executorReceipt.expectedPreferencesSHA256, contract.expectedPreferencesSHA256)
        XCTAssertEqual(executorReceipt.preferencesSHA256, contract.preferencesSHA256)
        XCTAssertEqual(receipt.previousRevision, contract.expectedRevision)
        XCTAssertEqual(receipt.revision, contract.adoptedRevision)
        XCTAssertEqual(receipt.preferencesSHA256, contract.preferencesSHA256)
    }

    func testExecutorReceiptRejectsExpectedAndResultingDigestMismatchesInIsolation() async throws {
        let revision = try ComparisonPreferencesRevision(lineage: 601)

        let resultTarget = try ComparisonPreferencesSnapshot(revision: revision)
        let resultTargetWorkflow = try ComparisonPreferencesWorkflow(snapshot: resultTarget)
        let resultTargetPlan = try await resultTargetWorkflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: revision
        )
        let resultSourceWorkflow = try ComparisonPreferencesWorkflow(snapshot: resultTarget)
        let resultSourcePlan = try await resultSourceWorkflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 64))),
            expectedRevision: revision
        )
        let resultSourceAdopter = TestComparisonPreferencesAdopter(
            revision: revision,
            digest: resultSourcePlan.expectedSHA256,
            preferences: resultTarget.preferences
        )
        _ = try await resultSourceWorkflow.execute(resultSourcePlan, using: resultSourceAdopter)
        let recordedWrongResultDigestReceipt = await resultSourceAdopter.lastExecutorReceipt()
        let wrongResultDigestReceipt = try XCTUnwrap(recordedWrongResultDigestReceipt)
        XCTAssertEqual(wrongResultDigestReceipt.expectedRevision, resultTargetPlan.expectedRevision)
        XCTAssertEqual(wrongResultDigestReceipt.adoptedRevision, resultTargetPlan.resultingRevision)
        XCTAssertEqual(wrongResultDigestReceipt.expectedPreferencesSHA256, resultTargetPlan.expectedSHA256)
        XCTAssertNotEqual(wrongResultDigestReceipt.preferencesSHA256, resultTargetPlan.resultingSHA256)
        let resultRejecting = TestComparisonPreferencesAdopter(
            revision: revision,
            digest: resultTargetPlan.expectedSHA256,
            preferences: resultTarget.preferences,
            behavior: .returnReceipt(wrongResultDigestReceipt)
        )
        await assertWorkflowError(.invalidExecutorReceipt) {
            _ = try await resultTargetWorkflow.execute(resultTargetPlan, using: resultRejecting)
        }

        let expectedTarget = try ComparisonPreferencesSnapshot(
            revision: revision,
            preferences: customPreferences()
        )
        let expectedTargetWorkflow = try ComparisonPreferencesWorkflow(snapshot: expectedTarget)
        let expectedTargetPlan = try await expectedTargetWorkflow.plan(.reset, expectedRevision: revision)
        let expectedSource = try ComparisonPreferencesSnapshot(
            revision: revision,
            preferences: ComparisonPreferences(image: customImagePreferences())
        )
        let expectedSourceWorkflow = try ComparisonPreferencesWorkflow(snapshot: expectedSource)
        let expectedSourcePlan = try await expectedSourceWorkflow.plan(.reset, expectedRevision: revision)
        let expectedSourceAdopter = TestComparisonPreferencesAdopter(
            revision: revision,
            digest: expectedSourcePlan.expectedSHA256,
            preferences: expectedSource.preferences
        )
        _ = try await expectedSourceWorkflow.execute(expectedSourcePlan, using: expectedSourceAdopter)
        let recordedWrongExpectedDigestReceipt = await expectedSourceAdopter.lastExecutorReceipt()
        let wrongExpectedDigestReceipt = try XCTUnwrap(recordedWrongExpectedDigestReceipt)
        XCTAssertEqual(wrongExpectedDigestReceipt.expectedRevision, expectedTargetPlan.expectedRevision)
        XCTAssertEqual(wrongExpectedDigestReceipt.adoptedRevision, expectedTargetPlan.resultingRevision)
        XCTAssertNotEqual(wrongExpectedDigestReceipt.expectedPreferencesSHA256, expectedTargetPlan.expectedSHA256)
        XCTAssertEqual(wrongExpectedDigestReceipt.preferencesSHA256, expectedTargetPlan.resultingSHA256)
        let expectedRejecting = TestComparisonPreferencesAdopter(
            revision: revision,
            digest: expectedTargetPlan.expectedSHA256,
            preferences: expectedTarget.preferences,
            behavior: .returnReceipt(wrongExpectedDigestReceipt)
        )
        await assertWorkflowError(.invalidExecutorReceipt) {
            _ = try await expectedTargetWorkflow.execute(expectedTargetPlan, using: expectedRejecting)
        }
    }

    func testInvalidExecutorReceiptDesynchronizesUntilAuthoritativeReload() async throws {
        let foreignInitial = try defaultSnapshot(lineage: 700)
        let foreignWorkflow = try ComparisonPreferencesWorkflow(snapshot: foreignInitial)
        let foreignPlan = try await foreignWorkflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 64))),
            expectedRevision: foreignInitial.revision
        )
        let foreignAdopter = TestComparisonPreferencesAdopter(
            revision: foreignPlan.expectedRevision,
            digest: foreignPlan.expectedSHA256,
            preferences: foreignInitial.preferences
        )
        _ = try await foreignWorkflow.execute(foreignPlan, using: foreignAdopter)
        let recordedForeignReceipt = await foreignAdopter.lastExecutorReceipt()
        let foreignReceipt = try XCTUnwrap(recordedForeignReceipt)

        let initial = try defaultSnapshot(lineage: 701)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: initial.revision
        )
        let adopter = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences,
            behavior: .returnReceipt(foreignReceipt)
        )
        await assertWorkflowError(.invalidExecutorReceipt) {
            _ = try await workflow.execute(plan, using: adopter)
        }
        await assertWorkflowError(.reloadRequired) { _ = try await workflow.snapshot() }
        await assertWorkflowError(.reloadRequired) {
            _ = try await workflow.plan(.reset, expectedRevision: initial.revision)
        }
        let forbidden = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )
        await assertWorkflowError(.reloadRequired) {
            _ = try await workflow.execute(plan, using: forbidden)
        }
        let forbiddenState = await forbidden.state()
        XCTAssertEqual(forbiddenState.compareCount, 0)

        let authoritativeStoreState = await adopter.state()
        let authoritative = try ComparisonPreferencesSnapshot(
            revision: authoritativeStoreState.revision,
            preferences: authoritativeStoreState.preferences
        )
        try await workflow.reload(authoritative)
        let reloaded = try await workflow.snapshot()
        XCTAssertEqual(reloaded, authoritative)
    }

    func testExecutorFailureRedactsDomainAndRequiresReload() async throws {
        let secretDomain = "com.example.SECRET.executor.domain"
        let initial = try defaultSnapshot(lineage: 800)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)
        let adopter = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences,
            behavior: .fail(domain: secretDomain, code: 73)
        )

        do {
            _ = try await workflow.execute(plan, using: adopter)
            XCTFail("Expected executor failure")
        } catch let error as ComparisonPreferencesWorkflowError {
            guard case .executorFailed(let domain, let code) = error else {
                return XCTFail("Unexpected workflow error: \(error)")
            }
            XCTAssertEqual(code, 73)
            XCTAssertTrue(domain.hasPrefix("sha256:"))
            XCTAssertEqual(domain.count, 71)
            XCTAssertFalse(domain.contains(secretDomain))
            XCTAssertFalse((error.errorDescription ?? "").contains(secretDomain))
        }
        let failedState = await adopter.state()
        XCTAssertEqual(failedState.commitCount, 0)
        await assertWorkflowError(.reloadRequired) { _ = try await workflow.snapshot() }
    }

    func testExecutorDomainTokenIsDeterministicBoundedAndMarksTruncatedDomains() async throws {
        let prefix = String(repeating: "s", count: 4_096)
        let longDomain = prefix + "A"
        let domains = [prefix, longDomain, longDomain]
        var tokens: [String] = []

        for (index, domain) in domains.enumerated() {
            let initial = try defaultSnapshot(lineage: UInt64(810 + index))
            let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
            let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)
            let adopter = TestComparisonPreferencesAdopter(
                revision: plan.expectedRevision,
                digest: plan.expectedSHA256,
                preferences: initial.preferences,
                behavior: .fail(domain: domain, code: 1)
            )
            do {
                _ = try await workflow.execute(plan, using: adopter)
                XCTFail("Expected executor failure")
            } catch let error as ComparisonPreferencesWorkflowError {
                guard case .executorFailed(let token, _) = error else {
                    return XCTFail("Unexpected workflow error: \(error)")
                }
                tokens.append(token)
                XCTAssertTrue(token.hasPrefix("sha256:"))
                XCTAssertEqual(token.count, 71)
                XCTAssertFalse(token.contains(domain))
            }
        }
        XCTAssertNotEqual(tokens[0], tokens[1])
        XCTAssertEqual(tokens[1], tokens[2])
    }

    func testCancellationErrorFromExecutorDoesNotInventCommitOrRequireReload() async throws {
        let initial = try defaultSnapshot(lineage: 900)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: initial.revision
        )
        let adopter = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences,
            behavior: .cancel
        )

        await assertWorkflowError(.cancelled) {
            _ = try await workflow.execute(plan, using: adopter)
        }
        let cancelledState = await adopter.state()
        let contracts = await adopter.contracts()
        let current = try await workflow.snapshot()
        XCTAssertEqual(cancelledState.compareCount, 1)
        XCTAssertEqual(cancelledState.commitCount, 0)
        XCTAssertEqual(contracts.count, 1)
        XCTAssertEqual(current, initial)
    }

    func testPreCancellationCoversValidationPersistencePlanningAndExecution() async throws {
        let snapshot = try defaultSnapshot(lineage: 910)
        let data = try snapshot.encodedData()
        let workflow = try ComparisonPreferencesWorkflow(snapshot: snapshot)
        let plan = try await workflow.plan(.reset, expectedRevision: snapshot.revision)
        let adopter = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: snapshot.preferences
        )
        let constructors: [@Sendable () async throws -> Void] = [
            { _ = try TextComparisonPreferences() },
            { _ = try FolderFilenameFilterPreferences() },
            { _ = try FolderComparisonPreferences() },
            { _ = try TableComparisonPreferences() },
            { _ = try BinaryComparisonPreferences() },
            { _ = try ImageComparisonPreferences() },
            { _ = try WebpageComparisonPreferences() },
            { _ = try ComparisonPreferences() },
            { _ = try ComparisonPreferencesSnapshot(revision: snapshot.revision) },
            { _ = try ComparisonPreferencesWorkflow(snapshot: snapshot) }
        ]
        for constructor in constructors {
            await assertPreCancelled(constructor)
        }

        let boundaries: [@Sendable () async throws -> Void] = [
            { _ = try snapshot.encodedData() },
            { _ = try ComparisonPreferencesSnapshot.decode(from: data) },
            { _ = try await workflow.plan(.reset, expectedRevision: snapshot.revision) },
            { _ = try await workflow.execute(plan, using: adopter) }
        ]

        for boundary in boundaries {
            await assertPreCancelled(boundary)
        }
        let adopterState = await adopter.state()
        XCTAssertEqual(adopterState.compareCount, 0)
    }

    func testLongRunningDecodeObservesPeriodicCancellation() async throws {
        let byteCount = 240 * 1_024
        let workflowLimits = try limits(
            maximumOptionStringUTF8Bytes: byteCount,
            maximumTotalOptionStringUTF8Bytes: byteCount + 64 * 1_024,
            cancellationCheckInterval: 1
        )
        let folder = try FolderComparisonPreferences(
            resultFilter: DirectoryResultFilter(pathQuery: String(repeating: "x", count: byteCount)),
            limits: workflowLimits
        )
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 915),
            preferences: ComparisonPreferences(folder: folder, limits: workflowLimits),
            limits: workflowLimits
        )
        let data = try snapshot.encodedData(limits: workflowLimits)
        let checkpoint = ComparisonPreferencesCancellationCheckpoint(cancellingAt: 2)

        assertWorkflowError(.cancelled) {
            try ComparisonPreferencesWorkflowTestHooks.withCancellationCheckpoint(checkpoint.check) {
                _ = try ComparisonPreferencesSnapshot.decode(from: data, limits: workflowLimits)
            }
        }
        XCTAssertEqual(checkpoint.callCount, 2)
    }

    func testLongRunningPlanningObservesPeriodicCancellation() async throws {
        let byteCount = 240 * 1_024
        let workflowLimits = try limits(
            maximumOptionStringUTF8Bytes: byteCount,
            maximumTotalOptionStringUTF8Bytes: byteCount + 64 * 1_024,
            cancellationCheckInterval: 1
        )
        let folder = try FolderComparisonPreferences(
            resultFilter: DirectoryResultFilter(pathQuery: String(repeating: "x", count: byteCount)),
            limits: workflowLimits
        )
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 918),
            preferences: ComparisonPreferences(folder: folder, limits: workflowLimits),
            limits: workflowLimits
        )
        let workflow = try ComparisonPreferencesWorkflow(snapshot: snapshot, limits: workflowLimits)
        let checkpoint = ComparisonPreferencesCancellationCheckpoint(cancellingAt: 2)

        await assertWorkflowError(.cancelled) {
            try await ComparisonPreferencesWorkflowTestHooks.withCancellationCheckpoint(checkpoint.check) {
                _ = try await workflow.plan(.reset, expectedRevision: snapshot.revision)
            }
        }
        XCTAssertEqual(checkpoint.callCount, 2)
    }

    func testLongRunningPersistenceObservesPeriodicCancellation() async throws {
        let byteCount = 240 * 1_024
        let workflowLimits = try limits(
            maximumOptionStringUTF8Bytes: byteCount,
            maximumTotalOptionStringUTF8Bytes: byteCount + 64 * 1_024,
            cancellationCheckInterval: 1
        )
        let folder = try FolderComparisonPreferences(
            resultFilter: DirectoryResultFilter(pathQuery: String(repeating: "x", count: byteCount)),
            limits: workflowLimits
        )
        let preferences = try ComparisonPreferences(folder: folder, limits: workflowLimits)
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 920),
            preferences: preferences,
            limits: workflowLimits
        )
        let checkpoint = ComparisonPreferencesCancellationCheckpoint(cancellingAt: 2)

        assertWorkflowError(.cancelled) {
            try ComparisonPreferencesWorkflowTestHooks.withCancellationCheckpoint(checkpoint.check) {
                _ = try snapshot.encodedData(limits: workflowLimits)
            }
        }
        XCTAssertEqual(checkpoint.callCount, 2)
    }

    func testAdoptionInProgressRejectsReentrantSnapshotPlanReloadAndExecute() async throws {
        let initial = try defaultSnapshot(lineage: 930)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: initial.revision
        )
        let adopter = SuspendingComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )
        let execution = Task { try await workflow.execute(plan, using: adopter) }
        await adopter.waitUntilEntered()

        await assertWorkflowError(.adoptionInProgress) { _ = try await workflow.snapshot() }
        await assertWorkflowError(.adoptionInProgress) {
            _ = try await workflow.plan(.reset, expectedRevision: initial.revision)
        }
        await assertWorkflowError(.adoptionInProgress) { try await workflow.reload(initial) }
        await assertWorkflowError(.adoptionInProgress) {
            _ = try await workflow.execute(plan, using: adopter)
        }

        await adopter.release()
        _ = try await execution.value
        let committed = try await workflow.snapshot()
        XCTAssertEqual(committed.revision, plan.resultingRevision)
    }

    func testRevisionExhaustionAffectsChangesButNotNoOpAdoption() async throws {
        let revision = try ComparisonPreferencesRevision(lineage: 940, generation: UInt64.max)
        let initial = try ComparisonPreferencesSnapshot(revision: revision)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        await assertWorkflowError(.revisionExhausted) {
            _ = try await workflow.plan(
                .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
                expectedRevision: revision
            )
        }

        let noOp = try await workflow.plan(.reset, expectedRevision: revision)
        XCTAssertFalse(noOp.didChange)
        let adopter = TestComparisonPreferencesAdopter(
            revision: noOp.expectedRevision,
            digest: noOp.expectedSHA256,
            preferences: initial.preferences
        )
        let receipt = try await workflow.execute(noOp, using: adopter)
        XCTAssertEqual(receipt.revision, revision)
        let adopterState = await adopter.state()
        XCTAssertEqual(adopterState.commitCount, 1)
    }

    func testSecretBearingValuesRedactDescriptionsDebugMirrorsAndDump() async throws {
        let secret = "COMPARISON-PREFERENCE-SECRET"
        let text = try TextComparisonPreferences(
            twoWay: LineDiffOptions(
                lineFiltersEnabled: false,
                lineFilters: [.init(pattern: secret)]
            )
        )
        let folder = try FolderComparisonPreferences(
            filenameFilter: FolderFilenameFilterPreferences(
                rules: [.init(.exclude, pattern: .glob("**/\(secret)"))]
            ),
            resultFilter: DirectoryResultFilter(pathQuery: secret)
        )
        let webpage = try WebpageComparisonPreferences(
            twoWay: WebPageComparisonOptions(
                lineDiffOptions: LineDiffOptions(
                    lineFiltersEnabled: false,
                    lineFilters: [.init(pattern: secret)]
                )
            ),
            threeWay: ThreeWayWebPageComparisonOptions(
                expectedContext: ThreeWayWebPageComparisonContext(identifier: secret, generation: 1)
            ),
            displayFilter: DisplayFilter(literal: secret)
        )
        let preferences = try ComparisonPreferences(text: text, folder: folder, webpage: webpage)
        let snapshot = try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: 950),
            preferences: preferences
        )
        let encoded = try snapshot.encodedDocument()
        let decoded = try ComparisonPreferencesSnapshot.decodeDocument(from: encoded.data)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: snapshot)
        let intent = ComparisonPreferencesIntent.apply(.text(text))
        let plan = try await workflow.plan(intent, expectedRevision: snapshot.revision)
        let adopter = TestComparisonPreferencesAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: snapshot.preferences
        )
        _ = try await workflow.execute(plan, using: adopter)
        let contracts = await adopter.contracts()
        let contract = try XCTUnwrap(contracts.only)
        let values: [Any] = [
            text,
            ComparisonPreferencesModeSettings.text(text),
            folder,
            folder.filenameFilter,
            ComparisonPreferencesModeSettings.folder(folder),
            webpage,
            ComparisonPreferencesModeSettings.webpage(webpage),
            preferences,
            snapshot,
            encoded,
            decoded,
            intent,
            plan,
            contract
        ]

        for value in values {
            let renderings = [
                String(describing: value),
                String(reflecting: value),
                mirrorRendering(value),
                dumpRendering(value)
            ]
            for rendering in renderings {
                XCTAssertFalse(rendering.contains(secret), "Leaked from \(type(of: value)): \(rendering)")
            }
        }
    }

    func testPublicWorkflowDomainTypesAreSendable() throws {
        requireSendable(ComparisonPreferencesMode.text)
        requireSendable(ComparisonPreferencesWorkflowLimits.default)
        requireSendable(ComparisonPreferences.default)
        requireSendable(try ComparisonPreferencesRevision(lineage: 1))
        requireSendable(try defaultSnapshot(lineage: 1))
        requireSendable(ComparisonPreferencesIntent.reset)
        requireSendable(ComparisonPreferencesWorkflowError.cancelled)
        requireSendable(ComparisonPreferencesExecutorAtomicity.exactRevisionAndContentCompareAndSwapWithoutEffectsOnFailure)
    }
}

extension ComparisonPreferencesWorkflowTests {
    private func customSettings() throws -> [ComparisonPreferencesModeSettings] {
        [
            .text(try customTextPreferences()),
            .folder(try customFolderPreferences()),
            .table(try customTablePreferences()),
            .binary(
                try BinaryComparisonPreferences(
                    twoWay: BinaryComparisonOptions(maximumExactEditDistance: 64, maximumAlignmentWork: 32_768),
                    threeWay: ThreeWayBinaryComparisonOptions(
                        maximumInputBytes: 1_024,
                        maximumExactEditDistance: 64,
                        maximumAlignmentWork: 65_536,
                        maximumRegions: 128,
                        maximumOutputBytes: 3_072
                    ),
                    bytesPerRow: 32
                )),
            .image(try customImagePreferences()),
            .webpage(try customWebpagePreferences())
        ]
    }

    private func customPreferences() throws -> ComparisonPreferences {
        var preferences = ComparisonPreferences.default
        for setting in try customSettings() {
            preferences = try preferences.replacing(setting)
        }
        return preferences
    }

    private func assertCustomPreferenceFields(
        _ preferences: ComparisonPreferences,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = preferences.text
        XCTAssertEqual(text.twoWay.algorithm, .patience, file: file, line: line)
        XCTAssertEqual(text.twoWay.whitespace, .ignoreChanges, file: file, line: line)
        XCTAssertTrue(text.twoWay.ignoreCase, file: file, line: line)
        XCTAssertTrue(text.twoWay.ignoreNumbers, file: file, line: line)
        XCTAssertTrue(text.twoWay.ignoreBlankLines, file: file, line: line)
        XCTAssertFalse(text.twoWay.ignoreComments, file: file, line: line)
        XCTAssertFalse(text.twoWay.ignoreLineEndings, file: file, line: line)
        XCTAssertTrue(text.twoWay.indentHeuristic, file: file, line: line)
        XCTAssertTrue(text.twoWay.detectMovedBlocks, file: file, line: line)
        XCTAssertEqual(text.twoWay.lineFilters, [.init(pattern: "^generated:", caseSensitive: false)], file: file, line: line)
        XCTAssertEqual(
            text.twoWay.substitutions,
            [.init(pattern: "v[0-9]+", replacement: "v#", caseSensitive: false)],
            file: file,
            line: line
        )
        XCTAssertEqual(text.threeWay.diffAlgorithm, .patience, file: file, line: line)
        XCTAssertEqual(text.threeWay.maximumInputBytes, 1_024, file: file, line: line)
        XCTAssertEqual(text.threeWay.maximumInputLines, 128, file: file, line: line)
        XCTAssertEqual(text.threeWay.maximumOutputBytes, 3_072, file: file, line: line)
        XCTAssertEqual(text.threeWay.maximumOutputLines, 384, file: file, line: line)
        XCTAssertEqual(text.threeWay.maximumRegions, 385, file: file, line: line)
        XCTAssertEqual(text.displayFilter, DisplayFilter(literal: "needle", caseSensitive: true, invert: true, predicate: .moved), file: file, line: line)

        let folder = preferences.folder
        XCTAssertEqual(folder.scanning.hiddenFilePolicy, .excludeEntriesAndSymbolicLinkTargets, file: file, line: line)
        XCTAssertEqual(folder.scanning.symbolicLinkPolicy, .doNotFollow, file: file, line: line)
        XCTAssertEqual(folder.scanning.errorPolicy, .collectIssues, file: file, line: line)
        XCTAssertEqual(folder.twoWay.method, .contentIfAvailable, file: file, line: line)
        XCTAssertEqual(folder.twoWay.pathCaseSensitivity, .insensitive, file: file, line: line)
        XCTAssertEqual(folder.twoWay.modificationDateTolerance, 1.5, file: file, line: line)
        XCTAssertEqual(folder.threeWay.comparison, folder.twoWay, file: file, line: line)
        XCTAssertEqual(folder.threeWay.maximumEntriesPerSnapshot, 100, file: file, line: line)
        XCTAssertEqual(folder.threeWay.maximumResultEntries, 300, file: file, line: line)
        XCTAssertEqual(folder.threeWay.maximumRelativePathUTF8Bytes, 512, file: file, line: line)
        XCTAssertEqual(folder.threeWay.maximumDigestBytes, 64, file: file, line: line)
        XCTAssertEqual(folder.threeWay.maximumDigestAlgorithmUTF8Bytes, 16, file: file, line: line)
        XCTAssertEqual(folder.threeWay.maximumWorkUnits, 10_000, file: file, line: line)
        XCTAssertEqual(folder.filenameFilter.rules.count, 2, file: file, line: line)
        XCTAssertEqual(folder.filenameFilter.rules[0].decision, .exclude, file: file, line: line)
        XCTAssertEqual(folder.filenameFilter.rules[0].pattern, .glob("**/*.tmp"), file: file, line: line)
        XCTAssertEqual(folder.filenameFilter.rules[0].applicability, .files, file: file, line: line)
        XCTAssertEqual(folder.filenameFilter.rules[1].decision, .include, file: file, line: line)
        XCTAssertEqual(folder.filenameFilter.rules[1].pattern, .regularExpression("^Sources/"), file: file, line: line)
        XCTAssertEqual(folder.filenameFilter.rules[1].applicability, .directories, file: file, line: line)
        XCTAssertEqual(folder.resultFilter.statuses, [.different, .leftOnly], file: file, line: line)
        XCTAssertEqual(folder.resultFilter.pathQuery, "src", file: file, line: line)
        XCTAssertEqual(folder.resultFilter.kinds, [.file, .symbolicLink], file: file, line: line)
        XCTAssertEqual(folder.resultFilter.hidden, .exclude, file: file, line: line)

        let table = preferences.table
        XCTAssertEqual(table.parsing.delimiter, "\t", file: file, line: line)
        XCTAssertNil(table.parsing.quote, file: file, line: line)
        XCTAssertFalse(table.parsing.allowsNewlinesInQuotedCells, file: file, line: line)
        XCTAssertEqual(table.parsing.limits.maximumInputBytes, 1_024, file: file, line: line)
        XCTAssertEqual(table.parsing.limits.maximumRows, 100, file: file, line: line)
        XCTAssertEqual(table.parsing.limits.maximumColumnsPerRow, 20, file: file, line: line)
        XCTAssertEqual(table.parsing.limits.maximumTotalCells, 1_000, file: file, line: line)
        XCTAssertEqual(table.parsing.limits.maximumCellBytes, 128, file: file, line: line)
        XCTAssertEqual(table.twoWay.maximumExactEditDistance, 32, file: file, line: line)
        XCTAssertEqual(table.twoWay.maximumAlignmentWork, 4_096, file: file, line: line)
        XCTAssertEqual(table.twoWay.maximumComparedRows, 200, file: file, line: line)
        XCTAssertEqual(table.twoWay.maximumComparedCells, 2_000, file: file, line: line)
        XCTAssertEqual(table.threeWay.parsingOptions, table.parsing, file: file, line: line)
        XCTAssertEqual(table.threeWay.comparisonOptions, table.twoWay, file: file, line: line)
        XCTAssertEqual(table.threeWay.maximumComparedValueBytes, 3_072, file: file, line: line)
        XCTAssertEqual(table.threeWay.maximumResultRows, 300, file: file, line: line)
        XCTAssertEqual(table.threeWay.maximumResultCells, 3_000, file: file, line: line)
        XCTAssertEqual(table.presentation.headerVisibility, .hidden, file: file, line: line)
        XCTAssertEqual(table.presentation.headerLabels, .firstRecord, file: file, line: line)
        XCTAssertFalse(table.presentation.showsRowNumbers, file: file, line: line)
        XCTAssertTrue(table.presentation.wrapsCellText, file: file, line: line)
        XCTAssertFalse(table.presentation.synchronizesColumnWidths, file: file, line: line)
        XCTAssertFalse(table.presentation.highlightsCellDifferences, file: file, line: line)

        let binary = preferences.binary
        XCTAssertEqual(binary.twoWay.maximumExactEditDistance, 64, file: file, line: line)
        XCTAssertEqual(binary.twoWay.maximumAlignmentWork, 32_768, file: file, line: line)
        XCTAssertEqual(binary.threeWay.maximumInputBytes, 1_024, file: file, line: line)
        XCTAssertEqual(binary.threeWay.maximumExactEditDistance, 64, file: file, line: line)
        XCTAssertEqual(binary.threeWay.maximumAlignmentWork, 65_536, file: file, line: line)
        XCTAssertEqual(binary.threeWay.maximumRegions, 128, file: file, line: line)
        XCTAssertEqual(binary.threeWay.maximumOutputBytes, 3_072, file: file, line: line)
        XCTAssertEqual(binary.bytesPerRow, 32, file: file, line: line)

        let image = preferences.image
        XCTAssertEqual(image.loading.maximumEncodedBytes, 2_048, file: file, line: line)
        XCTAssertEqual(image.loading.maximumDimension, 128, file: file, line: line)
        XCTAssertEqual(image.loading.maximumPixelCount, 1_024, file: file, line: line)
        XCTAssertEqual(image.loading.maximumDecodedBytes, 4_096, file: file, line: line)
        XCTAssertEqual(image.loading.supportedTypeIdentifiers, ["public.jpeg", "public.png"], file: file, line: line)
        XCTAssertEqual(image.controls.pageSelectionMode, .independent, file: file, line: line)
        XCTAssertEqual(image.controls.differences.pixelComparison.channelTolerance, 7, file: file, line: line)
        XCTAssertEqual(image.controls.differences.pixelComparison.maximumCanvasPixels, 1_024, file: file, line: line)
        XCTAssertEqual(image.controls.differences.pixelComparison.maximumRegions, 128, file: file, line: line)
        XCTAssertEqual(image.controls.differences.pixelComparison.maximumQueuedPixels, 256, file: file, line: line)
        XCTAssertFalse(image.controls.differences.showsDifferences, file: file, line: line)
        XCTAssertEqual(image.controls.differences.differenceBlockSize, 4, file: file, line: line)
        XCTAssertEqual(image.controls.differences.colorDistanceThreshold, 12.5, file: file, line: line)
        XCTAssertEqual(image.controls.differences.insertionDetection, .horizontal, file: file, line: line)
        XCTAssertEqual(image.controls.zoom, ImageToolZoom(mode: .fit, scale: 1.25), file: file, line: line)
        XCTAssertEqual(image.controls.overlay, ImageToolOverlay(mode: .alphaBlend, alpha: 0.4), file: file, line: line)
        XCTAssertEqual(image.controls.wipe, ImageToolWipe(mode: .vertical, position: 0.75), file: file, line: line)
        XCTAssertEqual(image.controls.animation.blinkIntervalMilliseconds, 500, file: file, line: line)
        XCTAssertEqual(image.controls.animation.overlayIntervalMilliseconds, 700, file: file, line: line)

        let webpage = preferences.webpage
        XCTAssertEqual(webpage.twoWay.mode, .renderedText, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.lineDiffOptions.algorithm, .histogram, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.lineDiffOptions.whitespace, .ignoreAll, file: file, line: line)
        XCTAssertTrue(webpage.twoWay.lineDiffOptions.ignoreCase, file: file, line: line)
        XCTAssertTrue(webpage.twoWay.lineDiffOptions.detectMovedBlocks, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.limits.maximumInputBytes, 1_024, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.limits.maximumTokenCount, 100, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.limits.maximumAttributeCount, 100, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.limits.maximumAttributesPerTag, 10, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.limits.maximumElementDepth, 20, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.limits.maximumWorkUnits, 10_000, file: file, line: line)
        XCTAssertEqual(webpage.twoWay.limits.maximumOutputBytes, 2_048, file: file, line: line)
        XCTAssertEqual(webpage.threeWay.diffAlgorithm, .histogram, file: file, line: line)
        XCTAssertEqual(webpage.threeWay.expectedContext?.identifier, "normalized", file: file, line: line)
        XCTAssertEqual(webpage.threeWay.expectedContext?.generation, 3, file: file, line: line)
        XCTAssertEqual(webpage.threeWay.limits.maximumTotalNormalizedInputBytes, 3_072, file: file, line: line)
        XCTAssertEqual(webpage.threeWay.limits.maximumMetadataEntriesPerSnapshot, 10, file: file, line: line)
        XCTAssertEqual(webpage.threeWay.limits.maximumMappedSegments, 600, file: file, line: line)
        XCTAssertEqual(webpage.threeWay.limits.maximumOutputLines, 300, file: file, line: line)
        XCTAssertEqual(webpage.displayFilter, DisplayFilter(literal: "article", predicate: .moved), file: file, line: line)
    }

    private func customTextPreferences() throws -> TextComparisonPreferences {
        let lineOptions = LineDiffOptions(
            algorithm: .patience,
            whitespace: .ignoreChanges,
            ignoreCase: true,
            ignoreNumbers: true,
            ignoreBlankLines: true,
            ignoreComments: false,
            ignoreLineEndings: false,
            indentHeuristic: true,
            detectMovedBlocks: true,
            lineFiltersEnabled: true,
            lineFilters: [.init(pattern: "^generated:", caseSensitive: false)],
            substitutionsEnabled: true,
            substitutions: [.init(pattern: "v[0-9]+", replacement: "v#", caseSensitive: false)]
        )
        return try TextComparisonPreferences(
            twoWay: lineOptions,
            threeWay: ThreeWayTextMergeOptions(
                diffAlgorithm: .patience,
                maximumInputBytes: 1_024,
                maximumInputLines: 128,
                maximumOutputBytes: 3_072,
                maximumOutputLines: 384,
                maximumRegions: 385
            ),
            displayFilter: DisplayFilter(
                literal: "needle",
                caseSensitive: true,
                invert: true,
                predicate: .moved
            )
        )
    }

    private func customFolderPreferences() throws -> FolderComparisonPreferences {
        let comparison = FolderComparisonOptions(
            method: .contentIfAvailable,
            pathCaseSensitivity: .insensitive,
            modificationDateTolerance: 1.5
        )
        let filenameFilter = try FolderFilenameFilterPreferences(
            rules: [
                .init(.exclude, pattern: .glob("**/*.tmp"), applicability: .files),
                .init(.include, pattern: .regularExpression("^Sources/"), applicability: .directories)
            ],
            defaultDecision: .exclude,
            matchSemantics: .firstMatchWins,
            casePolicy: .insensitive
        )
        return try FolderComparisonPreferences(
            scanning: FolderScanOptions(
                hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
                symbolicLinkPolicy: .doNotFollow,
                errorPolicy: .collectIssues
            ),
            twoWay: comparison,
            threeWay: ThreeWayFolderComparisonOptions(
                comparison: comparison,
                maximumEntriesPerSnapshot: 100,
                maximumResultEntries: 300,
                maximumRelativePathUTF8Bytes: 512,
                maximumDigestBytes: 64,
                maximumDigestAlgorithmUTF8Bytes: 16,
                maximumWorkUnits: 10_000
            ),
            filenameFilter: filenameFilter,
            resultFilter: DirectoryResultFilter(
                statuses: [.different, .leftOnly],
                pathQuery: "src",
                kinds: [.file, .symbolicLink],
                hidden: .exclude
            )
        )
    }

    private func customTablePreferences() throws -> TableComparisonPreferences {
        let parsing = DelimitedTableParsingOptions(
            delimiter: "\t",
            quote: nil,
            allowsNewlinesInQuotedCells: false,
            limits: DelimitedTableLimits(
                maximumInputBytes: 1_024,
                maximumRows: 100,
                maximumColumnsPerRow: 20,
                maximumTotalCells: 1_000,
                maximumCellBytes: 128
            )
        )
        let comparison = TableComparisonOptions(
            maximumExactEditDistance: 32,
            maximumAlignmentWork: 4_096,
            maximumComparedRows: 200,
            maximumComparedCells: 2_000
        )
        return try TableComparisonPreferences(
            parsing: parsing,
            twoWay: comparison,
            threeWay: ThreeWayTableComparisonOptions(
                parsingOptions: parsing,
                comparisonOptions: comparison,
                maximumComparedValueBytes: 3_072,
                maximumResultRows: 300,
                maximumResultCells: 3_000
            ),
            presentation: TableWorkspacePresentationOptions(
                headerVisibility: .hidden,
                headerLabels: .firstRecord,
                showsRowNumbers: false,
                wrapsCellText: true,
                synchronizesColumnWidths: false,
                highlightsCellDifferences: false
            )
        )
    }

    private func customImagePreferences() throws -> ImageComparisonPreferences {
        let pixelComparison = ImageComparisonOptions(
            channelTolerance: 7,
            maximumCanvasPixels: 1_024,
            maximumRegions: 128,
            maximumQueuedPixels: 256
        )
        return try ImageComparisonPreferences(
            loading: ImageComparisonLimits(
                maximumEncodedBytes: 2_048,
                maximumDimension: 128,
                maximumPixelCount: 1_024,
                maximumDecodedBytes: 4_096,
                supportedTypeIdentifiers: ["public.jpeg", "public.png"]
            ),
            controls: ImageToolControlState(
                pageSelectionMode: .independent,
                differences: ImageToolDifferenceOptions(
                    pixelComparison: pixelComparison,
                    showsDifferences: false,
                    differenceBlockSize: 4,
                    colorDistanceThreshold: 12.5,
                    insertionDetection: .horizontal
                ),
                zoom: ImageToolZoom(mode: .fit, scale: 1.25),
                overlay: ImageToolOverlay(mode: .alphaBlend, alpha: 0.4),
                wipe: ImageToolWipe(mode: .vertical, position: 0.75),
                animation: ImageToolAnimation(
                    blinksDifferences: true,
                    blinkIntervalMilliseconds: 500,
                    overlayIntervalMilliseconds: 700
                )
            )
        )
    }

    private func customWebpagePreferences() throws -> WebpageComparisonPreferences {
        let lineOptions = LineDiffOptions(
            algorithm: .histogram,
            whitespace: .ignoreAll,
            ignoreCase: true,
            detectMovedBlocks: true
        )
        return try WebpageComparisonPreferences(
            twoWay: WebPageComparisonOptions(
                mode: .renderedText,
                lineDiffOptions: lineOptions,
                limits: WebPageComparisonLimits(
                    maximumInputBytes: 1_024,
                    maximumTokenCount: 100,
                    maximumAttributeCount: 100,
                    maximumAttributesPerTag: 10,
                    maximumElementDepth: 20,
                    maximumWorkUnits: 10_000,
                    maximumOutputBytes: 2_048
                )
            ),
            threeWay: ThreeWayWebPageComparisonOptions(
                diffAlgorithm: .histogram,
                expectedContext: ThreeWayWebPageComparisonContext(identifier: "normalized", generation: 3),
                limits: ThreeWayWebPageComparisonLimits(
                    maximumSourceInputBytesPerSnapshot: 1_024,
                    maximumNormalizedInputBytesPerSnapshot: 1_024,
                    maximumTokenCountPerSnapshot: 100,
                    maximumAttributeCountPerSnapshot: 100,
                    maximumTotalNormalizedInputBytes: 3_072,
                    maximumInputLinesPerSnapshot: 100,
                    maximumMetadataEntriesPerSnapshot: 10,
                    maximumMetadataBytes: 1_024,
                    maximumWorkUnits: 20_000,
                    maximumResultRegions: 300,
                    maximumMappedSegments: 600,
                    maximumOutputBytes: 3_072,
                    maximumOutputLines: 300
                )
            ),
            displayFilter: DisplayFilter(literal: "article", predicate: .moved)
        )
    }

    private func normalizedPreferences(
        zero: Double,
        statuses: Set<DirectoryComparisonStatus>,
        kinds: Set<DirectoryEntryKind>,
        identifiers: Set<String>
    ) throws -> ComparisonPreferences {
        let comparison = FolderComparisonOptions(modificationDateTolerance: zero)
        let folder = try FolderComparisonPreferences(
            twoWay: comparison,
            threeWay: ThreeWayFolderComparisonOptions(comparison: comparison),
            resultFilter: DirectoryResultFilter(statuses: statuses, kinds: kinds)
        )
        let image = try ImageComparisonPreferences(
            loading: ImageComparisonLimits(
                maximumEncodedBytes: ImageComparisonLimits.default.maximumEncodedBytes,
                maximumDimension: ImageComparisonLimits.default.maximumDimension,
                maximumPixelCount: ImageComparisonLimits.default.maximumPixelCount,
                maximumDecodedBytes: ImageComparisonLimits.default.maximumDecodedBytes,
                supportedTypeIdentifiers: identifiers
            ),
            controls: ImageToolControlState(
                differences: ImageToolDifferenceOptions(colorDistanceThreshold: zero),
                zoom: ImageToolZoom(scale: zero == 0 ? 1 : zero),
                overlay: ImageToolOverlay(alpha: zero),
                wipe: ImageToolWipe(position: zero)
            )
        )
        return try ComparisonPreferences(folder: folder, image: image)
    }

    private func defaultSnapshot(
        lineage: UInt64,
        generation: UInt64 = 0
    ) throws -> ComparisonPreferencesSnapshot {
        try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: lineage, generation: generation)
        )
    }

    private func defaultData() throws -> Data {
        try defaultSnapshot(lineage: 1).encodedData()
    }

    private func limits(
        maximumOptionItems: Int = 4_096,
        maximumOptionStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalOptionStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumPersistenceInputBytes: Int = 8 * 1_024 * 1_024,
        maximumPersistenceOutputBytes: Int = 8 * 1_024 * 1_024,
        maximumWorkUnits: Int = 64 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 4_096
    ) throws -> ComparisonPreferencesWorkflowLimits {
        try ComparisonPreferencesWorkflowLimits(
            maximumOptionItems: maximumOptionItems,
            maximumOptionStringUTF8Bytes: maximumOptionStringUTF8Bytes,
            maximumTotalOptionStringUTF8Bytes: maximumTotalOptionStringUTF8Bytes,
            maximumPersistenceInputBytes: maximumPersistenceInputBytes,
            maximumPersistenceOutputBytes: maximumPersistenceOutputBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func minimumSuccessfulOutputLimit(
        for snapshot: ComparisonPreferencesSnapshot
    ) throws -> Int {
        var lower = 1
        var upper = ComparisonPreferencesWorkflowLimits.default.maximumPersistenceOutputBytes
        while lower < upper {
            let candidate = lower + (upper - lower) / 2
            do {
                _ = try snapshot.encodedData(limits: limits(maximumPersistenceOutputBytes: candidate))
                upper = candidate
            } catch ComparisonPreferencesWorkflowError.persistenceOutputTooLarge {
                lower = candidate + 1
            }
        }
        return lower
    }

    private func compiled(_ descriptor: ComparisonOpenFilenameFilter) throws -> FilenameFilter {
        try FilenameFilter(
            rules: descriptor.rules,
            defaultDecision: descriptor.defaultDecision,
            matchSemantics: descriptor.matchSemantics,
            casePolicy: descriptor.casePolicy,
            limits: descriptor.limits
        )
    }

    private func replacing(_ data: Data, _ target: String, with replacement: String) -> Data {
        let source = String(decoding: data, as: UTF8.self)
        guard let range = source.range(of: target) else {
            XCTFail("Missing persistence fixture: \(target)")
            return data
        }
        return Data(source.replacingCharacters(in: range, with: replacement).utf8)
    }

    private func insertingAfterOpeningBrace(_ value: String, in data: Data) -> Data {
        var source = String(decoding: data, as: UTF8.self)
        source.insert(contentsOf: value, at: source.index(after: source.startIndex))
        return Data(source.utf8)
    }

    private func movingSchemaVersionToFront(_ data: Data) -> Data {
        var source = String(decoding: data, as: UTF8.self)
        let field = #""schemaVersion":1,"#
        guard let range = source.range(of: field) else {
            XCTFail("Missing schema version")
            return data
        }
        source.removeSubrange(range)
        source.insert(contentsOf: field, at: source.index(after: source.startIndex))
        return Data(source.utf8)
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func set<Element: Hashable>(insertionOrder elements: some Sequence<Element>) -> Set<Element> {
        var result: Set<Element> = []
        for element in elements {
            result.insert(element)
        }
        return result
    }

    private func mirrorRendering(_ value: Any) -> String {
        Mirror(reflecting: value).children.map { child in
            "\(child.label ?? "_"): \(String(reflecting: child.value))"
        }.joined(separator: "\n")
    }

    private func dumpRendering(_ value: Any) -> String {
        var result = ""
        dump(value, to: &result)
        return result
    }

    private func assertWorkflowError<T>(
        _ expected: ComparisonPreferencesWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? ComparisonPreferencesWorkflowError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertWorkflowError<T>(
        _ expected: ComparisonPreferencesWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ComparisonPreferencesWorkflowError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertExecutorFailure<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected executor failure", file: file, line: line)
        } catch let error as ComparisonPreferencesWorkflowError {
            guard case .executorFailed(let domain, let code) = error else {
                return XCTFail("Unexpected workflow error: \(error)", file: file, line: line)
            }
            XCTAssertTrue(domain.hasPrefix("sha256:"), file: file, line: line)
            XCTAssertEqual(code, 409, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertPreCancelled(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async {
        let result = await Task.detached { @Sendable () -> ComparisonPreferencesWorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await operation()
                return nil
            } catch {
                return error as? ComparisonPreferencesWorkflowError
            }
        }.value
        XCTAssertEqual(result, .cancelled, file: file, line: line)
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }
}

private struct ComparisonPreferencesTestStoreState: Sendable {
    let revision: ComparisonPreferencesRevision
    let digest: [UInt8]
    let preferences: ComparisonPreferences
    let compareCount: Int
    let commitCount: Int
}

private enum ComparisonPreferencesTestAdopterBehavior: Sendable {
    case adopt
    case cancel
    case fail(domain: String, code: Int)
    case returnReceipt(ComparisonPreferencesExecutorReceipt)
}

private actor TestComparisonPreferencesAdopter: ComparisonPreferencesAdopting {
    private var revision: ComparisonPreferencesRevision
    private var digest: [UInt8]
    private var preferences: ComparisonPreferences
    private let behavior: ComparisonPreferencesTestAdopterBehavior
    private var compareCount = 0
    private var commitCount = 0
    private var recordedContracts: [ComparisonPreferencesAdoptionContract] = []
    private var recordedReceipt: ComparisonPreferencesExecutorReceipt?

    init(
        revision: ComparisonPreferencesRevision,
        digest: [UInt8],
        preferences: ComparisonPreferences,
        behavior: ComparisonPreferencesTestAdopterBehavior = .adopt
    ) {
        self.revision = revision
        self.digest = digest
        self.preferences = preferences
        self.behavior = behavior
    }

    func adoptComparisonPreferences(
        _ contract: ComparisonPreferencesAdoptionContract
    ) async throws -> ComparisonPreferencesExecutorReceipt {
        recordedContracts.append(contract)
        compareCount += 1
        switch behavior {
        case .cancel:
            throw CancellationError()
        case .fail(let domain, let code):
            throw NSError(domain: domain, code: code)
        case .adopt, .returnReceipt:
            guard revision == contract.expectedRevision,
                digest == contract.expectedPreferencesSHA256
            else {
                throw NSError(domain: "ComparisonPreferencesTestStore.CAS", code: 409)
            }
            revision = contract.adoptedRevision
            digest = contract.preferencesSHA256
            preferences = contract.preferences
            commitCount += 1
            let receipt = ComparisonPreferencesExecutorReceipt.adopted(contract)
            recordedReceipt = receipt
            if case .returnReceipt(let replacement) = behavior {
                return replacement
            }
            return receipt
        }
    }

    func state() -> ComparisonPreferencesTestStoreState {
        ComparisonPreferencesTestStoreState(
            revision: revision,
            digest: digest,
            preferences: preferences,
            compareCount: compareCount,
            commitCount: commitCount
        )
    }

    func contracts() -> [ComparisonPreferencesAdoptionContract] {
        recordedContracts
    }

    func lastExecutorReceipt() -> ComparisonPreferencesExecutorReceipt? {
        recordedReceipt
    }
}

private actor SuspendingComparisonPreferencesAdopter: ComparisonPreferencesAdopting {
    private var revision: ComparisonPreferencesRevision
    private var digest: [UInt8]
    private var preferences: ComparisonPreferences
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(
        revision: ComparisonPreferencesRevision,
        digest: [UInt8],
        preferences: ComparisonPreferences
    ) {
        self.revision = revision
        self.digest = digest
        self.preferences = preferences
    }

    func adoptComparisonPreferences(
        _ contract: ComparisonPreferencesAdoptionContract
    ) async throws -> ComparisonPreferencesExecutorReceipt {
        guard revision == contract.expectedRevision,
            digest == contract.expectedPreferencesSHA256
        else {
            throw NSError(domain: "ComparisonPreferencesSuspendingStore.CAS", code: 409)
        }
        entered = true
        await withCheckedContinuation { continuation = $0 }
        revision = contract.adoptedRevision
        digest = contract.preferencesSHA256
        preferences = contract.preferences
        return .adopted(contract)
    }

    func waitUntilEntered() async {
        while !entered {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private final class ComparisonPreferencesCancellationCheckpoint: @unchecked Sendable {
    private let lock = NSLock()
    private let cancellationCall: Int
    private var calls = 0

    init(cancellingAt cancellationCall: Int) {
        self.cancellationCall = cancellationCall
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func check() throws {
        let shouldCancel = lock.withLock {
            calls += 1
            return calls >= cancellationCall
        }
        if shouldCancel { throw ComparisonPreferencesWorkflowError.cancelled }
    }
}

extension Collection {
    fileprivate var only: Element? { count == 1 ? first : nil }
}

extension ComparisonPreferencesModeSettings {
    fileprivate var modeIndex: Int { mode.modeIndex }
}

extension ComparisonPreferencesMode {
    fileprivate var modeIndex: Int {
        switch self {
        case .text: 0
        case .folder: 1
        case .table: 2
        case .binary: 3
        case .image: 4
        case .webpage: 5
        }
    }
}
