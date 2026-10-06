import CryptoKit
import Darwin
import Foundation
import MacMergeCore
import XCTest

final class ImageToolWorkflowTests: XCTestCase {
    func testSynchronizedMultipageSelectionCanonicalizesPaneOrderAndInvalidatesDifferences() throws {
        let snapshot = try snapshotWithCurrentDifference(
            pageCount: 4,
            panes: [.left, .middle, .right]
        )
        let selection = ImageToolPageSelection(
            mode: .synchronized,
            selections: [
                ImageToolPanePageSelection(pane: .right, pageIndex: 2),
                ImageToolPanePageSelection(pane: .left, pageIndex: 2),
                ImageToolPanePageSelection(pane: .middle, pageIndex: 2)
            ]
        )

        let plan = try makePlan(snapshot: snapshot, intent: .selectPages(selection))

        XCTAssertEqual(plan.receipt.kind, .pageSelection)
        XCTAssertEqual(plan.receipt.source, ImageToolSnapshotReference(snapshot))
        XCTAssertTrue(plan.invalidatesDifferenceResult)
        XCTAssertNil(plan.projectedSnapshot?.differenceResult)
        XCTAssertEqual(plan.projectedSnapshot?.generation, snapshot.generation + 1)
        XCTAssertEqual(plan.projectedSnapshot?[.left]?.selectedPageIndex, 2)
        XCTAssertEqual(plan.projectedSnapshot?[.middle]?.selectedPageIndex, 2)
        XCTAssertEqual(plan.projectedSnapshot?[.right]?.selectedPageIndex, 2)
        XCTAssertEqual(plan.projectedSnapshot?.controls.pageSelectionMode, .synchronized)
        XCTAssertEqual(
            plan.requiredCapabilities.values,
            baselineCapabilities.union([
                .normalizedPixelComparison,
                .differenceBlockSize,
                .colorDistanceThreshold,
                .synchronizedPageSelection
            ])
        )
        guard case .selectPages(let canonical) = plan.intent else {
            return XCTFail("Expected page-selection intent")
        }
        XCTAssertEqual(canonical.selections.map(\.pane), [.left, .middle, .right])
        XCTAssertEqual(canonical.selections.map(\.pageIndex), [2, 2, 2])
    }

    func testIndependentPageControlsPreserveResultForModeOnlyChangeAndRejectInvalidSelections() throws {
        let synchronized = try snapshotWithCurrentDifference(pageCount: 3)
        let modeOnly = ImageToolPageSelection(
            mode: .independent,
            selections: [
                ImageToolPanePageSelection(pane: .left, pageIndex: 0),
                ImageToolPanePageSelection(pane: .right, pageIndex: 0)
            ]
        )
        let modePlan = try makePlan(snapshot: synchronized, intent: .selectPages(modeOnly))
        XCTAssertFalse(modePlan.invalidatesDifferenceResult)
        XCTAssertEqual(modePlan.projectedSnapshot?.differenceResult, synchronized.differenceResult)
        XCTAssertTrue(modePlan.requiredCapabilities.contains(.independentPageSelection))
        XCTAssertFalse(modePlan.requiredCapabilities.contains(.normalizedPixelComparison))

        let independent = makeSnapshot(
            pageCount: 3,
            controls: controls(pageSelectionMode: .independent)
        )
        let splitSelection = ImageToolPageSelection(
            mode: .independent,
            selections: [
                ImageToolPanePageSelection(pane: .left, pageIndex: 1),
                ImageToolPanePageSelection(pane: .right, pageIndex: 2)
            ]
        )
        let splitPlan = try makePlan(snapshot: independent, intent: .selectPages(splitSelection))
        XCTAssertTrue(splitPlan.invalidatesDifferenceResult)
        XCTAssertEqual(splitPlan.projectedSnapshot?[.left]?.selectedPageIndex, 1)
        XCTAssertEqual(splitPlan.projectedSnapshot?[.right]?.selectedPageIndex, 2)

        assertWorkflowError(.duplicatePaneSelection(.left)) {
            try makePlan(
                snapshot: independent,
                intent: .selectPages(
                    ImageToolPageSelection(
                        mode: .independent,
                        selections: [
                            ImageToolPanePageSelection(pane: .left, pageIndex: 0),
                            ImageToolPanePageSelection(pane: .left, pageIndex: 1)
                        ]
                    )
                )
            )
        }
        assertWorkflowError(.missingPaneSelection(.right)) {
            try makePlan(
                snapshot: independent,
                intent: .selectPages(
                    ImageToolPageSelection(
                        mode: .independent,
                        selections: [ImageToolPanePageSelection(pane: .left, pageIndex: 0)]
                    )
                )
            )
        }
        assertWorkflowError(.pageNotFound(pane: .right, pageIndex: 3)) {
            try makePlan(
                snapshot: independent,
                intent: .selectPages(
                    ImageToolPageSelection(
                        mode: .independent,
                        selections: [
                            ImageToolPanePageSelection(pane: .left, pageIndex: 0),
                            ImageToolPanePageSelection(pane: .right, pageIndex: 3)
                        ]
                    )
                )
            )
        }
        assertWorkflowError(.synchronizedPagesDiffer) {
            try makePlan(
                snapshot: independent,
                intent: .selectPages(
                    ImageToolPageSelection(
                        mode: .synchronized,
                        selections: [
                            ImageToolPanePageSelection(pane: .left, pageIndex: 1),
                            ImageToolPanePageSelection(pane: .right, pageIndex: 2)
                        ]
                    )
                )
            )
        }
    }

    func testHorizontalVerticalFlipAndRotationCapabilitiesAreIsolated() throws {
        let snapshot = try snapshotWithCurrentDifference()
        let cases: [(ImageToolTransform, ImageToolCapability)] = [
            (ImageToolTransform(flipsHorizontally: true), .horizontalFlip),
            (ImageToolTransform(flipsVertically: true), .verticalFlip),
            (ImageToolTransform(clockwiseQuarterTurns: 1), .quarterTurnRotation),
            (ImageToolTransform(clockwiseQuarterTurns: 2), .quarterTurnRotation),
            (ImageToolTransform(clockwiseQuarterTurns: 3), .quarterTurnRotation)
        ]

        for (transform, capability) in cases {
            let intent = ImageToolWorkflowIntent.setTransforms([
                ImageToolPaneTransform(pane: .right, transform: transform)
            ])
            let plan = try makePlan(snapshot: snapshot, intent: intent)
            XCTAssertEqual(plan.projectedSnapshot?[.right]?.transform, transform)
            XCTAssertEqual(plan.projectedSnapshot?[.left]?.transform, .identity)
            XCTAssertTrue(plan.invalidatesDifferenceResult)
            XCTAssertNil(plan.projectedSnapshot?.differenceResult)
            XCTAssertEqual(
                plan.requiredCapabilities.values,
                comparisonCapabilities.union([capability])
            )
            assertWorkflowError(.missingCapability(capability)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: intent,
                    capabilities: capabilities(removing: capability)
                )
            }
        }
    }

    func testTransformCanonicalizationCompositionAndValidationAreExact() throws {
        let snapshot = try snapshotWithCurrentDifference()
        let left = ImageToolTransform(
            clockwiseQuarterTurns: 3,
            flipsHorizontally: true,
            flipsVertically: true
        )
        let right = ImageToolTransform(clockwiseQuarterTurns: 1, flipsVertically: true)
        let plan = try makePlan(
            snapshot: snapshot,
            intent: .setTransforms([
                ImageToolPaneTransform(pane: .right, transform: right),
                ImageToolPaneTransform(pane: .left, transform: left)
            ])
        )
        guard case .setTransforms(let transforms) = plan.intent else {
            return XCTFail("Expected transform intent")
        }
        XCTAssertEqual(transforms.map(\.pane), [.left, .right])
        XCTAssertEqual(transforms.map(\.transform), [left, right])
        XCTAssertTrue(plan.requiredCapabilities.contains(.quarterTurnRotation))
        XCTAssertTrue(plan.requiredCapabilities.contains(.horizontalFlip))
        XCTAssertTrue(plan.requiredCapabilities.contains(.verticalFlip))
        XCTAssertNil(plan.projectedSnapshot?.differenceResult)

        assertWorkflowError(.duplicateTransform(.left)) {
            try makePlan(
                snapshot: snapshot,
                intent: .setTransforms([
                    ImageToolPaneTransform(pane: .left, transform: left),
                    ImageToolPaneTransform(pane: .left, transform: right)
                ])
            )
        }
        assertWorkflowError(.invalidTransform(.left)) {
            try makePlan(
                snapshot: snapshot,
                intent: .setTransforms([
                    ImageToolPaneTransform(
                        pane: .left,
                        transform: ImageToolTransform(clockwiseQuarterTurns: 4)
                    )
                ])
            )
        }
        assertWorkflowError(.noChange) {
            try makePlan(
                snapshot: snapshot,
                intent: .setTransforms([
                    ImageToolPaneTransform(pane: .left, transform: .identity)
                ])
            )
        }
    }

    func testDifferenceVisibilityOnlyChangePreservesCurrentResultAndRequiresVisibilityCapability() throws {
        let snapshot = try snapshotWithCurrentDifference()
        let hidden = differenceOptions(showsDifferences: false)
        let plan = try makePlan(snapshot: snapshot, intent: .setDifferenceOptions(hidden))

        XCTAssertFalse(plan.invalidatesDifferenceResult)
        XCTAssertEqual(plan.projectedSnapshot?.differenceResult, snapshot.differenceResult)
        XCTAssertEqual(plan.projectedSnapshot?.controls.differences, hidden)
        XCTAssertTrue(plan.requiredCapabilities.contains(.differenceVisibility))
        XCTAssertFalse(plan.requiredCapabilities.contains(.normalizedPixelComparison))
        assertWorkflowError(.missingCapability(.differenceVisibility)) {
            try makePlan(
                snapshot: snapshot,
                intent: .setDifferenceOptions(hidden),
                capabilities: capabilities(removing: .differenceVisibility)
            )
        }
    }

    func testHiddenDifferenceOptionChangesStillInvalidateAndRequireOnlyTheirComparisonCapabilities() throws {
        let original = differenceOptions(showsDifferences: false)
        let snapshot = try snapshotWithCurrentDifference(
            controls: controls(differences: original)
        )
        let pixelOptions = ImageComparisonOptions(
            channelTolerance: 1,
            maximumCanvasPixels: ImageComparisonOptions.default.maximumCanvasPixels,
            maximumRegions: ImageComparisonOptions.default.maximumRegions,
            maximumQueuedPixels: ImageComparisonOptions.default.maximumQueuedPixels
        )
        let hiddenComparisonCapabilities = comparisonCapabilities.subtracting([
            .differenceVisibility
        ])
        let cases: [(ImageToolDifferenceOptions, Set<ImageToolCapability>)] = [
            (
                differenceOptions(showsDifferences: false, differenceBlockSize: 64),
                hiddenComparisonCapabilities
            ),
            (
                differenceOptions(showsDifferences: false, colorDistanceThreshold: 442),
                hiddenComparisonCapabilities
            ),
            (
                differenceOptions(
                    showsDifferences: false,
                    insertionDetection: .horizontal
                ),
                hiddenComparisonCapabilities.union([.horizontalInsertionDetection])
            ),
            (
                differenceOptions(
                    showsDifferences: false,
                    insertionDetection: .vertical
                ),
                hiddenComparisonCapabilities.union([.verticalInsertionDetection])
            ),
            (
                differenceOptions(pixelComparison: pixelOptions, showsDifferences: false),
                hiddenComparisonCapabilities
            )
        ]
        for (changed, expectedCapabilities) in cases {
            let plan = try makePlan(
                snapshot: snapshot,
                intent: .setDifferenceOptions(changed),
                capabilities: capabilities(removing: .differenceVisibility)
            )
            XCTAssertTrue(plan.invalidatesDifferenceResult)
            XCTAssertNil(plan.projectedSnapshot?.differenceResult)
            XCTAssertEqual(plan.projectedSnapshot?.controls.differences, changed)
            XCTAssertEqual(plan.requiredCapabilities.values, expectedCapabilities)
        }
        for capability in [
            ImageToolCapability.horizontalInsertionDetection,
            .verticalInsertionDetection
        ] {
            let insertion: ImageToolInsertionDetection =
                capability == .horizontalInsertionDetection ? .horizontal : .vertical
            assertWorkflowError(.missingCapability(capability)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(
                        differenceOptions(
                            showsDifferences: false,
                            insertionDetection: insertion
                        )
                    ),
                    capabilities: capabilities(removing: capability)
                )
            }
        }
    }

    func testVisibilityToggleCombinedWithHiddenOptionChangeRequiresUnionAndInvalidates() throws {
        let snapshot = try snapshotWithCurrentDifference()
        let changed = differenceOptions(
            showsDifferences: false,
            differenceBlockSize: 9,
            insertionDetection: .horizontal
        )
        let expected = comparisonCapabilities.union([.horizontalInsertionDetection])
        let plan = try makePlan(snapshot: snapshot, intent: .setDifferenceOptions(changed))

        XCTAssertTrue(plan.invalidatesDifferenceResult)
        XCTAssertNil(plan.projectedSnapshot?.differenceResult)
        XCTAssertEqual(plan.projectedSnapshot?.controls.differences, changed)
        XCTAssertEqual(plan.requiredCapabilities.values, expected)
        for capability in expected {
            assertWorkflowError(.missingCapability(capability)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(changed),
                    capabilities: capabilities(removing: capability)
                )
            }
        }
    }

    func testEveryPixelComparisonFieldIsOwnedAndEveryInvalidLimitFailsClosed() throws {
        let snapshot = try snapshotWithCurrentDifference()
        let defaults = ImageComparisonOptions.default
        let mutationPairs = [
            (
                ImageComparisonOptions(
                    channelTolerance: 1,
                    maximumCanvasPixels: defaults.maximumCanvasPixels,
                    maximumRegions: defaults.maximumRegions,
                    maximumQueuedPixels: defaults.maximumQueuedPixels
                ),
                ImageComparisonOptions(
                    channelTolerance: 2,
                    maximumCanvasPixels: defaults.maximumCanvasPixels,
                    maximumRegions: defaults.maximumRegions,
                    maximumQueuedPixels: defaults.maximumQueuedPixels
                )
            ),
            (
                ImageComparisonOptions(
                    channelTolerance: defaults.channelTolerance,
                    maximumCanvasPixels: defaults.maximumCanvasPixels - 1,
                    maximumRegions: defaults.maximumRegions,
                    maximumQueuedPixels: defaults.maximumQueuedPixels
                ),
                ImageComparisonOptions(
                    channelTolerance: defaults.channelTolerance,
                    maximumCanvasPixels: defaults.maximumCanvasPixels - 2,
                    maximumRegions: defaults.maximumRegions,
                    maximumQueuedPixels: defaults.maximumQueuedPixels
                )
            ),
            (
                ImageComparisonOptions(
                    channelTolerance: defaults.channelTolerance,
                    maximumCanvasPixels: defaults.maximumCanvasPixels,
                    maximumRegions: defaults.maximumRegions - 1,
                    maximumQueuedPixels: defaults.maximumQueuedPixels
                ),
                ImageComparisonOptions(
                    channelTolerance: defaults.channelTolerance,
                    maximumCanvasPixels: defaults.maximumCanvasPixels,
                    maximumRegions: defaults.maximumRegions - 2,
                    maximumQueuedPixels: defaults.maximumQueuedPixels
                )
            ),
            (
                ImageComparisonOptions(
                    channelTolerance: defaults.channelTolerance,
                    maximumCanvasPixels: defaults.maximumCanvasPixels,
                    maximumRegions: defaults.maximumRegions,
                    maximumQueuedPixels: defaults.maximumQueuedPixels - 1
                ),
                ImageComparisonOptions(
                    channelTolerance: defaults.channelTolerance,
                    maximumCanvasPixels: defaults.maximumCanvasPixels,
                    maximumRegions: defaults.maximumRegions,
                    maximumQueuedPixels: defaults.maximumQueuedPixels - 2
                )
            )
        ]
        for (first, second) in mutationPairs {
            var digests: [[UInt8]] = []
            for options in [first, second] {
                let changed = differenceOptions(pixelComparison: options)
                let plan = try makePlan(snapshot: snapshot, intent: .setDifferenceOptions(changed))
                XCTAssertTrue(plan.invalidatesDifferenceResult)
                XCTAssertNil(plan.projectedSnapshot?.differenceResult)
                XCTAssertEqual(plan.projectedSnapshot?.controls.differences.pixelComparison, options)
                XCTAssertEqual(plan.requiredCapabilities.values, comparisonCapabilities)
                digests.append(plan.receipt.planSHA256)
            }
            XCTAssertNotEqual(digests[0], digests[1])
        }

        let invalidLimits = [
            ImageComparisonOptions(
                maximumCanvasPixels: 0,
                maximumRegions: defaults.maximumRegions,
                maximumQueuedPixels: defaults.maximumQueuedPixels
            ),
            ImageComparisonOptions(
                maximumCanvasPixels: defaults.maximumCanvasPixels,
                maximumRegions: 0,
                maximumQueuedPixels: defaults.maximumQueuedPixels
            ),
            ImageComparisonOptions(
                maximumCanvasPixels: defaults.maximumCanvasPixels,
                maximumRegions: defaults.maximumRegions,
                maximumQueuedPixels: 0
            )
        ]
        for options in invalidLimits {
            assertWorkflowError(.invalidPixelComparisonOptions) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(
                        differenceOptions(pixelComparison: options)
                    )
                )
            }
        }

        let undersizedCanvas = ImageComparisonOptions(
            maximumCanvasPixels: 199,
            maximumRegions: defaults.maximumRegions,
            maximumQueuedPixels: defaults.maximumQueuedPixels
        )
        assertWorkflowError(.comparisonCanvasTooLarge(maximumPixels: 199)) {
            try makePlan(
                snapshot: snapshot,
                intent: .setDifferenceOptions(
                    differenceOptions(pixelComparison: undersizedCanvas)
                )
            )
        }
    }

    func testZoomModesProjectWithoutComparisonInvalidationAndIsolateCapabilities() throws {
        let fixed = try snapshotWithCurrentDifference()
        let fitZoom = ImageToolZoom(mode: .fit, scale: 1.25)
        let fitPlan = try makePlan(snapshot: fixed, intent: .setZoom(fitZoom))
        XCTAssertEqual(fitPlan.receipt.kind, .zoom)
        XCTAssertEqual(fitPlan.projectedSnapshot?.controls.zoom, fitZoom)
        XCTAssertFalse(fitPlan.invalidatesDifferenceResult)
        XCTAssertEqual(fitPlan.projectedSnapshot?.differenceResult, fixed.differenceResult)
        XCTAssertTrue(fitPlan.requiredCapabilities.contains(.fitZoom))
        XCTAssertFalse(fitPlan.requiredCapabilities.contains(.fixedZoom))
        assertWorkflowError(.missingCapability(.fitZoom)) {
            try makePlan(
                snapshot: fixed,
                intent: .setZoom(fitZoom),
                capabilities: capabilities(removing: .fitZoom)
            )
        }

        let fit = try snapshotWithCurrentDifference(controls: controls(zoom: fitZoom))
        let fixedZoom = ImageToolZoom(mode: .fixed, scale: 2)
        let fixedPlan = try makePlan(snapshot: fit, intent: .setZoom(fixedZoom))
        XCTAssertEqual(fixedPlan.projectedSnapshot?.differenceResult, fit.differenceResult)
        XCTAssertTrue(fixedPlan.requiredCapabilities.contains(.fixedZoom))
        XCTAssertFalse(fixedPlan.requiredCapabilities.contains(.fitZoom))
        assertWorkflowError(.missingCapability(.fixedZoom)) {
            try makePlan(
                snapshot: fit,
                intent: .setZoom(fixedZoom),
                capabilities: capabilities(removing: .fixedZoom)
            )
        }
    }

    func testOverlayModesAndCapabilitiesAreExact() throws {
        let snapshot = try snapshotWithCurrentDifference()
        let cases: [(ImageToolOverlay, Set<ImageToolCapability>)] = [
            (ImageToolOverlay(mode: .xor, alpha: 0), [.xorOverlay]),
            (ImageToolOverlay(mode: .alphaBlend, alpha: 1), [.alphaOverlay]),
            (
                ImageToolOverlay(mode: .alphaBlendAnimation, alpha: 0.5),
                [.alphaOverlay, .animatedOverlay]
            )
        ]
        for (overlay, expected) in cases {
            let plan = try makePlan(snapshot: snapshot, intent: .setOverlay(overlay))
            XCTAssertEqual(plan.projectedSnapshot?.controls.overlay, overlay)
            XCTAssertEqual(plan.requiredCapabilities.values, baselineCapabilities.union(expected))
            XCTAssertFalse(plan.invalidatesDifferenceResult)
            XCTAssertEqual(plan.projectedSnapshot?.differenceResult, snapshot.differenceResult)
            for capability in expected {
                assertWorkflowError(.missingCapability(capability)) {
                    try makePlan(
                        snapshot: snapshot,
                        intent: .setOverlay(overlay),
                        capabilities: capabilities(removing: capability)
                    )
                }
            }
        }
    }

    func testWipeModesAndCapabilitiesAreExact() throws {
        let snapshot = try snapshotWithCurrentDifference()
        let cases: [(ImageToolWipe, ImageToolCapability)] = [
            (ImageToolWipe(mode: .vertical, position: 0), .verticalWipe),
            (ImageToolWipe(mode: .horizontal, position: 1), .horizontalWipe)
        ]
        for (wipe, capability) in cases {
            let plan = try makePlan(snapshot: snapshot, intent: .setWipe(wipe))
            XCTAssertEqual(plan.projectedSnapshot?.controls.wipe, wipe)
            XCTAssertTrue(plan.requiredCapabilities.contains(capability))
            let other: ImageToolCapability = capability == .verticalWipe ? .horizontalWipe : .verticalWipe
            XCTAssertFalse(plan.requiredCapabilities.contains(other))
            XCTAssertFalse(plan.invalidatesDifferenceResult)
            XCTAssertEqual(plan.projectedSnapshot?.differenceResult, snapshot.differenceResult)
            assertWorkflowError(.missingCapability(capability)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setWipe(wipe),
                    capabilities: capabilities(removing: capability)
                )
            }
        }
    }

    func testAnimationControlsRequireBlinkOnlyWhenEnabled() throws {
        let snapshot = try snapshotWithCurrentDifference()
        let blinking = ImageToolAnimation(
            blinksDifferences: true,
            blinkIntervalMilliseconds: 200,
            overlayIntervalMilliseconds: 8_000
        )
        let plan = try makePlan(snapshot: snapshot, intent: .setAnimation(blinking))
        XCTAssertEqual(plan.projectedSnapshot?.controls.animation, blinking)
        XCTAssertTrue(plan.requiredCapabilities.contains(.differenceBlink))
        XCTAssertFalse(plan.invalidatesDifferenceResult)
        XCTAssertEqual(plan.projectedSnapshot?.differenceResult, snapshot.differenceResult)
        assertWorkflowError(.missingCapability(.differenceBlink)) {
            try makePlan(
                snapshot: snapshot,
                intent: .setAnimation(blinking),
                capabilities: capabilities(removing: .differenceBlink)
            )
        }

        let enabledSnapshot = try snapshotWithCurrentDifference(
            controls: controls(animation: blinking)
        )
        let disabled = ImageToolAnimation(
            blinksDifferences: false,
            blinkIntervalMilliseconds: 201,
            overlayIntervalMilliseconds: 7_999
        )
        let disabledPlan = try makePlan(
            snapshot: enabledSnapshot,
            intent: .setAnimation(disabled),
            capabilities: capabilities(removing: .differenceBlink)
        )
        XCTAssertFalse(disabledPlan.requiredCapabilities.contains(.differenceBlink))
        XCTAssertEqual(
            disabledPlan.projectedSnapshot?.differenceResult,
            enabledSnapshot.differenceResult
        )
    }

    func testOCRIntentCanonicalizesTargetsBCP47HintsAndCompletion() throws {
        let snapshot = makeSnapshot(panes: [.left, .middle, .right], pageCount: 3)
        let request = ImageToolOCRRequestIntent(
            targets: [
                ImageToolOCRTarget(pane: .right, pageIndex: 2),
                ImageToolOCRTarget(pane: .left, pageIndex: 1),
                ImageToolOCRTarget(pane: .middle, pageIndex: 0)
            ],
            resultKind: .words,
            languageHints: [
                "zh-hANT-tw", "EN-us", "en-US", "sl-ROZAJ-biske-1994", "I-KLINGON",
                "en-b-foo-a-bar", "X-FOO"
            ],
            completion: .compareExtractedText
        )
        let plan = try makePlan(snapshot: snapshot, intent: .requestOCR(request))

        XCTAssertEqual(plan.receipt.kind, .ocr)
        XCTAssertNil(plan.projectedSnapshot)
        XCTAssertNil(plan.receipt.projected)
        XCTAssertFalse(plan.invalidatesDifferenceResult)
        XCTAssertEqual(
            plan.requiredCapabilities.values,
            [.ocrText, .ocrWordObservations, .ocrLanguageHints]
        )
        guard case .requestOCR(let canonical) = plan.intent else {
            return XCTFail("Expected OCR intent")
        }
        XCTAssertEqual(
            canonical.targets,
            [
                ImageToolOCRTarget(pane: .left, pageIndex: 1),
                ImageToolOCRTarget(pane: .middle, pageIndex: 0),
                ImageToolOCRTarget(pane: .right, pageIndex: 2)
            ]
        )
        XCTAssertEqual(
            canonical.languageHints,
            ["en-US", "en-a-bar-b-foo", "i-klingon", "sl-rozaj-biske-1994", "x-foo", "zh-Hant-TW"]
        )
        // v1 canonicalization preserves recognized grandfathered forms; it does not resolve registry aliases.
        XCTAssertTrue(canonical.languageHints.contains("i-klingon"))
        XCTAssertEqual(canonical.resultKind, .words)
        XCTAssertEqual(canonical.completion, .compareExtractedText)
    }

    func testOCRResultKindsRequireOnlyMatchingObservationCapability() throws {
        let snapshot = makeSnapshot()
        let target = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        let cases: [(ImageToolOCRResultKind, ImageToolCapability?)] = [
            (.textOnly, nil),
            (.lines, .ocrLineObservations),
            (.words, .ocrWordObservations)
        ]
        for (kind, observationCapability) in cases {
            let intent = ImageToolWorkflowIntent.requestOCR(
                ImageToolOCRRequestIntent(targets: [target], resultKind: kind)
            )
            let plan = try makePlan(snapshot: snapshot, intent: intent)
            XCTAssertTrue(plan.requiredCapabilities.contains(.ocrText))
            XCTAssertEqual(plan.requiredCapabilities.contains(.ocrLineObservations), kind == .lines)
            XCTAssertEqual(plan.requiredCapabilities.contains(.ocrWordObservations), kind == .words)
            if let observationCapability {
                assertWorkflowError(.missingCapability(observationCapability)) {
                    try makePlan(
                        snapshot: snapshot,
                        intent: intent,
                        capabilities: capabilities(removing: observationCapability)
                    )
                }
            }
        }
    }

    func testMalformedBCP47TagsAndDuplicateTargetsFailClosed() throws {
        let snapshot = makeSnapshot()
        let target = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        let malformed = [
            "", "-en", "en-", "e", "en--US", "en_US", "en-@", "en-a",
            "en-a-foo-a-bar", "sl-rozaj-rozaj", "x", "en-x", "en-US-abc",
            "abcdefghi", "x-abcdefghi", "en-a-abcdefghi", "en-abc-def-ghi-jkl",
            "en-US-Latn", "en-variant-US", "en-a-b", "en-1"
        ]
        for hint in malformed {
            assertWorkflowError(.invalidLanguageHint(hint)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .requestOCR(
                        ImageToolOCRRequestIntent(targets: [target], languageHints: [hint])
                    )
                )
            }
        }

        assertWorkflowError(.emptyOCRTargets) {
            try makePlan(
                snapshot: snapshot,
                intent: .requestOCR(ImageToolOCRRequestIntent(targets: []))
            )
        }
        assertWorkflowError(.duplicateOCRTarget(target)) {
            try makePlan(
                snapshot: snapshot,
                intent: .requestOCR(ImageToolOCRRequestIntent(targets: [target, target]))
            )
        }
    }

    func testNULIsRejectedInSnapshotLanguageHintAndOCRResult() throws {
        let displayNUL = makeSnapshot(displayNames: [.left: "left\0name"])
        assertWorkflowError(.invalidString) {
            try makePlan(snapshot: displayNUL, intent: .setZoom(ImageToolZoom(scale: 2)))
        }

        let pages = [ImageToolPageDescriptor(index: 0, width: 10, height: 10, bitsPerPixel: 32, label: "p\0age")]
        let labelNUL = makeSnapshot(customPages: [.left: pages])
        assertWorkflowError(.invalidString) {
            try makePlan(snapshot: labelNUL, intent: .setZoom(ImageToolZoom(scale: 2)))
        }

        let snapshot = makeSnapshot()
        let target = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        assertWorkflowError(.invalidString) {
            try makePlan(
                snapshot: snapshot,
                intent: .requestOCR(
                    ImageToolOCRRequestIntent(targets: [target], languageHints: ["en\0US"])
                )
            )
        }

        let plan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(ImageToolOCRRequestIntent(targets: [target]))
        )
        assertWorkflowError(.invalidOCRResult) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [ImageToolOCRResultDraft(target: target, text: "bad\0text")]
            )
        }
    }

    func testC1ControlsRemainVerbatimInMetadataAndOCRResultsButNotLanguageTags() throws {
        let c1 = "before\u{0085}after"
        let pages = [
            ImageToolPageDescriptor(
                index: 0,
                width: 10,
                height: 20,
                bitsPerPixel: 32,
                label: c1
            )
        ]
        let snapshot = makeSnapshot(
            displayNames: [.left: c1],
            customPages: [.left: pages]
        )
        let statePlan = try makePlan(
            snapshot: snapshot,
            intent: .setZoom(ImageToolZoom(scale: 2))
        )
        XCTAssertEqual(statePlan.projectedSnapshot?[.left]?.displayName, c1)
        XCTAssertEqual(statePlan.projectedSnapshot?[.left]?.pages[0].label, c1)

        let target = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        let ocrPlan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(ImageToolOCRRequestIntent(targets: [target]))
        )
        let receipt = try ImageToolExecutionReceiptFactory.ocr(
            plan: ocrPlan,
            currentSnapshot: snapshot,
            capabilities: .all,
            results: [ImageToolOCRResultDraft(target: target, text: c1)]
        )
        guard case .ocr(let results, _) = receipt.effect else {
            return XCTFail("Expected OCR effect")
        }
        XCTAssertEqual(results[0].text, c1)
        XCTAssertEqual(results[0].utf8ByteCount, c1.utf8.count)
        XCTAssertEqual(results[0].contentSHA256, sha256(c1))

        assertWorkflowError(.invalidLanguageHint("en\u{0085}US")) {
            try makePlan(
                snapshot: snapshot,
                intent: .requestOCR(
                    ImageToolOCRRequestIntent(
                        targets: [target],
                        languageHints: ["en\u{0085}US"]
                    )
                )
            )
        }
    }

    func testOCRExecutionReceiptOwnsOrderedResultsHashesByteCountsAndCompletion() throws {
        let snapshot = makeSnapshot(pageCount: 2)
        let left = ImageToolOCRTarget(pane: .left, pageIndex: 1)
        let right = ImageToolOCRTarget(pane: .right, pageIndex: 0)
        let plan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(
                ImageToolOCRRequestIntent(
                    targets: [right, left],
                    resultKind: .lines,
                    languageHints: ["EN-us"],
                    completion: .compareExtractedText
                )
            )
        )
        let drafts = [
            ImageToolOCRResultDraft(target: left, text: "caf\u{00E9}\n", itemCount: 1),
            ImageToolOCRResultDraft(target: right, text: "second\nline", itemCount: 2)
        ]
        let first = try ImageToolExecutionReceiptFactory.ocr(
            plan: plan,
            currentSnapshot: snapshot,
            capabilities: .all,
            results: drafts
        )
        let second = try ImageToolExecutionReceiptFactory.ocr(
            plan: plan,
            currentSnapshot: snapshot,
            capabilities: .all,
            results: drafts
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.planning, plan.receipt)
        guard case .ocr(let results, let completion) = first.effect else {
            return XCTFail("Expected OCR effect")
        }
        XCTAssertEqual(completion, .compareExtractedText)
        XCTAssertEqual(results.map(\.target), [left, right])
        XCTAssertEqual(results.map(\.text), drafts.map(\.text))
        XCTAssertEqual(results.map(\.itemCount), [1, 2])
        XCTAssertEqual(results.map(\.utf8ByteCount), drafts.map { $0.text.utf8.count })
        XCTAssertEqual(results.map(\.contentSHA256), drafts.map { sha256($0.text) })
    }

    func testDecomposedOCRTextIsPreservedAndHasOriginalUTF8Digest() throws {
        let snapshot = makeSnapshot()
        let target = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        let plan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(ImageToolOCRRequestIntent(targets: [target]))
        )
        let decomposed = "e\u{0301}"
        let composed = "\u{00E9}"
        let receipt = try ImageToolExecutionReceiptFactory.ocr(
            plan: plan,
            currentSnapshot: snapshot,
            capabilities: .all,
            results: [ImageToolOCRResultDraft(target: target, text: decomposed)]
        )
        guard case .ocr(let results, _) = receipt.effect else {
            return XCTFail("Expected OCR effect")
        }
        XCTAssertEqual(results[0].text, decomposed)
        XCTAssertFalse(results[0].text.utf8.elementsEqual(composed.utf8))
        XCTAssertEqual(results[0].utf8ByteCount, decomposed.utf8.count)
        XCTAssertEqual(results[0].contentSHA256, sha256(decomposed))
        XCTAssertNotEqual(results[0].contentSHA256, sha256(composed))
    }

    func testOCRExecutionRejectsOrderKindAndExactResultLimitViolations() throws {
        let snapshot = makeSnapshot(pageCount: 2)
        let left = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        let right = ImageToolOCRTarget(pane: .right, pageIndex: 1)
        let exactLimits = limits(maximumOCRResultUTF8Bytes: 4, maximumOCRResultItems: 2)
        let plan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(
                ImageToolOCRRequestIntent(targets: [right, left], resultKind: .lines)
            ),
            limits: exactLimits
        )
        XCTAssertNoThrow(
            try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [
                    ImageToolOCRResultDraft(target: left, text: "\u{00E9}", itemCount: 1),
                    ImageToolOCRResultDraft(target: right, text: "ok", itemCount: 1)
                ]
            )
        )
        assertWorkflowError(.invalidOCRResult) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [
                    ImageToolOCRResultDraft(target: right, text: "ok", itemCount: 1),
                    ImageToolOCRResultDraft(target: left, text: "ok", itemCount: 1)
                ]
            )
        }
        assertWorkflowError(.ocrResultTooLarge(maximumUTF8Bytes: 4)) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [
                    ImageToolOCRResultDraft(target: left, text: "abc", itemCount: 1),
                    ImageToolOCRResultDraft(target: right, text: "de", itemCount: 1)
                ]
            )
        }
        assertWorkflowError(.tooManyOCRResultItems(maximum: 2)) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [
                    ImageToolOCRResultDraft(target: left, text: "a", itemCount: 2),
                    ImageToolOCRResultDraft(target: right, text: "b", itemCount: 1)
                ]
            )
        }
        assertWorkflowError(.invalidOCRResult) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [ImageToolOCRResultDraft(target: left, text: "a", itemCount: 1)]
            )
        }
        assertWorkflowError(.invalidOCRResult) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [
                    ImageToolOCRResultDraft(target: left, text: "a", itemCount: 0),
                    ImageToolOCRResultDraft(target: right, text: "b", itemCount: 0),
                    ImageToolOCRResultDraft(target: left, text: "c", itemCount: 0)
                ]
            )
        }
        assertWorkflowError(.invalidOCRResult) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [
                    ImageToolOCRResultDraft(target: left, text: "a", itemCount: -1),
                    ImageToolOCRResultDraft(target: right, text: "b", itemCount: 0)
                ]
            )
        }

        let textPlan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(ImageToolOCRRequestIntent(targets: [left]))
        )
        assertWorkflowError(.invalidOCRResult) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: textPlan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [ImageToolOCRResultDraft(target: left, text: "text", itemCount: 1)]
            )
        }
    }

    func testOCRReceiptWorkBudgetAcceptsExactAndRejectsOneUnder() throws {
        let snapshot = makeSnapshot()
        let target = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        let text = String(repeating: "x", count: 4_096)
        let generous = limits(
            maximumWorkUnits: 1_000_000,
            maximumOCRResultUTF8Bytes: text.utf8.count,
            cancellationCheckInterval: 64
        )
        let intent = ImageToolWorkflowIntent.requestOCR(
            ImageToolOCRRequestIntent(targets: [target])
        )
        let generousPlan = try makePlan(snapshot: snapshot, intent: intent, limits: generous)
        XCTAssertNoThrow(
            try ImageToolExecutionReceiptFactory.ocr(
                plan: generousPlan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [ImageToolOCRResultDraft(target: target, text: text)]
            )
        )

        let exactWork = UInt64(text.utf8.count + 1)
        let exactPlan = try makePlan(
            snapshot: snapshot,
            intent: intent,
            limits: replacing(generous, maximumWorkUnits: exactWork)
        )
        XCTAssertNoThrow(
            try ImageToolExecutionReceiptFactory.ocr(
                plan: exactPlan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [ImageToolOCRResultDraft(target: target, text: text)]
            )
        )

        let oneUnder = exactWork - 1
        let oneUnderPlan = try makePlan(
            snapshot: snapshot,
            intent: intent,
            limits: replacing(generous, maximumWorkUnits: oneUnder)
        )
        assertWorkflowError(.workLimitExceeded(maximumUnits: oneUnder)) {
            try ImageToolExecutionReceiptFactory.ocr(
                plan: oneUnderPlan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [ImageToolOCRResultDraft(target: target, text: text)]
            )
        }
    }

    func testStatusProjectionReportsExactPageImageTransformZoomAndCurrentDifference() throws {
        let transform = ImageToolTransform(clockwiseQuarterTurns: 1, flipsVertically: true)
        let base = makeSnapshot(
            panes: [.left, .middle, .right],
            pageCount: 3,
            selectedPages: [.left: 1, .middle: 1, .right: 1],
            transforms: [.middle: transform],
            controls: controls(
                pageSelectionMode: .independent,
                zoom: ImageToolZoom(mode: .fit, scale: 1.5)
            ),
            readOnly: [.middle: false],
            modified: [.middle: true]
        )
        let inputDigest = try ImageToolWorkflowPlanner.differenceInputSHA256(for: base)
        let result = differenceResult(inputSHA256: inputDigest)
        let snapshot = replacing(base, differenceResult: result)
        let fingerprint = try ImageToolWorkflowPlanner.snapshotFingerprint(for: snapshot)
        let sample = ImageToolStatusSample(
            point: ImageToolPixelPoint(x: 5, y: 6),
            color: ImageToolRGBA8(red: 1, green: 2, blue: 3, alpha: 4)
        )
        let request = ImageToolStatusRequest(
            observedSnapshot: fingerprint,
            pane: .middle,
            observedImage: try XCTUnwrap(snapshot[.middle]?.image),
            observedPageIndex: 1,
            sample: sample,
            distances: [
                ImageToolStatusDistance(otherPane: .right, colorDistance: 9),
                ImageToolStatusDistance(otherPane: .left, colorDistance: 3)
            ]
        )

        let status = try ImageToolWorkflowPlanner.projectStatus(
            snapshot: snapshot,
            request: request,
            capabilities: ImageToolCapabilities([.pixelStatus])
        )

        XCTAssertEqual(status.snapshot, ImageToolSnapshotReference(snapshot))
        XCTAssertEqual(status.pane, .middle)
        XCTAssertEqual(status.image, snapshot[.middle]?.image)
        XCTAssertEqual(status.pageIndex, 1)
        XCTAssertEqual(status.pageNumber, 2)
        XCTAssertEqual(status.pageCount, 3)
        XCTAssertEqual(status.width, 11)
        XCTAssertEqual(status.height, 21)
        XCTAssertEqual(status.bitsPerPixel, 32)
        XCTAssertFalse(status.isVector)
        XCTAssertEqual(status.transform, transform)
        XCTAssertEqual(status.zoom, snapshot.controls.zoom)
        XCTAssertFalse(status.isReadOnly)
        XCTAssertTrue(status.isModified)
        XCTAssertEqual(status.sample, sample)
        XCTAssertEqual(status.distances.map(\.otherPane), [.left, .right])
        XCTAssertEqual(status.distances.map(\.colorDistance), [3, 9])
        XCTAssertEqual(status.differenceCount, 7)
        XCTAssertEqual(status.conflictCount, 2)
        XCTAssertEqual(status.selectedDifferenceIndex, 3)
        XCTAssertEqual(status.differingPixelCount, 99)
        XCTAssertTrue(status.differenceResultIsCurrent)

        let left = try XCTUnwrap(base[.left])
        let imageMutations = [
            ImageToolImageRevision(
                identity: ImageToolImageIdentity(rawValue: uuid(501)),
                revision: left.image.revision,
                generation: left.image.generation,
                contentSHA256: left.image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: left.image.identity,
                revision: left.image.revision + 1,
                generation: left.image.generation,
                contentSHA256: left.image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: left.image.identity,
                revision: left.image.revision,
                generation: left.image.generation + 1,
                contentSHA256: left.image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: left.image.identity,
                revision: left.image.revision,
                generation: left.image.generation,
                contentSHA256: digest(92)
            )
        ]
        var digestMutations = imageMutations.map { image in
            replacing(
                base,
                panes: base.panes.map { pane in
                    pane.pane == .left ? copyPane(pane, image: image) : pane
                }
            )
        }
        digestMutations.append(
            replacing(
                base,
                panes: base.panes.map { pane in
                    pane.pane == .left ? copyPane(pane, selectedPageIndex: 2) : pane
                }
            )
        )
        for transform in [
            ImageToolTransform(clockwiseQuarterTurns: 1),
            ImageToolTransform(flipsHorizontally: true),
            ImageToolTransform(flipsVertically: true)
        ] {
            digestMutations.append(
                replacing(
                    base,
                    panes: base.panes.map { pane in
                        pane.pane == .left ? copyPane(pane, transform: transform) : pane
                    }
                )
            )
        }
        let defaults = ImageComparisonOptions.default
        let comparisonMutations = [
            differenceOptions(
                pixelComparison: ImageComparisonOptions(channelTolerance: 1)
            ),
            differenceOptions(
                pixelComparison: ImageComparisonOptions(
                    maximumCanvasPixels: defaults.maximumCanvasPixels - 1,
                    maximumRegions: defaults.maximumRegions,
                    maximumQueuedPixels: defaults.maximumQueuedPixels
                )
            ),
            differenceOptions(
                pixelComparison: ImageComparisonOptions(
                    maximumCanvasPixels: defaults.maximumCanvasPixels,
                    maximumRegions: defaults.maximumRegions - 1,
                    maximumQueuedPixels: defaults.maximumQueuedPixels
                )
            ),
            differenceOptions(
                pixelComparison: ImageComparisonOptions(
                    maximumCanvasPixels: defaults.maximumCanvasPixels,
                    maximumRegions: defaults.maximumRegions,
                    maximumQueuedPixels: defaults.maximumQueuedPixels - 1
                )
            ),
            differenceOptions(differenceBlockSize: 9),
            differenceOptions(colorDistanceThreshold: 0.25),
            differenceOptions(insertionDetection: .vertical)
        ]
        digestMutations.append(
            contentsOf: comparisonMutations.map { differences in
                replacing(
                    base,
                    controls: controls(
                        pageSelectionMode: base.controls.pageSelectionMode,
                        differences: differences,
                        zoom: base.controls.zoom,
                        overlay: base.controls.overlay,
                        wipe: base.controls.wipe,
                        animation: base.controls.animation
                    )
                )
            }
        )
        for mutation in digestMutations {
            XCTAssertNotEqual(
                try ImageToolWorkflowPlanner.differenceInputSHA256(for: mutation),
                inputDigest
            )
        }
        let visibilityOnly = replacing(
            base,
            controls: controls(
                pageSelectionMode: base.controls.pageSelectionMode,
                differences: differenceOptions(showsDifferences: false),
                zoom: base.controls.zoom,
                overlay: base.controls.overlay,
                wipe: base.controls.wipe,
                animation: base.controls.animation
            )
        )
        XCTAssertEqual(
            try ImageToolWorkflowPlanner.differenceInputSHA256(for: visibilityOnly),
            inputDigest
        )

        let staleResult = replacing(
            snapshot,
            differenceResult: differenceResult(inputSHA256: digest(98))
        )
        let staleFingerprint = try ImageToolWorkflowPlanner.snapshotFingerprint(for: staleResult)
        let staleRequest = ImageToolStatusRequest(
            observedSnapshot: staleFingerprint,
            pane: .middle,
            observedImage: try XCTUnwrap(staleResult[.middle]?.image),
            observedPageIndex: 1
        )
        XCTAssertFalse(
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: staleResult,
                request: staleRequest,
                capabilities: ImageToolCapabilities([.pixelStatus])
            ).differenceResultIsCurrent
        )
    }

    func testStatusProjectionRejectsMissingCapabilityStaleObservationSampleAndDistances() throws {
        let snapshot = makeSnapshot()
        let fingerprint = try ImageToolWorkflowPlanner.snapshotFingerprint(for: snapshot)
        let image = try XCTUnwrap(snapshot[.left]?.image)
        let request = ImageToolStatusRequest(
            observedSnapshot: fingerprint,
            pane: .left,
            observedImage: image,
            observedPageIndex: 0
        )
        assertWorkflowError(.missingCapability(.pixelStatus)) {
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: snapshot,
                request: request,
                capabilities: ImageToolCapabilities([])
            )
        }

        let changedContents = replacing(
            snapshot,
            panes: snapshot.panes.map { pane in
                pane.pane == .left
                    ? copyPane(pane, displayName: "changed", setsDisplayName: true)
                    : pane
            }
        )
        assertWorkflowError(.snapshotContentsChanged) {
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: changedContents,
                request: request,
                capabilities: ImageToolCapabilities([.pixelStatus])
            )
        }

        let outside = ImageToolStatusRequest(
            observedSnapshot: fingerprint,
            pane: .left,
            observedImage: image,
            observedPageIndex: 0,
            sample: ImageToolStatusSample(
                point: ImageToolPixelPoint(x: 10, y: 0),
                color: ImageToolRGBA8(red: 0, green: 0, blue: 0, alpha: 0)
            )
        )
        assertWorkflowError(.invalidStatusSample) {
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: snapshot,
                request: outside,
                capabilities: ImageToolCapabilities([.pixelStatus])
            )
        }

        let invalidDistance = ImageToolStatusRequest(
            observedSnapshot: fingerprint,
            pane: .left,
            observedImage: image,
            observedPageIndex: 0,
            distances: [ImageToolStatusDistance(otherPane: .left, colorDistance: 0)]
        )
        assertWorkflowError(.invalidStatusDistance(.left)) {
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: snapshot,
                request: invalidDistance,
                capabilities: ImageToolCapabilities([.pixelStatus])
            )
        }

        let imageCases = [
            ImageToolImageRevision(
                identity: ImageToolImageIdentity(rawValue: uuid(901)),
                revision: image.revision,
                generation: image.generation,
                contentSHA256: image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: image.identity,
                revision: image.revision + 1,
                generation: image.generation,
                contentSHA256: image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: image.identity,
                revision: image.revision,
                generation: image.generation + 1,
                contentSHA256: image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: image.identity,
                revision: image.revision,
                generation: image.generation,
                contentSHA256: digest(97)
            )
        ]
        for observedImage in imageCases {
            let staleObservation = ImageToolStatusRequest(
                observedSnapshot: fingerprint,
                pane: .left,
                observedImage: observedImage,
                observedPageIndex: 0
            )
            assertWorkflowError(.snapshotContentsChanged) {
                try ImageToolWorkflowPlanner.projectStatus(
                    snapshot: snapshot,
                    request: staleObservation,
                    capabilities: ImageToolCapabilities([.pixelStatus])
                )
            }
        }
        let wrongPage = ImageToolStatusRequest(
            observedSnapshot: fingerprint,
            pane: .left,
            observedImage: image,
            observedPageIndex: 1
        )
        assertWorkflowError(.snapshotContentsChanged) {
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: snapshot,
                request: wrongPage,
                capabilities: ImageToolCapabilities([.pixelStatus])
            )
        }

        let threePane = makeSnapshot(panes: [.left, .middle, .right])
        let threePaneFingerprint = try ImageToolWorkflowPlanner.snapshotFingerprint(for: threePane)
        let threePaneImage = try XCTUnwrap(threePane[.left]?.image)
        let distanceCases: [(ImageToolStatusDistance, ImageToolPane)] = [
            (ImageToolStatusDistance(otherPane: .right, colorDistance: -1), .right),
            (ImageToolStatusDistance(otherPane: .right, colorDistance: .infinity), .right)
        ]
        for (distance, pane) in distanceCases {
            assertWorkflowError(.invalidStatusDistance(pane)) {
                try ImageToolWorkflowPlanner.projectStatus(
                    snapshot: threePane,
                    request: ImageToolStatusRequest(
                        observedSnapshot: threePaneFingerprint,
                        pane: .left,
                        observedImage: threePaneImage,
                        observedPageIndex: 0,
                        distances: [distance]
                    ),
                    capabilities: ImageToolCapabilities([.pixelStatus])
                )
            }
        }
        let duplicateDistances = ImageToolStatusRequest(
            observedSnapshot: threePaneFingerprint,
            pane: .left,
            observedImage: threePaneImage,
            observedPageIndex: 0,
            distances: [
                ImageToolStatusDistance(otherPane: .right, colorDistance: 1),
                ImageToolStatusDistance(otherPane: .right, colorDistance: 2)
            ]
        )
        assertWorkflowError(.invalidStatusDistance(.right)) {
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: threePane,
                request: duplicateDistances,
                capabilities: ImageToolCapabilities([.pixelStatus])
            )
        }
        let unknownDistance = ImageToolStatusRequest(
            observedSnapshot: fingerprint,
            pane: .left,
            observedImage: image,
            observedPageIndex: 0,
            distances: [ImageToolStatusDistance(otherPane: .middle, colorDistance: 1)]
        )
        assertWorkflowError(.invalidStatusDistance(.middle)) {
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: snapshot,
                request: unknownDistance,
                capabilities: ImageToolCapabilities([.pixelStatus])
            )
        }
        let tooManyDistances = ImageToolStatusRequest(
            observedSnapshot: fingerprint,
            pane: .left,
            observedImage: image,
            observedPageIndex: 0,
            distances: [
                ImageToolStatusDistance(otherPane: .right, colorDistance: 1),
                ImageToolStatusDistance(otherPane: .right, colorDistance: 2)
            ]
        )
        assertWorkflowError(.tooManyItems(maximum: 1)) {
            try ImageToolWorkflowPlanner.projectStatus(
                snapshot: snapshot,
                request: tooManyDistances,
                capabilities: ImageToolCapabilities([.pixelStatus])
            )
        }
    }

    func testPlanningExpectedSourceIdentityRevisionAndGenerationAreExact() throws {
        let snapshot = makeSnapshot(revision: 11, generation: 22)
        let intent = ImageToolWorkflowIntent.setZoom(ImageToolZoom(scale: 2))
        let otherIdentity = uuid(999)
        let cases: [(ImageToolSnapshotReference, ImageToolWorkflowError)] = [
            (
                ImageToolSnapshotReference(
                    identity: otherIdentity,
                    revision: snapshot.revision,
                    generation: snapshot.generation
                ),
                .staleIdentity(expected: otherIdentity, actual: snapshot.identity)
            ),
            (
                ImageToolSnapshotReference(
                    identity: snapshot.identity,
                    revision: 10,
                    generation: snapshot.generation
                ),
                .staleRevision(expected: 10, actual: snapshot.revision)
            ),
            (
                ImageToolSnapshotReference(
                    identity: snapshot.identity,
                    revision: snapshot.revision,
                    generation: 21
                ),
                .staleGeneration(expected: 21, actual: snapshot.generation)
            )
        ]
        for (reference, error) in cases {
            assertWorkflowError(error) {
                try makePlan(snapshot: snapshot, intent: intent, expecting: reference)
            }
        }

        let exact = try makePlan(
            snapshot: snapshot,
            intent: intent,
            expecting: ImageToolSnapshotReference(snapshot)
        )
        XCTAssertEqual(exact.expectedSnapshot.reference, ImageToolSnapshotReference(snapshot))
    }

    func testExecutionValidationRejectsStaleWorkflowReferenceAndMissingCapabilityExactly() throws {
        let snapshot = makeSnapshot(revision: 4, generation: 8)
        let plan = try makePlan(snapshot: snapshot, intent: .setZoom(ImageToolZoom(mode: .fit, scale: 1)))
        let otherIdentity = uuid(777)
        let staleIdentity = replacing(snapshot, identity: otherIdentity)
        assertWorkflowError(.staleIdentity(expected: snapshot.identity, actual: otherIdentity)) {
            try plan.validateForExecution(currentSnapshot: staleIdentity, capabilities: .all)
        }
        let staleRevision = replacing(snapshot, revision: 5)
        assertWorkflowError(.staleRevision(expected: 4, actual: 5)) {
            try plan.validateForExecution(currentSnapshot: staleRevision, capabilities: .all)
        }
        let staleGeneration = replacing(snapshot, generation: 9)
        assertWorkflowError(.staleGeneration(expected: 8, actual: 9)) {
            try plan.validateForExecution(currentSnapshot: staleGeneration, capabilities: .all)
        }
        assertWorkflowError(.missingCapability(.fitZoom)) {
            try plan.validateForExecution(
                currentSnapshot: snapshot,
                capabilities: capabilities(removing: .fitZoom)
            )
        }
        XCTAssertNoThrow(try plan.validateForExecution(currentSnapshot: snapshot, capabilities: .all))
    }

    func testExecutionFingerprintPinsImageIdentityRevisionGenerationDigestAndPageContents() throws {
        let snapshot = makeSnapshot()
        let plan = try makePlan(snapshot: snapshot, intent: .setZoom(ImageToolZoom(scale: 2)))
        let left = try XCTUnwrap(snapshot[.left])
        let imageCases = [
            ImageToolImageRevision(
                identity: ImageToolImageIdentity(rawValue: uuid(500)),
                revision: left.image.revision,
                generation: left.image.generation,
                contentSHA256: left.image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: left.image.identity,
                revision: left.image.revision + 1,
                generation: left.image.generation,
                contentSHA256: left.image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: left.image.identity,
                revision: left.image.revision,
                generation: left.image.generation + 1,
                contentSHA256: left.image.contentSHA256
            ),
            ImageToolImageRevision(
                identity: left.image.identity,
                revision: left.image.revision,
                generation: left.image.generation,
                contentSHA256: digest(91)
            )
        ]
        for image in imageCases {
            let changed = replacing(
                snapshot,
                panes: snapshot.panes.map { pane in
                    pane.pane == .left ? copyPane(pane, image: image) : pane
                }
            )
            assertWorkflowError(.snapshotContentsChanged) {
                try plan.validateForExecution(currentSnapshot: changed, capabilities: .all)
            }
        }

        let pageMutations = [
            left.pages.map { copyPage($0, width: $0.width + 1) },
            left.pages.map { copyPage($0, height: $0.height + 1) },
            left.pages.map { copyPage($0, bitsPerPixel: $0.bitsPerPixel + 1) },
            left.pages.map { copyPage($0, isVector: true) },
            left.pages.map { copyPage($0, label: "page", setsLabel: true) },
            left.pages
                + [
                    ImageToolPageDescriptor(
                        index: left.pages.count,
                        width: 1,
                        height: 1,
                        bitsPerPixel: 32
                    )
                ]
        ]
        for pages in pageMutations {
            let changed = replacing(
                snapshot,
                panes: snapshot.panes.map { pane in
                    pane.pane == .left ? copyPane(pane, pages: pages) : pane
                }
            )
            assertWorkflowError(.snapshotContentsChanged) {
                try plan.validateForExecution(currentSnapshot: changed, capabilities: .all)
            }
        }
    }

    func testExecutionFingerprintRejectsEverySameReferenceOwnerStateMutation() throws {
        let base = makeSnapshot(
            pageCount: 2,
            controls: controls(pageSelectionMode: .independent)
        )
        let inputDigest = try ImageToolWorkflowPlanner.differenceInputSHA256(for: base)
        let snapshot = replacing(base, differenceResult: differenceResult(inputSHA256: inputDigest))
        let plan = try makePlan(snapshot: snapshot, intent: .setZoom(ImageToolZoom(scale: 2)))
        let paneMutations = [
            snapshot.panes.map { pane in
                pane.pane == .left ? copyPane(pane, selectedPageIndex: 1) : pane
            },
            snapshot.panes.map { pane in
                pane.pane == .left
                    ? copyPane(pane, transform: ImageToolTransform(clockwiseQuarterTurns: 1))
                    : pane
            },
            snapshot.panes.map { pane in
                pane.pane == .left
                    ? copyPane(pane, transform: ImageToolTransform(flipsHorizontally: true))
                    : pane
            },
            snapshot.panes.map { pane in
                pane.pane == .left
                    ? copyPane(pane, transform: ImageToolTransform(flipsVertically: true))
                    : pane
            },
            snapshot.panes.map { pane in
                pane.pane == .left ? copyPane(pane, isReadOnly: false) : pane
            },
            snapshot.panes.map { pane in
                pane.pane == .left ? copyPane(pane, isModified: true) : pane
            }
        ]
        var mutations = paneMutations.map {
            replacing(snapshot, panes: $0, setsDifferenceResult: false)
        }
        let controlMutations = [
            controls(pageSelectionMode: .synchronized),
            controls(
                pageSelectionMode: .independent,
                differences: differenceOptions(
                    pixelComparison: ImageComparisonOptions(channelTolerance: 1)
                )
            ),
            controls(
                pageSelectionMode: .independent,
                differences: differenceOptions(showsDifferences: false)
            ),
            controls(
                pageSelectionMode: .independent,
                differences: differenceOptions(differenceBlockSize: 9)
            ),
            controls(
                pageSelectionMode: .independent,
                differences: differenceOptions(colorDistanceThreshold: 0.25)
            ),
            controls(
                pageSelectionMode: .independent,
                differences: differenceOptions(insertionDetection: .vertical)
            ),
            controls(
                pageSelectionMode: .independent,
                zoom: ImageToolZoom(scale: 1.25)
            ),
            controls(
                pageSelectionMode: .independent,
                overlay: ImageToolOverlay(mode: .xor)
            ),
            controls(
                pageSelectionMode: .independent,
                overlay: ImageToolOverlay(alpha: 0.5)
            ),
            controls(
                pageSelectionMode: .independent,
                wipe: ImageToolWipe(mode: .vertical)
            ),
            controls(
                pageSelectionMode: .independent,
                wipe: ImageToolWipe(position: 0.25)
            ),
            controls(
                pageSelectionMode: .independent,
                animation: ImageToolAnimation(blinksDifferences: true)
            ),
            controls(
                pageSelectionMode: .independent,
                animation: ImageToolAnimation(blinkIntervalMilliseconds: 400)
            ),
            controls(
                pageSelectionMode: .independent,
                animation: ImageToolAnimation(overlayIntervalMilliseconds: 600)
            )
        ]
        mutations.append(
            contentsOf: controlMutations.map {
                replacing(snapshot, controls: $0, setsDifferenceResult: false)
            }
        )

        let result = try XCTUnwrap(snapshot.differenceResult)
        let metadataMutations = [
            ImageToolDifferenceResultReference(
                identity: uuid(201),
                generation: result.generation,
                inputSHA256: result.inputSHA256,
                resultSHA256: result.resultSHA256,
                differenceCount: result.differenceCount,
                conflictCount: result.conflictCount,
                differingPixelCount: result.differingPixelCount,
                selectedDifferenceIndex: result.selectedDifferenceIndex
            ),
            ImageToolDifferenceResultReference(
                identity: result.identity,
                generation: result.generation + 1,
                inputSHA256: result.inputSHA256,
                resultSHA256: result.resultSHA256,
                differenceCount: result.differenceCount,
                conflictCount: result.conflictCount,
                differingPixelCount: result.differingPixelCount,
                selectedDifferenceIndex: result.selectedDifferenceIndex
            ),
            ImageToolDifferenceResultReference(
                identity: result.identity,
                generation: result.generation,
                inputSHA256: digest(81),
                resultSHA256: result.resultSHA256,
                differenceCount: result.differenceCount,
                conflictCount: result.conflictCount,
                differingPixelCount: result.differingPixelCount,
                selectedDifferenceIndex: result.selectedDifferenceIndex
            ),
            ImageToolDifferenceResultReference(
                identity: result.identity,
                generation: result.generation,
                inputSHA256: result.inputSHA256,
                resultSHA256: digest(82),
                differenceCount: result.differenceCount,
                conflictCount: result.conflictCount,
                differingPixelCount: result.differingPixelCount,
                selectedDifferenceIndex: result.selectedDifferenceIndex
            ),
            ImageToolDifferenceResultReference(
                identity: result.identity,
                generation: result.generation,
                inputSHA256: result.inputSHA256,
                resultSHA256: result.resultSHA256,
                differenceCount: result.differenceCount + 1,
                conflictCount: result.conflictCount,
                differingPixelCount: result.differingPixelCount,
                selectedDifferenceIndex: result.selectedDifferenceIndex
            ),
            ImageToolDifferenceResultReference(
                identity: result.identity,
                generation: result.generation,
                inputSHA256: result.inputSHA256,
                resultSHA256: result.resultSHA256,
                differenceCount: result.differenceCount,
                conflictCount: result.conflictCount + 1,
                differingPixelCount: result.differingPixelCount,
                selectedDifferenceIndex: result.selectedDifferenceIndex
            ),
            ImageToolDifferenceResultReference(
                identity: result.identity,
                generation: result.generation,
                inputSHA256: result.inputSHA256,
                resultSHA256: result.resultSHA256,
                differenceCount: result.differenceCount,
                conflictCount: result.conflictCount,
                differingPixelCount: result.differingPixelCount + 1,
                selectedDifferenceIndex: result.selectedDifferenceIndex
            ),
            ImageToolDifferenceResultReference(
                identity: result.identity,
                generation: result.generation,
                inputSHA256: result.inputSHA256,
                resultSHA256: result.resultSHA256,
                differenceCount: result.differenceCount,
                conflictCount: result.conflictCount,
                differingPixelCount: result.differingPixelCount,
                selectedDifferenceIndex: 2
            )
        ]
        mutations.append(contentsOf: metadataMutations.map { replacing(snapshot, differenceResult: $0) })

        for mutation in mutations {
            XCTAssertEqual(ImageToolSnapshotReference(mutation), ImageToolSnapshotReference(snapshot))
            assertWorkflowError(.snapshotContentsChanged) {
                try plan.validateForExecution(currentSnapshot: mutation, capabilities: .all)
            }
        }
    }

    func testStateReceiptRejectsProjectedContentMutationUnderExactReference() throws {
        let snapshot = makeSnapshot(
            pageCount: 2,
            controls: controls(pageSelectionMode: .independent)
        )
        let plan = try makePlan(snapshot: snapshot, intent: .setZoom(ImageToolZoom(scale: 2)))
        let projected = try XCTUnwrap(plan.projectedSnapshot)
        let left = try XCTUnwrap(projected[.left])
        let changedImage = ImageToolImageRevision(
            identity: left.image.identity,
            revision: left.image.revision,
            generation: left.image.generation,
            contentSHA256: digest(93)
        )
        let paneMutations = [
            projected.panes.map { pane in
                pane.pane == .left ? copyPane(pane, image: changedImage) : pane
            },
            projected.panes.map { pane in
                pane.pane == .left
                    ? copyPane(
                        pane,
                        pages: pane.pages.map { copyPage($0, width: $0.width + 1) }
                    )
                    : pane
            },
            projected.panes.map { pane in
                pane.pane == .left ? copyPane(pane, selectedPageIndex: 1) : pane
            },
            projected.panes.map { pane in
                pane.pane == .left
                    ? copyPane(pane, transform: ImageToolTransform(flipsHorizontally: true))
                    : pane
            },
            projected.panes.map { pane in
                pane.pane == .left
                    ? copyPane(pane, displayName: "mutated", setsDisplayName: true)
                    : pane
            },
            projected.panes.map { pane in
                pane.pane == .left ? copyPane(pane, isReadOnly: false) : pane
            },
            projected.panes.map { pane in
                pane.pane == .left ? copyPane(pane, isModified: true) : pane
            }
        ]
        var mutations = paneMutations.map { replacing(projected, panes: $0) }
        mutations.append(
            replacing(
                projected,
                controls: controls(
                    pageSelectionMode: projected.controls.pageSelectionMode,
                    differences: projected.controls.differences,
                    zoom: projected.controls.zoom,
                    overlay: ImageToolOverlay(mode: .xor),
                    wipe: projected.controls.wipe,
                    animation: projected.controls.animation
                )
            )
        )
        let inputDigest = try ImageToolWorkflowPlanner.differenceInputSHA256(for: projected)
        mutations.append(
            replacing(
                projected,
                differenceResult: differenceResult(inputSHA256: inputDigest)
            )
        )

        for mutation in mutations {
            XCTAssertEqual(ImageToolSnapshotReference(mutation), ImageToolSnapshotReference(projected))
            XCTAssertNoThrow(try ImageToolWorkflowPlanner.snapshotFingerprint(for: mutation))
            assertWorkflowError(.invalidExecutionResult) {
                try ImageToolExecutionReceiptFactory.stateTransition(
                    plan: plan,
                    currentSnapshot: snapshot,
                    capabilities: .all,
                    publishedSnapshot: mutation
                )
            }
        }
    }

    func testCanonicalUnicodeNormalizationProducesIdenticalFingerprintsPlansAndReceiptEncoding() throws {
        let decomposed = "e\u{301}"
        let composed = "\u{00E9}"
        let decomposedPages = [
            ImageToolPageDescriptor(
                index: 0,
                width: 10,
                height: 20,
                bitsPerPixel: 32,
                label: decomposed
            )
        ]
        let composedPages = [
            ImageToolPageDescriptor(
                index: 0,
                width: 10,
                height: 20,
                bitsPerPixel: 32,
                label: composed
            )
        ]
        let decomposedSnapshot = makeSnapshot(
            displayNames: [.left: decomposed],
            customPages: [.left: decomposedPages]
        )
        let composedSnapshot = makeSnapshot(
            displayNames: [.left: composed],
            customPages: [.left: composedPages]
        )
        let exactLimits = limits(maximumStringUTF8Bytes: 2, maximumTotalStringUTF8Bytes: 4)
        let decomposedPlan = try makePlan(
            snapshot: decomposedSnapshot,
            intent: .setZoom(ImageToolZoom(scale: 2)),
            limits: exactLimits
        )
        let composedPlan = try makePlan(
            snapshot: composedSnapshot,
            intent: .setZoom(ImageToolZoom(scale: 2)),
            limits: exactLimits
        )

        XCTAssertEqual(decomposedPlan.expectedSnapshot, composedPlan.expectedSnapshot)
        XCTAssertEqual(decomposedPlan.receipt.planSHA256, composedPlan.receipt.planSHA256)
        XCTAssertEqual(decomposedPlan.receipt.canonicalPlanByteCount, 802)
        XCTAssertEqual(
            decomposedPlan.receipt.planSHA256,
            hexBytes("ad921e0f75d721c824153734594a665ab944bc51a83fc77b0d894fddd14c831a")
        )
        XCTAssertEqual(decomposedPlan.receipt.estimatedWorkUnits, 1_350)
        XCTAssertEqual(
            decomposedPlan.receipt.canonicalPlanByteCount,
            composedPlan.receipt.canonicalPlanByteCount
        )
        XCTAssertEqual(
            Array(try XCTUnwrap(decomposedPlan.projectedSnapshot?[.left]?.displayName).utf8),
            Array(composed.utf8)
        )
        XCTAssertEqual(
            Array(try XCTUnwrap(decomposedPlan.projectedSnapshot?[.left]?.pages[0].label).utf8),
            Array(composed.utf8)
        )
    }

    func testNormalizedUTF8IndividualAndAggregateLimitsHaveExactBoundaries() throws {
        let composed = "\u{00E9}"
        let individualSnapshot = makeSnapshot(displayNames: [.left: composed])
        XCTAssertNoThrow(
            try makePlan(
                snapshot: individualSnapshot,
                intent: .setZoom(ImageToolZoom(scale: 2)),
                limits: limits(maximumStringUTF8Bytes: 2, maximumTotalStringUTF8Bytes: 2)
            )
        )
        assertWorkflowError(.stringTooLarge(maximumUTF8Bytes: 1)) {
            try makePlan(
                snapshot: individualSnapshot,
                intent: .setZoom(ImageToolZoom(scale: 2)),
                limits: limits(maximumStringUTF8Bytes: 1, maximumTotalStringUTF8Bytes: 2)
            )
        }

        let aggregateSnapshot = makeSnapshot(displayNames: [.left: "ab", .right: "cd"])
        XCTAssertNoThrow(
            try makePlan(
                snapshot: aggregateSnapshot,
                intent: .setZoom(ImageToolZoom(scale: 2)),
                limits: limits(maximumStringUTF8Bytes: 2, maximumTotalStringUTF8Bytes: 4)
            )
        )
        assertWorkflowError(.totalStringsTooLarge(maximumUTF8Bytes: 3)) {
            try makePlan(
                snapshot: aggregateSnapshot,
                intent: .setZoom(ImageToolZoom(scale: 2)),
                limits: limits(maximumStringUTF8Bytes: 2, maximumTotalStringUTF8Bytes: 3)
            )
        }
    }

    func testLargeMultipageOCRPlanningUsesBudgetAndHasExactWorkBoundary() throws {
        let pageCount = 4_096
        let pages = (0..<pageCount).map { index in
            ImageToolPageDescriptor(
                index: index,
                width: index == pageCount - 1 ? 256 : 1,
                height: index == pageCount - 1 ? 256 : 1,
                bitsPerPixel: 32
            )
        }
        let snapshot = makeSnapshot(
            pageCount: pageCount,
            customPages: [.left: pages, .right: pages]
        )
        let targets = (0..<pageCount).reversed().map {
            ImageToolOCRTarget(pane: .left, pageIndex: $0)
        }
        let generous = limits(
            maximumPagesPerPane: pageCount,
            maximumTotalPages: pageCount * 2,
            maximumItemCount: pageCount * 2,
            maximumPlanBytes: 4 * 1_024 * 1_024,
            maximumWorkUnits: 8 * 1_024 * 1_024
        )
        let request = ImageToolOCRRequestIntent(targets: targets, resultKind: .textOnly)
        let plan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(request),
            limits: generous
        )
        XCTAssertEqual(plan.receipt.estimatedWorkUnits, 484_049)
        guard case .requestOCR(let canonical) = plan.intent else {
            return XCTFail("Expected OCR intent")
        }
        XCTAssertEqual(canonical.targets.count, pageCount)
        XCTAssertEqual(canonical.targets.first?.pageIndex, 0)
        XCTAssertEqual(canonical.targets.last?.pageIndex, pageCount - 1)

        let exact = replacing(generous, maximumWorkUnits: plan.receipt.estimatedWorkUnits)
        let exactPlan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(request),
            limits: exact
        )
        XCTAssertEqual(exactPlan.receipt.estimatedWorkUnits, plan.receipt.estimatedWorkUnits)
        let insufficient = replacing(
            generous,
            maximumWorkUnits: plan.receipt.estimatedWorkUnits - 1
        )
        assertWorkflowError(
            .workLimitExceeded(maximumUnits: plan.receipt.estimatedWorkUnits - 1)
        ) {
            try makePlan(
                snapshot: snapshot,
                intent: .requestOCR(request),
                limits: insufficient
            )
        }
    }

    func testPlansAndStateReceiptsAreDeterministicAcrossCallerOrdering() throws {
        let ordered = makeSnapshot()
        let reversed = replacing(ordered, panes: Array(ordered.panes.reversed()))
        let left = ImageToolTransform(clockwiseQuarterTurns: 1, flipsHorizontally: true)
        let right = ImageToolTransform(clockwiseQuarterTurns: 2, flipsVertically: true)
        let first = try makePlan(
            snapshot: ordered,
            intent: .setTransforms([
                ImageToolPaneTransform(pane: .right, transform: right),
                ImageToolPaneTransform(pane: .left, transform: left)
            ])
        )
        let second = try makePlan(
            snapshot: reversed,
            intent: .setTransforms([
                ImageToolPaneTransform(pane: .left, transform: left),
                ImageToolPaneTransform(pane: .right, transform: right)
            ])
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt.planSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(first.expectedSnapshot.stateSHA256.count, SHA256.Digest.byteCount)
        let projected = try XCTUnwrap(first.projectedSnapshot)
        let receiptA = try ImageToolExecutionReceiptFactory.stateTransition(
            plan: first,
            currentSnapshot: ordered,
            capabilities: .all,
            publishedSnapshot: projected
        )
        let receiptB = try ImageToolExecutionReceiptFactory.stateTransition(
            plan: second,
            currentSnapshot: reversed,
            capabilities: .all,
            publishedSnapshot: projected
        )
        XCTAssertEqual(receiptA, receiptB)
        XCTAssertEqual(receiptA.planning, first.receipt)
        XCTAssertEqual(receiptA.effect, .stateTransition(ImageToolSnapshotReference(projected)))

        let wrongPublished = replacing(projected, generation: projected.generation + 1)
        assertWorkflowError(.invalidExecutionResult) {
            try ImageToolExecutionReceiptFactory.stateTransition(
                plan: first,
                currentSnapshot: ordered,
                capabilities: .all,
                publishedSnapshot: wrongPublished
            )
        }
    }

    func testCanonicalPlanByteLimitHasExactReceiptBoundary() throws {
        let snapshot = makeSnapshot(displayNames: [.left: "left", .right: "right"])
        let intent = ImageToolWorkflowIntent.setZoom(ImageToolZoom(scale: 2))
        let generous = limits(maximumPlanBytes: 1 * 1_024 * 1_024)
        let plan = try makePlan(snapshot: snapshot, intent: intent, limits: generous)
        XCTAssertGreaterThan(plan.receipt.canonicalPlanByteCount, 0)

        let exactLimits = replacing(
            generous,
            maximumPlanBytes: plan.receipt.canonicalPlanByteCount
        )
        let exact = try makePlan(snapshot: snapshot, intent: intent, limits: exactLimits)
        XCTAssertEqual(exact.receipt.canonicalPlanByteCount, plan.receipt.canonicalPlanByteCount)

        let oneUnder = replacing(
            generous,
            maximumPlanBytes: plan.receipt.canonicalPlanByteCount - 1
        )
        assertWorkflowError(
            .planTooLarge(maximumBytes: plan.receipt.canonicalPlanByteCount - 1)
        ) {
            try makePlan(snapshot: snapshot, intent: intent, limits: oneUnder)
        }
    }

    func testWorkflowLimitHardMaximaAreAcceptedAndEveryOneAboveIsRejected() throws {
        let hard = limits(
            maximumPaneCount: ImageToolWorkflowLimits.hardMaximumPaneCount,
            maximumPagesPerPane: ImageToolWorkflowLimits.hardMaximumPagesPerPane,
            maximumTotalPages: ImageToolWorkflowLimits.hardMaximumTotalPages,
            maximumItemCount: ImageToolWorkflowLimits.hardMaximumItemCount,
            maximumStringUTF8Bytes: ImageToolWorkflowLimits.hardMaximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: ImageToolWorkflowLimits.hardMaximumTotalStringUTF8Bytes,
            maximumPlanBytes: ImageToolWorkflowLimits.hardMaximumPlanBytes,
            maximumWorkUnits: ImageToolWorkflowLimits.hardMaximumWorkUnits,
            maximumOCRResultUTF8Bytes: ImageToolWorkflowLimits.hardMaximumOCRResultUTF8Bytes,
            maximumOCRResultItems: ImageToolWorkflowLimits.hardMaximumOCRResultItems,
            cancellationCheckInterval: ImageToolWorkflowLimits.hardMaximumCancellationCheckInterval
        )
        let snapshot = makeSnapshot()
        XCTAssertNoThrow(
            try makePlan(
                snapshot: snapshot,
                intent: .setZoom(ImageToolZoom(scale: 2)),
                limits: hard
            )
        )

        let invalid: [(ImageToolWorkflowLimit, ImageToolWorkflowLimits)] = [
            (
                .panes,
                replacing(hard, maximumPaneCount: ImageToolWorkflowLimits.hardMaximumPaneCount + 1)
            ),
            (
                .pagesPerPane,
                replacing(
                    hard,
                    maximumPagesPerPane: ImageToolWorkflowLimits.hardMaximumPagesPerPane + 1
                )
            ),
            (
                .totalPages,
                replacing(
                    hard,
                    maximumTotalPages: ImageToolWorkflowLimits.hardMaximumTotalPages + 1
                )
            ),
            (
                .items,
                replacing(
                    hard,
                    maximumItemCount: ImageToolWorkflowLimits.hardMaximumItemCount + 1
                )
            ),
            (
                .stringUTF8Bytes,
                replacing(
                    hard,
                    maximumStringUTF8Bytes: ImageToolWorkflowLimits.hardMaximumStringUTF8Bytes + 1
                )
            ),
            (
                .totalStringUTF8Bytes,
                replacing(
                    hard,
                    maximumTotalStringUTF8Bytes: ImageToolWorkflowLimits.hardMaximumTotalStringUTF8Bytes + 1
                )
            ),
            (
                .planBytes,
                replacing(
                    hard,
                    maximumPlanBytes: ImageToolWorkflowLimits.hardMaximumPlanBytes + 1
                )
            ),
            (
                .workUnits,
                replacing(
                    hard,
                    maximumWorkUnits: ImageToolWorkflowLimits.hardMaximumWorkUnits + 1
                )
            ),
            (
                .ocrResultUTF8Bytes,
                replacing(
                    hard,
                    maximumOCRResultUTF8Bytes: ImageToolWorkflowLimits.hardMaximumOCRResultUTF8Bytes + 1
                )
            ),
            (
                .ocrResultItems,
                replacing(
                    hard,
                    maximumOCRResultItems: ImageToolWorkflowLimits.hardMaximumOCRResultItems + 1
                )
            ),
            (
                .cancellationCheckInterval,
                replacing(
                    hard,
                    cancellationCheckInterval: ImageToolWorkflowLimits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]
        XCTAssertEqual(Set(invalid.map(\.0)), Set(ImageToolWorkflowLimit.allCases))
        for (limit, value) in invalid {
            assertWorkflowError(.invalidLimit(limit)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setZoom(ImageToolZoom(scale: 2)),
                    limits: value
                )
            }
        }

        let lower: [(ImageToolWorkflowLimit, ImageToolWorkflowLimits)] = [
            (.panes, limits(maximumPaneCount: 1)),
            (.pagesPerPane, limits(maximumPagesPerPane: 0)),
            (.totalPages, limits(maximumTotalPages: 1)),
            (.items, limits(maximumItemCount: 0)),
            (.stringUTF8Bytes, limits(maximumStringUTF8Bytes: 0)),
            (.totalStringUTF8Bytes, limits(maximumTotalStringUTF8Bytes: 0)),
            (.planBytes, limits(maximumPlanBytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (.ocrResultUTF8Bytes, limits(maximumOCRResultUTF8Bytes: 0)),
            (.ocrResultItems, limits(maximumOCRResultItems: 0)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0))
        ]
        XCTAssertEqual(Set(lower.map(\.0)), Set(ImageToolWorkflowLimit.allCases))
        for (limit, value) in lower {
            assertWorkflowError(.invalidLimit(limit)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setZoom(ImageToolZoom(scale: 2)),
                    limits: value
                )
            }
        }

        let crossField = [
            limits(
                maximumPaneCount: 3,
                maximumPagesPerPane: 1,
                maximumTotalPages: 2,
                maximumItemCount: 2
            ),
            limits(
                maximumPaneCount: 2,
                maximumPagesPerPane: 3,
                maximumTotalPages: 2,
                maximumItemCount: 3
            ),
            limits(
                maximumPaneCount: 2,
                maximumPagesPerPane: 1,
                maximumTotalPages: 3,
                maximumItemCount: 2
            ),
            limits(
                maximumPaneCount: 2,
                maximumPagesPerPane: 1,
                maximumTotalPages: 2,
                maximumItemCount: 2,
                maximumStringUTF8Bytes: 2,
                maximumTotalStringUTF8Bytes: 1
            )
        ]
        for value in crossField {
            assertWorkflowError(.invalidLimit(.items)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setZoom(ImageToolZoom(scale: 2)),
                    limits: value
                )
            }
        }
    }

    func testNumericControlHardBoundariesAreAcceptedAndOneStepOutsideFails() throws {
        let snapshot = makeSnapshot()
        for blockSize in [1, 64] {
            XCTAssertNoThrow(
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(
                        differenceOptions(differenceBlockSize: blockSize)
                    )
                )
            )
        }
        for blockSize in [0, 65] {
            assertWorkflowError(.invalidDifferenceBlockSize(blockSize)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(
                        differenceOptions(differenceBlockSize: blockSize)
                    )
                )
            }
        }
        for threshold in [0.0, 442.0] {
            let value = threshold == 0 ? -0.0 : threshold
            XCTAssertNoThrow(
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(
                        differenceOptions(
                            differenceBlockSize: 9,
                            colorDistanceThreshold: value
                        )
                    )
                )
            )
        }
        for threshold in [-0.000_001, 442.000_001] {
            assertWorkflowError(.invalidColorDistanceThreshold(threshold)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(
                        differenceOptions(colorDistanceThreshold: threshold)
                    )
                )
            }
        }
        for threshold in [Double.infinity, -Double.infinity] {
            assertWorkflowError(.invalidColorDistanceThreshold(threshold)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(
                        differenceOptions(colorDistanceThreshold: threshold)
                    )
                )
            }
        }
        assertWorkflowErrorMatching(
            {
                guard case .invalidColorDistanceThreshold(let value) = $0 else { return false }
                return value.isNaN
            },
            operation: {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setDifferenceOptions(
                        differenceOptions(colorDistanceThreshold: .nan)
                    )
                )
            }
        )
        for scale in [0.01, 8.0] {
            XCTAssertNoThrow(try makePlan(snapshot: snapshot, intent: .setZoom(ImageToolZoom(scale: scale))))
        }
        for scale in [0.009_999, 8.000_001] {
            assertWorkflowError(.invalidZoom(scale)) {
                try makePlan(snapshot: snapshot, intent: .setZoom(ImageToolZoom(scale: scale)))
            }
        }
        for scale in [Double.infinity, -Double.infinity] {
            assertWorkflowError(.invalidZoom(scale)) {
                try makePlan(snapshot: snapshot, intent: .setZoom(ImageToolZoom(scale: scale)))
            }
        }
        assertWorkflowErrorMatching(
            {
                guard case .invalidZoom(let value) = $0 else { return false }
                return value.isNaN
            },
            operation: {
                try makePlan(snapshot: snapshot, intent: .setZoom(ImageToolZoom(scale: .nan)))
            }
        )
        for alpha in [0.0, 1.0] {
            XCTAssertNoThrow(
                try makePlan(
                    snapshot: snapshot,
                    intent: .setOverlay(ImageToolOverlay(mode: .xor, alpha: alpha))
                )
            )
        }
        for alpha in [-0.000_001, 1.000_001] {
            assertWorkflowError(.invalidOverlayAlpha(alpha)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setOverlay(ImageToolOverlay(mode: .xor, alpha: alpha))
                )
            }
        }
        for alpha in [Double.infinity, -Double.infinity] {
            assertWorkflowError(.invalidOverlayAlpha(alpha)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setOverlay(ImageToolOverlay(mode: .xor, alpha: alpha))
                )
            }
        }
        assertWorkflowErrorMatching(
            {
                guard case .invalidOverlayAlpha(let value) = $0 else { return false }
                return value.isNaN
            },
            operation: {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setOverlay(ImageToolOverlay(mode: .xor, alpha: .nan))
                )
            }
        )
        for position in [0.0, 1.0] {
            XCTAssertNoThrow(
                try makePlan(
                    snapshot: snapshot,
                    intent: .setWipe(ImageToolWipe(mode: .vertical, position: position))
                )
            )
        }
        for position in [-0.000_001, 1.000_001] {
            assertWorkflowError(.invalidWipePosition(position)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setWipe(ImageToolWipe(mode: .vertical, position: position))
                )
            }
        }
        for position in [Double.infinity, -Double.infinity] {
            assertWorkflowError(.invalidWipePosition(position)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setWipe(ImageToolWipe(mode: .vertical, position: position))
                )
            }
        }
        assertWorkflowErrorMatching(
            {
                guard case .invalidWipePosition(let value) = $0 else { return false }
                return value.isNaN
            },
            operation: {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setWipe(ImageToolWipe(mode: .vertical, position: .nan))
                )
            }
        )
        let exactAnimation = ImageToolAnimation(
            blinksDifferences: true,
            blinkIntervalMilliseconds: 200,
            overlayIntervalMilliseconds: 8_000
        )
        XCTAssertNoThrow(try makePlan(snapshot: snapshot, intent: .setAnimation(exactAnimation)))
        for interval in [199, 8_001] {
            assertWorkflowError(.invalidAnimationInterval(interval)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setAnimation(
                        ImageToolAnimation(
                            blinksDifferences: true,
                            blinkIntervalMilliseconds: interval,
                            overlayIntervalMilliseconds: 1_000
                        )
                    )
                )
            }
        }
        for interval in [199, 8_001] {
            assertWorkflowError(.invalidAnimationInterval(interval)) {
                try makePlan(
                    snapshot: snapshot,
                    intent: .setAnimation(
                        ImageToolAnimation(
                            blinksDifferences: true,
                            blinkIntervalMilliseconds: 800,
                            overlayIntervalMilliseconds: interval
                        )
                    )
                )
            }
        }
    }

    func testGenerationOverflowNoChangeAndRotatedCanvasLimitFailExactly() throws {
        let overflow = makeSnapshot(generation: UInt64.max)
        assertWorkflowError(.generationOverflow) {
            try makePlan(snapshot: overflow, intent: .setZoom(ImageToolZoom(scale: 2)))
        }
        let snapshot = makeSnapshot()
        assertWorkflowError(.noChange) {
            try makePlan(snapshot: snapshot, intent: .setZoom(.normal))
        }

        let pages = [ImageToolPageDescriptor(index: 0, width: 8, height: 20, bitsPerPixel: 32)]
        let narrowCanvas = ImageComparisonOptions(
            maximumCanvasPixels: 159,
            maximumRegions: 1,
            maximumQueuedPixels: 1
        )
        let canvasSnapshot = makeSnapshot(
            controls: controls(
                differences: differenceOptions(pixelComparison: narrowCanvas)
            ),
            customPages: [.left: pages, .right: pages]
        )
        assertWorkflowError(.comparisonCanvasTooLarge(maximumPixels: 159)) {
            try makePlan(
                snapshot: canvasSnapshot,
                intent: .setTransforms([
                    ImageToolPaneTransform(
                        pane: .left,
                        transform: ImageToolTransform(clockwiseQuarterTurns: 1)
                    )
                ])
            )
        }
    }

    func testPublicPlanningFingerprintStatusAndOCRReceiptHonorPreCancellation() async throws {
        let snapshot = makeSnapshot()
        let planningRequest = ImageToolWorkflowRequest(
            snapshot: snapshot,
            intent: .setZoom(ImageToolZoom(scale: 2)),
            availableCapabilities: .all
        )
        let planningTask = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageToolWorkflowPlanner.plan(planningRequest)
        }
        await assertCancelled(planningTask)

        let fingerprintTask = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageToolWorkflowPlanner.snapshotFingerprint(for: snapshot)
        }
        await assertCancelled(fingerprintTask)

        let differenceTask = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageToolWorkflowPlanner.differenceInputSHA256(for: snapshot)
        }
        await assertCancelled(differenceTask)

        let fingerprint = try ImageToolWorkflowPlanner.snapshotFingerprint(for: snapshot)
        let image = try XCTUnwrap(snapshot[.left]?.image)
        let statusRequest = ImageToolStatusRequest(
            observedSnapshot: fingerprint,
            pane: .left,
            observedImage: image,
            observedPageIndex: 0
        )
        let statusTask = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageToolWorkflowPlanner.projectStatus(
                snapshot: snapshot,
                request: statusRequest,
                capabilities: ImageToolCapabilities([.pixelStatus])
            )
        }
        await assertCancelled(statusTask)

        let target = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        let plan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(ImageToolOCRRequestIntent(targets: [target]))
        )
        let validationTask = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            try plan.validateForExecution(currentSnapshot: snapshot, capabilities: .all)
        }
        await assertCancelled(validationTask)
        let receiptTask = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageToolExecutionReceiptFactory.ocr(
                plan: plan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [ImageToolOCRResultDraft(target: target, text: "text")]
            )
        }
        await assertCancelled(receiptTask)

        let statePlan = try makePlan(
            snapshot: snapshot,
            intent: .setZoom(ImageToolZoom(scale: 2))
        )
        let projected = try XCTUnwrap(statePlan.projectedSnapshot)
        let stateReceiptTask = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageToolExecutionReceiptFactory.stateTransition(
                plan: statePlan,
                currentSnapshot: snapshot,
                capabilities: .all,
                publishedSnapshot: projected
            )
        }
        await assertCancelled(stateReceiptTask)
    }

    func testOCRAndStateReceiptCancellationAfterObservedMidLoopCPUWork() async throws {
        let snapshot = makeSnapshot()
        let target = ImageToolOCRTarget(pane: .left, pageIndex: 0)
        let ocrLimits = limits(
            maximumPlanBytes: 4 * 1_024 * 1_024,
            maximumWorkUnits: 128 * 1_024 * 1_024,
            maximumOCRResultUTF8Bytes: 64 * 1_024 * 1_024,
            cancellationCheckInterval: 64
        )
        let ocrPlan = try makePlan(
            snapshot: snapshot,
            intent: .requestOCR(ImageToolOCRRequestIntent(targets: [target])),
            limits: ocrLimits
        )
        let ocrText = String(repeating: "x", count: 32 * 1_024 * 1_024)
        let ocrProbe = ImageToolInFlightProbe()
        let ocrTask = Task.detached { () throws -> ImageToolExecutionReceipt in
            ocrProbe.begin()
            defer { ocrProbe.finish() }
            return try ImageToolExecutionReceiptFactory.ocr(
                plan: ocrPlan,
                currentSnapshot: snapshot,
                capabilities: .all,
                results: [ImageToolOCRResultDraft(target: target, text: ocrText)]
            )
        }
        try cancelAfterObservedCPUWork(task: ocrTask, probe: ocrProbe, operation: "OCR receipt")
        await assertCancelled(ocrTask)

        let pageCount = 65_536
        let pages = (0..<pageCount).map {
            ImageToolPageDescriptor(index: $0, width: 1, height: 1, bitsPerPixel: 32)
        }
        let largeSnapshot = makeSnapshot(
            pageCount: pageCount,
            customPages: [.left: pages, .right: pages]
        )
        let stateLimits = limits(
            maximumPagesPerPane: pageCount,
            maximumTotalPages: pageCount * 2,
            maximumItemCount: pageCount * 2,
            maximumPlanBytes: 32 * 1_024 * 1_024,
            maximumWorkUnits: 256 * 1_024 * 1_024,
            cancellationCheckInterval: 64
        )
        let statePlan = try makePlan(
            snapshot: largeSnapshot,
            intent: .setZoom(ImageToolZoom(scale: 2)),
            limits: stateLimits
        )
        let projected = try XCTUnwrap(statePlan.projectedSnapshot)
        let stateProbe = ImageToolInFlightProbe()
        let stateTask = Task.detached { () throws -> ImageToolExecutionReceipt in
            stateProbe.begin()
            defer { stateProbe.finish() }
            return try ImageToolExecutionReceiptFactory.stateTransition(
                plan: statePlan,
                currentSnapshot: largeSnapshot,
                capabilities: .all,
                publishedSnapshot: projected
            )
        }
        try cancelAfterObservedCPUWork(
            task: stateTask,
            probe: stateProbe,
            operation: "state receipt"
        )
        await assertCancelled(stateTask)
    }

    private var baselineCapabilities: Set<ImageToolCapability> {
        [.fixedZoom, .differenceVisibility, .synchronizedPageSelection]
    }

    private var comparisonCapabilities: Set<ImageToolCapability> {
        baselineCapabilities.union([
            .normalizedPixelComparison,
            .differenceBlockSize,
            .colorDistanceThreshold
        ])
    }

    private func makePlan(
        snapshot: ImageToolWorkflowSnapshot,
        intent: ImageToolWorkflowIntent,
        capabilities: ImageToolCapabilities = .all,
        limits: ImageToolWorkflowLimits = .default,
        expecting expected: ImageToolSnapshotReference? = nil
    ) throws -> ImageToolWorkflowPlan {
        try ImageToolWorkflowPlanner.plan(
            ImageToolWorkflowRequest(
                snapshot: snapshot,
                intent: intent,
                availableCapabilities: capabilities,
                limits: limits
            ),
            expecting: expected
        )
    }

    private func makeSnapshot(
        identity: UUID? = nil,
        revision: UInt64 = 7,
        generation: UInt64 = 12,
        panes: [ImageToolPane] = [.left, .right],
        pageCount: Int = 1,
        selectedPages: [ImageToolPane: Int] = [:],
        transforms: [ImageToolPane: ImageToolTransform] = [:],
        controls: ImageToolControlState = .default,
        differenceResult: ImageToolDifferenceResultReference? = nil,
        displayNames: [ImageToolPane: String] = [:],
        readOnly: [ImageToolPane: Bool] = [:],
        modified: [ImageToolPane: Bool] = [:],
        customPages: [ImageToolPane: [ImageToolPageDescriptor]] = [:]
    ) -> ImageToolWorkflowSnapshot {
        let snapshots = panes.map { pane in
            let pages =
                customPages[pane]
                ?? (0..<pageCount).map { index in
                    ImageToolPageDescriptor(
                        index: index,
                        width: 10 + index,
                        height: 20 + index,
                        bitsPerPixel: 32
                    )
                }
            return ImageToolPaneSnapshot(
                pane: pane,
                image: imageRevision(pane),
                pages: pages,
                selectedPageIndex: selectedPages[pane] ?? 0,
                transform: transforms[pane] ?? .identity,
                displayName: displayNames[pane],
                isReadOnly: readOnly[pane] ?? true,
                isModified: modified[pane] ?? false
            )
        }
        return ImageToolWorkflowSnapshot(
            identity: identity ?? uuid(100),
            revision: revision,
            generation: generation,
            panes: snapshots,
            controls: controls,
            differenceResult: differenceResult
        )
    }

    private func snapshotWithCurrentDifference(
        pageCount: Int = 1,
        panes: [ImageToolPane] = [.left, .right],
        controls: ImageToolControlState = .default
    ) throws -> ImageToolWorkflowSnapshot {
        let base = makeSnapshot(panes: panes, pageCount: pageCount, controls: controls)
        let input = try ImageToolWorkflowPlanner.differenceInputSHA256(for: base)
        return replacing(base, differenceResult: differenceResult(inputSHA256: input))
    }

    private func imageRevision(_ pane: ImageToolPane) -> ImageToolImageRevision {
        let seed = UInt8(pane.rawValue + 1)
        return ImageToolImageRevision(
            identity: ImageToolImageIdentity(rawValue: uuid(pane.rawValue + 1)),
            revision: UInt64(20 + pane.rawValue),
            generation: UInt64(30 + pane.rawValue),
            contentSHA256: digest(seed)
        )
    }

    private func differenceResult(inputSHA256: [UInt8]) -> ImageToolDifferenceResultReference {
        ImageToolDifferenceResultReference(
            identity: uuid(200),
            generation: 3,
            inputSHA256: inputSHA256,
            resultSHA256: digest(44),
            differenceCount: 7,
            conflictCount: 2,
            differingPixelCount: 99,
            selectedDifferenceIndex: 3
        )
    }

    private func controls(
        pageSelectionMode: ImageToolPageSelectionMode = .synchronized,
        differences: ImageToolDifferenceOptions = .default,
        zoom: ImageToolZoom = .normal,
        overlay: ImageToolOverlay = .none,
        wipe: ImageToolWipe = .none,
        animation: ImageToolAnimation = .default
    ) -> ImageToolControlState {
        ImageToolControlState(
            pageSelectionMode: pageSelectionMode,
            differences: differences,
            zoom: zoom,
            overlay: overlay,
            wipe: wipe,
            animation: animation
        )
    }

    private func differenceOptions(
        pixelComparison: ImageComparisonOptions = .default,
        showsDifferences: Bool = true,
        differenceBlockSize: Int = 8,
        colorDistanceThreshold: Double = 0,
        insertionDetection: ImageToolInsertionDetection = .none
    ) -> ImageToolDifferenceOptions {
        ImageToolDifferenceOptions(
            pixelComparison: pixelComparison,
            showsDifferences: showsDifferences,
            differenceBlockSize: differenceBlockSize,
            colorDistanceThreshold: colorDistanceThreshold,
            insertionDetection: insertionDetection
        )
    }

    private func capabilities(removing capability: ImageToolCapability) -> ImageToolCapabilities {
        ImageToolCapabilities(ImageToolCapabilities.all.values.subtracting([capability]))
    }

    private func copyPane(
        _ pane: ImageToolPaneSnapshot,
        image: ImageToolImageRevision? = nil,
        pages: [ImageToolPageDescriptor]? = nil,
        selectedPageIndex: Int? = nil,
        transform: ImageToolTransform? = nil,
        displayName: String? = nil,
        setsDisplayName: Bool = false,
        isReadOnly: Bool? = nil,
        isModified: Bool? = nil
    ) -> ImageToolPaneSnapshot {
        ImageToolPaneSnapshot(
            pane: pane.pane,
            image: image ?? pane.image,
            pages: pages ?? pane.pages,
            selectedPageIndex: selectedPageIndex ?? pane.selectedPageIndex,
            transform: transform ?? pane.transform,
            displayName: setsDisplayName ? displayName : pane.displayName,
            isReadOnly: isReadOnly ?? pane.isReadOnly,
            isModified: isModified ?? pane.isModified
        )
    }

    private func copyPage(
        _ page: ImageToolPageDescriptor,
        width: Int? = nil,
        height: Int? = nil,
        bitsPerPixel: Int? = nil,
        isVector: Bool? = nil,
        label: String? = nil,
        setsLabel: Bool = false
    ) -> ImageToolPageDescriptor {
        ImageToolPageDescriptor(
            index: page.index,
            width: width ?? page.width,
            height: height ?? page.height,
            bitsPerPixel: bitsPerPixel ?? page.bitsPerPixel,
            isVector: isVector ?? page.isVector,
            label: setsLabel ? label : page.label
        )
    }

    private func replacing(
        _ snapshot: ImageToolWorkflowSnapshot,
        identity: UUID? = nil,
        revision: UInt64? = nil,
        generation: UInt64? = nil,
        panes: [ImageToolPaneSnapshot]? = nil,
        controls: ImageToolControlState? = nil,
        differenceResult: ImageToolDifferenceResultReference? = nil,
        setsDifferenceResult: Bool = true
    ) -> ImageToolWorkflowSnapshot {
        ImageToolWorkflowSnapshot(
            identity: identity ?? snapshot.identity,
            revision: revision ?? snapshot.revision,
            generation: generation ?? snapshot.generation,
            panes: panes ?? snapshot.panes,
            controls: controls ?? snapshot.controls,
            differenceResult: setsDifferenceResult ? differenceResult : snapshot.differenceResult
        )
    }

    private func limits(
        maximumPaneCount: Int = 3,
        maximumPagesPerPane: Int = 65_536,
        maximumTotalPages: Int = 196_608,
        maximumItemCount: Int = 262_144,
        maximumStringUTF8Bytes: Int = 16 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumPlanBytes: Int = 16 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
        maximumOCRResultUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumOCRResultItems: Int = 1_000_000,
        cancellationCheckInterval: Int = 4_096
    ) -> ImageToolWorkflowLimits {
        ImageToolWorkflowLimits(
            maximumPaneCount: maximumPaneCount,
            maximumPagesPerPane: maximumPagesPerPane,
            maximumTotalPages: maximumTotalPages,
            maximumItemCount: maximumItemCount,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumPlanBytes: maximumPlanBytes,
            maximumWorkUnits: maximumWorkUnits,
            maximumOCRResultUTF8Bytes: maximumOCRResultUTF8Bytes,
            maximumOCRResultItems: maximumOCRResultItems,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func replacing(
        _ limits: ImageToolWorkflowLimits,
        maximumPaneCount: Int? = nil,
        maximumPagesPerPane: Int? = nil,
        maximumTotalPages: Int? = nil,
        maximumItemCount: Int? = nil,
        maximumStringUTF8Bytes: Int? = nil,
        maximumTotalStringUTF8Bytes: Int? = nil,
        maximumPlanBytes: Int? = nil,
        maximumWorkUnits: UInt64? = nil,
        maximumOCRResultUTF8Bytes: Int? = nil,
        maximumOCRResultItems: Int? = nil,
        cancellationCheckInterval: Int? = nil
    ) -> ImageToolWorkflowLimits {
        self.limits(
            maximumPaneCount: maximumPaneCount ?? limits.maximumPaneCount,
            maximumPagesPerPane: maximumPagesPerPane ?? limits.maximumPagesPerPane,
            maximumTotalPages: maximumTotalPages ?? limits.maximumTotalPages,
            maximumItemCount: maximumItemCount ?? limits.maximumItemCount,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes ?? limits.maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes ?? limits.maximumTotalStringUTF8Bytes,
            maximumPlanBytes: maximumPlanBytes ?? limits.maximumPlanBytes,
            maximumWorkUnits: maximumWorkUnits ?? limits.maximumWorkUnits,
            maximumOCRResultUTF8Bytes: maximumOCRResultUTF8Bytes ?? limits.maximumOCRResultUTF8Bytes,
            maximumOCRResultItems: maximumOCRResultItems ?? limits.maximumOCRResultItems,
            cancellationCheckInterval: cancellationCheckInterval ?? limits.cancellationCheckInterval
        )
    }

    private func assertWorkflowError<T>(
        _ expected: ImageToolWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ImageToolWorkflowError, expected, file: file, line: line)
        }
    }

    private func assertWorkflowErrorMatching<T>(
        _ predicate: (ImageToolWorkflowError) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let error = error as? ImageToolWorkflowError else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            XCTAssertTrue(predicate(error), "Unexpected workflow error: \(error)", file: file, line: line)
        }
    }

    private func assertCancelled<T: Sendable>(
        _ task: Task<T, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled operation unexpectedly succeeded", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ImageToolWorkflowError, .cancelled, file: file, line: line)
        }
    }

    private func cancelAfterObservedCPUWork<T: Sendable>(
        task: Task<T, Error>,
        probe: ImageToolInFlightProbe,
        operation: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard let observation = probe.waitUntilStarted(timeout: 5) else {
            task.cancel()
            XCTFail("\(operation) worker did not start", file: file, line: line)
            return
        }
        guard
            probe.waitForCPUTime(
                observation: observation,
                minimumNanoseconds: 2_000_000,
                timeout: 5
            )
        else {
            task.cancel()
            mach_port_deallocate(mach_task_self_, observation.thread)
            XCTFail("\(operation) worker performed no observable mid-loop work", file: file, line: line)
            return
        }
        guard thread_suspend(observation.thread) == KERN_SUCCESS else {
            task.cancel()
            mach_port_deallocate(mach_task_self_, observation.thread)
            XCTFail("\(operation) worker could not be suspended", file: file, line: line)
            return
        }
        task.cancel()
        thread_resume(observation.thread)
        mach_port_deallocate(mach_task_self_, observation.thread)
    }

    private func sha256(_ text: String) -> [UInt8] {
        Array(SHA256.hash(data: Data(text.utf8)))
    }

    private func digest(_ byte: UInt8) -> [UInt8] {
        [UInt8](repeating: byte, count: SHA256.Digest.byteCount)
    }

    private func hexBytes(_ value: String) -> [UInt8] {
        stride(from: 0, to: value.count, by: 2).map { offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: 2)
            return UInt8(value[start..<end], radix: 16)!
        }
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
    }
}

private final class ImageToolInFlightProbe: @unchecked Sendable {
    struct Observation: Sendable {
        let thread: thread_t
        let initialCPUNanoseconds: UInt64
    }

    private let condition = NSCondition()
    private var observation: Observation?
    private var isFinished = false

    func begin() {
        let thread = mach_thread_self()
        let initialCPUNanoseconds = threadCPUNanoseconds(thread) ?? 0
        condition.lock()
        observation = Observation(
            thread: thread,
            initialCPUNanoseconds: initialCPUNanoseconds
        )
        condition.broadcast()
        condition.unlock()
    }

    func finish() {
        condition.lock()
        isFinished = true
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilStarted(timeout: TimeInterval) -> Observation? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while observation == nil, !isFinished {
            guard condition.wait(until: deadline) else { break }
        }
        return observation
    }

    func waitForCPUTime(
        observation: Observation,
        minimumNanoseconds: UInt64,
        timeout: TimeInterval
    ) -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            condition.lock()
            let finished = isFinished
            condition.unlock()
            if finished { return false }
            if let current = threadCPUNanoseconds(observation.thread),
                current >= observation.initialCPUNanoseconds + minimumNanoseconds
            {
                return true
            }
        }
        return false
    }

    private func threadCPUNanoseconds(_ thread: thread_t) -> UInt64? {
        var info = thread_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let seconds = UInt64(info.user_time.seconds) + UInt64(info.system_time.seconds)
        let microseconds =
            UInt64(info.user_time.microseconds) + UInt64(info.system_time.microseconds)
        return seconds * 1_000_000_000 + microseconds * 1_000
    }
}
