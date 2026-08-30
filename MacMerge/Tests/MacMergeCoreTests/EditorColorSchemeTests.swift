import Foundation
import MacMergeCore
import XCTest

final class EditorColorSchemeTests: XCTestCase {
    private struct DifferenceRoleContract {
        let background: EditorColorRole
        let foreground: EditorColorRole
        let cue: EditorColorRole
        let pattern: EditorColorRole
    }

    private struct ExpectedBackground {
        let role: EditorColorRole
        let components: EditorColorComponents
    }

    private struct IssueSignature: Hashable {
        let variant: EditorColorSchemeVariant
        let foregroundRole: EditorColorRole
        let backgroundRole: EditorColorRole
        let actualRatioBits: UInt64
        let minimumRatioBits: UInt64
    }

    private static let validFlagCodes = Set(
        "AC AD AE AF AG AI AL AM AN AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BU BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CP CQ CR CS CU CV CW CX CY CZ DD DE DG DJ DK DM DO DZ EA EC EE EG EH ER ES ET EU FI FJ FK FM FO FR FX GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU IC ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NT NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA QU RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SU SV SX SY SZ TA TC TD TF TG TH TJ TK TL TM TN TO TP TR TT TV TW TZ UA UG UM UN US UY UZ VA VC VE VG VI VN VU WF WS XK YD YE YT YU ZA ZM ZR ZW"
            .split(separator: " ").map(String.init)
    )

    private static let validNumericEmojiRegions: Set<Int> = [
        1, 2, 3, 5, 9, 11, 13, 14, 15, 17, 18, 19, 21, 29, 30, 34, 35, 39, 53, 54,
        57, 61, 142, 143, 145, 150, 151, 154, 155, 202, 419
    ]

    private static let acceptedCLDRSubdivisionValidationSamples = [
        "ad02", "aunsw", "auqld", "autas", "auvic", "brsp", "cabc", "caon", "caqc",
        "cayt", "clrm", "cn11", "cn31", "debe", "deby", "dehe", "dehh", "denw", "fridf",
        "gbeng", "gbsct", "gbwls", "inap", "indl", "inka", "inmh", "intn", "jp01", "jp13",
        "mxcmx", "usak", "usca", "usdc", "usfl", "ushi", "usny", "ustx", "uswa", "zagp",
        "zawc"
    ]

    func testBuiltInRegistryIsCompleteStableAndValid() throws {
        XCTAssertEqual(EditorBuiltInColorScheme.allCases, [.standard, .monochrome])
        XCTAssertEqual(EditorColorScheme.builtIns, [.standard, .monochrome])
        XCTAssertEqual(EditorColorScheme.default, .standard)
        XCTAssertEqual(EditorColorScheme.currentSchemaVersion, 2)

        let expected: [(EditorBuiltInColorScheme, String, String)] = [
            (.standard, "macmerge.standard", "MacMerge Standard"),
            (.monochrome, "macmerge.monochrome", "MacMerge Monochrome")
        ]
        for (kind, identifier, displayName) in expected {
            let scheme = EditorColorScheme.builtIn(kind)
            XCTAssertEqual(scheme.identifier, identifier)
            XCTAssertEqual(scheme.displayName, displayName)
            XCTAssertEqual(scheme.schemaVersion, 2)
            XCTAssertEqual(scheme.palettes.map(\.variant), EditorColorSchemeVariant.allCases)
            XCTAssertEqual(
                scheme.differenceDecorations.map(\.kind),
                EditorDifferenceKind.allCases
            )
            XCTAssertNoThrow(try scheme.validate())
            XCTAssertEqual(try EditorColorScheme.decode(from: scheme.encodedData()), scheme)
            requireSendable(scheme)
        }
    }

    func testEveryBuiltInPaletteIsCompleteAddressableAndMeetsDefaultContrast() throws {
        for scheme in EditorColorScheme.builtIns {
            for variant in EditorColorSchemeVariant.allCases {
                let palette = try XCTUnwrap(scheme.palette(for: variant))
                XCTAssertEqual(palette.variant, variant)
                XCTAssertEqual(palette.assignments.count, EditorColorRole.allCases.count)
                XCTAssertEqual(palette.definitions.count, EditorColorRole.allCases.count)
                XCTAssertEqual(
                    palette.assignments.map(\.role.rawValue),
                    EditorColorRole.allCases.map(\.rawValue).sorted()
                )
                XCTAssertEqual(
                    palette.definitions.map(\.token.rawValue),
                    palette.definitions.map(\.token.rawValue).sorted()
                )
                for role in EditorColorRole.allCases {
                    let token = try XCTUnwrap(palette.token(for: role))
                    XCTAssertEqual(token.rawValue, role.rawValue)
                    XCTAssertNotNil(palette.components(for: token))
                    XCTAssertNotNil(palette.color(for: role))
                }
                XCTAssertEqual(palette.color(for: .textBackground)?.alpha, 1)
                XCTAssertTrue(palette.contrastIssues().isEmpty)
                XCTAssertNoThrow(try palette.validateContrast())
            }
        }
    }

    func testVariantsExposeDarkAndHighContrastAxesExactly() {
        XCTAssertEqual(
            EditorColorSchemeVariant.allCases,
            [.light, .dark, .highContrastLight, .highContrastDark]
        )
        XCTAssertEqual(EditorColorSchemeVariant.allCases.map(\.isDark), [false, true, false, true])
        XCTAssertEqual(
            EditorColorSchemeVariant.allCases.map(\.isHighContrast),
            [false, false, true, true]
        )
    }

    func testEveryRoleHasExactRendererLayerAndPlaneContract() {
        let differenceBackgrounds: Set<EditorColorRole> = [
            .differenceAddedBackground, .differenceRemovedBackground,
            .differenceModifiedBackground, .differenceConflictBackground, .movedLineBackground
        ]
        let overlayBackgrounds: Set<EditorColorRole> = [
            .selectionBackground, .selectionInactiveBackground,
            .markerSearchBackground, .markerCurrentSearchBackground
        ]
        let patterns: Set<EditorColorRole> = [
            .differenceAddedPattern, .differenceRemovedPattern, .differenceModifiedPattern,
            .differenceConflictPattern, .movedLinePattern
        ]
        let content: Set<EditorColorRole> = [
            .textForeground, .textSecondary, .textLineNumber,
            .differenceAddedForeground, .differenceRemovedForeground,
            .differenceModifiedForeground, .differenceConflictForeground,
            .movedLineForeground, .syntaxKeyword, .syntaxString, .syntaxComment,
            .syntaxNumber, .syntaxLiteral, .syntaxHeading, .syntaxEmphasis, .syntaxCode,
            .syntaxLink
        ]
        let differenceCues: Set<EditorColorRole> = [
            .differenceAddedCue, .differenceRemovedCue, .differenceModifiedCue,
            .differenceConflictCue, .movedLineCue
        ]
        let overlayForegrounds: Set<EditorColorRole> = [
            .selectionForeground, .selectionInactiveForeground,
            .markerSearchForeground, .markerCurrentSearchForeground
        ]
        let systemColorsWithoutOwnPlane: Set<EditorColorRole> = [
            .systemSeparator, .systemFocusRing, .systemAccent, .systemWarning, .systemError
        ]

        for role in EditorColorRole.allCases {
            let expectedLayer: EditorColorLayer?
            if differenceBackgrounds.contains(role) {
                expectedLayer = .differenceOrMoved
            } else if role == .textCurrentLineBackground {
                expectedLayer = .currentLine
            } else if overlayBackgrounds.contains(role) {
                expectedLayer = .selectionOrSearch
            } else {
                expectedLayer = nil
            }
            XCTAssertEqual(role.backgroundLayer, expectedLayer, role.rawValue)

            let expectedPlane: EditorColorRenderPlane?
            switch role {
            case .textBackground:
                expectedPlane = .canvasBackground
            case .systemGutterBackground:
                expectedPlane = .gutterBackground
            case _ where differenceBackgrounds.contains(role):
                expectedPlane = .differenceFill
            case _ where patterns.contains(role):
                expectedPlane = .differencePattern
            case .textCurrentLineBackground:
                expectedPlane = .currentLineFill
            case _ where content.contains(role):
                expectedPlane = .contentForeground
            case _ where differenceCues.contains(role):
                expectedPlane = .differenceCue
            case .movedLineConnector:
                expectedPlane = .movedLineConnector
            case .markerBookmark:
                expectedPlane = .markerBookmark
            case .markerWhitespace:
                expectedPlane = .markerWhitespace
            case .markerEndOfLine:
                expectedPlane = .markerEndOfLine
            case .textCaret:
                expectedPlane = .textCaret
            case _ where overlayBackgrounds.contains(role):
                expectedPlane = .overlayFill
            case _ where overlayForegrounds.contains(role):
                expectedPlane = .overlayForeground
            case _ where systemColorsWithoutOwnPlane.contains(role):
                expectedPlane = nil
            default:
                XCTFail("Unclassified role: \(role.rawValue)")
                expectedPlane = nil
            }
            XCTAssertEqual(role.renderPlane, expectedPlane, role.rawValue)
        }
        XCTAssertEqual(Set(EditorColorRole.allCases.map(\.rawValue)).count, EditorColorRole.allCases.count)
    }

    func testRendererCompositingClippingAndPlaneOrderAreExact() {
        let expectedOrder: [EditorColorRenderPlane] = [
            .canvasBackground, .gutterBackground, .differenceFill, .differencePattern,
            .currentLineFill, .contentForeground, .differenceCue, .currentLineCue,
            .movedLineConnector, .markerBookmark, .markerWhitespace, .markerEndOfLine,
            .textCaret, .overlayFill, .overlayForeground, .overlayCue
        ]
        XCTAssertEqual(EditorColorRenderPlane.allCases, expectedOrder)
        XCTAssertEqual(EditorColorRenderingContract.backToFrontOrder, expectedOrder)
        XCTAssertEqual(expectedOrder.map(\.rawValue), Array(0..<expectedOrder.count))
        XCTAssertTrue(zip(expectedOrder, expectedOrder.dropFirst()).allSatisfy(<))
        XCTAssertEqual(
            EditorColorRenderingContract.backgroundCompositing,
            .sourceOverInRenderOrderWithGapOnlyOverlayUnderlay
        )
        XCTAssertEqual(
            EditorColorRenderingContract.foregroundCompositing,
            .differenceReplacesTextAndSyntaxOverPatternGap
        )
        XCTAssertEqual(
            EditorColorRenderingContract.cueCompositing,
            .sourceOverClippedPatternWithHigherCueReplacement
        )
        XCTAssertEqual(
            EditorColorRenderingContract.contentCueUnderlays,
            [
                .canvas, .differenceOrMovedPatternGap, .currentLineOverCanvas,
                .currentLineOverDifferenceOrMovedPatternGap
            ]
        )
        XCTAssertEqual(
            EditorColorRenderingContract.contentCueRoles,
            [.movedLineConnector, .markerBookmark, .markerWhitespace, .markerEndOfLine, .textCaret]
        )
        XCTAssertEqual(EditorColorRenderingContract.movedLineConnectorPlane, .movedLineConnector)
        XCTAssertEqual(EditorColorRenderingContract.markerBookmarkPlane, .markerBookmark)
        XCTAssertLessThan(
            EditorColorRenderingContract.movedLineConnectorPlane,
            EditorColorRenderingContract.markerBookmarkPlane
        )
        XCTAssertEqual(EditorColorLayer.allCases, [.differenceOrMoved, .currentLine, .selectionOrSearch])
        XCTAssertTrue(zip(EditorColorLayer.allCases, EditorColorLayer.allCases.dropFirst()).allSatisfy(<))
    }

    func testDifferenceDecorationCuePatternAndPhaseContractsAreExact() throws {
        let expected:
            [EditorDifferenceKind: (
                EditorDifferenceShape,
                EditorDifferencePattern,
                EditorColorRole,
                EditorColorRole
            )] = [
                .added: (.leadingBar, .solid, .differenceAddedCue, .differenceAddedPattern),
                .removed: (
                    .strikeThrough, .backwardDiagonal, .differenceRemovedCue,
                    .differenceRemovedPattern
                ),
                .modified: (
                    .underline, .forwardDiagonal, .differenceModifiedCue,
                    .differenceModifiedPattern
                ),
                .conflict: (
                    .outline, .crosshatch, .differenceConflictCue,
                    .differenceConflictPattern
                ),
                .moved: (.doubleOutline, .dots, .movedLineCue, .movedLinePattern)
            ]
        XCTAssertEqual(
            EditorDifferenceShape.allCases,
            [.leadingBar, .trailingBar, .underline, .strikeThrough, .outline, .doubleOutline]
        )
        XCTAssertEqual(
            EditorDifferencePattern.allCases,
            [.solid, .forwardDiagonal, .backwardDiagonal, .crosshatch, .dots]
        )

        for scheme in EditorColorScheme.builtIns {
            for kind in EditorDifferenceKind.allCases {
                let decoration = try XCTUnwrap(scheme.decoration(for: kind))
                let contract = try XCTUnwrap(expected[kind])
                XCTAssertEqual(decoration.kind, kind)
                XCTAssertEqual(decoration.shape, contract.0)
                XCTAssertEqual(decoration.pattern, contract.1)
                XCTAssertEqual(decoration.cueColorRole, contract.2)
                XCTAssertEqual(decoration.patternColorRole, contract.3)
                XCTAssertEqual(decoration.patternPhase, .editorCanvas)
                XCTAssertEqual(decoration.foregroundBehavior, .replacesTextAndSyntax)
                XCTAssertEqual(
                    decoration.compositingRule,
                    .sourceOverFillClippedPatternForegroundCue
                )
            }
        }
    }

    func testCurrentLineOverlayAndContentCueCoreContractsAreExact() {
        XCTAssertEqual(EditorColorPalette.requiredCurrentLineNonColorCue, .outline)
        XCTAssertEqual(
            EditorColorPalette.requiredCurrentLineNonColorCueColorRole,
            .systemSeparator
        )
        XCTAssertEqual(
            EditorOverlayState.allCases,
            [.activeSelection, .inactiveSelection, .ordinarySearch, .currentSearch]
        )
        XCTAssertEqual(
            EditorOverlayNonColorCue.allCases,
            [.solidOutline, .dashedOutline, .underline, .doubleUnderline]
        )
        let expected:
            [EditorOverlayState: (
                EditorOverlayNonColorCue,
                EditorColorRole,
                EditorColorRole,
                EditorColorRole
            )] = [
                .activeSelection: (
                    .solidOutline, .selectionBackground, .selectionForeground, .systemFocusRing
                ),
                .inactiveSelection: (
                    .dashedOutline, .selectionInactiveBackground, .selectionInactiveForeground,
                    .systemFocusRing
                ),
                .ordinarySearch: (
                    .underline, .markerSearchBackground, .markerSearchForeground, .systemFocusRing
                ),
                .currentSearch: (
                    .doubleUnderline, .markerCurrentSearchBackground,
                    .markerCurrentSearchForeground, .systemFocusRing
                )
            ]
        for state in EditorOverlayState.allCases {
            let contract = expected[state]
            XCTAssertEqual(state.requiredNonColorCue, contract?.0)
            XCTAssertEqual(contract?.1.backgroundLayer, .selectionOrSearch)
            XCTAssertEqual(contract?.1.renderPlane, .overlayFill)
            XCTAssertEqual(contract?.2.renderPlane, .overlayForeground)
            XCTAssertEqual(state.requiredNonColorCueColorRole, contract?.3)
            XCTAssertEqual(state.requiredNonColorCueFillEdgeColorRole, contract?.2)
        }
        let cuePlanes: [(EditorColorRole, EditorColorRenderPlane)] = [
            (.movedLineConnector, .movedLineConnector),
            (.markerBookmark, .markerBookmark),
            (.markerWhitespace, .markerWhitespace),
            (.markerEndOfLine, .markerEndOfLine),
            (.textCaret, .textCaret)
        ]
        XCTAssertEqual(cuePlanes.map(\.0), EditorColorRenderingContract.contentCueRoles)
        for (role, plane) in cuePlanes {
            XCTAssertEqual(role.renderPlane, plane)
        }
    }

    func testHexComponentsRoundTripExactBytesAndCanonicalizeNegativeZero() throws {
        let fixtures: [(String, String, [UInt64])] = [
            ("000000", "#000000", [0, 0, 0, 0x3FF0_0000_0000_0000]),
            ("#FFFFFF", "#FFFFFF", Array(repeating: 0x3FF0_0000_0000_0000, count: 4)),
            (
                "12345678", "#12345678",
                [
                    (Double(0x12) / 255).bitPattern,
                    (Double(0x34) / 255).bitPattern,
                    (Double(0x56) / 255).bitPattern,
                    (Double(0x78) / 255).bitPattern
                ]
            ),
            (
                "#abcdef80", "#ABCDEF80",
                [
                    (Double(0xAB) / 255).bitPattern,
                    (Double(0xCD) / 255).bitPattern,
                    (Double(0xEF) / 255).bitPattern,
                    (Double(0x80) / 255).bitPattern
                ]
            )
        ]
        for (source, expectedHex, bits) in fixtures {
            let color = try EditorColorComponents(sRGBHex: source)
            XCTAssertEqual(color.sRGBHex, expectedHex)
            XCTAssertEqual(
                [
                    color.red.bitPattern, color.green.bitPattern, color.blue.bitPattern,
                    color.alpha.bitPattern
                ],
                bits
            )
        }
        let negativeZero = try EditorColorComponents(
            red: -0.0,
            green: -0.0,
            blue: -0.0,
            alpha: -0.0
        )
        XCTAssertEqual(
            [negativeZero.red, negativeZero.green, negativeZero.blue, negativeZero.alpha]
                .map(\.bitPattern),
            [0, 0, 0, 0]
        )
    }

    func testComponentsRejectNonfiniteOutOfRangeAndMalformedHexWithBoundedDiagnostics() {
        let invalidComponents = [
            -Double.infinity, -Double.leastNonzeroMagnitude, 1.nextUp,
            Double.infinity, Double.nan
        ]
        for value in invalidComponents {
            assertSchemeError(.invalidColorComponent("red", value)) {
                _ = try EditorColorComponents(red: value, green: 0, blue: 0)
            }
        }
        for value in ["", "#", "12345", "1234567", "#1234567", "GGGGGG", "１２３４５６"] {
            XCTAssertThrowsError(try EditorColorComponents(sRGBHex: value))
        }

        let source = String(repeating: "😀", count: 100)
        XCTAssertThrowsError(try EditorColorComponents(sRGBHex: source)) { error in
            guard case EditorColorSchemeError.invalidHexColor(let diagnostic) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertLessThanOrEqual(diagnostic.utf8.count, 64)
            XCTAssertTrue(diagnostic.hasSuffix("..."))
            let description = try? XCTUnwrap((error as? LocalizedError)?.errorDescription)
            XCTAssertEqual(description?.components(separatedBy: diagnostic).count, 2)
            XCTAssertLessThan(description?.utf8.count ?? .max, 160)
        }
    }

    func testLuminanceContrastAndSourceOverCompositingUseRendererMath() throws {
        let black = try EditorColorComponents(sRGBHex: "000000")
        let white = try EditorColorComponents(sRGBHex: "FFFFFF")
        XCTAssertEqual(black.relativeLuminance, 0)
        XCTAssertEqual(white.relativeLuminance, 1)
        XCTAssertEqual(black.contrastRatio(with: white), 21)
        XCTAssertEqual(white.contrastRatio(with: black), 21)

        let foreground = try EditorColorComponents(red: 1, green: 0, blue: 0, alpha: 0.5)
        let background = try EditorColorComponents(red: 0, green: 0, blue: 1, alpha: 0.5)
        let result = foreground.composited(over: background)
        XCTAssertEqual(result.alpha, 0.75)
        XCTAssertEqual(result.red, 2.0 / 3.0, accuracy: 1e-15)
        XCTAssertEqual(result.green, 0)
        XCTAssertEqual(result.blue, 1.0 / 3.0, accuracy: 1e-15)

        let clear = try EditorColorComponents(red: 1, green: 1, blue: 1, alpha: 0)
        let transparentResult = clear.composited(over: clear)
        XCTAssertEqual(transparentResult, try EditorColorComponents(red: 0, green: 0, blue: 0, alpha: 0))
    }

    func testStrictContrastIssuesMatchExactReachableRatioBitPatternMultiset() throws {
        let standards = try EditorContrastStandards(
            normalText: 21,
            enhancedText: 21,
            nonText: 21,
            enhancedNonText: 21
        )
        let palette = try XCTUnwrap(EditorColorScheme.standard.palette(for: .light))
        let issues = palette.contrastIssues(standards: standards)
        XCTAssertFalse(issues.isEmpty)

        let canvas = try XCTUnwrap(palette.color(for: .textBackground))
        let baseRequirements: [(EditorColorRole, EditorColorRole)] = [
            (.textForeground, .textBackground),
            (.textSecondary, .textBackground),
            (.textLineNumber, .systemGutterBackground),
            (.syntaxKeyword, .textBackground),
            (.syntaxString, .textBackground),
            (.syntaxComment, .textBackground),
            (.syntaxNumber, .textBackground),
            (.syntaxLiteral, .textBackground),
            (.syntaxHeading, .textBackground),
            (.syntaxEmphasis, .textBackground),
            (.syntaxCode, .textBackground),
            (.syntaxLink, .textBackground),
            (.systemSeparator, .textBackground),
            (.systemFocusRing, .textBackground),
            (.systemAccent, .textBackground),
            (.systemWarning, .textBackground),
            (.systemError, .textBackground)
        ]
        var expected: [EditorContrastIssue] = []
        for (foregroundRole, backgroundRole) in baseRequirements {
            let background = try XCTUnwrap(palette.color(for: backgroundRole))
                .composited(over: canvas)
            expected.append(
                try expectedContrastIssue(
                    palette: palette,
                    foregroundRole: foregroundRole,
                    background: .init(role: backgroundRole, components: background)
                )
            )
        }

        let differenceRoles: [DifferenceRoleContract] = [
            .init(
                background: .differenceAddedBackground,
                foreground: .differenceAddedForeground,
                cue: .differenceAddedCue,
                pattern: .differenceAddedPattern
            ),
            .init(
                background: .differenceRemovedBackground,
                foreground: .differenceRemovedForeground,
                cue: .differenceRemovedCue,
                pattern: .differenceRemovedPattern
            ),
            .init(
                background: .differenceModifiedBackground,
                foreground: .differenceModifiedForeground,
                cue: .differenceModifiedCue,
                pattern: .differenceModifiedPattern
            ),
            .init(
                background: .differenceConflictBackground,
                foreground: .differenceConflictForeground,
                cue: .differenceConflictCue,
                pattern: .differenceConflictPattern
            ),
            .init(
                background: .movedLineBackground,
                foreground: .movedLineForeground,
                cue: .movedLineCue,
                pattern: .movedLinePattern
            )
        ]
        let currentLine = try XCTUnwrap(palette.color(for: .textCurrentLineBackground))
        var outerBackgrounds = [ExpectedBackground(role: .textBackground, components: canvas)]
        for roles in differenceRoles {
            let fill = try XCTUnwrap(palette.color(for: roles.background))
                .composited(over: canvas)
            let pattern = try XCTUnwrap(palette.color(for: roles.pattern))
                .composited(over: fill)
            let fillBackground = ExpectedBackground(role: roles.background, components: fill)
            expected.append(
                expectedRenderedContrastIssue(
                    foregroundRole: roles.pattern,
                    foreground: pattern,
                    background: fillBackground
                )
            )
            expected.append(
                try expectedContrastIssue(
                    palette: palette,
                    foregroundRole: roles.foreground,
                    background: fillBackground
                )
            )
            for background in [
                ExpectedBackground(role: .textBackground, components: canvas), fillBackground
            ] {
                expected.append(
                    try expectedContrastIssue(
                        palette: palette,
                        foregroundRole: roles.cue,
                        background: background
                    )
                )
            }

            let currentLineOverCanvas = currentLine.composited(over: canvas)
            let currentLineOverFill = currentLine.composited(over: fill)
            let currentLineOverPattern = currentLine.composited(over: pattern)
            let currentLineCanvasBackground = ExpectedBackground(
                role: .textCurrentLineBackground,
                components: currentLineOverCanvas
            )
            let currentLineFillBackground = ExpectedBackground(
                role: .textCurrentLineBackground,
                components: currentLineOverFill
            )
            expected.append(
                expectedRenderedContrastIssue(
                    foregroundRole: roles.pattern,
                    foreground: currentLineOverPattern,
                    background: currentLineFillBackground
                )
            )
            expected.append(
                try expectedContrastIssue(
                    palette: palette,
                    foregroundRole: roles.foreground,
                    background: currentLineFillBackground
                )
            )
            for background in [currentLineCanvasBackground, currentLineFillBackground] {
                expected.append(
                    try expectedContrastIssue(
                        palette: palette,
                        foregroundRole: roles.cue,
                        background: background
                    )
                )
            }
            outerBackgrounds.append(fillBackground)
        }

        let currentLineBackgrounds = outerBackgrounds.map {
            ExpectedBackground(
                role: .textCurrentLineBackground,
                components: currentLine.composited(over: $0.components)
            )
        }
        let currentLineTextRoles: [EditorColorRole] = [
            .textForeground, .textSecondary, .syntaxKeyword, .syntaxString, .syntaxComment,
            .syntaxNumber, .syntaxLiteral, .syntaxHeading, .syntaxEmphasis, .syntaxCode, .syntaxLink
        ]
        for role in currentLineTextRoles {
            expected.append(
                try expectedContrastIssue(
                    palette: palette,
                    foregroundRole: role,
                    background: currentLineBackgrounds[0]
                )
            )
        }

        for (predecessor, fill) in zip(outerBackgrounds, currentLineBackgrounds) {
            for background in [fill, predecessor] {
                expected.append(
                    try expectedContrastIssue(
                        palette: palette,
                        foregroundRole: .systemSeparator,
                        background: background
                    )
                )
            }
        }

        let contentBackgrounds = outerBackgrounds + currentLineBackgrounds
        for background in contentBackgrounds {
            for role in EditorColorRenderingContract.contentCueRoles {
                expected.append(
                    try expectedContrastIssue(
                        palette: palette,
                        foregroundRole: role,
                        background: background
                    )
                )
            }
        }

        let overlayContracts: [(EditorOverlayState, EditorColorRole, EditorColorRole)] = [
            (.activeSelection, .selectionBackground, .selectionForeground),
            (.inactiveSelection, .selectionInactiveBackground, .selectionInactiveForeground),
            (.ordinarySearch, .markerSearchBackground, .markerSearchForeground),
            (.currentSearch, .markerCurrentSearchBackground, .markerCurrentSearchForeground)
        ]
        for (state, fillRole, foregroundRole) in overlayContracts {
            XCTAssertEqual(state.requiredNonColorCueFillEdgeColorRole, foregroundRole)
            let overlay = try XCTUnwrap(palette.color(for: fillRole))
            for predecessor in contentBackgrounds {
                let fill = ExpectedBackground(
                    role: fillRole,
                    components: overlay.composited(over: predecessor.components)
                )
                expected.append(
                    try expectedContrastIssue(
                        palette: palette,
                        foregroundRole: foregroundRole,
                        background: fill
                    )
                )
                expected.append(
                    try expectedContrastIssue(
                        palette: palette,
                        foregroundRole: state.requiredNonColorCueFillEdgeColorRole,
                        background: fill
                    )
                )
                expected.append(
                    try expectedContrastIssue(
                        palette: palette,
                        foregroundRole: state.requiredNonColorCueColorRole,
                        background: predecessor
                    )
                )
            }
        }

        XCTAssertEqual(issueMultiset(issues), issueMultiset(expected))
    }

    func testContrastStandardsBoundsAndHighContrastSelectionAreExact() throws {
        XCTAssertEqual(EditorContrastStandards.default.normalText, 4.5)
        XCTAssertEqual(EditorContrastStandards.default.enhancedText, 7)
        XCTAssertEqual(EditorContrastStandards.default.nonText, 3)
        XCTAssertEqual(EditorContrastStandards.default.enhancedNonText, 4.5)
        XCTAssertNoThrow(
            try EditorContrastStandards(
                normalText: 1,
                enhancedText: 21,
                nonText: 1,
                enhancedNonText: 21
            )
        )
        for value in [-Double.infinity, 1.nextDown, 21.nextUp, Double.infinity, Double.nan] {
            assertSchemeError(.invalidContrastRatio(value)) {
                _ = try EditorContrastStandards(normalText: value)
            }
        }
        assertSchemeError(.invalidContrastStandards) {
            _ = try EditorContrastStandards(
                normalText: 7,
                enhancedText: 4.5,
                nonText: 3,
                enhancedNonText: 4.5
            )
        }
        let impossible = try EditorContrastStandards(
            normalText: 21,
            enhancedText: 21,
            nonText: 21,
            enhancedNonText: 21
        )
        let issue = try XCTUnwrap(
            EditorColorScheme.standard.palette(for: .highContrastLight)?
                .contrastIssues(standards: impossible).first
        )
        XCTAssertEqual(issue.minimumRatio, 21)
        assertSchemeError(.insufficientContrast(issue)) {
            try XCTUnwrap(EditorColorScheme.standard.palette(for: .highContrastLight))
                .validateContrast(standards: impossible)
        }
    }

    func testColorTokensAcceptPortableGrammarAtExactBound() throws {
        let punctuation = try EditorColorToken(rawValue: "A0-._/:z9")
        XCTAssertEqual(punctuation.rawValue, "A0-._/:z9")
        let exact = String(repeating: "a", count: EditorColorToken.maximumUTF8Bytes)
        XCTAssertEqual(try EditorColorToken(rawValue: exact).rawValue, exact)
        XCTAssertEqual(EditorColorToken.maximumUTF8Bytes, 128)
        for invalid in ["", "-a", "a-", "a b", "é", "a\\b", "a@b", "."] {
            assertSchemeError(.invalidColorToken(invalid)) {
                _ = try EditorColorToken(rawValue: invalid)
            }
        }
        assertSchemeError(
            .colorTokenTooLarge(maximumUTF8Bytes: EditorColorToken.maximumUTF8Bytes)
        ) {
            _ = try EditorColorToken(rawValue: exact + "a")
        }
        XCTAssertLessThan(
            try EditorColorToken(rawValue: "a").rawValue,
            try EditorColorToken(rawValue: "b").rawValue
        )
    }

    func testCustomSchemeCanonicalizesCallerCollectionOrder() throws {
        let base = EditorColorScheme.standard
        let scheme = try EditorColorScheme(
            identifier: "custom.order",
            displayName: "Custom Order",
            palettes: base.palettes.reversed(),
            differenceDecorations: base.differenceDecorations.reversed()
        )
        XCTAssertEqual(scheme.palettes.map(\.variant), EditorColorSchemeVariant.allCases)
        XCTAssertEqual(scheme.differenceDecorations.map(\.kind), EditorDifferenceKind.allCases)
        XCTAssertEqual(try EditorColorScheme.decode(from: scheme.encodedData()), scheme)
    }

    func testCustomSchemeCanonicalWireBytesRoundTripUnicodeQuotesBackslashesAndEmoji() throws {
        let base = EditorColorScheme.standard
        let displayName = #"Café "quoted" \ path 👩🏽‍💻"#
        let scheme = try EditorColorScheme(
            identifier: "custom.unicode-wire",
            displayName: displayName,
            palettes: base.palettes,
            differenceDecorations: base.differenceDecorations
        )
        let encoded = try scheme.encodedData()
        let standardSource = String(decoding: try base.encodedData(), as: UTF8.self)
        let expectedSource = standardSource.replacingOccurrences(
            of: #""displayName":"MacMerge Standard","identifier":"macmerge.standard""#,
            with: #""displayName":"Café \"quoted\" \\ path 👩🏽‍💻","identifier":"custom.unicode-wire""#
        )
        XCTAssertNotEqual(expectedSource, standardSource)
        XCTAssertEqual(encoded, Data(expectedSource.utf8))

        let decoded = try EditorColorScheme.decode(from: encoded)
        XCTAssertEqual(decoded, scheme)
        XCTAssertEqual(decoded.displayName, #"Café "quoted" \ path 👩🏽‍💻"#)
        XCTAssertEqual(try decoded.encodedData(), encoded)
    }

    func testCanonicalEncodingOwnsExactKeysCollectionsAndDoubleBitIntegers() throws {
        for scheme in EditorColorScheme.builtIns {
            let first = try scheme.encodedData()
            let second = try scheme.encodedData()
            XCTAssertEqual(first, second)
            XCTAssertEqual(first.first, UInt8(ascii: "{"))
            XCTAssertEqual(first.last, UInt8(ascii: "}"))
            XCTAssertFalse(first.contains(0x0A))
            XCTAssertFalse(first.contains(0x0D))
            XCTAssertFalse(first.contains(0x09))
            let source = String(decoding: first, as: UTF8.self)
            XCTAssertTrue(source.hasPrefix(#"{"differenceDecorations":[{"kind":"added","pattern":"solid","shape":"leadingBar"}"#))
            XCTAssertTrue(source.hasSuffix(#"],"schemaVersion":2}"#))
            XCTAssertEqual(source.components(separatedBy: #""schemaVersion""#).count, 2)
            XCTAssertEqual(source.components(separatedBy: #""palettes""#).count, 2)

            for palette in scheme.palettes {
                for definition in palette.definitions {
                    let components = definition.components
                    let exact =
                        #"{"components":{"alpha":\#(components.alpha.bitPattern),"blue":\#(components.blue.bitPattern),"green":\#(components.green.bitPattern),"red":\#(components.red.bitPattern)},"token":"\#(definition.token.rawValue)"}"#
                    XCTAssertTrue(source.contains(exact), definition.token.rawValue)
                }
            }
            let decoded = try EditorColorScheme.decode(from: first)
            for (originalPalette, decodedPalette) in zip(scheme.palettes, decoded.palettes) {
                for (original, restored) in zip(
                    originalPalette.definitions,
                    decodedPalette.definitions
                ) {
                    XCTAssertEqual(original.token, restored.token)
                    XCTAssertEqual(original.components.red.bitPattern, restored.components.red.bitPattern)
                    XCTAssertEqual(original.components.green.bitPattern, restored.components.green.bitPattern)
                    XCTAssertEqual(original.components.blue.bitPattern, restored.components.blue.bitPattern)
                    XCTAssertEqual(original.components.alpha.bitPattern, restored.components.alpha.bitPattern)
                }
            }
        }
    }

    func testCanonicalBuiltInBytesHaveStableCountAndFNV1aFingerprint() throws {
        let fixtures: [(EditorColorScheme, Int, UInt64)] = [
            (.standard, 44_730, 0x308F_186D_93D9_3BA7),
            (.monochrome, 42_286, 0x4228_BF18_8CE8_596D)
        ]
        for (scheme, expectedCount, expectedFingerprint) in fixtures {
            let data = try scheme.encodedData()
            XCTAssertEqual(data.count, expectedCount, scheme.identifier)
            XCTAssertEqual(fnv1a64(data), expectedFingerprint, scheme.identifier)
        }
    }

    func testDecodeRejectsMalformedAndNoncanonicalJSONForms() throws {
        let canonical = try EditorColorScheme.standard.encodedData()
        let source = String(decoding: canonical, as: UTF8.self)
        let malformed: [Data] = [
            Data(), Data("null".utf8), Data("true".utf8), Data("[]".utf8), Data("{".utf8),
            Data([0x22, 0xFF, 0x22]), canonical + Data("x".utf8),
            Data(source.replacingOccurrences(of: "{", with: "{ ", options: [], range: source.startIndex..<source.index(after: source.startIndex)).utf8),
            replacing(
                source, #""displayName":"MacMerge Standard""#,
                with: #""displayName":"MacMerge\u0020Standard""#),
            replacing(source, #""schemaVersion":2"#, with: #""schemaVersion":2.0"#),
            replacing(source, #""schemaVersion":2"#, with: #""schemaVersion":2e0"#),
            replacing(source, #""schemaVersion":2"#, with: #""schemaVersion":02"#),
            replacing(source, #""schemaVersion":2"#, with: #""schemaVersion":+2"#),
            replacing(
                source, #""displayName":"MacMerge Standard""#,
                with: "\"displayName\":\"MacMerge\u{0001}Standard\"")
        ]
        for (index, data) in malformed.enumerated() {
            assertDecodingFailure(data, "Malformed fixture \(index)")
        }
    }

    func testDecodeRejectsDuplicateUnknownAndOutOfOrderObjectKeys() throws {
        let source = try canonicalSource()
        let duplicateRoot = replacing(
            source,
            #""schemaVersion":2}"#,
            with: #""schemaVersion":2,"schemaVersion":2}"#
        )
        let duplicateDecoration = replacing(
            source,
            #"{"kind":"added","pattern":"solid","shape":"leadingBar"}"#,
            with: #"{"kind":"added","kind":"added","pattern":"solid","shape":"leadingBar"}"#
        )
        let unknownRoot = replacing(
            source,
            #""schemaVersion":2}"#,
            with: #""future":0,"schemaVersion":2}"#
        )
        let swappedRoot = replacing(
            source,
            #"],"displayName":"MacMerge Standard","identifier":"macmerge.standard","palettes":["#,
            with: #"],"identifier":"macmerge.standard","displayName":"MacMerge Standard","palettes":["#
        )
        let swappedDecorationKeys = replacing(
            source,
            #"{"kind":"added","pattern":"solid","shape":"leadingBar"}"#,
            with: #"{"pattern":"solid","kind":"added","shape":"leadingBar"}"#
        )
        for data in [
            duplicateRoot, duplicateDecoration, unknownRoot, swappedRoot,
            swappedDecorationKeys
        ] {
            assertDecodingFailure(data)
        }
    }

    func testDecodeRejectsDuplicateAndNoncanonicalCollectionOrder() throws {
        let source = try canonicalSource()
        let swappedDecorations = swappingFirstTwoArrayElements(named: "differenceDecorations", in: source)
        let swappedAssignments = swappingFirstTwoArrayElements(named: "assignments", in: source)
        let swappedDefinitions = swappingFirstTwoArrayElements(named: "definitions", in: source)
        let duplicateAssignment = duplicatingFirstArrayElement(named: "assignments", in: source)
        let duplicateDefinition = duplicatingFirstArrayElement(named: "definitions", in: source)
        let swappedVariants =
            source
            .replacingOccurrences(of: #""variant":"light""#, with: #""variant":"temporary""#)
            .replacingOccurrences(of: #""variant":"dark""#, with: #""variant":"light""#)
            .replacingOccurrences(of: #""variant":"temporary""#, with: #""variant":"dark""#)
        for data in [
            swappedDecorations, swappedAssignments, swappedDefinitions,
            duplicateAssignment, duplicateDefinition, Data(swappedVariants.utf8)
        ] {
            assertDecodingFailure(data)
        }
    }

    func testDecodeRejectsNoncanonicalOrInvalidDoubleBitPatterns() throws {
        let source = try canonicalSource()
        let alpha = #""alpha":4607182418800017408"#
        let invalidNumbers = [
            #""alpha":-0"#,
            #""alpha":00"#,
            #""alpha":0.0"#,
            #""alpha":0e0"#,
            #""alpha":18446744073709551616"#,
            #""alpha":9221120237041090560"#,
            #""alpha":9218868437227405312"#,
            #""alpha":9223372036854775808"#
        ]
        for replacement in invalidNumbers {
            assertDecodingFailure(replacing(source, alpha, with: replacement), replacement)
        }
    }

    func testDecodeEnforcesArrayDepthValueAndEncodedSizeBounds() throws {
        let source = try canonicalSource()
        let assignment = firstArrayElement(named: "assignments", in: source)
        let definition = firstArrayElement(named: "definitions", in: source)
        assertSchemeError(.paletteLimitExceeded) {
            _ = try EditorColorScheme.decode(
                from: replacingArrayContent(
                    named: "assignments",
                    in: source,
                    with: Array(repeating: assignment, count: EditorColorPalette.maximumAssignments + 1)
                        .joined(separator: ",")
                )
            )
        }
        assertSchemeError(.paletteLimitExceeded) {
            _ = try EditorColorScheme.decode(
                from: replacingArrayContent(
                    named: "definitions",
                    in: source,
                    with: Array(repeating: definition, count: EditorColorPalette.maximumDefinitions + 1)
                        .joined(separator: ",")
                )
            )
        }

        assertDecodingFailure(Data((String(repeating: "[", count: 17) + String(repeating: "]", count: 17)).utf8))
        let tooManyValues = "[" + Array(repeating: "0", count: 3_073).joined(separator: ",") + "]"
        assertDecodingFailure(Data(tooManyValues.utf8))

        let exactMaximum = Data(repeating: 0x20, count: 128 * 1024)
        assertDecodingFailure(exactMaximum)
        assertSchemeError(.encodedDataTooLarge(maximumBytes: 128 * 1024)) {
            _ = try EditorColorScheme.decode(from: exactMaximum + Data([0x20]))
        }
    }

    func testIdentifierDisplayNameAndStructuralCustomLimitsAreEnforced() throws {
        let base = EditorColorScheme.standard
        let exactIdentifier = "a" + String(repeating: "b", count: 127)
        XCTAssertEqual(
            try customScheme(identifier: exactIdentifier, displayName: "Bounded").identifier,
            exactIdentifier
        )
        assertSchemeError(.identifierTooLarge(maximumUTF8Bytes: 128)) {
            _ = try customScheme(identifier: exactIdentifier + "c", displayName: "Bounded")
        }
        for identifier in ["", "-bad", "bad-", "bad value", "é"] {
            assertSchemeError(.invalidIdentifier(identifier)) {
                _ = try customScheme(identifier: identifier, displayName: "Bounded")
            }
        }
        assertSchemeError(.paletteLimitExceeded) {
            _ = try EditorColorScheme(
                identifier: "custom.too-many-palettes",
                displayName: "Too Many Palettes",
                palettes: base.palettes + [base.palettes[0]],
                differenceDecorations: base.differenceDecorations
            )
        }
        assertSchemeError(.paletteLimitExceeded) {
            _ = try EditorColorScheme(
                identifier: "custom.too-many-decorations",
                displayName: "Too Many Decorations",
                palettes: base.palettes,
                differenceDecorations: base.differenceDecorations + [base.differenceDecorations[0]]
            )
        }
        XCTAssertEqual(EditorColorPalette.maximumDefinitions, 128)
        XCTAssertEqual(EditorColorPalette.maximumAssignments, 64)
        let token = try EditorColorToken(rawValue: "x")
        let color = try EditorColorComponents(sRGBHex: "000000")
        let definition = EditorColorDefinition(token: token, components: color)
        let assignment = EditorColorAssignment(role: .textBackground, token: token)
        assertSchemeError(.paletteLimitExceeded) {
            _ = try EditorColorPalette(
                variant: .light,
                definitions: Array(repeating: definition, count: 129),
                assignments: []
            )
        }
        assertSchemeError(.paletteLimitExceeded) {
            _ = try EditorColorPalette(
                variant: .light,
                definitions: [definition],
                assignments: Array(repeating: assignment, count: 65)
            )
        }
    }

    func testDisplayNameNormalizesToNFCBeforeApplyingUTF8Bound() throws {
        let decomposedExactAfterNFC = String(repeating: "e\u{301}", count: 128)
        XCTAssertEqual(decomposedExactAfterNFC.utf8.count, 384)
        let accepted = try customScheme(
            identifier: "custom.nfc-bound",
            displayName: decomposedExactAfterNFC
        )
        XCTAssertEqual(accepted.displayName.utf8.count, 256)
        XCTAssertEqual(
            accepted.displayName,
            decomposedExactAfterNFC.precomposedStringWithCanonicalMapping
        )

        let tooLargeAfterNFC = decomposedExactAfterNFC + "e\u{301}"
        assertSchemeError(.displayNameTooLarge(maximumUTF8Bytes: 256)) {
            _ = try customScheme(identifier: "custom.nfc-too-large", displayName: tooLargeAfterNFC)
        }

        let noncanonicalWire = replacing(
            try canonicalSource(),
            #""displayName":"MacMerge Standard""#,
            with: #""displayName":"Café""#
        )
        assertSchemeError(.invalidDisplayName) {
            _ = try EditorColorScheme.decode(from: noncanonicalWire)
        }
    }

    func testDisplayNameRejectsBlankFillerControlAndDefaultIgnorableOnlyValues() {
        let invalid = [
            "", " ", "\t", "\n", " surrounding ", "line\nbreak", "\u{0000}",
            "\u{115F}", "\u{1160}", "\u{2800}", "\u{3164}", "\u{FFA0}",
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FE0E}", "\u{FE0F}",
            "\u{E007F}"
        ]
        for value in invalid {
            assertInvalidDisplayName(value)
        }
    }

    func testEmoji16FlagDatasetIsExhaustiveAndContextual() throws {
        XCTAssertEqual(Self.validFlagCodes.count, 271)
        let validFlags = Self.validFlagCodes.sorted().map(flagEmoji)
        for chunk in validFlags.chunked(maximumUTF8Bytes: 256) {
            XCTAssertNoThrow(
                try customScheme(identifier: "emoji.flags", displayName: chunk.joined())
            )
        }

        for first in Unicode.Scalar("A").value...Unicode.Scalar("Z").value {
            for second in Unicode.Scalar("A").value...Unicode.Scalar("Z").value {
                let code = String(Unicode.Scalar(first)!) + String(Unicode.Scalar(second)!)
                guard !Self.validFlagCodes.contains(code) else { continue }
                assertInvalidDisplayName(flagEmoji(code), "Invalid flag \(code)")
            }
        }
        assertInvalidDisplayName("🇺", "Single regional indicator")
        assertInvalidDisplayName("🇺🇸🇨", "Three regional indicators")
        XCTAssertNoThrow(try customScheme(identifier: "emoji.flag-context", displayName: "US 🇺🇸"))
    }

    func testEmoji16NumericTagRegionsAreExhaustiveAndBounded() throws {
        XCTAssertEqual(Self.validNumericEmojiRegions.count, 31)
        let valid = Self.validNumericEmojiRegions.sorted().map {
            emojiTag(String(format: "%03d", $0))
        }
        for chunk in valid.chunked(maximumUTF8Bytes: 256) {
            XCTAssertNoThrow(
                try customScheme(identifier: "emoji.numeric-tags", displayName: chunk.joined())
            )
        }
        for region in 0...999 where !Self.validNumericEmojiRegions.contains(region) {
            assertInvalidDisplayName(
                emojiTag(String(format: "%03d", region)),
                "Invalid numeric tag region \(region)"
            )
        }
    }

    func testEmoji16SubdivisionPublicValidationSamplesHaveIndependentFingerprint() throws {
        let samples = Self.acceptedCLDRSubdivisionValidationSamples
        XCTAssertEqual(samples, samples.sorted())
        XCTAssertEqual(Set(samples).count, 40)
        XCTAssertEqual(
            fnv1a64(Data(samples.joined(separator: "\n").utf8)),
            0x09F3_6735_998B_3D4B
        )
        for identifier in samples {
            XCTAssertNoThrow(
                try customScheme(
                    identifier: "emoji.tag.\(identifier)",
                    displayName: emojiTag(identifier)
                ),
                identifier
            )
        }
    }

    func testEmoji16SubdivisionPublicValidationRejectsMalformedTags() {
        let invalid = [
            emojiTag("zzz"), emojiTag("zzzzz"), emojiTag("1234"), emojiTag("a"),
            "🏴\u{E0067}\u{E0062}",
            "🏴\u{E0067}\u{E0062}\u{E007F}\u{E0065}",
            "😀\u{E0067}\u{E0062}\u{E007F}",
            "🏴\u{E0020}\u{E007F}"
        ]
        for value in invalid {
            assertInvalidDisplayName(value)
        }
    }

    func testEmoji16VariationKeycapAndModifierGrammarIsContextual() throws {
        let valid = [
            "☀️", "☀︎", "©️", "™︎", "#️⃣", "*️⃣", "0️⃣", "9️⃣",
            "👍🏻", "👍🏼", "👍🏽", "👍🏾", "👍🏿", "🫸🏻",
            "🏻", "🏼", "🏽", "🏾", "🏿"
        ]
        XCTAssertNoThrow(
            try customScheme(identifier: "emoji.context-valid", displayName: valid.joined(separator: " "))
        )
        let invalid = [
            "A️", "A︎", "😀️", "😀︎", "1⃣", "1︎⃣", "A⃣", "😀🏻", "☀🏻", "🫹🏻",
            "🏻🏻"
        ]
        for value in invalid {
            assertInvalidDisplayName(value)
        }
    }

    func testEmoji16ZWJGrammarAcceptsPinnedSequencesAndRejectsBrokenJoins() throws {
        let valid = [
            "👩‍💻", "👨‍👩‍👧‍👦", "👩🏽‍🚀", "🏳️‍🌈", "🏴‍☠️", "🙂‍↔️", "🐦‍🔥",
            emojiTag("gbeng") + "‍💻"
        ]
        XCTAssertNoThrow(
            try customScheme(identifier: "emoji.zwj-valid", displayName: valid.joined())
        )
        let invalid = [
            "‍😀", "😀‍", "A‍😀", "😀‍A", "😀‍‍😀", "☀︎‍😀", "🏻‍😀",
            "🇺‍🇸", "🏴\u{E0067}\u{E0062}\u{E007F}‍"
        ]
        for value in invalid {
            assertInvalidDisplayName(value)
        }
    }

    func testRestorationUsesValidatedFallbackForNilMalformedUnsupportedAndOversizedData() throws {
        let fallback = EditorColorScheme.monochrome
        XCTAssertEqual(try EditorColorScheme.restored(from: nil, fallback: fallback), fallback)
        let invalid: [Data] = [
            Data(), Data("{}".utf8), Data([0xFF]),
            replacing(try canonicalSource(), #""schemaVersion":2"#, with: #""schemaVersion":3"#),
            Data(repeating: 0x20, count: 128 * 1024 + 1)
        ]
        for data in invalid {
            XCTAssertEqual(try EditorColorScheme.restored(from: data, fallback: fallback), fallback)
        }
        let standardData = try EditorColorScheme.standard.encodedData()
        XCTAssertEqual(
            try EditorColorScheme.restored(from: standardData, fallback: fallback),
            .standard
        )
    }

    func testErrorEqualityUsesDoubleBitsAndDuplicateDiagnosticsStayDistinct() {
        XCTAssertEqual(
            EditorColorSchemeError.invalidColorComponent("red", Double.nan),
            EditorColorSchemeError.invalidColorComponent(
                "red",
                Double(bitPattern: Double.nan.bitPattern)
            )
        )
        XCTAssertNotEqual(
            EditorColorSchemeError.invalidColorComponent("red", 0),
            EditorColorSchemeError.invalidColorComponent("red", -0.0)
        )
        let first = EditorContrastIssue(
            variant: .light,
            foregroundRole: .textCaret,
            backgroundRole: .textBackground,
            actualRatio: 0.0,
            minimumRatio: 3
        )
        let second = EditorContrastIssue(
            variant: .light,
            foregroundRole: .textCaret,
            backgroundRole: .textBackground,
            actualRatio: -0.0,
            minimumRatio: 3
        )
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(
            EditorColorSchemeError.duplicateColorToken("same"),
            EditorColorSchemeError.undefinedColorToken("same")
        )
        XCTAssertNotEqual(
            EditorColorSchemeError.duplicateVariant(.light),
            EditorColorSchemeError.missingVariant(.light)
        )
        XCTAssertEqual(
            EditorColorSchemeError.duplicateColorToken("same").errorDescription,
            "Editor color palette contains duplicate token: same."
        )
        XCTAssertEqual(
            EditorColorSchemeError.duplicateColorRole(.textCaret).errorDescription,
            "Editor color palette contains duplicate role: text.caret."
        )
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }

    private func customScheme(
        identifier: String,
        displayName: String
    ) throws -> EditorColorScheme {
        try EditorColorScheme(
            identifier: identifier,
            displayName: displayName,
            palettes: EditorColorScheme.standard.palettes,
            differenceDecorations: EditorColorScheme.standard.differenceDecorations
        )
    }

    private func expectedContrastIssue(
        palette: EditorColorPalette,
        foregroundRole: EditorColorRole,
        background: ExpectedBackground
    ) throws -> EditorContrastIssue {
        let foreground = try XCTUnwrap(palette.color(for: foregroundRole))
            .composited(over: background.components)
        return expectedRenderedContrastIssue(
            foregroundRole: foregroundRole,
            foreground: foreground,
            background: background
        )
    }

    private func expectedRenderedContrastIssue(
        foregroundRole: EditorColorRole,
        foreground: EditorColorComponents,
        background: ExpectedBackground
    ) -> EditorContrastIssue {
        let ratio = foreground.contrastRatio(with: background.components)
        XCTAssertLessThan(ratio, 21)
        return EditorContrastIssue(
            variant: .light,
            foregroundRole: foregroundRole,
            backgroundRole: background.role,
            actualRatio: ratio,
            minimumRatio: 21
        )
    }

    private func issueMultiset(_ issues: [EditorContrastIssue]) -> [IssueSignature: Int] {
        var result: [IssueSignature: Int] = [:]
        for issue in issues {
            let signature = IssueSignature(
                variant: issue.variant,
                foregroundRole: issue.foregroundRole,
                backgroundRole: issue.backgroundRole,
                actualRatioBits: issue.actualRatio.bitPattern,
                minimumRatioBits: issue.minimumRatio.bitPattern
            )
            result[signature, default: 0] += 1
        }
        return result
    }

    private func assertInvalidDisplayName(
        _ value: String,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try customScheme(identifier: "invalid.display-name", displayName: value),
            message,
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? EditorColorSchemeError,
                .invalidDisplayName,
                message,
                file: file,
                line: line
            )
        }
    }

    private func assertSchemeError(
        _ expected: EditorColorSchemeError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? EditorColorSchemeError, expected, file: file, line: line)
        }
    }

    private func assertDecodingFailure(
        _ data: Data,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try EditorColorScheme.decode(from: data),
            message,
            file: file,
            line: line
        )
    }

    private func canonicalSource() throws -> String {
        String(decoding: try EditorColorScheme.standard.encodedData(), as: UTF8.self)
    }

    private func replacing(_ source: String, _ target: String, with replacement: String) -> Data {
        let result = source.replacingOccurrences(of: target, with: replacement)
        XCTAssertNotEqual(result, source, "Mutation target was absent: \(target)")
        return Data(result.utf8)
    }

    private func firstArrayElement(named name: String, in source: String) -> String {
        let content = arrayContentRange(named: name, in: source)
        let ranges = topLevelElementRanges(in: source, contentRange: content)
        guard let first = ranges.first else {
            XCTFail("Array \(name) is empty")
            return ""
        }
        return String(source[first])
    }

    private func duplicatingFirstArrayElement(named name: String, in source: String) -> Data {
        let content = arrayContentRange(named: name, in: source)
        let ranges = topLevelElementRanges(in: source, contentRange: content)
        guard let first = ranges.first else {
            XCTFail("Array \(name) is empty")
            return Data(source.utf8)
        }
        var result = source
        result.insert(contentsOf: String(source[first]) + ",", at: content.lowerBound)
        return Data(result.utf8)
    }

    private func swappingFirstTwoArrayElements(named name: String, in source: String) -> Data {
        let content = arrayContentRange(named: name, in: source)
        let ranges = topLevelElementRanges(in: source, contentRange: content)
        guard ranges.count >= 2 else {
            XCTFail("Array \(name) has fewer than two elements")
            return Data(source.utf8)
        }
        var result = source
        result.replaceSubrange(
            ranges[0].lowerBound..<ranges[1].upperBound,
            with: String(source[ranges[1]]) + "," + String(source[ranges[0]])
        )
        return Data(result.utf8)
    }

    private func replacingArrayContent(
        named name: String,
        in source: String,
        with replacement: String
    ) -> Data {
        var result = source
        result.replaceSubrange(arrayContentRange(named: name, in: source), with: replacement)
        return Data(result.utf8)
    }

    private func arrayContentRange(named name: String, in source: String) -> Range<String.Index> {
        let marker = "\"\(name)\":["
        guard let markerRange = source.range(of: marker) else {
            XCTFail("Missing array: \(name)")
            return source.startIndex..<source.startIndex
        }
        let start = markerRange.upperBound
        var index = start
        var depth = 1
        var inString = false
        var escaped = false
        while index < source.endIndex {
            let character = source[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 { return start..<index }
            }
            index = source.index(after: index)
        }
        XCTFail("Unterminated array: \(name)")
        return start..<source.endIndex
    }

    private func topLevelElementRanges(
        in source: String,
        contentRange: Range<String.Index>
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = contentRange.lowerBound
        var index = start
        var objectDepth = 0
        var arrayDepth = 0
        var inString = false
        var escaped = false
        while index < contentRange.upperBound {
            let character = source[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"": inString = true
                case "{": objectDepth += 1
                case "}": objectDepth -= 1
                case "[": arrayDepth += 1
                case "]": arrayDepth -= 1
                case "," where objectDepth == 0 && arrayDepth == 0:
                    ranges.append(start..<index)
                    start = source.index(after: index)
                default: break
                }
            }
            index = source.index(after: index)
        }
        if start < contentRange.upperBound { ranges.append(start..<contentRange.upperBound) }
        return ranges
    }

    private func flagEmoji(_ code: String) -> String {
        String(
            code.unicodeScalars.compactMap {
                Unicode.Scalar(0x1F1E6 + $0.value - Unicode.Scalar("A").value)
            }.map(Character.init)
        )
    }

    private func emojiTag(_ identifier: String) -> String {
        var value = "🏴"
        for byte in identifier.utf8 {
            guard let scalar = Unicode.Scalar(0xE0000 + UInt32(byte)) else {
                XCTFail("Invalid tag byte: \(byte)")
                continue
            }
            value.unicodeScalars.append(scalar)
        }
        value.unicodeScalars.append(Unicode.Scalar(0xE007F)!)
        return value
    }

    private func fnv1a64(_ data: Data) -> UInt64 {
        data.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}

extension Array where Element == String {
    fileprivate func chunked(maximumUTF8Bytes: Int) -> [[String]] {
        var result: [[String]] = []
        var chunk: [String] = []
        var byteCount = 0
        for value in self {
            if !chunk.isEmpty, byteCount + value.utf8.count > maximumUTF8Bytes {
                result.append(chunk)
                chunk = []
                byteCount = 0
            }
            chunk.append(value)
            byteCount += value.utf8.count
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }
}
