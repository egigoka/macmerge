import Foundation
import MacMergeCore
import XCTest

final class ModeStatusWorkflowTests: XCTestCase {
    func testPublicEnumCasesAndOrderingCoverEveryModePhaseAndStage() {
        XCTAssertEqual(ModeStatusMode.allCases, [.folder, .binary, .image, .webpage])
        XCTAssertEqual(ModeStatusPhase.allCases, [.loading, .refreshing, .current, .stale, .failed, .cancelled])
        XCTAssertEqual(ModeStatusSide.allCases.sorted(), [.left, .middle, .right])
        XCTAssertEqual(
            ModeStatusProgressStage.allCases.sorted(),
            [.preparing, .loadingInputs, .comparing, .projecting, .publishing]
        )
        XCTAssertEqual(ModeStatusOperationKind.allCases, [.initialLoad, .refresh])
        XCTAssertEqual(ModeStatusBinarySurface.allCases, [.bytes, .characters])
        XCTAssertEqual(ModeStatusBinaryAlignment.allCases, [.exact, .boundedFallback])
        XCTAssertEqual(ModeStatusWebPageForm.allCases, [.source, .renderedText])
        XCTAssertEqual(
            ModeStatusExternalChangeState.allCases,
            [.notApplicable, .notChecked, .unchanged, .changed, .missing, .inaccessible]
        )
    }

    func testCurrentProjectionSupportsEveryModeAndTwoOrThreeSources() throws {
        let cases: [(ModeStatusMode, Int)] = [
            (.folder, 2),
            (.binary, 2),
            (.binary, 3),
            (.image, 2),
            (.image, 3),
            (.webpage, 2),
            (.webpage, 3)
        ]

        for (mode, sourceCount) in cases {
            let fixture = StatusFixture(mode: mode, sourceCount: sourceCount)
            let snapshot = fixture.currentSnapshot()
            let projection = try ModeStatusWorkflow.project(snapshot)

            XCTAssertEqual(projection.snapshot, snapshot.reference)
            XCTAssertEqual(projection.mode, mode)
            XCTAssertEqual(projection.phase, .current)
            XCTAssertEqual(projection.inputs, fixture.inputs)
            XCTAssertEqual(projection.sources, fixture.sources)
            XCTAssertNil(projection.operation)
            XCTAssertEqual(projection.comparison, fixture.comparison.reference)
            XCTAssertNil(projection.staleReason)
            XCTAssertNil(projection.failure)
            XCTAssertNil(projection.cancellation)
            XCTAssertEqual(projection.metrics, fixture.comparison.metrics)
            XCTAssertEqual(projection.interaction, .none)
            XCTAssertTrue(projection.isResultCurrent)
            XCTAssertTrue(try projection.isCurrent(snapshot: snapshot))
        }
    }

    func testEveryModeAcceptsAnExactZeroDifferenceResult() throws {
        let cases: [(mode: ModeStatusMode, sourceCount: Int, metrics: ModeStatusComparisonMetrics)] = [
            (
                .folder,
                2,
                .folder(
                    folderMetrics(
                        total: 10,
                        visible: 10,
                        identical: 10,
                        different: 0,
                        leftOnly: 0,
                        rightOnly: 0
                    )
                )
            ),
            (.binary, 2, .binary(binaryMetrics(regions: 0, differing: 0))),
            (.binary, 3, .binary(binaryMetrics(regions: 0, differing: 0))),
            (.image, 2, .image(imageMetrics(regions: 0, differing: 0))),
            (.image, 3, .image(imageMetrics(regions: 0, differing: 0))),
            (.webpage, 2, .webpage(webMetrics(differences: 0))),
            (.webpage, 3, .webpage(webMetrics(differences: 0)))
        ]

        for value in cases {
            let fixture = StatusFixture(mode: value.mode, sourceCount: value.sourceCount)
            let comparison = makeComparison(
                inputs: fixture.inputs,
                sourceMetrics: makeComparisonSourceMetrics(from: fixture.sources),
                metrics: value.metrics
            )
            let projection = try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .current(comparison.reference),
                    comparison: comparison
                )
            )

            XCTAssertEqual(projection.mode, value.mode)
            XCTAssertEqual(projection.phase, .current)
            XCTAssertEqual(projection.comparison, comparison.reference)
            XCTAssertEqual(projection.metrics, value.metrics)
            XCTAssertTrue(projection.isResultCurrent)
        }
    }

    func testProjectionMapsEveryLifecyclePhaseWithoutInventingTerminalState() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let old = staleComparison(for: fixture, reason: .sourceChanged(.left)).comparison
        let loading = makeOperation(kind: .initialLoad, inputs: fixture.inputs, stage: .loadingInputs)
        let refreshing = makeOperation(
            kind: .refresh,
            inputs: fixture.inputs,
            retainedComparison: old.reference,
            stage: .comparing
        )
        let failure = ModeStatusFailure(
            kind: .readFailed,
            stage: .publishing,
            side: .right,
            isRetryable: true
        )
        let cancellation = ModeStatusCancellation(reason: .superseded, stage: .projecting)
        let cases:
            [(
                lifecycle: ModeStatusLifecycle,
                comparison: ModeStatusComparisonSnapshot?,
                phase: ModeStatusPhase,
                operation: ModeStatusOperation?,
                comparisonReference: ModeStatusComparisonReference?,
                staleReason: ModeStatusStaleReason?,
                failure: ModeStatusFailure?,
                cancellation: ModeStatusCancellation?,
                isCurrent: Bool
            )] = [
                (.loading(loading), nil, .loading, loading, nil, nil, nil, nil, false),
                (.refreshing(refreshing), old, .refreshing, refreshing, old.reference, nil, nil, nil, false),
                (
                    .current(fixture.comparison.reference),
                    fixture.comparison,
                    .current,
                    nil,
                    fixture.comparison.reference,
                    nil,
                    nil,
                    nil,
                    true
                ),
                (
                    .stale(old.reference, reason: .sourceChanged(.left)),
                    old,
                    .stale,
                    nil,
                    old.reference,
                    .sourceChanged(.left),
                    nil,
                    nil,
                    false
                ),
                (.failed(loading, failure: failure), nil, .failed, loading, nil, nil, failure, nil, false),
                (
                    .cancelled(loading, cancellation: cancellation),
                    nil,
                    .cancelled,
                    loading,
                    nil,
                    nil,
                    nil,
                    cancellation,
                    false
                )
            ]

        for value in cases {
            let snapshot = fixture.snapshot(
                lifecycle: value.lifecycle,
                comparison: value.comparison
            )
            let projection = try ModeStatusWorkflow.project(snapshot)

            XCTAssertEqual(projection.phase, value.phase)
            XCTAssertEqual(projection.operation, value.operation)
            XCTAssertEqual(projection.comparison, value.comparisonReference)
            XCTAssertEqual(projection.staleReason, value.staleReason)
            XCTAssertEqual(projection.failure, value.failure)
            XCTAssertEqual(projection.cancellation, value.cancellation)
            XCTAssertEqual(projection.metrics, value.comparison?.metrics)
            XCTAssertEqual(projection.isResultCurrent, value.isCurrent)
        }
    }

    func testFailedAndCancelledRefreshesProjectTheirExactRetainedComparison() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let retained = staleComparison(for: fixture, reason: .sourceChanged(.left)).comparison
        let refresh = makeOperation(
            kind: .refresh,
            inputs: fixture.inputs,
            retainedComparison: retained.reference,
            stage: .comparing
        )
        let failure = ModeStatusFailure(
            kind: .comparisonFailed,
            stage: .publishing,
            side: .right,
            isRetryable: true
        )
        let cancellation = ModeStatusCancellation(reason: .ownerClosing, stage: .projecting)

        let failed = try ModeStatusWorkflow.project(
            fixture.snapshot(
                lifecycle: .failed(refresh, failure: failure),
                comparison: retained
            )
        )
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.operation, refresh)
        XCTAssertEqual(failed.comparison, retained.reference)
        XCTAssertEqual(failed.metrics, retained.metrics)
        XCTAssertEqual(failed.failure, failure)
        XCTAssertNil(failed.cancellation)
        XCTAssertFalse(failed.isResultCurrent)

        let cancelled = try ModeStatusWorkflow.project(
            fixture.snapshot(
                lifecycle: .cancelled(refresh, cancellation: cancellation),
                comparison: retained
            )
        )
        XCTAssertEqual(cancelled.phase, .cancelled)
        XCTAssertEqual(cancelled.operation, refresh)
        XCTAssertEqual(cancelled.comparison, retained.reference)
        XCTAssertEqual(cancelled.metrics, retained.metrics)
        XCTAssertNil(cancelled.failure)
        XCTAssertEqual(cancelled.cancellation, cancellation)
        XCTAssertFalse(cancelled.isResultCurrent)
    }

    func testReferencesBindExactIdentityGenerationAndSide() {
        let sourceIdentity = ModeStatusSourceIdentity(rawValue: statusUUID(10))
        let source = ModeStatusSourceReference(identity: sourceIdentity, generation: 11)
        let changedGeneration = ModeStatusSourceReference(identity: sourceIdentity, generation: 12)
        let changedIdentity = ModeStatusSourceReference(
            identity: ModeStatusSourceIdentity(rawValue: statusUUID(11)),
            generation: 11
        )
        XCTAssertNotEqual(source, changedGeneration)
        XCTAssertNotEqual(source, changedIdentity)

        let inputs = makeInput(mode: .binary, sourceCount: 3)
        XCTAssertEqual(inputs[.left], inputs.sources[0].source)
        XCTAssertEqual(inputs[.middle], inputs.sources[1].source)
        XCTAssertEqual(inputs[.right], inputs.sources[2].source)

        let item = ModeStatusItemIdentity(
            comparisonIdentity: ModeStatusComparisonIdentity(rawValue: statusUUID(20)),
            comparisonGeneration: 21,
            rawValue: statusUUID(22)
        )
        XCTAssertNotEqual(
            item,
            ModeStatusItemIdentity(
                comparisonIdentity: item.comparisonIdentity,
                comparisonGeneration: 22,
                rawValue: item.rawValue
            )
        )
    }

    func testSourceLayoutRequiresCanonicalTwoOrThreeSidesAndFolderIsTwoWayOnly() {
        for count in [0, 1, 4] {
            let input = makeInput(mode: .binary, sides: Array(repeating: .left, count: count))
            let snapshot = rawSnapshot(mode: .binary, inputs: input, sources: [])
            assertStatusError(.invalidSourceLayout) {
                try ModeStatusWorkflow.project(snapshot)
            }
        }

        let folderInput = makeInput(mode: .folder, sourceCount: 3)
        assertStatusError(.invalidSourceLayout) {
            try ModeStatusWorkflow.project(
                rawSnapshot(
                    mode: .folder,
                    inputs: folderInput,
                    sources: makeSourceStates(for: folderInput)
                )
            )
        }

        let duplicateInput = makeInput(mode: .binary, sides: [.left, .left])
        assertStatusError(.duplicateSourceSide(.left)) {
            try ModeStatusWorkflow.project(
                rawSnapshot(
                    mode: .binary,
                    inputs: duplicateInput,
                    sources: makeSourceStates(for: duplicateInput)
                )
            )
        }

        for sides in [[ModeStatusSide.right, .left], [.left, .middle], [.left, .right, .middle]] {
            let input = makeInput(mode: .binary, sides: sides)
            assertStatusError(.sourceOrderIsNotCanonical) {
                try ModeStatusWorkflow.project(
                    rawSnapshot(
                        mode: .binary,
                        inputs: input,
                        sources: makeSourceStates(for: input)
                    )
                )
            }
        }
    }

    func testSnapshotRejectsModeInputMismatchAndExactSourceCountOrOrderChanges() {
        let binaryInputs = makeInput(mode: .binary, sourceCount: 2)
        assertStatusError(.invalidLifecycle(.inputMismatch)) {
            try ModeStatusWorkflow.project(
                rawSnapshot(
                    mode: .webpage,
                    inputs: binaryInputs,
                    sources: makeSourceStates(for: binaryInputs)
                )
            )
        }

        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        for sources in [
            Array(fixture.sources.dropLast()),
            fixture.sources + [fixture.sources[0]]
        ] {
            assertStatusError(.invalidSourceLayout) {
                try ModeStatusWorkflow.project(
                    fixture.snapshot(
                        sources: sources,
                        lifecycle: .current(fixture.comparison.reference),
                        comparison: fixture.comparison
                    )
                )
            }
        }

        assertStatusError(.sourceOrderIsNotCanonical) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    sources: [fixture.sources[1], fixture.sources[0]],
                    lifecycle: .current(fixture.comparison.reference),
                    comparison: fixture.comparison
                )
            )
        }
    }

    func testSnapshotSourcesRequireExactOrderedReferenceModeAndPersistenceState() {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let first = fixture.sources[0]
        let wrongReference = ModeStatusSourceState(
            side: first.side,
            source: ModeStatusSourceReference(
                identity: first.source.identity,
                generation: first.source.generation + 1
            ),
            metrics: first.metrics,
            isReadOnly: first.isReadOnly,
            isDirty: first.isDirty,
            isPersisted: first.isPersisted,
            externalChange: first.externalChange
        )
        assertStatusError(.sourceReferenceMismatch(.left)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    sources: [wrongReference, fixture.sources[1]],
                    lifecycle: .current(fixture.comparison.reference),
                    comparison: fixture.comparison
                )
            )
        }

        let wrongMode = replacingSourceState(first, metrics: sourceMetrics(mode: .webpage, side: .left))
        assertStatusError(.sourceModeMismatch(.left)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    sources: [wrongMode, fixture.sources[1]],
                    lifecycle: .current(fixture.comparison.reference),
                    comparison: fixture.comparison
                )
            )
        }

        let invalidPersisted = replacingSourceState(
            first,
            isPersisted: true,
            externalChange: .notApplicable
        )
        let invalidTransient = replacingSourceState(
            first,
            isPersisted: false,
            externalChange: .unchanged
        )
        for source in [invalidPersisted, invalidTransient] {
            assertStatusError(.invalidExternalChangeState(.left)) {
                try ModeStatusWorkflow.project(
                    fixture.snapshot(
                        sources: [source, fixture.sources[1]],
                        lifecycle: .current(fixture.comparison.reference),
                        comparison: fixture.comparison
                    )
                )
            }
        }
    }

    func testSourceMetricBoundsAcceptExactLimitAndRejectOneOver() throws {
        let inputs = makeInput(mode: .binary, sourceCount: 2)
        let exactMetrics = ModeStatusSourceMetrics.binary(
            ModeStatusBinarySourceMetrics(byteCount: 10)
        )
        let sources = makeSourceStates(for: inputs, metrics: [.left: exactMetrics])
        let comparison = makeComparison(
            inputs: inputs,
            sourceMetrics: makeComparisonSourceMetrics(from: sources),
            metrics: .binary(
                ModeStatusBinaryComparisonMetrics(
                    alignedByteCount: 10,
                    differenceRegionCount: 1,
                    differingByteCount: 1,
                    alignment: .exact
                )
            )
        )
        let snapshot = rawSnapshot(
            mode: .binary,
            inputs: inputs,
            sources: sources,
            lifecycle: .current(comparison.reference),
            comparison: comparison
        )

        XCTAssertNoThrow(
            try ModeStatusWorkflow.project(snapshot, limits: statusLimits(maximumMetricValue: 10))
        )
        assertStatusError(.metricLimitExceeded(.metricValue)) {
            try ModeStatusWorkflow.project(snapshot, limits: statusLimits(maximumMetricValue: 9))
        }
    }

    func testEachSourceMetricFieldEnforcesItsOwnLimit() throws {
        let cases: [(ModeStatusMode, ModeStatusSourceMetrics)] = [
            (.folder, .folder(ModeStatusFolderSourceMetrics(entryCount: 11))),
            (.binary, .binary(ModeStatusBinarySourceMetrics(byteCount: 11))),
            (
                .image,
                .image(
                    ModeStatusImageSourceMetrics(
                        selectedPageIndex: 0,
                        pageCount: 11,
                        width: 1,
                        height: 1,
                        bitsPerPixel: 1
                    )
                )
            ),
            (
                .image,
                .image(
                    ModeStatusImageSourceMetrics(
                        selectedPageIndex: 0,
                        pageCount: 1,
                        width: 11,
                        height: 1,
                        bitsPerPixel: 1
                    )
                )
            ),
            (
                .image,
                .image(
                    ModeStatusImageSourceMetrics(
                        selectedPageIndex: 0,
                        pageCount: 1,
                        width: 1,
                        height: 11,
                        bitsPerPixel: 1
                    )
                )
            ),
            (
                .image,
                .image(
                    ModeStatusImageSourceMetrics(
                        selectedPageIndex: 0,
                        pageCount: 1,
                        width: 1,
                        height: 1,
                        bitsPerPixel: 11
                    )
                )
            ),
            (
                .webpage,
                .webpage(
                    ModeStatusWebPageSourceMetrics(
                        sourceUTF8ByteCount: 11,
                        normalizedUTF8ByteCount: 1,
                        tokenCount: 1,
                        attributeCount: 1,
                        comparisonLineCount: 1
                    )
                )
            ),
            (
                .webpage,
                .webpage(
                    ModeStatusWebPageSourceMetrics(
                        sourceUTF8ByteCount: 1,
                        normalizedUTF8ByteCount: 11,
                        tokenCount: 1,
                        attributeCount: 1,
                        comparisonLineCount: 1
                    )
                )
            ),
            (
                .webpage,
                .webpage(
                    ModeStatusWebPageSourceMetrics(
                        sourceUTF8ByteCount: 1,
                        normalizedUTF8ByteCount: 1,
                        tokenCount: 11,
                        attributeCount: 1,
                        comparisonLineCount: 1
                    )
                )
            ),
            (
                .webpage,
                .webpage(
                    ModeStatusWebPageSourceMetrics(
                        sourceUTF8ByteCount: 1,
                        normalizedUTF8ByteCount: 1,
                        tokenCount: 1,
                        attributeCount: 11,
                        comparisonLineCount: 1
                    )
                )
            ),
            (
                .webpage,
                .webpage(
                    ModeStatusWebPageSourceMetrics(
                        sourceUTF8ByteCount: 1,
                        normalizedUTF8ByteCount: 1,
                        tokenCount: 1,
                        attributeCount: 1,
                        comparisonLineCount: 11
                    )
                )
            )
        ]

        for (mode, metrics) in cases {
            let inputs = makeInput(mode: mode, sourceCount: 2)
            let sources = makeSourceStates(
                for: inputs,
                metrics: [.left: metrics, .right: boundedSourceMetrics(mode: mode)]
            )
            assertStatusError(.metricLimitExceeded(.metricValue)) {
                try ModeStatusWorkflow.project(
                    rawSnapshot(mode: mode, inputs: inputs, sources: sources),
                    limits: statusLimits(maximumMetricValue: 10)
                )
            }
        }
    }

    func testImageSourceMetricsValidatePageDimensionsAndPixelProduct() throws {
        let fixture = StatusFixture(mode: .image, sourceCount: 2)
        let exactLimits = statusLimits(maximumMetricValue: 32, maximumPixelCount: 30)
        XCTAssertNoThrow(try ModeStatusWorkflow.project(fixture.currentSnapshot(), limits: exactLimits))

        let invalidMetrics: [(ModeStatusImageSourceMetrics, ModeStatusWorkflowError)] = [
            (
                ModeStatusImageSourceMetrics(
                    selectedPageIndex: -1,
                    pageCount: 3,
                    width: 4,
                    height: 3,
                    bitsPerPixel: 32
                ),
                .invalidMetrics(.invalidImagePage)
            ),
            (
                ModeStatusImageSourceMetrics(
                    selectedPageIndex: 3,
                    pageCount: 3,
                    width: 4,
                    height: 3,
                    bitsPerPixel: 32
                ),
                .invalidMetrics(.invalidImagePage)
            ),
            (
                ModeStatusImageSourceMetrics(
                    selectedPageIndex: 0,
                    pageCount: 0,
                    width: 4,
                    height: 3,
                    bitsPerPixel: 32
                ),
                .invalidMetrics(.invalidImagePage)
            ),
            (
                ModeStatusImageSourceMetrics(
                    selectedPageIndex: 0,
                    pageCount: 1,
                    width: 0,
                    height: 3,
                    bitsPerPixel: 32
                ),
                .invalidMetrics(.invalidImageDimensions)
            ),
            (
                ModeStatusImageSourceMetrics(
                    selectedPageIndex: 0,
                    pageCount: 1,
                    width: 4,
                    height: 0,
                    bitsPerPixel: 32
                ),
                .invalidMetrics(.invalidImageDimensions)
            ),
            (
                ModeStatusImageSourceMetrics(
                    selectedPageIndex: 0,
                    pageCount: 1,
                    width: 4,
                    height: 3,
                    bitsPerPixel: 0
                ),
                .invalidMetrics(.invalidImageDimensions)
            ),
            (
                ModeStatusImageSourceMetrics(
                    selectedPageIndex: 0,
                    pageCount: 1,
                    width: Int.max,
                    height: Int.max,
                    bitsPerPixel: 1
                ),
                .invalidMetrics(.invalidImagePixelCount)
            )
        ]

        for (metrics, expected) in invalidMetrics {
            let changed = replacingSourceState(fixture.sources[0], metrics: .image(metrics))
            assertStatusError(expected) {
                try ModeStatusWorkflow.project(
                    fixture.snapshot(
                        sources: [changed, fixture.sources[1]],
                        lifecycle: .current(fixture.comparison.reference),
                        comparison: fixture.comparison
                    )
                )
            }
        }

        let finiteProduct = ModeStatusImageSourceMetrics(
            selectedPageIndex: 0,
            pageCount: 1,
            width: 6,
            height: 5,
            bitsPerPixel: 32
        )
        let finiteSource = replacingSourceState(fixture.sources[0], metrics: .image(finiteProduct))
        XCTAssertNoThrow(
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    sources: [finiteSource, fixture.sources[1]],
                    lifecycle: .loading(makeOperation(kind: .initialLoad, inputs: fixture.inputs)),
                    comparison: nil
                ),
                limits: statusLimits(maximumMetricValue: 32, maximumPixelCount: 30)
            )
        )
        assertStatusError(.invalidMetrics(.invalidImagePixelCount)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    sources: [finiteSource, fixture.sources[1]],
                    lifecycle: .loading(makeOperation(kind: .initialLoad, inputs: fixture.inputs)),
                    comparison: nil
                ),
                limits: statusLimits(maximumMetricValue: 32, maximumPixelCount: 29)
            )
        }
    }

    func testFolderMetricsRequireExactAggregateVisibilityCompletenessAndSourceExtent() throws {
        let fixture = StatusFixture(mode: .folder, sourceCount: 2)
        XCTAssertNoThrow(try ModeStatusWorkflow.project(fixture.currentSnapshot()))

        let cases: [(ModeStatusFolderComparisonMetrics, ModeStatusMetricsIssue)] = [
            (
                folderMetrics(total: 10, visible: 11),
                .visibleCountExceedsTotal
            ),
            (
                folderMetrics(total: 11, visible: 10),
                .aggregateMismatch
            ),
            (
                folderMetrics(total: 10, pending: 0, isComplete: false),
                .incompleteFolderHasNoPendingItems
            ),
            (
                folderMetrics(
                    total: 10,
                    pending: 1,
                    identical: 4,
                    different: 2,
                    leftOnly: 1,
                    rightOnly: 2,
                    isComplete: true
                ),
                .aggregateMismatch
            ),
            (
                folderMetrics(
                    total: 11,
                    visible: 10,
                    identical: 10,
                    different: 0,
                    leftOnly: 1,
                    rightOnly: 0
                ),
                .differencesExceedComparisonExtent
            ),
            (
                folderMetrics(
                    total: 13,
                    visible: 10,
                    identical: 10,
                    different: 0,
                    leftOnly: 0,
                    rightOnly: 3
                ),
                .differencesExceedComparisonExtent
            )
        ]

        for (metrics, issue) in cases {
            assertComparisonMetricsError(issue, fixture: fixture, metrics: .folder(metrics))
        }
    }

    func testBinaryMetricsRequireRegionByteConflictAndSourceConsistencyForTwoAndThreeWay() throws {
        for sourceCount in [2, 3] {
            let fixture = StatusFixture(mode: .binary, sourceCount: sourceCount)
            XCTAssertNoThrow(try ModeStatusWorkflow.project(fixture.currentSnapshot()))
        }

        let twoWay = StatusFixture(mode: .binary, sourceCount: 2)
        let invalidTwoWay: [(ModeStatusBinaryComparisonMetrics, ModeStatusMetricsIssue)] = [
            (binaryMetrics(aligned: 19), .differencesExceedComparisonExtent),
            (binaryMetrics(aligned: 3, regions: 2, differing: 4), .differencesExceedComparisonExtent),
            (binaryMetrics(regions: 0, differing: 1), .aggregateMismatch),
            (binaryMetrics(regions: 2, differing: 1), .aggregateMismatch),
            (binaryMetrics(regions: 2, differing: 4, conflicts: 1), .conflictsExceedDifferences)
        ]
        for (metrics, issue) in invalidTwoWay {
            assertComparisonMetricsError(issue, fixture: twoWay, metrics: .binary(metrics))
        }

        let threeWay = StatusFixture(mode: .binary, sourceCount: 3)
        XCTAssertNoThrow(
            try ModeStatusWorkflow.project(
                threeWay.snapshot(
                    lifecycle: .current(threeWay.comparison.reference),
                    comparison: makeComparison(
                        inputs: threeWay.inputs,
                        metrics: .binary(binaryMetrics(regions: 2, differing: 4, conflicts: 2))
                    )
                )
            )
        )
        assertComparisonMetricsError(
            .conflictsExceedDifferences,
            fixture: threeWay,
            metrics: .binary(binaryMetrics(regions: 1, differing: 4, conflicts: 2))
        )
    }

    func testImageMetricsRequireCanvasPixelRegionAndConflictConsistency() throws {
        let twoWay = StatusFixture(mode: .image, sourceCount: 2)
        let invalid: [(ModeStatusImageComparisonMetrics, ModeStatusMetricsIssue)] = [
            (imageMetrics(canvasWidth: 7), .differencesExceedComparisonExtent),
            (imageMetrics(canvasHeight: 6), .differencesExceedComparisonExtent),
            (
                imageMetrics(canvasWidth: 1, canvasHeight: 1, regions: 1, differing: 2),
                .differencesExceedComparisonExtent
            ),
            (imageMetrics(regions: 0, differing: 1), .aggregateMismatch),
            (imageMetrics(regions: 5, differing: 4), .differencesExceedComparisonExtent),
            (
                imageMetrics(regions: 2, differing: 4, conflicts: 0, conflicting: 1),
                .aggregateMismatch
            ),
            (
                imageMetrics(regions: 2, differing: 4, conflicts: 1, conflicting: 5),
                .differencesExceedComparisonExtent
            ),
            (
                imageMetrics(regions: 1, differing: 4, conflicts: 2, conflicting: 2),
                .conflictsExceedDifferences
            ),
            (
                imageMetrics(regions: 2, differing: 4, conflicts: 2, conflicting: 1),
                .conflictsExceedDifferences
            ),
            (
                imageMetrics(regions: 2, differing: 4, conflicts: 1, conflicting: 1),
                .conflictsExceedDifferences
            )
        ]
        for (metrics, issue) in invalid {
            assertComparisonMetricsError(issue, fixture: twoWay, metrics: .image(metrics))
        }

        let threeWay = StatusFixture(mode: .image, sourceCount: 3)
        let valid = imageMetrics(
            canvasWidth: 6,
            canvasHeight: 5,
            regions: 2,
            differing: 4,
            conflicts: 1,
            conflicting: 2
        )
        XCTAssertNoThrow(
            try ModeStatusWorkflow.project(
                threeWay.snapshot(
                    lifecycle: .current(threeWay.comparison.reference),
                    comparison: makeComparison(inputs: threeWay.inputs, metrics: .image(valid))
                )
            )
        )
        assertComparisonMetricsError(
            .conflictsExceedDifferences,
            fixture: threeWay,
            metrics: .image(
                imageMetrics(regions: 2, differing: 4, conflicts: 3, conflicting: 3)
            )
        )
    }

    func testWebMetricsRequireComparisonExtentAndThreeWayConflicts() throws {
        let twoWay = StatusFixture(mode: .webpage, sourceCount: 2)
        let invalid: [(ModeStatusWebPageComparisonMetrics, ModeStatusMetricsIssue)] = [
            (webMetrics(units: 17, differences: 2), .differencesExceedComparisonExtent),
            (webMetrics(units: 10, differences: 11), .differencesExceedComparisonExtent),
            (webMetrics(units: 10, differences: 2, conflicts: 1), .conflictsExceedDifferences)
        ]
        for (metrics, issue) in invalid {
            assertComparisonMetricsError(issue, fixture: twoWay, metrics: .webpage(metrics))
        }

        let threeWay = StatusFixture(mode: .webpage, sourceCount: 3)
        XCTAssertNoThrow(
            try ModeStatusWorkflow.project(
                threeWay.snapshot(
                    lifecycle: .current(threeWay.comparison.reference),
                    comparison: makeComparison(
                        inputs: threeWay.inputs,
                        metrics: .webpage(webMetrics(units: 12, differences: 3, conflicts: 2))
                    )
                )
            )
        )
        assertComparisonMetricsError(
            .conflictsExceedDifferences,
            fixture: threeWay,
            metrics: .webpage(webMetrics(units: 12, differences: 2, conflicts: 3))
        )
    }

    func testRetainedResultUsesItsBoundSourceMetricsInsteadOfAdvancedCurrentMetrics() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let stale = staleComparison(for: fixture, reason: .sourceChanged(.left))
        let advancedLeft = replacingSourceState(
            fixture.sources[0],
            metrics: .binary(ModeStatusBinarySourceMetrics(byteCount: 100))
        )
        let currentSources = [advancedLeft, fixture.sources[1]]
        let validSnapshot = fixture.snapshot(
            sources: currentSources,
            lifecycle: .stale(stale.comparison.reference, reason: .sourceChanged(.left)),
            comparison: stale.comparison
        )

        XCTAssertNoThrow(try ModeStatusWorkflow.project(validSnapshot))

        let invalidMetrics = ModeStatusComparisonMetrics.binary(
            binaryMetrics(aligned: 50, regions: 1, differing: 1)
        )
        let overRetainedExtent = makeComparison(
            inputs: stale.comparison.reference.inputs,
            identity: stale.comparison.reference.identity,
            generation: stale.comparison.reference.generation,
            sourceMetrics: stale.comparison.sourceMetrics,
            metrics: invalidMetrics
        )
        assertStatusError(.invalidMetrics(.differencesExceedComparisonExtent)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    sources: currentSources,
                    lifecycle: .stale(
                        overRetainedExtent.reference,
                        reason: .sourceChanged(.left)
                    ),
                    comparison: overRetainedExtent
                )
            )
        }

        let sameReferenceDifferentMetrics = replacingSourceState(
            fixture.sources[0],
            metrics: .binary(ModeStatusBinarySourceMetrics(byteCount: 9))
        )
        assertStatusError(.invalidLifecycle(.comparisonSourceMismatch)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    sources: [sameReferenceDifferentMetrics, fixture.sources[1]],
                    lifecycle: .current(fixture.comparison.reference),
                    comparison: fixture.comparison
                )
            )
        }
    }

    func testResultPayloadRejectsExactSourceAndModeMismatches() {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let sourceCases: [[ModeStatusComparisonSourceMetrics]] = [
            [fixture.comparison.sourceMetrics[0]],
            Array(fixture.comparison.sourceMetrics.reversed()),
            [
                ModeStatusComparisonSourceMetrics(
                    side: .left,
                    source: ModeStatusSourceReference(
                        identity: fixture.sources[0].source.identity,
                        generation: fixture.sources[0].source.generation + 1
                    ),
                    metrics: fixture.sources[0].metrics
                ),
                fixture.comparison.sourceMetrics[1]
            ]
        ]

        for sourceMetrics in sourceCases {
            let comparison = makeComparison(
                inputs: fixture.inputs,
                sourceMetrics: sourceMetrics,
                metrics: fixture.comparison.metrics
            )
            assertStatusError(.invalidLifecycle(.comparisonSourceMismatch)) {
                try ModeStatusWorkflow.project(
                    fixture.snapshot(
                        lifecycle: .current(comparison.reference),
                        comparison: comparison
                    )
                )
            }
        }

        let wrongSourceMode = makeComparison(
            inputs: fixture.inputs,
            sourceMetrics: [
                ModeStatusComparisonSourceMetrics(
                    side: .left,
                    source: fixture.sources[0].source,
                    metrics: sourceMetrics(mode: .webpage, side: .left)
                ),
                fixture.comparison.sourceMetrics[1]
            ],
            metrics: fixture.comparison.metrics
        )
        assertStatusError(.invalidMetrics(.modeMismatch)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .current(wrongSourceMode.reference),
                    comparison: wrongSourceMode
                )
            )
        }

        let wrongComparisonMode = makeComparison(
            inputs: fixture.inputs,
            sourceMetrics: fixture.comparison.sourceMetrics,
            metrics: .webpage(webMetrics())
        )
        assertStatusError(.invalidMetrics(.modeMismatch)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .current(wrongComparisonMode.reference),
                    comparison: wrongComparisonMode
                )
            )
        }
    }

    func testFolderSelectionRequiresMembershipProofBeforeUnsupportedState() {
        let fixture = StatusFixture(mode: .folder, sourceCount: 2)
        let valid = ModeStatusInteraction.folder(
            comparison: fixture.comparison.reference,
            selectedItems: [],
            cursor: nil
        )
        XCTAssertEqual(
            try ModeStatusWorkflow.project(fixture.currentSnapshot(interaction: valid)).interaction,
            valid
        )
        let validItem = ModeStatusItemIdentity(
            comparisonIdentity: fixture.comparison.reference.identity,
            comparisonGeneration: fixture.comparison.reference.generation,
            rawValue: statusUUID(600)
        )
        let wrongGeneration = ModeStatusItemIdentity(
            comparisonIdentity: fixture.comparison.reference.identity,
            comparisonGeneration: fixture.comparison.reference.generation + 1,
            rawValue: statusUUID(601)
        )

        assertInteractionError(
            .unsupportedFolderSelection,
            fixture: fixture,
            interaction: .folder(
                comparison: fixture.comparison.reference,
                selectedItems: [validItem],
                cursor: nil
            )
        )
        assertInteractionError(
            .itemUsesDifferentComparison,
            fixture: fixture,
            interaction: .folder(
                comparison: fixture.comparison.reference,
                selectedItems: [wrongGeneration],
                cursor: nil
            )
        )
        assertInteractionError(
            .duplicateSelectedItem,
            fixture: fixture,
            interaction: .folder(
                comparison: fixture.comparison.reference,
                selectedItems: [validItem, validItem],
                cursor: nil
            )
        )
        assertInteractionError(
            .itemUsesDifferentComparison,
            fixture: fixture,
            interaction: .folder(
                comparison: fixture.comparison.reference,
                selectedItems: [],
                cursor: wrongGeneration
            )
        )
        assertInteractionError(
            .tooManySelectedItems,
            fixture: fixture,
            interaction: .folder(
                comparison: fixture.comparison.reference,
                selectedItems: [validItem],
                cursor: nil
            ),
            limits: statusLimits(maximumSelectedItems: 0)
        )
    }

    func testBinaryInteractionBindsComparisonSideEndpointCursorAndNonemptyRange() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let valid = ModeStatusInteraction.binary(
            comparison: fixture.comparison.reference,
            side: .left,
            cursorByteOffset: 8,
            selection: 0..<8,
            surface: .characters
        )
        let projected = try ModeStatusWorkflow.project(fixture.currentSnapshot(interaction: valid))
        XCTAssertEqual(projected.interaction, valid)

        assertInteractionError(
            .invalidCursor,
            fixture: fixture,
            interaction: .binary(
                comparison: fixture.comparison.reference,
                side: .left,
                cursorByteOffset: 9,
                selection: nil,
                surface: .bytes
            )
        )
        let invalidRanges: [Range<UInt64>] = [4..<4, 0..<9]
        for range in invalidRanges {
            assertInteractionError(
                .invalidSelection,
                fixture: fixture,
                interaction: .binary(
                    comparison: fixture.comparison.reference,
                    side: .left,
                    cursorByteOffset: nil,
                    selection: range,
                    surface: .bytes
                )
            )
        }
        assertInteractionError(
            .unknownSide,
            fixture: fixture,
            interaction: .binary(
                comparison: fixture.comparison.reference,
                side: .middle,
                cursorByteOffset: nil,
                selection: nil,
                surface: .bytes
            )
        )
    }

    func testImageInteractionBindsSelectedPagePixelBoundsAndDifferenceIndex() throws {
        let fixture = StatusFixture(mode: .image, sourceCount: 2)
        let valid = ModeStatusInteraction.image(
            comparison: fixture.comparison.reference,
            side: .left,
            pageIndex: 1,
            cursor: ModeStatusPixelPoint(x: 3, y: 2),
            selectedDifferenceIndex: 1
        )
        XCTAssertEqual(
            try ModeStatusWorkflow.project(fixture.currentSnapshot(interaction: valid)).interaction,
            valid
        )

        assertInteractionError(
            .invalidPage,
            fixture: fixture,
            interaction: .image(
                comparison: fixture.comparison.reference,
                side: .left,
                pageIndex: 0,
                cursor: nil,
                selectedDifferenceIndex: nil
            )
        )
        for point in [ModeStatusPixelPoint(x: -1, y: 0), ModeStatusPixelPoint(x: 4, y: 0)] {
            assertInteractionError(
                .invalidCursor,
                fixture: fixture,
                interaction: .image(
                    comparison: fixture.comparison.reference,
                    side: .left,
                    pageIndex: 1,
                    cursor: point,
                    selectedDifferenceIndex: nil
                )
            )
        }
        for index in [-1, 2] {
            assertInteractionError(
                .invalidDifferenceIndex,
                fixture: fixture,
                interaction: .image(
                    comparison: fixture.comparison.reference,
                    side: .left,
                    pageIndex: 1,
                    cursor: nil,
                    selectedDifferenceIndex: index
                )
            )
        }
    }

    func testWebInteractionBindsNormalizedOffsetsNonemptyRangeAndDifferenceIndex() throws {
        let fixture = StatusFixture(mode: .webpage, sourceCount: 2)
        let valid = ModeStatusInteraction.webpage(
            comparison: fixture.comparison.reference,
            side: .left,
            cursorNormalizedUTF8Offset: 20,
            selectionNormalizedUTF8Range: 1..<20,
            selectedDifferenceIndex: 1
        )
        XCTAssertEqual(
            try ModeStatusWorkflow.project(fixture.currentSnapshot(interaction: valid)).interaction,
            valid
        )

        assertInteractionError(
            .invalidCursor,
            fixture: fixture,
            interaction: .webpage(
                comparison: fixture.comparison.reference,
                side: .left,
                cursorNormalizedUTF8Offset: 21,
                selectionNormalizedUTF8Range: nil,
                selectedDifferenceIndex: nil
            )
        )
        let invalidRanges: [Range<UInt64>] = [5..<5, 0..<21]
        for range in invalidRanges {
            assertInteractionError(
                .invalidSelection,
                fixture: fixture,
                interaction: .webpage(
                    comparison: fixture.comparison.reference,
                    side: .left,
                    cursorNormalizedUTF8Offset: nil,
                    selectionNormalizedUTF8Range: range,
                    selectedDifferenceIndex: nil
                )
            )
        }
        for index in [-1, 2] {
            assertInteractionError(
                .invalidDifferenceIndex,
                fixture: fixture,
                interaction: .webpage(
                    comparison: fixture.comparison.reference,
                    side: .left,
                    cursorNormalizedUTF8Offset: nil,
                    selectionNormalizedUTF8Range: nil,
                    selectedDifferenceIndex: index
                )
            )
        }
    }

    func testInteractionRejectsWrongModeAndExactComparisonReferenceChanges() {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let changedIdentity = ModeStatusComparisonReference(
            identity: ModeStatusComparisonIdentity(rawValue: statusUUID(700)),
            generation: fixture.comparison.reference.generation,
            inputs: fixture.inputs
        )
        let changedGeneration = ModeStatusComparisonReference(
            identity: fixture.comparison.reference.identity,
            generation: fixture.comparison.reference.generation + 1,
            inputs: fixture.inputs
        )
        for reference in [changedIdentity, changedGeneration] {
            assertInteractionError(
                .comparisonReferenceMismatch,
                fixture: fixture,
                interaction: .binary(
                    comparison: reference,
                    side: .left,
                    cursorByteOffset: nil,
                    selection: nil,
                    surface: .bytes
                )
            )
        }

        assertInteractionError(
            .modeMismatch,
            fixture: fixture,
            interaction: .image(
                comparison: fixture.comparison.reference,
                side: .left,
                pageIndex: 0,
                cursor: nil,
                selectedDifferenceIndex: nil
            )
        )
    }

    func testLifecycleRequiresExactInputsComparisonAndOperationContracts() {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let changedInputs = makeInput(
            mode: .binary,
            sourceCount: 2,
            identity: ModeStatusInputIdentity(rawValue: statusUUID(710)),
            generation: fixture.inputs.generation
        )
        let wrongInputOperation = makeOperation(kind: .initialLoad, inputs: changedInputs)
        assertStatusError(.invalidLifecycle(.inputMismatch)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(lifecycle: .loading(wrongInputOperation), comparison: nil)
            )
        }

        assertStatusError(.invalidLifecycle(.comparisonMissing)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .current(fixture.comparison.reference),
                    comparison: nil
                )
            )
        }
        assertStatusError(.invalidLifecycle(.unexpectedComparison)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .loading(makeOperation(kind: .initialLoad, inputs: fixture.inputs)),
                    comparison: fixture.comparison
                )
            )
        }

        let changedReference = ModeStatusComparisonReference(
            identity: fixture.comparison.reference.identity,
            generation: fixture.comparison.reference.generation + 1,
            inputs: fixture.inputs
        )
        assertStatusError(.invalidLifecycle(.comparisonReferenceMismatch)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .current(changedReference),
                    comparison: fixture.comparison
                )
            )
        }

        let refreshWithoutResult = makeOperation(kind: .refresh, inputs: fixture.inputs)
        let loadWithResult = makeOperation(
            kind: .initialLoad,
            inputs: fixture.inputs,
            retainedComparison: fixture.comparison.reference
        )
        for operation in [refreshWithoutResult, loadWithResult] {
            assertStatusError(.invalidLifecycle(.invalidOperation)) {
                try ModeStatusWorkflow.project(
                    fixture.snapshot(lifecycle: .loading(operation), comparison: nil)
                )
            }
        }

        let validRefresh = makeOperation(
            kind: .refresh,
            inputs: fixture.inputs,
            retainedComparison: fixture.comparison.reference
        )
        assertStatusError(.invalidLifecycle(.invalidOperation)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .loading(validRefresh),
                    comparison: fixture.comparison
                )
            )
        }
        let validInitialLoad = makeOperation(kind: .initialLoad, inputs: fixture.inputs)
        assertStatusError(.invalidLifecycle(.invalidOperation)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .refreshing(validInitialLoad),
                    comparison: nil
                )
            )
        }

        let oldInputs = oldInputs(for: fixture, reason: .sourceChanged(.left))
        let oldComparison = makeComparison(inputs: oldInputs)
        assertStatusError(.invalidLifecycle(.currentResultUsesDifferentInputs)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .current(oldComparison.reference),
                    comparison: oldComparison
                )
            )
        }
    }

    func testProgressTerminalStagesAndFailureSideAreValidatedExactly() throws {
        XCTAssertNil(ModeStatusProgress(stage: .preparing, completedUnits: 0).fractionCompleted)
        XCTAssertNil(
            ModeStatusProgress(stage: .preparing, completedUnits: 0, totalUnits: 0)
                .fractionCompleted
        )
        XCTAssertEqual(
            ModeStatusProgress(stage: .comparing, completedUnits: 1, totalUnits: 4)
                .fractionCompleted,
            0.25
        )
        XCTAssertEqual(
            ModeStatusProgress(
                stage: .comparing,
                completedUnits: UInt64.max - 1,
                totalUnits: UInt64.max
            ).fractionCompleted,
            Double(1).nextDown
        )
        XCTAssertEqual(
            ModeStatusProgress(stage: .publishing, completedUnits: 5, totalUnits: 5)
                .fractionCompleted,
            1
        )

        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let invalidProgress = [
            ModeStatusProgress(stage: .comparing, completedUnits: 1, totalUnits: 0),
            ModeStatusProgress(stage: .comparing, completedUnits: 3, totalUnits: 2),
            ModeStatusProgress(stage: .comparing, completedUnits: 6, totalUnits: 6),
            ModeStatusProgress(stage: .comparing, completedUnits: 6, totalUnits: nil)
        ]
        for progress in invalidProgress {
            let operation = makeOperation(
                kind: .initialLoad,
                inputs: fixture.inputs,
                declaredWorkUnits: 5,
                progress: progress
            )
            assertStatusError(.invalidLifecycle(.invalidProgress)) {
                try ModeStatusWorkflow.project(
                    fixture.snapshot(lifecycle: .loading(operation), comparison: nil)
                )
            }
        }

        let indeterminate = makeOperation(
            kind: .initialLoad,
            inputs: fixture.inputs,
            declaredWorkUnits: 5,
            progress: ModeStatusProgress(
                stage: .loadingInputs,
                completedUnits: 5,
                totalUnits: nil
            )
        )
        let indeterminateProjection = try ModeStatusWorkflow.project(
            fixture.snapshot(lifecycle: .loading(indeterminate), comparison: nil)
        )
        XCTAssertEqual(indeterminateProjection.operation?.progress, indeterminate.progress)
        XCTAssertNil(indeterminateProjection.operation?.progress.fractionCompleted)

        let operation = makeOperation(
            kind: .initialLoad,
            inputs: fixture.inputs,
            stage: .projecting
        )
        assertStatusError(.invalidLifecycle(.terminalStagePrecedesProgress)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .failed(
                        operation,
                        failure: ModeStatusFailure(kind: .readFailed, stage: .comparing)
                    ),
                    comparison: nil
                )
            )
        }
        assertStatusError(.invalidLifecycle(.terminalStagePrecedesProgress)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .cancelled(
                        operation,
                        cancellation: ModeStatusCancellation(
                            reason: .userRequested,
                            stage: .comparing
                        )
                    ),
                    comparison: nil
                )
            )
        }
        assertStatusError(.invalidLifecycle(.invalidFailureSide)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .failed(
                        operation,
                        failure: ModeStatusFailure(
                            kind: .readFailed,
                            stage: .publishing,
                            side: .middle
                        )
                    ),
                    comparison: nil
                )
            )
        }

        let equalStageFailure = ModeStatusFailure(kind: .comparisonFailed, stage: .projecting)
        XCTAssertEqual(
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .failed(operation, failure: equalStageFailure),
                    comparison: nil
                )
            ).failure,
            equalStageFailure
        )
        let equalStageCancellation = ModeStatusCancellation(
            reason: .userRequested,
            stage: .projecting
        )
        XCTAssertEqual(
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .cancelled(operation, cancellation: equalStageCancellation),
                    comparison: nil
                )
            ).cancellation,
            equalStageCancellation
        )
    }

    func testEveryStaleReasonRequiresItsSpecificInputChangeAndExternalEvidence() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let validReasons: [ModeStatusStaleReason] = [
            .sourceChanged(.left),
            .optionsChanged,
            .externalChange(.left),
            .modeChanged
        ]
        for reason in validReasons {
            let stale = staleComparison(for: fixture, reason: reason)
            let projection = try ModeStatusWorkflow.project(stale.snapshot)
            XCTAssertEqual(projection.phase, .stale)
            XCTAssertEqual(projection.staleReason, reason)
            XCTAssertFalse(projection.isResultCurrent)
        }

        assertStatusError(.invalidLifecycle(.staleResultUsesCurrentInputs)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .stale(
                        fixture.comparison.reference,
                        reason: .sourceChanged(.left)
                    ),
                    comparison: fixture.comparison
                )
            )
        }

        let oldOptions = oldInputs(for: fixture, reason: .optionsChanged)
        let oldOptionsComparison = makeComparison(inputs: oldOptions)
        for reason in [ModeStatusStaleReason.sourceChanged(.left), .externalChange(.left), .modeChanged] {
            assertStatusError(.invalidLifecycle(.invalidStaleReason)) {
                try ModeStatusWorkflow.project(
                    fixture.snapshot(
                        lifecycle: .stale(oldOptionsComparison.reference, reason: reason),
                        comparison: oldOptionsComparison
                    )
                )
            }
        }

        let oldSource = oldInputs(for: fixture, reason: .sourceChanged(.left))
        let oldSourceComparison = makeComparison(inputs: oldSource)
        assertStatusError(.invalidLifecycle(.invalidStaleReason)) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .stale(
                        oldSourceComparison.reference,
                        reason: .externalChange(.left)
                    ),
                    comparison: oldSourceComparison
                )
            )
        }

        for externalChange in [
            ModeStatusExternalChangeState.missing,
            .inaccessible
        ] {
            let stale = staleComparison(
                for: fixture,
                reason: .externalChange(.left),
                externalChange: externalChange
            )
            let projection = try ModeStatusWorkflow.project(stale.snapshot)
            XCTAssertEqual(projection.phase, .stale)
            XCTAssertEqual(projection.staleReason, .externalChange(.left))
            XCTAssertEqual(projection.sources[0].externalChange, externalChange)
            XCTAssertFalse(projection.isResultCurrent)
        }
    }

    func testProjectionCurrentValidationDistinguishesIdentityGenerationAndSameEnvelopeMutation() throws {
        let fixture = StatusFixture(mode: .webpage, sourceCount: 2)
        let snapshot = fixture.currentSnapshot()
        let projection = try ModeStatusWorkflow.project(snapshot)
        XCTAssertNoThrow(try projection.validateCurrent(snapshot: snapshot))
        XCTAssertNoThrow(try ModeStatusWorkflow.validateCurrent(projection, snapshot: snapshot))
        XCTAssertTrue(try projection.isCurrent(snapshot: snapshot))

        let changedIdentity = fixture.snapshot(
            identity: ModeStatusSnapshotIdentity(rawValue: statusUUID(800)),
            lifecycle: .current(fixture.comparison.reference),
            comparison: fixture.comparison
        )
        assertStatusError(.staleSnapshotIdentity) {
            try projection.validateCurrent(snapshot: changedIdentity)
        }
        XCTAssertFalse(try projection.isCurrent(snapshot: changedIdentity))

        let changedGeneration = fixture.snapshot(
            generation: snapshot.generation + 1,
            lifecycle: .current(fixture.comparison.reference),
            comparison: fixture.comparison
        )
        assertStatusError(
            .staleSnapshotGeneration(
                expected: snapshot.generation,
                actual: snapshot.generation + 1
            )
        ) {
            try projection.validateCurrent(snapshot: changedGeneration)
        }
        XCTAssertFalse(try projection.isCurrent(snapshot: changedGeneration))

        let changedSource = replacingSourceState(fixture.sources[0], isReadOnly: true)
        let changedContents = fixture.snapshot(
            sources: [changedSource, fixture.sources[1]],
            lifecycle: .current(fixture.comparison.reference),
            comparison: fixture.comparison
        )
        assertStatusError(.snapshotContentsChanged) {
            try projection.validateCurrent(snapshot: changedContents)
        }
        XCTAssertFalse(try projection.isCurrent(snapshot: changedContents))
    }

    func testIsCurrentPropagatesInvalidSnapshotErrors() throws {
        let fixture = StatusFixture(mode: .webpage, sourceCount: 2)
        let snapshot = fixture.currentSnapshot()
        let projection = try ModeStatusWorkflow.project(snapshot)
        let invalidSource = replacingSourceState(
            fixture.sources[0],
            metrics: sourceMetrics(mode: .binary, side: .left)
        )
        let invalidSnapshot = fixture.snapshot(
            sources: [invalidSource, fixture.sources[1]],
            lifecycle: .current(fixture.comparison.reference),
            comparison: fixture.comparison
        )

        assertStatusError(.sourceModeMismatch(.left)) {
            try projection.isCurrent(snapshot: invalidSnapshot)
        }
    }

    func testEachIndependentCurrentFieldMutationInvalidatesProjection() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let snapshot = fixture.currentSnapshot()
        let projection = try ModeStatusWorkflow.project(snapshot)
        let changedInteraction = ModeStatusInteraction.binary(
            comparison: fixture.comparison.reference,
            side: .left,
            cursorByteOffset: 1,
            selection: nil,
            surface: .bytes
        )
        let mutations: [ModeStatusSnapshot] = [
            fixture.snapshot(
                sources: [
                    replacingSourceState(fixture.sources[0], isReadOnly: true),
                    fixture.sources[1]
                ],
                lifecycle: .current(fixture.comparison.reference),
                comparison: fixture.comparison
            ),
            fixture.snapshot(
                sources: [
                    replacingSourceState(fixture.sources[0], isDirty: false),
                    fixture.sources[1]
                ],
                lifecycle: .current(fixture.comparison.reference),
                comparison: fixture.comparison
            ),
            fixture.snapshot(
                sources: [
                    replacingSourceState(fixture.sources[0], externalChange: .changed),
                    fixture.sources[1]
                ],
                lifecycle: .current(fixture.comparison.reference),
                comparison: fixture.comparison
            ),
            fixture.currentSnapshot(interaction: changedInteraction)
        ]

        for mutation in mutations {
            XCTAssertFalse(try projection.isCurrent(snapshot: mutation))
        }
    }

    func testReceiptSchemaDomainGoldenDigestAndDeterminism() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let snapshot = fixture.currentSnapshot(
            interaction: .binary(
                comparison: fixture.comparison.reference,
                side: .right,
                cursorByteOffset: 10,
                selection: 2..<7,
                surface: .characters
            )
        )
        let first = try ModeStatusWorkflow.project(snapshot)
        let second = try ModeStatusWorkflow.project(snapshot)

        XCTAssertEqual(
            ModeStatusProjectionReceipt.canonicalDomainIdentifier,
            "com.macmerge.mode-status-projection"
        )
        XCTAssertEqual(ModeStatusProjectionReceipt.currentCanonicalSchemaVersion, 1)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.receipt.canonicalDomain, "com.macmerge.mode-status-projection")
        XCTAssertEqual(first.receipt.canonicalSchemaVersion, 1)
        XCTAssertEqual(first.receipt.snapshot, snapshot.reference)
        XCTAssertEqual(first.receipt.comparison, fixture.comparison.reference)
        XCTAssertEqual(first.receipt.canonicalSHA256.count, 32)
        XCTAssertEqual(first.receipt.canonicalByteCount, 761)
        XCTAssertEqual(first.receipt.workUnitsConsumed, 1_530)
        XCTAssertEqual(
            hex(first.receipt.canonicalSHA256),
            "513b879b4a1e2239fa0e757e228e0b01991f631edad9a24e6662b70a5db1e5c1"
        )
    }

    func testReceiptCommitsEveryIdentityGenerationStateAndLimitField() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let baseline = fixture.currentSnapshot()
        let baselineReceipt = try ModeStatusWorkflow.project(baseline).receipt
        let changedSource = replacingSourceState(fixture.sources[0], isReadOnly: true)
        let snapshots = [
            fixture.snapshot(
                generation: baseline.generation + 1,
                lifecycle: .current(fixture.comparison.reference),
                comparison: fixture.comparison
            ),
            fixture.snapshot(
                sources: [changedSource, fixture.sources[1]],
                lifecycle: .current(fixture.comparison.reference),
                comparison: fixture.comparison
            )
        ]
        for changed in snapshots {
            XCTAssertNotEqual(
                try ModeStatusWorkflow.project(changed).receipt.canonicalSHA256,
                baselineReceipt.canonicalSHA256
            )
        }

        let changedLimitValues = [
            statusLimits(maximumSelectedItems: ModeStatusLimits.default.maximumSelectedItems - 1),
            statusLimits(maximumMetricValue: ModeStatusLimits.default.maximumMetricValue - 1),
            statusLimits(maximumPixelCount: ModeStatusLimits.default.maximumPixelCount - 1),
            statusLimits(
                maximumDeclaredWorkUnits:
                    ModeStatusLimits.default.maximumDeclaredWorkUnits - 1
            ),
            statusLimits(
                maximumCanonicalBytes: ModeStatusLimits.default.maximumCanonicalBytes - 1
            ),
            statusLimits(maximumWorkUnits: ModeStatusLimits.default.maximumWorkUnits - 1),
            statusLimits(
                cancellationCheckInterval:
                    ModeStatusLimits.default.cancellationCheckInterval - 1
            )
        ]
        for limits in changedLimitValues {
            let changedReceipt = try ModeStatusWorkflow.project(baseline, limits: limits).receipt
            XCTAssertNotEqual(changedReceipt.canonicalSHA256, baselineReceipt.canonicalSHA256)
        }
    }

    func testEveryLimitAcceptsHardBoundaryAndRejectsIndependentInvalidValues() throws {
        let snapshot = StatusFixture(mode: .binary, sourceCount: 2).currentSnapshot()
        let zeroMinimums = statusLimits(
            maximumSelectedItems: 0,
            maximumMetricValue: 0,
            maximumPixelCount: 1,
            maximumDeclaredWorkUnits: 0,
            maximumCanonicalBytes: ModeStatusLimits.default.maximumCanonicalBytes,
            maximumWorkUnits: ModeStatusLimits.default.maximumWorkUnits,
            cancellationCheckInterval: 1
        )
        let zeroFixture = StatusFixture(mode: .binary, sourceCount: 2)
        let zeroComparison = makeComparison(
            inputs: zeroFixture.inputs,
            sourceMetrics: zeroFixture.comparison.sourceMetrics.map { source in
                ModeStatusComparisonSourceMetrics(
                    side: source.side,
                    source: source.source,
                    metrics: .binary(ModeStatusBinarySourceMetrics(byteCount: 0))
                )
            },
            metrics: .binary(binaryMetrics(aligned: 0, regions: 0, differing: 0))
        )
        let zeroSources = zeroFixture.sources.map {
            replacingSourceState($0, metrics: .binary(ModeStatusBinarySourceMetrics(byteCount: 0)))
        }
        let zeroProjection = try ModeStatusWorkflow.project(
            zeroFixture.snapshot(
                sources: zeroSources,
                lifecycle: .current(zeroComparison.reference),
                comparison: zeroComparison
            ),
            limits: zeroMinimums
        )
        XCTAssertEqual(zeroProjection.limits.maximumSelectedItems, 0)
        XCTAssertEqual(zeroProjection.limits.maximumMetricValue, 0)
        XCTAssertEqual(zeroProjection.limits.maximumDeclaredWorkUnits, 0)

        let hard = ModeStatusLimits(
            maximumSelectedItems: ModeStatusLimits.hardMaximumSelectedItems,
            maximumMetricValue: ModeStatusLimits.hardMaximumMetricValue,
            maximumPixelCount: ModeStatusLimits.hardMaximumPixelCount,
            maximumDeclaredWorkUnits: ModeStatusLimits.hardMaximumDeclaredWorkUnits,
            maximumCanonicalBytes: ModeStatusLimits.hardMaximumCanonicalBytes,
            maximumWorkUnits: ModeStatusLimits.hardMaximumWorkUnits,
            cancellationCheckInterval: ModeStatusLimits.hardMaximumCancellationCheckInterval
        )
        XCTAssertNoThrow(try ModeStatusWorkflow.project(snapshot, limits: hard))

        let invalid: [(ModeStatusLimits, ModeStatusLimit)] = [
            (statusLimits(maximumSelectedItems: -1), .selectedItems),
            (
                statusLimits(
                    maximumSelectedItems: ModeStatusLimits.hardMaximumSelectedItems + 1
                ),
                .selectedItems
            ),
            (
                statusLimits(
                    maximumMetricValue: ModeStatusLimits.hardMaximumMetricValue + 1
                ),
                .metricValue
            ),
            (statusLimits(maximumPixelCount: 0), .pixelCount),
            (
                statusLimits(maximumPixelCount: ModeStatusLimits.hardMaximumPixelCount + 1),
                .pixelCount
            ),
            (
                statusLimits(
                    maximumDeclaredWorkUnits:
                        ModeStatusLimits.hardMaximumDeclaredWorkUnits + 1
                ),
                .declaredWorkUnits
            ),
            (statusLimits(maximumCanonicalBytes: 0), .canonicalBytes),
            (
                statusLimits(
                    maximumCanonicalBytes: ModeStatusLimits.hardMaximumCanonicalBytes + 1
                ),
                .canonicalBytes
            ),
            (statusLimits(maximumWorkUnits: 0), .workUnits),
            (
                statusLimits(maximumWorkUnits: ModeStatusLimits.hardMaximumWorkUnits + 1),
                .workUnits
            ),
            (statusLimits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (
                statusLimits(
                    cancellationCheckInterval:
                        ModeStatusLimits.hardMaximumCancellationCheckInterval + 1
                ),
                .cancellationCheckInterval
            )
        ]
        for (limits, expected) in invalid {
            assertStatusError(.invalidLimit(expected)) {
                try ModeStatusWorkflow.project(snapshot, limits: limits)
            }
        }
    }

    func testDeclaredCanonicalAndWorkLimitsAcceptExactAndRejectOneUnderOrOver() throws {
        let fixture = StatusFixture(mode: .binary, sourceCount: 2)
        let operation = makeOperation(
            kind: .initialLoad,
            inputs: fixture.inputs,
            declaredWorkUnits: 10,
            progress: ModeStatusProgress(
                stage: .loadingInputs,
                completedUnits: 10,
                totalUnits: 10
            )
        )
        let loading = fixture.snapshot(lifecycle: .loading(operation), comparison: nil)
        XCTAssertNoThrow(
            try ModeStatusWorkflow.project(
                loading,
                limits: statusLimits(maximumDeclaredWorkUnits: 10)
            )
        )
        assertStatusError(.declaredWorkLimitExceeded) {
            try ModeStatusWorkflow.project(
                loading,
                limits: statusLimits(maximumDeclaredWorkUnits: 9)
            )
        }

        let baseline = try ModeStatusWorkflow.project(fixture.currentSnapshot())
        XCTAssertEqual(baseline.receipt.canonicalByteCount, 626)
        XCTAssertEqual(baseline.receipt.workUnitsConsumed, 1_260)
        XCTAssertNoThrow(
            try ModeStatusWorkflow.project(
                fixture.currentSnapshot(),
                limits: statusLimits(
                    maximumCanonicalBytes: 626,
                    maximumWorkUnits: 1_260
                )
            )
        )
        assertStatusError(.canonicalRepresentationTooLarge) {
            try ModeStatusWorkflow.project(
                fixture.currentSnapshot(),
                limits: statusLimits(maximumCanonicalBytes: 625)
            )
        }
        assertStatusError(.workLimitExceeded) {
            try ModeStatusWorkflow.project(
                fixture.currentSnapshot(),
                limits: statusLimits(maximumWorkUnits: 1_259)
            )
        }
    }

    func testWorkAccountingIsDeterministicAcrossCancellationCadences() throws {
        let snapshot = StatusFixture(mode: .webpage, sourceCount: 3).currentSnapshot()
        let one = try ModeStatusWorkflow.project(
            snapshot,
            limits: statusLimits(cancellationCheckInterval: 1)
        )
        let defaultCadence = try ModeStatusWorkflow.project(snapshot)
        let maximum = try ModeStatusWorkflow.project(
            snapshot,
            limits: statusLimits(
                cancellationCheckInterval: ModeStatusLimits.hardMaximumCancellationCheckInterval
            )
        )

        XCTAssertEqual(one.receipt.workUnitsConsumed, defaultCadence.receipt.workUnitsConsumed)
        XCTAssertEqual(maximum.receipt.workUnitsConsumed, defaultCadence.receipt.workUnitsConsumed)
        XCTAssertGreaterThan(defaultCadence.receipt.workUnitsConsumed, 0)
        XCTAssertNotEqual(one.receipt.canonicalSHA256, defaultCadence.receipt.canonicalSHA256)
        XCTAssertNotEqual(maximum.receipt.canonicalSHA256, defaultCadence.receipt.canonicalSHA256)
    }

    func testProjectAndValidationHonorDefaultTaskCancellation() async throws {
        let snapshot = StatusFixture(mode: .webpage, sourceCount: 3).currentSnapshot()
        let projection = try ModeStatusWorkflow.project(snapshot)
        let projectTask = Task.detached { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ModeStatusWorkflow.project(snapshot)
        }
        await assertCancelled(projectTask)

        let validationTask = Task.detached { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try projection.validateCurrent(snapshot: snapshot)
        }
        await assertCancelled(validationTask)
    }

    func testPublicValuesAreSendableHashableValueTypesAndRedactSourceDetails() async throws {
        let fixture = StatusFixture(mode: .image, sourceCount: 3)
        let snapshot = fixture.currentSnapshot()
        let localProjection = try ModeStatusWorkflow.project(snapshot)
        let projection = try await Task.detached { @Sendable in
            try ModeStatusWorkflow.project(snapshot)
        }.value

        requireSendable(snapshot)
        requireSendable(projection)
        requireSendable(projection.receipt)
        requireSendable(ModeStatusWorkflowError.cancelled)
        XCTAssertEqual(localProjection, projection)
        XCTAssertEqual(Set([localProjection, projection]).count, 1)
        XCTAssertEqual(Mirror(reflecting: fixture.sources[0].source.identity).children.count, 1)
        XCTAssertEqual(
            Mirror(reflecting: fixture.sources[0].source.identity).children.first?.label,
            "rawValue"
        )

        let sensitiveLabels = ["path", "url", "displayname", "secret", "diagnostic"]
        let labels = recursiveMirrorLabels(of: fixture.sources[0])
        for sensitive in sensitiveLabels {
            XCTAssertFalse(labels.contains { $0.lowercased().contains(sensitive) })
        }
        XCTAssertEqual(
            recursiveStringValues(of: projection),
            [ModeStatusProjectionReceipt.canonicalDomainIdentifier]
        )

        let descriptions: [(ModeStatusWorkflowError, String)] = [
            (.cancelled, "Mode status projection was cancelled."),
            (.invalidLimit(.metricValue), "Mode status limits are invalid."),
            (.invalidSourceLayout, "Mode status source layout is invalid."),
            (.duplicateSourceSide(.left), "Mode status source layout is invalid."),
            (.sourceOrderIsNotCanonical, "Mode status source layout is invalid."),
            (
                .sourceReferenceMismatch(.left),
                "Mode status source identity or generation is inconsistent."
            ),
            (.sourceModeMismatch(.right), "Mode status source metrics do not match comparison mode."),
            (
                .invalidExternalChangeState(.middle),
                "Mode status external-change state is inconsistent."
            ),
            (.invalidMetrics(.aggregateMismatch), "Mode status comparison metrics are inconsistent."),
            (
                .invalidInteraction(.invalidSelection),
                "Mode status selection or cursor state is inconsistent."
            ),
            (
                .invalidLifecycle(.comparisonReferenceMismatch),
                "Mode status lifecycle state is inconsistent."
            ),
            (.metricLimitExceeded(.pixelCount), "Mode status metrics exceed configured limits."),
            (.declaredWorkLimitExceeded, "Mode status operation exceeds configured work limits."),
            (
                .canonicalRepresentationTooLarge,
                "Mode status canonical representation exceeds configured limits."
            ),
            (.workLimitExceeded, "Mode status projection exceeds configured work limits."),
            (.staleSnapshotIdentity, "Mode status projection belongs to another snapshot."),
            (
                .staleSnapshotGeneration(expected: 41, actual: 42),
                "Mode status projection generation is stale."
            ),
            (.snapshotContentsChanged, "Mode status snapshot changed without advancing generation.")
        ]
        for (error, expected) in descriptions {
            XCTAssertEqual(try XCTUnwrap(error.errorDescription), expected)
        }
    }

    private func assertComparisonMetricsError(
        _ issue: ModeStatusMetricsIssue,
        fixture: StatusFixture,
        metrics: ModeStatusComparisonMetrics,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let comparison = makeComparison(inputs: fixture.inputs, metrics: metrics)
        assertStatusError(.invalidMetrics(issue), file: file, line: line) {
            try ModeStatusWorkflow.project(
                fixture.snapshot(
                    lifecycle: .current(comparison.reference),
                    comparison: comparison
                )
            )
        }
    }

    private func assertInteractionError(
        _ issue: ModeStatusInteractionIssue,
        fixture: StatusFixture,
        interaction: ModeStatusInteraction,
        limits: ModeStatusLimits = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertStatusError(.invalidInteraction(issue), file: file, line: line) {
            try ModeStatusWorkflow.project(
                fixture.currentSnapshot(interaction: interaction),
                limits: limits
            )
        }
    }

    private func assertStatusError<T>(
        _ expected: ModeStatusWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ModeStatusWorkflowError, expected, file: file, line: line)
        }
    }

    private func assertCancelled<T: Sendable>(
        _ task: Task<T, any Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled operation unexpectedly succeeded", file: file, line: line)
        } catch let error as ModeStatusWorkflowError {
            XCTAssertEqual(error, .cancelled, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }
}

private struct StatusFixture: Sendable {
    let mode: ModeStatusMode
    let inputs: ModeStatusInputReference
    let sources: [ModeStatusSourceState]
    let comparison: ModeStatusComparisonSnapshot

    init(mode: ModeStatusMode, sourceCount: Int) {
        self.mode = mode
        inputs = makeInput(mode: mode, sourceCount: sourceCount)
        sources = makeSourceStates(for: inputs)
        comparison = makeComparison(
            inputs: inputs,
            sourceMetrics: makeComparisonSourceMetrics(from: sources)
        )
    }

    func currentSnapshot(
        interaction: ModeStatusInteraction = .none
    ) -> ModeStatusSnapshot {
        snapshot(
            lifecycle: .current(comparison.reference),
            comparison: comparison,
            interaction: interaction
        )
    }

    func snapshot(
        identity: ModeStatusSnapshotIdentity = ModeStatusSnapshotIdentity(
            rawValue: statusUUID(500)
        ),
        generation: UInt64 = 7,
        sources: [ModeStatusSourceState]? = nil,
        lifecycle: ModeStatusLifecycle,
        comparison: ModeStatusComparisonSnapshot?,
        interaction: ModeStatusInteraction = .none
    ) -> ModeStatusSnapshot {
        ModeStatusSnapshot(
            identity: identity,
            generation: generation,
            mode: mode,
            inputs: inputs,
            sources: sources ?? self.sources,
            lifecycle: lifecycle,
            comparison: comparison,
            interaction: interaction
        )
    }
}

private func statusUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
}

private func canonicalSides(_ sourceCount: Int) -> [ModeStatusSide] {
    sourceCount == 2 ? [.left, .right] : [.left, .middle, .right]
}

private func makeInput(
    mode: ModeStatusMode,
    sourceCount: Int,
    identity: ModeStatusInputIdentity? = nil,
    generation: UInt64 = 3
) -> ModeStatusInputReference {
    makeInput(
        mode: mode,
        sides: canonicalSides(sourceCount),
        identity: identity,
        generation: generation
    )
}

private func makeInput(
    mode: ModeStatusMode,
    sides: [ModeStatusSide],
    identity: ModeStatusInputIdentity? = nil,
    generation: UInt64 = 3,
    references: [ModeStatusSourceReference]? = nil
) -> ModeStatusInputReference {
    let modeOffset = Int(mode.rawValue) * 20
    let inputSources = sides.enumerated().map { index, side in
        let reference =
            references?[index]
            ?? ModeStatusSourceReference(
                identity: ModeStatusSourceIdentity(
                    rawValue: statusUUID(100 + modeOffset + index)
                ),
                generation: UInt64(10 + index)
            )
        return ModeStatusInputSource(side: side, source: reference)
    }
    return ModeStatusInputReference(
        identity: identity
            ?? ModeStatusInputIdentity(rawValue: statusUUID(200 + Int(mode.rawValue))),
        generation: generation,
        mode: mode,
        sources: inputSources
    )
}

private func sourceMetrics(
    mode: ModeStatusMode,
    side: ModeStatusSide
) -> ModeStatusSourceMetrics {
    switch mode {
    case .folder:
        return .folder(ModeStatusFolderSourceMetrics(entryCount: side == .left ? 10 : 12))
    case .binary:
        let counts: [ModeStatusSide: UInt64] = [.left: 8, .middle: 9, .right: 10]
        return .binary(ModeStatusBinarySourceMetrics(byteCount: counts[side]!))
    case .image:
        let dimensions: [ModeStatusSide: (Int, Int)] = [
            .left: (4, 3), .middle: (5, 4), .right: (6, 5)
        ]
        let dimensionsForSide = dimensions[side]!
        return .image(
            ModeStatusImageSourceMetrics(
                selectedPageIndex: 1,
                pageCount: 3,
                width: dimensionsForSide.0,
                height: dimensionsForSide.1,
                bitsPerPixel: 32,
                isVector: side == .middle
            )
        )
    case .webpage:
        let offset = UInt64(side.rawValue) * 4
        return .webpage(
            ModeStatusWebPageSourceMetrics(
                sourceUTF8ByteCount: 30 + offset,
                normalizedUTF8ByteCount: 20 + offset,
                tokenCount: 8 + offset,
                attributeCount: 3 + offset,
                comparisonLineCount: 4 + offset
            )
        )
    }
}

private func boundedSourceMetrics(mode: ModeStatusMode) -> ModeStatusSourceMetrics {
    switch mode {
    case .folder:
        .folder(ModeStatusFolderSourceMetrics(entryCount: 1))
    case .binary:
        .binary(ModeStatusBinarySourceMetrics(byteCount: 1))
    case .image:
        .image(
            ModeStatusImageSourceMetrics(
                selectedPageIndex: 0,
                pageCount: 1,
                width: 1,
                height: 1,
                bitsPerPixel: 1
            )
        )
    case .webpage:
        .webpage(
            ModeStatusWebPageSourceMetrics(
                sourceUTF8ByteCount: 1,
                normalizedUTF8ByteCount: 1,
                tokenCount: 1,
                attributeCount: 1,
                comparisonLineCount: 1
            )
        )
    }
}

private func makeSourceStates(
    for inputs: ModeStatusInputReference,
    metrics overrides: [ModeStatusSide: ModeStatusSourceMetrics] = [:]
) -> [ModeStatusSourceState] {
    inputs.sources.map { input in
        ModeStatusSourceState(
            side: input.side,
            source: input.source,
            metrics: overrides[input.side] ?? sourceMetrics(mode: inputs.mode, side: input.side),
            isReadOnly: input.side == .right,
            isDirty: input.side == .left,
            isPersisted: true,
            externalChange: .unchanged
        )
    }
}

private func replacingSourceState(
    _ source: ModeStatusSourceState,
    metrics: ModeStatusSourceMetrics? = nil,
    isReadOnly: Bool? = nil,
    isDirty: Bool? = nil,
    isPersisted: Bool? = nil,
    externalChange: ModeStatusExternalChangeState? = nil
) -> ModeStatusSourceState {
    ModeStatusSourceState(
        side: source.side,
        source: source.source,
        metrics: metrics ?? source.metrics,
        isReadOnly: isReadOnly ?? source.isReadOnly,
        isDirty: isDirty ?? source.isDirty,
        isPersisted: isPersisted ?? source.isPersisted,
        externalChange: externalChange ?? source.externalChange
    )
}

private func makeComparisonSourceMetrics(
    from sources: [ModeStatusSourceState]
) -> [ModeStatusComparisonSourceMetrics] {
    sources.map {
        ModeStatusComparisonSourceMetrics(
            side: $0.side,
            source: $0.source,
            metrics: $0.metrics
        )
    }
}

private func makeComparisonMetrics(
    mode: ModeStatusMode,
    sourceCount: Int
) -> ModeStatusComparisonMetrics {
    switch mode {
    case .folder:
        return .folder(folderMetrics())
    case .binary:
        return .binary(binaryMetrics(conflicts: sourceCount == 3 ? 1 : 0))
    case .image:
        return .image(
            imageMetrics(
                canvasWidth: sourceCount == 3 ? 6 : 6,
                canvasHeight: sourceCount == 3 ? 5 : 5,
                conflicts: sourceCount == 3 ? 1 : 0,
                conflicting: sourceCount == 3 ? 2 : 0
            )
        )
    case .webpage:
        return .webpage(webMetrics(conflicts: sourceCount == 3 ? 1 : 0))
    }
}

private func makeComparison(
    inputs: ModeStatusInputReference,
    identity: ModeStatusComparisonIdentity = ModeStatusComparisonIdentity(
        rawValue: statusUUID(300)
    ),
    generation: UInt64 = 5,
    sourceMetrics: [ModeStatusComparisonSourceMetrics]? = nil,
    metrics: ModeStatusComparisonMetrics? = nil
) -> ModeStatusComparisonSnapshot {
    let resolvedSourceMetrics =
        sourceMetrics
        ?? makeComparisonSourceMetrics(from: makeSourceStates(for: inputs))
    let reference = ModeStatusComparisonReference(
        identity: identity,
        generation: generation,
        inputs: inputs
    )
    return ModeStatusComparisonSnapshot(
        reference: reference,
        sourceMetrics: resolvedSourceMetrics,
        metrics: metrics ?? makeComparisonMetrics(mode: inputs.mode, sourceCount: inputs.sources.count)
    )
}

private func rawSnapshot(
    mode: ModeStatusMode,
    inputs: ModeStatusInputReference,
    sources: [ModeStatusSourceState],
    lifecycle: ModeStatusLifecycle? = nil,
    comparison: ModeStatusComparisonSnapshot? = nil,
    interaction: ModeStatusInteraction = .none
) -> ModeStatusSnapshot {
    let operation = makeOperation(kind: .initialLoad, inputs: inputs)
    return ModeStatusSnapshot(
        identity: ModeStatusSnapshotIdentity(rawValue: statusUUID(500)),
        generation: 7,
        mode: mode,
        inputs: inputs,
        sources: sources,
        lifecycle: lifecycle ?? .loading(operation),
        comparison: comparison,
        interaction: interaction
    )
}

private func makeOperation(
    kind: ModeStatusOperationKind,
    inputs: ModeStatusInputReference,
    retainedComparison: ModeStatusComparisonReference? = nil,
    declaredWorkUnits: UInt64 = 100,
    stage: ModeStatusProgressStage = .preparing,
    progress: ModeStatusProgress? = nil
) -> ModeStatusOperation {
    ModeStatusOperation(
        reference: ModeStatusOperationReference(
            identity: ModeStatusOperationIdentity(rawValue: statusUUID(400)),
            generation: 2
        ),
        kind: kind,
        inputs: inputs,
        retainedComparison: retainedComparison,
        declaredWorkUnits: declaredWorkUnits,
        progress: progress
            ?? ModeStatusProgress(stage: stage, completedUnits: 1, totalUnits: 100)
    )
}

private func folderMetrics(
    total: UInt64 = 10,
    visible: UInt64 = 8,
    pending: UInt64 = 0,
    identical: UInt64 = 5,
    different: UInt64 = 2,
    leftOnly: UInt64 = 1,
    rightOnly: UInt64 = 2,
    typeMismatch: UInt64 = 0,
    skipped: UInt64 = 0,
    errors: UInt64 = 0,
    isComplete: Bool = true
) -> ModeStatusFolderComparisonMetrics {
    ModeStatusFolderComparisonMetrics(
        totalItems: total,
        visibleItems: visible,
        pendingItems: pending,
        identicalItems: identical,
        differentItems: different,
        leftOnlyItems: leftOnly,
        rightOnlyItems: rightOnly,
        typeMismatchItems: typeMismatch,
        skippedItems: skipped,
        errorItems: errors,
        isComplete: isComplete
    )
}

private func binaryMetrics(
    aligned: UInt64 = 18,
    regions: UInt64 = 2,
    differing: UInt64 = 4,
    conflicts: UInt64 = 0
) -> ModeStatusBinaryComparisonMetrics {
    ModeStatusBinaryComparisonMetrics(
        alignedByteCount: aligned,
        differenceRegionCount: regions,
        differingByteCount: differing,
        conflictCount: conflicts,
        alignment: .exact
    )
}

private func imageMetrics(
    canvasWidth: Int = 6,
    canvasHeight: Int = 5,
    regions: UInt64 = 2,
    differing: UInt64 = 4,
    conflicts: UInt64 = 0,
    conflicting: UInt64 = 0
) -> ModeStatusImageComparisonMetrics {
    ModeStatusImageComparisonMetrics(
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        differenceRegionCount: regions,
        differingPixelCount: differing,
        conflictCount: conflicts,
        conflictingPixelCount: conflicting
    )
}

private func webMetrics(
    units: UInt64 = 10,
    differences: UInt64 = 2,
    conflicts: UInt64 = 0
) -> ModeStatusWebPageComparisonMetrics {
    ModeStatusWebPageComparisonMetrics(
        form: .renderedText,
        comparisonUnitCount: units,
        differenceCount: differences,
        conflictCount: conflicts
    )
}

private func oldInputs(
    for fixture: StatusFixture,
    reason: ModeStatusStaleReason
) -> ModeStatusInputReference {
    switch reason {
    case .sourceChanged(let side), .externalChange(let side):
        let references = fixture.inputs.sources.map { input in
            guard input.side == side else { return input.source }
            return ModeStatusSourceReference(
                identity: input.source.identity,
                generation: input.source.generation - 1
            )
        }
        return makeInput(
            mode: fixture.mode,
            sides: fixture.inputs.sources.map(\.side),
            identity: fixture.inputs.identity,
            generation: fixture.inputs.generation,
            references: references
        )
    case .optionsChanged:
        return makeInput(
            mode: fixture.mode,
            sides: fixture.inputs.sources.map(\.side),
            identity: ModeStatusInputIdentity(rawValue: statusUUID(201)),
            generation: fixture.inputs.generation - 1,
            references: fixture.inputs.sources.map(\.source)
        )
    case .modeChanged:
        let oldMode: ModeStatusMode = fixture.mode == .binary ? .webpage : .binary
        return makeInput(mode: oldMode, sourceCount: fixture.inputs.sources.count)
    }
}

private func staleComparison(
    for fixture: StatusFixture,
    reason: ModeStatusStaleReason,
    externalChange: ModeStatusExternalChangeState = .changed
) -> (snapshot: ModeStatusSnapshot, comparison: ModeStatusComparisonSnapshot) {
    let old = oldInputs(for: fixture, reason: reason)
    let comparison = makeComparison(inputs: old)
    var sources = fixture.sources
    if case .externalChange(let side) = reason,
        let index = sources.firstIndex(where: { $0.side == side })
    {
        sources[index] = replacingSourceState(sources[index], externalChange: externalChange)
    }
    let snapshot = fixture.snapshot(
        sources: sources,
        lifecycle: .stale(comparison.reference, reason: reason),
        comparison: comparison
    )
    return (snapshot, comparison)
}

private func statusLimits(
    maximumSelectedItems: Int = ModeStatusLimits.default.maximumSelectedItems,
    maximumMetricValue: UInt64 = ModeStatusLimits.default.maximumMetricValue,
    maximumPixelCount: UInt64 = ModeStatusLimits.default.maximumPixelCount,
    maximumDeclaredWorkUnits: UInt64 = ModeStatusLimits.default.maximumDeclaredWorkUnits,
    maximumCanonicalBytes: Int = ModeStatusLimits.default.maximumCanonicalBytes,
    maximumWorkUnits: UInt64 = ModeStatusLimits.default.maximumWorkUnits,
    cancellationCheckInterval: UInt64 = ModeStatusLimits.default.cancellationCheckInterval
) -> ModeStatusLimits {
    ModeStatusLimits(
        maximumSelectedItems: maximumSelectedItems,
        maximumMetricValue: maximumMetricValue,
        maximumPixelCount: maximumPixelCount,
        maximumDeclaredWorkUnits: maximumDeclaredWorkUnits,
        maximumCanonicalBytes: maximumCanonicalBytes,
        maximumWorkUnits: maximumWorkUnits,
        cancellationCheckInterval: cancellationCheckInterval
    )
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private func recursiveMirrorLabels(of value: Any) -> [String] {
    let mirror = Mirror(reflecting: value)
    return mirror.children.flatMap { child in
        [child.label].compactMap { $0 } + recursiveMirrorLabels(of: child.value)
    }
}

private func recursiveStringValues(of value: Any) -> [String] {
    if let string = value as? String { return [string] }
    return Mirror(reflecting: value).children.flatMap { recursiveStringValues(of: $0.value) }
}
