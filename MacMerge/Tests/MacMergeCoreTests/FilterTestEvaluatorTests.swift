import CXDiff
import Foundation
import MacMergeCore
import XCTest

final class FilterTestEvaluatorTests: XCTestCase {
    private static let nativeRegexWork = 1_000_000
    private static let nativePatternByteLimit = 4_096

    func testFilenameEvaluatorMatchesProductionDecisionDiagnosticsAndActualWork() throws {
        let rules = [
            FilenameFilterRule(.exclude, pattern: .glob("**/*.tmp"), applicability: .files),
            FilenameFilterRule(.include, pattern: .glob("Sources/**"), applicability: .files),
            FilenameFilterRule(.exclude, pattern: .glob("Build/**"), applicability: .directories)
        ]
        let relativePath = "Sources/cache.tmp"
        let filenameLimits = FilenameFilterLimits(maximumMatchWork: 50_000)
        let productionFilter = try FilenameFilter(
            rules: rules,
            defaultDecision: .exclude,
            matchSemantics: .lastMatchWins,
            casePolicy: .sensitive,
            limits: filenameLimits
        )
        let production = try productionFilter.evaluate(relativePath: relativePath, kind: .file)
        let test = FilterTestCase.filename(
            FilenameFilterTestCase(
                rules: rules,
                defaultDecision: .exclude,
                matchSemantics: .lastMatchWins,
                casePolicy: .sensitive,
                relativePath: relativePath,
                entryKind: .file,
                limits: filenameLimits
            ))

        let result = try FilterTestEvaluator.evaluate(test)

        XCTAssertEqual(result.state, .evaluated)
        XCTAssertEqual(result.outcome, production.isIncluded ? .matched : .notMatched)
        XCTAssertEqual(result.value, .filename(decision: production.decision))
        XCTAssertEqual(result.matchedRuleIndices, production.matchedRuleIndex.map { [$0] } ?? [])
        XCTAssertEqual(
            result.diagnostics,
            productionFilter.diagnostics.map {
                FilterTestDiagnostic(kind: .filename, code: diagnosticCode(for: $0), ruleIndex: $0.ruleIndex)
            })

        let retainedCount = 1 + result.matchedRuleIndices.count
        let expectedWork =
            2
            + rules.reduce(0) { $0 + $1.pattern.source.utf8.count }
            + relativePath.utf8.count
            + relativePath.utf8.count
            + rules.count
            + production.work
            + retainedCount
        let evaluation = try FilterTestEvaluator.evaluate(.test(test))
        XCTAssertEqual(evaluation.work, expectedWork)
        XCTAssertLessThan(production.work, filenameLimits.maximumMatchWork)
        XCTAssertEqual(try FilterTestEvaluator.evaluate(.test(test), limits: limits(maximumWork: expectedWork)), evaluation)
        assertFilterError(.workLimitExceeded(maximumWork: expectedWork - 1)) {
            _ = try FilterTestEvaluator.evaluate(.test(test), limits: self.limits(maximumWork: expectedWork - 1))
        }
    }

    func testFilenameEvaluatorMapsInvalidRuleAndInputDiagnostics() throws {
        let invalidRule = try FilterTestEvaluator.evaluate(
            .filename(
                FilenameFilterTestCase(
                    rules: [FilenameFilterRule(.exclude, pattern: .glob("["))],
                    relativePath: "valid.txt"
                )))
        XCTAssertEqual(invalidRule.state, .evaluated)
        XCTAssertEqual(invalidRule.value, .filename(decision: .include))
        XCTAssertEqual(
            invalidRule.diagnostics,
            [
                FilterTestDiagnostic(
                    kind: .filename,
                    code: .invalidPattern,
                    ruleIndex: 0,
                    unicodeScalarOffset: 0
                )
            ])

        let invalidInput = try FilterTestEvaluator.evaluate(
            .filename(
                FilenameFilterTestCase(
                    rules: [],
                    relativePath: "../escape"
                )))
        XCTAssertEqual(invalidInput.state, .invalid)
        XCTAssertNil(invalidInput.value)
        XCTAssertEqual(
            invalidInput.diagnostics,
            [
                FilterTestDiagnostic(kind: .filename, code: .invalidInput)
            ])
    }

    func testFilenameFailedMatchWorkChargesConfiguredLimitAtExactBoundary() throws {
        let rule = FilenameFilterRule(.exclude, pattern: .glob("*"), applicability: .files)
        let relativePath = "value"
        let matchWork = 1
        let test = FilterTestCase.filename(
            FilenameFilterTestCase(
                rules: [rule],
                relativePath: relativePath,
                limits: FilenameFilterLimits(maximumMatchWork: matchWork)
            ))
        let exactWork =
            2
            + rule.pattern.source.utf8.count
            + relativePath.utf8.count
            + relativePath.utf8.count
            + 1
            + matchWork
            + 2

        let evaluation = try FilterTestEvaluator.evaluate(
            .test(test),
            limits: limits(maximumWork: exactWork)
        )

        XCTAssertEqual(evaluation.work, exactWork)
        XCTAssertEqual(evaluation.outcome, .failed)
        XCTAssertEqual(
            evaluation.diagnostics,
            [
                FilterTestDiagnostic(
                    kind: .filename,
                    code: .evaluationLimitExceeded,
                    limit: matchWork
                )
            ])
        assertFilterError(.workLimitExceeded(maximumWork: exactWork - 1)) {
            _ = try FilterTestEvaluator.evaluate(
                .test(test),
                limits: self.limits(maximumWork: exactWork - 1)
            )
        }
    }

    func testDisplayEvaluatorMatchesProductionVisibilityAndLiteralRange() throws {
        let filter = DisplayFilter(
            literal: "needle",
            caseSensitive: false
        )
        let input = DisplayFilterTestInput(
            leftText: "left",
            rightText: "right NEEDLE value",
            kind: .modified
        )
        let production = try filter.apply(to: [input.row])
        let test = FilterTestCase.display(DisplayFilterTestCase(filter: filter, input: input))

        let result = try FilterTestEvaluator.evaluate(test)

        let expectedVisible = production.sourceRowIndices == [0]
        XCTAssertEqual(result.state, .evaluated)
        XCTAssertEqual(result.value, .display(isVisible: expectedVisible))
        XCTAssertEqual(result.outcome, expectedVisible ? .matched : .notMatched)
        XCTAssertEqual(
            result.matchRanges,
            [
                FilterTestMatchRange(
                    field: .rightInput,
                    utf16Range: NSRange(location: 6, length: 6)
                )
            ])

        let inputByteCount =
            (input.row.left?.text.utf8.count ?? 0)
            + (input.row.right?.text.utf8.count ?? 0)
        let expectedWork =
            2
            + filter.expression.text.utf8.count
            + inputByteCount
            + inputByteCount
            + 1
            + 1
            + result.matchRanges.count
        XCTAssertEqual(try FilterTestEvaluator.evaluate(.test(test)).work, expectedWork)
    }

    func testDisplayRegularExpressionReservesConfiguredProgressBoundExactly() throws {
        let progressLimit = 1_000
        let displayLimits = DisplayFilterLimits(maximumRegularExpressionProgressSteps: progressLimit)
        let filter = DisplayFilter(regularExpression: "^needle$", caseSensitive: true)
        let input = DisplayFilterTestInput(leftText: "needle", rightText: nil, kind: .modified)
        let test = FilterTestCase.display(
            DisplayFilterTestCase(
                filter: filter,
                input: input,
                limits: displayLimits
            ))
        let inputByteCount = input.row.left?.text.utf8.count ?? 0
        let exactWork =
            2
            + filter.expression.text.utf8.count
            + inputByteCount
            + inputByteCount
            + 1
            + progressLimit
            + 1

        let exact = try FilterTestEvaluator.evaluate(.test(test), limits: limits(maximumWork: exactWork))

        XCTAssertEqual(exact.outcome, .matched)
        XCTAssertEqual(exact.work, exactWork)
        assertFilterError(.workLimitExceeded(maximumWork: exactWork - 1)) {
            _ = try FilterTestEvaluator.evaluate(
                .test(test),
                limits: self.limits(maximumWork: exactWork - 1)
            )
        }
    }

    func testDisplayEvaluatorMapsPatternInputAndEvaluationDiagnostics() throws {
        let invalidPattern = try FilterTestEvaluator.evaluate(
            .display(
                DisplayFilterTestCase(
                    filter: DisplayFilter(regularExpression: "["),
                    input: DisplayFilterTestInput(leftText: "value", rightText: nil, kind: .modified)
                )))
        XCTAssertEqual(invalidPattern.state, .invalid)
        XCTAssertEqual(
            invalidPattern.diagnostics,
            [
                FilterTestDiagnostic(kind: .display, code: .invalidPattern)
            ])

        let missingMovedMetadata = try FilterTestEvaluator.evaluate(
            .display(
                DisplayFilterTestCase(
                    filter: DisplayFilter(predicate: .moved),
                    input: DisplayFilterTestInput(leftText: "value", rightText: "value", kind: .unchanged)
                )))
        XCTAssertEqual(missingMovedMetadata.state, .invalid)
        XCTAssertEqual(
            missingMovedMetadata.diagnostics,
            [
                FilterTestDiagnostic(kind: .display, code: .invalidInput)
            ])

        let inputLimit = 3
        let oversizedInput = try FilterTestEvaluator.evaluate(
            .display(
                DisplayFilterTestCase(
                    filter: DisplayFilter(literal: "x"),
                    input: DisplayFilterTestInput(leftText: "four", rightText: nil, kind: .modified),
                    limits: DisplayFilterLimits(maximumLineUTF16Length: inputLimit)
                )))
        XCTAssertEqual(oversizedInput.state, .failed)
        XCTAssertEqual(
            oversizedInput.diagnostics,
            [
                FilterTestDiagnostic(kind: .display, code: .inputLimitExceeded, limit: inputLimit)
            ])
    }

    func testLineEvaluatorMatchesProductionAndChargesOneNativePassExactly() throws {
        let rule = LineFilterRule(pattern: #"^error \d+$"#, caseSensitive: false)
        let input = "ERROR 42"
        let test = FilterTestCase.line(LineFilterTestCase(rule: rule, input: input))
        let productionRows = try LineDiff.compare(
            left: input,
            right: "error 99",
            options: LineDiffOptions(lineFilters: [rule])
        )

        let result = try FilterTestEvaluator.evaluate(test)

        XCTAssertEqual(DiffSummary(rows: productionRows).differences, 0)
        XCTAssertEqual(result.state, .evaluated)
        XCTAssertEqual(result.value, .line(isFiltered: true))
        XCTAssertEqual(result.matchedRuleIndices, [0])
        XCTAssertEqual(
            result.matchRanges,
            [
                FilterTestMatchRange(
                    field: .input,
                    utf16Range: NSRange(location: 0, length: input.utf16.count)
                )
            ])

        let expectedWork =
            2
            + rule.pattern.utf8.count
            + input.utf8.count
            + input.utf8.count
            + rule.pattern.utf8.count
            + input.utf8.count
            + Self.nativeRegexWork
            + 3
        let exact = try FilterTestEvaluator.evaluate(.test(test), limits: limits(maximumWork: expectedWork))
        XCTAssertEqual(exact.work, expectedWork)
        XCTAssertEqual(exact.results, [result])
        assertFilterError(.workLimitExceeded(maximumWork: expectedWork - 1)) {
            _ = try FilterTestEvaluator.evaluate(
                .test(test),
                limits: self.limits(maximumWork: expectedWork - 1)
            )
        }
    }

    func testMultiRuleLineEvaluatorReservesEverySequentialPassAndMatchesLineDiff() throws {
        let rules = [
            LineFilterRule(pattern: "^other$"),
            LineFilterRule(pattern: #"^value \d+$"#)
        ]
        let input = "value 1"
        let test = FilterTestCase.line(LineFilterTestCase(rules: rules, input: input))
        let productionRows = try LineDiff.compare(
            left: input,
            right: "value 2",
            options: LineDiffOptions(lineFilters: rules)
        )
        let patternBytes = rules.reduce(0) { $0 + $1.pattern.utf8.count }
        let inputBytes = input.utf8.count
        let exactWork =
            2
            + patternBytes
            + inputBytes
            + inputBytes
            + patternBytes
            + rules.count * (inputBytes + Self.nativeRegexWork)
            + 3

        let evaluation = try FilterTestEvaluator.evaluate(
            .test(test),
            limits: limits(maximumWork: exactWork)
        )

        XCTAssertEqual(DiffSummary(rows: productionRows).differences, 0)
        XCTAssertEqual(evaluation.work, exactWork)
        XCTAssertEqual(evaluation.outcome, .matched)
        XCTAssertEqual(evaluation.results.first?.matchedRuleIndices, [1])
        assertFilterError(.workLimitExceeded(maximumWork: exactWork - 1)) {
            _ = try FilterTestEvaluator.evaluate(
                .test(test),
                limits: self.limits(maximumWork: exactWork - 1)
            )
        }
    }

    func testLineEvaluatorRejectsCarriageReturnAndLineFeedSubjects() throws {
        for terminator in ["\r", "\n", "\r\n"] {
            let result = try FilterTestEvaluator.evaluate(
                .line(
                    LineFilterTestCase(
                        rule: LineFilterRule(pattern: ".*"),
                        input: "left\(terminator)right"
                    )))

            XCTAssertEqual(result.state, .invalid, terminator.debugDescription)
            XCTAssertNil(result.value, terminator.debugDescription)
            XCTAssertEqual(
                result.diagnostics,
                [
                    FilterTestDiagnostic(kind: .line, code: .invalidInput)
                ], terminator.debugDescription)
        }
    }

    func testNativeMultibytePatternBoundaryIsExactlyFourKiBForLineAndSubstitutionEvaluators() throws {
        let multibyteScalar = "é"
        let exactPattern = String(
            repeating: multibyteScalar,
            count: Self.nativePatternByteLimit / multibyteScalar.utf8.count
        )
        let oversizedPattern = exactPattern + "a"
        let permissiveLimits = limits(maximumPatternUTF8Bytes: Int.max)

        XCTAssertEqual(exactPattern.utf8.count, 4_096)
        XCTAssertEqual(oversizedPattern.utf8.count, 4_097)

        let line = try FilterTestEvaluator.evaluate(
            .line(LineFilterTestCase(rule: LineFilterRule(pattern: exactPattern), input: "")),
            limits: permissiveLimits
        )
        let substitution = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: SubstitutionRule(pattern: exactPattern, replacement: "x"),
                    input: ""
                )),
            limits: permissiveLimits
        )
        XCTAssertEqual(line.state, .evaluated)
        XCTAssertEqual(substitution.state, .evaluated)

        for test in [
            FilterTestCase.line(
                LineFilterTestCase(
                    rule: LineFilterRule(pattern: oversizedPattern),
                    input: ""
                )),
            FilterTestCase.substitution(
                SubstitutionFilterTestCase(
                    rule: SubstitutionRule(pattern: oversizedPattern, replacement: "x"),
                    input: ""
                ))
        ] {
            assertFilterError(
                .patternTooLarge(
                    kind: test.kind,
                    ruleIndex: 0,
                    maximumUTF8Bytes: Self.nativePatternByteLimit
                )
            ) {
                _ = try FilterTestEvaluator.evaluate(test, limits: permissiveLimits)
            }
        }
    }

    func testNativeRegexFailuresMapToRuleSpecificDiagnosticsAndRecover() throws {
        let invalidLine = try FilterTestEvaluator.evaluate(
            .line(
                LineFilterTestCase(
                    rule: LineFilterRule(pattern: "["),
                    input: "value"
                )))
        let invalidSubstitution = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: SubstitutionRule(pattern: "[", replacement: "value"),
                    input: "value"
                )))
        XCTAssertEqual(invalidLine.state, .invalid)
        XCTAssertEqual(
            invalidLine.diagnostics,
            [
                FilterTestDiagnostic(kind: .line, code: .invalidPattern, ruleIndex: 0)
            ])
        XCTAssertEqual(invalidSubstitution.state, .invalid)
        XCTAssertEqual(
            invalidSubstitution.diagnostics,
            [
                FilterTestDiagnostic(kind: .substitution, code: .invalidPattern, ruleIndex: 0)
            ])

        let subject = String(repeating: "a", count: 21) + "!"
        let pathologicalPattern = "(*NO_AUTO_POSSESS)(*NO_START_OPT)^(a+)+$"
        let limitedLine = try FilterTestEvaluator.evaluate(
            .line(
                LineFilterTestCase(
                    rule: LineFilterRule(pattern: pathologicalPattern),
                    input: subject
                )))
        let limitedSubstitution = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: SubstitutionRule(pattern: pathologicalPattern, replacement: "match"),
                    input: subject
                )))
        XCTAssertEqual(limitedLine.state, .failed)
        XCTAssertEqual(
            limitedLine.diagnostics,
            [
                FilterTestDiagnostic(kind: .line, code: .evaluationLimitExceeded, ruleIndex: 0)
            ])
        XCTAssertEqual(limitedSubstitution.state, .failed)
        XCTAssertEqual(
            limitedSubstitution.diagnostics,
            [
                FilterTestDiagnostic(kind: .substitution, code: .evaluationLimitExceeded, ruleIndex: 0)
            ])

        let recovered = try FilterTestEvaluator.evaluate(
            .line(
                LineFilterTestCase(
                    rule: LineFilterRule(pattern: "^ok$"),
                    input: "ok"
                )))
        XCTAssertEqual(recovered.outcome, .matched)
    }

    func testSubstitutionEvaluatorMatchesProductionBytesCapturesEscapesAndExactWork() throws {
        let rule = SubstitutionRule(pattern: #"([A-Z]+)-(\d+)"#, replacement: #"\2:\1"#)
        let input = "ABC-123"
        let expectedOutput = "123:ABC"
        let test = FilterTestCase.substitution(SubstitutionFilterTestCase(rule: rule, input: input))
        let productionRows = try LineDiff.compare(
            left: input,
            right: expectedOutput,
            options: LineDiffOptions(substitutions: [rule])
        )

        let result = try FilterTestEvaluator.evaluate(test)
        let substitution = try substitutionValue(result)

        XCTAssertEqual(DiffSummary(rows: productionRows).differences, 0)
        XCTAssertEqual(result.state, .evaluated)
        XCTAssertTrue(substitution.didMatch)
        XCTAssertEqual(substitution.output.bytes, Array(expectedOutput.utf8))
        XCTAssertEqual(result.matchedRuleIndices, [0])
        XCTAssertEqual(result.matchRanges.map(\.field), [.input, .output])

        let patternBytes = rule.pattern.utf8.count
        let storedReplacementBytes = rule.replacement.utf8.count
        let nativeReplacementBytes = #"$2:$1"#.utf8.count
        let inputBytes = input.utf8.count
        let outputBytes = expectedOutput.utf8.count
        let expectedWork =
            2
            + patternBytes
            + storedReplacementBytes
            + inputBytes
            + inputBytes
            + patternBytes
            + nativeReplacementBytes
            + inputBytes
            + patternBytes
            + nativeReplacementBytes
            + 1
            + (inputBytes + 1) * Self.nativeRegexWork
            + outputBytes
            + 4
        let exact = try FilterTestEvaluator.evaluate(.test(test), limits: limits(maximumWork: expectedWork))
        XCTAssertEqual(exact.work, expectedWork)
        XCTAssertEqual(exact.results, [result])
        assertFilterError(.workLimitExceeded(maximumWork: expectedWork - 1)) {
            _ = try FilterTestEvaluator.evaluate(
                .test(test),
                limits: self.limits(maximumWork: expectedWork - 1)
            )
        }
    }

    func testGrowingSubstitutionsChargeSequentialOutputSizesAndMatchLineDiff() throws {
        let rules = [
            SubstitutionRule(pattern: "a", replacement: "aa"),
            SubstitutionRule(pattern: "a", replacement: "bb")
        ]
        let input = "a"
        let expectedOutput = "bbbb"
        let test = FilterTestCase.substitution(SubstitutionFilterTestCase(rules: rules, input: input))
        let productionRows = try LineDiff.compare(
            left: input,
            right: expectedOutput,
            options: LineDiffOptions(substitutions: rules)
        )
        let patternBytes = rules.reduce(0) { $0 + $1.pattern.utf8.count }
        let replacementBytes = rules.reduce(0) { $0 + $1.replacement.utf8.count }
        let firstInputBytes = input.utf8.count
        let secondInputBytes = 2
        let outputBytes = expectedOutput.utf8.count
        let exactWork =
            2
            + patternBytes
            + replacementBytes
            + firstInputBytes
            + firstInputBytes
            + patternBytes
            + replacementBytes
            + firstInputBytes
            + rules[0].pattern.utf8.count
            + rules[0].replacement.utf8.count
            + 1
            + (firstInputBytes + 1) * Self.nativeRegexWork
            + secondInputBytes
            + rules[1].pattern.utf8.count
            + rules[1].replacement.utf8.count
            + 1
            + (secondInputBytes + 1) * Self.nativeRegexWork
            + outputBytes
            + 5

        let evaluation = try FilterTestEvaluator.evaluate(
            .test(test),
            limits: limits(maximumWork: exactWork)
        )
        let result = try XCTUnwrap(evaluation.results.first)
        let substitution = try substitutionValue(result)

        XCTAssertEqual(DiffSummary(rows: productionRows).differences, 0)
        XCTAssertEqual(substitution.output.bytes, Array(expectedOutput.utf8))
        XCTAssertEqual(result.matchedRuleIndices, [0, 1])
        XCTAssertEqual(evaluation.work, exactWork)
        assertFilterError(.workLimitExceeded(maximumWork: exactWork - 1)) {
            _ = try FilterTestEvaluator.evaluate(
                .test(test),
                limits: self.limits(maximumWork: exactWork - 1)
            )
        }
    }

    func testSubstitutionMatchedToEmptyRetainsMatchMetadata() throws {
        let input = "value"
        let result = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: SubstitutionRule(pattern: input, replacement: ""),
                    input: input
                )))
        let substitution = try substitutionValue(result)

        XCTAssertTrue(substitution.didMatch)
        XCTAssertEqual(substitution.output.bytes, [])
        XCTAssertEqual(result.matchedRuleIndices, [0])
        XCTAssertEqual(
            result.matchRanges,
            [
                FilterTestMatchRange(
                    field: .input,
                    utf16Range: NSRange(location: 0, length: input.utf16.count)
                ),
                FilterTestMatchRange(
                    field: .output,
                    utf16Range: NSRange(location: 0, length: 0)
                )
            ])
    }

    func testEmptySubstitutionSubjectReservesZeroNativeMatchWork() throws {
        let rule = SubstitutionRule(pattern: "a", replacement: "b")
        let test = FilterTestCase.substitution(SubstitutionFilterTestCase(rule: rule, input: ""))
        let expectedWorkWithoutNativeMatches = 10

        let evaluation = try FilterTestEvaluator.evaluate(
            .test(test),
            limits: limits(maximumWork: expectedWorkWithoutNativeMatches)
        )
        let result = try XCTUnwrap(evaluation.results.first)
        let substitution = try substitutionValue(result)

        XCTAssertEqual(evaluation.work, expectedWorkWithoutNativeMatches)
        XCTAssertFalse(substitution.didMatch)
        XCTAssertEqual(substitution.output.bytes, [])
        XCTAssertEqual(result.matchedRuleIndices, [])
        XCTAssertEqual(result.matchRanges, [])
        assertFilterError(.workLimitExceeded(maximumWork: expectedWorkWithoutNativeMatches - 1)) {
            _ = try FilterTestEvaluator.evaluate(
                .test(test),
                limits: self.limits(maximumWork: expectedWorkWithoutNativeMatches - 1)
            )
        }
    }

    func testSubstitutionMatchMetadataComesFromSameReplacementSensitiveNativeCall() throws {
        let rule = SubstitutionRule(pattern: "(a)|(b)", replacement: #"\1"#)
        let skipped = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: rule,
                    input: "b"
                )))
        let continued = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: rule,
                    input: "a b"
                )))
        let skippedValue = try substitutionValue(skipped)
        let continuedValue = try substitutionValue(continued)

        XCTAssertEqual(skippedValue.output.bytes, Array("b".utf8))
        XCTAssertFalse(skippedValue.didMatch, "Unset capture must skip the actual replacement call")
        XCTAssertEqual(skipped.matchedRuleIndices, [])
        XCTAssertEqual(skipped.matchRanges, [])

        XCTAssertEqual(continuedValue.output.bytes, Array("a b".utf8))
        XCTAssertTrue(continuedValue.didMatch, "Earlier successful replacement survives a later skipped continuation")
        XCTAssertEqual(continued.matchedRuleIndices, [0])
        XCTAssertEqual(continued.matchRanges.map(\.field), [.input, .output])
    }

    func testWinMergePartialHexByteParityForBackslashX1G() throws {
        let partialHexRule = SubstitutionRule(pattern: "left", replacement: #"\x1G"#)
        let explicitHexRule = SubstitutionRule(pattern: "right", replacement: #"\x01"#)
        let partial = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: partialHexRule,
                    input: "left"
                )))
        let explicit = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: explicitHexRule,
                    input: "right"
                )))
        let productionRows = try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [partialHexRule, explicitHexRule])
        )

        XCTAssertEqual(try substitutionValue(partial).output.bytes, [0x01])
        XCTAssertEqual(try substitutionValue(explicit).output.bytes, [0x01])
        XCTAssertEqual(DiffSummary(rows: productionRows).differences, 0)
    }

    func testSubstitutionPreservesRecordCountAcrossCRLFNormalizationAndRejectsStructuralChanges() throws {
        let input = "left\r\nright"
        let normalizationRule = SubstitutionRule(pattern: "\r\n", replacement: #"\n"#)
        let normalized = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: normalizationRule,
                    input: input
                )))
        let productionRows = try LineDiff.compare(
            left: input,
            right: "left\nright",
            options: LineDiffOptions(ignoreLineEndings: false, substitutions: [normalizationRule])
        )

        XCTAssertEqual(normalized.state, .evaluated)
        XCTAssertEqual(try substitutionValue(normalized).output.bytes, Array("left\nright".utf8))
        XCTAssertEqual(DiffSummary(rows: productionRows).differences, 0)

        for rule in [
            SubstitutionRule(pattern: "left", replacement: #"left\nextra"#),
            SubstitutionRule(pattern: "left\r\n", replacement: "")
        ] {
            let result = try FilterTestEvaluator.evaluate(
                .substitution(
                    SubstitutionFilterTestCase(
                        rule: rule,
                        input: input
                    )))
            XCTAssertEqual(result.state, .failed)
            XCTAssertNil(result.value)
            XCTAssertEqual(
                result.diagnostics,
                [
                    FilterTestDiagnostic(kind: .substitution, code: .changedLineStructure)
                ])
            XCTAssertThrowsError(
                try LineDiff.compare(
                    left: input,
                    right: "other\r\nvalue",
                    options: LineDiffOptions(ignoreLineEndings: false, substitutions: [rule])
                )
            ) { error in
                XCTAssertEqual(error as? LineDiffError, .filterChangedLineStructure)
            }
        }
    }

    func testSubstitutionOutputLimitAndInvalidUTF8Diagnostics() throws {
        let outputLimited = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: SubstitutionRule(pattern: "a", replacement: "bb"),
                    input: "aa"
                )),
            limits: limits(maximumOutputUTF8Bytes: 3)
        )
        XCTAssertEqual(outputLimited.state, .failed)
        XCTAssertEqual(
            outputLimited.diagnostics,
            [
                FilterTestDiagnostic(kind: .substitution, code: .outputLimitExceeded, ruleIndex: 0)
            ])

        let rawByte = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: SubstitutionRule(pattern: "value", replacement: #"\xEF"#),
                    input: "value"
                )))
        let rawValue = try substitutionValue(rawByte)
        XCTAssertEqual(rawValue.output.bytes, [0xEF])
        XCTAssertFalse(rawValue.output.isValidUTF8)
        XCTAssertEqual(
            rawByte.diagnostics,
            [
                FilterTestDiagnostic(kind: .substitution, code: .outputIsNotValidUTF8)
            ])
    }

    func testFrozenLegacyCRegexCallerReceivesPlainSizeWhileEvaluatorOptsIntoMetadata() throws {
        let successful = try frozenLegacyCSubstitute()
        let legacy = legacySubstitute(
            subject: "b",
            pattern: "(a)|(b)",
            replacement: "$1"
        )
        XCTAssertEqual(successful.status, 0)
        XCTAssertEqual(successful.reportedSize, "expanded".utf8.count)
        XCTAssertEqual(successful.output, Array("expanded".utf8))
        XCTAssertEqual(legacy.status, 0)
        XCTAssertEqual(legacy.reportedSize, 1)
        XCTAssertEqual(legacy.output, Array("b".utf8))

        let publicResult = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rule: SubstitutionRule(pattern: "(a)|(b)", replacement: #"\1"#),
                    input: "b"
                )))
        XCTAssertFalse(try substitutionValue(publicResult).didMatch)
    }

    func testDisabledAndRulelessCasesReturnTypedNoOps() throws {
        let disabled: [(test: FilterTestCase, value: FilterTestResultValue)] = [
            (
                .filename(
                    FilenameFilterTestCase(
                        enabled: false,
                        rules: [FilenameFilterRule(.exclude, pattern: .glob("*"))],
                        relativePath: "value"
                    )),
                .filename(decision: .include)
            ),
            (
                .display(
                    DisplayFilterTestCase(
                        enabled: false,
                        filter: DisplayFilter(literal: "value"),
                        input: DisplayFilterTestInput(
                            leftText: "value",
                            rightText: nil,
                            kind: .modified
                        )
                    )),
                .display(isVisible: true)
            ),
            (
                .line(
                    LineFilterTestCase(
                        enabled: false,
                        rule: LineFilterRule(pattern: "value"),
                        input: "value"
                    )),
                .line(isFiltered: false)
            ),
            (
                .substitution(
                    SubstitutionFilterTestCase(
                        enabled: false,
                        rule: SubstitutionRule(pattern: "value", replacement: "other"),
                        input: "value"
                    )),
                .substitution(output: FilterTestOutput("value"), didMatch: false)
            )
        ]
        for (test, value) in disabled {
            let result = try FilterTestEvaluator.evaluate(test)
            XCTAssertEqual(result.kind, test.kind)
            XCTAssertEqual(result.state, .noOp)
            XCTAssertEqual(result.outcome, .noOp)
            XCTAssertEqual(result.value, value)
            XCTAssertEqual(result.matchedRuleIndices, [])
            XCTAssertEqual(result.matchRanges, [])
            XCTAssertEqual(
                result.diagnostics,
                [
                    FilterTestDiagnostic(kind: test.kind, code: .disabled)
                ])
        }

        let ruleless: [(test: FilterTestCase, value: FilterTestResultValue)] = [
            (
                .filename(FilenameFilterTestCase(rules: [], relativePath: "value")),
                .filename(decision: .include)
            ),
            (
                .display(
                    DisplayFilterTestCase(
                        filter: DisplayFilter(),
                        input: DisplayFilterTestInput(
                            leftText: "value",
                            rightText: nil,
                            kind: .modified
                        )
                    )),
                .display(isVisible: true)
            ),
            (
                .line(LineFilterTestCase(rules: [], input: "value")),
                .line(isFiltered: false)
            ),
            (
                .substitution(SubstitutionFilterTestCase(rules: [], input: "value")),
                .substitution(output: FilterTestOutput("value"), didMatch: false)
            )
        ]
        for (test, value) in ruleless {
            let result = try FilterTestEvaluator.evaluate(test)
            XCTAssertEqual(result.kind, test.kind)
            XCTAssertEqual(result.state, .noOp)
            XCTAssertEqual(result.outcome, .noOp)
            XCTAssertEqual(result.value, value)
            XCTAssertEqual(result.matchedRuleIndices, [])
            XCTAssertEqual(result.matchRanges, [])
            XCTAssertEqual(
                result.diagnostics,
                [
                    FilterTestDiagnostic(kind: test.kind, code: .noRules)
                ])
        }
    }

    func testEmptySubstitutionPatternsAreIgnoredWithoutRenumberingMatches() throws {
        let result = try FilterTestEvaluator.evaluate(
            .substitution(
                SubstitutionFilterTestCase(
                    rules: [
                        SubstitutionRule(pattern: "", replacement: "ignored"),
                        SubstitutionRule(pattern: "value", replacement: "changed")
                    ],
                    input: "value"
                )))

        XCTAssertEqual(try substitutionValue(result).output.bytes, Array("changed".utf8))
        XCTAssertEqual(result.matchedRuleIndices, [1])
        XCTAssertEqual(
            result.diagnostics,
            [
                FilterTestDiagnostic(kind: .substitution, code: .emptyPatternIgnored, ruleIndex: 0)
            ])
    }

    func testCompositionEvaluatesEveryCaseAndPreservesOutcomePrecedence() throws {
        let matched = FilterTestCondition.test(
            .line(
                LineFilterTestCase(
                    rule: LineFilterRule(pattern: "^match$"),
                    input: "match"
                )))
        let notMatched = FilterTestCondition.test(
            .line(
                LineFilterTestCase(
                    rule: LineFilterRule(pattern: "^other$"),
                    input: "match"
                )))
        let invalid = FilterTestCondition.test(
            .line(
                LineFilterTestCase(
                    rule: LineFilterRule(pattern: "["),
                    input: "match"
                )))

        let all = try FilterTestEvaluator.evaluate(.all([matched, notMatched]))
        let any = try FilterTestEvaluator.evaluate(.any([notMatched, matched]))
        let negated = try FilterTestEvaluator.evaluate(.not(matched))
        let invalidAny = try FilterTestEvaluator.evaluate(.any([matched, invalid]))

        XCTAssertEqual(all.outcome, .notMatched)
        XCTAssertEqual(any.outcome, .matched)
        XCTAssertEqual(negated.outcome, .notMatched)
        XCTAssertEqual(invalidAny.outcome, .invalid)
        XCTAssertEqual(all.results.count, 2)
        XCTAssertEqual(any.results.count, 2)
        XCTAssertEqual(invalidAny.results.count, 2)
    }

    func testNestedCompositionChargesEveryNodeAtExactWorkBoundary() throws {
        let condition = FilterTestCondition.not(
            .all([
                .any([
                    .test(.line(LineFilterTestCase(rules: [], input: "")))
                ])
            ]))
        let exactWork = 10

        let evaluation = try FilterTestEvaluator.evaluate(
            condition,
            limits: limits(maximumConditionDepth: 4, maximumWork: exactWork)
        )

        XCTAssertEqual(evaluation.outcome, .noOp)
        XCTAssertEqual(evaluation.results.count, 1)
        XCTAssertEqual(evaluation.work, exactWork)
        assertFilterError(.conditionDepthExceeded(maximum: 3)) {
            _ = try FilterTestEvaluator.evaluate(
                condition,
                limits: self.limits(maximumConditionDepth: 3)
            )
        }
        assertFilterError(.workLimitExceeded(maximumWork: exactWork - 1)) {
            _ = try FilterTestEvaluator.evaluate(
                condition,
                limits: self.limits(maximumConditionDepth: 4, maximumWork: exactWork - 1)
            )
        }
    }

    func testDefaultPublicLimitsExposeExactCaps() {
        let limits = FilterTestLimits.default

        XCTAssertEqual(
            [
                limits.maximumCaseCount,
                limits.maximumCollectionCount,
                limits.maximumConditionDepth,
                limits.maximumPatternUTF8Bytes,
                limits.maximumReplacementUTF8Bytes,
                limits.maximumTotalPatternUTF8Bytes,
                limits.maximumInputUTF8Bytes,
                limits.maximumTotalInputUTF8Bytes,
                limits.maximumOutputUTF8Bytes,
                limits.maximumWork,
                limits.maximumResults
            ],
            [
                1_024,
                1_024,
                64,
                64 * 1_024,
                1_024 * 1_024,
                4 * 1_024 * 1_024,
                16 * 1_024 * 1_024,
                64 * 1_024 * 1_024,
                64 * 1_024 * 1_024,
                256 * 1_024 * 1_024,
                100_000
            ])
    }

    func testEveryGlobalLimitAcceptsValueAtConfiguredCap() throws {
        let rulelessLine = FilterTestCase.line(LineFilterTestCase(rules: [], input: ""))
        let oneByteInput = FilterTestCase.line(LineFilterTestCase(rules: [], input: "a"))
        let oneBytePattern = FilterTestCase.line(
            LineFilterTestCase(
                enabled: false,
                rule: LineFilterRule(pattern: "a"),
                input: ""
            ))
        let oneByteSubstitution = FilterTestCase.substitution(
            SubstitutionFilterTestCase(
                enabled: false,
                rule: SubstitutionRule(pattern: "a", replacement: "b"),
                input: ""
            ))
        let oneByteOutput = FilterTestCase.substitution(
            SubstitutionFilterTestCase(rules: [], input: "a")
        )

        _ = try FilterTestEvaluator.evaluate(
            [rulelessLine],
            limits: limits(maximumCollectionCount: 1)
        )
        _ = try FilterTestEvaluator.evaluate(rulelessLine, limits: limits(maximumCaseCount: 1))
        _ = try FilterTestEvaluator.evaluate(
            .not(.test(rulelessLine)),
            limits: limits(maximumConditionDepth: 2)
        )
        _ = try FilterTestEvaluator.evaluate(
            oneBytePattern,
            limits: limits(maximumPatternUTF8Bytes: 1)
        )
        _ = try FilterTestEvaluator.evaluate(
            oneByteSubstitution,
            limits: limits(
                maximumReplacementUTF8Bytes: 1,
                maximumTotalPatternUTF8Bytes: 2
            )
        )
        _ = try FilterTestEvaluator.evaluate(
            oneByteInput,
            limits: limits(maximumInputUTF8Bytes: 1)
        )
        _ = try FilterTestEvaluator.evaluate(
            [oneByteInput, oneByteInput],
            limits: limits(maximumTotalInputUTF8Bytes: 2)
        )
        _ = try FilterTestEvaluator.evaluate(
            oneByteOutput,
            limits: limits(maximumOutputUTF8Bytes: 1)
        )
        _ = try FilterTestEvaluator.evaluate(
            .test(rulelessLine),
            limits: limits(maximumWork: 4)
        )
        _ = try FilterTestEvaluator.evaluate(
            rulelessLine,
            limits: limits(maximumResults: 2)
        )
    }

    func testEveryGlobalLimitRejectsFirstValueBeyondConfiguredCap() {
        let line = FilterTestCase.line(
            LineFilterTestCase(
                rule: LineFilterRule(pattern: "a"),
                input: "a"
            ))
        let substitution = FilterTestCase.substitution(
            SubstitutionFilterTestCase(
                rule: SubstitutionRule(pattern: "a", replacement: "b"),
                input: "a"
            ))

        assertFilterError(.collectionLimitExceeded(maximum: 0)) {
            _ = try FilterTestEvaluator.evaluate([line], limits: self.limits(maximumCollectionCount: 0))
        }
        assertFilterError(.caseLimitExceeded(maximum: 0)) {
            _ = try FilterTestEvaluator.evaluate(line, limits: self.limits(maximumCaseCount: 0))
        }
        assertFilterError(.conditionDepthExceeded(maximum: 1)) {
            _ = try FilterTestEvaluator.evaluate(.not(.test(line)), limits: self.limits(maximumConditionDepth: 1))
        }
        assertFilterError(.patternTooLarge(kind: .line, ruleIndex: 0, maximumUTF8Bytes: 0)) {
            _ = try FilterTestEvaluator.evaluate(line, limits: self.limits(maximumPatternUTF8Bytes: 0))
        }
        assertFilterError(.replacementTooLarge(ruleIndex: 0, maximumUTF8Bytes: 0)) {
            _ = try FilterTestEvaluator.evaluate(
                substitution,
                limits: self.limits(maximumReplacementUTF8Bytes: 0)
            )
        }
        assertFilterError(.totalPatternSizeExceeded(maximumUTF8Bytes: 1)) {
            _ = try FilterTestEvaluator.evaluate(
                substitution,
                limits: self.limits(maximumTotalPatternUTF8Bytes: 1)
            )
        }
        assertFilterError(.inputTooLarge(kind: .line, maximumUTF8Bytes: 0)) {
            _ = try FilterTestEvaluator.evaluate(line, limits: self.limits(maximumInputUTF8Bytes: 0))
        }
        assertFilterError(.totalInputSizeExceeded(maximumUTF8Bytes: 1)) {
            _ = try FilterTestEvaluator.evaluate(
                [line, line],
                limits: self.limits(maximumTotalInputUTF8Bytes: 1)
            )
        }
        assertFilterError(.outputTooLarge(maximumUTF8Bytes: 0)) {
            _ = try FilterTestEvaluator.evaluate(
                substitution,
                limits: self.limits(maximumOutputUTF8Bytes: 0)
            )
        }
        assertFilterError(.workLimitExceeded(maximumWork: 0)) {
            _ = try FilterTestEvaluator.evaluate(line, limits: self.limits(maximumWork: 0))
        }
        assertFilterError(.resultLimitExceeded(maximumResults: 1)) {
            _ = try FilterTestEvaluator.evaluate(line, limits: self.limits(maximumResults: 1))
        }
    }

    func testRetainedResultCountAcceptsExactThreeAndRejectsTwo() throws {
        let test = FilterTestCase.line(
            LineFilterTestCase(
                rule: LineFilterRule(pattern: "^value$"),
                input: "value"
            ))

        let exact = try FilterTestEvaluator.evaluate(
            .test(test),
            limits: limits(maximumResults: 3)
        )

        XCTAssertEqual(exact.results.count, 1)
        XCTAssertEqual(exact.results.first?.matchedRuleIndices, [0])
        XCTAssertEqual(exact.results.first?.matchRanges.count, 1)
        assertFilterError(.resultLimitExceeded(maximumResults: 2)) {
            _ = try FilterTestEvaluator.evaluate(
                .test(test),
                limits: self.limits(maximumResults: 2)
            )
        }
    }

    func testPreCancelledEvaluationThrowsCancellationBeforeLimitValidation() async {
        let input = "x"
        let test = FilterTestCase.substitution(
            SubstitutionFilterTestCase(
                rule: SubstitutionRule(pattern: "x", replacement: "y"),
                input: input
            ))
        let restrictiveLimits = limits(
            maximumInputUTF8Bytes: 0,
            maximumOutputUTF8Bytes: 0,
            maximumWork: 0
        )

        let outcome = await Task.detached { @Sendable [test, restrictiveLimits] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try FilterTestEvaluator.evaluate(test, limits: restrictiveLimits)
                return "succeeded"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return String(describing: error)
            }
        }.value

        XCTAssertEqual(outcome, "cancelled")
    }

    private func limits(
        maximumCaseCount: Int = FilterTestLimits.default.maximumCaseCount,
        maximumCollectionCount: Int = FilterTestLimits.default.maximumCollectionCount,
        maximumConditionDepth: Int = FilterTestLimits.default.maximumConditionDepth,
        maximumPatternUTF8Bytes: Int = FilterTestLimits.default.maximumPatternUTF8Bytes,
        maximumReplacementUTF8Bytes: Int = FilterTestLimits.default.maximumReplacementUTF8Bytes,
        maximumTotalPatternUTF8Bytes: Int = FilterTestLimits.default.maximumTotalPatternUTF8Bytes,
        maximumInputUTF8Bytes: Int = FilterTestLimits.default.maximumInputUTF8Bytes,
        maximumTotalInputUTF8Bytes: Int = FilterTestLimits.default.maximumTotalInputUTF8Bytes,
        maximumOutputUTF8Bytes: Int = FilterTestLimits.default.maximumOutputUTF8Bytes,
        maximumWork: Int = FilterTestLimits.default.maximumWork,
        maximumResults: Int = FilterTestLimits.default.maximumResults
    ) -> FilterTestLimits {
        FilterTestLimits(
            maximumCaseCount: maximumCaseCount,
            maximumCollectionCount: maximumCollectionCount,
            maximumConditionDepth: maximumConditionDepth,
            maximumPatternUTF8Bytes: maximumPatternUTF8Bytes,
            maximumReplacementUTF8Bytes: maximumReplacementUTF8Bytes,
            maximumTotalPatternUTF8Bytes: maximumTotalPatternUTF8Bytes,
            maximumInputUTF8Bytes: maximumInputUTF8Bytes,
            maximumTotalInputUTF8Bytes: maximumTotalInputUTF8Bytes,
            maximumOutputUTF8Bytes: maximumOutputUTF8Bytes,
            maximumWork: maximumWork,
            maximumResults: maximumResults
        )
    }

    private func assertFilterError(
        _ expected: FilterTestError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? FilterTestError, expected, file: file, line: line)
        }
    }

    private func substitutionValue(
        _ result: FilterTestCaseResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (output: FilterTestOutput, didMatch: Bool) {
        guard case .substitution(let output, let didMatch)? = result.value else {
            XCTFail("Expected substitution value", file: file, line: line)
            throw MissingSubstitutionValue()
        }
        return (output, didMatch)
    }

    private func legacySubstitute(
        subject: String,
        pattern: String,
        replacement: String
    ) -> (status: Int32, output: [UInt8], reportedSize: Int) {
        let subjectBytes = Array(subject.utf8)
        let patternBytes = Array(pattern.utf8)
        let replacementBytes = Array(replacement.utf8)
        var nativeResult = mmx_bytes_result(bytes: nil, size: 0)
        let status = subjectBytes.withUnsafeBytes { subjectBuffer in
            patternBytes.withUnsafeBytes { patternBuffer in
                replacementBytes.withUnsafeBytes { replacementBuffer in
                    mmx_regex_substitute(
                        subjectBuffer.baseAddress,
                        subjectBuffer.count,
                        patternBuffer.baseAddress,
                        patternBuffer.count,
                        replacementBuffer.baseAddress,
                        replacementBuffer.count,
                        1,
                        1_024,
                        &nativeResult
                    )
                }
            }
        }
        let reportedSize = nativeResult.size
        let output =
            status == 0
            ? Array(UnsafeBufferPointer(start: nativeResult.bytes, count: reportedSize))
            : []
        mmx_bytes_result_free(&nativeResult)
        return (status, output, reportedSize)
    }

    private func frozenLegacyCSubstitute() throws -> (status: Int32, output: [UInt8], reportedSize: Int) {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appending(
            path: "MacMergeFrozenLegacyRegexCaller-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "frozen_legacy_regex_caller.c")
        let libraryURL = directory.appending(path: "frozen_legacy_regex_caller.dylib")
        try Self.frozenLegacyRegexCSource.write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = Process()
        compiler.executableURL = URL(filePath: "/usr/bin/clang")
        compiler.arguments = [
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-dynamiclib",
            "-undefined",
            "dynamic_lookup",
            sourceURL.path,
            "-o",
            libraryURL.path
        ]
        let diagnostics = Pipe()
        compiler.standardOutput = diagnostics
        compiler.standardError = diagnostics
        try compiler.run()
        compiler.waitUntilExit()
        let compilerOutput = String(
            decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        XCTAssertEqual(compiler.terminationReason, .exit, compilerOutput)
        XCTAssertEqual(compiler.terminationStatus, 0, compilerOutput)
        guard compiler.terminationReason == .exit, compiler.terminationStatus == 0 else {
            throw FrozenLegacyCFixtureError.compilationFailed
        }

        guard let library = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            throw FrozenLegacyCFixtureError.loadingFailed(Self.dynamicLoaderError())
        }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "mmx_frozen_legacy_substitute") else {
            throw FrozenLegacyCFixtureError.symbolMissing(Self.dynamicLoaderError())
        }
        typealias FrozenLegacySubstitute =
            @convention(c) (
                UnsafeMutablePointer<Int>,
                UnsafeMutablePointer<UInt8>,
                Int
            ) -> Int32
        let call = unsafeBitCast(symbol, to: FrozenLegacySubstitute.self)
        var reportedSize = 0
        var output = [UInt8](repeating: 0, count: 8)
        let status = output.withUnsafeMutableBufferPointer { buffer in
            call(&reportedSize, buffer.baseAddress!, buffer.count)
        }
        let outputCount = status == 0 && reportedSize >= 0 ? min(reportedSize, output.count) : 0
        return (status, Array(output.prefix(outputCount)), reportedSize)
    }

    private static func dynamicLoaderError() -> String {
        guard let error = dlerror() else { return "unknown dynamic-loader error" }
        return String(cString: error)
    }

    private static let frozenLegacyRegexCSource = #"""
        #include <stddef.h>
        #include <stdint.h>
        #include <string.h>

        typedef struct frozen_mmx_bytes_result {
            uint8_t *bytes;
            size_t size;
        } frozen_mmx_bytes_result;

        extern int32_t mmx_regex_substitute(
            const void *subject,
            size_t subject_size,
            const void *pattern,
            size_t pattern_size,
            const void *replacement,
            size_t replacement_size,
            int32_t case_sensitive,
            size_t maximum_size,
            frozen_mmx_bytes_result *result
        );
        extern void mmx_bytes_result_free(frozen_mmx_bytes_result *result);

        int32_t mmx_frozen_legacy_substitute(
            size_t *reported_size,
            uint8_t *output,
            size_t output_capacity
        ) {
            static const uint8_t subject[] = {'a'};
            static const uint8_t pattern[] = {'a'};
            static const uint8_t replacement[] = {'e', 'x', 'p', 'a', 'n', 'd', 'e', 'd'};
            frozen_mmx_bytes_result result = {NULL, 0};
            int32_t status = mmx_regex_substitute(
                subject,
                sizeof(subject),
                pattern,
                sizeof(pattern),
                replacement,
                sizeof(replacement),
                1,
                output_capacity,
                &result
            );
            if (status != 0) return status;
            *reported_size = result.size;
            if (result.size > output_capacity) {
                mmx_bytes_result_free(&result);
                return -1;
            }
            memcpy(output, result.bytes, result.size);
            mmx_bytes_result_free(&result);
            return 0;
        }
        """#

    private func diagnosticCode(for diagnostic: FilenameFilterDiagnostic) -> FilterTestDiagnosticCode {
        switch diagnostic.reason {
        case .ruleCountExceeded:
            .collectionLimitExceeded
        case .emptyPattern, .invalidGlob, .invalidRegularExpression:
            .invalidPattern
        case .patternContainsNull:
            .patternContainsNull
        case .patternTooLarge:
            .patternLimitExceeded
        case .totalPatternSizeExceeded:
            .totalPatternLimitExceeded
        case .unsupportedRegularExpression:
            .unsupportedPattern
        case .compiledStateCountExceeded:
            .compiledPatternLimitExceeded
        }
    }
}

private struct MissingSubstitutionValue: Error {}

private enum FrozenLegacyCFixtureError: Error {
    case compilationFailed
    case loadingFailed(String)
    case symbolMissing(String)
}
