import Foundation
@testable import MacMergeCore
import XCTest

private actor StartProbe {
    private var started = false

    func markStarted() {
        started = true
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }
}

final class SyntaxRendererBindingTests: XCTestCase {
    func testRoleBridgeIsCompleteBidirectionalAndStrict() throws {
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
        for (kind, role) in expected {
            XCTAssertEqual(kind.editorColorRole, role, kind.rawValue)
            XCTAssertEqual(role.syntaxTokenKind, kind, role.rawValue)
        }
        XCTAssertNil(EditorColorRole.textForeground.syntaxTokenKind)
        XCTAssertNil(EditorColorRole.textBackground.syntaxTokenKind)
        let cues = SyntaxTokenKind.allCases.map(\.insufficientContrastCue)
        XCTAssertEqual(Set(cues).count, cues.count)
    }

    func testBindResolvesPaletteRolesAndOpaqueBackground() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let tokens = SyntaxTokenKind.allCases.enumerated().map { index, kind in
            SyntaxToken(kind: kind, range: NSRange(location: index * 4, length: 3))
        }
        let plan = try bind(resolution, tokens: tokens, palette: palette, in: catalog)

        let background = try XCTUnwrap(palette.color(for: .textBackground))
        XCTAssertEqual(background.alpha, 1)
        XCTAssertEqual(plan.background, background)
        XCTAssertEqual(plan.variant, palette.variant)
        XCTAssertEqual(plan.schemeIdentifier, .builtInSwift)
        XCTAssertEqual(plan.schemeOrigin, .builtIn)
        XCTAssertEqual(plan.source, .languageDefault)
        XCTAssertEqual(plan.spans.count, tokens.count)
        for (span, token) in zip(plan.spans, tokens) {
            XCTAssertEqual(span.tokenKind, token.kind)
            XCTAssertEqual(span.range, token.range)
            XCTAssertEqual(span.colorRole, token.kind.editorColorRole)
            XCTAssertEqual(span.color, try XCTUnwrap(palette.color(for: span.colorRole)))
            let effective = span.color.composited(over: background)
            XCTAssertEqual(span.contrastRatio, effective.contrastRatio(with: background))
        }
    }

    func testHappyPathMeetsDefaultContrastWithoutFallback() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let plan = try bind(resolution, tokens: sampleTokens(), palette: palette, in: catalog)

        XCTAssertTrue(plan.contrastIssues.isEmpty)
        XCTAssertFalse(plan.requiresNonColorFallback)
        for span in plan.spans {
            XCTAssertTrue(span.meetsContrast)
            XCTAssertEqual(span.cue, .none)
            XCTAssertFalse(span.didFallBackToPlainTextColor)
        }
    }

    func testStrictStandardsFailContrastWithDistinctCuesAndDedupedIssues() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let strict = try EditorContrastStandards(
            normalText: 21,
            enhancedText: 21,
            nonText: 21,
            enhancedNonText: 21
        )
        let tokens = [
            SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 3)),
            SyntaxToken(kind: .keyword, range: NSRange(location: 4, length: 3)),
            SyntaxToken(kind: .comment, range: NSRange(location: 8, length: 3))
        ]
        let plan = try bind(
            resolution,
            tokens: tokens,
            palette: palette,
            in: catalog,
            standards: strict
        )

        let background = try XCTUnwrap(palette.color(for: .textBackground))
        var failingRoles: [EditorColorRole] = []
        for role in [EditorColorRole.syntaxKeyword, .syntaxComment] {
            let color = try XCTUnwrap(palette.color(for: role))
            let ratio = color.composited(over: background).contrastRatio(with: background)
            if ratio < strict.normalText {
                failingRoles.append(role)
            }
        }
        XCTAssertFalse(failingRoles.isEmpty)

        var expected: [EditorContrastIssue] = []
        for role in failingRoles {
            let color = try XCTUnwrap(palette.color(for: role))
            let ratio = color.composited(over: background).contrastRatio(with: background)
            expected.append(
                EditorContrastIssue(
                    variant: palette.variant,
                    foregroundRole: role,
                    backgroundRole: .textBackground,
                    actualRatio: ratio,
                    minimumRatio: strict.normalText
                )
            )
        }
        XCTAssertEqual(plan.contrastIssues, expected)

        for span in plan.spans {
            let color = try XCTUnwrap(palette.color(for: span.colorRole))
            let ratio = color.composited(over: background).contrastRatio(with: background)
            XCTAssertEqual(span.meetsContrast, ratio >= strict.normalText)
            XCTAssertEqual(
                span.cue,
                ratio >= strict.normalText ? .none : span.tokenKind.insufficientContrastCue
            )
        }
        XCTAssertEqual(
            plan.requiresNonColorFallback,
            plan.spans.contains { $0.cue != .none }
        )
    }

    func testHighContrastVariantUsesEnhancedThreshold() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let split = try EditorContrastStandards(
            normalText: 4.5,
            enhancedText: 21,
            nonText: 3,
            enhancedNonText: 4.5
        )
        let tokens = SyntaxTokenKind.allCases.enumerated().map { index, kind in
            SyntaxToken(kind: kind, range: NSRange(location: index * 4, length: 3))
        }
        let lightPlan = try bind(
            resolution,
            tokens: tokens,
            palette: lightPalette(),
            in: catalog,
            standards: split
        )
        XCTAssertTrue(lightPlan.contrastIssues.isEmpty)

        let strict = try EditorContrastStandards(
            normalText: 21,
            enhancedText: 21,
            nonText: 21,
            enhancedNonText: 21
        )
        let strictPlan = try bind(
            resolution,
            tokens: tokens,
            palette: lightPalette(),
            in: catalog,
            standards: strict
        )
        XCTAssertFalse(strictPlan.contrastIssues.isEmpty)
        for issue in strictPlan.contrastIssues {
            XCTAssertEqual(issue.minimumRatio, strict.normalText)
            XCTAssertEqual(issue.backgroundRole, .textBackground)
        }

        let highContrast = try XCTUnwrap(
            EditorColorScheme.standard.palette(for: .highContrastLight)
        )
        let contrastPlan = try bind(
            resolution,
            tokens: tokens,
            palette: highContrast,
            in: catalog,
            standards: split
        )
        XCTAssertTrue(contrastPlan.contrastIssues.isEmpty)
        XCTAssertEqual(contrastPlan.variant, .highContrastLight)
    }

    func testCompletePaletteNeverFallsBackToPlainText() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        for variant in [EditorColorSchemeVariant.light, .dark] as [EditorColorSchemeVariant] {
            let palette = try XCTUnwrap(EditorColorScheme.standard.palette(for: variant))
            let tokens = SyntaxTokenKind.allCases.enumerated().map { index, kind in
                SyntaxToken(kind: kind, range: NSRange(location: index * 2, length: 1))
            }
            let plan = try bind(resolution, tokens: tokens, palette: palette, in: catalog)
            for span in plan.spans {
                XCTAssertFalse(span.didFallBackToPlainTextColor, "\(variant)")
                XCTAssertEqual(span.color, try XCTUnwrap(palette.color(for: span.colorRole)))
            }
        }
    }

    func testFallbackFlagForcesNonColorFallbackRequirement() throws {
        let palette = try lightPalette()
        let plainTextColor = try XCTUnwrap(palette.color(for: .textForeground))
        let background = try XCTUnwrap(palette.color(for: .textBackground))
        let span = SyntaxRendererSpan(
            tokenKind: .keyword,
            range: NSRange(location: 0, length: 1),
            colorRole: .syntaxKeyword,
            color: plainTextColor,
            didFallBackToPlainTextColor: true,
            contrastRatio: 21,
            meetsContrast: true,
            cue: .none
        )
        XCTAssertEqual(span.colorRole, .syntaxKeyword)
        XCTAssertEqual(span.color, plainTextColor)
        XCTAssertTrue(span.didFallBackToPlainTextColor)
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let plan = SyntaxRendererBindingPlan(
            resolution: resolution,
            variant: palette.variant,
            background: background,
            spans: [span],
            contrastIssues: []
        )
        XCTAssertTrue(plan.requiresNonColorFallback)
    }

    func testAcceptsOrderedAdjacentEmptyAndEmptyTokenList() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let tokens = [
            SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 3)),
            SyntaxToken(kind: .string, range: NSRange(location: 3, length: 0)),
            SyntaxToken(kind: .comment, range: NSRange(location: 3, length: 2))
        ]
        let plan = try bind(resolution, tokens: tokens, palette: palette, in: catalog)
        XCTAssertEqual(plan.spans.map(\.range), tokens.map(\.range))

        let empty = try bind(resolution, tokens: [], palette: palette, in: catalog)
        XCTAssertTrue(empty.spans.isEmpty)
        XCTAssertTrue(empty.contrastIssues.isEmpty)
        XCTAssertFalse(empty.requiresNonColorFallback)
    }

    func testRejectsUnorderedOverlappingAndNotFoundRanges() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let badLists: [[SyntaxToken]] = [
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 3)),
                SyntaxToken(kind: .string, range: NSRange(location: 2, length: 2))
            ],
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 5, length: 1)),
                SyntaxToken(kind: .string, range: NSRange(location: 1, length: 1))
            ],
            [SyntaxToken(kind: .keyword, range: NSRange(location: NSNotFound, length: 1))],
            [SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: -1))]
        ]
        for tokens in badLists {
            assertBindingError(.unorderedOrOverlappingTokens, tokens: tokens) {
                _ = try self.bind(resolution, tokens: tokens, palette: palette, in: catalog)
            }
        }
    }

    func testRejectsRangeOverflow() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let tokens = [
            SyntaxToken(
                kind: .keyword,
                range: NSRange(location: Int.max - 1, length: 5)
            )
        ]
        assertBindingError(.unorderedOrOverlappingTokens, tokens: tokens) {
            _ = try self.bind(resolution, tokens: tokens, palette: palette, in: catalog)
        }
    }

    func testSpanLimitAcceptsExactMaximumAndRejectsOneOver() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let limits = try SyntaxRendererBindingLimits(maximumSpanCount: 2)
        let exact = [
            SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 1)),
            SyntaxToken(kind: .string, range: NSRange(location: 1, length: 1))
        ]
        XCTAssertEqual(
            try bind(resolution, tokens: exact, palette: palette, in: catalog, limits: limits)
                .spans.count,
            2
        )
        let oneOver =
            exact + [
                SyntaxToken(kind: .comment, range: NSRange(location: 2, length: 1))
            ]
        assertBindingError(.tooManySpans(maximum: 2), tokens: oneOver) {
            _ = try self.bind(
                resolution,
                tokens: oneOver,
                palette: palette,
                in: catalog,
                limits: limits
            )
        }
    }

    func testWorkBudgetAcceptsExactMaximumAndSurfacesExceededUnwrapped() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let exact = try SyntaxRendererBindingLimits(
            maximumSpanCount: 10,
            maximumWorkUnits: 2,
            cancellationCheckInterval: 64
        )
        let tokens = [
            SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 1)),
            SyntaxToken(kind: .string, range: NSRange(location: 1, length: 1))
        ]
        XCTAssertEqual(
            try bind(resolution, tokens: tokens, palette: palette, in: catalog, limits: exact)
                .spans.count,
            2
        )
        let short = try SyntaxRendererBindingLimits(
            maximumSpanCount: 10,
            maximumWorkUnits: 1,
            cancellationCheckInterval: 64
        )
        assertBindingError(.workLimitExceeded(maximumWorkUnits: 1), tokens: tokens) {
            _ = try self.bind(
                resolution,
                tokens: tokens,
                palette: palette,
                in: catalog,
                limits: short
            )
        }
    }

    func testLimitsRejectOutOfRangeValues() {
        XCTAssertEqual(SyntaxRendererBindingLimits.default.maximumSpanCount, 1_000_000)
        XCTAssertEqual(SyntaxRendererBindingLimits.default.maximumWorkUnits, 64 * 1_024 * 1_024)
        XCTAssertEqual(SyntaxRendererBindingLimits.default.cancellationCheckInterval, 64)
        XCTAssertEqual(SyntaxRendererBindingLimits.hardMaximumSpanCount, 1_000_000)
        XCTAssertEqual(
            SyntaxRendererBindingLimits.hardMaximumWorkUnits,
            64 * 1_024 * 1_024
        )
        XCTAssertEqual(SyntaxRendererBindingLimits.hardMaximumCancellationCheckInterval, 4_096)
        for operation in [
            { _ = try SyntaxRendererBindingLimits(maximumSpanCount: 0) },
            {
                _ = try SyntaxRendererBindingLimits(
                    maximumSpanCount: SyntaxRendererBindingLimits.hardMaximumSpanCount + 1
                )
            },
            { _ = try SyntaxRendererBindingLimits(maximumWorkUnits: 0) },
            {
                _ = try SyntaxRendererBindingLimits(
                    maximumWorkUnits: SyntaxRendererBindingLimits.hardMaximumWorkUnits + 1
                )
            },
            { _ = try SyntaxRendererBindingLimits(cancellationCheckInterval: 0) },
            {
                _ = try SyntaxRendererBindingLimits(
                    cancellationCheckInterval: SyntaxRendererBindingLimits
                        .hardMaximumCancellationCheckInterval + 1
                )
            }
        ] {
            XCTAssertThrowsError(try operation()) { error in
                XCTAssertEqual(error as? SyntaxRendererBindingError, .invalidLimits)
            }
        }
    }

    func testStaleCatalogValidationMapsExpectedAndActualRevisions() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let moved = try SyntaxSchemeCatalog(
            revision: SyntaxSchemeCatalogRevision(lineage: 0, generation: 1)
        )
        let palette = try lightPalette()

        XCTAssertTrue(try resolution.isCurrent(in: catalog))
        XCTAssertNoThrow(try resolution.validate(against: catalog))
        let plan = try bind(
            resolution,
            tokens: sampleTokens(),
            palette: palette,
            in: catalog
        )
        XCTAssertTrue(try plan.isCurrent(in: catalog))
        XCTAssertFalse(try plan.isCurrent(in: moved))

        let expected = SyntaxRendererBindingError.staleCatalog(
            expected: catalog.revision,
            actual: moved.revision
        )
        assertBindingError(expected, tokens: sampleTokens()) {
            _ = try self.bind(
                resolution,
                tokens: self.sampleTokens(),
                palette: palette,
                in: moved
            )
        }
        // Wave 3 decision: plan.validate maps stale/cancelled, rethrows other catalog errors raw.
        XCTAssertThrowsError(try plan.validate(against: moved)) { error in
            XCTAssertEqual(error as? SyntaxRendererBindingError, expected)
        }
    }

    func testCancelledBindReturnsTypedError() async throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try XCTUnwrap(EditorColorScheme.standard.palette(for: .light))
        let tokens = sampleTokens()
        let error = await Task.detached { [catalog, resolution, palette, tokens] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try SyntaxRendererBindingPlanner.bind(
                    resolution,
                    tokens: tokens,
                    palette: palette,
                    in: catalog
                )
                return nil as SyntaxRendererBindingError?
            } catch let bindingError as SyntaxRendererBindingError {
                return bindingError
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(error, .cancelled)
    }

    func testIncompletePaletteGuardMirrorsPaletteValidation() throws {
        let base = try lightPalette()
        let removedTokens = Set(
            base.assignments.filter { $0.role == .textBackground }.map(\.token)
        )
        let assignments = base.assignments.filter { $0.role != .textBackground }
        let definitions = base.definitions.filter { !removedTokens.contains($0.token) }
        XCTAssertThrowsError(
            try EditorColorPalette(
                variant: base.variant,
                definitions: definitions,
                assignments: assignments
            )
        ) { error in
            XCTAssertEqual(
                error as? EditorColorSchemeError,
                .missingColorRole(.textBackground)
            )
        }
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let plan = try bind(resolution, tokens: sampleTokens(), palette: base, in: catalog)
        XCTAssertFalse(plan.spans.isEmpty)
    }

    func testCancellationCheckIntervalOneSucceedsWhenNotCancelled() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let limits = try SyntaxRendererBindingLimits(
            maximumSpanCount: 10,
            maximumWorkUnits: 10,
            cancellationCheckInterval: 1
        )
        let tokens = [
            SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 1)),
            SyntaxToken(kind: .string, range: NSRange(location: 1, length: 1))
        ]
        let plan = try bind(
            resolution,
            tokens: tokens,
            palette: palette,
            in: catalog,
            limits: limits
        )
        XCTAssertEqual(plan.spans.count, 2)
    }

    func testMidLoopCancellationWithIntervalOneReturnsTypedError() async throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let limits = try SyntaxRendererBindingLimits(
            maximumSpanCount: 1_000_000,
            maximumWorkUnits: 64 * 1_024 * 1_024,
            cancellationCheckInterval: 1
        )
        let tokens = (0..<100_000).map { index in
            SyntaxToken(kind: .keyword, range: NSRange(location: index * 2, length: 1))
        }
        let start = StartProbe()
        let task = Task.detached { [catalog, resolution, palette, tokens, limits] in
            await start.markStarted()
            do {
                _ = try SyntaxRendererBindingPlanner.bind(
                    resolution,
                    tokens: tokens,
                    palette: palette,
                    in: catalog,
                    limits: limits
                )
                return nil as SyntaxRendererBindingError?
            } catch let bindingError as SyntaxRendererBindingError {
                return bindingError
            } catch {
                return nil
            }
        }
        await start.waitUntilStarted()
        try await ContinuousClock().sleep(for: .milliseconds(1))
        task.cancel()
        let error = await task.value
        XCTAssertEqual(error, .cancelled)
    }

    func testPlanRedactsSchemeMetadata() throws {
        let catalog = try SyntaxSchemeCatalog()
        let resolution = try catalog.resolve(.none, language: .swift, mode: .textComparison)
        let palette = try lightPalette()
        let plan = try bind(resolution, tokens: sampleTokens(), palette: palette, in: catalog)
        let identifier = SyntaxSchemeIdentifier.builtInSwift.rawValue

        for text in [plan.description, plan.debugDescription] {
            XCTAssertTrue(text.contains("<redacted>"))
            XCTAssertFalse(text.contains(identifier))
        }
        let mirrored = Mirror(reflecting: plan).children.map {
            "\($0.label ?? "")=\(String(describing: $0.value))"
        }.joined(separator: " ")
        XCTAssertTrue(mirrored.contains("<redacted>"))
        XCTAssertFalse(mirrored.contains(identifier))
    }

    func testErrorDescriptionsAreStable() {
        let cases: [(SyntaxRendererBindingError, String)] = [
            (.invalidLimits, "Syntax renderer binding limits are invalid."),
            (.tooManySpans(maximum: 5), "Syntax renderer binding exceeds the 5-span limit."),
            (
                .unorderedOrOverlappingTokens,
                "Syntax tokens are not in strictly increasing, non-overlapping order."
            ),
            (
                .incompletePalette,
                "Editor palette is missing a color required for syntax binding."
            ),
            (
                .workLimitExceeded(maximumWorkUnits: 7),
                "Syntax renderer binding exceeds the 7-unit work limit."
            ),
            (
                .staleCatalog(
                    expected: SyntaxSchemeCatalogRevision(lineage: 1, generation: 2),
                    actual: SyntaxSchemeCatalogRevision(lineage: 1, generation: 3)
                ),
                "Syntax renderer binding belongs to a stale catalog snapshot."
            ),
            (.cancelled, "Syntax renderer binding was cancelled.")
        ]
        for (error, message) in cases {
            XCTAssertEqual(error.errorDescription, message)
        }
    }

    private func sampleTokens() -> [SyntaxToken] {
        [
            SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 3)),
            SyntaxToken(kind: .string, range: NSRange(location: 4, length: 3))
        ]
    }

    private func lightPalette() throws -> EditorColorPalette {
        try XCTUnwrap(EditorColorScheme.standard.palette(for: .light))
    }

    private func bind(
        _ resolution: SyntaxSchemeResolution,
        tokens: [SyntaxToken],
        palette: EditorColorPalette,
        in catalog: SyntaxSchemeCatalog,
        standards: EditorContrastStandards = .default,
        limits: SyntaxRendererBindingLimits = .default
    ) throws -> SyntaxRendererBindingPlan {
        try SyntaxRendererBindingPlanner.bind(
            resolution,
            tokens: tokens,
            palette: palette,
            in: catalog,
            standards: standards,
            limits: limits
        )
    }

    private func assertBindingError(
        _ expected: SyntaxRendererBindingError,
        tokens: [SyntaxToken],
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), "\(tokens.count) tokens", file: file, line: line) {
            error in
            XCTAssertEqual(
                error as? SyntaxRendererBindingError,
                expected,
                "\(tokens.count) tokens",
                file: file,
                line: line
            )
        }
    }
}
