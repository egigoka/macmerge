import Foundation
import MacMergeCore
import XCTest

final class ThreePaneImageNewPlanTests: XCTestCase {
    private struct ProbeError: Error {}

    private func digest(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }

    private func makeSource(
        path: String,
        byteSize: Int = 1024,
        formatHint: String = "public.png",
        width: Int = 64,
        height: Int = 64
    ) -> ThreePaneImageNewSource {
        ThreePaneImageNewSource(
            canonicalPath: path,
            byteSize: byteSize,
            formatHint: formatHint,
            width: width,
            height: height
        )
    }

    private func makeRevision(source: ThreePaneImageNewSource, digestByte: UInt8) -> ThreePaneImageNewRevision {
        ThreePaneImageNewRevision(source: source, sha256: digest(digestByte))
    }

    private func validRevision(path: String, digestByte: UInt8) -> ThreePaneImageNewRevision {
        makeRevision(source: makeSource(path: path), digestByte: digestByte)
    }

    private func validRequest(displayMode: ThreePaneImageNewDisplayMode = .default) -> ThreePaneImageNewRequest {
        ThreePaneImageNewRequest(
            left: validRevision(path: "/tmp/left.png", digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            displayMode: displayMode
        )
    }

    private func tweakedCapability(
        identifiers: Set<String>? = nil,
        paneCounts: [Int]? = nil
    ) -> ThreePaneImageNewCapability {
        let base = ThreePaneImageNewCapability.default
        return ThreePaneImageNewCapability(
            loaderName: base.loaderName,
            limitsName: base.limitsName,
            optionsName: base.optionsName,
            comparisonName: base.comparisonName,
            supportedTypeIdentifiers: identifiers ?? base.supportedTypeIdentifiers,
            supportedPaneCounts: paneCounts ?? base.supportedPaneCounts
        )
    }

    private func assertPlanThrows(
        _ expected: ThreePaneImageNewError,
        request: ThreePaneImageNewRequest,
        limits: ThreePaneImageNewLimits = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try ThreePaneImageNewPlanner.plan(request, limits: limits)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let actual as ThreePaneImageNewError {
            XCTAssertEqual(actual, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func testCommandIDMatchesTodoLane() {
        XCTAssertEqual(ThreePaneImageNewPlanner.commandID, "ID_FILE_NEW3_IMAGE")
    }

    func testHappyPathBindsAllThreePanes() throws {
        let request = validRequest()
        let plan = try ThreePaneImageNewPlanner.plan(request)
        XCTAssertEqual(plan.paneCount, 3)
        XCTAssertEqual(plan.panes.map { $0.pane }, [.left, .middle, .right])
        XCTAssertEqual(plan.displayMode, .overlay)
        XCTAssertEqual(plan.receipt.value.count, 64)
        XCTAssertTrue(plan.receipt.value.allSatisfy({ $0.isHexDigit }))
        XCTAssertEqual(plan.executorContract.receiptValue, plan.receipt.value)
        XCTAssertEqual(plan.executorContract.expectedPaneCount, 3)
        XCTAssertEqual(plan.executorContract.steps.count, 3)
        XCTAssertEqual(plan.executorContract.loaderName, request.capability.loaderName)
        XCTAssertEqual(plan.executorContract.comparisonName, request.capability.comparisonName)
        XCTAssertGreaterThan(plan.workPerformed, 0)
        XCTAssertEqual(plan.panes[0].revision, request.left)
        XCTAssertEqual(plan.panes[1].revision, request.middle)
        XCTAssertEqual(plan.panes[2].revision, request.right)
        XCTAssertEqual(plan.comparisonOptions, request.comparisonOptions)
        XCTAssertEqual(plan.comparisonLimits, request.comparisonLimits)
        XCTAssertEqual(plan.capability, request.capability)
    }

    func testMakeAliasMatchesPlan() throws {
        let request = validRequest()
        let viaPlan = try ThreePaneImageNewPlanner.plan(request)
        let viaMake = try ThreePaneImageNewPlanner.make(request)
        XCTAssertEqual(viaMake, viaPlan)
    }

    func testZeroByteSizeRejected() {
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", byteSize: 0), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        let maximum = ThreePaneImageNewLimits.default.maximumByteSize
        assertPlanThrows(.byteSizeExceeded(maximumBytes: maximum), request: request)
    }

    func testUnsupportedFormatErrorCarriesLengthNotRawHint() {
        let hint = "image/x-secret-format"
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", formatHint: hint), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.unsupportedFormat(hint: hint), request: request)
        let error = ThreePaneImageNewError.unsupportedFormat(hint: hint)
        let summary = error.errorDescription ?? ""
        XCTAssertFalse(summary.contains(hint))
        XCTAssertTrue(summary.contains("\(hint.utf8.count)"))
    }

    func testReceiptBindsLimits() throws {
        let request = validRequest()
        let baseline = try ThreePaneImageNewPlanner.plan(request).receipt
        let relaxed = ThreePaneImageNewLimits(maximumByteSize: 32 * 1024 * 1024)
        let other = try ThreePaneImageNewPlanner.plan(request, limits: relaxed).receipt
        XCTAssertNotEqual(other, baseline)
    }

    func testReceiptBindsAllowlist() throws {
        let request = validRequest()
        let baseline = try ThreePaneImageNewPlanner.plan(request).receipt
        var identifiers = ThreePaneImageNewCapability.default.supportedTypeIdentifiers
        identifiers.insert("com.example.extra")
        let tweaked = ThreePaneImageNewRequest(
            left: request.left,
            middle: request.middle,
            right: request.right,
            displayMode: request.displayMode,
            comparisonOptions: request.comparisonOptions,
            comparisonLimits: request.comparisonLimits,
            capability: tweakedCapability(identifiers: identifiers)
        )
        let other = try ThreePaneImageNewPlanner.plan(tweaked).receipt
        XCTAssertNotEqual(other, baseline)
    }

    func testReceiptBindsDisplayMode() throws {
        let overlay = try ThreePaneImageNewPlanner.plan(validRequest(displayMode: .overlay)).receipt
        let blink = try ThreePaneImageNewPlanner.plan(validRequest(displayMode: .blink)).receipt
        XCTAssertNotEqual(overlay, blink)
    }

    func testReceiptBindsOptionsAndComparisonLimits() throws {
        let request = validRequest()
        let baseline = try ThreePaneImageNewPlanner.plan(request).receipt
        let otherOptions = ThreePaneImageNewRequest(
            left: request.left,
            middle: request.middle,
            right: request.right,
            displayMode: request.displayMode,
            comparisonOptions: ImageComparisonOptions(
                channelTolerance: 4,
                maximumCanvasPixels: request.comparisonOptions.maximumCanvasPixels,
                maximumRegions: request.comparisonOptions.maximumRegions,
                maximumQueuedPixels: request.comparisonOptions.maximumQueuedPixels
            ),
            comparisonLimits: request.comparisonLimits,
            capability: request.capability
        )
        XCTAssertNotEqual(try ThreePaneImageNewPlanner.plan(otherOptions).receipt, baseline)
        let otherLimits = ThreePaneImageNewRequest(
            left: request.left,
            middle: request.middle,
            right: request.right,
            displayMode: request.displayMode,
            comparisonOptions: request.comparisonOptions,
            comparisonLimits: ImageComparisonLimits(
                maximumEncodedBytes: 32 * 1024 * 1024,
                maximumDimension: request.comparisonLimits.maximumDimension,
                maximumPixelCount: request.comparisonLimits.maximumPixelCount,
                maximumDecodedBytes: request.comparisonLimits.maximumDecodedBytes,
                supportedTypeIdentifiers: request.comparisonLimits.supportedTypeIdentifiers
            ),
            capability: request.capability
        )
        XCTAssertNotEqual(try ThreePaneImageNewPlanner.plan(otherLimits).receipt, baseline)
    }

    func testInvalidLimitEveryKind() {
        XCTAssertEqual(ThreePaneImageNewLimit.allCases.count, 7)
        let cases: [(ThreePaneImageNewLimits, ThreePaneImageNewError)] = [
            (ThreePaneImageNewLimits(maximumSources: 1), .invalidLimit(.sources, value: 1)),
            (ThreePaneImageNewLimits(maximumPathUTF8Bytes: 0), .invalidLimit(.pathBytes, value: 0)),
            (ThreePaneImageNewLimits(maximumByteSize: 0), .invalidLimit(.byteSize, value: 0)),
            (ThreePaneImageNewLimits(maximumDimension: 0), .invalidLimit(.dimension, value: 0)),
            (ThreePaneImageNewLimits(maximumPixelCount: 0), .invalidLimit(.pixelCount, value: 0)),
            (ThreePaneImageNewLimits(maximumPlanningWorkUnits: 0), .invalidLimit(.workUnits, value: 0)),
            (ThreePaneImageNewLimits(cancellationCheckInterval: 0), .invalidLimit(.cancellationCheckInterval, value: 0))
        ]
        for (limits, expected) in cases {
            assertPlanThrows(expected, request: validRequest(), limits: limits)
        }
    }

    func testPaneCountExceeded() {
        let limits = ThreePaneImageNewLimits(maximumSources: 2)
        assertPlanThrows(.paneCountExceeded(requested: 3, maximum: 2), request: validRequest(), limits: limits)
    }

    func testUnsupportedPaneCount() {
        let twoOnly = tweakedCapability(paneCounts: [2])
        XCTAssertTrue(twoOnly.supports(paneCount: 2))
        XCTAssertFalse(twoOnly.supports(paneCount: 3))
        let request = ThreePaneImageNewRequest(
            left: validRevision(path: "/tmp/left.png", digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            capability: twoOnly
        )
        assertPlanThrows(.unsupportedPaneCount(panes: 3), request: request)
    }

    func testInvalidOptionsRejected() {
        let badOptions = ImageComparisonOptions(
            channelTolerance: 0,
            maximumCanvasPixels: 0,
            maximumRegions: 250_000,
            maximumQueuedPixels: 262_144
        )
        let request = ThreePaneImageNewRequest(
            left: validRevision(path: "/tmp/left.png", digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            comparisonOptions: badOptions
        )
        assertPlanThrows(.invalidOptions, request: request)
    }

    func testInvalidComparisonLimitsRejected() {
        let badLimits = ImageComparisonLimits(
            maximumEncodedBytes: 0,
            maximumDimension: 16_384,
            maximumPixelCount: 16 * 1024 * 1024,
            maximumDecodedBytes: 128 * 1024 * 1024
        )
        let request = ThreePaneImageNewRequest(
            left: validRevision(path: "/tmp/left.png", digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            comparisonLimits: badLimits
        )
        assertPlanThrows(.invalidComparisonLimits, request: request)
    }

    func testUnsupportedCapabilityRejected() {
        let empty = ThreePaneImageNewCapability(
            loaderName: "",
            limitsName: "",
            optionsName: "",
            comparisonName: "",
            supportedTypeIdentifiers: [],
            supportedPaneCounts: [3]
        )
        let request = ThreePaneImageNewRequest(
            left: validRevision(path: "/tmp/left.png", digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            capability: empty
        )
        assertPlanThrows(.unsupportedCapability(name: ""), request: request)
    }

    func testEmptyPathRejected() {
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: ""), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.emptyPath, request: request)
    }

    func testPathTooLarge() {
        let maximum = ThreePaneImageNewLimits.default.maximumPathUTF8Bytes
        let long = "/" + String(repeating: "a", count: maximum)
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: long), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.pathTooLarge(maximumUTF8Bytes: maximum), request: request)
    }

    func testByteSizeExceeded() {
        let maximum = ThreePaneImageNewLimits.default.maximumByteSize
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", byteSize: maximum + 1), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.byteSizeExceeded(maximumBytes: maximum), request: request)
    }

    func testDimensionsExceeded() {
        let maximum = ThreePaneImageNewLimits.default.maximumDimension
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: maximum + 1), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(
            .dimensionsExceeded(width: maximum + 1, height: 64, maximum: maximum),
            request: request
        )
    }

    func testPixelCountExceeded() {
        let maximum = ThreePaneImageNewLimits.default.maximumPixelCount
        XCTAssertEqual(maximum, 16 * 1024 * 1024)
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: 4097, height: 4096), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.pixelCountExceeded(maximumPixels: maximum), request: request)
    }

    func testInvalidDigest() {
        let short = ThreePaneImageNewRevision(source: makeSource(path: "/tmp/left.png"), sha256: Data(repeating: 1, count: 16))
        let shortRequest = ThreePaneImageNewRequest(
            left: short,
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.invalidDigest, request: shortRequest)
        let zero = ThreePaneImageNewRevision(source: makeSource(path: "/tmp/left.png"), sha256: Data(repeating: 0, count: 32))
        let zeroRequest = ThreePaneImageNewRequest(
            left: zero,
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.invalidDigest, request: zeroRequest)
    }

    func testDuplicateRevision() {
        let request = ThreePaneImageNewRequest(
            left: validRevision(path: "/tmp/left.png", digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/other.png", digestByte: 1)
        )
        assertPlanThrows(.duplicateRevision, request: request)
    }

    func testPlanningWorkExceeded() {
        let limits = ThreePaneImageNewLimits(maximumPlanningWorkUnits: 1)
        assertPlanThrows(.planningWorkExceeded(maximumWorkUnits: 1), request: validRequest(), limits: limits)
    }

    func testBoundaryByteSizeAndDimension() throws {
        let byteMax = ThreePaneImageNewLimits.default.maximumByteSize
        let dimensionMax = ThreePaneImageNewLimits.default.maximumDimension
        let tiny = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", byteSize: 1, width: 1, height: 1), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        _ = try ThreePaneImageNewPlanner.plan(tiny)
        let huge = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", byteSize: byteMax, width: dimensionMax, height: 1), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        _ = try ThreePaneImageNewPlanner.plan(huge)
    }

    func testBoundaryPathBytes() throws {
        let maximum = ThreePaneImageNewLimits.default.maximumPathUTF8Bytes
        let exact = "/" + String(repeating: "a", count: maximum - 1)
        XCTAssertEqual(exact.utf8.count, maximum)
        let fitting = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: exact), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        let fittingLimits = ThreePaneImageNewLimits(maximumPlanningWorkUnits: 16_384)
        _ = try ThreePaneImageNewPlanner.plan(fitting, limits: fittingLimits)
        let overflowing = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: exact + "a"), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.pathTooLarge(maximumUTF8Bytes: maximum), request: overflowing)
    }

    func testBoundaryPixelCount() throws {
        let fitting = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: 4096, height: 4096), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        _ = try ThreePaneImageNewPlanner.plan(fitting)
        let overflowing = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: 4097, height: 4096), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(
            .pixelCountExceeded(maximumPixels: ThreePaneImageNewLimits.default.maximumPixelCount),
            request: overflowing
        )
    }

    func testBoundaryEmptyPathVariants() {
        for path in ["   ", "\t\n ", "a\0b"] {
            let request = ThreePaneImageNewRequest(
                left: makeRevision(source: makeSource(path: path), digestByte: 1),
                middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
                right: validRevision(path: "/tmp/right.png", digestByte: 3)
            )
            assertPlanThrows(.emptyPath, request: request)
        }
    }

    func testCancellationMapsToCancelled() {
        do {
            _ = try ThreePaneImageNewPlanner.plan(validRequest(), cancellationCheck: { throw CancellationError() })
            XCTFail("Expected cancelled")
        } catch let error as ThreePaneImageNewError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonCancellationErrorPropagates() {
        do {
            _ = try ThreePaneImageNewPlanner.plan(validRequest(), cancellationCheck: { throw ProbeError() })
            XCTFail("Expected ProbeError")
        } catch let error as ThreePaneImageNewError {
            XCTFail("Must not map to planner error: \(error)")
        } catch {
            XCTAssertTrue(error is ProbeError, "Unexpected error: \(error)")
        }
    }

    func testReceiptDeterministic() throws {
        let request = validRequest()
        let first = try ThreePaneImageNewPlanner.plan(request)
        let second = try ThreePaneImageNewPlanner.plan(request)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        // Golden pin: same-process equality alone cannot catch cross-build drift.
        XCTAssertEqual(
            first.receipt.value,
            "1a3876ed3a2f826858b091510bd02f70ca0a04d80788455ec734b0a3f3576533"
        )
    }

    func testAllowlistSortedForDeterminism() throws {
        var firstIDs = Set<String>()
        firstIDs.insert("public.png")
        firstIDs.insert("public.jpeg")
        firstIDs.insert("public.tiff")
        var secondIDs = Set<String>()
        secondIDs.insert("public.tiff")
        secondIDs.insert("public.jpeg")
        secondIDs.insert("public.png")
        XCTAssertEqual(firstIDs, secondIDs)
        XCTAssertEqual(firstIDs.sorted(), secondIDs.sorted())
        let left = makeRevision(source: makeSource(path: "/tmp/left.png", formatHint: "public.png"), digestByte: 1)
        let middle = makeRevision(
            source: makeSource(path: "/tmp/middle.png", formatHint: "public.jpeg"),
            digestByte: 2
        )
        let right = makeRevision(source: makeSource(path: "/tmp/right.png", formatHint: "public.tiff"), digestByte: 3)
        let requestA = ThreePaneImageNewRequest(left: left, middle: middle, right: right, capability: tweakedCapability(identifiers: firstIDs))
        let requestB = ThreePaneImageNewRequest(left: left, middle: middle, right: right, capability: tweakedCapability(identifiers: secondIDs))
        let planA = try ThreePaneImageNewPlanner.plan(requestA)
        let planB = try ThreePaneImageNewPlanner.plan(requestB)
        XCTAssertEqual(planA.receipt, planB.receipt)
    }

    func testPathGuardsRunBeforeWorkConsume() {
        for path in ["", "   ", "\t\n ", "a\0b"] {
            let request = ThreePaneImageNewRequest(
                left: makeRevision(source: makeSource(path: path), digestByte: 1),
                middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
                right: validRevision(path: "/tmp/right.png", digestByte: 3)
            )
            let tiny = ThreePaneImageNewLimits(maximumPlanningWorkUnits: 1)
            assertPlanThrows(.emptyPath, request: request, limits: tiny)
        }
    }

    func testOverlongPathBeatsTinyWorkBudget() {
        let maximum = ThreePaneImageNewLimits.default.maximumPathUTF8Bytes
        let long = "/" + String(repeating: "a", count: maximum)
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: long), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        let tiny = ThreePaneImageNewLimits(maximumPlanningWorkUnits: 1)
        assertPlanThrows(.pathTooLarge(maximumUTF8Bytes: maximum), request: request, limits: tiny)
    }

    func testZeroCancellationIntervalThrowsInvalidLimit() {
        assertPlanThrows(
            .invalidLimit(.cancellationCheckInterval, value: 0),
            request: validRequest(),
            limits: ThreePaneImageNewLimits(cancellationCheckInterval: 0)
        )
    }

    func testLimitsValidatedBeforeMetering() {
        let tinyInvalid = ThreePaneImageNewLimits(maximumSources: 1, maximumPlanningWorkUnits: 1)
        assertPlanThrows(
            .invalidLimit(.sources, value: 1),
            request: validRequest(),
            limits: tinyInvalid
        )
    }

    func testRedactionLeaksNoPathsOrRawHints() throws {
        let secret = "/Users/secret/hunter2"
        let leftSource = makeSource(path: secret + "/left.png")
        let left = makeRevision(source: leftSource, digestByte: 1)
        let request = ThreePaneImageNewRequest(
            left: left,
            middle: validRevision(path: secret + "/middle.png", digestByte: 2),
            right: validRevision(path: secret + "/right.png", digestByte: 3)
        )
        let plan = try ThreePaneImageNewPlanner.plan(request)
        for text in [leftSource.description, left.debugDescription, request.description, request.debugDescription, plan.description, plan.debugDescription] {
            XCTAssertFalse(text.contains(secret), text)
        }
        for child in leftSource.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secret))
        }
        let hint = "image/x-secret-format"
        let formatError = ThreePaneImageNewError.unsupportedFormat(hint: hint)
        let summaries = [formatError.errorDescription ?? "", formatError.debugDescription, String(describing: formatError.customMirror)]
        for text in summaries {
            XCTAssertFalse(text.contains(hint), text)
        }
        XCTAssertTrue((formatError.errorDescription ?? "").contains("\(hint.utf8.count)"))
        let capabilityError = ThreePaneImageNewError.unsupportedCapability(name: "SomeCore")
        XCTAssertTrue((capabilityError.errorDescription ?? "").contains("8"))
        XCTAssertFalse((capabilityError.errorDescription ?? "").contains(secret))
    }

    func testDefaultBudgetCoversMaxPath() throws {
        XCTAssertEqual(ThreePaneImageNewLimits.default.maximumPlanningWorkUnits, 16_384)
        XCTAssertEqual(ThreePaneImageNewLimits.default.maximumPathUTF8Bytes, 4_096)
        let maximum = ThreePaneImageNewLimits.default.maximumPathUTF8Bytes
        let exact = "/" + String(repeating: "a", count: maximum - 1)
        XCTAssertEqual(exact.utf8.count, maximum)
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: exact), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        let plan = try ThreePaneImageNewPlanner.plan(request)
        XCTAssertEqual(plan.receipt.value.count, 64)
        XCTAssertLessThanOrEqual(plan.workPerformed, ThreePaneImageNewLimits.default.maximumPlanningWorkUnits)
    }

    func testByteSizeExceededBeatsTinyWorkBudget() {
        let maximum = ThreePaneImageNewLimits.default.maximumByteSize
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", byteSize: maximum + 1), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        let tiny = ThreePaneImageNewLimits(maximumPlanningWorkUnits: 1)
        assertPlanThrows(.byteSizeExceeded(maximumBytes: maximum), request: request, limits: tiny)
    }

    func testFormatAndDigestBeatTinyWorkBudget() {
        let tiny = ThreePaneImageNewLimits(maximumPlanningWorkUnits: 1)
        let hint = "image/x-secret-format"
        let formatRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", formatHint: hint), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.unsupportedFormat(hint: hint), request: formatRequest, limits: tiny)
        let short = ThreePaneImageNewRevision(source: makeSource(path: "/tmp/left.png"), sha256: Data(repeating: 1, count: 16))
        let shortRequest = ThreePaneImageNewRequest(
            left: short,
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.invalidDigest, request: shortRequest, limits: tiny)
        let zero = ThreePaneImageNewRevision(source: makeSource(path: "/tmp/left.png"), sha256: Data(repeating: 0, count: 32))
        let zeroRequest = ThreePaneImageNewRequest(
            left: zero,
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.invalidDigest, request: zeroRequest, limits: tiny)
    }

    func testSamePrefixLongNamesDiverge() throws {
        let prefix = String(repeating: "n", count: 256)
        let nameA = prefix + String(repeating: "a", count: 44)
        let nameB = prefix + String(repeating: "b", count: 44)
        XCTAssertEqual(nameA.count, nameB.count)
        XCTAssertEqual(nameA.utf8.count, nameB.utf8.count)
        XCTAssertEqual(String(nameA.prefix(256)), String(nameB.prefix(256)))
        XCTAssertNotEqual(nameA, nameB)
        func request(loader: String) -> ThreePaneImageNewRequest {
            let base = validRequest()
            let capability = ThreePaneImageNewCapability(
                loaderName: loader,
                limitsName: base.capability.limitsName,
                optionsName: base.capability.optionsName,
                comparisonName: base.capability.comparisonName,
                supportedTypeIdentifiers: base.capability.supportedTypeIdentifiers,
                supportedPaneCounts: base.capability.supportedPaneCounts
            )
            return ThreePaneImageNewRequest(
                left: base.left,
                middle: base.middle,
                right: base.right,
                displayMode: base.displayMode,
                comparisonOptions: base.comparisonOptions,
                comparisonLimits: base.comparisonLimits,
                capability: capability
            )
        }
        let planA = try ThreePaneImageNewPlanner.plan(request(loader: nameA))
        let planB = try ThreePaneImageNewPlanner.plan(request(loader: nameB))
        XCTAssertEqual(planA.receipt.value.count, 64)
        XCTAssertEqual(planB.receipt.value.count, 64)
        XCTAssertTrue(planA.receipt.value.allSatisfy({ $0.isHexDigit }))
        XCTAssertTrue(planB.receipt.value.allSatisfy({ $0.isHexDigit }))
        XCTAssertNotEqual(planA.receipt, planB.receipt)
    }

    func testRequestAndPlanAreEquatableOnly() throws {
        func probe<T>(_ type: T.Type) -> Bool { false }
        func probe<T: Hashable>(_ type: T.Type) -> Bool { true }
        func requireEquatable<T: Equatable>(_ value: T) -> T { value }
        let request = validRequest()
        XCTAssertEqual(requireEquatable(request), request)
        XCTAssertEqual(requireEquatable(request.left), request.left)
        let plan = try ThreePaneImageNewPlanner.plan(request)
        XCTAssertEqual(requireEquatable(plan), plan)
        XCTAssertFalse(probe(ThreePaneImageNewRequest.self))
        XCTAssertFalse(probe(ThreePaneImageNewPlan.self))
        XCTAssertTrue(probe(ThreePaneImageNewSource.self))
    }

    func testCompetingFaultOrderByteSizeFormatDigest() {
        let maximum = ThreePaneImageNewLimits.default.maximumByteSize
        let badHint = "image/x-secret-format"
        let shortDigest = Data(repeating: 1, count: 16)
        // Triple fault: byteSize (L720) beats format (L726) beats digest (L732).
        let tripleSource = makeSource(path: "/tmp/left.png", byteSize: maximum + 1, formatHint: badHint)
        let triple = ThreePaneImageNewRequest(
            left: ThreePaneImageNewRevision(source: tripleSource, sha256: shortDigest),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.byteSizeExceeded(maximumBytes: maximum), request: triple)
        // Double fault: format (L726) beats digest (L732).
        let formatSource = makeSource(path: "/tmp/left.png", formatHint: badHint)
        let formatFault = ThreePaneImageNewRequest(
            left: ThreePaneImageNewRevision(source: formatSource, sha256: shortDigest),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.unsupportedFormat(hint: badHint), request: formatFault)
        let zeroFault = ThreePaneImageNewRequest(
            left: ThreePaneImageNewRevision(
                source: makeSource(path: "/tmp/left.png"),
                sha256: Data(repeating: 0, count: 32)
            ),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.invalidDigest, request: zeroFault)
    }

    func testSecondTierComparisonLimitsBranches() {
        // Under defaults the second-tier comparisonLimits branches (L723 byteSize,
        // L729 allowlist, L753/L760 dimension, L772 pixelCount, L798/L801 canvas)
        // are shadowed because defaults equal first-tier thresholds. Narrow the
        // comparison limits to reach them without touching planner limits.
        let narrowBytes = ImageComparisonLimits(
            maximumEncodedBytes: 512,
            maximumDimension: 16_384,
            maximumPixelCount: 16 * 1024 * 1024,
            maximumDecodedBytes: 128 * 1024 * 1024
        )
        let bytesRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", byteSize: 1024), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            comparisonLimits: narrowBytes
        )
        assertPlanThrows(.byteSizeExceeded(maximumBytes: 512), request: bytesRequest)
        let narrowDimension = ImageComparisonLimits(
            maximumEncodedBytes: 64 * 1024 * 1024,
            maximumDimension: 32,
            maximumPixelCount: 16 * 1024 * 1024,
            maximumDecodedBytes: 128 * 1024 * 1024
        )
        let dimensionRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: 64, height: 64), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            comparisonLimits: narrowDimension
        )
        assertPlanThrows(
            .dimensionsExceeded(width: 64, height: 64, maximum: 32),
            request: dimensionRequest
        )
        let narrowPixels = ImageComparisonLimits(
            maximumEncodedBytes: 64 * 1024 * 1024,
            maximumDimension: 16_384,
            maximumPixelCount: 1_000,
            maximumDecodedBytes: 128 * 1024 * 1024
        )
        let pixelRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: 64, height: 64), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            comparisonLimits: narrowPixels
        )
        assertPlanThrows(.pixelCountExceeded(maximumPixels: 1_000), request: pixelRequest)
        let narrowAllowlist = ImageComparisonLimits(
            maximumEncodedBytes: 64 * 1024 * 1024,
            maximumDimension: 16_384,
            maximumPixelCount: 16 * 1024 * 1024,
            maximumDecodedBytes: 128 * 1024 * 1024,
            supportedTypeIdentifiers: ["public.jpeg"]
        )
        let allowlistRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", formatHint: "public.png"), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            comparisonLimits: narrowAllowlist
        )
        // Capability allowlist still contains public.png, so L726 passes and L729 fires.
        assertPlanThrows(.unsupportedFormat(hint: "public.png"), request: allowlistRequest)
        // Canvas via comparisonLimits: individuals pass, combined canvas fails.
        let narrowCanvas = ImageComparisonLimits(
            maximumEncodedBytes: 64 * 1024 * 1024,
            maximumDimension: 16_384,
            maximumPixelCount: 100_000,
            maximumDecodedBytes: 128 * 1024 * 1024
        )
        let canvasRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: 2000, height: 10), digestByte: 1),
            middle: makeRevision(source: makeSource(path: "/tmp/middle.png", width: 10, height: 2000), digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            comparisonLimits: narrowCanvas
        )
        assertPlanThrows(.pixelCountExceeded(maximumPixels: 100_000), request: canvasRequest)
        // Canvas via options: individuals and comparisonLimits pass, options cap fails.
        let narrowOptions = ImageComparisonOptions(
            channelTolerance: 0,
            maximumCanvasPixels: 1_000,
            maximumRegions: 250_000,
            maximumQueuedPixels: 262_144
        )
        let optionsCanvasRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: 64, height: 64), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3),
            comparisonOptions: narrowOptions
        )
        assertPlanThrows(.pixelCountExceeded(maximumPixels: 1_000), request: optionsCanvasRequest)
    }

    func testLateGuardsLoseToTinyWorkBudget() {
        // Early guards (emptyPath, pathTooLarge, byteSize, format, digest) beat a
        // 1-unit budget. Late guards consume path-byte work first, so they lose.
        let tiny = ThreePaneImageNewLimits(maximumPlanningWorkUnits: 1)
        let maximum = ThreePaneImageNewLimits.default.maximumDimension
        let dimensionRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: maximum + 1), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.planningWorkExceeded(maximumWorkUnits: 1), request: dimensionRequest, limits: tiny)
        let pixelRequest = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: "/tmp/left.png", width: 4097, height: 4096), digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        assertPlanThrows(.planningWorkExceeded(maximumWorkUnits: 1), request: pixelRequest, limits: tiny)
        let duplicateRequest = ThreePaneImageNewRequest(
            left: validRevision(path: "/tmp/left.png", digestByte: 1),
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/other.png", digestByte: 1)
        )
        assertPlanThrows(.planningWorkExceeded(maximumWorkUnits: 1), request: duplicateRequest, limits: tiny)
    }

    func testLimitsValidatedBeforeMeteringAllKinds() {
        let tinyWork = 1
        let cases: [(ThreePaneImageNewLimits, ThreePaneImageNewError)] = [
            (
                ThreePaneImageNewLimits(maximumSources: 1, maximumPlanningWorkUnits: tinyWork),
                .invalidLimit(.sources, value: 1)
            ),
            (
                ThreePaneImageNewLimits(maximumPathUTF8Bytes: 0, maximumPlanningWorkUnits: tinyWork),
                .invalidLimit(.pathBytes, value: 0)
            ),
            (
                ThreePaneImageNewLimits(maximumByteSize: 0, maximumPlanningWorkUnits: tinyWork),
                .invalidLimit(.byteSize, value: 0)
            ),
            (
                ThreePaneImageNewLimits(maximumDimension: 0, maximumPlanningWorkUnits: tinyWork),
                .invalidLimit(.dimension, value: 0)
            ),
            (
                ThreePaneImageNewLimits(maximumPixelCount: 0, maximumPlanningWorkUnits: tinyWork),
                .invalidLimit(.pixelCount, value: 0)
            ),
            (ThreePaneImageNewLimits(maximumPlanningWorkUnits: 0), .invalidLimit(.workUnits, value: 0)),
            (
                ThreePaneImageNewLimits(maximumPlanningWorkUnits: tinyWork, cancellationCheckInterval: 0),
                .invalidLimit(.cancellationCheckInterval, value: 0)
            )
        ]
        XCTAssertEqual(ThreePaneImageNewLimit.allCases.count, 7)
        for (limits, expected) in cases {
            assertPlanThrows(expected, request: validRequest(), limits: limits)
        }
    }

    func testTripleMaxPathFitsDefaultBudget() throws {
        let maximum = ThreePaneImageNewLimits.default.maximumPathUTF8Bytes
        XCTAssertEqual(ThreePaneImageNewLimits.default.maximumPlanningWorkUnits, 16_384)
        let base = "/" + String(repeating: "a", count: maximum - 2)
        let pathA = base + "a"
        let pathB = base + "b"
        let pathC = base + "c"
        for path in [pathA, pathB, pathC] {
            XCTAssertEqual(path.utf8.count, maximum)
        }
        let request = ThreePaneImageNewRequest(
            left: makeRevision(source: makeSource(path: pathA), digestByte: 1),
            middle: makeRevision(source: makeSource(path: pathB), digestByte: 2),
            right: makeRevision(source: makeSource(path: pathC), digestByte: 3)
        )
        let plan = try ThreePaneImageNewPlanner.plan(request)
        XCTAssertEqual(plan.receipt.value.count, 64)
        XCTAssertLessThanOrEqual(plan.workPerformed, ThreePaneImageNewLimits.default.maximumPlanningWorkUnits)
    }

    func testCappedReceiptNameNonASCIIAccounting() throws {
        // cappedReceiptName caps on Character count (256), while byteCount uses UTF8.
        // 256 é = 256 Characters but 512 UTF8 bytes: still accepted, proves the
        // split accounting. 257 é truncates the capped prefix yet still binds the
        // full value via fullHash, so receipts diverge.
        let accented256 = String(repeating: "é", count: 256)
        XCTAssertEqual(accented256.count, 256)
        XCTAssertEqual(accented256.utf8.count, 512)
        let accented257 = String(repeating: "é", count: 257)
        XCTAssertEqual(accented257.count, 257)
        func receiptForLoader(_ loader: String) throws -> String {
            let base = validRequest()
            let capability = ThreePaneImageNewCapability(
                loaderName: loader,
                limitsName: base.capability.limitsName,
                optionsName: base.capability.optionsName,
                comparisonName: base.capability.comparisonName,
                supportedTypeIdentifiers: base.capability.supportedTypeIdentifiers,
                supportedPaneCounts: base.capability.supportedPaneCounts
            )
            let request = ThreePaneImageNewRequest(
                left: base.left,
                middle: base.middle,
                right: base.right,
                displayMode: base.displayMode,
                comparisonOptions: base.comparisonOptions,
                comparisonLimits: base.comparisonLimits,
                capability: capability
            )
            return try ThreePaneImageNewPlanner.plan(request).receipt.value
        }
        let receipt256 = try receiptForLoader(accented256)
        let receipt257 = try receiptForLoader(accented257)
        XCTAssertEqual(receipt256.count, 64)
        XCTAssertEqual(receipt257.count, 64)
        XCTAssertNotEqual(receipt256, receipt257)
        let emoji256 = String(repeating: "😀", count: 256)
        XCTAssertEqual(emoji256.count, 256)
        XCTAssertEqual(emoji256.utf8.count, 1024)
        let receiptEmoji = try receiptForLoader(emoji256)
        XCTAssertEqual(receiptEmoji.count, 64)
        XCTAssertNotEqual(receiptEmoji, receipt256)
    }

    func testPathBindingGapKnownResidual_Impl845() throws {
        // Impl:845 residual (production frozen this wave): receipt binds digest,
        // bytes, extent, format — but not canonicalPath (no pathHash, unlike
        // TwoPaneImageNewPlanner). Different paths with identical digests yield
        // identical receipts, so path substitution is undetected. Record only;
        // a future production fix must bind pathHash and flip this test to
        // expect divergence.
        let leftA = validRevision(path: "/tmp/left.png", digestByte: 1)
        let leftB = validRevision(path: "/tmp/other-left.png", digestByte: 1)
        XCTAssertEqual(leftA.sha256, leftB.sha256)
        let requestA = ThreePaneImageNewRequest(
            left: leftA,
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        let requestB = ThreePaneImageNewRequest(
            left: leftB,
            middle: validRevision(path: "/tmp/middle.png", digestByte: 2),
            right: validRevision(path: "/tmp/right.png", digestByte: 3)
        )
        let receiptA = try ThreePaneImageNewPlanner.plan(requestA).receipt
        let receiptB = try ThreePaneImageNewPlanner.plan(requestB).receipt
        XCTAssertEqual(receiptA, receiptB)
    }
}
