import Foundation
import XCTest

@testable import MacMergeCore

final class RecompareModePlanTests: XCTestCase {
    func testCapabilitiesAndPlannerCoverEveryModeSourceKindAndCount() {
        XCTAssertEqual(
            RecompareMode.allCases,
            [.text, .table, .binary, .image, .webpage, .archive]
        )

        let expected: [RecompareMode: (counts: Set<Int>, kinds: Set<RecompareModeSourceKind>)] = [
            .text: ([2, 3], [.localFile, .scratchpad, .clipboardText]),
            .table: ([2, 3], [.localFile, .scratchpad]),
            .binary: ([2, 3], [.localFile, .clipboardBinary]),
            .image: ([2, 3], [.localFile]),
            .webpage: ([2, 3], [.localFile, .scratchpad, .remoteWebPage]),
            .archive: ([2], [.localFile])
        ]

        for mode in RecompareMode.allCases {
            let capability = RecompareModePlanner.capability(for: mode)
            let expectation = expected[mode]
            XCTAssertEqual(capability.mode, mode)
            XCTAssertEqual(capability.supportedSourceCounts, expectation?.counts, mode.rawValue)
            XCTAssertEqual(capability.supportedSourceKinds, expectation?.kinds, mode.rawValue)

            for count in 1...4 {
                for kind in RecompareModeSourceKind.allCases {
                    let clipboard = isClipboard(kind)
                    let supported =
                        expectation?.counts.contains(count) == true
                        && expectation?.kinds.contains(kind) == true
                        && (!clipboard || count == 2)
                    let context = "\(mode.rawValue), \(count), \(kind.rawValue)"
                    XCTAssertEqual(
                        capability.supports(sourceCount: count, kind: kind),
                        supported,
                        context
                    )

                    guard count == 2 || count == 3 else { continue }
                    let kinds = Dictionary(
                        uniqueKeysWithValues: sides(sourceCount: count).map { ($0, kind) }
                    )
                    let candidate = request(
                        sources: snapshot(sourceCount: count, kinds: kinds),
                        currentMode: mode,
                        targetMode: mode
                    )
                    if supported {
                        XCTAssertNoThrow(try RecompareModePlanner.plan(candidate), context)
                    } else if expectation?.counts.contains(count) != true {
                        assertPlanningError(.unsupportedSourceCount(mode: mode, count: count)) {
                            _ = try RecompareModePlanner.plan(candidate)
                        }
                    } else if clipboard && count == 3 {
                        assertPlanningError(.clipboardSourcesRequireMatchingPair) {
                            _ = try RecompareModePlanner.plan(candidate)
                        }
                    } else {
                        assertPlanningError(
                            .unsupportedSourceKind(side: .left, mode: mode, kind: kind)
                        ) {
                            _ = try RecompareModePlanner.plan(candidate)
                        }
                    }
                }
            }
        }
    }

    func testEveryInvalidClipboardCombinationRequiresAnExactTwoSourceMatchingPair() {
        let kinds = RecompareModeSourceKind.allCases
        for leftKind in kinds {
            for rightKind in kinds {
                let containsClipboard = isClipboard(leftKind) || isClipboard(rightKind)
                let isMatchingClipboardPair = leftKind == rightKind && isClipboard(leftKind)
                guard containsClipboard, !isMatchingClipboardPair else { continue }

                let sources = snapshot(
                    sourceCount: 2,
                    kinds: [.left: leftKind, .right: rightKind]
                )
                assertPlanningError(.clipboardSourcesRequireMatchingPair) {
                    _ = try RecompareModePlanner.plan(
                        request(sources: sources, currentMode: .text, targetMode: .text)
                    )
                }
            }
        }

        for leftKind in kinds {
            for middleKind in kinds {
                for rightKind in kinds {
                    guard
                        isClipboard(leftKind) || isClipboard(middleKind)
                            || isClipboard(rightKind)
                    else { continue }

                    let sources = snapshot(
                        sourceCount: 3,
                        kinds: [
                            .left: leftKind,
                            .middle: middleKind,
                            .right: rightKind
                        ]
                    )
                    assertPlanningError(.clipboardSourcesRequireMatchingPair) {
                        _ = try RecompareModePlanner.plan(
                            request(sources: sources, currentMode: .text, targetMode: .text)
                        )
                    }
                }
            }
        }
    }

    func testEveryTargetModePlansEverySupportedSourceCount() throws {
        for targetMode in RecompareMode.allCases {
            let capability = RecompareModePlanner.capability(for: targetMode)
            for sourceCount in capability.supportedSourceCounts.sorted() {
                let sources = snapshot(sourceCount: sourceCount)
                let expectedOptions = options(for: targetMode)
                let request = RecompareModeRequest(
                    sources: sources,
                    currentMode: targetMode,
                    targetMode: targetMode,
                    options: expectedOptions,
                    declaredWorkUnits: 17
                )

                let plan = try RecompareModePlanner.plan(request, expecting: sources.reference)

                XCTAssertEqual(plan.currentMode, targetMode)
                XCTAssertEqual(plan.targetMode, targetMode)
                XCTAssertEqual(plan.options, expectedOptions)
                XCTAssertEqual(plan.sources.count, sourceCount)
                XCTAssertEqual(plan.isThreeWay, sourceCount == 3)
                XCTAssertGreaterThan(plan.planningWorkUnits, 0)
            }
        }

        assertPlanningError(.unsupportedSourceCount(mode: .archive, count: 3)) {
            _ = try RecompareModePlanner.plan(
                request(sourceCount: 3, currentMode: .archive, targetMode: .archive)
            )
        }
    }

    func testCurrentModeCapabilitiesAreValidatedIndependentlyOfTargetMode() {
        assertPlanningError(.unsupportedSourceCount(mode: .archive, count: 3)) {
            _ = try RecompareModePlanner.plan(
                request(sourceCount: 3, currentMode: .archive, targetMode: .text)
            )
        }

        let scratchpads = snapshot(
            sourceCount: 2,
            kinds: [.left: .scratchpad, .right: .scratchpad]
        )
        assertPlanningError(
            .unsupportedSourceKind(side: .left, mode: .image, kind: .scratchpad)
        ) {
            _ = try RecompareModePlanner.plan(
                RecompareModeRequest(
                    sources: scratchpads,
                    currentMode: .image,
                    targetMode: .webpage,
                    options: options(for: .webpage),
                    declaredWorkUnits: 1
                )
            )
        }
    }

    func testTargetModeCapabilitiesAreValidatedIndependentlyOfCurrentMode() {
        assertPlanningError(.unsupportedSourceCount(mode: .archive, count: 3)) {
            _ = try RecompareModePlanner.plan(
                request(sourceCount: 3, currentMode: .text, targetMode: .archive)
            )
        }

        let scratchpads = snapshot(
            sourceCount: 2,
            kinds: [.left: .scratchpad, .right: .scratchpad]
        )
        assertPlanningError(
            .unsupportedSourceKind(side: .left, mode: .image, kind: .scratchpad)
        ) {
            _ = try RecompareModePlanner.plan(
                RecompareModeRequest(
                    sources: scratchpads,
                    currentMode: .text,
                    targetMode: .image,
                    options: options(for: .image),
                    declaredWorkUnits: 1
                )
            )
        }
    }

    func testEveryTargetModeRequiresItsModeSpecificOptions() {
        let modes = RecompareMode.allCases
        for (index, targetMode) in modes.enumerated() {
            let actualMode = modes[(index + 1) % modes.count]
            assertPlanningError(
                .modeOptionsMismatch(expected: targetMode, actual: actualMode)
            ) {
                _ = try RecompareModePlanner.plan(
                    RecompareModeRequest(
                        sources: snapshot(sourceCount: 2),
                        currentMode: targetMode,
                        targetMode: targetMode,
                        options: options(for: actualMode),
                        declaredWorkUnits: 1
                    )
                )
            }
        }
    }

    func testPlanAndReceiptPreserveExactSourcesOptionsLimitsAndWorkDeterministically() throws {
        let filter = LineFilterRule(pattern: "^ignore$", caseSensitive: false)
        let substitution = SubstitutionRule(
            pattern: "v[0-9]+",
            replacement: "version",
            caseSensitive: true
        )
        let twoWay = LineDiffOptions(
            algorithm: .histogram,
            lineFiltersEnabled: true,
            lineFilters: [filter],
            substitutionsEnabled: true,
            substitutions: [substitution]
        )
        let expectedOptions = RecompareModeOptions.text(
            twoWay: twoWay,
            threeWay: ThreeWayTextMergeOptions(diffAlgorithm: .minimal)
        )
        let expectedWork =
            3
            + filter.pattern.utf8.count
            + substitution.pattern.utf8.count
            + substitution.replacement.utf8.count
        let limits = RecompareModePlanLimits(
            maximumOptionItemCount: 2,
            maximumOptionStringUTF8Bytes: 32,
            maximumTotalOptionStringUTF8Bytes: 64,
            maximumDeclaredWorkUnits: 100,
            maximumPlanningWorkUnits: expectedWork,
            cancellationCheckInterval: 1
        )
        let sources = snapshot(sourceCount: 3)
        let request = RecompareModeRequest(
            sources: sources,
            currentMode: .binary,
            targetMode: .text,
            options: expectedOptions,
            declaredWorkUnits: 73,
            limits: limits
        )

        let first = try RecompareModePlanner.plan(request, expecting: sources.reference)
        let second = try RecompareModePlanner.plan(request, expecting: sources.reference)
        let expectedSources = [
            source(.left),
            source(.middle),
            source(.right)
        ]

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(Set([first, second]).count, 1)
        XCTAssertEqual(first.sourceReference.identity, Self.sourceSetIdentity)
        XCTAssertEqual(first.sourceReference.generation, Self.generation)
        XCTAssertEqual(first.sources, expectedSources)
        XCTAssertEqual(first.source(.left)?.identity, Self.leftIdentity)
        XCTAssertEqual(first.source(.left)?.revision, RecompareModeSourceRevision(rawValue: 11))
        XCTAssertEqual(first.source(.middle)?.identity, Self.middleIdentity)
        XCTAssertEqual(first.source(.middle)?.revision, RecompareModeSourceRevision(rawValue: 22))
        XCTAssertEqual(first.source(.right)?.identity, Self.rightIdentity)
        XCTAssertEqual(first.source(.right)?.revision, RecompareModeSourceRevision(rawValue: 33))
        XCTAssertEqual(first.currentMode, .binary)
        XCTAssertEqual(first.targetMode, .text)
        XCTAssertEqual(first.options, expectedOptions)
        XCTAssertEqual(first.declaredWorkUnits, 73)
        XCTAssertEqual(first.planningWorkUnits, expectedWork)
        XCTAssertEqual(first.limits, limits)
        XCTAssertTrue(first.isThreeWay)
        XCTAssertEqual(first.receipt.sourceReference, first.sourceReference)
        XCTAssertEqual(first.receipt.sources, first.sources)
        XCTAssertEqual(first.receipt.currentMode, first.currentMode)
        XCTAssertEqual(first.receipt.targetMode, first.targetMode)
        XCTAssertEqual(first.receipt.options, first.options)
        XCTAssertEqual(first.receipt.declaredWorkUnits, first.declaredWorkUnits)
        XCTAssertEqual(first.receipt.planningWorkUnits, first.planningWorkUnits)
        XCTAssertEqual(first.receipt.limits, first.limits)
    }

    func testReceiptValidatesExactIdentityRevisionKindCountAndGeneration() throws {
        let original = snapshot(sourceCount: 3)
        let plan = try RecompareModePlanner.plan(
            request(sources: original, currentMode: .text, targetMode: .text)
        )

        try plan.requireCurrentSources(original)
        try plan.receipt.requireCurrentSources(original)
        XCTAssertTrue(try plan.isCurrent(for: original))
        XCTAssertTrue(try plan.receipt.isCurrent(for: original))

        let otherSetIdentity = RecompareModeSourceSetIdentity(
            rawValue: uuid("00000000-0000-0000-0000-000000000099")
        )
        let otherSet = RecompareModeSourceSnapshot(
            identity: otherSetIdentity,
            generation: original.generation,
            sources: original.sources
        )
        assertNotCurrent(
            otherSet,
            plan: plan,
            error: .sourceSetIdentityChanged(
                expected: Self.sourceSetIdentity,
                actual: otherSetIdentity
            )
        )

        let stale = RecompareModeSourceSnapshot(
            identity: original.identity,
            generation: original.generation + 1,
            sources: original.sources
        )
        assertNotCurrent(
            stale,
            plan: plan,
            error: .staleSourceGeneration(expected: Self.generation, actual: Self.generation + 1)
        )

        let twoSources = snapshot(sourceCount: 2)
        assertNotCurrent(
            twoSources,
            plan: plan,
            error: .sourceCountChanged(expected: 3, actual: 2)
        )

        let changedIdentity = RecompareModeSourceIdentity(
            rawValue: uuid("00000000-0000-0000-0000-000000000098")
        )
        let identityChanged = replacingSource(in: original, side: .left) {
            RecompareModeSourceBinding(
                side: $0.side,
                identity: changedIdentity,
                revision: $0.revision,
                kind: $0.kind
            )
        }
        assertNotCurrent(
            identityChanged,
            plan: plan,
            error: .sourceIdentityChanged(
                side: .left,
                expected: Self.leftIdentity,
                actual: changedIdentity
            )
        )

        let changedRevision = RecompareModeSourceRevision(rawValue: 12)
        let revisionChanged = replacingSource(in: original, side: .left) {
            RecompareModeSourceBinding(
                side: $0.side,
                identity: $0.identity,
                revision: changedRevision,
                kind: $0.kind
            )
        }
        assertNotCurrent(
            revisionChanged,
            plan: plan,
            error: .sourceRevisionChanged(
                side: .left,
                expected: RecompareModeSourceRevision(rawValue: 11),
                actual: changedRevision
            )
        )

        let kindChanged = replacingSource(in: original, side: .left) {
            RecompareModeSourceBinding(
                side: $0.side,
                identity: $0.identity,
                revision: $0.revision,
                kind: .scratchpad
            )
        }
        assertNotCurrent(
            kindChanged,
            plan: plan,
            error: .sourceKindChanged(
                side: .left,
                expected: .localFile,
                actual: .scratchpad
            )
        )
    }

    func testThreeWayTextAndWebPageIgnoreIrrelevantTwoWayRegularExpressions() throws {
        let invalidRegex = LineDiffOptions(
            lineFiltersEnabled: true,
            lineFilters: [LineFilterRule(pattern: "(")]
        )
        let textOptions = RecompareModeOptions.text(
            twoWay: invalidRegex,
            threeWay: ThreeWayTextMergeOptions()
        )

        _ = try RecompareModePlanner.plan(
            request(sourceCount: 3, currentMode: .text, targetMode: .text, options: textOptions)
        )
        assertPlanningError(
            .invalidOption(mode: .text, name: "text.twoWay.lineFilters[0].pattern")
        ) {
            _ = try RecompareModePlanner.plan(
                request(sourceCount: 2, currentMode: .text, targetMode: .text, options: textOptions)
            )
        }

        let webOptions = RecompareModeOptions.webpage(
            twoWay: WebPageComparisonOptions(lineDiffOptions: invalidRegex),
            threeWay: ThreeWayWebPageComparisonOptions()
        )
        _ = try RecompareModePlanner.plan(
            request(
                sourceCount: 3,
                currentMode: .webpage,
                targetMode: .webpage,
                options: webOptions
            )
        )
        assertPlanningError(
            .invalidOption(
                mode: .webpage,
                name: "webpage.twoWay.lineDiffOptions.lineFilters[0].pattern"
            )
        ) {
            _ = try RecompareModePlanner.plan(
                request(
                    sourceCount: 2,
                    currentMode: .webpage,
                    targetMode: .webpage,
                    options: webOptions
                )
            )
        }
    }

    func testTableItemAccountingIncludesBothParsingOptionFamilies() throws {
        let exactLimits = RecompareModePlanLimits(maximumOptionItemCount: 4)
        let exact = try RecompareModePlanner.plan(
            request(
                sourceCount: 2,
                currentMode: .table,
                targetMode: .table,
                limits: exactLimits
            )
        )
        XCTAssertEqual(exact.planningWorkUnits, 6)

        let insufficientLimits = RecompareModePlanLimits(maximumOptionItemCount: 3)
        assertPlanningError(.tooManyOptionItems(maximum: 3)) {
            _ = try RecompareModePlanner.plan(
                request(
                    sourceCount: 2,
                    currentMode: .table,
                    targetMode: .table,
                    limits: insufficientLimits
                )
            )
        }
    }

    func testOptionStringLimitsCountExactUTF8BytesPerStringAndInTotal() throws {
        let fourByteString = "éé"
        XCTAssertEqual(fourByteString.utf8.count, 4)

        let exactPerString = RecompareModeOptions.text(
            twoWay: LineDiffOptions(
                lineFiltersEnabled: false,
                lineFilters: [LineFilterRule(pattern: fourByteString)]
            ),
            threeWay: ThreeWayTextMergeOptions()
        )
        _ = try RecompareModePlanner.plan(
            request(
                sourceCount: 2,
                currentMode: .text,
                targetMode: .text,
                options: exactPerString,
                limits: RecompareModePlanLimits(
                    maximumOptionStringUTF8Bytes: 4,
                    maximumTotalOptionStringUTF8Bytes: 4
                )
            )
        )

        let overPerString = RecompareModeOptions.text(
            twoWay: LineDiffOptions(
                lineFiltersEnabled: false,
                lineFilters: [LineFilterRule(pattern: fourByteString + "a")]
            ),
            threeWay: ThreeWayTextMergeOptions()
        )
        assertPlanningError(
            .optionStringTooLarge(
                name: "text.twoWay.lineFilters[0].pattern",
                maximumUTF8Bytes: 4
            )
        ) {
            _ = try RecompareModePlanner.plan(
                request(
                    sourceCount: 2,
                    currentMode: .text,
                    targetMode: .text,
                    options: overPerString,
                    limits: RecompareModePlanLimits(
                        maximumOptionStringUTF8Bytes: 4,
                        maximumTotalOptionStringUTF8Bytes: 8
                    )
                )
            )
        }

        let twoFourByteStrings = RecompareModeOptions.text(
            twoWay: LineDiffOptions(
                substitutionsEnabled: false,
                substitutions: [
                    SubstitutionRule(pattern: fourByteString, replacement: fourByteString)
                ]
            ),
            threeWay: ThreeWayTextMergeOptions()
        )
        _ = try RecompareModePlanner.plan(
            request(
                sourceCount: 2,
                currentMode: .text,
                targetMode: .text,
                options: twoFourByteStrings,
                limits: RecompareModePlanLimits(
                    maximumOptionStringUTF8Bytes: 4,
                    maximumTotalOptionStringUTF8Bytes: 8
                )
            )
        )
        assertPlanningError(.totalOptionStringsTooLarge(maximumUTF8Bytes: 7)) {
            _ = try RecompareModePlanner.plan(
                request(
                    sourceCount: 2,
                    currentMode: .text,
                    targetMode: .text,
                    options: twoFourByteStrings,
                    limits: RecompareModePlanLimits(
                        maximumOptionStringUTF8Bytes: 4,
                        maximumTotalOptionStringUTF8Bytes: 7
                    )
                )
            )
        }
    }

    func testTextEngineCeilingsAcceptExactValuesAndRejectOneOver() {
        let cases = [
            engineCeiling(
                mode: .text,
                sourceCount: 2,
                name: "text.twoWay.lineFilters[0].pattern",
                maximum: 4_096
            ) {
                .text(
                    twoWay: LineDiffOptions(
                        lineFilters: [LineFilterRule(pattern: String(repeating: "a", count: $0))]
                    ),
                    threeWay: ThreeWayTextMergeOptions()
                )
            },
            engineCeiling(mode: .text, sourceCount: 3, name: "text.threeWay.maximumInputBytes", maximum: 64 * 1_024 * 1_024) {
                .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions(maximumInputBytes: $0))
            },
            engineCeiling(mode: .text, sourceCount: 3, name: "text.threeWay.maximumInputLines", maximum: 1_024 * 1_024) {
                .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions(maximumInputLines: $0))
            },
            engineCeiling(mode: .text, sourceCount: 3, name: "text.threeWay.maximumOutputBytes", maximum: 192 * 1_024 * 1_024) {
                .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions(maximumOutputBytes: $0))
            },
            engineCeiling(mode: .text, sourceCount: 3, name: "text.threeWay.maximumOutputLines", maximum: 3 * 1_024 * 1_024) {
                .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions(maximumOutputLines: $0))
            },
            engineCeiling(mode: .text, sourceCount: 3, name: "text.threeWay.maximumRegions", maximum: 3 * 1_024 * 1_024 + 1) {
                .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions(maximumRegions: $0))
            }
        ]

        assertEngineCeilings(cases)
    }

    func testTableEngineCeilingsAcceptExactValuesAndRejectOneOver() {
        let parsingCases = tableParsingEngineCeilings(
            prefix: "table.parsing",
            makeOptions: {
                .table(parsing: $0, twoWay: .default, threeWay: .default)
            }
        )
        let threeWayParsingCases = tableParsingEngineCeilings(
            prefix: "table.threeWay.parsingOptions",
            makeOptions: {
                .table(
                    parsing: .commaSeparated,
                    twoWay: .default,
                    threeWay: ThreeWayTableComparisonOptions(parsingOptions: $0)
                )
            }
        )
        let twoWayCases = tableComparisonEngineCeilings(
            prefix: "table.twoWay",
            makeOptions: {
                .table(parsing: .commaSeparated, twoWay: $0, threeWay: .default)
            }
        )
        let threeWayComparisonCases = tableComparisonEngineCeilings(
            prefix: "table.threeWay.comparisonOptions",
            makeOptions: {
                .table(
                    parsing: .commaSeparated,
                    twoWay: .default,
                    threeWay: ThreeWayTableComparisonOptions(comparisonOptions: $0)
                )
            }
        )
        let threeWayResultCases = [
            engineCeiling(mode: .table, sourceCount: 3, name: "table.threeWay.maximumComparedValueBytes", maximum: 192 * 1_024 * 1_024) {
                .table(
                    parsing: .commaSeparated,
                    twoWay: .default,
                    threeWay: ThreeWayTableComparisonOptions(maximumComparedValueBytes: $0)
                )
            },
            engineCeiling(mode: .table, sourceCount: 3, name: "table.threeWay.maximumResultRows", maximum: 3 * 1_048_576) {
                .table(
                    parsing: .commaSeparated,
                    twoWay: .default,
                    threeWay: ThreeWayTableComparisonOptions(maximumResultRows: $0)
                )
            },
            engineCeiling(mode: .table, sourceCount: 3, name: "table.threeWay.maximumResultCells", maximum: 3 * 1_048_576) {
                .table(
                    parsing: .commaSeparated,
                    twoWay: .default,
                    threeWay: ThreeWayTableComparisonOptions(maximumResultCells: $0)
                )
            }
        ]

        assertEngineCeilings(
            parsingCases + threeWayParsingCases + twoWayCases
                + threeWayComparisonCases + threeWayResultCases
        )
    }

    func testBinaryEngineCeilingsAcceptExactValuesAndRejectOneOver() {
        let cases = [
            engineCeiling(mode: .binary, sourceCount: 2, name: "binary.twoWay.maximumExactEditDistance", maximum: 2_048) {
                .binary(twoWay: BinaryComparisonOptions(maximumExactEditDistance: $0), threeWay: .default)
            },
            engineCeiling(mode: .binary, sourceCount: 2, name: "binary.twoWay.maximumAlignmentWork", maximum: 16 * 1_024 * 1_024) {
                .binary(twoWay: BinaryComparisonOptions(maximumAlignmentWork: $0), threeWay: .default)
            },
            engineCeiling(mode: .binary, sourceCount: 3, name: "binary.threeWay.maximumInputBytes", maximum: 64 * 1_024 * 1_024) {
                .binary(twoWay: BinaryComparisonOptions(), threeWay: ThreeWayBinaryComparisonOptions(maximumInputBytes: $0))
            },
            engineCeiling(mode: .binary, sourceCount: 3, name: "binary.threeWay.maximumExactEditDistance", maximum: 2_048) {
                .binary(twoWay: BinaryComparisonOptions(), threeWay: ThreeWayBinaryComparisonOptions(maximumExactEditDistance: $0))
            },
            engineCeiling(mode: .binary, sourceCount: 3, name: "binary.threeWay.maximumAlignmentWork", maximum: 32 * 1_024 * 1_024) {
                .binary(twoWay: BinaryComparisonOptions(), threeWay: ThreeWayBinaryComparisonOptions(maximumAlignmentWork: $0))
            },
            engineCeiling(mode: .binary, sourceCount: 3, name: "binary.threeWay.maximumRegions", maximum: 16 * 1_024 * 1_024) {
                .binary(twoWay: BinaryComparisonOptions(), threeWay: ThreeWayBinaryComparisonOptions(maximumRegions: $0))
            },
            engineCeiling(mode: .binary, sourceCount: 3, name: "binary.threeWay.maximumOutputBytes", maximum: 192 * 1_024 * 1_024) {
                .binary(twoWay: BinaryComparisonOptions(), threeWay: ThreeWayBinaryComparisonOptions(maximumOutputBytes: $0))
            }
        ]

        assertEngineCeilings(cases)
    }

    func testImageEngineCeilingsAcceptExactValuesAndRejectOneOver() {
        let cases = [
            imageLoadingEngineCeiling(name: "maximumEncodedBytes", maximum: 64 * 1_024 * 1_024) {
                ImageComparisonLimits(
                    maximumEncodedBytes: $0,
                    maximumDimension: 16_384,
                    maximumPixelCount: 16 * 1_024 * 1_024,
                    maximumDecodedBytes: 128 * 1_024 * 1_024
                )
            },
            imageLoadingEngineCeiling(name: "maximumDimension", maximum: 16_384) {
                ImageComparisonLimits(
                    maximumEncodedBytes: 64 * 1_024 * 1_024,
                    maximumDimension: $0,
                    maximumPixelCount: 16 * 1_024 * 1_024,
                    maximumDecodedBytes: 128 * 1_024 * 1_024
                )
            },
            imageLoadingEngineCeiling(name: "maximumPixelCount", maximum: 16 * 1_024 * 1_024) {
                ImageComparisonLimits(
                    maximumEncodedBytes: 64 * 1_024 * 1_024,
                    maximumDimension: 16_384,
                    maximumPixelCount: $0,
                    maximumDecodedBytes: 128 * 1_024 * 1_024
                )
            },
            imageLoadingEngineCeiling(name: "maximumDecodedBytes", maximum: 128 * 1_024 * 1_024) {
                ImageComparisonLimits(
                    maximumEncodedBytes: 64 * 1_024 * 1_024,
                    maximumDimension: 16_384,
                    maximumPixelCount: 16 * 1_024 * 1_024,
                    maximumDecodedBytes: $0
                )
            },
            engineCeiling(mode: .image, sourceCount: 2, name: "image.comparison.maximumCanvasPixels", maximum: 16 * 1_024 * 1_024) {
                .image(loading: .default, comparison: ImageComparisonOptions(maximumCanvasPixels: $0))
            },
            engineCeiling(mode: .image, sourceCount: 2, name: "image.comparison.maximumRegions", maximum: 250_000) {
                .image(loading: .default, comparison: ImageComparisonOptions(maximumRegions: $0))
            },
            engineCeiling(mode: .image, sourceCount: 2, name: "image.comparison.maximumQueuedPixels", maximum: 262_144) {
                .image(loading: .default, comparison: ImageComparisonOptions(maximumQueuedPixels: $0))
            }
        ]

        assertEngineCeilings(cases)
    }

    func testWebPageEngineCeilingsAcceptExactValuesAndRejectOneOver() {
        let cases = twoWayWebPageEngineCeilings() + threeWayWebPageEngineCeilings()

        assertEngineCeilings(cases)
    }

    func testArchiveEngineCeilingsAcceptExactValuesAndRejectOneOver() {
        let defaults = ArchiveLimits.default
        let cases = [
            archiveEngineCeiling(label: "maximumArchiveBytes", maximum: Int(defaults.maximumArchiveBytes)) {
                ArchiveLimits(maximumArchiveBytes: UInt64($0))
            },
            archiveEngineCeiling(label: "maximumEntryCount", maximum: defaults.maximumEntryCount) {
                ArchiveLimits(maximumEntryCount: $0)
            },
            archiveEngineCeiling(label: "maximumEntryUncompressedBytes", maximum: Int(defaults.maximumEntryUncompressedBytes)) {
                ArchiveLimits(maximumEntryUncompressedBytes: UInt64($0))
            },
            archiveEngineCeiling(label: "maximumTotalUncompressedBytes", maximum: Int(defaults.maximumTotalUncompressedBytes)) {
                ArchiveLimits(maximumTotalUncompressedBytes: UInt64($0))
            },
            archiveEngineCeiling(label: "maximumCompressionRatio", maximum: Int(defaults.maximumCompressionRatio)) {
                ArchiveLimits(maximumCompressionRatio: UInt64($0))
            },
            archiveEngineCeiling(label: "maximumPathDepth", maximum: defaults.maximumPathDepth) {
                ArchiveLimits(maximumPathDepth: $0)
            },
            archiveEngineCeiling(label: "maximumTotalPathComponents", maximum: defaults.maximumTotalPathComponents) {
                ArchiveLimits(maximumTotalPathComponents: $0)
            }
        ]

        assertEngineCeilings(cases)
    }

    func testSourceCountDeclaredWorkAndPlanningWorkLimitsHaveDistinctErrors() {
        assertPlanningError(.sourceCountLimitExceeded(maximum: 2)) {
            _ = try RecompareModePlanner.plan(
                request(
                    sourceCount: 3,
                    currentMode: .text,
                    targetMode: .text,
                    limits: RecompareModePlanLimits(maximumSourceCount: 2)
                )
            )
        }

        assertPlanningError(.declaredWorkLimitExceeded(maximumWorkUnits: 4)) {
            _ = try RecompareModePlanner.plan(
                request(
                    sourceCount: 2,
                    currentMode: .text,
                    targetMode: .text,
                    declaredWorkUnits: 5,
                    limits: RecompareModePlanLimits(maximumDeclaredWorkUnits: 4)
                )
            )
        }

        assertPlanningError(.planningWorkLimitExceeded(maximumWorkUnits: 1)) {
            _ = try RecompareModePlanner.plan(
                request(
                    sourceCount: 2,
                    currentMode: .text,
                    targetMode: .text,
                    limits: RecompareModePlanLimits(maximumPlanningWorkUnits: 1)
                )
            )
        }
    }

    func testEveryConfiguredPlanLimitAcceptsItsLowerBoundaryAndRejectsOutsideBounds() throws {
        XCTAssertEqual(
            RecompareModePlanLimit.allCases,
            [
                .sourceCount,
                .optionItemCount,
                .optionStringUTF8Bytes,
                .totalOptionStringUTF8Bytes,
                .declaredWorkUnits,
                .planningWorkUnits,
                .cancellationCheckInterval
            ]
        )

        _ = try RecompareModePlanner.plan(
            request(
                sourceCount: 2,
                currentMode: .text,
                targetMode: .text,
                declaredWorkUnits: 0,
                limits: RecompareModePlanLimits(
                    maximumSourceCount: 2,
                    maximumOptionItemCount: 0,
                    maximumOptionStringUTF8Bytes: 0,
                    maximumTotalOptionStringUTF8Bytes: 0,
                    maximumDeclaredWorkUnits: 0,
                    maximumPlanningWorkUnits: 2,
                    cancellationCheckInterval: 1
                )
            )
        )
        assertPlanningError(.planningWorkLimitExceeded(maximumWorkUnits: 0)) {
            _ = try RecompareModePlanner.plan(
                request(
                    sourceCount: 2,
                    currentMode: .text,
                    targetMode: .text,
                    declaredWorkUnits: 0,
                    limits: RecompareModePlanLimits(
                        maximumSourceCount: 2,
                        maximumOptionItemCount: 0,
                        maximumOptionStringUTF8Bytes: 0,
                        maximumTotalOptionStringUTF8Bytes: 0,
                        maximumDeclaredWorkUnits: 0,
                        maximumPlanningWorkUnits: 0,
                        cancellationCheckInterval: 1
                    )
                )
            )
        }

        let invalidCases: [(RecompareModePlanLimit, RecompareModePlanLimits)] = [
            (.sourceCount, planLimits(maximumSourceCount: 1)),
            (
                .sourceCount,
                planLimits(
                    maximumSourceCount: RecompareModePlanLimits.hardMaximumSourceCount + 1
                )
            ),
            (.optionItemCount, planLimits(maximumOptionItemCount: -1)),
            (
                .optionItemCount,
                planLimits(
                    maximumOptionItemCount:
                        RecompareModePlanLimits.hardMaximumOptionItemCount + 1
                )
            ),
            (.optionStringUTF8Bytes, planLimits(maximumOptionStringUTF8Bytes: -1)),
            (
                .optionStringUTF8Bytes,
                planLimits(
                    maximumOptionStringUTF8Bytes:
                        RecompareModePlanLimits.hardMaximumOptionStringUTF8Bytes + 1
                )
            ),
            (
                .totalOptionStringUTF8Bytes,
                planLimits(maximumTotalOptionStringUTF8Bytes: -1)
            ),
            (
                .totalOptionStringUTF8Bytes,
                planLimits(
                    maximumTotalOptionStringUTF8Bytes:
                        RecompareModePlanLimits.hardMaximumTotalOptionStringUTF8Bytes + 1
                )
            ),
            (
                .declaredWorkUnits,
                planLimits(
                    maximumDeclaredWorkUnits:
                        RecompareModePlanLimits.hardMaximumDeclaredWorkUnits + 1
                )
            ),
            (.planningWorkUnits, planLimits(maximumPlanningWorkUnits: -1)),
            (
                .planningWorkUnits,
                planLimits(
                    maximumPlanningWorkUnits:
                        RecompareModePlanLimits.hardMaximumPlanningWorkUnits + 1
                )
            ),
            (.cancellationCheckInterval, planLimits(cancellationCheckInterval: 0)),
            (
                .cancellationCheckInterval,
                planLimits(
                    cancellationCheckInterval:
                        RecompareModePlanLimits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]

        for (limit, limits) in invalidCases {
            assertPlanningError(.invalidLimit(limit)) {
                _ = try RecompareModePlanner.plan(
                    request(
                        sourceCount: 2,
                        currentMode: .text,
                        targetMode: .text,
                        limits: limits
                    )
                )
            }
        }
    }

    func testExpectedSourceReferenceRejectsStaleGenerationBeforePlanning() {
        let sources = snapshot(sourceCount: 2)
        let expected = RecompareModeSourceSnapshotReference(
            identity: sources.identity,
            generation: sources.generation - 1
        )

        assertPlanningError(
            .staleSourceGeneration(expected: Self.generation - 1, actual: Self.generation)
        ) {
            _ = try RecompareModePlanner.plan(
                request(sources: sources, currentMode: .text, targetMode: .text),
                expecting: expected
            )
        }
    }

    func testCancelledTaskReturnsPlanningCancellationError() async {
        let request = request(sourceCount: 2, currentMode: .text, targetMode: .text)
        let task = Task { () throws -> RecompareModePlan in
            withUnsafeCurrentTask { $0?.cancel() }
            return try RecompareModePlanner.plan(request)
        }

        do {
            _ = try await task.value
            XCTFail("Cancelled planning unexpectedly returned a plan")
        } catch {
            XCTAssertEqual(error as? RecompareModePlanningError, .cancelled)
        }
    }

    private static let sourceSetIdentity = RecompareModeSourceSetIdentity(
        rawValue: uuid("00000000-0000-0000-0000-000000000010")
    )
    private static let leftIdentity = RecompareModeSourceIdentity(
        rawValue: uuid("00000000-0000-0000-0000-000000000011")
    )
    private static let middleIdentity = RecompareModeSourceIdentity(
        rawValue: uuid("00000000-0000-0000-0000-000000000022")
    )
    private static let rightIdentity = RecompareModeSourceIdentity(
        rawValue: uuid("00000000-0000-0000-0000-000000000033")
    )
    private static let generation: UInt64 = 42

    private struct EngineCeilingCase {
        let mode: RecompareMode
        let sourceCount: Int
        let name: String
        let exactOptions: RecompareModeOptions
        let overOptions: RecompareModeOptions
    }

    private func engineCeiling(
        mode: RecompareMode,
        sourceCount: Int,
        name: String,
        maximum: Int,
        makeOptions: (Int) -> RecompareModeOptions
    ) -> EngineCeilingCase {
        EngineCeilingCase(
            mode: mode,
            sourceCount: sourceCount,
            name: name,
            exactOptions: makeOptions(maximum),
            overOptions: makeOptions(maximum + 1)
        )
    }

    private func assertEngineCeilings(
        _ cases: [EngineCeilingCase],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for testCase in cases {
            XCTAssertNoThrow(
                try RecompareModePlanner.plan(
                    request(
                        sourceCount: testCase.sourceCount,
                        currentMode: testCase.mode,
                        targetMode: testCase.mode,
                        options: testCase.exactOptions
                    )
                ),
                "Exact ceiling rejected: \(testCase.name)",
                file: file,
                line: line
            )
            assertPlanningError(
                .invalidOption(mode: testCase.mode, name: testCase.name),
                file: file,
                line: line
            ) {
                _ = try RecompareModePlanner.plan(
                    request(
                        sourceCount: testCase.sourceCount,
                        currentMode: testCase.mode,
                        targetMode: testCase.mode,
                        options: testCase.overOptions
                    )
                )
            }
        }
    }

    private func tableParsingEngineCeilings(
        prefix: String,
        makeOptions: (DelimitedTableParsingOptions) -> RecompareModeOptions
    ) -> [EngineCeilingCase] {
        [
            tableParsingEngineCeiling(
                prefix: prefix,
                name: "maximumInputBytes",
                maximum: 64 * 1_024 * 1_024,
                makeLimits: {
                    DelimitedTableLimits(maximumInputBytes: $0)
                },
                makeOptions: makeOptions
            ),
            tableParsingEngineCeiling(
                prefix: prefix,
                name: "maximumRows",
                maximum: 1_048_576,
                makeLimits: {
                    DelimitedTableLimits(maximumRows: $0)
                },
                makeOptions: makeOptions
            ),
            tableParsingEngineCeiling(
                prefix: prefix,
                name: "maximumColumnsPerRow",
                maximum: 16_384,
                makeLimits: {
                    DelimitedTableLimits(maximumColumnsPerRow: $0)
                },
                makeOptions: makeOptions
            ),
            tableParsingEngineCeiling(
                prefix: prefix,
                name: "maximumTotalCells",
                maximum: 1_048_576,
                makeLimits: {
                    DelimitedTableLimits(maximumTotalCells: $0)
                },
                makeOptions: makeOptions
            ),
            tableParsingEngineCeiling(
                prefix: prefix,
                name: "maximumCellBytes",
                maximum: 16 * 1_024 * 1_024,
                makeLimits: {
                    DelimitedTableLimits(maximumCellBytes: $0)
                },
                makeOptions: makeOptions
            )
        ]
    }

    private func tableParsingEngineCeiling(
        prefix: String,
        name: String,
        maximum: Int,
        makeLimits: (Int) -> DelimitedTableLimits,
        makeOptions: (DelimitedTableParsingOptions) -> RecompareModeOptions
    ) -> EngineCeilingCase {
        engineCeiling(
            mode: .table,
            sourceCount: prefix.contains("threeWay") ? 3 : 2,
            name: "\(prefix).limits.\(name)",
            maximum: maximum
        ) {
            makeOptions(DelimitedTableParsingOptions(limits: makeLimits($0)))
        }
    }

    private func tableComparisonEngineCeilings(
        prefix: String,
        makeOptions: (TableComparisonOptions) -> RecompareModeOptions
    ) -> [EngineCeilingCase] {
        [
            tableComparisonEngineCeiling(
                prefix: prefix,
                name: "maximumExactEditDistance",
                maximum: 2_048,
                makeComparison: {
                    TableComparisonOptions(maximumExactEditDistance: $0)
                },
                makeOptions: makeOptions
            ),
            tableComparisonEngineCeiling(
                prefix: prefix,
                name: "maximumAlignmentWork",
                maximum: 16 * 1_024 * 1_024,
                makeComparison: {
                    TableComparisonOptions(maximumAlignmentWork: $0)
                },
                makeOptions: makeOptions
            ),
            tableComparisonEngineCeiling(
                prefix: prefix,
                name: "maximumComparedRows",
                maximum: 2_097_152,
                makeComparison: {
                    TableComparisonOptions(maximumComparedRows: $0)
                },
                makeOptions: makeOptions
            ),
            tableComparisonEngineCeiling(
                prefix: prefix,
                name: "maximumComparedCells",
                maximum: 2_097_152,
                makeComparison: {
                    TableComparisonOptions(maximumComparedCells: $0)
                },
                makeOptions: makeOptions
            )
        ]
    }

    private func tableComparisonEngineCeiling(
        prefix: String,
        name: String,
        maximum: Int,
        makeComparison: (Int) -> TableComparisonOptions,
        makeOptions: (TableComparisonOptions) -> RecompareModeOptions
    ) -> EngineCeilingCase {
        engineCeiling(
            mode: .table,
            sourceCount: prefix.contains("threeWay") ? 3 : 2,
            name: "\(prefix).\(name)",
            maximum: maximum
        ) {
            makeOptions(makeComparison($0))
        }
    }

    private func imageLoadingEngineCeiling(
        name: String,
        maximum: Int,
        makeLimits: (Int) -> ImageComparisonLimits
    ) -> EngineCeilingCase {
        engineCeiling(
            mode: .image,
            sourceCount: 2,
            name: "image.loading.\(name)",
            maximum: maximum
        ) {
            .image(loading: makeLimits($0), comparison: .default)
        }
    }

    private func twoWayWebPageEngineCeilings() -> [EngineCeilingCase] {
        let defaults = WebPageComparisonLimits.default
        return [
            twoWayWebPageEngineCeiling(name: "maximumInputBytes", maximum: 64 * 1_024 * 1_024) {
                WebPageComparisonLimits(maximumInputBytes: $0)
            },
            twoWayWebPageEngineCeiling(name: "maximumTokenCount", maximum: defaults.maximumTokenCount) {
                WebPageComparisonLimits(maximumTokenCount: $0)
            },
            twoWayWebPageEngineCeiling(name: "maximumAttributeCount", maximum: defaults.maximumAttributeCount) {
                WebPageComparisonLimits(maximumAttributeCount: $0)
            },
            twoWayWebPageEngineCeiling(name: "maximumAttributesPerTag", maximum: defaults.maximumAttributesPerTag) {
                WebPageComparisonLimits(maximumAttributesPerTag: $0)
            },
            twoWayWebPageEngineCeiling(name: "maximumElementDepth", maximum: defaults.maximumElementDepth) {
                WebPageComparisonLimits(maximumElementDepth: $0)
            },
            twoWayWebPageEngineCeiling(name: "maximumWorkUnits", maximum: defaults.maximumWorkUnits) {
                WebPageComparisonLimits(maximumWorkUnits: $0)
            },
            twoWayWebPageEngineCeiling(name: "maximumOutputBytes", maximum: 64 * 1_024 * 1_024) {
                WebPageComparisonLimits(maximumOutputBytes: $0)
            }
        ]
    }

    private func twoWayWebPageEngineCeiling(
        name: String,
        maximum: Int,
        makeLimits: (Int) -> WebPageComparisonLimits
    ) -> EngineCeilingCase {
        engineCeiling(
            mode: .webpage,
            sourceCount: 2,
            name: "webpage.twoWay.limits.\(name)",
            maximum: maximum
        ) {
            .webpage(
                twoWay: WebPageComparisonOptions(limits: makeLimits($0)),
                threeWay: .default
            )
        }
    }

    private func threeWayWebPageEngineCeilings() -> [EngineCeilingCase] {
        let defaults = ThreeWayWebPageComparisonLimits.default
        return [
            threeWayWebPageEngineCeiling(
                name: "maximumSourceInputBytesPerSnapshot",
                maximum: 64 * 1_024 * 1_024
            ) {
                ThreeWayWebPageComparisonLimits(maximumSourceInputBytesPerSnapshot: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumNormalizedInputBytesPerSnapshot",
                maximum: 64 * 1_024 * 1_024
            ) {
                ThreeWayWebPageComparisonLimits(maximumNormalizedInputBytesPerSnapshot: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumTokenCountPerSnapshot",
                maximum: defaults.maximumTokenCountPerSnapshot
            ) {
                ThreeWayWebPageComparisonLimits(maximumTokenCountPerSnapshot: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumAttributeCountPerSnapshot",
                maximum: defaults.maximumAttributeCountPerSnapshot
            ) {
                ThreeWayWebPageComparisonLimits(maximumAttributeCountPerSnapshot: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumTotalNormalizedInputBytes",
                maximum: 192 * 1_024 * 1_024
            ) {
                ThreeWayWebPageComparisonLimits(maximumTotalNormalizedInputBytes: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumInputLinesPerSnapshot",
                maximum: 1_024 * 1_024
            ) {
                ThreeWayWebPageComparisonLimits(maximumInputLinesPerSnapshot: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumMetadataEntriesPerSnapshot",
                maximum: defaults.maximumMetadataEntriesPerSnapshot
            ) {
                ThreeWayWebPageComparisonLimits(maximumMetadataEntriesPerSnapshot: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumMetadataBytes",
                maximum: defaults.maximumMetadataBytes
            ) {
                ThreeWayWebPageComparisonLimits(maximumMetadataBytes: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumWorkUnits",
                maximum: 512 * 1_024 * 1_024
            ) {
                ThreeWayWebPageComparisonLimits(maximumWorkUnits: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumResultRegions",
                maximum: 3 * 1_024 * 1_024 + 1
            ) {
                ThreeWayWebPageComparisonLimits(maximumResultRegions: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumMappedSegments",
                maximum: defaults.maximumMappedSegments
            ) {
                ThreeWayWebPageComparisonLimits(maximumMappedSegments: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumOutputBytes",
                maximum: 192 * 1_024 * 1_024
            ) {
                ThreeWayWebPageComparisonLimits(maximumOutputBytes: $0)
            },
            threeWayWebPageEngineCeiling(
                name: "maximumOutputLines",
                maximum: 3 * 1_024 * 1_024
            ) {
                ThreeWayWebPageComparisonLimits(maximumOutputLines: $0)
            }
        ]
    }

    private func threeWayWebPageEngineCeiling(
        name: String,
        maximum: Int,
        makeLimits: (Int) -> ThreeWayWebPageComparisonLimits
    ) -> EngineCeilingCase {
        engineCeiling(
            mode: .webpage,
            sourceCount: 3,
            name: "webpage.threeWay.limits.\(name)",
            maximum: maximum
        ) {
            .webpage(
                twoWay: .default,
                threeWay: ThreeWayWebPageComparisonOptions(limits: makeLimits($0))
            )
        }
    }

    private func archiveEngineCeiling(
        label: String,
        maximum: Int,
        makeLimits: (Int) -> ArchiveLimits
    ) -> EngineCeilingCase {
        engineCeiling(
            mode: .archive,
            sourceCount: 2,
            name: "archive.limits",
            maximum: maximum
        ) {
            .archive(limits: makeLimits($0))
        }
    }

    private func planLimits(
        maximumSourceCount: Int = RecompareModePlanLimits.default.maximumSourceCount,
        maximumOptionItemCount: Int = RecompareModePlanLimits.default.maximumOptionItemCount,
        maximumOptionStringUTF8Bytes: Int = RecompareModePlanLimits.default.maximumOptionStringUTF8Bytes,
        maximumTotalOptionStringUTF8Bytes: Int = RecompareModePlanLimits.default.maximumTotalOptionStringUTF8Bytes,
        maximumDeclaredWorkUnits: UInt64 = RecompareModePlanLimits.default.maximumDeclaredWorkUnits,
        maximumPlanningWorkUnits: Int = RecompareModePlanLimits.default.maximumPlanningWorkUnits,
        cancellationCheckInterval: Int = RecompareModePlanLimits.default.cancellationCheckInterval
    ) -> RecompareModePlanLimits {
        RecompareModePlanLimits(
            maximumSourceCount: maximumSourceCount,
            maximumOptionItemCount: maximumOptionItemCount,
            maximumOptionStringUTF8Bytes: maximumOptionStringUTF8Bytes,
            maximumTotalOptionStringUTF8Bytes: maximumTotalOptionStringUTF8Bytes,
            maximumDeclaredWorkUnits: maximumDeclaredWorkUnits,
            maximumPlanningWorkUnits: maximumPlanningWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func isClipboard(_ kind: RecompareModeSourceKind) -> Bool {
        kind == .clipboardText || kind == .clipboardBinary
    }

    private func sides(sourceCount: Int) -> [ComparisonOpenSidePosition] {
        sourceCount == 2 ? [.left, .right] : [.left, .middle, .right]
    }

    private func request(
        sourceCount: Int,
        currentMode: RecompareMode,
        targetMode: RecompareMode,
        options: RecompareModeOptions? = nil,
        declaredWorkUnits: UInt64 = 1,
        limits: RecompareModePlanLimits = .default
    ) -> RecompareModeRequest {
        request(
            sources: snapshot(sourceCount: sourceCount),
            currentMode: currentMode,
            targetMode: targetMode,
            options: options,
            declaredWorkUnits: declaredWorkUnits,
            limits: limits
        )
    }

    private func request(
        sources: RecompareModeSourceSnapshot,
        currentMode: RecompareMode,
        targetMode: RecompareMode,
        options: RecompareModeOptions? = nil,
        declaredWorkUnits: UInt64 = 1,
        limits: RecompareModePlanLimits = .default
    ) -> RecompareModeRequest {
        RecompareModeRequest(
            sources: sources,
            currentMode: currentMode,
            targetMode: targetMode,
            options: options ?? self.options(for: targetMode),
            declaredWorkUnits: declaredWorkUnits,
            limits: limits
        )
    }

    private func options(for mode: RecompareMode) -> RecompareModeOptions {
        switch mode {
        case .text:
            .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions())
        case .table:
            .table(
                parsing: .commaSeparated,
                twoWay: .default,
                threeWay: .default
            )
        case .binary:
            .binary(twoWay: BinaryComparisonOptions(), threeWay: .default)
        case .image:
            .image(loading: .default, comparison: .default)
        case .webpage:
            .webpage(twoWay: .default, threeWay: .default)
        case .archive:
            .archive(limits: .default)
        }
    }

    private func snapshot(
        sourceCount: Int,
        kinds: [ComparisonOpenSidePosition: RecompareModeSourceKind] = [:]
    ) -> RecompareModeSourceSnapshot {
        let sides: [ComparisonOpenSidePosition] =
            sourceCount == 2
            ? [.left, .right]
            : [.left, .middle, .right]
        return RecompareModeSourceSnapshot(
            identity: Self.sourceSetIdentity,
            generation: Self.generation,
            sources: sides.reversed().map {
                source($0, kind: kinds[$0] ?? .localFile)
            }
        )
    }

    private func source(
        _ side: ComparisonOpenSidePosition,
        kind: RecompareModeSourceKind = .localFile
    ) -> RecompareModeSourceBinding {
        switch side {
        case .left:
            RecompareModeSourceBinding(
                side: side,
                identity: Self.leftIdentity,
                revision: RecompareModeSourceRevision(rawValue: 11),
                kind: kind
            )
        case .middle:
            RecompareModeSourceBinding(
                side: side,
                identity: Self.middleIdentity,
                revision: RecompareModeSourceRevision(rawValue: 22),
                kind: kind
            )
        case .right:
            RecompareModeSourceBinding(
                side: side,
                identity: Self.rightIdentity,
                revision: RecompareModeSourceRevision(rawValue: 33),
                kind: kind
            )
        }
    }

    private func replacingSource(
        in snapshot: RecompareModeSourceSnapshot,
        side: ComparisonOpenSidePosition,
        transform: (RecompareModeSourceBinding) -> RecompareModeSourceBinding
    ) -> RecompareModeSourceSnapshot {
        RecompareModeSourceSnapshot(
            identity: snapshot.identity,
            generation: snapshot.generation,
            sources: snapshot.sources.map { source in
                source.side == side ? transform(source) : source
            }
        )
    }

    private func assertNotCurrent(
        _ snapshot: RecompareModeSourceSnapshot,
        plan: RecompareModePlan,
        error expected: RecompareModePlanningError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNoThrow(
            XCTAssertFalse(try plan.isCurrent(for: snapshot), file: file, line: line),
            file: file,
            line: line
        )
        assertPlanningError(expected, file: file, line: line) {
            try plan.requireCurrentSources(snapshot)
        }
    }

    private func assertPlanningError(
        _ expected: RecompareModePlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? RecompareModePlanningError, expected, file: file, line: line)
        }
    }

    private static func uuid(_ value: String) -> UUID {
        guard let result = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID")
        }
        return result
    }

    private func uuid(_ value: String) -> UUID {
        Self.uuid(value)
    }
}
